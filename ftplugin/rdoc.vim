vim9script

# Only do this when not yet done for this buffer
if exists("b:did_rdoc_ftplugin")
    finish
endif

# Don't load another plugin for this buffer
b:did_rdoc_ftplugin = 1

var cpo_save = &cpo
set cpo&vim

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
setlocal iskeyword=@,48-57,_,.

if !exists("g:did_vimr_rdoc_functions")
    g:did_vimr_rdoc_functions = 1

    # Prepare R documentation output to be displayed by Vim
    def g:FixRdoc()
        var lnr = line("$")
        for ii in range(1, lnr)
            var lii = getline(ii)
            lii = substitute(lii, "_\010", "", "g")
            lii = substitute(lii, '<URL: \(.\{-}\)>', ' |\1|', 'g')
            lii = substitute(lii, '<email: \(.\{-}\)>', ' |\1|', 'g')
            if &encoding == "utf-8"
                lii = substitute(lii, "\x91", "'", 'g')
                lii = substitute(lii, "\x92", "'", 'g')
            endif
            setline(ii, lii)
        endfor

        # Mark the end of Examples
        var exline = search("^Examples:$", "nw")
        if exline
            if getline("$") !~ "^###$"
                setline(line("$") + 1, '###')
            endif
        endif

        # Add a tab character at the end of the Arguments section to mark its end.
        var argline = search("^Arguments:$", "nw")
        if argline
            # A space after 'Arguments:' is necessary for correct syntax highlight
            # of the first argument
            setline(argline, "Arguments: ")
            var doclength = line("$")
            var cur = argline + 2
            var lin = getline(cur)
            while lin !~ "^[A-Z].*:$" && cur < doclength
                cur += 1
                lin = getline(cur)
            endwhile
            if cur < doclength
                cur -= 1
                if getline(cur) =~ "^$"
                    setline(cur, " \t")
                endif
            endif
        endif

        # Add a tab character at the end of the Usage section to mark its end.
        var usageline = search("^Usage:$", "nw")
        if usageline
            var doclength = line("$")
            var cur = usageline + 2
            var lin = getline(cur)
            while lin !~ "^[A-Z].*:" && cur < doclength
                cur += 1
                lin = getline(cur)
            endwhile
            if cur < doclength
                cur -= 1
                if getline(cur) =~ "^ *$"
                    setline(cur, "\t")
                endif
            endif
        endif

        normal! gg

        # Clear undo history
        var old_undolevels = &undolevels
        setlocal undolevels=-1
        exe "normal a \<BS>\<Esc>"
        &undolevels = old_undolevels
    enddef

    def g:RdocIsInRCode(vrb: number): number
        var exline = search("^Examples:$", "bncW")
        if exline > 0 && line(".") > exline
            return 1
        else
            if vrb
                g:RWarningMsg('Not in the "Examples" section.')
            endif
            return 0
        endif
    enddef

    def g:RDocExSection()
        var exline = search("^Examples:$", "nW")
        if exline == 0
            g:RWarningMsg("No example section below.")
            return
        else
            cursor(exline + 1, 1)
        endif
    enddef
endif

b:IsInRCode = function('g:RdocIsInRCode')

#==========================================================================
# Key bindings and menu items

g:RCreateSendMaps()
g:RControlMaps()

# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

nnoremap <buffer><silent> ge :call g:RDocExSection()<CR>
nnoremap <buffer><silent> q :q<CR>

setlocal bufhidden=wipe
setlocal nonumber
setlocal noswapfile
setlocal buftype=nofile
autocmd VimResized <buffer> g:R_newsize = 1
g:FixRdoc()
autocmd FileType <buffer> g:FixRdoc()

&cpo = cpo_save

# vim: sw=4
