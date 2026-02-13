vim9script

# Test harness for bibtex.vim (vim-rr edition)
# Reads manifest.json, runs tests, writes output JSON files.
# Invoked by run_bibtex_tests.py — not part of run_tests.vim framework.

import '../R/bibtex.vim' as bibtex

var manifest_path = expand('<sfile>:p:h') .. '/manifest.json'
var manifest_text = join(readfile(manifest_path), "\n")
var manifest = json_decode(manifest_text)

var output_dir: string = manifest.output_dir

# Ensure output directory exists
if !isdirectory(output_dir)
  mkdir(output_dir, 'p')
endif

# Run bib-file tests
if has_key(manifest, 'bib_file_tests')
  for test in manifest.bib_file_tests
    var result = bibtex.ParseBibFile(test.bib_path)
    var json_str = json_encode(result)
    writefile([json_str], output_dir .. '/' .. test.output_name)
  endfor
endif

# Run inline-string tests
if has_key(manifest, 'inline_tests')
  for test in manifest.inline_tests
    # Concatenate all input strings and parse as one (macros carry over)
    var combined: string = join(test.input_strings, '')
    var result = bibtex.ParseBibString(combined)
    var json_str = json_encode(result)
    writefile([json_str], output_dir .. '/' .. test.output_name)
  endfor
endif

# Run name tests
if has_key(manifest, 'name_tests')
  var name_results: list<any> = []
  for test in manifest.name_tests
    var parsed = bibtex.ParsePerson(test.input)
    var entry: dict<any> = {
      'input': test.input,
      'first_names': parsed.first_names,
      'middle_names': parsed.middle_names,
      'prelast_names': parsed.prelast_names,
      'last_names': parsed.last_names,
      'lineage_names': parsed.lineage_names,
    }
    add(name_results, entry)
  endfor
  var json_str = json_encode(name_results)
  writefile([json_str], output_dir .. '/ref_names.json')
endif

qa!
