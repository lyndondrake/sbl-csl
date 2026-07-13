"""Tests exercising sbl-filter.lua + ld-author-index.lua against a CSL JSON
fixture hand-crafted to mirror the exact output shape of ld-agent's
CSLJSONExporter (~/repo/project/ld-agent,
Packages/LDAgentKit/Sources/LDAgentKit/Bibliography/CSLJSONExporter.swift).

No built ld-agent binary/CLI exists at the time this module was written, so
the fixture (tests/fixtures/exporter-shape.json) was constructed by hand,
entry by entry, by tracing CSLJSONExporter.swift's algorithm: pretty-printed
JSON array with alphabetically sorted keys (JSONSerialization
[.prettyPrinted, .sortedKeys]); "id"/"citation-key" pairs; name dictionaries
with family/given/suffix/dropping-particle/non-dropping-particle or
{"literal": ...}; date-parts date objects; "archive_location" (underscore);
and the "note" field's `sbl:` YAML block built line-by-line by
buildSBLNote()/appendIfNonNil() (2-space-indented "key: value" lines,
double-quoted iff the value contains one of : [ , " ', with embedded double
quotes backslash-escaped; a standalone "  skipbib: true" line; a
"  options: [...]" line; and a four/six-space-indented "  related:" list).

This fixture MUST be regenerated or verified against real `ld-agent bib
export` output once that CLI command gains key-scoped export -- it is
presently a best-effort mirror of the exporter source, not a captured
sample.

Field values for the HALOT/COS-chain entries are drawn from the real
sbl:-note shapes recorded in the thesis-monograph repo's
tests/gold/monograph-gold.json (entries "HALOT", "COS", "COS1",
"COS2.27"), adjusted only where CSLJSONExporter's current SBLMetadata model
cannot produce a field that legacy data happens to carry (see
test_cos_chain_parent_omits_unsupported_source_type below).
"""

import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
FIXTURE = ROOT / 'tests' / 'fixtures' / 'exporter-shape.json'
CSL = ROOT / 'society-of-biblical-literature-fullnote-bibliography.csl'
SBL_FILTER = ROOT / 'sbl-filter.lua'
AUTHOR_INDEX_FILTER = ROOT / 'ld-author-index.lua'

DOC = """---
bibliography: {bib}
---

A plain book citation.[@clines-1981-nehemiah-memoir]

A shorthand-bearing reference work, cited twice.[@HALOT] Again.[@HALOT]

An ancient text with an annote, cited twice (first / subsequent
form).[@COS1.26] And again.[@COS1.26]

A quoting-edge ancient text, cited twice.[@COS3.115] And again.[@COS3.115]

An unknown-keys entry.[@brown-2005-example-article]

The collection cited directly.[@COS]

A von Rad citation.[@rad-1966-hexateuch-problem]

# Abbreviations {{#sbl-abbreviations}}

# Author Index {{#author-index}}

# Bibliography
"""


def run_pandoc(extra_filters: list[Path] | None = None, extra_args: list[str] | None = None) -> subprocess.CompletedProcess:
    filters = [SBL_FILTER, AUTHOR_INDEX_FILTER]
    if extra_filters:
        filters = extra_filters
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(DOC.format(bib=FIXTURE))
        input_file = f.name
    try:
        cmd = [
            'pandoc',
            '--from=markdown',
            '--to=html',
            '--wrap=none',
            '--citeproc',
            f'--csl={CSL}',
        ]
        for filt in filters:
            cmd.append(f'--lua-filter={filt}')
        if extra_args:
            cmd.extend(extra_args)
        cmd.append(input_file)
        return subprocess.run(cmd, capture_output=True, text=True)
    finally:
        Path(input_file).unlink()


def run_pandoc_html() -> str:
    result = run_pandoc()
    if result.returncode != 0:
        pytest.fail(f'pandoc failed: {result.stderr}')
    return result.stdout


def test_full_filter_stack_runs_cleanly():
    """pandoc + the full filter stack (sbl-filter, ld-author-index) runs to
    completion on the exporter-shape fixture with exit 0 and no filter
    errors on stderr."""
    result = run_pandoc()
    assert result.returncode == 0, f'pandoc failed: {result.stderr}'
    assert 'sbl-filter' not in result.stderr
    assert 'lua' not in result.stderr.lower() or 'error' not in result.stderr.lower()


def test_shorthand_entry_renders_and_is_dropped_from_bibliography():
    """HALOT (shorthand + skipbib, no skipbiblist) renders as the bare
    shorthand at first citation, and does not appear in the rendered
    #refs bibliography div (it is dropped to the abbreviation list)."""
    html = run_pandoc_html()
    assert 'HALOT' in html
    # The bibliography div itself must not carry a ref-HALOT entry.
    assert 'id="ref-HALOT"' not in html
    # The full title may appear in the abbreviation list, but the footnotes
    # must carry only the shorthand — the full title appearing there would
    # mean shorthand substitution silently failed.
    footnotes = html.split('id="footnotes"')[1] if 'id="footnotes"' in html else ''
    assert footnotes, 'no footnotes section rendered'
    assert 'The Hebrew and Aramaic Lexicon' not in footnotes.split('id="refs"')[0]


def test_skipbib_ancient_text_cites_via_annote_then_subsequent_annote():
    """COS1.26 (skipbib: true, entrysubtype: inancientcollection) renders
    its top-level CSL annote text on first citation, and the sbl
    subsequent_annote text on the second citation; it never appears in the
    rendered bibliography."""
    html = run_pandoc_html()
    # First citation: the CSL annote text (only it contains the subtitle).
    assert '(The Book of Balaam' in html
    # Second citation: the sbl subsequent_annote (only it uses the
    # single-quoted short form).
    assert '‘Deir ʿAlla Plaster Inscriptions’,' in html
    assert 'id="ref-COS1.26"' not in html


