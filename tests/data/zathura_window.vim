vim9script
# Run by test_17_names_in_r.vim in a Vim of its own, since pdf_zathura.vim
# looks for its programs once, when it is sourced. The test puts stand-ins for
# zathura, wmctrl, and dbus-send on PATH. This script opens $RR_TEST_PDF and
# writes the error and the warnings into $RR_TEST_OUT.
var report = ['']
g:rplugin = {has_wmctrl: 1, jobs: {}, myport: 1, zathura_pid: {}}
g:R_openpdf = 1
def g:RWarningMsg(msg: string)
  add(report, msg)
enddef
def g:ROnJobStderr(_job: any, msg: string)
  add(report, msg)
enddef
def g:RRaiseWindow(_title: string): number
  return 0
enddef
try
  execute 'source ' .. fnameescape($RR_TEST_ROOT .. '/R/pdf_zathura.vim')
  g:ROpenPDF2($RR_TEST_PDF)
catch
  report[0] = v:exception
endtry
writefile(report, $RR_TEST_OUT)
qall!
