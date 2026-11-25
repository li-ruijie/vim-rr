vim9script

# Shared D-Bus infrastructure for Evince SyncTeX communication.
#
# Original: Gedit Synctex plugin, Copyright (C) 2010 Jose Aliste (GPL v2+)
# Modified for Vim-R by Jakson Aquino; ported to Vim9script.
#
# Provides the low-level plumbing that both forward and backward search
# scripts need: D-Bus constants, FindDocument/GetWindowList call chains,
# dbus-monitor signal parsing, and helper utilities.
#
# Consumers register callback Funcrefs to react to events.  Each consumer owns
# one proxy (see NewProxy), and every function below works on the proxy that
# it is given, so a forward search leaves a running backward search alone.
#
# Requirements: gdbus (glib2), dbus-monitor (dbus)

# ── D-Bus names and object paths ──────────────────────────────────────

export const EV_DAEMON_PATH  = '/org/gnome/evince/Daemon'
export const EV_DAEMON_NAME  = 'org.gnome.evince.Daemon'
export const EV_DAEMON_IFACE = 'org.gnome.evince.Daemon'

export const EVINCE_PATH  = '/org/gnome/evince/Evince'
export const EVINCE_IFACE = 'org.gnome.evince.Application'

export const EV_WINDOW_IFACE = 'org.gnome.evince.Window'

# ── Proxy state ────────────────────────────────────────────────────────

# Create the state of one proxy.
export def NewProxy(): dict<any>
    return {
        uri:         '',
        dbus_name:   '',
        status:      'CLOSED',
        connected:   false,
        window_path: '',

        # Signal monitor internals
        monitor_job: null_job,
        cur_sig:     {},
        cur_args:    [],
        flush_timer: -1,

        # Consumer callbacks.  Set these before calling FindDocument().

        # Called after GetWindowList succeeds with the window object path.
        # Signature: (wpath: string) => void
        OnConnected: null_function,

        # Called for each signal dispatched by the monitor.
        # Signature: (member: string, sig: dict<string>, args: list<string>) => void
        OnSignal:    null_function,
    }
enddef

# ── Public API ─────────────────────────────────────────────────────────

# Initialise the proxy for a given PDF URI.
# Resets all state; does NOT start monitoring or call FindDocument.
export def Init(px: dict<any>, pdf_uri: string)
    Reset(px)
    px.uri = pdf_uri
enddef

# Clean up everything: stop monitor, reset state.
export def Shutdown(px: dict<any>)
    StopMonitor(px)
    Reset(px)
enddef

# ── FindDocument / GetWindowList chain ─────────────────────────────────

# Ask the Evince Daemon whether the document is known (and optionally
# spawn Evince).  Mirrors _get_dbus_name(spawn).
export def FindDocument(px: dict<any>, spawn: bool)
    var cmd = ['gdbus', 'call', '--session',
        '--dest',        EV_DAEMON_NAME,
        '--object-path', EV_DAEMON_PATH,
        '--method',      EV_DAEMON_IFACE .. '.FindDocument',
        px.uri, spawn ? 'true' : 'false']
    job_start(cmd, {
        out_cb: (ch: channel, msg: string) => HandleFindDocReply(px, msg),
        err_cb: (ch: channel, msg: string) => Warn('FindDocument DBus call has failed: ' .. msg),
    })
enddef

def HandleFindDocReply(px: dict<any>, msg: string)
    var name = matchstr(msg, "'\\zs.\\{-}\\ze'")
    if name !=# ''
        ConnectToEvince(px, name)
    endif
enddef

# Establish connection: set dbus_name, mark RUNNING, fetch window list.
# Can also be called directly by signal handlers that learn the sender.
export def ConnectToEvince(px: dict<any>, evince_name: string)
    px.dbus_name = evince_name
    px.status    = 'RUNNING'

    var cmd = ['gdbus', 'call', '--session',
        '--dest',        px.dbus_name,
        '--object-path', EVINCE_PATH,
        '--method',      EVINCE_IFACE .. '.GetWindowList']
    job_start(cmd, {
        out_cb: (ch: channel, msg: string) => HandleWindowListReply(px, msg),
        err_cb: (ch: channel, msg: string) => Warn('GetWindowList DBus call has failed: ' .. msg),
    })
enddef

