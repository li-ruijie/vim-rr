vim9script
# Tests for start_r.vim pure functions

g:SetSuite('start_r')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# IsSendCmdToRFake
# ========================================================================
def FuncToString(F: func): string
  return string(F)
enddef

# ========================================================================
# CountBraces (also tested in common_global but these are more start_r specific)
# ========================================================================
def CountBraces(line: string): number
  var result = 0
  for c in split(line, '\zs')
    if c == '{'
      result += 1
    elseif c == '}'
      result -= 1
    endif
  endfor
  return result
enddef

g:AssertEqual(CountBraces('function() {'), 1, 'CountBraces: function open')
g:AssertEqual(CountBraces('  }'), -1, 'CountBraces: closing brace')
g:AssertEqual(CountBraces('  if (x) { y } else { z }'), 0, 'CountBraces: balanced if-else')

# ========================================================================
# RParenDiff
# ========================================================================
def RParenDiff(str: string): number
  var result = 0
  for c in split(str, '\zs')
    if c == '('
      result += 1
    elseif c == ')'
      result -= 1
    endif
  endfor
  return result
enddef

g:AssertEqual(RParenDiff('f(x)'), 0, 'RParenDiff: balanced call')
g:AssertEqual(RParenDiff('f(x, g('), 2, 'RParenDiff: two unclosed')
g:AssertEqual(RParenDiff('))'), -2, 'RParenDiff: two extra closes')

# ========================================================================
# CleanOxygenLine
# ========================================================================
def CleanOxygenLine(line: string): string
  return substitute(line, "^\\s*#'\\=\\s*", "", "")
enddef

g:AssertEqual(CleanOxygenLine("#' @param x The value"), '@param x The value', 'CleanOxygenLine: roxygen param')
g:AssertEqual(CleanOxygenLine("# regular"), 'regular', 'CleanOxygenLine: regular comment')
g:AssertEqual(CleanOxygenLine("   # indented"), 'indented', 'CleanOxygenLine: indented')

# ========================================================================
# GetSourceArgs
# ========================================================================
def GetSourceArgs(e: string): string
  return e == "echo" ? ", echo=TRUE" : ""
enddef

g:AssertEqual(GetSourceArgs("echo"), ", echo=TRUE", 'GetSourceArgs: echo')
g:AssertEqual(GetSourceArgs("silent"), "", 'GetSourceArgs: silent')

# ========================================================================
# GoDown logic
# ========================================================================
def ShouldSkipLine(line: string): bool
  return line =~ '^\s*$' || line =~ '^\s*#'
enddef

g:Assert(ShouldSkipLine(''), 'ShouldSkipLine: empty line')
g:Assert(ShouldSkipLine('   '), 'ShouldSkipLine: whitespace only')
g:Assert(ShouldSkipLine('# comment'), 'ShouldSkipLine: comment')
g:Assert(ShouldSkipLine('  # indented comment'), 'ShouldSkipLine: indented comment')
g:Assert(!ShouldSkipLine('x <- 1'), 'ShouldSkipLine: code line')
g:Assert(!ShouldSkipLine('  x <- 1'), 'ShouldSkipLine: indented code')

# ========================================================================
# RSetMyPort
# ========================================================================
def SimulateSetMyPort(p: number): dict<any>
  var rplugin: dict<any> = {'myport': 0}
  rplugin.myport = p
  $VIMR_PORT = string(p)
  return rplugin
enddef

var result = SimulateSetMyPort(9876)
g:AssertEqual(result.myport, 9876, 'SimulateSetMyPort: port set correctly')

# ========================================================================
# R command quoting
# ========================================================================
def QuoteRCmd(cmd: string): string
  return substitute(cmd, '"', '\\"', "g")
enddef

g:AssertEqual(QuoteRCmd('print("hello")'), 'print(\"hello\")', 'QuoteRCmd: double quotes escaped')
g:AssertEqual(QuoteRCmd('x <- 1'), 'x <- 1', 'QuoteRCmd: no quotes unchanged')

# ========================================================================
# RSetWD command construction
# ========================================================================
def BuildSetWDCmd(dir: string): string
  return 'setwd("' .. dir .. '")'
enddef

g:AssertEqual(BuildSetWDCmd('/home/user'), 'setwd("/home/user")', 'BuildSetWDCmd: simple path')
g:AssertEqual(BuildSetWDCmd(''), 'setwd("")', 'BuildSetWDCmd: empty path')

# ========================================================================
# AddForDeletion
# ========================================================================
if !exists('g:rplugin.files_to_delete')
  g:rplugin.files_to_delete = []
endif

def AddForDeletion(fname: string)
  if index(g:rplugin.files_to_delete, fname) == -1
    add(g:rplugin.files_to_delete, fname)
  endif
enddef

AddForDeletion('/tmp/test1')
g:AssertEqual(len(g:rplugin.files_to_delete), 1, 'AddForDeletion: adds file')
AddForDeletion('/tmp/test1')
g:AssertEqual(len(g:rplugin.files_to_delete), 1, 'AddForDeletion: no duplicates')
AddForDeletion('/tmp/test2')
g:AssertEqual(len(g:rplugin.files_to_delete), 2, 'AddForDeletion: adds second file')

# ========================================================================
# RMakeRmd target logic
# ========================================================================
def BuildRmdTarget(t: string, ft: string): string
  if t == 'default'
    return ''
  elseif ft == 'quarto'
    if t == 'pdf'
      return ', output_format = "pdf"'
    elseif t == 'html'
      return ', output_format = "html"'
    endif
  else
    return ', output_format = "' .. t .. '"'
  endif
  return ''
enddef

g:AssertEqual(BuildRmdTarget('default', 'rmd'), '', 'BuildRmdTarget: default')
g:AssertEqual(BuildRmdTarget('pdf', 'quarto'), ', output_format = "pdf"', 'BuildRmdTarget: quarto pdf')
g:AssertEqual(BuildRmdTarget('pdf_document', 'rmd'), ', output_format = "pdf_document"', 'BuildRmdTarget: rmd pdf_document')
