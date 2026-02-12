vim9script

# Only do this when not yet done for this buffer
if exists("b:did_ftplugin")
    finish
endif

# Don't load another plugin for this buffer
b:did_ftplugin = 1

g:rplugin.ob_upobcnt = 0

var cpo_save = &cpo
set cpo&vim

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
setlocal noswapfile
setlocal buftype=nofile
setlocal nowrap
setlocal iskeyword=@,48-57,_,.
setlocal nolist
setlocal nonumber
setlocal norelativenumber
setlocal nocursorline
setlocal nocursorcolumn
setlocal nospell

if !has_key(g:rplugin, "hasmenu")
    g:rplugin.hasmenu = 0
endif

# Popup menu
if !has_key(g:rplugin, 'ob_hasbrowsermenu')
    g:rplugin.ob_hasbrowsermenu = 0
endif

if !exists('*g:UpdateOB')
    function g:UpdateOB(what)
        if a:what == "both"
            let wht = g:rplugin.curview
        else
            let wht = a:what
        endif
        if g:rplugin.curview != wht
            return "curview != what"
        endif
        if g:rplugin.ob_upobcnt
            echoerr "OB called twice"
            return "OB called twice"
        endif
        let g:rplugin.ob_upobcnt = 1

        let rplugin_switchedbuf = 0
        let bufl = execute("buffers")
        if bufl !~ "Object_Browser"
            let g:rplugin.ob_upobcnt = 0
            return "Object_Browser not listed"
        endif

        try
            if wht == "GlobalEnv"
                let fcntt = readfile(g:rplugin.localtmpdir . "/globenv_" . $VIMR_ID)
            else
                let fcntt = readfile(g:rplugin.localtmpdir . "/liblist_" . $VIMR_ID)
            endif
        catch
            let g:rplugin.ob_upobcnt = 0
            return "Error reading OB file: " . v:exception
        endtry
        if has_key(g:rplugin, "curbuf") && g:rplugin.curbuf != "Object_Browser"
            let savesb = &switchbuf
            set switchbuf=useopen,usetab
            sil noautocmd sb Object_Browser
            let rplugin_switchedbuf = 1
        endif

        setlocal modifiable
        let curline = line(".")
        let curcol = col(".")
        let save_unnamed_reg = @@
        sil normal! ggdG
        let @@ = save_unnamed_reg
        call setline(1, fcntt)
        call cursor(curline, curcol)
        if bufname("%") =~ "Object_Browser"
            setlocal nomodifiable
        endif
        if rplugin_switchedbuf
            exe "sil noautocmd sb " . g:rplugin.curbuf
            exe "set switchbuf=" . savesb
        endif
        let g:rplugin.ob_upobcnt = 0
    endfunction
endif

if !exists('*g:RBrowserDoubleClick')
    function g:RBrowserDoubleClick()
        if line(".") == 2
            return
        endif
        if !g:IsJobRunning("Server")
            return
        endif

        " Toggle view: Objects in the workspace X List of libraries
        if line(".") == 1
            if g:rplugin.curview == "libraries"
                let g:rplugin.curview = "GlobalEnv"
                call g:JobStdin(g:rplugin.jobs["Server"], "31\n")
            else
                let g:rplugin.curview = "libraries"
                call g:JobStdin(g:rplugin.jobs["Server"], "321\n")
            endif
            return
        endif

        " Toggle state of list or data.frame: open X closed
        let key = g:RBrowserGetName()
        let curline = getline(".")
        if g:rplugin.curview == "GlobalEnv"
            if curline =~ "&#.*\t"
                call g:SendToVimcom("L", key)
            elseif curline =~ "\[#.*\t" || curline =~ "\$#.*\t" || curline =~ "<#.*\t" || curline =~ ":#.*\t"
                let key = substitute(key, '`', '', 'g')
                call g:JobStdin(g:rplugin.jobs["Server"], "33G" . key . "\n")
            else
                call g:SendCmdToR("str(" . key . ")")
            endif
        else
            if curline =~ "(#.*\t"
                let key = substitute(key, '`', '', 'g')
                call g:AskRDoc(key, g:RBGetPkgName(), 0)
            else
                if key =~ ":$" || curline =~ "\[#.*\t" || curline =~ "\$#.*\t" || curline =~ "<#.*\t" || curline =~ ":#.*\t"
                    call g:JobStdin(g:rplugin.jobs["Server"], "33L" . key . "\n")
                else
                    call g:SendCmdToR("str(" . key . ")")
                endif
            endif
        endif
    endfunction
endif

if !exists('*g:RBrowserRightClick')
    function g:RBrowserRightClick()
        if line(".") == 1
            return
        endif

        let key = g:RBrowserGetName()
        if key == ""
            return
        endif

        let line = getline(".")
        if line =~ "^   ##"
            return
        endif
        let isfunction = 0
        if line =~ "(#.*\t"
            let isfunction = 1
        endif

        if g:rplugin.ob_hasbrowsermenu == 1
            aunmenu ]RBrowser
        endif
        let key = substitute(key, '\.', '\\.', "g")
        let key = substitute(key, ' ', '\\ ', "g")

        exe 'amenu ]RBrowser.summary('. key . ') :call g:RAction("summary")<CR>'
        exe 'amenu ]RBrowser.str('. key . ') :call g:RAction("str")<CR>'
        exe 'amenu ]RBrowser.names('. key . ') :call g:RAction("names")<CR>'
        exe 'amenu ]RBrowser.plot('. key . ') :call g:RAction("plot")<CR>'
        exe 'amenu ]RBrowser.print(' . key . ') :call g:RAction("print")<CR>'
        amenu ]RBrowser.-sep01- <nul>
        exe 'amenu ]RBrowser.example('. key . ') :call g:RAction("example")<CR>'
        exe 'amenu ]RBrowser.help('. key . ') :call g:RAction("help")<CR>'
        if isfunction
            exe 'amenu ]RBrowser.args('. key . ') :call g:RAction("args")<CR>'
        endif
        popup ]RBrowser
        let g:rplugin.ob_hasbrowsermenu = 1
    endfunction
