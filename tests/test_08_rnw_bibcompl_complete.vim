vim9script
# Tests for rnw_fun.vim, bibcompl.vim, and complete.vim functions

g:SetSuite('rnw_bibcompl_complete')

if !exists('g:rplugin')
  g:rplugin = {'debug_info': {}, 'libs_in_nrs': [], 'nrs_running': 0, 'myport': 0, 'R_pid': 0}
endif

# ========================================================================
# RnwIsInRCode logic
# ========================================================================
def SimulateRnwIsInRCode(line_content: string, chunk_start: number, chunk_end: number, curline: number): bool
  # In rnoweb, R code is between <<...>>= and @
  return curline > chunk_start && (chunk_end == 0 || curline < chunk_end)
enddef

g:Assert(SimulateRnwIsInRCode('x <- 1', 5, 10, 7), 'RnwIsInRCode: inside chunk')
g:Assert(!SimulateRnwIsInRCode('text', 5, 10, 3), 'RnwIsInRCode: before chunk')
g:Assert(!SimulateRnwIsInRCode('text', 5, 10, 12), 'RnwIsInRCode: after chunk')

# ========================================================================
# RmdIsInRCode logic
# ========================================================================
def SimulateRmdIsInRCode(chunkline: number, docline: number, curline: number): bool
  return chunkline > docline && chunkline != curline
enddef

g:Assert(SimulateRmdIsInRCode(5, 3, 7), 'RmdIsInRCode: inside chunk')
g:Assert(!SimulateRmdIsInRCode(3, 5, 7), 'RmdIsInRCode: outside chunk')
g:Assert(!SimulateRmdIsInRCode(5, 3, 5), 'RmdIsInRCode: on chunk header line')

# ========================================================================
# SyncTeX_GetMaster logic
# ========================================================================
def SimulateGetMaster(bufname: string, has_main: bool, main_file: string): string
  if has_main
    return main_file
  else
    return substitute(bufname, '\.\(rnw\|Rnw\|tex\)$', '', '')
  endif
enddef

g:AssertEqual(SimulateGetMaster('doc.Rnw', false, ''), 'doc', 'GetMaster: strips .Rnw')
g:AssertEqual(SimulateGetMaster('doc.tex', false, ''), 'doc', 'GetMaster: strips .tex')
g:AssertEqual(SimulateGetMaster('doc.Rnw', true, 'main'), 'main', 'GetMaster: uses main file')

# ========================================================================
# RWriteChunk generation
# ========================================================================
def GenerateRnwChunk(): list<string>
  return ['<<>>=', '', '@']
enddef

def GenerateRmdChunk(ft: string): list<string>
  if ft == 'quarto'
    return ['```{r}', '', '```', '']
  else
    return ['```{r}', '```', '']
  endif
enddef

var rnw_chunk = GenerateRnwChunk()
g:AssertEqual(rnw_chunk[0], '<<>>=', 'GenerateRnwChunk: correct header')
g:AssertEqual(rnw_chunk[2], '@', 'GenerateRnwChunk: correct footer')
g:AssertEqual(len(rnw_chunk), 3, 'GenerateRnwChunk: correct length')

var rmd_chunk = GenerateRmdChunk('rmd')
g:AssertEqual(rmd_chunk[0], '```{r}', 'GenerateRmdChunk: correct header')
g:AssertEqual(rmd_chunk[1], '```', 'GenerateRmdChunk: correct footer')

var quarto_chunk = GenerateRmdChunk('quarto')
g:AssertEqual(len(quarto_chunk), 4, 'GenerateRmdChunk quarto: has extra blank line')

# ========================================================================
# BibComplete parsing
# ========================================================================
def ParseBibCompletionLine(line: string): dict<string>
  var tmp = split(line, "\x09")
  if len(tmp) >= 3
    return {'word': tmp[0], 'abbr': tmp[1], 'menu': tmp[2]}
  endif
  return {}
