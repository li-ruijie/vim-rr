vim9script
# Regression tests for names that cross between Vim and R. vimcom builds Vim
# commands that hold a file name, and Vim builds R code that holds one. Each
# block names the defect it guards against.

g:SetSuite('names_in_r')

var plugin_root = expand('<sfile>:p:h:h')
execute 'set runtimepath=' .. fnameescape(plugin_root) .. ',' .. $VIMRUNTIME
filetype plugin indent on
syntax on
execute 'source ' .. fnameescape(plugin_root .. '/ftdetect/r.vim')

# Run a block and return the error it raised, or '' when it raised none
def Caught(Fn: func()): string
  v:errmsg = ''
  try
    Fn()
  catch
    return v:exception
  endtry
  return v:errmsg
enddef

# The plugin writes its paths with forward slashes
var work = substitute(tempname(), '\\', '/', 'g')
mkdir(work, 'p')
# What the blocks make in the work directory, for the removal at the end
var made_files: list<string> = []
var made_dirs: list<string> = []
var err = ''

writefile(['x <- 1'], work .. '/main.R')
add(made_files, 'main.R')
execute 'edit ' .. fnameescape(work .. '/main.R')
var rbuf = bufnr('%')

# ========================================================================
# vimcom: a name in a Vim command is a string, whatever it holds
# ========================================================================
# vimcom put a name between single quotes without doubling a single quote in
# it, so the quote ended the string. Vim then refused the command or ran what
# followed the quote. The commands are built by the R code itself, read from
# the source files, and are evaluated here as Vim evaluates them, with the
# function that they call replaced by one that records its arguments.
def g:RrTestTake(...args: list<any>)
  g:rr_test_taken = args
enddef
def Taken(cmd: string): list<any>
  g:rr_test_taken = ['not called']
  var fn = matchstr(cmd, '^g:\w\+')
  try
    execute substitute(cmd, '^g:\w\+', 'g:RrTestTake', '')
  catch
    return [fn, v:exception]
  endtry
  return [fn, g:rr_test_taken]
enddef

