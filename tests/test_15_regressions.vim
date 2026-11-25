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
