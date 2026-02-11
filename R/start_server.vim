vim9script

if exists("g:did_vimr_start_server")
    finish
endif
g:did_vimr_start_server = 1

# Functions to start vimrserver or that are called only after the
# vimrserver is running

# Check if it's necessary to build and install vimcom before attempting to load it
def g:CheckVimcomVersion()
    var flines: list<string>
    if filereadable(g:rplugin.home .. '/R/vimcom/DESCRIPTION')
        var ndesc = readfile(g:rplugin.home .. '/R/vimcom/DESCRIPTION')
        var current = substitute(matchstr(ndesc, '^Version: '), 'Version: ', '', '')
        flines = ['needed_vimcom_version <- "' .. current .. '"']
    else
        flines = ['needed_vimcom_version <- NULL']
    endif

    var libs = g:ListRLibsFromBuffer()
    flines += ['vim_r_home <- "' .. g:rplugin.home .. '"',
                'libs <- c(' .. libs .. ')']
    flines += readfile(g:rplugin.home .. "/R/before_nrs.R")
    var scrptnm = g:rplugin.tmpdir .. "/before_nrs.R"
    writefile(flines, scrptnm)
    g:AddForDeletion(g:rplugin.tmpdir .. "/before_nrs.R")

    # Run the script as a job, setting callback functions to receive its
    # stdout, stderr and exit code.
    var jobh = {'out_cb':  'g:RInitStdout',
                'err_cb':  'g:RInitStderr',
                'exit_cb': 'g:RInitExit'}

    RBout = []
    RBerr = []
    RWarn = []
    if exists("g:R_remote_compldir")
        scrptnm = g:R_remote_compldir .. "/tmp/before_nrs.R"
    endif
    g:rplugin.debug_info['Time']['before_nrs.R'] = reltime()
    g:rplugin.jobs["Init R"] = g:StartJob([g:rplugin.Rcmd, "--quiet", "--no-save", "--no-restore", "--slave", "-f", scrptnm], jobh)
    g:AddForDeletion(g:rplugin.tmpdir .. "/libPaths")
enddef

def g:MkRdir()
    redraw
    var resp = input('"' .. g:rplugin.libd .. '" is not writable. Create it now? [y/n] ')
    if resp[0] ==? "y"
        var dw = mkdir(g:rplugin.libd, "p")
        if dw
            # Try again
            g:CheckVimcomVersion()
        else
            g:RWarningMsg('Failed creating "' .. g:rplugin.libd .. '"')
        endif
    else
        echo ""
        redraw
    endif
    remove(g:rplugin, 'libd')
enddef

# Get the output of R CMD build and INSTALL
var RoutLine = ''
var RBout: list<string> = []
var RBerr: list<string> = []
var RWarn: list<string> = []

def g:RInitStdout(...args: list<any>)
    var rcmd = substitute(args[1], '[\r\n]', '', 'g')
    if RoutLine != ''
        rcmd = RoutLine .. rcmd
        if rcmd !~ "\x14"
            RoutLine = rcmd
            return
        endif
    endif
    if rcmd =~ '^RWarn: ' || rcmd =~ '^let ' || rcmd =~ '^echo ' || rcmd =~ '^call '
        if rcmd !~ "\x14"
            # R has sent an incomplete line
            RoutLine ..= rcmd
            return
        endif
        RoutLine = ''

        # In spite of flush(stdout()), rcmd might be concatenating two commands
        # (https://github.com/jalvesaq/Vim-R/issues/713)
        var rcmdl = split(rcmd, "\x14", 0)
        var cmd: string
        for rcmd_item in rcmdl
            cmd = rcmd_item
            if cmd == ''
                continue
            endif
            if cmd =~ '^RWarn: '
                RWarn += [substitute(cmd, '^RWarn: ', '', '')]
            elseif cmd =~ '^let '
                try
                    execute substitute(cmd, '^let ', '', '')
                catch
                    g:RWarningMsg("[Init R] " .. v:exception .. ": " .. cmd)
                endtry
            elseif cmd =~ '^echo ' || cmd =~ '^call '
                try
                    execute cmd
                catch
                    g:RWarningMsg("[Init R] " .. v:exception .. ": " .. cmd)
                endtry
                if cmd =~ '^echo'
                    redraw
                endif
            else
                RBout += [cmd]
            endif
        endfor
    else
        RBout += [rcmd]
    endif
