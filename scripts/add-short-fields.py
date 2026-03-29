#!/usr/bin/env python3
"""Add container-title-short and collection-title-short from sbl note field."""

import re
from pathlib import Path
from ruamel.yaml import YAML

BIB_FILE = Path(__file__).parent.parent / 'sbl-examples.yaml'


def parse_sbl_note(note: str) -> dict:
    """Parse the sbl: section from a note field."""
    if not note:
        return {}

    # Find the sbl: block
    m = re.search(r'sbl:\s*\n((?:\s+\S.*\n?)*)', note)
    if not m:
        return {}

    sbl_text = m.group(1)
    result = {}
    for line in sbl_text.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if ':' in line:
            key, _, value = line.partition(':')
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if value:
                result[key] = value
    return result


def main():
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 120

    data = yaml.load(BIB_FILE)
    refs = data['references']

    changes = 0
    for ref in refs:
        note = ref.get('note', '')
        if not note:
            continue

        sbl = parse_sbl_note(str(note))

        # Add container-title-short from shortjournal
        if sbl.get('shortjournal') and 'container-title-short' not in ref:
            ref['container-title-short'] = sbl['shortjournal']
            changes += 1
            print(f'Added container-title-short to {ref["id"]}: {sbl["shortjournal"]}')

        # Add collection-title-short from shortseries
        if sbl.get('shortseries') and 'collection-title-short' not in ref:
            ref['collection-title-short'] = sbl['shortseries']
            changes += 1
            print(f'Added collection-title-short to {ref["id"]}: {sbl["shortseries"]}')

    if changes:
        print(f'\n{changes} fields added.')
        yaml.dump(data, BIB_FILE)
        print(f'Written to {BIB_FILE}')
    else:
        print('No changes needed.')


if __name__ == '__main__':
    main()
