-- ld-author-index.lua
-- Pandoc Lua filter that generates an author index from citations.
--
-- Three output paths:
--   Word (.docx): injects XE index entry fields alongside citations
--     and an INDEX field at the marker heading. Word builds the index
--     with real page numbers when fields are updated (Ctrl+A, F9).
--   Typst: injects #index[] calls from the in-dexter package alongside
--     citations, and #make-index() at the marker heading. Typst renders
--     the index with real page numbers at compile time.
--   HTML/other: generates a static definition list mapping author names
--     to footnote numbers.
--
-- Usage:
--   pandoc doc.md --citeproc --lua-filter=ld-author-index.lua -o doc.docx
--   pandoc doc.md --citeproc --lua-filter=ld-author-index.lua -o doc.typ
--
-- Place this heading in your document where the index should appear:
--   # Author Index {#author-index}
--
-- For typst output, the document needs: #import "@preview/in-dexter:0.7.2": *
--
-- Runs AFTER citeproc (so citations are already resolved).
-- Compatible with Quarto (use citeproc: false + explicit filter ordering).

local utils = pandoc.utils

-- ──────────────────────────────────────────────
-- Configuration
-- ──────────────────────────────────────────────

local OUTPUT_FORMAT = FORMAT or "html"
local is_docx = OUTPUT_FORMAT == "docx" or OUTPUT_FORMAT == "openxml"
local is_typst = OUTPUT_FORMAT == "typst"

-- ──────────────────────────────────────────────
-- Bibliography data: parse author names from YAML
-- ──────────────────────────────────────────────

local bib_authors = {}  -- id -> list of {family, given, literal}

