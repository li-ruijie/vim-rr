vim9script

g:rplugin.has_wmctrl = 0
g:rplugin.has_awbt = 0

var viewer_modules: dict<string> = {
    zathura: "pdf_zathura.vim",
    evince: "pdf_evince.vim",
    okular: "pdf_okular.vim",
    qpdfview: "pdf_qpdfview.vim",
}
if has("win32")
    viewer_modules['sumatra'] = "pdf_sumatra.vim"
endif

def g:RSetPDFViewer()
    g:rplugin.pdfviewer = tolower(g:R_pdfviewer)

    if has_key(viewer_modules, g:rplugin.pdfviewer)
        execute "source " .. fnameescape(
            g:rplugin.home .. "/R/" .. viewer_modules[g:rplugin.pdfviewer])
    else
        execute "source " .. fnameescape(g:rplugin.home .. "/R/pdf_generic.vim")
        if !executable(g:R_pdfviewer)
            g:RWarningMsg("R_pdfviewer (" .. g:R_pdfviewer .. ") not found.")
            return
        endif
        if g:R_synctex
            g:RWarningMsg('Invalid value for R_pdfviewer: "'
                .. g:R_pdfviewer .. '" (SyncTeX will not work)')
        endif
    endif

    if !has("win32") && $WAYLAND_DISPLAY == ""
        if executable("wmctrl")
            g:rplugin.has_wmctrl = 1
        elseif &filetype == "rnoweb" && g:R_synctex
            g:RWarningMsg("The application wmctrl must be installed to edit Rnoweb effectively.")
        endif
    endif
enddef

def g:RRaiseWindow(wttl: string): number
    if g:rplugin.has_wmctrl
        system("wmctrl -a '" .. wttl .. "'")
        return v:shell_error ? 0 : 1
    elseif $WAYLAND_DISPLAY != ""
        if $GNOME_SHELL_SESSION_MODE != "" && g:rplugin.has_awbt
            var sout = system("busctl --user call org.gnome.Shell "
                .. "/de/lucaswerkmeister/ActivateWindowByTitle "
                .. "de.lucaswerkmeister.ActivateWindowByTitle "
                .. "activateBySubstring s '" .. wttl .. "'")
            if v:shell_error
                g:RWarningMsg('Error running Gnome Shell Extension'
                    .. ' "Activate Window By Title": '
                    .. substitute(sout, "\n", " ", "g"))
                return 0
            endif
            return sout =~ 'false' ? 0 : 1
        elseif $XDG_CURRENT_DESKTOP == "sway"
            var sout = system("swaymsg -t get_tree")
            if v:shell_error
                g:RWarningMsg('Error running swaymsg: '
                    .. substitute(sout, "\n", " ", "g"))
                return 0
            endif
            return sout =~ wttl ? 1 : 0
        endif
    endif
    return 0
enddef

if $XDG_CURRENT_DESKTOP == "sway"
    g:R_openpdf = get(g:, "R_openpdf", 2)
elseif $WAYLAND_DISPLAY != ""
    g:R_openpdf = get(g:, "R_openpdf", 1)
else
    g:R_openpdf = get(g:, "R_openpdf", 2)
endif

if has("win32")
    g:R_pdfviewer = "sumatra"
else
    g:R_pdfviewer = get(g:, "R_pdfviewer", "zathura")
endif

if &filetype == 'rnoweb'
    g:RSetPDFViewer()
    g:SetPDFdir()
    if g:R_synctex && $DISPLAY != "" && g:rplugin.pdfviewer == "evince"
        g:rplugin.evince_loop = 0
        g:Run_EvinceBackward()
    endif
endif
