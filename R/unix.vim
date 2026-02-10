vim9script

if exists('g:R_path')
    var rpath = split(g:R_path, ':')
    map(rpath, (_, v) => expand(v))
    reverse(rpath)
    for dir in rpath
        if isdirectory(dir)
            $PATH = dir .. ':' .. $PATH
        else
            RWarningMsg('"' .. dir .. '" is not a directory. Fix the value of R_path in your vimrc.')
        endif
    endfor
endif

if !executable(g:rplugin.R)
    RWarningMsg('"' .. g:rplugin.R .. '" not found. Fix the value of either R_path or R_app in your vimrc.')
endif

if (type(g:R_external_term) == v:t_number && g:R_external_term == 1)
        || type(g:R_external_term) == v:t_string
        || (exists('g:R_source') && g:R_source =~# 'tmux_split.vim')
    execute 'source ' .. substitute(g:rplugin.home, ' ', '\\ ', 'g') .. '/R/tmux.vim'
endif
