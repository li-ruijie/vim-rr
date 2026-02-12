vim9script

# Functions that are called only after omni completion is triggered
#
# The menu must be built and rendered very quickly (< 100ms) to make auto
# completion feasible. That is, the data must be cached (OK, vim.bol.R),
# indexed (not yet) and processed quickly (OK, vimrserver.c).
#
# The float window that appears when an item is selected can be slower.
# That is, we can call a function in vimcom to get the contents of the float
# window.

if exists("g:did_vimr_complete")
    finish
endif
g:did_vimr_complete = 1

g:rplugin.compl_float_win = 0
g:rplugin.compl_event = {}
g:rplugin.compl_cls = ''
g:rplugin.compl_usage = ''

def g:FormatInfo(width: number, needblank: number): list<string>
    var ud = g:rplugin.compl_event['completed_item']['user_data']
    g:rplugin.compl_cls = ud['cls']

    # Some regions delimited by non separable spaces (digraph NS)
    var info = ''
    if ud['cls'] == 'a'
        info = ' ' .. g:FormatTxt(ud['argument'], ' ', " \n  ", width - 1)
    elseif ud['cls'] == 'l'
        info = ' ' .. g:FormatTxt(ud['ttl'], ' ', " \n ", width - 1) .. ' '
        info ..= "\n————\n"
        info ..= ' ' .. g:FormatTxt(ud['descr'], ' ', " \n ", width - 1)
    else
        if ud['descr'] != ''
            info = ' ' .. g:FormatTxt(ud['descr'], ' ', " \n ", width - 1)
        endif
        if ud['cls'] == 'f'
            if g:rplugin.compl_usage != ''
                if ud['descr'] != ''
                    info ..= "\n————\n"
                endif
                var usg = "```{R} \n "
                # Avoid the prefix ', \n  ' if function name + first argment is longer than width
                usg ..= g:FormatTxt(g:rplugin.compl_usage, ', ', ",  \n   ", width)
                usg = substitute(usg, "^,  \n   ", "", "")
                usg ..= "\n```\n"
                info ..= usg
            endif
        endif
        if width > 29 && has_key(ud, 'summary')
            info ..= "\n```{Rout} \n" .. join(ud['summary'], "\n ") .. "\n```\n"
        endif
    endif

    if info == ''
        return []
    endif
    var lines: list<string>
    if needblank
        lines = [''] + split(info, "\n")
    else
        lines = split(info, "\n")
    endif
    return lines
enddef

