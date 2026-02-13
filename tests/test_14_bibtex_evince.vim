vim9script
# Tests for R/bibtex.vim parser and R/evince_dbus.vim helpers

g:SetSuite('bibtex_evince')

import '../R/bibtex.vim' as bibtex

# ========================================================================
# ParseBibString — simple article
# ========================================================================
var simple_bib = '@article{smith2020, author = {John Smith}, title = {A Title}, year = {2020}, journal = {J. Example}}'
var result = bibtex.ParseBibString(simple_bib)

g:Assert(has_key(result, 'entries'), 'ParseBibString: result has entries key')
g:Assert(has_key(result, 'preamble'), 'ParseBibString: result has preamble key')
g:Assert(has_key(result, 'preamble_list'), 'ParseBibString: result has preamble_list key')
g:Assert(has_key(result.entries, 'smith2020'), 'ParseBibString: entry smith2020 exists')

var entry = result.entries.smith2020
g:AssertEqual(entry.type, 'article', 'ParseBibString: entry type is article')
g:AssertEqual(entry.fields.title, 'A Title', 'ParseBibString: title field')
g:AssertEqual(entry.fields.year, '2020', 'ParseBibString: year field')
g:AssertEqual(entry.fields.journal, 'J. Example', 'ParseBibString: journal field')

# Person field should be in persons, not fields
g:Assert(!has_key(entry.fields, 'author'), 'ParseBibString: author not in fields')
g:Assert(has_key(entry.persons, 'author'), 'ParseBibString: author in persons')
g:AssertEqual(len(entry.persons.author), 1, 'ParseBibString: one author')

var author = entry.persons.author[0]
g:AssertEqual(author.first_names, ['John'], 'ParseBibString: author first name')
g:AssertEqual(author.last_names, ['Smith'], 'ParseBibString: author last name')

# ========================================================================
# ParseBibString — empty input
# ========================================================================
var empty_result = bibtex.ParseBibString('')
g:AssertEqual(empty_result.preamble, '', 'ParseBibString empty: no preamble')
g:AssertEqual(len(keys(empty_result.entries)), 0, 'ParseBibString empty: no entries')

# ========================================================================
# ParseBibString — preamble and macro expansion
# ========================================================================
var macro_bib = '@string{myjournal = "Journal of Testing"} @preamble{"This is a preamble"} @article{key1, title = {Test}, journal = myjournal, year = {2021}}'
var macro_result = bibtex.ParseBibString(macro_bib)

g:AssertEqual(macro_result.preamble, 'This is a preamble', 'ParseBibString macro: preamble text')
g:AssertEqual(len(macro_result.preamble_list), 1, 'ParseBibString macro: one preamble entry')
g:AssertEqual(macro_result.entries.key1.fields.journal, 'Journal of Testing', 'ParseBibString macro: macro expanded in journal')

# ========================================================================
# ParseBibString — month macro (built-in)
# ========================================================================
var month_bib = '@article{m1, title = {Test}, month = jan, year = {2020}}'
var month_result = bibtex.ParseBibString(month_bib)
g:AssertEqual(month_result.entries.m1.fields.month, 'January', 'ParseBibString: month macro jan -> January')

# ========================================================================
# ParsePerson — representative names
# ========================================================================
var p1 = bibtex.ParsePerson('John Smith')
g:AssertEqual(p1.first_names, ['John'], 'ParsePerson simple: first')
g:AssertEqual(p1.last_names, ['Smith'], 'ParsePerson simple: last')
g:AssertEqual(p1.prelast_names, [], 'ParsePerson simple: no prelast')
g:AssertEqual(p1.lineage_names, [], 'ParsePerson simple: no lineage')

var p2 = bibtex.ParsePerson('Andrea de Leeuw van Weenen')
g:AssertEqual(p2.first_names, ['Andrea'], 'ParsePerson particles: first')
g:AssertEqual(p2.prelast_names, ['de', 'Leeuw', 'van'], 'ParsePerson particles: prelast')
g:AssertEqual(p2.last_names, ['Weenen'], 'ParsePerson particles: last')

var p3 = bibtex.ParsePerson('Ford, Jr., Henry')
g:AssertEqual(p3.first_names, ['Henry'], 'ParsePerson lineage: first')
g:AssertEqual(p3.last_names, ['Ford'], 'ParsePerson lineage: last')
g:AssertEqual(p3.lineage_names, ['Jr.'], 'ParsePerson lineage: lineage')

var p4 = bibtex.ParsePerson('Edwin V. {Bell, II}')
g:AssertEqual(p4.first_names, ['Edwin'], 'ParsePerson braces: first')
g:AssertEqual(p4.middle_names, ['V.'], 'ParsePerson braces: middle')
g:AssertEqual(p4.last_names, ['{Bell, II}'], 'ParsePerson braces: last preserves braced group')