enddef

def g:RInitStderr(...args: list<any>)
    RBerr += [substitute(args[1], '\r', '', 'g')]
enddef

# Check if the exit code of the script that built vimcom was zero and if the
# file vimcom_info seems to be OK (has three lines).
def g:RInitExit(...args: list<any>)
    var cnv_again = 0
    if args[1] == 0 || args[1] == 512  # ssh success seems to be 512
        g:StartNServer()
    elseif args[1] == 71
        # No writable directory to update vimcom
        # Avoid redraw of status line while waiting user input in MkRdir()
        RBerr += RWarn
        RWarn = []
        g:MkRdir()
    elseif args[1] == 72 && !has('win32') && !exists('g:rplugin._pkgbuild_attempt')
        # Vim-R/R/vimcom directory not found. Perhaps R running in remote machine...
        # Try to use local R to build the vimcom package.
        g:rplugin._pkgbuild_attempt = 1
        if executable("R")
            var shf = ['cd ' .. g:rplugin.tmpdir,
                        'R CMD build ' .. g:rplugin.home .. '/R/vimcom']
            writefile(shf, g:rplugin.tmpdir .. '/buildpkg.sh')
            var rout = system('sh ' .. g:rplugin.tmpdir .. '/buildpkg.sh')
            if v:shell_error == 0
                g:CheckVimcomVersion()
                cnv_again = 1
            endif
            delete(g:rplugin.tmpdir .. '/buildpkg.sh')
        endif
    else
        if filereadable(expand("~/.R/Makevars"))
            g:RWarningMsg("ERROR! Please, run :RDebugInfo for details, and check your '~/.R/Makevars'.")
        else
            g:RWarningMsg("ERROR: R exit code = " .. string(args[1]) .. "! Please, run :RDebugInfo for details.")
        endif
    endif
    g:rplugin.debug_info["before_nrs.R stderr"] = join(RBerr, "\n")
    g:rplugin.debug_info["before_nrs.R stdout"] = join(RBout, "\n")
    RBerr = []
    RBout = []
    g:AddForDeletion(g:rplugin.tmpdir .. "/bo_code.R")
    g:AddForDeletion(g:rplugin.localtmpdir .. "/libs_in_nrs_" .. $VIMR_ID)
    g:AddForDeletion(g:rplugin.tmpdir .. "/libnames_" .. $VIMR_ID)
    if len(RWarn) > 0
        g:rplugin.debug_info['RInit Warning'] = ''
        for wrn in RWarn
            g:rplugin.debug_info['RInit Warning'] ..= wrn .. "\n"
            g:RWarningMsg(wrn)
        endfor
    endif
    if cnv_again == 0
        g:rplugin.debug_info['Time']['before_nrs.R'] = reltimefloat(reltime(g:rplugin.debug_info['Time']['before_nrs.R'], reltime()))
    endif
enddef

def g:FindNCSpath(libdir: string): string
    var ncs: string
    if has('win32')
        ncs = 'vimrserver.exe'
    else
        ncs = 'vimrserver'
    endif
    if filereadable(libdir .. '/bin/' .. ncs)
        return libdir .. '/bin/' .. ncs
    elseif filereadable(libdir .. '/bin/x64/' .. ncs)
        return libdir .. '/bin/x64/' .. ncs
    elseif filereadable(libdir .. '/bin/i386/' .. ncs)
        return libdir .. '/bin/i386/' .. ncs
    endif

    g:RWarningMsg('Application "' .. ncs .. '" not found at "' .. libdir .. '"')
    return ''
enddef

