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
  # One command of vimcom starts with "call"
  var fn = matchstr(cmd, '^\%(call \)\=\zsg:\w\+')
  try
    execute substitute(cmd, '^\%(call \)\=g:\w\+', 'g:RrTestTake', '')
  catch
    return [fn, v:exception]
  endtry
  return [fn, g:rr_test_taken]
enddef
# The message with the arguments of a function that R builds, which the test
# of the server below sends to the server as well
var r_args_msg = ''
# The items of that message, in Vim
var args_items = [{word: "it's", menu: ' '}, {word: "a\x12b = ", menu: "\"x\x12y\""},
  {word: "c\x12l", menu: '[dq]', user_data: {word: "dq$c\x12l", env: '.GlobalEnv', cls: 'v', descr: ''}}]
# The messages of R for a function without arguments, and the items of the
# columns of the data frame that the second one adds
var r_noargs_msgs: list<string> = []
var noargs_columns = ["it's", 'b']->mapnew((_, n) => ({word: n, menu: "[d'f]",
  user_data: {word: "d'f$" .. n, env: '.GlobalEnv', cls: 'v', descr: ''}}))

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
  g:AssertEqual(len(cmds), 19, 'vimcom: every command is one line (' .. r_errors .. ')')
  cmds += repeat(['missing'], 19 - len(cmds))
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
  # The arguments of a function of the global environment, for completion
  g:AssertEqual(Taken(cmds[12]),
    ['g:FinishGlbEnvFunArgs', ['it''s "f"\', [['x'], ['y', '1']]]],
    'vimcom: the name of a function reaches FinishGlbEnvFunArgs() with its quotes and its backslash')
  # The arguments of a function and the columns of the data frame that is
  # its first argument go to the server as the items of a list. The server
  # hands the list to Vim as it is, which is done here in its place.
  var items_head = '+A7;;plainf;'
  var items: any = 'no list'
  try
    items = eval('[' .. strpart(cmds[13], len(items_head)) .. ']')
  catch
    items = v:exception
  endtry
  var column = {env: '.GlobalEnv', cls: 'v', descr: ''}
  g:AssertEqual([strpart(cmds[13], 0, len(items_head)), items], [items_head, [
    {word: 'a', menu: ' '},
    {word: 'b = ', menu: '2'},
    {word: "it's", menu: "[d'f]", user_data: extend({word: "d'f$it's"}, column)},
    {word: 'b', menu: "[d'f]", user_data: extend({word: "d'f$b"}, column)}]],
    'vimcom: the columns of a data frame reach Vim as a list, with the quotes of their names')
  # The summary of an object comes back with the word that it was asked for,
  # so that Vim can tell which item of the menu the answer belongs to
  var summary_taken = Taken(cmds[14])
  g:AssertEqual([summary_taken[0],
    type(summary_taken[1]) == v:t_list ? summary_taken[1][1 :] : summary_taken[1]],
    ['g:FinishGetSummary', ["d'f$it's"]], 'vimcom: the summary of an object names the word that it is for')
  # vimcom wrote the byte 0x12 for each quote of the items of the arguments,
  # and the server turned every such byte into a quote. A name or a value
  # that held the byte itself therefore ended its string, and so did a
  # column name that held it, which R had quoted for Vim already. Vim then
  # refused the whole menu.
  r_args_msg = cmds[15]
  var args_head = '+A8;;qf;'
  try
    items = eval('[' .. strpart(cmds[15], len(args_head)) .. ']')
  catch
    items = v:exception
  endtry
  g:AssertEqual([strpart(cmds[15], 0, len(args_head)), items], [args_head, args_items],
    'vimcom: names and values with a quote or the byte 0x12 reach Vim as the items of a list')
  # A function without arguments gave the item "[]", which the server put
  # into the list of the menu as it was. Vim then got a list in the place of
  # the first item (E1030), and with the columns of a data frame no list at
  # all (E696). The test of the server below sends these messages as well.
  r_noargs_msgs = cmds[16 : 17]
  var noargs_items: list<any> = []
  for [cmd, head] in [[cmds[16], '+A11;;nf;'], [cmds[17], '+A12;;nf;']]
    try
      add(noargs_items, [strpart(cmd, 0, len(head)), eval('[' .. strpart(cmd, len(head)) .. ']')])
    catch
      add(noargs_items, [strpart(cmd, 0, len(head)), v:exception])
    endtry
  endfor
  g:AssertEqual(noargs_items, [['+A11;;nf;', []], ['+A12;;nf;', noargs_columns]],
    'vimcom: a function without arguments gives no item, and the columns of a data frame stay a list')
  # The arguments of a function of the global environment reached
  # FinishGlbEnvFunArgs() as a string, with the byte 0x12 for each quote of
  # its items, which Vim turned into quotes before it evaluated the string. A
  # name with a quote ended its string, and so did a byte 0x12 in a name.
  # The command runs here as Vim runs it, with the function selected in the
  # menu.
  if !exists('*g:FinishGlbEnvFunArgs')
    execute 'source ' .. fnameescape(plugin_root .. '/R/complete.vim')
  endif
  var saved_compl = ['compl_event', 'compl_asked', 'compl_usage']->mapnew((_, k) => [k, g:rplugin[k]])
  g:rplugin.compl_event = {completed_item: {word: "g'q",
    user_data: {cls: 'f', pkg: '.GlobalEnv', descr: ''}},
    col: 1.0, row: 1.0, width: 10.0, height: 2.0, scrollbar: false}
  g:rplugin.compl_asked = "g'q"
  g:rplugin.compl_usage = ''
  err = Caught(() => {
    execute cmds[18]
  })
  g:AssertEqual([err, g:rplugin.compl_usage], ['', "g'q(it's, a\x12b = \"x\x12'y\", c = 1)"],
    'vimcom: names with a quote or the byte 0x12 reach the usage line of a global function')
  for [key, value] in saved_compl
    g:rplugin[key] = value
  endfor

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
# vimrserver: a name in R code for vimcom is an R string
# ========================================================================
# The server asks vimcom for the arguments of a function of the global
# environment, and it put the name between double quotes as it was, so a
# double quote or a backslash in the name gave R code that R refused. The
# server is not built for these tests, so its source is read. No format of
# the server may put a string between double quotes into a call of vimcom.
var server_source = readfile(plugin_root .. '/R/vimcom/src/apps/vimrserver.c')
g:AssertEqual(server_source->copy()->filter((_, l) => l =~ 'vimcom:::[^ ]*(\\"%s')
  ->mapnew((_, l) => trim(l)), [], 'vimrserver: no name goes raw into an R string for vimcom')
# vimcom does not look up the arguments of a function of the global
# environment when it lists the objects. It writes "not_checked" between two
# bytes 0x12 in their place, and the server asks R for the arguments when Vim
# wants the information on such a function. The server looked for the mark
# with the two bytes, which check_omils_buffer() has turned into single
# quotes by then. So it never asked, and the usage line of the completion
# read "f(not_checked)".
g:AssertEqual(server_source->copy()->filter((_, l) => l =~ 'str_here(f\[4\], ".*not_checked')
  ->mapnew((_, l) => matchstr(l, 'str_here(f\[4\], \zs".*not_checked[^"]*"')), ['"[''not_checked'']"'],
  'vimrserver: the mark of a function without arguments is compared as check_omils_buffer() leaves it')
# The request is sent while the state is locked for the lookup. A function
# that locks the state itself would wait for its own caller on Unix.
var info_first = match(server_source, '^void completion_info(')
var info_last = match(server_source, '^}', info_first)
g:AssertEqual(server_source[info_first : info_last]->filter((_, l) => l =~ '\<send_to_vimcom(')
  ->mapnew((_, l) => trim(l)), [], 'vimrserver: completion_info() sends under the lock of its caller')

# ========================================================================
# vimrserver: a name between single quotes holds the byte 0x13 for a quote
# ========================================================================
# The lists of objects hold the byte 0x13 in the place of each single quote
# of a name, and Vim turns it back. The word that Vim asked the server about
# was looked up with its quotes, so the server found nothing for it. The name
# of a library went into the menu with its quotes, which ended the string.
# Where a C compiler exists, the server is built and asked about such names,
# with the list of a package and a library of its own and without R.
# What the server wrote to Vim, one line for each command
var server_replies: list<string> = []
# Wait for a reply that matches a pattern, and return the replies that do
def ServerReplies(pat: string): list<string>
  for _ in range(100)
    if match(server_replies, pat) >= 0
      break
    endif
    sleep 50m
  endfor
  return server_replies->copy()->filter((_, r) => r =~ pat)
enddef
# The arguments that a command of the server passes to Vim, or the error that
# Vim raises for them
def ServerPassed(reply: string): any
  try
    return eval('[' .. matchstr(reply, '^\%(\%x11\d\+\%x11\)\=g:\w\+(\zs.*\ze)$') .. ']')
  catch
    return v:exception
  endtry
enddef
# Send a message to the server as vimcom does, with the secret, the size in
# nine digits, the message, and the byte 0x11
def SendAsVimcom(ch: channel, secret: string, msg: string)
  ch_sendraw(ch, secret .. printf('%09d', strlen(msg)) .. msg .. "\x11")
enddef
# Wait until a job has ended
def JobEnded(job: job, tenths: number)
  for _ in range(tenths)
    if job_status(job) !=# 'run'
      return
    endif
    sleep 100m
  endfor
enddef
if executable('gcc')
  var srv = work .. '/srv'
  mkdir(srv .. "/lib/it's", 'p')
  mkdir(srv .. '/compl', 'p')
  # On Unix the server refuses a temporary directory that others may use
  mkdir(srv .. '/tmp', 'p', 0o700)
  writefile(['Package: its', "Title: It's a title", "Description: It's a package."],
    srv .. "/lib/it's/DESCRIPTION")
  # Objects of the package, with their seven fields. vimcom writes the byte
  # 0x12 for each quote of the list of arguments of a function, and a name, a
  # class, or a title may hold that byte itself.
  writefile([["it's", '{', "my'cls", 'qpkg', '', 'A number', 'Text'],
    ["zq\x12x", '{', "c\x12l", 'qpkg', '', "T\x12t", 'Text'],
    ['zqf', "\x03", '', 'qpkg', "[\x12a\x12], [\x12b\x12, \x122\x12]", 'Title', 'Text']]
    ->mapnew((_, l) => l->join("\x06") .. "\x06"), srv .. '/compl/omnils_qpkg_1.0')
  writefile([], srv .. '/compl/fun_qpkg_1.0')
  writefile(['qpkg_1.0'], srv .. '/tmp/libnames_rrtest')
  writefile([srv .. '/lib'], srv .. '/tmp/libPaths')
  var exe = srv .. (has('win32') ? '/vimrserver.exe' : '/vimrserver')
  var src = plugin_root .. '/R/vimcom/src/apps/vimrserver.c'
  JobEnded(job_start(has('win32')
    ? ['gcc', '-mwindows', '-std=gnu99', '-DWIN32', src, '-o', exe, '-lWs2_32', '-lbcrypt']
    : ['gcc', '-pthread', '-std=gnu99', src, '-o', exe], {in_io: 'null', out_io: 'null', err_io: 'null'}), 1200)
  var sjob = job_start([exe], {in_mode: 'raw', err_io: 'null',
    out_cb: (_, msg) => add(server_replies, substitute(msg, '\r$', '', '')),
    env: {VIMR_ID: 'rrtest', VIMR_COMPLDIR: srv .. '/compl', VIMR_TMPDIR: srv .. '/tmp',
      VIMR_LOCAL_TMPDIR: srv .. '/tmp', VIMR_COMPLCB: 'g:SetComplMenu', VIMR_COMPLInfo: 'g:SetComplInfo',
      VIMR_RPATH: 'no_such_r'}})
  ServerReplies('nrs_running')
  # The completion of a word, the information on the word, and the
  # completion of the name of a library
  for request in ["51\x03it", "6it's\x02qpkg", "52\x03\x04it"]
    ch_sendraw(sjob, request .. "\n")
  endfor
  ServerReplies('SetComplMenu(2,')
  g:AssertEqual(ServerReplies('g:SetCompl')->mapnew((_, r) => ServerPassed(r)), [
    [1, [{word: "it\x13s", menu: "my\x13cls [qpkg]", user_data: {cls: '{', pkg: 'qpkg'}}]],
    [{cls: '{', word: "it\x13s", pkg: 'qpkg', usage: [], ttl: 'A number', descr: 'Text'}],
    [2, [{word: "it\x13s", menu: '[pkg]', user_data: {ttl: "It\x13s a title", descr: "It\x13s a package.",
      cls: 'l'}}]]], 'vimrserver: a name with a single quote reaches Vim in a list and a dictionary')
  # A word that the server does not find. The answer was an empty dictionary,
  # which did not tell Vim which item it was for.
  ch_sendraw(sjob, "6no'pe\x02qpkg\n")
  g:AssertEqual(ServerReplies('no\%x13pe')->mapnew((_, r) => ServerPassed(r)), [[{word: "no\x13pe"}]],
    'vimrserver: the answer of nothing found names the word')
  # The server wrote a single quote in the place of every byte 0x12, so a name
  # that held one ended its string, and Vim refused the whole list
  for request in ["53\x03zq", "6zq\x12x\x02qpkg", "6zqf\x02qpkg"]
    ch_sendraw(sjob, request .. "\n")
  endfor
  ServerReplies('SetComplInfo(.*zqf')
  g:AssertEqual([ServerReplies('SetComplMenu(3,'), ServerReplies('SetComplInfo(.*zq\%x12x'),
    ServerReplies('SetComplInfo(.*zqf')]
    ->mapnew((_, l) => l->mapnew((_, r) => ServerPassed(r))), [
    [[3, [{word: "zq\x12x", menu: "c\x12l [qpkg]", user_data: {cls: '{', pkg: 'qpkg'}},
      {word: 'zqf', menu: 'func [qpkg]', user_data: {cls: 'f', pkg: 'qpkg'}}]]],
    [[{cls: '{', word: "zq\x12x", pkg: 'qpkg', usage: [], ttl: "T\x12t", descr: 'Text'}]],
    [[{cls: 'f', word: 'zqf', pkg: 'qpkg', usage: [['a'], ['b', '2']], ttl: 'Title', descr: 'Text'}]]],
    'vimrserver: a byte 0x12 of a name, a class, or a title reaches Vim, and the arguments are a list')
  # The server sent no answer for a package that it did not know, for a
  # request that named no package, and for a function of the global
  # environment while R was not connected, so the window of the item that
  # was selected before stayed open. The test connects to the server as
  # vimcom does, lists a function of the global environment, and asks for it
  # once while connected and once after the connection has ended.
  for request in ["6it's\x02nopkg", '6zz']
    ch_sendraw(sjob, request .. "\n")
  endfor
  var unknown_answers = ['''it\%x13s''})$', '''zz''})$']
    ->mapnew((_, pat) => ServerReplies(pat)->mapnew((_, r) => ServerPassed(r)))
  var secret = matchstr(get(ServerReplies('VIMR_SECRET'), 0, ''), '''\zs[^'']*')
  ch_sendraw(sjob, "1\n")
  var port = matchstr(get(ServerReplies('RSetMyPort'), 0, ''), '\d\+')
  var from_server: list<string> = []
  var rch = ch_open('127.0.0.1:' .. port, {mode: 'raw', waittime: 5000,
    callback: (_, msg) => add(from_server, msg)})
  SendAsVimcom(rch, secret, "+Ggf\x06\x03\x06\x06.GlobalEnv\x06[\x12not_checked\x12]\x06\x06\x06\n")
  ServerReplies('UpdateLocalFunctions')
  ch_sendraw(sjob, "6gf\x02.GlobalEnv\n")
  for _ in range(100)
    if join(from_server, '') =~ 'fun\.args'
      break
    endif
    sleep 50m
  endfor
  var asked = matchstr(join(from_server, ''), 'vimcom:::.*)')
  # The server turned every byte 0x12 of the items of the arguments into a
  # quote, so a name or a value that held the byte ended its string, and Vim
  # refused the whole menu. The items are sent as Vim writes them, and as R
  # wrote them in the block above.
  SendAsVimcom(rch, secret, '+A9;;qf;' .. string(args_items)[1 : -2])
  var args_ids = [9]
  if r_args_msg != ''
    SendAsVimcom(rch, secret, r_args_msg)
    add(args_ids, 8)
  endif
  g:AssertEqual(args_ids->mapnew((_, id) => ServerReplies('SetComplMenu(' .. id .. ',')
    ->mapnew((_, r) => ServerPassed(r))), args_ids->mapnew((_, id) => [[id, args_items]]),
    'vimrserver: the items of the arguments reach Vim as vimcom wrote them, with the byte 0x12')
  # The menu of a function without arguments, as R wrote it in the block
  # above, is empty or holds the columns alone
  if len(r_noargs_msgs) == 2
    for msg in r_noargs_msgs
      SendAsVimcom(rch, secret, msg)
    endfor
    g:AssertEqual([11, 12]->mapnew((_, id) => ServerReplies('SetComplMenu(' .. id .. ',')
      ->mapnew((_, r) => ServerPassed(r))), [[[11, []]], [[12, noargs_columns]]],
      'vimrserver: the menu of a function without arguments is a list that Vim reads')
  endif
  ch_close(rch)
  ServerReplies('OnVimcomDisconnect')
  ch_sendraw(sjob, "6gf\x02.GlobalEnv\n")
  g:AssertEqual([unknown_answers, asked, ServerReplies('''gf''})$')->mapnew((_, r) => ServerPassed(r))],
    [[[[{word: "it\x13s"}]], [[{word: 'zz'}]]], 'vimcom:::vim.GlobalEnv.fun.args("gf")', [[{word: 'gf'}]]],
    'vimrserver: a word that cannot be looked up is answered with the word alone')
  ch_sendraw(sjob, "9\n")
  JobEnded(sjob, 30)
  job_stop(sjob, 'kill')
  JobEnded(sjob, 30)
  extend(made_files, ['srv/compl/omnils_qpkg_1.0', 'srv/compl/fun_qpkg_1.0', 'srv/compl/inst_libs',
    'srv/tmp/libnames_rrtest', 'srv/tmp/libPaths', 'srv/tmp/libs_in_nrs_rrtest', 'srv/tmp/bo_code.R',
    "srv/lib/it's/DESCRIPTION", 'srv/' .. fnamemodify(exe, ':t')])
  extend(made_dirs, ["srv/lib/it's", 'srv/lib', 'srv/compl', 'srv/tmp', 'srv'])
