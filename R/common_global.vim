vim9script

# ==============================================================================
# Functions that might be called even before R is started.
#
# The functions and variables defined here are common for all buffers of all
# file types supported by Vim-R and must be defined only once.
# ==============================================================================


set encoding=utf-8
scriptencoding utf-8

# Do this only once
if exists("g:did_vimr_global_stuff")
    finish
endif
g:did_vimr_global_stuff = 1

if !exists('g:rplugin')
    # Attention: also in functions.vim because either of them might be sourced first.
    g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0, 'rscript_name': ''}
endif

g:rplugin.debug_info['Time'] = {'common_global.vim': reltime()}

# ==============================================================================
# Check if there is more than one copy of Vim-R
# (e.g. from the Vimballl and from a plugin manager)
# ==============================================================================

if exists("g:did_vimr_rwarningmsg")
    # A common_global.vim script was sourced from another version of Vim-R.
    finish
endif
g:did_vimr_rwarningmsg = 1


# ==============================================================================
# WarningMsg
# ==============================================================================

def g:FormatPrgrph(text: string, splt: string, jn: string, maxlen: number): string
    var wlist = split(text, splt)
    var txt = ['']
    var ii = 0
    for wrd in wlist
        if strdisplaywidth(txt[ii] .. splt .. wrd) < maxlen
            txt[ii] ..= splt .. wrd
        else
            ii += 1
            txt += [wrd]
        endif
    endfor
    txt[0] = substitute(txt[0], '^' .. splt, '', '')
    return join(txt, jn)
enddef

def g:FormatTxt(text: string, splt: string, jn: string, maxl: number): string
    var maxlen = maxl - len(jn)
    var atext = substitute(text, "\x13", "'", "g")
    var plist = split(atext, "\x14")
    var txt = ''
    for prg in plist
        txt ..= "\n " .. g:FormatPrgrph(prg, splt, jn, maxlen)
    endfor
    txt = substitute(txt, "^\n ", "", "")
    return txt
enddef

g:rplugin.float_warn = 0
def g:RFloatWarn(wmsg: string)
    var fmsg = ' ' .. g:FormatTxt(wmsg, ' ', " \n ", 60)
    var fmsgl = split(fmsg, "\n")
    var realwidth = 10
    for lin in fmsgl
        if strdisplaywidth(lin) > realwidth
            realwidth = strdisplaywidth(lin)
        endif
    endfor
    var wht = len(fmsgl) > 3 ? 3 : len(fmsgl)
    var fline = &lines - 2 - wht
    var fcol = winwidth(0) - realwidth
    g:rplugin.float_warn = popup_create(fmsgl, {
        line: fline,
        col: fcol,
        highlight: 'WarningMsg',
        time: 2000 * len(fmsgl),
        })
enddef

def g:WarnAfterVimEnter1()
    timer_start(1000, 'g:WarnAfterVimEnter2')
enddef

def g:WarnAfterVimEnter2(...args: list<any>)
    for msg in g:rplugin.start_msg
        g:RWarningMsg(msg)
    endfor
enddef

def g:RWarningMsg(wmsg: string)
    if v:vim_did_enter == 0
        if !exists('g:rplugin.start_msg')
            g:rplugin.start_msg = [wmsg]
            execute 'autocmd VimEnter * call g:WarnAfterVimEnter1()'
        else
            g:rplugin.start_msg += [wmsg]
        endif
        return
    endif
    if mode() == 'i' && has('patch-8.2.84')
        g:RFloatWarn(wmsg)
    endif
    echohl WarningMsg
    echomsg wmsg
    echohl None
enddef

# ==============================================================================
# Check Vim version
# ==============================================================================

if v:version < 802
    g:RWarningMsg("Vim-R requires Vim >= 8.2.84")
    g:rplugin.failed = 1
    finish
elseif !has("channel") || !has("job") || !has('patch-8.2.84')
    g:RWarningMsg("Vim-R requires Vim >= 8.2.84\nVim must have been compiled with both +channel and +job features.\n")
    g:rplugin.failed = 1
    finish
endif

# Convert _ into <-
def g:ReplaceUnderS()
    if g:R_assign == 0
        # See https://github.com/jalvesaq/Vim-R/issues/668
        execute 'iunmap <buffer> ' .. g:R_assign_map
        execute "normal! a" .. g:R_assign_map
        return
    endif
    var isString: number
    if &filetype != "r" && b:IsInRCode(0) != 1
        isString = 1
    else
        var save_unnamed_reg = @@
        var j = col(".")
        var s = getline(".")
        if g:R_assign == 1 && g:R_assign_map == "_" && j > 3 && s[j - 3] == "<" && s[j - 2] == "-" && s[j - 1] == " "
            execute "normal! 3h3xr_"
            @@ = save_unnamed_reg
            return
        endif
        isString = 0
        var synName = synIDattr(synID(line("."), j, 1), "name")
        if synName == "rSpecial"
            isString = 1
        else
            if synName == "rString"
                isString = 1
                if (s[j - 1] == '"' || s[j - 1] == "'") && g:R_assign == 1
                    synName = synIDattr(synID(line("."), j - 2, 1), "name")
                    if synName == "rString" || synName == "rSpecial"
                        isString = 0
                    endif
                endif
            else
                if g:R_assign == 2
                    if s[j - 1] != "_" && !(j > 3 && s[j - 3] == "<" && s[j - 2] == "-" && s[j - 1] == " ")
                        isString = 1
                    elseif j > 3 && s[j - 3] == "<" && s[j - 2] == "-" && s[j - 1] == " "
                        execute "normal! 3h3xr_a_"
                        @@ = save_unnamed_reg
                        return
                    else
                        if j == len(s)
                            execute "normal! 1x"
                            @@ = save_unnamed_reg
                        else
                            execute "normal! 1xi <- "
                            @@ = save_unnamed_reg
                            return
                        endif
                    endif
                endif
            endif
        endif
    endif
    if isString
        execute "normal! a" .. g:R_assign_map
    else
        execute "normal! a <- "
    endif