def g:CreateNewFloat(...args: list<any>)
    # The popup menu might already be closed.
    if !pumvisible()
        return
    endif

    if len(g:rplugin.compl_event) == 0
        return
    endif

    var wrd = g:rplugin.compl_event['completed_item']['word']

    # Get the required height for a standard float preview window
    var flines = g:FormatInfo(60, 1)
    if len(flines) == 0
        g:CloseFloatWin()
        return
    endif
    var reqh = len(flines) > 15 ? 15 : len(flines)

    # Ensure that some variables are integers:
    var mc = float2nr(g:rplugin.compl_event['col'])
    var mr = float2nr(g:rplugin.compl_event['row'])
    var mw = float2nr(g:rplugin.compl_event['width'])
    var mh = float2nr(g:rplugin.compl_event['height'])

    # Default position and size of float window (at the right side of the popup menu)
    var has_space = 1
    var needblank = 0
    var frow = mr
    var flwd = 60
    var fanchor = 'NW'
    var fcol = mc + mw + g:rplugin.compl_event['scrollbar']

    # Required to fix the position and size of the float window
    var dspwd = &columns
    var freebelow = (mr == (line('.') - line('w0')) ? &lines - mr - mh : &lines - mr) - 3
    var freeright = dspwd - mw - mc - g:rplugin.compl_event['scrollbar']
    var freeleft = mc - 1
    var freetop = mr - 1

    # If there is enough vertical space, open the window beside the menu
    if freebelow > reqh && (freeright > 30 || freeleft > 30)
        if freeright > 30
            # right side
            flwd = freeright > 60 ? 60 : freeright
        else
            # left side
            flwd = (mc - 1) > 60 ? 60 : (mc - 1)
            fcol = mc - 1
            fanchor = 'NE'
        endif
    else
        # If there is enough vertical space and enough right space, then, if the menu
        #   - is below the current line, open the window below the menu
        #   - is above the current line, open the window above the menu
        freeright = dspwd - mc
        var freeabove = mr - 1
        freebelow = &lines - mr - mh - 3

        if freeright > 45 && (mr == (line('.') - line('w0') + 1)) && freebelow > reqh
            # below the menu
            flwd = freeright > 60 ? 60 : freeright
            fcol = mc - 1
            frow = mr + mh
            needblank = 1
        elseif freeright > 45 && (line('.') - line('w0') + 1) > mr && freeabove > reqh
            # above the menu
            flwd = freeright > 60 ? 60 : freeright
            fcol = mc - 1
            frow = mr
            fanchor = 'SW'
        else
            # Finally, check if it's possible to open the window
            # either on the top or on the bottom of the display
            flwd = dspwd
            flines = g:FormatInfo(flwd, 0)
            reqh = len(flines) > 15 ? 15 : len(flines)
            fcol = 0

            if freeabove > reqh || (freeabove > 3 && freeabove > freebelow)
                # top
                frow = 0
            elseif freebelow > 3
                # bottom
                frow = &lines
                fanchor = 'SW'
            else
                # no space available
                has_space = 0
            endif
        endif
    endif

    if len(flines) == 0 || has_space == 0
        return
    endif

    # Now that the position is defined, calculate the available height
    var maxh: number
    if frow == &lines
        if mr == (line('.') - line('w0') + 1)
            maxh = &lines - mr - mh - 2
        else
            maxh = &lines - line('.') + line('w0') - 2
        endif
        needblank = 1
    elseif frow == 0
        maxh = mr - 3
    else
        maxh = &lines - frow - 2
    endif

    # Open the window if there is enough available height
    if maxh < 2
        return
    endif

    flines = g:FormatInfo(flwd, needblank)
    # replace ———— with a complete line
    var realwidth = 10
    for lin in flines
        if strdisplaywidth(lin) > realwidth
            realwidth = strdisplaywidth(lin)
        endif
    endfor

    if has("win32")
        map(flines, 'substitute(v:val, "^————$", repeat("-", realwidth), "")')
    else
        map(flines, 'substitute(v:val, "^————$", repeat("—", realwidth), "")')
    endif

    var flht = (len(flines) > maxh) ? maxh : len(flines)

    var fpos: string
    if fanchor == 'NE'
        fpos = 'topright'
    elseif fanchor == 'SW'
        fpos = 'botleft'
        frow -= 1
    else
        fpos = 'topleft'
    endif
    if g:rplugin.compl_float_win
        popup_close(g:rplugin.compl_float_win)
    endif
    g:rplugin.compl_float_win = popup_create(flines, {
        line: frow + 1, col: fcol, pos: fpos,
        maxheight: flht})
enddef

def g:CloseFloatWin(...args: list<any>)
    popup_close(g:rplugin.compl_float_win)
    g:rplugin.compl_float_win = 0
enddef

def g:OnCompleteDone()
    g:CloseFloatWin()
enddef

