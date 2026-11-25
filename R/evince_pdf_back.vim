vim9script

# SyncTeX backward search: Evince → Vim
#
# Original: Gedit Synctex plugin, Copyright (C) 2010 Jose Aliste (GPL v2+)
# Modified for Vim-R by Jakson Aquino; ported to Vim9script.
#
# Listens for Evince SyncSource signals (user ctrl-clicks in the PDF)
# and calls SyncTeX_backward() in Vim with the source file and line.
#
# Requirements: gdbus (glib2), dbus-monitor (dbus)

import autoload './evince_dbus.vim' as dbus

# The proxies of the backward search, one for each PDF, by the URI of the PDF.
# The monitor of each stays alive between searches.
var proxies: dict<dict<any>> = {}

# ── Public API ─────────────────────────────────────────────────────────

# Start backward-search monitoring for a PDF.
# Equivalent to EvinceWindowProxy(uri, spawn=True) + loop.run().
export def Start(path_output: string)
    var uri = dbus.PathToUri(path_output)
    if !has_key(proxies, uri)
        proxies[uri] = dbus.NewProxy()
    endif
    var px = proxies[uri]

    dbus.Init(px, uri)
    px.OnConnected = OnConnected
    px.OnSignal    = (member: string, sig: dict<string>, args: list<string>) =>
        OnSignal(px, member, sig, args)

    # Listen for all Evince window signals (DocumentLoaded, SyncSource,
    # Closed) — mirrors bus.add_signal_receiver + connect_to_signal.
    dbus.StartMonitor(px)

    # Check whether the document is already open (spawn=false).
    dbus.FindDocument(px, false)
enddef

# Stop monitoring and clean up.
# Equivalent to SIGTERM handler + loop.quit().
export def Stop()
    for px in values(proxies)
        dbus.Shutdown(px)
    endfor
    proxies = {}
enddef

# ── Callbacks ──────────────────────────────────────────────────────────

def OnConnected(wpath: string)
    # Window found and connected — nothing extra needed for backward
    # search; the signal monitor is already running.
enddef

def OnSignal(px: dict<any>, member: string, sig: dict<string>, args: list<string>)
    if member ==# 'DocumentLoaded'
        OnDocumentLoaded(px, sig, args)
    elseif !dbus.IsFromWindow(px, sig)
        # A signal of another Evince window, which shows another document
        return
    elseif member ==# 'SyncSource'
        OnSyncSource(px, args)
    elseif member ==# 'Closed'
        OnWindowClose(px)
    endif
enddef

# ── Signal handlers ────────────────────────────────────────────────────

# _on_doc_loaded: if the loaded URI matches ours, use the sender to
# establish the connection, unless that sender is the one we are connected
# to.  Another sender means that a new Evince shows the document, which
# happens with no Closed signal when the old one was killed.
def OnDocumentLoaded(px: dict<any>, sig: dict<string>, args: list<string>)
    var loaded_uri = dbus.ExtractFirstString(args)
    var sender = get(sig, 'sender', '')
    if loaded_uri ==# px.uri && sender !=# '' && !(px.connected && sender ==# px.dbus_name)
        dbus.ConnectToEvince(px, sender)
    endif
enddef

# on_sync_source: extract source file + line, call SyncTeX_backward().
def OnSyncSource(px: dict<any>, args: list<string>)
    if px.status !=# 'RUNNING'
        return
    endif

    var input_file = dbus.ExtractFirstString(args)
    if input_file ==# ''
        return
    endif

    # source_link is a struct { int32 line, int32 col }.
    # Extract the first int32 (line number).
    var line_nr = 0
    var in_struct = false
    for a in args
        if a =~# 'struct\s*{'
            in_struct = true
        elseif in_struct && a =~# 'int32'
            line_nr = str2nr(matchstr(a, 'int32\s\+\zs-\?\d\+'))
            break
        endif
    endfor

    g:SyncTeX_backward(dbus.UriToPath(input_file), line_nr)
enddef

# on_window_close
def OnWindowClose(px: dict<any>)
    px.status    = 'CLOSED'
    px.connected = false
enddef
