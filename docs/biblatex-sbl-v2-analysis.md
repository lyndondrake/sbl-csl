# biblatex-sbl v2 Analysis

## Overview

biblatex-sbl v2 (main branch) is a **complete rewrite** from scratch — there
is no common ancestor with the legacy branch (v0.x series, up to v0.15). The
v2 branch has 280 commits. The README explicitly states: "version 2.0 and
later of biblatex-sbl completely breaks compatibility with the version 0.x
releases."

The v2 branch targets the **second edition** of the SBL Handbook of Style
(SBLHS2), including rolling updates from the SBLHS Blog (https://sblhs2.com/).

## Structural changes

### Base style

- **Legacy**: built on `standard` bibliography style; citation style was
  custom (no base citation style)
- **v2**: built on `verbose-ibid` for both BBX and CBX

### File layout

- **Legacy**: files in `latex/` subdirectory; docs in `doc/`; tests in
  `test/` using PDF reference comparison
- **v2**: files in repository root; tests use `l3build` framework
  (`testfiles/` with `.lvt`/`.tlg` pairs); no German or Spanish localisation
  files (only English and American)

### Dependencies

- **v2 adds**: `biblatex-source-division` package (for source division
  parsing from postnotes), `xpatch`
- **v2 removes**: no longer checks for minimum biblatex version; requires
  Biber 3+

### Test framework

- **Legacy**: 5 PDF reference files compared via `Makefile`
- **v2**: ~170 l3build test files covering sections 6.x, 7.x, 8.x of SBLHS2
  (each section gets multiple test variants)

## Entry types

### Removed entry types

| Type | Notes |
|------|-------|
| `classictext` | Merged into `ancienttext` with entrysubtypes |
| `conferencepaper` | Mapped to `unpublished` |
| `seminarpaper` | Mapped to `unpublished` |
| `lexicon` / `mvlexicon` / `inlexicon` | Replaced by `reference` / `mvreference` / `inreference` |

### New entry types

| Type | Purpose |
|------|---------|
| `abbreviation` | Sigla, grammatical abbreviations, acronyms (e.g. `abl.` = ablative) |
| `series` | Standalone series entries (always skipbib) |
| `video` | Film, DVD, streaming content (with `invideo` subtype) |
| `review` | Book reviews (was already in legacy but now a proper entry type) |

### Changed entry types

| Type | Change |
|------|--------|
| `commentary` / `mvcommentary` | Now aliases for `book` (was separate) |
| `incommentary` | Now alias for `inbook` (with xref mapping to `inreference`) |
| `inproceedings` | Falls through to `inseries` (if no `booktitle`) or `incollection` |
| `inreference` | Expanded: supports both long form (`incollection` driver) and short form with xref shorthand |

### New entry subtypes for `ancienttext`

| Subtype | Purpose |
|---------|---------|
| `inancientcollection` | Text in a modern collection (e.g. COS, ANET, AEL) |
| `ancientbook` | Complete ancient work in a collection (e.g. Clementine Homilies in ANF) |
| `inancientbook` | Part of an ancient work in a collection (e.g. Eusebius, Life of Constantine in NPNF) |
| `comment` | Social media comment on a blog post |
| `blog` | Blog post (for `@online` type) |
| `invideo` | Segment within a video (e.g. DVD commentary track) |

Legacy subtypes removed: `churchfather`, `inscription`, `chronicle`,
`COS`, `ANRW`, `RIMA`, `primarysource`.

## Fields

### New fields

| Field | Type | Purpose |
|-------|------|---------|
| `datemodifier` | literal | Prefix for approximate dates (e.g. "ca.") |
| `definition` | literal | Definition text for `@abbreviation` entries |
| `parts` | literal | Number of physical parts |
| `printing` | literal | Printing number (distinct from edition) |
| `text` | literal | Text number within a collection (e.g. COS 1.26) |
| `translatedtitle` | literal | Title translation (displayed in brackets) |
| `translatedshorttitle` | literal | Short form of translated title |
| `translatedsubtitle` | literal | Subtitle translation |
| `translatedbooktitle` | literal | Book title translation |
| `translatedbooksubtitle` | literal | Book subtitle translation |
| `translatedmaintitle` | literal | Main title translation |
| `translatedmainsubtitle` | literal | Main subtitle translation |
| `website` | literal | Website name (for online entries) |
| `xrefstring` | literal | String to print before xref citation |
| `shortmaintitle` | literal (label) | Abbreviated form of maintitle |
| `postnominal` | namepart | Post-nominal letters (e.g. Jr., SJ) |
| `shortfamily` | namepart | Short form of family name |
| `preface` | name list | Preface author |
| `withauthor` | name list | "with" collaborator for authors |
| `witheditor` | name list | "with" collaborator for editors |
| `withbookauthor` / `withbookeditor` | name lists | "with" collaborators for book-level names |
| `withmainauthor` / `withmaineditor` | name lists | "with" collaborators for main-level names |
| `withauthortype` etc. | literal | Type strings for "with" collaborators |

### Removed fields

| Field | Notes |
|-------|-------|
| `seriesseries` | No longer needed |
| `shortbooktitle` | Replaced by translatedbooktitle mechanism |
| `shortissuetitle` | No longer needed |
| `withtranslator` / `withbooktranslator` / `withmaintranslator` | Simplified |
| `withtranslatortype` etc. | Simplified |
| `eprintdate` / `eprintday` / `eprintmonth` / `eprintyear` | Removed as separate date fields |

## Options

### Changed default options

| Option | Legacy | v2 |
|--------|--------|----|
| Base style | `standard` | `verbose-ibid` |
| `citetracker` | `true` (global) | `context` |
| `idemtracker` | `sbl` (custom) | `citation` (custom redefinition) |
| `sorting` | default | `nwty` (new sorting template including withauthor/witheditor) |
| `isbn` | `false` | `false` (now set in cbx) |
| `uniquework` | not set | `true` |
| `mincrossrefs` | not set | `2` |
| `minxrefs` | `1` | `1` |
| `citepages` | `sbl` (custom) | `omit` (with custom `separate` available) |
| `language` | `american` | `american` |

### Removed options

| Option | Notes |
|--------|-------|
| `sblfootnotes` | No longer a package option |
| `usefullcite` | Replaced by `\fullcite` command family |
| `useshorttitle` | Always uses short title when available |
| `usevolume` | Always uses volume |
| `useseries` | Always uses series |
| `accessdate` | Removed |
| `shorthand` | Always enables shorthands |
| `dashed` | Always uses author dash in bibliography |
| `fullbibrefs` | Still exists as toggle for inreference/incommentary |
| `pagination` / `bookpagination` | Global options removed; entry-level still works |

### New options

| Option | Type | Purpose |
|--------|------|---------|
| `nonlatintitle` | entry, boolean | Format title without italics (for non-Latin scripts) |
| `nonlatinbooktitle` | entry, boolean | Same for booktitle |
| `nonlatinmaintitle` | entry, boolean | Same for maintitle |
| `shorthandformat` | entry, string | Override shorthand field format |
| `usetitle` | type/entry, boolean | Control whether title appears in bibliography (for multivolume works) |
| `usexref` | entry, boolean | Control whether xref is used |
| `nametracker` | global/type/entry | Custom name tracker (context/strict/constrict) for author deduplication |

## Citation formatting

### Subsequent notes (short form)

**Legacy**: Complex per-entry-type macros with `blx@usefullcite` toggle
checked at every point.

**v2**: Cleaner architecture using `verbose-ibid` as base. Short citations
print `Author, Short Title, postnote`. The `\fullcite` family of commands
uses `\AtNextCite` to temporarily override tracking. Key changes:

- `\ifciteseen` drives the full/short decision
- Cross-reference tracking (`\ifcrossrefseen`) is new — when a parent work
  has been cited, child entries can use the short form of the parent
- `cite:full:*:seen` macros handle the case where a cross-referenced parent
  is already known (print child author + title + "vol. X of" Parent Short)
- The `uniquework` option disambiguates same-author works

### Ibid handling

Both versions disable ibid by default (`ibidtracker=false`). v2 uses the
`verbose-ibid` base style which provides the infrastructure but the style
disables it.

### Idem handling

- **Legacy**: Custom `idemtracker=sbl` implementation
- **v2**: Redefines `idemtracker=citation` to work per-context (footnote vs.
  body text), tracking last name hash separately for each context

### Name tracking

v2 introduces a completely new **name tracker** system:
- Tracks whether an author name has been seen before
- On first occurrence: prints "Given Family" (full form)
- On subsequent occurrences: prints "Family" (short form)
- Works per-context (footnote/body text) with `nametracker=context`
- Provides `\citeauthorreset` command

### fullcite system

**Legacy**: `\fullcite`, `\fullcite*`, `\footfullcite`, `\footfullcite*`
only.

**v2**: Comprehensive fullcite family with every citation variant:
- `\fullcite`, `\pfullcite`, `\ffullcite`, `\ftfullcite`, `\sfullcite`, `\afullcite`
- `\fullcites`, `\pfullcites`, etc. (multi-cite variants)
- `\volfullcite`, `\pvolfullcite`, etc. (volcite variants)
- `\Fullcite`, `\Pfullcite`, etc. (capitalising variants)
- All combinations of the above

### transcite system (new)

v2 introduces `\transcite` commands for citing ancient texts with translators:
- `\transcite`, `\ptranscite`, `\ftranscite`, `\fttranscite`, `\stranscite`, `\atranscite`
- Multi-cite and volcite variants
- Capitalising variants
- Combination fullcite+transcite variants
- `\citecollection` / `\parencitecollection` for citing the text collection
  portion of an ancient text

### smartcite in footnotes (new)

v2 redefines `\smartcite` behaviour when already inside a footnote:
- First unseen citation: adds period + space + "See" + full citation
- First seen citation: adds parenthesised short citation
- Handles parenthesis balancing automatically

### Other new citation commands

| Command | Purpose |
|---------|---------|
| `\citeauthor` / `\citeauthor*` | Print author name (full form / first name only) |
| `\citeshortauthor` / `\citeshortauthor*` | Print author name (short form) |
| `\citefullauthor` / `\citefullauthor*` | Print author name (always given-family form) |
| `\Citefullauthor` / `\Citeshortauthor` | Capitalising variants |
| `\citetitle` / `\citetitle*` | Print title (short/full form) |
| `\citejournal` / `\citejournal*` | Print journal abbreviation/full name |
| `\citeseries` / `\citeseries*` | Print series abbreviation/full name |
| `\citeshorthand` / `\abbrev` | Print shorthand (nestable within citations) |
| `\cite*` | Suppress author in citation (starred variants for all cite commands) |

## Bibliography formatting

### Key changes

1. **Location suppression**: v2 automatically clears location for books
   published after 1900 (SBLHS Blog update).

2. **Publisher+location merging**: v2 uses a sophisticated list-merging
   system (`mergelists` macro) to interleave location and publisher lists
   (e.g. "London: SCM; Louisville: Westminster John Knox").

3. **Parentheses in notes**: Publication details in notes are wrapped in
   parentheses; bibliography entries use periods as unit separators.

4. **Name dash**: v2 includes withauthor/witheditor tracking in the dash
   check — a new entry by the same author but different collaborator gets
   the author's name printed again (not dashed).

5. **Sorting**: New `nwty` template sorts by Name, With-author/editor,
   Title, Year, Volume.

6. **Subtitle handling**: Automatic splitting of title:subtitle via Biber
   source mapping (regex splits on unbraced colons). Intelligent subtitle
   punctuation handling (space after ? or ! rather than colon).

7. **Short title generation**: Automatic removal of "A", "An", "The" from
   titles to generate shorttitle and sorttitle via source mapping.

8. **ISBN suppression**: Set globally via `isbn=false`.

### Entry-specific changes

- **`@article`**: Integer-only issue field is moved to volume if no volume
  exists; integer issue is dropped if volume exists. Journal series uses
  slash separator. Electronic article ID (`eid`) support.

- **`@book`**: `usetitle` toggle controls whether title or maintitle
  appears first (for citing one volume of a multivolume work). New
  `parts` field distinct from `volumes`.

- **`@online`**: New `website` field. Blog entries (entrysubtype=blog)
  without website get italicised title. Comment entries
  (entrysubtype=comment) are excluded from bibliography.

- **`@review`**: Proper handling of review title + reviewed work title +
  reviewed work author/editor. Short citation prints "Review of Title" with
  label name in parentheses.

- **`@unpublished`**: Now handles `eventtitle`, `eventtitleaddon`, `venue`,
  event dates. Publication details in parentheses in notes.

- **`@video`**: New driver with support for director (via authortype),
  howpublished (DVD, Blu-ray), organization (studio), maintitle.

## Abbreviation list

### Architecture changes

- **Legacy**: Custom abbreviation list with per-entry-type checking
- **v2**: Uses biblatex's `biblist` mechanism with custom
  `abbreviations` filter and sorting template

### New features

1. **Three-section abbreviation list**: Ancient sources (shorttitle),
   secondary sources (shorthand, shortjournal, shortseries), and sigla
   (`@abbreviation` entries).

2. **Hyperlinking**: Abbreviations hyperlink to their first use. Short
   titles, short journals, short series, and shorthands all have
   target/link format pairs.

3. **Deduplication**: Same shorttitle for different entries (e.g. multiple
   ancient texts abbreviated "Josephus") are combined into a single
   abbreviation list entry showing all associated works.

4. **Width calculation**: Abbreviation list automatically calculates the
   widest abbreviation for label alignment.

5. **Source mapping for skipbib/skipbiblist**: Automatic via Biber source
   maps:
   - Entries with `shorthand` → `skipbib` (excluded from bibliography)
   - `@series` entries → `skipbib`
   - `@periodical` without title → `skipbib`
   - `@online` with entrysubtype → `skipbib`
   - `@ancienttext` without entrysubtype → `skipbiblist=false` (appears in
     abbreviation list)
   - All entries get `skipbiblist=false` to ensure related clones appear

## Ancient text handling

This is the area with the most significant changes.

### Architecture

- **Legacy**: Used `related` field to link ancienttext to its collection;
  separate `classictext` type for Graeco-Roman texts; `entrysubtype`
  values like `churchfather`, `inscription` described the text type
- **v2**: Uses `xref` field (not `related`) to link to the text collection;
  `entrysubtype` describes the relationship: `inancientcollection`,
  `ancientbook`, `inancientbook`; `classictext` eliminated entirely

### Citation format

1. **Short form**: `Author, Short Title Source.Division (Collection
   Edition, Pages)` — parenthesised collection info only when xref has
   postnote or when using `\transcite`

2. **Translator handling**: `\transcite` commands print translator before
   the collection reference; translator is "smuggled" from the xref entry
   to the parent if not defined on the parent

3. **Source division**: Uses `biblatex-source-division` package to parse
   source divisions from the postnote (e.g. `3.12.4` becomes titleaddon or
   maintitleaddon)

4. **Text collections**: `xref` points to the collection entry (a `@book`,
   `@mvbook`, `@collection`, etc. with a `shorthand`). The collection is
   cited using its shorthand when available.

5. **New `text` field**: For text numbers within collections (e.g. COS
   1.26 — the `26` is the text number)

6. **Title formatting**:
   - `inancientcollection`: quoted title
   - `ancientbook`: italicised if has author, plain if anonymous
   - `inancientbook`: quoted title
   - No entrysubtype: italicised if has author, plain if anonymous

### Bibliography format

Ancient texts are excluded from the main bibliography (`skipbib` for
`@ancienttext`). They appear in the abbreviation list (when they have no
entrysubtype, i.e. they are standalone ancient works).

## Data inheritance

v2 introduces comprehensive data inheritance rules for all multivolume and
container relationships:

| Parent → Child | Inherited fields |
|----------------|-----------------|
| `mvbook` → `book`, `inbook`, `bookinbook`, `suppbook` | author→mainauthor, title→maintitle, subtitle→mainsubtitle, translatedtitle→translatedmaintitle, editor→maineditor, translator→maintranslator, with*→withmain* |
| `book` → `inbook`, `bookinbook`, `suppbook` | author→bookauthor, title→booktitle, subtitle→booksubtitle, translatedtitle→translatedbooktitle, editor→bookeditor, translator→booktranslator, with*→withbook* |
| Same patterns for `mvcollection`→`collection`→`incollection` | |
| Same patterns for `mvreference`→`reference`→`inreference` | |
| Same patterns for `mvcommentary`→`commentary`→`incommentary` | |

All inheritance rules include `\noinherit{shorttitle}`,
`\noinherit{sorttitle}`, `\noinherit{indextitle}`,
`\noinherit{indexsorttitle}`.

## Localisation

### Removed strings
`by`, `introduction`, `foreword`, `mathesis`, `paperpresented`,
`patentfiled`, `urlseen`, `commonera`, `beforecommonera`, `annodomini`,
`beforechrist`

### New strings
`bydirector`, `bytranslatorrev`, `director`, `directors`, `fragment`,
`fragments`, `obverse`, `of`, `paper`, `parts`, `printing`, `released`,
`reverse`, `series`, `subverbis`, `subverbo`, `thiscite`, `to`, `with`,
`withassistance`, `withpreface`, `byreviser`, `compiler`

### Changed strings

- `chapter`: long form "chapter" / short form "ch." (was default)
- `translator`/`translators`: always short "trans." (both long and short)
- `editor`/`editors`: always short "ed."/"eds." (both long and short)
- `editortr`/`editorstr`: consistent abbreviation
- `phdthesis`: long "PhD dissertation" / short "PhD diss." (legacy had
  both as short)
- `reprint`: always abbreviated "repr."

## Punctuation and delimiters

### New delimiters

| Delimiter | Value (notes) | Value (bibliography) |
|-----------|---------------|---------------------|
| `languagedelim` | space | space |
| `namedashdelim` | comma + space | comma + space |
| `postnotedelim` | context-dependent (comma/space/colon) | — |
| `voltextdelim` | period | period |

### Changed punctuation

| Punctuation | Legacy | v2 |
|-------------|--------|----|
| `\newunitpunct` (notes) | comma + space | comma + space |
| `\newunitpunct` (bibliography) | period + space | period + space |
| `\subtitlepunct` | colon + space | intelligent (space after ?/!, else colon + space) |
| `\locationpublisherdelim` | colon + space | colon + space |
| `\publisherdelim` | semicolon + space | semicolon + space |
| `\volcitedelim` | — | context-dependent (colon/period/comma) |
| `\seriesnumberdelim` | space | space (non-breaking if shortseries) |

## Hyperlinking

v2 introduces comprehensive hyperlinking throughout:

- Short titles link to their first full citation
- Shorthands link to their abbreviation list entry
- Short journal names link to their abbreviation list entry
- Short series names link to their abbreviation list entry
- Ancient text short titles link to their abbreviation list entry
- Short maintitles link to their abbreviation list entry
- `\bibhypertarget` / `\bibhyperlink` pairs for all abbreviation types

## Page range handling

- Page ranges compressed with minimum comparison width of 10
- Multiples of 100 are not compressed (e.g. 200–204 stays as 200–204)
- Semicolons preserved in page ranges (not replaced by `\bibrangessep`)
- Unicode prime (′) added as number character for XeTeX/LuaTeX
- `\pnfmt` redefined to use current field format
- Helper macros: `\sv`/`\svv` (sub verbo/verbis), `\lno`/`\llno`
  (line/lines), `\colno`/`\colsno` (column/columns), `\sno`/`\ssno`
  (section/sections), `\obv`/`\rev` (obverse/reverse)

## Impact on CSL project

### CSL style file

| Change | Impact | Priority |
|--------|--------|----------|
| Location suppression after 1900 | Need to implement in CSL or Lua filter | High |
| Subtitle auto-splitting | CSL JSON should have subtitle separate; no auto-split needed | Low |
| Short title generation (remove A/An/The) | Lua filter or data convention | Medium |
| Printing field | New CSL variable needed | Low |
| datemodifier field | Lua filter to prefix date | Medium |
| Review format changes | Update review CSL formatting | Medium |
| Online/blog format changes | Update online CSL formatting | Medium |
| Video entry type | New CSL type mapping needed | Low |
| Abbreviation entry type | CSL has no equivalent; handle in Lua filter | Low |
| Parts field | New CSL handling | Low |

### Lua filter

| Change | Impact | Priority |
|--------|--------|----------|
| Name tracking (first full, then short) | Already handled by CSL position macros; no filter needed | Done |
| Cross-reference tracking | Must implement in filter state | High |
| Ancient text citation formatting | Complex; needs xref/collection logic | High |
| transcite commands | No direct CSL equivalent; filter must handle | High |
| smartcite footnote behaviour | Filter must detect footnote context | Medium |
| source-division parsing | Filter must parse postnote for divisions | High |
| Abbreviation list generation | Filter must produce the list | Medium |
| Hyperlinking | Not applicable to CSL output | N/A |

### Bibliography data (CSL YAML/JSON)

| Change | Impact | Priority |
|--------|--------|----------|
| `text` field | Map to custom CSL variable | Medium |
| `xrefstring` field | Map to custom CSL variable | Low |
| `website` field | Map to `container-title` for online | Medium |
| `translatedtitle` etc. | Use CSL's built-in `translated-title` | Medium |
| `datemodifier` | Custom variable | Medium |
| `printing` | Custom variable | Low |
| `shortmaintitle` | Custom variable | Medium |
| `parts` | Custom variable | Low |
| `withauthor` / `witheditor` | No direct CSL equivalent | Medium |
| `postnominal` namepart | No CSL equivalent | Low |
| `shortfamily` namepart | No CSL equivalent; use `non-dropping-particle` | Low |
| `entrysubtype` values | Map to CSL `genre` or custom variables | High |

### Abbreviation handling

| Change | Impact | Priority |
|--------|--------|----------|
| Three-section abbreviation list | Update abbreviation list generation | Medium |
| `@abbreviation` entries | Add to abbreviation data | Low |
| Deduplication of ancient source abbreviations | Lua filter logic needed | Medium |
| Short field hyperlinks | Not applicable to CSL | N/A |

### Test suite

| Change | Impact | Priority |
|--------|--------|----------|
| 170 l3build test files | Can extract expected output for comparison | High |
| Handbook examples file | Reference for expected formatting | High |
| Blog examples file | Reference for latest SBLHS updates | High |
| Student supplement examples | Additional test coverage | Medium |
