vim9script

if exists("g:did_vimr_rstudio")
    finish
endif
g:did_vimr_rstudio = 1

def g:StartRStudio()
    if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
        return
    endif

    g:SendCmdToR = function('g:SendCmdToR_NotYet')

    if has("win32")
        g:SetRHome()
    endif
    var rstudio_launch_cmd = has("win32") && g:RStudio_cmd =~? '\.exe$'
        ? ['cmd', '/c', g:RStudio_cmd]
        : [g:RStudio_cmd]
    g:rplugin.jobs["RStudio"] = g:StartJob(rstudio_launch_cmd, {
        'err_cb':  'g:ROnJobStderr',
        'exit_cb': 'g:ROnJobExit',
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