var p5 = bibtex.ParsePerson('')
g:AssertEqual(p5.first_names, [], 'ParsePerson empty: no first')
g:AssertEqual(p5.last_names, [], 'ParsePerson empty: no last')

var p6 = bibtex.ParsePerson('Anonymous')
g:AssertEqual(p6.first_names, [], 'ParsePerson single: no first')
g:AssertEqual(p6.last_names, ['Anonymous'], 'ParsePerson single: last is the word')

# ========================================================================
# PersonToString — round-trip
# ========================================================================
var p_vl = bibtex.ParsePerson('Ford, Jr., Henry')
var s_vl = bibtex.PersonToString(p_vl)
g:AssertEqual(s_vl, 'Ford, Jr., Henry', 'PersonToString: von Last, Jr, First format')

var p_simple = bibtex.ParsePerson('John Smith')
var s_simple = bibtex.PersonToString(p_simple)
g:AssertEqual(s_simple, 'Smith, John', 'PersonToString: simple Last, First')

# ========================================================================
# GetField — case-insensitive lookup
# ========================================================================
var gf_bib = '@article{k, Title = {Hello World}, YEAR = {2025}}'
var gf_result = bibtex.ParseBibString(gf_bib)
var gf_entry = gf_result.entries.k

g:AssertEqual(bibtex.GetField(gf_entry, 'title'), 'Hello World', 'GetField: case-insensitive title')
g:AssertEqual(bibtex.GetField(gf_entry, 'YEAR'), '2025', 'GetField: case-insensitive YEAR')
g:AssertEqual(bibtex.GetField(gf_entry, 'nonexistent'), '', 'GetField: missing field returns empty')

# ========================================================================
# GetPersons — case-insensitive role lookup
# ========================================================================
var gp_bib = '@article{k2, author = {Alice Bob}, editor = {Carol Dee}}'
var gp_result = bibtex.ParseBibString(gp_bib)
var gp_entry = gp_result.entries.k2

var authors = bibtex.GetPersons(gp_entry, 'author')
g:AssertEqual(len(authors), 1, 'GetPersons: one author')
g:AssertEqual(authors[0].last_names, ['Bob'], 'GetPersons: author last name')

var editors = bibtex.GetPersons(gp_entry, 'EDITOR')
g:AssertEqual(len(editors), 1, 'GetPersons: case-insensitive editor')

var missing = bibtex.GetPersons(gp_entry, 'translator')
g:AssertEqual(len(missing), 0, 'GetPersons: missing role returns empty list')

# ========================================================================
# GetEntry — case-insensitive key lookup
# ========================================================================
var ge_entry = bibtex.GetEntry(gf_result, 'K')
g:Assert(ge_entry != null, 'GetEntry: case-insensitive key lookup')

var ge_missing = bibtex.GetEntry(gf_result, 'nonexistent')
g:AssertEqual(ge_missing, null, 'GetEntry: missing key returns null')

# ========================================================================
# Multiple authors with "and"
# ========================================================================
var multi_bib = '@article{m, author = {Alice Smith and Bob Jones and Carol Lee}}'
var multi_result = bibtex.ParseBibString(multi_bib)
var multi_authors = multi_result.entries.m.persons.author
g:AssertEqual(len(multi_authors), 3, 'ParseBibString: three authors split on "and"')
g:AssertEqual(multi_authors[0].last_names, ['Smith'], 'ParseBibString: first author last')
g:AssertEqual(multi_authors[1].last_names, ['Jones'], 'ParseBibString: second author last')
g:AssertEqual(multi_authors[2].last_names, ['Lee'], 'ParseBibString: third author last')

# ========================================================================
# Evince D-Bus helper: ExtractFirstString
# ========================================================================
import '../R/evince_dbus.vim' as dbus

# Empty args
g:AssertEqual(dbus.ExtractFirstString([]), '', 'ExtractFirstString: empty list')

# Single string arg
g:AssertEqual(dbus.ExtractFirstString(['   string "file:///foo.pdf"']), 'file:///foo.pdf', 'ExtractFirstString: single string arg')

# Mixed args — skip non-string lines
var mixed_args = ['   int32 42', '   string "hello.tex"']
g:AssertEqual(dbus.ExtractFirstString(mixed_args), 'hello.tex', 'ExtractFirstString: skips non-string lines')

# Multiple string lines — returns first match
var multi_str_args = ['   string "first.pdf"', '   string "second.pdf"']
g:AssertEqual(dbus.ExtractFirstString(multi_str_args), 'first.pdf', 'ExtractFirstString: returns first match')

