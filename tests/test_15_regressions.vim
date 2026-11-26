vim9script
# Regression tests that call the plugin's own functions in real buffers.
# Each block names the defect it guards against.

g:SetSuite('regressions')

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

def OpenBuf(ext: string, ft: string, lines: list<string>): string
  var tmpfile = tempname() .. ext
  writefile(lines, tmpfile)
  execute 'edit ' .. fnameescape(tmpfile)
  if &filetype != ft
    execute 'set filetype=' .. ft
  endif
  return tmpfile
enddef

def CloseBuf(tmpfile: string)
  bwipeout!
  delete(tmpfile)
enddef

# ========================================================================
# R buffer
# ========================================================================
var rfile = OpenBuf('.R', 'r', ['ééé <- mean(xyz)', 'ééé <- mea', 'x <- 1', 'y <- 2', 'z <- 3'])

# The cursor column is a byte offset, and a string index counts characters
cursor(1, 12)
var keyword = ''
var err = Caught(() => {
  keyword = g:RGetKeyword()
})
g:AssertEqual(err, '', 'RGetKeyword: no error after multibyte text')
g:AssertEqual(keyword, 'mean', 'RGetKeyword: keyword after multibyte text')

cursor(2, 14)
var startcol = -1
err = Caught(() => {
  startcol = g:FindStartRObj()
})
g:AssertEqual(err, '', 'FindStartRObj: no error after multibyte text')
g:AssertEqual(startcol, 10, 'FindStartRObj: byte column after multibyte text')

# The maps exist before start_r.vim is sourced, so their targets must too
g:AssertMatch(maparg('<Plug>RSendMotion', 'n'), 'opfunc=RSendMotion',
  'RSendMotion: operatorfunc names a function')
g:Assert(exists('*g:RSendMotion'), 'RSendMotion: the operator function is defined')
for name in ['RKnit', 'RSetWD', 'RSourceLines']
  g:Assert(exists('*g:' .. name), name .. ': callable before R starts')
endfor

# Completion asks vimrserver, which is not running in the tests
var matches: any = 0
var server_job = g:rplugin.jobs["Server"]
g:rplugin.jobs["Server"] = "no"
err = Caught(() => {
  cursor(2, 14)
  if g:CompleteR(1, '') >= 0
    matches = g:CompleteR(0, 'mea')
  endif
})
g:rplugin.jobs["Server"] = server_job
g:AssertEqual(err, '', 'CompleteR: no error without the server')
g:AssertEqual(string(matches), '[]', 'CompleteR: no matches without the server')

# A string expression given to filter() cannot see the local variable
var opts: list<any> = []
err = Caught(() => {
  opts = g:CompleteChunkOptions('ech')
})
g:AssertEqual(err, '', 'CompleteChunkOptions: no error with a base')
g:AssertEqual(mapnew(opts, (_, v) => v.abbr), ['echo'], 'CompleteChunkOptions: filters by the base')

# Messages from vimrserver carry a byte count
g:regr_recv = []
var first = "call add(g:regr_recv, 'ééé')"
var second = "call add(g:regr_recv, 'two')"
var Frame = (s: string): string => "\x11" .. strlen(s) .. "\x11" .. s
err = Caught(() => {
  g:ROnJobStdout('none', Frame(first) .. Frame(second))
})
g:AssertEqual(err, '', 'ROnJobStdout: no error for two multibyte messages in one chunk')
g:AssertEqual(g:regr_recv, ['ééé', 'two'], 'ROnJobStdout: splits two messages by byte count')

g:regr_recv = []
var framed = Frame(first) .. Frame(second)
var cut = strlen(Frame(first)) - 5
err = Caught(() => {
  g:ROnJobStdout('none', strpart(framed, 0, cut))
  g:ROnJobStdout('none', strpart(framed, cut))
})
g:AssertEqual(err, '', 'ROnJobStdout: no error for a message split across chunks')
g:AssertEqual(g:regr_recv, ['ééé', 'two'], 'ROnJobStdout: keeps the message that follows a split one')
unlet g:regr_recv

