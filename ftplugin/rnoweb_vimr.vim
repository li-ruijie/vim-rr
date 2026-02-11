vim9script

if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rnoweb') == -1
    finish
endif

# Define some buffer variables common to R, Rnoweb, Rmd, Rrst, Rhelp and rdoc:
execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/common_buffer.vim'
if exists('g:has_Rnvim')
    finish
endif

# Bibliographic completion
if index(g:R_bib_compl, 'rnoweb') > -1
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/bibcompl.vim'
endif

if exists('g:R_cite_pattern')
    g:rplugin.rnw_cite_ptrn = g:R_cite_pattern
elseif exists('g:LatexBox_cite_pattern')
    g:rplugin.rnw_cite_ptrn = g:LatexBox_cite_pattern
else
    # From LaTeX-Box/ftplugin/latex-box/complete.vim:
    g:rplugin.rnw_cite_ptrn = '\C\\\a*cite\a*\*\?\(\[[^\]]*\]\)*\_\s*{'
endif

g:R_rnowebchunk = get(g:, "R_rnowebchunk", 1)

if g:R_rnowebchunk == 1
    # Write code chunk in rnoweb files
    inoremap <buffer><silent> < <Esc>:call g:RWriteChunk()<CR>a
endif

execute 'source ' .. substitute(g:rplugin.home, " ", "\\ ", "g") .. '/R/rnw_fun.vim'

def CompleteEnv(base: string): list<dict<string>>
    # List from LaTeX-Box
    var lenv = ['abstract]', 'align*}', 'align}', 'center}', 'description}',
                'document}', 'enumerate}', 'equation}', 'figure}',
                'itemize}', 'table}', 'tabular}']
    filter(lenv, (_, v) => v =~ base)
    sort(lenv)
    var rr: list<dict<string>> = []
    for env in lenv
        add(rr, {word: env})
    endfor
    return rr
enddef

def CompleteLaTeXCmd(base: string): list<dict<string>>
    # List from LaTeX-Box
    var lcmd = ['\begin{', '\bottomrule', '\caption', '\chapter', '\cite',
                '\citep', '\citet', '\cmidrule{', '\end{', '\eqref', '\hline',
                '\includegraphics', '\item', '\label', '\midrule', '\multicolumn{',
                '\multirow{', '\newcommand', '\pageref', '\ref', '\section{',
                '\subsection{', '\subsubsection{', '\toprule', '\usepackage{']
    var newbase = '\' .. base
    filter(lcmd, (_, v) => v =~ newbase)
    sort(lcmd)
    var rr: list<dict<string>> = []
    for cmd in lcmd
        add(rr, {word: cmd})
    endfor
    return rr
enddef

def CompleteRef(base: string): list<dict<string>>
    # Get \label{abc}
    var lines = getline(1, '$')
    var bigline = join(lines)
    var labline = substitute(bigline, '^.\{-}\label{', '', 'g')
    labline = substitute(labline, '\label{', "\x05", 'g')
    var labels = split(labline, "\x05")
    map(labels, (_, v) => substitute(v, '}.*', '', 'g'))
    filter(labels, (_, v) => len(v) < 40)

    # Get chunk label if it has fig.cap
    var lfig = copy(lines)
    filter(lfig, (_, v) => v =~ '^<<.*fig\.cap\s*=')
    map(lfig, (_, v) => substitute(v, '^<<', '', ''))
    map(lfig, (_, v) => substitute(v, ',.*', '', ''))
    map(lfig, (_, v) => 'fig:' .. v)
    labels += lfig

    # Get label="tab:abc"
    filter(lines, (_, v) => v =~ 'label\s*=\s*.tab:')
    map(lines, (_, v) => substitute(v, '.*label\s*=\s*.', '', ''))
    map(lines, (_, v) => substitute(v, "'.*", '', ''))
    map(lines, (_, v) => substitute(v, '".*', '', ''))
    labels += lines

    filter(labels, (_, v) => v =~ '^' .. base)

    var resp: list<dict<string>> = []
    for lbl in labels
        add(resp, {word: lbl})
    endfor
    return resp
enddef

g:rplugin.rnw_compl_type = 0

