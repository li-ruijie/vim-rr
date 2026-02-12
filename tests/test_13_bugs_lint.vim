vim9script
# Static lint checks that catch classes of bugs likely to recur during
# vim9script and C development.  Each rule scans all relevant files (not
# just the original buggy file) so it detects future regressions.
#
# Rules ported from test_14, test_15, test_16 are noted with their
# original bug IDs for reference.

g:SetSuite('bugs_lint')

var plugin_root = expand('<sfile>:p:h:h')

# Collect all .vim files from plugin directories
var vim_files: list<string> = []
for dir in ['R', 'ftdetect', 'ftplugin', 'syntax', 'autoload']
  var d = plugin_root .. '/' .. dir
  if isdirectory(d)
    vim_files += glob(d .. '/**/*.vim', false, true)
  endif
endfor

# Helper: read a specific file, return empty list if missing
def ReadPluginFile(relpath: string): list<string>
  var filepath = plugin_root .. '/' .. relpath
  if filereadable(filepath)
    return readfile(filepath)
  endif
  return []
enddef

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
# Block-scoped variable leak detection
# ========================================================================
# In vim9, `var` inside if/else/for/while/try blocks is block-scoped.
# Variables declared inside a block are not visible after the closing
# keyword (endif/endfor/endwhile/endtry).  This rule detects variables
# declared at nesting > 0 that are referenced after their block closes.
def BlockScopedVarLeak(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var in_def = false
  var in_legacy = 0
  var nesting = 0
  # var_name -> nesting level where declared
  var block_vars: dict<number> = {}
  # var names that have gone out of scope
  var out_of_scope: dict<bool> = {}
  var lnum = 0

  for line in lines
    lnum += 1

    # Track legacy function blocks (skip them entirely)
    if line =~ '^\s*fu\%[nction]!\?\s'
      in_legacy += 1
    elseif line =~ '^\s*endfu\%[nction]'
      in_legacy = max([0, in_legacy - 1])
    endif
    if in_legacy > 0
      continue
    endif

    # Track def/enddef
    if line =~ '^\s*def\s'
      in_def = true
      nesting = 0
      block_vars = {}
      out_of_scope = {}
    elseif line =~ '^\s*enddef'
      in_def = false
    endif

    if !in_def || line =~ '^\s*#'
      continue
    endif

    # Track block nesting
    if line =~ '^\s*\%(if\|for\|while\|try\)\>'
      nesting += 1
    elseif line =~ '^\s*\%(else\|elseif\|catch\|finally\)\>'
      # These start a new sub-block at the same nesting level.
      # Variables from the previous sub-block go out of scope.
      for [nm, lvl] in items(block_vars)
        if lvl == nesting
          out_of_scope[nm] = true
        endif
      endfor
      filter(block_vars, (_, v) => v != nesting)
    elseif line =~ '^\s*\%(endif\|endfor\|endwhile\|endtry\)\>'
      # Variables at the current nesting level go out of scope
      for [nm, lvl] in items(block_vars)
        if lvl == nesting
          out_of_scope[nm] = true
        endif
      endfor
      filter(block_vars, (_, v) => v != nesting)
      nesting = max([0, nesting - 1])
    endif

    # Detect var declarations
    var m = matchstr(line, '^\s*var\s\+\zs\w\+')
    if m != ''
      if nesting > 0
        block_vars[m] = nesting
      endif
      # Re-declaration at any level removes from out_of_scope
      if has_key(out_of_scope, m)
        remove(out_of_scope, m)
      endif
    endif

    # Check for references to out-of-scope variables.
    # Exclude:
    #   - var declarations (already handled above)
    #   - comment lines
    #   - dict member access (.name) — prevents false positives from
    #     patterns like g:rplugin.varname or dict.varname
    if len(out_of_scope) > 0
      for nm in keys(out_of_scope)
        if line !~ '^\s*var\s' && line !~ '^\s*#'
              && line =~ '\%(^\|[^.]\)\<' .. nm .. '\>'
          add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
            .. ' ' .. nm)
          remove(out_of_scope, nm)
        endif
      endfor
    endif
  endfor
  return errors
enddef

