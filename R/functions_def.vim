vim9script

# Function definitions for R/functions.vim
# This file is sourced exactly once (guarded by finish in functions.vim),
# so def g: will never be recompiled and E127 cannot occur.

def g:SourceRFunList(lib: string)
    if g:R_hi_fun == 0
        return
    endif

    var fnm = g:rplugin.compldir .. '/fun_' .. lib

    if has_key(g:rplugin, 'localfun')
        g:UpdateLocalFunctions(g:rplugin.localfun)
    endif

    # Highlight R functions
    if !exists('g:R_hi_fun_paren') || g:R_hi_fun_paren == 0
        execute 'source ' .. substitute(fnm, ' ', '\\ ', 'g')
    else
        var lines = readfile(fnm)
        for line in lines
            if line !~ '^syn keyword rFunction '
                continue
            endif
            var newline = substitute(line, '\.', '\\.', 'g')
            if substitute(line, 'syn keyword rFunction ', '', '') =~ "[ ']"
                newline = substitute(newline, 'keyword rFunction ', 'match rSpaceFun /`\\zs', '')
                execute newline .. '\ze`\s*(/ contained'
            else
                newline = substitute(newline, 'keyword rFunction ', 'match rFunction /\\<', '')
                execute newline .. '\s*\ze(/'
            endif
        endfor
    endif
enddef

def g:FunHiOtherBf()
    if &diff || g:R_hi_fun == 0
        return
    endif

    # Syntax highlight other buffers
    silent execute 'set syntax=' .. &syntax
    redraw
enddef
