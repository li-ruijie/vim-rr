vim9script

# bibtex.vim — Faithful port of pybtex.database.parse_file to Vim9 script
#
# Copyright (c) 2006-2021  Andrey Golovizin (original pybtex)
# Copyright (c) 2026-      Li Ruijie (vim9script port)
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

# ═══════════════════════════════════════════════════════════════════════
# Public API
# ═══════════════════════════════════════════════════════════════════════
#
# Returns a dict matching pybtex.database.BibliographyData:
#   {
#     'preamble':      string,           # joined preamble text
#     'preamble_list': list<string>,      # individual @preamble values
#     'entries':       dict<string, Entry>,
#   }
#
# Each Entry is:
#   {
#     'type':    string,                  # lowercased entry type
#     'fields':  dict<string, string>,    # non-person fields (original-case keys)
#     'persons': dict<string, list<Person>>,
#   }
#
# Each Person is:
#   {
#     'first_names':    list<string>,
#     'middle_names':   list<string>,
#     'prelast_names':  list<string>,
#     'last_names':     list<string>,
#     'lineage_names':  list<string>,
#   }

export def ParseBibFile(path: string): dict<any>
  var text = join(readfile(path), nr2char(10))
  return ParseBibString(text)
enddef

export def ParseBibString(text: string): dict<any>
  var macros: dict<string> = {
    'jan': 'January',  'feb': 'February', 'mar': 'March',
    'apr': 'April',    'may': 'May',      'jun': 'June',
    'jul': 'July',     'aug': 'August',   'sep': 'September',
    'oct': 'October',  'nov': 'November', 'dec': 'December',
  }
  var preamble_list: list<string> = []
  var entries: dict<any> = {}   # cite_key => Entry
  var person_fields = ['author', 'editor']

  # Run the low-level parser to get commands
  var commands = LowLevelParse(text, macros)

  for cmd in commands
    var cmd_type: string = cmd.command
    var cmd_type_lower = tolower(cmd_type)

    if cmd_type_lower == 'string'
      # Already handled inside LowLevelParse (macros dict mutated)
      continue
    elseif cmd_type_lower == 'preamble'
      var val = NormalizeWhitespace(join(cmd.value, ''))
      add(preamble_list, val)
    else
      # Regular entry
      ProcessEntry(cmd_type, cmd.key, cmd.fields,
                   person_fields, entries)
    endif
  endfor

  return {
    'preamble':      join(preamble_list, ''),
    'preamble_list': preamble_list,
    'entries':       entries,
  }
enddef

# Helper: convert a Person dict to "von Last, Jr, First" string
export def PersonToString(p: dict<any>): string
  var von_last = join(p.prelast_names + p.last_names, ' ')
  var jr = join(p.lineage_names, ' ')
  var first = join(p.first_names + p.middle_names, ' ')
  var parts: list<string> = []
  for part in [von_last, jr, first]
    if part != ''
      add(parts, part)
    endif
  endfor
  return join(parts, ', ')
enddef

# ═══════════════════════════════════════════════════════════════════════
# Process entry: separate person fields from regular fields
# Matches pybtex Parser.process_entry
# ═══════════════════════════════════════════════════════════════════════

def ProcessEntry(
    entry_type: string,
    cite_key: string,
    raw_fields: list<any>,
    person_fields: list<string>,
    entries: dict<any>)

  var entry: dict<any> = {
    'type': tolower(entry_type),
    'fields': {},
    'persons': {},
  }

  var seen_fields: list<string> = []

  for fld in raw_fields
    var field_name: string = fld[0]
    var field_value_list: list<string> = fld[1]
    var field_name_lower = tolower(field_name)

    # Duplicate check
    if index(seen_fields, field_name_lower) >= 0
      continue
    endif

    var field_value = NormalizeWhitespace(join(field_value_list, ''))

    if index(person_fields, field_name_lower) >= 0
      # Person field — parse into Person objects
      var names = SplitNameList(field_value)
      var persons_list: list<any> = []
      for name in names
        add(persons_list, ParsePerson(name))
      endfor
      if len(persons_list) > 0
        entry.persons[field_name] = persons_list
      endif
    else
      entry.fields[field_name] = field_value
    endif

    add(seen_fields, field_name_lower)
  endfor

  # Case-insensitive duplicate entry check
  for existing_key in keys(entries)
    if tolower(existing_key) == tolower(cite_key)
      return
    endif
  endfor

  entries[cite_key] = entry
