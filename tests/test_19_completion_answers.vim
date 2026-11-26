vim9script
# Regression tests for the answers to a request of the completion menu. When
# an item of the menu is selected, the plugin asks the server for its
# information, and the server or the plugin asks R for a part of it. Each
# answer arrives later, when the user may have moved to another item or left
# the menu. The answers were written into whatever item was selected then,
# so an item showed the information of another one, and they raised an error
# when no item with a dictionary of its own was selected.

g:SetSuite('completion_answers')

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
var err = ''
writefile(['x <- 1'], work .. '/answers.R')
execute 'edit ' .. fnameescape(work .. '/answers.R')
var answers_buf = bufnr('%')
if !exists('*g:SetComplInfo')
  execute 'source ' .. fnameescape(plugin_root .. '/R/complete.vim')
endif
if !exists('*g:RDebugJump')
  execute 'source ' .. fnameescape(plugin_root .. '/R/start_r.vim')
endif

var saved_event: dict<any> = g:rplugin.compl_event
var saved_usage = g:rplugin.compl_usage
var saved_asked = get(g:rplugin, 'compl_asked', '')

# Put the plugin into the state that AskForComplInfo() leaves when an item is
# selected. The event of the menu holds the item, and the plugin remembers the
# word that it asked the server about.
def Select(word: string, user_data: any, asked: string)
  g:rplugin.compl_event = {completed_item: {word: word, user_data: user_data},
    col: 1.0, row: 1.0, width: 10.0, height: 2.0, scrollbar: false}
  g:rplugin.compl_asked = asked
  g:rplugin.compl_usage = 'usage of an earlier item'
enddef
# The data of the selected item
def Data(): any
  return get(get(g:rplugin.compl_event, 'completed_item', {}), 'user_data', 'no item')
enddef

# ========================================================================
# FinishGlbEnvFunArgs: the arguments of a function, which R sends
# ========================================================================
var fun_args = "[\x12a\x12], [\x12b\x12, \x122\x12], "
Select('plainf', {cls: 'f', pkg: '.GlobalEnv', descr: 'text'}, 'plainf')
err = Caught(() => {
  g:FinishGlbEnvFunArgs('plainf', fun_args)
})
g:AssertEqual([err, g:rplugin.compl_usage, Data()],
  ['', 'plainf(a, b = 2)', {cls: 'f', pkg: '.GlobalEnv', descr: ''}],
  'FinishGlbEnvFunArgs: the answer for the selected function is applied')

Select('zetanum', {cls: '{', pkg: '.GlobalEnv', descr: 'text'}, 'zetanum')
err = Caught(() => {
  g:FinishGlbEnvFunArgs('plainf', fun_args)
})
g:AssertEqual([err, g:rplugin.compl_usage, Data()],
  ['', 'usage of an earlier item', {cls: '{', pkg: '.GlobalEnv', descr: 'text'}],
  'FinishGlbEnvFunArgs: the answer for another item changes nothing')

# The item of another plugin carries a string as its data
Select('plainf', 'data of another plugin', 'plainf')
err = Caught(() => {
  g:FinishGlbEnvFunArgs('plainf', fun_args)
})
g:AssertEqual([err, g:rplugin.compl_usage, Data()],
  ['', 'usage of an earlier item', 'data of another plugin'],
  'FinishGlbEnvFunArgs: data of the item that is a string raises nothing')

g:rplugin.compl_event = {}
err = Caught(() => {
  g:FinishGlbEnvFunArgs('plainf', fun_args)
})
g:AssertEqual([err, g:rplugin.compl_event], ['', {}],
  'FinishGlbEnvFunArgs: no selected item raises nothing')

# ========================================================================
# FinishGetSummary: the summary of an object, which R sends with its word
# ========================================================================
# The answer held only the text, so nothing told which item it was for. R
# now sends the word that the summary was asked for as well.
var column = {cls: '{', word: 'zetadf$first', pkg: '.GlobalEnv', usage: [], ttl: '', descr: ''}
Select('zetadf$first', copy(column), 'zetadf$first')
err = Caught(() => {
  g:FinishGetSummary("Min. 1\x14it\x13s Max. 3", 'zetadf$first')
})
g:AssertEqual([err, get(Data(), 'summary', 'no summary')], ['', ['Min. 1', "it's Max. 3"]],
  'FinishGetSummary: the answer for the selected column is applied')

var other = {cls: '{', word: 'zetadf$second', pkg: '.GlobalEnv', usage: [], ttl: '', descr: ''}
Select('zetadf$second', copy(other), 'zetadf$second')
err = Caught(() => {
  g:FinishGetSummary("Min. 1\x14Max. 3", 'zetadf$first')
})
g:AssertEqual([err, Data()], ['', other], 'FinishGetSummary: the answer for another item changes nothing')

Select('zetadf$first', 'data of another plugin', 'zetadf$first')
err = Caught(() => {
  g:FinishGetSummary("Min. 1\x14Max. 3", 'zetadf$first')
})
g:AssertEqual([err, Data()], ['', 'data of another plugin'],
  'FinishGetSummary: data of the item that is a string raises nothing')

