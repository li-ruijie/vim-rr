vim9script
# Static lint checks for vim9script files
# Catches porting errors that cause E114, E117, E127, and E477 at runtime.

g:SetSuite('vim9_lint')

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
# E114: legacy " comments at script level in vim9script files
# ========================================================================
# In vim9script, only # is a valid comment token at the script level.
# The " character is the legacy comment and only valid inside
# function!/endfunction blocks.
def ScriptLevelLegacyComments(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var in_legacy_func = 0
  var in_def = 0
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '^\s*fu\%[nction]!\?\s'
      in_legacy_func += 1
    elseif line =~ '^\s*endfu\%[nction]'
      in_legacy_func = max([0, in_legacy_func - 1])
    endif
    if line =~ '^\s*def\s'
      in_def += 1
    elseif line =~ '^\s*enddef'
      in_def = max([0, in_def - 1])
    endif
    # Flag " as first non-whitespace only at true script level
    if in_legacy_func == 0 && in_def == 0 && line =~ '^\s*"'
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# E127: def g: in vim9script files with re-source guards
# ========================================================================
# A re-source guard is:  if exists('*SomeName') ... finish ... endif
# In vim9script, def g: is compiled at parse time for the whole file,
# BEFORE finish can execute at runtime.  So the guard does not prevent
# redefinition and Vim throws E127 when the function is in the call stack.
# These functions must use function! instead.
def DefGWithFinishGuard(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  # Detect the re-source guard pattern: exists('*Name') followed by finish
  # before the matching endif.  A bare exists('*...) without finish (e.g.
  # checking whether another plugin is installed) is not a guard.
  var has_resource_guard = false
  var in_exists_block = false
  for line in lines
    if line =~ 'exists(''\*' || line =~ "exists(\"\\*"
      in_exists_block = true
    endif
    if in_exists_block && line =~ '^\s*finish\>'
      has_resource_guard = true
      break
    endif
    if in_exists_block && line =~ '^\s*endif\>'
      in_exists_block = false
    endif
  endfor
  if !has_resource_guard
    return errors
  endif
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '^\s*def g:'
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# E477: function! (with bang) is not allowed in vim9script
# ========================================================================
# In vim9script, function definitions use def/enddef.  Legacy function
# (without !) is tolerated for interop, but function! is an error.
def FunctionBangInVim9(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '^\s*function!\s'
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# E117: bare calls to legacy functions inside def blocks
# ========================================================================
# In a def body, calling FuncName() (uppercase, no g: prefix) requires
# the function to exist at compile time.  Legacy functions defined in
# other files may not exist yet — use g:FuncName() to defer lookup.
# We collect all legacy function names from the plugin, then flag bare
# calls to them inside def blocks of vim9script files.
def StripStringLiterals(line: string): string
  # Strip double-quoted strings (handling \" escapes)
  var s = substitute(line, '"[^"\\]*\%(\\.[^"\\]*\)*"', '', 'g')
  # Strip single-quoted strings
  return substitute(s, "'[^']*'", '', 'g')
enddef

def CollectLegacyFuncNames(all_files: list<string>): dict<bool>
  var names: dict<bool> = {}
  for filepath in all_files
    for line in readfile(filepath)
      var m = matchstr(line, '^\s*function!\?\s\+\zs[A-Z]\w*')
      if m != ''
        names[m] = true
      endif
    endfor
  endfor
  return names
enddef

def BareCallsInDef(filepath: string, legacy: dict<bool>): list<string>
  var errors: list<string> = []
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
    if !in_def
      continue
    endif
    # Skip comment lines
    if line =~ '^\s*#'
      continue
    endif
    var stripped = StripStringLiterals(line)
    for fname in keys(legacy)
      # Match FuncName( but not g:FuncName(
      if stripped =~ '\<' .. fname .. '\s*(' && stripped !~ 'g:' .. fname
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum .. ' ' .. fname)
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# E117: bare calls to def g: functions inside def blocks
# ========================================================================
# Same issue as legacy functions: inside a def body, FuncName() is
# resolved at compile time in script-local scope only.  Functions
# defined with `def g:FuncName()` are global, not script-local, so
# calling them without g: prefix causes E117.
def CollectDefGFuncNames(all_files: list<string>): dict<bool>
  var names: dict<bool> = {}
  for filepath in all_files
    if !IsVim9(filepath)
      continue
    endif
    for line in readfile(filepath)
      var m = matchstr(line, '^\s*def g:\zs[A-Z]\w*')
      if m != ''
        names[m] = true
      endif
    endfor
  endfor
  return names
enddef

# ========================================================================
# E700: function('LegacyName') inside def blocks without g: prefix
# ========================================================================
# In a def body, function('FuncName') resolves at runtime but only in
# script-local scope — global functions require function('g:FuncName').
# Without the prefix, Vim throws E700 (Unknown function).
# Additionally, function('g:Name') changes the string() representation
# to include 'g:', breaking comparisons.  The preferred fix is to resolve
# the funcref at script level and capture it in a script variable.
def StripDoubleQuotedStrings(line: string): string
  return substitute(line, '"[^"\\]*\%(\\.[^"\\]*\)*"', '', 'g')
enddef

def FuncrefInDef(filepath: string, legacy: dict<bool>): list<string>
  var errors: list<string> = []
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
    if !in_def || line =~ '^\s*#'
      continue
    endif
    # Only strip double-quoted strings: "function('Name')" in comparisons
    # should be ignored, but function('Name') calls must be detected.
    var stripped = StripDoubleQuotedStrings(line)
    for fname in keys(legacy)
      if stripped =~ "function('" .. fname .. "')"
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum .. ' ' .. fname)
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# E114 (execute context): readfile loop + execute without content guard
# ========================================================================
# Inside a def, execute runs in vim9 context where " starts a string
# literal.  If readfile() output is iterated and passed to execute
# without filtering, legacy " comment lines cause E114.
# Require a `continue` guard before any `execute` in such loops.
def ReadfileExecuteGuard(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var in_def = false
  var def_has_readfile = false
  var in_for = 0
  var for_has_execute = false
  var for_has_guard = false
  var for_execute_lnum = 0
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '^\s*def\s'
      in_def = true
      def_has_readfile = false
    elseif line =~ '^\s*enddef'
      in_def = false
    endif
    if !in_def
      continue
    endif
    if line =~ '\<readfile\s*('
      def_has_readfile = true
    endif
    if line =~ '^\s*for\s'
      in_for += 1
      if in_for == 1
        for_has_execute = false
        for_has_guard = false
        for_execute_lnum = 0
      endif
    elseif line =~ '^\s*endfor'
      if in_for == 1 && def_has_readfile && for_has_execute && !for_has_guard
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. for_execute_lnum)
      endif
      in_for = max([0, in_for - 1])
    endif
    if in_for == 1
      if line =~ '^\s*continue\>'
        for_has_guard = true
      endif
      if line =~ '^\s*execute\s' && !for_has_guard
        for_has_execute = true
        if for_execute_lnum == 0
          for_execute_lnum = lnum
        endif
      endif
    endif
  endfor
  return errors
enddef

# ========================================================================
# E114: legacy " comments inside def blocks
# ========================================================================
# In vim9script def bodies, " starts a string literal, not a comment.
# Legacy " comments (common as section separators like "------) cause E114.
# Use # for comments inside def blocks.
def LegacyCommentInDef(filepath: string): list<string>
  var errors: list<string> = []
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
    if in_def && line =~ '^\s*"'
      # Distinguish comments from string literals: strip escaped quotes
      # then check parity.  Strings have paired " (even count); a lone
      # leading " with no closing pair (odd count) is a legacy comment.
      var stripped = substitute(line, '\\"', '', 'g')
      if count(stripped, '"') % 2 == 1
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
      endif
    endif
  endfor
  return errors
enddef

# ========================================================================
# E1012: env var assigned numeric function result without string() wrap
# ========================================================================
# Environment variables ($VAR) are always strings.  Assigning a numeric
# function result (rand, len, etc.) without string() causes E1012.
def EnvVarNumericAssign(filepath: string): list<string>
  var errors: list<string> = []
  var lines = readfile(filepath)
  var in_def = false
  var lnum = 0
  var numeric_pat = '\$\w\+\s*=\s*\%('
    .. 'rand\|srand\|len\|strlen\|strchars\|line\|col\|virtcol'
    .. '\|bufnr\|winnr\|tabpagenr\|char2nr\|str2nr\|str2float'
    .. '\|float2nr\|getpid\|localtime\|empty\|has\|exists'
    .. '\|count\|index\|match\|matchend\|stridx\|strridx'
    .. '\|abs\|max\|min\|and\|or\|xor\|indent\|shiftwidth'
    .. '\)\s*('
  for line in lines
    lnum += 1
    if line =~ '^\s*def\s'
      in_def = true
    elseif line =~ '^\s*enddef'
      in_def = false
    endif
    if !in_def || line =~ '^\s*#'
      continue
    endif
    if line =~ numeric_pat && line !~ '\$\w\+\s*=\s*string\s*('
      add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum)
    endif
  endfor
  return errors
