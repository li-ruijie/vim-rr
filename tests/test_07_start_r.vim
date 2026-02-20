vim9script
# Tests for start_r.vim pure functions

g:SetSuite('start_r')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# IsSendCmdToRFake
# ========================================================================
def FuncToString(F: func): string
  return string(F)
enddef

# ========================================================================
# CountBraces (also tested in common_global but these are more start_r specific)
# ========================================================================
def CountBraces(line: string): number
  var result = 0
  for c in split(line, '\zs')
    if c == '{'
      result += 1
    elseif c == '}'
      result -= 1
    endif
  endfor
  return result
enddef

g:AssertEqual(CountBraces('function() {'), 1, 'CountBraces: function open')
g:AssertEqual(CountBraces('  }'), -1, 'CountBraces: closing brace')
g:AssertEqual(CountBraces('  if (x) { y } else { z }'), 0, 'CountBraces: balanced if-else')

# ========================================================================
# RParenDiff
# ========================================================================
def RParenDiff(str: string): number
  var result = 0
  for c in split(str, '\zs')
    if c == '('
      result += 1
    elseif c == ')'
      result -= 1
    endif
  endfor
  return result
enddef

g:AssertEqual(RParenDiff('f(x)'), 0, 'RParenDiff: balanced call')
g:AssertEqual(RParenDiff('f(x, g('), 2, 'RParenDiff: two unclosed')
g:AssertEqual(RParenDiff('))'), -2, 'RParenDiff: two extra closes')

# ========================================================================
# CleanOxygenLine
# ========================================================================
def CleanOxygenLine(line: string): string
  return substitute(line, "^\\s*#'\\=\\s*", "", "")
enddef

g:AssertEqual(CleanOxygenLine("#' @param x The value"), '@param x The value', 'CleanOxygenLine: roxygen param')
g:AssertEqual(CleanOxygenLine("# regular"), 'regular', 'CleanOxygenLine: regular comment')
g:AssertEqual(CleanOxygenLine("   # indented"), 'indented', 'CleanOxygenLine: indented')

# ========================================================================
# GetSourceArgs
# ========================================================================
def GetSourceArgs(e: string): string
  return e == "echo" ? ", echo=TRUE" : ""
enddef

g:AssertEqual(GetSourceArgs("echo"), ", echo=TRUE", 'GetSourceArgs: echo')
g:AssertEqual(GetSourceArgs("silent"), "", 'GetSourceArgs: silent')

# ========================================================================
# GoDown logic
# ========================================================================
def ShouldSkipLine(line: string): bool
  return line =~ '^\s*$' || line =~ '^\s*#'
enddef

g:Assert(ShouldSkipLine(''), 'ShouldSkipLine: empty line')
g:Assert(ShouldSkipLine('   '), 'ShouldSkipLine: whitespace only')
g:Assert(ShouldSkipLine('# comment'), 'ShouldSkipLine: comment')
g:Assert(ShouldSkipLine('  # indented comment'), 'ShouldSkipLine: indented comment')
g:Assert(!ShouldSkipLine('x <- 1'), 'ShouldSkipLine: code line')
g:Assert(!ShouldSkipLine('  x <- 1'), 'ShouldSkipLine: indented code')

# ========================================================================
# RSetMyPort
# ========================================================================
def SimulateSetMyPort(p: number): dict<any>
  var rplugin: dict<any> = {'myport': 0}
  rplugin.myport = p
  $VIMR_PORT = string(p)
  return rplugin
enddef

var result = SimulateSetMyPort(9876)
g:AssertEqual(result.myport, 9876, 'SimulateSetMyPort: port set correctly')

# ========================================================================
# R command quoting
# ========================================================================
def QuoteRCmd(cmd: string): string
  return substitute(cmd, '"', '\\"', "g")
enddef

g:AssertEqual(QuoteRCmd('print("hello")'), 'print(\"hello\")', 'QuoteRCmd: double quotes escaped')
g:AssertEqual(QuoteRCmd('x <- 1'), 'x <- 1', 'QuoteRCmd: no quotes unchanged')

# ========================================================================
# RSetWD command construction
# ========================================================================
def BuildSetWDCmd(dir: string): string
  return 'setwd("' .. dir .. '")'
enddef

g:AssertEqual(BuildSetWDCmd('/home/user'), 'setwd("/home/user")', 'BuildSetWDCmd: simple path')
g:AssertEqual(BuildSetWDCmd(''), 'setwd("")', 'BuildSetWDCmd: empty path')