endif

if !exists('*g:RBGetPkgName')
    function g:RBGetPkgName()
        let lnum = line(".")
        while lnum > 0
            let line = getline(lnum)
            if line =~ '.*##[0-9a-zA-Z\.]*\t'
                let line = substitute(line, '.*##\(.\{-}\)\t.*', '\1', "")
                return line
            endif
            let lnum -= 1
        endwhile
        return ""
    endfunction
endif

if !exists('*g:RBrowserFindParent')
    function g:RBrowserFindParent(word, curline, curpos)
        let curline = a:curline
        let curpos = a:curpos
        while curline > 1 && curpos >= a:curpos
            let curline -= 1
            let line = substitute(getline(curline), "\x09.*", "", "")
            let curpos = stridx(line, '[#')
            if curpos == -1
                let curpos = stridx(line, '$#')
                if curpos == -1
                    let curpos = stridx(line, '<#')
                    if curpos == -1
                        let curpos = a:curpos
                    endif
                endif
            endif
        endwhile

        if g:rplugin.curview == "GlobalEnv"
            let spacelimit = 3
        else
            if g:rplugin.ob_isutf8
                let spacelimit = 10
            else
                let spacelimit = 6
            endif
        endif
        if curline > 1
            if line =~ ' <#'
                let suffix = '@'
            else
                let suffix = '$'
            endif
            let thisword = substitute(line, '^.\{-}#', '', '')
            if thisword =~ " " || thisword =~ '^[0-9_]' || thisword =~ g:rplugin.ob_punct
                let thisword = '`' . thisword . '`'
            endif
            let word = thisword . suffix . a:word
            if curpos != spacelimit
                let word = g:RBrowserFindParent(word, curline, curpos)
            endif
            return word
        else
            " Didn't find the parent: should never happen.
            let msg = "R-plugin Error: " . a:word . ":" . curline
            echoerr msg
        endif
        return ""
    endfunction
endif

if !exists('*g:RBrowserGetName')
    function g:RBrowserGetName()
        let line = getline(".")
        if line =~ "^$" || line(".") < 3
            return ""
        endif

        let curpos = stridx(line, "#")
        let word = substitute(line, '.\{-}\(.#\)\(.\{-}\)\t.*', '\2', '')

        if word =~ ' ' || word =~ '^[0-9]' || word =~ g:rplugin.ob_punct || word =~ '^' . g:rplugin.ob_reserved . '$'
            let word = '`' . word . '`'
        endif

        if curpos == 4
            " top level object
            let word = substitute(word, '\$\[\[', '[[', "g")
            if g:rplugin.curview == "libraries"
                return word . ':'
            else
                return word
            endif
        else
            if g:rplugin.curview == "libraries"
                if g:rplugin.ob_isutf8
                    if curpos == 11
                        let word = substitute(word, '\$\[\[', '[[', "g")
                        return word
                    endif
                elseif curpos == 7
                    let word = substitute(word, '\$\[\[', '[[', "g")
                    return word
                endif
            endif
            if curpos > 4
                " Find the parent data.frame or list
                let word = g:RBrowserFindParent(word, line("."), curpos - 1)
                let word = substitute(word, '\$\[\[', '[[', "g")
                return word
            else
                " Wrong object name delimiter: should never happen.
                let msg = "R-plugin Error: (curpos = " . curpos . ") " . word
                echoerr msg
                return ""
            endif
        endif
    endfunction
endif

if !exists('*g:OnOBBufUnload')
    function g:OnOBBufUnload()
        if g:rplugin.update_glbenv == 0 && exists('*g:SendToVimcom')
            call g:SendToVimcom("N", "OnOBBufUnload")
        endif
    endfunction
endif

if !exists('*g:PrintListTree')
    function g:PrintListTree()
        if g:IsJobRunning("Server")
            call g:JobStdin(g:rplugin.jobs["Server"], "37\n")
        endif
    endfunction
endif

nnoremap <buffer><silent> <CR> :call g:RBrowserDoubleClick()<CR>
nnoremap <buffer><silent> <2-LeftMouse> :call g:RBrowserDoubleClick()<CR>
nnoremap <buffer><silent> <RightMouse> :call g:RBrowserRightClick()<CR>

g:RControlMaps()

setlocal winfixwidth
setlocal bufhidden=wipe

if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:RControlMenu()
    g:RBrowserMenu()
endif

autocmd BufEnter <buffer> stopinsert
autocmd BufUnload <buffer> g:OnOBBufUnload()

g:rplugin.ob_reserved = '\(if\|else\|repeat\|while\|function\|for\|in\|next\|break\|TRUE\|FALSE\|NULL\|Inf\|NaN\|NA\|NA_integer_\|NA_real_\|NA_complex_\|NA_character_\)'
g:rplugin.ob_punct = '\(!\|''\|"\|#\|%\|&\|(\|)\|\*\|+\|,\|-\|/\|\\\|:\|;\|<\|=\|>\|?\|@\|\[\|/\|\]\|\^\|\$\|{\||\|}\|\~\)'

var envstring = tolower($LC_MESSAGES .. $LC_ALL .. $LANG)
if envstring =~ "utf-8" || envstring =~ "utf8"
    g:rplugin.ob_isutf8 = 1
else
    g:rplugin.ob_isutf8 = 0
endif

setline(1, ".GlobalEnv | Libraries")

&cpo = cpo_save

# vim: sw=4