# Check and set some variables and, finally, start the vimrserver
def g:StartNServer()
    if g:IsJobRunning("Server")
        return
    endif

    var nrs_path: string
    if exists("g:R_local_R_library_dir")
        nrs_path = g:FindNCSpath(g:R_local_R_library_dir .. '/vimcom')
    else
        if filereadable(g:rplugin.compldir .. '/vimcom_info')
            var info = readfile(g:rplugin.compldir .. '/vimcom_info')
            if len(info) == 3
                # Update vimcom information
                g:rplugin.vimcom_info = {'version': info[0], 'home': info[1], 'Rversion': info[2]}
                g:rplugin.debug_info['vimcom_info'] = g:rplugin.vimcom_info
                nrs_path = g:FindNCSpath(info[1])
            else
                delete(g:rplugin.compldir .. '/vimcom_info')
                g:RWarningMsg("ERROR in vimcom_info! Please, do :RDebugInfo for details.")
                return
            endif
        else
            g:RWarningMsg("ERROR: vimcom_info not found. Please, run :RDebugInfo for details.")
            return
        endif
    endif

    var ncspath = substitute(nrs_path, '/vimrserver.*', '', '')
    var ncs = substitute(nrs_path, '.*/vimrserver', 'vimrserver', '')

    # Some pdf viewers run vimrserver to send SyncTeX messages back to Vim
    if $PATH !~ ncspath
        if has('win32')
            $PATH = ncspath .. ';' .. $PATH
        else
            $PATH = ncspath .. ':' .. $PATH
        endif
    endif

    # Options in the vimrserver application are set through environment variables
    if g:R_objbr_opendf
        $VIMR_OPENDF = "TRUE"
    endif
    if g:R_objbr_openlist
        $VIMR_OPENLS = "TRUE"
    endif
    if g:R_objbr_allnames
        $VIMR_OBJBR_ALLNAMES = "TRUE"
    endif
    $VIMR_RPATH = g:rplugin.Rcmd

    $VIMR_LOCAL_TMPDIR = g:rplugin.localtmpdir

    # We have to set R's home directory on Window because vimrserver will
    # run R to build the list for omni completion.
    if has('win32')
        g:SetRHome()
    endif
    g:rplugin.jobs["Server"] = g:StartJob([ncs], g:rplugin.job_handlers)
    if has('win32')
        g:UnsetRHome()
    endif

    unlet $VIMR_OPENDF
    unlet $VIMR_OPENLS
    unlet $VIMR_OBJBR_ALLNAMES
    unlet $VIMR_RPATH
    unlet $VIMR_LOCAL_TMPDIR
enddef

def g:ListRLibsFromBuffer(): string
    if !exists("g:R_start_libs")
        g:R_start_libs = "base,stats,graphics,grDevices,utils,methods"
    endif

    var lines = getline(1, "$")
    filter(lines, (_, v) => v =~ '^\s*library\|require\s*(')
    map(lines, (_, v) => substitute(v, '\s*).*', '', ''))
    map(lines, (_, v) => substitute(v, '\s*,.*', '', ''))
    map(lines, (_, v) => substitute(v, '\s*\(library\|require\)\s*(\s*', '', ''))
    map(lines, (_, v) => substitute(v, "['" .. '"]', '', 'g'))
    map(lines, (_, v) => substitute(v, '\\', '', 'g'))
    var libs = ""
    if len(g:R_start_libs) > 4
        libs = '"' .. substitute(g:R_start_libs, ",", '", "', "g") .. '"'
    endif
    if len(lines) > 0
        if libs != ""
            libs ..= ", "
        endif
        libs ..= '"' .. join(lines, '", "') .. '"'
    endif
    return libs
enddef

# Get information from vimrserver (currently only the names of loaded libraries).
def g:RequestNCSInfo()
    g:JobStdin(g:rplugin.jobs["Server"], "42\n")
enddef

command RGetNCSInfo :call g:RequestNCSInfo()

# Callback function
def g:EchoNCSInfo(info: string)
    echo info
enddef

# Called by vimrserver when it gets error running R code
def g:ShowBuildOmnilsError(stt: string)
    if filereadable(g:rplugin.tmpdir .. '/run_R_stderr')
        var ferr = readfile(g:rplugin.tmpdir .. '/run_R_stderr')
        g:rplugin.debug_info['Error running R code'] = 'Exit status: ' .. stt .. "\n" .. join(ferr, "\n")
        g:RWarningMsg('Error building omnils_ file. Run :RDebugInfo for details.')
        delete(g:rplugin.tmpdir .. '/run_R_stderr')
        if g:rplugin.debug_info['Error running R code'] =~ "Error in library(.vimcom.).*there is no package called .*vimcom"
            # This will happen if the user manually changes .libPaths
            delete(g:rplugin.compldir .. "/vimcom_info")
            g:rplugin.debug_info['Error running R code'] ..= "\nPlease, restart " .. v:progname
        endif
    else
        g:RWarningMsg(g:rplugin.tmpdir .. '/run_R_stderr not found')
    endif