endif

# ========================================================================
# vimrserver: a message that lacks a part is read within its end
# ========================================================================
# The server stepped past the end of a message that lacked a separator. The
# menu of arguments without the separator before its items was read and
# written past the buffer of the message when the message filled it, and a
# request to open a list without its kind, or to close all lists without
# their state, updated the libraries. The number of elements of a list was
# read from its second digit on, so the second element of a list of twelve
# was drawn as the last one, and for an environment it was read past the end
# of the line. On Linux the server is built with the address sanitizer where
# gcc has it, so that a read past the buffer ends the server.
# A server that the sanitizer has ended takes nothing more, and the checks
# below then fail without an error
def ToRunning(job: job, msg: string)
  if job_status(job) ==# 'run'
    ch_sendraw(job, msg)
  endif
enddef
def ToVimcomIfOpen(ch: channel, secret: string, msg: string)
  if ch_status(ch) ==# 'open'
    SendAsVimcom(ch, secret, msg)
  endif
enddef
if executable('gcc')
  var srv2 = work .. '/srv2'
  mkdir(srv2 .. '/lib', 'p')
  mkdir(srv2 .. '/compl', 'p')
  mkdir(srv2 .. '/tmp', 'p', 0o700)
  writefile([], srv2 .. '/tmp/libnames_rrtest')
  writefile([srv2 .. '/lib'], srv2 .. '/tmp/libPaths')
  var exe2 = srv2 .. (has('win32') ? '/vimrserver.exe' : '/vimrserver')
  var src2 = plugin_root .. '/R/vimcom/src/apps/vimrserver.c'
  if !has('win32')
    JobEnded(job_start(['gcc', '-fsanitize=address', '-g', '-pthread', '-std=gnu99', src2, '-o', exe2],
      {in_io: 'null', out_io: 'null', err_io: 'null'}), 1200)
  endif
  if !executable(exe2)
    JobEnded(job_start(has('win32')
      ? ['gcc', '-mwindows', '-std=gnu99', '-DWIN32', src2, '-o', exe2, '-lWs2_32', '-lbcrypt']
      : ['gcc', '-pthread', '-std=gnu99', src2, '-o', exe2],
      {in_io: 'null', out_io: 'null', err_io: 'null'}), 1200)
  endif
  server_replies->filter((_, _) => false)
  var sjob2 = job_start([exe2], {in_mode: 'raw', err_io: 'null',
    out_cb: (_, msg) => add(server_replies, substitute(msg, '\r$', '', '')),
    env: {VIMR_ID: 'rrtest', VIMR_COMPLDIR: srv2 .. '/compl', VIMR_TMPDIR: srv2 .. '/tmp',
      VIMR_LOCAL_TMPDIR: srv2 .. '/tmp', VIMR_COMPLCB: 'g:SetComplMenu', VIMR_COMPLInfo: 'g:SetComplInfo',
      VIMR_RPATH: 'no_such_r', VIMR_OPENLS: '1', LC_MESSAGES: 'C', LC_ALL: 'C', LANG: 'C',
      ASAN_OPTIONS: 'detect_leaks=0'}})
  ServerReplies('nrs_running')
  var secret2 = matchstr(get(ServerReplies('VIMR_SECRET'), 0, ''), '''\zs[^'']*')
  ToRunning(sjob2, "1\n")
  var port2 = matchstr(get(ServerReplies('RSetMyPort'), 0, ''), '\d\+')
  var rch2 = ch_open('127.0.0.1:' .. port2, {mode: 'raw', waittime: 5000})
  # The first message of 1023 bytes fills the buffer of 1024 bytes
  ToVimcomIfOpen(rch2, secret2, '+A13;;' .. repeat('f', 1017))
  ServerReplies('SetComplMenu(13,')
  ToRunning(sjob2, "6zz\n")
  g:AssertEqual([ServerReplies('SetComplMenu(13,')->mapnew((_, r) => ServerPassed(r)),
    len(ServerReplies('''zz''})$'))], [[[13, []]], 1],
    'vimrserver: a menu of arguments without its items is answered, and the server goes on')
  for request in ['33', '34', '6zy']
    ToRunning(sjob2, request .. "\n")
  endfor
  ServerReplies('''zy''})$')
  g:AssertEqual([ServerReplies('UpdateOB'), len(ServerReplies('''zy''})$'))], [[], 1],
    'vimrserver: a request about the lists that lacks its last part changes nothing')
  # A list of twelve numbers and an environment, as vimcom writes them
  var zl_lines = ["zl\x06[\x06list\x06.GlobalEnv\x06\x06\x06 [12]\x06"]
    + range(1, 12)->mapnew((_, i) => 'zl$e' .. i .. "\x06{\x06\x06.GlobalEnv\x06\x06\x06\x06")
    + ["zenv\x06:\x06environment\x06.GlobalEnv\x06\x06\x06\x06"]
  ToVimcomIfOpen(rch2, secret2, '+G' .. zl_lines->join("\n") .. "\n")
  ServerReplies('UpdateLocalFunctions')
  ToRunning(sjob2, "31\n")
  ServerReplies("UpdateOB('GlobalEnv')")
  var ob_file = srv2 .. '/tmp/globenv_rrtest'
  var ob_lines = filereadable(ob_file) ? readfile(ob_file) : []
  g:AssertEqual(ob_lines->copy()->filter((_, l) => l =~ '#e\d')
    ->mapnew((_, l) => matchstr(l, '^ *\zs.\{-}\ze{')), repeat(['|- '], 11) + ['`- '],
    'vimrserver: only the twelfth element of a list of twelve is drawn as the last')
  g:Assert(match(ob_lines, '^   :#zenv\t$') >= 0, 'vimrserver: an environment is listed')
  if ch_status(rch2) ==# 'open'
    ch_close(rch2)
  endif
  ToRunning(sjob2, "9\n")
  JobEnded(sjob2, 30)
  job_stop(sjob2, 'kill')
  JobEnded(sjob2, 30)
  extend(made_files, ['srv2/compl/inst_libs', 'srv2/tmp/libnames_rrtest', 'srv2/tmp/libPaths',
    'srv2/tmp/libs_in_nrs_rrtest', 'srv2/tmp/bo_code.R', 'srv2/tmp/globenv_rrtest',
    'srv2/tmp/liblist_rrtest', 'srv2/' .. fnamemodify(exe2, ':t')])
  extend(made_dirs, ['srv2/lib', 'srv2/compl', 'srv2/tmp', 'srv2'])
