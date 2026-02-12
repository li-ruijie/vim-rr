vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rrst') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'

if !exists("g:did_vimr_rrst_functions")
    g:did_vimr_rrst_functions = 1

    def g:RrstIsInRCode(vrb: number): number
        var chunkline = search("^\\.\\. {r", "bncW")
        var docline = search("^\\.\\. \\.\\.", "bncW")
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

    def g:RrstPreviousChunk(count: number = 1)
        for _ in range(1, count)
            var curline = line(".")
            if g:RrstIsInRCode(0) == 1
                var i = search("^\\.\\. {r", "bnW")
                if i != 0
                    cursor(i - 1, 1)
                endif
            endif
            var i = search("^\\.\\. {r", "bnW")
            if i == 0
                cursor(curline, 1)
                g:RWarningMsg("There is no previous R code chunk to go.")
                return
            else
                cursor(i + 1, 1)
            endif
        endfor
    enddef

    def g:RrstNextChunk(count: number = 1)
        for _ in range(1, count)
            var i = search("^\\.\\. {r", "nW")
            if i == 0
                g:RWarningMsg("There is no next R code chunk to go.")
                return
            else
                cursor(i + 1, 1)
            endif
        endfor
    enddef

    def g:RMakeHTMLrrst(t: string)
        g:RSetWD()
        update
        if g:rplugin.rrst_has_rst2pdf == 0
            if executable("rst2pdf")
                g:rplugin.rrst_has_rst2pdf = 1
            else
                g:RWarningMsg("Is 'rst2pdf' application installed? Cannot convert into HTML/ODT: 'rst2pdf' executable not found.")
                return
            endif
        endif

        var rcmd = 'require(knitr)'
        if g:R_strict_rst
            rcmd = rcmd .. '; render_rst(strict=TRUE)'
        endif
        rcmd = rcmd .. '; knit("' .. expand("%:t") .. '")'

        if t == "odt"
            rcmd = rcmd .. '; system("rst2odt ' .. expand("%:r:t") .. ".rst " .. expand("%:r:t") .. '.odt")'
        else
            rcmd = rcmd .. '; system("rst2html ' .. expand("%:r:t") .. ".rst " .. expand("%:r:t") .. '.html")'
        endif

        if g:R_openhtml && t == "html"
            rcmd = rcmd .. '; browseURL("' .. expand("%:r:t") .. '.html")'
        endif
        g:SendCmdToR(rcmd)
    enddef

    def g:RMakePDFrrst()
        if !has_key(g:rplugin, "pdfviewer")
            g:RSetPDFViewer()
        endif

        update
        g:RSetWD()
        if g:rplugin.rrst_has_rst2pdf == 0
            if exists("g:R_rst2pdfpath") && executable(g:R_rst2pdfpath)
                g:rplugin.rrst_has_rst2pdf = 1
            elseif executable("rst2pdf")
                g:rplugin.rrst_has_rst2pdf = 1
            else
                g:RWarningMsg("Is 'rst2pdf' application installed? Cannot convert into PDF: 'rst2pdf' executable not found.")
                return
            endif
        endif

        var rrstdir = expand("%:p:h")
        if has("win32")
            rrstdir = substitute(rrstdir, '\\', '/', 'g')
        endif
        var pdfcmd = 'vim.interlace.rrst("' .. expand("%:t") .. '", rrstdir = "' .. rrstdir .. '"'
        if exists("g:R_rrstcompiler")
            pdfcmd = pdfcmd .. ", compiler='" .. g:R_rrstcompiler .. "'"
        endif
        if exists("g:R_knitargs")
            pdfcmd = pdfcmd .. ", " .. g:R_knitargs
        endif
        if exists("g:R_rst2pdfpath")
            pdfcmd = pdfcmd .. ", rst2pdfpath='" .. g:R_rst2pdfpath .. "'"
        endif
        if exists("g:R_rst2pdfargs")
            pdfcmd = pdfcmd .. ", " .. g:R_rst2pdfargs
        endif
        pdfcmd = pdfcmd .. ")"
        var ok = g:SendCmdToR(pdfcmd)
        if ok == 0
            return
        endif
    enddef

    # Send Rrst chunk to R
    def g:SendRrstChunkToR(e: string, m: string)
        if g:RrstIsInRCode(0) == 2
            cursor(line(".") + 1, 1)
        elseif g:RrstIsInRCode(0) != 1
            g:RWarningMsg("Not inside an R code chunk.")
            return
        endif
        var chunkline = search("^\\.\\. {r", "bncW") + 1
        var docline = search("^\\.\\. \\.\\.", "ncW") - 1
        var lines = getline(chunkline, docline)
        var ok = g:RSourceLines(lines, e, "chunk")
        if ok == 0
            return
        endif
        if m == "down"
            g:RrstNextChunk()
        endif
    enddef
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
g:RCreateMaps('n',   'RNextRChunk',     'gn', ':call b:NextRChunk(v:count1)')
g:RCreateMaps('n',   'RPreviousRChunk', 'gN', ':call b:PreviousRChunk(v:count1)')

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
    def g:RPDFinit(...args: list<any>)
        exe "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/pdf_init.vim"
    enddef
endif

timer_start(1, 'g:RPDFinit')

if exists("b:undo_ftplugin")
    b:undo_ftplugin ..= " | unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR"
else
    b:undo_ftplugin = "unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR"
endif