if executable('Rscript')
  var rtmp = work .. "/it's tmp"
  var cmdfile = work .. '/commands.txt'
  mkdir(rtmp, 'p')
  var rjob = job_start(['Rscript', '--vanilla', plugin_root .. '/tests/data/vimcom_commands.R',
    plugin_root .. '/R/vimcom/R', cmdfile, rtmp],
    {out_io: 'null', err_io: 'file', err_name: work .. '/commands.err'})
  for _ in range(600)
    if job_status(rjob) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  var cmds = filereadable(cmdfile) ? readfile(cmdfile) : []
  var r_errors = filereadable(work .. '/commands.err') ? readfile(work .. '/commands.err')->join(' ') : ''
  g:AssertEqual(len(cmds), 12, 'vimcom: every command is one line (' .. r_errors .. ')')
  cmds += repeat(['missing'], 12 - len(cmds))
  var saved_df_viewer = get(g:, 'R_df_viewer', v:none)
  g:R_df_viewer = 'View(%s)'

  g:AssertEqual(Taken(cmds[0]), ['g:ROpenDoc', ["it's.pdf", '']],
    'vimcom: the PDF of an Rrst file reaches ROpenDoc() with its quote')
  g:AssertEqual(Taken(cmds[1]), ['g:ROpenDoc', ['it''s a "doc".html', "my 'browser'"]],
    'vimcom: the rendered file and the browser reach ROpenDoc() with their quotes')
  var edit_taken = Taken(cmds[2])
  var edit_name = type(edit_taken[1]) == v:t_list ? fnamemodify(edit_taken[1][0], ':t') : ''
  g:AssertEqual([edit_taken[0], type(edit_taken[1]) == v:t_list ? edit_taken[1][0] : edit_taken[1],
    edit_name =~ '^vimcom_edit_\d\+$'], ['g:EditRObject', rtmp .. '/' .. edit_name, true],
    'vimcom: a file in a temporary directory with a quote reaches EditRObject()')
  g:AssertEqual(Taken(cmds[3]), ['g:RViewDF', ["it's", 'tabnew', "a\x141"]],
    'vimcom: the name of a data frame reaches RViewDF() with its quote')
  g:AssertEqual(Taken(cmds[4]), ['g:SendCmdToR', ["View(it's)"]],
    'vimcom: the name of a data frame reaches R_df_viewer with its quote')
  g:AssertEqual(Taken(cmds[5]), ['g:RWarningMsg', ['"no''such" not found in .GlobalEnv']],
    'vimcom: the warning for a missing object keeps the quote of the name')
  g:AssertEqual(Taken(cmds[6]), ['g:ShowRObj', ['tabnew', "c('a')", 'r', '"a"']],
    'vimcom: the expression that was printed reaches ShowRObj() with its quotes')
  var out_taken = Taken(cmds[7])
  g:AssertEqual([out_taken[0], type(out_taken[1]) == v:t_list ? out_taken[1][0] : out_taken[1]],
    ['g:GetROutput', "it's out"], 'vimcom: the name of the buffer reaches GetROutput() with its quote')
  g:AssertEqual(Taken(cmds[8]), ['g:FinishRInsert', ["it's", '[1] 2']],
    'vimcom: the first argument reaches FinishRInsert() with its quote')
  g:AssertEqual(Taken(cmds[9]), ['g:RWarningMsg', ['There is no help for "it''s".']],
    'vimcom: the warning for a topic without example keeps the quote')
  g:AssertEqual(Taken(cmds[10]),
    ['g:RWarningMsg', ['No documentation for "it''s" in loaded packages and libraries.']],
    'vimcom: the warning for a topic without help keeps the quote')
  # Vim receives a command as one line, so a line break in it would cut it
  g:AssertEqual(Taken(cmds[11]), ['g:RWarningMsg', ['"no such" not found in .GlobalEnv']],
    'vimcom: a line break in a warning becomes a space')

  if type(saved_df_viewer) == v:t_none
    unlet g:R_df_viewer
  else
    g:R_df_viewer = saved_df_viewer
  endif
  extend(made_files, ['commands.txt', 'commands.err', "it's tmp/code.R", "it's tmp/edit_1_wait",
    "it's tmp/" .. edit_name])
  add(made_dirs, "it's tmp")
endif
delfunction g:RrTestTake
unlet! g:rr_test_taken

# ========================================================================
# R code: a file name is an R string, whatever it holds
# ========================================================================
# Vim put a file name between double quotes into the R code that it sends, so
# a double quote in the name ended the R string, and R read a backslash as the
# start of an escape. Windows allows neither character in a file name, so
# there the names are plain and only the options carry the two characters.
if !exists('*g:RDebugJump')
  execute 'source ' .. fnameescape(plugin_root .. '/R/start_r.vim')
endif
def g:RrTestSend(...args: list<any>): number
  add(g:rr_test_sent, args[0])
  return 1
enddef
g:rr_test_sent = []
var SavedSend = g:SendCmdToR
g:SendCmdToR = function('g:RrTestSend')
# The R code that a block sent last, or the error that it raised
def Sent(Fn: func()): string
  g:rr_test_sent = []
  var caught = Caught(Fn)
  return caught != '' ? caught : get(g:rr_test_sent, -1, 'nothing sent')
enddef
# Whether a text starts with another one, compared character by character
def StartsWith(text: string, start: string): bool
  return strpart(text, 0, len(start)) ==# start
enddef

# The name of a file, and the same name as the inside of an R string
var odd = has('win32') ? 'a b' : 'a"b\c'
var odd_r = has('win32') ? 'a b' : 'a\"b\\c'
var saved_cwd = getcwd()
var saved_viewer = get(g:rplugin, 'pdfviewer', v:none)
g:rplugin.pdfviewer = 'none'

