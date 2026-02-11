vim9script
# Test runner framework for Vim-R plugin
# Usage: vim -u NONE -N -es -S tests/run_tests.vim

set nocompatible
set encoding=utf-8
scriptencoding utf-8
set nomore
if has('gui_running')
  set guioptions+=c
endif

var total_tests = 0
var passed_tests = 0
var failed_tests = 0
var test_errors: list<string> = []
var current_suite = ''

def g:SetSuite(name: string)
  current_suite = name
  echomsg '=== Suite: ' .. name .. ' ==='
enddef

def g:Assert(condition: bool, description: string)
  total_tests += 1
  if condition
    passed_tests += 1
  else
    failed_tests += 1
    var msg = '[FAIL] ' .. current_suite .. ': ' .. description
    add(test_errors, msg)
    echomsg msg
  endif
enddef

def g:AssertEqual(actual: any, expected: any, description: string)
  total_tests += 1
  if actual == expected
    passed_tests += 1
  else
    failed_tests += 1
    var msg = '[FAIL] ' .. current_suite .. ': ' .. description
      .. ' (expected ' .. string(expected) .. ', got ' .. string(actual) .. ')'
    add(test_errors, msg)
    echomsg msg
  endif
enddef

def g:AssertMatch(actual: string, pattern: string, description: string)
  total_tests += 1
  if actual =~ pattern
    passed_tests += 1
  else
    failed_tests += 1
    var msg = '[FAIL] ' .. current_suite .. ': ' .. description
      .. ' (string "' .. actual .. '" does not match "' .. pattern .. '")'
    add(test_errors, msg)
    echomsg msg
  endif
enddef

def g:AssertNotEqual(actual: any, unexpected: any, description: string)
  total_tests += 1
  if actual != unexpected
    passed_tests += 1
  else
    failed_tests += 1
    var msg = '[FAIL] ' .. current_suite .. ': ' .. description
      .. ' (unexpectedly got ' .. string(actual) .. ')'
    add(test_errors, msg)
    echomsg msg
  endif
enddef

def g:AssertType(val: any, expected_type: number, description: string)
  total_tests += 1
  if type(val) == expected_type
    passed_tests += 1
  else
    failed_tests += 1
    var msg = '[FAIL] ' .. current_suite .. ': ' .. description
      .. ' (expected type ' .. string(expected_type) .. ', got ' .. string(type(val)) .. ')'
    add(test_errors, msg)
    echomsg msg
  endif
enddef

def g:PrintSummary()
  echomsg ''
  echomsg '=============================='
  echomsg 'Test Summary'
  echomsg '=============================='
  echomsg 'Total:  ' .. total_tests
  echomsg 'Passed: ' .. passed_tests
  echomsg 'Failed: ' .. failed_tests
  echomsg ''
  if failed_tests > 0
    echomsg 'Failures:'
    for err in test_errors
      echomsg '  ' .. err
    endfor
  else
    echomsg 'All tests passed!'
  endif
  echomsg '=============================='
enddef

# Write results to file for CI
def g:WriteResults(filepath: string)
  var lines = [
    'Total: ' .. string(total_tests),
    'Passed: ' .. string(passed_tests),
    'Failed: ' .. string(failed_tests),
  ]
  for err in test_errors
    add(lines, err)
  endfor
  writefile(lines, filepath)
enddef

# Source test files
# Set VIMR_TEST_FILTER to a comma-separated list of filenames (relative to
# tests/) to run only those tests.  Leave unset to run all test_*.vim files.
var test_dir = expand('<sfile>:p:h')
var filter = $VIMR_TEST_FILTER

var test_files: list<string>
if filter != ''
  test_files = split(filter, ',')->map((_, f) => test_dir .. '/' .. f)->sort()
else
  test_files = glob(test_dir .. '/test_*.vim', false, true)->sort()
endif

for test_file in test_files
  try
    execute 'source ' .. fnameescape(test_file)
  catch
    failed_tests += 1
    var msg = '[ERROR] Failed to source ' .. test_file .. ': ' .. v:exception
    add(test_errors, msg)
    echomsg msg
  endtry
endfor

g:PrintSummary()
g:WriteResults(test_dir .. '/results.txt')

if failed_tests > 0
  cquit!
else
  qall!
endif
