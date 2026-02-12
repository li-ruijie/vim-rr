vim9script

if exists("g:did_vimr_pdf_sumatra")
    finish
endif
g:did_vimr_pdf_sumatra = 1

var sumatra_in_path = 0

def SumatraInPath(): bool
    if sumatra_in_path
        return true
    endif
    if $PATH =~ "SumatraPDF"
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

def g:ROpenPDF2(fullpath: string)
    if SumatraInPath()
        $VIMR_PORT = string(g:rplugin.myport)
        job_start(['SumatraPDF.exe', '-reuse-instance',
            '-inverse-search', 'vimrserver.exe %f %l',
            fullpath], {stoponexit: ''})
    endif
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, unused: number)
    if SumatraInPath()
        var tname = substitute(tpath, '.*/\(.*\)', '\1', '')
        var tdir = substitute(tpath, '\(.*\)/.*', '\1', '')
        var pname = substitute(ppath, tdir .. '/', '', '')
        $VIMR_PORT = string(g:rplugin.myport)
        job_start(['SumatraPDF.exe', '-reuse-instance',
            '-forward-search', tname, string(texln),
            '-inverse-search', 'vimrserver.exe %f %l',
            pname], {stoponexit: ''})
    endif
enddef
