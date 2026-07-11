-- ld-ancient-index.lua
-- Pandoc Lua filter that generates an index of ancient sources from body
-- text and footnotes. Closely modelled on ld-author-index.lua: same three
-- output paths, same marker-heading mechanics, same coding style.
--
-- v3: the index is SECTIONED in SBL style (Hebrew Bible/Old Testament,
-- New Testament, Pseudepigrapha, Dead Sea Scrolls, ..., Ancient Near
-- Eastern Texts, ...). Two recognition mechanisms feed it:
--
--   1. AUTOMATIC: biblical references ("Jer 32.6--15", "Lev 25:23",
--      "2 Sam 24") are recognised in running text exactly as in v1/v2 and
--      filed under "Hebrew Bible/Old Testament" or "New Testament" by
--      canonical position.
--   2. EXPLICIT MARKERS: non-biblical ancient sources are declared with an
--      empty inline span carrying class .anc:
--
--        []{.anc section="dss" entry="4QInstruction"}
--        []{.anc section="ane" entry="Laws of Hammurabi" locus="117"}
--        []{.anc section="ane" entry="Laws of Hammurabi" locus="t" sort="0065.20"}
--        []{.anc section="rabbinic" entry="m. B. Bat." locus="10:1"}
--
--      Attributes:
--        section     (required) one of the SECTIONS slugs below; a marker
--                    with an unknown slug or missing entry is reported on
--                    stderr and skipped.
--        entry       (required) the top-level index entry, displayed
--                    verbatim (Unicode superscripts are fine: "4QJer\u{1D47}").
--        locus       (optional) the subentry (passage/paragraph). Omitted
--                    for name-only mentions: page numbers then attach to
--                    the entry line itself.
--        sort        (optional) explicit sort key for THIS locus,
--                    overriding the automatic key (digit runs zero-padded
--                    to 4). Use where document order isn't lexical, e.g.
--                    LH gap paragraphs lettered between ¶65 and ¶100.
--        entry-sort  (optional) explicit sort key for the entry within its
--                    section (default: the entry text, plain string order).
--
--      The span itself renders as nothing (empty content); the filter
--      appends the docx bookmark / typst #index call after it. Markers
--      work inside footnotes and block quotations (sources cited within
--      quoted matter are indexed, per standard practice).
--
-- Three output paths, all sectioned, entries in canonical/sorted order:
--   Word (.docx): at each recognised occurrence (auto or marker), emits a
--     hidden bookmark (<w:bookmarkStart/><w:bookmarkEnd/>, names anc0001,
--     anc0002, ...). At the marker heading, this filter generates the full
--     index itself: a small-caps bold section heading per non-empty
--     section, one bold paragraph per entry, subentry lines with PAGEREF
--     fields pointing at the bookmarks (real page numbers once fields are
--     updated with Ctrl+A, F9). Word's INDEX/XE machinery cannot be
--     custom-ordered, so it is not used at all.
--   Typst: injects #index(entry, (display, key), index: "ancient-<slug>")
--     calls from the in-dexter package (>=0.3.0, tested against 0.7.2)
--     alongside references, and one #make-index(...) per non-empty section
--     at the marker heading, each preceded by a section-heading paragraph,
--     sharing a single sort-order callback (see "in-dexter API note").
--     Typst renders the index with real page numbers at compile time.
--   HTML/other: generates a static sectioned two-level list (entry ->
--     locus subentries), with no page numbers.
--
-- Usage:
--   pandoc doc.md --lua-filter=ld-ancient-index.lua -o doc.docx
--   pandoc doc.md --lua-filter=ld-ancient-index.lua -o doc.typ
--
-- Place this heading in your document where the index should appear:
--   # Index of Ancient Sources {#ancient-index}
--
-- For typst output, the document needs: #import "@preview/in-dexter:0.7.2": *
--
-- Does not depend on citeproc; can run before or after it, and alongside
-- ld-author-index.lua (both filters can be passed to the same pandoc run).
--
-- ──────────────────────────────────────────────
-- in-dexter API note (verified against the pinned 0.7.2 source,
-- ~/Library/Caches/typst/packages/preview/in-dexter/0.7.2/in-dexter.typ)
-- ──────────────────────────────────────────────
--   #index() takes variadic positional "..entry" arguments to nest index
--   entries left to right; each positional argument may be a plain string
--   (used as both display and key) or a 2-element array `(display, key)`
--   (confirmed by the "Handle tuple as (display, key)" comment and code in
--   the `references()` function). HOWEVER, `make-entries()` only attaches
--   the `display` value to the *rightmost* (leaf) entry of a nested chain;
--   intermediate/grouping-level entries never get a `display` field
--   inserted, so `render-entry()` falls back to the raw KEY as the
--   displayed text for any grouping level. This was confirmed empirically:
--   compiling a minimal document with
--     #index(("Genesis", "01 Genesis"), ("23", "023.000"), index: "ancient")
--   renders the book heading as "01 Genesis", not "Genesis" — the intended
--   sort-key prefix leaks into the display.
--
--   Consequence: the (display, key) tuple trick works for level-2 (locus)
--   entries, which are always leaves, but NOT for level-1 (entry) names,
--   which are grouping nodes whenever loci exist. The entry name is
--   therefore always passed as a plain string (display == key == the
--   name), and ordering is obtained by passing a custom `sort-order`
--   callback to #make-index() — a literal dict of entry name ->
--   sort key (canonical zero-padded ordinals "01".."66" for biblical
--   books, any entry-sort attributes for marker entries), generated by
--   this filter, with `k => dict.at(k, default: k)`. `sort-order` is
--   applied uniformly by in-dexter to both grouping keys and leaf keys
--   (locus sort keys, already zero-padded so default string order matches
--   numeric order), so a single shared callback handles all levels and all
--   sections correctly.
--
--   in-dexter also buckets entries into initial-letter sections (a normal
--   A/B/C-style index convention) based on the first character of
--   sort-order(key). With zero-padded ordinals this would produce spurious
--   inline headings, so they are suppressed via
--   `section-title: (letter, counter) => []`, which keeps the (harmless,
--   invisible) bucketing behaviour but renders no heading text, giving one
--   continuous ordered list per section.
--
-- ──────────────────────────────────────────────
-- Known limitations / design decisions
-- ──────────────────────────────────────────────
--   * Docx occurrence marking: EVERY recognised occurrence gets its own
--     bookmark (not just the first per unique reference), so the
--     PAGEREF-based index lists every page a reference appears on. The
--     one exception is same-block dedupe: if the identical (section,
--     entry, locus) triple is recognised more than once within the SAME
--     Para/Plain block (including a single footnote paragraph), only the
--     first occurrence in that block gets a bookmark — repeats within one
--     block are almost certainly on the same page, and Word's PAGEREF
--     cannot dedupe repeated page numbers within one subentry's field
--     list.
--   * Residual limitation: two occurrences of the same reference that land
--     on the same page but in DIFFERENT paragraphs are not deduped (that
--     would require knowing page layout, which this filter cannot do at
--     the Pandoc-AST stage) and will render as duplicate page numbers in
--     the index (e.g. "26, 26"). A final proof-reading pass in Word may be
--     needed to manually collapse these. When placing .anc markers by
--     hand, prefer ONE marker per contiguous discussion of a source.
--   * Chapter/verse separator: source text may use either "." or ":"
--     (e.g. "Jer 32.7" and "Lev 25:23"). Both are recognised, but output
--     subentries always use "." for consistency (e.g. "Lev 25:23" indexes
--     as "Leviticus" -> "25.23"). Marker locus attributes are displayed
--     verbatim.
--   * Automatic recognition is limited to Str/Space/SoftBreak runs
--     directly inside Para/Plain blocks (including footnote content, via
--     Note elements found in that flat run). Para/Plain blocks are found
--     by recursing into BlockQuote, Div, list items and DefinitionList
--     content, so references in block quotations and lists are covered;
--     Table cells are NOT recursed into. References nested inside further
--     inline containers (Emph, Strong, Span, Link, etc.) are NOT scanned,
--     so an italicised reference would be missed. In practice this also
--     means content inside `[...]{lang="he"}` spans is skipped. This is
--     exactly why non-biblical sources use explicit markers: forms like
--     `[lh]{.smallcaps} 117` or `4QJer^b^` are invisible to the
--     tokenizer.
--   * A "book name" is only recognised when the following token begins
--     with a digit (the chapter number). This is applied uniformly, not
--     just for ambiguous short words, since every real biblical reference
--     in this scheme is book + chapter.
--
-- Compatible with Quarto (use citeproc: false + explicit filter ordering).

