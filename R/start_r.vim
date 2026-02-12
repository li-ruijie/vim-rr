vim9script

# ==============================================================================
# Function to start R and functions that are called only after R is started.
# ==============================================================================

# On re-source (e.g. FuncUndefined fires after partial prior sourcing),
# delete existing global functions so def g: does not E1073-abort the script.
if exists('*g:SanitizeRLine')
    for fn in ['IsSendCmdToRFake', 'SendCmdToR_NotYet', 'RSetMyPort',
            'StartR', 'ReallyStartR', 'SignalToR',
            'CheckIfVimcomIsRunning', 'WaitVimcomStart', 'SetVimcomInfo',
            'SetSendCmdToR', 'RQuit', 'RRestart', 'QuitROnClose',
            'ClearRInfo', 'SendToVimcom', 'UpdateLocalFunctions',
            'ShowRObj', 'EditRObject', 'StartObjBrowser', 'RObjBrowser',
            'RBrOpenCloseLs', 'StopRDebugging', 'FindDebugFunc',
            'RDebugJump', 'RFormatCode', 'FinishRFormatCode',
            'RInsert', 'SendLineToRAndInsertOutput', 'FinishRInsert',
            'GetROutput', 'RViewDF', 'SetRTextWidth', 'RAskHelp',
            'AskRDoc', 'ShowRDoc', 'GetSourceArgs', 'RSourceLines',
            'CleanOxygenLine', 'CleanCurrentLine', 'GoDown',
            'SendMotionToR', 'SendFileToR', 'SendMBlockToR',
            'SanitizeRLine', 'CountBraces', 'SendFunctionToR',
            'SendAboveLinesToR', 'SendSelectionToR',
            'SendParagraphToR', 'SendFHChunkToR', 'KnitChild',
            'RParenDiff', 'SendLineToR', 'RSendPartOfLine',
            'RClearConsole', 'RClearAll', 'RSetWD', 'RKnit',
            'StartTxtBrowser', 'RSourceDirectory', 'PrintRObject',
            'OpenRExample', 'RAction', 'RLoadHTML', 'ROpenDoc',
            'RMakeRmd', 'RBuildTags']
        execute 'silent! delfunc g:' .. fn
    endfor
endif

# Delete provisory links (unlet! tolerates re-sourcing when vars are gone)
unlet! g:RAction
unlet! g:RAskHelp
unlet! g:RBrOpenCloseLs
unlet! g:RBuildTags
unlet! g:RClearAll
unlet! g:RClearConsole
unlet! g:RFormatCode
unlet! g:RInsert
unlet! g:RMakeRmd
unlet! g:RObjBrowser
unlet! g:RQuit
unlet! g:RSendPartOfLine
unlet! g:RSourceDirectory
unlet! g:SendFileToR
unlet! g:SendFunctionToR
unlet! g:SendLineToR
unlet! g:SendLineToRAndInsertOutput
unlet! g:SendMBlockToR
unlet! g:SendParagraphToR
unlet! g:SendSelectionToR
unlet! g:SignalToR

# Save R_DEFAULT_PACKAGES early so it is available even if sourcing is
# interrupted by E1073 partway through the function definitions below.
var r_default_pkgs  = $R_DEFAULT_PACKAGES

# ==============================================================================
# Functions to start and close R
# ==============================================================================

def RGetBufDir(): string
    var rwd = expand("%:p:h")
    if has("win32")
        rwd = substitute(rwd, '\\', '/', 'g')
    endif
    return rwd
enddef

def g:IsSendCmdToRFake(): number
    if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
        var qcmd = "\\rq"
        var nkblist = execute("nmap")
        var nkbls = split(nkblist, "\n")
        for nkb in nkbls
            if stridx(nkb, "RQuit('nosave')") > 0
                var qls = split(nkb, " ")
                qcmd = qls[1]
                break
            endif
        endfor
        g:RWarningMsg("As far as I know, R is already running. If it is not running, did you quit it from within " .. v:progname .. " (command " .. qcmd .. ")?")
        return 1
    endif
    return 0
enddef

def g:SendCmdToR_NotYet(...args: list<any>): number
    g:RWarningMsg("Not ready yet")
    return 0
enddef

# This function is called by vimrserver when its server binds to a specific port.
var waiting_to_start_r = ''
def g:RSetMyPort(p: string)
    g:rplugin.myport = str2nr(p)
    $VIMR_PORT = p
    if waiting_to_start_r != ''
        g:StartR(waiting_to_start_r)
        waiting_to_start_r = ''
    endif
enddef

def g:StartR(whatr: string)
    g:rplugin.debug_info['Time']['start_R'] = reltime()
    g:ReallyStartR(whatr)
enddef

# Start R
def g:ReallyStartR(whatr: string)
    wait_vimcom = 1

    if g:rplugin.myport == 0
        if g:IsJobRunning("Server") == 0
            g:RWarningMsg("Cannot start R: vimrserver not running")
            return
        endif
        if g:rplugin.nrs_running == 0
            g:RWarningMsg("vimrserver not ready yet")
            return
        endif
        waiting_to_start_r = whatr
        g:JobStdin(g:rplugin.jobs["Server"], "1\n") # Start the TCP server
        return
    endif

    if (type(g:R_external_term) == v:t_number && g:R_external_term == 1) || type(g:R_external_term) == v:t_string
        g:R_objbr_place = substitute(g:R_objbr_place, 'console', 'script', '')
    endif

    # https://github.com/jalvesaq/Vim-R/issues/157
    if !exists("*FunHiOtherBf")
        exe "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/functions.vim"
    endif

    if whatr =~ "custom"
        inputsave()
        var r_args = input('Enter parameters for R: ')
        inputrestore()
        g:rplugin.r_args = split(r_args)
    else
        if exists("g:R_args")
            g:rplugin.r_args = g:R_args
        else
            g:rplugin.r_args = []
        endif
    endif

    writefile([], g:rplugin.localtmpdir .. "/globenv_" .. $VIMR_ID)
    writefile([], g:rplugin.localtmpdir .. "/liblist_" .. $VIMR_ID)

    g:AddForDeletion(g:rplugin.localtmpdir .. "/globenv_" .. $VIMR_ID)
    g:AddForDeletion(g:rplugin.localtmpdir .. "/liblist_" .. $VIMR_ID)

    if &encoding == "utf-8"
        g:AddForDeletion(g:rplugin.tmpdir .. "/start_options_utf8.R")
    else
        g:AddForDeletion(g:rplugin.tmpdir .. "/start_options.R")
    endif

    # Reset R_DEFAULT_PACKAGES to its original value (see https://github.com/jalvesaq/Vim-R/issues/554):
    var start_options = ['Sys.setenv("R_DEFAULT_PACKAGES" = "' .. r_default_pkgs .. '")']

    start_options += ['options(vimcom.max_depth = ' .. g:R_compl_data.max_depth .. ')']
    start_options += ['options(vimcom.max_size = '  .. g:R_compl_data.max_size .. ')']
    start_options += ['options(vimcom.max_time = '  .. g:R_compl_data.max_time .. ')']

    if g:R_objbr_allnames
        start_options += ['options(vimcom.allnames = TRUE)']
    else
        start_options += ['options(vimcom.allnames = FALSE)']
    endif
    if g:R_texerr
        start_options += ['options(vimcom.texerrs = TRUE)']
    else
        start_options += ['options(vimcom.texerrs = FALSE)']
    endif
    if g:rplugin.update_glbenv
        start_options += ['options(vimcom.autoglbenv = TRUE)']
    else
        start_options += ['options(vimcom.autoglbenv = FALSE)']
    endif
    if g:R_debug
        start_options += ['options(vimcom.debug_r = TRUE)']
    else
        start_options += ['options(vimcom.debug_r = FALSE)']
    endif
    if exists('g:R_setwidth') && g:R_setwidth == 2
        start_options += ['options(vimcom.setwidth = TRUE)']
    else
        start_options += ['options(vimcom.setwidth = FALSE)']
    endif
    if g:R_vimpager == "no"
        start_options += ['options(vimcom.vimpager = FALSE)']
    else
        start_options += ['options(vimcom.vimpager = TRUE)']
    endif
    if type(g:R_external_term) == v:t_number && g:R_external_term == 0 && g:R_esc_term
        start_options += ['options(editor = vimcom:::vim.edit)']
    endif
    if exists("g:R_csv_delim") && (g:R_csv_delim == "," || g:R_csv_delim == ";")
        start_options += ['options(vimcom.delim = "' .. g:R_csv_delim .. '")']
    else
        start_options += ['options(vimcom.delim = "\t")']
    endif
    start_options += ['options(vimcom.source.path = "' .. Rsource_read .. '")']

    var rwd = ""
    if g:R_vim_wd == 0
        rwd = RGetBufDir()
    elseif g:R_vim_wd == 1
        rwd = getcwd()
    endif
    if rwd != "" && !exists("g:R_remote_compldir")
        if has("win32")
            rwd = substitute(rwd, '\\', '/', 'g')
        endif

        # `rwd` will not be a real directory if editing a file on the internet
        # with netrw plugin
        if isdirectory(rwd)
            start_options += ['setwd("' .. rwd .. '")']
        endif
    endif

    if len(g:R_after_start) > 0
        var extracmds = deepcopy(g:R_after_start)
        filter(extracmds, (_, v) => v =~ "^R:")
        if len(extracmds) > 0
            map(extracmds, (_, v) => substitute(v, "^R:", "", ""))
            start_options += extracmds
        endif
    endif

    if &encoding == "utf-8"
        writefile(start_options, g:rplugin.tmpdir .. "/start_options_utf8.R")
    else
        writefile(start_options, g:rplugin.tmpdir .. "/start_options.R")
    endif

    # Required to make R load vimcom without the need of the user including
    # library(vimcom) in his or her ~/.Rprofile.
    if $R_DEFAULT_PACKAGES == ""
        $R_DEFAULT_PACKAGES = "datasets,utils,grDevices,graphics,stats,methods,vimcom"
    elseif $R_DEFAULT_PACKAGES !~ "vimcom"
        $R_DEFAULT_PACKAGES ..= ",vimcom"
    endif

    if exists("g:RStudio_cmd")
        $R_DEFAULT_PACKAGES ..= ",rstudioapi"
        g:StartRStudio()
        return
    endif

    if type(g:R_external_term) == v:t_number && g:R_external_term == 0
        g:StartR_InBuffer()
        return
    endif

    if has("win32")
        g:StartR_Windows()
        return
    endif

    if g:IsSendCmdToRFake()
        return
    endif

    var args_str = join(g:rplugin.r_args)
    var rcmd: string
    if args_str == ""
        rcmd = g:rplugin.R
    else
        rcmd = g:rplugin.R .. " " .. args_str
    endif

    g:StartR_ExternalTerm(rcmd)
