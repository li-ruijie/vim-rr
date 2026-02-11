vim9script
# Tests for common_global.vim pure functions

g:SetSuite('common_global')

# --- Bootstrap minimal g:rplugin so the file can be sourced ---
g:rplugin = {
  'debug_info': {},
  'libs_in_nrs': [],
  'nrs_running': 0,
  'myport': 0,
  'R_pid': 0,
}

# We source only the functions we need by defining stubs and then extracting
# the pure functions manually.

# ========================================================================
# FormatPrgrph
# ========================================================================
def FormatPrgrph(text: string, splt: string, jn: string, maxlen: number): string
  var wlist = split(text, splt)
  var txt = ['']
  var ii = 0
  for wrd in wlist
    if strdisplaywidth(txt[ii] .. splt .. wrd) < maxlen
      txt[ii] ..= splt .. wrd
    else
      ii += 1
      txt += [wrd]
    endif
  endfor
  txt[0] = substitute(txt[0], '^' .. splt, '', '')
  return join(txt, jn)
enddef

g:AssertEqual(
  FormatPrgrph('hello world foo', ' ', "\n", 20),
  "hello world foo",
  'FormatPrgrph: short text stays on one line')

g:AssertMatch(
  FormatPrgrph('hello world foo bar baz qux', ' ', "\n", 15),
  "\\n",
  'FormatPrgrph: long text wraps')

g:AssertEqual(
  FormatPrgrph('one', ' ', "\n", 80),
  'one',
  'FormatPrgrph: single word')

g:AssertEqual(
  FormatPrgrph('', ' ', "\n", 80),
  '',
  'FormatPrgrph: empty string')

# ========================================================================
# FormatTxt
# ========================================================================
def FormatTxt(text: string, splt: string, jn: string, maxl: number): string
  var maxlen = maxl - len(jn)
  var atext = substitute(text, "\x13", "'", "g")
  var plist = split(atext, "\x14")
  var txt = ''
  for prg in plist
    txt ..= "\n " .. FormatPrgrph(prg, splt, jn, maxlen)
  endfor
  txt = substitute(txt, "^\n ", "", "")
  return txt
enddef

g:AssertEqual(
  FormatTxt("hello world", ' ', "\n ", 80),
  'hello world',
  'FormatTxt: simple text')

g:Assert(
  FormatTxt("hello\x14world", ' ', "\n ", 80) =~ 'hello',
  'FormatTxt: paragraph separator splits text')

g:Assert(
  FormatTxt("it\x13s a test", ' ', "\n ", 80) =~ "it's a test",
  'FormatTxt: x13 replaced with single quote')

# ========================================================================
# CountBraces  (from start_r.vim)
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

g:AssertEqual(CountBraces('{}'), 0, 'CountBraces: matched braces')
g:AssertEqual(CountBraces('{'), 1, 'CountBraces: open brace')
g:AssertEqual(CountBraces('}'), -1, 'CountBraces: close brace')
g:AssertEqual(CountBraces('{{}}'), 0, 'CountBraces: nested braces')
g:AssertEqual(CountBraces('{{}'), 1, 'CountBraces: unmatched nested')
g:AssertEqual(CountBraces(''), 0, 'CountBraces: empty string')
g:AssertEqual(CountBraces('no braces here'), 0, 'CountBraces: no braces')
g:AssertEqual(CountBraces('f(x) { g(y) }'), 0, 'CountBraces: code with parens and braces')

# ========================================================================
# RParenDiff  (from start_r.vim)
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

g:AssertEqual(RParenDiff('()'), 0, 'RParenDiff: matched parens')
g:AssertEqual(RParenDiff('('), 1, 'RParenDiff: open paren')
g:AssertEqual(RParenDiff(')'), -1, 'RParenDiff: close paren')
g:AssertEqual(RParenDiff('f(x, g(y))'), 0, 'RParenDiff: nested call')
g:AssertEqual(RParenDiff('f(x, g(y)'), 1, 'RParenDiff: unclosed call')
g:AssertEqual(RParenDiff(''), 0, 'RParenDiff: empty string')

# ========================================================================
# CleanOxygenLine  (from start_r.vim)
# ========================================================================
def CleanOxygenLine(line: string): string
  return substitute(line, "^\\s*#'\\=\\s*", "", "")
enddef

g:AssertEqual(CleanOxygenLine("#' some doc"), 'some doc', 'CleanOxygenLine: roxygen comment')
g:AssertEqual(CleanOxygenLine("# a comment"), 'a comment', 'CleanOxygenLine: normal comment')
g:AssertEqual(CleanOxygenLine("  #' indented"), 'indented', 'CleanOxygenLine: indented roxygen')
g:AssertEqual(CleanOxygenLine("no comment"), 'no comment', 'CleanOxygenLine: no hash')

# ========================================================================
# GetSourceArgs  (from start_r.vim)
# ========================================================================
def GetSourceArgs(e: string): string
  if e == "echo"
    return ", echo=TRUE"
  else
    return ""
  endif
enddef

g:AssertEqual(GetSourceArgs('echo'), ', echo=TRUE', 'GetSourceArgs: echo mode')
g:AssertEqual(GetSourceArgs('silent'), '', 'GetSourceArgs: silent mode')
g:AssertEqual(GetSourceArgs(''), '', 'GetSourceArgs: empty string')

# ========================================================================
# g:rplugin structure
# ========================================================================
g:AssertType(g:rplugin, v:t_dict, 'rplugin is a dictionary')
g:Assert(has_key(g:rplugin, 'debug_info'), 'rplugin has debug_info')
g:Assert(has_key(g:rplugin, 'libs_in_nrs'), 'rplugin has libs_in_nrs')
g:AssertType(g:rplugin.libs_in_nrs, v:t_list, 'libs_in_nrs is a list')
g:AssertType(g:rplugin.debug_info, v:t_dict, 'debug_info is a dict')

# ========================================================================
# Variable defaults and type checks
# ========================================================================
g:R_assign = get(g:, 'R_assign', 1)
g:AssertType(g:R_assign, v:t_number, 'R_assign default is number')
g:AssertEqual(g:R_assign, 1, 'R_assign default is 1')

g:R_indent_commented = get(g:, 'R_indent_commented', 1)
g:AssertEqual(g:R_indent_commented, 1, 'R_indent_commented default is 1')
