vim9script

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
        var pdir = substitute(fullpath, '\(.*\)/.*', '\1', '')
        var pname = substitute(fullpath, '.*/\(.*\)', '\1', '')
        var olddir = substitute(substitute(getcwd(), '\\', '/', 'g'), ' ', '\\ ', 'g')
        execute "cd " .. pdir
        $VIMR_PORT = string(g:rplugin.myport)
        writefile(['start SumatraPDF.exe -reuse-instance -inverse-search "vimrserver.exe %%f %%l" "' .. fullpath .. '"'], g:rplugin.tmpdir .. "/run_cmd.bat")
        system(g:rplugin.tmpdir .. "/run_cmd.bat")
        execute "cd " .. olddir
    endif
enddef

def g:SyncTeX_forward2(tpath: string, ppath: string, texln: number, unused: number)
    if tpath =~ ' '
        # SumatraPDF has issues with spaces in file names for SyncTeX
    endif
    if SumatraInPath()
        var tname = substitute(tpath, '.*/\(.*\)', '\1', '')
        var tdir = substitute(tpath, '\(.*\)/.*', '\1', '')
        var pname = substitute(ppath, tdir .. '/', '', '')
        var olddir = substitute(substitute(getcwd(), '\\', '/', 'g'), ' ', '\\ ', 'g')
        execute "cd " .. substitute(tdir, ' ', '\\ ', 'g')
        $VIMR_PORT = string(g:rplugin.myport)
        writefile(['start SumatraPDF.exe -reuse-instance -forward-search "' .. tname .. '" ' .. texln .. ' -inverse-search "vimrserver.exe %%f %%l" "' .. pname .. '"'], g:rplugin.tmpdir .. "/run_cmd.bat")
        system(g:rplugin.tmpdir .. "/run_cmd.bat")
        execute "cd " .. olddir
    endif
enddef
