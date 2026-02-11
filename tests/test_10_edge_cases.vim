vim9script
# Tests for edge cases, ReplaceUnderS logic, and integration patterns

g:SetSuite('edge_cases_integration')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# R_assign replacement logic
# ========================================================================
def ShouldReplaceUnderscore(
    r_assign: number,
    char_before: string,
    char_before2: string,
    char_before3: string,
    in_string: bool
): bool
  if r_assign == 0
    return false
  endif
  if in_string
    return false
  endif
  if r_assign == 1
    # Check if we need to undo: <-_ -> _
    if char_before3 == '<' && char_before2 == '-' && char_before == ' '
      return false  # will undo
    endif
  endif
  return true
enddef

g:Assert(!ShouldReplaceUnderscore(0, '', '', '', false), 'ReplaceUnder: disabled')
g:Assert(!ShouldReplaceUnderscore(1, '', '', '', true), 'ReplaceUnder: in string')
g:Assert(ShouldReplaceUnderscore(1, 'x', ' ', 'y', false), 'ReplaceUnder: normal case')
g:Assert(!ShouldReplaceUnderscore(1, ' ', '-', '<', false), 'ReplaceUnder: undo case')

# ========================================================================
# R_assign_map default
# ========================================================================
g:R_assign = get(g:, 'R_assign', 1)
g:R_assign_map = get(g:, 'R_assign_map', '_')
g:AssertEqual(g:R_assign_map, '_', 'R_assign_map default is _')

# ========================================================================
# ShowRDebugInfo structure
# ========================================================================
g:rplugin.debug_info['Test'] = 'value'
g:Assert(has_key(g:rplugin.debug_info, 'Test'), 'debug_info: key added')
g:AssertEqual(g:rplugin.debug_info['Test'], 'value', 'debug_info: correct value')

# ========================================================================
# Escape sequences for R communication
# ========================================================================
# \x02 = STX (start of text), used as field separator
# \x03 = ETX (end of text), used in bib completion
# \x05 = ENQ, used as separator in bib queries
# \x06 = ACK, used as field separator in omnils files
# \x11 = XON, used as size header marker
# \x13 = XOFF, replacement for single quotes
# \x14 = paragraph separator

def ProtocolSeparator(): string
  return "\x06"
enddef

def ParseOmnilsLine(line: string): list<string>
  return split(line, "\x06")
enddef

var omnils_line = "mean\x06f\x06function\x06base\x06['x', '...']\x06Arithmetic Mean\x06"
var fields = ParseOmnilsLine(omnils_line)
g:AssertEqual(fields[0], 'mean', 'ParseOmnilsLine: name')
g:AssertEqual(fields[1], 'f', 'ParseOmnilsLine: type')
g:AssertEqual(fields[2], 'function', 'ParseOmnilsLine: class')
g:AssertEqual(fields[3], 'base', 'ParseOmnilsLine: package')

# ========================================================================
# Tmux version check logic
# ========================================================================
def CheckTmuxVersion(version_str: string): bool
  var ver = substitute(version_str, '.* \([0-9]\.[0-9]\).*', '\1', '')
  if strlen(ver) != 3
    ver = "1.0"
  endif
  return ver >= "3.0"
enddef

g:Assert(CheckTmuxVersion('tmux 3.2'), 'CheckTmuxVersion: 3.2 OK')
g:Assert(CheckTmuxVersion('tmux 3.0'), 'CheckTmuxVersion: 3.0 OK')
g:Assert(!CheckTmuxVersion('tmux 2.9'), 'CheckTmuxVersion: 2.9 too old')
g:Assert(!CheckTmuxVersion('tmux 1.8'), 'CheckTmuxVersion: 1.8 too old')

# ========================================================================
# R_objbr_place transformation
# ========================================================================
def TransformObjBrPlace(place: string): string
  return substitute(place, "console", "script", "")
enddef

g:AssertEqual(TransformObjBrPlace('console'), 'script', 'TransformObjBrPlace: console -> script')
g:AssertEqual(TransformObjBrPlace('script'), 'script', 'TransformObjBrPlace: script unchanged')
g:AssertEqual(TransformObjBrPlace('LEFT'), 'LEFT', 'TransformObjBrPlace: LEFT unchanged')

# ========================================================================
# R_rmdchunk logic
# ========================================================================
def ShouldMapBacktick(rmdchunk: any): bool
  if type(rmdchunk) == v:t_number
    return rmdchunk == 1 || rmdchunk == 2
  elseif type(rmdchunk) == v:t_string
    return true
  endif
  return false
enddef

g:Assert(ShouldMapBacktick(1), 'ShouldMapBacktick: 1')
g:Assert(ShouldMapBacktick(2), 'ShouldMapBacktick: 2')
g:Assert(!ShouldMapBacktick(0), 'ShouldMapBacktick: 0')
g:Assert(ShouldMapBacktick('aa'), 'ShouldMapBacktick: string')

# ========================================================================
# Cite pattern (rnoweb)
# ========================================================================
var cite_ptrn = '\C\\\a*cite\a*\*\?\(\[[^\]]*\]\)*\_\s*{'
g:Assert('\\cite{' =~ cite_ptrn, 'cite_ptrn: basic \\cite')
g:Assert('\\textcite{' =~ cite_ptrn, 'cite_ptrn: \\textcite')
g:Assert('\\parencite{' =~ cite_ptrn, 'cite_ptrn: \\parencite')
g:Assert('\\cite[p.~5]{' =~ cite_ptrn, 'cite_ptrn: \\cite with optional arg')

# ========================================================================
# LaTeX environment completion
# ========================================================================
def CompleteEnv(base: string): list<string>
  var lenv = ['abstract]', 'align*}', 'align}', 'center}', 'description}',
    'document}', 'enumerate}', 'equation}', 'figure}',
    'itemize}', 'table}', 'tabular}']
  return filter(copy(lenv), (_, v) => v =~? base)
enddef

g:AssertEqual(len(CompleteEnv('')), 12, 'CompleteEnv: empty base returns all')
g:AssertEqual(CompleteEnv('fig'), ['figure}'], 'CompleteEnv: fig matches figure')
g:AssertEqual(CompleteEnv('tab'), ['table}', 'tabular}'], 'CompleteEnv: tab matches table and tabular')
g:AssertEqual(CompleteEnv('xyz'), [], 'CompleteEnv: no match')

# ========================================================================
# R_OutDec float matching
# ========================================================================
def MatchesRFloat(s: string, outdec: string): bool
  if outdec == ','
    return s =~ '\<\d\+,\d*\([Ee][-+]\=\d\+\)\='
  else
    return s =~ '\<\d\+\.\d*\([Ee][-+]\=\d\+\)\='
  endif
enddef

g:Assert(MatchesRFloat('3.14', '.'), 'MatchesRFloat: period decimal')
g:Assert(MatchesRFloat('3,14', ','), 'MatchesRFloat: comma decimal')
g:Assert(MatchesRFloat('1.5e10', '.'), 'MatchesRFloat: scientific notation')
g:Assert(!MatchesRFloat('abc', '.'), 'MatchesRFloat: not a float')

# ========================================================================
# R_buffer_opts parsing
# ========================================================================
def ParseBufferOpts(opts_str: string): list<string>
  return split(opts_str)
enddef

g:AssertEqual(
  ParseBufferOpts('nobuflisted'),
  ['nobuflisted'],
  'ParseBufferOpts: single option')
g:AssertEqual(
  ParseBufferOpts('nobuflisted noswapfile'),
  ['nobuflisted', 'noswapfile'],
  'ParseBufferOpts: multiple options')
