# Guide: Producing CSL JSON for the SBL Citation System

This guide is designed for use by Claude Code or any developer building an application that stores bibliographic data in SQLite and produces CSL JSON files for use with the SBL citation system (CSL style + Lua filter).

## Overview

The SBL citation system uses standard CSL JSON with one extension: the `note` field contains structured YAML metadata under an `sbl:` namespace. All SBL-specific features flow through this single field. The CSL style handles standard formatting; the Lua filter reads the `sbl:` metadata for advanced features.

**Key principle**: populate standard CSL fields first, then add `sbl:` metadata for anything CSL can't express natively.

## SQLite Schema Design

### Core tables

```sql
-- Main bibliography entries
CREATE TABLE entries (
    id TEXT PRIMARY KEY,           -- Citation key (e.g., 'talbert:1992')
    type TEXT NOT NULL,            -- CSL type (see Type Reference below)
    title TEXT,
    title_short TEXT,              -- Abbreviated title for subsequent notes
    container_title TEXT,          -- Journal/book title for chapters/articles
    container_title_short TEXT,    -- Journal abbreviation for notes
    collection_title TEXT,         -- Series name
    collection_title_short TEXT,   -- Series abbreviation
    collection_number TEXT,        -- Series volume number (string, may be "2/6")
    reviewed_title TEXT,           -- For reviews: title of reviewed work
    volume TEXT,                   -- Volume number (string)
    issue TEXT,                    -- Issue number
    page TEXT,                     -- Page range(s), e.g., "311-43" or "23-33, 36-37"
    number_of_volumes TEXT,        -- Total volumes, e.g., "7"
    edition TEXT,                  -- Edition text, e.g., "3" or "rev. and enl. ed"
    publisher TEXT,
    publisher_place TEXT,
    original_publisher TEXT,       -- For reprints
    original_publisher_place TEXT,
    doi TEXT,
    url TEXT,
    genre TEXT,                    -- e.g., "PhD diss.", "paper"
    medium TEXT,                   -- e.g., "Kindle edition", "Nook"
    status TEXT,                   -- e.g., "forthcoming"
    annote TEXT,                   -- Custom first-note citation text (HTML allowed)
    event_title TEXT,              -- Conference/event name
    event_place TEXT,              -- Conference location
    section TEXT,                  -- Document section

    -- SBL-specific metadata (stored as JSON, maps to note field sbl: block)
    sbl_metadata TEXT              -- JSON object, see SBL Metadata section
);

-- Authors, editors, translators, etc.
CREATE TABLE entry_names (
    entry_id TEXT NOT NULL REFERENCES entries(id),
    role TEXT NOT NULL,            -- 'author', 'editor', 'translator',
                                  -- 'collection-editor', 'container-author',
                                  -- 'reviewed-author'
    position INTEGER NOT NULL,    -- 0-based ordering
    family TEXT,                   -- Family name (NULL for literal names)
    given TEXT,                    -- Given name(s)
    literal TEXT,                  -- Full literal name (for ancient authors: "Josephus")
    suffix TEXT,                   -- "Jr.", "III", etc.
    PRIMARY KEY (entry_id, role, position)
);

-- Dates (issued, original-date, accessed, event-date)
CREATE TABLE entry_dates (
    entry_id TEXT NOT NULL REFERENCES entries(id),
    date_type TEXT NOT NULL,       -- 'issued', 'original-date', 'accessed', 'event-date'
    date_index INTEGER NOT NULL DEFAULT 0,  -- 0 for single date, 0+1 for ranges
    year INTEGER,
    month INTEGER,                -- NULL if unknown
    day INTEGER,                  -- NULL if unknown
    PRIMARY KEY (entry_id, date_type, date_index)
);

-- SBL relationship metadata
CREATE TABLE entry_relations (
    entry_id TEXT NOT NULL REFERENCES entries(id),
    related_id TEXT NOT NULL,      -- The related entry's ID
    relation_type TEXT NOT NULL,   -- 'container', 'translationof', 'reprintof', 'introduction'
    options TEXT,                  -- JSON array of options, e.g., '["skipbib","usevolume=false"]'
    PRIMARY KEY (entry_id, related_id)
);
```

### SBL metadata column

The `sbl_metadata` column stores a JSON object:

