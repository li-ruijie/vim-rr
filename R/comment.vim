vim9script

# Get first and last selected lines
def g:RGetFL(mode: string): list<number>
    var fline: number
    var lline: number
    if mode == "normal"
        fline = line(".")
        lline = line(".")
    else
        fline = line("'<")
        lline = line("'>")
    endif
    if fline > lline
        var tmp = lline
        lline = fline
        fline = tmp
    endif
    return [fline, lline]
enddef

# Each file type defines a function to say whether the cursor is in a block of
# R code. Useful for Rmd, Rnw, Rhelp, Rdoc, etc...
def g:IsLineInRCode(vrb: number, line: number): bool
    var save_cursor = getpos(".")
    setpos(".", [0, line, 1, 0])
    var isR = b:IsInRCode(vrb) == 1
    setpos('.', save_cursor)
    return isR
enddef

var curtabstop = ''

def g:RSimpleCommentLine(mode: string, what: string)
    var [fline, lline] = g:RGetFL(mode)
    var cstr = g:R_rcomment_string
    if (&filetype == "rnoweb" || &filetype == "rhelp") && g:IsLineInRCode(0, fline) == 0
        cstr = "%"
    elseif (&filetype == "rmd" || &filetype == "quarto" || &filetype == "rrst") && g:IsLineInRCode(0, fline) == 0
        return
    endif

    if what == "c"
        for ii in range(fline, lline)
            setline(ii, cstr .. getline(ii))
        endfor
    else
        for ii in range(fline, lline)
            setline(ii, substitute(getline(ii), "^" .. cstr, "", ""))
        endfor
    endif
enddef

def g:RCommentLine(lnum: number, ind: number, cmt: string)
    var line = getline(lnum)
    cursor(lnum, 0)

    if line =~ '^\s*' .. cmt || line =~ '^\s*#'
        line = substitute(line, '^\s*' .. cmt, '', '')
        line = substitute(line, '^\s*#*', '', '')
        setline(lnum, line)
        normal! ==
    else
        if g:R_indent_commented
            while line =~ '^\s*\t'
                line = substitute(line, '^\(\s*\)\t', '\1' .. curtabstop, "")
            endwhile
            line = strpart(line, ind)
        endif
        line = cmt .. line
        setline(lnum, line)
        if g:R_indent_commented
            normal! ==
        endif
    endif
enddef

def g:RComment(mode: string)
    var cpos = getpos(".")
    var [fline, lline] = g:RGetFL(mode)

    # What comment string to use?
    var cmt: string
    if g:r_indent_ess_comments
        if g:R_indent_commented
            cmt = '## '
        else
            cmt = '### '
        endif
    else
        cmt = g:R_rcomment_string
    endif
    if (&filetype == "rnoweb" || &filetype == "rhelp") && g:IsLineInRCode(0, fline) == 0
        cmt = "%"
    elseif (&filetype == "rmd" || &filetype == "quarto" || &filetype == "rrst") && g:IsLineInRCode(0, fline) == 0
        return
    endif

    var lnum = fline
    var ind = &tw
    while lnum <= lline
        var idx = indent(lnum)
        if idx < ind
            ind = idx
        endif
        lnum += 1
    endwhile

    lnum = fline
    curtabstop = repeat(' ', &tabstop)
    while lnum <= lline
        g:RCommentLine(lnum, ind, cmt)
        lnum += 1
    endwhile
    cursor(cpos[1], cpos[2])
enddef

def g:MovePosRCodeComment(mode: string)
    var fline: number
    var lline: number
    if mode == "selection"
        fline = line("'<")
        lline = line("'>")
    else
        fline = line(".")
        lline = fline
    endif

    var cpos = g:r_indent_comment_column
    var lnum = fline
    while lnum <= lline
        var line = getline(lnum)
        var cleanl = substitute(line, '\s*#.*', "", "")
        var llen = strlen(cleanl)
        if llen > (cpos - 2)
            cpos = llen + 2
        endif
        lnum += 1
    endwhile

    lnum = fline
    while lnum <= lline
        g:MovePosRLineComment(lnum, cpos)
        lnum += 1
    endwhile
    cursor(fline, cpos + 1)
    if mode == "insert"
        startinsert!
    endif
enddef

def g:MovePosRLineComment(lnum: number, cpos: number)
    var line = getline(lnum)

    var ok = 1

    if &filetype == "rnoweb"
        if search("^<<", "bncW") > search("^@", "bncW")
            ok = 1
        else
            ok = 0
        endif
        if line =~ "^<<.*>>=$"
            ok = 0
        endif
        if ok == 0
            g:RWarningMsg("Not inside an R code chunk.")
            return
        endif
    endif

    if &filetype == "rhelp"
        var lastsection = search('^\\[a-z]*{', "bncW")
        var secname = getline(lastsection)
        if secname =~ '^\\usage{' || secname =~ '^\\examples{' || secname =~ '^\\dontshow{' || secname =~ '^\\dontrun{' || secname =~ '^\\donttest{' || secname =~ '^\\testonly{' || secname =~ '^\\method{.*}{.*}('
            ok = 1
        else
            ok = 0
        endif
        if ok == 0
            g:RWarningMsg("Not inside an R code section.")
            return
        endif
    endif

    if line !~ '#'
        # Write the comment character
        line = line .. repeat(' ', cpos)
        line = substitute(line, '^\(.\{' .. (cpos - 1) .. '}\).*', '\1# ', '')
        setline(lnum, line)
    else
        # Align the comment character(s)
        line = substitute(line, '\s*#', '#', "")
        var idx = stridx(line, '#')
        var str1 = strpart(line, 0, idx)
        var str2 = strpart(line, idx)
        line = str1 .. repeat(' ', cpos - idx - 1) .. str2
        setline(lnum, line)
    endif
enddef

def g:RCreateCommentMaps()
    g:RCreateMaps('ni', 'RToggleComment',   'xx', ':call g:RComment("normal")')
    g:RCreateMaps('v',  'RToggleComment',   'xx', ':call g:RComment("selection")')
    g:RCreateMaps('ni', 'RSimpleComment',   'xc', ':call g:RSimpleCommentLine("normal", "c")')
    g:RCreateMaps('v',  'RSimpleComment',   'xc', ':call g:RSimpleCommentLine("selection", "c")')
    g:RCreateMaps('ni', 'RSimpleUnComment', 'xu', ':call g:RSimpleCommentLine("normal", "u")')
    g:RCreateMaps('v',  'RSimpleUnComment', 'xu', ':call g:RSimpleCommentLine("selection", "u")')
    g:RCreateMaps('ni', 'RRightComment',     ';', ':call g:MovePosRCodeComment("normal")')
    g:RCreateMaps('v',  'RRightComment',     ';', ':call g:MovePosRCodeComment("selection")')
enddef

g:R_indent_commented = get(g:, "R_indent_commented", 1)
if !exists("g:r_indent_ess_comments")
    g:r_indent_ess_comments = 0
endif
if g:r_indent_ess_comments
    if g:R_indent_commented
        g:R_rcomment_string = get(g:, "R_rcomment_string", "## ")
    else
        g:R_rcomment_string = get(g:, "R_rcomment_string", "### ")
    endif
else
    g:R_rcomment_string = get(g:, "R_rcomment_string", "# ")
endif
