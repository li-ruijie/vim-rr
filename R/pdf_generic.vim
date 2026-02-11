vim9script

if exists("g:did_vimr_pdf_generic")
    finish
endif
g:did_vimr_pdf_generic = 1

def g:ROpenPDF2(fullpath: string)
    system(g:R_pdfviewer .. " '" .. fullpath .. "' 2>/dev/null >/dev/null &")
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, tryagain: number)
    g:RWarningMsg("Vim-R has no support for SyncTeX with '" .. g:R_pdfviewer .. "'")
enddef