endif

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
# knit() writes its output into the working directory, which RSetWD() has set
# to that of the file. The names had the modifiers of expand() in the wrong
# order, so they held the whole path of the file.
var html_end = '; system2("rst2html", shQuote(c("' .. odd_r .. '.rst", "' .. odd_r .. '.html")))'
  .. '; browseURL("' .. odd_r .. '.html")'
g:AssertEqual(strpart(html_sent, len(html_sent) - len(html_end)), html_end,
  'RMakeHTMLrrst: the converter and the browser get the names without a directory')
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
# ------------------------------------------------------------------------
# Text of the buffer and names from R are R strings as well
# ------------------------------------------------------------------------
# The word under the cursor, a selection, the first argument of a call, and
# a name that R sent were put between double quotes as they were. A selection
# such as d[d$g == "a", ] is ordinary, and its quotes ended the R string. The
# first argument had its double quotes escaped and its backslashes not.
# Most of this code goes to the server of vimcom. A program that copies its
# input into a file stands in for the server. It goes into a table of jobs of
# its own, which is declared for any value, since a table that a test has
# saved in a variable and put back takes strings only.
var names_log = work .. '/names_sent.txt'
var saved_jobs: dict<any> = g:rplugin.jobs
var names_jobs: dict<any> = g:rplugin.jobs->copy()
names_jobs['Server'] = job_start(has('win32') ? ['findstr', '^'] : ['cat'],
  {out_io: 'file', out_name: names_log, err_io: 'null'})
g:rplugin.jobs = names_jobs
var saved_names_opts = ['R_df_viewer', 'R_open_example', 'R_listmethods']
  ->mapnew((_, o) => [o, get(g:, o, v:none)])
unlet! g:R_df_viewer
g:R_open_example = 1
g:R_listmethods = 1
writefile(['summary(gsub("\\d", "", x), 1)', 'd[d$g == "a\b", ]'], work .. '/names.R')
execute 'edit ' .. fnameescape(work .. '/names.R')
var names_buf = bufnr('%')
# The whole second line is the selection, and the cursor is on the first line
setpos("'<", [0, 2, 1, 0])
setpos("'>", [0, 2, col([2, '$']) - 1, 0])
cursor(1, 1)

g:AssertEqual(g:RGetFirstObj('summary')[0], 'gsub("\\d", "", x)',
  'RGetFirstObj: the first argument is returned as the buffer holds it')
g:AssertEqual(Sent(() => {
  g:PrintRObject('summary')
}), 'vim.print("summary", "gsub(\"\\\\d\", \"\", x)")',
  'PrintRObject: the first argument is an R string')
g:AssertEqual(Sent(() => {
  g:RAction('args', 'v')
}), 'vim.list.args("d[d$g == \"a\\b\", ]")',
  'RAction: a selection is an R string for vim.list.args()')

# input() in ShowRDoc() takes the number of the library from the keys of :normal
err = Caught(() => {
  g:RAction('viewobj', 'v')
  g:RAction('dputtab', 'v')
  g:RAction('example', 'v')
  g:AskRDoc('summary', '', 1)
  g:AskRDoc('a"b', 'p\q', 0)
  g:AskRDoc('a"b', '', 0)
  g:GetRArgs(7, 'ba', 'summary', 0, g:RGetFirstObj('summary')[0], '', false)
  execute "normal :call g:ShowRDoc('MULTILIB to\"pic', 'lib1 li\\b2')\<CR>2\<CR>"
})
g:AssertEqual(err, '', 'R code for vimcom: no error for a name with a quote or a backslash')
ch_close_in(job_getchannel(g:rplugin.jobs['Server']))
for _ in range(100)
  if job_status(g:rplugin.jobs['Server']) !=# 'run'
    break
  endif
  sleep 50m
endfor
job_stop(g:rplugin.jobs['Server'], 'kill')
# The width of the help text depends on the window
var names_sent = (filereadable(names_log) ? readfile(names_log) : [])
  ->mapnew((_, l) => l->substitute('\r$', '', '')->substitute('", \d\+L', '", NL', ''))