g:rplugin.compl_event = {}
err = Caught(() => {
  g:FinishGetSummary("Min. 1\x14Max. 3", 'zetadf$first')
})
g:AssertEqual([err, g:rplugin.compl_event], ['', {}], 'FinishGetSummary: no selected item raises nothing')

# ========================================================================
# SetComplInfo: the information on an item, which the server sends
# ========================================================================
var info = {cls: 'f', word: 'read.csv', pkg: 'utils', usage: [['file'], ['header', 'TRUE']],
  ttl: 'Data Input', descr: 'Reads a file'}
Select('read.csv', {cls: 'f', pkg: 'utils'}, 'read.csv')
err = Caught(() => {
  g:SetComplInfo(info)
})
g:AssertEqual([err, g:rplugin.compl_usage, Data()], ['', 'read.csv(file, header = TRUE)', info],
  'SetComplInfo: the answer for the selected item is applied')

Select('zetanum', {cls: '{', pkg: '.GlobalEnv'}, 'zetanum')
err = Caught(() => {
  g:SetComplInfo(info)
})
g:AssertEqual([err, g:rplugin.compl_usage, Data()],
  ['', 'usage of an earlier item', {cls: '{', pkg: '.GlobalEnv'}],
  'SetComplInfo: the answer for another item changes nothing')

Select('read.csv', 'data of another plugin', 'read.csv')
err = Caught(() => {
  g:SetComplInfo(info)
})
g:AssertEqual([err, Data()], ['', 'data of another plugin'],
  'SetComplInfo: data of the item that is a string raises nothing')

g:rplugin.compl_event = {}
err = Caught(() => {
  g:SetComplInfo(info)
  # The server found nothing for a word
  g:SetComplInfo({})
})
g:AssertEqual([err, g:rplugin.compl_event], ['', {}], 'SetComplInfo: no selected item raises nothing')

# For an element of a list or a column of a data frame the plugin asks R for
# the summary, and names the word a second time, as a string that R sends
# back. A program that copies its input into a file stands in for the
# server, which passes the request on to R. It goes into a table of jobs that
# is declared for any value.
def g:RrTestAnswersSend(...args: list<any>): number
  return 1
enddef
var SavedSend = g:SendCmdToR
g:SendCmdToR = function('g:RrTestAnswersSend')
var saved_jobs: dict<any> = g:rplugin.jobs
var answers_jobs: dict<any> = g:rplugin.jobs->copy()
var sent_log = work .. '/answers_sent.txt'
answers_jobs['Server'] = job_start(has('win32') ? ['findstr', '^'] : ['cat'],
  {out_io: 'file', out_name: sent_log, err_io: 'null'})
g:rplugin.jobs = answers_jobs
Select('zetadf$first', {cls: '{', pkg: '.GlobalEnv'}, 'zetadf$first')
err = Caught(() => {
  g:SetComplInfo(column)
  # The same answer once the user has moved to the other column
  g:rplugin.compl_asked = 'zetadf$second'
  g:SetComplInfo(column)
})
ch_close_in(job_getchannel(g:rplugin.jobs['Server']))
for _ in range(100)
  if job_status(g:rplugin.jobs['Server']) !=# 'run'
    break
  endif
  sleep 50m
endfor
job_stop(g:rplugin.jobs['Server'], 'kill')
var sent_lines = (filereadable(sent_log) ? readfile(sent_log) : [])
  ->mapnew((_, l) => substitute(l, '\r$', '', ''))
g:AssertEqual([err, sent_lines],
  ['', ['2E' .. $VIMR_ID .. 'vimcom:::vim.get.summary(zetadf$first, 59, "zetadf$first")']],
  'SetComplInfo: the summary is asked once, for the selected column, with its word as a string')
g:rplugin.jobs = saved_jobs
g:SendCmdToR = SavedSend
delfunction g:RrTestAnswersSend

# ========================================================================
# OnCompleteDone: an answer that arrives after the menu was left is dropped
# ========================================================================
Select('plainf', {cls: 'f', pkg: '.GlobalEnv', descr: 'text'}, 'plainf')
err = Caught(() => {
  g:OnCompleteDone()
  g:FinishGlbEnvFunArgs('plainf', fun_args)
})
g:AssertEqual([err, g:rplugin.compl_usage], ['', 'usage of an earlier item'],
  'OnCompleteDone: an answer that arrives after the menu was left changes nothing')

g:rplugin.compl_event = saved_event
g:rplugin.compl_usage = saved_usage
g:rplugin.compl_asked = saved_asked
enew
execute 'bwipeout! ' .. answers_buf
# On Unix the work directory lies in the temporary directory of Vim, which Vim
# removes when it exits. On Windows it stays, so the two files that the blocks
# above made there are removed by name.
if has('win32')
  delete(work .. '/answers.R')
  delete(sent_log)
  delete(work, 'd')
endif
