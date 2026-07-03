"""Tests for ld-author-index.lua.

Verifies index name formatting, in particular name particles:
cited as "von Rad", indexed as "Rad, Gerhard von" (sorted under R),
while names whose particle is part of the family field ("Van Seters")
index under the particle. Mirrors biblatex-sbl v2 issue #153.
"""

import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
BIBLIOGRAPHY = ROOT / 'sbl-examples.yaml'
CSL = ROOT / 'society-of-biblical-literature-fullnote-bibliography.csl'
INDEX_FILTER = ROOT / 'ld-author-index.lua'

DOC = """---
bibliography: {bib}
---

Text with citations.[@vonrad:1990] More text.[@vanseters:1995]

# Author Index {{#author-index}}
"""


def run_pandoc(to_format: str) -> str:
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(DOC.format(bib=BIBLIOGRAPHY))
        input_file = f.name
    try:
        result = subprocess.run(
            [
                'pandoc',
                '--from=markdown',
                f'--to={to_format}',
                '--citeproc',
                f'--csl={CSL}',
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


def test_html_index_demotes_particle():
    """von Rad indexes as 'Rad, Gerhard von' (under R), not 'von Rad, Gerhard'."""
    html = run_pandoc('html')
    assert 'Rad, Gerhard von' in html
    assert 'von Rad, Gerhard' not in html


def test_html_index_keeps_family_particle():
    """'Van Seters' is part of the family name and stays index-first."""
    html = run_pandoc('html')
    assert 'Van Seters, John' in html


def test_html_index_sorted_under_r():
    """'Rad, Gerhard von' sorts before 'Van Seters, John' (R before V)."""
    html = run_pandoc('html')
    assert html.index('Rad, Gerhard von') < html.index('Van Seters, John')


def test_typst_index_entries():
    """Typst output emits in-dexter #index[] calls with the demoted form."""
    typst = run_pandoc('typst')
    assert '#index[Rad, Gerhard von]' in typst
    assert '#index[Van Seters, John]' in typst
