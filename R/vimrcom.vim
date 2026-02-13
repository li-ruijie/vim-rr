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
        var val = g:rplugin.jobs[key]
        if type(val) == v:t_job && val == jid
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
        # Parse \x11<size>\x11<payload> using positional slicing — split()
        # would break if the payload itself contains \x11 (BUG-126).
        var idx2 = stridx(cmd, "\x11", 1)
        if idx2 < 0
            return
        endif
        var size = str2nr(cmd[1 : idx2 - 1])
        var payload = cmd[idx2 + 1 :]
        var received = strlen(payload)
        if received == size
            cmd = payload
        elseif received > size
            # Chunk contains tail of current message + start of next
            cmd = payload[0 : size - 1]
            var remainder = payload[size :]
            # Process current message, then re-enter for the remainder
            g:ROnJobStdout_Execute(job_id, cmd)
            if remainder != ''
                g:ROnJobStdout(job_id, remainder)
            endif
            return
        else
            waiting_more_input = 1
            incomplete_input.size = size
            incomplete_input.received = received
            incomplete_input.str = payload
            timer_start(100, 'g:StopWaitingNCS')
            return
        endif
    endif

    if waiting_more_input
        incomplete_input.received = incomplete_input.received + strlen(cmd)
        if incomplete_input.received == incomplete_input.size
            waiting_more_input = 0
            cmd = incomplete_input.str .. cmd
        elseif incomplete_input.received > incomplete_input.size
            # Extract the exact amount needed, feed remainder back
            var needed = incomplete_input.size - (incomplete_input.received - strlen(cmd))
            waiting_more_input = 0
            cmd = incomplete_input.str .. cmd[0 : needed - 1]
            var remainder = cmd[needed :]
            g:ROnJobStdout_Execute(job_id, cmd)
            if remainder != ''
                g:ROnJobStdout(job_id, remainder)
            endif
            return
        else
            incomplete_input.str = incomplete_input.str .. cmd
            return
        endif
    endif

    g:ROnJobStdout_Execute(job_id, cmd)
enddef

def g:ROnJobStdout_Execute(job_id: any, cmd: string)
    if cmd != ""
        var excmd = substitute(cmd, '^let ', '', '')
        try
            execute excmd
        catch
            g:RWarningMsg("[" .. g:GetJobTitle(job_id) .. "] " .. v:exception .. ": " .. cmd)
        endtry
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
    if key ==# 'RStudio' && exists('*g:OnRStudioQuitComplete')
        g:OnRStudioQuitComplete()
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

g:rplugin.jobs = {Server: "no", R: "no", "Terminal emulator": "no"}
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