def g:AskForComplInfo()
    if ! pumvisible()
        return
    endif

    # Other plugins fill the 'user_data' dictionary
    if has_key(v:event, 'completed_item') && has_key(v:event['completed_item'], 'word')
        g:rplugin.compl_event = deepcopy(v:event)
        if has_key(g:rplugin.compl_event['completed_item'], 'user_data') &&
                type(g:rplugin.compl_event['completed_item']['user_data']) == v:t_dict
            if has_key(g:rplugin.compl_event['completed_item']['user_data'], 'pkg')
                var pkg = g:rplugin.compl_event['completed_item']['user_data']['pkg']
                var wrd = g:rplugin.compl_event['completed_item']['word']
                # Request function description and usage
                g:JobStdin(g:rplugin.jobs["Server"], "6" .. wrd .. "\002" .. pkg .. "\n")
            elseif has_key(g:rplugin.compl_event['completed_item']['user_data'], 'cls')
                if g:rplugin.compl_event['completed_item']['user_data']['cls'] == 'v'
                    var pkg = g:rplugin.compl_event['completed_item']['user_data']['env']
                    var wrd = g:rplugin.compl_event['completed_item']['user_data']['word']
                    g:JobStdin(g:rplugin.jobs["Server"], "6" .. wrd .. "\002" .. pkg .. "\n")
                else
                    # Can't open a float window from here directly:
                    timer_start(1, 'g:CreateNewFloat', {})
                endif
            elseif g:rplugin.compl_float_win
                g:CloseFloatWin()
            endif
        endif
    elseif g:rplugin.compl_float_win
        g:CloseFloatWin()
    endif
enddef

def g:FinishGlbEnvFunArgs(fnm: string, txt: string)
    var usage = substitute(txt, "\x14", "\n", "g")
    usage = substitute(usage, "\x13", "''", "g")
    usage = substitute(usage, "\005", '\\"', "g")
    usage = substitute(usage, "\x12", "'", "g")
    usage = '[' .. usage .. ']'
    var usagelist = eval(usage)
    map(usagelist, 'join(v:val, " = ")')
    var usagestr = join(usagelist, ", ")
    g:rplugin.compl_usage = fnm .. '(' .. usagestr .. ')'
    g:rplugin.compl_event['completed_item']['user_data']['descr'] = ''
    g:CreateNewFloat()
enddef

def g:FinishGetSummary(txt: string)
    var summary = split(substitute(txt, "\x13", "'", "g"), "\x14")
    g:rplugin.compl_event['completed_item']['user_data']['summary'] = summary
    g:CreateNewFloat()
enddef

def g:SetComplInfo(dctnr: dict<any>)
    # Replace user_data with the complete version
    g:rplugin.compl_event['completed_item']['user_data'] = deepcopy(dctnr)

    if has_key(dctnr, 'cls') && dctnr['cls'] == 'f'
        var usage = deepcopy(dctnr['usage'])
        map(usage, 'join(v:val, " = ")')
        var usagestr = join(usage, ", ")
        g:rplugin.compl_usage = dctnr['word'] .. '(' .. usagestr .. ')'
    elseif has_key(dctnr, 'word') && dctnr['word'] =~ '\k\{-}\$\k\{-}'
        g:SendToVimcom("E", 'vimcom:::vim.get.summary(' .. dctnr['word'] .. ', 59)')
        return
    endif

    if len(dctnr) > 0
        g:CreateNewFloat()
    else
        g:CloseFloatWin()
    endif
enddef

# We can't transfer this function to the vimrserver because
# vimcom:::vim_complete_args runs the function methods(), and we couldn't do
# something similar in the vimrserver.
def g:GetRArgs(id: any, base: string, rkeyword0: string, listdf: any, firstobj: string, pkg: string, isfarg: any)
    if rkeyword0 == ""
        return
    endif
    var msg = 'vimcom:::vim_complete_args("' .. id .. '", "' .. rkeyword0 .. '", "' .. base .. '"'
    if firstobj != ""
        msg ..= ', firstobj = "' .. firstobj .. '"'
    elseif pkg != ""
        msg ..= ', pkg = ' .. pkg
    endif
    if firstobj != '' && ((listdf == 1 && !isfarg) || listdf == 2)
        msg ..= ', ldf = TRUE'
    endif
    msg ..= ')'

    # Save documentation of arguments to be used by vimrserver
    g:SendToVimcom("E", msg)
enddef