enddef

var bib_line = "smith2020\tSmith (2020)\tMachine Learning" .. "\x09"
# Manually construct with tabs
bib_line = "smith2020\tSmith (2020)\tMachine Learning"
var parsed = ParseBibCompletionLine(bib_line)
g:AssertEqual(parsed.word, 'smith2020', 'ParseBibCompletionLine: word')
g:AssertEqual(parsed.abbr, 'Smith (2020)', 'ParseBibCompletionLine: abbr')
g:AssertEqual(parsed.menu, 'Machine Learning', 'ParseBibCompletionLine: menu')

g:AssertEqual(ParseBibCompletionLine('incomplete'), {}, 'ParseBibCompletionLine: incomplete line')

# ========================================================================
# HasPython3 logic
# ========================================================================
def CheckPython3Binary(): string
  if executable('python3')
    return 'python3'
  elseif executable('python')
    return 'python'
  else
    return ''
  endif
enddef

var py = CheckPython3Binary()
g:AssertType(py, v:t_string, 'CheckPython3Binary: returns string')

# ========================================================================
# RmdGetYamlField logic
# ========================================================================
def ParseYamlField(lines: list<string>, field: string): string
  for line in lines
    if line == '---' || line == '...'
      break
    endif
    if line =~ '^\s*' .. field .. '\s*:'
      var bstr = substitute(line, '^\s*' .. field .. '\s*:\s*\(.*\)\s*', '\1', '')
      if bstr =~ '^".*"$' || bstr =~ "^'.*'$"
        return substitute(substitute(bstr, '"', '', 'g'), "'", '', 'g')
      endif
      return bstr
    endif
  endfor
  return ''
enddef

var yaml_lines = ['title: "My Doc"', 'bibliography: refs.bib', 'output: html_document', '---']
g:AssertEqual(ParseYamlField(yaml_lines, 'bibliography'), 'refs.bib', 'ParseYamlField: bibliography')
g:AssertEqual(ParseYamlField(yaml_lines, 'title'), 'My Doc', 'ParseYamlField: quoted title')
g:AssertEqual(ParseYamlField(yaml_lines, 'nonexistent'), '', 'ParseYamlField: missing field')

# ========================================================================
# FindStartRObj logic (completion)
# ========================================================================
def FindWordStart(line: string, col: number): number
  if col <= 0 || len(line) == 0
    return 0
  endif
  var idx = col - 1
  while idx > 0 && line[idx - 1] =~ '[A-Za-z0-9._]'
    idx -= 1
  endwhile
  return idx
enddef

g:AssertEqual(FindWordStart('library(dplyr)', 14), 8, 'FindWordStart: inside parens')
g:AssertEqual(FindWordStart('x <- mean', 9), 5, 'FindWordStart: after assignment')
g:AssertEqual(FindWordStart('mean', 4), 0, 'FindWordStart: start of line')
g:AssertEqual(FindWordStart('', 0), 0, 'FindWordStart: empty line')

# ========================================================================
# CompleteChunkOptions parsing
# ========================================================================
def FilterChunkOptions(base: string, options: list<string>): list<string>
  if base == ''
    return copy(options)
  endif
  return filter(copy(options), (_, v) => v =~? '^' .. base)
enddef

var opts = ['echo', 'eval', 'include', 'results', 'fig.width', 'fig.height']
g:AssertEqual(len(FilterChunkOptions('', opts)), 6, 'FilterChunkOptions: empty base returns all')
g:AssertEqual(FilterChunkOptions('fig', opts), ['fig.width', 'fig.height'], 'FilterChunkOptions: prefix filter')
g:AssertEqual(FilterChunkOptions('e', opts), ['echo', 'eval'], 'FilterChunkOptions: single char filter')
g:AssertEqual(FilterChunkOptions('xyz', opts), [], 'FilterChunkOptions: no match')