enddef

# ═══════════════════════════════════════════════════════════════════════
# Low-level BibTeX scanner / parser
# Matches pybtex LowLevelParser
# ═══════════════════════════════════════════════════════════════════════

# NAME_CHARS from pybtex: ascii_letters + '@!$&*+-./:;<>?[\\]^_`|~\x7f'
const NAME_CHARS_PATTERN = '[A-Za-z@!$&*+\-./:;<>?\[\\\]^_`|~]'
const NAME_PATTERN = NAME_CHARS_PATTERN .. '[A-Za-z0-9@!$&*+\-./:;<>?\[\\\]^_`|~]*'

def LowLevelParse(text: string, macros: dict<string>): list<any>
  var s: dict<any> = {
    'text': text,
    'pos': 0,
    'end': strchars(text),
    'macros': macros,
  }
  var results: list<any> = []

  while true
    if !SkipToAt(s)
      break
    endif
    # pos is now right after '@'
    var cmd = ParseCommand(s)
    if cmd != null
      add(results, cmd)
    endif
  endwhile

  return results
enddef

def SkipToAt(s: dict<any>): bool
  var byte_pos = byteidx(s.text, s.pos)
  if byte_pos < 0
    s.pos = s.end
    return false
  endif
  var idx = stridx(s.text, '@', byte_pos)
  if idx < 0
    s.pos = s.end
    return false
  endif
  s.pos = charidx(s.text, idx) + 1  # skip past '@'
  return true
enddef

def EatWhitespace(s: dict<any>)
  while s.pos < s.end && s.text[s.pos] =~ '[ \t\n\r]'
    s.pos += 1
  endwhile
enddef

def MatchPattern(s: dict<any>, pattern: string): string
  EatWhitespace(s)
  if s.pos >= s.end
    return ''
  endif
  var remainder = s.text[s.pos :]
  var m = matchstr(remainder, '^\(' .. pattern .. '\)')
  if m != ''
    s.pos += strchars(m)
  endif
  return m
enddef

def MatchLiteral(s: dict<any>, ch: string): bool
  EatWhitespace(s)
  if s.pos < s.end && s.text[s.pos] == ch
    s.pos += 1
    return true
  endif
  return false
enddef

# Read a NAME token
def ReadName(s: dict<any>): string
  return MatchPattern(s, NAME_PATTERN)
enddef

# Read a NUMBER token
def ReadNumber(s: dict<any>): string
  return MatchPattern(s, '[0-9]\+')
enddef

# Parse the brace/quote-delimited string content
# Returns the text consumed (flattened).
# string_end: '}' or '"'
def ParseString(s: dict<any>, string_end: string, level: number): string
  var result = ''
  while s.pos < s.end
    var ch = s.text[s.pos]
    if string_end == '"' && ch == '"' && level == 0
      s.pos += 1
      return result
    elseif ch == '}' && level > 0
      s.pos += 1
      return result
    elseif ch == '}' && level == 0 && string_end == '}'
      s.pos += 1
      return result
    elseif ch == '{'
      s.pos += 1
      result ..= '{'
      result ..= ParseString(s, '}', level + 1)
      result ..= '}'
    else
      result ..= ch
      s.pos += 1
    endif
  endwhile
  return result
enddef

