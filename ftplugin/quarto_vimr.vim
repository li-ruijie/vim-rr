vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'quarto') == -1
    finish
endif

g:R_quarto_preview_args = get(g:, 'R_quarto_preview_args', '')
g:R_quarto_render_args = get(g:, 'R_quarto_render_args', '')

if !exists('*g:RQuarto')
    function g:RQuarto(what)
        if a:what == "render"
            update
            call g:SendCmdToR('quarto::quarto_render("' . substitute(expand('%'), '\\', '/', 'g') . '"' . g:R_quarto_render_args . ')')
        elseif a:what == "preview"
            update
            call g:SendCmdToR('quarto::quarto_preview("' . substitute(expand('%'), '\\', '/', 'g') . '"' . g:R_quarto_preview_args . ')')
        else
            call g:SendCmdToR('quarto::quarto_preview_stop()')
        endif
    endfunction
endif

# Necessary for RCreateMaps():
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_global.vim'
if exists('g:has_Rnvim')
    finish
endif

g:RCreateMaps('n', 'RQuartoRender',  'qr', ':call g:RQuarto("render")')
g:RCreateMaps('n', 'RQuartoPreview', 'qp', ':call g:RQuarto("preview")')
g:RCreateMaps('n', 'RQuartoStop',    'qs', ':call g:RQuarto("stop")')

execute 'source ' .. substitute(expand('<sfile>:h'), ' ', '\ ', 'g') .. '/rmd_vimr.vim'
