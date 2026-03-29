# Integration Notes: Quarto and Typst

Research notes on integrating the SBL citation system with Quarto and standalone typst.

## Quarto

### What works today

The three core components (CSL, abbreviation JSON, Lua filter) all have direct YAML equivalents in Quarto. Word (.docx) XE index fields work — Quarto uses the same pandoc docx writer.

### Filter ordering (the critical challenge)

Quarto's internal pipeline doesn't clearly guarantee filters run after citeproc. The workaround:

```yaml
citeproc: false
filters:
  - quarto
  - citeproc
  - sbl-filter.lua
  - ld-author-index.lua
```

This explicitly places citeproc in the filter chain. This pattern is used by the `recursive-citeproc` extension. Needs testing with the SBL filters.

### Configuration

Single document:
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

Book project (`_quarto.yml`):
```yaml
project:
  type: book
book:
  chapters:
    - index.qmd
    - abbreviations.qmd
    - chapter1.qmd
    - references.qmd
    - author-index.qmd
bibliography: bibliography.yaml
csl: society-of-biblical-literature-fullnote-bibliography.csl
citation-abbreviations: sbl-abbreviations-extended.json
citeproc: false
filters:
  - quarto
  - citeproc
  - sbl-filter.lua
  - ld-author-index.lua
```

### Extension packaging

Could be packaged as a Quarto custom format extension:
```
_extensions/sbl-fullnote/
├── _extension.yml
├── society-of-biblical-literature-fullnote-bibliography.csl
├── sbl-filter.lua
├── ld-author-index.lua
├── sbl-abbreviations.json
└── sbl-abbreviations-extended.json
```

### Known limitations

- **Multi-page HTML books**: Lua filters not applied to bibliography in `references.html` (open bug quarto-dev/quarto-cli#10180)
- **Filter ordering in extensions**: metadata merging behaviour for `citeproc: false` within an extension needs verification
- **`sbl-filter.lua` bibliography path**: filter opens YAML file directly via `io.open` — path resolution may differ in Quarto extension context

### Typst via Quarto

Must set `citeproc: true` to force pandoc's citeproc instead of typst's native bibliography. Lua filters work on the pandoc AST before the typst writer. Static footnote-number indices only (no typst equivalent of Word's XE fields).

## Standalone Typst

### Current state

Typst has built-in CSL support and can load our CSL file directly:
```typst
#set bibliography(style: "society-of-biblical-literature-fullnote-bibliography.csl")
```

However, several gaps make a fully standalone implementation infeasible today.

### Critical blockers

1. **No CSL JSON input**: Typst reads Hayagriva YAML and BibTeX only. Our CSL YAML/JSON bibliography cannot be used directly. Open feature request (typst/typst#2924), developers "open to it" but no timeline.

2. **Footnote placement not automatic**: Note-style CSL (`class="note"`) doesn't auto-place citations in footnotes. Requires a fragile show-rule workaround. Full footnote-style bibliography support is not implemented (typst/typst#4994).

3. **No Lua filter equivalent**: All post-citeproc transforms (shorthand replacement, skipbib, abbreviation list, subsequent note enhancement) would need reimplementation in typst scripting.

4. **No abbreviation list generation**: No equivalent to BibLaTeX's `\printbiblist`. Would need building from scratch.

5. **No automatic author index from citations**: The `in-dexter` community package handles manual index entries but cannot extract author names from citations automatically.

### What does work

- CSL file loading and basic CSL processing
- Ibid handling (substantially improved in hayagriva 0.9.x)
- The `in-dexter` package for manual indexing
- BibTeX input (so a CSL→BibTeX conversion path exists, though lossy)

### Recommended path

**Near term**: Use pandoc + citeproc + Lua filter with typst as output format. This preserves the entire three-layer architecture. The Lua filter would need updates to emit `pandoc.RawInline('typst', ...)` for format-specific content.

**Future**: A fully standalone typst SBL implementation becomes feasible when typst adds CSL JSON input support and reliable footnote-style bibliography placement. At that point, the `sbl:` metadata could be stored in the Hayagriva `note` field and processed via typst scripting packages like `pergamon` or `citegeist`.

### Conversion tools

No direct CSL JSON ↔ Hayagriva converter exists. Available paths:
- CSL YAML → (custom script) → BibTeX → hayagriva CLI → Hayagriva YAML (lossy)
- CSL JSON → Citation.js → BibTeX → hayagriva CLI → Hayagriva YAML (lossy)

The `sbl:` namespace metadata in the `note` field would survive as a plain string but needs typst-side parsing.

## Summary

| Feature | Quarto | Standalone Typst |
|---------|--------|-----------------|
| CSL style | ✓ works | ✓ works (can load CSL file) |
| CSL JSON bibliography | ✓ via citeproc | ✗ not supported as input |
| Lua filter | ✓ works (ordering needs care) | ✗ no equivalent |
| Abbreviation list | ✓ works | ✗ no equivalent |
| Author index (Word) | ✓ XE fields work | n/a |
| Author index (other) | ✓ static def list | ✗ no auto-extraction |
| Footnote citations | ✓ via citeproc | ⚠ fragile workaround |
| Book projects | ✓ PDF/docx work well | n/a |
| Extension packaging | ✓ custom format extension | n/a |

**Quarto is the clear near-term path.** Standalone typst needs CSL JSON input and reliable footnote citations before it's viable.
