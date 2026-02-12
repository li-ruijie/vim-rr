vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'r') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'

if !exists("g:did_vimr_r_functions")
    g:did_vimr_r_functions = 1

    def g:GetRCmdBatchOutput(routfile: string, ...extra: list<any>)
        if filereadable(routfile)
            if g:R_routnotab == 1
                exe "split " .. routfile
                setlocal filetype=rout
                exe "normal! \<c-w>\<c-p>"
            else
                exe "tabnew " .. routfile
                setlocal filetype=rout
                normal! gT
            endif
        else
            g:RWarningMsg("The file '" .. routfile .. "' either does not exist or not readable.")
        endif
    enddef

    # Run R CMD BATCH on current file and load the resulting .Rout in a split
    # window
    def g:ShowRout()
        var routfile = expand("%:r") .. ".Rout"
        if bufloaded(routfile)
            exe "bunload " .. routfile
            delete(routfile)
        endif

        # if not silent, the user will have to type <Enter>
        silent update

        var rcmd = [g:rplugin.Rcmd, "CMD", "BATCH", "--no-restore", "--no-save", expand("%"), routfile]
        var Cb = function('g:GetRCmdBatchOutput', [routfile])
        var rjob = job_start(rcmd, {close_cb: Cb})
        g:rplugin.jobs["R_CMD"] = rjob
    enddef

    # Convert R script into Rmd, md and, then, html -- using knitr::spin()
    def g:RSpin()
        update
        var dir = substitute(expand("%:p:h"), '"', '\\"', 'g')
        var fname = substitute(expand("%:t"), '"', '\\"', 'g')
        g:SendCmdToR('require(knitr); .vim_oldwd <- getwd(); setwd("' .. dir .. '"); spin("' .. fname .. '"); setwd(.vim_oldwd); rm(.vim_oldwd)')
    enddef

    # Default IsInRCode function when the plugin is used as a global plugin
    def g:DefaultIsInRCode(vrb: number): number
        return 1
    enddef
endif

b:IsInRCode = function('g:DefaultIsInRCode')

#==========================================================================
# Key bindings and menu items

g:RCreateStartMaps()
g:RCreateEditMaps()

# Only .R files are sent to R
g:RCreateMaps('ni', 'RSendFile',  'aa', ':call g:SendFileToR("silent")')
g:RCreateMaps('ni', 'RESendFile', 'ae', ':call g:SendFileToR("echo")')
g:RCreateMaps('ni', 'RShowRout',  'ao', ':call g:ShowRout()')

# Knitr::spin
g:RCreateMaps('ni', 'RSpinFile',  'ks', ':call g:RSpin()')

g:RCreateSendMaps()
g:RControlMaps()
g:RCreateMaps('nvi', 'RSetwd',    'rd', ':call g:RSetWD()')


# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

g:RSourceOtherScripts()

if exists("b:undo_ftplugin")
    b:undo_ftplugin ..= " | unlet! b:IsInRCode"
else
    b:undo_ftplugin = "unlet! b:IsInRCode"
endif
