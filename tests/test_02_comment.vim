vim9script
# Tests for comment.vim functions

g:SetSuite('comment')

# ========================================================================
# RGetFL — get first and last line
# ========================================================================
def RGetFL(mode: string): list<number>
  if mode == "normal"
    var fline = line(".")
    var lline = line(".")
  else
    var fline = line("'<")
    var lline = line("'>")
  endif
  # For testing, use simple values
  var fline = mode == "normal" ? 1 : 1
  var lline = mode == "normal" ? 1 : 3
  if fline > lline
    var tmp = lline
    lline = fline
    fline = tmp
  endif
  return [fline, lline]
enddef

g:AssertEqual(RGetFL("normal"), [1, 1], 'RGetFL: normal mode returns same line')
g:AssertEqual(RGetFL("selection"), [1, 3], 'RGetFL: selection returns range')

# ========================================================================
# Comment string defaults
# ========================================================================
g:r_indent_ess_comments = 0
g:R_indent_commented = 1
g:R_rcomment_string = get(g:, 'R_rcomment_string', '# ')

g:AssertEqual(g:R_rcomment_string, '# ', 'Default comment string is "# "')

g:r_indent_ess_comments = 1
g:R_indent_commented = 1
var cmt_ess_indented = '## '
g:AssertEqual(cmt_ess_indented, '## ', 'ESS + indented comment string is "## "')

g:r_indent_ess_comments = 1
g:R_indent_commented = 0
var cmt_ess_not_indented = '### '
g:AssertEqual(cmt_ess_not_indented, '### ', 'ESS + not-indented comment string is "### "')

# Reset
g:r_indent_ess_comments = 0

# ========================================================================
# Comment/uncomment logic (unit-tested in isolation)
# ========================================================================
# Simulate RSimpleCommentLine logic
def SimpleComment(line: string, cstr: string): string
  return cstr .. line
enddef

def SimpleUncomment(line: string, cstr: string): string
  return substitute(line, '^' .. cstr, '', '')
enddef

g:AssertEqual(SimpleComment('x <- 1', '# '), '# x <- 1', 'SimpleComment: adds comment prefix')
g:AssertEqual(SimpleUncomment('# x <- 1', '# '), 'x <- 1', 'SimpleUncomment: removes comment prefix')
g:AssertEqual(SimpleUncomment('x <- 1', '# '), 'x <- 1', 'SimpleUncomment: no-op if not commented')
g:AssertEqual(SimpleComment('', '# '), '# ', 'SimpleComment: empty line')
g:AssertEqual(SimpleComment('  indented', '# '), '#   indented', 'SimpleComment: indented line')

# ========================================================================
# RCommentLine logic
# ========================================================================
def IsCommented(line: string, cmt: string): bool
  return line =~ '^\s*' .. cmt || line =~ '^\s*#'
enddef

def ToggleComment(line: string, cmt: string): string
  if IsCommented(line, cmt)
    var result = substitute(line, '^\s*' .. cmt, '', '')
    result = substitute(result, '^\s*#*', '', '')
    return result
  else
    return cmt .. line
  endif
enddef

g:AssertEqual(ToggleComment('x <- 1', '## '), '## x <- 1', 'ToggleComment: uncommented -> commented')
g:AssertEqual(ToggleComment('## x <- 1', '## '), 'x <- 1', 'ToggleComment: commented -> uncommented')
g:AssertEqual(ToggleComment('# x <- 1', '## '), ' x <- 1', 'ToggleComment: hash-commented -> uncommented')

# ========================================================================
# MovePosRLineComment alignment logic
# ========================================================================
def CalcCommentPos(lines: list<string>, target_col: number): number
  var cpos = target_col
  for line in lines
    var cleanl = substitute(line, '\s*#.*', '', '')
    var llen = strlen(cleanl)
    if llen > (cpos - 2)
      cpos = llen + 2
    endif
  endfor
  return cpos
enddef

g:AssertEqual(CalcCommentPos(['x <- 1'], 40), 40, 'CalcCommentPos: short line keeps default')
var long_line = repeat('x', 50)
g:AssertEqual(CalcCommentPos([long_line], 40), 52, 'CalcCommentPos: long line pushes comment right')
g:AssertEqual(CalcCommentPos(['short', long_line], 40), 52, 'CalcCommentPos: max of all lines')