# A count before a command needs a colon inside :execute
if !exists('*g:FinishRFormatCode')
  execute 'source ' .. fnameescape(plugin_root .. '/R/start_r.vim')
endif
err = Caught(() => {
  g:FinishRFormatCode(3, 4, "x <- 10\x14y <- 20")
})
g:AssertEqual(err, '', 'FinishRFormatCode: no error')
g:AssertEqual(getline(3, 5), ['x <- 10', 'y <- 20', 'z <- 3'], 'FinishRFormatCode: replaces the range')

CloseBuf(rfile)

# ========================================================================
# R Markdown buffer
# ========================================================================
# Quarto is supported only when R_filetypes names it. R Markdown is
# supported unless the list leaves it out.
unlet! g:R_filetypes
var plain = OpenBuf('.qmd', 'quarto', ['text'])
g:AssertEqual(maparg('<Plug>RNextRChunk', 'n') .. maparg('`', 'i') .. maparg('<Plug>RQuartoRender', 'n'), '',
  'quarto: no maps unless R_filetypes names the file type')
CloseBuf(plain)
plain = OpenBuf('.Rmd', 'rmd', ['text'])
g:Assert(maparg('<Plug>RNextRChunk', 'n') != '', 'rmd: maps are defined without R_filetypes')
CloseBuf(plain)
g:R_filetypes = ['r', 'rnoweb']
plain = OpenBuf('.Rmd', 'rmd', ['text'])
g:AssertEqual(maparg('<Plug>RNextRChunk', 'n'), '', 'rmd: no maps when R_filetypes leaves the file type out')
CloseBuf(plain)
g:R_filetypes = ['r', 'rmd', 'rnoweb', 'rhelp', 'rrst', 'quarto']
var named = OpenBuf('.qmd', 'quarto', ['text'])
g:Assert(maparg('<Plug>RNextRChunk', 'n') != '' && maparg('<Plug>RQuartoRender', 'n') != '',
  'quarto: maps are defined when R_filetypes names the file type')
CloseBuf(named)

var rmdfile = OpenBuf('.Rmd', 'rmd', [
  '---',
  'title: "t"',
  'bibliography: [a.bib, "b c.bib", ''d.bib'']',
  '---',
  '',
  'Some text',
  '',
  '```{r}',
  'x <- 1',
  '```',
])

# comment.vim is sourced at start-up only when R_enable_comment is set
if !exists('*g:RComment')
  execute 'source ' .. fnameescape(plugin_root .. '/R/comment.vim')
endif
cursor(9, 1)
err = Caught(() => {
  g:RComment('normal')
})
g:AssertEqual(err, '', 'RComment: no error in an R chunk of an rmd buffer')
g:AssertMatch(getline(9), '^#', 'RComment: comments a line of an R chunk')

# The YAML list is not Vim script, so it must not go through eval()
var bib = ''
err = Caught(() => {
  bib = g:RmdGetYamlField('bibliography')
})
g:AssertEqual(err, '', 'RmdGetYamlField: no error for a flow sequence')
g:AssertEqual(split(bib, "\x06"), ['a.bib', 'b c.bib', 'd.bib'], 'RmdGetYamlField: reads a flow sequence')

setline(3, 'bibliography: $HOME/%.bib')
g:AssertEqual(g:RmdGetYamlField('bibliography'), '$HOME/%.bib', 'RmdGetYamlField: leaves % and $ alone')

CloseBuf(rmdfile)

# ========================================================================
# Rnoweb buffers: the second one sources the guarded scripts again
# ========================================================================
var rnw1 = OpenBuf('.Rnw', 'rnoweb', ['\documentclass{article}', '\begin{document}', 'ééé \bot', '\end{document}'])
err = Caught(() => {
  execute 'edit ' .. fnameescape(tempname() .. '.Rnw')
  set filetype=rnoweb
  g:SetPDFdir()
  doautocmd BufWritePost
})
g:AssertEqual(err, '', 'rnoweb: a second buffer leaves the script functions defined')
bwipeout!