enddef

# Send signal to R
def g:SignalToR(signal: string)
    if g:rplugin.R_pid
        if has('win32')
            # Windows: only termination is supported via taskkill
            if signal ==? 'SIGTERM' || signal ==? 'SIGKILL' || signal ==? 'TERM' || signal ==? 'KILL'
                system('taskkill /PID ' .. g:rplugin.R_pid .. ' /F')
            endif
        else
            system('kill -s ' .. signal .. ' ' .. g:rplugin.R_pid)
        endif
    endif
enddef


def g:CheckIfVimcomIsRunning(...args: list<any>)
    nseconds = nseconds - 1
    if g:rplugin.R_pid == 0
        if nseconds > 0
            timer_start(1000, "g:CheckIfVimcomIsRunning")
        else
            var msg = "The package vimcom wasn't loaded yet. Please, quit R and try again."
            g:RWarningMsg(msg)
            sleep 500m
        endif
    endif
enddef

def g:WaitVimcomStart()
    var args_str = join(g:rplugin.r_args)
    if args_str =~ "vanilla"
        return
    endif
    if g:R_wait < 2
        g:R_wait = 2
    endif

    nseconds = g:R_wait
    timer_start(1000, "g:CheckIfVimcomIsRunning")
enddef

def g:SetVimcomInfo(vimcomversion: string, rpid: number, wid: string, r_info: string)
    g:rplugin.debug_info['Time']['start_R'] = reltimefloat(reltime(g:rplugin.debug_info['Time']['start_R'], reltime()))
    if filereadable(g:rplugin.home .. '/R/vimcom/DESCRIPTION')
        var ndesc = readfile(g:rplugin.home .. '/R/vimcom/DESCRIPTION')
        var current = substitute(matchstr(ndesc, '^Version: '), 'Version: ', '', '')
        if vimcomversion != current
            g:RWarningMsg('Mismatch in vimcom versions: R (' .. vimcomversion .. ') and Vim (' .. current .. ')')
            sleep 1
        endif
    endif

    $R_DEFAULT_PACKAGES = r_default_pkgs

    g:rplugin.R_pid = rpid
    $RCONSOLE = wid

    var Rinfo = split(r_info, "\x12")
    R_version = Rinfo[0]
    if !exists("g:R_OutDec")
        g:R_OutDec = Rinfo[1]
    endif
    if !exists('g:Rout_prompt_str')
        g:Rout_prompt_str = substitute(Rinfo[2], ' $', '', '')
        g:Rout_prompt_str = substitute(g:Rout_prompt_str, '.*#N#', '', '')
    endif
    if !exists('g:Rout_continue_str')
        g:Rout_continue_str = substitute(Rinfo[3], ' $', '', '')
        g:Rout_continue_str = substitute(g:Rout_continue_str, '.*#N#', '', '')
    endif

    if g:IsJobRunning("Server")
        # Set RConsole window ID in vimrserver to ArrangeWindows()
        if has("win32")
            if $RCONSOLE == "0"
                g:RWarningMsg("vimcom did not save R window ID")
            endif
        endif
    else
        g:RWarningMsg("vimcom is not running")
    endif

    if exists("g:RStudio_cmd")
        if has("win32") && g:R_arrange_windows && filereadable(g:rplugin.compldir .. "/win_pos") && g:IsJobRunning("Server")
            # ArrangeWindows
            g:JobStdin(g:rplugin.jobs["Server"], "85" .. g:rplugin.compldir .. "\n")
        endif
    elseif has("win32")
        if g:R_arrange_windows && filereadable(g:rplugin.compldir .. "/win_pos") && g:IsJobRunning("Server")
            # ArrangeWindows
            g:JobStdin(g:rplugin.jobs["Server"], "85" .. g:rplugin.compldir .. "\n")
        endif
    else
        delete(g:rplugin.tmpdir .. "/initterm_" .. $VIMR_ID .. ".sh")
        delete(g:rplugin.tmpdir .. "/openR")
    endif

    if type(g:R_after_start) == v:t_list
        for cmd in g:R_after_start
            if cmd =~ '^!'
                system(substitute(cmd, '^!', '', ''))
            elseif cmd =~ '^:'
                exe substitute(cmd, '^:', '', '')
            elseif cmd !~ '^R:'
                g:RWarningMsg("R_after_start must be a list of strings starting with 'R:', '!', or ':'")
            endif
        endfor
    endif
    timer_start(1000, "g:SetSendCmdToR")
    if g:R_objbr_auto_start
        autosttobjbr = 1
        timer_start(1010, "g:RObjBrowser")
    endif
enddef

def g:SetSendCmdToR(...args: list<any>)
    if exists("g:RStudio_cmd")
        g:SendCmdToR = function('g:SendCmdToRStudio')
    elseif type(g:R_external_term) == v:t_number && g:R_external_term == 0
        g:SendCmdToR = function('g:SendCmdToR_Buffer')
    elseif has("win32")
        g:SendCmdToR = function('g:SendCmdToR_Windows')
    endif
    wait_vimcom = 0
enddef

# Quit R
def g:RQuit(how: string)
    var qcmd: string
    if exists("b:quit_command")
        qcmd = b:quit_command
    else
        if how == "save"
            qcmd = 'quit(save = "yes")'
        else
            qcmd = 'quit(save = "no")'
        endif
    endif

    if has("win32") && g:IsJobRunning("Server")
	if type(g:R_external_term) == v:t_number && g:R_external_term == 1
	    # SaveWinPos
	    g:JobStdin(g:rplugin.jobs["Server"], "84" .. $VIMR_COMPLDIR .. "\n")
	endif
	g:JobStdin(g:rplugin.jobs["Server"], "2QuitNow\n")
    endif

    if bufloaded('Object_Browser')
        exe 'bunload! Object_Browser'
        sleep 30m
    endif

    g:SendCmdToR(qcmd)

    if has_key(g:rplugin, "tmux_split") || how == 'save'
        sleep 200m
    endif

    sleep 50m
    g:ClearRInfo()
enddef

def g:RRestart()
    if string(g:SendCmdToR) == "function('g:SendCmdToR_fake')"
        g:StartR("R")
        return
    endif
    g:RQuit('nosave')
    timer_start(200, (_) => g:StartR("R"))
enddef

# Send quit(save="no") through the pipeline.
# Called from RVimLeave() when g:R_quit_on_close is set.
# At this point the pipeline is still alive (before Server teardown).
def g:QuitROnClose()
    if string(g:SendCmdToR) == "function('g:SendCmdToR_fake')"
        return
    endif
    g:SendCmdToR('quit(save = "no")')
    sleep 200m
enddef

def g:ClearRInfo()
    delete(g:rplugin.tmpdir .. "/globenv_" .. $VIMR_ID)
    delete(g:rplugin.localtmpdir .. "/liblist_" .. $VIMR_ID)
    for fn in g:rplugin.del_list
        delete(fn)
    endfor
    g:SendCmdToR = function('g:SendCmdToR_fake')
    g:rplugin.R_pid = 0
    if has_key(g:rplugin, 'R_bufnr')
        remove(g:rplugin, 'R_bufnr')
    endif

    # Legacy support for running R in a Tmux split pane
    if has_key(g:rplugin, "tmux_split") && exists('g:R_tmux_title') && g:rplugin.tmux_split
                && g:R_tmux_title != 'automatic' && g:R_tmux_title != ''
        system("tmux set automatic-rename on")
    endif

    if g:IsJobRunning("Server")
        g:JobStdin(g:rplugin.jobs["Server"], "43\n")
    endif
enddef

var wait_vimcom = 0


# ==============================================================================
# Internal communication with R
# ==============================================================================

# Send a message to vimrserver job which will send the message to vimcom
# through a TCP connection.
def g:SendToVimcom(code: string, attch: string)
    if string(g:SendCmdToR) == "function('g:SendCmdToR_fake')"
        g:RWarningMsg("R is not running")
        return
    endif
    if wait_vimcom && string(g:SendCmdToR) == "function('g:SendCmdToR_NotYet')"
        g:RWarningMsg("R is not ready yet")
        return
    endif

    if !g:IsJobRunning("Server")
        g:RWarningMsg("Server not running.")
        return
    endif
    g:JobStdin(g:rplugin.jobs["Server"], "2" .. code .. $VIMR_ID .. attch .. "\n")