enddef

def g:BAAExit(...args: list<any>)
    if args[1] == 0 || args[1] == 512  # ssh success seems to be 512
        g:JobStdin(g:rplugin.jobs["Server"], "41\n")
    endif
enddef

def BuildAllArgs(_t: number = 0)
    if filereadable(g:rplugin.compldir .. '/args_lock')
        timer_start(5000, (t) => BuildAllArgs(t))
        return
    endif

    var flist = glob(g:rplugin.compldir .. '/omnils_*', false, true)
    map(flist, (_, v) => substitute(v, "/omnils_", "/args_", ""))
    var rscrpt = ['library("vimcom", warn.conflicts = FALSE)']
    for afile in flist
        if filereadable(afile) == 0
            var pkg = substitute(substitute(afile, ".*/args_", "", ""), "_.*", "", "")
            rscrpt += ['vimcom:::vim.buildargs("' .. afile .. '", "' .. pkg .. '")']
        endif
    endfor
    if len(rscrpt) == 1
        return
    endif
    writefile([""], g:rplugin.compldir .. '/args_lock')
    rscrpt += ['unlink("' .. g:rplugin.compldir .. '/args_lock")']

    var scrptnm = g:rplugin.tmpdir .. "/build_args.R"
    g:AddForDeletion(scrptnm)
    writefile(rscrpt, scrptnm)
    if exists("g:R_remote_compldir")
        scrptnm = g:R_remote_compldir .. "/tmp/build_args.R"
    endif
    var jobh = {'exit_cb': 'g:BAAExit'}
    g:rplugin.jobs["Build_args"] = g:StartJob([g:rplugin.Rcmd, "--quiet", "--no-save", "--no-restore", "--slave", "-f", scrptnm], jobh)
enddef

# This function is called for the first time before R is running because we
# support syntax highlighting and omni completion of default libraries' objects.
def g:UpdateSynRhlist()
    if !filereadable(g:rplugin.localtmpdir .. "/libs_in_nrs_" .. $VIMR_ID)
        return
    endif

    g:rplugin.libs_in_nrs = readfile(g:rplugin.localtmpdir .. "/libs_in_nrs_" .. $VIMR_ID)
    for lib in g:rplugin.libs_in_nrs
        g:AddToRhelpList(lib)
    endfor
    if exists("*FunHiOtherBf")
        # R/functions.vim will not be sourced if r_syntax_fun_pattern = 1
        g:FunHiOtherBf()
    endif
    # Building args_ files is too time consuming. Do it asynchronously.
    timer_start(1, (t) => BuildAllArgs(t))
enddef

# Filter words to :Rhelp
def g:RLisObjs(arglead: string, cmdline: string, curpos: number): list<string>
    var lob: list<string> = []
    var rkeyword = '^' .. arglead
    for xx in Rhelp_list
        if xx =~ rkeyword
            add(lob, xx)
        endif
    endfor
    return lob
enddef

var Rhelp_list: list<string> = []
var Rhelp_loaded: list<string> = []

# Add words to completion list of :Rhelp
def g:AddToRhelpList(lib: string)
    for lbr in Rhelp_loaded
        if lbr == lib
            return
        endif
    endfor
    Rhelp_loaded += [lib]

    var omf = g:rplugin.compldir .. '/omnils_' .. lib

    # List of objects
    var olist = readfile(omf)

    # Library setwidth has no functions
    if len(olist) == 0 || (len(olist) == 1 && len(olist[0]) < 3)
        return
    endif

    # List of objects for :Rhelp completion
    for xx in olist
        var xxx = split(xx, "\x06")
        if len(xxx) > 0 && xxx[0] !~ '\$'
            add(Rhelp_list, xxx[0])
        endif
    endfor
enddef

