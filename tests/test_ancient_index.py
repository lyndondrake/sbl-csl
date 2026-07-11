"""Tests for ld-ancient-index.lua.

Verifies recognition of scripture references (dot/colon chapter-verse
separators, en-dash ranges, numbered books, full names, semicolon
continuations, footnote content), explicit .anc marker spans for
non-biblical sources, SBL sectioning, and the marker-heading expansion
for docx and HTML output. Mirrors tests/test_author_index.py's structure.
"""

import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
INDEX_FILTER = ROOT / 'ld-ancient-index.lua'

DOC = """---
title: Ancient index test
---

{body}

# Index of Ancient Sources {{#ancient-index}}
"""


def run_pandoc(body: str, to_format: str) -> str:
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(DOC.format(body=body))
        input_file = f.name
    try:
        result = subprocess.run(
            [
                'pandoc',
                '--from=markdown',
                f'--to={to_format}',
                '--wrap=none',
                f'--lua-filter={INDEX_FILTER}',
                input_file,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f'pandoc failed: {e.stderr}')
    finally:
        Path(input_file).unlink()


def run_pandoc_docx(body: str) -> str:
    """Build docx and return the extracted document.xml text."""
    import zipfile

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(DOC.format(body=body))
        input_file = f.name
    out_file = input_file.replace('.md', '.docx')
    try:
        subprocess.run(
            [
                'pandoc',
                '--from=markdown',
                '--to=docx',
                f'--lua-filter={INDEX_FILTER}',
                input_file,
                '-o', out_file,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        with zipfile.ZipFile(out_file) as z:
            return z.read('word/document.xml').decode('utf-8')
    except subprocess.CalledProcessError as e:
        pytest.fail(f'pandoc failed: {e.stderr}')
    finally:
        Path(input_file).unlink()
        if Path(out_file).exists():
            Path(out_file).unlink()


def test_simple_reference():
    """'Jer 8.8' indexes under Jeremiah with subentry 8.8."""
    html = run_pandoc('Text with Jer 8.8 in it.', 'html')
    assert '<dt>Jeremiah</dt>' in html
    assert '<li>8.8</li>' in html


def test_colon_separator():
    """'Lev 25:23' is recognised with a colon chapter/verse separator."""
    html = run_pandoc('See Lev 25:23 for the land law.', 'html')
    assert '<dt>Leviticus</dt>' in html
    assert '<li>25.23</li>' in html


def test_dash_range():
    """'Jer 32.6--15' (rendered as en dash) becomes subentry 32.6-15."""
    html = run_pandoc('Compare Jer 32.6--15 with the parallel.', 'html')
    assert '<dt>Jeremiah</dt>' in html
    assert '32.6–15' in html


def test_numbered_book():
    """'2 Sam 24' is recognised as a numbered book."""
    html = run_pandoc('The census in 2 Sam 24 is notorious.', 'html')
    assert '<dt>2 Samuel</dt>' in html
    assert '<li>24</li>' in html


def test_full_book_name():
    """'Jeremiah 36' (full name, not abbreviation) is recognised."""
    html = run_pandoc('The scroll in Jeremiah 36 is burned.', 'html')
    assert '<dt>Jeremiah</dt>' in html
    assert '<li>36</li>' in html


def test_semicolon_continuation_same_book():
    """'Gen 25.9--10; 49.29--32' both index under Genesis."""
    html = run_pandoc('Gen 25.9--10; 49.29--32 record burials.', 'html')
    assert '<dt>Genesis</dt>' in html
    assert '25.9–10' in html
    assert '49.29–32' in html


def test_reference_inside_footnote():
    """A reference inside a footnote is still indexed."""
    body = 'Main text continues.[^1]\n\n[^1]: See Deut 27.2--3 for the curse.'
    html = run_pandoc(body, 'html')
    assert '<dt>Deuteronomy</dt>' in html
    assert '27.2–3' in html


def test_lookalike_word_without_digit_not_matched():
    """'John' with no following digit is not treated as a book reference."""
    html = run_pandoc('John the Baptist preached repentance.', 'html')
    assert '<dt>John</dt>' not in html


def test_marker_heading_html():
    """The {#ancient-index} heading expands to a static definition list."""
    html = run_pandoc('A reference to Gen 23 for context.', 'html')
    assert '<h1 id="ancient-index">Index of Ancient Sources</h1>' in html
    assert '<dt>Genesis</dt>' in html


def test_docx_bookmark_at_occurrence():
    """A reference occurrence gets a hidden bookmark, not an XE field."""
    xml = run_pandoc_docx('A reference to Gen 23 for context.')
    assert '<w:bookmarkStart w:id="90001" w:name="anc0001"/>' in xml
    assert '<w:bookmarkEnd w:id="90001"/>' in xml
    assert 'XE "Genesis:23"' not in xml


def test_docx_no_xe_or_index_field():
    """The old XE/INDEX \\f "ancient" machinery is gone entirely."""
    xml = run_pandoc_docx('A reference to Gen 23 for context.')
    assert 'INDEX \\f "ancient"' not in xml
    assert '\\f "ancient"' not in xml
    assert 'XE "' not in xml


def test_docx_marker_generates_pageref_index():
    """The {#ancient-index} heading expands to a self-generated index with
    a bold book heading and a PAGEREF field pointing at the bookmark."""
    xml = run_pandoc_docx('A reference to Gen 23 for context.')
    assert '<w:b' in xml  # bold book heading (pandoc emits '<w:b />')
    assert '>Genesis<' in xml
    assert 'PAGEREF anc0001 \\h' in xml


def test_docx_every_occurrence_bookmarked_across_blocks():
    """Two occurrences of the same reference in DIFFERENT paragraphs each
    get their own bookmark, and the index lists both PAGEREF fields."""
    body = 'First mention of Gen 23 here.\n\nSecond mention of Gen 23 there.'
    xml = run_pandoc_docx(body)
    assert xml.count('w:name="anc0001"') == 1
    assert xml.count('w:name="anc0002"') == 1
    assert 'PAGEREF anc0001 \\h' in xml
    assert 'PAGEREF anc0002 \\h' in xml


def test_docx_same_block_dedupe():
    """Two occurrences of the same reference in the SAME paragraph are
    only bookmarked once."""
    body = 'Gen 23 is mentioned, and Gen 23 is mentioned again in the same sentence.'
    xml = run_pandoc_docx(body)
    assert xml.count('w:name="anc0001"') == 1
    assert 'anc0002' not in xml
    assert xml.count('PAGEREF anc0001 \\h') == 1


def test_docx_canonical_order():
    """Genesis precedes Exodus precedes Jeremiah in the generated docx
    index, regardless of the order they're first mentioned in the text."""
    body = 'See Jer 8.8, then Exod 3.1, then Gen 1.1 for context.'
    xml = run_pandoc_docx(body)
    gen_pos = xml.find('>Genesis<')
    exod_pos = xml.find('>Exodus<')
    jer_pos = xml.find('>Jeremiah<')
    assert gen_pos != -1 and exod_pos != -1 and jer_pos != -1
    assert gen_pos < exod_pos < jer_pos


def test_docx_subentry_numeric_order():
    """Within a book, subentries are ordered numerically (2.26 before
    11.21), not lexicographically."""
    body = 'Gen 11.21 is mentioned before Gen 2.26 in the text.'
    xml = run_pandoc_docx(body)
    pos_226 = xml.find('2.26:')
    pos_1121 = xml.find('11.21:')
    assert pos_226 != -1 and pos_1121 != -1
    assert pos_226 < pos_1121


def test_typst_index_entry_display_key_tuple():
    """The typst path emits a book string plus a (display, key) tuple for
    the chapter/verse level, with a zero-padded numeric sort key, filed
    under the section index ancient-hb."""
    typst = run_pandoc('Compare Jer 32.6--15 with the parallel.', 'typst')
    assert '#index("Jeremiah", ("32.6–15", "0032.0006-0015"), index: "ancient-hb")' in typst


def test_typst_index_entry_simple_chapter():
    """A bare chapter reference (no verse) gets a zero-padded chapter-only
    sort key."""
    typst = run_pandoc('A reference to Gen 23 for context.', 'typst')
    assert '#index("Genesis", ("23", "0023"), index: "ancient-hb")' in typst


def test_typst_marker_heading():
    """The {#ancient-index} heading expands to per-section make-index calls
    with a shared canonical-order sort-order callback and suppressed
    initial-letter section titles."""
    typst = run_pandoc('A reference to Gen 23 for context.', 'typst')
    assert '__ancient_index_order' in typst
    assert '"Genesis": "01"' in typst
    assert '"Revelation": "66"' in typst
    assert 'indexes: ("ancient-hb",)' in typst
    assert 'section-title: (letter, counter) => []' in typst
    assert 'sort-order: k => __ancient_index_order.at(k, default: k)' in typst
    assert 'entry-casing: k => k' in typst


def test_typst_every_occurrence_emitted_undeduped():
    """Every occurrence of a reference gets its own #index() call (in-dexter
    itself collapses duplicate pages)."""
    body = 'First mention of Gen 23 here.\n\nSecond mention of Gen 23 there.'
    typst = run_pandoc(body, 'typst')
    assert typst.count('#index("Genesis", ("23", "0023"), index: "ancient-hb")') == 2


# ──────────────────────────────────────────────
# Sections
# ──────────────────────────────────────────────


def test_html_ot_nt_sections():
    """OT and NT references are filed under separate section headings, in
    SBL order (Hebrew Bible first)."""
    html = run_pandoc('Compare Jer 8.8 with Matt 5.3 for context.', 'html')
    assert 'Hebrew Bible/Old Testament' in html
    assert 'New Testament' in html
    assert html.find('Hebrew Bible/Old Testament') < html.find('New Testament')
    assert '<dt>Jeremiah</dt>' in html
    assert '<dt>Matthew</dt>' in html


def test_html_empty_sections_not_rendered():
    """Sections with no entries produce no heading."""
    html = run_pandoc('Only Gen 23 is cited.', 'html')
    assert 'New Testament' not in html
    assert 'Dead Sea Scrolls' not in html


def test_typst_nt_filed_separately():
    """An NT reference goes to the ancient-nt index."""
    typst = run_pandoc('See Matt 5.3 for the beatitude.', 'typst')
    assert '#index("Matthew", ("5.3", "0005.0003"), index: "ancient-nt")' in typst
    assert 'indexes: ("ancient-nt",)' in typst


# ──────────────────────────────────────────────
# Explicit .anc marker spans (non-biblical sources)
# ──────────────────────────────────────────────


def test_marker_html():
    """A marker span files its entry and locus under the right section."""
    body = 'The law[]{.anc section="ane" entry="Laws of Hammurabi" locus="117"} is severe.'
    html = run_pandoc(body, 'html')
    assert 'Ancient Near Eastern Texts' in html
    assert '<dt>Laws of Hammurabi</dt>' in html
    assert '<li>117</li>' in html


def test_marker_page_only_entry_html():
    """A marker without a locus indexes the entry name alone."""
    body = 'Jubilees[]{.anc section="pseud" entry="Jubilees"} reworks history.'
    html = run_pandoc(body, 'html')
    assert 'Pseudepigrapha' in html
    assert '<dt>Jubilees</dt>' in html


def test_marker_docx_bookmark_and_pageref():
    """A marker occurrence gets a bookmark; the generated index carries a
    PAGEREF and the entry name."""
    body = 'The law[]{.anc section="ane" entry="Laws of Hammurabi" locus="117"} is severe.'
    xml = run_pandoc_docx(body)
    assert '<w:bookmarkStart w:id="90001" w:name="anc0001"/>' in xml
    assert 'PAGEREF anc0001 \\h' in xml
    assert '>Laws of Hammurabi<' in xml


def test_marker_docx_page_only_pageref_on_entry_line():
    """With no locus, the PAGEREF attaches to the entry line itself."""
    body = 'Jubilees[]{.anc section="pseud" entry="Jubilees"} reworks history.'
    xml = run_pandoc_docx(body)
    assert '>Jubilees<' in xml
    assert 'PAGEREF anc0001 \\h' in xml


def test_marker_typst():
    """A marker emits an #index call into its section's index, with the
    auto-generated zero-padded locus key."""
    body = 'The law[]{.anc section="ane" entry="Laws of Hammurabi" locus="117"} is severe.'
    typst = run_pandoc(body, 'typst')
    assert '#index("Laws of Hammurabi", ("117", "0117"), index: "ancient-ane")' in typst
    assert 'indexes: ("ancient-ane",)' in typst


def test_marker_typst_page_only():
    """A locus-less marker emits a single-level #index call."""
    body = 'Jubilees[]{.anc section="pseud" entry="Jubilees"} reworks history.'
    typst = run_pandoc(body, 'typst')
    assert '#index("Jubilees", index: "ancient-pseud")' in typst


def test_marker_explicit_sort_key():
    """A sort attribute overrides the automatic locus key, so LH gap
    paragraph t (between 65 and 100) sorts before 117."""
    body = (
        'See[]{.anc section="ane" entry="Laws of Hammurabi" locus="117"} and'
        '[]{.anc section="ane" entry="Laws of Hammurabi" locus="t" sort="0065.20"} both.'
    )
    html = run_pandoc(body, 'html')
    assert html.find('<li>t</li>') < html.find('<li>117</li>')


def test_marker_entry_sort_orders_entries():
    """entry-sort overrides plain alphabetical entry ordering within a
    marker section."""
    body = (
        'A[]{.anc section="dss" entry="Zed Scroll" entry-sort="01"} then'
        ' B[]{.anc section="dss" entry="Alpha Scroll" entry-sort="02"}.'
    )
    html = run_pandoc(body, 'html')
    assert html.find('<dt>Zed Scroll</dt>') < html.find('<dt>Alpha Scroll</dt>')


def test_marker_inside_footnote_and_blockquote():
    """Markers are recognised inside footnotes and block quotations."""
    body = (
        'Main text.[^1]\n\n'
        '> Quoted matter citing the Mishnah[]{.anc section="rabbinic" entry="m. B. Bat." locus="10:1"}.\n\n'
        '[^1]: See 4QInstruction[]{.anc section="dss" entry="4QInstruction"}.'
    )
    html = run_pandoc(body, 'html')
    assert 'Rabbinic Works' in html
    assert '<dt>m. B. Bat.</dt>' in html
    assert '<li>10:1</li>' in html
    assert 'Dead Sea Scrolls' in html
    assert '<dt>4QInstruction</dt>' in html


def test_marker_invalid_section_skipped():
    """A marker with an unknown section slug is skipped with a warning,
    not indexed, and does not crash the build."""
    body = 'Bad[]{.anc section="nope" entry="Ghost"} marker.'
    html = run_pandoc(body, 'html')
    assert 'Ghost' not in html


def test_marker_sections_in_sbl_order():
    """Marker sections render in SBL order regardless of occurrence order."""
    body = (
        'First[]{.anc section="ane" entry="Laws of Eshnunna" locus="39"} then'
        ' second[]{.anc section="dss" entry="4QInstruction"}.'
    )
    html = run_pandoc(body, 'html')
    assert html.find('Dead Sea Scrolls') < html.find('Ancient Near Eastern Texts')