enddef


# ==============================================================================
# Keep syntax highlighting, data for omni completion and object browser up to
# date
# ==============================================================================

# Called by vimrserver. When g:rplugin has the key 'localfun', the function
# is also called by SourceRFunList() (R/functions.vim)
def g:UpdateLocalFunctions(funnames: string)
    g:rplugin.localfun = funnames
    syntax clear rGlobEnvFun
    var flist = split(funnames, " ")
    for fnm in flist
        if fnm =~ '[\\\[\$@-]'
            continue
        endif
        if !exists('g:R_hi_fun_paren') || g:R_hi_fun_paren == 0
            exe 'syntax keyword rGlobEnvFun ' .. fnm
        else
            exe 'syntax match rGlobEnvFun /\<' .. fnm .. '\s*\ze(/'
        endif
    endfor
enddef



# ==============================================================================
#  Functions triggered by vimcom after user action on R Console
# ==============================================================================

def g:ShowRObj(howto: string, bname: string, ftype: string, txt: string)
    var bfnm = substitute(bname, '[ [:punct:]]', '_', 'g')
    g:AddForDeletion(g:rplugin.tmpdir .. "/" .. bfnm)
    silent exe howto .. ' ' .. substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') .. '/' .. bfnm
    silent exe 'set ft=' .. ftype
    setline(1, split(substitute(txt, "\x13", "'", "g"), "\x14"))
    set nomodified
enddef

# This function is called by vimcom
def g:EditRObject(fname: string)
    var fcont = readfile(fname)
    exe "tabnew " .. substitute($VIMR_TMPDIR .. "/edit_" .. $VIMR_ID, ' ', '\\ ', 'g')
    setline(".", fcont)
    set filetype=r
    stopinsert
    autocmd BufUnload <buffer> delete($VIMR_TMPDIR .. "/edit_" .. $VIMR_ID .. "_wait") | startinsert
enddef


# ==============================================================================
#  Object Browser (see also ../ftplugin/rbrowser.vim)
# ==============================================================================

def g:StartObjBrowser()
    # Either open or close the Object Browser
    var savesb = &switchbuf
    set switchbuf=useopen,usetab
    if bufloaded('Object_Browser')
        var curwin = win_getid()
        var curtab = tabpagenr()
        exe 'sb Object_Browser'
        var objbrtab = tabpagenr()
        quit
        win_gotoid(curwin)
        if curtab != objbrtab
            g:StartObjBrowser()
        endif
    else
        var edbuf = bufnr()

        if g:R_objbr_place =~# 'RIGHT'
            sil exe 'botright vsplit Object_Browser'
        elseif g:R_objbr_place =~# 'LEFT'
            sil exe 'topleft vsplit Object_Browser'
        elseif g:R_objbr_place =~# 'TOP'
            sil exe 'topleft split Object_Browser'
        elseif g:R_objbr_place =~# 'BOTTOM'
            sil exe 'botright split Object_Browser'
        else
            if g:R_objbr_place =~? 'console' && has_key(g:rplugin, 'R_bufnr')
                sil exe 'sb ' .. g:rplugin.R_bufnr
            elseif g:rplugin.rscript_name != ''
                sil exe 'sb ' .. g:rplugin.rscript_name
            endif
            if g:R_objbr_place =~# 'right'
                sil exe 'rightbelow vsplit Object_Browser'
            elseif g:R_objbr_place =~# 'left'
                sil exe 'leftabove vsplit Object_Browser'
            elseif g:R_objbr_place =~# 'above'
                sil exe 'aboveleft split Object_Browser'
            elseif g:R_objbr_place =~# 'below'
                sil exe 'belowright split Object_Browser'
            else
                g:RWarningMsg('Invalid value for R_objbr_place: "' .. g:R_objbr_place .. '"')
                exe "set switchbuf=" .. savesb
                return
            endif
        endif
        if g:R_objbr_place =~? 'left' || g:R_objbr_place =~? 'right'
            sil exe 'vertical resize ' .. g:R_objbr_w
        else
            sil exe 'resize ' .. g:R_objbr_h
        endif
        sil set filetype=rbrowser
        g:rplugin.curview = "GlobalEnv"
        g:rplugin.ob_winnr = win_getid()

        if autosttobjbr == 1
            autosttobjbr = 0
            exe edbuf .. 'sb'
        endif
    endif
    exe "set switchbuf=" .. savesb
enddef

# Open an Object Browser window
def g:RObjBrowser(...args: list<any>)
    # Only opens the Object Browser if R is running
    if string(g:SendCmdToR) == "function('g:SendCmdToR_fake')"
        g:RWarningMsg("The Object Browser can be opened only if R is running.")
        return
    endif

    if running_objbr == 1
        # Called twice due to BufEnter event
        return
    endif

    running_objbr = 1

    # call RealUpdateRGlbEnv(1)
    if g:IsJobRunning("Server")
        g:JobStdin(g:rplugin.jobs["Server"], "31\n")
    endif
    g:SendToVimcom("A", "RObjBrowser")

    g:StartObjBrowser()
    running_objbr = 0

    if len(g:R_after_ob_open) > 0
        redraw
        for cmd in g:R_after_ob_open
            exe substitute(cmd, '^:', '', '')
        endfor
    endif

    return
enddef

def g:RBrOpenCloseLs(stt: string)
    if g:IsJobRunning("Server")
        g:JobStdin(g:rplugin.jobs["Server"], "34" .. stt .. g:rplugin.curview .. "\n")
    endif
enddef


# ==============================================================================
# Support for debugging R code
# ==============================================================================

# No support for break points
#if synIDattr(synIDtrans(hlID("SignColumn")), "bg") =~ '^#'
#    exe 'hi def StopSign guifg=red guibg=' .. synIDattr(synIDtrans(hlID("SignColumn")), "bg")
#else
#    exe 'hi def StopSign ctermfg=red ctermbg=' .. synIDattr(synIDtrans(hlID("SignColumn")), "bg")
#endif
#call sign_define('stpline', {'text': '●', 'texthl': 'StopSign', 'linehl': 'None', 'numhl': 'None'})

# Functions sign_define(), sign_place() and sign_unplace()
#call sign_define('dbgline', {'text': '▬▶', 'texthl': 'SignColumn', 'linehl': 'QuickFixLine', 'numhl': 'Normal'})

if &ambiwidth == "double" || has("win32")
    sign define dbgline text==> texthl=SignColumn linehl=QuickFixLine
else
    sign define dbgline text=▬▶ texthl=SignColumn linehl=QuickFixLine
endif

var func_offset = -2
var rdebugging = 0
def g:StopRDebugging()
    #call sign_unplace('rdebugcurline')
    #sign unplace rdebugcurline
    sign unplace 1
    func_offset = -2 # Did not seek yet
    rdebugging = 0
enddef

def g:FindDebugFunc(srcref: string)
    var sbopt = &switchbuf
    var curtab = tabpagenr()
    var isnormal = mode() ==# 'n'
    var curwin = winnr()
    var rlines: list<string> = []
    if type(g:R_external_term) == v:t_number && g:R_external_term == 0
        func_offset = -1 # Not found
        sbopt = &switchbuf
        set switchbuf=useopen,usetab
        curtab = tabpagenr()
        isnormal = mode() ==# 'n'
        curwin = winnr()
        if has_key(g:rplugin, 'R_bufnr')
            exe 'sb ' .. g:rplugin.R_bufnr
        endif
        sleep 30m # Time to fill the buffer lines
        rlines = getline(1, "$")
        if g:rplugin.rscript_name != ''
            exe 'sb ' .. g:rplugin.rscript_name
        endif
    elseif string(g:SendCmdToR) == "function('g:SendCmdToR_Term')"
        var tout = system('tmux -L VimR capture-pane -p -t ' .. g:rplugin.tmuxsname)
        rlines = split(tout, "\n")
    elseif string(g:SendCmdToR) == "function('g:SendCmdToR_TmuxSplit')"
        var tout = system('tmux capture-pane -p -t ' .. g:rplugin.rconsole_pane)
        rlines = split(tout, "\n")
    else
        rlines = []
    endif

    var idx = len(rlines) - 1
    while idx > 0
        if rlines[idx] =~# '^debugging in: '
            var funcnm = substitute(rlines[idx], '^debugging in: \(.\{-}\)(.*', '\1', '')
            func_offset = search('.*\<' .. funcnm .. '\s*<-\s*function\s*(', 'b')
            if func_offset < 1
                func_offset = search('.*\<' .. funcnm .. '\s*=\s*function\s*(', 'b')
            endif
            if func_offset < 1
                func_offset = search('.*\<' .. funcnm .. '\s*<<-\s*function\s*(', 'b')
            endif
            if func_offset > 0
                func_offset -= 1
            endif
            if srcref == '<text>'
                if &filetype == 'rmd' || &filetype == 'quarto'
                    func_offset = search('^\s*```\s*{\s*r', 'nb')
                elseif &filetype == 'rnoweb'
                    func_offset = search('^<<', 'nb')
                endif
            endif
            break
        endif
        idx -= 1
    endwhile

    if type(g:R_external_term) == v:t_number && g:R_external_term == 0
        if tabpagenr() != curtab
            exe 'normal! ' .. curtab .. 'gt'
        endif
        exe curwin .. 'wincmd w'
        if isnormal
            stopinsert
        endif
        exe 'set switchbuf=' .. sbopt
    endif
enddef

