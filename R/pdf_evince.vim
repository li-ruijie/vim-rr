vim9script noclear

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
    if !has_key(g:rplugin, 'evince_loop')
        g:rplugin.evince_loop = 0
    endif
    if g:rplugin.evince_loop < 2
        # Evince gives the source file to its SyncTeX parser as a plain file
        # name and decodes nothing, so the path is passed as it is
        fwd.SyncView(tpath, ppath, texln)
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
