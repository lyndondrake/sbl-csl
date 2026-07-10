-- ld-ancient-index.lua
-- Pandoc Lua filter that generates an index of ancient sources (scripture
-- references) from body text and footnotes. Closely modelled on
-- ld-author-index.lua: same three output paths, same marker-heading
-- mechanics, same coding style.
--
-- Three output paths:
--   Word (.docx): injects XE index entry fields ("Book:Chapter.Verse")
--     flagged \f "ancient" alongside recognised references, and an
--     INDEX \f "ancient" field at the marker heading. Flagging keeps this
--     index separate from ld-author-index.lua's (unflagged) author index,
--     so both INDEX fields can coexist in the same document without either
--     filter needing to know about the other. Word builds the index with
--     real page numbers when fields are updated (Ctrl+A, F9).
--   Typst: injects #index("Book", "Chapter.Verse", index: "ancient") calls
--     from the in-dexter package (>=0.3.0, tested against 0.7.2) alongside
--     references, and #make-index(title: none, indexes: ("ancient",)) at
--     the marker heading. in-dexter's `index:` parameter and its two-
--     positional-argument nested-entry form give a fully separate,
--     genuinely hierarchical ancient-sources index alongside the (default)
--     author index built by ld-author-index.lua. Typst renders the index
--     with real page numbers at compile time.
--   HTML/other: generates a static two-level list (book -> chapter.verse
--     subentries), with no page numbers, in canonical biblical book order.
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
-- Known limitations / design decisions (v1)
-- ──────────────────────────────────────────────
--   * Ordering: Word's INDEX field and in-dexter's #make-index() both sort
--     alphabetically by default, which is not the canonical scholarly
--     ordering (Genesis..Revelation) for an ancient-sources index. Fixing
--     this would require sort-key tricks (e.g. hidden ordinal prefixes)
--     that this filter deliberately does NOT attempt in v1. The HTML
--     static list IS produced in canonical order, since it is generated
--     directly by this filter rather than by Word/typst sorting machinery.
--     Reordering the docx/typst indexes is left as future work.
--   * Chapter/verse separator: source text may use either "." or ":"
--     (e.g. "Jer 32.7" and "Lev 25:23"). Both are recognised, but output
--     subentries always use "." for consistency (e.g. "Lev 25:23" indexes
--     as "Leviticus" -> "25.23").
--   * Recognition is limited to Str/Space/SoftBreak runs directly inside
--     Para/Plain blocks (including footnote content, via Note elements
--     found in that flat run). Para/Plain blocks are found by recursing
--     into BlockQuote, Div, list items and DefinitionList content, so
--     references in block quotations and lists are covered; Table cells
--     are NOT recursed into in v1. References nested inside further
--     inline containers (Emph, Strong, Span, Link, etc.) are NOT scanned,
--     so an italicised reference would be missed. In practice this also means
--     content inside `[...]{lang="he"}` spans is skipped, satisfying the
--     brief's requirement to exclude Hebrew-language spans, but as a
--     side effect of the simpler "don't descend into inline containers"
--     rule rather than a dedicated lang="he" check.
--   * A "book name" is only recognised when the following token begins
--     with a digit (the chapter number). This is applied uniformly, not
--     just for ambiguous short words, since every real reference in this
--     scheme is book + chapter.
--
-- Compatible with Quarto (use citeproc: false + explicit filter ordering).

-- ──────────────────────────────────────────────
-- Configuration
-- ──────────────────────────────────────────────

local OUTPUT_FORMAT = FORMAT or "html"
local is_docx = OUTPUT_FORMAT == "docx" or OUTPUT_FORMAT == "openxml"
local is_typst = OUTPUT_FORMAT == "typst"

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

-- Canonical scholarly ordering, for the HTML static list.
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

-- ──────────────────────────────────────────────
-- Reference tracking
-- ──────────────────────────────────────────────

local ancient_refs = {}     -- book -> { ref_string -> true }
local ancient_order = {}    -- book -> list of ref_string, insertion order (dedup)

local function record_ref(book, ref)
  if not ancient_refs[book] then
    ancient_refs[book] = {}
    ancient_order[book] = {}
  end
  if not ancient_refs[book][ref] then
    ancient_refs[book][ref] = true
    table.insert(ancient_order[book], ref)
  end