enddef

# ========================================================================
# E1073: def g: in vim9script files without re-source guard
# ========================================================================
# In vim9script, `def g:Func` raises E1073 if the function already exists,
# and E1073 aborts the entire sourced script.  Every vim9script file with
# `def g:` must have a re-source guard: either a variable-based finish
# guard (exists("g:did_vimr_*") + finish) or a delfunc cleanup loop.
def DefGWithoutGuard(filepath: string): list<string>
  var lines = readfile(filepath)
  # Check if file has any def g: at all
  var has_defg = false
  for line in lines
    if line =~ '^\s*def g:'
      has_defg = true
      break
    endif
  endfor
  if !has_defg
    return []
  endif
  # Check for variable-based finish guard: exists("g:did_vimr_*") + finish
  var has_var_guard = false
  for line in lines
    if line =~ 'exists("g:did_vimr_'
      has_var_guard = true
      break
    endif
  endfor
  # Check for delfunc guard pattern
  var has_delfunc_guard = false
  for line in lines
    if line =~ 'delfunc g:'
      has_delfunc_guard = true
      break
    endif
  endfor
  if has_var_guard || has_delfunc_guard
    return []
  endif
  return [fnamemodify(filepath, ':~:.')]
enddef

# ========================================================================
# Run checks on every vim9script file
# ========================================================================
var comment_errors: list<string> = []
var defg_errors: list<string> = []
var unguarded_errors: list<string> = []
var funcbang_errors: list<string> = []
var barecall_errors: list<string> = []
var baredefg_errors: list<string> = []
var funcref_errors: list<string> = []
var rfexec_errors: list<string> = []
var defcomment_errors: list<string> = []
var envnum_errors: list<string> = []

