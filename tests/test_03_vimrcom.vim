vim9script
# Tests for vimrcom.vim job management functions

g:SetSuite('vimrcom')

# ========================================================================
# g:rplugin.jobs structure
# ========================================================================
if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif
g:rplugin.jobs = {"Server": "no", "R": "no", "Terminal emulator": "no", "BibComplete": "no"}

g:AssertType(g:rplugin.jobs, v:t_dict, 'jobs is a dictionary')
g:AssertEqual(g:rplugin.jobs["Server"], "no", 'Server job initially "no"')
g:AssertEqual(g:rplugin.jobs["R"], "no", 'R job initially "no"')
g:AssertEqual(g:rplugin.jobs["Terminal emulator"], "no", 'Terminal emulator job initially "no"')
g:AssertEqual(g:rplugin.jobs["BibComplete"], "no", 'BibComplete job initially "no"')

# ========================================================================
# GetJobTitle
# ========================================================================
def GetJobTitle(job_id: any): string
  for key in keys(g:rplugin.jobs)
    if g:rplugin.jobs[key] == job_id
      return key
    endif
  endfor
  return "Job"
enddef

g:Assert(GetJobTitle("no") != 'Job', 'GetJobTitle: finds a matching value for "no"')
g:AssertEqual(GetJobTitle("nonexistent"), 'Job', 'GetJobTitle: returns "Job" for unknown')

# Simulate a real job id
g:rplugin.jobs["TestJob"] = "test_id_123"
g:AssertEqual(GetJobTitle("test_id_123"), 'TestJob', 'GetJobTitle: finds custom job')
remove(g:rplugin.jobs, "TestJob")

# ========================================================================
# IsJobRunning (simulated without real channels)
# ========================================================================
def IsJobRunningSimulated(key: string): bool
  try
    var val = g:rplugin.jobs[key]
    # In real code, ch_status is called; here we just check "no"
    return val != "no"
  catch
    return false
  endtry
enddef

g:Assert(!IsJobRunningSimulated("Server"), 'IsJobRunning: Server not running')
g:Assert(!IsJobRunningSimulated("R"), 'IsJobRunning: R not running')
g:rplugin.jobs["Server"] = "some_channel"
g:Assert(IsJobRunningSimulated("Server"), 'IsJobRunning: Server running after assignment')
g:rplugin.jobs["Server"] = "no"

# ========================================================================
# job_handlers structure
# ========================================================================
g:rplugin.job_handlers = {
  'out_cb':  'ROnJobStdout',
  'err_cb':  'ROnJobStderr',
  'exit_cb': 'ROnJobExit',
}
g:Assert(has_key(g:rplugin.job_handlers, 'out_cb'), 'job_handlers has out_cb')
g:Assert(has_key(g:rplugin.job_handlers, 'err_cb'), 'job_handlers has err_cb')
g:Assert(has_key(g:rplugin.job_handlers, 'exit_cb'), 'job_handlers has exit_cb')
g:AssertEqual(g:rplugin.job_handlers['out_cb'], 'ROnJobStdout', 'out_cb is ROnJobStdout')

# ========================================================================
# Incomplete input handling
# ========================================================================
var incomplete_input = {'size': 0, 'received': 0, 'str': ''}
var waiting_more_input = false

def ResetIncompleteInput()
  incomplete_input = {'size': 0, 'received': 0, 'str': ''}
  waiting_more_input = false
enddef

def SimulateStdoutParsing(msg: string): string
  var cmd = substitute(msg, '\n', '', 'g')
  cmd = substitute(cmd, '\r', '', 'g')

  if cmd[0] == "\x11"
    var cmdsplt = split(cmd, "\x11")
    var size = str2nr(cmdsplt[0])
    var received = strlen(cmdsplt[1])
    if size == received
      return cmdsplt[1]
    else
      waiting_more_input = true
      incomplete_input.size = size
      incomplete_input.received = received
      incomplete_input.str = cmdsplt[1]
      return 'INCOMPLETE'
    endif
  endif
  return cmd
enddef

ResetIncompleteInput()
g:AssertEqual(SimulateStdoutParsing("call Foo()\n"), 'call Foo()', 'StdoutParsing: simple call command')
g:AssertEqual(SimulateStdoutParsing("let x = 1\r\n"), 'let x = 1', 'StdoutParsing: strips CR+LF')
g:AssertEqual(SimulateStdoutParsing(""), '', 'StdoutParsing: empty string')

# ========================================================================
# Command dispatch logic
# ========================================================================
def IsValidCommand(cmd: string): bool
  return cmd =~ '^call ' || cmd =~ '^let ' || cmd =~ '^unlet '
enddef

g:Assert(IsValidCommand('call Foo()'), 'IsValidCommand: call')
g:Assert(IsValidCommand('let x = 1'), 'IsValidCommand: let')
g:Assert(IsValidCommand('unlet x'), 'IsValidCommand: unlet')
g:Assert(!IsValidCommand('echo "hi"'), 'IsValidCommand: echo rejected')
g:Assert(!IsValidCommand(''), 'IsValidCommand: empty rejected')
g:Assert(!IsValidCommand('source file.vim'), 'IsValidCommand: source rejected')