def g:RDebugJump(fnm: string, lnum: number)
    var saved_so = &scrolloff
    if g:R_debug_center == 1
        set so=999
    endif
    if fnm == '' || fnm == '<text>'
        # Functions sent directly to R Console have no associated source file
        # and functions sourced by knitr have '<text>' as source reference.
        if func_offset == -2
            g:FindDebugFunc(fnm)
        endif
        if func_offset < 0
            exe 'set so=' .. saved_so
            return
        endif
    endif

    var flnum: number
    var fname: string
    if func_offset >= 0
        flnum = lnum + func_offset
        fname = g:rplugin.rscript_name
    else
        flnum = lnum
        fname = expand(fnm)
    endif

    var bname = bufname("%")

    if !bufloaded(fname) && fname != g:rplugin.rscript_name && fname != expand("%") && fname != expand("%:p")
        if filereadable(fname)
            exe 'sb ' .. g:rplugin.rscript_name
            if &modified
                split
            endif
            exe 'edit ' .. fname
        elseif glob("*") =~ fname
            exe 'sb ' .. g:rplugin.rscript_name
            if &modified
                split
            endif
            exe 'edit ' .. fname
        else
            exe 'set so=' .. saved_so
            return
        endif
    endif

    if bufloaded(fname)
        if fname != expand("%")
            exe 'sb ' .. fname
        endif
        exe ':' .. flnum
    endif

    # Call sign_place() and sign_unplace() (requires Vim 8.2+)
    #call sign_unplace('rdebugcurline')
    #call sign_place(1, 'rdebugcurline', 'dbgline', fname, {'lnum': flnum})
    sign unplace 1
    exe 'sign place 1 line=' .. flnum .. ' name=dbgline file=' .. fname
    if g:R_dbg_jump && !rdebugging && type(g:R_external_term) == v:t_number && g:R_external_term == 0 && has_key(g:rplugin, 'R_bufnr')
        exe 'sb ' .. g:rplugin.R_bufnr
        startinsert
    elseif bname != expand("%")
        exe 'sb ' .. bname
    endif
    rdebugging = 1
    exe 'set so=' .. saved_so
enddef


# ==============================================================================
# Functions that ask R to help editing the code
# ==============================================================================

def g:RFormatCode(line1: number, line2: number)
    if g:rplugin.R_pid == 0
        return
    endif

    var wco = &textwidth
    if wco == 0
        wco = 78
    elseif wco < 20
        wco = 20
    elseif wco > 180
        wco = 180
    endif

    var lns = getline(line1, line2)
    var txt = substitute(substitute(join(lns, "\x14"), '\\', '\\\\', 'g'), "'", "\x13", "g")
    g:SendToVimcom("E", "vimcom:::vim_format(" .. line1 .. ", " .. line2 .. ", " .. wco .. ", " .. &shiftwidth .. ", '" .. txt .. "')")
enddef

def g:FinishRFormatCode(lnum1: number, lnum2: number, txt: string)
    var lns =  split(substitute(txt, "\x13", "'", "g"), "\x14")
    silent exe lnum1 .. "," .. lnum2 .. "delete"
    append(lnum1 - 1, lns)
    echo (lnum2 - lnum1 + 1) .. " lines formatted."
enddef

def g:RInsert(cmd: string, type: string)
    if g:rplugin.R_pid == 0
        return
    endif
    g:SendToVimcom("E", 'vimcom:::vim_insert(' .. cmd .. ', "' .. type .. '")')
enddef

def g:SendLineToRAndInsertOutput()
    var lin = getline(".")
    var cleanl = substitute(lin, '".\{-}"', '', 'g')
    if cleanl =~ ';'
        g:RWarningMsg('`print(line)` works only if `line` is a single command')
    endif
    cleanl = substitute(lin, '\s*#.*', "", "")
    g:RInsert("print(" .. cleanl .. ")", "comment")
enddef

def g:FinishRInsert(type: string, txt: string)
    var ilines = split(substitute(txt, "\x13", "'", "g"), "\x14")
    if type == "comment"
        map(ilines, (_, v) => "# " .. v)
    endif
    append(line('.'), ilines)
enddef

def g:GetROutput(fnm: string, txt: string)
    if fnm == "NewtabInsert"
        var tnum = 1
        while bufexists("so" .. tnum)
            tnum += 1
        endwhile
        exe 'tabnew so' .. tnum
        setline(1, split(substitute(txt, "\x13", "'", "g"), "\x14"))
        set filetype=rout
        setlocal buftype=nofile
        setlocal noswapfile
    else
        exe 'tabnew ' .. fnm
        setline(1, split(substitute(txt, "\x13", "'", "g"), "\x14"))
    endif
    normal! gT
    redraw
enddef


def g:RViewDF(oname: string, howto: string, txt: string)
    if exists('g:R_csv_app')
        var tsvnm = g:rplugin.tmpdir .. '/' .. oname .. '.tsv'
        writefile(split(substitute(txt, "\x13", "'", "g"), "\x14"), tsvnm)
        g:AddForDeletion(tsvnm)

        var cmd: string
        if g:R_csv_app =~ '%s'
            cmd = printf(g:R_csv_app, tsvnm)
        else
            cmd = g:R_csv_app .. ' ' .. tsvnm
        endif

        if g:R_csv_app =~# '^:'
            exe cmd
            return
        elseif g:R_csv_app =~# '^terminal:'
            cmd = substitute(cmd, '^terminal:', '', '')
            tabnew
            exe 'terminal ' .. cmd
            startinsert
            return
        endif

        normal! :<Esc>
        if has("win32")
            silent exe '!start "' .. g:R_csv_app .. '" "' .. tsvnm .. '"'
        else
            system(cmd .. ' >' .. devnull .. ' 2>' .. devnull .. ' &')
        endif
        return
    endif

    var location = howto
    silent exe location .. ' ' .. oname
    # silent 1,$d
    setline(1, split(substitute(txt, "\x13", "'", "g"), "\x14"))
    setlocal filetype=csv
    setlocal nomodified
    setlocal bufhidden=wipe
    setlocal noswapfile
    set buftype=nofile
    redraw
enddef


# ==============================================================================
# Show R documentation
# ==============================================================================

def g:SetRTextWidth(rkeyword: string)
    if g:R_vimpager == "tabnew"
        rdoctitle = rkeyword
    else
        var tnr = tabpagenr()
        if g:R_vimpager != "tab" && tnr > 1
            rdoctitle = "R_doc" .. tnr
        else
            rdoctitle = "R_doc"
        endif
    endif
    if !bufloaded(rdoctitle) || get(g:, 'R_newsize', 0) == 1
        g:R_newsize = 0

        # vimpager_local is used to calculate the width of the R help documentation
        # and to decide whether to obey R_vimpager = 'vertical'
        vimpager_local = g:R_vimpager

        var wwidth = winwidth(0)

        # Not enough room to split vertically
        if g:R_vimpager == "vertical" && wwidth <= (g:R_help_w + g:R_editor_w)
            vimpager_local = "horizontal"
        endif

        var htwf: float
        if vimpager_local == "horizontal"
            # Use the window width (at most 80 columns)
            htwf = (wwidth > 80) ? 88.1 : ((wwidth - 1) / 0.9)
        elseif g:R_vimpager == "tab" || g:R_vimpager == "tabnew"
            wwidth = &columns
            htwf = (wwidth > 80) ? 88.1 : ((wwidth - 1) / 0.9)
        else
            var min_e = (g:R_editor_w > 80) ? g:R_editor_w : 80
            var min_h = (g:R_help_w > 73) ? g:R_help_w : 73

            if wwidth > (min_e + min_h)
                # The editor window is large enough to be split
                hwidth = min_h
            elseif wwidth > (min_e + g:R_help_w)
                # The help window must have less than min_h columns
                hwidth = wwidth - min_e
            else
                # The help window must have the minimum value
                hwidth = g:R_help_w
            endif
            htwf = (hwidth - 1) / 0.9
        endif
        htw = float2nr(htwf)
        var numcol = (&number || &relativenumber) ? &numberwidth : 0
        htw = htw - numcol
    endif
enddef

def g:RAskHelp(...args: list<any>)
    if args[0] == ""
        g:SendCmdToR("help.start()")
        return
    endif
    if g:R_vimpager == "no"
        g:SendCmdToR("help(" .. args[0] .. ")")
    else
        g:AskRDoc(args[0], "", 0)
    endif
enddef

# Show R's help doc in Vim's buffer
# (based  on pydoc plugin)
def g:AskRDoc(rkeyword: string, package: string, getclass: number)
    var firstobj = ""
    if bufname("%") =~ "Object_Browser" || (has_key(g:rplugin, "R_bufnr") && bufnr("%") == g:rplugin.R_bufnr)
        var savesb = &switchbuf
        set switchbuf=useopen,usetab
        exe "sb " .. g:rplugin.rscript_name
        exe "set switchbuf=" .. savesb
    else
        if getclass
            firstobj = g:RGetFirstObj(rkeyword)[0]
        endif
    endif

    g:SetRTextWidth(rkeyword)

    var rcmd: string
    if firstobj == "" && package == ""
        rcmd = 'vimcom:::vim.help("' .. rkeyword .. '", ' .. htw .. 'L)'
    elseif package != ""
        rcmd = 'vimcom:::vim.help("' .. rkeyword .. '", ' .. htw .. 'L, package="' .. package  .. '")'
    else
        rcmd = 'vimcom:::vim.help("' .. rkeyword .. '", ' .. htw .. 'L, "' .. firstobj .. '")'
    endif

    g:SendToVimcom("E", rcmd)
enddef