# Parse a single value part: quoted, braced, number, or macro name
def ParseValuePart(s: dict<any>): string
  EatWhitespace(s)
  if s.pos >= s.end
    return ''
  endif
  var ch = s.text[s.pos]
  if ch == '"'
    s.pos += 1
    return ParseString(s, '"', 0)
  elseif ch == '{'
    s.pos += 1
    return ParseString(s, '}', 0)
  elseif ch =~ '[0-9]'
    return ReadNumber(s)
  else
    var name = ReadName(s)
    if name == ''
      return ''
    endif
    var name_lower = tolower(name)
    if has_key(s.macros, name_lower)
      return s.macros[name_lower]
    else
      # Undefined macro — return empty string (pybtex behavior with error
      # reporting; we silently return empty)
      return ''
    endif
  endif
enddef

# Parse a full value (parts connected by '#')
def ParseValue(s: dict<any>): list<string>
  var parts: list<string> = []
  var first = true
  while true
    if !first
      if !MatchLiteral(s, '#')
        break
      endif
    endif
    var part = ParseValuePart(s)
    add(parts, part)
    first = false
  endwhile
  return parts
enddef

# Parse a command body after reading entry type and opening delimiter
def ParseCommand(s: dict<any>): any
  var name = ReadName(s)
  if name == ''
    return null
  endif

  EatWhitespace(s)
  if s.pos >= s.end
    return null
  endif

  var command_lower = tolower(name)

  # @comment — skip the command, let scanner continue finding @-entries
  if command_lower == 'comment'
    return null
  endif

  # Determine delimiter
  var ch = s.text[s.pos]
  var close_ch = ''
  if ch == '{'
    close_ch = '}'
    s.pos += 1
  elseif ch == '('
    close_ch = ')'
    s.pos += 1
  else
    return null
  endif

  if command_lower == 'string'
    var str_name = ReadName(s)
    MatchLiteral(s, '=')
    var str_value = ParseValue(s)
    s.macros[tolower(str_name)] = join(str_value, '')
    EatWhitespace(s)
    MatchLiteral(s, close_ch)
    return {'command': name, 'name': str_name, 'value': str_value}
  elseif command_lower == 'preamble'
    var val = ParseValue(s)
    EatWhitespace(s)
    MatchLiteral(s, close_ch)
    return {'command': name, 'value': val}
  else
    # Regular entry: read cite key, then fields
    EatWhitespace(s)
    var cite_key = ''
    if close_ch == ')'
      # KEY_PAREN: r'[^\s\,]+'
      cite_key = MatchPattern(s, '[^ \t\n\r,]\+')
    else
      # KEY_BRACE: r'[^\s\,}]+'
      cite_key = MatchPattern(s, '[^ \t\n\r,}]\+')
    endif

    var fields = ParseEntryFields(s)

    EatWhitespace(s)
    MatchLiteral(s, close_ch)

    return {'command': name, 'key': cite_key, 'fields': fields}
  endif
enddef

# Parse field = value pairs separated by commas
def ParseEntryFields(s: dict<any>): list<any>
  var fields: list<any> = []
  while true
    # Expect comma before each field (first comma follows cite_key)
    if !MatchLiteral(s, ',')
      break
    endif
    # Try to read a field name
    EatWhitespace(s)
    var field_name = ReadName(s)
    if field_name == ''
      # Trailing comma — acceptable
      continue
    endif
    if !MatchLiteral(s, '=')
      # No equals sign — not a real field; might be end of entry
      break
    endif
    var field_value = ParseValue(s)
    add(fields, [field_name, field_value])
  endwhile
  return fields
enddef

# Skip over a braced group (used for @comment)
def SkipBracedContent(s: dict<any>)
  var depth = 1
  while s.pos < s.end && depth > 0
    var ch = s.text[s.pos]
    if ch == '{'
      depth += 1
    elseif ch == '}'
      depth -= 1
    endif
    s.pos += 1
  endwhile
enddef

# ═══════════════════════════════════════════════════════════════════════
# Text utilities
# Matches pybtex.textutils.normalize_whitespace
# ═══════════════════════════════════════════════════════════════════════

def NormalizeWhitespace(str: string): string
  var s = substitute(str, '^\_s\+', '', '')
  s = substitute(s, '\_s\+$', '', '')
  s = substitute(s, '\_s\+', ' ', 'g')
  return s
enddef

