vim9script noclear

if exists("g:did_vimr_rnw_fun")
    finish
endif
g:did_vimr_rnw_fun = 1

def g:RWriteChunk()
    if getline(".") =~ "^\\s*$" && g:RnwIsInRCode(0) == 0
        var curline = line(".")
        setline(curline, "<<>>=")
        append(curline, ["@", ""])
        cursor(curline, 2)
    else
        execute "normal! a<"
    endif
enddef

def g:RnwIsInRCode(vrb: number): number
    var chunkline = search("^<<", "bncW")
    var docline = search("^@", "bncW")
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

def g:RnwPreviousChunk()
    var curline = line(".")
    if g:RnwIsInRCode(0) == 1
        var i = search("^<<.*$", "bnW")
        if i != 0
            cursor(i - 1, 1)
        endif
    endif
    var i = search("^<<.*$", "bnW")
    if i == 0
        cursor(curline, 1)
        g:RWarningMsg("There is no previous R code chunk to go.")
    else
        cursor(i + 1, 1)
    endif
enddef

def g:RnwNextChunk()
    var i = search("^<<.*$", "nW")
    if i == 0
        g:RWarningMsg("There is no next R code chunk to go.")
    else
        cursor(i + 1, 1)
    endif
enddef


# Because this function delete files, it will not be documented.
# If you want to try it, put in your vimrc:
#
# let R_rm_knit_cache = 1
#
# If don't want to answer the question about deleting files, and
# if you trust this code more than I do, put in your vimrc:
#
# let R_ask_rm_knitr_cache = 0
#
# Note that if you have the string "cache.path=" in more than one place only
# the first one above the cursor position will be found. The path must be
# surrounded by quotes; if it's an R object, it will not be recognized.
def g:RKnitRmCache()
    var lnum = search('\<cache\.path\>\s*=', 'bnwc')
    var pathdir: string
    if lnum == 0
        pathdir = "cache/"
    else
        var pathregexpr = '.*\<cache\.path\>\s*=\s*[' .. "'" .. '"]\(.\{-}\)[' .. "'" .. '"].*'
        pathdir = substitute(getline(lnum), pathregexpr, '\1', '')
        if pathdir !~ '/$'
            pathdir ..= '/'
        endif
    endif
    var cleandir: number
    if exists("g:R_ask_rm_knitr_cache") && g:R_ask_rm_knitr_cache == 0
        cleandir = 1
    else
        inputsave()
        var answer = input('Delete all files from "' .. pathdir .. '"? [y/n]: ')
        inputrestore()
        if answer == "y"
            cleandir = 1
        else
            cleandir = 0
        endif
    endif
    normal! :<Esc>
    if cleandir
        var safe_pathdir = substitute(pathdir, '"', '\\"', 'g')
        g:SendCmdToR('rm(list=ls(all.names=TRUE)); unlink("' .. safe_pathdir .. '*")')
    endif
enddef

var check_latexcmd = false