enddef

# Get the word either under or after the cursor.
# Works for word(| where | is the cursor position.
def g:RGetKeyword(...args: list<any>): string
    # Go back some columns if character under cursor is not valid
    var line: string
    var i: number
    if len(args) == 2
        line = getline(args[0])
        i = args[1]
    else
        line = getline(".")
        i = col(".") - 1
    endif
    if strlen(line) == 0
        return ""
    endif
    # line index starts in 0; cursor index starts in 1:
    # Skip opening braces
    while i > 0 && line[i] =~ '(\|\[\|{'
        i -= 1
    endwhile
    # Go to the beginning of the word
    # See https://en.wikipedia.org/wiki/UTF-8#Codepage_layout
    while i > 0 && (line[i - 1] =~ '\k\|@\|\$\|\:\|_\|\.' || (line[i - 1] > "\x80" && line[i - 1] < "\xf5"))
        i -= 1
    endwhile
    # Go to the end of the word
    var j = i
    while j < strlen(line) && (line[j] =~ '\k\|@\|\$\|\:\|_\|\.' || (line[j] > "\x80" && line[j] < "\xf5"))
        j += 1
    endwhile
    var rkeyword = strpart(line, i, j - i)
    return rkeyword
enddef

# Get the name of the first object after the opening parenthesis. Useful to
# call a specific print, summary, ..., method instead of the generic one.
def g:RGetFirstObj(rkeyword: string, ...args: list<any>): list<any>
    var firstobj = ""
    var line: string
    var begin: number
    var listdf: any
    if len(args) == 3
        line = substitute(args[0], '#.*', '', "")
        begin = args[1]
        listdf = args[2]
    else
        line = substitute(getline("."), '#.*', '', "")
        begin = col(".")
        listdf = v:false
    endif
    if strlen(line) > begin
        var piece = strpart(line, begin)
        while piece !~ '^' .. rkeyword && begin >= 0
            begin -= 1
            piece = strpart(line, begin)
        endwhile

        # check if the first argument is being passed through a pipe operator
        if begin > 2
            var part1 = strpart(line, 0, begin)
            if part1 =~ '\k\+\s*\(|>\|%>%\)'
                var pipeobj = substitute(part1, '.\{-}\(\k\+\)\s*\(|>\|%>%\)\s*', '\1', '')
                return [pipeobj, v:true]
            endif
        endif
        var pline = substitute(getline(line('.') - 1), '#.*$', '', '')
        if pline =~ '\k\+\s*\(|>\|%>%\)\s*$'
            var pipeobj = substitute(pline, '.\{-}\(\k\+\)\s*\(|>\|%>%\)\s*$', '\1', '')
            return [pipeobj, v:true]
        endif

        line = piece
        if line !~ '^\k*\s*('
            return [firstobj, v:false]
        endif
        begin = 1
        var linelen = strlen(line)
        while line[begin] != '(' && begin < linelen
            begin += 1
        endwhile
        begin += 1
        line = strpart(line, begin)
        line = substitute(line, '^\s*', '', "")
        if (line =~ '^\k*\s*(' || line =~ '^\k*\s*=\s*\k*\s*(') && line !~ '[.*('
            var idx = 0
            while line[idx] != '('
                idx += 1
            endwhile
            idx += 1
            var nparen = 1
            var len = strlen(line)
            var lnum = line(".")
            while nparen != 0
                if idx == len
                    lnum += 1
                    while lnum <= line("$") && strlen(substitute(getline(lnum), '#.*', '', "")) == 0
                        lnum += 1
                    endwhile
                    if lnum > line("$")
                        return ["", v:false]
                    endif
                    line = line .. substitute(getline(lnum), '#.*', '', "")
                    len = strlen(line)
                endif
                if line[idx] == '('
                    nparen += 1
                else
                    if line[idx] == ')'
                        nparen -= 1
                    endif
                endif
                idx += 1
            endwhile
            firstobj = strpart(line, 0, idx)
        elseif line =~ '^\(\k\|\$\)*\s*[' || line =~ '^\(\k\|\$\)*\s*=\s*\(\k\|\$\)*\s*[.*('
            var idx = 0
            while line[idx] != '['
                idx += 1
            endwhile
            idx += 1
            var nparen = 1
            var len = strlen(line)
            var lnum = line(".")
            while nparen != 0
                if idx == len
                    lnum += 1
                    while lnum <= line("$") && strlen(substitute(getline(lnum), '#.*', '', "")) == 0
                        lnum += 1
                    endwhile
                    if lnum > line("$")
                        return ["", v:false]
                    endif
                    line = line .. substitute(getline(lnum), '#.*', '', "")
                    len = strlen(line)
                endif
                if line[idx] == '['
                    nparen += 1
                else
                    if line[idx] == ']'
                        nparen -= 1
                    endif
                endif
                idx += 1
            endwhile
            firstobj = strpart(line, 0, idx)
        else
            firstobj = substitute(line, ').*', '', "")
            firstobj = substitute(firstobj, ',.*', '', "")
            firstobj = substitute(firstobj, ' .*', '', "")
        endif
    endif

    if firstobj =~ "="
        firstobj = ""
    endif

    if firstobj[0] == '"' || firstobj[0] == "'"
        firstobj = "#c#"
    elseif firstobj[0] >= "0" && firstobj[0] <= "9"
        firstobj = "#n#"
    endif


    if firstobj =~ '"'
        firstobj = substitute(firstobj, '"', '\\"', "g")
    endif

    return [firstobj, v:false]
