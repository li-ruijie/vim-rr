vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rmd') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
if exists('g:has_Rnvim')
    finish
endif

# Bibliographic completion
if index(g:R_bib_compl, &filetype) > -1
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/bibcompl.vim'
endif

g:R_rmdchunk = get(g:, "R_rmdchunk", 2)

if g:R_rmdchunk == 1 || g:R_rmdchunk == 2
    # Write code chunk in rnoweb files
    inoremap <buffer><silent> ` <Esc>:call g:RWriteRmdChunk()<CR>a
elseif type(g:R_rmdchunk) == v:t_string
    execute 'inoremap <buffer><silent> ' .. g:R_rmdchunk .. ' <Esc>:call g:RWriteRmdChunk()<CR>a'
endif

if !exists('*g:RWriteRmdChunk')
    function g:RWriteRmdChunk()
        if g:RmdIsInRCode(0) == 0
            if getline(".") =~ "^\\s*$"
                let curline = line(".")
                call setline(curline, "```{r}")
                if &filetype == 'quarto'
                    call append(curline, ["", "```", ""])
                    call cursor(curline + 1, 1)
                else
                    call append(curline, ["```", ""])
                    call cursor(curline, 5)
                endif
                return
            else
                if g:R_rmdchunk == 2
                    exe "normal! a`r `\<Esc>i"
                    return
                endif
            endif
        endif
        exe 'normal! a`'
    endfunction
endif

if !exists('*g:RmdGetYamlField')
    function g:RmdGetYamlField(field)
        let value = []
        let lastl = line('$')
        let idx = 2
        while idx < lastl
            let line = getline(idx)
            if line == '...' || line == '---'
                break
            endif
            if line =~ '^\s*' . a:field . '\s*:'
                let bstr = substitute(line, '^\s*' . a:field . '\s*:\s*\(.*\)\s*', '\1', '')
                if bstr =~ '^".*"$' || bstr =~ "^'.*'$"
                    let bib = substitute(bstr, '"', '', 'g')
                    let bib = substitute(bib, "'", '', 'g')
                    let bibl = [bib]
                elseif bstr =~ '^\[.*\]$'
                    try
                        let l:bbl = eval(bstr)
                    catch /.*/
                        call g:RWarningMsg('YAML line invalid for Vim: ' . line)
                        let bibl = []
                    endtry
                    if exists('l:bbl')
                        let bibl = l:bbl
                    endif
                else
                    let bibl = [bstr]
                endif
                for fn in bibl
                    call add(value, fn)
                endfor
                break
            endif
            let idx += 1
        endwhile
        if value == []
            return ''
        endif
        if a:field == "bibliography"
            call map(value, "expand(v:val)")
        endif
        return join(value, "\x06")
    endfunction
endif

if !exists('*g:RmdIsInPythonCode')
    function g:RmdIsInPythonCode(vrb)
        let chunkline = search("^[ \t]*```[ ]*{python", "bncW")
        let docline = search("^[ \t]*```$", "bncW")
        if chunkline > docline && chunkline != line(".")
            return 1
        else
            if a:vrb
                call g:RWarningMsg("Not inside a Python code chunk.")
            endif
            return 0
        endif
    endfunction
endif

if !exists('*g:RmdIsInRCode')
    function g:RmdIsInRCode(vrb)
        let chunkline = search("^[ \t]*```[ ]*{r", "bncW")
        let docline = search("^[ \t]*```$", "bncW")
        if chunkline == line(".")
            return 2
        elseif chunkline > docline
            return 1
        else
            if a:vrb
                call g:RWarningMsg("Not inside an R code chunk.")
            endif
            return 0
        endif
    endfunction
endif

if !exists('*g:RmdPreviousChunk')
    function g:RmdPreviousChunk() range
        let rg = range(a:firstline, a:lastline)
        let chunk = len(rg)
        for var in range(1, chunk)
            let curline = line(".")
            if g:RmdIsInRCode(0) == 1 || g:RmdIsInPythonCode(0)
                let i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
                if i != 0
                    call cursor(i-1, 1)
                endif
            endif
            let i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
            if i == 0
                call cursor(curline, 1)
                call g:RWarningMsg("There is no previous R code chunk to go.")
                return
            else
                call cursor(i+1, 1)
            endif
        endfor
        return
    endfunction
endif

if !exists('*g:RmdNextChunk')
    function g:RmdNextChunk() range
        let rg = range(a:firstline, a:lastline)
        let chunk = len(rg)
        for var in range(1, chunk)
            let i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW")
            if i == 0
                call g:RWarningMsg("There is no next R code chunk to go.")
                return
            else
                call cursor(i+1, 1)
            endif
        endfor
        return
    endfunction
