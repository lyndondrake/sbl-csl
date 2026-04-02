#!/usr/bin/env python3
"""Generate annote values from entrysubtype templates.

For entries with entrysubtype (ancientbook, inancientbook,
inancientcollection, etc.), this script generates the expected annote
value from the entry's standard CSL fields. This makes adding new entries
trivial — just set the entrysubtype and standard fields, then run this
script to populate the annote.

Usage:
    python scripts/generate-annote.py [--apply] [--validate]
"""

import re
import sys
from pathlib import Path
from ruamel.yaml import YAML

PROJECT_DIR = Path(__file__).parent.parent
BIB_FILE = PROJECT_DIR / 'sbl-examples.yaml'


def get_author_literal(ref: dict) -> str | None:
    """Extract the literal author name from an entry."""
    authors = ref.get('author', [])
    if authors and isinstance(authors, list):
        first = authors[0]
        if isinstance(first, dict):
            if 'literal' in first:
                return first['literal']
            family = first.get('family', '')
            given = first.get('given', '')
            if family and given:
                return f'{given} {family}'
            return family or given or None
    return None


def get_author_short(ref: dict) -> str | None:
    """Extract the short author name (family only)."""
    authors = ref.get('author', [])
    if authors and isinstance(authors, list):
        first = authors[0]
        if isinstance(first, dict):
            if 'literal' in first:
                return first['literal']
            return first.get('family')
    return None


# Template functions: return annote string from entry fields
TEMPLATES = {}


def template_ancientbook(ref: dict, sbl: dict) -> str | None:
    """Ancient book: complete ancient work in a collection series (ANF, NPNF, PG).

    The locator with series reference is passed separately, so the template
    only generates the base: Author, <i>Work</i>
    """
    author = get_author_literal(ref)
    title = ref.get('title', '')
    if not title:
        return None
    if author:
        return f'{author}, <i>{title}</i>'
    return f'<i>{title}</i>'

TEMPLATES['ancientbook'] = template_ancientbook


def template_inancientbook(ref: dict, sbl: dict) -> str | None:
    """Part of an ancient work in a collection series.

    Uses the same format as ancientbook for now.
    """
    return template_ancientbook(ref, sbl)

TEMPLATES['inancientbook'] = template_inancientbook


def template_inancientcollection(ref: dict, sbl: dict) -> str | None:
    """Text in a modern collection (COS, ANET, RIMA, ABC, ANRW).

    Uses the same base format as ancientbook for now.
    """
    return template_ancientbook(ref, sbl)

TEMPLATES['inancientcollection'] = template_inancientcollection


def template_lexicon_article(ref: dict, sbl: dict) -> str | None:
    """Lexicon/dictionary articles: Author, "Headword," <i>SHORTHAND</i> vol:pages.

    Requires shorthand from parent entry (via xref) and volume/page from entry.
    """
    author = get_author_literal(ref)
    title = ref.get('title', '')  # headword
    shorthand = sbl.get('shorthand')
    volume = ref.get('volume', '')
    page = ref.get('page', '')

    if not title or not shorthand:
        return None

    parts = []
    if author:
        parts.append(f'{author}, ')
    parts.append(f'"{title}," <i>{shorthand}</i>')
    if volume and page:
        parts.append(f' {volume}:{page}')
    elif page:
        parts.append(f', {page}')

    return ''.join(parts)

# Note: lexicon_article is not an entrysubtype but a pattern based on type + xref


def parse_sbl_note(note: str) -> dict:
    """Parse sbl: block from note field."""
    sbl = {}
    in_sbl = False
    for line in note.split('\n'):
        if re.match(r'^\s*sbl:\s*$', line):
            in_sbl = True
        elif in_sbl:
            m = re.match(r'^\s+(\S+):\s*(.+)\s*$', line)
            if m:
                key, value = m.group(1), m.group(2).strip().strip('"').strip("'")
                sbl[key] = value
            elif not re.match(r'^\s', line):
                in_sbl = False
    return sbl


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Generate annote from templates')
    parser.add_argument('--apply', action='store_true', help='Write annote to YAML')
    parser.add_argument('--validate', action='store_true', help='Check existing annote matches template')
    args = parser.parse_args()

    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 120
    data = yaml.load(BIB_FILE)

    changes = 0
    mismatches = 0

    for ref in data['references']:
        note = str(ref.get('note', ''))
        sbl = parse_sbl_note(note)
        subtype = sbl.get('entrysubtype')

        if not subtype or subtype not in TEMPLATES:
            continue

        template_fn = TEMPLATES[subtype]
        generated = template_fn(ref, sbl)

        if not generated:
            continue

        existing = ref.get('annote', '')

        if args.validate:
            if existing and existing != generated:
                mismatches += 1
                print(f'MISMATCH {ref["id"]} ({subtype}):')
                print(f'  existing: {existing}')
                print(f'  template: {generated}')
                print()
            elif not existing:
                print(f'MISSING {ref["id"]} ({subtype}): template would generate:')
                print(f'  {generated}')
                print()
        elif args.apply:
            if not existing:
                ref['annote'] = generated
                changes += 1
                print(f'Generated annote for {ref["id"]}: {generated[:60]}')
        else:
            status = '✓ match' if existing == generated else '✗ differs' if existing else '○ no annote'
            print(f'{status} [{ref["id"]}] ({subtype})')
            if existing and existing != generated:
                print(f'  existing: {existing}')
                print(f'  template: {generated}')

    if args.apply and changes:
        yaml.dump(data, BIB_FILE)
        print(f'\n{changes} annote values generated.')
    elif args.validate:
        print(f'\n{mismatches} mismatches found.')


if __name__ == '__main__':
    main()
