vim9script

# Quarto is supported only when R_filetypes names it
if !exists("g:R_filetypes") || type(g:R_filetypes) != v:t_list || index(g:R_filetypes, 'quarto') == -1
    finish
endif

g:R_quarto_preview_args = get(g:, 'R_quarto_preview_args', '')
g:R_quarto_render_args = get(g:, 'R_quarto_render_args', '')

if !exists("g:did_vimr_quarto_functions")
    g:did_vimr_quarto_functions = 1

    def g:RQuarto(what: string)
        if what == "render"
            update
            g:SendCmdToR('quarto::quarto_render(' .. g:RString(substitute(expand('%'), '\\', '/', 'g')) .. g:R_quarto_render_args .. ')')
        elseif what == "preview"
            update
            g:SendCmdToR('quarto::quarto_preview(' .. g:RString(substitute(expand('%'), '\\', '/', 'g')) .. g:R_quarto_preview_args .. ')')
        else
            g:SendCmdToR('quarto::quarto_preview_stop()')
        endif
    enddef
endif

# Necessary for RCreateMaps():
# This line runs before common_global.vim defines g:RExFile(), so the
# escape of that function is written out here
var common_global = fnameescape(expand('<sfile>:h:h') .. '/R/common_global.vim')
execute 'source ' .. (has('win32') ? substitute(common_global, '\[', '[[]', 'g') : common_global)
g:RCreateMaps('n', 'RQuartoRender',  'qr', ':call g:RQuarto("render")')
g:RCreateMaps('n', 'RQuartoPreview', 'qp', ':call g:RQuarto("preview")')
g:RCreateMaps('n', 'RQuartoStop',    'qs', ':call g:RQuarto("stop")')

execute 'source ' .. g:RExFile(expand('<sfile>:h') .. '/rmd_vimr.vim')
