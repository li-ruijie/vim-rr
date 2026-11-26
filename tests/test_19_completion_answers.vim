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
var fun_args = [['a'], ['b', '2']]
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

# The server writes the byte 0x13 in the place of each single quote of a name
Select("f'n", {cls: 'f', pkg: 'qpkg'}, "f'n")
err = Caught(() => {
  g:SetComplInfo({cls: 'f', word: "f\x13n", pkg: 'qpkg', usage: [['a']], ttl: '', descr: ''})
})
g:AssertEqual([err, g:rplugin.compl_usage], ['', "f'n(a)"],
  'SetComplInfo: the answer for a function whose name holds a single quote is applied')

# When the server finds nothing for a word, it sends the word alone, and the
# window of the item closes. The answer was an empty dictionary, which closed
# the window of whatever item was selected when it arrived, so the late answer
# for an item that the user had left closed the window of the next one.
var saved_float = g:rplugin.compl_float_win
var float_data = {cls: '{', pkg: '.GlobalEnv', descr: 'text'}
# Whether the window that was opened for the selected item is still open
def FloatOpen(id: number): bool
  return g:rplugin.compl_float_win == id && popup_getpos(id) != {}
enddef
var float_states: list<any> = []
err = Caught(() => {
  for answer in [{word: 'zetaother'}, {}]
    Select('zetanum', copy(float_data), 'zetanum')
    var id = popup_create(['window of zetanum'], {})
    g:rplugin.compl_float_win = id
    g:SetComplInfo(answer)
    add(float_states, [FloatOpen(id), Data()])
    popup_close(id)
  endfor
  for [word, answer] in [['zetanum', {word: 'zetanum'}], ["f'n", {word: "f\x13n"}]]
    Select(word, copy(float_data), word)
    var id = popup_create(['window of ' .. word], {})
    g:rplugin.compl_float_win = id
    g:SetComplInfo(answer)
    add(float_states, [FloatOpen(id), Data()])
    popup_close(id)
  endfor
})
g:AssertEqual([err, float_states[0 : 1]], ['', [[true, float_data], [true, float_data]]],
  'SetComplInfo: an answer of nothing found for another item, or with no word, leaves the window open')
g:AssertEqual(float_states[2 :], [[false, float_data], [false, float_data]],
  'SetComplInfo: an answer of nothing found for the selected item closes its window')
g:rplugin.compl_float_win = saved_float

# ========================================================================
# SetComplMenu: the items of the menu, which the server sends
# ========================================================================
# The server writes the byte 0x13 in the place of each single quote of a name
# and of the class of an object, which the menu shows
var menu_keys = ['compl_menu', 'waiting_compl_menu', 'completion_id', 'is_completing']
var saved_menu_state = menu_keys->mapnew((_, k) => [k, get(g:rplugin, k, v:none)])
g:rplugin.completion_id = 7
err = Caught(() => {
  g:SetComplMenu(7, [{word: "it\x13s", menu: "my\x13cls [.GlobalEnv]", user_data: {cls: '{'}},
    {word: "it\x13s"}])
})
g:AssertEqual([err, get(g:rplugin, 'compl_menu', [])],
  ['', [{word: "it's", menu: "my'cls [.GlobalEnv]", user_data: {cls: '{'}}, {word: "it's"}]],
  'SetComplMenu: the word and the class of an item have their single quotes')

# WaitRCompletion() waits a second for the menu. It returned the menu that
# it found then, which was that of an earlier request when R had not
# answered yet, and SetComplMenu() took the late answer for an earlier
# request as the answer for the one that was awaited. The answers come from
# timers here, which run while WaitRCompletion() sleeps.
var waited: list<any> = []
err = Caught(() => {
  # No answer comes
  g:rplugin.completion_id = 12
  g:rplugin.compl_menu = [{word: 'earlier'}]
  g:rplugin.waiting_compl_menu = 1
  add(waited, g:WaitRCompletion())
  # The answer for the earlier request comes late, and then the answer for
  # the request that is awaited
  timer_start(100, (_) => g:SetComplMenu(11, [{word: 'late'}]))
  timer_start(300, (_) => g:SetComplMenu(12, [{word: 'awaited'}]))
  add(waited, g:WaitRCompletion())
  # The late answer comes after the answer that was awaited
  g:SetComplMenu(11, [{word: 'late'}])
  add(waited, [g:rplugin.compl_menu, g:rplugin.waiting_compl_menu])
})
g:AssertEqual([err, waited], ['', [[], [{word: 'awaited'}], [[{word: 'awaited'}], 0]]],
  'WaitRCompletion: no menu without an answer, and a late answer for an earlier request is dropped')