-- ──────────────────────────────────────────────
-- Configuration
-- ──────────────────────────────────────────────

local OUTPUT_FORMAT = FORMAT or "html"
local is_docx = OUTPUT_FORMAT == "docx" or OUTPUT_FORMAT == "openxml"
local is_typst = OUTPUT_FORMAT == "typst"

-- ──────────────────────────────────────────────
-- Sections (SBL order). Only sections with entries are rendered.
-- ──────────────────────────────────────────────

local SECTIONS = {
  { slug = "hb",       title = "Hebrew Bible/Old Testament" },
  { slug = "nt",       title = "New Testament" },
  { slug = "apoc",     title = "Deuterocanonical Works" },
  { slug = "pseud",    title = "Pseudepigrapha" },
  { slug = "dss",      title = "Dead Sea Scrolls" },
  { slug = "philo",    title = "Philo" },
  { slug = "josephus", title = "Josephus" },
  { slug = "rabbinic", title = "Rabbinic Works" },
  { slug = "ane",      title = "Ancient Near Eastern Texts" },
  { slug = "inscr",    title = "Inscriptions, Papyri, and Ostraca" },
  { slug = "greco",    title = "Greco-Roman Literature" },
}
local SECTION_TITLES = {}
for _, s in ipairs(SECTIONS) do SECTION_TITLES[s.slug] = s.title end

