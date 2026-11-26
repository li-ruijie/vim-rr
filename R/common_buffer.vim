vim9script

# The variables defined here are not in the ftplugin directory because they
# are common for all file types supported by Vim-R.

# Source scripts common to R, Rnoweb, Rhelp and rdoc files:
# This line runs before common_global.vim defines g:RExFile(), so the
# escape of that function is written out here
var common_global = fnameescape(expand('<sfile>:h:h') .. '/R/common_global.vim')
execute 'source ' .. (has('win32') ? substitute(common_global, '\[', '[[]', 'g') : common_global)

b:rplugin_knitr_pattern = ''

g:rplugin.lastft = &filetype

# Check if b:pdf_is_open already exists to avoid errors at other places
if !exists('b:pdf_is_open')
    b:pdf_is_open = 0
endif

if g:R_assign == 3
    iabb <buffer> _ <-
endif

if index(g:R_set_omnifunc, &filetype) > -1
    execute 'source ' .. g:RExFile(g:rplugin.home .. '/R/complete.vim')
    g:RComplAutCmds()
endif

if !exists('b:did_unrll_au')
    b:did_unrll_au = 1
    autocmd BufWritePost <buffer> execute 'if exists("*UpdateNoRLibList") | call UpdateNoRLibList() | endif'
    autocmd BufEnter <buffer> execute 'if exists("*UpdateNoRLibList") | call UpdateNoRLibList() | endif'
endif