enddef

def g:ROpenPDF(fullpath: string)
    if !exists('g:R_openpdf') || g:R_openpdf == 0
        return
    endif

    if fullpath == "Get Master"
        var fpath = g:SyncTeX_GetMaster() .. ".pdf"
        fpath = b:rplugin_pdfdir .. "/" .. substitute(fpath, ".*/", "", "")
        g:ROpenPDF(fpath)
        return
    endif

    if b:pdf_is_open == 0
        if g:R_openpdf == 1
            b:pdf_is_open = 1
        endif
        if exists('*g:ROpenPDF2')
            g:ROpenPDF2(fullpath)
        endif
    endif
enddef

# For each noremap we need a vnoremap including <Esc> before the :call,
# otherwise Vim will call the function as many times as the number of selected
# lines. If we put <Esc> in the noremap, Vim will bell.
# RCreateMaps Args:
#   type : modes to which create maps (normal, visual and insert) and whether
#          the cursor have to go the beginning of the line
#   plug : the <Plug>Name
#   combo: combination of letters that make the shortcut
#   target: the command or function to be called
def g:RCreateMaps(type: string, plug: string, combo: string, target: string)
    if index(g:R_disable_cmds, plug) > -1
        return
    endif
    var tg: string
    var il: string
    if type =~ '0'
        tg = target .. '<CR>0'
        il = 'i'
    elseif type =~ '\.'
        tg = target
        il = 'a'
    else
        tg = target .. '<CR>'
        il = 'a'
    endif
    if type =~ "n"
        execute 'noremap <buffer><silent> <Plug>' .. plug .. ' ' .. tg
        if g:R_user_maps_only != 1 && !hasmapto('<Plug>' .. plug, "n")
            execute 'noremap <buffer><silent> <LocalLeader>' .. combo .. ' ' .. tg
        endif
    endif
    if type =~ "v"
        execute 'vnoremap <buffer><silent> <Plug>' .. plug .. ' <Esc>' .. tg
        if g:R_user_maps_only != 1 && !hasmapto('<Plug>' .. plug, "v")
            execute 'vnoremap <buffer><silent> <LocalLeader>' .. combo .. ' <Esc>' .. tg
        endif
    endif
    if g:R_insert_mode_cmds == 1 && type =~ "i"
        execute 'inoremap <buffer><silent> <Plug>' .. plug .. ' <Esc>' .. tg .. il
        if g:R_user_maps_only != 1 && !hasmapto('<Plug>' .. plug, "i")
            execute 'inoremap <buffer><silent> <LocalLeader>' .. combo .. ' <Esc>' .. tg .. il
        endif
    endif
enddef