# Function called by vimcom
def g:ShowRDoc(rkeyword: string, txt: string = '')
    var rkeyw = rkeyword
    if rkeyword =~ "^MULTILIB"
        var topic = split(rkeyword)[1]
        var libs = split(txt)
        var msg = "The topic '" .. topic .. "' was found in more than one library:\n"
        for idx in range(0, len(libs) - 1)
            msg ..= idx + 1 .. " : " .. libs[idx] .. "\n"
        endfor
        redraw
        var chn = str2nr(input(msg .. "Please, select one of them: "))
        if chn > 0 && chn <= len(libs)
            g:SendToVimcom("E", 'vimcom:::vim.help("' .. topic .. '", ' .. htw .. 'L, package="' .. libs[chn - 1] .. '")')
        endif
        return
    endif

    if has_key(g:rplugin, "R_bufnr") && bufnr("%") == g:rplugin.R_bufnr
        # Exit Terminal mode and go to Normal mode
        stopinsert
    endif

    # Legacy support for running R in a Tmux split pane.
    # If the help command was triggered in the R Console, jump to Vim pane:
    if has_key(g:rplugin, "tmux_split") && g:rplugin.tmux_split && !running_rhelp
        var slog = system("tmux select-pane -t " .. g:rplugin.editor_pane)
        if v:shell_error
            g:RWarningMsg(slog)
        endif
    endif
    running_rhelp = 0

    if bufname("%") =~ "Object_Browser" || (has_key(g:rplugin, "R_bufnr") && bufnr("%") == g:rplugin.R_bufnr)
        var savesb = &switchbuf
        set switchbuf=useopen,usetab
        exe "sb " .. g:rplugin.rscript_name
        exe "set switchbuf=" .. savesb
    endif
    g:SetRTextWidth(rkeyword)

    var rdoccaption = substitute(rdoctitle, '\\', '', "g")
    if rkeyword =~ "R History"
        rdoccaption = "R_History"
        rdoctitle = "R_History"
    endif
    if bufloaded(rdoccaption)
        var curtabnr = tabpagenr()
        var savesb = &switchbuf
        set switchbuf=useopen,usetab
        exe "sb " .. rdoctitle
        exe "set switchbuf=" .. savesb
        if g:R_vimpager == "tabnew"
            exe "tabmove " .. curtabnr
        endif
    else
        if g:R_vimpager == "tab" || g:R_vimpager == "tabnew"
            exe 'tabnew ' .. rdoctitle
        elseif vimpager_local == "vertical"
            var splr = &splitright
            set splitright
            exe hwidth .. 'vsplit ' .. rdoctitle
            &splitright = splr
        elseif vimpager_local == "horizontal"
            exe 'split ' .. rdoctitle
            if winheight(0) < 20
                resize 20
            endif
        elseif vimpager_local == "no"
            # The only way of ShowRDoc() being called when R_vimpager=="no"
            # is the user setting the value of R_vimpager to 'no' after
            # Vim startup. It should be set in the vimrc.
            if type(g:R_external_term) == v:t_number && g:R_external_term == 0
                g:R_vimpager = "vertical"
            else
                g:R_vimpager = "tab"
            endif
            g:ShowRDoc(rkeyword)
            return
        else
            echohl WarningMsg
            echomsg 'Invalid R_vimpager value: "' .. g:R_vimpager .. '". Valid values are: "tab", "vertical", "horizontal", "tabnew" and "no".'
            echohl None
            return
        endif
    endif

    setlocal modifiable
    g:rplugin.curbuf = bufname("%")

    var save_unnamed_reg = @@
    set modifiable
    sil normal! ggdG
    var fcntt = split(substitute(txt, "\x13", "'", "g"), "\x14")
    setline(1, fcntt)
    if rkeyword =~ "R History"
        set filetype=r
        cursor(1, 1)
    elseif rkeyword =~ '(help)' || search("\x08", "nw") > 0
        set filetype=rdoc
        cursor(1, 1)
    elseif rkeyword =~? '\.Rd$'
        # Called by devtools::load_all().
        # See https://github.com/jalvesaq/Vim-R/issues/482
        set filetype=rhelp
        cursor(1, 1)
    else
        set filetype=rout
        setlocal bufhidden=wipe
        setlocal nonumber
        setlocal noswapfile
        set buftype=nofile
        nnoremap <buffer><silent> q :q<CR>
        cursor(1, 1)
    endif
    @@ = save_unnamed_reg
    setlocal nomodified
    stopinsert
    redraw
enddef


# ==============================================================================
# Functions to send code directly to R Console
# ==============================================================================

def g:GetSourceArgs(e: string): string
    var sargs = ""
    if g:R_source_args != ""
        sargs = ", " .. g:R_source_args
    endif
    if e == "echo"
        sargs ..= ', echo=TRUE'
    endif
    return sargs
enddef

# Send sources to R
def g:RSourceLines(...args: list<any>): number
    var lines = args[0]
    if &filetype == "rrst"
        lines = map(copy(lines), (_, v) => substitute(v, "^\\.\\. \\?", "", ""))
    endif
    if &filetype == "rmd" || &filetype == "quarto"
        lines = map(copy(lines), (_, v) => substitute(v, "^(\\`\\`)\\?", "", ""))
    endif

    if len(args) == 3 && args[2] == "NewtabInsert"
        writefile(lines, Rsource_write)
        g:SendToVimcom("E", 'vimcom:::vim_capture_source_output("' .. Rsource_read .. '", "NewtabInsert")')
        return 1
    endif

    # The "brackted paste" option is not documented because it is not well
    # tested and source() have always worked flawlessly.
    var rcmd: string
    if g:R_source_args == "bracketed paste"
        rcmd = "\x1b[200~" .. join(lines, "\n") .. "\x1b[201~"
    else
        writefile(lines, Rsource_write)
        var sargs = substitute(g:GetSourceArgs(args[1]), '^, ', '', '')
        if len(args) == 3
            rcmd = 'VimR.' .. args[2] .. '(' .. sargs .. ')'
        else
            rcmd = 'VimR.source(' .. sargs .. ')'
        endif
    endif

    if len(args) == 3 && args[2] == "PythonCode"
        rcmd = 'reticulate::py_run_file("' .. Rsource_read .. '")'
    endif

    var ok = g:SendCmdToR(rcmd)
    return ok
enddef

def g:CleanOxygenLine(line: string): string
    var cline = line
    if cline =~ "^\s*#\\{1,2}'"
        var synName = synIDattr(synID(line("."), col("."), 1), "name")
        if synName == "rOExamples"
            cline = substitute(cline, "^\s*#\\{1,2}'", "", "")
        endif
    endif
    return cline
enddef

def g:CleanCurrentLine(): string
    var curline = substitute(getline("."), '^\s*', "", "")
    if &filetype == "r"
        curline = g:CleanOxygenLine(curline)
    endif
    return curline
enddef

# Skip empty lines and lines whose first non blank char is '#'
def g:GoDown()
    if &filetype == "rnoweb"
        var curline = getline(".")
        if curline[0] == '@'
            g:RnwNextChunk()
            return
        endif
    elseif &filetype == "rmd" || &filetype == "quarto"
        var curline = getline(".")
        if curline =~ '^```$'
            g:RmdNextChunk()
            return
        endif
    elseif &filetype == "rrst"
        var curline = getline(".")
        if curline =~ '^\.\. \.\.$'
            g:RrstNextChunk()
            return
        endif
    endif

    var i = line(".") + 1
    cursor(i, 1)
    var curline = g:CleanCurrentLine()
    var lastLine = line("$")
    while i < lastLine && (curline[0] == '#' || strlen(curline) == 0)
        i = i + 1
        cursor(i, 1)
        curline = g:CleanCurrentLine()
    endwhile
enddef

# Send motion to R
def g:SendMotionToR(type: string)
    var lstart = line("'[")
    var lend = line("']")
    if lstart == lend
        g:SendLineToR("stay", lstart)
    else
        var lines = getline(lstart, lend)
        g:RSourceLines(lines, "", "block")
    endif
enddef

# Send file to R
def g:SendFileToR(e: string)
    var fpath = expand("%:p") .. ".tmp.R"

    if filereadable(fpath)
        g:RWarningMsg('Error: cannot create "' .. fpath .. '" because it already exists. Please, delete it.')
        return
    endif

    if has("win32")
        fpath = substitute(fpath, "\\", "/", "g")
    endif
    writefile(getline(1, "$"), fpath)
    g:AddForDeletion(fpath)
    var sargs = g:GetSourceArgs(e)
    var ok = g:SendCmdToR('vimcom:::source.and.clean("' .. fpath ..  '"' .. sargs .. ')')
    if !ok
        delete(fpath)
    endif
enddef

# Send block to R
# Adapted from marksbrowser plugin
# Function to get the marks which the cursor is between
def g:SendMBlockToR(e: string, m: string)
    if &filetype != "r" && b:IsInRCode(1) != 1
        return
    endif

    var curline = line(".")
    var lineA = 1
    var lineB = line("$")
    var maxmarks = strlen(all_marks)
    var n = 0
    while n < maxmarks
        var c = strpart(all_marks, n, 1)
        var lnum = line("'" .. c)
        if lnum != 0
            if lnum <= curline && lnum > lineA
                lineA = lnum
            elseif lnum > curline && lnum < lineB
                lineB = lnum
            endif
        endif
        n = n + 1
    endwhile
    if lineA == 1 && lineB == (line("$"))
        g:RWarningMsg("The file has no mark!")
        return
    endif
    if lineB < line("$")
        lineB -= 1
    endif
    var lines = getline(lineA, lineB)
    var ok = g:RSourceLines(lines, e, "block")
    if ok == 0
        return
    endif
    if m == "down" && lineB != line("$")
        cursor(lineB, 1)
        g:GoDown()
    endif
