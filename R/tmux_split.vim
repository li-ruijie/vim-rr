vim9script

if exists("g:did_vimr_tmux_split") || $TMUX == ''
    finish
endif
g:did_vimr_tmux_split = 1

g:R_external_term = 1
g:rplugin.tmux_split = 1
g:R_tmux_title = get(g:, 'R_tmux_title', 'VimR')

# Adapted from screen plugin:
def g:TmuxActivePane(): string
    var line = system("tmux list-panes | grep '(active)$'")
    var paneid = matchstr(line, '\v\%\d+ \(active\)')
    if !empty(paneid)
        return matchstr(paneid, '\v^\%\d+')
    else
        return matchstr(line, '\v^\d+')
    endif
enddef

# Replace StartR_ExternalTerm with a function that starts R in a Tmux split pane
def g:StartR_ExternalTerm(rcmd: string)
    g:rplugin.editor_pane = $TMUX_PANE
    var tmuxconf = ['set-environment VIMR_TMPDIR "' .. g:rplugin.tmpdir .. '"',
                'set-environment VIMR_COMPLDIR "' .. substitute(g:rplugin.compldir, ' ', '\\ ', "g") .. '"',
                'set-environment VIMR_ID ' .. $VIMR_ID,
                'set-environment VIMR_SECRET ' .. $VIMR_SECRET,
                'set-environment VIMR_PORT ' .. g:rplugin.myport,
                'set-environment R_DEFAULT_PACKAGES ' .. $R_DEFAULT_PACKAGES]
    if $R_LIBS_USER != ""
        extend(tmuxconf, ['set-environment R_LIBS_USER ' .. $R_LIBS_USER])
    endif
    if &t_Co == 256
        extend(tmuxconf, ['set default-terminal "' .. $TERM .. '"'])
    endif
    writefile(tmuxconf, g:rplugin.tmpdir .. "/tmux" .. $VIMR_ID .. ".conf")
    system("tmux source-file '" .. g:rplugin.tmpdir .. "/tmux" .. $VIMR_ID .. ".conf" .. "'")
    delete(g:rplugin.tmpdir .. "/tmux" .. $VIMR_ID .. ".conf")
    var tcmd = "tmux split-window "
    if g:R_rconsole_width == -1
        tcmd ..= "-h"
    elseif g:R_rconsole_width > 0 && winwidth(0) > (g:R_rconsole_width + g:R_min_editor_width + 1 + ((&number ? 1 : 0) * &numberwidth))
        tcmd ..= "-h -l " .. g:R_rconsole_width
    else
        tcmd ..= "-l " .. g:R_rconsole_height
    endif

    # Let Tmux automatically kill the panel when R quits.
    tcmd ..= " '" .. rcmd .. "'"

    var rlog = system(tcmd)
    if v:shell_error
        g:RWarningMsg(rlog)
        return
    endif
    g:rplugin.rconsole_pane = g:TmuxActivePane()
    rlog = system("tmux select-pane -t " .. g:rplugin.editor_pane)
    if v:shell_error
        g:RWarningMsg(rlog)
        return
    endif
    g:SendCmdToR = function('g:SendCmdToR_TmuxSplit')
    g:rplugin.last_rcmd = rcmd
    if g:R_tmux_title != "automatic" && g:R_tmux_title != ""
        system("tmux rename-window " .. g:R_tmux_title)
    endif
    g:WaitVimcomStart()
    # Environment variables persist across Tmux windows.
    # Unset VIMR_TMPDIR to avoid vimcom loading its C library
    # when R was not started by Vim:
    system("tmux set-environment -u VIMR_TMPDIR")
    # Also unset R_DEFAULT_PACKAGES so that other R instances do not
    # load vimcom unnecessarily
    system("tmux set-environment -u R_DEFAULT_PACKAGES")
enddef

def g:SendCmdToR_TmuxSplit(...args: list<any>): number
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

    var str = substitute(cmd, "'", "'\\\\''", "g")
    if str =~ '^-'
        str = ' ' .. str
    endif
    var scmd: string
    if len(args) == 2 && args[1] == 0
        scmd = "tmux set-buffer '" .. str .. "' ; tmux paste-buffer -t " .. g:rplugin.rconsole_pane
    else
        scmd = "tmux set-buffer '" .. str .. "\<CR>' ; tmux paste-buffer -t " .. g:rplugin.rconsole_pane
    endif
    var rlog = system(scmd)
    if v:shell_error
        rlog = substitute(rlog, "\n", " ", "g")
        rlog = substitute(rlog, "\r", " ", "g")
        g:RWarningMsg(rlog)
        g:ClearRInfo()
        return 0
    endif
    return 1
enddef
