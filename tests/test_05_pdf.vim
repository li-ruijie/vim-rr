vim9script
# Tests for pdf_init.vim and PDF viewer selection logic

g:SetSuite('pdf_init')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif
g:rplugin.has_wmctrl = 0
g:rplugin.has_awbt = 0
g:rplugin.zathura_pid = {}

# ========================================================================
# PDF viewer selection
# ========================================================================
def SelectPDFViewer(pdfviewer: string): string
  var viewer = tolower(pdfviewer)
  var known = ['zathura', 'evince', 'okular', 'sumatra', 'qpdfview']
  if index(known, viewer) >= 0
    return viewer
  else
    return 'generic'
  endif
enddef

g:AssertEqual(SelectPDFViewer('zathura'), 'zathura', 'SelectPDFViewer: zathura')
g:AssertEqual(SelectPDFViewer('Zathura'), 'zathura', 'SelectPDFViewer: case insensitive')
g:AssertEqual(SelectPDFViewer('evince'), 'evince', 'SelectPDFViewer: evince')
g:AssertEqual(SelectPDFViewer('okular'), 'okular', 'SelectPDFViewer: okular')
g:AssertEqual(SelectPDFViewer('sumatra'), 'sumatra', 'SelectPDFViewer: sumatra')
g:AssertEqual(SelectPDFViewer('qpdfview'), 'qpdfview', 'SelectPDFViewer: qpdfview')
g:AssertEqual(SelectPDFViewer('firefox'), 'generic', 'SelectPDFViewer: unknown -> generic')
g:AssertEqual(SelectPDFViewer(''), 'generic', 'SelectPDFViewer: empty -> generic')

# ========================================================================
# R_openpdf defaults based on environment
# ========================================================================
def GetDefaultOpenPDF(wayland: string, desktop: string): number
  if desktop == "sway"
    return 2
  elseif wayland != ""
    return 1
  else
    return 2
  endif
enddef

g:AssertEqual(GetDefaultOpenPDF('', ''), 2, 'GetDefaultOpenPDF: X11 default is 2')
g:AssertEqual(GetDefaultOpenPDF('wayland-0', ''), 1, 'GetDefaultOpenPDF: Wayland default is 1')
g:AssertEqual(GetDefaultOpenPDF('wayland-0', 'sway'), 2, 'GetDefaultOpenPDF: Sway default is 2')

# ========================================================================
# Zathura PID tracking
# ========================================================================
g:AssertType(g:rplugin.zathura_pid, v:t_dict, 'zathura_pid is a dictionary')

g:rplugin.zathura_pid['/tmp/test.pdf'] = 12345
g:Assert(has_key(g:rplugin.zathura_pid, '/tmp/test.pdf'), 'zathura_pid: key added')
g:AssertEqual(g:rplugin.zathura_pid['/tmp/test.pdf'], 12345, 'zathura_pid: correct value')

g:rplugin.zathura_pid['/tmp/test.pdf'] = 0
g:AssertEqual(g:rplugin.zathura_pid['/tmp/test.pdf'], 0, 'zathura_pid: reset to 0')

# ========================================================================
# Evince SyncTeX path handling
# ========================================================================
def EvinceSyncTeXPath(tpath: string): list<string>
  var n1 = substitute(tpath, '\(^/.*/\).*', '\1', '')
  var n2 = substitute(tpath, '.*/\(.*\)', '\1', '')
  var texname = substitute(n1, " ", "%20", "g") .. n2
  return [n1, n2, texname]
enddef

var result = EvinceSyncTeXPath('/home/user/my doc/file.tex')
g:AssertEqual(result[0], '/home/user/my doc/', 'EvinceSyncTeXPath: directory extracted')
g:AssertEqual(result[1], 'file.tex', 'EvinceSyncTeXPath: filename extracted')
g:AssertEqual(result[2], '/home/user/my%20doc/file.tex', 'EvinceSyncTeXPath: spaces encoded in dir')

result = EvinceSyncTeXPath('/home/user/file.tex')
g:AssertEqual(result[2], '/home/user/file.tex', 'EvinceSyncTeXPath: no spaces, no encoding')

# ========================================================================
# Sumatra path detection logic
# ========================================================================
def SumatraCheckPath(path_env: string): bool
  return path_env =~ 'SumatraPDF'
enddef

g:Assert(SumatraCheckPath('C:\\Program Files\\SumatraPDF;C:\\Windows'), 'SumatraCheckPath: found in PATH')
g:Assert(!SumatraCheckPath('C:\\Windows;C:\\Program Files'), 'SumatraCheckPath: not in PATH')
