vim9script
# Regression tests for numbers that were used as conditions. In Vim9 script a
# condition takes a boolean, 0, or 1, and any other number raises E1023. The
# plugin used a line number from search() and the exit status of a shell
# command in this way. Compiling the functions does not show it, since the
# number is known only when the line runs.

g:SetSuite('number_conditions')

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
# The warnings of the plugin are collected here while the tests are sourced
var saved_msgs = get(get(g:, 'rplugin', {}), 'start_msg', v:none)

# ========================================================================
# FixRdoc: the line number of a section is no condition
# ========================================================================
# g:FixRdoc() prepares the help text that R sends. It looked for the sections
# Examples, Arguments, and Usage with search() and used each line number as
# a condition, so every help text with one of these sections below its first
# line raised E1023. The marks that the syntax file needs were not set, and
# ShowRDoc() stopped before its end.
new
setline(1, [
  'match                   package:base                   R Documentation',
  '',
  "_\x08V_\x08a_\x08l_\x08u_\x08e Matching",
  '',
  'Description:',
  '',
  '     text',
  '',
  'Usage:',
  '',
  '     match(x, table)',
  '',
  'Arguments:',
  '',
  '       x: vector',
  '',
  'Examples:',
  '',
  '     1 %in% 2'])
err = Caught(() => {
  setlocal filetype=rdoc
})
g:AssertEqual(err, '', 'FixRdoc: no error for a help text with Usage, Arguments, and Examples')
g:AssertEqual(getline(3), 'Value Matching', 'FixRdoc: the overstruck title is plain text')
g:AssertEqual([line('$'), getline('$')], [20, '###'], 'FixRdoc: the end of the examples is marked')
g:AssertEqual(getline(13), 'Arguments: ', 'FixRdoc: the heading of the arguments ends with a space')
g:AssertEqual([getline(12), getline(16)], ["\t", " \t"],
  'FixRdoc: a tab marks the end of the usage and of the arguments')
# The file type is set again when the same buffer shows another topic
err = Caught(() => {
  g:FixRdoc()
})
g:AssertEqual([err, line('$')], ['', 20], 'FixRdoc: a second run adds no second end mark')
bwipeout!

# ========================================================================
# Rnoweb: the line that names the root of a child document
# ========================================================================
# SyncTeX_GetMaster() and SyncTeX_forward() looked for "% !Rnw root = " with
# search() and used the line number as a condition, so a child document that
# names its root on another line than the first raised E1023.
writefile(['% a child document', '% !Rnw root = main.Rnw', 'text'], work .. '/child.Rnw')
execute 'edit ' .. fnameescape(work .. '/child.Rnw')
var child_buf = bufnr('%')
cursor(3, 1)
var master = ''
err = Caught(() => {
  master = g:SyncTeX_GetMaster()
})
g:AssertEqual([err, master], ['', work .. '/main'],
  'SyncTeX_GetMaster: the root that the second line of a child names is found')
g:rplugin.start_msg = []
err = Caught(() => {
  g:SyncTeX_forward()
})
g:AssertEqual([err, g:rplugin.start_msg], ['', ['Vim-R [SyncTeX]: "main-concordance.tex" not found.']],
  'SyncTeX_forward: the root of a child is looked up, and its missing concordance is reported')
enew
execute 'bwipeout! ' .. child_buf

