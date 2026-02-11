vim9script

# Support for rGlobEnvFun
# File types that embed R, such as Rnoweb, require at least one keyword
# defined immediately
syn keyword rGlobEnvFun ThisIsADummyGlobEnvFunKeyword
hi def link rGlobEnvFun Function

# Only source the remaining of this script once
if exists('*SourceRFunList')
    for lib in g:rplugin.libs_in_nrs
        SourceRFunList(lib)
    endfor
    finish
endif

# Set global variables when this script is called for the first time
if !exists('g:rplugin')
    # Attention: also in common_global.vim because either of them might be sourced first.
    g:rplugin = {debug_info: {}, libs_in_nrs: [], nrs_running: 0, myport: 0, R_pid: 0}
endif

# syntax/r.vim may have been called before ftplugin/r.vim
if !has_key(g:rplugin, 'compldir')
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/setcompldir.vim'
endif

g:R_hi_fun = get(g:, 'R_hi_fun', 1)

# Must be run for each buffer
# Use function! (not def) because this file is re-sourced while these
# functions may be in the call stack.  Vim9 def compiles at parse time,
# before `finish` can guard against redefinition, causing E127.
function! SourceRFunList(lib)
    if g:R_hi_fun == 0
        return
    endif

    let fnm = g:rplugin.compldir .. '/fun_' .. a:lib

    if has_key(g:rplugin, 'localfun')
        call UpdateLocalFunctions(g:rplugin.localfun)
    endif

    " Highlight R functions
    if !exists('g:R_hi_fun_paren') || g:R_hi_fun_paren == 0
        execute 'source ' .. substitute(fnm, ' ', '\\ ', 'g')
    else
        let lines = readfile(fnm)
        for line in lines
            let newline = substitute(line, '\.', '\\.', 'g')
            if substitute(line, 'syn keyword rFunction ', '', '') =~ "[ ']"
                let newline = substitute(newline, 'keyword rFunction ', 'match rSpaceFun /`\\zs', '')
                execute newline .. '\ze`\s*(/ contained'
            else
                let newline = substitute(newline, 'keyword rFunction ', 'match rFunction /\\<', '')
                execute newline .. '\s*\ze(/'
            endif
        endfor
    endif
endfunction

# Function called when vimcom updates the list of loaded libraries
function! FunHiOtherBf()
    if &diff || g:R_hi_fun == 0
        return
    endif

    " Syntax highlight other buffers
    silent execute 'set syntax=' .. &syntax
    redraw
endfunction