def g:FindStartRObj(): number
    var line = getline(".")
    var lnum = line(".")
    var cpos = getpos(".")
    var idx = cpos[2] - 2
    var idx2 = cpos[2] - 2
    if idx2 < 0
        g:rplugin.compl_argkey = ''
        return 0
    endif
    if line[idx2] == ' ' || line[idx2] == ',' || line[idx2] == '('
        idx2 = cpos[2]
        g:rplugin.compl_argkey = ''
    else
        var idx1 = idx2
        while line[idx1] =~ '\w' || line[idx1] == '.' || line[idx1] == '_' ||
                line[idx1] == ':' || line[idx1] == '$' || line[idx1] == '@' ||
                (line[idx1] > "\x80" && line[idx1] < "\xf5")
            idx1 -= 1
        endwhile
        idx1 += 1
        var argkey = strpart(line, idx1, idx2 - idx1 + 1)
        idx2 = cpos[2] - strlen(argkey)
        g:rplugin.compl_argkey = argkey
    endif
    return idx2 - 1
enddef

def g:NeedRArguments(line: string, cpos: list<number>): list<any>
    # Check if we need function arguments
    var ln = line
    var lnum = line(".")
    var cp = cpos
    var idx = cp[2] - 2
    if idx < 0
        return []
    endif
    var np = 1
    var nl = 0
    # Look up to 10 lines above for an opening parenthesis
    while nl < 10
        if ln[idx] == '('
            np -= 1
        elseif ln[idx] == ')'
            np += 1
        endif
        if np == 0
            # The opening parenthesis was found
            var rkeyword0 = g:RGetKeyword(lnum, idx)
            var firstobj = ""
            var ispiped = v:false
            var listdf: any = 0
            var pkg: string
            if rkeyword0 =~ "::"
                pkg = '"' .. substitute(rkeyword0, "::.*", "", "") .. '"'
                rkeyword0 = substitute(rkeyword0, ".*::", "", "")
            else
                var rkeyword1 = rkeyword0
                if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
                    for fnm in g:R_fun_data_1
                        if fnm == rkeyword0
                            listdf = 1
                            break
                        endif
                    endfor
                    for key in keys(g:R_fun_data_2)
                        if g:R_fun_data_2[key][0] == '*' || index(g:R_fun_data_2[key], rkeyword0) > -1
                            listdf = 2
                            rkeyword1 = key
                            break
                        endif
                    endfor
                    if listdf == 2
                        # Get first object of nesting function, if any
                        if ln =~ rkeyword1 .. '\s*('
                            idx = stridx(ln, rkeyword1)
                        else
                            ln = getline(lnum - 1)
                            if ln =~ rkeyword1 .. '\s*('
                                idx = stridx(ln, rkeyword1)
                            else
                                rkeyword1 = rkeyword0
                                listdf = 0
                            endif
                        endif
                    endif
                    var ro = g:RGetFirstObj(rkeyword1, ln, idx, listdf)
                    firstobj = ro[0]
                    ispiped = ro[1]
                endif
                pkg = ""
            endif
            return [rkeyword0, listdf, firstobj, ispiped, pkg, lnum, cp]
        endif
        idx -= 1
        if idx <= 0
            lnum -= 1
            if lnum == 0
                break
            endif
            ln = getline(lnum)
            idx = strlen(ln)
            nl += 1
        endif
    endwhile
    return []
enddef

def g:SetComplMenu(id: any, cmn: list<any>)
    g:rplugin.compl_menu = deepcopy(cmn)
    for idx in range(len(g:rplugin.compl_menu))
        g:rplugin.compl_menu[idx]['word'] = substitute(g:rplugin.compl_menu[idx]['word'], "\x13", "'", "g")
    endfor
    g:rplugin.waiting_compl_menu = 0
enddef

