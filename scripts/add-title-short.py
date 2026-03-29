#!/usr/bin/env python3
"""Add title-short to bibliography entries based on subsequent note expectations."""

import re
import sys
from pathlib import Path
from ruamel.yaml import YAML

PROJECT_DIR = Path(__file__).parent.parent
TESTS_FILE = PROJECT_DIR / 'tests' / 'citation-tests.yaml'
BIB_FILE = PROJECT_DIR / 'sbl-examples.yaml'


def extract_short_title(expected: str, entry_type: str = 'book') -> str | None:
    """Extract the short title from a subsequent note expected value.

    Patterns:
      Author, *Short Title*, locator.        (book-like)
      Author, "Short Title," locator.        (article-like)
    """
    if not expected:
        return None

    # Strip leading footnote number
    text = re.sub(r'^\d+\.\s+', '', expected.strip())

    # Try italic title: Author(s), *Short Title*, ...
    m = re.search(r',\s*\*([^*]+)\*', text)
    if m:
        return m.group(1).strip()

    # Try quoted title: Author(s), "Short Title," ...
    m = re.search(r',\s*"([^"]+)"', text)
    if m:
        return m.group(1).strip()

    return None


def main():
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 120

    tests_data = yaml.load(TESTS_FILE)
    bib_data = yaml.load(BIB_FILE)

    refs = bib_data['references']
    ref_lookup = {r['id']: r for r in refs}

    changes = 0
    for test in tests_data['tests']:
        entry_id = test['entry_id']
        if entry_id not in ref_lookup:
            continue

        ref = ref_lookup[entry_id]
        if 'title-short' in ref:
            continue  # Already has one

        exps = test.get('expectations', {}).get('sbl-fullnote', {})
        sub = exps.get('subsequent_note', {})
        expected = sub.get('expected', '')
        if not expected:
            continue

        entry_type = ref.get('type', 'book')
        short_title = extract_short_title(expected, entry_type)
        if not short_title:
            continue

        # Check the short title is actually shorter than the full title
        full_title = str(ref.get('title', ''))
        if len(short_title) >= len(full_title):
            continue  # Not actually shorter

        # Check the short title is a prefix/subset of the full title
        if short_title.lower() not in full_title.lower() and short_title[:20].lower() not in full_title[:30].lower():
            # The short title might be a very abbreviated form
            print(f'  NOTE: {entry_id}: short="{short_title}" not in full="{full_title[:60]}"')

        ref['title-short'] = short_title
        changes += 1
        print(f'Added title-short to {entry_id}: "{short_title}"')

    if changes:
        print(f'\n{changes} entries updated.')
        yaml.dump(bib_data, BIB_FILE)
        print(f'Written to {BIB_FILE}')
    else:
        print('No changes needed.')


if __name__ == '__main__':
    main()