enddef

# Strip strings and comments from an R line so that brace/paren
# matching is not confused by characters inside literals.
def g:SanitizeRLine(line: string): string
    # Remove content inside double-quoted strings (handle \" escapes)
    var result = substitute(line, '"[^"\\]*\%(\\.[^"\\]*\)*"', 's', 'g')
    # Remove content inside single-quoted strings (handle \' escapes)
    result = substitute(result, "'[^'\\]*\\%(\\.[^'\\]*\\)*'", 's', 'g')
    # Remove R comments
    result = substitute(result, '#.*', '', '')
    # Strip trailing whitespace
    result = substitute(result, '\s*$', '', '')
    return result
enddef

# Count braces
def g:CountBraces(line: string): number
    var line2 = substitute(line, "{", "", "g")
    var line3 = substitute(line, "}", "", "g")
    var result = strlen(line3) - strlen(line2)
    return result
enddef

# Send functions to R
def g:SendFunctionToR(e: string, m: string)
    if &filetype != "r" && b:IsInRCode(1) != 1
        return
    endif

    var startline = line(".")
    var save_cursor = getpos(".")
    var line = g:SanitizeRLine(getline("."))
    var i = line(".")
    while i > 0 && line !~ "function"
        i -= 1
        line = g:SanitizeRLine(getline(i))
    endwhile
    if i == 0
        g:RWarningMsg("Begin of function not found.")
        return
    endif
    var functionline = i
    while i > 0 && line !~ '\(<-\|=\)[[:space:]]*\($\|function\)'
        i -= 1
        line = g:SanitizeRLine(getline(i))
    endwhile
    if i == 0
        g:RWarningMsg("The function assign operator  <-  was not found.")
        return
    endif
    var firstline = i
    i = functionline
    line = g:SanitizeRLine(getline(i))
    var tt = line("$")
    while i < tt && line !~ "{"
        i += 1
        line = g:SanitizeRLine(getline(i))
    endwhile
    if i == tt
        g:RWarningMsg("The function opening brace was not found.")
        return
    endif
    var nb = g:CountBraces(line)
    while i < tt && nb > 0
        i += 1
        line = g:SanitizeRLine(getline(i))
        nb += g:CountBraces(line)
    endwhile
    if nb != 0
        g:RWarningMsg("The function closing brace was not found.")
        return
    endif
    var lastline = i

    if startline > lastline
        setpos(".", [0, max([firstline - 1, 1]), 1])
        g:SendFunctionToR(e, m)
        setpos(".", save_cursor)
        return
    endif

    var lines = getline(firstline, lastline)
    var ok = g:RSourceLines(lines, e, "function")
    if  ok == 0
        return
    endif
    if m == "down"
        cursor(lastline, 1)
        g:GoDown()
    endif
enddef

# Send all lines above to R
def g:SendAboveLinesToR()
    var lines = getline(1, line(".") - 1)
    g:RSourceLines(lines, "")
enddef

# Send selection to R
def g:SendSelectionToR(...args: list<any>)
    var ispy = 0
    if &filetype != "r"
        if (&filetype == 'rmd' || &filetype == 'quarto') && g:RmdIsInPythonCode(0)
            ispy = 1
        elseif b:IsInRCode(0) != 1
            if (&filetype == "rnoweb" && getline(".") !~ "\\Sexpr{") || ((&filetype == "rmd" || &filetype == "quarto") && getline(".") !~ "`r ") || (&filetype == "rrst" && getline(".") !~ ":r:`")
                g:RWarningMsg("Not inside an R code chunk.")
                return
            endif
        endif
    endif

    if line("'<") == line("'>")
        var i = col("'<") - 1
        var j = col("'>") - i
        var l = getline("'<")
        var line = strpart(l, i, j)
        if &filetype == "r"
            line = g:CleanOxygenLine(line)
        endif
        var ok = g:SendCmdToR(line)
        if ok && args[1] =~ "down"
            g:GoDown()
        endif
        return
    endif

    var lines = getline("'<", "'>")

    if visualmode() == "\<C-V>"
        var lj = line("'<")
        var cj = col("'<")
        var lk = line("'>")
        var ck = col("'>")
        var bb: number
        var ee: number
        if cj > ck
            bb = ck - 1
            ee = cj - ck + 1
        else
            bb = cj - 1
            ee = ck - cj + 1
        endif
        if cj > len(getline(lj)) || ck > len(getline(lk))
            for idx in range(0, len(lines) - 1)
                lines[idx] = strpart(lines[idx], bb)
            endfor
        else
            for idx in range(0, len(lines) - 1)
                lines[idx] = strpart(lines[idx], bb, ee)
            endfor
        endif
    else
        var i = col("'<") - 1
        var j = col("'>")
        lines[0] = strpart(lines[0], i)
        var llen = len(lines) - 1
        lines[llen] = strpart(lines[llen], 0, j)
    endif

    var curpos = getpos(".")
    var curline = line("'<")
    for idx in range(0, len(lines) - 1)
        setpos(".", [0, curline, 1, 0])
        if &filetype == "r"
            lines[idx] = g:CleanOxygenLine(lines[idx])
        endif
        curline += 1
    endfor
    setpos(".", curpos)

    var ok: number
    if len(args) == 3 && args[2] == "NewtabInsert"
        ok = g:RSourceLines(lines, args[0], "NewtabInsert")
    elseif ispy
        ok = g:RSourceLines(lines, args[0], 'PythonCode')
    else
        ok = g:RSourceLines(lines, args[0], 'selection')
    endif

    if ok == 0
        return
    endif

    if args[1] == "down"
        g:GoDown()
    else
        if len(args) < 3 || (len(args) == 3 && args[2] != "normal")
            normal! gv
        endif
    endif
enddef

# Send paragraph to R
def g:SendParagraphToR(e: string, m: string)
    if &filetype != "r" && b:IsInRCode(1) != 1
        return
    endif

    var o = line(".")
    var c = col(".")
    var i = o
    if g:R_paragraph_begin && getline(i) !~ '^\s*$'
        var line = getline(i - 1)
        while i > 1 && !(line =~ '^\s*$' ||
                    (&filetype == "rnoweb" && line =~ "^<<") ||
                    ((&filetype == "rmd" || &filetype == "quarto") && line =~ "^[ \t]*```{\\(r\\|python\\)"))
            i -= 1
            line = getline(i - 1)
        endwhile
    endif
    var max = line("$")
    var j = i
    var gotempty = 0
    while j < max
        var line = getline(j + 1)
        if line =~ '^\s*$' ||
                    (&filetype == "rnoweb" && line =~ "^@$") ||
                    ((&filetype == "rmd" || &filetype == "quarto") && line =~ "^[ \t]*```$")
            break
        endif
        j += 1
    endwhile
    var lines = getline(i, j)
    var ok = g:RSourceLines(lines, e, "paragraph")
    if ok == 0
        return
    endif
    if j < max
        cursor(j, 1)
    else
        cursor(max, 1)
    endif
    if m == "down"
        g:GoDown()
    else
        cursor(o, c)
    endif
enddef

# Send R code from the first chunk up to current line
def g:SendFHChunkToR()
    var begchk: string
    var endchk: string
    var chdchk: string
    if &filetype == "rnoweb"
        begchk = "^<<.*>>=\$"
        endchk = "^@"
        chdchk = "^<<.*child *= *"
    elseif &filetype == "rmd" || &filetype == "quarto"
        begchk = "^[ \t]*```[ ]*{r"
        endchk = "^[ \t]*```$"
        chdchk = "^```.*child *= *"
    elseif &filetype == "rrst"
        begchk = "^\\.\\. {r"
        endchk = "^\\.\\. \\.\\."
        chdchk = "^\\.\\. {r.*child *= *"
    else
        # Should never happen
        g:RWarningMsg('Strange filetype (SendFHChunkToR): "' .. &filetype .. '"')
    endif

    var codelines: list<string> = []
    var here = line(".")
    var curbuf = getline(1, "$")
    var idx = 0
    while idx < here
        if curbuf[idx] =~ begchk && curbuf[idx] !~ '\<eval\s*=\s*F'
            # Child R chunk
            if curbuf[idx] =~ chdchk
                # First run everything up to child chunk and reset buffer
                g:RSourceLines(codelines, "silent", "chunk")
                codelines = []

                # Next run child chunk and continue
                g:KnitChild(curbuf[idx], 'stay')
                idx += 1
                # Regular R chunk
            else
                idx += 1
                while curbuf[idx] !~ endchk && idx < here
                    codelines += [curbuf[idx]]
                    idx += 1
                endwhile
            endif
        else
            idx += 1
        endif
    endwhile
    g:RSourceLines(codelines, "silent", "chunk")
enddef

def g:KnitChild(line: string, godown: string)
    var nline = substitute(line, '.*child *= *', "", "")
    var cfile = substitute(nline, nline[0], "", "")
    cfile = substitute(cfile, nline[0] .. '.*', "", "")
    if filereadable(cfile)
        var ok = g:SendCmdToR("require(knitr); knit('" .. cfile .. "', output=" .. devnull .. ")")
        if godown =~ "down"
            cursor(line(".") + 1, 1)
            g:GoDown()
        endif
    else
        g:RWarningMsg("File not found: '" .. cfile .. "'")
    endif