local function load_bibliography(path)
  local f = io.open(path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()

  local current_id = nil
  local current_authors = {}
  local in_names = false
  local current_name = {}

  for line in content:gmatch("[^\n]*") do
    local id = line:match("^%- id:%s*(.+)%s*$")
    if id then
      if current_id then
        -- Save pending name
        if next(current_name) then
          table.insert(current_authors, current_name)
          current_name = {}
        end
        if #current_authors > 0 then
          bib_authors[current_id] = current_authors
        end
      end
      current_id = id
      current_authors = {}
      in_names = false
      current_name = {}
    end

    -- Detect author or editor block start
    if line:match("^%s+author:$") or line:match("^%s+author:%s*$") then
      in_names = true
      current_name = {}
    elseif line:match("^%s+editor:$") or line:match("^%s+editor:%s*$") then
      -- Also index editors
      in_names = true
      current_name = {}
    elseif in_names then
      -- Check if we've left the names block
      if line:match("^%s+%w") and not line:match("^%s+%-") and
         not line:match("^%s+family:") and not line:match("^%s+given:") and
         not line:match("^%s+literal:") and not line:match("^%s+suffix:") then
        -- Save pending name
        if next(current_name) then
          table.insert(current_authors, current_name)
          current_name = {}
        end
        in_names = false
      end

      -- Parse name fields
      local new_family = line:match("^%s+%- family:%s*(.+)%s*$")
      if new_family then
        if next(current_name) then
          table.insert(current_authors, current_name)
        end
        current_name = {family = new_family}
      end

      local given = line:match("^%s+given:%s*(.+)%s*$")
      if given then
        current_name.given = given
      end

      local literal = line:match("^%s+%- literal:%s*(.+)%s*$")
      if literal then
        if next(current_name) then
          table.insert(current_authors, current_name)
        end
        current_name = {}
        table.insert(current_authors, {literal = literal})
      end
    end
  end

  -- Last entry
  if current_id then
    if next(current_name) then
      table.insert(current_authors, current_name)
    end
    if #current_authors > 0 then
      bib_authors[current_id] = current_authors
    end
  end
end

local function format_index_name(name)
  if name.literal then
    return name.literal
  end
  local family = name.family or ""
  local given = name.given or ""
  if family ~= "" and given ~= "" then
    return family .. ", " .. given
  end
  return family ~= "" and family or given
end

-- ──────────────────────────────────────────────
-- Citation tracking
-- ──────────────────────────────────────────────

local author_locations = {}  -- "Family, Given" -> sorted list of footnote numbers
local footnote_counter = 0

-- ──────────────────────────────────────────────
-- Word (docx) XE field generation
-- ──────────────────────────────────────────────

local function make_xe_field(name)
  local escaped = name:gsub('"', '&quot;')
  return pandoc.RawInline("openxml",
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>' ..
    '<w:r><w:instrText xml:space="preserve"> XE "' .. escaped .. '" </w:instrText></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
  )
end

local function make_index_field()
  return pandoc.RawBlock("openxml",
    '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>' ..
    '<w:r><w:instrText xml:space="preserve"> INDEX \\c "2" \\z "1033" </w:instrText></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>' ..
    '<w:r><w:t>Update this field to generate the index (Ctrl+A, then F9)</w:t></w:r>' ..
    '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
  )
end

-- ──────────────────────────────────────────────
-- Typst index generation (via in-dexter package)
-- ──────────────────────────────────────────────

local function make_typst_index_entry(name)
  -- in-dexter: #index[Entry Name]
  local escaped = name:gsub("[%[%]#]", "\\%1")
  return pandoc.RawInline("typst", '#index[' .. escaped .. ']')
end

local function make_typst_index()
  -- in-dexter: #make-index(title: none) — title already provided by the heading
  return pandoc.RawBlock("typst", '#make-index(title: none)')
end

-- ──────────────────────────────────────────────
-- Filter
-- ──────────────────────────────────────────────

return {
  {
    -- First pass: load bibliography
    Meta = function(meta)
      if meta.bibliography then
        load_bibliography(utils.stringify(meta.bibliography))
      end
      return nil
    end,
  },
  {
    -- Second pass: walk Cite elements at document level
    -- After citeproc, Cite elements wrap Note elements. The Cite
    -- has the citation ID; the Note content is the formatted text.
    Cite = function(cite)
      if #cite.citations == 0 then return nil end

      -- Check if this cite contains a Note (footnote-style citation)
      local has_note = false
      for _, el in ipairs(cite.content) do
        if el.t == "Note" then
          has_note = true
          break
        end
      end
      if has_note then
        footnote_counter = footnote_counter + 1
      end
      local fn_num = footnote_counter

      -- Record authors for each citation in this cite
      local xe_inlines = pandoc.List{}
      local seen = {}

      for _, citation in ipairs(cite.citations) do
        local id = citation.id
        local authors = bib_authors[id]
        if authors then
          for _, name in ipairs(authors) do
            local formatted = format_index_name(name)
            if formatted ~= "" and formatted ~= "others" and not seen[formatted] then
              seen[formatted] = true

              -- Record location
              if not author_locations[formatted] then
                author_locations[formatted] = {}
              end
              local locs = author_locations[formatted]
              if #locs == 0 or locs[#locs] ~= fn_num then
                table.insert(locs, fn_num)
              end

              -- For docx/typst: collect index entry inlines
              if is_docx then
                xe_inlines:insert(make_xe_field(formatted))
              elseif is_typst then
                xe_inlines:insert(make_typst_index_entry(formatted))
              end
            end
          end
        end
      end

      -- For docx/typst: append index entries after the citation
      if (is_docx or is_typst) and #xe_inlines > 0 then
        local new_content = pandoc.List{}
        new_content:extend(cite.content)
        new_content:extend(xe_inlines)
        cite.content = new_content
        return cite
      end

      return nil
    end,
  },
  {
    -- Third pass: generate the index at the marker heading
    Pandoc = function(doc)
      local index_idx = nil
      for i, block in ipairs(doc.blocks) do
        if block.t == "Header" and block.identifier == "author-index" then
          index_idx = i
          break
        end
      end

      if not index_idx then return nil end

      if is_docx then
        -- Word: insert INDEX field (renders with real page numbers)
        table.insert(doc.blocks, index_idx + 1, make_index_field())
      elseif is_typst then
        -- Typst: insert make-index call (in-dexter renders with real page numbers)
        table.insert(doc.blocks, index_idx + 1, make_typst_index())
      else
        -- HTML/other: static definition list with footnote numbers
        local sorted_authors = {}
        for name, _ in pairs(author_locations) do
          table.insert(sorted_authors, name)
        end
        table.sort(sorted_authors)

        if #sorted_authors == 0 then return nil end

        local items = pandoc.List{}
        for _, name in ipairs(sorted_authors) do
          local locs = author_locations[name]
          local loc_strs = {}
          for _, fn in ipairs(locs) do
            table.insert(loc_strs, tostring(fn))
          end
          local term = pandoc.Inlines{pandoc.Str(name)}
          local def = pandoc.Blocks{pandoc.Para(pandoc.Inlines(
            table.concat(loc_strs, ", ")
          ))}
          items:insert({term, {def}})
        end

        table.insert(doc.blocks, index_idx + 1, pandoc.DefinitionList(items))
      end

      return doc
    end,
  },
}