def test_abbreviations_list_contains_shorthand_and_sigla_definition():
    """With a `# Abbreviations {#sbl-abbreviations}` header in the document,
    the generated abbreviation list contains both the HALOT shorthand
    (a bibliography-style shorthand entry) and the sigla definition
    ("genitive") from the abbreviation_type: sigla entry."""
    html = run_pandoc_html()
    assert 'HALOT' in html
    assert 'genitive' in html


def test_unknown_sbl_keys_are_inert():
    """The entry whose sbl: note carries xref, sortkey, bibNote, and a
    related: list renders as a normal citation, none of those raw YAML
    fragments leak into the HTML output, and — critically — the related
    item's nested `options: [skipbib]` line does NOT flatten into the
    parent entry's own flags (regression test for the parse_sbl_note
    indent-scoping fix): the entry must still appear in the bibliography."""
    html = run_pandoc_html()
    assert 'An Example Article for Unknown-Key Testing' in html or 'Brown' in html
    assert 'sortkey' not in html
    assert 'bibNote' not in html
    assert 'related:' not in html
    # A leaked nested skipbib would silently drop this entry from #refs.
    assert 'id="ref-brown-2005-example-article"' in html


def test_author_index_demotes_non_dropping_particle():
    """The von Rad author (non-dropping-particle: von) indexes as
    'Rad, Gerhard von', matching the convention in test_author_index.py."""
    html = run_pandoc_html()
    assert 'Rad, Gerhard von' in html
    assert 'von Rad, Gerhard' not in html


def test_citation_key_field_is_inert():
    """The redundant "citation-key" field (identical to "id" on every
    fixture entry) has no rendering effect: the literal string
    "citation-key" never appears in filter output."""
    html = run_pandoc_html()
    assert 'citation-key' not in html


def test_quoting_edge_embedded_double_quote_round_trips_cleanly():
    """COS3.115's subsequent_annote contains an embedded double-quoted
    phrase plus a colon and comma, forcing CSLJSONExporter's quote-wrap +
    backslash-escape path (`appendIfNonNil()` escapes " as \\").
    parse_sbl_note() must strip the outer quote pair AND undo the YAML
    double-quoted-style escapes, so the phrase renders with clean quote
    marks and no literal backslashes."""
    html = run_pandoc_html()
    assert '"A Boundary Stone Inscription"' in html
    assert '\\"' not in html


def test_place_suppression_survives_link_citations():
    """With link-citations: true (as real book builds set), citeproc wraps
    each rendered note citation in a Link. suppress_location_in_bib must
    descend into the wrapper — the walk previously saw only top-level
    Str/Space inlines and silently no-opped, leaving post-1900 places in
    every footnote of a link-citations build."""
    result = run_pandoc(extra_args=['--metadata=link-citations:true'])
    assert result.returncode == 0, f'pandoc failed: {result.stderr}'
    html = result.stdout
    assert 'id="footnotes"' in html, 'no footnotes section rendered'
    footnotes = html.split('id="footnotes"')[1]
    # clines-1981 (Sheffield: JSOT Press, 1981) is post-1900: the place must
    # be suppressed inside the link-wrapped citation, keeping the publisher.
    assert '(JSOT Press, 1981)' in footnotes
    assert 'Sheffield' not in footnotes


def test_maintitle_italics_survive_link_citations():
    """Mirror of the place-suppression regression: italicise_maintitle must
    also descend into the Link wrapper that link-citations: true adds.
    Uses sbl-examples.yaml's winter+clarke:1993 entry, whose first note
    renders "vol. 1 of <em>The Book of Acts in Its First Century
    Setting</em>" via the filter (locked in non-link mode by the existing
    6.2.22 citation-tests case)."""
    doc = f"""---
bibliography: {ROOT / 'sbl-examples.yaml'}
link-citations: true
---

A titled volume in a multivolume work.[@winter+clarke:1993]
"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(doc)
        input_file = f.name
    try:
        result = subprocess.run(
            ['pandoc', '--from=markdown', '--to=html', '--wrap=none',
             '--citeproc', f'--csl={CSL}', f'--lua-filter={SBL_FILTER}',
             input_file],
            capture_output=True, text=True)
    finally:
        Path(input_file).unlink()
    assert result.returncode == 0, f'pandoc failed: {result.stderr}'
    footnotes = result.stdout.split('id="footnotes"')[1]
    assert 'of <em>The Book of Acts' in footnotes


def test_cos_chain_parent_omits_unsupported_source_type():
    """Documents a genuine exporter/legacy-data gap: the real-world COS
    entry (tests/gold/monograph-gold.json in the thesis-monograph
    repo) carries `source_type: ancient` in its sbl: note, which routes it
    into the "Ancient Sources" abbreviation sub-heading
    (sbl-filter.lua ~line 1303: `local target = (entry.source_type ==
    "ancient") and ancient or secondary`). CSLJSONExporter.swift's
    SBLMetadata model has no source_type field and can never emit one, so
    an ld-agent-exported COS entry is filed under "Secondary Sources"
    instead -- cosmetically wrong (wrong sub-heading) but not a crash or a
    dropped citation. Filters were not changed to accommodate this;
    tracked in ld-agent's bib-export change list."""
    html = run_pandoc_html()
    # The entry still renders as a shorthand and is excluded from the main
    # bibliography -- functionally intact despite the mis-routed heading.
    assert 'id="ref-COS"' not in html
    # Without source_type: ancient anywhere in the fixture, everything
    # files under Secondary Sources and no Ancient Sources section exists.
    assert 'Secondary Sources' in html
    assert 'Ancient Sources' not in html
