"""Tests for the sbl-filter.lua abbreviation list.

Verifies the punctuation convention settled in biblatex-sbl v2.0rc3:
sigla (@abbreviation-style) entries carry no trailing period, while
bibliography-style entries (secondary sources) keep theirs. Also checks
section sub-headings appear when more than one section has entries.
"""

import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
BIBLIOGRAPHY = ROOT / 'sbl-examples.yaml'
CSL = ROOT / 'society-of-biblical-literature-fullnote-bibliography.csl'
SBL_FILTER = ROOT / 'sbl-filter.lua'

DOC = """---
bibliography: {bib}
---

Text with a citation.[@BDAG]

# Abbreviations {{#sbl-abbreviations}}

# Bibliography
"""


def run_pandoc() -> str:
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(DOC.format(bib=BIBLIOGRAPHY))
        input_file = f.name
    try:
        result = subprocess.run(
            [
                'pandoc',
                '--from=markdown',
                '--to=html',
                '--citeproc',
                f'--csl={CSL}',
                f'--lua-filter={SBL_FILTER}',
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


def test_sigla_entry_has_no_trailing_period():
    """Sigla expansions print bare: 'abl.  ablative' with no final period."""
    html = run_pandoc()
    assert 'ablative' in html
    assert 'ablative.' not in html


def test_secondary_source_keeps_trailing_period():
    """Bibliography-style abbreviation entries keep their final period."""
    html = run_pandoc()
    assert 'University of Chicago Press, 2000.' in html


def test_sections_appear_when_multiple():
    """With both secondary sources and sigla present, sub-headings render."""
    html = run_pandoc()
    assert 'Secondary Sources' in html
    assert 'General Abbreviations and Sigla' in html
