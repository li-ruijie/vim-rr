vim9script

if exists("g:did_vimr_windows")
    finish
endif
g:did_vimr_windows = 1

# This file contains code used only on Windows

g:R_set_home_env = get(g:, 'R_set_home_env', 1)
g:R_i386 = get(g:, 'R_i386', 0)

if exists('g:R_path')
    var rpath = split(g:R_path, ';')
    map(rpath, (_, v) => expand(v))
    reverse(rpath)
    for dir in rpath
        if isdirectory(dir)
            $PATH = dir .. ';' .. $PATH
        else
            g:RWarningMsg('"' .. dir .. '" is not a directory. Fix the value of R_path in your vimrc.')
        endif
    endfor
else
    if isdirectory($RTOOLS40_HOME .. '\usr\bin')
        $PATH = $RTOOLS40_HOME .. '\usr\bin;' .. $PATH
    elseif isdirectory('C:\rtools40\usr\bin')
        $PATH = 'C:\rtools40\usr\bin;' .. $PATH
    endif
    if isdirectory($RTOOLS40_HOME .. '\mingw64\bin\')
        $PATH = $RTOOLS40_HOME .. '\mingw64\bin;' .. $PATH
    elseif isdirectory('C:\rtools40\mingw64\bin')
        $PATH = 'C:\rtools40\mingw64\bin;' .. $PATH
    endif

    var rinstallpath = ''
    for rr in ['HKLM', 'HKCU']
        writefile(['reg.exe QUERY "' .. rr .. '\SOFTWARE\R-core\R" /s'], g:rplugin.tmpdir .. '/run_cmd.bat')
        var ripl = system(g:rplugin.tmpdir .. '/run_cmd.bat')
        var rip = split(ripl, "\n")->filter((_, v) => v =~ '.*InstallPath.*REG_SZ')
        if len(rip) == 0
            # Normally, 32 bit applications access only 32 bit registry and...
            # We have to try again if the user has installed R only in the other architecture.
            if has('win64')
                writefile(['reg.exe QUERY "' .. rr .. '\SOFTWARE\R-core\R" /s /reg:32'], g:rplugin.tmpdir .. '/run_cmd.bat')
            else
                writefile(['reg.exe QUERY "' .. rr .. '\SOFTWARE\R-core\R" /s /reg:64'], g:rplugin.tmpdir .. '/run_cmd.bat')
            endif
            ripl = system(g:rplugin.tmpdir .. '/run_cmd.bat')
            rip = split(ripl, "\n")->filter((_, v) => v =~ '.*InstallPath.*REG_SZ')
        endif
        if len(rip) > 0
            rinstallpath = substitute(rip[0], '.*InstallPath.*REG_SZ\s*', '', '')
            rinstallpath = substitute(rinstallpath, '\n', '', 'g')
            rinstallpath = substitute(rinstallpath, '\s*$', '', 'g')
            break
        endif
    endfor
    if rinstallpath == ''
        if !executable('R')
            g:RWarningMsg("Could not find R path in Windows Registry or in $PATH. If you have already installed R, please, set the value of 'R_path'.")
            g:rplugin.failed = 1
        endif
    else
        var hasR32 = isdirectory(rinstallpath .. '\bin\i386')
        var hasR64 = isdirectory(rinstallpath .. '\bin\x64')
        if hasR32 && !hasR64
            g:R_i386 = 1
        endif
        if hasR64 && !hasR32
            g:R_i386 = 0
        endif
        if hasR32 && g:R_i386
            $PATH = rinstallpath .. '\bin\i386;' .. $PATH
        elseif hasR64 && g:R_i386 == 0
            $PATH = rinstallpath .. '\bin\x64;' .. $PATH
        else
            $PATH = rinstallpath .. '\bin;' .. $PATH
        endif
    endif
endif

if !exists('g:R_args')
    if type(g:R_external_term) == v:t_number && g:R_external_term == 0
        g:R_args = ['--no-save']
    else
        g:R_args = ['--sdi', '--no-save']
    endif
endif

g:R_R_window_title = get(g:, 'R_R_window_title', 'R Console')

var saved_home = ''

def g:SetRHome()
    # R and Vim use different values for the $HOME variable.
    if g:R_set_home_env
        saved_home = $HOME
        writefile(['reg.exe QUERY "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v "Personal"'], g:rplugin.tmpdir .. '/run_cmd.bat')
        var prs = system(g:rplugin.tmpdir .. '/run_cmd.bat')
        if len(prs) > 0
            prs = substitute(prs, '.*REG_SZ\s*', '', '')
            prs = substitute(prs, '\n', '', 'g')
            prs = substitute(prs, '\r', '', 'g')
            prs = substitute(prs, '\s*$', '', 'g')
            $HOME = prs
        endif
    endif
enddef

def g:UnsetRHome()
    if saved_home != ''
        $HOME = saved_home
        saved_home = ''
    endif
enddef

def g:StartR_Windows()
    if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
        if g:IsJobRunning("Server")
            g:JobStdin(g:rplugin.jobs['Server'], "81Check if R is running\n")
        endif
        return
    endif

    if g:rplugin.R =~? 'Rterm' && exists('g:R_app') && g:R_app =~? 'Rterm'
        g:RWarningMsg('"R_app" cannot be "Rterm.exe". R will crash if you send any command.')
        sleep 200m
    endif

    g:SendCmdToR = function('g:SendCmdToR_NotYet')

    g:SetRHome()
    silent execute '!start ' .. g:rplugin.R .. ' ' .. join(g:R_args)
    g:UnsetRHome()

    g:WaitVimcomStart()
enddef

def g:CleanVimAndStartR()
    g:ClearRInfo()
    g:StartR_Windows()
enddef

def g:SendCmdToR_Windows(...args: list<any>): number
    var cmd: string
    if g:R_clear_line
        cmd = "\001" .. "\013" .. args[0] .. "\n"
    else
        cmd = args[0] .. "\n"
    endif
    if !g:IsJobRunning("Server")
        g:RWarningMsg("Server not running.")
        return 0
    endif
    g:JobStdin(g:rplugin.jobs['Server'], '83' .. cmd)
    return 1
enddef

execute 'call AddForDeletion(g:rplugin.tmpdir .. "/run_cmd.bat")'

# 2020-05-19
if exists('g:Rtools_path')
    g:RWarningMsg('The variable "Rtools_path" is no longer used.')
endif