g:rplugin.completion_id = 0
def g:CompleteR(findstart: number, base: string): any
    if findstart
        var lin = getline(".")
        var isInR = b:IsInRCode(0)
        if (&filetype == 'quarto' || &filetype == 'rmd') && isInR == 1 && lin =~ '^#| ' && lin !~ '^#| \k.*:'
            g:rplugin.compl_type = 4
            var ywrd = substitute(lin, '^#| *', '', '')
            return stridx(lin, ywrd)
        elseif b:rplugin_knitr_pattern != '' && lin =~ b:rplugin_knitr_pattern
            g:rplugin.compl_type = 3
            return g:FindStartRObj()
        elseif isInR == 0 && b:rplugin_non_r_omnifunc != ''
            g:rplugin.compl_type = 2
            var Ofun = function(b:rplugin_non_r_omnifunc)
            return Ofun(findstart, base)
        else
            g:rplugin.compl_type = 1
            return g:FindStartRObj()
        endif
    else
        g:rplugin.completion_id += 1
        if g:rplugin.compl_type == 4
            return g:CompleteQuartoCellOptions(base)
        elseif g:rplugin.compl_type == 3
            return g:CompleteChunkOptions(base)
        elseif g:rplugin.compl_type == 2
            var Ofun = function(b:rplugin_non_r_omnifunc)
            return Ofun(findstart, base)
        endif

        # The base might have changed because the user has hit the backspace key
        g:CloseFloatWin()

        var nra = g:NeedRArguments(getline("."), getpos("."))
        if len(nra) > 0
            var isfa = nra[3] ? v:false : g:IsFirstRArg(getline("."), nra[6])
            if (nra[0] == "library" || nra[0] == "require") && isfa
                g:rplugin.waiting_compl_menu = 1
                g:JobStdin(g:rplugin.jobs["Server"], "5" .. g:rplugin.completion_id .. "\003" .. "\004" .. base .. "\n")
                return g:WaitRCompletion()
            endif

            g:rplugin.waiting_compl_menu = 1
            if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
                g:GetRArgs(g:rplugin.completion_id, base, nra[0], nra[1], nra[2], nra[4], isfa)
                return g:WaitRCompletion()
            endif
        endif

        if base == ''
            # Require at least one character to try omni completion
            return []
        endif

        if exists('g:rplugin.compl_menu')
            unlet g:rplugin.compl_menu
        endif
        g:rplugin.waiting_compl_menu = 1
        g:JobStdin(g:rplugin.jobs["Server"], "5" .. g:rplugin.completion_id .. "\003" .. base .. "\n")
        return g:WaitRCompletion()
    endif
enddef

def g:WaitRCompletion(): any
    sleep 10m
    var nwait = 0
    while g:rplugin.waiting_compl_menu && nwait < 100
        nwait += 1
        sleep 10m
    endwhile
    if exists('g:rplugin.compl_menu')
        g:rplugin.is_completing = 1
        return g:rplugin.compl_menu
    endif
    return []
enddef

def g:CompleteChunkOptions(base: string): list<any>
    # https://yihui.org/knitr/options/#chunk-options (2021-04-19)
    var lines = json_decode(join(readfile(g:rplugin.home .. '/R/chunk_options.json')))

    var ktopt: list<any> = []
    for lin in lines
        lin['abbr'] = lin['word']
        lin['word'] = lin['word'] .. '='
        lin['menu'] = '= ' .. lin['menu']
        lin['user_data']['cls'] = 'k'
        ktopt += [deepcopy(lin)]
    endfor

    var rr: list<any> = []

    if strlen(base) > 0
        var newbase = '^' .. substitute(base, "\\$$", "", "")
        filter(ktopt, 'v:val["abbr"] =~ newbase')
    endif

    sort(ktopt)
    for kopt in ktopt
        add(rr, kopt)
    endfor
    return rr
enddef

def g:CompleteQuartoCellOptions(base: string): list<any>
    if !exists('g:rplugin.qchunk_opt_list')
        g:FillQuartoComplMenu()
    endif
    g:rplugin.cell_opt_list = deepcopy(g:rplugin.qchunk_opt_list)
    if strlen(base) > 0
        var newbase = '^' .. substitute(base, "\\$$", "", "")
        filter(g:rplugin.cell_opt_list, 'v:val["abbr"] =~ newbase')
    endif
    return g:rplugin.cell_opt_list