enddef

def g:RParenDiff(str: string): number
    var clnln = substitute(str, '\\"',  "", "g")
    clnln = substitute(clnln, "\\\\'",  "", "g")
    clnln = substitute(clnln, '".\{-}"',  '', 'g')
    clnln = substitute(clnln, "'.\\{-}'",  "", "g")
    clnln = substitute(clnln, "#.*", "", "g")
    var llen1 = strlen(substitute(clnln, '[{(\[]', '', 'g'))
    var llen2 = strlen(substitute(clnln, '[})\]]', '', 'g'))
    return llen1 - llen2
enddef

if exists('g:r_indent_op_pattern')
    g:rplugin.op_pattern = g:r_indent_op_pattern
else
    g:rplugin.op_pattern = '\(&\||\|+\|-\|\*\|/\|=\|\~\|%\|->\||>\)\s*$'
endif

# Send current line to R.
def g:SendLineToR(godown: string, ...args: list<any>)
    var lnum = get(args, 0, ".")
    var line = getline(lnum)
    if strlen(line) == 0
        if godown =~ "down"
            g:GoDown()
        endif
        return
    endif

    if &filetype == "rnoweb"
        if line == "@"
            if godown =~ "down"
                g:GoDown()
            endif
            return
        endif
        if line =~ "^<<.*child *= *"
            g:KnitChild(line, godown)
            return
        endif
        if g:RnwIsInRCode(1) != 1
            return
        endif
    endif

    if &filetype == "rmd" || &filetype == "quarto"
        if line == "```"
            if godown =~ "down"
                g:GoDown()
            endif
            return
        endif
        if line =~ "^```.*child *= *"
            g:KnitChild(line, godown)
            return
        endif
        line = substitute(line, "^(\\`\\`)\\?", "", "")
        if g:RmdIsInRCode(0) != 1
            if g:RmdIsInPythonCode(0) == 0
                g:RWarningMsg("Not inside an R code chunk.")
                return
            else
                line = 'reticulate::py_run_string("' .. substitute(line, '"', '\\"', 'g') .. '")'
            endif
        endif
    endif

    if &filetype == "rrst"
        if line == ".. .."
            if godown =~ "down"
                g:GoDown()
            endif
            return
        endif
        if line =~ "^\.\. {r.*child *= *"
            g:KnitChild(line, godown)
            return
        endif
        line = substitute(line, "^\\.\\. \\?", "", "")
        if g:RrstIsInRCode(1) != 1
            return
        endif
    endif

    if &filetype == "rdoc"
        if getline(1) =~ '^The topic'
            var topic = substitute(line, '.*::', '', "")
            var package = substitute(line, '::.*', '', "")
            g:AskRDoc(topic, package, 1)
            return
        endif
        if g:RdocIsInRCode(1) != 1
            return
        endif
    endif

    if &filetype == "rhelp" && g:RhelpIsInRCode(1) != 1
        return
    endif

    if &filetype == "r"
        line = g:CleanOxygenLine(line)
    endif

    var block = 0
    var has_op = false
    var ok = 0
    if g:R_parenblock
        var chunkend = ""
        if &filetype == "rmd" || &filetype == "quarto"
            chunkend = "```"
        elseif &filetype == "rnoweb"
            chunkend = "@"
        elseif &filetype == "rrst"
            chunkend = ".. .."
        endif
        var rpd = g:RParenDiff(line)
        has_op = substitute(line, '#.*', '', '') =~ g:rplugin.op_pattern
        if rpd < 0
            var line1 = line(".")
            var cline = line1 + 1
            while cline <= line("$")
                var txt = getline(cline)
                if chunkend != "" && txt == chunkend
                    break
                endif
                rpd += g:RParenDiff(txt)
                if rpd == 0
                    has_op = substitute(getline(cline), '#.*', '', '') =~ g:rplugin.op_pattern
                    for lnum2 in range(line1, cline)
                        if g:R_bracketed_paste
                            if lnum2 == line1 && lnum2 == cline
                                ok = g:SendCmdToR("\x1b[200~" .. getline(lnum2) .. "\x1b[201~\n", 0)
                            elseif lnum2 == line1
                                ok = g:SendCmdToR("\x1b[200~" .. getline(lnum2))
                            elseif lnum2 == cline
                                ok = g:SendCmdToR(getline(lnum2) .. "\x1b[201~\n", 0)
                            else
                                ok = g:SendCmdToR(getline(lnum2))
                            endif
                        else
                            ok = g:SendCmdToR(getline(lnum2))
                        endif
                        if !ok
                            # always close bracketed mode upon failure
                            if g:R_bracketed_paste
                                g:SendCmdToR("\x1b[201~\n", 0)
                            endif
                            return
                        endif
                    endfor
                    cursor(cline, 1)
                    block = 1
                    break
                endif
                cline += 1
            endwhile
        endif
    endif

    if !block
        if g:R_bracketed_paste
            ok = g:SendCmdToR("\x1b[200~" .. line .. "\x1b[201~\n", 0)
        else
            ok = g:SendCmdToR(line)
        endif
    endif

    if ok
        if godown =~ "down"
            g:GoDown()
            if has_op
                g:SendLineToR(godown)
            endif
        else
            if godown == "newline"
                normal! o
            endif
        endif
    endif
enddef

def g:RSendPartOfLine(direction: string, correctpos: number)
    var lin = getline(".")
    var idx = col(".") - 1
    if correctpos
        cursor(line("."), idx)
    endif
    var rcmd: string
    if direction == "right"
        rcmd = strpart(lin, idx)
    else
        rcmd = strpart(lin, 0, idx + 1)
    endif
    g:SendCmdToR(rcmd)
enddef

# Clear the console screen
def g:RClearConsole()
    if g:R_clear_console == 0
        return
    endif
    if has("win32") && type(g:R_external_term) == v:t_number && g:R_external_term == 1
        g:JobStdin(g:rplugin.jobs["Server"], "86\n")
        sleep 50m
        g:JobStdin(g:rplugin.jobs["Server"], "87\n")
    else
        g:SendCmdToR("\014", 0)
    endif
enddef

# Remove all objects
def g:RClearAll()
    if g:R_rmhidden
        g:SendCmdToR("rm(list=ls(all.names = TRUE))")
    else
        g:SendCmdToR("rm(list=ls())")
    endif
    sleep 500m
    g:RClearConsole()
enddef

# Set working directory to the path of current buffer
def g:RSetWD()
    var wdcmd = 'setwd("' .. RGetBufDir() .. '")'
    if has("win32")
        wdcmd = substitute(wdcmd, "\\", "/", "g")
    endif
    g:SendCmdToR(wdcmd)
    sleep 100m
enddef

# knit the current buffer content
def g:RKnit()
    update
    g:SendCmdToR('require(knitr); .vim_oldwd <- getwd(); setwd("' .. RGetBufDir() .. '"); knit("' .. expand("%:t") .. '"); setwd(.vim_oldwd); rm(.vim_oldwd)')
enddef

def g:StartTxtBrowser(brwsr: string, url: string)
    exe 'terminal ++curwin ++close ' .. brwsr .. ' "' .. url .. '"'
enddef

def g:RSourceDirectory(...args: list<any>)
    var dir: string
    if has("win32")
        dir = substitute(args[0], '\\', '/', "g")
    else
        dir = args[0]
    endif
    if dir == ""
        g:SendCmdToR("vim.srcdir()")
    else
        g:SendCmdToR("vim.srcdir('" .. dir .. "')")
    endif
enddef

def g:PrintRObject(rkeyword: string)
    var firstobj: string
    if bufname("%") =~ "Object_Browser"
        firstobj = ""
    else
        firstobj = g:RGetFirstObj(rkeyword)[0]
    endif
    if firstobj == ""
        g:SendCmdToR("print(" .. rkeyword .. ")")
    else
        g:SendCmdToR('vim.print("' .. rkeyword .. '", "' .. firstobj .. '")')
    endif
enddef

def g:OpenRExample()
    if bufloaded(g:rplugin.tmpdir .. "/example.R")
        exe "bunload! " .. substitute(g:rplugin.tmpdir .. "/example.R", ' ', '\\ ', 'g')
    endif
    if g:R_vimpager == "tabnew" || g:R_vimpager == "tab"
        exe "tabnew " .. substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') .. "/example.R"
    else
        var vimpager = g:R_vimpager
        if g:R_vimpager == "vertical"
            var wwidth = winwidth(0)
            var min_e = (g:R_editor_w > 78) ? g:R_editor_w : 78
            var min_h = (g:R_help_w > 78) ? g:R_help_w : 78
            if wwidth < (min_e + min_h)
                vimpager = "horizontal"
            endif
        endif
        if vimpager == "vertical"
            exe "belowright vsplit " .. substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') .. "/example.R"
        else
            exe "belowright split " .. substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') .. "/example.R"
        endif
    endif
    nnoremap <buffer><silent> q :q<CR>
    setlocal bufhidden=wipe
    setlocal noswapfile
    set buftype=nofile
    delete(g:rplugin.tmpdir .. "/example.R")
enddef

