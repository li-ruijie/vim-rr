vim9script

if exists("g:did_vimr_bibcompl")
    finish
endif
g:did_vimr_bibcompl = 1

def g:RCompleteBib(base: string): list<dict<string>>
    if !g:IsJobRunning("BibComplete")
        return []
    endif
    if b:rplugin_bibf == ''
        g:RWarningMsg('Bib file not defined')
        return []
    endif
    delete(g:rplugin.tmpdir .. "/bibcompl")
    g:rplugin.bib_finished = 0
    g:JobStdin(g:rplugin.jobs["BibComplete"], "\x03" .. base .. "\x05" .. expand("%:p") .. "\n")
    g:AddForDeletion(g:rplugin.tmpdir .. "/bibcompl")
    var resp: list<dict<string>> = []
    var wt = 0
    sleep 20m
    while wt < 10 && g:rplugin.bib_finished == 0
        wt += 1
        sleep 50m
    endwhile
    if filereadable(g:rplugin.tmpdir .. "/bibcompl")
        var lines = readfile(g:rplugin.tmpdir .. "/bibcompl")
        for line in lines
            var tmp = split(line, "\x09")
            if len(tmp) >= 3
                add(resp, {word: tmp[0], abbr: tmp[1], menu: tmp[2]})
            endif
        endfor
    endif
    return resp
enddef

def GetBibFileName()
    if !exists('b:rplugin_bibf')
        b:rplugin_bibf = ''
    endif
    var newbibf: string
    if &filetype == 'rmd' || &filetype == 'quarto'
        newbibf = g:RmdGetYamlField('bibliography')
        if newbibf == ''
            newbibf = join(glob(expand("%:p:h") .. '/*.bib', 0, 1), "\x06")
        endif
    else
        newbibf = join(glob(expand("%:p:h") .. '/*.bib', 0, 1), "\x06")
    endif
    if newbibf != b:rplugin_bibf && newbibf !~ 'zotcite.bib$'
        b:rplugin_bibf = newbibf
        if g:IsJobRunning('BibComplete')
            g:JobStdin(g:rplugin.jobs["BibComplete"], "\x04" .. expand("%:p") .. "\x05" .. b:rplugin_bibf .. "\n")
        else
            var aa = [g:rplugin.py3, g:rplugin.home .. '/R/bibtex.py', expand("%:p"), b:rplugin_bibf]
            g:rplugin.jobs["BibComplete"] = g:StartJob(aa, g:rplugin.job_handlers)
            g:RCreateMaps('n', 'ROpenRefFile', 'od', ':call g:GetBibAttachment()')
        endif
    endif
enddef

def HasPython3(): bool
    if exists("g:R_python3")
        if filereadable(g:R_python3)
            if executable(g:R_python3)
                g:rplugin.py3 = g:R_python3
                return true
            else
                g:rplugin.debug_info['BibComplete'] = g:R_python3 .. ' is not executable'
            endif
        else
            g:rplugin.debug_info['BibComplete'] = g:R_python3 .. ' not found'
        endif
        return false
    endif
    silent var out = system('python3 --version')
    if v:shell_error == 0 && out =~ 'Python 3'
        g:rplugin.py3 = 'python3'
    else
        silent out = system('python --version')
        if v:shell_error == 0 && out =~ 'Python 3'
            g:rplugin.py3 = 'python'
        else
            g:rplugin.debug_info['BibComplete'] = "No Python 3"
            g:rplugin.py3 = ''
            return false
        endif
    endif
    return true
enddef

def g:CheckPyBTeX(_timer: number)
    if !has_key(g:rplugin.debug_info, 'BibComplete')
        if !HasPython3()
            return
        endif
        silent system(g:rplugin.py3, "from pybtex.database import parse_file\n")
        if v:shell_error == 0
            g:rplugin.debug_info['BibComplete'] = "PyBTex OK"
        else
            g:rplugin.debug_info['BibComplete'] = "No PyBTex"
            g:rplugin.py3 = ''
        endif
    endif
    if g:rplugin.debug_info['BibComplete'] == "PyBTex OK"
        # Use RBibComplete if possible
        GetBibFileName()
        if !exists("b:rplugin_did_bib_autocmd")
            autocmd BufWritePost <buffer> call <SID>GetBibFileName()
            if &filetype == 'rnoweb'
                b:rplugin_non_r_omnifunc = "g:RnwNonRCompletion"
                autocmd CompleteDone <buffer> call g:RnwOnCompleteDone()
            endif
        endif
        b:rplugin_did_bib_autocmd = 1
    endif
enddef

def g:GetBibAttachment()
    var oldisk = &iskeyword
    set iskeyword=@,48-57,_,192-255,@-@
    var wrd = expand('<cword>')
    execute 'set iskeyword=' .. oldisk
    if wrd =~ '^@'
        wrd = substitute(wrd, '^@', '', '')
        if wrd != ''
            g:rplugin.last_attach = ''
            if !g:IsJobRunning("BibComplete")
                g:RWarningMsg("BibComplete not running.")
                return
            endif
            g:JobStdin(g:rplugin.jobs["BibComplete"], "\x02" .. expand("%:p") .. "\x05" .. wrd .. "\n")
            sleep 20m
            var count = 0
            while count < 100 && g:rplugin.last_attach == ''
                count += 1
                sleep 10m
            endwhile
            if g:rplugin.last_attach == 'nOaTtAChMeNt'
                g:RWarningMsg(wrd .. "'s attachment not found")
            elseif g:rplugin.last_attach =~ 'nObIb:'
                g:RWarningMsg('"' .. substitute(g:rplugin.last_attach, 'nObIb:', '', '') .. '" not found')
            elseif g:rplugin.last_attach == 'nOcItEkEy'
                g:RWarningMsg(wrd .. " not found")
            elseif g:rplugin.last_attach == ''
                g:RWarningMsg('No reply from BibComplete')
            else
                var fpath = g:rplugin.last_attach
                var fls = split(fpath, ':')
                if filereadable(fls[0])
                    fpath = fls[0]
                elseif len(fls) > 1 && filereadable(fls[1])
                    fpath = fls[1]
                endif
                if filereadable(fpath)
                    if has('win32')
                        system('start "" ' .. shellescape(fpath, 1))
                    else
                        system('xdg-open ' .. shellescape(fpath))
                    endif
                else
                    g:RWarningMsg('Could not find "' .. fpath .. '"')
                endif
            endif
        endif
    endif
enddef