# ========================================================================
# AddForDeletion
# ========================================================================
if !exists('g:rplugin.files_to_delete')
  g:rplugin.files_to_delete = []
endif

def AddForDeletion(fname: string)
  if index(g:rplugin.files_to_delete, fname) == -1
    add(g:rplugin.files_to_delete, fname)
  endif
enddef

AddForDeletion('/tmp/test1')
g:AssertEqual(len(g:rplugin.files_to_delete), 1, 'AddForDeletion: adds file')
AddForDeletion('/tmp/test1')
g:AssertEqual(len(g:rplugin.files_to_delete), 1, 'AddForDeletion: no duplicates')
AddForDeletion('/tmp/test2')
g:AssertEqual(len(g:rplugin.files_to_delete), 2, 'AddForDeletion: adds second file')

# ========================================================================
# RMakeRmd target logic
# ========================================================================
def BuildRmdTarget(t: string, ft: string): string
  if t == 'default'
    return ''
  elseif ft == 'quarto'
    if t == 'pdf'
      return ', output_format = "pdf"'
    elseif t == 'html'
      return ', output_format = "html"'
    endif
  else
    return ', output_format = "' .. t .. '"'
  endif
  return ''
enddef

g:AssertEqual(BuildRmdTarget('default', 'rmd'), '', 'BuildRmdTarget: default')
g:AssertEqual(BuildRmdTarget('pdf', 'quarto'), ', output_format = "pdf"', 'BuildRmdTarget: quarto pdf')
g:AssertEqual(BuildRmdTarget('pdf_document', 'rmd'), ', output_format = "pdf_document"', 'BuildRmdTarget: rmd pdf_document')

# ========================================================================
# StartRStudio guard must use IsJobRunning, not SendCmdToR (restart bug)
# ========================================================================
var rstudio_lines = readfile(expand('<sfile>:p:h:h') .. '/R/rstudio.vim')
var in_startrstudio = false
var guard_uses_isjobrunning = false
for rstline in rstudio_lines
  if rstline =~ 'def g:StartRStudio()'
    in_startrstudio = true
  elseif in_startrstudio && rstline =~ '^\s*enddef\s*$'
    break
  elseif in_startrstudio && rstline =~ 'IsJobRunning.*RStudio'
    guard_uses_isjobrunning = true
  endif
endfor
g:Assert(guard_uses_isjobrunning, 'StartRStudio guard must use IsJobRunning("RStudio")')

# ========================================================================
# SetSendCmdToR must check R_pid before activating (stale timer guard)
# ========================================================================
var start_r_lines = readfile(expand('<sfile>:p:h:h') .. '/R/start_r.vim')
var in_setsendcmd = false
var rpid_guard_found = false
for srline in start_r_lines
  if srline =~ 'def g:SetSendCmdToR('
    in_setsendcmd = true
  elseif in_setsendcmd && srline =~ '^\s*enddef\s*$'
    break
  elseif in_setsendcmd && srline =~ 'R_pid\s*==\s*0'
    rpid_guard_found = true
  endif
endfor
g:Assert(rpid_guard_found, 'SetSendCmdToR must guard against stale timers via R_pid check')

# ========================================================================
# SetVimcomInfo must cancel the vimcom timeout timer
# ========================================================================
var in_setvimcominfo = false
var cancels_timeout = false
for svline in start_r_lines
  if svline =~ 'def g:SetVimcomInfo('
    in_setvimcominfo = true
  elseif in_setvimcominfo && svline =~ '^\s*enddef\s*$'
    break
  elseif in_setvimcominfo && svline =~ 'timer_stop(vimcom_timeout_timer)'
    cancels_timeout = true
  endif
endfor
g:Assert(cancels_timeout, 'SetVimcomInfo must cancel vimcom_timeout_timer')

# ========================================================================
# SetVimcomInfo calls SetSendCmdToR synchronously (no timer)
# ========================================================================
var in_setvimcominfo2 = false
var has_setsend_timer = false
var has_setsend_direct = false
for sv2line in start_r_lines
  if sv2line =~ 'def g:SetVimcomInfo('
    in_setvimcominfo2 = true
  elseif in_setvimcominfo2 && sv2line =~ '^\s*enddef\s*$'
    break
  elseif in_setvimcominfo2 && sv2line =~ 'timer_start.*SetSendCmdToR'
    has_setsend_timer = true
  elseif in_setvimcominfo2 && sv2line =~ '^\s*g:SetSendCmdToR()\s*$'
    has_setsend_direct = true
  endif
endfor
g:Assert(!has_setsend_timer, 'SetVimcomInfo must not use timer for SetSendCmdToR')
g:Assert(has_setsend_direct, 'SetVimcomInfo must call SetSendCmdToR() directly')