```json
{
    "shorthand": "BDAG",
    "shortseries": "WUNT",
    "shortjournal": "JBL",
    "shortauthor": "Josephus",
    "entrysubtype": "classical",
    "skipbib": true,
    "subsequent_annote": "Josephus, <i>Ant</i>.",
    "subsequent_suffix": "Thackeray, LCL",
    "xref": "josephus",
    "maintitle": "The Book of Acts in Its First Century Setting",
    "maineditor": "Winter, Bruce W.",
    "origlanguage": "from the 3rd German ed.",
    "seriesseries": "2",
    "abbreviation_type": "sigla",
    "definition": "ablative",
    "options": ["skipbiblist"]
}
```

Not all fields are needed for every entry. Most entries have only 1–3 SBL metadata fields. The `skipbib` boolean and `options` array are separate concerns: `skipbib` suppresses the entry from the bibliography, while `options` carries flags like `skipbiblist` (keep in bibliography instead of abbreviation list).

The `abbreviation_type` and `definition` fields are used for sigla entries (general abbreviations like grammatical terms). See the Abbreviation List section below for details.

## Generating CSL JSON from SQLite

### The output format

CSL JSON is an array of objects. Each entry maps directly from the SQLite tables:

```python
def entry_to_csl_json(entry_id, db):
    entry = db.execute("SELECT * FROM entries WHERE id = ?", (entry_id,)).fetchone()

    csl = {
        "id": entry["id"],
        "type": entry["type"],
    }

    # Simple string fields (only include if non-NULL)
    for field in ["title", "title-short", "container-title", "container-title-short",
                   "collection-title", "collection-title-short", "collection-number",
                   "reviewed-title", "volume", "issue", "page", "number-of-volumes",
                   "edition", "publisher", "publisher-place", "original-publisher",
                   "original-publisher-place", "DOI", "URL", "genre", "medium",
                   "status", "annote", "event-title", "event-place", "section"]:
        db_col = field.replace("-", "_")
        value = entry[db_col]
        if value is not None:
            csl[field] = value

    # Names
    for role in ["author", "editor", "translator", "collection-editor",
                 "container-author", "reviewed-author"]:
        names = db.execute(
            "SELECT * FROM entry_names WHERE entry_id = ? AND role = ? ORDER BY position",
            (entry_id, role)
        ).fetchall()
        if names:
            csl[role] = [name_to_csl(n) for n in names]

    # Dates
    for date_type in ["issued", "original-date"]:
        dates = db.execute(
            "SELECT * FROM entry_dates WHERE entry_id = ? AND date_type = ? ORDER BY date_index",
            (entry_id, date_type)
        ).fetchall()
        if dates:
            csl[date_type] = {"date-parts": [date_to_parts(d) for d in dates]}

    # Build the note field from SBL metadata
    note = build_sbl_note(entry["sbl_metadata"], entry_id, db)
    if note:
        csl["note"] = note

    return csl


def name_to_csl(name_row):
    if name_row["literal"]:
        return {"literal": name_row["literal"]}
    result = {}
    if name_row["family"]:
        result["family"] = name_row["family"]
    if name_row["given"]:
        result["given"] = name_row["given"]
    if name_row["suffix"]:
        result["suffix"] = name_row["suffix"]
    return result


def date_to_parts(date_row):
    parts = [date_row["year"]]
    if date_row["month"] is not None:
        parts.append(date_row["month"])
        if date_row["day"] is not None:
            parts.append(date_row["day"])
    return parts


def build_sbl_note(sbl_metadata_json, entry_id, db):
    """Build the note field YAML from SBL metadata and relationships."""
    import json

    if not sbl_metadata_json:
        meta = {}
    else:
        meta = json.loads(sbl_metadata_json)

    # Add relationships from the relations table
    relations = db.execute(
        "SELECT * FROM entry_relations WHERE entry_id = ?", (entry_id,)
    ).fetchall()

    if not meta and not relations:
        return None

    lines = ["sbl:"]

    # Simple key-value pairs
    for key in ["shorthand", "shortseries", "shortjournal", "shortauthor",
                "entrysubtype", "subsequent_annote", "subsequent_suffix",
                "xref", "maintitle", "maineditor", "origlanguage",
                "seriesseries", "abbreviation_type", "definition"]:
        if key in meta and meta[key]:
            lines.append(f"  {key}: {meta[key]}")

    # Boolean flags (standalone keys — the filter reads both this form
    # and the options array form, but use one or the other, not both)
    if meta.get("skipbib"):
        lines.append("  skipbib: true")

    # Options array — for skipbiblist and other per-entry/per-relation flags
    options = []
    if meta.get("skipbiblist"):
        options.append("skipbiblist")
    # Add any extra options from metadata
    for opt in meta.get("options", []):
        if opt not in options:
            options.append(opt)
    if options:
        lines.append(f"  options: [{', '.join(options)}]")

    # Related entries
    if relations:
        lines.append("  related:")
        for rel in relations:
            lines.append(f"    - id: {rel['related_id']}")
            lines.append(f"      type: {rel['relation_type']}")
            if rel["options"]:
                opts = json.loads(rel["options"])
                lines.append(f"      options: [{', '.join(opts)}]")

    return "\n".join(lines) + "\n"
```