-- ──────────────────────────────────────────────
-- Book name tables
-- ──────────────────────────────────────────────

-- Single-token book names: SBL abbreviation and full name both map to the
-- canonical full English name used as the top-level index entry.
local SINGLE_BOOKS = {
  Gen = "Genesis", Genesis = "Genesis",
  Exod = "Exodus", Exodus = "Exodus",
  Lev = "Leviticus", Leviticus = "Leviticus",
  Num = "Numbers", Numbers = "Numbers",
  Deut = "Deuteronomy", Deuteronomy = "Deuteronomy",
  Josh = "Joshua", Joshua = "Joshua",
  Judg = "Judges", Judges = "Judges",
  Ruth = "Ruth",
  Ezra = "Ezra",
  Neh = "Nehemiah", Nehemiah = "Nehemiah",
  Esth = "Esther", Esther = "Esther",
  Job = "Job",
  Ps = "Psalms", Pss = "Psalms", Psalm = "Psalms", Psalms = "Psalms",
  Prov = "Proverbs", Proverbs = "Proverbs",
  Qoh = "Ecclesiastes", Eccl = "Ecclesiastes", Ecclesiastes = "Ecclesiastes",
  Song = "Song of Songs", Cant = "Song of Songs",
  Isa = "Isaiah", Isaiah = "Isaiah",
  Jer = "Jeremiah", Jeremiah = "Jeremiah",
  Lam = "Lamentations", Lamentations = "Lamentations",
  Ezek = "Ezekiel", Ezekiel = "Ezekiel",
  Dan = "Daniel", Daniel = "Daniel",
  Hos = "Hosea", Hosea = "Hosea",
  Joel = "Joel",
  Amos = "Amos",
  Obad = "Obadiah", Obadiah = "Obadiah",
  Jonah = "Jonah",
  Mic = "Micah", Micah = "Micah",
  Nah = "Nahum", Nahum = "Nahum",
  Hab = "Habakkuk", Habakkuk = "Habakkuk",
  Zeph = "Zephaniah", Zephaniah = "Zephaniah",
  Hag = "Haggai", Haggai = "Haggai",
  Zech = "Zechariah", Zechariah = "Zechariah",
  Mal = "Malachi", Malachi = "Malachi",
  Matt = "Matthew", Matthew = "Matthew",
  Mark = "Mark",
  Luke = "Luke",
  John = "John",
  Acts = "Acts",
  Rom = "Romans", Romans = "Romans",
  Gal = "Galatians", Galatians = "Galatians",
  Eph = "Ephesians", Ephesians = "Ephesians",
  Phil = "Philippians", Philippians = "Philippians",
  Col = "Colossians", Colossians = "Colossians",
  Titus = "Titus",
  Phlm = "Philemon", Philemon = "Philemon",
  Heb = "Hebrews", Hebrews = "Hebrews",
  Jas = "James", James = "James",
  Jude = "Jude",
  Rev = "Revelation", Revelation = "Revelation",
}

-- Books that require a leading numeral (1-2, or 1-3 for John). Keyed by
-- the token following the numeral; value is the base name used to build
-- the canonical "N Base" form.
local NUMBERED_BASES = {
  Sam = "Samuel", Samuel = "Samuel",
  Kgs = "Kings", Kings = "Kings",
  Chr = "Chronicles", Chronicles = "Chronicles",
  Cor = "Corinthians", Corinthians = "Corinthians",
  Thess = "Thessalonians", Thessalonians = "Thessalonians",
  Tim = "Timothy", Timothy = "Timothy",
  Pet = "Peter", Peter = "Peter",
  John = "John",
}

-- Maximum numeral prefix allowed per base (1-3 John, 1-2 everything else).
local MAX_NUMERAL = { John = 3 }

