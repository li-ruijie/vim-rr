vim9script noclear

if exists("g:did_vimr_pdf_okular")
    finish
endif
g:did_vimr_pdf_okular = 1

# Okular prints the --editor-cmd text with the file name and the line number
# filled in. The two values are parsed out of the line, and the line is never
# executed, since a file name may contain quotes, backslashes, or Vim script.
def OkularJobStdout(_ch: channel, msg: string)
    var m = matchlist(substitute(msg, '[\n\r]', '', 'g'),
        '^call SyncTeX_backward("\(.*\)",\s*str2nr("\(\d\+\)"))$')
    if !empty(m)
        g:SyncTeX_backward(m[1], str2nr(m[2]))
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
    # job_start() runs no shell for a list, so the paths are passed unescaped
    var jobid = job_start(["okular", "--unique",
        "--editor-cmd", "echo 'call SyncTeX_backward(\"%f\",  str2nr(\"%l\"))'",
        ppath .. "#src:" .. texln .. tpath],
        {stoponexit: "", out_cb: OkularJobStdout})
    if job_info(jobid)["status"] == "run"
        g:rplugin.jobs["OkularSyncTeX"] = jobid
    else
        g:RWarningMsg("Failed to run Okular (SyncTeX forward)...")
    endif
    g:RRaiseWindow(ppath)
enddef
