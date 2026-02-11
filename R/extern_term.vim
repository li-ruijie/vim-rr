vim9script

if exists("g:did_vimr_extern_term")
    finish
endif
g:did_vimr_extern_term = 1

# Define a function to retrieve tmux settings
def g:TmuxOption(option: string, isglobal: string): string
    var result: string
    if isglobal == "global"
        result = system("tmux -L VimR show-options -gv " .. option)
    else
        result = system("tmux -L VimR show-window-options -gv " .. option)
    endif
    return substitute(result, '\n\+$', '', '')
enddef

def g:StartR_ExternalTerm(rcmd: string)
    var tmuxcnf: string
    if g:R_notmuxconf
        tmuxcnf = ' '
    else
        # Create a custom tmux.conf
        var cnflines = ['set-option -g prefix C-a',
                    'unbind-key C-b',
                    'bind-key C-a send-prefix',
                    'set-window-option -g mode-keys vi',
                    'set -g status off',
                    'set -g default-terminal "screen-256color"',
                    "set -g terminal-overrides 'xterm*:smcup@:rmcup@'"]

        if executable('/bin/sh')
            cnflines += ['set-option -g default-shell "/bin/sh"']
        endif

        if term_name == "rxvt" || term_name == "urxvt"
            cnflines = cnflines + [
                        "set terminal-overrides 'rxvt*:smcup@:rmcup@'"]
        endif

        if term_name == "alacritty"
            cnflines = cnflines + [
                        "set terminal-overrides 'alacritty:smcup@:rmcup@'"]
        endif

        writefile(cnflines, g:rplugin.tmpdir .. "/tmux.conf")
        g:AddForDeletion(g:rplugin.tmpdir .. "/tmux.conf")
        tmuxcnf = '-f "' .. g:rplugin.tmpdir .. "/tmux.conf" .. '"'
    endif

    var envrcmd = 'VIMR_TMPDIR=' .. substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') ..
                ' VIMR_COMPLDIR=' .. substitute(g:rplugin.compldir, ' ', '\\ ', 'g') ..
                ' VIMR_ID=' .. $VIMR_ID ..
                ' VIMR_SECRET=' .. $VIMR_SECRET ..
                ' VIMR_PORT=' .. g:rplugin.myport ..
                ' R_DEFAULT_PACKAGES=' .. $R_DEFAULT_PACKAGES

    envrcmd ..= ' ' .. rcmd

    system("tmux -L VimR has-session -t " .. g:rplugin.tmuxsname)
    var opencmd: string
    if v:shell_error
        if term_name == "konsole"
            opencmd = printf("%s 'tmux -L VimR -2 %s new-session -s %s \"%s\"'",
                        term_cmd, tmuxcnf, g:rplugin.tmuxsname, envrcmd)
        else
            opencmd = printf("%s tmux -L VimR -2 %s new-session -s %s \"%s\"",
                        term_cmd, tmuxcnf, g:rplugin.tmuxsname, envrcmd)
        endif
    else
        opencmd = printf("%s tmux -L VimR -2 %s attach-session -d -t %s",
                    term_cmd, tmuxcnf, g:rplugin.tmuxsname)
    endif

    if g:R_silent_term
        opencmd ..= " &"
        var rlog = system(opencmd)
        if v:shell_error
            g:RWarningMsg(rlog)
            return
        endif
    else
        var initterm = ['cd "' .. getcwd() .. '"',
                    opencmd]
        writefile(initterm, g:rplugin.tmpdir .. "/initterm_" .. $VIMR_ID .. ".sh")
        g:rplugin.jobs["Terminal emulator"] = g:StartJob(["sh", g:rplugin.tmpdir .. "/initterm_" .. $VIMR_ID .. ".sh"],
                    {err_cb: 'g:ROnJobStderr', exit_cb: 'g:ROnJobExit'})
        g:AddForDeletion(g:rplugin.tmpdir .. "/initterm_" .. $VIMR_ID .. ".sh")
    endif
    g:rplugin.debug_info['R open command'] = opencmd

    g:SendCmdToR = function('g:SendCmdToR_Term')
    g:WaitVimcomStart()
