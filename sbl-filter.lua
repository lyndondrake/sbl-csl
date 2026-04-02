-- sbl-filter.lua
-- Pandoc Lua filter for SBL citation post-processing.
-- Runs AFTER citeproc to fix limitations in CSL output.
--
-- Usage: pandoc --citeproc --lua-filter=sbl-filter.lua
--
-- Handles:
-- 1. Shorthand references (BDAG, BDB, etc.) in notes
-- 2. Note field appendices (reprint info, translation history)

local utils = pandoc.utils

-- ──────────────────────────────────────────────
-- Parse the bibliography YAML for SBL metadata
-- ──────────────────────────────────────────────

local sbl_entries = {}  -- id -> { shorthand, append, subsequent_suffix, ... }
local bib_path = nil
local seen_ids = {}     -- track cited entries for subsequent note detection

-- Parse sbl: block from a note field string
local function parse_sbl_note(note_str)
  if not note_str then return {} end
  local sbl = {}
  local in_sbl = false

  for line in note_str:gmatch("[^\n]+") do
    if line:match("^%s*sbl:%s*$") then
      in_sbl = true
    elseif in_sbl then
      local key, value = line:match("^%s+(%S+):%s*(.+)%s*$")
      if key and value then
        value = value:gsub("^['\"](.+)['\"]$", "%1")
        sbl[key] = value
      elseif not line:match("^%s") then
        in_sbl = false
      end
    end
  end

  -- Parse options array into boolean flags
  if sbl.options then
    local opts = sbl.options
    -- Check each option individually to avoid substring matching
    for opt in opts:gmatch("[%w_=]+") do
      opt = opt:match("^%s*(.-)%s*$")  -- trim
      if opt == "skipbib" then
        sbl.skipbib = true
      elseif opt == "skipbiblist" or opt == "skipbiblistshorthand" then
        sbl.skipbiblist = true
      end
    end
  end
  -- Also support explicit skipbib: true as a direct key
  if sbl.skipbib == "true" then
    sbl.skipbib = true
  end

  return sbl
end

-- Read bibliography file and extract SBL metadata
local function load_bibliography(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("sbl-filter: cannot open bibliography: " .. path .. "\n")
    return
  end

  local content = f:read("*a")
  f:close()

  -- Simple YAML parser for the fields we need
  -- We parse entry blocks delimited by "- id:" lines
  local current_id = nil
  local current_note = nil
  local current_annote = false
  local in_note = false
  local note_indent = 0

  for line in content:gmatch("[^\n]*") do
    -- New entry
    local id = line:match("^%- id:%s*(.+)%s*$")
    if id then
      -- Save previous entry's note
      if current_id and current_note then
        local sbl = parse_sbl_note(current_note)
        if next(sbl) then
          -- Merge sbl data with any existing entry (preserves collection_title etc.)
          if not sbl_entries[current_id] then
            sbl_entries[current_id] = sbl
          else
            for k, v in pairs(sbl) do
              sbl_entries[current_id][k] = v
            end
          end
        end
        -- Mark if entry has annote
        if current_annote then
          if not sbl_entries[current_id] then
            sbl_entries[current_id] = {}
          end
          sbl_entries[current_id].annote = true
        end
      end
      current_id = id
      current_note = nil
      current_annote = false
      in_note = false
    end

    -- Detect annote field
    if line:match("^%s+annote:") then
      current_annote = true
    end

    -- Parse author (literal form) for template use
    local author_literal = line:match("^%s+%- literal:%s*(.+)%s*$")
    if author_literal and current_id then
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].author_literal = author_literal
    end

    -- Parse title for template use
    local title = line:match("^%s+title:%s*(.+)%s*$")
    if title and current_id then
      title = title:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].entry_title = title
    end

    -- Parse entry type
    local entry_type = line:match("^%s+type:%s*(.+)%s*$")
    if entry_type and current_id then
      entry_type = entry_type:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].entry_type = entry_type
    end

    -- Detect collection-title and collection-title-short (for maintitle italic and abbreviation list)
    local ct = line:match("^%s+collection%-title:%s*(.+)%s*$")
    if ct and current_id then
      ct = ct:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then
        sbl_entries[current_id] = {}
      end
      sbl_entries[current_id].collection_title = ct
    end
    local cts = line:match("^%s+collection%-title%-short:%s*(.+)%s*$")
    if cts and current_id then
      cts = cts:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then
        sbl_entries[current_id] = {}
      end
      sbl_entries[current_id].collection_title_short = cts
    end

    -- Detect container-title and container-title-short (for abbreviation list)
    local cnt = line:match("^%s+container%-title:%s*(.+)%s*$")
    if cnt and current_id then
      cnt = cnt:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].container_title = cnt
    end
    local cnts = line:match("^%s+container%-title%-short:%s*(.+)%s*$")
    if cnts and current_id then
      cnts = cnts:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].container_title_short = cnts
    end

    -- Parse publisher-place (for location suppression in bibliography)
    local pp = line:match("^%s+publisher%-place:%s*(.+)%s*$")
    if pp and current_id then
      pp = pp:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].publisher_place = pp
    end

    -- Parse issued year from date-parts (for location suppression)
    -- Format: "    - - YYYY" under "  issued:" / "    date-parts:"
    local year = line:match("^%s+%-%s+%-%s+(%d+)%s*$")
    if year and current_id then
      local y = tonumber(year)
      if y then
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        -- Store the first (earliest) year only
        if not sbl_entries[current_id].issued_year then
          sbl_entries[current_id].issued_year = y
        end
      end
    end

    -- Note field start
    if line:match("^%s+note:%s*|%s*$") or line:match("^%s+note:%s*>%s*$") then
      in_note = true
      current_note = ""
      note_indent = #(line:match("^(%s+)") or "") + 2
    elseif line:match("^%s+note:%s+.+$") then
      -- Single-line note
      current_note = line:match("^%s+note:%s+(.+)$")
      in_note = false
    elseif in_note then
      -- Check if still in the note block (must be indented more)
      local indent = #(line:match("^(%s*)") or "")
      if line == "" or indent >= note_indent then
        current_note = current_note .. "\n" .. line
      else
        in_note = false
      end
    end
  end

  -- Don't forget the last entry
  if current_id and current_note then
    local sbl = parse_sbl_note(current_note)
    if next(sbl) then
      sbl_entries[current_id] = sbl
    end
  end
