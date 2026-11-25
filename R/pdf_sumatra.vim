vim9script noclear

if exists("g:did_vimr_pdf_sumatra")
    finish
endif
g:did_vimr_pdf_sumatra = 1

var sumatra_in_path = 0

def SumatraInPath(): bool
    if sumatra_in_path
        return true
    endif
    if executable("SumatraPDF.exe")
        sumatra_in_path = 1
        return true
    endif

    # $ProgramFiles has different values for win32 and win64
    if executable($ProgramFiles .. "\\SumatraPDF\\SumatraPDF.exe")
        $PATH = $ProgramFiles .. "\\SumatraPDF;" .. $PATH
        sumatra_in_path = 1
        return true
    endif
    if executable($ProgramFiles .. " (x86)\\SumatraPDF\\SumatraPDF.exe")
        $PATH = $ProgramFiles .. " (x86)\\SumatraPDF;" .. $PATH
        sumatra_in_path = 1
        return true
    endif
    return false
enddef

# SumatraPDF keeps one command for a backward search, which other plugins
# use as well, so it is set once in the settings of SumatraPDF and never
# passed from here. That command starts a Vim that sources
# sumatra_inverse.vim, which calls g:SumatraInverseSearch() in every running
# Vim. See |vim-rr-sumatra|.

# A path in lower case, with forward slashes and no slash at the end
def Canonical(path: string): string
    return fnamemodify(path, ':p')->simplify()->tolower()
        ->substitute('\\', '/', 'g')->substitute('/$', '', '')
enddef

# Return whether this Vim edits the document of the TeX file "tex". It does
# when one of its loaded Rnoweb buffers is a file that the concordance of the
# document names, or is in the directory of the TeX file or below it.
def EditsDocument(tex: string): bool
    var texdir = Canonical(fnamemodify(tex, ':h')) .. '/'
    var base = substitute(tex, '\....$', '', '')
    var sources = filereadable(base .. '-concordance.tex') && filereadable(base .. '.tex')
        ? g:SyncTeX_readconc(base).rnwfile->mapnew((_, f) => f == '' ? '' : Canonical(texdir .. f))
        : []
    return !getbufinfo({bufloaded: 1})
        ->filter((_, b) => getbufvar(b.bufnr, '&filetype') == 'rnoweb')
        ->mapnew((_, b) => Canonical(b.name))
        ->filter((_, name) => stridx(name, texdir) == 0 || index(sources, name) >= 0)
        ->empty()
enddef

# Called through remote_expr(), which needs a value, for a double click on
# line "ln" of the TeX file "fname" in the PDF
def g:SumatraInverseSearch(fname: string, ln: number): string
    if exists('*g:SyncTeX_backward') && EditsDocument(fname)
        g:SyncTeX_backward(substitute(fname, '\\', '/', 'g'), ln)
    endif
    return ''
enddef

def g:ROpenPDF2(fullpath: string)
    if SumatraInPath()
        job_start(['SumatraPDF.exe', '-reuse-instance', fullpath], {stoponexit: ''})
    endif
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, unused: number)
    if SumatraInPath()
        var tname = substitute(tpath, '.*/\(.*\)', '\1', '')
        var tdir = substitute(tpath, '\(.*\)/.*', '\1', '')
        var pname = substitute(ppath, tdir .. '/', '', '')
        job_start(['SumatraPDF.exe', '-reuse-instance',
            '-forward-search', tname, string(texln),
            pname], {stoponexit: '', cwd: tdir})
    endif
enddef