## Type Reference

Use these CSL types for SBL entries:

| SBL Category | CSL Type | When to use |
|-------------|----------|-------------|
| Book (single or multi-volume) | `book` | Standard books, reference works, lexicons, commentaries |
| Chapter in edited volume | `chapter` | Contributions to collected works, Festschriften |
| Journal article | `article-journal` | Peer-reviewed journal articles |
| Magazine article | `article-magazine` | Popular magazines (BAR, Atlantic Monthly) |
| Book review | `review` | Reviews with or without own title |
| Encyclopedia article | `entry-encyclopedia` | Articles in multivolume reference works |
| Dictionary/lexicon article | `entry-dictionary` | Headword entries in lexicons |
| Dissertation | `thesis` | PhD dissertations, MA theses |
| Conference paper | `speech` | Papers presented at conferences |
| Classical text | `classic` | Greek/Latin classical authors (Josephus, Tacitus) |
| Ancient text | `document` | ANE texts, papyri, inscriptions |
| Website/blog | `webpage` | Online-only sources |
| Conference proceedings | `paper-conference` | Published conference papers |

## Annote Generation

For entries with `entrysubtype`, generate the `annote` field using templates:

### Classical texts (entrysubtype: classical)

```python
def annote_classical(entry):
    """Author, <i>Work</i>."""
    author = get_literal_author(entry)  # e.g., "Josephus"
    title = entry["title"]              # e.g., "Ant."
    if title.endswith("."):
        return f'{author}, <i>{title[:-1]}</i>.'
    return f'{author}, <i>{title}</i>,'
```

### Church father texts (entrysubtype: churchfather)

The annote includes the series reference embedded in the text. This must be composed from the entry's fields plus its related container entry:

```python
def annote_churchfather(entry, container_entry):
    """Author, <i>Work</i> section (SERIES vol:page)"""
    author = get_literal_author(entry)
    title = entry["title"]
    # The locator (section + series reference) is entry-specific
    # and should be stored in the annote directly
    if author:
        return f'{author}, <i>{title}</i>'
    return f'<i>{title}</i>'
```

### Lexicon articles (xref pattern)

```python
def annote_lexicon(entry, parent_entry):
    """Author, "Headword," <i>SHORTHAND</i> vol:pages"""
    author = get_full_author(entry)
    title = entry["title"]  # headword
    shorthand = parent_metadata["shorthand"]
    volume = entry["volume"]
    page = entry["page"]

    parts = []
    if author:
        parts.append(f'{author}, ')
    parts.append(f'"{title}," <i>{shorthand}</i>')
    if volume and page:
        parts.append(f' {volume}:{page}')
    return ''.join(parts)
```

## SBL Metadata Decision Tree

When creating an entry, use this decision tree for the `sbl_metadata`:

```
Is it a well-known reference work (BDAG, TDNT, etc.)?
  → Set shorthand, possibly skipbib

Is it a journal article?
  → Set shortjournal if the journal has a standard SBL abbreviation

Is it in a series?
  → Set shortseries; also set collection-title-short in the main entry

Is it a classical text (Josephus, Tacitus, Pliny, etc.)?
  → Set entrysubtype: classical
  → Set annote using classical template
  → Set subsequent_suffix with translator and series (e.g., "Thackeray, LCL")

Is it a church father text (Augustine, Gregory, Origen, etc.)?
  → Set entrysubtype: churchfather
  → Set annote with work title and series reference
  → Add related entry pointing to the series (ANF, NPNF, PG, PL)

Is it an ancient Near Eastern text?
  → Set entrysubtype: COS, inscription, chronicle, or RIMA as appropriate
  → Set annote with full citation text (these are highly variable)
  → Add related entry pointing to the collection/anthology

Is it a lexicon/dictionary article?
  → Set xref to parent lexicon
  → Set annote with author + headword + shorthand + vol:pages
  → Embed parent data (editor, publisher, etc.) in the entry for bibliography

Should it appear in bibliography?
  → If NO: set skipbib: true
  → If bibliography should show parent instead: set skipbib + xref

Where does it appear — abbreviation list or bibliography?
  → Entries with shorthand are automatically moved from bibliography
    to the abbreviation list by the Lua filter. No extra flag needed.
  → To KEEP a shorthand entry in the bibliography instead of the
    abbreviation list: set skipbiblist in options.
  → Entries without shorthand always remain in the bibliography.

Is it a grammatical abbreviation or siglum (abl., col., etc.)?
  → Set abbreviation_type: sigla
  → Set definition: with the expansion text
  → Set shorthand: with the abbreviation
  → The entry appears in the "General Abbreviations and Sigla" section

Does the subsequent note need different text from the first note?
  → Set subsequent_annote for complete replacement
  → OR set subsequent_suffix for "(Translator, Series)" appending
  → Both can be set: subsequent_annote composes base, suffix appends
```

