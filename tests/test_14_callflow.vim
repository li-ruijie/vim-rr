vim9script
# Static analysis tests for call-flow bugs found during Round 2 review.
# Each test catches a specific class of bug with low false-positive rates.
#
# Bugs caught by these rules (see BUGS.md for details):
#   UndefinedGlobalFunc       -> BUG-41
#   IsJobRunningArgType       -> BUG-42
#   StartJobReturnType        -> BUG-43
#   SubstituteNumericArg      -> BUG-44
#   FuncrefMissingGAtScript   -> BUG-45
#   SyncTexMissingStr2nr      -> BUG-46
#   QpdfviewInvertedMsg       -> BUG-49
#   CompletionIdNeverIncr     -> BUG-50
#   ComplUsageNotInitialized  -> BUG-51
#   HasAwbtNeverSet           -> BUG-57
#   DeadExistsAfterAssign     -> BUG-58
#   IncompletePrefixCoverage  -> BUG-61

g:SetSuite('callflow')

var plugin_root = expand('<sfile>:p:h:h')

# Collect all .vim files from plugin directories
var vim_files: list<string> = []
for dir in ['R', 'ftdetect', 'ftplugin', 'syntax', 'autoload']
  var d = plugin_root .. '/' .. dir
  if isdirectory(d)
    vim_files += glob(d .. '/**/*.vim', false, true)
  endif
endfor

# ========================================================================
# Helper: does the file start with vim9script?
# ========================================================================
def IsVim9(filepath: string): bool
  var lines = readfile(filepath, '', 10)
  for line in lines
    if line =~ '^\s*vim9script\s*$'
      return true
    endif
  endfor
  return false
enddef

# ========================================================================
# BUG-42: IsJobRunning receives dict value instead of string key
# ========================================================================
# g:IsJobRunning(key: string) expects a string like "R", not
# g:rplugin.jobs["R"] which is a channel/job object.
def IsJobRunningArgType(): list<string>
  var errors: list<string> = []
  for filepath in vim_files
    var lines = readfile(filepath)
    var lnum = 0
    for line in lines
      lnum += 1
      if line =~ 'g:IsJobRunning(g:rplugin\.jobs\['
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# BUG-43: jobs dict must store job objects, not channels
# ========================================================================
# g:rplugin.jobs must store job objects so exit_cb (which receives a job)
# can match against stored values in g:GetJobTitle.  Storing channels via
# job_getchannel makes the comparison always fail.
def JobsStoreChannel(): list<string>
  var errors: list<string> = []
  for filepath in vim_files
    var lines = readfile(filepath)
    var lnum = 0
    for line in lines
      lnum += 1
      # Flag any line that stores job_getchannel() result in g:rplugin.jobs
      if line =~ 'g:rplugin\.jobs\[' && line =~ 'job_getchannel('
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
          .. ' jobs dict stores channel instead of job')
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# BUG-44: substitute() called with numeric first argument
# ========================================================================
# substitute() requires a string first argument.  Functions like
# localtime() return a number.
def SubstituteNumericArg(): list<string>
  var errors: list<string> = []
  var num_funcs = ['localtime', 'line', 'col', 'winnr', 'bufnr',
    'tabpagenr', 'virtcol', 'getpid', 'argc']
  for filepath in vim_files
    var lines = readfile(filepath)
    var lnum = 0
    for line in lines
      lnum += 1
      for fn in num_funcs
        if line =~ 'substitute(' .. fn .. '('
          add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
            .. ' substitute(' .. fn .. '() returns number')
        endif
      endfor
    endfor
  endfor
  return errors
enddef