# Weave and compile the current buffer content
def g:RWeave(bibtex: string, knit: number, pdf: number)
    if !check_latexcmd
        check_latexcmd = true
        if g:R_latexcmd[0] == "default"
            if !executable("xelatex")
                if executable("pdflatex")
                    g:R_latexcmd = ['latexmk', '-pdf', '-pdflatex="pdflatex %O -file-line-error -interaction=nonstopmode -synctex=1 %S"']
                else
                    g:RWarningMsg("You should install 'xelatex' to be able to compile pdf documents.")
                endif
            endif
            if (g:R_latexcmd[0] == "default" || g:R_latexcmd[0] == "latexmk") && !executable("latexmk")
                if executable("xelatex")
                    g:R_latexcmd = ['xelatex', '-file-line-error', '-interaction=nonstopmode', '-synctex=1']
                elseif executable("pdflatex")
                    g:R_latexcmd = ['pdflatex', '-file-line-error', '-interaction=nonstopmode', '-synctex=1']
                else
                    g:RWarningMsg("You should install both 'xelatex' and 'latexmk' to be able to compile pdf documents.")
                endif
            endif
        endif
    endif

    update
    var rnwdir = expand("%:p:h")
    if has("win32")
        rnwdir = substitute(rnwdir, '\\', '/', 'g')
    endif
    var pdfcmd = 'vim.interlace.rnoweb(' .. g:RString(expand("%:t")) .. ', rnwdir = ' .. g:RString(rnwdir)

    if knit == 0
        pdfcmd = pdfcmd .. ', knit = FALSE'
    endif

    if pdf == 0
        pdfcmd = pdfcmd .. ', buildpdf = FALSE'
    endif

    if g:R_latexcmd[0] != "default"
        pdfcmd = pdfcmd .. ", latexcmd = '" .. g:R_latexcmd[0] .. "'"
        if len(g:R_latexcmd) == 1
            pdfcmd = pdfcmd .. ", latexargs = character()"
        else
            pdfcmd = pdfcmd .. ", latexargs = c('" .. join(g:R_latexcmd[1 :], "', '") .. "')"
        endif
    endif

    if g:R_synctex == 0
        pdfcmd = pdfcmd .. ", synctex = FALSE"
    endif

    if bibtex == "bibtex"
        pdfcmd = pdfcmd .. ", bibtex = TRUE"
    endif

    if pdf == 0 || g:R_openpdf == 0 || b:pdf_is_open
        pdfcmd = pdfcmd .. ", view = FALSE"
    endif

    if pdf && g:R_openpdf == 1
        b:pdf_is_open = 1
    endif

    if exists('g:R_latex_build_dir')
        pdfcmd ..= ', builddir=' .. g:RString(g:R_latex_build_dir)
    endif

    if knit == 0 && exists("g:R_sweaveargs")
        pdfcmd = pdfcmd .. ", " .. g:R_sweaveargs
    endif

    pdfcmd = pdfcmd .. ")"
    g:SendCmdToR(pdfcmd)
enddef

# Send Sweave chunk to R
def g:RnwSendChunkToR(e: string, m: string)
    if g:RnwIsInRCode(1) == 2
        cursor(line(".") + 1, 1)
    elseif g:RnwIsInRCode(1) == 0
        return
    endif
    var chunkline = search("^<<", "bncW") + 1
    var docline = search("^@", "ncW") - 1
    var lines = getline(chunkline, docline)
    var ok = g:RSourceLines(lines, e, "chunk")
    if ok == 0
        return
    endif
    if m == "down"
        g:RnwNextChunk()
    endif
enddef

# The file that the line "% !Rnw root =" of the current buffer names, with
# its directory. A relative name is taken in the directory of the buffer,
# where SyncTeX_forward() looks for the concordance of the master. The
# directory is joined to the name as text, and simplify() expands nothing,
# so a bracket or "$" in a name stays as it is.
def RootFile(root: string): string
    var path = root =~ '^\(/\|\a:[/\\]\)' ? root : expand("%:p:h") .. "/" .. root
    return simplify(has("win32") ? substitute(path, '\\', '/', 'g') : path)
enddef

def g:SyncTeX_GetMaster(): string
    if filereadable(expand("%:p:r") .. "-concordance.tex")
        if has("win32")
            return substitute(expand("%:p:r"), '\\', '/', 'g')
        else
            return expand("%:p:r")
        endif
    endif

    var ischild = search('% *!Rnw *root *=', 'bwn')
    if ischild > 0
        var mfile = substitute(getline(ischild), '.*% *!Rnw *root *= *\(.*\) *', '\1', '')
        return substitute(RootFile(mfile), '\....$', '', '')
    endif

    # Maybe this buffer is a master Rnoweb not compiled yet.
    if has("win32")
        return substitute(expand("%:p:r"), '\\', '/', 'g')
    else
        return expand("%:p:r")
    endif
