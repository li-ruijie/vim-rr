vim9script

# This file contains code used only when R run in a Vim buffer

var R_width = 0
var number_col = 0

def g:SendCmdToR_Buffer(...args: list<any>): number
    if g:IsJobRunning(g:rplugin.jobs["R"])
        var cmd: string
        if g:R_clear_line
            if g:R_editing_mode == "emacs"
                cmd = "\001\013" .. args[0]
            else
                cmd = "\x1b0Da" .. args[0]
            endif
        else
            cmd = args[0]
        endif

        # Update the width, if necessary
        if g:R_setwidth != 0 && g:R_setwidth != 2
            var rwnwdth = winwidth(g:rplugin.R_winnr)
            if rwnwdth != R_width && rwnwdth != -1 && rwnwdth > 10 && rwnwdth < 999
                R_width = rwnwdth
                var Rwidth = R_width + number_col
                if has("win32")
                    cmd = "options(width=" .. Rwidth .. "); " .. cmd
                else
                    g:SendToVimcom("E", "options(width=" .. Rwidth .. ")")
                    sleep 10m
                endif
            endif
        endif

        if len(args) == 2 && args[1] == 0
            term_sendkeys(g:term_bufn, cmd)
        else
            term_sendkeys(g:term_bufn, cmd .. "\n")
        endif
        return 1
    else
        g:RWarningMsg("Is R running?")
        return 0
    endif
enddef

def g:StartR_InBuffer()
    if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
        return
    endif

    g:SendCmdToR = function('g:SendCmdToR_NotYet')

    var edbuf = bufname("%")
    set switchbuf=useopen

    if g:R_rconsole_width > 0 && winwidth(0) > (g:R_rconsole_width + g:R_min_editor_width + 1 + (&number * &numberwidth))
        if g:R_rconsole_width > 16 && g:R_rconsole_width < (winwidth(0) - 17)
            silent execute "belowright " .. g:R_rconsole_width .. "vnew"
        else
            silent belowright vnew
        endif
    else
        if g:R_rconsole_height > 0 && g:R_rconsole_height < (winheight(0) - 1)
            silent execute "belowright " .. g:R_rconsole_height .. "new"
        else
            silent belowright new
        endif
    endif

    if has("win32")
        g:SetRHome()
    endif

    var rcmd = len(g:rplugin.r_args)
        ? g:rplugin.R .. " " .. join(g:rplugin.r_args)
        : g:rplugin.R
    g:term_bufn = g:R_close_term
        ? term_start(rcmd,
            {'exit_cb': function('g:ROnJobExit'), "curwin": 1, "term_finish": "close"})
        : term_start(rcmd,
            {'exit_cb': function('g:ROnJobExit'), "curwin": 1})
    g:rplugin.jobs["R"] = term_getjob(g:term_bufn)

    if has("win32")
        redraw
        g:UnsetRHome()
    endif
    g:rplugin.R_bufnr = bufnr("%")
    g:rplugin.R_winnr = win_getid()
    R_width = 0
    number_col = &number
        ? (g:R_setwidth < 0 && g:R_setwidth > -17 ? g:R_setwidth : -6)
        : 0
    if exists("g:R_hl_term") && g:R_hl_term
        set syntax=rout
    endif
    for optn in split(g:R_buffer_opts)
        execute 'setlocal ' .. optn
    endfor
    # Set b:pdf_is_open to avoid error when the user has to go to R Console to
    # deal with latex errors while compiling the pdf
    b:pdf_is_open = 1
    execute "sbuffer " .. edbuf
    g:WaitVimcomStart()
enddef

g:R_setwidth = get(g:, 'R_setwidth', 1)

if has("win32")
    # The R package colorout only works on Unix systems
    g:R_hl_term = get(g:, "R_hl_term", 1)
endif
