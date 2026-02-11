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
  var lnum = 0
  for line in lines
    lnum += 1
    if line =~ '^\s*fu\%[nction]!\?\s'
      in_legacy_func += 1
    elseif line =~ '^\s*endfu\%[nction]'
      in_legacy_func = max([0, in_legacy_func - 1])
    endif
    # Flag " as first non-whitespace when outside legacy function bodies
    if in_legacy_func == 0 && line =~ '^\s*"'
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
  # Detect the re-source guard pattern
  var has_resource_guard = false
  for line in lines
    if line =~ 'exists(''\*' || line =~ "exists(\"\\*"
      has_resource_guard = true
      break
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
    for fname in keys(legacy)
      # Match FuncName( but not g:FuncName(
      if line =~ '\<' .. fname .. '\s*(' && line !~ 'g:' .. fname
        add(errors, fnamemodify(filepath, ':~:.') .. ':' .. lnum .. ' ' .. fname)
      endif
    endfor
  endfor
  return errors
enddef

# ========================================================================
# Run checks on every vim9script file
# ========================================================================
var comment_errors: list<string> = []
var defg_errors: list<string> = []
var funcbang_errors: list<string> = []
var barecall_errors: list<string> = []

var legacy_names = CollectLegacyFuncNames(vim_files)

for filepath in vim_files
  if IsVim9(filepath)
    comment_errors += ScriptLevelLegacyComments(filepath)
    defg_errors += DefGWithFinishGuard(filepath)
    funcbang_errors += FunctionBangInVim9(filepath)
    barecall_errors += BareCallsInDef(filepath, legacy_names)
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