enddef

# See http://www.stats.uwo.ca/faculty/murdoch/9864/Sweave.pdf page 25
def g:SyncTeX_readconc(basenm: string): dict<list<any>>
    var texidx = 0
    var rnwidx = 0
    var ntexln = len(readfile(basenm .. ".tex"))
    var lstexln = range(1, ntexln)
    # An empty name and line 0 mark the TeX lines that the concordance does
    # not cover, which the callers report as not found.
    var lsrnwf: list<any> = repeat([''], ntexln)
    var lsrnwl: list<any> = repeat([0], ntexln)
    var conc = readfile(basenm .. "-concordance.tex")
    var idx = 0
    var maxidx = len(conc)
    while idx < maxidx && texidx < ntexln && conc[idx] =~ "Sconcordance"
        var texf = substitute(conc[idx], '\\Sconcordance{concordance:\(.\{-}\):.*', '\1', "g")
        var rnwf = substitute(conc[idx], '\\Sconcordance{concordance:.\{-}:\(.\{-}\):.*', '\1', "g")
        idx += 1
        var concnum = ""
        while idx < maxidx && conc[idx] !~ "Sconcordance"
            concnum = concnum .. conc[idx]
            idx += 1
        endwhile
        concnum = substitute(concnum, '%', '', 'g')
        concnum = substitute(concnum, '}', '', '')
        var concl = split(concnum)
        if len(concl) == 0
            continue
        endif
        var ii = 0
        var maxii = len(concl) - 2
        var rnwl = str2nr(concl[0])
        lsrnwl[texidx] = rnwl
        lsrnwf[texidx] = rnwf
        texidx += 1
        while ii < maxii && texidx < ntexln
            ii += 1
            var lnrange = range(1, str2nr(concl[ii]))
            ii += 1
            for iii in lnrange
                if texidx >= ntexln
                    break
                endif
                rnwl += str2nr(concl[ii])
                lsrnwl[texidx] = rnwl
                lsrnwf[texidx] = rnwf
                texidx += 1
            endfor
        endwhile
    endwhile
    return {texlnum: lstexln, rnwfile: lsrnwf, rnwline: lsrnwl}
enddef

# The file name comes from a PDF viewer or from a concordance file. Its
# buffer is given to the Ex commands below by its number, since in a name a
# bar would start another command and a percent sign would stand for the
# current file. bufnr() takes a name for a pattern, so that "a[1].tex" gives
# the buffer of "a1.tex", and bufadd() gives the number of the buffer that has
# the name itself, which bufloaded() has found.
def g:GoToBuf(rnwbn: string, rnwf: string, basedir: string, rnwln: number): number
    if expand("%:t") != rnwbn
        if bufloaded(basedir .. '/' .. rnwf)
            var savesb = &switchbuf
            set switchbuf=useopen,usetab
            execute "sb " .. bufadd(basedir .. '/' .. rnwf)
            execute "set switchbuf=" .. savesb
        elseif bufloaded(rnwf)
            var savesb = &switchbuf
            set switchbuf=useopen,usetab
            execute "sb " .. bufadd(rnwf)
            execute "set switchbuf=" .. savesb
        else
            if filereadable(basedir .. '/' .. rnwf)
                g:RGoToFile('tab sbuffer', basedir .. '/' .. rnwf)
            elseif filereadable(rnwf)
                g:RGoToFile('tab sbuffer', rnwf)
            else
                g:RWarningMsg('Could not find either "' .. rnwbn .. ' or "' .. rnwf .. '" in "' .. basedir .. '".')
                return 0
            endif
        endif
    endif
    cursor(rnwln, 1)
    redraw
    return 1
enddef

