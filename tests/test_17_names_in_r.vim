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
