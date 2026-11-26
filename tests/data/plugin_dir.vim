vim9script
# Run by test_17_names_in_r.vim in a Vim of its own. Loads the plugin from
# $RR_TEST_ROOT for every file type, with the files of $RR_TEST_WORK, and
# writes into $RR_TEST_OUT the errors and the scripts of the plugin that were
# sourced. The test compares the report for a plugin directory with an odd
# name with that for the real one.
var report: list<string> = []
&runtimepath = escape($RR_TEST_ROOT, ',') .. ',' .. $VIMRUNTIME
filetype plugin indent on
syntax on
g:R_filetypes = ['r', 'rmd', 'rnoweb', 'rhelp', 'rrst', 'quarto']
for ext in ['R', 'Rmd', 'Rnw', 'Rd', 'Rrst', 'qmd', 'Rout']
  try
    execute 'edit ' .. fnameescape($RR_TEST_WORK .. '/x.' .. ext)
  catch
    add(report, 'error for x.' .. ext .. ': ' .. matchstr(v:exception, 'E\d\+'))
  endtry
endfor
# What loads start_r.vim when R is started
try
  doautocmd FuncUndefined StartR
catch
  add(report, 'error for StartR: ' .. matchstr(v:exception, 'E\d\+'))
endtry

# The names as Vim keeps them, with forward slashes
def Norm(name: string): string
  var full = substitute(fnamemodify(name, ':p'), '\\', '/', 'g')
  return has('win32') ? tolower(full) : full
enddef
# This script lies in the real directory, under tests, and is left out
var root = Norm($RR_TEST_ROOT .. '/')
var sourced = getscriptinfo()
  ->mapnew((_, s) => Norm(s.name))
  ->filter((_, n) => stridx(n, root) == 0)
  ->mapnew((_, n) => strpart(n, len(root)))
  ->filter((_, n) => n !~# '^tests/')
  ->sort()
writefile(report + sourced, $RR_TEST_OUT)
qall!