# LaTeX commands complete from the backslash, which follows multibyte text
execute 'buffer ' .. bufnr(rnw1)
cursor(3, 12)
var texcol = -1
var texcmds: any = []
err = Caught(() => {
  texcol = g:RnwNonRCompletion(1, '')
  texcmds = g:RnwNonRCompletion(0, '\bot')
})
g:AssertEqual(err, '', 'RnwNonRCompletion: no error after multibyte text')
g:AssertEqual(texcol, 7, 'RnwNonRCompletion: byte column of the backslash')
g:AssertEqual(texcmds, [{word: '\bottomrule'}], 'RnwNonRCompletion: completes a LaTeX command')

CloseBuf(rnw1)

# TeX lines past the end of the concordance have no Rnoweb source
var concbase = tempname()
writefile(range(1, 6)->mapnew((_, v) => 'line ' .. v), concbase .. '.tex')
writefile(['\Sconcordance{concordance:doc.tex:doc.Rnw:%', '1 2 1}'], concbase .. '-concordance.tex')
var conc: dict<list<any>> = {}
err = Caught(() => {
  conc = g:SyncTeX_readconc(concbase)
})
g:AssertEqual(err, '', 'SyncTeX_readconc: no error')
g:AssertEqual(get(conc, 'rnwline', []), [1, 2, 3, 0, 0, 0], 'SyncTeX_readconc: line 0 past the concordance')
g:AssertEqual(get(conc, 'rnwfile', []), ['doc.Rnw', 'doc.Rnw', 'doc.Rnw', '', '', ''],
  'SyncTeX_readconc: empty file name past the concordance')
delete(concbase .. '.tex')
delete(concbase .. '-concordance.tex')

# ========================================================================
# PDF viewers: backward search with Okular, and the D-Bus state for Evince
# ========================================================================
# Okular prints a backward search as a line of Vim script. The file name in
# that line is data, so the line is parsed and never executed. The file does
# not exist, and the warning about it shows the name that was passed on.
execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_okular.vim')
var OkularOut = function(matchstr(execute('function /OkularJobStdout'), '<SNR>\d\+_OkularJobStdout'))
var saved_msgs = get(g:rplugin, 'start_msg', v:none)
g:rplugin.start_msg = []
err = Caught(() => {
  OkularOut(null_channel, 'call SyncTeX_backward("/nowhere/a"b\c.tex",  str2nr("3"))')
})
g:AssertEqual(err, '', 'Okular: no error for a quote and a backslash in the file name')
g:AssertEqual(g:rplugin.start_msg, ["Could not find '/nowhere/a\"b\\c.Rnw'."],
  'Okular: the file name reaches SyncTeX_backward unchanged')
g:rr_okular_ran = 0
g:rplugin.start_msg = []
err = Caught(() => {
  OkularOut(null_channel, 'call SyncTeX_backward("/nowhere/x" .. execute("g:rr_okular_ran = 1")'
    .. ' .. "y.tex",  str2nr("3"))')
  OkularOut(null_channel, 'call execute("g:rr_okular_ran = 2")')
})
g:AssertEqual([err, g:rr_okular_ran], ['', 0], 'Okular: text from a file name is not executed')
g:AssertEqual(len(g:rplugin.start_msg), 1, 'Okular: a line that is no backward search is ignored')
unlet g:rr_okular_ran

# Zathura prints the same line, and its callback treats it the same way.
# Sourcing the file without Zathura installed sets the viewer to "none".
var saved_viewer = get(g:rplugin, 'pdfviewer', v:none)
# Both viewer files define these two functions
delfunction g:ROpenPDF2
delfunction g:SyncTeX_forward2
execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_zathura.vim')
var ZathuraOut = function(matchstr(execute('function /ZathuraJobStdout'), '<SNR>\d\+_ZathuraJobStdout'))
g:rr_zathura_ran = 0
g:rplugin.start_msg = []
err = Caught(() => {
  ZathuraOut(null_channel, 'call SyncTeX_backward("/nowhere/a"b\c.tex",  str2nr("3"))')
  ZathuraOut(null_channel, 'call execute("g:rr_zathura_ran = 1")')
})
g:AssertEqual([err, g:rr_zathura_ran], ['', 0], 'Zathura: text from the output is not executed')
g:AssertEqual(g:rplugin.start_msg, ["Could not find '/nowhere/a\"b\\c.Rnw'."],
  'Zathura: the file name reaches SyncTeX_backward unchanged')
