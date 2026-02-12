vim9script

if exists("g:did_vimr_vimrcom")
    finish
endif
g:did_vimr_vimrcom = 1

def g:JobStdin(jb: any, cmd: string)
    ch_sendraw(job_getchannel(jb), cmd)
enddef

def g:StartJob(cmd: any, opt: dict<any>): job
    return job_start(cmd, opt)
enddef

def g:GetJobTitle(job_id: any): string
    var jid = type(job_id) == v:t_channel ? ch_getjob(job_id) : job_id
    for key in keys(g:rplugin.jobs)
        if g:rplugin.jobs[key] == jid
            return key
        endif
    endfor
    return "Job"
enddef

var incomplete_input: dict<any> = {size: 0, received: 0, str: ''}
var waiting_more_input = 0

def g:StopWaitingNCS(_timer: number)
    if waiting_more_input
        waiting_more_input = 0
        g:RWarningMsg('Incomplete string received. Expected ' ..
                    incomplete_input.size .. ' bytes; received ' ..
                    incomplete_input.received .. '.')
    endif
    incomplete_input = {size: 0, received: 0, str: ''}
enddef

def g:ROnJobStdout(job_id: any, msg: string)
    var cmd = substitute(msg, '\n', '', 'g')
    cmd = substitute(cmd, '\r', '', 'g')
    # DEBUG: writefile([cmd], "/dev/shm/vimrserver_vim_stdout", "a")

    if cmd[0 : 0] == "\x11"
        # Check the size of possibly very big string (dictionary for menu completion).
        var cmdsplt = split(cmd, "\x11")
        if len(cmdsplt) < 2
            return
        endif
        var size = str2nr(cmdsplt[0])
        var received = strlen(cmdsplt[1])
        if size == received
            cmd = cmdsplt[1]
        else
            waiting_more_input = 1
            incomplete_input.size = size
            incomplete_input.received = received
            incomplete_input.str = cmdsplt[1]
            timer_start(100, 'g:StopWaitingNCS')
            return
        endif
    endif

    if waiting_more_input
        incomplete_input.received = incomplete_input.received + strlen(cmd)
        if incomplete_input.received == incomplete_input.size
            waiting_more_input = 0
            cmd = incomplete_input.str .. cmd
        else
            incomplete_input.str = incomplete_input.str .. cmd
            if incomplete_input.received > incomplete_input.size
                g:RWarningMsg('Received larger than expected message.')
            endif
            return
        endif
    endif

    if cmd =~ "^let "
        try
            execute substitute(cmd, '^let ', '', '')
        catch
            g:RWarningMsg("[" .. g:GetJobTitle(job_id) .. "] " .. v:exception .. ": " .. cmd)
        endtry
    elseif cmd =~ "^call " || cmd =~ "^unlet "
        try
            execute cmd
        catch
            g:RWarningMsg("[" .. g:GetJobTitle(job_id) .. "] " .. v:exception .. ": " .. cmd)
        endtry
    elseif cmd != ""
        if len(cmd) > 128
            cmd = substitute(cmd, '^\(.\{128}\).*', '\1', '') .. ' [...]'
        endif
        g:RWarningMsg("[" .. g:GetJobTitle(job_id) .. "] Unknown command: " .. cmd)
    endif
enddef

def g:ROnJobStderr(job_id: any, msg: string)
    g:RWarningMsg("[" .. g:GetJobTitle(job_id) .. "] " .. substitute(msg, '\n', '', 'g'))
enddef

def g:ROnJobExit(job_id: any, stts: number)
    var key = g:GetJobTitle(job_id)
    if key != "Job"
        g:rplugin.jobs[key] = "no"
    endif
    if stts != 0
        g:RWarningMsg('"' .. key .. '"' .. ' exited with status ' .. stts)
    endif
    if key ==# 'R'
        g:ClearRInfo()
    endif
    if key ==# 'Server'
        g:rplugin.nrs_running = 0
    endif
enddef

def g:IsJobRunning(key: string): number
    var jstt: string
    try
        jstt = job_status(g:rplugin.jobs[key])
    catch /.*/
        jstt = "fail"
    endtry
    return jstt == "run" ? 1 : 0
enddef

g:rplugin.jobs = {Server: "no", R: "no", "Terminal emulator": "no", BibComplete: "no"}
g:rplugin.job_handlers = {
            out_cb: 'g:ROnJobStdout',
            err_cb: 'g:ROnJobStderr',
            exit_cb: 'g:ROnJobExit'}

# Check if Vim-R-plugin is installed
var ff = globpath(&rtp, "r-plugin/functions.vim")
var ft = globpath(&rtp, "ftplugin/r*_rplugin.vim")
if ff != "" || ft != ""
    ff = substitute(ff, "functions.vim", "", "g")
    g:RWarningMsg("Vim-R conflicts with Vim-R-plugin. Please, uninstall Vim-R-plugin.\n" ..
                ff .. "\n" .. ft .. "\n")
endif
