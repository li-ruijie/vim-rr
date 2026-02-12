vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'r') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
if !exists('*g:GetRCmdBatchOutput')
    function g:GetRCmdBatchOutput(routfile, ...)
        if filereadable(a:routfile)
            if g:R_routnotab == 1
                exe "split " . a:routfile
                set filetype=rout
                exe "normal! \<c-w>\<c-p>"
            else
                exe "tabnew " . a:routfile
                set filetype=rout
                normal! gT
            endif
        else
            call g:RWarningMsg("The file '" . a:routfile . "' either does not exist or not readable.")
        endif
    endfunction
endif

# Run R CMD BATCH on current file and load the resulting .Rout in a split
# window
if !exists('*g:ShowRout')
    function g:ShowRout()
        let l:routfile = expand("%:r") . ".Rout"
        if bufloaded(l:routfile)
            exe "bunload " . l:routfile
            call delete(l:routfile)
        endif

        " if not silent, the user will have to type <Enter>
        silent update

        let rcmd = [g:rplugin.Rcmd, "CMD", "BATCH", "--no-restore", "--no-save", expand("%"),  l:routfile]
        let Cb = function('g:GetRCmdBatchOutput', [l:routfile])
        let rjob = job_start(rcmd, {'close_cb': Cb})
        let g:rplugin.jobs["R_CMD"] = rjob
    endfunction
endif

# Convert R script into Rmd, md and, then, html -- using knitr::spin()
if !exists('*g:RSpin')
    function g:RSpin()
        update
        let l:dir = substitute(expand("%:p:h"), '"', '\\"', 'g')
        let l:fname = substitute(expand("%:t"), '"', '\\"', 'g')
        call g:SendCmdToR('require(knitr); .vim_oldwd <- getwd(); setwd("' . l:dir . '"); spin("' . l:fname . '"); setwd(.vim_oldwd); rm(.vim_oldwd)')
    endfunction
endif

# Default IsInRCode function when the plugin is used as a global plugin
if !exists('*g:DefaultIsInRCode')
    function g:DefaultIsInRCode(vrb)
        return 1
    endfunction
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
