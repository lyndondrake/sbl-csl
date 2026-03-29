#!/usr/bin/env python3
"""Fix expected values in citation-tests.yaml.

Strips footnote numbers and fixes spacing issues from PDF extraction.
"""

import re
from pathlib import Path
from ruamel.yaml import YAML

TESTS_FILE = Path(__file__).parent.parent / 'tests' / 'citation-tests.yaml'

# Specific collapsed word pairs from PDF extraction
# Format: (collapsed, corrected)
COLLAPSED_WORDS = [
    # Common preposition/article collapses
    ('ofthe', 'of the'), ('inthe', 'in the'), ('tothe', 'to the'),
    ('ofIsrael', 'of Israel'), ('ofBooks', 'of Books'),
    ('andIts', 'and Its'), ('andOther', 'and Other'),
    ('andAndrew', 'and Andrew'), ('andAndré', 'and André'),
    # Verb + preposition collapses
    ('reviewof', 'review of'), ('Illustratedby', 'Illustrated by'),
    ('Editedby', 'Edited by'), ('Translatedby', 'Translated by'),
    ('Editedand', 'Edited and'),
    ('toLinguistic', 'to Linguistic'), ('byPeter', 'by Peter'),
    ('byNeil', 'by Neil'), ('byBruce', 'by Bruce'),
    ('byJames', 'by James'), ('byColin', 'by Colin'),
    ('byWatson', 'by Watson'),
    # Publisher/place collapses
    ('BiblicalLiterature', 'Biblical Literature'),
    ('BiblicalPoetry', 'Biblical Poetry'),
    ('BiblicalInterpretation', 'Biblical Interpretation'),
    ('EarlyChristian', 'Early Christian'),
    ('AkkadianLiterature', 'Akkadian Literature'),
    ('NewTestament', 'New Testament'), ('OldTestament', 'Old Testament'),
    ('LiterarySetting', 'Literary Setting'),
    ('TheAnchor', 'The Anchor'), ('TheBook', 'The Book'),
    ('TheOriental', 'The Oriental'), ('TheHebrewand', 'The Hebrew and'),
    ('ScholarsPress', 'Scholars Press'),
    ('HarvardUniversity', 'Harvard University'),
    ('OxfordUniversity', 'Oxford University'),
    ('OrientalInstitute', 'Oriental Institute'),
    ('TorontoPress', 'Toronto Press'),
    ('HittiteMyths', 'Hittite Myths'),
    ('WilburGingrich', 'Wilbur Gingrich'),
    ('EnglishLexicon', 'English Lexicon'),
    ('Checklistof', 'Checklist of'),
    ('DesmondAlexander', 'Desmond Alexander'),
    # Shorthand + author collapses
    ('BDAGDanker', 'BDAG Danker'),
    ('BDBBrown', 'BDB Brown'),
    ('BDFBlass', 'BDF Blass'),
    ('HALOTKoehler', 'HALOT Koehler'),
    ('TLOTJenni', 'TLOT Jenni'),
    ('SBLHSThe', 'SBLHS The'),
    ('Str-BStrack', 'Str-B Strack'),
]

# Line-break hyphens from PDF extraction
HYPHEN_FIXES = [
    ('Gram-mar', 'Grammar'), ('Tes-tament', 'Testament'),
    ('Chris-tian', 'Christian'), ('Edin-burgh', 'Edinburgh'),
    ('Jeru-salem', 'Jerusalem'), ('Phila-delphia', 'Philadelphia'),
    ('Cam-bridge', 'Cambridge'), ('Prin-ceton', 'Princeton'),
    ('Inter-pretation', 'Interpretation'), ('Inter-preters', 'Interpreters'),
    ('Histo-ry', 'History'), ('Reli-gion', 'Religion'),
    ('Theol-ogy', 'Theology'), ('Ar-chaeology', 'Archaeology'),
    ('Lit-erature', 'Literature'), ('Bib-lical', 'Biblical'),
    ('West-minster', 'Westminster'), ('Hen-drickson', 'Hendrickson'),
    ('Hendrick-son', 'Hendrickson'),
    ('Ei-senbrauns', 'Eisenbrauns'), ('Eerd-mans', 'Eerdmans'),
    ('Fort-ress', 'Fortress'), ('Vanden-hoeck', 'Vandenhoeck'),
    ('Rup-recht', 'Ruprecht'), ('Testa-ment', 'Testament'),
]


def fix_expected(text: str) -> str:
    """Fix a single expected value."""
    if not text or not text.strip():
        return text

    result = text.strip()

    # Strip leading footnote number (e.g., "47. " or "9. " at the very start)
    result = re.sub(r'^\d+\.\s+', '', result)

    # Apply line-break hyphen fixes
    for before, after in HYPHEN_FIXES:
        result = result.replace(before, after)

    # Fix missing spaces after period before asterisk (italic)
    result = re.sub(r'(\w)\.\*([A-Z])', r'\1. *\2', result)
    result = re.sub(r'(ed)\.\*', r'\1. *', result)

    # Fix missing spaces before italic markers after commas/quotes
    result = re.sub(r'([,"])\*([A-Z])', r'\1 *\2', result)

    # Fix missing space after closing italic/asterisk before digit
    result = re.sub(r'\*(\d)', r'* \1', result)

    # Apply collapsed word fixes
    for before, after in COLLAPSED_WORDS:
        result = result.replace(before, after)

    # Fix "ofBooks" etc. — "of" + uppercase (generic)
    result = re.sub(r'\bof([A-Z])', r'of \1', result)

    # Fix missing space after comma before uppercase letter
    result = re.sub(r',([A-Z])', r', \1', result)

    # Fix missing space after colon before uppercase letter
    result = re.sub(r':([A-Z])', r': \1', result)

    # Fix missing space before "in" when preceded by digits
    result = re.sub(r'(\d)in\b', r'\1 in', result)

    # Fix italic closing followed by period: "Literature.*" -> "Literature*."
    result = re.sub(r'(\w)\.\*(\s)', r'\1*.\2', result)
    result = re.sub(r'(\w)\.\*$', r'\1*.', result)

    # Fix "ed.David" -> "ed. David" etc.
    result = re.sub(r'(ed\.)([A-Z])', r'\1 \2', result)

    # Fix period-space issues: "Word*.Word" -> "Word*. Word"
    result = re.sub(r'\*\.([A-Z])', r'*. \1', result)

    # Fix general "word.Word" where there should be ". "
    # (sentence boundary from PDF, but be careful not to break abbreviations)
    result = re.sub(r'([a-z])\*\.([A-Z][a-z])', r'\1*. \2', result)

    # Collapse multiple spaces
    result = re.sub(r'  +', ' ', result)

    return result


def main():
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 120

    data = yaml.load(TESTS_FILE)

    changes = 0
    for test in data['tests']:
        expectations = test.get('expectations', {})
        if not expectations:
            continue
        for style_id, style_exp in expectations.items():
            if not style_exp:
                continue
            for form, form_exp in style_exp.items():
                if not form_exp or 'expected' not in form_exp:
                    continue
                original = form_exp['expected']
                if not original:
                    continue
                fixed = fix_expected(str(original))
                if fixed != str(original):
                    form_exp['expected'] = fixed
                    changes += 1

    if changes:
        print(f'{changes} expected values fixed.')
        yaml.dump(data, TESTS_FILE)
        print(f'Written to {TESTS_FILE}')
    else:
        print('No changes needed.')


if __name__ == '__main__':
    main()