-- Canonical scholarly ordering. Positions 1-39 are the Hebrew Bible/Old
-- Testament ("hb" section), 40-66 the New Testament ("nt" section). Used
-- for entry ordering in those two sections in all three output paths, and
-- (as a zero-padded ordinal lookup) in the typst sort-order callback.
local CANONICAL_ORDER = {
  "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
  "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings",
  "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job",
  "Psalms", "Proverbs", "Ecclesiastes", "Song of Songs",
  "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel",
  "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum",
  "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
  "Matthew", "Mark", "Luke", "John", "Acts",
  "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
  "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
  "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James",
  "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation",
}
local ORDER_INDEX = {}
for i, name in ipairs(CANONICAL_ORDER) do ORDER_INDEX[name] = i end
local LAST_OT_POSITION = 39

local function book_section(book)
  local pos = ORDER_INDEX[book]
  if pos and pos > LAST_OT_POSITION then return "nt" end
  return "hb"
end

-- ──────────────────────────────────────────────
-- Sort keys
-- ──────────────────────────────────────────────

-- Automatic locus sort key: every digit run zero-padded to 4 so plain
-- string comparison matches numeric order ("2.26" -> "0002.0026" sorts
-- before "11.21" -> "0011.0021"); en dashes normalised to '-' since keys
-- are never displayed.
local function auto_sort_key(s)
  local key = s:gsub("%d+", function(d) return string.format("%04d", tonumber(d)) end)
  key = key:gsub("\u{2013}", "-")
  return key
end

-- ──────────────────────────────────────────────
-- Entry/locus tracking
-- ──────────────────────────────────────────────

-- sections_data[slug] = {
--   entry_order = { entry, ... }   (insertion order; sorted at output)
--   entries = { entry -> {
--     entry_sort  = string or nil  (explicit entry-sort attribute)
--     locus_order = { locus, ... } (insertion order; "" = page-only)
--     loci        = { locus -> true }
--     locus_sort  = { locus -> key }
--     locations   = { locus -> { bookmark_name, ... } }  (docx path)
--   } }
-- }
local sections_data = {}

local function record_entry(slug, entry, locus, entry_sort, locus_sort)
  local sec = sections_data[slug]
  if not sec then
    sec = { entry_order = {}, entries = {} }
    sections_data[slug] = sec
  end
  local rec = sec.entries[entry]
  if not rec then
    rec = { locus_order = {}, loci = {}, locus_sort = {}, locations = {} }
    sec.entries[entry] = rec
    table.insert(sec.entry_order, entry)
  end
  if entry_sort then rec.entry_sort = entry_sort end
  if not rec.loci[locus] then
    rec.loci[locus] = true
    table.insert(rec.locus_order, locus)
  end
  if locus_sort then
    rec.locus_sort[locus] = locus_sort
  elseif not rec.locus_sort[locus] then
    rec.locus_sort[locus] = auto_sort_key(locus)
  end
end

-- ──────────────────────────────────────────────
-- Shared ordering helpers (used by all output paths)
-- ──────────────────────────────────────────────

-- Entries of a section in output order: canonical position for hb/nt,
-- entry-sort (falling back to the entry text) elsewhere.
local function sorted_entries(slug)
  local sec = sections_data[slug]
  local entries = {}
  for _, e in ipairs(sec.entry_order) do table.insert(entries, e) end
  if slug == "hb" or slug == "nt" then
    table.sort(entries, function(a, b)
      local oa, ob = ORDER_INDEX[a], ORDER_INDEX[b]
      if oa and ob then return oa < ob end
      if oa then return true end
      if ob then return false end
      return a < b
    end)
  else
    table.sort(entries, function(a, b)
      local ka = sec.entries[a].entry_sort or a
      local kb = sec.entries[b].entry_sort or b
      if ka ~= kb then return ka < kb end
      return a < b
    end)
  end
  return entries
end

-- Loci of an entry in output order (by sort key; "" page-only first).
local function sorted_loci(slug, entry)
  local rec = sections_data[slug].entries[entry]
  local loci = {}
  for _, l in ipairs(rec.locus_order) do table.insert(loci, l) end
  table.sort(loci, function(a, b)
    local ka = rec.locus_sort[a] or a
    local kb = rec.locus_sort[b] or b
    if ka ~= kb then return ka < kb end
    return a < b
  end)
  return loci
end

-- Non-empty sections in SECTIONS order.
local function active_sections()
  local out = {}
  for _, s in ipairs(SECTIONS) do
    if sections_data[s.slug] then table.insert(out, s) end
  end
  return out
end

-- Section heading block, shared across output paths: bold small caps.
local function section_heading_block(title)
  return pandoc.Para(pandoc.Inlines{
    pandoc.Strong(pandoc.Inlines{
      pandoc.SmallCaps(pandoc.Inlines{pandoc.Str(title)})
    })
  })
end

-- ──────────────────────────────────────────────
-- Word (docx) bookmark + PAGEREF field generation
-- ──────────────────────────────────────────────

