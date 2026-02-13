#!/usr/bin/env python3
"""Generate reference JSON from pybtex for person name parsing.

Parses each name string with pybtex.database.Person and writes a JSON
file with the expected results, matching the structure returned by
bibtex.vim's ParsePerson:

    [
        {
            "input": "name string",
            "first_names": [...],
            "middle_names": [...],
            "prelast_names": [...],
            "last_names": [...],
            "lineage_names": [...]
        },
        ...
    ]

The sample_names list is taken directly from parse_name_test.py.
"""

from __future__ import annotations

import json
from collections import OrderedDict
from pathlib import Path

from pybtex import errors
from pybtex.database import Person


# Copied from parse_name_test.py — (input, (first, prelast, last, lineage), errors)
sample_names = [
    ('A. E.                   Siegman', (['A.', 'E.'], [], ['Siegman'], []), None),
    ('A. G. W. Cameron', (['A.', 'G.', 'W.'], [], ['Cameron'], []), None),
    ('A. Hoenig', (['A.'], [], ['Hoenig'], []), None),
    ('A. J. Van Haagen', (['A.', 'J.', 'Van'], [], ['Haagen'], []), None),
    ('A. S. Berdnikov', (['A.', 'S.'], [], ['Berdnikov'], []), None),
    ('A. Trevorrow', (['A.'], [], ['Trevorrow'], []), None),
    ('Adam H. Lewenberg', (['Adam', 'H.'], [], ['Lewenberg'], []), None),
    ('Addison-Wesley Publishing Company',
     (['Addison-Wesley', 'Publishing'], [], ['Company'], []), None),
    ('Advogato (Raph Levien)', (['Advogato', '(Raph'], [], ['Levien)'], []), None),
    ('Andrea de Leeuw van Weenen',
     (['Andrea'], ['de', 'Leeuw', 'van'], ['Weenen'], []), None),
    ('Andreas Geyer-Schulz', (['Andreas'], [], ['Geyer-Schulz'], []), None),
    ("Andr{\\'e} Heck", (["Andr{\\'e}"], [], ['Heck'], []), None),
    ('Anne Br{\\"u}ggemann-Klein', (['Anne'], [], ['Br{\\"u}ggemann-Klein'], []), None),
    ('Anonymous', ([], [], ['Anonymous'], []), None),
    ('B. Beeton', (['B.'], [], ['Beeton'], []), None),
    ('B. Hamilton Kelly', (['B.', 'Hamilton'], [], ['Kelly'], []), None),
    ('B. V. Venkata Krishna Sastry',
     (['B.', 'V.', 'Venkata', 'Krishna'], [], ['Sastry'], []), None),
    ('Benedict L{\\o}fstedt', (['Benedict'], [], ['L{\\o}fstedt'], []), None),
    ('Bogus{\\l}aw Jackowski', (['Bogus{\\l}aw'], [], ['Jackowski'], []), None),
    ('Christina A. L.\\ Thiele',
     (['Christina', 'A.', 'L.'], [], ['Thiele'], []), None),
    ("D. Men'shikov", (['D.'], [], ["Men'shikov"], []), None),
    ("Darko \\v{Z}ubrini{\\'c}", (['Darko'], [], ["\\v{Z}ubrini{\\'c}"], []), None),
    ("Dunja Mladeni{\\'c}", (['Dunja'], [], ["Mladeni{\\'c}"], []), None),
    ('Edwin V. {Bell, II}', (['Edwin', 'V.'], [], ['{Bell, II}'], []), None),
    ('Frank G. {Bennett, Jr.}', (['Frank', 'G.'], [], ['{Bennett, Jr.}'], []), None),
    ("Fr{\\'e}d{\\'e}ric Boulanger",
     (["Fr{\\'e}d{\\'e}ric"], [], ['Boulanger'], []), None),
    ('Ford, Jr., Henry', (['Henry'], [], ['Ford'], ['Jr.']), None),
    ('mr Ford, Jr., Henry', (['Henry'], ['mr'], ['Ford'], ['Jr.']), None),
    ('Fukui Rei', (['Fukui'], [], ['Rei'], []), None),
    ('G. Gr{\\"a}tzer', (['G.'], [], ['Gr{\\"a}tzer'], []), None),
    ('George Gr{\\"a}tzer', (['George'], [], ['Gr{\\"a}tzer'], []), None),
    ('Georgia K. M. Tobin', (['Georgia', 'K.', 'M.'], [], ['Tobin'], []), None),
    ('Gilbert van den Dobbelsteen',
     (['Gilbert'], ['van', 'den'], ['Dobbelsteen'], []), None),
    ('Gy{\\"o}ngyi Bujdos{\\\'o}', (['Gy{\\"o}ngyi'], [], ["Bujdos{\\'o}"], []), None),
    ('Helmut J{\\"u}rgensen', (['Helmut'], [], ['J{\\"u}rgensen'], []), None),
    ('Herbert Vo{\\ss}', (['Herbert'], [], ['Vo{\\ss}'], []), None),
    ("H{\\'a}n Th{\\^e}\\llap{\\raise 0.5ex\\hbox{\\'{\\relax}}}                  Th{\\'a}nh",
     (["H{\\'a}n", "Th{\\^e}\\llap{\\raise 0.5ex\\hbox{\\'{\\relax}}}"],
      [], ["Th{\\'a}nh"], []), None),
    ("H{\\`a}n Th\\^e\\llap{\\raise0.5ex\\hbox{\\'{\\relax}}}                  Th{\\`a}nh",
     (['H{\\`a}n', "Th\\^e\\llap{\\raise0.5ex\\hbox{\\'{\\relax}}}"],
      [], ['Th{\\`a}nh'], []), None),
    ("J. Vesel{\\'y}", (['J.'], [], ["Vesel{\\'y}"], []), None),
    ("Javier Rodr\\'{\\i}guez Laguna",
     (['Javier', "Rodr\\'{\\i}guez"], [], ['Laguna'], []), None),
    ("Ji\\v{r}\\'{\\i} Vesel{\\'y}",
     (["Ji\\v{r}\\'{\\i}"], [], ["Vesel{\\'y}"], []), None),
    ("Ji\\v{r}\\'{\\i} Zlatu{\\v{s}}ka",
     (["Ji\\v{r}\\'{\\i}"], [], ['Zlatu{\\v{s}}ka'], []), None),
    ("Ji\\v{r}{\\'\\i} Vesel{\\'y}",
     (["Ji\\v{r}{\\'\\i}"], [], ["Vesel{\\'y}"], []), None),
    ("Ji\\v{r}{\\'{\\i}}Zlatu{\\v{s}}ka",
     ([], [], ["Ji\\v{r}{\\'{\\i}}Zlatu{\\v{s}}ka"], []), None),
    ('Jim Hef{}feron', (['Jim'], [], ['Hef{}feron'], []), None),
    ('J{\\"o}rg Knappen', (['J{\\"o}rg'], [], ['Knappen'], []), None),
    ('J{\\"o}rgen L. Pind', (['J{\\"o}rgen', 'L.'], [], ['Pind'], []), None),
    ("J{\\'e}r\\^ome Laurens", (["J{\\'e}r\\^ome"], [], ['Laurens'], []), None),
    ('J{{\\"o}}rg Knappen', (['J{{\\"o}}rg'], [], ['Knappen'], []), None),
    ('K. Anil Kumar', (['K.', 'Anil'], [], ['Kumar'], []), None),
    ("Karel Hor{\\'a}k", (['Karel'], [], ["Hor{\\'a}k"], []), None),
    ("Karel P\\'{\\i}{\\v{s}}ka", (['Karel'], [], ["P\\'{\\i}{\\v{s}}ka"], []), None),
    ("Karel P{\\'\\i}{\\v{s}}ka", (['Karel'], [], ["P{\\'\\i}{\\v{s}}ka"], []), None),
    ("Karel Skoup\\'{y}", (['Karel'], [], ["Skoup\\'{y}"], []), None),
    ("Karel Skoup{\\'y}", (['Karel'], [], ["Skoup{\\'y}"], []), None),
    ('Kent McPherson', (['Kent'], [], ['McPherson'], []), None),
    ('Klaus H{\\"o}ppner', (['Klaus'], [], ['H{\\"o}ppner'], []), None),
    ('Lars Hellstr{\\"o}m', (['Lars'], [], ['Hellstr{\\"o}m'], []), None),
    ('Laura Elizabeth Jackson',
     (['Laura', 'Elizabeth'], [], ['Jackson'], []), None),
    ("M. D{\\'{\\i}}az", (['M.'], [], ["D{\\'{\\i}}az"], []), None),
    ('M/iche/al /O Searc/oid', (['M/iche/al', '/O'], [], ['Searc/oid'], []), None),
    ("Marek Ry{\\'c}ko", (['Marek'], [], ["Ry{\\'c}ko"], []), None),
    ('Marina Yu. Nikulina', (['Marina', 'Yu.'], [], ['Nikulina'], []), None),
    ("Max D{\\'{\\i}}az", (['Max'], [], ["D{\\'{\\i}}az"], []), None),
    ('Merry Obrecht Sawdey', (['Merry', 'Obrecht'], [], ['Sawdey'], []), None),
    ("Miroslava Mis{\\'a}kov{\\'a}",
     (['Miroslava'], [], ["Mis{\\'a}kov{\\'a}"], []), None),
    ('N. A. F. M. Poppelier', (['N.', 'A.', 'F.', 'M.'], [], ['Poppelier'], []), None),
    ('Nico A. F. M. Poppelier',
     (['Nico', 'A.', 'F.', 'M.'], [], ['Poppelier'], []), None),
    ('Onofrio de Bari', (['Onofrio'], ['de'], ['Bari'], []), None),
    ("Pablo Rosell-Gonz{\\'a}lez", (['Pablo'], [], ["Rosell-Gonz{\\'a}lez"], []), None),
    ('Paco La                  Bruna', (['Paco', 'La'], [], ['Bruna'], []), None),
    ('Paul                  Franchi-Zannettacci',
     (['Paul'], [], ['Franchi-Zannettacci'], []), None),
    ('Pavel \\v{S}eve\\v{c}ek', (['Pavel'], [], ['\\v{S}eve\\v{c}ek'], []), None),
    ('Petr Ol{\\v{s}}ak', (['Petr'], [], ['Ol{\\v{s}}ak'], []), None),
    ("Petr Ol{\\v{s}}{\\'a}k", (['Petr'], [], ["Ol{\\v{s}}{\\'a}k"], []), None),
    ('Primo\\v{z} Peterlin', (['Primo\\v{z}'], [], ['Peterlin'], []), None),
    ('Prof. Alban Grimm', (['Prof.', 'Alban'], [], ['Grimm'], []), None),
    ("P{\\'e}ter Husz{\\'a}r", (["P{\\'e}ter"], [], ["Husz{\\'a}r"], []), None),
    ("P{\\'e}ter Szab{\\'o}", (["P{\\'e}ter"], [], ["Szab{\\'o}"], []), None),
    ('Rafa{\\l}\\.Zbikowski', ([], [], ['Rafa{\\l}\\.Zbikowski'], []), None),
    ('Rainer Sch{\\"o}pf', (['Rainer'], [], ['Sch{\\"o}pf'], []), None),
    ('T. L. (Frank) Pappas', (['T.', 'L.', '(Frank)'], [], ['Pappas'], []), None),
    ('TUG 2004 conference', (['TUG', '2004'], [], ['conference'], []), None),
    ('TUG {\\sltt DVI} Driver Standards Committee',
     (['TUG', '{\\sltt DVI}', 'Driver', 'Standards'], [], ['Committee'], []), None),
    ('TUG {\\sltt xDVIx} Driver Standards Committee',
     (['TUG'], ['{\\sltt xDVIx}'], ['Driver', 'Standards', 'Committee'], []), None),
    ('University of M{\\"u}nster',
     (['University'], ['of'], ['M{\\"u}nster'], []), None),
    ('Walter van der Laan', (['Walter'], ['van', 'der'], ['Laan'], []), None),
    ('Wendy G.                  McKay', (['Wendy', 'G.'], [], ['McKay'], []), None),
    ('Wendy McKay', (['Wendy'], [], ['McKay'], []), None),
    ('W{\\l}odek Bzyl', (['W{\\l}odek'], [], ['Bzyl'], []), None),
    ('\\LaTeX Project Team', (['\\LaTeX', 'Project'], [], ['Team'], []), None),
    ('\\rlap{Lutz Birkhahn}', ([], [], ['\\rlap{Lutz Birkhahn}'], []), None),
    ('{Jim Hef{}feron}', ([], [], ['{Jim Hef{}feron}'], []), None),
    ('{Kristoffer H\\o{}gsbro Rose}',
     ([], [], ['{Kristoffer H\\o{}gsbro Rose}'], []), None),
    ('{TUG} {Working} {Group} on a {\\TeX} {Directory}                  {Structure}',
     (['{TUG}', '{Working}', '{Group}'],
      ['on', 'a'],
      ['{\\TeX}', '{Directory}', '{Structure}'],
      []), None),
    ('{The \\TUB{} Team}', ([], [], ['{The \\TUB{} Team}'], []), None),
    ('{\\LaTeX} project team', (['{\\LaTeX}'], ['project'], ['team'], []), None),
    ('{\\NTG{} \\TeX{} future working group}',
     ([], [], ['{\\NTG{} \\TeX{} future working group}'], []), None),
    ('{{\\LaTeX\\,3} Project Team}',
     ([], [], ['{{\\LaTeX\\,3} Project Team}'], []), None),
    ('Johansen Kyle, Derik Mamania M.',
     (['Derik', 'Mamania', 'M.'], [], ['Johansen', 'Kyle'], []), None),
    ("Johannes Adam Ferdinand Alois Josef Maria Marko d'Aviano "
     'Pius von und zu Liechtenstein',
     (['Johannes', 'Adam', 'Ferdinand', 'Alois', 'Josef', 'Maria', 'Marko'],
      ["d'Aviano", 'Pius', 'von', 'und', 'zu'], ['Liechtenstein'], []), None),
    (r'Brand\~{a}o, F', (['F'], [], [r'Brand\~{a}o'], []), None),
    ('Chong, B. M., Specia, L., & Mitkov, R.',
     (['Specia', 'L.', '&', 'Mitkov', 'R.'], [], ['Chong'], ['B.', 'M.']),
     "error"),
    ('LeCun, Y. ,      Bottou,   L . , Bengio, Y. ,  Haffner ,  P',
     (['Bottou', 'L', '.', 'Bengio', 'Y.', 'Haffner', 'P'], [], ['LeCun'], ['Y.']),
     "error"),
]


def parse_name(name_str: str) -> dict:
    """Parse a name string with pybtex and return the reference dict."""
    with errors.capture():
        person = Person(name_str)

    return OrderedDict([
        ("input", name_str),
        ("first_names", list(person.first_names)),
        ("middle_names", list(person.middle_names)),
        ("prelast_names", list(person.prelast_names)),
        ("last_names", list(person.last_names)),
        ("lineage_names", list(person.lineage_names)),
    ])


def main() -> None:
    tests_dir = Path(__file__).parent
    ref_dir = tests_dir / "reference"
    ref_dir.mkdir(exist_ok=True)

    results = []
    for name_str, _expected, _errs in sample_names:
        result = parse_name(name_str)
        results.append(result)

    out_path = ref_dir / "ref_names.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"Generated {len(results)} name references -> {out_path}")


if __name__ == "__main__":
    main()
