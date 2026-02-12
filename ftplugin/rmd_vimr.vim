vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rmd') == -1 && index(g:R_filetypes, 'quarto') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
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

if !exists("g:did_vimr_rmd_functions")
    g:did_vimr_rmd_functions = 1

    def g:RWriteRmdChunk()
        if g:RmdIsInRCode(0) == 0
            if getline(".") =~ "^\\s*$"
                var curline = line(".")
                setline(curline, "```{r}")
                if &filetype == 'quarto'
                    append(curline, ["", "```", ""])
                    cursor(curline + 1, 1)
                else
                    append(curline, ["```", ""])
                    cursor(curline, 5)
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
    enddef

    def g:RmdGetYamlField(field: string): string
        var value: list<string> = []
        var lastl = line('$')
        var idx = 2
        while idx < lastl
            var line = getline(idx)
            if line == '...' || line == '---'
                break
            endif
            if line =~ '^\s*' .. field .. '\s*:'
                var bstr = substitute(line, '^\s*' .. field .. '\s*:\s*\(.*\)\s*', '\1', '')
                var bibl: list<string> = []
                if bstr =~ '^".*"$' || bstr =~ "^'.*'$"
                    var bib = substitute(bstr, '"', '', 'g')
                    bib = substitute(bib, "'", '', 'g')
                    bibl = [bib]
                elseif bstr =~ '^\[.*\]$'
                    try
                        bibl = eval(bstr)
                    catch /.*/
                        g:RWarningMsg('YAML line invalid for Vim: ' .. line)
                        bibl = []
                    endtry
                else
                    bibl = [bstr]
                endif
                for fn in bibl
                    add(value, fn)
                endfor
                break
            endif
            idx += 1
        endwhile
        if value == []
            return ''
        endif
        if field == "bibliography"
            map(value, (_, v) => expand(v))
        endif
        return join(value, "\x06")
    enddef

    def g:RmdIsInPythonCode(vrb: number): number
        var chunkline = search("^[ \t]*```[ ]*{python", "bncW")
        var docline = search("^[ \t]*```$", "bncW")
        if chunkline > docline && chunkline != line(".")
            return 1
        else
            if vrb
                g:RWarningMsg("Not inside a Python code chunk.")
            endif
            return 0
        endif
    enddef

    def g:RmdIsInRCode(vrb: number): number
        var chunkline = search("^[ \t]*```[ ]*{r", "bncW")
        var docline = search("^[ \t]*```$", "bncW")
        if chunkline == line(".")
            return 2
        elseif chunkline > docline
            return 1
        else
            if vrb
                g:RWarningMsg("Not inside an R code chunk.")
            endif
            return 0
        endif
    enddef

    def g:RmdPreviousChunk(count: number = 1)
        for _ in range(1, count)
            var curline = line(".")
            if g:RmdIsInRCode(0) == 1 || g:RmdIsInPythonCode(0)
                var i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
                if i != 0
                    cursor(i - 1, 1)
                endif
            endif
            var i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
            if i == 0
                cursor(curline, 1)
                g:RWarningMsg("There is no previous R code chunk to go.")
                return
            else
                cursor(i + 1, 1)
            endif
        endfor
    enddef

    def g:RmdNextChunk(count: number = 1)
        for _ in range(1, count)
            var i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW")
            if i == 0
                g:RWarningMsg("There is no next R code chunk to go.")
                return
            else
                cursor(i + 1, 1)
            endif
        endfor
    enddef

    # Send Python chunk to R
    def g:SendRmdPyChunkToR(e: string, m: string)
        var chunkline = search("^[ \t]*```[ ]*{python", "bncW") + 1
        var docline = search("^[ \t]*```", "ncW") - 1
        var lines = getline(chunkline, docline)
        var ok = g:RSourceLines(lines, e, 'PythonCode')
        if ok == 0
            return
        endif
        if m == "down"
            g:RmdNextChunk()
        endif
    enddef

    # Send R chunk to R
    def g:SendRmdChunkToR(e: string, m: string)
        if g:RmdIsInRCode(0) == 2
            cursor(line(".") + 1, 1)
        endif
        if g:RmdIsInRCode(0) != 1
            if g:RmdIsInPythonCode(0) == 0
                g:RWarningMsg("Not inside an R code chunk.")
            else
                g:SendRmdPyChunkToR(e, m)
            endif
            return
        endif
        var chunkline = search("^[ \t]*```[ ]*{r", "bncW") + 1
        var docline = search("^[ \t]*```", "ncW") - 1
        var lines = getline(chunkline, docline)
        var ok = g:RSourceLines(lines, e, "chunk")
        if ok == 0
            return
        endif
        if m == "down"
            g:RmdNextChunk()
        endif
    enddef

    def g:RmdNonRCompletion(findstart: number, base: string): any
        if g:RmdIsInPythonCode(0) && exists('*jedi#completions')
            return jedi#completions(findstart, base)
        endif

        if b:rplugin_bibf != ''
            if findstart
                var line = getline(".")
                var cpos = getpos(".")
                var idx = cpos[2] - 2
                while line[idx] =~ '\w' && idx > 0
                    idx -= 1
                endwhile
                return idx + 1
            else
                var citekey = substitute(base, '^@', '', '')
                return g:RCompleteBib(citekey)
            endif
        endif

        if exists('*zotcite#CompleteBib')
            return zotcite#CompleteBib(findstart, base)
        endif

        if exists('*pandoc#completion#Complete')
            return pandoc#completion#Complete(findstart, base)
        endif

        if findstart
            return 0
        else
            return []
        endif
    enddef
endif

b:rplugin_non_r_omnifunc = "g:RmdNonRCompletion"
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
g:RCreateMaps('n',   'RNextRChunk',     'gn', ':call b:NextRChunk(v:count1)')
g:RCreateMaps('n',   'RPreviousRChunk', 'gN', ':call b:PreviousRChunk(v:count1)')

# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

g:RSourceOtherScripts()

if !exists('*g:RPDFinit')
    def g:RPDFinit(...args: list<any>)
        exe "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/pdf_init.vim"
    enddef
endif

timer_start(1, 'g:RPDFinit')

if exists("b:undo_ftplugin")
    b:undo_ftplugin ..= " | unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR b:rplugin_non_r_omnifunc b:rplugin_bibf b:rplugin_knitr_pattern"
else
    b:undo_ftplugin = "unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR b:rplugin_non_r_omnifunc b:rplugin_bibf b:rplugin_knitr_pattern"
endif
