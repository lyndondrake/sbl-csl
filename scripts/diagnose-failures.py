#!/usr/bin/env python3
"""Diagnose test failures by categorising them."""

import sys
import re
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / 'tests'))

import yaml
from lib.generator import CitationGenerator
from lib.normaliser import normalise

PROJECT_DIR = Path(__file__).parent.parent
TESTS_FILE = PROJECT_DIR / 'tests' / 'citation-tests.yaml'
BIB_FILE = PROJECT_DIR / 'sbl-examples.yaml'
CSL_FILE = PROJECT_DIR / 'society-of-biblical-literature-fullnote-bibliography.csl'


def categorise_diff(expected, actual, form):
    """Categorise a failure into a type."""
    categories = []

    # Check for footnote numbers in expected
    if re.match(r'^\d+\.\s', expected):
        categories.append('expected_has_footnote_number')

    # Check for title casing difference
    exp_lower = expected.lower()
    act_lower = actual.lower()
    if exp_lower == act_lower:
        categories.append('case_difference_only')
    elif re.sub(r'[A-Z]', 'x', expected) != re.sub(r'[A-Z]', 'x', actual):
        # More nuanced case check
        pass

    # Check for series abbreviation vs full name
    if re.search(r'\b[A-Z]{2,}\s+\d', expected) and not re.search(r'\b[A-Z]{2,}\s+\d', actual):
        categories.append('series_abbreviation_needed')

    # Check for journal abbreviation
    if form in ('first_note',) and re.search(r'\*[A-Z]{2,}\*', expected) and not re.search(r'\*[A-Z]{2,}\*', actual):
        categories.append('journal_abbreviation_needed')

    # Check for shorthand (BDAG, BDB, etc.)
    if re.match(r'^[A-Z]{2,}', expected) and not re.match(r'^[A-Z]{2,}', actual):
        categories.append('shorthand_needed')

    # Check for missing/different content (structural)
    if len(actual) < len(expected) * 0.5:
        categories.append('major_content_missing')
    elif len(actual) > len(expected) * 1.5:
        categories.append('excess_content')

    # Check for 'vol. X of' pattern
    if 'vol.' in expected and 'vol.' not in actual:
        categories.append('multivolume_formatting')

    # Check for reprint info
    if 'repr.' in expected.lower() or 'orig.' in expected.lower():
        categories.append('reprint_info')

    # Check for empty expected
    if not expected.strip():
        categories.append('empty_expected')

    # Check for 'ed.' in expected where actual has 'by'
    if ', ed.' in expected and ', by' in actual:
        categories.append('editor_vs_by')

    if not categories:
        categories.append('other')

    return categories


def main():
    with open(TESTS_FILE) as f:
        data = yaml.safe_load(f)

    LUA_FILTER = PROJECT_DIR / 'sbl-filter.lua'
    generator = CitationGenerator(BIB_FILE, CSL_FILE, LUA_FILTER)

    tests = data['tests']
    style_id = 'sbl-fullnote'

    category_counts = {}
    category_examples = {}
    pass_count = 0
    fail_count = 0
    skip_count = 0
    error_count = 0

    for test in tests:
        expectations = test.get('expectations', {}).get(style_id, {})
        for form in ('first_note', 'subsequent_note', 'bibliography'):
            form_exp = expectations.get(form)
            if not form_exp:
                skip_count += 1
                continue

            expected = normalise(form_exp['expected'])
            locator = form_exp.get('locator')
            entry_id = test['entry_id']

            try:
                actual = normalise(generator.generate_citation(entry_id, form, locator))
            except Exception as e:
                error_count += 1
                continue

            if expected == actual:
                pass_count += 1
                continue

            fail_count += 1
            cats = categorise_diff(expected, actual, form)
            for cat in cats:
                category_counts[cat] = category_counts.get(cat, 0) + 1
                if cat not in category_examples or len(category_examples[cat]) < 3:
                    category_examples.setdefault(cat, []).append({
                        'test_id': test['id'],
                        'form': form,
                        'expected': expected[:120],
                        'actual': actual[:120],
                    })

    print(f'=== SBL Fullnote Failure Diagnosis ===')
    print(f'Passed: {pass_count}')
    print(f'Failed: {fail_count}')
    print(f'Skipped: {skip_count}')
    print(f'Errors: {error_count}')
    print()
    print('=== Failure Categories ===')
    for cat, count in sorted(category_counts.items(), key=lambda x: -x[1]):
        print(f'\n{cat}: {count}')
        for ex in category_examples[cat]:
            print(f'  [{ex["test_id"]}] ({ex["form"]})')
            print(f'    Expected: {ex["expected"]}')
            print(f'    Actual:   {ex["actual"]}')


if __name__ == '__main__':
    main()