enddef

def g:SendCmdToR_Term(...args: list<any>): number
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

    # Send the command to R running in an external terminal emulator
    var str = substitute(cmd, "'", "'\\\\''", "g")
    if str =~ '^-'
        str = ' ' .. str
    endif
    var scmd: string
    if len(args) == 2 && args[1] == 0
        scmd = "tmux -L VimR set-buffer '" .. str .. "' ; tmux -L VimR paste-buffer -t " .. g:rplugin.tmuxsname .. '.' .. g:TmuxOption("pane-base-index", "window")
    else
        scmd = "tmux -L VimR set-buffer '" .. str .. "\<CR>' ; tmux -L VimR paste-buffer -t " .. g:rplugin.tmuxsname .. '.' .. g:TmuxOption("pane-base-index", "window")
    endif
    var rlog = system(scmd)
    if v:shell_error
        rlog = substitute(rlog, '\n', ' ', 'g')
        rlog = substitute(rlog, '\r', ' ', 'g')
        g:RWarningMsg(rlog)
        g:ClearRInfo()
        return 0
    endif
    return 1
enddef

# The Object Browser can run in a Tmux pane only if Vim is inside a Tmux session
g:R_objbr_place = substitute(g:R_objbr_place, "console", "script", "")

g:R_silent_term = get(g:, "R_silent_term", 0)

var term_name = ''
var term_cmd = ''

if type(g:R_external_term) == v:t_string
    term_name = substitute(g:R_external_term, ' .*', '', '')
    term_cmd = g:R_external_term
    if g:R_external_term =~ ' '
        # The terminal command is complete
        finish
    endif
endif

if term_name != ''
    if !executable(term_name)
        g:RWarningMsg("'" .. term_name .. "' not found. Please change the value of 'R_external_term' in your vimrc.")
        finish
    endif
else
    # Choose a terminal (code adapted from screen.vim)
    var terminals = ['gnome-terminal', 'konsole', 'xfce4-terminal', 'Eterm',
                'rxvt', 'urxvt', 'aterm', 'roxterm', 'lxterminal', 'alacritty', 'xterm']
    if $WAYLAND_DISPLAY != ''
        terminals = ['foot'] + terminals
    endif
    for term in terminals
        if executable(term)
            term_name = term
            break
        endif
    endfor
endif

if term_name == ''
    g:RWarningMsg("Please, set the variable 'g:R_external_term' in your vimrc. See the plugin documentation for details.")
    g:rplugin.failed = 1
    finish
endif

if term_name =~ '^\(foot\|gnome-terminal\|xfce4-terminal\|roxterm\|Eterm\|aterm\|lxterminal\|rxvt\|urxvt\|alacritty\)$'
    term_cmd = term_name .. " --title R"
elseif term_name =~ '^\(xterm\|uxterm\|lxterm\)$'
    term_cmd = term_name .. " -title R"
else
    term_cmd = term_name
endif

if term_name == 'foot'
    term_cmd ..= ' --log-level error'
endif

if !g:R_vim_wd
    if term_name =~ '^\(gnome-terminal\|xfce4-terminal\|lxterminal\)$'
        term_cmd ..= " --working-directory='" .. expand("%:p:h") .. "'"
    elseif term_name == "konsole"
        term_cmd ..= " -p tabtitle=R --workdir '" .. expand("%:p:h") .. "'"
    elseif term_name == "roxterm"
        term_cmd ..= " --directory='" .. expand("%:p:h") .. "'"
    endif
endif

if term_name == "gnome-terminal"
    term_cmd ..= " --"
elseif term_name =~ '^\(terminator\|xfce4-terminal\)$'
    term_cmd ..= " -x"
else
    term_cmd ..= " -e"
endif
