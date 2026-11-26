vim9script

# SyncTeX forward search: Vim → Evince
#
# Original: Gedit Synctex plugin, Copyright (C) 2010 Jose Aliste (GPL v2+)
# Modified for Vim-R by Jakson Aquino; ported to Vim9script.
#
# Given a source file and line number, tells Evince to scroll to the
# corresponding position in the PDF.
#
# Requirements: gdbus (glib2), dbus-monitor (dbus)

import autoload './evince_dbus.vim' as dbus

# The proxy of the forward search.  It is separate from the proxy of the
# backward search, whose monitor must keep running after a forward search.
var px = dbus.NewProxy()

# Pending SyncView call (mirrors _tmp_syncview + _handler)
var s_pending_input: string = ''
var s_pending_line: number  = 0
var s_has_pending: bool     = false

# ── Public API ─────────────────────────────────────────────────────────

# Perform a forward SyncTeX search.
# Equivalent to:
#   a = EvinceWindowProxy('file://' + path_output, True)
#   GLib.timeout_add(400, sync_view, a, path_input, line_number)
#   loop.run()
export def SyncView(path_input: string, path_output: string, line_number: number)
    s_has_pending   = false
    s_pending_input = ''
    s_pending_line  = 0

    var uri = dbus.PathToUri(path_output)

    dbus.Init(px, uri)
    px.OnConnected = OnConnected
    px.OnSignal    = OnSignal

    # Monitor DocumentLoaded only (needed when Evince is being spawned).
    dbus.StartMonitor(px, ',member=DocumentLoaded')

    # Ask daemon if document is already open (spawn=false first).
    dbus.FindDocument(px, false)

    # After 400 ms, attempt the SyncView — mirrors GLib.timeout_add(400, ...).
    timer_start(400, (_) => DoSyncView(path_input, line_number))
enddef

# ── Core SyncView logic ───────────────────────────────────────────────

# Mirrors the Python sync_view() timeout callback + EvinceWindowProxy.SyncView().
def DoSyncView(input_file: string, line_nr: number)
    if px.status ==# 'RUNNING' && px.connected
        # Window is ready — call SyncView directly.
        CallSyncViewDBus(input_file, line_nr)
    else
        # Window not ready (CLOSED).  Store the pending call, ask the
        # daemon to spawn Evince, and tell Vim to retry.
        # Mirrors: self._tmp_syncview, self._handler, _get_dbus_name(True)
        s_pending_input = input_file
        s_pending_line  = line_nr
        s_has_pending   = true
        dbus.FindDocument(px, true)
        g:Evince_Again()
    endif
enddef

# Issue the D-Bus SyncView call on the Evince window.
# Mirrors: self.window.SyncView(input_file, data, 0, ...)
def CallSyncViewDBus(input_file: string, line_nr: number)
    var cmd = ['gdbus', 'call', '--session',
        '--dest',        px.dbus_name,
        '--object-path', px.window_path,
        '--method',      dbus.EV_WINDOW_IFACE .. '.SyncView',
        input_file,
        '(' .. line_nr .. ', 1)',
        '0']
    job_start(cmd, {
        out_cb: (ch: channel, msg: string) => OnSyncViewDone(),
        err_cb: (ch: channel, msg: string) => dbus.Warn('SyncView DBus call failed: ' .. msg),
    })
enddef

def OnSyncViewDone()
    # Mirrors: vimr_cmd("let g:rplugin.evince_loop = 0")
    g:rplugin.evince_loop = 0
    dbus.StopMonitor(px)
enddef

# ── Callbacks ──────────────────────────────────────────────────────────

# Called when GetWindowList succeeds.
# If there's a pending SyncView (spawn path), fire it now.
# Mirrors _syncview_handler.
def OnConnected(wpath: string)
    if s_has_pending
        s_has_pending = false
        CallSyncViewDBus(s_pending_input, s_pending_line)
    endif
enddef

def OnSignal(member: string, sig: dict<string>, args: list<string>)
    if member ==# 'DocumentLoaded'
        OnDocumentLoaded(sig, args)
    endif
enddef

# _on_doc_loaded: if the loaded URI matches ours and we haven't
# connected yet, use the sender to establish the connection.
def OnDocumentLoaded(sig: dict<string>, args: list<string>)
    var loaded_uri = dbus.ExtractFirstString(args)
    if loaded_uri ==# px.uri && !px.connected
        var sender = get(sig, 'sender', '')
        if sender !=# ''
            dbus.ConnectToEvince(px, sender)
        endif
    endif
enddef
