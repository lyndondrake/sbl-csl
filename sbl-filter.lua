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

-- Set a field on sbl_entries[id], creating the entry table on demand
local function set_entry_field(id, key, value)
  if value == nil then return end
  if not sbl_entries[id] then sbl_entries[id] = {} end
  sbl_entries[id][key] = value
end

-- CSL JSON bibliographies (e.g. Bookends/Zotero exports) are decoded
-- directly; the line-based parser below handles CSL YAML. Both populate
-- sbl_entries with the same keys.
local function load_bibliography_json(content)
  local ok, data = pcall(pandoc.json.decode, content)
  if not ok or type(data) ~= "table" then
    io.stderr:write("sbl-filter: cannot parse JSON bibliography\n")
    return
  end

  for _, entry in ipairs(data) do
    if type(entry) == "table" and entry.id then
      local id = entry.id

      if type(entry.note) == "string" then
        local sbl = parse_sbl_note(entry.note)
        if next(sbl) then
          for k, v in pairs(sbl) do
            set_entry_field(id, k, v)
          end
        end
      end

      if entry.annote ~= nil then
        set_entry_field(id, "annote", true)
        if type(entry.annote) == "string" then
          set_entry_field(id, "annote_value", entry.annote)
        end
      end

      -- First author's names (literal and family/given forms)
      if type(entry.author) == "table" then
        for _, name in ipairs(entry.author) do
          if type(name) == "table" then
            if name.literal and not (sbl_entries[id] or {}).author_literal then
              set_entry_field(id, "author_literal", name.literal)
            end
            if name.family and not (sbl_entries[id] or {}).author_family then
              set_entry_field(id, "author_family", name.family)
            end
            if name.given and not (sbl_entries[id] or {}).author_given then
              set_entry_field(id, "author_given", name.given)
            end
          end
        end
      end

      -- First editor's names (fallback for editor-as-primary entries)
      if type(entry.editor) == "table" then
        for _, name in ipairs(entry.editor) do
          if type(name) == "table" then
            if name.family and not (sbl_entries[id] or {}).editor_family then
              set_entry_field(id, "editor_family", name.family)
            end
            if name.given and not (sbl_entries[id] or {}).editor_given then
              set_entry_field(id, "editor_given", name.given)
            end
          end
        end
      end

      if type(entry.title) == "string" then
        set_entry_field(id, "entry_title", entry.title)
      end
      if type(entry.type) == "string" then
        set_entry_field(id, "entry_type", entry.type)
      end
      set_entry_field(id, "collection_title", entry["collection-title"])
      set_entry_field(id, "collection_title_short", entry["collection-title-short"])
      set_entry_field(id, "container_title", entry["container-title"])
      set_entry_field(id, "container_title_short", entry["container-title-short"])
      set_entry_field(id, "publisher_place", entry["publisher-place"])
      set_entry_field(id, "original_publisher_place", entry["original-publisher-place"])

      -- First year of issued / original-date
      local function first_year(date)
        if type(date) == "table" and type(date["date-parts"]) == "table" then
          local parts = date["date-parts"][1]
          if type(parts) == "table" then
            return tonumber(parts[1])
          end
        end
        return nil
      end
      set_entry_field(id, "issued_year", first_year(entry.issued))
      set_entry_field(id, "original_year", first_year(entry["original-date"]))
    end
  end
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

  if path:match("%.json$") then
    return load_bibliography_json(content)
  end

  -- Simple YAML parser for the fields we need
  -- We parse entry blocks delimited by "- id:" lines
  local current_id = nil
  local current_note = nil
  local current_annote = false
  local current_annote_value = nil
  local in_note = false
  local note_indent = 0
  local in_author_block = false  -- tracks whether we're inside an author: array
  local in_editor_block = false  -- tracks whether we're inside an editor: array
  local current_date_field = nil -- tracks which date field's date-parts we're in

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
        -- Mark if entry has annote (store the value for shorthand italic detection)
        if current_annote then
          if not sbl_entries[current_id] then
            sbl_entries[current_id] = {}
          end
          sbl_entries[current_id].annote = true
          if current_annote_value then
            sbl_entries[current_id].annote_value = current_annote_value
          end
        end
      end
      current_id = id
      current_note = nil
      current_annote = false
      current_annote_value = nil
      in_note = false
      in_author_block = false
      in_editor_block = false
      current_date_field = nil
    end

    -- Track whether we are inside the author: or editor: block
    if not in_note then
      if line:match("^%s+author:%s*$") then
        in_author_block = true
        in_editor_block = false
      elseif line:match("^%s+editor:%s*$") then
        in_editor_block = true
        in_author_block = false
      elseif line:match("^%s+%a[%a%-]*:") and not line:match("^%s+%-%s") and not line:match("^%s+given:") then
        -- A new top-level field (not a list item or given: continuation) exits any block
        if not line:match("^%s+author:") and not line:match("^%s+editor:") then
          in_author_block = false
          in_editor_block = false
        end
      end
    end

    -- Detect annote field and capture its value
    local annote_val = line:match("^%s+annote:%s*(.+)%s*$")
    if annote_val then
      current_annote = true
      -- Strip surrounding quotes
      annote_val = annote_val:gsub("^['\"](.+)['\"]$", "%1")
      current_annote_value = annote_val
    elseif line:match("^%s+annote:") then
      current_annote = true
    end

    -- Parse author (literal form) for template use — only inside author: block
    if in_author_block then
      local author_literal = line:match("^%s+%- literal:%s*(.+)%s*$")
      if author_literal and current_id then
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        sbl_entries[current_id].author_literal = author_literal
      end

      -- Parse author (family/given form) for bibliography em-dash repair
      local author_family = line:match("^%s+%- family:%s*(.+)%s*$")
      if author_family and current_id then
        author_family = author_family:gsub("^['\"](.+)['\"]$", "%1")
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        -- Only store the first author's family name (for bibliography formatting)
        if not sbl_entries[current_id].author_family then
          sbl_entries[current_id].author_family = author_family
        end
      end
      local author_given = line:match("^%s+given:%s*(.+)%s*$")
      if author_given and current_id then
        author_given = author_given:gsub("^['\"](.+)['\"]$", "%1")
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        if not sbl_entries[current_id].author_given then
          sbl_entries[current_id].author_given = author_given
        end
      end
    end

    -- Parse editor family/given as fallback for entries without author
    -- (editor-as-primary entries like ANET, IDB, etc.)
    if in_editor_block and current_id then
      local editor_family = line:match("^%s+%- family:%s*(.+)%s*$")
      if editor_family then
        editor_family = editor_family:gsub("^['\"](.+)['\"]$", "%1")
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        if not sbl_entries[current_id].editor_family then
          sbl_entries[current_id].editor_family = editor_family
        end
      end
      local editor_given = line:match("^%s+given:%s*(.+)%s*$")
      if editor_given then
        editor_given = editor_given:gsub("^['\"](.+)['\"]$", "%1")
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        if not sbl_entries[current_id].editor_given then
          sbl_entries[current_id].editor_given = editor_given
        end
      end
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

    -- Parse publisher-place (for location suppression)
    local pp = line:match("^%s+publisher%-place:%s*(.+)%s*$")
    if pp and current_id then
      pp = pp:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].publisher_place = pp
    end

    -- Parse original-publisher-place (for location suppression in reprint chains)
    local opp = line:match("^%s+original%-publisher%-place:%s*(.+)%s*$")
    if opp and current_id then
      opp = opp:gsub("^['\"](.+)['\"]$", "%1")
      if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
      sbl_entries[current_id].original_publisher_place = opp
    end

    -- Track which date field we are inside, so years land on the right key.
    -- Date fields open a block like "  issued:" followed by "    date-parts:".
    local date_field = line:match("^%s+(issued):%s*$")
      or line:match("^%s+(original%-date):%s*$")
      or line:match("^%s+(accessed):%s*$")
      or line:match("^%s+(event%-date):%s*$")
    if date_field then
      current_date_field = date_field
    elseif line:match("^%s+%a[%a%-]*:") and not line:match("^%s+date%-parts:") then
      -- Any other field ends the date block
      current_date_field = nil
    end

    -- Parse year from date-parts: "    - - YYYY" lines
    local year = line:match("^%s+%-%s+%-%s+(%d+)%s*$")
    if year and current_id then
      local y = tonumber(year)
      if y then
        if not sbl_entries[current_id] then sbl_entries[current_id] = {} end
        local e = sbl_entries[current_id]
        -- Store the first year of each date field only
        if current_date_field == "original-date" then
          if not e.original_year then e.original_year = y end
        elseif current_date_field == "issued" or current_date_field == nil then
          if not e.issued_year then e.issued_year = y end
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
      -- Merge sbl data with any existing entry (preserves publisher_place etc.)
      if not sbl_entries[current_id] then
        sbl_entries[current_id] = sbl
      else
        for k, v in pairs(sbl) do
          sbl_entries[current_id][k] = v
        end
      end
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
      -- Try to match publisher_place starting at this Str element.
      -- In notes the place follows an opening paren or bracket, so the
      -- first word may carry a "(" or "[" prefix (e.g. "(Winona",
      -- "[Oxford:", "(Jerusalem:").
      local match_end = nil
      local leading_paren = nil
      local word_idx = 1
      local j = i

      while j <= #inlines and word_idx <= #place_words do
        local el = inlines[j]
        if el.t == "Str" then
          local text = el.text
          local first = text:sub(1, 1)
          if word_idx == 1 and (first == "(" or first == "[") then
            text = text:sub(2)
            leading_paren = first
          end
          local expected_word = place_words[word_idx]
          if word_idx == #place_words then
            -- Last word of place: expect ":" appended (e.g. "York:")
            if text == expected_word .. ":" then
              -- Found complete match including colon
              match_end = j
              word_idx = word_idx + 1
            else
              -- Doesn't match the expected "lastword:" pattern
              break
            end
          else
            if text == expected_word then
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
        -- Successfully matched the publisher_place + colon.
        -- Keep preceding Space so ". Place: Publisher" becomes ". Publisher",
        -- and re-emit the opening paren when the place began "(Place:".
        found = true
        if leading_paren then
          result:insert(pandoc.Str(leading_paren))
        end
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