if !exists('*g:RnwNonRCompletion')
    function g:RnwNonRCompletion(findstart, base)
        if a:findstart
            let line = getline('.')
            let idx = col('.') - 2
            let widx = idx

            " Where is the cursor in 'text \command{ } text'?
            let g:rplugin.rnw_compl_type = 0
            while idx >= 0
                if line[idx] =~ '\w'
                    let widx = idx
                elseif line[idx] == '\'
                    let g:rplugin.rnw_compl_type = 1
                    return idx
                elseif line[idx] == '{'
                    let g:rplugin.rnw_compl_type = 2
                    return widx
                elseif line[idx] == '}'
                    return widx
                endif
                let idx -= 1
            endwhile
        else
            if g:rplugin.rnw_compl_type == 0
                return []
            elseif g:rplugin.rnw_compl_type == 1
                return s:CompleteLaTeXCmd(a:base)
            endif

            let line = getline('.')
            let cpos = getpos(".")
            let idx = cpos[2] - 2
            let piece = line[0:idx]
            let piece = substitute(piece, ".*\\", "\\", '')
            let piece = substitute(piece, ".*}", "", '')

            " Get completions even for 'empty' base
            if piece =~ '^\\' && a:base == '{'
                let piece .= '{'
                let newbase = ''
            else
                let newbase = a:base
            endif

            if newbase != '' && piece =~ g:rplugin.rnw_cite_ptrn
                return RCompleteBib(newbase)
            elseif piece == '\begin{'
                let g:rplugin.rnw_compl_type = 9
                return s:CompleteEnv(newbase)
            elseif piece == '\ref{' || piece == '\pageref{'
                return s:CompleteRef(newbase)
            endif

            return []
        endif
    endfunction
endif

if !exists('*g:RnwOnCompleteDone')
    function g:RnwOnCompleteDone()
        if g:rplugin.rnw_compl_type == 9
            let g:rplugin.rnw_compl_type = 0
            if has_key(v:completed_item, 'word')
                call append(line('.'), [repeat(' ', indent(line('.'))) . '\end{' . v:completed_item['word']])
            endif
        endif
    endfunction
endif


# Pointers to functions whose purposes are the same in rnoweb, rrst, rmd,
# rhelp and rdoc and which are called at common_global.vim
b:IsInRCode = function('g:RnwIsInRCode')
b:PreviousRChunk = function('g:RnwPreviousChunk')
b:NextRChunk = function('g:RnwNextChunk')
b:SendChunkToR = function('g:RnwSendChunkToR')

b:rplugin_knitr_pattern = "^<<.*>>=$"

#==========================================================================
# Key bindings and menu items

g:RCreateStartMaps()
g:RCreateEditMaps()
g:RCreateSendMaps()
g:RControlMaps()
g:RCreateMaps('nvi', 'RSetwd',        'rd', ':call g:RSetWD()')

# Only .Rnw files use these functions:
g:RCreateMaps('nvi', 'RSweave',      'sw', ':call g:RWeave("nobib", 0, 0)')
g:RCreateMaps('nvi', 'RMakePDF',     'sp', ':call g:RWeave("nobib", 0, 1)')
g:RCreateMaps('nvi', 'RBibTeX',      'sb', ':call g:RWeave("bibtex", 0, 1)')
if exists("g:R_rm_knit_cache") && g:R_rm_knit_cache == 1
    g:RCreateMaps('nvi', 'RKnitRmCache', 'kr', ':call g:RKnitRmCache()')
endif
g:RCreateMaps('nvi', 'RKnit',        'kn', ':call g:RWeave("nobib", 1, 0)')
g:RCreateMaps('nvi', 'RMakePDFK',    'kp', ':call g:RWeave("nobib", 1, 1)')
g:RCreateMaps('nvi', 'RBibTeXK',     'kb', ':call g:RWeave("bibtex", 1, 1)')
g:RCreateMaps('ni',  'RSendChunk',   'cc', ':call b:SendChunkToR("silent", "stay")')
g:RCreateMaps('ni',  'RESendChunk',  'ce', ':call b:SendChunkToR("echo", "stay")')
g:RCreateMaps('ni',  'RDSendChunk',  'cd', ':call b:SendChunkToR("silent", "down")')
g:RCreateMaps('ni',  'REDSendChunk', 'ca', ':call b:SendChunkToR("echo", "down")')
g:RCreateMaps('nvi', 'ROpenPDF',     'op', ':call g:ROpenPDF("Get Master")')
if g:R_synctex
    g:RCreateMaps('ni', 'RSyncFor',  'gp', ':call g:SyncTeX_forward()')
    g:RCreateMaps('ni', 'RGoToTeX',  'gt', ':call g:SyncTeX_forward(1)')
endif
g:RCreateMaps('n', 'RNextRChunk',     'gn', ':call b:NextRChunk()')
g:RCreateMaps('n', 'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

# Menu R
if has("gui_running")
    execute 'source ' .. substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') .. '/R/gui_running.vim'
    g:MakeRMenu()
endif

g:RSourceOtherScripts()

if g:R_non_r_compl && index(g:R_bib_compl, 'rnoweb') > -1
    timer_start(1, 'g:CheckPyBTeX')
endif

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