unlet g:rr_zathura_ran
if type(saved_viewer) == v:t_none
  remove(g:rplugin, 'pdfviewer')
else
  g:rplugin.pdfviewer = saved_viewer
endif
if type(saved_msgs) == v:t_none
  remove(g:rplugin, 'start_msg')
else
  g:rplugin.start_msg = saved_msgs
endif

# The forward search and the backward search of Evince each own a proxy, so
# resetting one of them leaves the connection of the other alone
import '../R/evince_dbus.vim' as evdbus
var back_px = evdbus.NewProxy()
var fwd_px = evdbus.NewProxy()
evdbus.Init(back_px, 'file:///tmp/a.pdf')
back_px.status = 'RUNNING'
evdbus.Init(fwd_px, 'file:///tmp/b.pdf')
fwd_px.status = 'RUNNING'
evdbus.Shutdown(fwd_px)
g:AssertEqual([back_px.uri, back_px.status], ['file:///tmp/a.pdf', 'RUNNING'],
  'Evince: resetting one proxy leaves the other one connected')
g:AssertEqual([fwd_px.uri, fwd_px.status], ['', 'CLOSED'], 'Evince: Shutdown resets its own proxy')

# ========================================================================
# Rout syntax: the prompt is matched literally and the option is not rewritten
# ========================================================================
var saved_prompt = get(g:, 'Rout_prompt_str', v:none)
g:Rout_prompt_str = 'a|b>'
var routfile = OpenBuf('.Rout', 'rout', ['a|b> x <- 1', 'a> x <- 2'])
err = Caught(() => {
  syntax clear
  set syntax=rout
})
g:AssertEqual(err, '', 'rout: no error for a prompt holding a pattern character')
g:AssertEqual(g:Rout_prompt_str, 'a|b>', 'rout: the prompt option keeps its value')
g:AssertEqual(synIDattr(synID(1, 1, 1), 'name'), 'routInput', 'rout: a line starting with the prompt is input')
g:AssertNotEqual(synIDattr(synID(2, 1, 1), 'name'), 'routInput',
  'rout: a line starting with part of the prompt is not input')
CloseBuf(routfile)
if type(saved_prompt) == v:t_none
  unlet g:Rout_prompt_str
else
  g:Rout_prompt_str = saved_prompt
endif
unlet! g:R_filetypes

# ========================================================================
# start_r.vim: sourcing it keeps the placeholder that means R is not running
# ========================================================================
if !exists('*g:ClearRInfo')
  execute 'source ' .. fnameescape(plugin_root .. '/R/start_r.vim')
endif
g:Assert(exists('*g:SendCmdToR_fake'), 'start_r.vim: g:SendCmdToR_fake survives the sourcing')
g:AssertMatch(execute('verbose function SanitizeRLine'), 'indent[/\\]r\.vim',
  'start_r.vim: SanitizeRLine() of the R indent script of Vim is left in place')
g:AssertEqual(g:RSanitizeLine('x <- "a # b" # comment'), 'x <- s', 'RSanitizeLine: a string becomes a letter and the comment is removed')
g:SendCmdToR = function('g:RWarningMsg')
g:ClearRInfo()
g:AssertEqual(string(g:SendCmdToR), "function('g:SendCmdToR_fake')", 'ClearRInfo: the send function is reset')

# ========================================================================
# RStudio: a short hidden job stands in for the program
# ========================================================================
if !exists('*g:SignalToRStudio')
  execute 'source ' .. fnameescape(plugin_root .. '/R/rstudio.vim')
endif

var sent_to_r: list<string> = []
def g:TestSendCmdToR(...args: list<any>): number
  add(sent_to_r, args[0])
  return 1
enddef

