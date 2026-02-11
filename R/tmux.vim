vim9script

# Check whether Tmux is OK
if !executable('tmux')
    g:R_external_term = 0
    execute 'call RWarningMsg("tmux executable not found")'
    finish
endif

var tmuxversion: string
if system("uname") =~ "OpenBSD"
    # Tmux does not have -V option on OpenBSD
    tmuxversion = "0.0"
else
    tmuxversion = system("tmux -V")
    tmuxversion = substitute(tmuxversion, '.* \([0-9]\.[0-9]\).*', '\1', '')
    if strlen(tmuxversion) != 3
        tmuxversion = "1.0"
    endif
    if tmuxversion < "3.0"
        execute 'call RWarningMsg("Vim-R requires Tmux >= 3.0")'
        g:rplugin.failed = 1
        finish
    endif
endif

g:rplugin.tmuxsname = "VimR-" .. substitute(string(localtime()), '.*\(...\)', '\1', '')

g:R_setwidth = get(g:, 'R_setwidth', 2)

if !exists('g:R_source') || (exists('g:R_source') && g:R_source !~# 'tmux_split.vim')
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/extern_term.vim'
endif