var legacy_names = CollectLegacyFuncNames(vim_files)
var defg_names = CollectDefGFuncNames(vim_files)

for filepath in vim_files
  if IsVim9(filepath)
    comment_errors += ScriptLevelLegacyComments(filepath)
    defg_errors += DefGWithFinishGuard(filepath)
    unguarded_errors += DefGWithoutGuard(filepath)
    funcbang_errors += FunctionBangInVim9(filepath)
    barecall_errors += BareCallsInDef(filepath, legacy_names)
    baredefg_errors += BareCallsInDef(filepath, defg_names)
    funcref_errors += FuncrefInDef(filepath, legacy_names)
    rfexec_errors += ReadfileExecuteGuard(filepath)
    defcomment_errors += LegacyCommentInDef(filepath)
    envnum_errors += EnvVarNumericAssign(filepath)
  endif
endfor

g:Assert(len(comment_errors) == 0,
  'E114: no legacy " comments at script level'
  .. (len(comment_errors) > 0
      ? ' — found in: ' .. join(comment_errors, ', ')
      : ''))

g:Assert(len(defg_errors) == 0,
  'E127: no def g: in files with re-source guards'
  .. (len(defg_errors) > 0
      ? ' — found in: ' .. join(defg_errors, ', ')
      : ''))

g:Assert(len(funcbang_errors) == 0,
  'E477: no function! in vim9script files'
  .. (len(funcbang_errors) > 0
      ? ' — found in: ' .. join(funcbang_errors, ', ')
      : ''))

g:Assert(len(barecall_errors) == 0,
  'E117: no bare calls to legacy functions inside def blocks (use g: prefix)'
  .. (len(barecall_errors) > 0
      ? ' — found in: ' .. join(barecall_errors, ', ')
      : ''))

g:Assert(len(baredefg_errors) == 0,
  'E117: no bare calls to def g: functions inside def blocks (use g: prefix)'
  .. (len(baredefg_errors) > 0
      ? ' — found in: ' .. join(baredefg_errors, ', ')
      : ''))

g:Assert(len(funcref_errors) == 0,
  'E700: no function(''LegacyName'') inside def blocks (use g: prefix)'
  .. (len(funcref_errors) > 0
      ? ' — found in: ' .. join(funcref_errors, ', ')
      : ''))

g:Assert(len(rfexec_errors) == 0,
  'E114: readfile loop in def must guard before execute (add continue filter)'
  .. (len(rfexec_errors) > 0
      ? ' — found in: ' .. join(rfexec_errors, ', ')
      : ''))

g:Assert(len(defcomment_errors) == 0,
  'E114: no legacy " comments inside def blocks (use # instead)'
  .. (len(defcomment_errors) > 0
      ? ' — found in: ' .. join(defcomment_errors, ', ')
      : ''))

g:Assert(len(envnum_errors) == 0,
  'E1012: no $ENVVAR = numeric_func() without string() wrap'
  .. (len(envnum_errors) > 0
      ? ' — found in: ' .. join(envnum_errors, ', ')
      : ''))

g:Assert(len(unguarded_errors) == 0,
  'E1073: all vim9script files with def g: must have a re-source guard'
  .. (len(unguarded_errors) > 0
      ? ' — found in: ' .. join(unguarded_errors, ', ')
      : ''))