if executable('Rscript')
  # R itself reads the string back and writes its bytes into a file
  var text = "a\"b\\c\nd 'e'"
  writefile(['writeBin(charToRaw(' .. g:RString(text) .. '), ' .. g:RString(work .. '/rstring.out') .. ')'],
    work .. '/rstring.R')
  var sjob = job_start(['Rscript', '--vanilla', work .. '/rstring.R'], {out_io: 'null', err_io: 'null'})
  for _ in range(600)
    if job_status(sjob) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  g:AssertEqual(filereadable(work .. '/rstring.out') ? readfile(work .. '/rstring.out', 'b') : [],
    ['a"b\c', "d 'e'"], 'RString: R reads the string back unchanged')
  extend(made_files, ['rstring.R', 'rstring.out'])
endif

writefile(['text'], work .. '/' .. odd .. '.Rmd')
execute 'edit ' .. fnameescape(work .. '/' .. odd .. '.Rmd')
g:AssertEqual(Sent(() => {
  g:RSetWD()
}), 'setwd("' .. work .. '")', 'RSetWD: the directory is an R string')
g:AssertEqual(Sent(() => {
  g:RKnit()
}), 'require(knitr); .vim_oldwd <- getwd(); setwd("' .. work .. '"); knit("' .. odd_r
  .. '.Rmd"); setwd(.vim_oldwd); rm(.vim_oldwd)', 'RKnit: the file name is an R string')
var rmd_sent = Sent(() => {
  g:RMakeRmd('default')
})
g:Assert(StartsWith(rmd_sent,
  'vim.interlace.rmd("' .. odd_r .. '.Rmd", rmddir = "' .. work .. '", envir = '),
  'RMakeRmd: the file name is an R string (' .. rmd_sent .. ')')
var file_sent = Sent(() => {
  g:SendFileToR('silent')
})
g:Assert(StartsWith(file_sent, 'vimcom:::source.and.clean("' .. work .. '/' .. odd_r .. '.Rmd.tmp.R"'),
  'SendFileToR: the name of the copy is an R string (' .. file_sent .. ')')
extend(made_files, [odd .. '.Rmd', odd .. '.Rmd.tmp.R'])

g:AssertEqual(Sent(() => {
  g:RSourceDirectory('d"1\x')
}), has('win32') ? 'vim.srcdir("d\"1/x")' : 'vim.srcdir("d\"1\\x")',
  'RSourceDirectory: the directory is an R string')

# The name of a child document stands between quotes in the chunk header
execute 'cd ' .. fnameescape(work)
var kid = has('win32') ? 'kid 1.Rnw' : 'kid"1\k.Rnw'
writefile(['text'], work .. '/' .. kid)
add(made_files, kid)
var kid_sent = Sent(() => {
  g:KnitChild("<<child='" .. kid .. "'>>=", 'stay')
})
g:Assert(StartsWith(kid_sent, 'require(knitr); knit("' .. (has('win32') ? 'kid 1.Rnw' : 'kid\"1\\k.Rnw')
  .. '", output='), 'KnitChild: the file name is an R string (' .. kid_sent .. ')')
execute 'cd ' .. fnameescape(saved_cwd)

writefile(['x <- 1'], work .. '/' .. odd .. '.R')
add(made_files, odd .. '.R')
execute 'edit ' .. fnameescape(work .. '/' .. odd .. '.R')
g:AssertEqual(Sent(() => {
  g:RSpin()
}), 'require(knitr); .vim_oldwd <- getwd(); setwd("' .. work .. '"); spin("' .. odd_r
  .. '.R"); setwd(.vim_oldwd); rm(.vim_oldwd)', 'RSpin: the file name is an R string')

writefile(['Title', '=====', '', 'text'], work .. '/' .. odd .. '.Rrst')
add(made_files, odd .. '.Rrst')
execute 'edit ' .. fnameescape(work .. '/' .. odd .. '.Rrst')
var saved_rst2pdf = g:rplugin.rrst_has_rst2pdf
var saved_openhtml = g:R_openhtml
var saved_rst2pdfpath = get(g:, 'R_rst2pdfpath', v:none)
g:rplugin.rrst_has_rst2pdf = 1
g:R_openhtml = 1
var html_sent = Sent(() => {
  g:RMakeHTMLrrst('html')
})
g:Assert(stridx(html_sent, '; knit("' .. odd_r .. '.Rrst"); system2(') > 0,
  'RMakeHTMLrrst: the file that is knitted is an R string (' .. html_sent .. ')')