enddef

def g:IsFirstRArg(line: string, cpos: list<number>): number
    var ii = cpos[2] - 2
    while ii > 0
        if line[ii] == '('
            return 1
        endif
        if line[ii] == ','
            return 0
        endif
        ii -= 1
    endwhile
    return 0
enddef

def g:FillQuartoComplMenu()
    g:rplugin.qchunk_opt_list = []

    var quarto_yaml_intel: string
    if exists('g:R_quarto_intel')
        quarto_yaml_intel = g:R_quarto_intel
    else
        quarto_yaml_intel = ''
        if has('win32')
            var paths = split($PATH, ';')
            filter(paths, 'v:val =~? "quarto"')
            if len(paths) > 0
                var qjson = substitute(paths[0], 'bin$', 'share/editor/tools/yaml/yaml-intelligence-resources.json', '')
                qjson = substitute(qjson, '\\', '/', 'g')
                if filereadable(qjson)
                    quarto_yaml_intel = qjson
                endif
            endif
        elseif executable('quarto')
            var quarto_bin = exepath('quarto')
            var quarto_dir1 = substitute(quarto_bin, '\(.*\)/.\{-}/.*', '\1', 'g')
            if filereadable(quarto_dir1 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json')
                quarto_yaml_intel = quarto_dir1 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json'
            else
                quarto_bin = resolve(quarto_bin)
                var quarto_dir2 = substitute(quarto_bin, '\(.*\)/.\{-}/.*', '\1', 'g')
                if quarto_dir2 =~ '^\.\./'
                    while quarto_dir2 =~ '^\.\./'
                        quarto_dir2 = substitute(quarto_dir2, '^\.\./*', '', '')
                    endwhile
                    quarto_dir2 = quarto_dir1 .. '/' .. quarto_dir2
                endif
                if filereadable(quarto_dir2 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json')
                    quarto_yaml_intel = quarto_dir2 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json'
                endif
            endif
        endif
    endif

    if quarto_yaml_intel != ''
        var intel = json_decode(join(readfile(quarto_yaml_intel), "\n"))
        for key in ['schema/cell-attributes.yml',
                'schema/cell-cache.yml',
                'schema/cell-codeoutput.yml',
                'schema/cell-figure.yml',
                'schema/cell-include.yml',
                'schema/cell-layout.yml',
                'schema/cell-pagelayout.yml',
                'schema/cell-table.yml',
                'schema/cell-textoutput.yml']
            if !has_key(intel, key)
                continue
            endif
            var tmp = intel[key]
            for item in tmp
                if !has_key(item, 'name') || !has_key(item, 'description')
                    continue
                endif
                var abr = item['name']
                var wrd = abr .. ': '
                var descr = type(item['description']) == v:t_string ? item['description'] : item['description']['long']
                descr = substitute(descr, '\n', ' ', 'g')
                var dict = {word: wrd, abbr: abr, menu: '[opt]', user_data: {cls: 'k', descr: descr}}
                add(g:rplugin.qchunk_opt_list, dict)
            endfor
        endfor
    endif
enddef

def g:RComplAutCmds()
    if &filetype == "rnoweb" || &filetype == "rrst" || &filetype == "rmd" || &filetype == "quarto"
        if &omnifunc == "CompleteR"
            b:rplugin_non_r_omnifunc = ""
        else
            b:rplugin_non_r_omnifunc = &omnifunc
        endif
    endif
    if index(g:R_set_omnifunc, &filetype) > -1
        setlocal omnifunc=CompleteR
    endif

    # Test whether the autocommands were already defined to avoid getting them
    # registered three times
    if !exists('b:did_RBuffer_au')
        augroup RBuffer
            if index(g:R_set_omnifunc, &filetype) > -1
                autocmd CompleteChanged <buffer> g:AskForComplInfo()
                autocmd CompleteDone <buffer> g:OnCompleteDone()
            endif
        augroup END
    endif
    b:did_RBuffer_au = 1
enddef