def HandleWindowListReply(px: dict<any>, msg: string)
    var wpath = matchstr(msg, "'\\zs[^']*\\ze'")
    if wpath ==# ''
        Warn('GetWindowList returned empty list')
        return
    endif
    px.window_path = wpath
    px.connected   = true
    if px.OnConnected != null_function
        px.OnConnected(wpath)
    endif
enddef

# ── Signal monitor ─────────────────────────────────────────────────────

# Start a dbus-monitor job.  |match_rule| is appended to the base
# interface filter, e.g. ",member=DocumentLoaded" or "" for all members.
export def StartMonitor(px: dict<any>, match_suffix: string = '')
    var rule = "type='signal',interface=" .. EV_WINDOW_IFACE .. match_suffix
    var cmd  = ['dbus-monitor', '--session', rule]
    px.monitor_job = job_start(cmd, {
        out_cb: (ch: channel, line: string) => OnMonitorLine(px, line),
        err_cb: (ch: channel, _: string) => 0,
    })
enddef

export def StopMonitor(px: dict<any>)
    if px.monitor_job != null_job && job_status(px.monitor_job) ==# 'run'
        job_stop(px.monitor_job)
    endif
    px.monitor_job = null_job
    if px.flush_timer != -1
        timer_stop(px.flush_timer)
        px.flush_timer = -1
    endif
    px.cur_sig  = {}
    px.cur_args = []
enddef

def OnMonitorLine(px: dict<any>, line: string)
    if line =~# '^signal '
        FlushSignal(px)
        px.cur_sig  = ParseSignalHeader(line)
        px.cur_args = []
    elseif !empty(px.cur_sig)
        add(px.cur_args, line)
    endif

    if px.flush_timer != -1
        timer_stop(px.flush_timer)
    endif
    px.flush_timer = timer_start(50, (_) => FlushSignal(px))
enddef

def FlushSignal(px: dict<any>)
    if px.flush_timer != -1
        timer_stop(px.flush_timer)
        px.flush_timer = -1
    endif
    if empty(px.cur_sig)
        return
    endif
    var sig  = px.cur_sig
    var args = px.cur_args
    px.cur_sig  = {}
    px.cur_args = []
    DispatchSignal(px, sig, args)
enddef

def ParseSignalHeader(line: string): dict<string>
    return {
        member: matchstr(line, 'member=\zs\S\+'),
        sender: matchstr(line, 'sender=\zs\S\+'),
        path:   matchstr(line, 'path=\zs[^;]\+'),
    }
enddef

def DispatchSignal(px: dict<any>, sig: dict<string>, args: list<string>)
    if px.OnSignal != null_function
        px.OnSignal(get(sig, 'member', ''), sig, args)
    endif
enddef

# ── Helpers (exported for consumers) ───────────────────────────────────

# Return the file URI of an absolute path, escaped as GLib escapes it, since
# Evince reports the URI of a document in that form and the two are compared.
# Letters, digits, and the characters that a path may hold are kept, and
# every other byte is written as a percent sign and two hexadecimal digits.
export def PathToUri(path: string): string
    return 'file://' .. range(strlen(path))
        ->mapnew((_, i) => strpart(path, i, 1))
        ->mapnew((_, b) => b =~ '^[A-Za-z0-9!$&''()*+,./:=@_~-]$' ? b : printf('%%%02X', char2nr(b)))
        ->join('')
enddef

# Return the path that a file URI names, with every percent escape decoded
export def UriToPath(uri: string): string
    return uri->substitute('^file://', '', '')
        ->substitute('%\(\x\x\)', '\=eval(''"\x'' .. submatch(1) .. ''"'')', 'g')
enddef

# Extract the value of the first  string "..."  line from dbus-monitor output.
export def ExtractFirstString(args: list<string>): string
    for a in args
        var m = matchstr(a, '^\s*string\s\+"\zs.\{-}\ze"\s*$')
        if m !=# ''
            return m
        endif
    endfor
    return ''
enddef

# Warning message (replaces vimr_warn).
export def Warn(msg: string)
    echohl WarningMsg
    echomsg msg
    echohl None
enddef

# ── Internal ───────────────────────────────────────────────────────────

def Reset(px: dict<any>)
    StopMonitor(px)
    px.uri         = ''
    px.dbus_name   = ''
    px.status      = 'CLOSED'
    px.connected   = false
    px.window_path = ''
enddef
