# SBL Citation Style for Pandoc

A comprehensive implementation of the [Society of Biblical Literature Handbook of Style](https://www.sbl-site.org/publications/SBLHandbookofStyle.aspx) (SBLHS, 2nd edition) for [pandoc](https://pandoc.org/) citeproc. Based on the upstream CSL style with extensions for ancient texts, lexicons, papyri, church fathers, abbreviation lists, and shorthand references.

The reference implementation is the [`biblatex-sbl`](https://ctan.org/pkg/biblatex-sbl) LaTeX package. This project provides equivalent functionality for pandoc users, with output to Word, typst, HTML, and other formats.

## Quick start

```bash
pandoc document.md \
  --citeproc \
  --bibliography=your-bibliography.yaml \
  --csl=society-of-biblical-literature-fullnote-bibliography.csl \
  --lua-filter=sbl-filter.lua \
  --citation-abbreviations=sbl-abbreviations-extended.json \
  -o document.pdf
```

## What you get without the Lua filter

The CSL file alone works with **any citeproc implementation** (Zotero, Mendeley, pandoc, etc.) and produces correct output for:

- Books, articles, chapters, reviews, theses, conference papers
- Journal abbreviations in notes (full titles in bibliography)
- Reprint chains with "repr. of" / "orig." formatting
- Forthcoming works, reviews, magazine articles
- Position-aware `annote`: first citations use custom text, subsequent citations use normal short form

See [examples/sbl-examples-csl-only.pdf](examples/sbl-examples-csl-only.pdf) for CSL-only output.

## What the Lua filter adds

With `sbl-filter.lua` (pandoc only):

- **Shorthand references** (BDAG, BDB, HALOT, etc.) replace full citations in notes
- **Shorthand labels** prepended to bibliography entries
- **skipbib**: entries suppressed from bibliography (classical text variants, papyri abbreviations)
- **Abbreviation list**: generated at `# Abbreviations {#sbl-abbreviations}` heading
- **Subsequent note refinement**: translator/series suffixes and replacements
- **Italic maintitle**: "vol. X of *Title*" with italic collection title
- **Bibliography override**: `bibliography_annote` replaces an entry's bibliography text for non-standard formats

See [examples/sbl-examples-full.pdf](examples/sbl-examples-full.pdf) for full output with the Lua filter.

## Files

| File | Purpose |
|------|---------|
| `society-of-biblical-literature-fullnote-bibliography.csl` | Modified SBL CSL style (works with any citeproc) |
| `sbl-filter.lua` | Pandoc Lua filter for SBL-specific enhancements |
| `ld-author-index.lua` | Author index filter (Word, typst, HTML) |
| `sbl-abbreviations.json` | 1,284 SBLHS abbreviations (standard) |
| `sbl-abbreviations-extended.json` | 1,847 abbreviations (standard + Zacharias 2nd ed. data) |
| `sbl-examples.yaml` | Reference bibliography (133 entries, CSL YAML) |
| `sbl-examples.json` | Same bibliography in CSL JSON format |
| `sbl-examples.md` | Comprehensive example document (49 sections) |

## Architecture

The system uses three layers, prioritising CSL portability:

1. **CSL style** — Works with any citeproc. Handles standard formatting, position-aware annote, review/magazine/encyclopedia types.
2. **Bibliography data** (`sbl:` namespace in `note` field) — All SBL-specific metadata: shorthand, skipbib, xref, entrysubtype, subsequent note variants.
3. **Lua filter** — Pandoc-specific enhancements. Reads `sbl:` metadata for advanced features.

## Bibliography data format

Standard CSL fields are used wherever possible. SBL-specific metadata goes in a structured `sbl:` block within the `note` field:

```yaml
- id: beyer:diakoneo+diakonia+ktl
  type: entry-dictionary
  author:
    - family: Beyer
      given: Hermann W.
  title: "διακονέω, διακονία, κτλ"
  container-title: Theological Dictionary of the New Testament
  volume: "2"
  page: "81-93"
  annote: 'Hermann W. Beyer, "διακονέω, διακονία, κτλ," <i>TDNT</i> 2:81–93'
  note: |
    sbl:
      shorthand: TDNT
      xref: TDNT
```

See [CSL-JSON-GUIDE.md](CSL-JSON-GUIDE.md) for the complete data format reference, including SQLite schema design for applications producing CSL JSON.

## Abbreviation lists

Two lists for pandoc's `--citation-abbreviations` flag:

| File | Entries | Source |
|------|---------|--------|
| `sbl-abbreviations.json` | 1,284 | SBLHS 1st edition + supplements |
| `sbl-abbreviations-extended.json` | 1,847 | Above + Danny Zacharias SBLHS 2nd edition data |

## Author index

The `ld-author-index.lua` filter generates an author index from citations. Place `# Author Index {#author-index}` where the index should appear.

| Output | Mechanism |
|--------|-----------|
| Word (.docx) | XE fields — real page numbers (update with Ctrl+A, F9) |
| Typst | in-dexter `#index[]` — real page numbers |
| HTML | Static definition list with footnote numbers |

This filter is also available standalone at [pandoc-filters](https://github.com/lyndondrake/pandoc-filters).

## Quarto

```yaml
---
bibliography: bibliography.yaml
csl: society-of-biblical-literature-fullnote-bibliography.csl
citation-abbreviations: sbl-abbreviations-extended.json
citeproc: false
filters:
  - quarto
  - citeproc
  - sbl-filter.lua
  - ld-author-index.lua
---
```

See [INTEGRATION-NOTES.md](INTEGRATION-NOTES.md) for detailed Quarto and typst integration guidance.

## Running tests

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
TMPDIR=.tmp/ .venv/bin/python -m pytest tests/ -k "sbl-fullnote" --tb=short -v
```

Current results: 259 of 259 SBL fullnote tests passing (100%).

## CSL modifications from upstream

| Change | Rationale |
|--------|-----------|
| Position-aware annote | First citation uses custom text; subsequent uses normal short form |
| Review/magazine type handling | Added to article-journal formatting branches |
| Encyclopedia bibliography format | Expanded "Pages X–Y in *Title*. Edited by Editor." |
| Reprint chain reordering | Current publisher first, then "repr. of" original |
| Series abbreviations in roman | Not italic for short-form collection titles |
| Full journal titles in bibliography | Abbreviations in notes only |
| Forthcoming support | `status` variable outputs "forthcoming" |
| Classic/document italic titles | Added to italic type lists |
| Magazine issue format | `, no. 2` instead of `.2` |
| Untitled review support | Handles reviews with reviewed-author but no title |

This is a modified version of the upstream CSL style. Changes are additive and backward-compatible. We intend to contribute compatible improvements upstream to the [CSL styles repository](https://github.com/citation-style-language/styles).

## For developers

- [CSL-JSON-GUIDE.md](CSL-JSON-GUIDE.md) — SQLite schema and CSL JSON production guide
- [scripts/README.md](scripts/README.md) — Maintenance script documentation
- [INTEGRATION-NOTES.md](INTEGRATION-NOTES.md) — Quarto and typst integration research

## Acknowledgements

- [biblatex-sbl](https://ctan.org/pkg/biblatex-sbl) by David Purton — the reference implementation
- Upstream CSL contributors: Julian Onions, Simon Kornblith, Elena Razlogova, Sebastian Karcher, Tyler Mykkanen, J. David Stark
- Danny Zacharias — SBLHS 2nd edition abbreviation data

## License

CC-BY-SA-3.0. See [LICENSE](LICENSE).