# ========================================================================
# filereadable/executable called on literal "g:variable_name" string
# ========================================================================
# Detects filereadable("g:R_python3") where the quoted "g:..." is passed
# as a literal string instead of the variable value g:R_python3.
def FilereadableLiteralGVar(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '\<\%(filereadable\|executable\|isdirectory\|filewritable\|getftype\)\s*(\s*"g:'
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# Job callback strings missing g: prefix
# ========================================================================
# In vim9, string callback names passed to job_start() must include the
# g: prefix for global functions.
def CallbackMissingGPrefix(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ "'" .. '\%(err_cb\|exit_cb\|out_cb\|close_cb\|callback\)' .. "'" .. ':\s*'
          .. "'" .. '[A-Z]'
      # Check it does NOT already have g:
      if line !~ "'" .. '\%(err_cb\|exit_cb\|out_cb\|close_cb\|callback\)' .. "'" .. ':\s*'
            .. "'" .. 'g:'
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
      endif
    endif
  endfor
  return errors
enddef

# ========================================================================
# out_cb / err_cb callback with wrong `: job` type annotation
# ========================================================================
# The out_cb and close_cb callbacks receive a `channel` as the first
# argument, not a `job`.  Annotating the first parameter as `: job`
# causes E1013 at runtime.
def OutCbWrongParamType(filepath: string): list<string>
  var errors: list<string> = []
  if !IsVim9(filepath)
    return errors
  endif
  var lines = readfile(filepath)
  # Phase 1: collect function names used as out_cb/err_cb/close_cb
  var cb_func_names: dict<bool> = {}
  var lnum = 0
  for line in lines
    lnum += 1
    for cb in ['out_cb', 'err_cb', 'close_cb']
      var m = matchstr(line, "\\<" .. cb .. "\\>\\s*[:=]\\s*\\zs[A-Za-z_]\\w*")
      if m != '' && m !~ '^function\|true\|false\|v:'
        cb_func_names[m] = true
      endif
    endfor
  endfor
  # Phase 2: check those function defs for `: job` on first param
  lnum = 0
  for line in lines
    lnum += 1
    if line !~ '^\s*def\s'
      continue
    endif
    for fname in keys(cb_func_names)
      if line =~ '^\s*def\s\+\%(\w\+:\)\?' .. fname .. '\s*('
        if line =~ '(\s*\w\+\s*:\s*job\>'
          add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
            .. ' ' .. fname .. ' first param should be channel or any, not job')
        endif
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# exists('s:varname') in vim9script
# ========================================================================
# In vim9script, there is no s: prefix for script-local variables.
# exists('s:name') always returns false.
def ExistsSPrefixInVim9(filepath: string): list<string>
  var errors: list<string> = []
  if !IsVim9(filepath)
    return errors
  endif
  var lines = readfile(filepath)
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
    if line =~ "exists('s:" || line =~ 'exists("s:'
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# exists("varname") without scope prefix in vim9script
# ========================================================================
# In vim9script at script level, exists("rdoc_minlines") checks
# script-local scope.  Users set these as g:rdoc_minlines.  The check
# should be exists("g:rdoc_minlines").
def ExistsBareName(filepath: string): list<string>
  var errors: list<string> = []
  if !IsVim9(filepath)
    return errors
  endif
  var lines = readfile(filepath)
  var in_legacy = 0
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '^\s*fu\%[nction]!\?\s'
      in_legacy += 1
    elseif line =~ '^\s*endfu\%[nction]'
      in_legacy = max([0, in_legacy - 1])
    endif
    if in_legacy > 0 || line =~ '^\s*#'
      continue
    endif
    if line =~ "\\<exists\\>(['\"][a-z]"
          && line !~ "\\<exists\\>(['\"][gbwtv]:"
          && line !~ "\\<exists\\>(['\"][$&*#:+]"
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# || 1 (always-true condition)
# ========================================================================
# Detects conditions like `if expr || 1` which are always true, making
# the else branch dead code.  Typically a debugging leftover.
def AlwaysTrueOrOne(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '||\s*1\s*$' || line =~ '||\s*1\s*#'
          || line =~ '||\s*true\s*$' || line =~ '||\s*true\s*#'
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# $ENVVAR = v:variable (number-typed v: variables)
# ========================================================================
# Environment variables are always strings.  Assigning a number-typed
# v: variable without string() wrap causes E1012.
def EnvVarVimVarAssign(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var lnum = 0
  var numeric_vvars = 'v:windowid\|v:count\|v:count1\|v:lnum\|v:prevcount'
    .. '\|v:searchforward\|v:hlsearch\|v:mouse_win\|v:mouse_winid'
    .. '\|v:mouse_lnum\|v:mouse_col\|v:testing\|v:vim_did_enter'
  for line in lines
    lnum += 1
    if line =~ '\$\w\+\s*=\s*\%(' .. numeric_vvars .. '\)'
      if line !~ '\$\w\+\s*=\s*string\s*('
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
      endif
    endif
  endfor
  return errors
enddef

# ========================================================================
# execute/exe of string containing "let " in def blocks
# ========================================================================
# In vim9 def blocks, execute runs in vim9 context where `let` is E1126.
def ExecuteLetInDef(filepath: string): list<string>
  var errors: list<string> = []
  if !IsVim9(filepath)
    return errors
  endif
  var lines = readfile(filepath)
  var in_def = false
  var in_legacy = 0
  var let_vars: dict<bool> = {}
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
      let_vars = {}
    elseif line =~ '^\s*enddef'
      in_def = false
    endif
    if !in_def || line =~ '^\s*#'
      continue
    endif
    var m = matchstr(line, '^\s*\%(var\s\+\)\?\zs\w\+\ze\s*=.*"let\s')
    if m != ''
      let_vars[m] = true
    endif
    if line =~ '^\s*\%(exe\|execute\)\s' && line !~ '^\s*legacy\s'
      for vname in keys(let_vars)
        if line =~ '^\s*\%(exe\|execute\)\s\+' .. vname .. '\>'
          add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
            .. ' execute of var containing let')
        endif
      endfor
    endif
  endfor
  return errors
enddef

# ========================================================================
# substitute() called with numeric first argument
# ========================================================================
# substitute() requires a string first argument.  Functions like
# localtime() return a number.  (From BUG-44.)
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
# function('Name') without g: prefix at script level
# ========================================================================
# At script level in vim9script, function('Name') only searches
# script-local scope.  Global functions need function('g:Name').
# (Extends test_11's in-def check to script level.  From BUG-45.)
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
      if line =~ "function('[A-Z]" && line !~ "function('g:" && line !~ "function('s:"
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# exists() check immediately after unconditional assignment
# ========================================================================
# Scans all files for dead-code pattern where exists("var") is checked
# within 5 lines of unconditionally assigning that variable.  (From
# BUG-58.)
def DeadExistsAfterAssign(): list<string>
  var errors: list<string> = []
  for filepath in vim_files
    var lines = readfile(filepath)
    var lnum = 0
    var prev_assigned: dict<number> = {}
    for line in lines
      lnum += 1
      var m = matchstr(line, '^\s*let\s\+\zs\w\+\ze\s*=')
      if m == ''
        m = matchstr(line, '^\s*var\s\+\zs\w\+\ze\s*=')
      endif
      if m != ''
        prev_assigned[m] = lnum
      endif
      var ex = matchstr(line, 'exists("\zs\w\+\ze")')
      if ex == ''
        ex = matchstr(line, "exists('" .. '\zs\w\+' .. "'" .. ')')
      endif
      if ex != '' && has_key(prev_assigned, ex)
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
# &t_Co must be wrapped in str2nr() before comparison in def blocks
# ========================================================================
# In vim9 def blocks, &t_Co returns a string.  Comparing with a number
# via == is a type mismatch (E1072).  (From BUG-76.)
def TCoWithoutStr2nr(): list<string>
  var errors: list<string> = []
  var r_files = glob(plugin_root .. '/R/**/*.vim', false, true)
  for filepath in r_files
    var lines = readfile(filepath)
    var in_def = false
    var lnum = 0
    for line in lines
      lnum += 1
      if line =~ '^\s*def\s'
        in_def = true
      elseif line =~ '^\s*enddef'
        in_def = false
      endif
      if in_def && line =~ '&t_Co\s*==' && line !~ 'str2nr' && line !~ '^\s*#'
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
          .. ' &t_Co needs str2nr() in def block')
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# ftplugin autocmd FileType must use <buffer>
# ========================================================================
# Global autocmd FileType in a ftplugin accumulates on each buffer load.
# Must use <buffer> to keep the autocmd buffer-local.  (From BUG-90.)
def FtpluginGlobalAutocmd(): list<string>
  var errors: list<string> = []
  var ftplugin_files = glob(plugin_root .. '/ftplugin/**/*.vim', false, true)
  for filepath in ftplugin_files
    var lines = readfile(filepath)
    var lnum = 0
    for line in lines
      lnum += 1
      if line =~ 'autocmd\s\+FileType\s' && line !~ '<buffer>'
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum
          .. ' autocmd FileType must use <buffer> in ftplugin')
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# All g:JobStdin calls must have g:IsJobRunning guard
# ========================================================================
# Calling g:JobStdin without checking IsJobRunning first throws E906
# when the server is not running.  Scans all files that use JobStdin.
# (From BUG-103.)
def JobStdinAllSitesGuarded(): list<string>
  var errors: list<string> = []
  # Scan files known to use JobStdin
  var check_files = [
    'R/start_r.vim',
    'R/start_server.vim',
    'R/windows.vim',
    'R/bibcompl.vim',
    'ftplugin/rbrowser.vim',
  ]
  for relpath in check_files
    var filepath = plugin_root .. '/' .. relpath
    if !filereadable(filepath)
      continue
    endif
    var lines = readfile(filepath)
    var in_func = ''
    var has_guard = false
    var lnum = 0
    for line in lines
      lnum += 1
      if line =~ '^\s*def\s\+g:\(\w\+\)'
        in_func = matchstr(line, 'g:\zs\w\+')
        has_guard = false
      elseif line =~ '^\s*function\s\+g:\(\w\+\)'
        in_func = matchstr(line, 'g:\zs\w\+')
        has_guard = false
      elseif line =~ '^\s*enddef\>' || line =~ '^\s*endfunction\>'
        in_func = ''
        has_guard = false
      endif
      if in_func != ''
        # Skip functions that are only called when R is known running
        if index(['RClearConsole', 'RClearAll'], in_func) >= 0
          continue
        endif
        if line =~ 'IsJobRunning'
          has_guard = true
        endif
        if line =~ 'g:JobStdin(' && !has_guard && line !~ '^\s*#'
          add(errors, fnamemodify(filepath, ':t') .. ':' .. lnum
            .. ' ' .. in_func .. ': JobStdin needs IsJobRunning guard')
        endif
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# b:undo_ftplugin must include all buffer-local variables
# ========================================================================
# ftplugin files that set buffer-local variables must clean them up in
# b:undo_ftplugin.  (From BUG-119.)
def UndoFtpluginVars(): list<string>
  var errors: list<string> = []

  # rnoweb_vimr.vim must include b:rplugin_knitr_pattern
  var lines = ReadPluginFile('ftplugin/rnoweb_vimr.vim')
  var has_knitr_in_undo = false
  for line in lines
    if line =~ 'undo_ftplugin' && line =~ 'rplugin_knitr_pattern'
      has_knitr_in_undo = true
      break
    endif
  endfor
  if !has_knitr_in_undo
    add(errors, 'ftplugin/rnoweb_vimr.vim: undo_ftplugin missing'
      .. ' b:rplugin_knitr_pattern')
  endif

  # rmd_vimr.vim must include b:rplugin_non_r_omnifunc and b:rplugin_bibf
  lines = ReadPluginFile('ftplugin/rmd_vimr.vim')
  var has_omnifunc_undo = false
  var has_bibf_undo = false
  for line in lines
    if line =~ 'undo_ftplugin' && line =~ 'rplugin_non_r_omnifunc'
      has_omnifunc_undo = true
    endif
    if line =~ 'undo_ftplugin' && line =~ 'rplugin_bibf'
      has_bibf_undo = true
    endif
  endfor
  if !has_omnifunc_undo
    add(errors, 'ftplugin/rmd_vimr.vim: undo_ftplugin missing'
      .. ' b:rplugin_non_r_omnifunc')
  endif
  if !has_bibf_undo
    add(errors, 'ftplugin/rmd_vimr.vim: undo_ftplugin missing'
      .. ' b:rplugin_bibf')
  endif

  # rhelp_vimr.vim must include b:rplugin_non_r_omnifunc
  lines = ReadPluginFile('ftplugin/rhelp_vimr.vim')
  has_omnifunc_undo = false
  for line in lines
    if line =~ 'undo_ftplugin' && line =~ 'rplugin_non_r_omnifunc'
      has_omnifunc_undo = true
      break
    endif
  endfor
  if !has_omnifunc_undo
    add(errors, 'ftplugin/rhelp_vimr.vim: undo_ftplugin missing'
      .. ' b:rplugin_non_r_omnifunc')
  endif
  return errors
