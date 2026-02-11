vim9script

# Support for rGlobEnvFun
# File types that embed R, such as Rnoweb, require at least one keyword
# defined immediately
syn keyword rGlobEnvFun ThisIsADummyGlobEnvFunKeyword
hi def link rGlobEnvFun Function

# On re-source: refresh highlights for loaded libraries, then stop.
# g:SourceRFunList was defined (in functions_def.vim) on first source.
if exists('*g:SourceRFunList')
    for lib in g:rplugin.libs_in_nrs
        g:SourceRFunList(lib)
    endfor
    finish
endif

# First-time initialisation
if !exists('g:rplugin')
    # Also in common_global.vim because either file might be sourced first.
    g:rplugin = {debug_info: {}, libs_in_nrs: [], nrs_running: 0, myport: 0, R_pid: 0}
endif

if !has_key(g:rplugin, 'compldir')
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/setcompldir.vim'
endif

g:R_hi_fun = get(g:, 'R_hi_fun', 1)

# Source the def g: definitions.  This line is only reached on first
# source — the finish guard above prevents re-sourcing, so the defs in
# that file are never recompiled and E127 cannot occur.
execute 'source ' .. substitute(expand('<sfile>:h'), ' ', '\\ ', 'g') .. '/functions_def.vim'