g:Assert(html_sent =~# '\V; browseURL("\.\{-}' .. escape(odd_r, '\') .. '.html")\$',
  'RMakeHTMLrrst: the file for the browser is an R string (' .. html_sent .. ')')
g:R_rst2pdfpath = 'C:\tools\rst "2" pdf'
var pdf_sent = Sent(() => {
  g:RMakePDFrrst()
})
g:Assert(StartsWith(pdf_sent, 'vim.interlace.rrst("' .. odd_r .. '.Rrst", rrstdir = "' .. work .. '"'),
  'RMakePDFrrst: the file name is an R string (' .. pdf_sent .. ')')
g:Assert(stridx(pdf_sent, ', rst2pdfpath="C:\\tools\\rst \"2\" pdf"') > 0,
  'RMakePDFrrst: the path of rst2pdf is an R string (' .. pdf_sent .. ')')
if type(saved_rst2pdfpath) == v:t_none
  unlet g:R_rst2pdfpath
else
  g:R_rst2pdfpath = saved_rst2pdfpath
endif
g:R_openhtml = saved_openhtml
g:rplugin.rrst_has_rst2pdf = saved_rst2pdf

if type(saved_viewer) == v:t_none
  remove(g:rplugin, 'pdfviewer')
else
  g:rplugin.pdfviewer = saved_viewer
endif
g:SendCmdToR = SavedSend
delfunction g:RrTestSend
unlet g:rr_test_sent
execute 'buffer ' .. rbuf

# ========================================================================
# Ex commands: the window of the R script is found by its buffer number
# ========================================================================
# RDebugJump() and four other functions went to the window of the R script
# with ":sb NAME". A space or a bracket in the name made Vim look for another
# buffer, and a percent sign was replaced with the name of the current file.
writefile(['x <- 1'], work .. '/s [1] %.R')
writefile(['f <- function() {', '  1', '}'], work .. '/sourced.R')
extend(made_files, ['s [1] %.R', 'sourced.R'])
execute 'edit ' .. fnameescape(work .. '/s [1] %.R')
var saved_rscript = g:rplugin.rscript_name
g:rplugin.rscript_name = bufname('%')
err = Caught(() => {
  g:RDebugJump(work .. '/sourced.R', 2)
})
g:AssertEqual([err, bufexists(work .. '/sourced.R')
  ? sign_getplaced(work .. '/sourced.R')[0].signs->mapnew((_, v) => v.lnum) : [], expand('%:t')],
  ['', [2], 's [1] %.R'], 'RDebugJump: goes to the R script "s [1] %.R" and comes back to it')
sign unplace 1
silent! only
g:rplugin.rscript_name = saved_rscript
execute 'buffer ' .. rbuf

# ========================================================================
# RDebugJump: the file that R names is taken as it is
# ========================================================================
# The name went through expand(), which takes brackets for a wildcard and, on
# Unix, runs a command between backticks. Then it was used as a pattern.
writefile(['f <- function() {', '  1', '}'], work .. '/a1.R')
writefile(['f <- function() {', '  1', '}'], work .. '/a[1].R')
writefile(['f <- function() {', '  1', '}'], work .. '/home.R')
extend(made_files, ['a1.R', 'a[1].R', 'home.R'])
saved_rscript = g:rplugin.rscript_name
g:rplugin.rscript_name = bufname('%')
# The lines of the file that carry the sign of the debugger
def SignLines(file: string): list<number>
  return bufexists(file) ? sign_getplaced(bufnr(file))[0].signs->mapnew((_, v) => v.lnum) : []
enddef