## Abbreviation List Data

The project provides two abbreviation JSON files for pandoc's `--citation-abbreviations` flag:

| File | Entries | Use case |
|------|---------|----------|
| `sbl-abbreviations.json` | 1,284 | Strict SBLHS compliance |
| `sbl-abbreviations-extended.json` | 1,847 | Broader coverage (SBLHS 2nd ed. + Zacharias) |

These map abbreviations to full titles for `container-title` fields. Your app could use these to:
1. Auto-populate `container-title-short` from `container-title` when a match exists
2. Validate that journal/series abbreviations are SBLHS-standard
3. Offer abbreviation lookup in the UI

## Abbreviation List vs Bibliography

The Lua filter generates an abbreviation list matching the three-section model used by biblatex-sbl v2. Entries are collected from cited bibliography data and organised into up to three sections:

### Three-section model

biblatex-sbl v2 organises the abbreviation list into three sections. Our filter supports the same model:

1. **Secondary Sources** — reference works with `shorthand` (e.g., BDAG, TDNT, HALOT). Each entry shows the shorthand abbreviation followed by the full formatted bibliography text.

2. **Journals, Series, and Other Abbreviations** — journal and series titles derived from `container-title-short` and `collection-title-short` fields on cited entries (e.g., *JBL* → *Journal of Biblical Literature*, AB → Anchor Bible). These are simple abbreviation → full title mappings.

3. **General Abbreviations and Sigla** — grammatical abbreviations, sigla, and other conventional abbreviations (e.g., abl. → ablative, col. → column). These use the `abbreviation_type: sigla` field in `sbl:` metadata.

**When sub-headings appear**: the filter only adds section sub-headings when entries exist in more than one section. If all abbreviation entries belong to a single section (the typical case for documents that cite only reference works and journals), the list remains flat with no sub-headings — identical to the previous behaviour.

**Ancient sources**: biblatex-sbl v2 also supports a separate "Ancient Sources" section for standalone ancient works with `shorttitle`. Our system handles ancient text abbreviations through the `annote` bypass mechanism rather than a separate abbreviation list section, since ancient text citations embed their abbreviations directly in the formatted citation text.

### How entries reach the abbreviation list

| Source | Section | What appears | Example |
|--------|---------|-------------|---------|
| Entry with `shorthand` (no `skipbiblist`) | Secondary Sources | Full formatted bibliography text | BDAG, TDNT, HALOT |
| `container-title-short` on a cited entry | Journals, Series, and Other Abbreviations | Full journal/magazine title (italic for journals) | *JBL*, *JECS*, *BAR* |
| `collection-title-short` on a cited entry | Journals, Series, and Other Abbreviations | Full series name (roman) | AB, WUNT, LCL |
| Entry with `abbreviation_type: sigla` | General Abbreviations and Sigla | Definition text | abl. → ablative |

### Where entries appear

| Entry has... | Abbreviation list | Bibliography |
|-----------|-------------------|-------------|
| `shorthand` only | Yes (full bib text) | No (moved to abbreviation list) |
| `shorthand` + `skipbib: true` | Yes (full bib text) | No |
| `shorthand` + `skipbiblist` option | No | Yes |
| `shorthand` + `entrysubtype` | No | Yes |
| `container-title-short` or `collection-title-short` | Yes (simple title) | Entry stays in bibliography |
| `abbreviation_type: sigla` | Yes (definition text) | No |
| No shorthand and no short titles | No | Yes |

