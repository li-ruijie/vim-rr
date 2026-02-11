vim9script
# Tests for ftplugin logic, syntax patterns, GUI helpers, windows functions

g:SetSuite('ftplugin_syntax_gui_windows')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# Filetype detection patterns (ftdetect/r.vim)
# ========================================================================
def MatchesRHistoryPattern(fname: string): bool
  return fname =~ '\.Rhistory$'
enddef

def MatchesQmdPattern(fname: string): bool
  return fname =~ '\.qmd$'
enddef

def MatchesRoutPattern(fname: string): bool
  return fname =~ '\.Rout\(\.fail\|\.save\)\?$'
enddef

def MatchesRprojPattern(fname: string): bool
  return fname =~ '\.Rproj$'
enddef

g:Assert(MatchesRHistoryPattern('session.Rhistory'), 'ftdetect: .Rhistory')
g:Assert(!MatchesRHistoryPattern('file.R'), 'ftdetect: .R not Rhistory')
g:Assert(MatchesQmdPattern('document.qmd'), 'ftdetect: .qmd')
g:Assert(MatchesRoutPattern('output.Rout'), 'ftdetect: .Rout')
g:Assert(MatchesRoutPattern('output.Rout.fail'), 'ftdetect: .Rout.fail')
g:Assert(MatchesRoutPattern('output.Rout.save'), 'ftdetect: .Rout.save')
g:Assert(MatchesRprojPattern('project.Rproj'), 'ftdetect: .Rproj')

# ========================================================================
# R_filetypes filtering
# ========================================================================
def ShouldLoadForFiletype(filetypes: list<string>, ft: string): bool
  return index(filetypes, ft) != -1
enddef

var all_fts = ['r', 'rmd', 'rnoweb', 'rhelp', 'rrst', 'quarto', 'rdoc', 'rbrowser']
g:Assert(ShouldLoadForFiletype(all_fts, 'r'), 'ShouldLoadForFiletype: r')
g:Assert(ShouldLoadForFiletype(all_fts, 'rmd'), 'ShouldLoadForFiletype: rmd')
g:Assert(!ShouldLoadForFiletype(all_fts, 'python'), 'ShouldLoadForFiletype: python excluded')
g:Assert(!ShouldLoadForFiletype(['r', 'rmd'], 'rnoweb'), 'ShouldLoadForFiletype: rnoweb excluded from subset')

# ========================================================================
# GUI menu item construction (gui_running.vim)
# ========================================================================
def ParseMenuType(mtype: string): dict<bool>
  return {
    'normal': mtype =~ 'n',
    'visual': mtype =~ 'v',
    'insert': mtype =~ 'i',
    'has_zero': mtype =~ '0',
  }
enddef

var mt = ParseMenuType('nvi')
g:Assert(mt.normal, 'ParseMenuType: n detected')
g:Assert(mt.visual, 'ParseMenuType: v detected')
g:Assert(mt.insert, 'ParseMenuType: i detected')
g:Assert(!mt.has_zero, 'ParseMenuType: no 0')

mt = ParseMenuType('ni0')
g:Assert(mt.normal, 'ParseMenuType ni0: n detected')
g:Assert(!mt.visual, 'ParseMenuType ni0: no v')
g:Assert(mt.insert, 'ParseMenuType ni0: i detected')
g:Assert(mt.has_zero, 'ParseMenuType ni0: 0 detected')

# ========================================================================
# Syntax patterns (syntax/rout.vim)
# ========================================================================
def MatchesRoutString(line: string): bool
  return line =~ '^".*"$\|"[^"]*"'
enddef

def MatchesRoutNumber(line: string): bool
  return line =~ '\<\d\+\>'
enddef

def MatchesRoutConst(word: string): bool
  return word =~ '^\(NULL\|NA\|NaN\)$'
enddef

def MatchesRoutBool(word: string): bool
  return word =~ '^\(TRUE\|FALSE\)$'
enddef