# No string lines at all
g:AssertEqual(dbus.ExtractFirstString(['   int32 1', '   boolean true']), '', 'ExtractFirstString: no strings returns empty')

# ========================================================================
# Evince D-Bus constants — verify non-empty
# ========================================================================
g:Assert(dbus.EV_DAEMON_PATH != '', 'dbus const: EV_DAEMON_PATH non-empty')
g:Assert(dbus.EV_DAEMON_NAME != '', 'dbus const: EV_DAEMON_NAME non-empty')
g:Assert(dbus.EV_DAEMON_IFACE != '', 'dbus const: EV_DAEMON_IFACE non-empty')
g:Assert(dbus.EVINCE_PATH != '', 'dbus const: EVINCE_PATH non-empty')
g:Assert(dbus.EVINCE_IFACE != '', 'dbus const: EVINCE_IFACE non-empty')
g:Assert(dbus.EV_WINDOW_IFACE != '', 'dbus const: EV_WINDOW_IFACE non-empty')

# ========================================================================
# Deep comparison helper
# ========================================================================

def DeepCompare(expected: any, actual: any, path: string = '$'): list<string>
  var diffs: list<string> = []
  if type(expected) == v:t_dict && type(actual) == v:t_dict
    for key in sort(keys(expected))
      if !has_key(actual, key)
        add(diffs, path .. '.' .. key .. ': missing in output')
        continue
      endif
      extend(diffs, DeepCompare(expected[key], actual[key], path .. '.' .. key))
    endfor
    for key in sort(keys(actual))
      if !has_key(expected, key)
        add(diffs, path .. '.' .. key .. ': unexpected in output')
      endif
    endfor
  elseif type(expected) == v:t_list && type(actual) == v:t_list
    if len(expected) != len(actual)
      add(diffs, path .. ': length ' .. string(len(expected)) .. ' vs ' .. string(len(actual)))
    endif
    for i in range(min([len(expected), len(actual)]))
      extend(diffs, DeepCompare(expected[i], actual[i], path .. '[' .. string(i) .. ']'))
    endfor
  else
    if expected != actual
      add(diffs, path .. ': ' .. string(expected) .. ' vs ' .. string(actual))
    endif
  endif
  return diffs
enddef

# ========================================================================
# Deep comparison: .bib file tests (against pybtex reference JSON)
# ========================================================================

var data_dir = expand('<sfile>:p:h') .. '/data'

for bib_path in sort(glob(data_dir .. '/*.bib', false, true))
  var stem = fnamemodify(bib_path, ':t:r')
  var ref_path = data_dir .. '/ref_' .. stem .. '.json'
  if !filereadable(ref_path)
    continue
  endif
  var ref_data = json_decode(join(readfile(ref_path), "\n"))
  var actual = bibtex.ParseBibFile(bib_path)
  var diffs = DeepCompare(ref_data, actual)
  g:Assert(len(diffs) == 0, 'Deep bib ' .. stem .. ': ' .. (len(diffs) > 0 ? diffs[0] : 'ok'))
endfor

# ========================================================================
# Deep comparison: inline BibTeX string tests
# ========================================================================

var inputs_path = data_dir .. '/inline_inputs.json'
var inline_tests: dict<any> = json_decode(join(readfile(inputs_path), "\n"))

for [name, input_strings] in sort(items(inline_tests))
  var ref_path = data_dir .. '/ref_' .. name .. '.json'
  if !filereadable(ref_path)
    continue
  endif
  var combined: string = join(input_strings, '')
  var ref_data = json_decode(join(readfile(ref_path), "\n"))
  var actual = bibtex.ParseBibString(combined)
  var diffs = DeepCompare(ref_data, actual)
  g:Assert(len(diffs) == 0, 'Deep inline ' .. name .. ': ' .. (len(diffs) > 0 ? diffs[0] : 'ok'))
endfor

# ========================================================================
# Deep comparison: person name parsing (176 names)
# ========================================================================

var ref_names_path = data_dir .. '/ref_names.json'
var ref_names: list<any> = json_decode(join(readfile(ref_names_path), "\n"))

var name_results: list<dict<any>> = []
for ref_entry in ref_names
  var parsed = bibtex.ParsePerson(ref_entry.input)
  add(name_results, {
    'input': ref_entry.input,
    'first_names': parsed.first_names,
    'middle_names': parsed.middle_names,
    'prelast_names': parsed.prelast_names,
    'last_names': parsed.last_names,
    'lineage_names': parsed.lineage_names,
  })
endfor

var name_diffs = DeepCompare(ref_names, name_results)
g:Assert(len(name_diffs) == 0, 'Deep names: ' .. (len(name_diffs) > 0 ? name_diffs[0] : 'ok'))