-- Bookmark ids start at a high offset to avoid colliding with pandoc's own
-- bookmark ids (used for internal cross-references, TOC anchors, etc.).
local BOOKMARK_ID_BASE = 90000
local bookmark_seq = 0

-- Emit a hidden bookmark at an occurrence and record its name against
-- (slug, entry, locus) for later PAGEREF generation at the marker heading.
local function make_bookmark(slug, entry, locus)
  bookmark_seq = bookmark_seq + 1
  local name = string.format("anc%04d", bookmark_seq)
  local id = BOOKMARK_ID_BASE + bookmark_seq

  local rec = sections_data[slug].entries[entry]
  if not rec.locations[locus] then rec.locations[locus] = {} end
  table.insert(rec.locations[locus], name)

  return pandoc.RawInline("openxml",
    '<w:bookmarkStart w:id="' .. id .. '" w:name="' .. name .. '"/>' ..
    '<w:bookmarkEnd w:id="' .. id .. '"/>'
  )
end

-- A PAGEREF field pointing at a bookmark, with a placeholder result text
-- (Word replaces it with the real page number on field update).
local function make_pageref_field(bookmark_name)
  return pandoc.RawInline("openxml",
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>' ..
    '<w:r><w:instrText xml:space="preserve"> PAGEREF ' .. bookmark_name .. ' \\h </w:instrText></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>' ..
    '<w:r><w:t>1</w:t></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
  )
end

local function append_pagerefs(inl, names)
  for k, name in ipairs(names) do
    if k > 1 then inl:insert(pandoc.Str(", ")) end
    inl:insert(make_pageref_field(name))
  end
end

-- Build the docx index blocks: per non-empty section, a heading paragraph,
-- then one bold paragraph per entry (with the page-only PAGEREFs on the
-- entry line itself, if any) and subentry paragraphs with comma-separated
-- PAGEREF fields.
local function build_docx_index_blocks()
  local out_blocks = {}
  for _, s in ipairs(active_sections()) do
    table.insert(out_blocks, section_heading_block(s.title))
    for _, entry in ipairs(sorted_entries(s.slug)) do
      local rec = sections_data[s.slug].entries[entry]
      local head = pandoc.List{}
      head:insert(pandoc.Strong(pandoc.Inlines{pandoc.Str(entry)}))
      local page_only = rec.locations[""]
      if page_only and #page_only > 0 then
        head:insert(pandoc.Str(": "))
        append_pagerefs(head, page_only)
      end
      table.insert(out_blocks, pandoc.Para(head))
      for _, locus in ipairs(sorted_loci(s.slug, entry)) do
        if locus ~= "" then
          local inl = pandoc.List{}
          inl:insert(pandoc.Str(locus))
          inl:insert(pandoc.Str(": "))
          append_pagerefs(inl, rec.locations[locus] or {})
          table.insert(out_blocks, pandoc.Para(inl))
        end
      end
    end
  end
  return out_blocks
end

-- ──────────────────────────────────────────────
-- Typst index generation (via in-dexter, one index per section)
-- ──────────────────────────────────────────────

local function typst_escape(s)
  return (s:gsub('"', '\\"'))
end

-- The occurrence-site #index() call. Entry names are always plain strings
-- (see the in-dexter API note); loci are (display, key) tuples; page-only
-- occurrences are single-level entries.
local function make_typst_index_entry(slug, entry, locus)
  local index_name = "ancient-" .. slug
  if locus == "" then
    return pandoc.RawInline("typst",
      '#index("' .. typst_escape(entry) .. '", index: "' .. index_name .. '")')
  end
  local rec = sections_data[slug].entries[entry]
  local key = rec.locus_sort[locus] or auto_sort_key(locus)
  return pandoc.RawInline("typst",
    '#index("' .. typst_escape(entry) .. '", ("' .. typst_escape(locus) ..
    '", "' .. typst_escape(key) .. '"), index: "' .. index_name .. '")')
end

