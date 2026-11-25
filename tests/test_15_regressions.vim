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
if saved_prompt == v:none
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
if saved_rstudio_cmd == v:none
  unlet g:RStudio_cmd
else
  g:RStudio_cmd = saved_rstudio_cmd
endif
