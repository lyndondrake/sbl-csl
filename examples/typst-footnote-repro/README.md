# Typst footnote-citation repro (typst/typst#8126, PR #8147)

Minimal reproduction of note-class CSL citations inside explicit
footnotes, using the SBL fullnote style. Prepared for the comment on
typst PR #8147 (see `docs/upstream-submissions-2026-07.md`).

To compile, copy the CSL file alongside these files first:

```bash
cp ../../society-of-biblical-literature-fullnote-bibliography.csl .
typst compile repro.typ
```

Observed 3 July 2026:

- **typst 0.15.0 (3ae52774)**: the citation inside the explicit footnote
  spawns a nested footnote — the note renders as "See further³." with
  the citation exiled to footnote 3.
- **PR #8147 branch (4cc24510)**: the citation renders inline within the
  footnote, taking the correct subsequent (short) form.
