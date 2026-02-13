#!/usr/bin/env python3
"""Generate reference JSON from pybtex for .bib file parsing.

Parses each .bib file with pybtex and writes a JSON file matching the
structure returned by bibtex.vim's ParseBibFile / ParseBibString:

    {
        "preamble": str,
        "preamble_list": [str, ...],
        "entries": {
            "cite_key": {
                "type": str,
                "fields": {"name": "value", ...},
                "persons": {
                    "role": [
                        {
                            "first_names": [...],
                            "middle_names": [...],
                            "prelast_names": [...],
                            "last_names": [...],
                            "lineage_names": [...]
                        },
                        ...
                    ]
                }
            },
            ...
        }
    }

Also generates reference JSON for the inline test strings from
bibtex_parser_test.py.
"""

from __future__ import annotations

import json
from collections import OrderedDict
from pathlib import Path

from pybtex.database import BibliographyData, Entry, Person
from pybtex.database.input.bibtex import Parser


class _SilentParser(Parser):
    """Parser subclass that collects errors instead of raising."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.errors = []

    def handle_error(self, error):
        self.errors.append(error)


def person_to_dict(p: Person) -> dict:
    """Convert a pybtex Person to a dict matching vim9 Person structure."""
    return OrderedDict([
        ("first_names", list(p.first_names)),
        ("middle_names", list(p.middle_names)),
        ("prelast_names", list(p.prelast_names)),
        ("last_names", list(p.last_names)),
        ("lineage_names", list(p.lineage_names)),
    ])


def entry_to_dict(entry: Entry) -> dict:
    """Convert a pybtex Entry to a dict matching vim9 Entry structure."""
    fields = OrderedDict()
    for name, value in entry.fields.items():
        fields[name] = value

    persons = OrderedDict()
    for role, person_list in entry.persons.items():
        persons[role] = [person_to_dict(p) for p in person_list]

    return OrderedDict([
        ("type", entry.type),
        ("fields", fields),
        ("persons", persons),
    ])


def bib_data_to_dict(data: BibliographyData) -> dict:
    """Convert pybtex BibliographyData to a dict matching vim9 output."""
    entries = OrderedDict()
    for key, entry in data.entries.items():
        entries[key] = entry_to_dict(entry)

    # pybtex stores preamble as a list internally
    preamble_list = list(data._preamble)  # noqa: SLF001
    preamble = "".join(preamble_list)

    return OrderedDict([
        ("preamble", preamble),
        ("preamble_list", preamble_list),
        ("entries", entries),
    ])


def parse_bib_file(path: str) -> dict:
    """Parse a .bib file with pybtex and return the reference dict."""
    parser = _SilentParser(encoding="UTF-8")
    data = parser.parse_file(path)
    return bib_data_to_dict(data)


def parse_bib_string(text: str) -> dict:
    """Parse a BibTeX string with pybtex and return the reference dict."""
    parser = _SilentParser(encoding="UTF-8")
    parser.parse_string(text)
    return bib_data_to_dict(parser.data)


def parse_bib_strings(texts: list[str]) -> dict:
    """Parse multiple BibTeX strings (accumulated) and return the reference dict."""
    parser = _SilentParser(encoding="UTF-8")
    for text in texts:
        parser.parse_string(text)
    return bib_data_to_dict(parser.data)


# ── Inline test cases from bibtex_parser_test.py ──────────────────────

INLINE_TESTS = OrderedDict()

INLINE_TESTS["empty_data"] = {
    "input_strings": [""],
}

INLINE_TESTS["braces"] = {
    "input_strings": [
        """@ARTICLE{
                test,
                title={Polluted
                    with {DDT}.
            },
    }"""
    ],
}

INLINE_TESTS["braces_and_quotes"] = {
    "input_strings": [
        u'''@ARTICLE{
                test,
                title="Nested braces  and {"quotes"}",
        }'''
    ],
}

INLINE_TESTS["entry_in_string"] = {
    "input_strings": [
        """
        @article{Me2010, author="Brett, Matthew", title="An article
        @article{something, author={Name, Another}, title={not really an article}}
        "}
        @article{Me2009,author={Nom de Plume, My}, title="A short story"}
    """
    ],
}

INLINE_TESTS["entry_in_comment"] = {
    "input_strings": [
        """
        Both the articles register despite the comment block
        @Comment{
        @article{Me2010, title="An article"}
        @article{Me2009, title="A short story"}
        }
        These all work OK without errors
        @Comment{and more stuff}

        Last article to show we can get here
        @article{Me2011, }
    """
    ],
}

INLINE_TESTS["at_test"] = {
    "input_strings": [
        """
        The @ here parses fine in both cases
        @article{Me2010,
            title={An @tey article}}
        @article{Me2009, title="A @tey short story"}
    """
    ],
}

INLINE_TESTS["entry_types"] = {
    "input_strings": [
        """
        Testing what are allowed for entry types

        These are OK
        @somename{an_id,}
        @t2{another_id,}
        @t@{again_id,}
        @t+{aa1_id,}
        @_t{aa2_id,}

        These ones not
        @2thou{further_id,}
        @some name{id3,}
        @some#{id4,}
        @some%{id4,}
    """
    ],
}

INLINE_TESTS["field_names"] = {
    "input_strings": [
        """
        Check for characters allowed in field names
        Here the cite key is fine, but the field name is not allowed:
        ``You are missing a field name``
        @article{2010, 0author="Me"}

        Underscores allowed (no error)
        @article{2011, _author="Me"}

        Not so for spaces obviously (``expecting an '='``)
        @article{2012, author name = "Myself"}

        Or hashes (``missing a field name``)
        @article{2013, #name = "Myself"}

        But field names can start with +-.
        @article{2014, .name = "Myself"}
        @article{2015, +name = "Myself"}
        @article{2016, -name = "Myself"}
        @article{2017, @name = "Myself"}
    """
    ],
}

INLINE_TESTS["inline_comment"] = {
    "input_strings": [
        """
        "some text" causes an error like this
        ``You're missing a field name---line 6 of file bibs/inline_comment.bib``
        for all 3 of the % some text occurences below; in each case the parser keeps
        what it has up till that point and skips, so that it correctly gets the last
        entry.
        @article{Me2010,}
        @article{Me2011,
            author="Brett-like, Matthew",
        % some text
            title="Another article"}
        @article{Me2012, % some text
            author="Real Brett"}
        This one correctly read
        @article{Me2013,}
    """
    ],
}

INLINE_TESTS["simple_entry"] = {
    "input_strings": [
        """
        % maybe the simplest possible
        % just a comment and one reference

        @ARTICLE{Brett2002marsbar,
        author = {Matthew Brett and Jean-Luc Anton and Romain Valabregue and Jean-Baptise
            Poline},
        title = {{Region of interest analysis using an SPM toolbox}},
        journal = {Neuroimage},
        institution = {},
        year = {2002},
        volume = {16},
        pages = {1140--1141},
        number = {2}
        }
    """
    ],
}

INLINE_TESTS["key_parsing"] = {
    "input_strings": [
        """
        # will not work as expected
        @article(test(parens1))

        # works fine
        @article(test(parens2),)

        # works fine
        @article{test(braces1)}

        # also works
        @article{test(braces2),}
    """
    ],
}

INLINE_TESTS["macros"] = {
    "input_strings": [
        """
        @String{and = { and }}
        @String{etal = and # { {et al.}}}
        @Article(
            unknown,
            author = nobody,
        )
        @Article(
            gsl,
            author = "Gough, Brian"#etal,
        )
    """
    ],
}

INLINE_TESTS["cross_file_macros"] = {
    "input_strings": [
        '@string{jackie = "Jackie Chan"}',
        """,
            @Book{
                i_am_jackie,
                author = jackie,
                title = "I Am " # jackie # ": My Life in Action",
            }
        """,
    ],
}

INLINE_TESTS["at_character"] = {
    "input_strings": [
        r""",
            @proceedings{acc,
                title = {Proc.\@ of the American Control Conference},
                notes = "acc@example.org"
            }
        """,
    ],
}

INLINE_TESTS["case_sensitivity"] = {
    "input_strings": [
        r""",
            @Article{CamelCase,
                Title = {To CamelCase or Under score},
                year = 2009,
                NOTES = "none"
            }
        """,
    ],
}

INLINE_TESTS["duplicate_field"] = {
    "input_strings": [
        r"""
            @MASTERSTHESIS{
                Mastering,
                year = 1364,
                title = "Mastering Thesis Writing",
                school = "Charles University in Prague",
                TITLE = "No One Reads Master's Theses Anyway LOL",
                TiTlE = "Well seriously, lol.",
            }
        """
    ],
}

INLINE_TESTS["duplicate_person_field"] = {
    "input_strings": [
        """
        @article{Me2009,author={Nom de Plume, My}, title="A short story", AUTHoR = {Foo}}
    """
    ],
}


def generate_inline_references(out_dir: Path) -> None:
    """Generate JSON for each inline test case."""
    for name, spec in INLINE_TESTS.items():
        texts = spec["input_strings"]
        result = parse_bib_strings(texts)
        out_path = out_dir / f"ref_{name}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f"  {out_path.name}")


def generate_file_references(data_dir: Path, out_dir: Path) -> None:
    """Generate JSON for each .bib file in data_dir."""
    for bib_path in sorted(data_dir.glob("*.bib")):
        result = parse_bib_file(str(bib_path))
        out_path = out_dir / f"ref_{bib_path.stem}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f"  {out_path.name}")


def main() -> None:
    tests_dir = Path(__file__).parent
    data_dir = tests_dir / "data"
    ref_dir = tests_dir / "reference"
    ref_dir.mkdir(exist_ok=True)

    print("Generating .bib file references:")
    generate_file_references(data_dir, ref_dir)

    print("Generating inline test references:")
    generate_inline_references(ref_dir)

    print("Done.")


if __name__ == "__main__":
    main()