var names_fenc = has('win32') && &encoding == 'utf-8' ? ', fenc="UTF-8"' : ''
var names_expected = [
  ['vim_viewobj("d[d$g == \"a\\b\", ]"' .. names_fenc .. ')',
    'RAction: a selection is an R string for vim_viewobj()'],
  ['vim_dput("d[d$g == \"a\\b\", ]")', 'RAction: a selection is an R string for vim_dput()'],
  ['vim.example("d[d$g == \"a\\b\", ]")', 'RAction: a selection is an R string for vim.example()'],
  ['vim.help("summary", NL, "gsub(\"\\\\d\", \"\", x)")', 'AskRDoc: the first argument is an R string'],
  ['vim.help("a\"b", NL, package="p\\q")', 'AskRDoc: the topic and the package are R strings'],
  ['vim.help("a\"b", NL)', 'AskRDoc: the topic is an R string'],
  ['vim_complete_args("7", "summary", "ba", firstobj = "gsub(\"\\\\d\", \"\", x)")',
    'GetRArgs: the first argument is an R string'],
  ['vim.help("to\"pic", NL, package="li\\b2")',
    'ShowRDoc: the topic and the library from R are R strings'],
]
for i in range(len(names_expected))
  g:AssertEqual(get(names_sent, i, 'nothing sent'),
    '2E' .. $VIMR_ID .. 'vimcom:::' .. names_expected[i][0], names_expected[i][1])
endfor

g:rplugin.jobs = saved_jobs
for [name, value] in saved_names_opts
  if type(value) != v:t_none
    extend(g:, {[name]: value})
  elseif has_key(g:, name)
    remove(g:, name)
  endif
endfor
execute 'buffer ' .. rbuf
execute 'bwipeout! ' .. names_buf
extend(made_files, ['names.R', 'names_sent.txt'])

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

# ========================================================================
# ValidateTmpdir: a slash at the end of the name is no symlink
# ========================================================================
# The temporary directory of R_tmpdir goes through expand(), which on Unix
# puts a slash at the end of a name that holds a single quote. The directory
# was then compared with its resolved name, which has no such slash, and was
# refused as a symlink.
var saved_msgs = get(g:rplugin, 'start_msg', v:none)
mkdir(work .. "/it's v", 'p', 0o700)
add(made_dirs, "it's v")
g:Assert(g:ValidateTmpdir(substitute(expand(work .. "/it's v"), '\\', '/', 'g')),
  'ValidateTmpdir: a directory with a single quote in its name is accepted')
if has('unix') && !has('win32unix')
  system('ln -s ' .. shellescape(work .. "/it's v") .. ' ' .. shellescape(work .. '/vlink'))
  g:Assert(!g:ValidateTmpdir(work .. '/vlink/'),
    'ValidateTmpdir: a symlink is refused, with a slash at its end too')
  delete(work .. '/vlink')
endif
if type(saved_msgs) != v:t_none
  g:rplugin.start_msg = saved_msgs
elseif has_key(g:rplugin, 'start_msg')
  remove(g:rplugin, 'start_msg')
endif

# ========================================================================
# RLoadHTML: on Windows cmd.exe reads the command that opens the file
# ========================================================================
# The command was a list, which Vim joins with quotes only around an argument
# that holds a space. A path with an ampersand and no space reached cmd.exe
# bare, so cmd.exe cut it at the ampersand and ran the rest as a command.
# Between double quotes cmd.exe still put the value of a variable in the place
# of its name between percent signs. The path now reaches cmd.exe in the
# environment of the job, and the line holds only the name of that variable.
# Nothing is opened here. The line is given to cmd.exe with echo in the place
# of start, which shows what cmd.exe makes of it.
g:AssertEqual(g:RHtmlCommand('a&b.html', 'my browser'), [['my', 'browser', 'a&b.html'], {}],
  'RLoadHTML: a browser gets the path as one argument')
if has('win32')
  # OS is a variable that every Windows defines
  var html = work .. '/100%OS%^a&b!c.html'
  var open_cmd: any = g:RHtmlCommand(html, '')
  var open_line = type(open_cmd) == v:t_list && type(open_cmd[0]) == v:t_string ? open_cmd[0] : ''
  var echo_cmd = substitute(open_line, '^cmd /v:on /c start "" ', 'cmd /v:on /c echo ', '')
  g:Assert(echo_cmd =~# '^cmd /v:on /c echo ',
    'RLoadHTML: the command for Windows is a line for cmd.exe with delayed expansion')
  if echo_cmd =~# '^cmd /v:on /c echo '
    var echoed: list<string> = []
    var ejob = job_start(echo_cmd, extend({in_io: 'null', err_io: 'out', out_cb: (_, msg) => {
      add(echoed, substitute(msg, '\r$', '', ''))
    }}, open_cmd[1]))
    for _ in range(100)
      if job_status(ejob) !=# 'run'
        break
      endif
      sleep 50m
    endfor
    sleep 100m
    g:AssertEqual(echoed, ['"' .. html .. '"'],
      'RLoadHTML: cmd.exe takes a path with the name of a variable and an ampersand as it is')
  endif
else
  g:AssertEqual(g:RHtmlCommand('a&b.html', ''), [['xdg-open', 'a&b.html'], {}],
    'RLoadHTML: xdg-open gets the path as one argument')
endif

# ========================================================================
# Ex commands: a bracket in a file name is no wildcard
# ========================================================================
# On Windows fnameescape() leaves a bracket alone, so :tabnew and :split
# opened "a1.tex" for "a[1].tex" when both files existed.
writefile(['\documentclass{article}', '\begin{document}', 'x', '\end{document}'], work .. '/main.Rnw')
add(made_files, 'main.Rnw')
for ext in ['tex', 'Rout', 'tsv']
  writefile(['plain'], work .. '/a1.' .. ext)
  extend(made_files, ['a1.' .. ext, 'a[1].' .. ext])
endfor
writefile(['bracket'], work .. '/a[1].tex')
writefile(['bracket'], work .. '/a[1].Rout')
execute 'edit ' .. fnameescape(work .. '/main.Rnw')
err = Caught(() => {
  g:GoToBuf('a[1].tex', 'a[1].tex', work, 1)
})
g:AssertEqual([err, expand('%:t'), getline(1)], ['', 'a[1].tex', 'bracket'],
  'GoToBuf: opens "a[1].tex" and not "a1.tex" beside it')
silent! tabonly
execute 'buffer ' .. rbuf

var saved_routnotab = g:R_routnotab
for notab in [0, 1]
  g:R_routnotab = notab
  err = Caught(() => {
    g:GetRCmdBatchOutput(work .. '/a[1].Rout')
  })
  g:AssertEqual([err, bufloaded(work .. '/a[1].Rout'), bufloaded(work .. '/a1.Rout')], ['', 1, 0],
    'GetRCmdBatchOutput: opens "a[1].Rout" and not "a1.Rout" beside it, R_routnotab = ' .. notab)
  silent! tabonly
  silent! only
  execute 'buffer ' .. rbuf
endfor
g:R_routnotab = saved_routnotab

# RViewDF() appends the name of its file to the Ex command of R_csv_app
var saved_tmpdir = g:rplugin.tmpdir
var saved_csv_app = get(g:, 'R_csv_app', v:none)
g:rplugin.tmpdir = work
g:R_csv_app = ':split'
err = Caught(() => {
  g:RViewDF('a[1]', '', "bracket\x141")
})
g:AssertEqual([err, expand('%:t'), getline(1)], ['', 'a[1].tsv', 'bracket'],
  'RViewDF: an Ex command opens "a[1].tsv" and not "a1.tsv" beside it')
silent! only
execute 'buffer ' .. rbuf
# On Windows fnameescape() leaves "$" alone, and Vim replaced "$HOME" in the
# name with the value of that variable. The name also holds braces, which a
# command that takes the name for a wildcard reads as a set of alternatives.
err = Caught(() => {
  g:RViewDF('v$HOME {1}', '', "dollar\x141")
})
g:AssertEqual([err, expand('%:t'), getline(1)], ['', 'v$HOME {1}.tsv', 'dollar'],
  'RViewDF: an Ex command opens "v$HOME {1}.tsv"')
extend(made_files, ['v$HOME {1}.tsv'])
silent! only
execute 'buffer ' .. rbuf
# The file was named after the R code as it was, so on Windows a character
# such as ">", "|", or ":" made writefile() fail, and on both systems a slash
# pointed into a directory that does not exist. A name that Windows keeps
# for a device and a name that is too long for a file are covered as well.
var tsv_cases = [["d[d$x >\t1, \"a|b\"] / 2 * ? : <y>", "d[d$x __1, _a_b_] _ 2 _ _ _ _y_.tsv"],
  ['aux', '_aux.tsv'], ['Com1.x', '_Com1.x.tsv'], [repeat('n', 150), repeat('n', 100) .. '.tsv']]
var tsv_shown: list<any> = []
for [expr, tsv] in tsv_cases
  err = Caught(() => {
    g:RViewDF(expr, '', "x\tn\x14a\t1")
  })
  add(tsv_shown, [err, expand('%:t'), getline(1, '$')])
  silent! only
  execute 'buffer ' .. rbuf
  add(made_files, tsv)
endfor
g:AssertEqual(tsv_shown, tsv_cases->mapnew((_, c) => ['', c[1], ["x\tn", "a\t1"]]),
  'RViewDF: the file of an expression with characters that a file name cannot hold is written and opened')

g:rplugin.tmpdir = saved_tmpdir
if type(saved_csv_app) == v:t_none
  unlet g:R_csv_app
else
  g:R_csv_app = saved_csv_app
endif