endif

# Send Python chunk to R
if !exists('*g:SendRmdPyChunkToR')
    function g:SendRmdPyChunkToR(e, m)
        let chunkline = search("^[ \t]*```[ ]*{python", "bncW") + 1
        let docline = search("^[ \t]*```", "ncW") - 1
        let lines = getline(chunkline, docline)
        let ok = g:RSourceLines(lines, a:e, 'PythonCode')
        if ok == 0
            return
        endif
        if a:m == "down"
            call g:RmdNextChunk()
        endif
    endfunction
endif


# Send R chunk to R
if !exists('*g:SendRmdChunkToR')
    function g:SendRmdChunkToR(e, m)
        if g:RmdIsInRCode(0) == 2
            call cursor(line(".") + 1, 1)
        endif
        if g:RmdIsInRCode(0) != 1
            if g:RmdIsInPythonCode(0) == 0
                call g:RWarningMsg("Not inside an R code chunk.")
            else
                call g:SendRmdPyChunkToR(a:e, a:m)
            endif
            return
        endif
        let chunkline = search("^[ \t]*```[ ]*{r", "bncW") + 1
        let docline = search("^[ \t]*```", "ncW") - 1
        let lines = getline(chunkline, docline)
        let ok = g:RSourceLines(lines, a:e, "chunk")
        if ok == 0
            return
        endif
        if a:m == "down"
            call g:RmdNextChunk()
        endif
    endfunction
endif

if !exists('*g:RmdNonRCompletion')
    function g:RmdNonRCompletion(findstart, base)
        if g:RmdIsInPythonCode(0) && exists('*jedi#completions')
            return jedi#completions(a:findstart, a:base)
        endif

        if b:rplugin_bibf != ''
            if a:findstart
                let line = getline(".")
                let cpos = getpos(".")
                let idx = cpos[2] -2
                while line[idx] =~ '\w' && idx > 0
                    let idx -= 1
                endwhile
                return idx + 1
            else
                let citekey = substitute(a:base, '^@', '', '')
                return RCompleteBib(citekey)
            endif
        endif

        if exists('*zotcite#CompleteBib')
            return zotcite#CompleteBib(a:findstart, a:base)
        endif

        if exists('*pandoc#completion#Complete')
            return pandoc#completion#Complete(a:findstart, a:base)
        endif

        if a:findstart
            return 0
        else
            return []
        endif
    endfunction
endif

b:rplugin_non_r_omnifunc = "RmdNonRCompletion"
if !exists('b:rplugin_bibf')
    b:rplugin_bibf = ''
endif

if g:R_non_r_compl && index(g:R_bib_compl, &filetype) > -1
    timer_start(1, 'g:CheckPyBTeX')
endif

b:IsInRCode = function('g:RmdIsInRCode')
b:PreviousRChunk = function('g:RmdPreviousChunk')
b:NextRChunk = function('g:RmdNextChunk')
b:SendChunkToR = function('g:SendRmdChunkToR')

b:rplugin_knitr_pattern = "^``` *{.*}$"

#==========================================================================
# Key bindings and menu items

g:RCreateStartMaps()
g:RCreateEditMaps()
g:RCreateSendMaps()
g:RControlMaps()
g:RCreateMaps('nvi', 'RSetwd', 'rd', ':call g:RSetWD()')

# Only .Rmd and .qmd files use these functions:
g:RCreateMaps('nvi', 'RKnit',           'kn', ':call g:RKnit()')
g:RCreateMaps('ni',  'RSendChunk',      'cc', ':call b:SendChunkToR("silent", "stay")')
g:RCreateMaps('ni',  'RESendChunk',     'ce', ':call b:SendChunkToR("echo", "stay")')
g:RCreateMaps('ni',  'RDSendChunk',     'cd', ':call b:SendChunkToR("silent", "down")')
g:RCreateMaps('ni',  'REDSendChunk',    'ca', ':call b:SendChunkToR("echo", "down")')
g:RCreateMaps('n',   'RNextRChunk',     'gn', ':call b:NextRChunk()')
g:RCreateMaps('n',   'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

g:RSourceOtherScripts()

if !exists('*g:RPDFinit')
    function g:RPDFinit(...)
        exe "source " . substitute(g:rplugin.home, " ", "\\ ", "g") . "/R/pdf_init.vim"
    endfunction
endif

timer_start(1, 'g:RPDFinit')

if exists("b:undo_ftplugin")
    b:undo_ftplugin ..= " | unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR"
else
    b:undo_ftplugin = "unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR"
endif
