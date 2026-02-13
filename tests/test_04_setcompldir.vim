vim9script
# Tests for setcompldir.vim setup logic

g:SetSuite('setcompldir')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# User login detection logic
# ========================================================================
def DetermineUserLogin(): string
  if $LOGNAME != ""
    return $LOGNAME
  elseif $USER != ""
    return $USER
  elseif $USERNAME != ""
    return $USERNAME
  elseif $HOME != ""
    return substitute($HOME, '.*/', '', '')
  else
    return ""
  endif
enddef

var login = DetermineUserLogin()
g:Assert(login != '', 'DetermineUserLogin: returns non-empty string')
g:AssertType(login, v:t_string, 'DetermineUserLogin: returns string type')

# Sanitize login
def SanitizeLogin(raw: string): string
  var cleaned = substitute(raw, '.*\\', '', '')
  cleaned = substitute(cleaned, '\W', '', 'g')
  return cleaned
enddef

g:AssertEqual(SanitizeLogin('DOMAIN\\User'), 'User', 'SanitizeLogin: strips domain prefix')
g:AssertEqual(SanitizeLogin('simpleuser'), 'simpleuser', 'SanitizeLogin: simple user unchanged')
g:AssertEqual(SanitizeLogin('user.name'), 'username', 'SanitizeLogin: strips dots')
g:AssertEqual(SanitizeLogin('user-name'), 'username', 'SanitizeLogin: strips hyphens')

# ========================================================================
# Completion directory logic
# ========================================================================
def DetermineComplDir(): string
  if exists("g:R_compldir")
    return expand(g:R_compldir)
  elseif has("win32") && $APPDATA != "" && isdirectory($APPDATA)
    return $APPDATA .. "\\vim-rr"
  elseif $XDG_CACHE_HOME != "" && isdirectory($XDG_CACHE_HOME)
    return $XDG_CACHE_HOME .. "/vim-rr"
  elseif isdirectory(expand("~/.cache"))
    return expand("~/.cache/vim-rr")
  elseif isdirectory(expand("~/Library/Caches"))
    return expand("~/Library/Caches/vim-rr")
  else
    return "fallback"
  endif
enddef

var compldir = DetermineComplDir()
g:Assert(compldir != '', 'DetermineComplDir: returns non-empty string')
g:AssertType(compldir, v:t_string, 'DetermineComplDir: returns string type')

# ========================================================================
# README generation
# ========================================================================
var first_line = 'Last change in this file: 2024-08-15'
g:AssertEqual(first_line, 'Last change in this file: 2024-08-15', 'README first line constant')

def NeedReadme(compldir_path: string, expected_first_line: string): bool
  if !filereadable(compldir_path .. "/README")
    return true
  endif
  if readfile(compldir_path .. "/README")[0] != expected_first_line
    return true
  endif
  return false
enddef

# Non-existent dir should need README
g:Assert(NeedReadme('/tmp/nonexistent_vim_r_test', first_line), 'NeedReadme: true for missing dir')

# ========================================================================
# Path normalization on Windows
# ========================================================================
def NormalizeWinPath(path: string): string
  return substitute(path, '\\', '/', 'g')
enddef

g:AssertEqual(NormalizeWinPath("C:\\Users\\test"), 'C:/Users/test', 'NormalizeWinPath: backslash to forward')
g:AssertEqual(NormalizeWinPath('/unix/path'), '/unix/path', 'NormalizeWinPath: unix path unchanged')
g:AssertEqual(NormalizeWinPath(''), '', 'NormalizeWinPath: empty string')