# Without R_csv_app, RViewDF() opened a buffer with the Ex command of howto
# and the name of the object as it was. A selection such as d[d$x > 1, ] made
# Vim refuse the command (E172), and a percent sign, a number sign, or a bar
# was read as the current file, the alternate file, or the end of the
# command. The buffer holds no file, and it goes when its window closes.
var df_names = ['d[d$x > 1, ]', 'a%b #1', 'p|q', 'v$HOME']
var df_shown: list<any> = []
for [df_name, df_howto] in df_names->mapnew((i, n) => [n, i % 2 == 0 ? 'tabnew' : 'above 7split'])
  var nbufs = len(getbufinfo())
  err = Caught(() => {
    g:RViewDF(df_name, df_howto, "x\tn\x14a\t1")
  })
  add(df_shown, [err, bufname('%'), getline(1, '$'), &buftype, &swapfile, df_howto == 'tabnew'
    ? tabpagenr('$') : winheight(0)])
  # The window of the data frame is closed, where the call opened one
  if tabpagenr('$') > 1
    tabclose
  elseif winnr('$') > 1
    close
  endif
  add(df_shown[-1], len(getbufinfo()) - nbufs)
endfor
g:AssertEqual(df_shown, df_names->mapnew((i, n) => ['', n, ["x\tn", "a\t1"], 'nofile', false, i % 2 == 0 ? 2 : 7,
  0]), 'RViewDF: the buffer of a data frame has the name of the object, whatever it holds')
execute 'buffer ' .. rbuf
# A window that still shows the table of an object keeps its buffer, and a
# second view of the object reused it. setline() replaced the first lines
# only, so the lines of a longer table stayed below a shorter one.
var df_nbufs = len(getbufinfo())
var df_views: list<any> = []
for rows in [["x\tn", "a\t1", "b\t2", "c\t3"], ["x\tn", "z\t9"]]
  err = Caught(() => {
    g:RViewDF('d[1:2, ]', 'tabnew', join(rows, "\x14"))
  })
  add(df_views, [err, bufnr('%'), getline(1, '$'), &buftype, &swapfile, &bufhidden, &filetype, &modified])
endfor
var df_twice = [df_views[0][1] == df_views[1][1], tabpagebuflist(2) == [df_views[0][1]]]
silent! tabonly
execute 'buffer ' .. rbuf
g:AssertEqual([df_views->mapnew((_, v) => v[0 : 0] + v[2 :]), df_twice, len(getbufinfo()) - df_nbufs],
  [[['', ["x\tn", "a\t1", "b\t2", "c\t3"], 'nofile', false, 'wipe', 'csv', false],
    ['', ["x\tn", "z\t9"], 'nofile', false, 'wipe', 'csv', false]], [true, true], 0],
  'RViewDF: a shorter table replaces all lines of the buffer that a window still shows')

# ========================================================================
# SyncTeX_forward: the directory of the master file is no wildcard
# ========================================================================
# A child document names its master file, which may lie in another
# directory. SyncTeX_forward() changed into that directory with ":cd" and
# fnameescape(), which on Windows leaves a bracket alone, so ":cd r[1]" went
# into "r1" when that directory existed, and the TeX file of "r1" was opened.
# ":cd" and chdir() also replace "$HOME" in a directory name with its value.
# The search from the child to the TeX file of its master runs for a master in
# "r[1]", beside "r1", and in "r$HOME".
var sync_cwd = getcwd()
chdir(work)
var sync_opened: list<any> = []
mkdir(work .. '/r1', 'p')
writefile(['twin'], work .. '/r1/main.tex')
extend(made_files, ['r1/main.tex'])
add(made_dirs, 'r1')
for mdir in ['r[1]', 'r$HOME']
  mkdir(work .. '/' .. mdir, 'p')
  writefile(['\documentclass{article}', "<<child='kid.Rnw'>>=", '@'], work .. '/' .. mdir .. '/main.Rnw')
  writefile(['line 1', 'line 2', 'line 3', 'line 4'], work .. '/' .. mdir .. '/main.tex')
  writefile(['\Sconcordance{concordance:main.tex:main.Rnw:%', '1 3 1}'],
    work .. '/' .. mdir .. '/main-concordance.tex')
  writefile(['% !Rnw root = ' .. mdir .. '/main.Rnw', 'text'], work .. '/kid.Rnw')
  execute 'edit ' .. fnameescape(work .. '/kid.Rnw')
  var kid_buf = bufnr('%')
  err = Caught(() => {
    g:SyncTeX_forward(1)
  })
  add(sync_opened, [err, substitute(expand('%:p'), '\\', '/', 'g'), line('.'),
    substitute(getcwd(), '\\', '/', 'g')])
  silent! tabonly
  execute 'buffer ' .. rbuf
  execute 'bwipeout! ' .. kid_buf
  if bufexists(work .. '/' .. mdir .. '/main.tex')
    execute 'bwipeout! ' .. bufnr(work .. '/' .. mdir .. '/main.tex')
  endif
  extend(made_files, ['main.Rnw', 'main.tex', 'main-concordance.tex']->mapnew((_, f) => mdir .. '/' .. f))
  add(made_dirs, mdir)
endfor
add(made_files, 'kid.Rnw')
chdir(sync_cwd)
g:AssertEqual(sync_opened, ['r[1]', 'r$HOME']->mapnew((_, d) => ['', work .. '/' .. d .. '/main.tex', 2,
  substitute(work, '\\', '/', 'g')]), 'SyncTeX_forward: opens the TeX file of a master in "r[1]" and in "r$HOME"')

# A relative root is taken in the directory of the child that names it.
# SyncTeX_GetMaster() returned such a root as it was written, unless it was
# "../" and a name, and SetPDFdir() made the PDF directory of it. Taken in
# the working directory, the root named another file, and SyncTeX_forward()
# put the directory of the master in front of the PDF directory a second
# time, which gave "sub/sub". The working directory is not that of any
# child here. The PDF exists and its SyncTeX file does not, so the forward
# search stops with a warning that names the file that it looked for. The
# LaTeX command is set, so that no .latexmkrc of the home directory counts.
chdir(work)
var saved_latexcmd = g:R_latexcmd
g:R_latexcmd = ['pdflatex', '-synctex=1']
var root_cases = [['A', 's[1]/main.Rnw', 'A/s[1]'], ['B/k$HOME', '../main.Rnw', 'B'],
  ['C/k[2]', '../m$HOME/main.Rnw', 'C/m$HOME']]
var root_found: list<any> = []
for [kdir, root, rdir] in root_cases
  mkdir(work .. '/' .. kdir, 'p')
  mkdir(work .. '/' .. rdir, 'p')
  writefile(['\documentclass{article}', "<<child='kid.Rnw'>>=", '@'], work .. '/' .. rdir .. '/main.Rnw')
  writefile(['line 1', 'line 2', 'line 3', 'line 4'], work .. '/' .. rdir .. '/main.tex')
  writefile(['\Sconcordance{concordance:main.tex:main.Rnw:%', '1 3 1}'],
    work .. '/' .. rdir .. '/main-concordance.tex')
  writefile(['pdf'], work .. '/' .. rdir .. '/main.pdf')
  writefile(['% !Rnw root = ' .. root, 'text'], work .. '/' .. kdir .. '/kid.Rnw')
  # On Windows :edit would replace "$HOME" in the name
  var kid_buf = bufadd(work .. '/' .. kdir .. '/kid.Rnw')
  execute 'buffer ' .. kid_buf
  var found: list<any> = []
  g:rplugin.start_msg = []
  err = Caught(() => {
    add(found, g:SyncTeX_GetMaster())
    g:SetPDFdir()
    add(found, b:rplugin_pdfdir)
    g:SyncTeX_forward()
    g:SyncTeX_forward(1)
  })
  add(root_found, [err] + found + [g:rplugin.start_msg, substitute(expand('%:p'), '\\', '/', 'g'), line('.')])
  silent! tabonly
  execute 'buffer ' .. rbuf
  execute 'bwipeout! ' .. kid_buf
  if bufexists(work .. '/' .. rdir .. '/main.tex')
    execute 'bwipeout! ' .. bufnr(work .. '/' .. rdir .. '/main.tex')
  endif
  extend(made_files, [rdir .. '/main.Rnw', rdir .. '/main.tex', rdir .. '/main-concordance.tex',
    rdir .. '/main.pdf', kdir .. '/kid.Rnw'])
endfor
extend(made_dirs, ['A/s[1]', 'A', 'B/k$HOME', 'B', 'C/k[2]', 'C/m$HOME', 'C'])
chdir(sync_cwd)
g:R_latexcmd = saved_latexcmd
g:rplugin.start_msg = []
g:AssertEqual(root_found, root_cases->mapnew((_, c) => ['', work .. '/' .. c[2] .. '/main', work .. '/' .. c[2],
  ['SyncTeX forward cannot be done because the file "' .. work .. '/' .. c[2] .. '/main.synctex.gz" is missing.'],
  work .. '/' .. c[2] .. '/main.tex', 2]),
  'SyncTeX: the root, the PDF directory, and the TeX file of a child or of a root in another directory')

# The name of the root kept the spaces that end its line, and a carriage
# return, which a line of a file with mixed line endings holds in Vim. A
# space inside the name stays.
chdir(work)
g:R_latexcmd = ['pdflatex', '-synctex=1']
var trail_cases = [['D', 'm n/main.Rnw   ', 'D/m n'], ['E', "main.Rnw\r", 'E'],
  ['F', "m n/main.Rnw \t\r", 'F/m n']]
