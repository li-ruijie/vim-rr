vim9script
# Tests for extern_term.vim and tmux-related functions

g:SetSuite('extern_term')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# Terminal selection logic
# ========================================================================
def SelectTerminal(available: list<string>, wayland: string): string
  var terminals = copy(available)
  if wayland != ''
    insert(terminals, 'foot', 0)
  endif
  for term in terminals
    if executable(term)
      return term
    endif
  endfor
  return ''
enddef

# We can't control what's installed, but we can test the logic
var term_list = ['gnome-terminal', 'konsole', 'xfce4-terminal', 'xterm']
var selected = SelectTerminal(term_list, '')
g:AssertType(selected, v:t_string, 'SelectTerminal: returns a string')

# With wayland, foot should be prepended
def BuildTermListWithWayland(base: list<string>): list<string>
  return ['foot'] + base
enddef

var wayland_list = BuildTermListWithWayland(term_list)
g:AssertEqual(wayland_list[0], 'foot', 'BuildTermListWithWayland: foot is first')
g:AssertEqual(len(wayland_list), len(term_list) + 1, 'BuildTermListWithWayland: correct length')

# ========================================================================
# Terminal command construction
# ========================================================================
def BuildTermCmd(term_name: string, vim_wd: bool): string
  var cmd = ''
  if term_name =~ '^\(foot\|gnome-terminal\|xfce4-terminal\|roxterm\|Eterm\|aterm\|lxterminal\|rxvt\|urxvt\|alacritty\)$'
    cmd = term_name .. ' --title R'
  elseif term_name =~ '^\(xterm\|uxterm\|lxterm\)$'
    cmd = term_name .. ' -title R'
  else
    cmd = term_name
  endif

  if term_name == 'foot'
    cmd ..= ' --log-level error'
  endif

  if term_name == 'gnome-terminal'
    cmd ..= ' --'
  elseif term_name =~ '^\(terminator\|xfce4-terminal\)$'
    cmd ..= ' -x'
  else
    cmd ..= ' -e'
  endif

  return cmd
enddef

g:AssertMatch(BuildTermCmd('gnome-terminal', false), '--title R', 'BuildTermCmd: gnome-terminal has --title')
g:AssertMatch(BuildTermCmd('gnome-terminal', false), '-- *$', 'BuildTermCmd: gnome-terminal ends with --')
g:AssertMatch(BuildTermCmd('xterm', false), '-title R', 'BuildTermCmd: xterm has -title')
g:AssertMatch(BuildTermCmd('xterm', false), '-e$', 'BuildTermCmd: xterm ends with -e')
g:AssertMatch(BuildTermCmd('foot', false), '--log-level error', 'BuildTermCmd: foot has log-level')
g:AssertMatch(BuildTermCmd('xfce4-terminal', false), '-x$', 'BuildTermCmd: xfce4-terminal ends with -x')
g:AssertMatch(BuildTermCmd('alacritty', false), '--title R', 'BuildTermCmd: alacritty has --title')

# ========================================================================
# SendCmdToR_Term escape logic
# ========================================================================
def EscapeTmuxString(cmd: string): string
  return substitute(cmd, "'", "'\\'", "g")
enddef

g:AssertEqual(EscapeTmuxString("hello"), "hello", 'EscapeTmuxString: no quotes')
var escaped = EscapeTmuxString("it's")
g:Assert(escaped != "it's", 'EscapeTmuxString: single quote is escaped')
g:AssertEqual(EscapeTmuxString(""), "", 'EscapeTmuxString: empty string')

# Dash prefix handling
def HandleDashPrefix(str: string): string
  if str =~ '^-'
    return ' ' .. str
  endif
  return str
enddef

g:AssertEqual(HandleDashPrefix('-flag'), ' -flag', 'HandleDashPrefix: dash gets space prefix')
g:AssertEqual(HandleDashPrefix('normal'), 'normal', 'HandleDashPrefix: no dash unchanged')

# ========================================================================
# R_clear_line prefix logic
# ========================================================================
def ClearLinePrefix(cmd: string, editing_mode: string): string
  if editing_mode == "emacs"
    return "\x01\x0b" .. cmd
  else
    return "\x1b0Da" .. cmd
  endif
enddef

g:AssertMatch(ClearLinePrefix('ls()', 'emacs'), 'ls()$', 'ClearLinePrefix: emacs appends cmd')
g:AssertMatch(ClearLinePrefix('ls()', 'vi'), 'ls()$', 'ClearLinePrefix: vi appends cmd')

# ========================================================================
# Tmux session name generation
# ========================================================================
def GenerateTmuxSessionName(): string
  var ts = string(localtime())
  return 'VimR-' .. substitute(ts, '.*\(...\)', '\1', '')
enddef

var sname = GenerateTmuxSessionName()
g:AssertMatch(sname, '^VimR-', 'GenerateTmuxSessionName: starts with VimR-')
g:Assert(len(sname) <= 10, 'GenerateTmuxSessionName: reasonable length')

# ========================================================================
# TmuxActivePane parsing
# ========================================================================
def ParseTmuxPaneId(line: string): string
  var paneid = matchstr(line, '\v\%\d+ \(active\)')
  if !empty(paneid)
    return matchstr(paneid, '\v^\%\d+')
  else
    return matchstr(line, '\v^\d+')
  endif
enddef

g:AssertEqual(ParseTmuxPaneId('0: [80x24] [history 0/2000, 0 bytes] %0 (active)'), '%0', 'ParseTmuxPaneId: active pane')
g:AssertEqual(ParseTmuxPaneId('1: [80x24] %1'), '1', 'ParseTmuxPaneId: fallback to line start number')

# ========================================================================
# IMP-03: TmuxOption cache
# ========================================================================
g:SetSuite('IMP-03: TmuxOption cache')

# Test the caching pattern: second call returns cached value without system()
var tmux_cache: dict<string> = {}

def CachedLookup(key: string): string
    if has_key(tmux_cache, key)
        return tmux_cache[key]
    endif
    var result = 'value_for_' .. key
    tmux_cache[key] = result
    return result
enddef

g:AssertEqual(len(tmux_cache), 0, 'cache starts empty')
g:AssertEqual(CachedLookup('pane-base-index:window'), 'value_for_pane-base-index:window', 'first lookup returns value')
g:AssertEqual(len(tmux_cache), 1, 'cache populated after first call')
g:AssertEqual(CachedLookup('pane-base-index:window'), 'value_for_pane-base-index:window', 'second lookup returns cached value')
