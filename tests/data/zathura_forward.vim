vim9script
# Run by test_18_number_conditions.vim in a Vim of its own, since
# pdf_zathura.vim looks for its programs once, when it is sourced. The test
# puts stand-ins for zathura, wmctrl, and dbus-send on PATH, and its zathura
# ends with a status of 3. This script asks for a forward search in a viewer
# that is taken as open, and writes the error, the warnings, and the process
# number that is kept for the PDF into $RR_TEST_OUT.
var report = ['']
g:rplugin = {has_wmctrl: 1, jobs: {}, myport: 1, zathura_pid: {}}
g:rplugin.zathura_pid[$RR_TEST_PDF] = 4242
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
  g:SyncTeX_forward2($RR_TEST_TEX, $RR_TEST_PDF, 12, 0)
catch
  report[0] = v:exception
endtry
add(report, 'process ' .. g:rplugin.zathura_pid[$RR_TEST_PDF])
writefile(report, $RR_TEST_OUT)
qall!