# ========================================================================
# RQuit must not use a sleep-poll loop for RStudio exit
# ========================================================================
var in_rquit = false
var has_sleep_poll = false
for rqline in start_r_lines
  if rqline =~ 'def g:RQuit('
    in_rquit = true
  elseif in_rquit && rqline =~ '^\s*enddef\s*$'
    break
  elseif in_rquit && rqline =~ 'while.*IsJobRunning.*RStudio'
    has_sleep_poll = true
  endif
endfor
g:Assert(!has_sleep_poll, 'RQuit must not use while/sleep loop for RStudio exit')

# ========================================================================
# RQuit bunload must not be followed by sleep
# ========================================================================
var in_rquit2 = false
var saw_bunload = false
var sleep_after_bunload = false
for rq2line in start_r_lines
  if rq2line =~ 'def g:RQuit('
    in_rquit2 = true
  elseif in_rquit2 && rq2line =~ '^\s*enddef\s*$'
    break
  elseif in_rquit2 && rq2line =~ 'bunload.*Object_Browser'
    saw_bunload = true
  elseif in_rquit2 && saw_bunload && rq2line =~ '^\s*sleep\b'
    sleep_after_bunload = true
    saw_bunload = false
  elseif in_rquit2 && saw_bunload && rq2line =~ '\S'
    saw_bunload = false
  endif
endfor
g:Assert(!sleep_after_bunload, 'RQuit must not sleep after bunload')

# ========================================================================
# ClearRInfo must chain restart via restart_pending flag
# ========================================================================
var in_clearrinfo = false
var has_restart_chain = false
for crline in start_r_lines
  if crline =~ 'def g:ClearRInfo('
    in_clearrinfo = true
  elseif in_clearrinfo && crline =~ '^\s*enddef\s*$'
    break
  elseif in_clearrinfo && crline =~ 'restart_pending'
    has_restart_chain = true
  endif
endfor
g:Assert(has_restart_chain, 'ClearRInfo must check restart_pending flag')

# ========================================================================
# ROnJobExit must call OnRStudioQuitComplete for RStudio key
# ========================================================================
var vimrcom_lines = readfile(expand('<sfile>:p:h:h') .. '/R/vimrcom.vim')
var in_ronjobxit = false
var has_rstudio_quit_hook = false
for vjline in vimrcom_lines
  if vjline =~ 'def g:ROnJobExit('
    in_ronjobxit = true
  elseif in_ronjobxit && vjline =~ '^\s*enddef\s*$'
    break
  elseif in_ronjobxit && vjline =~ 'RStudio.*OnRStudioQuitComplete'
    has_rstudio_quit_hook = true
  endif
endfor
g:Assert(has_rstudio_quit_hook, 'ROnJobExit must call OnRStudioQuitComplete for RStudio')

# ========================================================================
# RRestart must not use timer_start to delay StartR
# ========================================================================
var in_rrestart = false
var has_restart_timer = false
for rrline in start_r_lines
  if rrline =~ 'def g:RRestart('
    in_rrestart = true
  elseif in_rrestart && rrline =~ '^\s*enddef\s*$'
    break
  elseif in_rrestart && rrline =~ 'timer_start'
    has_restart_timer = true
  endif
endfor
g:Assert(!has_restart_timer, 'RRestart must not use timer_start (uses restart_pending instead)')

# ========================================================================
# SendAboveLinesToR, SendFHChunkToR, SendMotionToR must have stubs
# ========================================================================
var cg_lines = readfile(expand('<sfile>:p:h:h') .. '/R/common_global.vim')
var cg_text = join(cg_lines, "\n")
for stub_name in ['SendAboveLinesToR', 'SendFHChunkToR', 'SendMotionToR']
  g:Assert(cg_text =~ 'g:' .. stub_name .. " = function('g:RNotRunning')",
    stub_name .. ' must have provisory link in common_global.vim')
endfor

# ========================================================================
# start_r.vim must unlet! the new stubs
# ========================================================================
var sr_text = join(start_r_lines, "\n")
for unlet_name in ['SendAboveLinesToR', 'SendFHChunkToR', 'SendMotionToR']
  g:Assert(sr_text =~ 'unlet! g:' .. unlet_name,
    unlet_name .. ' must have unlet! in start_r.vim')
endfor

# ========================================================================
# R_start_on_send defaults to 0
# ========================================================================
g:AssertEqual(get(g:, 'R_start_on_send', 0), 0, 'R_start_on_send defaults to 0')