def g:RControlMaps()
    # List space, clear console, clear all
    #-------------------------------------
    g:RCreateMaps('nvi', 'RListSpace',    'rl', ':call g:SendCmdToR("ls()")')
    g:RCreateMaps('nvi', 'RClearConsole', 'rr', ':call RClearConsole()')
    g:RCreateMaps('nvi', 'RClearAll',     'rm', ':call RClearAll()')

    # Print, names, structure
    #-------------------------------------
    g:RCreateMaps('ni', 'RObjectPr',    'rp', ':call RAction("print")')
    g:RCreateMaps('ni', 'RObjectNames', 'rn', ':call RAction("vim.names")')
    g:RCreateMaps('ni', 'RObjectStr',   'rt', ':call RAction("str")')
    g:RCreateMaps('ni', 'RViewDF',      'rv', ':call RAction("viewobj")')
    g:RCreateMaps('ni', 'RViewDFs',     'vs', ':call RAction("viewobj", ", howto=''split''")')
    g:RCreateMaps('ni', 'RViewDFv',     'vv', ':call RAction("viewobj", ", howto=''vsplit''")')
    g:RCreateMaps('ni', 'RViewDFa',     'vh', ':call RAction("viewobj", ", howto=''above 7split'', nrows=6")')
    g:RCreateMaps('ni', 'RDputObj',     'td', ':call RAction("dputtab")')

    g:RCreateMaps('v', 'RObjectPr',     'rp', ':call RAction("print", "v")')
    g:RCreateMaps('v', 'RObjectNames',  'rn', ':call RAction("vim.names", "v")')
    g:RCreateMaps('v', 'RObjectStr',    'rt', ':call RAction("str", "v")')
    g:RCreateMaps('v', 'RViewDF',       'rv', ':call RAction("viewobj", "v")')
    g:RCreateMaps('v', 'RViewDFs',      'vs', ':call RAction("viewobj", "v", ", howto=''split''")')
    g:RCreateMaps('v', 'RViewDFv',      'vv', ':call RAction("viewobj", "v", ", howto=''vsplit''")')
    g:RCreateMaps('v', 'RViewDFa',      'vh', ':call RAction("viewobj", "v", ", howto=''above 7split'', nrows=6")')
    g:RCreateMaps('v', 'RDputObj',      'td', ':call RAction("dputtab", "v")')

    # Arguments, example, help
    #-------------------------------------
    g:RCreateMaps('nvi', 'RShowArgs',   'ra', ':call RAction("args")')
    g:RCreateMaps('nvi', 'RShowEx',     're', ':call RAction("example")')
    g:RCreateMaps('nvi', 'RHelp',       'rh', ':call RAction("help")')

    # Summary, plot, both
    #-------------------------------------
    g:RCreateMaps('ni', 'RSummary',     'rs', ':call RAction("summary")')
    g:RCreateMaps('ni', 'RPlot',        'rg', ':call RAction("plot")')
    g:RCreateMaps('ni', 'RSPlot',       'rb', ':call RAction("plotsumm")')

    g:RCreateMaps('v', 'RSummary',      'rs', ':call RAction("summary", "v")')
    g:RCreateMaps('v', 'RPlot',         'rg', ':call RAction("plot", "v")')
    g:RCreateMaps('v', 'RSPlot',        'rb', ':call RAction("plotsumm", "v")')

    # Build list of objects for omni completion
    #-------------------------------------
    g:RCreateMaps('nvi', 'RUpdateObjBrowser', 'ro', ':call RObjBrowser()')
    g:RCreateMaps('nvi', 'ROpenLists',        'r=', ':call RBrOpenCloseLs("O")')
    g:RCreateMaps('nvi', 'RCloseLists',       'r-', ':call RBrOpenCloseLs("C")')

    # Render script with rmarkdown
    #-------------------------------------
    g:RCreateMaps('nvi', 'RMakeRmd',    'kr', ':call RMakeRmd("default")')
    g:RCreateMaps('nvi', 'RMakeAll',    'ka', ':call RMakeRmd("all")')
    if &filetype == "quarto"
        g:RCreateMaps('nvi', 'RMakePDFK',   'kp', ':call RMakeRmd("pdf")')
        g:RCreateMaps('nvi', 'RMakePDFKb',  'kl', ':call RMakeRmd("beamer")')
        g:RCreateMaps('nvi', 'RMakeWord',   'kw', ':call RMakeRmd("docx")')
        g:RCreateMaps('nvi', 'RMakeHTML',   'kh', ':call RMakeRmd("html")')
        g:RCreateMaps('nvi', 'RMakeODT',    'ko', ':call RMakeRmd("odt")')
    else
        g:RCreateMaps('nvi', 'RMakePDFK',   'kp', ':call RMakeRmd("pdf_document")')
        g:RCreateMaps('nvi', 'RMakePDFKb',  'kl', ':call RMakeRmd("beamer_presentation")')
        g:RCreateMaps('nvi', 'RMakeWord',   'kw', ':call RMakeRmd("word_document")')
        g:RCreateMaps('nvi', 'RMakeHTML',   'kh', ':call RMakeRmd("html_document")')
        g:RCreateMaps('nvi', 'RMakeODT',    'ko', ':call RMakeRmd("odt_document")')
    endif
enddef

def g:RCreateStartMaps()
    # Start
    #-------------------------------------
    g:RCreateMaps('nvi', 'RStart',       'rf', ':call g:StartR("R")')
    g:RCreateMaps('nvi', 'RCustomStart', 'rc', ':call g:StartR("custom")')

    # Close
    #-------------------------------------
    g:RCreateMaps('nvi', 'RClose',       'rq', ":call RQuit('nosave')")
    g:RCreateMaps('nvi', 'RSaveClose',   'rw', ":call RQuit('save')")

    # Restart
    #-------------------------------------
    g:RCreateMaps('nvi', 'RRestart', 'rst', ':call RRestart()')

enddef

def g:RCreateEditMaps()
    # Edit
    #-------------------------------------
    if g:R_enable_comment
        g:RCreateCommentMaps()
    endif
    # Replace 'underline' with '<-'
    if g:R_assign == 1
        silent execute 'inoremap <buffer><silent> ' .. g:R_assign_map .. ' <Esc>:call ReplaceUnderS()<CR>a'
    endif
    if  g:R_assign == 2
        silent execute 'inoremap <buffer><silent> ' .. g:R_assign_map .. g:R_assign_map .. ' ' .. g:R_assign_map .. '<Esc>:call ReplaceUnderS()<CR>a'
    endif
enddef

