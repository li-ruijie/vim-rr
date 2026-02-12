vim9script

if exists("g:did_vimr_pdf_evince")
    finish
endif
g:did_vimr_pdf_evince = 1

var py = executable('python3') ? 'python3' : 'python'

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
        g:rplugin.jobs["Python (Evince forward)"] = g:StartJob([py,
            g:rplugin.home .. "/R/pdf_evince_forward.py",
            texname, pdfname, string(texln)], g:rplugin.job_handlers)
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
        g:rplugin.jobs["Python (Evince backward)"] = g:StartJob([py,
            g:rplugin.home .. "/R/pdf_evince_back.py", pdfpath],
            g:rplugin.job_handlers)
    endif
enddef

# Avoid possible infinite loop if Evince cannot open the document and
# pdf_evince_forward.py keeps sending the message to run
# SyncTeX_forward() again.
def g:Evince_Again()
    g:rplugin.evince_loop += 1
    g:SyncTeX_forward()
enddef