# Call R functions for the word under cursor
def g:RAction(rcmd: string, ...args: list<any>)
    var rkeyword: string
    if &filetype == "rdoc"
        rkeyword = expand('<cword>')
    elseif &filetype == "rbrowser"
        rkeyword = g:RBrowserGetName()
    elseif len(args) >= 1 && args[0] == "v" && line("'<") == line("'>")
        rkeyword = strpart(getline("'>"), col("'<") - 1, col("'>") - col("'<") + 1)
    elseif len(args) >= 1 && args[0] != "v" && args[0] !~ '^,'
        rkeyword = g:RGetKeyword()
    else
        rkeyword = g:RGetKeyword()
    endif
    if strlen(rkeyword) > 0
        if rcmd == "help"
            var rhelppkg: string
            var rhelptopic: string
            if rkeyword =~ "::"
                var rhelplist = split(rkeyword, "::")
                rhelppkg = rhelplist[0]
                rhelptopic = rhelplist[1]
            else
                rhelppkg = ""
                rhelptopic = rkeyword
            endif
            running_rhelp = 1
            if g:R_vimpager == "no"
                g:SendCmdToR("help(" .. rkeyword .. ")")
            else
                if bufname("%") =~ "Object_Browser"
                    if g:rplugin.curview == "libraries"
                        rhelppkg = g:RBGetPkgName()
                    endif
                endif
                g:AskRDoc(rhelptopic, rhelppkg, 1)
            endif
            return
        endif
        if rcmd == "print"
            g:PrintRObject(rkeyword)
            return
        endif
        var rfun = rcmd
        if rcmd == "args"
            if g:R_listmethods == 1 && rkeyword !~ '::'
                g:SendCmdToR('vim.list.args("' .. rkeyword .. '")')
            else
                g:SendCmdToR('args(' .. rkeyword .. ')')
            endif
            return
        endif
        if rcmd == "plot" && g:R_specialplot == 1
            rfun = "vim.plot"
        endif
        if rcmd == "plotsumm"
            var raction: string
            if g:R_specialplot == 1
                raction = "vim.plot(" .. rkeyword .. "); summary(" .. rkeyword .. ")"
            else
                raction = "plot(" .. rkeyword .. "); summary(" .. rkeyword .. ")"
            endif
            g:SendCmdToR(raction)
            return
        endif

        if g:R_open_example && rcmd == "example"
            g:SendToVimcom("E", 'vimcom:::vim.example("' .. rkeyword .. '")')
            return
        endif

        var argmnts: string
        if len(args) == 1 && args[0] =~ '^,'
            argmnts = args[0]
        elseif len(args) == 2 && args[1] =~ '^,'
            argmnts = args[1]
        else
            argmnts = ''
        endif

        if rcmd == "viewobj" || rcmd == "dputtab"
            if rcmd == "viewobj"
                if exists("g:R_df_viewer")
                    argmnts ..= ', R_df_viewer = "' .. g:R_df_viewer .. '"'
                endif
                if rkeyword =~ '::'
                    g:SendToVimcom("E",
                                'vimcom:::vim_viewobj(' .. rkeyword .. argmnts .. ')')
                else
                    if has("win32") && &encoding == "utf-8"
                        g:SendToVimcom("E",
                                    'vimcom:::vim_viewobj("' .. rkeyword .. '"' .. argmnts ..
                                    ', fenc="UTF-8"' .. ')')
                    else
                        g:SendToVimcom("E",
                                    'vimcom:::vim_viewobj("' .. rkeyword .. '"' .. argmnts .. ')')
                    endif
                endif
            else
                g:SendToVimcom("E",
                            'vimcom:::vim_dput("' .. rkeyword .. '"' .. argmnts .. ')')
            endif
            return
        endif

        var raction = rfun .. '(' .. rkeyword .. argmnts .. ')'
        g:SendCmdToR(raction)
    endif
enddef

def g:RLoadHTML(fullpath: string, browser: string)
    if g:R_openhtml == 0
        return
    endif

    var cmd: list<string>
    if browser == ''
        if has('win32')
            cmd = ['cmd', '/c', 'start', '', fullpath]
        else
            cmd = ['xdg-open', fullpath]
        endif
    else
        cmd = split(browser) + [fullpath]
    endif

    job_start(cmd)
enddef

def g:ROpenDoc(fullpath: string, browser: string)
    if fullpath == ""
        return
    endif
    if !filereadable(fullpath)
        g:RWarningMsg('The file "' .. fullpath .. '" does not exist.')
        return
    endif
    if fullpath =~ '.odt$' || fullpath =~ '.docx$'
        system('lowriter ' .. fullpath .. ' &')
    elseif fullpath =~ '.pdf$'
        g:ROpenPDF(fullpath)
    elseif fullpath =~ '.html$'
        g:RLoadHTML(fullpath, browser)
    else
        g:RWarningMsg("Unknown file type from vim.interlace: " .. fullpath)
    endif
enddef

# render a document with rmarkdown
def g:RMakeRmd(t: string)
    if !has_key(g:rplugin, "pdfviewer")
        g:RSetPDFViewer()
    endif

    update

    var rmddir = RGetBufDir()
    var rcmd: string
    if t == "default"
        rcmd = 'vim.interlace.rmd("' .. expand("%:t") .. '", rmddir = "' .. rmddir .. '"'
    else
        rcmd = 'vim.interlace.rmd("' .. expand("%:t") .. '", outform = "' .. t .. '", rmddir = "' .. rmddir .. '"'
    endif

    if g:R_rmarkdown_args == ''
        rcmd = rcmd .. ', envir = ' .. g:R_rmd_environment .. ')'
    else
        rcmd = rcmd .. ', envir = ' .. g:R_rmd_environment .. ', ' .. substitute(g:R_rmarkdown_args, "'", '"', 'g') .. ')'
    endif
    g:SendCmdToR(rcmd)
enddef

def g:RBuildTags()
    if filereadable("etags")
        g:RWarningMsg('The file "etags" exists. Please, delete it and try again.')
        return
    endif
    g:SendCmdToR('rtags(ofile = "etags"); etags2ctags("etags", "tags"); unlink("etags")')
enddef


# ==============================================================================
# Set variables
# ==============================================================================

g:R_rmhidden          = get(g:, "R_rmhidden",           0)
g:R_paragraph_begin   = get(g:, "R_paragraph_begin",    1)
g:R_after_ob_open     = get(g:, "R_after_ob_open",     [])
g:R_min_editor_width  = get(g:, "R_min_editor_width",  80)
g:R_rconsole_width    = get(g:, "R_rconsole_width",    80)
g:R_rconsole_height   = get(g:, "R_rconsole_height",   15)
g:R_after_start       = get(g:, "R_after_start",       [])
g:R_listmethods       = get(g:, "R_listmethods",        0)
g:R_specialplot       = get(g:, "R_specialplot",        0)
g:R_notmuxconf        = get(g:, "R_notmuxconf",         0)
g:R_editor_w          = get(g:, "R_editor_w",          66)
g:R_help_w            = get(g:, "R_help_w",            46)
g:R_esc_term          = get(g:, "R_esc_term",           1)
g:R_close_term        = get(g:, "R_close_term",         1)
g:R_buffer_opts       = get(g:, "R_buffer_opts", "winfixwidth winfixheight nobuflisted")
g:R_debug             = get(g:, "R_debug",              1)
g:R_debug_center      = get(g:, "R_debug_center",       0)
g:R_dbg_jump          = get(g:, "R_dbg_jump",           1)
g:R_wait              = get(g:, "R_wait",              60)
g:R_wait_reply        = get(g:, "R_wait_reply",         2)
g:R_open_example      = get(g:, "R_open_example",       1)
g:R_bracketed_paste   = get(g:, "R_bracketed_paste",    0)
g:R_clear_console     = get(g:, "R_clear_console",      1)
g:R_objbr_auto_start  = get(g:, "R_objbr_auto_start",   0)
g:R_compl_data        = get(g:, "R_compl_data", {'max_depth': 12, 'max_size': 1000000, 'max_time': 100})

# ^K (\013) cleans from cursor to the right and ^U (\025) cleans from cursor
# to the left. However, ^U causes a beep if there is nothing to clean. The
# solution is to use ^A (\001) to move the cursor to the beginning of the line
# before sending ^K. But the control characters may cause problems in some
# circumstances.
g:R_clear_line = get(g:, "R_clear_line", 0)

# Avoid problems if either R_rconsole_width or R_rconsole_height is a float
# number (https://github.com/jalvesaq/Vim-R/issues/751#issuecomment-1742784447).
if type(g:R_rconsole_width) == v:t_float
    g:R_rconsole_width = float2nr(g:R_rconsole_width)
endif
if type(g:R_rconsole_height) == v:t_float
    g:R_rconsole_height = float2nr(g:R_rconsole_height)
endif


if type(g:R_after_start) != v:t_list
    g:RWarningMsg('R_after_start must be a list of strings')
    sleep 1
    g:R_after_start = []
endif

# Make the file name of files to be sourced
var Rsource_read: string
if exists("g:R_remote_compldir")
    Rsource_read = g:R_remote_compldir .. "/tmp/Rsource-" .. getpid()
else
    Rsource_read = g:rplugin.tmpdir .. "/Rsource-" .. getpid()
endif
var Rsource_write = g:rplugin.tmpdir .. "/Rsource-" .. getpid()
g:AddForDeletion(Rsource_write)

var running_objbr = 0
var running_rhelp = 0
g:rplugin.R_pid = 0

# List of marks that the plugin seeks to find the block to be sent to R
var all_marks = "abcdefghijklmnopqrstuvwxyz"

var devnull: string
if filewritable('/dev/null')
    devnull = "'/dev/null'"
elseif has("win32") && filewritable('NUL')
    devnull = "'NUL'"
else
    devnull = 'tempfile()'
endif

var nseconds: number
var autosttobjbr: number
var R_version: string
var rdoctitle: string
var vimpager_local: string
var htw: number
var hwidth: number
