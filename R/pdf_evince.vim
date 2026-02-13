vim9script

if exists("g:did_vimr_pdf_evince")
    finish
endif
g:did_vimr_pdf_evince = 1

import autoload './evince_pdf_forward.vim' as fwd
import autoload './evince_pdf_back.vim' as back

if !has_key(g:rplugin, 'evince_list')
    g:rplugin.evince_list = []
endif

def g:ROpenPDF2(fullpath: string)
    system("evince " .. shellescape(fullpath) .. " 2>/dev/null >/dev/null &")
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, unused: number)
    # Most of Evince's code requires spaces replaced by %20, but the
    # actual file name is processed by a SyncTeX library that does not:
    var n1 = substitute(tpath, '\(^/.*/\).*', '\1', '')
    var n2 = substitute(tpath, '.*/\(.*\)', '\1', '')
    var texname = substitute(n1, " ", "%20", "g") .. n2
    var pdfname = substitute(ppath, " ", "%20", "g")

    if !has_key(g:rplugin, 'evince_loop')
        g:rplugin.evince_loop = 0
    endif
    if g:rplugin.evince_loop < 2
        fwd.SyncView(texname, pdfname, texln)
    else
        g:rplugin.evince_loop = 0
    endif
    g:RRaiseWindow(substitute(ppath, ".*/", "", ""))
enddef

def g:Run_EvinceBackward()
    var basenm = g:SyncTeX_GetMaster() .. ".pdf"
    var pdfpath = b:rplugin_pdfdir .. "/" .. substitute(basenm, ".*/", "", "")
    if index(g:rplugin.evince_list, pdfpath) < 0
        add(g:rplugin.evince_list, pdfpath)
        back.Start(pdfpath)
    endif
enddef

# Avoid possible infinite loop if Evince cannot open the document and
# evince_pdf_forward.vim keeps calling Evince_Again().
def g:Evince_Again()
    g:rplugin.evince_loop += 1
    g:SyncTeX_forward()
enddef
