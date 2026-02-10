
function StartRStudio()
    if string(g:SendCmdToR) != "function('SendCmdToR_fake')"
        return
    endif

    let g:SendCmdToR = function('SendCmdToR_NotYet')

    if has("win32")
        call SetRHome()
    endif
    if has("nvim")
        let g:rplugin.jobs["RStudio"] = StartJob([g:RStudio_cmd], {
                    \ 'on_stderr': function('ROnJobStderr'),
                    \ 'on_exit':   function('ROnJobExit'),
                    \ 'detach': 1 })
    else
        if has("win32") && g:RStudio_cmd =~? '\.exe$'
            let rstudio_launch_cmd = ['cmd', '/c', g:RStudio_cmd]
        else
            let rstudio_launch_cmd = [g:RStudio_cmd]
        endif
        let g:rplugin.jobs["RStudio"] = StartJob(rstudio_launch_cmd, {
                    \ 'err_cb':  'ROnJobStderr',
                    \ 'exit_cb': 'ROnJobExit',
                    \ 'stoponexit': '' })
    endif
    if has("win32")
        call UnsetRHome()
    endif

    call WaitVimcomStart()
endfunction

function SendCmdToRStudio(...)
    if !IsJobRunning("RStudio")
        call RWarningMsg("Is RStudio running?")
        return 0
    endif
    let cmd = substitute(a:1, '"', '\\"', "g")
    call SendToVimcom("E", 'sendToConsole("' . cmd . '", execute=TRUE)')
    return 1
endfunction

let g:R_bracketed_paste = 0
let g:R_parenblock = 0