end

-- ──────────────────────────────────────────────
-- Word (docx) XE field generation
-- ──────────────────────────────────────────────

local function make_xe_field(book, ref)
  local escaped = (book .. ":" .. ref):gsub('"', '&quot;')
  return pandoc.RawInline("openxml",
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>' ..
    '<w:r><w:instrText xml:space="preserve"> XE "' .. escaped .. '" \\f "ancient" </w:instrText></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
  )
end

local function make_index_field()
  return pandoc.RawBlock("openxml",
    '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>' ..
    '<w:r><w:instrText xml:space="preserve"> INDEX \\f "ancient" \\c "2" \\z "1033" </w:instrText></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>' ..
    '<w:r><w:t>Update this field to generate the index (Ctrl+A, then F9)</w:t></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
  )
end

-- ──────────────────────────────────────────────
-- Typst index generation (via in-dexter package, dedicated "ancient" index)
-- ──────────────────────────────────────────────

local function typst_escape(s)
  return (s:gsub('"', '\\"'))
end

local function make_typst_index_entry(book, ref)
  return pandoc.RawInline("typst",
    '#index("' .. typst_escape(book) .. '", "' .. typst_escape(ref) .. '", index: "ancient")'
  )
end

local function make_typst_index()
  return pandoc.RawBlock("typst",
    '#make-index(title: none, indexes: ("ancient",))'
  )
end

-- ──────────────────────────────────────────────
-- Reference recognition
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
-- returning a new Inlines list with index-field RawInlines inserted after
-- each recognised reference (docx/typst only; HTML output is unaffected
-- here but references are still recorded for the static list).
local function process_inlines(inlines)
  local tokens = tokenize(inlines)
  local n = #inlines
  local out = pandoc.List{}
  local i = 1
  while i <= n do
    local book, refs, match_end
    if inlines[i].t == "Str" then
      book, refs, match_end = match_reference(inlines, tokens, n, i)
    end
    if book then
      for k = i, match_end do out:insert(inlines[k]) end
      for _, ref in ipairs(refs) do
        record_ref(book, ref)
        if is_docx then
          out:insert(make_xe_field(book, ref))
        elseif is_typst then
          out:insert(make_typst_index_entry(book, ref))
        end
      end
      i = match_end + 1
    else
      out:insert(inlines[i])
      i = i + 1
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

      if is_docx then
        table.insert(doc.blocks, index_idx + 1, make_index_field())
      elseif is_typst then
        table.insert(doc.blocks, index_idx + 1, make_typst_index())
      else
        -- HTML/other: static two-level list in canonical book order,
        -- subentries sorted numerically by chapter then verse.
        local books = {}
        for book, _ in pairs(ancient_refs) do table.insert(books, book) end
        table.sort(books, function(a, b)
          local oa, ob = ORDER_INDEX[a], ORDER_INDEX[b]
          if oa and ob then return oa < ob end
          if oa then return true end
          if ob then return false end
          return a < b
        end)

        if #books == 0 then return doc end

        local function ref_sort_key(ref)
          local c, v = ref:match("^(%d+)%.(%d+)")
          if not c then c = ref:match("^(%d+)") end
          return tonumber(c) or 0, tonumber(v) or 0
        end

        local outer_items = pandoc.List{}
        for _, book in ipairs(books) do
          local refs = {}
          for _, r in ipairs(ancient_order[book]) do table.insert(refs, r) end
          table.sort(refs, function(a, b)
            local ca, va = ref_sort_key(a)
            local cb, vb = ref_sort_key(b)
            if ca ~= cb then return ca < cb end
            return va < vb
          end)

          local inner_items = pandoc.List{}
          for _, ref in ipairs(refs) do
            inner_items:insert(pandoc.Plain(pandoc.Inlines{pandoc.Str(ref)}))
          end

          local term = pandoc.Inlines{pandoc.Str(book)}
          local def = pandoc.Blocks{pandoc.BulletList(
            (function()
              local items = {}
              for _, it in ipairs(inner_items) do
                table.insert(items, pandoc.Blocks{it})
              end
              return items
            end)()
          )}
          outer_items:insert({term, {def}})
        end

        table.insert(doc.blocks, index_idx + 1, pandoc.DefinitionList(outer_items))
      end

      return doc
    end,
  },
}
