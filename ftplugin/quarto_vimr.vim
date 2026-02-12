vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'quarto') == -1
    finish
endif

g:R_quarto_preview_args = get(g:, 'R_quarto_preview_args', '')
g:R_quarto_render_args = get(g:, 'R_quarto_render_args', '')

if !exists("g:did_vimr_quarto_functions")
    g:did_vimr_quarto_functions = 1

    def g:RQuarto(what: string)
        if what == "render"
            update
            g:SendCmdToR('quarto::quarto_render("' .. substitute(expand('%'), '\\', '/', 'g') .. '"' .. g:R_quarto_render_args .. ')')
        elseif what == "preview"
            update
            g:SendCmdToR('quarto::quarto_preview("' .. substitute(expand('%'), '\\', '/', 'g') .. '"' .. g:R_quarto_preview_args .. ')')
        else
            g:SendCmdToR('quarto::quarto_preview_stop()')
        endif
    enddef
endif

# Necessary for RCreateMaps():
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_global.vim'
g:RCreateMaps('n', 'RQuartoRender',  'qr', ':call g:RQuarto("render")')
g:RCreateMaps('n', 'RQuartoPreview', 'qp', ':call g:RQuarto("preview")')
g:RCreateMaps('n', 'RQuartoStop',    'qs', ':call g:RQuarto("stop")')

execute 'source ' .. substitute(expand('<sfile>:h'), ' ', '\ ', 'g') .. '/rmd_vimr.vim'
