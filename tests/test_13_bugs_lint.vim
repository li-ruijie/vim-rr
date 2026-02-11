vim9script
# Additional static lint checks targeting specific bug patterns found during
# the vim9script port review.  Each rule is designed to catch a class of bugs
# with low false-positive rates.
#
# Bugs caught by these rules (see BUGS.md for details):
#   BlockScopedVarLeak      -> BUG-01, BUG-11
#   FilereadableLiteralGVar -> BUG-07
#   CallbackMissingGPrefix  -> BUG-13
#   OmnifuncMissingGPrefix  -> BUG-14, BUG-15
#   OutCbWrongParamType     -> BUG-17, BUG-19
#   ExistsSPrefixInVim9     -> BUG-22
#   ExistsBareName          -> BUG-32
#   AlwaysTrueOrOne         -> BUG-25
#   EnvVarVimVarAssign      -> BUG-21
#   ExecuteLetInDef         -> BUG-04, BUG-05
#
# Bugs NOT catchable by static lint (need type inference or semantic analysis):
#   BUG-02 (missing g: on option variable)
#   BUG-03 (input() string vs number)
#   BUG-06 (uninitialized variable — cross-file)
#   BUG-08, BUG-09, BUG-10 (split() returns strings)
#   BUG-12 (list vs string comparison)
#   BUG-16 (inverted logic — semantic)
#   BUG-18, BUG-20 (SyncTeX string through execute)
#   BUG-23 (g:R_newsize uninitialized — cross-file)
#   BUG-24 (mixed bool/number — type inference)
#   BUG-26 (dead code from conflicting guards — semantic)

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
# Catches: BUG-01 (FindDebugFunc), BUG-11 (SyncTeX_backward)
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
# Catches: BUG-07 (bibcompl.vim)
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
# g: prefix for global functions.  Detects patterns like:
#   'err_cb': 'ROnJobStderr'  (should be 'g:ROnJobStderr')
#   'exit_cb': 'ROnJobExit'   (should be 'g:ROnJobExit')
# Catches: BUG-13 (rstudio.vim)
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
# b:rplugin_non_r_omnifunc value missing g: prefix
# ========================================================================
# The b:rplugin_non_r_omnifunc variable stores a function name string
# that is later resolved via function(name) inside def g:CompleteR().
# In a def block, function("Name") only searches script-local scope.
# The value must include "g:" for global function resolution.
# Catches: BUG-14, BUG-15 (rmd_vimr.vim, rhelp_vimr.vim)
def OmnifuncMissingGPrefix(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var lnum = 0
  for line in lines
    lnum += 1
    # Match: b:rplugin_non_r_omnifunc = "SomeName"
    # where SomeName does NOT start with g:
    if line =~ 'b:rplugin_non_r_omnifunc\s*=\s*"[A-Z]'
      if line !~ 'b:rplugin_non_r_omnifunc\s*=\s*"g:'
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
# argument, not a `job`.  The err_cb callback also receives a `channel`.
# Annotating the first parameter as `: job` causes E1013 at runtime.
# Catches: BUG-17 (pdf_okular.vim), BUG-19 (pdf_zathura.vim)
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
# Script-local variables are simply declared with `var name` at script
# level.  exists('s:name') always returns false.
# Catches: BUG-22 (start_r.vim)
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
# should be exists("g:rdoc_minlines").  This rule flags exists() calls
# where the argument is a bare identifier without g:/b:/w:/t:/v:/$/*
# prefix and starts with a lowercase letter (user option convention).
# Uses \< word boundary to avoid matching bufexists(), fileexists() etc.
# Catches: BUG-32 (syntax/rdoc.vim)
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
    # Match \<exists\>( to avoid matching bufexists(), fileexists() etc.
    # Then check for a bare lowercase name without scope prefix.
    # Exclude exists('*name') (function), exists(':name') (command),
    # exists('#name') (autocmd), exists('+name') (option).
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
# the else branch dead code.  This is typically a debugging leftover.
# Catches: BUG-25 (vimbuffer.vim)
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
# v: variable like v:windowid, v:count, v:lnum etc. without string()
# wrap may cause E1012 depending on Vim version.
# Catches: BUG-21 (common_global.vim)
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
# This rule detects patterns where a variable is assigned a string
# starting with "let " and is later passed to execute/exe without the
# `legacy` keyword.
# Catches: BUG-05 (comment.vim)
def ExecuteLetInDef(filepath: string): list<string>
  var errors: list<string> = []
  if !IsVim9(filepath)
    return errors
  endif
  var lines = readfile(filepath)
  var in_def = false
  var in_legacy = 0
  # Track vars assigned from strings containing "let "
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
    # Detect: var cmd = "let ..." or cmd = "let ..."
    var m = matchstr(line, '^\s*\%(var\s\+\)\?\zs\w\+\ze\s*=.*"let\s')
    if m != ''
      let_vars[m] = true
    endif
    # Detect: execute cmd  or  exe cmd  (without legacy prefix)
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
# Run all checks
# ========================================================================
var blockleak_errors: list<string> = []
var freadable_errors: list<string> = []
var callback_errors: list<string> = []
var omnifunc_errors: list<string> = []
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
    omnifunc_errors += OmnifuncMissingGPrefix(filepath)
    outcb_errors += OutCbWrongParamType(filepath)
    exists_s_errors += ExistsSPrefixInVim9(filepath)
    exists_bare_errors += ExistsBareName(filepath)
    or_one_errors += AlwaysTrueOrOne(filepath)
    envvvar_errors += EnvVarVimVarAssign(filepath)
    exelet_errors += ExecuteLetInDef(filepath)
  endif
endfor

g:Assert(len(blockleak_errors) == 0,
  'block-scoped var used after block closes (E1001)'
  .. (len(blockleak_errors) > 0
      ? ' — found: ' .. join(blockleak_errors, ', ') : ''))

g:Assert(len(freadable_errors) == 0,
  'filereadable/executable called on literal "g:..." string'
  .. (len(freadable_errors) > 0
      ? ' — found: ' .. join(freadable_errors, ', ') : ''))

g:Assert(len(callback_errors) == 0,
  'job callback string missing g: prefix'
  .. (len(callback_errors) > 0
      ? ' — found: ' .. join(callback_errors, ', ') : ''))

g:Assert(len(omnifunc_errors) == 0,
  'b:rplugin_non_r_omnifunc value missing g: prefix (E700)'
  .. (len(omnifunc_errors) > 0
      ? ' — found: ' .. join(omnifunc_errors, ', ') : ''))

g:Assert(len(outcb_errors) == 0,
  'out_cb/err_cb callback first param should be channel not job (E1013)'
  .. (len(outcb_errors) > 0
      ? ' — found: ' .. join(outcb_errors, ', ') : ''))

g:Assert(len(exists_s_errors) == 0,
  'exists(''s:name'') always false in vim9 — no s: prefix'
  .. (len(exists_s_errors) > 0
      ? ' — found: ' .. join(exists_s_errors, ', ') : ''))

g:Assert(len(exists_bare_errors) == 0,
  'exists("name") without scope prefix — probably needs g:'
  .. (len(exists_bare_errors) > 0
      ? ' — found: ' .. join(exists_bare_errors, ', ') : ''))

g:Assert(len(or_one_errors) == 0,
  '|| 1 or || true makes condition always true (dead else branch)'
  .. (len(or_one_errors) > 0
      ? ' — found: ' .. join(or_one_errors, ', ') : ''))

g:Assert(len(envvvar_errors) == 0,
  '$ENVVAR = v:numeric_var without string() wrap (E1012)'
  .. (len(envvvar_errors) > 0
      ? ' — found: ' .. join(envvvar_errors, ', ') : ''))

g:Assert(len(exelet_errors) == 0,
  'execute of string containing "let" in def block without legacy (E1126)'
  .. (len(exelet_errors) > 0
      ? ' — found: ' .. join(exelet_errors, ', ') : ''))