-- Emits one shared entry-name -> sort-key dict (canonical zero-padded
-- ordinals for biblical books, plus any entry-sort attributes from
-- markers) and, per non-empty section, a heading and a #make-index() call
-- for that section's index, all sharing the dict as sort-order callback.
-- section-title is overridden to render nothing, so in-dexter's
-- initial-letter bucketing stays invisible and each section reads as one
-- continuous ordered list.
local function make_typst_index_blocks()
  local lines = { '#let __ancient_index_order = (' }
  for i, name in ipairs(CANONICAL_ORDER) do
    table.insert(lines,
      '  "' .. typst_escape(name) .. '": "' .. string.format('%02d', i) .. '",')
  end
  for _, s in ipairs(active_sections()) do
    if s.slug ~= "hb" and s.slug ~= "nt" then
      local sec = sections_data[s.slug]
      for _, entry in ipairs(sec.entry_order) do
        local es = sec.entries[entry].entry_sort
        if es then
          table.insert(lines,
            '  "' .. typst_escape(entry) .. '": "' .. typst_escape(es) .. '",')
        end
      end
    end
  end
  table.insert(lines, ')')

  local out_blocks = { pandoc.RawBlock("typst", table.concat(lines, "\n")) }
  for _, s in ipairs(active_sections()) do
    table.insert(out_blocks, section_heading_block(s.title))
    local mk = {
      '#make-index(',
      '  title: none,',
      '  indexes: ("ancient-' .. s.slug .. '",),',
      '  section-title: (letter, counter) => [],',
      '  sort-order: k => __ancient_index_order.at(k, default: k),',
      -- in-dexter's entry-casing defaults to first-letter-up, which would
      -- corrupt entries/loci like "m. B. Bat." or "gap ¶ l"; display text
      -- is already exactly as authored, so use the identity.
      '  entry-casing: k => k,',
      ')',
    }
    table.insert(out_blocks, pandoc.RawBlock("typst", table.concat(mk, "\n")))
  end
  return out_blocks
end

-- ──────────────────────────────────────────────
-- Explicit marker spans ([]{.anc section=".." entry=".." locus=".."})
-- ──────────────────────────────────────────────

local function handle_marker_span(span)
  local attrs = span.attributes
  local slug = attrs["section"]
  local entry = attrs["entry"]
  if not slug or not SECTION_TITLES[slug] or not entry or entry == "" then
    io.stderr:write("[ld-ancient-index] WARNING: skipping .anc marker with " ..
      "missing/unknown section or entry (section=" .. tostring(slug) ..
      ", entry=" .. tostring(entry) .. ")\n")
    return nil
  end
  local locus = attrs["locus"] or ""
  record_entry(slug, entry, locus, attrs["entry-sort"], attrs["sort"])
  return slug, entry, locus
end

-- ──────────────────────────────────────────────
-- Automatic biblical reference recognition
-- ──────────────────────────────────────────────

-- Strip leading bracket/quote punctuation only (book-name tokens).
local function core_word(s)
  s = s:gsub("^[%(%[{\"']+", "")
  s = s:gsub("[%)%]}\"'%.,;:]+$", "")
  return s
end

-- Strip leading bracket/quote punctuation from a numeral token, and
-- trailing junk one character at a time, recording whether the clause
-- was semicolon-continued.
local function trim_numeral_token(s)
  s = s:gsub("^[%(%[{\"']+", "")
  local trailing_semicolon = false
  while #s > 0 do
    local last = s:sub(-1)
    if last == ";" then
      trailing_semicolon = true
      s = s:sub(1, -2)
    elseif last == ")" or last == "]" or last == '"' or last == "'"
        or last == "." or last == "," then
      s = s:sub(1, -2)
    else
      break
    end
  end
  return s, trailing_semicolon
end

-- Normalise a raw dash sequence ("-", "--", en dash) to an en dash.
local function endash(a, b)
  return a .. "\u{2013}" .. b
end

-- Parse a single clause (already comma-free) into a ref string, or nil.
-- Tries chapter.verse-range, chapter.verse, chapter-range, chapter.
local function parse_clause(core)
  local c, v1, v2 = core:match("^(%d+)[%.:](%d+)[\u{2013}%-]+(%d+)$")
  if c then return c .. "." .. endash(v1, v2) end

  c, v1 = core:match("^(%d+)[%.:](%d+)$")
  if c then return c .. "." .. v1 end

  local c1, c2 = core:match("^(%d+)[\u{2013}%-]+(%d+)$")
  if c1 then return endash(c1, c2) end

  c = core:match("^(%d+)$")
  if c then return c end

  return nil
end

-- Parse a numeral token (possibly containing a comma-separated verse
-- list, e.g. "50.5,13") into a list of ref strings.
local function parse_numeral_field(core)
  if not core:find(",") then
    local ref = parse_clause(core)
    if ref then return { ref } end
    return {}
  end

  local parts = {}
  for part in (core .. ","):gmatch("([^,]*),") do
    table.insert(parts, part)
  end
  if #parts < 2 then return {} end

  local refs = {}
  local chapter, verse1 = parts[1]:match("^(%d+)[%.:](%d+)$")
  if not chapter then
    -- First part might itself be a chapter.verse-range; fall back to
    -- treating the whole field as one clause if that fails too.
    local ref = parse_clause(parts[1])
    if not ref then return {} end
    table.insert(refs, ref)
    chapter = nil
  else
    table.insert(refs, chapter .. "." .. verse1)
  end

  for i = 2, #parts do
    local p = parts[i]
    if chapter then
      local vs, ve = p:match("^(%d+)[\u{2013}%-]+(%d+)$")
      if vs then
        table.insert(refs, chapter .. "." .. endash(vs, ve))
      else
        local v = p:match("^(%d+)$")
        if v then table.insert(refs, chapter .. "." .. v) end
      end
    end
  end

  return refs