var trail_found: list<any> = []
for [kdir, root, rdir] in trail_cases
  mkdir(work .. '/' .. rdir, 'p')
  writefile(['\documentclass{article}', "<<child='kid.Rnw'>>=", '@'], work .. '/' .. rdir .. '/main.Rnw')
  writefile(['line 1', 'line 2', 'line 3', 'line 4'], work .. '/' .. rdir .. '/main.tex')
  writefile(['\Sconcordance{concordance:main.tex:main.Rnw:%', '1 3 1}'],
    work .. '/' .. rdir .. '/main-concordance.tex')
  writefile(['pdf'], work .. '/' .. rdir .. '/main.pdf')
  writefile(['% !Rnw root = ' .. root, 'text'], work .. '/' .. kdir .. '/kid.Rnw')
  var kid_buf = bufadd(work .. '/' .. kdir .. '/kid.Rnw')
  execute 'buffer ' .. kid_buf
  var found: list<any> = [getline(1) =~ "\r$" || root !~ "\r"]
  g:rplugin.start_msg = []
  err = Caught(() => {
    add(found, g:SyncTeX_GetMaster())
    g:SetPDFdir()
    add(found, b:rplugin_pdfdir)
    g:SyncTeX_forward()
    g:SyncTeX_forward(1)
  })
  add(trail_found, [err] + found
    + [g:rplugin.start_msg, substitute(expand('%:p'), '\\', '/', 'g'), line('.')])
  silent! tabonly
  execute 'buffer ' .. rbuf
  execute 'bwipeout! ' .. kid_buf
  if bufexists(work .. '/' .. rdir .. '/main.tex')
    execute 'bwipeout! ' .. bufadd(work .. '/' .. rdir .. '/main.tex')
  endif
  extend(made_files, [rdir .. '/main.Rnw', rdir .. '/main.tex', rdir .. '/main-concordance.tex',
    rdir .. '/main.pdf', kdir .. '/kid.Rnw'])
endfor
extend(made_dirs, ['D/m n', 'D', 'E', 'F/m n', 'F'])
chdir(sync_cwd)
g:R_latexcmd = saved_latexcmd
g:rplugin.start_msg = []
g:AssertEqual(trail_found, trail_cases->mapnew((_, c) => ['', true, work .. '/' .. c[2] .. '/main',
  work .. '/' .. c[2], ['SyncTeX forward cannot be done because the file "' .. work .. '/' .. c[2]
    .. '/main.synctex.gz" is missing.'],
  work .. '/' .. c[2] .. '/main.tex', 2]),
  'SyncTeX: the name of the root ends before the spaces and the carriage return that end its line')

# The name of a child is matched as it is. SyncTeX_forward() looked for the
# line of the master that includes the child, and for the lines of the
# concordance that belong to a file, with the names as patterns, and
# GoToBuf() took the buffer of the TeX file from bufnr(), which takes a name
# for a pattern as well. A bracket then matched another file, a tilde raised
# E33 or matched the text of the last substitution, and a name matched
# within a longer one. Each master below names a decoy first, which the
# pattern form matches, and the buffer of a decoy TeX file is loaded beside
# the real one. The knitr master names its child, and the Sweave master
# includes its children, which the concordance names, one of them with a
# directory.
var odd_kid = has('win32') ? 'k~1.Rnw' : 'k*~\1.Rnw'
var kid_cases = [
  ['kx', 'm[1]', ['\documentclass{article}', "<<child='kid1.Rnw'>>=", '@', "<<child='kid[1].Rnw'>>=", '@'],
    'kid[1].Rnw', [['m[1].Rnw', 6]], 1, 4],
  ['sx', 'main', ['\documentclass{article}', '\SweaveInput{kid1.Rnw}', '\SweaveInput{kid[1].Rnw}'],
    'kid[1].Rnw', [['main.Rnw', 3], ['kid1.Rnw', 3], ['./kid[1].Rnw', 3]], 2, 8],
  ['ox', 'main', ['\documentclass{article}', '% text', '% text', "<<child='" .. odd_kid .. "'>>=", '@'],
    odd_kid, [['main.Rnw', 6]], 1, 4],
  ['dx', 'main', ['\documentclass{article}', "<<child='xkid.Rnw'>>=", '@', "<<child='./kid.Rnw'>>=", '@'],
    'kid.Rnw', [['main.Rnw', 6]], 1, 4]]
# Run the forward search from a child to the TeX file of its master, in a
# tree that holds the master, its TeX file and concordance, a decoy TeX file,
# and the child, and return the error, the file, and the line that it went to
def KidFound(kdir: string, master: string, mlines: list<string>, kname: string,
    blocks: list<any>, kline: number): list<any>
  var dir = work .. '/' .. kdir
  mkdir(dir, 'p')
  writefile(mlines, dir .. '/' .. master .. '.Rnw')
  var ntex = blocks->mapnew((_, b) => b[1])->reduce((a, b) => a + b, 0)
  writefile(range(1, ntex)->mapnew((_, n) => 'line ' .. n), dir .. '/' .. master .. '.tex')
  writefile(blocks->mapnew((_, b) => ['\Sconcordance{concordance:' .. master .. '.tex:' .. b[0] .. ':%',
    '1 ' .. (b[1] - 1) .. ' 1}'])->flattennew(), dir .. '/' .. master .. '-concordance.tex')
  writefile(['decoy'], dir .. '/m1.tex')
  writefile(['% !Rnw root = ' .. master .. '.Rnw', 'line 2', 'line 3'], dir .. '/' .. kname)
  var tex_bufs = [master .. '.tex', 'm1.tex']->mapnew((_, t) => bufadd(dir .. '/' .. t))
  for tb in tex_bufs
    bufload(tb)
  endfor
  var kid_buf = bufadd(dir .. '/' .. kname)
  execute 'buffer ' .. kid_buf
  cursor(kline, 1)
  var kerr = Caught(() => {
    g:SyncTeX_forward(1)
  })
  var found = [kerr, substitute(expand('%:p'), '\\', '/', 'g'), line('.')]
  silent! only
  execute 'buffer ' .. rbuf
  for tb in tex_bufs + [kid_buf]
    execute 'bwipeout! ' .. tb
  endfor
  extend(made_files, [master .. '.Rnw', master .. '.tex', master .. '-concordance.tex', 'm1.tex', kname]
    ->mapnew((_, f) => kdir .. '/' .. f))
  add(made_dirs, kdir)
  return found
enddef
var kid_found = kid_cases->mapnew((_, c) => KidFound(c[0], c[1], c[2], c[3], c[4], c[5]))
g:AssertEqual(kid_found,
  kid_cases->mapnew((_, c) => ['', work .. '/' .. c[0] .. '/' .. c[1] .. '.tex', c[6]]),
  'SyncTeX_forward: a child named "kid[1].Rnw" or "' .. odd_kid .. '" is found, and no decoy is taken')

# ========================================================================
# Ex commands: names from R and the temporary directory are taken as they are
# ========================================================================
# GetROutput(), EditRObject(), ShowRObj(), and ShowRDoc() put a name into an
# Ex command with nothing or only its spaces escaped. A percent sign in the
# name was replaced with the name of the current file. On Windows
# fnameescape() leaves a bracket alone, and ShowRObj() then opened a file of
# another directory that the name matches as a wildcard, which a directory
# beside the temporary one provides. ShowRObj() then gave the command "#" and
# the number of the buffer, and Vim replaced "$HOME" in the name that it put
# in its place with the value of that variable.
var saved_env = [$VIMR_TMPDIR, $VIMR_ID]
saved_tmpdir = g:rplugin.tmpdir
var tdir = 't%d #1 [1] $HOME'
mkdir(work .. '/' .. tdir, 'p')
mkdir(work .. '/t%d #1 1 $HOME', 'p')
writefile(['other'], work .. '/t%d #1 1 $HOME/x')
extend(made_files, ['t%d #1 1 $HOME/x'])
extend(made_dirs, [tdir, 't%d #1 1 $HOME'])
g:rplugin.tmpdir = work .. '/' .. tdir
$VIMR_TMPDIR = work .. '/' .. tdir
$VIMR_ID = '7'

err = Caught(() => {
  g:GetROutput('out%1 #2 $HOME', "a\x14b")
})
g:AssertEqual([err, bufexists('out%1 #2 $HOME') ? getbufline('out%1 #2 $HOME', 1, '$') : []], ['', ['a', 'b']],
  'GetROutput: the buffer has the name that R gave')
if bufexists('out%1 #2 $HOME')
  execute 'bwipeout! ' .. bufnr('out%1 #2 $HOME')
endif
silent! tabonly!

writefile(['c(1, 2)'], work .. '/' .. tdir .. '/vimcom_edit_1')
extend(made_files, [tdir .. '/vimcom_edit_1'])
err = Caught(() => {
  g:EditRObject(work .. '/' .. tdir .. '/vimcom_edit_1')
})
g:AssertEqual([err, substitute(expand('%:p'), '\\', '/', 'g'), getline(1)],
  ['', work .. '/' .. tdir .. '/edit_7', 'c(1, 2)'],
  'EditRObject: the buffer lies in a temporary directory "' .. tdir .. '"')
if bufnr('%') != rbuf
  autocmd! BufUnload <buffer>
  bwipeout!
endif
silent! tabonly

err = Caught(() => {
  g:ShowRObj('tabnew', 'x', 'r', "c(1,\x142)")
})
g:AssertEqual([err, substitute(expand('%:p'), '\\', '/', 'g'), getline(1, '$')],
  ['', work .. '/' .. tdir .. '/x', ['c(1,', '2)']],
  'ShowRObj: the buffer lies in a temporary directory "' .. tdir .. '"')
if bufnr('%') != rbuf
  bwipeout!
