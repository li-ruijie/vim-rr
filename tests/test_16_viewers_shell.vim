vim9script
# Regression tests for file names that the plugin hands to an Ex command, to
# a shell, to R, or to a PDF viewer. Each block names the defect it guards
# against. The blocks that run a shell command use stand-in programs that the
# test writes itself, so no viewer has to be installed.

g:SetSuite('viewers_shell')

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

# Return what a stand-in program logged, once it has written its last line.
# The plugin starts these programs in the background.
def Logged(logfile: string): list<string>
  for _ in range(600)
    if filereadable(logfile) && get(readfile(logfile), -1, '') ==# 'end'
      break
    endif
    sleep 50m
  endfor
  var lines = filereadable(logfile) ? readfile(logfile) : []
  delete(logfile)
  return lines
enddef

# A program in a terminal window may still run after it has written its
# log, and :buffer refuses to leave a terminal whose job runs (E948)
def TerminalsDone()
  for _ in range(600)
    if term_list()->filter((_, b) => term_getstatus(b) =~# 'running')->empty()
      return
    endif
    sleep 50m
  endfor
enddef

# The plugin writes its paths with forward slashes
var work = substitute(tempname(), '\\', '/', 'g')
mkdir(work, 'p')
var err = ''

# ========================================================================
# Ex commands: a file name is data, whatever characters it holds
# ========================================================================
# A backward search ends in GoToBuf(), which built :tabnew and :sb commands
# from the file name. A percent sign was replaced with the name of the
# current file, and a bracket made :sb find no buffer.
writefile(['\documentclass{article}', '\begin{document}', 'x', '\end{document}'], work .. '/main.Rnw')
execute 'edit ' .. fnameescape(work .. '/main.Rnw')
var rnwbuf = bufnr('%')
for name in ['my file.tex', 'a%b.tex', 'a#b.tex', 'a[1].tex']
  writefile(['1', '2', '3', '4'], work .. '/' .. name)
  err = Caught(() => {
    g:GoToBuf(name, name, work, 3)
  })
  g:AssertEqual([err, expand('%:t'), line('.')], ['', name, 3],
    'GoToBuf: opens "' .. name .. '" in a new tab')
  tabfirst
  execute 'buffer ' .. rnwbuf
  err = Caught(() => {
    g:GoToBuf(name, work .. '/' .. name, work, 4)
  })
  g:AssertEqual([err, expand('%:t'), line('.')], ['', name, 4],
    'GoToBuf: goes to the loaded "' .. name .. '"')
  tabonly
  execute 'buffer ' .. rnwbuf
endfor

# The Rout file of "R CMD BATCH" has the name of the R script, and the file
# that the R debugger reports is any file that R has sourced
writefile(['x <- 1'], work .. '/main.R')
execute 'edit ' .. fnameescape(work .. '/main.R')
var rbuf = bufnr('%')
writefile(['> x <- 1'], work .. '/a%b.Rout')
var saved_routnotab = g:R_routnotab
g:R_routnotab = 0
err = Caught(() => {
  g:GetRCmdBatchOutput(work .. '/a%b.Rout')
})
g:AssertEqual([err, bufloaded(work .. '/a%b.Rout')], ['', 1], 'GetRCmdBatchOutput: opens "a%b.Rout"')
g:R_routnotab = saved_routnotab
tabonly
execute 'buffer ' .. rbuf

# A second sourcing would delete the functions that other functions have
# been compiled against
if !exists('*g:RDebugJump')
  execute 'source ' .. fnameescape(plugin_root .. '/R/start_r.vim')
endif
var saved_rscript = get(g:rplugin, 'rscript_name', v:none)
g:rplugin.rscript_name = bufname('%')
writefile(['f <- function() {', '  1', '}'], work .. '/a%b.R')
err = Caught(() => {
  g:RDebugJump(work .. '/a%b.R', 2)
})
g:AssertEqual([err, bufexists(work .. '/a%b.R')
  ? sign_getplaced(work .. '/a%b.R')[0].signs->mapnew((_, v) => v.lnum) : []], ['', [2]],
  'RDebugJump: opens "a%b.R" and places the sign in it')
sign unplace 1
only
execute 'buffer ' .. rbuf
if type(saved_rscript) == v:t_none
  remove(g:rplugin, 'rscript_name')
else
  g:rplugin.rscript_name = saved_rscript
endif

# RViewDF() appends the path of its file to an Ex command in R_csv_app
var saved_tmpdir = g:rplugin.tmpdir
var saved_csv_app = get(g:, 'R_csv_app', v:none)
g:rplugin.tmpdir = work .. '/t%d'
mkdir(g:rplugin.tmpdir, 'p')
g:R_csv_app = ':split'
err = Caught(() => {
  g:RViewDF('df', '', "a\x14b")
})
g:AssertEqual([err, bufloaded(work .. '/t%d/df.tsv')], ['', 1],
  'RViewDF: an Ex command gets the escaped path')
only
execute 'buffer ' .. rbuf
# In the place of "%s" the path went into the Ex command as it was, and "%"
# in it was replaced with the name of the current file
g:R_csv_app = ':split %s'
err = Caught(() => {
  g:RViewDF('df2', '', "a\x14b")
})
g:AssertEqual([err, bufloaded(work .. '/t%d/df2.tsv')], ['', 1],
  'RViewDF: an Ex command with "%s" gets the escaped path')
only
execute 'buffer ' .. rbuf

# ========================================================================
# Shell commands on Unix: a path is one word for the shell
# ========================================================================
# The stand-in appends its arguments, one per line, to $RR_TEST_LOG
if has('unix')
  var bindir = work .. '/bin'
  var shlog = work .. '/shell.log'
  var odd = work .. "/it's a $(touch INJECTED) dir"
  mkdir(bindir, 'p')
  mkdir(odd, 'p')
  # In a terminal a program lingers after its log, as it may on a loaded
  # machine
  for prog in ['myviewer', 'qpdfview', 'lowriter']
    writefile(['#!/bin/sh', 'for a in "$@"; do printf ''%s\n'' "$a"; done >> "$RR_TEST_LOG"',
      'echo end >> "$RR_TEST_LOG"', '[ -t 1 ] && sleep 1', 'exit 0'], bindir .. '/' .. prog)
    setfperm(bindir .. '/' .. prog, 'rwx------')
  endfor
  for doc in ['doc.pdf', 'doc.tex', 'doc.odt']
    writefile(['x'], odd .. '/' .. doc)
  endfor
  var saved_path = $PATH
  var saved_cwd = getcwd()
  var saved_viewer = get(g:, 'R_pdfviewer', v:none)
  $PATH = bindir .. ':' .. $PATH
  $RR_TEST_LOG = shlog
  execute 'cd ' .. fnameescape(work)
  if !exists('*g:RRaiseWindow')
    execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_init.vim')
  endif

  # The generic viewer put the path between single quotes, which an
  # apostrophe in the path ended. R_pdfviewer may hold arguments.
  silent! delfunction g:ROpenPDF2
  silent! delfunction g:SyncTeX_forward2
  unlet! g:did_vimr_pdf_generic
  g:R_pdfviewer = 'myviewer --flag'
  execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_generic.vim')
  err = Caught(() => {
    g:ROpenPDF2(odd .. '/doc.pdf')
  })
  g:AssertEqual([err, Logged(shlog)], ['', ['--flag', odd .. '/doc.pdf', 'end']],
    'generic viewer: the path is one argument after those of R_pdfviewer')

  # Qpdfview got the same quotes, and its forward search escaped only spaces
  delfunction g:ROpenPDF2
  delfunction g:SyncTeX_forward2
  unlet! g:did_vimr_pdf_qpdfview
  execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_qpdfview.vim')
  err = Caught(() => {
    g:ROpenPDF2(odd .. '/doc.pdf')
  })
  g:AssertEqual([err, Logged(shlog)], ['', ['--unique', odd .. '/doc.pdf', 'end']],
    'qpdfview: the path is one argument')
  err = Caught(() => {
    g:SyncTeX_forward2(odd .. '/doc.tex', odd .. '/doc.pdf', 12, 1)
  })
  g:AssertEqual([err, Logged(shlog)],
    ['', ['--unique', odd .. '/doc.pdf#src:' .. odd .. '/doc.tex:12:1', 'end']],
    'qpdfview: the forward search is one argument')

  # ROpenDoc() gave lowriter a bare path
  err = Caught(() => {
    g:ROpenDoc(odd .. '/doc.odt', '')
  })
  g:AssertEqual([err, Logged(shlog)], ['', [odd .. '/doc.odt', 'end']],
    'lowriter: the path is one argument')

  # RViewDF() appended a bare path to the program in R_csv_app
  g:rplugin.tmpdir = odd
  g:R_csv_app = 'myviewer --flag'
  err = Caught(() => {
    g:RViewDF('df', '', "a\x14b")
  })
  g:AssertEqual([err, Logged(shlog)], ['', ['--flag', odd .. '/df.tsv', 'end']],
    'RViewDF: a program gets the path as one argument')
  g:Assert(!filereadable(work .. '/INJECTED'), 'shell commands: no part of a path is run as a command')

  # The path went bare into the shell command of "%s", and into :terminal,
  # which split it at each space, replaced "%" and "#" with the names of the
  # current and the alternate file, and dropped double quotes and backslashes
  var odd2 = work .. '/it''s a "%b" #c $HOME [1] !x \ dir'
  mkdir(odd2, 'p')
  g:rplugin.tmpdir = odd2
  for [app, expected] in [
      ['myviewer %s --flag', [odd2 .. '/df.tsv', '--flag', 'end']],
      ['terminal:myviewer --flag', ['--flag', odd2 .. '/df.tsv', 'end']],
      ['terminal:myviewer %s --flag', [odd2 .. '/df.tsv', '--flag', 'end']]]
    g:R_csv_app = app
    err = Caught(() => {
      g:RViewDF('df', '', "a\x14b")
    })
    stopinsert
    g:AssertEqual([err, Logged(shlog)], ['', expected], 'RViewDF: "' .. app .. '" gets the path as one argument')
    TerminalsDone()
    silent! tabonly
    silent! only
    execute 'buffer ' .. rbuf
  endfor

  # ShowRout() gave :bunload a bare name, so a space or a bracket in the name
  # of a loaded Rout file stopped it before R ran. The stand-in for R writes
  # the Rout file, which is its last argument.
  writefile(['#!/bin/sh', 'for a in "$@"; do printf ''%s\n'' "$a" >> "$RR_TEST_LOG"; last=$a; done',
    'echo "> 1" > "$last"', 'echo end >> "$RR_TEST_LOG"'], bindir .. '/rbatch')
  setfperm(bindir .. '/rbatch', 'rwx------')
  var saved_rcmd = g:rplugin.Rcmd
  g:rplugin.Rcmd = bindir .. '/rbatch'
  writefile(['1'], work .. '/my [1].R')
  writefile(['> 1'], work .. '/my [1].Rout')
  execute 'edit ' .. fnameescape(work .. '/my [1].R')
  execute 'split ' .. fnameescape(work .. '/my [1].Rout')
  wincmd p
  err = Caught(() => {
    g:ShowRout()
  })
  var rout_loaded = bufloaded(work .. '/my [1].Rout')
  g:AssertEqual([err, rout_loaded, Logged(shlog)[-3 :]->mapnew((_, v) => fnamemodify(v, ':t'))],
    ['', 0, ['my [1].R', 'my [1].Rout', 'end']],
    'ShowRout: unloads the loaded "my [1].Rout" and runs R on the script')
  # The job hands the new Rout file to GetRCmdBatchOutput() when it ends
  for _ in range(40)
    if !has_key(g:rplugin.jobs, 'R_CMD') || job_status(g:rplugin.jobs['R_CMD']) !=# 'run'
      break
    endif
    sleep 50m
  endfor
  sleep 100m
  g:rplugin.Rcmd = saved_rcmd
  silent! tabonly
  silent! only
  execute 'buffer ' .. rbuf

  execute 'cd ' .. fnameescape(saved_cwd)
  $PATH = saved_path
  if type(saved_viewer) == v:t_none
    unlet g:R_pdfviewer
  else
    g:R_pdfviewer = saved_viewer
  endif
endif

# ========================================================================
# Programs on Windows: a path is one argument
# ========================================================================
# RViewDF() gave ":!start" the bare path, and Vim replaced "%", "#", and "!"
# in it. It ignored "%s" in R_csv_app and took the whole value for the name
# of the program. :terminal split the path at each space and replaced "%"
# and "#" as well. Where a C compiler exists, a stand-in program is built
# that appends its arguments to $RR_TEST_LOG. It is a program of the Windows
# subsystem, so it opens no console window. It lingers after its log, as a
# program may on a loaded machine.
if has('win32') && executable('gcc')
  var wbin = work .. '/wbin'
  var wodd = work .. "/it's a %b #c $HOME [1] !x dir"
  mkdir(wbin, 'p')
  mkdir(wodd, 'p')
  writefile(['#include <stdio.h>', '#include <stdlib.h>', '#include <windows.h>',
    'int main(int argc, char **argv) {',
    '    FILE *f = fopen(getenv("RR_TEST_LOG"), "a");', '    if (!f)', '        return 1;',
    '    for (int i = 1; i < argc; i++)', '        fprintf(f, "%s\n", argv[i]);', '    fprintf(f, "end\n");',
    '    fclose(f);', '    Sleep(1000);', '    return 0;', '}'], wbin .. '/argv.c')
  var exe = wbin .. '/argv.exe'
  var cc = job_start(['gcc', '-mwindows', wbin .. '/argv.c', '-o', exe],
    {in_io: 'null', out_io: 'null', err_io: 'null'})
  for _ in range(600)
    if job_status(cc) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  $RR_TEST_LOG = work .. '/win.log'
  g:rplugin.tmpdir = wodd
  var tsv = wodd .. '/df.tsv'
  for [app, expected] in [
      [exe, [tsv, 'end']],
      ['"' .. exe .. '" --flag %s', ['--flag', tsv, 'end']],
      ['terminal:"' .. exe .. '" --flag', ['--flag', tsv, 'end']],
      ['terminal:"' .. exe .. '" %s --flag', [tsv, '--flag', 'end']]]
    g:R_csv_app = app
    err = Caught(() => {
      g:RViewDF('df', '', "a\x14b")
    })
    stopinsert
    g:AssertEqual([err, Logged($RR_TEST_LOG)], ['', expected],
      'RViewDF: "' .. substitute(app, '.*argv\.exe"\=', 'PROGRAM', '') .. '" gets the path as one argument')
    TerminalsDone()
    silent! tabonly
    silent! only
    execute 'buffer ' .. rbuf
  endfor
  unlet $RR_TEST_LOG
endif
g:rplugin.tmpdir = saved_tmpdir
if type(saved_csv_app) == v:t_none
  unlet g:R_csv_app
else
  g:R_csv_app = saved_csv_app
endif

# ========================================================================
# Windows: the batch file that queries the registry
# ========================================================================
# g:SetRHome() ran the batch file by a bare path, so a space in the temporary
# directory left HOME as it was. The check needs cmd.exe as the shell.
if has('win32') && exists('*g:SetRHome')
  var saved_shell = [&shell, &shellcmdflag, &shellxquote, &shellquote, &shellredir]
  var saved_home_env = g:R_set_home_env
  &shell = $COMSPEC
  &shellcmdflag = '/c'
  &shellxquote = '('
  &shellquote = ''
  &shellredir = '>%s 2>&1'
  g:R_set_home_env = 1
  var homes: list<string> = []
  for dir in ['plain', 'tmp dir']
    g:rplugin.tmpdir = work .. '/' .. dir
    mkdir(g:rplugin.tmpdir, 'p')
    g:SetRHome()
    add(homes, $HOME)
    g:UnsetRHome()
  endfor
  g:AssertEqual(homes[1], homes[0], 'SetRHome: a space in the temporary directory changes nothing')
  g:rplugin.tmpdir = saved_tmpdir
  g:R_set_home_env = saved_home_env
  [&shell, &shellcmdflag, &shellxquote, &shellquote, &shellredir] = saved_shell
endif

# ========================================================================
# R commands: a file name is quoted for R, and R quotes it for its shell
# ========================================================================
# RMakeHTMLrrst() sent system("rst2odt NAME.rst NAME.odt") with bare names
writefile(['Title', '=====', '', 'text'], work .. "/it's my file.Rrst")
execute 'edit ' .. fnameescape(work .. "/it's my file.Rrst")
var sent: list<string> = []
var SavedSend = g:SendCmdToR
var saved_rst2pdf = g:rplugin.rrst_has_rst2pdf
g:rplugin.rrst_has_rst2pdf = 1
def g:TestRecordCmd(...args: list<any>): number
  add(g:rr_test_sent, args[0])
  return 1
enddef
g:rr_test_sent = []
g:SendCmdToR = function('g:TestRecordCmd')
err = Caught(() => {
  g:RMakeHTMLrrst('odt')
})
g:AssertEqual(err, '', 'RMakeHTMLrrst: no error')
g:AssertMatch(get(g:rr_test_sent, -1, ''),
  '; system2("rst2odt", shQuote(c(".*it''s my file\.rst", ".*it''s my file\.odt")))$',
  'RMakeHTMLrrst: R quotes the two file names for its shell')
g:SendCmdToR = SavedSend
g:rplugin.rrst_has_rst2pdf = saved_rst2pdf
delfunction g:TestRecordCmd
unlet g:rr_test_sent
bwipeout!

# ========================================================================
# Evince: only the window of the document counts
# ========================================================================
# The monitor shows the signals of every Evince window, and every Evince
# process names its first window /org/gnome/evince/Window/0
import '../R/evince_dbus.vim' as evdbus
var win_px = evdbus.NewProxy()
win_px.dbus_name = ':1.42'
win_px.window_path = '/org/gnome/evince/Window/0'
win_px.connected = true
var sig = {sender: ':1.42', path: '/org/gnome/evince/Window/0', member: 'SyncSource'}
g:Assert(evdbus.IsFromWindow(win_px, sig), 'Evince: a signal of the connected window is taken')
g:Assert(!evdbus.IsFromWindow(win_px, extendnew(sig, {sender: ':1.77'})),
  'Evince: a signal of another Evince process is ignored')
g:Assert(!evdbus.IsFromWindow(win_px, extendnew(sig, {path: '/org/gnome/evince/Window/1'})),
  'Evince: a signal of another window of the process is ignored')
win_px.connected = false
g:Assert(!evdbus.IsFromWindow(win_px, sig), 'Evince: no signal is taken while the window is unknown')

silent! tabonly
silent! only
# On Unix the work directory lies in the temporary directory of Vim, which Vim
# removes when it exits. On Windows it stays, so what the blocks above made
# there is removed by name, after the buffers have given up their swap files.
if has('win32')
  silent! :%bwipeout!
  for name in ['main.Rnw', 'my file.tex', 'a%b.tex', 'a#b.tex', 'a[1].tex', 'main.R', 'a%b.Rout', 'a%b.R',
      't%d/df.tsv', 't%d/df2.tsv', 'plain/run_cmd.bat', 'tmp dir/run_cmd.bat', "it's my file.Rrst",
      'wbin/argv.c', 'wbin/argv.exe', "it's a %b #c $HOME [1] !x dir/df.tsv"]
    delete(work .. '/' .. name)
  endfor
  for dir in ['/t%d', '/plain', '/tmp dir', '/wbin', "/it's a %b #c $HOME [1] !x dir", '']
    delete(work .. dir, 'd')
  endfor
endif