# Start the stand-in, which exits by itself after about a second
def StartStandIn(): job
  var cmd = has('win32') ? ['cmd', '/c', 'ping -n 2 127.0.0.1 >nul'] : ['sleep', '1']
  var started = job_start(cmd, {exit_cb: 'g:ROnJobExit'})
  g:rplugin.jobs['RStudio'] = started
  g:rplugin.vimcom_connected = 1
  g:rplugin.R_pid = 4242
  g:SendCmdToR = function('g:TestSendCmdToR')
  sent_to_r = []
  return started
enddef

def WaitForExit(running: job)
  var t0 = reltime()
  while job_status(running) == 'run' && reltimefloat(reltime(t0)) < 10
    sleep 50m
  endwhile
  sleep 100m
enddef

def QuitTimers(): number
  return timer_info()->filter((_, t) => string(t.callback) =~ 'RStudioQuitTimeout')->len()
enddef

def RIsCleared(): bool
  return string(g:SendCmdToR) == "function('g:SendCmdToR_fake')"
    && g:rplugin.vimcom_connected == 0 && g:rplugin.R_pid == 0
enddef

var saved_rstudio_cmd = get(g:, 'RStudio_cmd', v:none)
g:RStudio_cmd = 'rstudio'

# RStudio closed from its own window, without a quit request from Vim
var standin = StartStandIn()
WaitForExit(standin)
g:AssertEqual(job_status(standin), 'dead', 'RStudio: the stand-in exited')
g:Assert(RIsCleared(), 'RStudio: closing the program by hand clears the state of R')

# A quit that saves the workspace must not be killed after two seconds
standin = StartStandIn()
g:RQuit('save')
g:AssertEqual(sent_to_r, ['quit(save = "yes")'], 'RStudio: the save request is sent')
g:AssertEqual(QuitTimers(), 0, 'RStudio: no kill timer while the workspace is saved')
g:AssertEqual(job_status(standin), 'run', 'RStudio: the program keeps running while it saves')
WaitForExit(standin)
g:Assert(RIsCleared(), 'RStudio: the state of R is cleared when the saving program exits')

# A quit without saving keeps the timer, and a normal exit cancels it
standin = StartStandIn()
g:RQuit('nosave')
g:AssertEqual(sent_to_r, ['quit(save = "no")'], 'RStudio: the quit request is sent')
g:AssertEqual(QuitTimers(), 1, 'RStudio: one kill timer after a quit without saving')
WaitForExit(standin)
g:AssertEqual(QuitTimers(), 0, 'RStudio: the kill timer is cancelled when the program exits')
g:Assert(RIsCleared(), 'RStudio: the state of R is cleared after a quit without saving')

g:rplugin.jobs['RStudio'] = 'no'
if type(saved_rstudio_cmd) == v:t_none
  unlet g:RStudio_cmd
else
  g:RStudio_cmd = saved_rstudio_cmd
endif

# ========================================================================
# SumatraPDF: a backward search is answered by the Vim that edits the document
# ========================================================================
delfunction g:ROpenPDF2
delfunction g:SyncTeX_forward2
unlet! g:did_vimr_pdf_sumatra
execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_sumatra.vim')
g:AssertEqual(readfile(plugin_root .. '/R/pdf_sumatra.vim')->filter((_, l) => l =~ 'inverse-search'), [],
  'SumatraPDF: no inverse search command is passed, so the saved one is kept')

var sumatra_dir = tempname()
mkdir(sumatra_dir .. '/child', 'p')
var saved_start_msg = get(g:rplugin, 'start_msg', v:none)
g:rplugin.start_msg = []
var sumatra_result: any = v:none
var sumatra_tex = sumatra_dir .. '\doc.tex'
err = Caught(() => {
  sumatra_result = g:SumatraInverseSearch(sumatra_tex, 3)
})
g:AssertEqual([err, sumatra_result, g:rplugin.start_msg], ['', '', []],
  'SumatraPDF: a Vim without an Rnoweb buffer of the document ignores the search')