def g:SyncTeX_backward(fname: string, ln: number)
    var flnm = substitute(fname, '/\./', '/', '')   # Okular
    var basenm = substitute(flnm, "\....$", "", "")   # Delete extension
    var basedir: string
    if basenm =~ "/"
        basedir = substitute(basenm, '\(.*\)/.*', '\1', '')
    else
        basedir = '.'
    endif
    var rnwln = 0
    var rnwf = ''
    if filereadable(basenm .. "-concordance.tex")
        if !filereadable(basenm .. ".tex")
            g:RWarningMsg('SyncTeX [Vim-R]: "' .. basenm .. '.tex" not found.')
            return
        endif
        var concdata = g:SyncTeX_readconc(basenm)
        var texlnum = concdata["texlnum"]
        var rnwfile = concdata["rnwfile"]
        var rnwline = concdata["rnwline"]
        for ii in range(len(texlnum))
            if texlnum[ii] >= ln
                rnwf = rnwfile[ii]
                rnwln = rnwline[ii]
                break
            endif
        endfor
        if rnwln == 0
            g:RWarningMsg("Could not find Rnoweb source line.")
            return
        endif
    else
        if filereadable(basenm .. ".Rnw") || filereadable(basenm .. ".rnw")
            g:RWarningMsg('SyncTeX [Vim-R]: "' .. basenm .. '-concordance.tex" not found.')
            return
        elseif filereadable(flnm)
            rnwf = flnm
            rnwln = ln
        else
            g:RWarningMsg("Could not find '" .. basenm .. ".Rnw'.")
            return
        endif
    endif

    var rnwbn = substitute(rnwf, '.*/', '', '')
    rnwf = substitute(rnwf, '^\./', '', '')

    if g:GoToBuf(rnwbn, rnwf, basedir, rnwln)
        g:RaiseVimWindow()
    endif
enddef

