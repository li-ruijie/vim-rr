vim9script

if exists("g:did_vimr_bibcompl")
    finish
endif
g:did_vimr_bibcompl = 1

import './bibtex.vim'

# Cache: parsed entries by bib file path
var bib_entries: dict<dict<dict<any>>> = {}
var bib_mtimes: dict<number> = {}
var doc_bibs: dict<list<string>> = {}

def GetAuthors(entry: dict<any>): string
    var persons = bibtex.GetPersons(entry, 'author')
    if len(persons) == 0
        persons = bibtex.GetPersons(entry, 'editor')
    endif
    if len(persons) == 0
        return ''
    endif
    var isetal = len(persons) > 3
    var cit = ''
    for p in persons
        var lname = join(p.last_names, ' ')
        if lname == 'others'
            cit ..= ' et al.'
            break
        endif
        cit ..= ', ' .. substitute(lname, '\<\(\w\)\(\w*\)\>', '\u\1\L\2', 'g')
        if isetal
            cit ..= ' et al.'
            break
        endif
    endfor
    return substitute(cit, '^, ', '', '')
enddef

def ParseBib(bibpath: string)
    bib_mtimes[bibpath] = getftime(bibpath)
    bib_entries[bibpath] = {}
    var bib: dict<any>
    try
        bib = bibtex.ParseBibFile(bibpath)
    catch
        g:RWarningMsg('Error parsing ' .. bibpath .. ': ' .. v:exception)
        return
    endtry
    for [k, entry] in items(bib.entries)
        var e: dict<any> = {citekey: k, title: '', year: '????', author: '', file: ''}
        e.author = GetAuthors(entry)
        var title = bibtex.GetField(entry, 'title')
        if title != ''
            e.title = title
        endif
        var year = bibtex.GetField(entry, 'year')
        if year != ''
            e.year = year
        endif
        var file = bibtex.GetField(entry, 'file')
        if file != ''
            e.file = file
        endif
        bib_entries[bibpath][k] = e
    endfor
enddef

def EnsureParsed(docpath: string)
    if !has_key(doc_bibs, docpath)
        return
    endif
    var valid_bibs: list<string> = []
    for b in doc_bibs[docpath]
        if filereadable(b)
            if !has_key(bib_entries, b) || getftime(b) > bib_mtimes[b]
                ParseBib(b)
            endif
            add(valid_bibs, b)
        endif
    endfor
    doc_bibs[docpath] = valid_bibs
enddef

def SetBibfiles(docpath: string, biblist: list<string>)
    doc_bibs[docpath] = []
    for b in biblist
        if b != ''
            if filereadable(b)
                ParseBib(b)
                add(doc_bibs[docpath], b)
            else
                g:RWarningMsg('File "' .. b .. '" not found.')
            endif
        endif
    endfor
enddef

def GetComplLine(k: string, e: dict<any>): dict<string>
    return {word: k, abbr: strcharpart(e.author, 0, 40), menu: '(' .. e.year .. ') ' .. e.title}
enddef

def g:RCompleteBib(base: string): list<dict<string>>
    if b:rplugin_bibf == ''
        g:RWarningMsg('Bib file not defined')
        return []
    endif
    var docpath = expand("%:p")
    var biblist = split(b:rplugin_bibf, "\x06")
    if !has_key(doc_bibs, docpath) || doc_bibs[docpath] != biblist
        SetBibfiles(docpath, biblist)
    endif
    EnsureParsed(docpath)
    if !has_key(doc_bibs, docpath)
        return []
    endif
    var ptrn = tolower(base)
    var p1: list<dict<string>> = []
    var p2: list<dict<string>> = []
    var p3: list<dict<string>> = []
    var p4: list<dict<string>> = []
    var p5: list<dict<string>> = []
    var p6: list<dict<string>> = []
    for b in doc_bibs[docpath]
        if !has_key(bib_entries, b)
            continue
        endif
        for [k, e] in items(bib_entries[b])
            var ck = tolower(e.citekey)
            var au = tolower(e.author)
            var ti = tolower(e.title)
            if stridx(ck, ptrn) == 0
                add(p1, GetComplLine(k, e))
            elseif stridx(au, ptrn) == 0
                add(p2, GetComplLine(k, e))
            elseif stridx(ti, ptrn) == 0
                add(p3, GetComplLine(k, e))
            elseif stridx(ck, ptrn) > 0
                add(p4, GetComplLine(k, e))
            elseif stridx(au, ptrn) > 0
                add(p5, GetComplLine(k, e))
            elseif stridx(ti, ptrn) > 0
                add(p6, GetComplLine(k, e))
            endif
        endfor
    endfor
    return p1 + p2 + p3 + p4 + p5 + p6
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
        var biblist = split(b:rplugin_bibf, "\x06")
        SetBibfiles(expand("%:p"), biblist)
        g:RCreateMaps('n', 'ROpenRefFile', 'od', ':call g:GetBibAttachment()')
    endif
enddef

def g:InitBibComplete(_timer: number)
    g:rplugin.debug_info['BibComplete'] = "Vim9script"
    GetBibFileName()
    if !exists("b:rplugin_did_bib_autocmd")
        autocmd BufWritePost <buffer> call <SID>GetBibFileName()
        if &filetype == 'rnoweb'
            b:rplugin_non_r_omnifunc = "g:RnwNonRCompletion"
            autocmd CompleteDone <buffer> call g:RnwOnCompleteDone()
        endif
    endif
    b:rplugin_did_bib_autocmd = 1
enddef

def g:GetBibAttachment()
    var oldisk = &iskeyword
    setlocal iskeyword=@,48-57,_,192-255,@-@
    var wrd = expand('<cword>')
    execute 'setlocal iskeyword=' .. oldisk
    if wrd =~ '^@'
        wrd = substitute(wrd, '^@', '', '')
        if wrd != ''
            var docpath = expand("%:p")
            EnsureParsed(docpath)
            if !has_key(doc_bibs, docpath)
                g:RWarningMsg('No bib files associated with this document.')
                return
            endif
            for b in doc_bibs[docpath]
                if !has_key(bib_entries, b)
                    continue
                endif
                for [k, e] in items(bib_entries[b])
                    if e.citekey == wrd
                        if e.file != ''
                            var fpath = e.file
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
                            return
                        endif
                        g:RWarningMsg(wrd .. "'s attachment not found")
                        return
                    endif
                endfor
            endfor
            g:RWarningMsg(wrd .. " not found")
        endif
    endif
enddef
