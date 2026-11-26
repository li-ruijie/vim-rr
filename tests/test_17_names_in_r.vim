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
  g:AssertEqual(len(cmds), 15, 'vimcom: every command is one line (' .. r_errors .. ')')
  cmds += repeat(['missing'], 15 - len(cmds))
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
    ['g:FinishGlbEnvFunArgs', ['it''s "f"\', "[\x12x\x12], [\x12y\x12, \x121\x12], "]],
    'vimcom: the name of a function reaches FinishGlbEnvFunArgs() with its quotes and its backslash')
  # The arguments of a function and the columns of the data frame that is
  # its first argument go to the server as the items of a list. The server
  # writes a single quote in the place of each byte 0x12 and hands the list
  # to Vim, which is done here in its place.
  var items_head = '+A7;;plainf;'
  var items: any = 'no list'
  try
    items = eval('[' .. substitute(strpart(cmds[13], len(items_head)), "\x12", "'", 'g') .. ']')
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
  # An object of the package, with its seven fields
  writefile([["it's", '{', "my'cls", 'qpkg', '', 'A number', 'Text']->join("\x06") .. "\x06"],
    srv .. '/compl/omnils_qpkg_1.0')
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
