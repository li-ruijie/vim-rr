vim9script

def g:StartRStudio()
    if string(g:SendCmdToR) != "function('SendCmdToR_fake')"
        return
    endif

    g:SendCmdToR = function('SendCmdToR_NotYet')

    if has("win32")
        g:SetRHome()
    endif
    var rstudio_launch_cmd: list<string>
    if has("win32") && g:RStudio_cmd =~? '\.exe$'
        rstudio_launch_cmd = ['cmd', '/c', g:RStudio_cmd]
    else
        rstudio_launch_cmd = [g:RStudio_cmd]
    endif
    g:rplugin.jobs["RStudio"] = g:StartJob(rstudio_launch_cmd, {
        'err_cb':  'ROnJobStderr',
        'exit_cb': 'ROnJobExit',
        'stoponexit': ''})
    if has("win32")
        g:UnsetRHome()
    endif

    g:WaitVimcomStart()
enddef

def g:SendCmdToRStudio(...args: list<string>): number
    if !g:IsJobRunning("RStudio")
        g:RWarningMsg("Is RStudio running?")
        return 0
    endif
    var cmd = substitute(args[0], '"', '\\"', "g")
    g:SendToVimcom("E", 'sendToConsole("' .. cmd .. '", execute=TRUE)')
    return 1
enddef

g:R_bracketed_paste = 0
g:R_parenblock = 0
