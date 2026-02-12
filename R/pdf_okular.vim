vim9script

if exists("g:did_vimr_pdf_okular")
    finish
endif
g:did_vimr_pdf_okular = 1

def OkularJobStdout(_ch: channel, msg: string)
    var cmd = substitute(msg, '[\n\r]', '', 'g')
    if cmd =~ "^call "
        execute cmd
    endif
enddef

def StartOkularVim(fullpath: string)
    var jobid = job_start(["okular", "--unique",
        "--editor-cmd", "echo 'call SyncTeX_backward(\"%f\",  str2nr(\"%l\"))'", fullpath],
        {stoponexit: "", out_cb: OkularJobStdout})
    if job_info(jobid)["status"] == "run"
        g:rplugin.jobs["Okular"] = jobid
    else
        g:RWarningMsg("Failed to run Okular...")
    endif
enddef

def g:ROpenPDF2(fullpath: string)
    StartOkularVim(fullpath)
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, tryagain: number)
    var texname = substitute(tpath, ' ', '\\ ', 'g')
    var pdfname = substitute(ppath, ' ', '\\ ', 'g')
    var jobid = job_start(["okular", "--unique",
        "--editor-cmd", "echo 'call SyncTeX_backward(\"%f\",  str2nr(\"%l\"))'",
        pdfname .. "#src:" .. texln .. texname],
        {stoponexit: "", out_cb: OkularJobStdout})
    if job_info(jobid)["status"] == "run"
        g:rplugin.jobs["OkularSyncTeX"] = jobid
    else
        g:RWarningMsg("Failed to run Okular (SyncTeX forward)...")
    endif
    g:RRaiseWindow(pdfname)
enddef