endif
silent! tabonly
# The map for the head of an object asks for "above 7split", and Vim9 script
# refused the count without a colon
err = Caught(() => {
  g:ShowRObj('above 7split', 'x', 'r', "c(1,\x142)")
})
g:AssertEqual([err, substitute(expand('%:p'), '\\', '/', 'g'), winheight(0)], ['', work .. '/' .. tdir .. '/x', 7],
  'ShowRObj: a count in the command gives the height of the window')
if bufnr('%') != rbuf
  bwipeout!
endif
silent! only

# OpenRExample() opens the file of the example in that directory, and unloads
# its buffer first when an example is still shown
var saved_example_pager = g:R_vimpager
var example_shown: list<any> = []
for pager in ['tabnew', 'horizontal']
  g:R_vimpager = pager
  writefile([pager], work .. '/' .. tdir .. '/example.R')
  err = Caught(() => {
    g:OpenRExample()
  })
  add(example_shown, [err, substitute(expand('%:p'), '\\', '/', 'g'), getline(1)])
  # Back to the window of the R script, with the example still open
  win_gotoid(bufwinid(rbuf) > 0 ? bufwinid(rbuf) : win_findbuf(rbuf)->get(0, 0))
endfor
g:AssertEqual(example_shown, ['tabnew', 'horizontal']
  ->mapnew((_, p) => ['', work .. '/' .. tdir .. '/example.R', p]),
  'OpenRExample: the buffer lies in a temporary directory "' .. tdir .. '"')
g:R_vimpager = saved_example_pager
if bufexists(work .. '/' .. tdir .. '/example.R')
  execute 'bwipeout! ' .. bufnr(work .. '/' .. tdir .. '/example.R')
endif
silent! tabonly
silent! only
add(made_files, tdir .. '/example.R')
g:rplugin.tmpdir = saved_tmpdir
$VIMR_TMPDIR = saved_env[0]
$VIMR_ID = saved_env[1]

# With R_vimpager = "tabnew" the title that R gives is the name of the buffer
var saved_vimpager = g:R_vimpager
g:R_vimpager = 'tabnew'
execute 'buffer ' .. rbuf
err = Caught(() => {
  g:ShowRDoc('x%y #1 (help)', "first\x14text")
})
var doc_buf = bufnr('x%y #1 (help)')
g:AssertEqual([err, bufname('%'), getline(1)], ['', 'x%y #1 (help)', 'first'],
  'ShowRDoc: the buffer has the title that R gave')
tabfirst
err = Caught(() => {
  g:ShowRDoc('x%y #1 (help)', "second\x14text")
})
g:AssertEqual([err, bufnr('%') == doc_buf, getline(1)], ['', true, 'second'],
  'ShowRDoc: the buffer of a title is found again')
g:R_vimpager = saved_vimpager
silent! tabonly
if doc_buf > 0
  execute 'bwipeout! ' .. doc_buf
endif
execute 'buffer ' .. rbuf

# ========================================================================
# SourceRFunList: the cache directory is taken as it is
# ========================================================================
# The names of the functions of a package, for their highlighting, lie in a
# file of the cache directory, which SourceRFunList() gave to :source. Vim
# replaces "$HOME" in every name that :source receives with the value of that
# variable, so nothing was highlighted for a cache directory that holds it.
if !exists('*g:SourceRFunList')
  execute 'source ' .. fnameescape(plugin_root .. '/R/functions_def.vim')
endif
var saved_compldir = g:rplugin.compldir
var saved_hi_opts = ['R_hi_fun', 'R_hi_fun_paren']->mapnew((_, o) => [o, get(g:, o, v:none)])
var cdir = 'c$HOME'
mkdir(work .. '/' .. cdir, 'p')
writefile(['" A comment line', 'syn keyword rFunction rrtestfun'], work .. '/' .. cdir .. '/fun_rrtest')
extend(made_files, [cdir .. '/fun_rrtest'])
add(made_dirs, cdir)
g:rplugin.compldir = work .. '/' .. cdir
g:R_hi_fun = 1
var fun_listed: list<any> = []
for paren in [0, 1]
  g:R_hi_fun_paren = paren
  enew
  err = Caught(() => {
    g:SourceRFunList('rrtest')
  })
  add(fun_listed, [err, execute('syntax list')->split("\n")->filter((_, l) => l =~ 'rrtestfun')->len() > 0])
  bwipeout!
endfor
execute 'buffer ' .. rbuf
g:rplugin.compldir = saved_compldir
for [name, value] in saved_hi_opts
  if type(value) != v:t_none
    extend(g:, {[name]: value})
  elseif has_key(g:, name)
    remove(g:, name)
  endif
endfor
g:AssertEqual(fun_listed, [['', true], ['', true]],
  'SourceRFunList: the functions in a cache directory "c$HOME" are highlighted, with and without parentheses')

# ========================================================================
# :source: the directory of the plugin is taken as it is
# ========================================================================
# The files of the plugin source each other with ":source DIR/R/NAME.vim",
# where only the spaces of the directory were escaped. A percent sign or a
# number sign in it was replaced with a file name, and a bar ended the
# command. On Windows fnameescape() leaves a bracket alone, and :source then
# took another file that the name matches as a wildcard. The Vim files are
# copied into such a directory, and into a directory beside it that the name
# matches, and a Vim of its own loads every file type from the first one and
# from the real directory. Both must source the same scripts. The name ends
# with "$", which is taken as it is. A "$" that is followed by a name is not
# used. Vim itself replaces it with the value of that environment variable
# in an entry of 'runtimepath' and in every name that :source receives, so no
# plugin can be loaded from such a directory when the variable is set, and
# on Unix not even when it is unset.
var odd_root = work .. (has('win32') ? '/p%l #1 [1] x$' : '/p%l #1|x [1] x$')
var odd_twin = work .. (has('win32') ? '/p%l #1 1 x$' : '/p%l #1|x 1 x$')
var copied: list<string> = []
for sub in ['R', 'ftplugin', 'ftdetect', 'syntax']
  mkdir(odd_root .. '/' .. sub, 'p')
  mkdir(odd_twin .. '/' .. sub, 'p')
  for src in glob(plugin_root .. '/' .. sub .. '/*.vim', false, true)
    var rel = sub .. '/' .. fnamemodify(src, ':t')
    writefile(readfile(src, 'b'), odd_root .. '/' .. rel, 'b')
    writefile(readfile(src, 'b'), odd_twin .. '/' .. rel, 'b')
    add(copied, rel)
  endfor
endfor
for ext in ['R', 'Rmd', 'Rnw', 'Rd', 'Rrst', 'qmd', 'Rout']
  writefile(['text'], work .. '/x.' .. ext)
  add(made_files, 'x.' .. ext)
endfor
# Load the plugin from a directory in a Vim of its own and return its report
def LoadedFrom(root: string, outfile: string): list<string>
  var job = job_start([v:progpath, '-N', '-u', 'NONE', '-i', 'NONE', '-es', '-S',
    plugin_root .. '/tests/data/plugin_dir.vim'], {in_io: 'null', out_io: 'null', err_io: 'null',
    env: {RR_TEST_ROOT: root, RR_TEST_WORK: work, RR_TEST_OUT: outfile}})
  for _ in range(600)
    if job_status(job) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  job_stop(job, 'kill')
  return filereadable(outfile) ? readfile(outfile) : ['no report']
enddef
var real_report = LoadedFrom(plugin_root, work .. '/loaded_real.txt')
var odd_report = LoadedFrom(odd_root, work .. '/loaded_odd.txt')
# On Windows the report holds the names in lower case
g:Assert(match(real_report, '\c^R/common_global\.vim$') >= 0 && match(real_report, '^error') < 0,
  'source: the plugin loads from its own directory (' .. real_report->join(' ') .. ')')
g:AssertEqual(odd_report, real_report,
  'source: the plugin loads from a directory with odd characters in its name')
# The Vim above does not run every :source line. Each of them takes the name
# through g:RExFile(), or through its escape written out where the function
# is not defined yet. The names of R_source come from an option of the user,
# and that line is left out.
var unguarded_sources: list<string> = []
for file in glob(plugin_root .. '/R/*.vim', false, true) + glob(plugin_root .. '/ftplugin/*.vim', false, true)
  var lnum = 0
  for line in readfile(file)
    lnum += 1
    if line =~# '\<source [''"]' && line !~# 'g:RExFile(\|? substitute(common_\w\+, \|escape(fl, '
      add(unguarded_sources, fnamemodify(file, ':t') .. ':' .. lnum)
    endif
  endfor
endfor
g:AssertEqual(unguarded_sources, [], 'source: every name of a file of the plugin is escaped for a bracket')
add(made_files, 'loaded_real.txt')
add(made_files, 'loaded_odd.txt')
for odd_tail in [fnamemodify(odd_root, ':t'), fnamemodify(odd_twin, ':t')]
  extend(made_files, copied->mapnew((_, c) => odd_tail .. '/' .. c))
  extend(made_dirs, ['/R', '/ftplugin', '/ftdetect', '/syntax', '']->mapnew((_, d) => odd_tail .. d))
endfor

# ========================================================================
# Buffers: a name is found as it is, not as a pattern
# ========================================================================
# bufnr(), sign_place(), :sbuffer, and :bunload take a name as a file
# pattern. With "k1.R" and "k[1].R" both loaded, the bracket matched the other
# buffer, so the plugin went to "k1.R", placed the sign of the debugger there,
# or unloaded it, when it meant "k[1].R". The buffers are loaded with
# bufload(), since an Ex command on Windows would take the bracket for a
# wildcard as well.
var buf_cwd = getcwd()
execute 'cd ' .. fnameescape(work)
var saved_rscript_b = g:rplugin.rscript_name
for n in ['k1.R', 'k[1].R']
  writefile(['f <- function() {', '  1', '}'], work .. '/' .. n)