def g:SyncTeX_forward(...args: list<any>)
    var basenm = expand("%:t:r")
    var lnum = 0
    var rnwf = expand("%:t")

    if filereadable(expand("%:p:r") .. "-concordance.tex")
        lnum = line(".")
    else
        var ischild = search('% *!Rnw *root *=', 'bwn')
        if ischild > 0
            var mfile = substitute(getline(ischild), '.*% *!Rnw *root *= *\(.*\) *', '\1', '')
            basenm = substitute(mfile, '\....$', '', '')
            var mpath = RootFile(mfile)
            if filereadable(substitute(mpath, '\....$', '', '') .. "-concordance.tex")
                var mlines = readfile(mpath)
                # The name of the child is matched as it is, after a brace, a
                # quote, or the slash of a directory
                var kid = '\V' .. escape(expand("%:t"), '\') .. '\m'
                for ii in range(len(mlines))
                    # Sweave has detailed child information
                    if mlines[ii] =~ 'SweaveInput.*[{/\\]' .. kid
                        lnum = line(".")
                        break
                    endif
                    # Knitr does not include detailed child information
                    if mlines[ii] =~ '<<.*child *=.*[''"/\\]' .. kid .. '[''"]'
                        lnum = ii + 1
                        rnwf = mpath
                        break
                    endif
                endfor
                if lnum == 0
                    g:RWarningMsg('Could not find "child=' .. expand("%:t") .. '" in ' .. mpath .. '.')
                    return
                endif
            else
                g:RWarningMsg('Vim-R [SyncTeX]: "' .. basenm .. '-concordance.tex" not found.')
                return
            endif
        else
            g:RWarningMsg('SyncTeX [Vim-R]: "' .. basenm .. '-concordance.tex" not found.')
            return
        endif
    endif

    # The master file with its directory and without its extension
    var master = g:SyncTeX_GetMaster()
    if !filereadable(master .. ".tex")
        g:RWarningMsg('"' .. master .. '.tex" not found.')
        return
    endif
    var concdata = g:SyncTeX_readconc(master)
    rnwf = substitute(rnwf, ".*/", "", "")
    var texlnum = concdata["texlnum"]
    var rnwfile = concdata["rnwfile"]
    var rnwline = concdata["rnwline"]
    var texln = 0
    for ii in range(len(texlnum))
        # The concordance may name the file with a directory
        if substitute(rnwfile[ii], '.*[/\\]', '', '') ==# rnwf && rnwline[ii] >= lnum
            texln = texlnum[ii]
            break
        endif
    endfor

    if texln == 0
        g:RWarningMsg("Error: did not find LaTeX line.")
        return
    endif
    # The master file may lie in another directory. A relative PDF directory
    # is taken in that directory, as if Vim had changed into it. Vim does not
    # change into it, since :cd and chdir() put the value of an environment
    # variable in the place of "$NAME" in the name of a directory, and on
    # Windows :cd takes a bracket for a wildcard.
    var basedir = substitute(master, '\(.*\)/.*', '\1', '')
    basenm = substitute(master, '.*/', '', '')
    var InBase = (p: string): string => p =~ '^\(/\|\a:[/\\]\)' ? p : basedir .. '/' .. p

    if len(args) > 0 && args[0]
        g:GoToBuf(basenm .. ".tex", basenm .. ".tex", basedir, texln)
        return
    endif

    var pdfbase = InBase(b:rplugin_pdfdir) .. "/" .. basenm
    if !filereadable(pdfbase .. ".pdf")
        g:RWarningMsg('SyncTeX forward cannot be done because the file "' .. pdfbase .. '.pdf" is missing.')
        return
    endif
    if !filereadable(pdfbase .. ".synctex.gz")
        g:RWarningMsg('SyncTeX forward cannot be done because the file "' .. pdfbase .. '.synctex.gz" is missing.')
        if g:R_latexcmd[0] != "default" && join(g:R_latexcmd) !~ "synctex"
            g:RWarningMsg('Note: The string "-synctex=1" is not in your R_latexcmd. Please check your vimrc.')
        endif
        return
    endif

    g:SyncTeX_forward2(master .. '.tex', pdfbase .. ".pdf", texln, 1)
enddef

def g:SetPDFdir()
    var master = g:SyncTeX_GetMaster()
    var mdir = substitute(master, '\(.*\)/.*', '\1', '')
    b:rplugin_pdfdir = "."
    # Latexmk has an option to create the PDF in a directory other than '.'
    if (g:R_latexcmd[0] =~ "default" || g:R_latexcmd[0] =~ "latexmk") && filereadable(expand("~/.latexmkrc"))
        var ltxmk = readfile(expand("~/.latexmkrc"))
        for line in ltxmk
            if line =~ '\$out_dir\s*='
                b:rplugin_pdfdir = substitute(line, '.*\$out_dir\s*=\s*"\(.*\)".*', '\1', '')
                b:rplugin_pdfdir = substitute(b:rplugin_pdfdir, ".*\\$out_dir\\s*=\\s*'\\(.*\\)'.*", '\1', '')
            endif
        endfor
    endif
    if join(g:R_latexcmd) =~ "-outdir" || join(g:R_latexcmd) =~ "-output-directory"
        b:rplugin_pdfdir = substitute(join(g:R_latexcmd), '.*\(-outdir\|-output-directory\)\s*=*\s*', '', '')
        b:rplugin_pdfdir = substitute(b:rplugin_pdfdir, " .*", "", "")
        b:rplugin_pdfdir = substitute(b:rplugin_pdfdir, '["' .. "']", "", "g")
    endif
    if b:rplugin_pdfdir == "."
        b:rplugin_pdfdir = mdir
    elseif b:rplugin_pdfdir !~ '^\(/\|\a:[/\\]\)'
        b:rplugin_pdfdir = mdir .. "/" .. b:rplugin_pdfdir
        if !isdirectory(b:rplugin_pdfdir)
            b:rplugin_pdfdir = "."
        endif
    endif
enddef