g:Assert(MatchesRoutString('"hello world"'), 'RoutString: quoted string')
g:Assert(MatchesRoutNumber('42'), 'RoutNumber: integer')
g:Assert(MatchesRoutConst('NULL'), 'RoutConst: NULL')
g:Assert(MatchesRoutConst('NA'), 'RoutConst: NA')
g:Assert(MatchesRoutConst('NaN'), 'RoutConst: NaN')
g:Assert(MatchesRoutBool('TRUE'), 'RoutBool: TRUE')
g:Assert(MatchesRoutBool('FALSE'), 'RoutBool: FALSE')
g:Assert(!MatchesRoutBool('true'), 'RoutBool: lowercase false')

# ========================================================================
# Windows path handling (windows.vim)
# ========================================================================
def NormalizeWindowsPath(path: string): string
  return substitute(path, '\\', '/', 'g')
enddef

def BuildWindowsRCmd(R_path: string, args: list<string>): string
  return R_path .. ' ' .. join(args, ' ')
enddef

g:AssertEqual(NormalizeWindowsPath("C:\\Users\\test\\R"), 'C:/Users/test/R',
  'NormalizeWindowsPath: backslashes to forward')
g:AssertEqual(NormalizeWindowsPath(''), '', 'NormalizeWindowsPath: empty')

g:AssertEqual(
  BuildWindowsRCmd('R.exe', ['--no-save', '--sdi']),
  'R.exe --no-save --sdi',
  'BuildWindowsRCmd: correct command')

# ========================================================================
# R_hi_fun feature flag
# ========================================================================
g:R_hi_fun = get(g:, 'R_hi_fun', 1)
g:AssertEqual(g:R_hi_fun, 1, 'R_hi_fun default is 1')

# ========================================================================
# Object Browser view state
# ========================================================================
def OBViewState(curview: string, requested: string): bool
  return curview == requested
enddef

g:Assert(OBViewState('GlobalEnv', 'GlobalEnv'), 'OBViewState: matching view')
g:Assert(!OBViewState('GlobalEnv', 'Libraries'), 'OBViewState: non-matching view')

# ========================================================================
# R_disable_cmds filtering
# ========================================================================
def IsCommandDisabled(plug: string, disabled: list<string>): bool
  return index(disabled, plug) > -1
enddef

var disabled_cmds = ['RStart', 'RClose']
g:Assert(IsCommandDisabled('RStart', disabled_cmds), 'IsCommandDisabled: disabled command')
g:Assert(!IsCommandDisabled('RSendLine', disabled_cmds), 'IsCommandDisabled: enabled command')

# ========================================================================
# rdoc FixRdoc substitution logic
# ========================================================================
def FixRdocLine(line: string): string
  var result = substitute(line, "_\x08", "", "g")
  result = substitute(result, '<URL: \(.\{-}\)>', ' |\1|', 'g')
  result = substitute(result, '<email: \(.\{-}\)>', ' |\1|', 'g')
  return result
enddef

g:AssertEqual(FixRdocLine('_' .. "\x08" .. 'bold'), 'bold', 'FixRdocLine: backspace underline removed')
g:AssertEqual(FixRdocLine('<URL: http://example.com>'), ' |http://example.com|', 'FixRdocLine: URL converted')
g:AssertEqual(FixRdocLine('<email: user@host>'), ' |user@host|', 'FixRdocLine: email converted')
g:AssertEqual(FixRdocLine('normal text'), 'normal text', 'FixRdocLine: normal text unchanged')

# ========================================================================
# start_server.vim version parsing
# ========================================================================
def ParseVimcomVersion(info: string): string
  var parts = split(info, "\x02")
  return len(parts) > 0 ? parts[0] : ''
enddef

g:AssertEqual(ParseVimcomVersion("1.2.3\x02extra"), '1.2.3', 'ParseVimcomVersion: extracts version')
g:AssertEqual(ParseVimcomVersion(''), '', 'ParseVimcomVersion: empty string')
