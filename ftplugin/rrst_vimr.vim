vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rrst') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
if exists('g:has_Rnvim')
    finish
endif

if !exists('*g:RrstIsInRCode')
    function g:RrstIsInRCode(vrb)
        let chunkline = search("^\\.\\. {r", "bncW")
        let docline = search("^\\.\\. \\.\\.", "bncW")
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

if !exists('*g:RrstPreviousChunk')
    function g:RrstPreviousChunk() range
        let rg = range(a:firstline, a:lastline)
        let chunk = len(rg)
        for var in range(1, chunk)
            let curline = line(".")
            if g:RrstIsInRCode(0) == 1
                let i = search("^\\.\\. {r", "bnW")
                if i != 0
                    call cursor(i - 1, 1)
                endif
            endif
            let i = search("^\\.\\. {r", "bnW")
            if i == 0
                call cursor(curline, 1)
                call g:RWarningMsg("There is no previous R code chunk to go.")
                return
            else
                call cursor(i + 1, 1)
            endif
        endfor
        return
    endfunction
endif

if !exists('*g:RrstNextChunk')
    function g:RrstNextChunk() range
        let rg = range(a:firstline, a:lastline)
        let chunk = len(rg)
        for var in range(1, chunk)
            let i = search("^\\.\\. {r", "nW")
            if i == 0
                call g:RWarningMsg("There is no next R code chunk to go.")
                return
            else
                call cursor(i + 1, 1)
            endif
        endfor
        return
    endfunction
endif

if !exists('*g:RMakeHTMLrrst')
    function g:RMakeHTMLrrst(t)
        call g:RSetWD()
        update
        if g:rplugin.rrst_has_rst2pdf == 0
            if executable("rst2pdf")
                let g:rplugin.rrst_has_rst2pdf = 1
            else
                call g:RWarningMsg("Is 'rst2pdf' application installed? Cannot convert into HTML/ODT: 'rst2pdf' executable not found.")
                return
            endif
        endif

        let rcmd = 'require(knitr)'
        if g:R_strict_rst
            let rcmd = rcmd . '; render_rst(strict=TRUE)'
        endif
        let rcmd = rcmd . '; knit("' . expand("%:t") . '")'

        if a:t == "odt"
            let rcmd = rcmd . '; system("rst2odt ' . expand("%:r:t") . ".rst " . expand("%:r:t") . '.odt")'
        else
            let rcmd = rcmd . '; system("rst2html ' . expand("%:r:t") . ".rst " . expand("%:r:t") . '.html")'
        endif

        if g:R_openhtml && a:t == "html"
            let rcmd = rcmd . '; browseURL("' . expand("%:r:t") . '.html")'
        endif
        call g:SendCmdToR(rcmd)
    endfunction
endif

if !exists('*g:RMakePDFrrst')
    function g:RMakePDFrrst()
        if !has_key(g:rplugin, "pdfviewer")
            call g:RSetPDFViewer()
        endif

        update
        call g:RSetWD()
        if g:rplugin.rrst_has_rst2pdf == 0
            if exists("g:R_rst2pdfpath") && executable(g:R_rst2pdfpath)
                let g:rplugin.rrst_has_rst2pdf = 1
            elseif executable("rst2pdf")
                let g:rplugin.rrst_has_rst2pdf = 1
            else
                call g:RWarningMsg("Is 'rst2pdf' application installed? Cannot convert into PDF: 'rst2pdf' executable not found.")
                return
            endif
        endif

        let rrstdir = expand("%:p:h")
        if has("win32")
            let rrstdir = substitute(rrstdir, '\\', '/', 'g')
        endif
        let pdfcmd = 'vim.interlace.rrst("' . expand("%:t") . '", rrstdir = "' . rrstdir . '"'
        if exists("g:R_rrstcompiler")
            let pdfcmd = pdfcmd . ", compiler='" . g:R_rrstcompiler . "'"
        endif
        if exists("g:R_knitargs")
            let pdfcmd = pdfcmd . ", " . g:R_knitargs
        endif
        if exists("g:R_rst2pdfpath")
            let pdfcmd = pdfcmd . ", rst2pdfpath='" . g:R_rst2pdfpath . "'"
        endif
        if exists("g:R_rst2pdfargs")
            let pdfcmd = pdfcmd . ", " . g:R_rst2pdfargs
        endif
        let pdfcmd = pdfcmd . ")"
        let ok = g:SendCmdToR(pdfcmd)
        if ok == 0
            return
        endif
    endfunction
endif

# Send Rrst chunk to R
if !exists('*g:SendRrstChunkToR')
    function g:SendRrstChunkToR(e, m)
        if g:RrstIsInRCode(0) == 2
            call cursor(line(".") + 1, 1)
        elseif g:RrstIsInRCode(0) != 1
            call g:RWarningMsg("Not inside an R code chunk.")
            return
        endif
        let chunkline = search("^\\.\\. {r", "bncW") + 1
        let docline = search("^\\.\\. \\.\\.", "ncW") - 1
        let lines = getline(chunkline, docline)
        let ok = g:RSourceLines(lines, a:e, "chunk")
        if ok == 0
            return
        endif
        if a:m == "down"
            call g:RrstNextChunk()
        endif
    endfunction
endif

b:IsInRCode = function('g:RrstIsInRCode')
b:PreviousRChunk = function('g:RrstPreviousChunk')
b:NextRChunk = function('g:RrstNextChunk')
b:SendChunkToR = function('g:SendRrstChunkToR')

b:rplugin_knitr_pattern = "^.. {r.*}$"

#==========================================================================
# Key bindings and menu items

g:RCreateStartMaps()
g:RCreateEditMaps()
g:RCreateSendMaps()
g:RControlMaps()
g:RCreateMaps('nvi', 'RSetwd',          'rd', ':call g:RSetWD()')

# Only .Rrst files use these functions:
g:RCreateMaps('nvi', 'RKnit',           'kn', ':call g:RKnit()')
g:RCreateMaps('nvi', 'RMakePDFK',       'kp', ':call g:RMakePDFrrst()')
g:RCreateMaps('nvi', 'RMakeHTML',       'kh', ':call g:RMakeHTMLrrst("html")')
g:RCreateMaps('nvi', 'RMakeODT',        'ko', ':call g:RMakeHTMLrrst("odt")')
g:RCreateMaps('ni',  'RSendChunk',      'cc', ':call b:SendChunkToR("silent", "stay")')
g:RCreateMaps('ni',  'RESendChunk',     'ce', ':call b:SendChunkToR("echo", "stay")')
g:RCreateMaps('ni',  'RDSendChunk',     'cd', ':call b:SendChunkToR("silent", "down")')
g:RCreateMaps('ni',  'REDSendChunk',    'ca', ':call b:SendChunkToR("echo", "down")')
g:RCreateMaps('n',   'RNextRChunk',     'gn', ':call b:NextRChunk()')
g:RCreateMaps('n',   'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

g:R_strict_rst = get(g:, "R_strict_rst", 1)

# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

if !has_key(g:rplugin, 'rrst_has_rst2pdf')
    g:rplugin.rrst_has_rst2pdf = 0
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