enddef

# ========================================================================
# sprintf(ebuf, ...) must be snprintf in C source
# ========================================================================
# sprintf without bounds checking is a buffer overflow risk.  All
# sprintf(ebuf calls should use snprintf(ebuf, sizeof(ebuf) instead.
# (From BUG-C25.)
def CSprintfEbuf(): list<string>
  var errors: list<string> = []
  var lines = ReadPluginFile('R/vimcom/src/vimcom.c')
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ 'sprintf(ebuf' && line !~ '^\s*//'
      add(errors, 'R/vimcom/src/vimcom.c:' .. lnum
        .. ' sprintf(ebuf must be snprintf(ebuf, sizeof(ebuf)')
    endif
  endfor
  return errors
enddef

# ========================================================================
# Run all checks
# ========================================================================

# Per-file checks (scan all vim files)
var blockleak_errors: list<string> = []
var freadable_errors: list<string> = []
var callback_errors: list<string> = []
var outcb_errors: list<string> = []
var exists_s_errors: list<string> = []
var exists_bare_errors: list<string> = []
var or_one_errors: list<string> = []
var envvvar_errors: list<string> = []
var exelet_errors: list<string> = []

for filepath in vim_files
  if IsVim9(filepath)
    blockleak_errors += BlockScopedVarLeak(filepath)
    freadable_errors += FilereadableLiteralGVar(filepath)
    callback_errors += CallbackMissingGPrefix(filepath)
    outcb_errors += OutCbWrongParamType(filepath)
    exists_s_errors += ExistsSPrefixInVim9(filepath)
    exists_bare_errors += ExistsBareName(filepath)
    or_one_errors += AlwaysTrueOrOne(filepath)
    envvvar_errors += EnvVarVimVarAssign(filepath)
    exelet_errors += ExecuteLetInDef(filepath)
  endif