def g:RCreateSendMaps()
    # Block
    #-------------------------------------
    g:RCreateMaps('ni', 'RSendMBlock',     'bb', ':call SendMBlockToR("silent", "stay")')
    g:RCreateMaps('ni', 'RESendMBlock',    'be', ':call SendMBlockToR("echo", "stay")')
    g:RCreateMaps('ni', 'RDSendMBlock',    'bd', ':call SendMBlockToR("silent", "down")')
    g:RCreateMaps('ni', 'REDSendMBlock',   'ba', ':call SendMBlockToR("echo", "down")')

    # Function
    #-------------------------------------
    g:RCreateMaps('nvi', 'RSendFunction',  'ff', ':call SendFunctionToR("silent", "stay")')
    g:RCreateMaps('nvi', 'RDSendFunction', 'fe', ':call SendFunctionToR("echo", "stay")')
    g:RCreateMaps('nvi', 'RDSendFunction', 'fd', ':call SendFunctionToR("silent", "down")')
    g:RCreateMaps('nvi', 'RDSendFunction', 'fa', ':call SendFunctionToR("echo", "down")')

    # Selection
    #-------------------------------------
    g:RCreateMaps('n', 'RSendSelection',   'ss', ':call SendSelectionToR("silent", "stay", "normal")')
    g:RCreateMaps('n', 'RESendSelection',  'se', ':call SendSelectionToR("echo", "stay", "normal")')
    g:RCreateMaps('n', 'RDSendSelection',  'sd', ':call SendSelectionToR("silent", "down", "normal")')
    g:RCreateMaps('n', 'REDSendSelection', 'sa', ':call SendSelectionToR("echo", "down", "normal")')

    g:RCreateMaps('v', 'RSendSelection',   'ss', ':call SendSelectionToR("silent", "stay")')
    g:RCreateMaps('v', 'RESendSelection',  'se', ':call SendSelectionToR("echo", "stay")')
    g:RCreateMaps('v', 'RDSendSelection',  'sd', ':call SendSelectionToR("silent", "down")')
    g:RCreateMaps('v', 'REDSendSelection', 'sa', ':call SendSelectionToR("echo", "down")')
    g:RCreateMaps('v', 'RSendSelAndInsertOutput', 'so', ':call SendSelectionToR("echo", "stay", "NewtabInsert")')

    # Paragraph
    #-------------------------------------
    g:RCreateMaps('ni', 'RSendParagraph',   'pp', ':call SendParagraphToR("silent", "stay")')
    g:RCreateMaps('ni', 'RESendParagraph',  'pe', ':call SendParagraphToR("echo", "stay")')
    g:RCreateMaps('ni', 'RDSendParagraph',  'pd', ':call SendParagraphToR("silent", "down")')
    g:RCreateMaps('ni', 'REDSendParagraph', 'pa', ':call SendParagraphToR("echo", "down")')

    if &filetype == "rnoweb" || &filetype == "rmd" || &filetype == "quarto" || &filetype == "rrst"
        g:RCreateMaps('ni', 'RSendChunkFH', 'ch', ':call SendFHChunkToR()')
    endif

    # *Line*
    #-------------------------------------
    g:RCreateMaps('ni',  'RSendLine', 'l', ':call SendLineToR("stay")')
    g:RCreateMaps('ni0', 'RDSendLine', 'd', ':call SendLineToR("down")')
    g:RCreateMaps('ni0', '(RDSendLineAndInsertOutput)', 'o', ':call SendLineToRAndInsertOutput()')
    g:RCreateMaps('v',   '(RDSendLineAndInsertOutput)', 'o', ':call RWarningMsg("This command does not work over a selection of lines.")')
    g:RCreateMaps('i',   'RSendLAndOpenNewOne', 'q', ':call SendLineToR("newline")')
    g:RCreateMaps('ni.', 'RSendMotion', 'm', ':set opfunc=SendMotionToR<CR>g@')
    g:RCreateMaps('n',   'RNLeftPart', 'r<left>', ':call RSendPartOfLine("left", 0)')
    g:RCreateMaps('n',   'RNRightPart', 'r<right>', ':call RSendPartOfLine("right", 0)')
    g:RCreateMaps('i',   'RILeftPart', 'r<left>', 'l:call RSendPartOfLine("left", 1)')
    g:RCreateMaps('i',   'RIRightPart', 'r<right>', 'l:call RSendPartOfLine("right", 1)')
    if &filetype == "r"
        g:RCreateMaps('n', 'RSendAboveLines',  'su', ':call g:SendAboveLinesToR()')
    endif

    # Debug
    g:RCreateMaps('n',   'RDebug', 'bg', ':call RAction("debug")')
    g:RCreateMaps('n',   'RUndebug', 'ud', ':call RAction("undebug")')
enddef

def g:RBufEnter()
    g:rplugin.curbuf = bufname("%")
    if has("gui_running")
        if &filetype != g:rplugin.lastft
            g:UnMakeRMenu()
            if &filetype == "r" || &filetype == "rnoweb" || &filetype == "rmd" || &filetype == "quarto" || &filetype == "rrst" || &filetype == "rdoc" || &filetype == "rbrowser" || &filetype == "rhelp"
                if &filetype == "rbrowser"
                    g:MakeRBrowserMenu()
                else
                    g:MakeRMenu()
                endif
            endif
        endif
        if &buftype != "nofile" || (&buftype == "nofile" && &filetype == "rbrowser")
            g:rplugin.lastft = &filetype
        endif
    endif
    if &filetype == "r" || &filetype == "rnoweb" || &filetype == "rmd" || &filetype == "quarto" || &filetype == "rrst" || &filetype == "rhelp"
        g:rplugin.rscript_name = bufname("%")
    endif
enddef

# Store list of files to be deleted on VimLeave
def g:AddForDeletion(fname: string)
    for fn in g:rplugin.del_list
        if fn == fname
            return
        endif
    endfor
    add(g:rplugin.del_list, fname)
enddef

def g:RVimLeave()
    if get(g:, 'R_quit_on_close', 0) && exists("*g:QuitROnClose")
        g:QuitROnClose()
    endif

    for fn in g:rplugin.del_list
        delete(fn)
    endfor
    delete(g:rplugin.tmpdir, 'd')
    if g:rplugin.localtmpdir != g:rplugin.tmpdir
        delete(g:rplugin.localtmpdir, 'd')
    endif
enddef

