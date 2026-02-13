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

# ── Public API ─────────────────────────────────────────────────────────

# Start backward-search monitoring for a PDF.
# Equivalent to EvinceWindowProxy(uri, spawn=True) + loop.run().
export def Start(path_output: string)
    var uri = 'file://' .. substitute(path_output, ' ', '%20', 'g')

    dbus.Init(uri)
    dbus.OnConnected = OnConnected
    dbus.OnSignal    = OnSignal

    # Listen for all Evince window signals (DocumentLoaded, SyncSource,
    # Closed) — mirrors bus.add_signal_receiver + connect_to_signal.
    dbus.StartMonitor()

    # Check whether the document is already open (spawn=false).
    dbus.FindDocument(false)
enddef

# Stop monitoring and clean up.
# Equivalent to SIGTERM handler + loop.quit().
export def Stop()
    dbus.Shutdown()
enddef

# ── Callbacks ──────────────────────────────────────────────────────────

def OnConnected(wpath: string)
    # Window found and connected — nothing extra needed for backward
    # search; the signal monitor is already running.
enddef

def OnSignal(member: string, sig: dict<string>, args: list<string>)
    if member ==# 'DocumentLoaded'
        OnDocumentLoaded(sig, args)
    elseif member ==# 'SyncSource'
        OnSyncSource(args)
    elseif member ==# 'Closed'
        OnWindowClose()
    endif
enddef

# ── Signal handlers ────────────────────────────────────────────────────

# _on_doc_loaded: if the loaded URI matches ours and we haven't
# connected yet, use the sender to establish the connection.
def OnDocumentLoaded(sig: dict<string>, args: list<string>)
    var loaded_uri = dbus.ExtractFirstString(args)
    if loaded_uri ==# dbus.uri && !dbus.connected
        var sender = get(sig, 'sender', '')
        if sender !=# ''
            dbus.ConnectToEvince(sender)
        endif
    endif
enddef

# on_sync_source: extract source file + line, call SyncTeX_backward().
def OnSyncSource(args: list<string>)
    if dbus.status !=# 'RUNNING'
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

    input_file = substitute(input_file, '^file://', '', '')
    input_file = substitute(input_file, '%20', ' ', 'g')

    execute "call SyncTeX_backward('" .. escape(input_file, "'\\") .. "', " .. line_nr .. ")"
enddef

# on_window_close
def OnWindowClose()
    dbus.status    = 'CLOSED'
    dbus.connected = false
enddef
