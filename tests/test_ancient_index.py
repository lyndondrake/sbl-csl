"""Tests for ld-ancient-index.lua.

Verifies recognition of scripture references (dot/colon chapter-verse
separators, en-dash ranges, numbered books, full names, semicolon
continuations, footnote content) and the marker-heading expansion for
docx and HTML output. Mirrors tests/test_author_index.py's structure.
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


def test_marker_heading_docx():
    """The {#ancient-index} heading expands to a flagged INDEX field."""
    xml = run_pandoc_docx('A reference to Gen 23 for context.')
    assert 'INDEX \\f "ancient"' in xml
    assert 'XE "Genesis:23" \\f "ancient"' in xml