for [key, value] in saved_menu_state
  if type(value) != v:t_none
    g:rplugin[key] = value
  elseif has_key(g:rplugin, key)
    remove(g:rplugin, key)
  endif
endfor

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
# The server writes the byte 0x13 in the place of each single quote of a name
var quoted = {cls: '{', word: "d\x13f$it\x13s", pkg: '.GlobalEnv', usage: [], ttl: '', descr: ''}
err = Caught(() => {
  g:SetComplInfo(column)
  # The same answer once the user has moved to the other column
  g:rplugin.compl_asked = 'zetadf$second'
  g:SetComplInfo(column)
  # A column whose name and whose data frame hold a single quote
  Select("it's", {cls: 'v', env: '.GlobalEnv', word: "d'f$it's"}, "d'f$it's")
  g:SetComplInfo(quoted)
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
var summary_head = '2E' .. $VIMR_ID .. 'vimcom:::vim.get.summary('
g:AssertEqual([err, sent_lines], ['', [summary_head .. '`zetadf`$`first`, 59, "zetadf$first")',
  summary_head .. "`d'f`$`it's`, 59, \"d'f$it's\")"]],
  'SetComplInfo: the summary is asked once for each selected column, with its word as a string')
g:AssertEqual(get(Data(), 'word', 'no word'), "d'f$it's",
  'SetComplInfo: the word of the answer has the single quotes of its names')
# R itself runs the request, with a function in the place of the one of
# vimcom that writes what it receives into a file
if executable('Rscript') && len(sent_lines) == 2
  var summary_out = work .. '/summary.out'
  writefile(["`d'f` <- data.frame(`it's` = c(1.5, 2.5), check.names = FALSE)",
    'vim_summary <- function(obj, wdth, word) writeLines(c(format(sum(obj)), word), '
      .. g:RString(summary_out) .. ')',
    substitute(sent_lines[1], '^.\{-}vimcom:::vim\.get\.summary', 'vim_summary', '')], work .. '/summary.R')
  var rjob = job_start(['Rscript', '--vanilla', work .. '/summary.R'], {out_io: 'null', err_io: 'null'})
  for _ in range(600)
    if job_status(rjob) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  g:AssertEqual(filereadable(summary_out) ? readfile(summary_out) : [], ['4', "d'f$it's"],
    'SetComplInfo: R takes the column of a data frame whose names hold a single quote')
  delete(work .. '/summary.R')
  delete(summary_out)
endif
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

# ========================================================================
# NeedRArguments: the data frame whose columns join the menu of arguments
# ========================================================================
# With the default R_fun_data_2, which names every function for "with", each
# call was taken for one nested in "with". A function of R_fun_data_1 then got
# no columns outside a call of "with", and the first object was read from the
# line above the call. Each case is buffer text with the cursor after its
# last character, and the result is the function, the kind of data frame (1
# for R_fun_data_1, 2 for R_fun_data_2), the first object, and whether that
# object is piped.
def g:RrTestDataSend(...args: list<any>): number
  return 1
enddef
var SavedDataSend = g:SendCmdToR
g:SendCmdToR = function('g:RrTestDataSend')
var saved_fun_data = [g:R_fun_data_1, g:R_fun_data_2]
def NeedArgs(lines: list<string>): list<any>
  deletebufline('%', 1, '$')
  setline(1, lines)
  cursor(len(lines), 1)
  return g:NeedRArguments(getline('.'), [0, len(lines), strlen(lines[-1]) + 1, 0])[0 : 3]
enddef
var data_cases = [
  [['filter(dat, '], ['filter', 1, 'dat', false], 'R_fun_data_1 on one line'],
  [['filter(dat,', '       '], ['filter', 1, 'dat', false], 'R_fun_data_1 across lines'],
  [['dat %>%', '  filter(', '    x > 1, '], ['filter', 1, 'dat', true],
    'R_fun_data_1 with the object piped on the line above the call'],
  [['with(dat, lm(y ~ '], ['lm', 2, 'dat', false], 'R_fun_data_2 with "*" on one line'],
  [['with(dat,', 'lm(y ~ '], ['lm', 2, 'dat', false], 'R_fun_data_2 with "*" across lines'],
  [['ggplot(dat, aes(x = '], ['aes', 2, 'dat', false], 'R_fun_data_2 with a name on one line'],
  [['ggplot2::ggplot(dat,', '  aes(x = '], ['aes', 2, 'dat', false],
    'R_fun_data_2 with a name across lines, the parent named with its package'],
  [['dat |> with(lm(y ~ '], ['lm', 2, 'dat', true], 'R_fun_data_2 with the object piped'],
  [['ggplot(dat, geom_point('], ['geom_point', 0, '', false], 'R_fun_data_2: a function not listed'],
  [['with(a, b); lm(dat, '], ['lm', 0, 'dat', false], 'R_fun_data_2: a call after "with" is not nested'],
  [['print(other)', 'summary(dat, '], ['summary', 0, 'dat', false],
    'no data frame: the first object is read from the line of the call'],
]
# Each option alone and both together
var option_cases = [
  [['summary'], {}, ['summary(dat, '], ['summary', 1, 'dat', false], 'R_fun_data_1 alone'],
  [['summary'], {}, ['with(dat, lm('], ['lm', 0, '', false], 'R_fun_data_1 alone: no "with"'],
  [[], {with: ['lm']}, ['with(dat, lm('], ['lm', 2, 'dat', false], 'R_fun_data_2 alone'],
  [[], {with: ['lm']}, ['with(dat,', '  glm('], ['glm', 0, '', false],
    'R_fun_data_2 alone: a function not listed'],
  [[], {with: ['lm']}, ['filter(dat, '], ['filter', 0, 'dat', false], 'R_fun_data_2 alone: no "filter"'],
  [['filter'], {with: ['*']}, ['with(dat, filter(d2, '], ['filter', 1, 'd2', false],
    'both: R_fun_data_1 comes first'],
  [['filter'], {with: ['*']}, ['with(dat,', '  lm('], ['lm', 2, 'dat', false], 'both: R_fun_data_2'],
]
var data_got: list<any> = []
err = Caught(() => {
  # The defaults of the two options
  g:R_fun_data_1 = ['select', 'rename', 'mutate', 'filter']
  g:R_fun_data_2 = {ggplot: ['aes'], with: ['*']}
  data_got = data_cases->mapnew((_, c) => NeedArgs(c[0]))
  for c in option_cases
    [g:R_fun_data_1, g:R_fun_data_2] = [c[0], c[1]]
    add(data_got, NeedArgs(c[2]))
  endfor
})
g:AssertEqual(err, '', 'NeedRArguments: no error for the data frames of the menu of arguments')
for i in range(len(data_cases))
  g:AssertEqual(get(data_got, i, 'no result'), data_cases[i][1], 'NeedRArguments: ' .. data_cases[i][2])
endfor
for i in range(len(option_cases))
  g:AssertEqual(get(data_got, len(data_cases) + i, 'no result'), option_cases[i][3],
    'NeedRArguments: ' .. option_cases[i][4])
endfor
# The first argument on the line below the call. RGetFirstObj() looked for
# it on the line of the call alone, and IsFirstRArg() looked at the line of
# the cursor alone, so it took the first argument for a later one.
var below_got: list<any> = []
err = Caught(() => {
  g:R_fun_data_1 = ['select', 'rename', 'mutate', 'filter']
  g:R_fun_data_2 = {ggplot: ['aes'], with: ['*']}
  add(below_got, NeedArgs(['filter(', '  dat, x > 1, ']))
  add(below_got, NeedArgs(['summary(', '', '  dat, ']))
  for lines in [['filter(', '  da'], ['filter(dat,', '  x'], ['filter(da']]
    deletebufline('%', 1, '$')
    setline(1, lines)
    add(below_got, g:IsFirstRArg(lines[-1], [0, len(lines), strlen(lines[-1]) + 1, 0]))
  endfor
})
g:AssertEqual([err, below_got], ['', [['filter', 1, 'dat', false], ['summary', 0, 'dat', false], 1, 0, 1]],
  'NeedRArguments and IsFirstRArg: the first argument on a line below the call')
[g:R_fun_data_1, g:R_fun_data_2] = saved_fun_data
g:SendCmdToR = SavedDataSend
delfunction g:RrTestDataSend
deletebufline('%', 1, '$')
setline(1, ['x <- 1'])
setlocal nomodified

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