end

-- Flatten a Pandoc Inlines list into a parallel token array. Only Str,
-- Space and SoftBreak are given semantic types; everything else
-- (Emph, Strong, Span, Note, Cite, LineBreak, ...) is opaque and blocks a
-- book/chapter match from spanning across it.
local function tokenize(inlines)
  local tokens = {}
  for i, el in ipairs(inlines) do
    if el.t == "Str" then
      tokens[i] = { kind = "str", text = el.text }
    elseif el.t == "Space" or el.t == "SoftBreak" then
      tokens[i] = { kind = "space" }
    else
      tokens[i] = { kind = "other" }
    end
  end
  return tokens
end

-- Try to match a book name starting at token index i. Returns
-- canonical_book, end_index (index of the last book token) or nil.
local function match_book(tokens, n, i)
  if not tokens[i] or tokens[i].kind ~= "str" then return nil end
  local word = core_word(tokens[i].text)

  -- Numbered form: "1", Space, "Sam" / "Samuel" / ...
  if word:match("^[123]$") and tokens[i + 1] and tokens[i + 1].kind == "space"
      and tokens[i + 2] and tokens[i + 2].kind == "str" then
    local word2 = core_word(tokens[i + 2].text)
    local base = NUMBERED_BASES[word2]
    if base then
      local numeral = tonumber(word)
      local max = MAX_NUMERAL[word2] or 2
      if numeral <= max then
        return numeral .. " " .. base, i + 2
      end
    end
  end

  -- Single-token form.
  local book = SINGLE_BOOKS[word]
  if book then
    return book, i
  end

  return nil
end

-- Given the flat inline list and tokens, try to find and parse a full
-- reference (book + one or more semicolon-continued clauses) starting at
-- token index i. Returns book, {ref, ref, ...}, end_index or nil.
local function match_reference(inlines, tokens, n, i)
  local book, book_end = match_book(tokens, n, i)
  if not book then return nil end

  -- Require the next token (after a space) to start with a digit.
  local j = book_end + 1
  if not (tokens[j] and tokens[j].kind == "space") then return nil end
  j = j + 1
  if not (tokens[j] and tokens[j].kind == "str" and tokens[j].text:match("^%d")) then
    return nil
  end

  local refs = {}
  local last_end = book_end
  while tokens[j] and tokens[j].kind == "str" do
    local core, continued = trim_numeral_token(tokens[j].text)
    local clause_refs = parse_numeral_field(core)
    if #clause_refs == 0 then
      if #refs == 0 then return nil end
      break
    end
    for _, r in ipairs(clause_refs) do table.insert(refs, r) end
    last_end = j

    if not continued then break end
    -- Continue to the next semicolon-separated clause under the same book.
    if not (tokens[j + 1] and tokens[j + 1].kind == "space"
        and tokens[j + 2] and tokens[j + 2].kind == "str") then
      break
    end
    j = j + 2
  end

  if #refs == 0 then return nil end
  return book, refs, last_end
end