# The calls to system() and executable() below are in this script to run
# asynchronously and avoid slow startup.
# See https://github.com/jalvesaq/Vim-R/issues/625
if !executable(g:rplugin.R)
    g:RWarningMsg("R executable not found: '" .. g:rplugin.R .. "'")
endif

#==============================================================================
# Check for the existence of duplicated or obsolete code and deprecated options
#==============================================================================

# Check if Vim-R-plugin is installed
if exists("*WaitVimComStart")
    echohl WarningMsg
    input("Please, uninstall Vim-R-plugin before using Vim-R. [Press <Enter> to continue]")
    echohl None
endif

var ff = split(globpath(&rtp, "R/functions.vim"), '\n')
if len(ff) > 1
    def g:WarnDupVimR()
        var wff = split(globpath(&rtp, "R/functions.vim"), '\n')
        var msg = ["", "===   W A R N I N G   ===", "",
                    "It seems that Vim-R is installed in more than one place.",
                    "Please, remove one of them to avoid conflicts.",
                    "Below are the paths of the possibly duplicated installations:", ""]
        for ffd in wff
            msg += ["  " .. substitute(ffd, "R/functions.vim", "", "g")]
        endfor
        msg  += ["", "Please, uninstall one version of Vim-R.", ""]
        exe len(msg) .. "split Warning"
        setline(1, msg)
        setlocal bufhidden=wipe
        setlocal noswapfile
        set buftype=nofile
        set nomodified
        redraw
    enddef
    if v:vim_did_enter
        g:WarnDupVimR()
    else
        autocmd VimEnter * call g:WarnDupVimR()
    endif
endif

# 2017-02-07
if exists("g:R_vsplit")
    g:RWarningMsg("The option R_vsplit is deprecated. If necessary, use R_min_editor_width instead.")
endif

# 2017-03-14
if exists("g:R_ca_ck")
    g:RWarningMsg("The option R_ca_ck was renamed as R_clear_line. Please, update your vimrc.")
endif

# 2017-11-15
if len(g:R_latexcmd[0]) == 1
    g:RWarningMsg("The option R_latexcmd should be a list. Please update your vimrc.")
endif

# 2017-12-14
if hasmapto("<Plug>RCompleteArgs", "i")
    g:RWarningMsg("<Plug>RCompleteArgs no longer exists. Please, delete it from your vimrc.")
else
    # Delete <C-X><C-A> mapping in RCreateEditMaps()
    def g:RCompleteArgs(): list<any>
        stopinsert
        g:RWarningMsg("Completion of function arguments are now done by omni completion.")
        return []
    enddef
endif

# 2018-03-31
if exists('g:R_tmux_split')
    g:RWarningMsg('The option R_tmux_split no longer exists. Please see https://github.com/jalvesaq/Vim-R/blob/master/R/tmux_split.md')
endif

# 2020-05-18
if exists('g:R_complete')
    g:RWarningMsg("The option 'R_complete' no longer exists.")
endif
if exists('R_args_in_stline')
    g:RWarningMsg("The option 'R_args_in_stline' no longer exists.")
endif
if exists('R_sttline_fmt')
    g:RWarningMsg("The option 'R_sttline_fmt' no longer exists.")
endif
if exists('R_show_args')
    g:RWarningMsg("The option 'R_show_args' no longer exists.")
endif

# 2020-06-16
if exists('g:R_in_buffer')
    g:RWarningMsg('The option "R_in_buffer" was replaced with "R_external_term".')
endif
if exists('g:R_term')
    g:RWarningMsg('The option "R_term" was replaced with "R_external_term".')
endif
if exists('g:R_term_cmd')
    g:RWarningMsg('The option "R_term_cmd" was replaced with "R_external_term".')
endif

# 2023-06-03
if exists("g:R_auto_omni")
    g:RWarningMsg('R_auto_omni no longer exists. Use vim-mucomplete for auto completion.')
endif

# 2023-07-23
if exists('g:R_commented_lines')
    g:RWarningMsg('R_commented_lines no longer exists. See: https://github.com/jalvesaq/Vim-R/issues/743')
endif

# 2023-10-23
if exists('g:R_hi_fun_globenv')
    g:RWarningMsg('R_hi_fun_globenv no longer exists.')
endif
