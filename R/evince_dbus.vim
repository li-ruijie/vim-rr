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
# Consumers register callback Funcrefs to react to events.
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

export var uri: string         = ''
export var dbus_name: string   = ''
export var status: string      = 'CLOSED'
export var connected: bool     = false
export var window_path: string = ''

# Signal monitor internals
var monitor_job: job         = null_job
var cur_sig: dict<string>    = {}
var cur_args: list<string>   = []
var flush_timer: number      = -1

# ── Consumer callbacks ─────────────────────────────────────────────────
# Set these before calling Init() / FindDocument().

# Called after GetWindowList succeeds with the window object path.
# Signature: (wpath: string) => void
export var OnConnected: func(string) = null_function

# Called for each signal dispatched by the monitor.
# Signature: (member: string, sig: dict<string>, args: list<string>) => void
export var OnSignal: func(string, dict<string>, list<string>) = null_function

# ── Public API ─────────────────────────────────────────────────────────

# Initialise the proxy for a given PDF URI.
# Resets all state; does NOT start monitoring or call FindDocument.
export def Init(pdf_uri: string)
    Reset()
    uri = pdf_uri
enddef

# Clean up everything: stop monitor, reset state.
export def Shutdown()
    StopMonitor()
    Reset()
enddef

# ── FindDocument / GetWindowList chain ─────────────────────────────────

# Ask the Evince Daemon whether the document is known (and optionally
# spawn Evince).  Mirrors _get_dbus_name(spawn).
export def FindDocument(spawn: bool)
    var cmd = ['gdbus', 'call', '--session',
        '--dest',        EV_DAEMON_NAME,
        '--object-path', EV_DAEMON_PATH,
        '--method',      EV_DAEMON_IFACE .. '.FindDocument',
        uri, spawn ? 'true' : 'false']
    job_start(cmd, {
        out_cb: (ch: channel, msg: string) => HandleFindDocReply(msg),
        err_cb: (ch: channel, msg: string) => Warn('FindDocument DBus call has failed: ' .. msg),
    })
enddef

def HandleFindDocReply(msg: string)
    var name = matchstr(msg, "'\\zs.\\{-}\\ze'")
    if name !=# ''
        ConnectToEvince(name)
    endif
enddef

# Establish connection: set dbus_name, mark RUNNING, fetch window list.
# Can also be called directly by signal handlers that learn the sender.
export def ConnectToEvince(evince_name: string)
    dbus_name = evince_name
    status    = 'RUNNING'

    var cmd = ['gdbus', 'call', '--session',
        '--dest',        dbus_name,
        '--object-path', EVINCE_PATH,
        '--method',      EVINCE_IFACE .. '.GetWindowList']
    job_start(cmd, {
        out_cb: (ch: channel, msg: string) => HandleWindowListReply(msg),
        err_cb: (ch: channel, msg: string) => Warn('GetWindowList DBus call has failed: ' .. msg),
    })
enddef

def HandleWindowListReply(msg: string)
    var wpath = matchstr(msg, "'\\zs[^']*\\ze'")
    if wpath ==# ''
        Warn('GetWindowList returned empty list')
        return
    endif
    window_path = wpath
    connected   = true
    if OnConnected != null_function
        OnConnected(wpath)
    endif
enddef

# ── Signal monitor ─────────────────────────────────────────────────────

# Start a dbus-monitor job.  |match_rule| is appended to the base
# interface filter, e.g. ",member=DocumentLoaded" or "" for all members.
export def StartMonitor(match_suffix: string = '')
    var rule = "type='signal',interface=" .. EV_WINDOW_IFACE .. match_suffix
    var cmd  = ['dbus-monitor', '--session', rule]
    monitor_job = job_start(cmd, {
        out_cb: (ch: channel, line: string) => OnMonitorLine(line),
        err_cb: (ch: channel, _: string) => {},
    })
enddef

export def StopMonitor()
    if monitor_job != null_job && job_status(monitor_job) ==# 'run'
        job_stop(monitor_job)
    endif
    monitor_job = null_job
    if flush_timer != -1
        timer_stop(flush_timer)
        flush_timer = -1
    endif
    cur_sig  = {}
    cur_args = []
enddef

def OnMonitorLine(line: string)
    if line =~# '^signal '
        FlushSignal()
        cur_sig  = ParseSignalHeader(line)
        cur_args = []
    elseif !empty(cur_sig)
        add(cur_args, line)
    endif

    if flush_timer != -1
        timer_stop(flush_timer)
    endif
    flush_timer = timer_start(50, (_) => FlushSignal())
enddef

def FlushSignal()
    if flush_timer != -1
        timer_stop(flush_timer)
        flush_timer = -1
    endif
    if empty(cur_sig)
        return
    endif
    var sig  = cur_sig
    var args = cur_args
    cur_sig  = {}
    cur_args = []
    DispatchSignal(sig, args)
enddef

def ParseSignalHeader(line: string): dict<string>
    return {
        member: matchstr(line, 'member=\zs\S\+'),
        sender: matchstr(line, 'sender=\zs\S\+'),
        path:   matchstr(line, 'path=\zs[^;]\+'),
    }
enddef

def DispatchSignal(sig: dict<string>, args: list<string>)
    if OnSignal != null_function
        OnSignal(get(sig, 'member', ''), sig, args)
    endif
enddef

# ── Helpers (exported for consumers) ───────────────────────────────────

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

def Reset()
    StopMonitor()
    uri         = ''
    dbus_name   = ''
    status      = 'CLOSED'
    connected   = false
    window_path = ''
enddef
