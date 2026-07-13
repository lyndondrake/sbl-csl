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

For PDF output via typst with Greek/Hebrew support, use [Noto Serif](https://fonts.google.com/noto/specimen/Noto+Serif) (OFL, full italic/bold) with [SBL BibLit](https://www.sbl-site.org/educational/BiblicalFonts_SBLBibLit.aspx) (freely available) as fallback for Greek and Hebrew glyphs:

```bash
pandoc document.md \
  --citeproc \
  --bibliography=your-bibliography.yaml \
  --csl=society-of-biblical-literature-fullnote-bibliography.csl \
  --lua-filter=sbl-filter.lua \
  --citation-abbreviations=sbl-abbreviations-extended.json \
  --pdf-engine-opt="--font-path=/path/to/noto-serif" \
  --pdf-engine-opt="--font-path=/path/to/sbl-biblit" \
  -V mainfont:"Noto Serif" \
  -o document.pdf -t typst
```

Typst automatically falls back to SBL BibLit for Greek (διακονέω) and Hebrew (בָּרָא) characters not covered by Noto Serif.

## What you get without the Lua filter

The CSL file alone works with **any citeproc implementation** (Zotero, Mendeley, pandoc, etc.) and produces correct output for:

- Books, articles, chapters, reviews, theses, conference papers
- Journal abbreviations in notes (full titles in bibliography)
- Reprint chains: original publication first, then "repr.," and the current publisher (SBLHS §6.2.17–18)
- Name particles: cited as "von Rad", alphabetised as "Rad, Gerhard von" (`non-dropping-particle`)
- Forthcoming works, reviews, magazine articles
- Position-aware `annote`: first citations use custom text, subsequent citations use normal short form

See [examples/sbl-examples-csl-only.pdf](examples/sbl-examples-csl-only.pdf) for CSL-only output.

## What the Lua filter adds

With `sbl-filter.lua` (pandoc only):

- **Shorthand references** (BDAG, BDB, HALOT, etc.) replace full citations in notes
- **Shorthand labels** prepended to bibliography entries
- **Location suppression**: publisher place omitted for works published 1900 or later, in notes as well as bibliography, including original/reprint segments (SBLHS Blog update, as implemented by biblatex-sbl v2)
- **skipbib**: entries suppressed from bibliography (classical text variants, papyri abbreviations)
- **Abbreviation list**: generated at `# Abbreviations {#sbl-abbreviations}` heading; sigla entries print without trailing periods, bibliography-style entries keep theirs
- **Subsequent note refinement**: translator/series suffixes and replacements
- **Italic maintitle**: "vol. X of *Title*" with italic collection title
- **Bibliography override**: `bibliography_annote` replaces an entry's bibliography text for non-standard formats (also gets shorthand labels and location suppression)

See [examples/sbl-examples-full.pdf](examples/sbl-examples-full.pdf) for full output with the Lua filter.

## Files

| File | Purpose |
|------|---------|
| `society-of-biblical-literature-fullnote-bibliography.csl` | Modified SBL CSL style (works with any citeproc) |
| `sbl-filter.lua` | Pandoc Lua filter for SBL-specific enhancements |
| `ld-author-index.lua` | Author index filter (Word, typst, HTML) |
| `sbl-abbreviations.json` | 1,284 SBLHS abbreviations (standard) |
| `sbl-abbreviations-extended.json` | 1,847 abbreviations (standard + Zacharias 2nd ed. data) |
| `sbl-examples.yaml` | Reference bibliography (150 entries, CSL YAML) |
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

## Consumer contract

This section is the stable interface for tools that generate bibliographies
for this pipeline (for example ld-agent's `CSLJSONExporter`) and for projects
that build documents with it. Everything not listed here is an internal
detail and may change without notice.

**Files a consuming project needs.** The CSL style, `sbl-filter.lua`, one of
the abbreviation lists, and optionally `ld-author-index.lua` and
`ld-ancient-index.lua`. Consumers should pin the commit (or release tag) they
build against rather than tracking the working tree.

**Bibliography input.** CSL YAML or CSL JSON, selected by file extension.
The filters expect a single `bibliography` path in the document metadata —
multiple bibliography files are not supported by the filters (citeproc
itself still merges them, but the `sbl:` metadata will not load). Citekeys
are opaque strings — the filters never parse their internal structure, so
any key scheme works.

**`sbl:` note keys that `sbl-filter.lua` acts on.** All other keys inside the
`sbl:` block are parsed and then ignored silently; producers may emit extra
keys freely.

| Key | Effect |
|-----|--------|
| `shorthand` | Replaces citations with the shorthand form; labels the bibliography entry |
| `options: [skipbib]` / `skipbib: true` | Suppresses the entry from the bibliography |
| `options: [skipbiblist]` | Suppresses the entry from the abbreviation list |
| `entrysubtype` | Selects ancient-text citation templates (e.g. `inancientcollection`) |
| `subsequent_annote` | Full replacement text for subsequent citations |
| `subsequent_suffix` | Suffix appended to subsequent citations |
| `bibliography_annote` | Replaces the entry's bibliography text entirely |
| `source_type: ancient` | Files the shorthand under Ancient Sources in the abbreviation list |
| `abbreviation_type: sigla` + `definition` | Adds a sigla entry (no trailing period) to the abbreviation list |

**Note-value format.** A key without a value (e.g. `related:`) opens a
nested block: everything indented deeper than it is ignored rather than
read as entry keys. Values containing `:`, `[`, `,`, `"` or `'` must be
YAML-quoted with a matching pair: double-quoted style un-escapes `\"`
(backslashes are otherwise left alone, matching what `CSLJSONExporter`
emits), single-quoted style un-escapes `''`.

Notably **not** read by any filter: `xref`. It is a convention for
bibliography-assembly tools (scope the export so that xref-target entries are
included in the emitted file — their shorthands feed the abbreviation list);
the filters themselves never follow it. Also note the filter key is
`bibliography_annote` (snake_case): ld-agent's exporter currently emits
`bibliographyAnnote`, which is inert — tracked as an ld-agent fix.

**CSL entry fields the filters read directly** (beyond what citeproc
renders): `id`, `type`, `title`, `annote` (position-aware first-citation
text), `author`/`editor` (including `non-dropping-particle` etc., for the
author index), `collection-title`/`-short`, `container-title`/`-short`,
`publisher-place`, `original-publisher-place`, and the year of
`issued`/`original-date` (location suppression for post-1900 works).

**Document markers.** `# Abbreviations {#sbl-abbreviations}`,
`# Author Index {#author-index}` and `# Ancient Sources Index
{#ancient-index}` headings position the generated lists;
`[]{.anc section=… entry=… locus=…}` spans index non-biblical ancient
sources (`ld-ancient-index.lua` reads no bibliography at all).

This contract is exercised by `tests/test_exporter_shape.py` against a
fixture in the exact shape `CSLJSONExporter` emits.

## Abbreviation lists

Two lists for pandoc's `--citation-abbreviations` flag:

| File | Entries | Source |
|------|---------|--------|
| `sbl-abbreviations.json` | 1,284 | SBLHS 1st edition + supplements |
| `sbl-abbreviations-extended.json` | 1,847 | Above + Danny Zacharias SBLHS 2nd edition data |

## Author index

The `ld-author-index.lua` filter generates an author index from citations. Place `# Author Index {#author-index}` where the index should appear.

Name particles are demoted in index entries: an author stored with `non-dropping-particle: von` is cited as "von Rad" but indexed as "Rad, Gerhard von" (under R), while names whose particle belongs to the family field ("Van Seters") index under the particle (under V).

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

Current results: 974 passing, 2 skipped, 0 failing (976 total, including author-index, abbreviation-list, ancient-index and exporter-shape filter tests). Output is aligned with biblatex-sbl v2.0 final (April 2026), verified against its l3build regression outputs.

## CSL modifications from upstream

| Change | Rationale |
|--------|-----------|
| Position-aware annote | First citation uses custom text; subsequent uses normal short form |
| Review/magazine type handling | Added to article-journal formatting branches |
| Encyclopedia bibliography format | Expanded "Pages X–Y in *Title*. Edited by Editor." |
| Reprint chains | Original publication first, then "repr.," current publisher (notes) / "Repr.," (bibliography), per SBLHS §6.2.17–18 and biblatex-sbl v2 |
| Name particles demoted | `demote-non-dropping-particle="display-and-sort"`: "von Rad" in citations, "Rad, Gerhard von" in bibliography (biblatex-sbl v2 issue 153) |
| Locator label spacing | "fig. 2", not "fig.2"; section locators keep "§110a" unspaced |
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