-- Suppress all post-1900 locations for an entry (current and original
-- publisher places). SBL Press style (SBLHS Blog update, as implemented by
-- biblatex-sbl v2's clearrecentlocations) omits the place of publication
-- for works published 1900 or later, in notes as well as bibliography,
-- including the original-publication segment of reprint chains.
local function suppress_recent_locations(inlines, entry)
  local out = inlines
  if entry.publisher_place and entry.issued_year and entry.issued_year >= 1900 then
    out = suppress_location_in_bib(out, entry.publisher_place)
  end
  if entry.original_publisher_place and entry.original_year and entry.original_year >= 1900 then
    out = suppress_location_in_bib(out, entry.original_publisher_place)
  end
  return out
end

-- ──────────────────────────────────────────────
-- Note manipulation
-- ──────────────────────────────────────────────

-- Build the inline form of a shorthand citation ("BDAG, 35"; "BDF §151").
-- If italic is true, the shorthand is wrapped in Emph.
local function make_shorthand_inlines(shorthand, suffix_inlines, italic)
  local inlines = pandoc.Inlines{}
  if italic then
    inlines:insert(pandoc.Emph{pandoc.Str(shorthand)})
  else
    inlines:insert(pandoc.Str(shorthand))
  end

  -- Add suffix (locator) if present. Page locators take a comma
  -- ("BDAG, 35"); section locators take a bare space ("Zerwick §360",
  -- "BDF §151") per SBLHS shorthand conventions.
  if suffix_inlines and #suffix_inlines > 0 then
    local suffix_text = utils.stringify(suffix_inlines):gsub("^[,%s]+", "")
    if suffix_text ~= "" then
      if not suffix_text:match("^§") then
        inlines:insert(pandoc.Str(","))
      end
      inlines:insert(pandoc.Space())
      inlines:extend(pandoc.Inlines(suffix_text))
    end
  end

  return inlines
end

-- Determine whether a shorthand should be rendered in italic,
-- by checking if the annote value wraps the shorthand in <i> tags.
local function is_shorthand_italic(entry)
  if not entry.annote_value or not entry.shorthand then return false end
  return entry.annote_value:find("<i>" .. entry.shorthand .. "</i>", 1, true) ~= nil
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

      -- Suppress post-1900 publisher locations in notes (SBLHS Blog update).
      -- Applies to every citation in the note; mutates note blocks in place
      -- so later transformations retain the change.
      local location_modified = false
      if #cite.content > 0 and cite.content[1].t == "Note" then
        local note = cite.content[1]
        for _, cit in ipairs(cite.citations) do
          local cit_entry = sbl_entries[cit.id]
          if cit_entry then
            for _, block in ipairs(note.content) do
              if block.t == "Para" then
                local new_content = suppress_recent_locations(block.content, cit_entry)
                if new_content ~= block.content then
                  block.content = new_content
                  location_modified = true
                end
              end
            end
          end
        end
      end

      -- Full-citation annotes (ending in a parenthetical whose last
      -- element is a publication year) take a comma before an appended
      -- locator: "…, 2011), §§360–62" per the SBLHS full-note convention.
      -- Abbreviation-style annotes (BDAG, GKC) and reference glosses
      -- ("(NPNF1 1:252)") keep the bare-space join handled by the CSL.
      if entry and not is_subsequent and entry.annote_value
          and entry.annote_value:match("[%s(]%d%d%d%d%)$") then
        if #cite.content > 0 and cite.content[1].t == "Note" then
          for _, block in ipairs(cite.content[1].content) do
            if block.t == "Para" then
              local last_paren = nil
              for i, el in ipairs(block.content) do
                if el.t == "Str" and el.text:sub(-1) == ")" then
                  last_paren = i
                end
              end
              if last_paren and last_paren < #block.content then
                block.content[last_paren] = pandoc.Str(block.content[last_paren].text .. ",")
                location_modified = true
              end
            end
          end
        end
      end

      if not entry then
        if location_modified then return cite end
        return nil
      end

      -- Handle shorthand references (only for reference works, not ancient texts)
      -- Skip if entry has annote (CSL annote bypass takes precedence for first notes)
      -- Skip if entry has entrysubtype (ancient texts use shorthand differently)
      if entry.shorthand and not entry.entrysubtype and not entry.annote then
        -- Only shorthand the citation group when EVERY member is
        -- shorthand-capable; a mixed group falls through to the CSL
        -- rendering so that no citation is silently dropped.
        local group = {}
        for _, cit in ipairs(cite.citations) do
          local e = sbl_entries[cit.id]
          if e and e.shorthand and not e.entrysubtype and not e.annote then
            table.insert(group, { entry = e, suffix = cit.suffix })
          else
            group = nil
            break
          end
        end

        if group and #cite.content > 0 then
          local combined = pandoc.Inlines{}
          for i, g in ipairs(group) do
            if i > 1 then
              combined:insert(pandoc.Str(";"))
              combined:insert(pandoc.Space())
            end
            combined:extend(make_shorthand_inlines(
              g.entry.shorthand, g.suffix, is_shorthand_italic(g.entry)))
          end

          if cite.content[1].t == "Note" then
            combined:insert(pandoc.Str("."))
            return pandoc.Note(pandoc.Blocks{pandoc.Para(combined)})
          end

          -- Citation inside a manual footnote: citeproc renders it as
          -- inline text (note-form at the start of the note, parenthesised
          -- mid-note) rather than wrapping it in a Note. Replace the
          -- rendered text with the shorthand, preserving the surrounding
          -- shape: parentheses if citeproc parenthesised it, the closing
          -- full stop if the note-form citation carried one.
          local rendered = utils.stringify(cite.content)
          local out = pandoc.Inlines{}
          if rendered:match("^%(") then
            out:insert(pandoc.Str("("))
            out:extend(combined)
            out:insert(pandoc.Str(")"))
          else
            out:extend(combined)
            if rendered:match("%.$") then
              out:insert(pandoc.Str("."))
            end
          end
          return out
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
              -- Attach suffix directly if annote ends with colon (e.g., "COS 1.26:")
              -- Otherwise separate with a space
              if annote_text:match(":%s*$") then
                annote_text = annote_text:gsub("%s*$", "") .. suffix
              else
                annote_text = annote_text .. " " .. suffix
              end
            else
              -- No suffix: strip trailing comma or colon
              annote_text = annote_text:gsub("[,:]%s*$", "")
            end
            -- Also append subsequent_suffix if present (e.g., "(Thackeray, LCL)")
            if entry.subsequent_suffix then
              annote_text = annote_text .. " (" .. entry.subsequent_suffix .. ")"
            end
            annote_text = annote_text .. "."
            -- Parse the annote text (may contain HTML italic)
            local inlines = pandoc.read(annote_text, "html").blocks[1].content
            -- Annote-authored text is also subject to location suppression
            inlines = suppress_recent_locations(inlines, entry)
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

      if location_modified then return cite end
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
                -- Location suppression applies to abbreviation-list entries too
                for _, sub_block in ipairs(block.content) do
                  if sub_block.t == "Para" then
                    sub_block.content = suppress_recent_locations(sub_block.content, entry)
                    changed = true
                  end
                end
              elseif not entry.skipbib then
                -- Replace entire bibliography entry with bibliography_annote if set
                if entry.bibliography_annote then
                  local annote_doc = pandoc.read(entry.bibliography_annote, "html")
                  if annote_doc and #annote_doc.blocks > 0 and annote_doc.blocks[1].content then
                    for _, sub_block in ipairs(block.content) do
                      if sub_block.t == "Para" then
                        -- Annote-authored text is also subject to location suppression
                        sub_block.content = suppress_recent_locations(annote_doc.blocks[1].content, entry)
                        changed = true
                        break
                      end
                    end
                  end
                  -- Shorthand entries keep their label even when the
                  -- bibliography text is annote-authored (e.g. Zerwick)
                  if entry.shorthand and not entry.entrysubtype then
                    prepend_shorthand_to_bib(block, entry.shorthand)
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
                  -- Suppress publisher locations for post-1900 entries (SBLHS Blog update),
                  -- including the original place in reprint chains
                  if (entry.publisher_place and entry.issued_year and entry.issued_year >= 1900)
                      or (entry.original_publisher_place and entry.original_year and entry.original_year >= 1900) then
                    for _, sub_block in ipairs(block.content) do
                      if sub_block.t == "Para" then
                        sub_block.content = suppress_recent_locations(sub_block.content, entry)
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

      -- Repair orphaned em-dash authors (———.) left by citeproc after
      -- skipbib removal.  Citeproc replaces repeated authors with an
      -- em-dash; when the preceding entry is removed the dash becomes
      -- meaningless.  Also repair em-dashes on shorthand entries, which
      -- will appear in the abbreviation list where the em-dash convention
      -- is inappropriate (entries are reordered alphabetically by shorthand).
      -- Walk the remaining entries and restore the real author name
      -- wherever the dash no longer follows a same-author entry, or where
      -- the entry carries a shorthand.
      --
      -- Note: entries with shorthand (no skipbiblist, no entrysubtype)
      -- will be removed from the bibliography by pass 3.  For prev_author
      -- tracking, treat those entries as already removed so that the
      -- *following* entry's em-dash is correctly identified as orphaned.
      do
        local emdash_dot   = "\u{2014}\u{2014}\u{2014}."   -- ———.  (author)
        local emdash_comma = "\u{2014}\u{2014}\u{2014},"   -- ———,  (editor)
        local prev_author = nil
        for _, block in ipairs(div.content) do
          if block.t == "Div" then
            local ref_id = block.identifier:match("^ref%-(.+)$")
            local entry = ref_id and sbl_entries[ref_id]
            -- Determine the expected author name for this entry.
            -- Fall back to editor if no author is available (editor-as-primary
            -- entries like ANET, IDB, etc.).
            local author_name = nil
            if entry then
              if entry.author_literal then
                author_name = entry.author_literal
              elseif entry.author_family then
                author_name = entry.author_family
                if entry.author_given then
                  author_name = author_name .. ", " .. entry.author_given
                end
              elseif entry.editor_family then
                author_name = entry.editor_family
                if entry.editor_given then
                  author_name = author_name .. ", " .. entry.editor_given
                end
              end
            end

            -- Will this entry be removed from bibliography by pass 3?
            local will_be_removed = entry and entry.shorthand
                and not entry.skipbiblist and not entry.entrysubtype

            -- Check whether the entry starts with an em-dash author.
            -- The em-dash may be the very first Str element, or it may
            -- follow a shorthand label (Str + LineBreak) prepended earlier.
            -- Citeproc uses ———. for authors and ———, for editors.
            for _, sub_block in ipairs(block.content) do
              if sub_block.t == "Para" and #sub_block.content > 0 then
                -- Find the first content Str (skip shorthand label if present)
                local target_idx = 1
                local inlines = sub_block.content
                if #inlines >= 3 and inlines[1].t == "Str" and inlines[2].t == "LineBreak" then
                  -- Shorthand label present — check the element after LineBreak
                  target_idx = 3
                end
                if target_idx <= #inlines then
                  local target = inlines[target_idx]
                  local is_author_dash = target.t == "Str" and target.text == emdash_dot
                  local is_editor_dash = target.t == "Str" and target.text == emdash_comma
                  if (is_author_dash or is_editor_dash) and author_name then
                    local is_orphaned = author_name ~= prev_author
                    local has_shorthand = entry and entry.shorthand
                    if is_orphaned or has_shorthand then
                      if is_author_dash then
                        target.text = author_name .. "."
                      else
                        target.text = author_name .. ","
                      end
                      changed = true
                    end
                  end
                end
                break
              end
            end

            -- Track the current entry's author for the next iteration,
            -- but skip entries that will be removed by pass 3.
            if not will_be_removed then
              if author_name then
                prev_author = author_name
              else
                -- No author info from sbl_entries; read from the formatted text
                for _, sub_block in ipairs(block.content) do
                  if sub_block.t == "Para" and #sub_block.content > 0 then
                    local inlines = sub_block.content
                    local idx = 1
                    if #inlines >= 3 and inlines[1].t == "Str" and inlines[2].t == "LineBreak" then
                      idx = 3
                    end
                    if idx <= #inlines then
                      local first = inlines[idx]
                      if first.t == "Str" and (first.text == emdash_dot or first.text == emdash_comma) then
                        -- Still an em-dash (legitimate); author unchanged
                      elseif first.t == "Str" then
                        -- Extract author: text before "." in first Str
                        local a = first.text:match("^(.-)%.$")
                        if a then prev_author = a end
                      end
                    end
                    break
                  end
                end
              end
            end
          end
        end
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
          -- A "short" title equal to the full title is not an abbreviation
          -- (unabbreviated journals round-trip through CSL data that way);
          -- listing it as self-mapping would be noise, so skip it.
          if entry.container_title_short and entry.container_title
              and entry.container_title_short ~= entry.container_title
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
              and entry.collection_title_short ~= entry.collection_title
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

      -- Sub-headings are apparatus, not sections: never numbered (under
      -- --number-sections they would otherwise number 0.1, 0.2, ... below
      -- an unnumbered Abbreviations heading) and kept out of the TOC.
      local sub_attr = pandoc.Attr("", {"unnumbered", "unlisted"})
      local function make_sub_heading(text)
        return pandoc.Header(sub_level, pandoc.Inlines{pandoc.Str(text)}, sub_attr)
      end

      -- Insert blocks after the abbreviation heading
      local insert_pos = abbrev_idx

      if is_typst then
        -- Typst: emit a two-column grid matching biblatex-sbl layout
        for _, section in ipairs(sections) do
          if section.heading then
            insert_pos = insert_pos + 1
            table.insert(doc.blocks, insert_pos, make_sub_heading(section.heading))
          end

          local lines = {}
          -- Override the default template's #show terms.item: rule
          -- to get a two-column layout with aligned definitions
          table.insert(lines, '#show terms.item: it => {')
          table.insert(lines, '  let abbr-width = 2cm')
          table.insert(lines, '  grid(')
          table.insert(lines, '    columns: (abbr-width, 1fr),')
          table.insert(lines, '    column-gutter: 1em,')
          table.insert(lines, '    it.term,')
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
            table.insert(doc.blocks, insert_pos, make_sub_heading(section.heading))
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
  {
    -- Fourth pass: unwrap dangling citation links. link-citations wraps
    -- citations in Links targeting #ref-<id>; entries removed from the
    -- bibliography (skipbib, or moved to the abbreviation list) leave
    -- those targets dangling, which typst rejects as missing labels.
    Pandoc = function(doc)
      local present = {}
      doc:walk({
        Div = function(d)
          if d.identifier and d.identifier ~= "" then
            present[d.identifier] = true
          end
        end,
        Span = function(s)
          if s.identifier and s.identifier ~= "" then
            present[s.identifier] = true
          end
        end,
      })
      return doc:walk({
        Link = function(link)
          local target = link.target:match("^#(ref%-.+)$")
          if target and not present[target] then
            return link.content
          end
        end,
      })
    end,
  },
}