# ═══════════════════════════════════════════════════════════════════════
# BibTeX string splitting (brace-aware)
# Matches pybtex.bibtex.utils.split_tex_string / split_name_list
# ═══════════════════════════════════════════════════════════════════════

# Find matching closing brace in string; returns [consumed, remainder]
def FindClosingBrace(str: string): list<string>
  var brace_level = 1
  var pos = 0
  while pos < strchars(str) && brace_level >= 1
    var ch = str[pos]
    if ch == '{'
      brace_level += 1
    elseif ch == '}'
      brace_level -= 1
    endif
    pos += 1
  endwhile
  # pos now points right after the closing '}'
  # Return everything up to and including the '}', and the remainder
  return [str[: pos - 1], str[pos :]]
enddef

# BIBTEX_SPACE_RE equivalent: r'(?:\\ |\s|(?<!\\)~)+'
# We split on whitespace/tilde/control-space at brace level 0
def SplitTexString(str: string, sep_pattern: string = ''): list<string>
  var use_default_sep = (sep_pattern == '')
  var result: list<string> = []
  var word_parts: list<string> = []
  var remaining = str

  while true
    # Split at first '{'
    var brace_byte_idx = stridx(remaining, '{')
    var head: string
    var brace: string

    if brace_byte_idx >= 0
      var brace_idx = charidx(remaining, brace_byte_idx)
      if brace_idx > 0
        head = remaining[: brace_idx - 1]
      else
        head = ''
      endif
      brace = '{'
      remaining = remaining[brace_idx + 1 :]
    else
      head = remaining
      brace = ''
      remaining = ''
    endif

    if head != ''
      var head_parts: list<string>
      if use_default_sep
        # BIBTEX_SPACE_RE: r'(?:\\ |\s|(?<!\\)~)+'
        # Replace "\ " (control space) and unescaped ~ with a placeholder,
        # then split on runs of whitespace/placeholder.
        head_parts = SplitBibtexSpace(head)
      else
        head_parts = SplitRegexp(head, sep_pattern)
      endif

      # Process head_parts: all but last go into completed words
      var idx = 0
      for part in head_parts
        if idx < len(head_parts) - 1
          add(result, join(word_parts, '') .. part)
          word_parts = []
        else
          add(word_parts, part)
        endif
        idx += 1
      endfor
    endif

    if brace != ''
      add(word_parts, '{')
      var r = FindClosingBrace(remaining)
      add(word_parts, r[0])
      remaining = r[1]
    else
      break
    endif
  endwhile

  if len(word_parts) > 0
    add(result, join(word_parts, ''))
  endif

  # Strip whitespace from each part
  result = mapnew(result, (_, v) => substitute(substitute(v, '^\s\+', '', ''), '\s\+$', '', ''))

  if use_default_sep
    # filter_empty when using default separator
    result = filter(result, (_, v) => v != '')
  endif

  return result
enddef