def g:RSourceOtherScripts()
    if exists("g:R_source")
        var flist = split(g:R_source, ",")
        for fl in flist
            if fl =~ " "
                g:RWarningMsg("Invalid file name (empty spaces are not allowed): '" .. fl .. "'")
            else
                execute "source " .. escape(fl, ' \')
            endif
        endfor
    endif

    if (g:R_auto_start == 1 && v:vim_did_enter == 0) || g:R_auto_start == 2
        timer_start(200, 'g:AutoStartR')
    endif
enddef

def g:ShowRDebugInfo()
    for key in keys(g:rplugin.debug_info)
        if len(g:rplugin.debug_info[key]) == 0
            continue
        endif
        echohl Title
        echo key
        echohl None
        if key == 'Time' || key == 'vimcom_info'
            for step in keys(g:rplugin.debug_info[key])
                echohl Identifier
                echo '  ' .. step .. ': '
                if key == 'Time'
                    echohl Number
                else
                    echohl String
                endif
                echon g:rplugin.debug_info[key][step]
                echohl None
            endfor
            echo ""
        else
            echo g:rplugin.debug_info[key]
        endif
        echo ""
    endfor
enddef

# Function to send commands
# return 0 on failure and 1 on success
def g:SendCmdToR_fake(...args: list<any>): number
    g:RWarningMsg("Did you already start R?")
    return 0
enddef

def g:AutoStartR(...args: list<any>)
    if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
        return
    endif
    if v:vim_did_enter == 0 || g:rplugin.nrs_running == 0
        timer_start(100, 'g:AutoStartR')
        return
    endif
    g:StartR("R")
enddef

command -nargs=1 -complete=customlist,g:RLisObjs Rinsert :call g:RInsert(<q-args>, "here")
command -range=% Rformat g:RFormatCode(<line1>, <line2>)
command RBuildTags :call g:RBuildTags()
command -nargs=? -complete=customlist,g:RLisObjs Rhelp :call g:RAskHelp(<q-args>)
command -nargs=? -complete=dir RSourceDir :call g:RSourceDirectory(<q-args>)
command RStop :call g:SignalToR('SIGINT')
command RKill :call g:SignalToR('SIGKILL')
command -nargs=? RSend :call g:SendCmdToR(<q-args>)
command RDebugInfo :call g:ShowRDebugInfo()

# ==============================================================================
# Temporary links to be deleted when start_r.vim is sourced

def g:RNotRunning(...args: list<any>)
    echohl WarningMsg
    echon "R is not running"
    echohl None
enddef

g:RAction = function('g:RNotRunning')
g:RAskHelp = function('g:RNotRunning')
g:RBrOpenCloseLs = function('g:RNotRunning')
g:RBuildTags = function('g:RNotRunning')
g:RClearAll = function('g:RNotRunning')
g:RClearConsole = function('g:RNotRunning')
g:RFormatCode = function('g:RNotRunning')
g:RInsert = function('g:RNotRunning')
g:RMakeRmd = function('g:RNotRunning')
g:RObjBrowser = function('g:RNotRunning')
g:RQuit = function('g:RNotRunning')
g:RSendPartOfLine = function('g:RNotRunning')
g:RSourceDirectory = function('g:RNotRunning')
g:SendCmdToR = function('g:SendCmdToR_fake')
g:SendFileToR = function('g:SendCmdToR_fake')
g:SendFunctionToR = function('g:RNotRunning')
g:SendLineToR = function('g:RNotRunning')
g:SendLineToRAndInsertOutput = function('g:RNotRunning')
g:SendMBlockToR = function('g:RNotRunning')
g:SendParagraphToR = function('g:RNotRunning')
g:SendSelectionToR = function('g:RNotRunning')
g:SignalToR = function('g:RNotRunning')


# ==============================================================================
# Global variables
# Convention: R_        for user options
#             rplugin_  for internal parameters
# ==============================================================================

if !has_key(g:rplugin, "compldir")
    execute "source " .. substitute(expand("<sfile>:h:h"), " ", "\\ ", "g") .. "/R/setcompldir.vim"
endif

def g:ValidateTmpdir(dir: string): bool
    # Reject symlinks — real path must equal given path
    if resolve(dir) != dir
        g:RWarningMsg('Tmpdir is a symlink: ' .. dir)
        return false
    endif
    # Check permissions (Unix only — skip on Windows and Cygwin/MSYS2
    # where NTFS ACLs don't map cleanly to Unix permission bits)
    if !has('win32') && !has('win32unix')
        var perms = getfperm(dir)
        if perms != 'rwx------'
            g:RWarningMsg('Tmpdir has unsafe permissions: ' .. perms)
            return false
        endif
    endif
    # Must be a real directory
    if getftype(dir) != 'dir'
        g:RWarningMsg('Tmpdir is not a directory: ' .. dir)
        return false
    endif
    return true
enddef

if exists("g:R_tmpdir")
    g:rplugin.tmpdir = expand(g:R_tmpdir)
else
    if has("win32")
        if isdirectory($TMP)
            g:rplugin.tmpdir = $TMP .. "/Vim-R-" .. g:rplugin.userlogin
        elseif isdirectory($TEMP)
            g:rplugin.tmpdir = $TEMP .. "/Vim-R-" .. g:rplugin.userlogin
        else
            g:rplugin.tmpdir = g:rplugin.uservimfiles .. "/R/tmp"
        endif
        g:rplugin.tmpdir = substitute(g:rplugin.tmpdir, "\\", "/", "g")
    else
        if isdirectory($TMPDIR)
            if $TMPDIR =~ "/$"
                g:rplugin.tmpdir = $TMPDIR .. "Vim-R-" .. g:rplugin.userlogin
            else
                g:rplugin.tmpdir = $TMPDIR .. "/Vim-R-" .. g:rplugin.userlogin
            endif
        elseif isdirectory("/dev/shm")
            g:rplugin.tmpdir = "/dev/shm/Vim-R-" .. g:rplugin.userlogin
        elseif isdirectory("/tmp")
            g:rplugin.tmpdir = "/tmp/Vim-R-" .. g:rplugin.userlogin
        else
            g:rplugin.tmpdir = g:rplugin.uservimfiles .. "/R/tmp"
        endif
    endif
endif

# When accessing R remotely, a local tmp directory is used by the
# vimrserver to save the contents of the ObjectBrowser to avoid traffic
# over the ssh connection
g:rplugin.localtmpdir = g:rplugin.tmpdir

if exists("g:R_remote_compldir")
    $VIMR_REMOTE_COMPLDIR = g:R_remote_compldir
    $VIMR_REMOTE_TMPDIR = g:R_remote_compldir .. '/tmp'
    g:rplugin.tmpdir = g:rplugin.compldir .. '/tmp'
    if !isdirectory(g:rplugin.tmpdir)
        mkdir(g:rplugin.tmpdir, "p", 0700)
    endif
else
    $VIMR_REMOTE_COMPLDIR = g:rplugin.compldir
    $VIMR_REMOTE_TMPDIR = g:rplugin.tmpdir
endif
if !isdirectory(g:rplugin.localtmpdir)
    mkdir(g:rplugin.localtmpdir, "p", 0700)
endif
if isdirectory(g:rplugin.localtmpdir) && !g:ValidateTmpdir(g:rplugin.localtmpdir)
    g:rplugin.localtmpdir = fnamemodify(tempname(), ':h') .. '/Vim-R-' .. localtime()
    mkdir(g:rplugin.localtmpdir, "p", 0700)
    if !exists("g:R_remote_compldir")
        g:rplugin.tmpdir = g:rplugin.localtmpdir
    endif
endif
$VIMR_TMPDIR = g:rplugin.tmpdir

# Delete options with invalid values
if exists("g:R_set_omnifunc") && type(g:R_set_omnifunc) != v:t_list
    g:RWarningMsg('"R_set_omnifunc" must be a list')
    unlet g:R_set_omnifunc
endif

# Default values of some variables

g:R_assign            = get(g:, "R_assign",             1)
if type(g:R_assign) == v:t_number && g:R_assign == 2
    g:R_assign_map = '_'
endif
g:R_assign_map        = get(g:, "R_assign_map",       "_")

g:R_synctex           = get(g:, "R_synctex",            1)
g:R_non_r_compl       = get(g:, "R_non_r_compl",        1)
g:R_vim_wd            = get(g:, "R_vim_wd",            0)
g:R_auto_start        = get(g:, "R_auto_start",         0)
g:R_quit_on_close     = get(g:, "R_quit_on_close",      0)
g:R_routnotab         = get(g:, "R_routnotab",          0)
g:R_objbr_w           = get(g:, "R_objbr_w",           40)
g:R_objbr_h           = get(g:, "R_objbr_h",           10)
g:R_objbr_opendf      = get(g:, "R_objbr_opendf",       1)
g:R_objbr_openlist    = get(g:, "R_objbr_openlist",     0)
g:R_objbr_allnames    = get(g:, "R_objbr_allnames",     0)
g:R_never_unmake_menu = get(g:, "R_never_unmake_menu",  0)
g:R_insert_mode_cmds  = get(g:, "R_insert_mode_cmds",   0)
g:R_disable_cmds      = get(g:, "R_disable_cmds",    [''])
g:R_enable_comment    = get(g:, "R_enable_comment",     0)
g:R_openhtml          = get(g:, "R_openhtml",           1)
g:R_hi_fun_paren      = get(g:, "R_hi_fun_paren",       0)
g:R_bib_compl         = get(g:, "R_bib_compl", ["rnoweb"])

if type(g:R_bib_compl) == v:t_string
    g:R_bib_compl = [g:R_bib_compl]
endif

g:R_fun_data_1 = get(g:, 'R_fun_data_1', ['select', 'rename', 'mutate', 'filter'])
g:R_fun_data_2 = get(g:, 'R_fun_data_2', {'ggplot': ['aes'], 'with': ['*']})

if exists(":terminal") != 2
    g:R_external_term = get(g:, "R_external_term", 1)
endif
if !exists("*term_start")
    # exists(':terminal') return 2 even when Vim does not have the +terminal feature
    g:R_external_term = get(g:, "R_external_term", 1)
endif
g:R_external_term = get(g:, "R_external_term", 0)

var editing_mode = "emacs"
if filereadable(expand("~/.inputrc"))
    var inputrc = readfile(expand("~/.inputrc"))
    map(inputrc, (_, v) => substitute(v, "^\s*#.*", "", ""))
    filter(inputrc, (_, v) => v =~ "set.*editing-mode")
    if len(inputrc) && inputrc[len(inputrc) - 1] =~ '^\s*set\s*editing-mode\s*vi\>'
        editing_mode = "vi"
    endif
endif
g:R_editing_mode = get(g:, "R_editing_mode", editing_mode)

if has('win32') && !(type(g:R_external_term) == v:t_number && g:R_external_term == 0)
    # Sending multiple lines at once to Rgui on Windows does not work.
    g:R_parenblock = get(g:, 'R_parenblock',         0)
else
    g:R_parenblock = get(g:, 'R_parenblock',         1)
endif

if type(g:R_external_term) == v:t_number && g:R_external_term == 0
    g:R_vimpager = get(g:, 'R_vimpager', 'vertical')
else
    g:R_vimpager = get(g:, 'R_vimpager', 'tab')
endif

g:R_objbr_place      = get(g:, "R_objbr_place",    "script,right")
g:R_source_args      = get(g:, "R_source_args",                "")
g:R_user_maps_only   = get(g:, "R_user_maps_only",              0)
g:R_latexcmd         = get(g:, "R_latexcmd",          ["default"])
g:R_texerr           = get(g:, "R_texerr",                      1)
g:R_rmd_environment  = get(g:, "R_rmd_environment",  ".GlobalEnv")
g:R_rmarkdown_args   = get(g:, "R_rmarkdown_args",             "")

if type(g:R_external_term) == v:t_number && g:R_external_term == 0
    g:R_save_win_pos = 0
    g:R_arrange_windows  = 0
endif
if has("win32")
    g:R_save_win_pos    = get(g:, "R_save_win_pos",    1)
    g:R_arrange_windows = get(g:, "R_arrange_windows", 1)
else
    g:R_save_win_pos    = get(g:, "R_save_win_pos",    0)
    g:R_arrange_windows = get(g:, "R_arrange_windows", 0)
endif

# The environment variables VIMR_COMPLCB and VIMR_COMPLInfo must be defined
# before starting the vimrserver because it needs them at startup.
# The R_set_omnifunc must be defined before finalizing the source of common_buffer.vim.
g:rplugin.update_glbenv = 0
$VIMR_COMPLCB = 'g:SetComplMenu'
$VIMR_COMPLInfo = "g:SetComplInfo"
g:R_set_omnifunc = get(g:, "R_set_omnifunc", ["r",  "rmd", "quarto", "rnoweb", "rhelp", "rrst"])

if len(g:R_set_omnifunc) > 0
    g:rplugin.update_glbenv = 1
endif

# Look for invalid options

var objbrplace = split(g:R_objbr_place, ',')
if len(objbrplace) > 2
    g:RWarningMsg('Too many options for R_objbr_place.')
    g:rplugin.failed = 1
    finish
endif
for pos in objbrplace
    if pos !=? 'console' && pos !=? 'script' &&
                pos !=# 'left' && pos !=# 'right' &&
                pos !=# 'LEFT' && pos !=# 'RIGHT' &&
                pos !=# 'above' && pos !=# 'below' &&
                pos !=# 'TOP' && pos !=# 'BOTTOM'
        g:RWarningMsg('Invalid value for R_objbr_place: "' .. pos .. ". Please see Vim-R's documentation.")
        g:rplugin.failed = 1
        finish
    endif
endfor

# ==============================================================================
# Check if default mean of communication with R is OK
# ==============================================================================

# Minimum width for the Object Browser
if g:R_objbr_w < 10
    g:R_objbr_w = 10
endif

# Minimum height for the Object Browser
if g:R_objbr_h < 4
    g:R_objbr_h = 4
endif

# Control the menu 'R' and the tool bar buttons
if !has_key(g:rplugin, "hasmenu")
    g:rplugin.hasmenu = 0
endif

autocmd BufEnter * call g:RBufEnter()
if &filetype != "rbrowser"
    autocmd VimLeave * call g:RVimLeave()
endif

if v:windowid != 0 && $WINDOWID == ""
    $WINDOWID = string(v:windowid)
endif

# Current view of the object browser: .GlobalEnv X loaded libraries
g:rplugin.curview = "None"

execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/vimrcom.vim"

# SyncTeX options
g:rplugin.has_wmctrl = 0

# Initial List of files to be deleted on VimLeave
g:rplugin.del_list = [
            g:rplugin.tmpdir .. '/run_R_stdout',
            g:rplugin.tmpdir .. '/run_R_stderr']

# Set the name of R executable
if exists("g:R_app")
    g:rplugin.R = g:R_app
    if !has("win32") && !exists("g:R_cmd")
        g:R_cmd = g:R_app
    endif
else
    if has("win32")
        if type(g:R_external_term) == v:t_number && g:R_external_term == 0
            g:rplugin.R = "Rterm.exe"
        else
            g:rplugin.R = "Rgui.exe"
        endif
    else
        g:rplugin.R = "R"
    endif
endif

# Set the name of R executable to be used in `R CMD`
if exists("g:R_cmd")
    g:rplugin.Rcmd = g:R_cmd
else
    g:rplugin.Rcmd = "R"
endif

if exists("g:RStudio_cmd")
    execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/rstudio.vim"
endif

if has("win32")
    execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/windows.vim"
else
    execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/unix.vim"
endif

if type(g:R_external_term) == v:t_number && g:R_external_term == 0
    execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/vimbuffer.vim"
endif

if g:R_enable_comment
    execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/comment.vim"
endif

if has("gui_running")
    execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/gui_running.vim"
endif

autocmd FuncUndefined StartR execute "source " .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/start_r.vim"

def g:GlobalRInit(...args: list<any>)
    g:rplugin.debug_info['Time']['GlobalRInit'] = reltime()
    execute 'source ' .. substitute(g:rplugin.home, " ", "\\ ", "g") .. "/R/start_server.vim"
    # Set security variables — VIMR_ID is a random session ID; VIMR_SECRET
    # is generated by vimrserver using OS crypto APIs and sent back via stdout.
    $VIMR_ID = string(rand(srand()))
    g:CheckVimcomVersion()
    g:rplugin.debug_info['Time']['GlobalRInit'] = reltimefloat(reltime(g:rplugin.debug_info['Time']['GlobalRInit'], reltime()))
enddef

if v:vim_did_enter == 0
    autocmd VimEnter * call timer_start(1, "g:GlobalRInit")
else
    timer_start(1, "g:GlobalRInit")
endif
g:rplugin.debug_info['Time']['common_global.vim'] = reltimefloat(reltime(g:rplugin.debug_info['Time']['common_global.vim'], reltime()))
