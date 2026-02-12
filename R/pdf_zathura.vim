vim9script

if exists("g:did_vimr_pdf_zathura")
    finish
endif
g:did_vimr_pdf_zathura = 1

if !has_key(g:rplugin, 'zathura_pid')
    g:rplugin.zathura_pid = {}
endif

if !executable("zathura")
    g:rplugin.pdfviewer = "none"
    g:RWarningMsg('Please, either install "zathura" or set the value of R_pdfviewer.')
endif

var has_dbus_send = executable("dbus-send")
var synctex_editor_cmd = "echo 'call SyncTeX_backward(\"%{input}\",  str2nr(\"%{line}\"))'"
var OnJobStderr = function('g:ROnJobStderr')

def ZathuraJobStdout(_ch: channel, msg: string)
    var cmd = substitute(msg, '[\n\r]', '', 'g')
    if cmd =~ "^call "
        execute cmd
    endif
enddef

def StartZathuraVim(fullpath: string)
    var jobid = job_start(
        ["zathura", "--synctex-editor-command", synctex_editor_cmd, fullpath],
        {stoponexit: "", err_cb: OnJobStderr,
            out_cb: ZathuraJobStdout})
    if job_info(jobid)["status"] == "run"
        g:rplugin.jobs["Zathura"] = jobid
        g:rplugin.zathura_pid[fullpath] = job_info(jobid)["process"]
    else
        g:RWarningMsg("Failed to run Zathura...")
    endif
enddef

def RStartZathura(fullpath: string)
    var fname = substitute(fullpath, ".*/", "", "")

    if has_key(g:rplugin.zathura_pid, fullpath) && g:rplugin.zathura_pid[fullpath] != 0
        system('kill ' .. g:rplugin.zathura_pid[fullpath])
    elseif g:rplugin.has_wmctrl && has_dbus_send && filereadable("/proc/sys/kernel/pid_max")
        var info = split(system("wmctrl -xpl"), "\n")
            ->filter((_, v) => v =~ 'Zathura.*' .. fname)
        if len(info) > 0
            var pid = str2nr(split(info[0])[2])
            var max_pid = str2nr(readfile("/proc/sys/kernel/pid_max")[0])
            if pid > 0 && pid <= max_pid
                system('dbus-send --print-reply --session --dest=org.pwmt.zathura.PID-'
                    .. pid .. ' /org/pwmt/zathura org.pwmt.zathura.CloseDocument')
                sleep 5m
                system('kill ' .. pid)
                sleep 5m
            endif
        endif
    endif

    $VIMR_PORT = string(g:rplugin.myport)
    StartZathuraVim(fullpath)
enddef

def g:ROpenPDF2(fullpath: string)
    if g:R_openpdf == 1
        RStartZathura(fullpath)
        return
    endif

    # Time for Zathura to reload the PDF
    sleep 200m

    var fname = substitute(fullpath, ".*/", "", "")
    var pid = get(g:rplugin.zathura_pid, fullpath, 0)

    if pid != 0
        if system("ps -p " .. pid) =~ string(pid)
            if g:RRaiseWindow(fname)
                return
            endif
        else
            g:rplugin.zathura_pid[fullpath] = 0
        endif
        RStartZathura(fullpath)
        return
    endif

    g:rplugin.zathura_pid[fullpath] = 0
    if !g:RRaiseWindow(fname)
        RStartZathura(fullpath)
    endif
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, tryagain: number)
    var texname = shellescape(tpath)
    var pdfname = shellescape(ppath)
    var shortp = substitute(ppath, '.*/', '', 'g')

    if get(g:rplugin.zathura_pid, ppath, 0) == 0
        RStartZathura(ppath)
        sleep 900m
    endif

    var result = system("zathura --synctex-forward=" .. texln .. ":1:" .. texname
        .. " --synctex-pid=" .. g:rplugin.zathura_pid[ppath] .. " " .. pdfname)
    if v:shell_error
        g:rplugin.zathura_pid[ppath] = 0
        if tryagain
            RStartZathura(ppath)
            sleep 900m
            g:SyncTeX_forward2(tpath, ppath, texln, 0)
            return
        else
            g:RWarningMsg(substitute(result, "\n", " ", "g"))
            return
        endif
    endif
    g:RRaiseWindow(shortp)
enddef
