# Upstream submission drafts — 3 July 2026

Five drafts, ordered by leverage. Items 1, 3, 4, and 5 can be posted as-is.
Item 2 needs a local test run first (instructions included) to fill in the
observed results before posting.

---

## 1. Comment on typst/hayagriva#489 (Restructure Hayagriva as a Workspace)

> This restructure — particularly the `hayagriva-json` crate with an
> `EntryLike` implementation for CSL-JSON — is exactly what's needed for
> typst to become viable for full-note academic styles, so thank you for
> taking it on.
>
> I maintain an SBL (Society of Biblical Literature) citation system for
> pandoc/citeproc (https://github.com/lyndondrake/sbl-csl) and am preparing
> a monograph for an SBL Press series. I'd be glad to test `hayagriva-json`
> against its reference corpus: ~150 CSL-JSON entries covering the SBL
> Handbook of Style examples, with the edge cases that tend to break
> CSL-JSON consumers:
>
> - name particles (`non-dropping-particle: von`), corporate authors, and
>   `literal` names;
> - date ranges (`"date-parts": [[1918], [1929]]`) and uncertain dates;
> - non-Latin titles (Greek and Hebrew) and mixed-script fields;
> - `title-short` / `container-title-short` / `collection-title-short`;
> - structured metadata carried in the `note` field (which should survive
>   round-tripping untouched);
> - `original-publisher` / `original-date` reprint chains.
>
> The corpus has a matching expected-output test suite (863 cases against
> a note-class CSL style), so it can serve as an end-to-end fixture rather
> than just a parsing smoke test. Happy to run the branch against it and
> report issues here, or to contribute a subset as test data if that's
> useful — whichever helps most.

---

## 2. Comment on typst/typst#8147 (Do not emit note-style citations when already in a footnote)

**Tested 3 July 2026** on typst 0.15.0 (3ae52774, release binary) and the
PR branch (4cc24510, built from source on aarch64). Results are filled in
below — ready to post.

Files: `repro.typ` +
`society-of-biblical-literature-fullnote-bibliography.csl` (from
https://github.com/lyndondrake/sbl-csl) + a one-entry `works.bib`:

```bibtex
@book{talbert,
  author    = {Talbert, Charles H.},
  title     = {Reading John: A Literary and Theological Commentary},
  publisher = {Crossroad},
  year      = {1992},
}
```

```typst
// repro.typ — note-class CSL style, citation inside an explicit footnote
#set page(width: 14cm, height: auto)

Auto-noted citation.#cite(<talbert>)

Discursive note containing a citation.#footnote[
  See further #cite(<talbert>, supplement: [127]).
]

#bibliography("works.bib",
  style: "society-of-biblical-literature-fullnote-bibliography.csl")
```

> Adding a real-world data point from an academic full-note workflow. I'm
> preparing a monograph in SBL style (Society of Biblical Literature —
> a `class="note"` CSL style, as used across biblical studies and much of
> the humanities), where the pattern this PR fixes is not an edge case:
> discursive footnotes that also cite something ("See further Talbert,
> *Reading John*, 127.") occur on nearly every page of a typical
> manuscript.
>
> Minimal repro with the SBL CSL style attached below.
>
> **On typst 0.15.0 (3ae52774):** compiles without a panic, but the
> citation inside the explicit footnote spawns a *nested* footnote — the
> discursive note renders as just "See further³." with the citation
> content exiled to a separate footnote 3:
>
> ```
> ²See further³.
> ³Talbert, Reading John: A Literary and Theological Commentary, 127.
> ```
>
> **On this branch (4cc24510):** fixed. The citation renders inline
> inside the explicit footnote, and position tracking is preserved (it
> correctly takes the subsequent/short form, since the auto-noted
> citation in footnote 1 came first):
>
> ```
> ²See further Talbert, Reading John: A Literary and Theological Commentary, 127..
> ```
>
> The auto-noted citation still becomes its own footnote with the full
> first-citation form in both builds, as expected.
>
> One small adjacent observation (arguably out of scope): the note
> layout's terminal period is still emitted when the citation renders
> inline, so an author who ends their own sentence with "." gets "127.."
> — suppressing the layout suffix for in-footnote citations, or leaving
> it to authors, may be worth a note in the docs.
>
> With this fix in place, note-class CSL styles become usable for real
> humanities manuscripts, where mixing auto-noted citations and discursive
> footnotes-with-citations is the norm rather than the exception.
>
> [attach repro.typ, works.bib, CSL file]

---

## 3. New issue on typst/hayagriva — CSL abbreviation lists (citation-abbreviations)

**Title:** Support CSL abbreviation lists (journal/series abbreviations à la citeproc-js abbreviation filters)

> ## Problem
>
> Humanities note styles (SBL, Chicago fullnote variants, and most
> biblical-studies/classics house styles) abbreviate journal and series
> titles in citations while printing the full title in the bibliography:
>
> - note: `Gary N. Knoppers, "Prayer and Propaganda," *CBQ* 57 (1995): 229–54`
> - bibliography: `… Catholic Biblical Quarterly 57 (1995): 229–54.`
>
> The abbreviation sets are large and standardised (the SBL Handbook of
> Style defines ~1,800 journal/series abbreviations), so they are
> maintained as external lists rather than per-entry data.
>
> Hayagriva currently has no way to supply such a list. Per-entry
> `short` forms in the Hayagriva format can encode one-off cases, but
> (a) they don't exist for CSL-JSON input, and (b) duplicating a
> standard 1,800-entry mapping into every user's bibliography data is
> the wrong layer.
>
> ## Prior art
>
> - **citeproc-js** "abbreviation filters": a JSON object keyed by
>   category (`container-title`, `collection-title`, …) mapping full
>   form → short form, consulted whenever the style requests
>   `form="short"` and the entry lacks an explicit short field.
>   https://citeproc-js.readthedocs.io/en/latest/running.html#abbreviation-filters
> - **pandoc/citeproc** exposes the same mechanism as
>   `--citation-abbreviations=file.json`.
>
> Example (pandoc/citeproc-js format):
>
> ```json
> {
>   "default": {
>     "container-title": {
>       "Catholic Biblical Quarterly": "CBQ",
>       "Journal of Biblical Literature": "JBL"
>     },
>     "collection-title": {
>       "Society of Biblical Literature Dissertation Series": "SBLDS"
>     }
>   }
> }
> ```
>
> ## Proposal
>
> Accept an optional abbreviation mapping (the citeproc-js JSON format
> would maximise ecosystem compatibility) at render time; when a CSL
> style requests the short form of a variable, resolve: entry short field
> → abbreviation list → full form. In typst this could surface as an
> optional `abbreviations:` argument to `bibliography()`.
>
> ## Offer
>
> I maintain the SBL abbreviation dataset in this format (1,847 entries,
> CC-BY-SA, https://github.com/lyndondrake/sbl-csl —
> `sbl-abbreviations-extended.json`) plus a reference bibliography and
> expected-output test suite, and am happy to contribute test fixtures or
> help spec the lookup semantics.

---

## 4. Comment on typst/hayagriva#286 (Consecutive citations use a wrong CSL position definition)

> A note from the SBL (Society of Biblical Literature) style perspective:
> this bug's blast radius is wider than ibid rendering. SBL fullnote
> *disables* ibid entirely, but depends completely on correct
> `position="first"` vs `position="subsequent"` tracking — first citation
> prints the full form ("Charles H. Talbert, *Reading John: A Literary and
> Theological Commentary* (Crossroad, 1992), 127"), every later citation
> the short form ("Talbert, *Reading John*, 22"). If consecutive citations
> are classified as `ibid`/`ibid-with-locator` when the style only tests
> `subsequent`, styles like SBL still work by accident (ibid positions
> imply subsequent), but any misclassification in the other direction —
> or position state leaking across footnotes — silently produces
> full-form repeats or premature short forms, which a copy-editor will
> catch one at a time.
>
> Happy to contribute test cases: the SBL fullnote CSL plus a
> first/subsequent expectation set is available at
> https://github.com/lyndondrake/sbl-csl (863-case suite, CC-BY-SA), and
> I can distil a minimal position-tracking fixture (cite A, cite B,
> cite A again → expect full, full, short) if that's useful.

---

## 5. Comment on typst/typst#8316 (Allow for pluggable citation backends?)

> Requirements data point: I maintain an SBL (Society of Biblical
> Literature) citation system currently implemented as pandoc + citeproc
> + Lua filters (https://github.com/lyndondrake/sbl-csl), and am watching
> this discussion as the path to doing the same natively in typst. For a
> full-note humanities style, a pluggable backend would need, roughly in
> order of importance:
>
> 1. **Note placement** — citations auto-wrapped in footnotes
>    (`class="note"` CSL), composing correctly with citations inside
>    explicit footnotes (#8126/#8147).
> 2. **Position tracking** — first vs subsequent (and near-note) state,
>    exposed to the backend; entire styles hinge on it (#286 in
>    hayagriva).
> 3. **External abbreviation lists** — journal/series abbreviations
>    resolved at render time, not baked into entry data.
> 4. **Per-entry render overrides** — hooks to replace a citation or
>    bibliography entry wholesale for the long tail of special formats
>    (ancient texts, papyri, reference-work shorthands). In our pandoc
>    system this is a post-citeproc filter layer; a backend API that
>    exposes "about to emit citation for key X, here's the default
>    rendering" would subsume it.
> 5. **Bibliography-adjacent lists** — generating an abbreviations list
>    (shorthand → full entry) alongside the bibliography.
>
> If a draft API materialises, I'm happy to prototype the SBL style
> against it — it exercises most of the hard cases (note class, position
> tracking, abbreviations, per-entry overrides) in one style.

---

## Parked observations (for the PR #489 test engagement)

Noticed while testing #8147 on 3 July 2026, out of scope for the drafts
above but worth raising once the hayagriva CSL-JSON work is engaged:

1. **Stray semicolon before the publication parenthetical.** With the
   SBL fullnote CSL, hayagriva renders the first note as
   "…Reading John: A Literary and Theological Commentary**;** (Crossroad,
   1992)" — pandoc/citeproc renders the same style with no semicolon.
   Present in both typst 0.15.0 and the PR #8147 build, so it is a
   hayagriva CSL-rendering divergence (likely group-delimiter handling),
   not related to footnote placement. Repro: `examples/typst-footnote-repro/`.
2. **Note-layout terminal period emitted for inline citations** — the
   "127.." doubling already noted in the #8147 draft comment.
