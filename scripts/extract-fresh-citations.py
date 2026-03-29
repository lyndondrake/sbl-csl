#!/usr/bin/env python3
"""Extract expected citation values from the freshly compiled biblatex-sbl PDF.

This script parses the .tex source for structure (entry keys, section numbers,
citation types) and the fresh PDF for rendered output. It produces clean
expected values by handling LaTeX line-break hyphenation.

Usage:
    python scripts/extract-fresh-citations.py [--pdf PATH] [--tex PATH]
"""

import re
import sys
from pathlib import Path

try:
    import fitz
except ImportError:
    print("PyMuPDF required: pip install PyMuPDF")
    sys.exit(1)

PROJECT_DIR = Path(__file__).parent.parent
PDF_PATH = PROJECT_DIR / '.tmp' / 'tex-build' / 'biblatex-sbl-examples.pdf'
TEX_PATH = PROJECT_DIR / '.tmp' / 'tex-build' / 'biblatex-sbl-examples.tex'


def extract_citations_from_pdf(pdf_path: Path) -> list[dict]:
    """Extract citation text blocks from the PDF using colour detection."""
    doc = fitz.open(str(pdf_path))
    results = []

    for page_num in range(len(doc)):
        page = doc[page_num]
        blocks = page.get_text("dict")["blocks"]

        for block in blocks:
            if "lines" not in block:
                continue
            for line in block["lines"]:
                line_text = ""
                is_citation = False
                for span in line["spans"]:
                    color = span.get("color", 0)
                    r = (color >> 16) & 0xFF
                    g = (color >> 8) & 0xFF
                    b = color & 0xFF

                    # Blue-ish text = biblatex output
                    if b > 100 and r < 100 and g < 100:
                        is_citation = True
                        font = span["font"]
                        txt = span["text"]
                        # Detect italic
                        italic = ("Italic" in font or font.endswith("I") or
                                  "LinLibertineOI" in font or "LinLibertineO-Italic" in font)
                        if italic:
                            line_text += f"*{txt}*"
                        else:
                            line_text += txt

                if is_citation and line_text.strip():
                    results.append({
                        'page': page_num + 1,
                        'text': line_text,
                    })

    return results


def join_citation_blocks(blocks: list[dict]) -> list[str]:
    """Join multi-line citation blocks into single strings.

    Handles LaTeX line-break hyphens by rejoining split words.
    """
    citations = []
    current = ""

    for block in blocks:
        text = block['text'].strip()
        if not text:
            continue

        # Detect the start of a new citation (starts with number + period)
        if re.match(r'^\d+\.\s', text) and current:
            citations.append(clean_citation(current))
            current = text
        elif not current and (re.match(r'^\d+\.\s', text) or
                              re.match(r'^[A-Z]', text)):
            current = text
        elif current:
            # Continue current citation
            # Handle line-break hyphen: "word-\n" + "continuation"
            if current.endswith('-'):
                current = current[:-1] + text
            else:
                current += " " + text
        else:
            current = text

    if current:
        citations.append(clean_citation(current))

    return citations


def clean_citation(text: str) -> str:
    """Clean up a citation string."""
    result = text.strip()
    # Collapse multiple spaces
    result = re.sub(r'\s+', ' ', result)
    # Clean up italic markers
    result = re.sub(r'\*\s*\*', '', result)  # Remove empty italic
    result = re.sub(r'\*\*', '', result)  # Remove double markers
    # Clean up common line-break hyphens
    hyphen_fixes = [
        ('Hen- drickson', 'Hendrickson'),
        ('Edin- burgh', 'Edinburgh'),
        ('Testa- mento', 'Testamento'),
        ('Merid- ian', 'Meridian'),
        ('Uni- versity', 'University'),
        ('Suther- land', 'Sutherland'),
    ]
    for before, after in hyphen_fixes:
        result = result.replace(before, after)
    # Generic line-break hyphen fix: "word- continuation" where lowercase-uppercase
    result = re.sub(r'(\w)- (\w)', lambda m: m.group(1) + m.group(2), result)
    return result


def main():
    if not PDF_PATH.exists():
        print(f"PDF not found: {PDF_PATH}")
        print("Run the LaTeX build first:")
        print("  cd .tmp/tex-build && lualatex ... && biber ... && lualatex ...")
        sys.exit(1)

    print(f"Extracting citations from {PDF_PATH}...")
    blocks = extract_citations_from_pdf(PDF_PATH)
    print(f"Found {len(blocks)} citation text blocks")

    # Group by page and show
    by_page = {}
    for block in blocks:
        by_page.setdefault(block['page'], []).append(block['text'])

    for page, texts in sorted(by_page.items())[:10]:
        print(f"\n=== Page {page} ===")
        for t in texts[:5]:
            print(f"  {t[:100]}")
        if len(texts) > 5:
            print(f"  ... +{len(texts)-5} more lines")


if __name__ == '__main__':
    main()