endfor
extend(made_files, ['k1.R', 'k[1].R'])
var k1buf = bufadd(work .. '/k1.R')
var kbbuf = bufadd(work .. '/k[1].R')
bufload(k1buf)
bufload(kbbuf)
# The plugin's own buffers. The Object Browser is a buffer without a file, R
# runs in a terminal buffer named after its command, and the help pages are
# made below by g:ShowRDoc() itself.
execute 'buffer ' .. rbuf
silent split Object_Browser
setlocal buftype=nofile noswapfile
var obbuf = bufnr()
close
var term_bufs = ['!R --args k1', '!R --args k[1]']->mapnew((_, n) =>
  term_start(has('win32') ? 'cmd /c exit' : 'true', {hidden: true, term_name: n}))
for _ in range(200)
  if term_bufs->copy()->filter((_, b) => term_getstatus(b) =~ 'running')->empty()
    break
  endif
  sleep 50m
endfor
g:AssertEqual(!exists('*g:RBufNr') ? ['g:RBufNr() is not defined'] : [g:RBufNr(work .. '/k[1].R'),
  g:RBufNr(work .. '/k1.R'), g:RBufNr('k[1].R'), g:RBufNr(bufname(kbbuf)), g:RBufNr('Object_Browser'),
  g:RBufNr('!R --args k[1]'), g:RBufNr('!R --args k1'), g:RBufNr(work .. '/k?.R'), g:RBufNr('')],
  [kbbuf, k1buf, kbbuf, kbbuf, obbuf, term_bufs[1], term_bufs[0], -1, rbuf],
  'RBufNr: each buffer is found by its own name')
# The plugin keeps names from bufname(), which are relative to the directory
# that was current then, and bufnr() still found such a buffer after a change
# of directory, as "autochdir" makes. The buffer whose path ends with the
# name is taken, if it is the only one, and the name is still no pattern.
for d in ['cw', 'u1', 'u2']
  mkdir(work .. '/' .. d, 'p')
endfor
writefile(['x'], work .. '/u1/x.R')
writefile(['x'], work .. '/u2/x.R')
var tail_bufs = ['u1', 'u2']->mapnew((_, d) => bufadd(work .. '/' .. d .. '/x.R'))
extend(made_files, ['u1/x.R', 'u2/x.R'])
extend(made_dirs, ['cw', 'u1', 'u2'])
execute 'cd ' .. fnameescape(work .. '/cw')
g:AssertEqual(!exists('*g:RBufNr') ? ['g:RBufNr() is not defined'] : [g:RBufNr('k[1].R'), g:RBufNr('k1.R'),
  g:RBufNr('k?.R'), g:RBufNr('x.R'), g:RBufNr('u1/x.R')], [kbbuf, k1buf, -1, -1, tail_bufs[0]],
  'RBufNr: a name from another directory is found when only one buffer ends with it')
execute 'cd ' .. fnameescape(work)
for b in tail_bufs
  execute 'bwipeout! ' .. b
endfor
# The test finds a buffer by the name that bufname() gives it
def BufOf(name: string): number
  var found = getbufinfo()->filter((_, b) => bufname(b.bufnr) ==# name)
  return empty(found) ? -1 : found[0].bufnr
enddef

# RDebugJump() went to "k1.R" and placed the sign there for "k[1].R"
def DbgLines(nr: number): list<number>
  return sign_getplaced(nr)[0].signs->mapnew((_, v) => v.lnum)
enddef
g:rplugin.rscript_name = bufname(kbbuf)
err = Caught(() => {
  g:RDebugJump(work .. '/k[1].R', 2)
})
g:AssertEqual([err, DbgLines(kbbuf), DbgLines(k1buf), bufnr()], ['', [2], [], rbuf],
  'RDebugJump: the sign goes into "k[1].R", and the window of the script comes back')
sign unplace 1
silent! only
# It came back to "k1.R" from a file that it opened for "k[1].R"
execute 'buffer ' .. kbbuf
err = Caught(() => {
  g:RDebugJump(work .. '/sourced.R', 2)
})
g:AssertEqual([err, bufnr()], ['', kbbuf], 'RDebugJump: comes back to the window of "k[1].R"')
sign unplace 1
silent! only
execute 'buffer ' .. rbuf

# ShowRDoc() replaced the text of the help page "h1" for the topic "h[1]".
# With the R console in front it went to the window of the R script first,
# and the console is stood in for here by the buffer of main.R.
var saved_vimpager_b = g:R_vimpager
var saved_rbufnr_b = get(g:rplugin, 'R_bufnr', v:none)
g:R_vimpager = 'tabnew'
g:rplugin.R_bufnr = rbuf
# Entering the buffer of main.R made it the R script
g:rplugin.rscript_name = bufname(kbbuf)
var script_shown_b = -1
err = Caught(() => {
  g:ShowRDoc('h1', 'one')
  script_shown_b = tabpagebuflist(tabpagenr() - 1)[tabpagewinnr(tabpagenr() - 1) - 1]
  g:ShowRDoc('h[1]', 'two')
  g:ShowRDoc('h[1]', 'three')
})
g:AssertEqual([err, script_shown_b], ['', kbbuf], 'ShowRDoc: goes from the R console to "k[1].R"')
g:AssertEqual([getbufline(BufOf('h1'), 1, '$'), getbufline(BufOf('h[1]'), 1, '$')],
  [['one'], ['three']], 'ShowRDoc: the text of "h[1]" goes into its own page')
if type(saved_rbufnr_b) == v:t_none
  remove(g:rplugin, 'R_bufnr')
else
  g:rplugin.R_bufnr = saved_rbufnr_b
endif
silent! tabonly
silent! only
execute 'buffer ' .. rbuf

# OpenRExample() unloaded the example of another temporary directory, so the
# old text of its own example stayed
var saved_tmpdir_b = g:rplugin.tmpdir
mkdir(work .. '/t1', 'p')
mkdir(work .. '/t[1]', 'p')
writefile(['old'], work .. '/t1/example.R')
writefile(['old'], work .. '/t[1]/example.R')
var ex1 = bufadd(work .. '/t1/example.R')
var exb = bufadd(work .. '/t[1]/example.R')
bufload(ex1)
bufload(exb)
writefile(['new'], work .. '/t[1]/example.R')
g:rplugin.tmpdir = work .. '/t[1]'
err = Caught(() => {
  g:OpenRExample()
})
g:AssertEqual([err, bufloaded(ex1), getline(1, '$'), filereadable(work .. '/t[1]/example.R')],
  ['', 1, ['new'], 0], 'OpenRExample: unloads the example of its own directory')
g:rplugin.tmpdir = saved_tmpdir_b
g:R_vimpager = saved_vimpager_b
silent! tabonly
silent! only
execute 'buffer ' .. rbuf
add(made_files, 't1/example.R')
extend(made_dirs, ['t1', 't[1]'])

# ShowRout() unloaded "q1.Rout" for "q[1].Rout". R itself runs the file.
if executable('R')
  for n in ['q1', 'q[1]']
    writefile(['x <- 1'], work .. '/' .. n .. '.R')
    writefile(['old'], work .. '/' .. n .. '.Rout')
  endfor
  extend(made_files, ['q1.R', 'q[1].R', 'q1.Rout', 'q[1].Rout'])
  var rout1 = bufadd(work .. '/q1.Rout')
  var routb = bufadd(work .. '/q[1].Rout')
  bufload(rout1)
  bufload(routb)
  execute 'buffer ' .. bufadd(work .. '/q[1].R')
  var saved_rcmd_b = g:rplugin.Rcmd
  g:rplugin.Rcmd = exepath('R')
  err = Caught(() => {
    g:ShowRout()
  })
  for _ in range(1200)
    if job_status(g:rplugin.jobs['R_CMD']) !=# 'run' && bufloaded(routb)
      break
    endif
    sleep 50m
  endfor
  g:AssertEqual([err, bufloaded(rout1), getbufline(rout1, 1, '$'),
    match(getbufline(routb, 1, '$'), '^> x <- 1') >= 0],
    ['', 1, ['old'], true], 'ShowRout: unloads "q[1].Rout" and leaves "q1.Rout" alone')
  g:rplugin.Rcmd = saved_rcmd_b
  silent! tabonly
  silent! only
  execute 'buffer ' .. rbuf
endif

# No other line of the plugin gives a name to bufnr() or to an Ex command that
# takes a buffer, or matches the name of the current buffer as a pattern
var name_lookups: list<string> = []
var buf_cmd = '\%(^\s*\|[''"]\)\%(sil\%[ent]!\= \)\=\%(noautocmd \)\='
  .. '\%(sb\|sbuffer\|bunload\|bdelete\|bwipeout\)!\= \h'
for file in glob(plugin_root .. '/R/*.vim', false, true)
    + glob(plugin_root .. '/ftplugin/*.vim', false, true)
  var lnum = 0
  for line in readfile(file)
    lnum += 1
    if line !~ '^\s*#' && (line =~# '\<bufnr(\%(\s*)\|\s*[''"]%[''"]\s*)\)\@!'
        || line =~# buf_cmd || line =~# 'bufname("%") =\~')
      add(name_lookups, fnamemodify(file, ':t') .. ':' .. lnum)
    endif
  endfor
endfor
g:AssertEqual(name_lookups, [], 'buffers: no name of a buffer is taken as a pattern')
g:rplugin.rscript_name = saved_rscript_b
# The example of OpenRExample() wipes itself once its window is closed
for b in [obbuf, k1buf, kbbuf, ex1, exb] + term_bufs
  if bufexists(b)
    execute 'bwipeout! ' .. b
  endif
endfor
execute 'cd ' .. fnameescape(buf_cwd)

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
