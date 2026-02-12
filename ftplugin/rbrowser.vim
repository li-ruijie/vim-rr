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

if !exists("g:did_vimr_rbrowser_functions")
    g:did_vimr_rbrowser_functions = 1

    def g:UpdateOB(what: string): string
        var wht: string
        if what == "both"
            wht = g:rplugin.curview
        else
            wht = what
        endif
        if g:rplugin.curview != wht
            return "curview != what"
        endif
        if g:rplugin.ob_upobcnt
            echoerr "OB called twice"
            return "OB called twice"
        endif
        g:rplugin.ob_upobcnt = 1

        var rplugin_switchedbuf = 0
        var savesb: string
        var bufl = execute("buffers")
        if bufl !~ "Object_Browser"
            g:rplugin.ob_upobcnt = 0
            return "Object_Browser not listed"
        endif

        var fcntt: list<string>
        try
            if wht == "GlobalEnv"
                fcntt = readfile(g:rplugin.localtmpdir .. "/globenv_" .. $VIMR_ID)
            else
                fcntt = readfile(g:rplugin.localtmpdir .. "/liblist_" .. $VIMR_ID)
            endif
        catch
            g:rplugin.ob_upobcnt = 0
            return "Error reading OB file: " .. v:exception
        endtry
        if has_key(g:rplugin, "curbuf") && g:rplugin.curbuf != "Object_Browser"
            savesb = &switchbuf
            set switchbuf=useopen,usetab
            sil noautocmd sb Object_Browser
            rplugin_switchedbuf = 1
        endif

        setlocal modifiable
        var curline = line(".")
        var curcol = col(".")
        var save_unnamed_reg = @@
        sil normal! ggdG
        @@ = save_unnamed_reg
        setline(1, fcntt)
        cursor(curline, curcol)
        if bufname("%") =~ "Object_Browser"
            setlocal nomodifiable
        endif
        if rplugin_switchedbuf
            exe "sil noautocmd sb " .. g:rplugin.curbuf
            exe "set switchbuf=" .. savesb
        endif
        g:rplugin.ob_upobcnt = 0
        return ""
    enddef

    def g:RBrowserDoubleClick()
        if line(".") == 2
            return
        endif
        if !g:IsJobRunning("Server")
            return
        endif

        # Toggle view: Objects in the workspace X List of libraries
        if line(".") == 1
            if g:rplugin.curview == "libraries"
                g:rplugin.curview = "GlobalEnv"
                g:JobStdin(g:rplugin.jobs["Server"], "31\n")
            else
                g:rplugin.curview = "libraries"
                g:JobStdin(g:rplugin.jobs["Server"], "321\n")
            endif
            return
        endif

        # Toggle state of list or data.frame: open X closed
        var key = g:RBrowserGetName()
        var curline = getline(".")
        if g:rplugin.curview == "GlobalEnv"
            if curline =~ "&#.*\t"
                g:SendToVimcom("L", key)
            elseif curline =~ "\[#.*\t" || curline =~ "\$#.*\t" || curline =~ "<#.*\t" || curline =~ ":#.*\t"
                key = substitute(key, '`', '', 'g')
                g:JobStdin(g:rplugin.jobs["Server"], "33G" .. key .. "\n")
            else
                g:SendCmdToR("str(" .. key .. ")")
            endif
        else
            if curline =~ "(#.*\t"
                key = substitute(key, '`', '', 'g')
                g:AskRDoc(key, g:RBGetPkgName(), 0)
            else
                if key =~ ":$" || curline =~ "\[#.*\t" || curline =~ "\$#.*\t" || curline =~ "<#.*\t" || curline =~ ":#.*\t"
                    g:JobStdin(g:rplugin.jobs["Server"], "33L" .. key .. "\n")
                else
                    g:SendCmdToR("str(" .. key .. ")")
                endif
            endif
        endif
    enddef

    def g:RBrowserRightClick()
        if line(".") == 1
            return
        endif

        var key = g:RBrowserGetName()
        if key == ""
            return
        endif

        var line = getline(".")
        if line =~ "^   ##"
            return
        endif
        var isfunction = 0
        if line =~ "(#.*\t"
            isfunction = 1
        endif

        if g:rplugin.ob_hasbrowsermenu == 1
            aunmenu ]RBrowser
        endif
        key = substitute(key, '\.', '\\.', "g")
        key = substitute(key, ' ', '\\ ', "g")

        exe 'amenu ]RBrowser.summary(' .. key .. ') :call g:RAction("summary")<CR>'
        exe 'amenu ]RBrowser.str(' .. key .. ') :call g:RAction("str")<CR>'
        exe 'amenu ]RBrowser.names(' .. key .. ') :call g:RAction("names")<CR>'
        exe 'amenu ]RBrowser.plot(' .. key .. ') :call g:RAction("plot")<CR>'
        exe 'amenu ]RBrowser.print(' .. key .. ') :call g:RAction("print")<CR>'
        amenu ]RBrowser.-sep01- <nul>
        exe 'amenu ]RBrowser.example(' .. key .. ') :call g:RAction("example")<CR>'
        exe 'amenu ]RBrowser.help(' .. key .. ') :call g:RAction("help")<CR>'
        if isfunction
            exe 'amenu ]RBrowser.args(' .. key .. ') :call g:RAction("args")<CR>'
        endif
        popup ]RBrowser
        g:rplugin.ob_hasbrowsermenu = 1
    enddef

    def g:RBGetPkgName(): string
        var lnum = line(".")
        while lnum > 0
            var line = getline(lnum)
            if line =~ '.*##[0-9a-zA-Z\.]*\t'
                return substitute(line, '.*##\(.\{-}\)\t.*', '\1', "")
            endif
            lnum -= 1
        endwhile
        return ""
    enddef

    def g:RBrowserFindParent(word: string, curline: number, curpos: number): string
        var cl = curline
        var cp = curpos
        var line: string
        while cl > 1 && cp >= curpos
            cl -= 1
            line = substitute(getline(cl), "\x09.*", "", "")
            cp = stridx(line, '[#')
            if cp == -1
                cp = stridx(line, '$#')
                if cp == -1
                    cp = stridx(line, '<#')
                    if cp == -1
                        cp = curpos
                    endif
                endif
            endif
        endwhile

        var spacelimit: number
        if g:rplugin.curview == "GlobalEnv"
            spacelimit = 3
        else
            if g:rplugin.ob_isutf8
                spacelimit = 10
            else
                spacelimit = 6
            endif
        endif
        if cl > 1
            var suffix: string
            if line =~ ' <#'
                suffix = '@'
            else
                suffix = '$'
            endif
            var thisword = substitute(line, '^.\{-}#', '', '')
            if thisword =~ " " || thisword =~ '^[0-9_]' || thisword =~ g:rplugin.ob_punct
                thisword = '`' .. thisword .. '`'
            endif
            var result = thisword .. suffix .. word
            if cp != spacelimit
                result = g:RBrowserFindParent(result, cl, cp)
            endif
            return result
        else
            # Didn't find the parent: should never happen.
            var msg = "R-plugin Error: " .. word .. ":" .. string(cl)
            echoerr msg
        endif
        return ""
    enddef

    def g:RBrowserGetName(): string
        var line = getline(".")
        if line =~ "^$" || line(".") < 3
            return ""
        endif

        var curpos = stridx(line, "#")
        var word = substitute(line, '.\{-}\(.#\)\(.\{-}\)\t.*', '\2', '')

        if word =~ ' ' || word =~ '^[0-9]' || word =~ g:rplugin.ob_punct || word =~ '^' .. g:rplugin.ob_reserved .. '$'
            word = '`' .. word .. '`'
        endif

        if curpos == 4
            # top level object
            word = substitute(word, '\$\[\[', '[[', "g")
            if g:rplugin.curview == "libraries"
                return word .. ':'
            else
                return word
            endif
        else
            if g:rplugin.curview == "libraries"
                if g:rplugin.ob_isutf8
                    if curpos == 11
                        word = substitute(word, '\$\[\[', '[[', "g")
                        return word
                    endif
                elseif curpos == 7
                    word = substitute(word, '\$\[\[', '[[', "g")
                    return word
                endif
            endif
            if curpos > 4
                # Find the parent data.frame or list
                word = g:RBrowserFindParent(word, line("."), curpos - 1)
                word = substitute(word, '\$\[\[', '[[', "g")
                return word
            else
                # Wrong object name delimiter: should never happen.
                var msg = "R-plugin Error: (curpos = " .. string(curpos) .. ") " .. word
                echoerr msg
                return ""
            endif
        endif
    enddef

    def g:OnOBBufUnload()
        if g:rplugin.update_glbenv == 0 && exists('*g:SendToVimcom')
            g:SendToVimcom("N", "OnOBBufUnload")
        endif
    enddef

    def g:PrintListTree()
        if g:IsJobRunning("Server")
            g:JobStdin(g:rplugin.jobs["Server"], "37\n")
        endif
    enddef
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