-- Process a flat Inlines list (the direct content of a Para/Plain block),
-- returning a new Inlines list with index-marker RawInlines inserted after
-- each recognised biblical reference and each .anc marker span (docx/typst
-- only; HTML output is unaffected here but occurrences are still recorded
-- for the static list).
--
-- docx: every occurrence gets a bookmark, EXCEPT that the same (section,
-- entry, locus) triple recognised more than once within this single block
-- is only bookmarked on its first occurrence (see the "Docx occurrence
-- marking" note at the top of the file).
-- typst: every occurrence gets its own #index() call, un-deduped;
-- in-dexter collapses duplicate pages on its own.
local function process_inlines(inlines)
  local tokens = tokenize(inlines)
  local n = #inlines
  local out = pandoc.List{}
  local seen_in_block = {}

  local function emit_occurrence(slug, entry, locus)
    if is_docx then
      local dedup_key = slug .. "\30" .. entry .. "\30" .. locus
      if not seen_in_block[dedup_key] then
        seen_in_block[dedup_key] = true
        out:insert(make_bookmark(slug, entry, locus))
      end
    elseif is_typst then
      out:insert(make_typst_index_entry(slug, entry, locus))
    end
  end

  local i = 1
  while i <= n do
    local el = inlines[i]
    if el.t == "Span" and el.classes:includes("anc") then
      -- The marker span is a pure directive: drop it from the output and
      -- emit only the bookmark/#index call in its place.
      local slug, entry, locus = handle_marker_span(el)
      if slug then emit_occurrence(slug, entry, locus) end
      i = i + 1
    else
      local book, refs, match_end
      if el.t == "Str" then
        book, refs, match_end = match_reference(inlines, tokens, n, i)
      end
      if book then
        for k = i, match_end do out:insert(inlines[k]) end
        local slug = book_section(book)
        for _, ref in ipairs(refs) do
          record_entry(slug, book, ref)
          emit_occurrence(slug, book, ref)
        end
        i = match_end + 1
      else
        out:insert(el)
        i = i + 1
      end
    end
  end
  return out
end

-- Recurse into Note elements found within an Inlines list, processing
-- their block content (which may itself contain further Notes, though
-- Pandoc does not nest footnotes in practice).
local function process_notes_in_inlines(inlines)
  for i, el in ipairs(inlines) do
    if el.t == "Note" then
      el.content = process_blocks(el.content)
      inlines[i] = el
    end
  end
  return inlines
end

-- ──────────────────────────────────────────────
-- Block-level walking
-- ──────────────────────────────────────────────

function process_blocks(blocks)
  local out = pandoc.List{}
  for _, block in ipairs(blocks) do
    if block.t == "Para" or block.t == "Plain" then
      local content = process_notes_in_inlines(block.content)
      content = process_inlines(content)
      if block.t == "Para" then
        out:insert(pandoc.Para(content))
      else
        out:insert(pandoc.Plain(content))
      end
    elseif block.t == "BlockQuote" then
      block.content = process_blocks(block.content)
      out:insert(block)
    elseif block.t == "Div" then
      block.content = process_blocks(block.content)
      out:insert(block)
    elseif block.t == "BulletList" or block.t == "OrderedList" then
      -- .content is a list of items, each itself a list of Blocks.
      local new_items = {}
      for _, item in ipairs(block.content) do
        table.insert(new_items, process_blocks(item))
      end
      block.content = new_items
      out:insert(block)
    elseif block.t == "DefinitionList" then
      -- .content is a list of {Inlines, {Blocks, Blocks, ...}} pairs.
      local new_items = {}
      for _, pair in ipairs(block.content) do
        local term, defs = pair[1], pair[2]
        local new_defs = {}
        for _, def_blocks in ipairs(defs) do
          table.insert(new_defs, process_blocks(def_blocks))
        end
        table.insert(new_items, { term, new_defs })
      end
      block.content = new_items
      out:insert(block)
    else
      out:insert(block)
    end
  end
  return out
end

-- ──────────────────────────────────────────────
-- Filter
-- ──────────────────────────────────────────────

return {
  {
    Pandoc = function(doc)
      doc.blocks = process_blocks(doc.blocks)

      local index_idx = nil
      for i, block in ipairs(doc.blocks) do
        if block.t == "Header" and block.identifier == "ancient-index" then
          index_idx = i
          break
        end
      end

      if not index_idx then return doc end

      if #active_sections() == 0 then return doc end

      if is_docx then
        local index_blocks = build_docx_index_blocks()
        for j, blk in ipairs(index_blocks) do
          table.insert(doc.blocks, index_idx + j, blk)
        end
      elseif is_typst then
        local index_blocks = make_typst_index_blocks()
        for j, blk in ipairs(index_blocks) do
          table.insert(doc.blocks, index_idx + j, blk)
        end
      else
        -- HTML/other: static sectioned two-level list, entries in
        -- canonical/sorted order, subentries by sort key.
        local insert_at = index_idx
        for _, s in ipairs(active_sections()) do
          insert_at = insert_at + 1
          table.insert(doc.blocks, insert_at, section_heading_block(s.title))

          local outer_items = pandoc.List{}
          for _, entry in ipairs(sorted_entries(s.slug)) do
            local inner_items = pandoc.List{}
            for _, locus in ipairs(sorted_loci(s.slug, entry)) do
              if locus ~= "" then
                inner_items:insert(pandoc.Plain(pandoc.Inlines{pandoc.Str(locus)}))
              end
            end

            local term = pandoc.Inlines{pandoc.Str(entry)}
            local defs
            if #inner_items > 0 then
              local def = pandoc.Blocks{pandoc.BulletList(
                (function()
                  local items = {}
                  for _, it in ipairs(inner_items) do
                    table.insert(items, pandoc.Blocks{it})
                  end
                  return items
                end)()
              )}
              defs = {def}
            else
              defs = {pandoc.Blocks{}}
            end
            outer_items:insert({term, defs})
          end

          insert_at = insert_at + 1
          table.insert(doc.blocks, insert_at, pandoc.DefinitionList(outer_items))
        end
      end

      return doc
    end,
  },
}