endfor

# Self-contained checks
var subst_errors = SubstituteNumericArg()
var funcref_errors = FuncrefMissingGAtScript()
var dead_exists_errors = DeadExistsAfterAssign()
var tco_errors = TCoWithoutStr2nr()
var ftplugin_autocmd_errors = FtpluginGlobalAutocmd()
var jobstdin_errors = JobStdinAllSitesGuarded()
var undo_errors = UndoFtpluginVars()
var sprintf_errors = CSprintfEbuf()

# Helper for error suffix
def Err(errors: list<string>): string
  if len(errors) > 0
    return ' — found: ' .. join(errors, ', ')
  endif
  return ''
enddef

g:Assert(len(blockleak_errors) == 0,
  'block-scoped var used after block closes (E1001)'
  .. Err(blockleak_errors))

g:Assert(len(freadable_errors) == 0,
  'filereadable/executable called on literal "g:..." string'
  .. Err(freadable_errors))

g:Assert(len(callback_errors) == 0,
  'job callback string missing g: prefix'
  .. Err(callback_errors))

g:Assert(len(outcb_errors) == 0,
  'out_cb/err_cb callback first param should be channel not job (E1013)'
  .. Err(outcb_errors))

g:Assert(len(exists_s_errors) == 0,
  'exists(''s:name'') always false in vim9 — no s: prefix'
  .. Err(exists_s_errors))