# Split string on BibTeX whitespace: \s, "\ " (control space), unescaped ~
# Returns list including empty strings at boundaries (like Python re.split)
def SplitBibtexSpace(str: string): list<string>
  var result: list<string> = []
  var current = ''
  var i = 0
  while i < strchars(str)
    var is_sep = false
    # Check for "\ " (control space: backslash followed by space)
    if str[i] == '\' && i + 1 < strchars(str) && str[i + 1] == ' '
      is_sep = true
      i += 2
    # Check for unescaped ~ (tilde not preceded by backslash)
    elseif str[i] == '~' && !(i > 0 && str[i - 1] == '\')
      is_sep = true
      i += 1
    # Check for regular whitespace
    elseif str[i] =~ '[ \t\n\r]'
      is_sep = true
      i += 1
    endif

    if is_sep
      add(result, current)
      current = ''
      # Continue consuming separator chars
      while i < strchars(str)
        if str[i] == '\' && i + 1 < strchars(str) && str[i + 1] == ' '
          i += 2
        elseif str[i] == '~' && !(i > 0 && str[i - 1] == '\')
          i += 1
        elseif str[i] =~ '[ \t\n\r]'
          i += 1
        else
          break
        endif
      endwhile
    else
      current ..= str[i]
      i += 1
    endif
  endwhile
  add(result, current)
  return result
enddef

# Split string using a Vim regex pattern (like Python re.split)
def SplitRegexp(str: string, pattern: string): list<string>
  var result: list<string> = []
  var remaining = str
  while true
    var m = matchstrpos(remaining, pattern)
    if m[1] < 0
      add(result, remaining)
      break
    endif
    # Convert byte positions from matchstrpos to character positions
    var char_start = charidx(remaining, m[1])
    var char_end = charidx(remaining, m[2])
    if char_start > 0
      add(result, remaining[: char_start - 1])
    else
      add(result, '')
    endif
    remaining = remaining[char_end :]
  endwhile
  return result
enddef

# Split name list on " and " (case insensitive), respecting braces
# Matches pybtex.bibtex.utils.split_name_list
def SplitNameList(str: string): list<string>
  return SplitTexString(str, ' \c\<and\> ')
enddef

# ═══════════════════════════════════════════════════════════════════════
# Person name parsing
# Matches pybtex.database.Person._parse_string
# ═══════════════════════════════════════════════════════════════════════

export def ParsePerson(name_str: string): dict<any>
  var p: dict<any> = {
    'first_names': [],
    'middle_names': [],
    'prelast_names': [],
    'last_names': [],
    'lineage_names': [],
  }

  var name = substitute(substitute(name_str, '^\s\+', '', ''), '\s\+$', '', '')
  if name == ''
    return p
  endif

  var parts = SplitTexString(name, ',')
  if len(parts) > 3
    # Too many commas — join extras into last part
    var last_parts = parts[2 :]
    parts = [parts[0], parts[1], join(last_parts, ' ')]
  endif

  if len(parts) == 3
    # von Last, Jr, First
    var von_last_parts = SplitTexString(parts[0])
    ProcessVonLast(p, von_last_parts)
    p.lineage_names = SplitTexString(parts[1])
    ProcessFirstMiddle(p, SplitTexString(parts[2]))
  elseif len(parts) == 2
    # von Last, First
    var von_last_parts = SplitTexString(parts[0])
    ProcessVonLast(p, von_last_parts)
    ProcessFirstMiddle(p, SplitTexString(parts[1]))
  elseif len(parts) == 1
    # First von Last
    var all_parts = SplitTexString(name)
    var split_result = SplitAtVon(all_parts)
    var first_middle: list<string> = split_result[0]
    var von_last: list<string> = split_result[1]
    if len(von_last) == 0 && len(first_middle) > 0
      add(von_last, first_middle[-1])
      first_middle = first_middle[: -2]
    endif
    ProcessFirstMiddle(p, first_middle)
    ProcessVonLast(p, von_last)
  endif

  return p
enddef

def ProcessFirstMiddle(p: dict<any>, parts: list<string>)
  if len(parts) > 0
    add(p.first_names, parts[0])
    if len(parts) > 1
      extend(p.middle_names, parts[1 :])
    endif
  endif
enddef

def ProcessVonLast(p: dict<any>, parts: list<string>)
  if len(parts) == 0
    return
  endif
  # The last element is definitely "last"
  var von_last = parts[: -2]    # everything except the last
  var definitely_not_von = [parts[-1]]

  if len(von_last) > 0
    # rsplit_at: split from the right, second part starts with
    # last element for which IsVonName is true
    var split_result = RSplitAtVon(von_last)
    extend(p.prelast_names, split_result[0])
    extend(p.last_names, split_result[1])
  endif
  extend(p.last_names, definitely_not_von)
enddef

# Split list at first element where predicate is true
# Returns [before, from_match_onwards]
def SplitAtVon(lst: list<string>): list<any>
  var i = 0
  for item in lst
    if IsVonName(item)
      if i == 0
        return [[], lst]
      endif
      return [lst[: i - 1], lst[i :]]
    endif
    i += 1
  endfor
  return [lst, []]
enddef

# Reverse split: split so that the first part includes everything up to and
# including the LAST von-name when scanning from left to right.
# Matches pybtex's rsplit_at(lst, is_von_name).
def RSplitAtVon(lst: list<string>): list<any>
  # Find the rightmost von name
  var last_von_idx = -1
  var i = 0
  for item in lst
    if IsVonName(item)
      last_von_idx = i
    endif
    i += 1
  endfor

  if last_von_idx < 0
    # No von found: everything goes to "last" part
    return [[], lst]
  endif

  # Split: everything up to and including last_von_idx goes to "von" (first),
  # rest goes to "last" (second)
  return [lst[: last_von_idx], lst[last_von_idx + 1 :]]
enddef

# Check if a name part is a "von" part (starts with lowercase)
# Matches pybtex's is_von_name logic
def IsVonName(str: string): bool
  if str == ''
    return false
  endif
  var first_ch = str[0]
  if first_ch =~ '[A-Z]'
    return false
  endif
  if first_ch =~ '[a-z]'
    return true
  endif
  # Non-letter first char: scan for first letter at brace level 0,
  # or check special char at brace level 1
  var brace_level = 0
  var i = 0
  while i < strchars(str)
    var ch = str[i]
    if ch == '{'
      brace_level += 1
      if brace_level == 1
        # Check if this is a special char (starts with \)
        if i + 1 < strchars(str) && str[i + 1] == '\'
          # Extract the content inside braces and check with
          # special_char_islower
          var content = ExtractBracedContent(str, i)
          return SpecialCharIsLower(content)
        endif
      endif
      i += 1
    elseif ch == '}'
      brace_level -= 1
      i += 1
    else
      if brace_level == 0 && ch =~ '[a-zA-Z]'
        return ch =~ '[a-z]'
      endif
      i += 1
    endif
  endwhile
  return false
enddef

# Extract content of braced group starting at position pos (which has '{')
def ExtractBracedContent(str: string, pos: number): string
  var depth = 0
  var result = ''
  var i = pos
  while i < strchars(str)
    var ch = str[i]
    if ch == '{'
      depth += 1
      if depth > 1
        result ..= ch
      endif
    elseif ch == '}'
      depth -= 1
      if depth == 0
        return result
      endif
      result ..= ch
    else
      result ..= ch
    endif
    i += 1
  endwhile
  return result
enddef

# Check if a special character (content after \) represents a lowercase letter
# Matches pybtex's special_char_islower
def SpecialCharIsLower(special_char: string): bool
  if strchars(special_char) < 2 || special_char[0] != '\'
    return false
  endif
  var control_sequence = true
  var i = 1   # skip the backslash
  while i < strchars(special_char)
    var ch = special_char[i]
    if control_sequence
      if ch !~ '[a-zA-Z]'
        control_sequence = false
      endif
    else
      if ch =~ '[a-zA-Z]'
        return ch =~ '[a-z]'
      endif
    endif
    i += 1
  endwhile
  return false
enddef

# ═══════════════════════════════════════════════════════════════════════
# Case-insensitive lookup helpers
# ═══════════════════════════════════════════════════════════════════════

# Get entry by case-insensitive key
export def GetEntry(bib: dict<any>, key: string): any
  var key_lower = tolower(key)
  for [k, v] in items(bib.entries)
    if tolower(k) == key_lower
      return v
    endif
  endfor
  return null
enddef

# Get field by case-insensitive name from an entry
export def GetField(entry: dict<any>, name: string): string
  var name_lower = tolower(name)
  for [k, v] in items(entry.fields)
    if tolower(k) == name_lower
      return v
    endif
  endfor
  # Check person fields
  for [k, persons] in items(entry.persons)
    if tolower(k) == name_lower
      return join(mapnew(persons, (_, p) => PersonToString(p)), ' and ')
    endif
  endfor
  return ''
enddef

# Get persons by case-insensitive role name
export def GetPersons(entry: dict<any>, role: string): list<any>
  var role_lower = tolower(role)
  for [k, v] in items(entry.persons)
    if tolower(k) == role_lower
      return v
    endif
  endfor
  return []
enddef