execute 'edit ' .. fnameescape(sumatra_dir .. '/child/part.Rnw')
setlocal filetype=rnoweb
err = Caught(() => {
  sumatra_result = g:SumatraInverseSearch(sumatra_tex, 3)
})
g:AssertEqual([err, sumatra_result], ['', ''], 'SumatraPDF: the search returns an empty string')
g:AssertEqual(g:rplugin.start_msg, ["Could not find '" .. substitute(sumatra_dir, '\\', '/', 'g') .. "/doc.Rnw'."],
  'SumatraPDF: the Vim that edits the document passes the search to SyncTeX_backward')
bwipeout!
delete(sumatra_dir .. '/child', 'd')
delete(sumatra_dir, 'd')
if type(saved_start_msg) == v:t_none
  remove(g:rplugin, 'start_msg')
else
  g:rplugin.start_msg = saved_start_msg
endif

# ========================================================================
# RRaiseWindow: the window title is quoted for the shell by shellescape()
# ========================================================================
g:AssertEqual(readfile(plugin_root .. '/R/pdf_init.vim')
  ->filter((_, l) => l =~ 'wmctrl -a\|activateBySubstring s')
  ->filter((_, l) => l !~ 'shellescape(wttl)'), [],
  'RRaiseWindow: every shell command escapes the window title')

# ========================================================================
# Evince: file URIs are percent-encoded and decoded in full
# ========================================================================
g:AssertEqual(evdbus.PathToUri('/tmp/my doc/a.pdf'), 'file:///tmp/my%20doc/a.pdf',
  'Evince: a space in the PDF path is encoded as before')
g:AssertEqual(evdbus.PathToUri('/tmp/é#1 [x]/a%b;c.pdf'), 'file:///tmp/%C3%A9%231%20%5Bx%5D/a%25b%3Bc.pdf',
  'Evince: other characters of the PDF path are encoded')
g:AssertEqual(evdbus.PathToUri("/tmp/a-b_c.d~e!$&'()*+,:=@/f.pdf"), "file:///tmp/a-b_c.d~e!$&'()*+,:=@/f.pdf",
  'Evince: characters that a file URI allows are kept')
g:AssertEqual(evdbus.UriToPath('file:///tmp/%C3%A9%231%20%5Bx%5D/a%25b%3bc.tex'), '/tmp/é#1 [x]/a%b;c.tex',
  'Evince: the source file of a backward search is decoded')
g:AssertEqual(evdbus.UriToPath('/tmp/100%/a%zz.tex'), '/tmp/100%/a%zz.tex',
  'Evince: a percent sign that starts no escape is kept')

# ========================================================================
# SumatraPDF: an Rnoweb file of the document may be outside its directory
# ========================================================================
var conc_root = tempname()
mkdir(conc_root .. '/main', 'p')
mkdir(conc_root .. '/other', 'p')
writefile(range(1, 4)->mapnew((_, v) => 'tex line ' .. v), conc_root .. '/main/doc.tex')
writefile(['\Sconcordance{concordance:doc.tex:../other/part.Rnw:%', '1 4 1}'],
  conc_root .. '/main/doc-concordance.tex')
writefile(range(1, 4)->mapnew((_, v) => 'rnw line ' .. v), conc_root .. '/other/part.Rnw')
execute 'edit ' .. fnameescape(conc_root .. '/other/part.Rnw')
setlocal filetype=rnoweb
cursor(1, 1)
err = Caught(() => {
  g:SumatraInverseSearch(conc_root .. '/main/doc.tex', 3)
})
g:AssertEqual([err, expand('%:t'), line('.')], ['', 'part.Rnw', 3],
  'SumatraPDF: a Vim that edits a file named by the concordance answers the search')
bwipeout!
delete(conc_root .. '/main/doc.tex')
delete(conc_root .. '/main/doc-concordance.tex')
delete(conc_root .. '/other/part.Rnw')
delete(conc_root .. '/main', 'd')
delete(conc_root .. '/other', 'd')
delete(conc_root, 'd')