g:Assert(len(exists_bare_errors) == 0,
  'exists("name") without scope prefix — probably needs g:'
  .. Err(exists_bare_errors))

g:Assert(len(or_one_errors) == 0,
  '|| 1 or || true makes condition always true (dead else branch)'
  .. Err(or_one_errors))

g:Assert(len(envvvar_errors) == 0,
  '$ENVVAR = v:numeric_var without string() wrap (E1012)'
  .. Err(envvvar_errors))

g:Assert(len(exelet_errors) == 0,
  'execute of string containing "let" in def block without legacy (E1126)'
  .. Err(exelet_errors))

g:Assert(len(subst_errors) == 0,
  'substitute() first arg must be string, not number'
  .. Err(subst_errors))

g:Assert(len(funcref_errors) == 0,
  'function(''Name'') at script level needs g: prefix for globals'
  .. Err(funcref_errors))

g:Assert(len(dead_exists_errors) == 0,
  'exists() check after unconditional assignment is dead code'
  .. Err(dead_exists_errors))

g:Assert(len(tco_errors) == 0,
  '&t_Co must use str2nr() before numeric comparison in def blocks'
  .. Err(tco_errors))

g:Assert(len(ftplugin_autocmd_errors) == 0,
  'ftplugin autocmd FileType must use <buffer>'
  .. Err(ftplugin_autocmd_errors))

g:Assert(len(jobstdin_errors) == 0,
  'all JobStdin calls must have IsJobRunning guard'
  .. Err(jobstdin_errors))

g:Assert(len(undo_errors) == 0,
  'b:undo_ftplugin must include all buffer-local variables'
  .. Err(undo_errors))

g:Assert(len(sprintf_errors) == 0,
  'sprintf(ebuf must be snprintf(ebuf, sizeof(ebuf))'
  .. Err(sprintf_errors))