end

-- ──────────────────────────────────────────────
-- Inline element helpers
-- ──────────────────────────────────────────────

-- Create inlines from simple text with *italic* markers
local function parse_inline(str)
  local result = pandoc.Inlines{}
  local pos = 1

  while pos <= #str do
    local star_start = str:find("*", pos, true)
    if star_start then
      if star_start > pos then
        result:extend(pandoc.Inlines(str:sub(pos, star_start - 1)))
      end
      local star_end = str:find("*", star_start + 1, true)
      if star_end then
        result:insert(pandoc.Emph(pandoc.Inlines(str:sub(star_start + 1, star_end - 1))))
        pos = star_end + 1
      else
        result:extend(pandoc.Inlines(str:sub(star_start)))
        pos = #str + 1
      end
    else
      result:extend(pandoc.Inlines(str:sub(pos)))
      pos = #str + 1
    end
  end

  return result
end

-- ──────────────────────────────────────────────
-- Entrysubtype templates (Phase E)
-- ──────────────────────────────────────────────
-- Templates compose citation text from entry fields, replacing static annote.
-- Each template function takes the sbl_entry table and returns an HTML string
-- (or nil if the entry can't be templated).

local templates = {}

-- Ancient texts (standalone): Author, *Work*. [locator added by CSL annote branch]
-- Examples: Josephus, *Ant*. / Tacitus, *Ann*. / Heraclitus, *Epistle 1*,
-- These are entries with no entrysubtype (standalone ancient works).
-- Kept as a named function for use via ancienttext_standalone below.
local function template_ancienttext_standalone(entry)
  local author = entry.author_literal
  local title = entry.entry_title
  if not author or not title then return nil end
  -- Remove trailing period from title (CSL adds it via the annote branch)
  local suffix = ","
  if title:match("%.$") then
    title = title:sub(1, -2)
    suffix = "."
  end
  return author .. ", <i>" .. title .. "</i>" .. suffix
end

-- Ancient book: complete ancient work in a collection series (ANF, NPNF, PG)
-- Examples: Augustine, *Letters of St. Augustin* / Gregory, *Orationes theologicae*
-- Note: The locator includes the series reference (ANF/NPNF/PG vol:page)
-- which is embedded in the annote, so this template only handles the base.
templates.ancientbook = function(entry)
  local author = entry.author_literal
  local title = entry.entry_title
  if not title then return nil end
  if author then
    return author .. ", <i>" .. title .. "</i>"
  else
    return "<i>" .. title .. "</i>"
  end
end

-- inancientbook: part of an ancient work in a collection series
-- Uses the same format as ancientbook for now.
templates.inancientbook = templates.ancientbook

-- inancientcollection: text in a modern collection (COS, ANET, RIMA, ABC, ANRW)
-- These are typically handled via annote; template provides fallback.
templates.inancientcollection = templates.ancientbook

-- Generate annote-equivalent text from a template
-- Returns nil if no template matches or entry lacks required fields
local function apply_template(entry)
  if not entry.entrysubtype then return nil end
  local template_fn = templates[entry.entrysubtype]
  if not template_fn then return nil end
  return template_fn(entry)
end

-- ──────────────────────────────────────────────
-- Italic maintitle in "vol. X of Title" pattern
-- ──────────────────────────────────────────────

-- Italicise the collection-title after "of " in the inline AST.
-- Walks the inlines, finds "of" followed by the collection-title text,
-- and wraps the title portion in Emph.
local function italicise_maintitle(inlines, collection_title)
  if not collection_title or collection_title == "" then return inlines end

  -- First check if the text even contains the pattern
  local full_text = utils.stringify(inlines)
  if not full_text:find(collection_title, 1, true) then return inlines end

  -- Split collection-title into first word for matching
  local ct_first_word = collection_title:match("^(%S+)")
  if not ct_first_word then return inlines end

  -- Walk inlines looking for Str "of" followed by Space then ct_first_word
  local result = pandoc.Inlines{}
  local i = 1
  local found = false

  while i <= #inlines do
    local el = inlines[i]

    -- Look for the pattern: Str ending with "of", Space, Str starting with ct_first_word
    if not found and el.t == "Str" and el.text:match("of$") and
       i + 2 <= #inlines and inlines[i+1].t == "Space" then
      local next_str = inlines[i+2]
      if next_str.t == "Str" and next_str.text == ct_first_word then
        -- Found the "of Title" pattern — collect all title words into Emph
        result:insert(el)      -- "of"
        result:insert(inlines[i+1])  -- Space
        i = i + 2

        -- Collect words that are part of the collection-title
        local title_inlines = pandoc.Inlines{}
        local collected_text = ""
        while i <= #inlines do
          local cur = inlines[i]
          if cur.t == "Str" then
            local new_text = collected_text .. (collected_text ~= "" and " " or "") .. cur.text
            -- Check if this still matches the collection-title prefix
            if collection_title:sub(1, #new_text) == new_text or
               collection_title == new_text or
               collection_title:sub(1, #collected_text + #cur.text + 1):find(cur.text, 1, true) then
              title_inlines:insert(cur)
              collected_text = new_text
              i = i + 1
            else
              break
            end
          elseif cur.t == "Space" then
            title_inlines:insert(cur)
            i = i + 1
          else
            break
          end
        end

        -- Wrap collected title words in Emph
        if #title_inlines > 0 then
          result:insert(pandoc.Emph(title_inlines))
          found = true
        end
        -- Continue with remaining inlines (don't increment i, already advanced)
        goto continue
      end
    end

    result:insert(el)
    i = i + 1
    ::continue::
  end

  if found then return result end
  return inlines
end

-- ──────────────────────────────────────────────
-- Location suppression (SBLHS Blog update)
-- ──────────────────────────────────────────────
-- For books published after 1900, remove publisher location from bibliography.
-- Notes (footnotes) retain the full location:publisher format.
-- The citeproc output contains "Place: Publisher, Year" in the bibliography.
-- We need to remove the "Place: " portion, leaving "Publisher, Year".

-- Suppress publisher-place in bibliography inlines for post-1900 entries.
-- Walks the inline elements, finds the publisher_place text followed by
-- a colon, and removes it. Returns the modified inlines (or original if
-- no match found).
local function suppress_location_in_bib(inlines, publisher_place)
  if not publisher_place or publisher_place == "" then return inlines end

  -- Stringify the inlines to find the place text
  local full_text = utils.stringify(inlines)

  -- Check if the publisher-place appears in the text
  -- The pattern in bibliography is "Place: Publisher" or "Place and Place: Publisher"
  -- We need to find "Place:" (with the colon) and also remove the following space
  if not full_text:find(publisher_place, 1, true) then return inlines end

  -- Build the target text to remove: "Place: " (with colon and space after)
  -- We need to find the publisher_place text followed by ": " in the inline elements
  -- Strategy: walk through inlines collecting text, find the range of elements
  -- that comprise "Place: " and remove them.

  -- First, split publisher_place into words to match against Str elements
  local place_words = {}
  for word in publisher_place:gmatch("%S+") do
    table.insert(place_words, word)
  end
  if #place_words == 0 then return inlines end

  -- Walk inlines to find where the place text starts
  -- We look for a sequence of Str/Space elements that spell out the publisher_place
  -- followed by a colon (which may be attached to the last Str of the place)
  local result = pandoc.Inlines{}
  local i = 1
  local found = false

  while i <= #inlines do
    if not found and inlines[i].t == "Str" then
      -- Try to match publisher_place starting at this Str element
      local match_end = nil
      local word_idx = 1
      local j = i

      while j <= #inlines and word_idx <= #place_words do
        local el = inlines[j]
        if el.t == "Str" then
          local expected_word = place_words[word_idx]
          if word_idx == #place_words then
            -- Last word of place: expect ":" appended (e.g. "York:")
            if el.text == expected_word .. ":" then
              -- Found complete match including colon
              match_end = j
              word_idx = word_idx + 1
            else
              -- Doesn't match the expected "lastword:" pattern
              break
            end
          else
            if el.text == expected_word then
              word_idx = word_idx + 1
            else
              break
            end
          end
        elseif el.t == "Space" then
          -- Spaces between words are expected; skip them
        else
          -- Non-Str/non-Space element breaks the match
          break
        end
        j = j + 1
      end

      if match_end then
        -- Successfully matched the publisher_place + colon
        -- Remove the preceding Space (period-space-Place becomes period-space)
        -- Actually: keep preceding Space so we get ". Crossroad, 1992."
        found = true
        i = match_end + 1
        -- Skip trailing Space after the colon
        if i <= #inlines and inlines[i].t == "Space" then
          i = i + 1
        end
      else
        -- No match at this position; keep the element
        result:insert(inlines[i])
        i = i + 1
      end
    else
      -- Either already found, or not a Str element — keep it
      result:insert(inlines[i])
      i = i + 1
    end
  end

  if found then return result end
  return inlines
end

-- ──────────────────────────────────────────────
-- Note manipulation
-- ──────────────────────────────────────────────

-- Replace note content with shorthand citation
local function make_shorthand_cite(shorthand, suffix_inlines)
  local inlines = pandoc.Inlines{}
  inlines:insert(pandoc.Str(shorthand))

  -- Add suffix (locator) if present
  if suffix_inlines and #suffix_inlines > 0 then
    local suffix_text = utils.stringify(suffix_inlines):gsub("^[,%s]+", "")
    if suffix_text ~= "" then
      inlines:insert(pandoc.Str(","))
      inlines:insert(pandoc.Space())
      inlines:extend(pandoc.Inlines(suffix_text))
    end
  end

  inlines:insert(pandoc.Str("."))
  return pandoc.Note(pandoc.Blocks{pandoc.Para(inlines)})
end

-- Prepend shorthand label before a bibliography entry's content
local function prepend_shorthand_to_bib(div, shorthand)
  for i, block in ipairs(div.content) do
    if block.t == "Para" then
      local new_content = pandoc.Inlines{}
      new_content:insert(pandoc.Str(shorthand))
      new_content:insert(pandoc.LineBreak())
      new_content:extend(block.content)
      div.content[i] = pandoc.Para(new_content)
      return
    end
  end
end

-- ──────────────────────────────────────────────
-- Main filter (two passes)
-- ──────────────────────────────────────────────

return {
  {
    -- First pass: load bibliography metadata
    Meta = function(meta)
      if meta.bibliography then
        local bib = utils.stringify(meta.bibliography)
        -- Handle relative paths
        if not bib:match("^/") then
          -- Try to find it relative to the document
          bib_path = bib
        else
          bib_path = bib
        end
        load_bibliography(bib_path)
      end
      return nil
    end,
  },
  {
    -- Second pass: transform citations and bibliography
    Cite = function(cite)
      if #cite.citations == 0 then return nil end

      local citation = cite.citations[1]
      local id = citation.id
      local entry = sbl_entries[id]

      -- Track whether this citation has been seen before (for subsequent note suffix)
      local is_subsequent = seen_ids[id] or false
      seen_ids[id] = true

      if not entry then return nil end

      -- Handle shorthand references (only for reference works, not ancient texts)
      -- Skip if entry has annote (CSL annote bypass takes precedence)
      -- Skip if entry has entrysubtype (ancient texts use shorthand differently)
      if entry.shorthand and not entry.entrysubtype and not entry.annote then
        if #cite.content > 0 and cite.content[1].t == "Note" then
          return make_shorthand_cite(entry.shorthand, citation.suffix)
        end
      end

      -- Italicise maintitle in "vol. X of Title" pattern (notes)
      -- Only for entries with collection_title but NO collection_title_short
      if entry.collection_title and not entry.collection_title_short then
        if #cite.content > 0 and cite.content[1].t == "Note" then
          local note = cite.content[1]
          local modified = false
          for _, block in ipairs(note.content) do
            if block.t == "Para" then
              local new_content = italicise_maintitle(block.content, entry.collection_title)
              if new_content ~= block.content then
                block.content = new_content
                modified = true
              end
            end
          end
          if modified then return cite end
        end
      end

      -- Handle subsequent note replacement for annote entries
      if is_subsequent and entry.annote then
        if #cite.content > 0 and cite.content[1].t == "Note" then
          -- If entry has subsequent_annote, replace the entire note content
          if entry.subsequent_annote then
            local suffix = utils.stringify(citation.suffix or {}):gsub("^[,%s]+", "")
            local annote_text = entry.subsequent_annote
            if suffix ~= "" then
              annote_text = annote_text .. " " .. suffix
            end
            -- Also append subsequent_suffix if present (e.g., "(Thackeray, LCL)")
            if entry.subsequent_suffix then
              annote_text = annote_text .. " (" .. entry.subsequent_suffix .. ")"
            end
            annote_text = annote_text .. "."
            -- Parse the annote text (may contain HTML italic)
            local inlines = pandoc.read(annote_text, "html").blocks[1].content
            return pandoc.Note(pandoc.Blocks{pandoc.Para(inlines)})
          -- If entry has subsequent_suffix, append it
          elseif entry.subsequent_suffix then
            local note = cite.content[1]
            local blocks = note.content
            if #blocks > 0 then
              local last_para = blocks[#blocks]
              if last_para.t == "Para" then
                local content = last_para.content
                -- Remove trailing period if present
                if #content > 0 then
                  local last_el = content[#content]
                  if last_el.t == "Str" and last_el.text:sub(-1) == "." then
                    content[#content] = pandoc.Str(last_el.text:sub(1, -2))
                  end
                end
                -- Append the suffix
                content:insert(pandoc.Str(" "))
                content:insert(pandoc.Str("(" .. entry.subsequent_suffix .. ")."))
              end
            end
            return cite
          end
        end
      end

      return nil
    end,

    -- Process bibliography entries: shorthand labels and skipbib removal
    Div = function(div)
      if div.identifier ~= "refs" then return nil end

      local changed = false
      local to_remove = {}

      for i, block in ipairs(div.content) do
        if block.t == "Div" then
          local ref_id = block.identifier:match("^ref%-(.+)$")
          if ref_id then
            local entry = sbl_entries[ref_id]
            if entry then
              -- Remove entries with skipbib from bibliography
              -- BUT keep shorthand entries that should appear in the abbreviation list
              -- (they'll be moved to the abbreviation list in pass 3)
              local dominated_by_abbrev_list = entry.shorthand and not entry.skipbiblist
              if entry.skipbib and not dominated_by_abbrev_list then
                table.insert(to_remove, i)
                changed = true
              elseif entry.skipbib and dominated_by_abbrev_list then
                -- Kept for abbreviation list — prepend shorthand label
                if entry.shorthand then
                  prepend_shorthand_to_bib(block, entry.shorthand)
                  changed = true
                end
              elseif not entry.skipbib then
                -- Replace entire bibliography entry with bibliography_annote if set
                if entry.bibliography_annote then
                  local annote_doc = pandoc.read(entry.bibliography_annote, "html")
                  if annote_doc and #annote_doc.blocks > 0 and annote_doc.blocks[1].content then
                    for _, sub_block in ipairs(block.content) do
                      if sub_block.t == "Para" then
                        sub_block.content = annote_doc.blocks[1].content
                        changed = true
                        break
                      end
                    end
                  end
                else
                  -- Prepend shorthand to bibliography entries
                  if entry.shorthand and not entry.entrysubtype then
                    prepend_shorthand_to_bib(block, entry.shorthand)
                    changed = true
                  end
                  -- Italicise maintitle in bibliography
                  if entry.collection_title and not entry.collection_title_short then
                    for _, sub_block in ipairs(block.content) do
                      if sub_block.t == "Para" then
                        sub_block.content = italicise_maintitle(sub_block.content, entry.collection_title)
                        changed = true
                      end
                    end
                  end
                  -- Suppress publisher location for post-1900 entries (SBLHS Blog update)
                  if entry.publisher_place and entry.issued_year and entry.issued_year > 1900 then
                    for _, sub_block in ipairs(block.content) do
                      if sub_block.t == "Para" then
                        sub_block.content = suppress_location_in_bib(sub_block.content, entry.publisher_place)
                        changed = true
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      -- Remove skipbib entries (iterate in reverse to preserve indices)
      for j = #to_remove, 1, -1 do
        table.remove(div.content, to_remove[j])
      end

      if changed then return div end
      return nil
    end,
  },
  {
    -- Third pass: generate abbreviation list
    -- Finds heading with id "sbl-abbreviations" and populates it with
    -- a definition list of all cited shorthand entries.
    Pandoc = function(doc)
      -- Find the abbreviation list heading
      local abbrev_idx = nil
      for i, block in ipairs(doc.blocks) do
        if block.t == "Header" and block.identifier == "sbl-abbreviations" then
          abbrev_idx = i
          break
        end
      end

      if not abbrev_idx then return nil end

      -- Find the bibliography div to extract formatted entries
      local refs_div = nil
      for _, block in ipairs(doc.blocks) do
        if block.t == "Div" and block.identifier == "refs" then
          refs_div = block
          break
        end
      end

      if not refs_div then return nil end

      -- Collect abbreviation entries in four categories (matching biblatex-sbl v2):
      --   ancient:    primary source shorthand entries (source_type: ancient)
      --   secondary:  secondary source shorthand entries (full bibliography text)
      --   simple:     journal/series abbreviations (simple titles)
      --   sigla:      general abbreviations and sigla (abbreviation_type: sigla)
      local ancient = {}
      local secondary = {}
      local simple = {}
      local sigla = {}
      local seen_abbrevs = {}

      -- Category 1: Shorthand entries (bibliography-style, "Secondary Sources")
      for ref_id, entry in pairs(sbl_entries) do
        if entry.shorthand and not entry.skipbiblist and not seen_abbrevs[entry.shorthand] then
          -- Check for sigla entries (abbreviation_type: sigla in sbl: metadata)
          if entry.abbreviation_type == "sigla" then
            -- Sigla: use definition field if present, otherwise entry title
            local def_text = entry.definition or entry.entry_title or ""
            table.insert(sigla, {
              shorthand = entry.shorthand,
              content = pandoc.Inlines{pandoc.Str(def_text)},
            })
            seen_abbrevs[entry.shorthand] = true
          else
            -- Check if this entry was cited (exists in bibliography)
            local bib_entry = nil
            for _, block in ipairs(refs_div.content) do
              if block.t == "Div" and block.identifier == "ref-" .. ref_id then
                bib_entry = block
                break
              end
            end

            if bib_entry then
              -- Extract the formatted bibliography text
              local content = pandoc.Inlines{}
              for _, sub_block in ipairs(bib_entry.content) do
                if sub_block.t == "Para" then
                  -- Skip the shorthand label line if present
                  local skip_first = false
                  for _, inline in ipairs(sub_block.content) do
                    if inline.t == "LineBreak" then
                      skip_first = true
                      break
                    end
                  end
                  if skip_first then
                    -- Content after the LineBreak is the actual bibliography text
                    local after_break = false
                    for _, inline in ipairs(sub_block.content) do
                      if after_break then
                        content:insert(inline)
                      end
                      if inline.t == "LineBreak" then
                        after_break = true
                      end
                    end
                  else
                    content:extend(sub_block.content)
                  end
                end
              end

              local target = (entry.source_type == "ancient") and ancient or secondary
              table.insert(target, {
                shorthand = entry.shorthand,
                content = content,
              })
              seen_abbrevs[entry.shorthand] = true
            end
          end
        end
      end

      -- Category 2: Journal and series abbreviations (simple title)
      -- Build set of all cited/referenced entry IDs (refs div + seen_ids)
      -- to catch entries removed from refs div by skipbib
      local cited_ids = {}
      for id, _ in pairs(seen_ids) do
        cited_ids[id] = true
      end
      for _, block in ipairs(refs_div.content) do
        if block.t == "Div" then
          local ref_id = block.identifier:match("^ref%-(.+)$")
          if ref_id then cited_ids[ref_id] = true end
        end
      end

      -- Collect from all cited entries (including skipbib ones)
      for ref_id, entry in pairs(sbl_entries) do
        if cited_ids[ref_id] then
          -- Container-title-short → container-title (journals/magazines: italic)
          if entry.container_title_short and entry.container_title
              and not seen_abbrevs[entry.container_title_short] then
            local is_journal = entry.entry_type == "article-journal"
                or entry.entry_type == "article-magazine"
                or entry.entry_type == "review"
            local title_inlines = pandoc.Inlines{}
            if is_journal then
              title_inlines:insert(pandoc.Emph{pandoc.Str(entry.container_title)})
            else
              title_inlines:insert(pandoc.Str(entry.container_title))
            end
            table.insert(simple, {
              shorthand = entry.container_title_short,
              content = title_inlines,
              is_journal = is_journal,
            })
            seen_abbrevs[entry.container_title_short] = true
          end
          -- Collection-title-short → collection-title (series: roman)
          if entry.collection_title_short and entry.collection_title
              and not seen_abbrevs[entry.collection_title_short] then
            table.insert(simple, {
              shorthand = entry.collection_title_short,
              content = pandoc.Inlines{pandoc.Str(entry.collection_title)},
            })
            seen_abbrevs[entry.collection_title_short] = true
          end
          -- Sigla from definition field (entries without shorthand)
          if entry.abbreviation_type == "sigla" and entry.definition
              and not seen_abbrevs[ref_id] then
            local abbr_key = entry.shorthand or ref_id
            if not seen_abbrevs[abbr_key] then
              table.insert(sigla, {
                shorthand = abbr_key,
                content = pandoc.Inlines{pandoc.Str(entry.definition)},
              })
              seen_abbrevs[abbr_key] = true
            end
          end
        end
      end

      -- Merge into a flat list or sectioned list depending on what's present
      -- When only one section has entries, produce a single flat list (no sub-headings).
      -- When multiple sections have entries, add sub-headings per biblatex-sbl v2.
      local section_count = 0
      if #ancient > 0 then section_count = section_count + 1 end
      if #secondary > 0 then section_count = section_count + 1 end
      if #simple > 0 then section_count = section_count + 1 end
      if #sigla > 0 then section_count = section_count + 1 end

      if section_count == 0 then return nil end

      -- Sort each section alphabetically by shorthand
      local function sort_abbrevs(list)
        table.sort(list, function(a, b)
          return a.shorthand:lower() < b.shorthand:lower()
        end)
      end
      sort_abbrevs(ancient)
      sort_abbrevs(secondary)
      sort_abbrevs(simple)
      sort_abbrevs(sigla)

      -- Build the sections list: each entry is {heading, items}
      -- When only one section exists, the heading is nil (no sub-heading)
      local sections = {}
      if section_count == 1 then
        -- Single section: flat list, no sub-heading
        local all = {}
        for _, item in ipairs(ancient) do table.insert(all, item) end
        for _, item in ipairs(secondary) do table.insert(all, item) end
        for _, item in ipairs(simple) do table.insert(all, item) end
        for _, item in ipairs(sigla) do table.insert(all, item) end
        sort_abbrevs(all)
        table.insert(sections, {heading = nil, items = all})
      else
        -- Multiple sections: add sub-headings
        if #ancient > 0 then
          table.insert(sections, {heading = "Ancient Sources", items = ancient})
        end
        if #secondary > 0 then
          table.insert(sections, {heading = "Secondary Sources", items = secondary})
        end
        if #simple > 0 then
          table.insert(sections, {heading = "Journals, Series, and Other Abbreviations", items = simple})
        end
        if #sigla > 0 then
          table.insert(sections, {heading = "General Abbreviations and Sigla", items = sigla})
        end
      end

      -- Render inline content to a string for raw output
      local function inlines_to_typst(inlines)
        local parts = {}
        for _, el in ipairs(inlines) do
          if el.t == "Str" then
            -- Escape typst special characters
            local s = el.text
            s = s:gsub("[#$]", "\\%0")
            table.insert(parts, s)
          elseif el.t == "Space" then
            table.insert(parts, " ")
          elseif el.t == "Emph" then
            table.insert(parts, "_" .. inlines_to_typst(el.content) .. "_")
          elseif el.t == "Strong" then
            table.insert(parts, "*" .. inlines_to_typst(el.content) .. "*")
          elseif el.t == "Quoted" then
            if el.quotetype == "DoubleQuote" then
              table.insert(parts, '\u{201c}' .. inlines_to_typst(el.content) .. '\u{201d}')
            else
              table.insert(parts, '\u{2018}' .. inlines_to_typst(el.content) .. '\u{2019}')
            end
          elseif el.t == "SoftBreak" or el.t == "LineBreak" then
            table.insert(parts, " ")
          else
            -- Fallback: use pandoc to render
            table.insert(parts, utils.stringify(el))
          end
        end
        return table.concat(parts)
      end

      -- Helper: render a list of abbreviation items as typst definition list lines
      local function render_typst_items(items, lines)
        for _, abbr in ipairs(items) do
          local term_str
          if abbr.is_journal then
            term_str = "_" .. abbr.shorthand .. "_"
          else
            term_str = abbr.shorthand
          end
          local def_str = inlines_to_typst(abbr.content)
          table.insert(lines, "/ " .. term_str .. ": " .. def_str)
        end
      end

      -- Helper: render a list of abbreviation items as pandoc definition list
      local function render_deflist_items(items)
        local dl_items = pandoc.List{}
        for _, abbr in ipairs(items) do
          local term
          if abbr.is_journal then
            term = pandoc.Inlines{pandoc.Emph{pandoc.Str(abbr.shorthand)}}
          else
            term = pandoc.Inlines{pandoc.Str(abbr.shorthand)}
          end
          local def = pandoc.Blocks{pandoc.Plain(abbr.content)}
          dl_items:insert({term, {def}})
        end
        return pandoc.DefinitionList(dl_items)
      end

      -- Detect output format
      local is_typst = FORMAT:match("typst")

      -- Determine the heading level for sub-headings (one level below the
      -- abbreviation list heading itself)
      local abbrev_heading = doc.blocks[abbrev_idx]
      local sub_level = (abbrev_heading.level or 1) + 1

      -- Insert blocks after the abbreviation heading
      local insert_pos = abbrev_idx

      if is_typst then
        -- Typst: emit a two-column grid matching biblatex-sbl layout
        for _, section in ipairs(sections) do
          if section.heading then
            -- Sub-heading as a typst raw block
            insert_pos = insert_pos + 1
            local heading_block = pandoc.Header(sub_level, pandoc.Inlines{pandoc.Str(section.heading)})
            table.insert(doc.blocks, insert_pos, heading_block)
          end

          local lines = {}
          -- Override the default template's #show terms.item: rule
          -- to get a two-column layout with aligned definitions
          table.insert(lines, '#show terms.item: it => {')
          table.insert(lines, '  let abbr-width = 2cm')
          table.insert(lines, '  grid(')
          table.insert(lines, '    columns: (abbr-width, 1fr),')
          table.insert(lines, '    column-gutter: 1em,')
          table.insert(lines, '    text(weight: "bold")[#it.term],')
          table.insert(lines, '    it.description,')
          table.insert(lines, '  )')
          table.insert(lines, '}')
          render_typst_items(section.items, lines)
          insert_pos = insert_pos + 1
          table.insert(doc.blocks, insert_pos, pandoc.RawBlock("typst", table.concat(lines, "\n")))
        end
      else
        -- Other formats: definition list(s) with optional sub-headings
        for _, section in ipairs(sections) do
          if section.heading then
            insert_pos = insert_pos + 1
            local heading_block = pandoc.Header(sub_level, pandoc.Inlines{pandoc.Str(section.heading)})
            table.insert(doc.blocks, insert_pos, heading_block)
          end
          insert_pos = insert_pos + 1
          table.insert(doc.blocks, insert_pos, render_deflist_items(section.items))
        end
      end

      -- Remove shorthand entries from bibliography — they now live in the
      -- abbreviation list only, per SBL convention. This includes:
      -- 1. Normal shorthand entries (moved from bib to abbrev list)
      -- 2. skipbib+shorthand entries (kept in pass 2 for extraction, now removed)
      -- 3. Sigla entries (abbreviation_type: sigla) — never in bibliography
      local bib_remove = {}
      for i, block in ipairs(refs_div.content) do
        if block.t == "Div" then
          local ref_id = block.identifier:match("^ref%-(.+)$")
          if ref_id then
            local entry = sbl_entries[ref_id]
            if entry then
              local is_abbrev_list_entry = entry.shorthand and not entry.skipbiblist and not entry.entrysubtype
              local is_sigla = entry.abbreviation_type == "sigla"
              if is_abbrev_list_entry or is_sigla then
                table.insert(bib_remove, i)
              end
            end
          end
        end
      end
      for j = #bib_remove, 1, -1 do
        table.remove(refs_div.content, bib_remove[j])
      end

      return doc
    end,
  },
}