# ========================================================================
# BUG-45: function('Name') without g: prefix at script level
# ========================================================================
# At script level in vim9script, function('Name') only searches
# script-local scope.  Global functions need function('g:Name').
def FuncrefMissingGAtScript(): list<string>
  var errors: list<string> = []
  for filepath in vim_files
    if !IsVim9(filepath)
      continue
    endif
    var lines = readfile(filepath)
    var in_def = false
    var in_legacy = 0
    var lnum = 0
    for line in lines
      lnum += 1
      if line =~ '^\s*fu\%[nction]!\?\s'
        in_legacy += 1
      elseif line =~ '^\s*endfu\%[nction]'
        in_legacy = max([0, in_legacy - 1])
      endif
      if in_legacy > 0
        continue
      endif
      if line =~ '^\s*def\s'
        in_def = true
      elseif line =~ '^\s*enddef'
        in_def = false
      endif
      # Only check script level (def blocks covered by test_11)
      if in_def || line =~ '^\s*#'
        continue
      endif
      # Match function('Name') where Name starts uppercase
      # and does NOT have g: or s: prefix
      if line =~ "function('[A-Z]" && line !~ "function('g:" && line !~ "function('s:"
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# BUG-46: SyncTeX_backward called with string line number (no str2nr)
# ========================================================================
def SyncTexMissingStr2nr(): list<string>
  var errors: list<string> = []
  for filepath in vim_files
    var lines = readfile(filepath)
    var lnum = 0
    for line in lines
      lnum += 1
      # Match SyncTeX_backward calls where second arg is a "%l" string
      # without str2nr() wrapping
      if line =~ 'SyncTeX_backward(' && line =~ '"%[lf]'
            && line !~ 'str2nr(' && line !~ '^\s*#'
        # Only flag lines where %l is the line number argument (second)
        if line =~ 'SyncTeX_backward([^)]*,\s*[^s][^t][^r]'
              || line =~ 'SyncTeX_backward([^)]*,\s*\\*"'
          add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
        endif
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# BUG-49: qpdfview inverted message — "does support" without "not"
# ========================================================================
def QpdfviewInvertedMsg(): list<string>
  var errors: list<string> = []
  var qpdf = plugin_root .. '/R/pdf_qpdfview.vim'
  if !filereadable(qpdf)
    return errors
  endif
  var lines = readfile(qpdf)
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ 'does support file names' && line !~ 'does not support'
      add(errors, fnamemodify(qpdf, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# BUG-50: completion_id never incremented
# ========================================================================
def CompletionIdNeverIncr(): list<string>
  var errors: list<string> = []
  var found_increment = false
  for filepath in vim_files
    var lines = readfile(filepath)
    for line in lines
      if line =~ 'completion_id\s*+=\s*1'
            || line =~ 'completion_id\s*=\s*.*completion_id\s*+\s*1'
        found_increment = true
        break
      endif
    endfor
    if found_increment
      break
    endif
  endfor
  if !found_increment
    add(errors, 'g:rplugin.completion_id is never incremented')
  endif
  return errors
enddef

# ========================================================================
# BUG-51: compl_usage not initialized at script level
# ========================================================================
def ComplUsageNotInitialized(): list<string>
  var errors: list<string> = []
  var complete_vim = plugin_root .. '/R/complete.vim'
  if !filereadable(complete_vim)
    return errors
  endif
  var lines = readfile(complete_vim)
  var found_init = false
  var in_def = false
  for line in lines
    if line =~ '^\s*def\s'
      in_def = true
    elseif line =~ '^\s*enddef'
      in_def = false
    endif
    # Script-level initialization
    if !in_def && line =~ 'g:rplugin\.compl_usage\s*='
      found_init = true
      break
    endif
  endfor
  if !found_init
    add(errors, 'R/complete.vim: g:rplugin.compl_usage missing script-level init')
  endif
  return errors
enddef

# ========================================================================
# BUG-57: has_awbt never set to truthy value
# ========================================================================
def HasAwbtNeverSet(): list<string>
  var errors: list<string> = []
  var found_set = false
  for filepath in vim_files
    var lines = readfile(filepath)
    for line in lines
      if line =~ 'has_awbt\s*=\s*[1-9]'
            || line =~ 'has_awbt\s*=\s*v:true'
            || line =~ 'has_awbt\s*=\s*true'
        found_set = true
        break
      endif
    endfor
    if found_set
      break
    endif
  endfor
  if !found_set
    add(errors, 'g:rplugin.has_awbt is never set to a truthy value (dead feature)')
  endif
  return errors
enddef

# ========================================================================
# BUG-58: exists() check immediately after unconditional assignment
# ========================================================================
def DeadExistsAfterAssign(): list<string>
  var errors: list<string> = []
  for filepath in vim_files
    var lines = readfile(filepath)
    var lnum = 0
    var prev_assigned: dict<number> = {}  # varname -> line number
    for line in lines
      lnum += 1
      # Track let/var assignments
      var m = matchstr(line, '^\s*let\s\+\zs\w\+\ze\s*=')
      if m == ''
        m = matchstr(line, '^\s*var\s\+\zs\w\+\ze\s*=')
      endif
      if m != ''
        prev_assigned[m] = lnum
      endif
      # Check for exists() on recently-assigned variable
      var ex = matchstr(line, 'exists("\zs\w\+\ze")')
      if ex == ''
        ex = matchstr(line, "exists('" .. '\zs\w\+' .. "'" .. ')')
      endif
      if ex != '' && has_key(prev_assigned, ex)
        # Only flag if the assignment was within the last 5 lines
        if lnum - prev_assigned[ex] <= 5
          add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
            .. ' exists("' .. ex .. '") after assignment at line '
            .. prev_assigned[ex])
        endif
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# BUG-61: incomplete-line prefix coverage in RInitStdout
# ========================================================================
# The incomplete-line check must cover the same prefixes as the
# processing loop.  Currently the check has {RWarn, let, echo} but the
# loop also handles {call}.
def IncompletePrefixCoverage(): list<string>
  var errors: list<string> = []
  var ss = plugin_root .. '/R/start_server.vim'
  if !filereadable(ss)
    return errors
  endif
  var lines = readfile(ss)
  # Find the incomplete-line check line (contains '^RWarn' and '^let')
  var check_prefixes: list<string> = []
  var loop_prefixes: list<string> = []
  var in_init = false
  var past_split = false
  for line in lines
    if line =~ 'def g:RInitStdout'
      in_init = true
    elseif line =~ '^\s*enddef' && in_init
      in_init = false
    endif
    if !in_init
      continue
    endif
    # The incomplete-line check: extract prefixes from rcmd =~ patterns
    if line =~ "rcmd =\\~ '\\^" && !past_split
      for pref in ['RWarn', 'let', 'echo', 'call']
        if line =~ "'\\^" .. pref
          add(check_prefixes, pref)
        endif
      endfor
    endif
    # The processing loop: detect which prefixes are handled
    if line =~ 'split(rcmd'
      past_split = true
    endif
    if past_split
      for pref in ['RWarn', 'let', 'echo', 'call']
        if line =~ "cmd =\\~ '\\^" .. pref
              || line =~ "cmd =\\~ '\\^" .. pref
          if index(loop_prefixes, pref) < 0
            add(loop_prefixes, pref)
          endif
        endif
      endfor
    endif
  endfor
  # Check that every prefix in the loop is also in the check
  for pref in loop_prefixes
    if index(check_prefixes, pref) < 0
      add(errors, 'R/start_server.vim: RInitStdout incomplete-line check'
        .. ' missing prefix "' .. pref .. '"')
    endif
  endfor
  return errors
enddef

# ========================================================================
# Run all checks
# ========================================================================
var bug42_errors = IsJobRunningArgType()
var bug43_errors = JobsStoreChannel()
var bug44_errors = SubstituteNumericArg()
var bug45_errors = FuncrefMissingGAtScript()
var bug46_errors = SyncTexMissingStr2nr()
var bug49_errors = QpdfviewInvertedMsg()
var bug50_errors = CompletionIdNeverIncr()
var bug51_errors = ComplUsageNotInitialized()
var bug57_errors = HasAwbtNeverSet()
var bug58_errors = DeadExistsAfterAssign()
var bug61_errors = IncompletePrefixCoverage()

g:Assert(len(bug42_errors) == 0,
  'BUG-42: IsJobRunning must receive string key, not dict value'
  .. (len(bug42_errors) > 0
      ? ' — found: ' .. join(bug42_errors, ', ') : ''))

g:Assert(len(bug43_errors) == 0,
  'BUG-43: jobs dict must store job objects, not channels (job_getchannel)'
  .. (len(bug43_errors) > 0
      ? ' — found: ' .. join(bug43_errors, ', ') : ''))

g:Assert(len(bug44_errors) == 0,
  'BUG-44: substitute() first arg must be string, not number'
  .. (len(bug44_errors) > 0
      ? ' — found: ' .. join(bug44_errors, ', ') : ''))

g:Assert(len(bug45_errors) == 0,
  'BUG-45: function(''Name'') at script level needs g: prefix for globals'
  .. (len(bug45_errors) > 0
      ? ' — found: ' .. join(bug45_errors, ', ') : ''))

g:Assert(len(bug46_errors) == 0,
  'BUG-46: SyncTeX_backward line arg needs str2nr() wrapping'
  .. (len(bug46_errors) > 0
      ? ' — found: ' .. join(bug46_errors, ', ') : ''))

g:Assert(len(bug49_errors) == 0,
  'BUG-49: qpdfview message should say "does not support"'
  .. (len(bug49_errors) > 0
      ? ' — found: ' .. join(bug49_errors, ', ') : ''))

g:Assert(len(bug50_errors) == 0,
  'BUG-50: completion_id must be incremented before each request'
  .. (len(bug50_errors) > 0
      ? ' — found: ' .. join(bug50_errors, ', ') : ''))

g:Assert(len(bug51_errors) == 0,
  'BUG-51: g:rplugin.compl_usage must have script-level initialization'
  .. (len(bug51_errors) > 0
      ? ' — found: ' .. join(bug51_errors, ', ') : ''))

g:Assert(len(bug57_errors) == 0,
  'BUG-57: has_awbt must be set when GNOME AWBT extension is available'
  .. (len(bug57_errors) > 0
      ? ' — found: ' .. join(bug57_errors, ', ') : ''))

g:Assert(len(bug58_errors) == 0,
  'BUG-58: exists() check after unconditional assignment is dead code'
  .. (len(bug58_errors) > 0
      ? ' — found: ' .. join(bug58_errors, ', ') : ''))

g:Assert(len(bug61_errors) == 0,
  'BUG-61: RInitStdout incomplete-line check must cover all handled prefixes'
  .. (len(bug61_errors) > 0
      ? ' — found: ' .. join(bug61_errors, ', ') : ''))