### Sigla entries

Sigla (general abbreviations) use two fields in the `sbl:` metadata block:

- `abbreviation_type: sigla` — marks the entry as a sigla entry
- `definition: ablative` — the expansion text displayed in the abbreviation list

The `shorthand` field provides the abbreviation key (e.g., `abl.`). A minimal sigla entry:

```yaml
- id: abl
  type: book
  title: ablative
  note: |
    sbl:
      shorthand: abl.
      abbreviation_type: sigla
      definition: ablative
```

Sigla entries are document-specific and typically not needed unless the document uses specialist grammatical or text-critical notation. SBLHS provides standard abbreviation lists for biblical books, Dead Sea Scrolls, Nag Hammadi texts, and similar corpora, but grammatical sigla vary by discipline.

### Populating the abbreviation list

Place `# Abbreviations {#sbl-abbreviations}` in the document. The filter collects abbreviations from all cited entries (including those brought in by `nocite` and those removed by `skipbib`), builds the list, and removes shorthand entries from the bibliography.

**Important**: parent entries with `shorthand` that are not directly cited must be included via `nocite` in the document front matter for their abbreviation to appear. For example, if child entries cite COS volumes but the parent COS entry is not directly cited:

```yaml
nocite: |
  @COS, @ANET, @AEL
```

Similarly, entries whose `collection-title-short` or `container-title-short` should appear in the abbreviation list must either be cited or included via `nocite`.

### Output format

For typst output, the filter emits a two-column grid layout (abbreviation column + definition column) matching the biblatex-sbl tabular format. For other output formats (HTML, docx), it uses a pandoc definition list. When multiple sections are present, each section receives a sub-heading one level below the abbreviation list heading.

Without the Lua filter, shorthand entries remain in the bibliography as normal entries and no abbreviation list is generated.

## Validation Checklist

Before producing CSL JSON, verify:

- [ ] Every entry has `id` and `type`
- [ ] Names use `family`+`given` for modern authors, `literal` for ancient authors
- [ ] Dates use `date-parts` array format (not string dates)
- [ ] Date ranges use two arrays in `date-parts` (not a single array)
- [ ] `title-short` is set for entries that will be cited more than once
- [ ] `container-title-short` is set for journal articles (abbreviation for notes and abbreviation list)
- [ ] `collection-title-short` is set for series entries (abbreviation for notes and abbreviation list)
- [ ] Both `container-title` (full) and `container-title-short` are set — the filter needs both to generate abbreviation list entries
- [ ] Both `collection-title` (full) and `collection-title-short` are set — same reason
- [ ] `annote` uses HTML `<i>` tags for italic (not markdown `*`)
- [ ] The `note` field contains valid YAML under the `sbl:` key
- [ ] `sbl:` YAML uses block scalar format (`note: |`) not quoted strings with `\n`
- [ ] Entries with `shorthand` go to abbreviation list by default; set `skipbiblist` if they should stay in bibliography
- [ ] Entries that should not appear in bibliography at all have `skipbib: true`
- [ ] Entries with `xref` have parent data embedded (editor, publisher, etc.) for bibliography
- [ ] `collection-number` is a string (not integer) — may contain "2/6" for series-in-series

## Example: Complete Entry

A complex entry demonstrating most features:

```json
{
  "id": "beyer:diakoneo+diakonia+ktl",
  "type": "entry-dictionary",
  "author": [
    {"family": "Beyer", "given": "Hermann W."}
  ],
  "title": "διακονέω, διακονία, κτλ",
  "container-title": "Theological Dictionary of the New Testament",
  "editor": [
    {"family": "Kittel", "given": "Gerhard"},
    {"family": "Friedrich", "given": "Gerhard"}
  ],
  "volume": "2",
  "page": "81-93",
  "number-of-volumes": "10",
  "publisher": "Eerdmans",
  "publisher-place": "Grand Rapids",
  "issued": {"date-parts": [[1964], [1976]]},
  "annote": "Hermann W. Beyer, \"διακονέω, διακονία, κτλ,\" <i>TDNT</i> 2:81–93",
  "note": "sbl:\n  shorthand: TDNT\n  xref: TDNT\n"
}
```

This entry:
- Uses `annote` for custom first-note format (shorthand instead of full title)
- Has `xref` pointing to parent lexicon TDNT
- Embeds parent data (editor, publisher, volumes) for bibliography
- The `note` field carries the SBL metadata in YAML format