# ========================================================================
# Temporary directory: its owner alone may use it
# ========================================================================
# In Vim9 script 0700 is the decimal number 700. As a mode it gives a directory
# that its owner can neither read nor enter. An octal number is written 0o700.
var plugin_scripts = glob(plugin_root .. '/**/*.vim', false, true)
g:AssertEqual(plugin_scripts
  ->filter((_, f) => readfile(f)->filter((_, l) => l =~ 'mkdir(.*,\s*0\d\+)')->len() > 0)
  ->mapnew((_, f) => fnamemodify(f, ':t')), [],
  'tmpdir: no mkdir() with a mode that Vim9 script reads as decimal')
if !has('win32') && !has('win32unix')
  g:AssertEqual([getfperm(g:rplugin.localtmpdir), filewritable(g:rplugin.localtmpdir)], ['rwx------', 2],
    'tmpdir: the directory that the plugin made is usable by its owner alone')
endif

# ========================================================================
# Line endings: Vim on Unix does not source a script with CRLF line endings
# ========================================================================
g:AssertEqual(glob(plugin_root .. '/**/*.vim', false, true)
  ->filter((_, f) => readfile(f, 'b')->filter((_, l) => l =~ "\r$")->len() > 0)
  ->mapnew((_, f) => fnamemodify(f, ':t')), [],
  'line endings: every Vim script of the plugin ends its lines with LF')

# ========================================================================
# Compilation: every function that the plugin has defined compiles
# ========================================================================
# Vim compiles a function when it is first called, and a function that it
# calls along with it. Vim 9.1.1230 cannot compile a declaration that takes
# the result of mkdir() with two arguments, as MkRdir() had it. RInitExit()
# calls MkRdir(), so it did not compile either, and the server was never
# started with that Vim.
if !exists('*g:RInitExit')
  execute 'source ' .. fnameescape(plugin_root .. '/R/start_server.vim')
endif
g:AssertEqual(execute('function')->split("\n")
  ->mapnew((_, l) => matchstr(l, '^def \zs[^(]\+'))
  ->filter((_, n) => n != '')
  ->mapnew((_, n) => {
    try
      execute 'defcompile ' .. n
    catch
      return n .. ': ' .. v:exception
    endtry
    return ''
  })
  ->filter((_, e) => e != ''), [],
  'compilation: no function of the plugin fails to compile')

# ========================================================================
# RQuit: the connection that a requested quit drops is not reported as lost
# ========================================================================
# R may exit, and the server may report the lost connection, while RQuit()
# still waits for the quit command to arrive. The stand-in for the send
# function reports the lost connection at once.
def g:TestQuitAndDisconnect(...args: list<any>): number
  g:OnVimcomDisconnect()
  return 1
enddef
var saved_quit_msgs = get(g:rplugin, 'start_msg', v:none)
g:rplugin.start_msg = []
g:rplugin.vimcom_connected = 1
g:rplugin.R_pid = 4242
g:SendCmdToR = function('g:TestQuitAndDisconnect')
g:RQuit('nosave')
g:AssertEqual(g:rplugin.start_msg, [], 'RQuit: no warning for the connection that the quit itself drops')
g:Assert(RIsCleared(), 'RQuit: the state of R is cleared')

g:rplugin.vimcom_connected = 1
g:SendCmdToR = function('g:TestSendCmdToR')
g:OnVimcomDisconnect()
g:AssertEqual(g:rplugin.start_msg, ['Connection to R lost'],
  'OnVimcomDisconnect: a connection that is lost without a quit is still reported')
g:ClearRInfo()
if type(saved_quit_msgs) == v:t_none
  remove(g:rplugin, 'start_msg')
else
  g:rplugin.start_msg = saved_quit_msgs
endif

