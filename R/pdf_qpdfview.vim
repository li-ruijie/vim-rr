vim9script

def g:ROpenPDF2(fullpath: string)
    system("env VIMR_PORT=" .. g:rplugin.myport
        .. " qpdfview --unique '" .. fullpath .. "' 2>/dev/null >/dev/null &")
    if g:R_synctex && fullpath =~ " "
        g:RWarningMsg("Qpdfview does support file names with spaces: SyncTeX backward will not work.")
    endif
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, tryagain: number)
    var texname = substitute(tpath, ' ', '\\ ', 'g')
    var pdfname = substitute(ppath, ' ', '\\ ', 'g')
    system("VIMR_PORT=" .. g:rplugin.myport .. " qpdfview --unique "
        .. pdfname .. "#src:" .. texname .. ":" .. texln .. ":1 2> /dev/null >/dev/null &")
    g:RRaiseWindow(substitute(substitute(ppath, ".*/", "", ""), ".pdf$", "", ""))
enddef
