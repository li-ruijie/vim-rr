vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rhelp') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
if exists('g:has_Rnvim')
    finish
endif

if !exists('*g:RhelpIsInRCode')
    function g:RhelpIsInRCode(vrb)
        let lastsec = search('^\\[a-z][a-z]*{', "bncW")
        let secname = getline(lastsec)
        if line(".") > lastsec && (secname =~ '^\\usage{' || secname =~ '^\\examples{' || secname =~ '^\\dontshow{' || secname =~ '^\\dontrun{' || secname =~ '^\\donttest{' || secname =~ '^\\testonly{')
            return 1
        else
            if a:vrb
                call g:RWarningMsg("Not inside an R section.")
            endif
            return 0
        endif
    endfunction
endif

if !exists('*g:RhelpComplete')
    function g:RhelpComplete(findstart, base)
        if a:findstart
            let line = getline('.')
            let start = col('.') - 1
            while start > 0 && (line[start - 1] =~ '\w' || line[start - 1] == '\')
                let start -= 1
            endwhile
            return start
        else
            let resp = []
            let hwords = ['\Alpha', '\Beta', '\Chi', '\Delta', '\Epsilon',
                        \ '\Eta', '\Gamma', '\Iota', '\Kappa', '\Lambda', '\Mu', '\Nu',
                        \ '\Omega', '\Omicron', '\Phi', '\Pi', '\Psi', '\R', '\Rdversion',
                        \ '\Rho', '\S4method', '\Sexpr', '\Sigma', '\Tau', '\Theta', '\Upsilon',
                        \ '\Xi', '\Zeta', '\acronym', '\alias', '\alpha', '\arguments',
                        \ '\author', '\beta', '\bold', '\chi', '\cite', '\code', '\command',
                        \ '\concept', '\cr', '\dQuote', '\delta', '\deqn', '\describe',
                        \ '\description', '\details', '\dfn', '\docType', '\dontrun', '\dontshow',
                        \ '\donttest', '\dots', '\email', '\emph', '\encoding', '\enumerate',
                        \ '\env', '\epsilon', '\eqn', '\eta', '\examples', '\file', '\format',
                        \ '\gamma', '\ge', '\href', '\iota', '\item', '\itemize', '\kappa',
                        \ '\kbd', '\keyword', '\lambda', '\ldots', '\le',
                        \ '\link', '\linkS4class', '\method', '\mu', '\name', '\newcommand',
                        \ '\note', '\nu', '\omega', '\omicron', '\option', '\phi', '\pi',
                        \ '\pkg', '\preformatted', '\psi', '\references', '\renewcommand', '\rho',
                        \ '\sQuote', '\samp', '\section', '\seealso', '\sigma', '\source',
                        \ '\special', '\strong', '\subsection', '\synopsis', '\tab', '\tabular',
                        \ '\tau', '\testonly', '\theta', '\title', '\upsilon', '\url', '\usage',
                        \ '\value', '\var', '\verb', '\xi', '\zeta']
            for word in hwords
                if word =~ '^' . escape(a:base, '\')
                    call add(resp, {'word': word})
                endif
            endfor
            return resp
        endif
    endfunction
endif

b:IsInRCode = function('g:RhelpIsInRCode')
b:rplugin_non_r_omnifunc = "g:RhelpComplete"

#==========================================================================
# Key bindings and menu items

g:RCreateStartMaps()
g:RCreateEditMaps()
g:RCreateSendMaps()
g:RControlMaps()
g:RCreateMaps('nvi', 'RSetwd', 'rd', ':call g:RSetWD()')

# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

g:RSourceOtherScripts()

if exists("b:undo_ftplugin")
    b:undo_ftplugin ..= " | unlet! b:IsInRCode"
else
    b:undo_ftplugin = "unlet! b:IsInRCode"
endif