err = Caught(() => {
  g:RDebugJump(work .. '/a[1].R', 2)
})
g:AssertEqual([err, SignLines(work .. '/a[1].R'), bufloaded(work .. '/a1.R')], ['', [2], 0],
  'RDebugJump: opens "a[1].R" and leaves "a1.R" alone')
sign unplace 1
silent! only

# R gives the name as source() received it, so a tilde at its start is kept
var saved_home = $HOME
$HOME = work
err = Caught(() => {
  g:RDebugJump('~/home.R', 3)
})
$HOME = saved_home
g:AssertEqual([err, SignLines(work .. '/home.R')], ['', [3]],
  'RDebugJump: a tilde at the start is the home directory')
sign unplace 1
silent! only

err = Caught(() => {
  g:RDebugJump('no~such [1].R', 1)
})
g:AssertEqual(err, '', 'RDebugJump: a name that is no file is no pattern either')
silent! only

if has('unix')
  err = Caught(() => {
    g:RDebugJump(work .. '/x`touch ' .. work .. '/INJECTED`.R', 1)
  })
  g:AssertEqual([err, filereadable(work .. '/INJECTED')], ['', 0],
    'RDebugJump: a command between backticks in the name is not run')
endif
g:rplugin.rscript_name = saved_rscript
execute 'buffer ' .. rbuf

# ========================================================================
# Zathura: the title of a window is compared with the name as text
# ========================================================================
# Before it opens a PDF, the plugin closes the Zathura that shows the same
# file, which it finds by the title in the list of wmctrl. The file name went
# into the pattern as it was, so a bracket in it matched other text than
# itself and a tilde raised E33. The stand-in for wmctrl lists one window that
# belongs to a sleeping process, which the plugin must end.
if has('unix') && filereadable('/proc/sys/kernel/pid_max')
  var zbin = work .. '/zbin'
  mkdir(zbin, 'p')
  writefile(['#!/bin/sh', 'sleep 1'], zbin .. '/zathura')
  writefile(['#!/bin/sh', 'echo "0x04000003  0 $RR_TEST_PID zathura.Zathura  host $RR_TEST_TITLE"'],
    zbin .. '/wmctrl')
  writefile(['#!/bin/sh', 'exit 0'], zbin .. '/dbus-send')
  for prog in ['zathura', 'wmctrl', 'dbus-send']
    setfperm(zbin .. '/' .. prog, 'rwx------')
  endfor
  var old_zathura = job_start(['sleep', '30'])
  var zjob = job_start([v:progpath, '-N', '-u', 'NONE', '-i', 'NONE', '-es', '-S',
    plugin_root .. '/tests/data/zathura_window.vim'], {in_io: 'null', out_io: 'null', err_io: 'null',
    env: {PATH: zbin .. ':' .. $PATH, RR_TEST_PID: string(job_info(old_zathura).process),
      RR_TEST_TITLE: 'my[1]~.pdf', RR_TEST_ROOT: plugin_root, RR_TEST_PDF: work .. '/my[1]~.pdf',
      RR_TEST_OUT: work .. '/zathura.out'}})
  for _ in range(300)
    if job_status(zjob) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  sleep 100m
  g:AssertEqual([filereadable(work .. '/zathura.out') ? readfile(work .. '/zathura.out') : ['no report'],
    job_status(old_zathura)], [[''], 'dead'],
    'Zathura: the window that shows "my[1]~.pdf" is found and its process is ended')
  job_stop(old_zathura, 'kill')
  job_stop(zjob, 'kill')
endif

silent! tabonly
silent! only
# On Unix the work directory lies in the temporary directory of Vim, which Vim
# removes when it exits. On Windows it stays, so what the blocks above made
# there is removed by name, after the buffers have given up their swap files.
if has('win32')
  silent! :%bwipeout!
  for name in made_files
    delete(work .. '/' .. name)
  endfor
  for dir in made_dirs->mapnew((_, d) => work .. '/' .. d) + [work]
    delete(dir, 'd')
  endfor
endif