# ========================================================================
# Shell commands: an exit status above 1 is a failure, and no error of Vim
# ========================================================================
# RRaiseWindow() and the forward search of Zathura used v:shell_error as a
# condition. wmctrl, busctl, and swaymsg end with 1 for most failures, but a
# program that is missing ends the shell with 127, and swaymsg ends with 2
# when sway refuses the command. The stand-ins end with 2 or 3.
if has('unix')
  var bindir = work .. '/bin'
  mkdir(bindir, 'p')
  for [prog, status] in [['wmctrl', 3], ['busctl', 3], ['swaymsg', 2], ['zathura', 3]]
    writefile(['#!/bin/sh', 'echo "' .. prog .. ' failed"', 'exit ' .. status], bindir .. '/' .. prog)
    setfperm(bindir .. '/' .. prog, 'rwx------')
  endfor
  writefile(['#!/bin/sh', 'exit 0'], bindir .. '/dbus-send')
  setfperm(bindir .. '/dbus-send', 'rwx------')
  if !exists('*g:RRaiseWindow')
    execute 'source ' .. fnameescape(plugin_root .. '/R/pdf_init.vim')
  endif
  # getenv() returns v:null for a variable that is not set, and setenv()
  # removes the variable again when it gets v:null
  var saved_env = ['PATH', 'WAYLAND_DISPLAY', 'GNOME_SHELL_SESSION_MODE', 'XDG_CURRENT_DESKTOP']
    ->mapnew((_, name) => [name, getenv(name)])
  var saved_wm = [g:rplugin.has_wmctrl, g:rplugin.has_awbt]
  $PATH = bindir .. ':' .. $PATH
  var raised = -1

  g:rplugin.has_wmctrl = 1
  err = Caught(() => {
    raised = g:RRaiseWindow('a title')
  })
  g:AssertEqual([err, raised], ['', 0], 'RRaiseWindow: wmctrl that ends with 3 has raised no window')

  g:rplugin.has_wmctrl = 0
  g:rplugin.has_awbt = 1
  $WAYLAND_DISPLAY = 'wayland-test'
  $GNOME_SHELL_SESSION_MODE = 'user'
  g:rplugin.start_msg = []
  raised = -1
  err = Caught(() => {
    raised = g:RRaiseWindow('a title')
  })
  g:AssertEqual([err, raised, g:rplugin.start_msg],
    ['', 0, ['Error running Gnome Shell Extension "Activate Window By Title": busctl failed ']],
    'RRaiseWindow: busctl that ends with 3 is reported as a failure')

  g:rplugin.has_awbt = 0
  $XDG_CURRENT_DESKTOP = 'sway'
  g:rplugin.start_msg = []
  raised = -1
  err = Caught(() => {
    raised = g:RRaiseWindow('a title')
  })
  g:AssertEqual([err, raised, g:rplugin.start_msg], ['', 0, ['Error running swaymsg: swaymsg failed ']],
    'RRaiseWindow: swaymsg that ends with 2 is reported as a failure')
  [g:rplugin.has_wmctrl, g:rplugin.has_awbt] = saved_wm
  for [name, value] in saved_env
    setenv(name, value)
  endfor

  # pdf_zathura.vim is sourced once and looks for its programs then, so the
  # forward search of Zathura runs in a Vim of its own
  var zout = work .. '/zathura_forward.out'
  var zjob = job_start([v:progpath, '-N', '-u', 'NONE', '-i', 'NONE', '-es', '-S',
    plugin_root .. '/tests/data/zathura_forward.vim'], {in_io: 'null', out_io: 'null', err_io: 'null',
    env: {PATH: bindir .. ':' .. $PATH, RR_TEST_ROOT: plugin_root, RR_TEST_OUT: zout,
      RR_TEST_PDF: work .. '/doc.pdf', RR_TEST_TEX: work .. '/doc.tex'}})
  for _ in range(300)
    if job_status(zjob) !=# 'run'
      break
    endif
    sleep 100m
  endfor
  job_stop(zjob, 'kill')
  g:AssertEqual(filereadable(zout) ? readfile(zout) : ['no report'], ['', 'zathura failed ', 'process 0'],
    'Zathura: a forward search that ends with 3 is reported, and the viewer is taken as closed')
endif

if type(saved_msgs) == v:t_none
  remove(g:rplugin, 'start_msg')
else
  g:rplugin.start_msg = saved_msgs
endif
# On Unix the work directory lies in the temporary directory of Vim, which Vim
# removes when it exits. On Windows it stays, so the one file that the blocks
# above made there is removed by name.
if has('win32')
  delete(work .. '/child.Rnw')
  delete(work, 'd')
endif
