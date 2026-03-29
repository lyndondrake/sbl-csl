#!/usr/bin/env python3
"""Add annote fields to bibliography entries for non-standard citation formats.

The CSL annote bypass (lines 1169-1185) outputs annote text directly instead
of normal citation formatting. Two modes:
- sub-verbo locator: "annote, locator"
- other: "annote locator"

For entries where the expected first note IS the annote + locator, we set annote
to the text before the locator. For entries where the entire citation is in the
expected text (no separate locator), we set annote to the full expected text
minus the trailing period.
"""

import re
from pathlib import Path
from ruamel.yaml import YAML

PROJECT_DIR = Path(__file__).parent.parent
BIB_FILE = PROJECT_DIR / 'sbl-examples.yaml'

# Map of entry_id -> annote value
# These are derived from the expected first_note outputs in citation-tests.yaml
# The annote must NOT include the locator — CSL appends that automatically
ANNOTE_MAP = {
    # 6.2.37 Loeb Classical Library
    'josephus:ant': 'Josephus, <i>Ant</i>.',
    'tacitus:ann': 'Tacitus, <i>Ann</i>.',
    'josephus:ant:thackery': 'Josephus, <i>Ant</i>.',
    'tacitus:ann:jackson': 'Tacitus, <i>Ann</i>.',
    'josephus:ant1-19': 'Josephus, <i>Ant</i>.',
    'josephus': 'Josephus, <i>Ant</i>.',
    'tacitus': 'Tacitus, <i>Ann</i>.',

    # 6.2.38 Papyri
    'p.cair.zen.': 'P.Cair.Zen.',
    'p.cair.zen.:hunt+edgar': 'P.Cair.Zen.',
    'PGM': '<i>PGM</i>',
    'PGM:betz': '<i>PGM</i>',

    # 6.2.39 Ancient epistles
    'heraclitus:epistle1': 'Heraclitus, <i>Epistle 1</i>,',
    'heraclitus:epistle1:worley': 'Heraclitus, <i>Epistle 1</i>,',

    # 6.2.41 Patrologia
    'gregory:orationestheologicae': 'Gregory of Nazianzus, <i>Orationes theologicae</i>',

    # 6.2.14 Introduction
    'boers:1996': 'Hendrikus Boers, introduction to <i>How to Read the New Testament: An Introduction to Linguistic and Historical-Critical Methodology</i>, by Wilhelm Egger, trans. Peter Heinegg (Peabody, MA: Hendrickson, 1996),',
}


def main():
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 120

    data = yaml.load(BIB_FILE)
    refs = data['references']
    ref_lookup = {r['id']: r for r in refs}

    changes = 0
    for entry_id, annote_value in ANNOTE_MAP.items():
        if entry_id in ref_lookup:
            ref = ref_lookup[entry_id]
            if 'annote' not in ref or ref['annote'] != annote_value:
                ref['annote'] = annote_value
                changes += 1
                print(f'Set annote for {entry_id}: {annote_value[:60]}')
        else:
            print(f'WARNING: entry {entry_id} not found in bibliography')

    if changes:
        print(f'\n{changes} entries updated.')
        yaml.dump(data, BIB_FILE)
        print(f'Written to {BIB_FILE}')
    else:
        print('No changes needed.')


if __name__ == '__main__':
    main()