# ========================================================================
# StartR_Windows: a second start request while R is still starting
# ========================================================================
# Until vimcom has connected, the server cannot tell that R is running, and
# it answers a second request with an order to start R. While the time that
# R is given to start has not run out, the request is therefore answered in
# Vim, and no second R is started.
if has('win32')
  var saved_starting_msgs = get(g:rplugin, 'start_msg', v:none)
  var saved_r_args = get(g:rplugin, 'r_args', v:none)
  g:rplugin.r_args = []
  g:rplugin.start_msg = []
  g:SendCmdToR = function('g:SendCmdToR_NotYet')
  g:WaitVimcomStart()
  g:StartR_Windows()
  g:AssertEqual(g:rplugin.start_msg, ['R is starting'],
    'StartR_Windows: a second request while R is starting is answered with a warning')
  g:AssertEqual(string(g:SendCmdToR), "function('g:SendCmdToR_NotYet')",
    'StartR_Windows: the state of the first start is kept')
  g:ClearRInfo()

  # After that time the question goes to the server, which is not running here
  g:rplugin.start_msg = []
  g:SendCmdToR = function('g:SendCmdToR_NotYet')
  g:StartR_Windows()
  g:AssertEqual(g:rplugin.start_msg, [], 'StartR_Windows: no warning from Vim once R is no longer starting')
  g:ClearRInfo()
  if type(saved_starting_msgs) == v:t_none
    remove(g:rplugin, 'start_msg')
  else
    g:rplugin.start_msg = saved_starting_msgs
  endif
  if type(saved_r_args) == v:t_none
    remove(g:rplugin, 'r_args')
  else
    g:rplugin.r_args = saved_r_args
  endif
endif

# ========================================================================
# start_r.vim: a second sourcing deletes every global function it defines
# ========================================================================
# A global function that is missing from the list stops the second sourcing
# with E1073, and the functions below it keep their old definitions.
var start_r_lines = readfile(plugin_root .. '/R/start_r.vim')
var start_r_defined = start_r_lines
  ->mapnew((_, l) => matchstr(l, '^def g:\zs\w\+'))
  ->filter((_, n) => n != '')
var start_r_list_first = match(start_r_lines, '^\s*for fn in \[')
var start_r_list_last = match(start_r_lines, "^\\s*execute 'silent! delfunc g:'")
var start_r_listed = start_r_lines[start_r_list_first : start_r_list_last]->join(' ')
g:AssertEqual(start_r_defined->copy()->filter((_, n) => start_r_listed !~ "'" .. n .. "'"), [],
  'start_r.vim: every global function is in the list that a second sourcing deletes')

# ========================================================================
# PrintListTree: the file of the server is named and removed with the others
# ========================================================================
# vimrserver writes the list tree into its temporary directory. The function
# that asks for it tells where the file is and registers it for deletion.
# A variable takes the type of its first value, and the table holds only
# strings while no job runs. The copy is put back at the end, so it is
# declared for any value. Without that, Vim 9.2.1398 refuses a job in the
# table from then on, which Vim 9.1.1244 does not.
var saved_tree_jobs: dict<any> = g:rplugin.jobs->copy()
var saved_tree_del = g:rplugin.del_list->copy()
if !exists('*g:PrintListTree')
  execute 'source ' .. fnameescape(plugin_root .. '/ftplugin/rbrowser.vim')
  bwipeout!
endif
var tree_job = job_start(has('win32') ? ['cmd', '/c', 'more'] : ['cat'])
g:rplugin.jobs['Server'] = tree_job
var tree_said = ''
err = Caught(() => {
  tree_said = execute('g:PrintListTree()')
})
var tree_file = g:rplugin.localtmpdir .. '/listTree_' .. $VIMR_ID
g:AssertEqual(err, '', 'PrintListTree: no error')
g:Assert(stridx(tree_said, tree_file) >= 0, 'PrintListTree: the message names the file')
g:Assert(index(g:rplugin.del_list, tree_file) >= 0, 'PrintListTree: the file is removed with the other files')
job_stop(tree_job)
g:rplugin.jobs = saved_tree_jobs
g:rplugin.del_list = saved_tree_del
# The table that was put back must take a job again, as the plugin stores
# the server and R in it
err = Caught(() => {
  g:rplugin.jobs['Server'] = tree_job
})
g:AssertEqual(err, '', 'PrintListTree: the table of jobs takes a job after the test')
g:rplugin.jobs['Server'] = saved_tree_jobs['Server']
