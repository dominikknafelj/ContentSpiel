# The Table block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A built-in Table block: a small table per language, typed into a grid in CS Studio, drawn on the site without ever breaking the page.

**Architecture:** The table is the block's `body`: a rich-text document per language whose only content is one `table` node (`tableRow`, `tableHeader`, `tableCell`, each cell one paragraph of inline content). Four built-in node types join `RichText::Schema`; a body accepts them only where its block type declares `body_content :table`, and a table body accepts nothing else. Everything a body has (translation pair, state, AI translation through Markdown, published copy, audit digests) is the table's; Markdown learns GFM tables both ways, only where asked. The editor is the existing `admin--rich-text--editor` in a table mode, plus a thin `admin--editor--table` controller for the grid's controls.

**Tech Stack:** Rails 8.1, ViewComponent, Tiptap 3.31.3 with `@tiptap/extension-table` and `prosemirror-tables` (vendored by import map), Stimulus, Tailwind, Minitest, Capybara on Cuprite, Commonmarker.

**Spec:** `docs/superpowers/specs/2026-10-27-table-block-design.md` (decisions 1–15; read it whole). Claude Design's answers: `.superpowers/design-answers/2026-10-13-note-and-table-blocks.md` (B4–B8) and `2026-10-27-table-block.md` (the revisions). The recipe: `docs/reference/content-blocks-and-types.md`, "Adding a block type" (steps 0–11).

## Global Constraints

- Work only in `/Users/dknafelj/src/ContentSpiel-table` on branch `table-block`. Never push. Never skip hooks. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`.
- Every test command is prefixed `PGGSSENCMODE=disable`. Once per new worktree: `PGGSSENCMODE=disable bin/rails db:test:prepare` and `bin/rails tailwindcss:build`. Never build while tests run. System tests: `PARALLEL_WORKERS=6`, only when `sysctl -n vm.loadavg` (one-minute) is under 6. Implementers run their own files, not the whole browser suite.
- Limits (spec decision 7), exact: warning from **6 columns** and from **40 rows**; hard limit **30 columns, 500 rows, 2,000 characters per cell**.
- Exact words: column warning "7 columns. On a phone, visitors scroll sideways to read this table." (the number is the table's: "%{count} columns. …"); row warning "45 rows. A long table is easier to read split into several." ("%{count} rows. …"); hard refusal "A table can have at most 30 columns and 500 rows."; cell refusal "A cell can have at most 2,000 characters." (our wording for the cell, spec decision 7 names only the figure).
- Tokens, themed, each defined from a base token: `--th-table-rule` → `--th-line-strong`, `--th-table-line` → `--th-line`, `--th-table-head` → `--th-ink`, `--th-table-caption` → `--th-meta`, `--th-table-ground` → `--th-paper`. Tinted band: only `--th-table-ground: var(--th-band-tinted)`. Strong band: head and cell text `--th-on-band-strong`, caption `--th-on-band-strong-dim`, rule `--th-on-band-strong` at 40%, row lines at 16%, ground `--th-band-strong`.
- Alignment values: `left`, `center`, `right`; absent means left. Header cells are `tableHeader`; there is no separate "header" setting.
- Icon: Lucide `table`, written `table` in `BlockTypeDefinition::ICONS`.
- Every CS Studio string is a key (`config/locales/admin/…`), scripts read words from `data-messages`; public words from `config/locales/public.en.yml` through `PublicStrings.read`.
- Theme contract: the component's line and the five tokens go into `test/support/contract_ledger.rb` and `docs/reference/theming.md` with a release note; nothing else of the component may be called by a template.
- Tables never reach any other body: post, text block, note, section.

## Review Focus

1. **A paste into a cell** (several paragraphs, a list, an image, a whole table copied from a web page) must land as inline text in that one cell, never as a nested block or a second table; the save must not be refused for it. → Task 5, test "pasting paragraphs, a list and an HTML table into a cell leaves one table with inline text in the cell".
2. **Ragged rows** (a Markdown or AI table, or a hand-made JSON, whose rows have different cell counts) must be refused or padded, never drawn as a broken grid. → Task 1 refuses a table whose rows differ in length; Task 2's loader pads short rows to the header's width before validation (test "a GFM table with a short row loads padded to the header's width").
3. **Pipes, backslashes and line breaks in a cell** must survive the Markdown round trip (AI translation): `a | b`, `C:\path`, a hard break. → Task 2, test "cell text with a pipe, a backslash and a line break comes back unchanged".
4. **A table emptied to nothing** (all rows deleted, or every cell blank) is a blank body: the site draws nothing and the language reads Missing, never a table of empty rows. → Task 1 (a table with no rows is refused; the editor sends an empty document instead, Task 6) and Task 3 (component `render?` false when no cell has text).
5. **A table HTML-pasted into a post's or a text block's editor** is not refused with an error the editor cannot fix: the ordinary editor has no table extension, so ProseMirror drops the table structure on paste and keeps the text. → Task 5, test "pasting an HTML table into a post body keeps its text and no table".

---

## File Structure

- `app/models/rich_text/built_ins.rb` — the four table node types (Task 1).
- `app/models/rich_text/document.rb` — `table?`, `table_shape`, cell-aware `plain_paragraphs` (Tasks 1, 7).
- `app/models/rich_text/html_renderer.rb` — public `render_fragment(nodes)` (Task 1).
- `app/models/rich_text/rich_text_scrubber.rb` (or wherever `RichTextScrubber` lives) — table elements allowed (Task 1).
- `app/models/concerns/has_rich_text_body.rb` — `body_content` hook and the table body rule (Task 1).
- `app/models/content_model/block_type_definition.rb` — `body_content`, `table` in `ICONS` (Tasks 1, 3).
- `app/values/table_body.rb` — `TableBody`: the table of one document as rows of cells, its limits and warnings (Task 1; read by Tasks 3, 6, 7).
- `app/models/rich_text/markdown.rb` — GFM table dump; load with `tables:` (Task 2).
- `app/services/ai/translate.rb` — shape check (Task 2).
- `app/models/block_types/table.rb`, `app/components/blocks/table_component.{rb,html.erb}`, `config/initializers/types.rb`, `config/locales/public.en.yml`, `app/views/admin/shared/_icon.html.erb` — the type (Task 3).
- `app/assets/tailwind/themes/default/table.css`, `tokens.css`, `sections.css` — the look (Task 4).
- `vendor/javascript/…`, `config/importmap.rb`, `app/javascript/rich_text/schema.js`, `app/javascript/rich_text/table.js`, `app/components/admin/columns/rich_text_column_component.{rb,html.erb}` — the grid editor (Task 5).
- `app/javascript/controllers/admin/editor/table_controller.js`, `app/components/admin/editor_screen/table_controls_component.{rb,html.erb}`, `config/locales/admin/editor_screen.en.yml` — the grid's controls and warnings (Task 6).
- `app/components/admin/editor_screen/reference_card_component.rb`, the column component — translation (Task 7).
- `docs/reference/*.md`, `CLAUDE.md`, the spec's "As built", `docs/roadmap.md` — Task 9.

---

### Task 1: Table nodes, the table body rule and `TableBody`

**Files:**
- Modify: `app/models/rich_text/built_ins.rb`, `app/models/rich_text/document.rb`, `app/models/rich_text/html_renderer.rb`, the `RichTextScrubber` file, `app/models/concerns/has_rich_text_body.rb`, `app/models/content_block.rb`, `app/models/content_model/block_type_definition.rb`, `config/locales/en.yml`
- Create: `app/values/table_body.rb`
- Test: `test/models/rich_text/table_nodes_test.rb`, `test/values/table_body_test.rb`, `test/models/content_block_table_body_test.rb`, `test/models/content_model/block_type_definition_test.rb`

**Interfaces:**
- Produces:
  - Node types `table` (group `block`, content `tableRow+`), `tableRow` (content `(tableHeader | tableCell)+`), `tableHeader` and `tableCell` (content `paragraph`, attribute `align` `:string, in: %w[left center right]`). Their `html` blocks write `table`/`tbody`/`tr`/`th scope="col"`/`td` with `class="align-<value>"` when aligned; `markdown_out` is Task 2's.
  - `RichText::Document#table?` → true when the document's only top-level node is a `table`.
  - `TableBody.new(document)` (a value): `#rows` → `Array<Array<TableBody::Cell>>`; `Cell` = `Data.define(:header, :align, :nodes, :text)` (`nodes` the paragraph's inline JSON nodes, `text` plain text); `#column_count`, `#row_count`, `#header_row?` (every cell of the first row is a header), `#header_column?` (the first cell of every row is a header), `#blank?` (no cell has text), `#warnings` → `Array<[Symbol, Integer]>` (`[:columns, n]` from 6, `[:rows, n]` from 40), `#limit_errors` → `Array<Symbol>` (`:size` over 30 columns or 500 rows, `:cell` over 2,000 characters), `#shape` → `[row_count, column_count]`. Constants `WARN_COLUMNS = 6`, `WARN_ROWS = 40`, `MAX_COLUMNS = 30`, `MAX_ROWS = 500`, `MAX_CELL = 2_000`.
  - `RichText::HtmlRenderer#render_fragment(nodes)` → sanitized safe HTML of inline nodes with no wrapper (what a cell draws).
  - `BlockTypeDefinition#body_content(kind = nil)`: `:rich` (default) or `:table`; anything else refused at registration; an outside type may declare only `:rich` (refused in `refuse_outside!`, as `read_only_actions`).
  - A record's body content kind: `HasRichTextBody#body_content_kind` → `:rich`; `ContentBlock` overrides it with `definition&.body_content || :rich`.

- [ ] **Step 1: Write the failing tests**

`test/models/rich_text/table_nodes_test.rb`:
- "a table of header and plain cells with inline marks validates" (a 2×2 doc with bold and a link in a cell: `Document#validate` is empty).
- "a cell holding a list, an image or two paragraphs is refused" (each case: `validate` names the content).
- "an unknown align is refused" (`align: "justify"`).
- "the renderer draws th scope=col for a header row, td otherwise, and the alignment as a class" (assert the HTML).
- "render_fragment draws a cell's inline content with its marks and no paragraph" (`<strong>` present, no `<p>`).

`test/values/table_body_test.rb`:
- "rows, cells, header row and header column are read from the document".
- "warnings start at 6 columns and at 40 rows, and not below" (5 cols → no `:columns`; 6 → `[:columns, 6]`; 39 rows → none; 40 → `[:rows, 40]`).
- "limit errors: 31 columns or 501 rows is :size, a 2,001-character cell is :cell, exactly the limits are fine".
- "a table whose every cell is blank is blank".

`test/models/content_block_table_body_test.rb` (register a test type with `body_content :table` via `TestTypes`, or use the real `table` type once Task 3 lands — use a test type here):
- "a table body holding exactly one table is valid; a table followed by a paragraph is refused; a paragraph alone is refused".
- "an empty body is valid (blank)".
- "rows of different lengths are refused".
- "a text block's, a note's and a post's body with a table in it is refused" (one each).
- "over the hard limit the save is refused with the table's sentence and no language prefix" (`errors[:body]` includes "A table can have at most 30 columns and 500 rows."), and the 2,001-character cell with "A cell can have at most 2,000 characters.".

`block_type_definition_test.rb`: "body_content is :rich unless declared, takes :table, refuses anything else; an outside type may not declare :table".

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/rich_text/table_nodes_test.rb test/values/table_body_test.rb test/models/content_block_table_body_test.rb test/models/content_model/block_type_definition_test.rb`
Expected: FAIL (unknown node type "table", uninitialized constant TableBody, undefined method body_content).

- [ ] **Step 3: Implement**

- Register the four nodes in `RichText::BuiltIns#register_nodes` beside `hardBreak`. `table` gets no `markdown_out` yet (Task 2).
- Allow `table thead tbody tr th td` and the `scope` and `class` attributes in the scrubber.
- `render_fragment` reuses `render_node` over the given nodes and the same scrubber as `render`.
- In `HasRichTextBody#body_errors_for`, after the document's own validation, apply the kind rule: `:rich` → refuse any `table` node anywhere (message: "a table is allowed only in a Table block", with the existing "(code) " prefix: it is a developer's error, not an editor's); `:table` → refuse unless blank or `table?`, refuse ragged rows, and add each `TableBody#limit_errors` as a bare message (no "(code) " prefix) from `config/locales/en.yml` (`errors.messages.table_too_large`, `errors.messages.table_cell_too_long`, with `%{columns}`, `%{rows}`, `%{characters}` filled from `TableBody`'s constants, delimited).
- Comments in the codebase's density: why tables are refused elsewhere (the spec's decision 2), why the limit messages carry no language prefix.

- [ ] **Step 4: Run the tests to see them pass, and the rich-text suite around them**

Run: `PGGSSENCMODE=disable bin/rails test test/models/rich_text test/values/table_body_test.rb test/models/content_block_table_body_test.rb test/models/content_model test/models/concerns test/values/theme/contract_test.rb`
Expected: PASS. If `contract_test.rb`'s "a rendered text is the elements the contract lists" now fails because the renderer can emit table elements: the contract's rich-text selectors are NOT extended (a public `rich_text(record)` never holds a table, decision 2); make that test's sample exclude table nodes with a one-line reason.

- [ ] **Step 5: Commit** — `feat: table nodes in rich text, allowed only in a body that declares them`

---

### Task 2: Markdown tables both ways, and the AI shape check

**Files:**
- Modify: `app/models/rich_text/markdown.rb`, `app/models/rich_text/document.rb`, `app/models/rich_text/built_ins.rb` (`markdown_out`), `app/services/ai/translate.rb`, `config/locales/en.yml` (or the AI locale file the service's messages use)
- Test: `test/models/rich_text/markdown_table_test.rb`, `test/services/ai/translate_test.rb`

**Interfaces:**
- Consumes: Task 1's nodes, `Document#table?`, `TableBody#shape`.
- Produces: `RichText::Markdown.load(markdown, known_references:, tables: false)` and `RichText::Document.from_markdown(markdown, known_references: nil, tables: false)`: with `tables: true` a GFM table becomes a `table` node (header row from the GFM header, column alignment onto every cell of its column, short rows padded with empty cells to the header's width); with `false` it degrades exactly as today. `Dumper` writes a `table` node as GFM: header line, delimiter line with `:---`, `:---:`, `---:` per column (a table without a header row writes its first row as the GFM header and loses nothing on the way back, because the loader turns a GFM header into header cells — accept that and say it in a comment), `|` and `\` in a cell escaped, a hard break as `<br>`.

- [ ] **Step 1: Write the failing tests**

`markdown_table_test.rb`:
- "a table with a header row, alignment, bold and a link dumps to GFM and loads back to the same document with tables: true".
- "cell text with a pipe, a backslash and a line break comes back unchanged".
- "a GFM table with a short row loads padded to the header's width".
- "without tables: true a GFM table still degrades to one paragraph per row, with the warning" (today's behaviour, unchanged).

`translate_test.rb`:
- "a table body goes out as GFM and its suggestion comes back as a table of the source's shape" (stub provider returns the translated GFM).
- "a suggestion whose table has another shape fails the whole call and offers nothing" (provider drops a row: `result.failure?`, no suggestion; message key's text).

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/rich_text/markdown_table_test.rb test/services/ai/translate_test.rb`

- [ ] **Step 3: Implement**

- `Loader#render_block`'s `when :table`: with `@tables` build the node (Commonmarker gives the header row and per-column alignment), else the existing degrade.
- `AI::Translate#suggest` for `format: :markdown`: load with `tables: original[:document].table?`; when the original is a table, compare `TableBody.new(document).shape` with the original's and raise `AI::Error` with a message key ("The translation came back with a different table: try again."; our words) on a mismatch.

- [ ] **Step 4: Run them to see them pass, plus `test/models/rich_text` and `test/services/ai`**

- [ ] **Step 5: Commit** — `feat: GFM tables in Markdown, and AI translation keeps a table's shape`

---

### Task 3: The Table block type and its public component

**Files:**
- Generate: `bin/rails generate block_type table` (writes the definition, the initializer line, the component pair, `table.css`, the two locale scopes, the preview and two tests)
- Modify: `app/models/block_types/table.rb`, `app/components/blocks/table_component.{rb,html.erb}`, `app/models/content_model/block_type_definition.rb` (`ICONS` gets `table`), `app/views/admin/shared/_icon.html.erb` (a `when :table` branch: Lucide `table`'s paths), `config/locales/public.en.yml` (`public.blocks.table.label: "Table"`), `config/locales/admin/editor_screen.en.yml` (`tile_summary.types.table`: `word: "Table"`, `empty: "Empty table"`), `test/support/contract_ledger.rb`, `test/support/block_samples.rb` (only if the sample's body needs it; see Step 3)
- Test: `test/models/block_types/table_test.rb`, `test/components/blocks/table_component_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/components/admin/editor_screen/block_icon_component_test.rb`

**Interfaces:**
- Consumes: `body_content`, `TableBody`, `render_fragment` (Task 1).
- Produces:
  - Registration (exact):
    ```ruby
    t.label "Table"
    t.icon "table"
    t.uses :body, :caption
    t.body_content :table
    t.component Blocks::TableComponent
    t.theme_methods :block, :page, :rows, :header_row?, :header_column?, :column_count, :caption
    t.tokens themed: %w[table-rule table-line table-head table-caption table-ground]
    t.stylesheet "table.css"
    t.summary ->(block, locale:) { Table.summary(block, locale: locale) }
    ```
  - `BlockTypes::Table.summary(block, locale:)` → `[[:text, "Table · #{columns} × #{rows} · "], [:text, caption_or_first_header_words] or [:hint, :empty]]` (columns × rows of the language shown; truncated to `SUMMARY_LENGTH`).
  - `Blocks::TableComponent.new(block:, page:)`: `rows` (each cell answers `header?`, `align`, `html`), `header_row?`, `header_column?`, `column_count`, `caption` (the visitor's language, else default), `render?` false when `TableBody#blank?` in the language shown and the default. `label` for the scroll box is written in the template from `PublicStrings.read("public.blocks.table.label")`, not a method (the contract's rule: a method only the default template needs stays in the template).
  - Default template: `div.table-scroll[tabindex=0][role=region]` labelled by the caption's id (`aria-labelledby`) or `aria-label` = the label word; `table` → `caption` (when present) → `thead` with `th scope="col"` for a header row → `tbody` with `th scope="row"` for a header column's cells and `td` otherwise; each cell `class="align-#{align}"` when aligned.
  - Ledger: `"blocks/table_component" => %w[block page rows header_row? header_column? column_count caption]` after the note's line; the five tokens after the note's sixteen.

- [ ] **Step 1: Generate, then write the failing tests**

`table_test.rb`: "the table type declares its body as a table, its caption, its icon and its theme methods"; "summary reads columns × rows and the first header words, the caption in their place, and Empty table for a blank body" (3 cases).
`table_component_test.rb`: "a header row draws thead and th scope=col"; "a header column draws th scope=row"; "both, and neither"; "each alignment is a class on its cells"; "a caption names the scroll box; without one the box is named Table"; "text that looks like markup is text" (`<script>` in a cell); "a long unbroken word is in the cell" (the CSS of Task 4 breaks it; here only that it is drawn); "an empty table draws nothing"; "a language without a table draws the default language's".
`tile_summary_component_test.rb`: "a table's tile reads Table · 3 × 3 · and its first header words".
`block_icon_component_test.rb`: already draws every `ICONS` entry: it goes red until the `_icon` branch exists.

- [ ] **Step 2: Run them to see them fail**

- [ ] **Step 3: Implement**

The sample: `t.sample translations: { "en" => { caption: "Plans compared" }, "de" => { caption: "Tarife im Vergleich" }, "es" => { caption: "Planes comparados" } }, body: <GFM table string>, shows: [ "Plans compared", "Monthly price", "Unlimited" ]` with a 3×3 GFM body: header `| Plan | Monthly price | Storage |` with the second column right-aligned, rows `| **Basic** | 5 € | 10 GB |` and `| Pro | 12 € | [Unlimited](https://example.com) |`. `BlockSamples#sample_block` turns `sample.body` into a document with `rich_doc`: make that call pass `tables: true` when the type's `body_content` is `:table` (one line in `test/support/block_samples.rb`), so the shared tests build a real table.

- [ ] **Step 4: Run them to see them pass, then the shared guards**

Run: `PGGSSENCMODE=disable bin/rails test test/models/block_types test/components/blocks test/components/admin/editor_screen test/integration/block_samples_test.rb test/integration/public_canary_test.rb test/values/theme test/lib/theming_reference_test.rb test/models/built_in_types_test.rb test/lib/generators`
Expected: PASS except `theming_reference_test.rb` and the token guards in `contract_test.rb`, which Task 4 makes green (the tokens are declared and not yet defined). Write that in the report; do not define tokens here.

- [ ] **Step 5: Commit** — `feat: the Table block type and its public component`

---

### Task 4: The table's look, its tokens and bands, and the theme contract's pages

**Files:**
- Modify: `app/assets/tailwind/themes/default/table.css`, `tokens.css` (light and dark, after the note's), `sections.css` (tinted: one line; strong: five values after the note's), `docs/reference/theming.md` (components table row, tokens rows, a section "The Table block" with the release note), `test/fixtures/themes/` (a fixture theme that replaces `blocks/table_component.html.erb` from the reference alone), `test/integration/theme_pages_test.rb`
- Test: `test/integration/design_tokens_test.rb`, `test/integration/theme_pages_test.rb`

**Interfaces:**
- Consumes: Task 3's component markup and classes (`table-scroll`, `align-*`).

- [ ] **Step 1: Write the failing tests** (`design_tokens_test.rb`, beside the note's):
- "the five table tokens are defined from the theme's base tokens in both schemes, never a literal".
- "the table's stylesheet is declared by the type and holds no colour of its own".
- "a table's header text, cell text and caption are readable on its ground, on the page, in a tinted band and in a strong band, in both themes" (3 tokens × 3 grounds × 2 schemes = 18 pairs at 4.5:1; cell text is `--th-ink`, or `--th-on-band-strong` in a strong band).
- "a tinted band changes only the table's ground; a strong band re-values all five".
`theme_pages_test.rb`: "a theme replaces the Table block's template from the contract's names alone, and a theme that does not is drawn the default one".

- [ ] **Step 2: Run them to see them fail**

- [ ] **Step 3: Implement** `table.css` (tokens only): the scroll box `overflow-x: auto` inside the column (the page never scrolls sideways), `border-collapse: collapse`, header rule 1px `--th-table-rule`, row lines 1px `--th-table-line`, no stripes, cell padding 10px × 12px, top-aligned, line height 1.5, text one step under the body size (an existing size token: `--th-t-small` if that is the step; no new token), `overflow-wrap: anywhere`, header weight 600 in `--th-table-head`, `caption-side: bottom` small sans in `--th-table-caption`, the header column `position: sticky; left: 0` on `--th-table-ground`, and the 24px edge fade from `--th-table-ground` to transparent on the side that has more, without a script (scroll-driven animation or the `background-attachment: local/scroll` shadow technique, decided by the implementer; if neither holds in the test browser, say so in the report and stop — the controller rules on a script fallback).

- [ ] **Step 4: Run them to see them pass**, plus `test/values/theme test/lib/theming_reference_test.rb test/values/theme/contract_test.rb`

- [ ] **Step 5: Commit** — `feat: the table's look, its five tokens on the page and in the bands`

---

### Task 5: The grid editor (table mode of the rich-text editor)

**Files:**
- Vendor: `bin/importmap pin @tiptap/extension-table@3.31.3 @tiptap/pm@3.31.3/tables prosemirror-tables` (whatever subpaths jspm writes), then re-add `preload: "admin"` to each new pin (CLAUDE.md's pitfall)
- Create: `app/javascript/rich_text/table.js`
- Modify: `app/javascript/rich_text/schema.js` (`extensions({ …, content })`), `app/javascript/controllers/admin/rich_text/editor_controller.js` (a `content` value: `"rich"` default, `"table"`), `app/components/admin/columns/rich_text_column_component.{rb,html.erb}` (table mode: `content: :table` from the block's definition; the toolbar limited to bold, italic, code, link; no insert menu)
- Test: `test/components/admin/columns/rich_text_column_component_test.rb`, `test/integration/public_javascript_test.rb` (no new pin preloads on the public site), `test/system/admin/table_block_test.rb` (new)

**Interfaces:**
- Produces: `extensions({ resolveAssetUrl, resolveLinkTitle, onEditImage, content = "rich" })`: for `"table"` a `Document` whose content is `table`, `Paragraph`, `Text`, `HardBreak`, `Bold`, `Italic`, `Code`, `SchemaLink`, `InternalLink`, and `Table`, `TableRow`, `TableHeader`, `TableCell` configured to the server's schema (cells hold one paragraph; an `align` attribute on header and cell, rendered as the `align-*` class); `resizable: false`. `table.js` holds the table nodes' configuration and the keys of Claude Design's B5: Tab / Shift+Tab next and previous cell, Tab in the last cell adds a row, Enter to the cell below (adds no paragraph), Shift+Enter a hard break, arrows leave a cell only at its text's start or end (prosemirror-tables' default), Esc blurs the editor. A paste into a cell keeps inline text only (`transformPasted` flattens block content to text joined by hard breaks).
- In the editor a cell is at least 160px wide, so four fit the 640px editor column; from five the grid scrolls sideways in its own box with the same 24px edge fade as the site (spec decision 12), and the cells show their column's alignment (the `align-*` class, styled in CS Studio's stylesheet with tokens only).
- The editor emits the same `input` JSON as for a body; an editor emptied of every row sends an empty document (`{ type: "doc", content: [] }`).

- [ ] **Step 1: Write the failing tests**
Component: "a table block's body is drawn in table mode with the limited toolbar and no insert menu; a text block's is not".
System (`table_block_test.rb`), each with `await_admin_controllers`:
- "typing in the grid, Tab to the next cell and in the last cell adds a row, Enter goes down, Shift+Enter breaks the line; autosave and reload keep it all".
- "bold and a link from the toolbar land in the focused cell".
- "a five-column grid scrolls sideways inside the card while the editor column keeps its width".
- "pasting paragraphs, a list and an HTML table into a cell leaves one table with inline text in the cell".
- "pasting an HTML table into a post body keeps its text and no table".

- [ ] **Step 2: Run them to see them fail**

- [ ] **Step 3: Implement** (vendor first; check `bin/importmap audit` stays clean)

- [ ] **Step 4: Run them to see them pass**, plus `test/integration/public_javascript_test.rb test/system/admin/rich_text_editor_test.rb` (or the existing editor system file) to show the ordinary editor unchanged

- [ ] **Step 5: Commit** — `feat: the Table block's grid, a table mode of the rich-text editor`

---

### Task 6: The grid's controls, the header toggles and the warnings

**Files:**
- Create: `app/javascript/controllers/admin/editor/table_controller.js` (`admin--editor--table`), `app/components/admin/editor_screen/table_controls_component.{rb,html.erb}`
- Modify: `app/components/admin/editor_screen/block_card_component.html.erb` (draw the controls for a `body_content :table` type), `config/locales/admin/editor_screen.en.yml`, `app/models/block_types/table.rb` (`read_only_actions` only if a reading action survives in a held form), `test/components/admin/editor_screen/held_fields_test.rb` (`ALLOWED`, only with that), `docs/reference/live-editing.md` (the count, only with that)
- Test: `test/components/admin/editor_screen/table_controls_component_test.rb`, `test/system/admin/table_block_test.rb`

**Interfaces:**
- Consumes: the Tiptap editor of Task 5, reached as the `admin--rich-text--editor` controller's `editor` (an event or a small shared module, never an outlet: the roadmap's scripts rule), `TableBody#warnings` (server side).
- Produces:
  - The options row: "Header row" (on by default for a new table) and "First column as header", switches that turn that row's or column's cells into headers and back.
  - Per row and per column, on hover or focus, a "⋯" menu (the existing `Admin::Ui` menu): Insert above / Insert below / Move up / Move down / Delete row; Insert left / Insert right / Move left / Move right / Align: Left, Centre, Right (the current one checked) / Delete column. Deleting a row or column that has text asks first in the existing confirm dialog.
  - A "+" at the end of each row and under each column (hover or focus) and a permanent "Add row" button under the grid.
  - The warning line between the card's header and the grid: the existing warn alert at its small size, the column sentence, the row sentence, or both in one alert; drawn by the server from `TableBody#warnings` and recomputed by the script as rows and columns change.
  - A new table (no body yet) starts as a 3 × 3 grid with a header row (our call; the editor's grid needs cells to type into).
  - Every string a key; the script's words from `data-messages`.

- [ ] **Step 1: Write the failing tests**
Component: "the warning is drawn from 6 columns and from 40 rows, both in one alert, and not below"; "the controls are not drawn in a held form" (through `HeldFields`).
System:
- "a column's menu inserts, moves, aligns and deletes; deleting a column with text asks first; the cells show the alignment".
- "Header row and First column as header turn cells into headers and back, and the site draws th".
- "adding a sixth column shows the warning at once, removing it takes it away".
- "a second person sees the grid read-only: no controls, no toolbar, nothing typed".
- "over the hard limit the save is refused with the table's sentence and the grid keeps its text" (a 31st column through the controls, or a stubbed body over the limit).

- [ ] **Step 2–4:** fail, implement, pass (run the file and `test/components/admin/editor_screen/held_fields_test.rb`)

- [ ] **Step 5: Commit** — `feat: the table grid's rows, columns, alignment, header toggles and warnings`

---

### Task 7: The translation tab

**Files:**
- Modify: `app/models/rich_text/document.rb` (`plain_paragraphs` descends into a table: one entry per cell, row by row), `app/components/admin/columns/rich_text_column_component.rb` (table mode on a translation tab: the source's table as the editor's starting content when this language has none, while the hidden input stays empty until the first change), `app/javascript/controllers/admin/rich_text/editor_controller.js` (a `startingContent` value used for the editor's content when the input is empty; `onUpdate` writes the input only after a real change)
- Test: `test/models/rich_text/document_test.rb`, `test/components/admin/columns/rich_text_column_component_test.rb`, `test/system/admin/table_block_test.rb`, `test/services/translation_state_parity_test.rb` (the shared sample already covers the table)

**Interfaces:**
- Consumes: Task 5's editor, Task 2's AI shape check.

- [ ] **Step 1: Write the failing tests**
- `document_test.rb`: "a table's plain paragraphs are its cells' texts, row by row".
- Component: "on a translation tab a language with no table starts from the source's table, with the field empty, Translate offered and the mark Missing".
- System:
  - "the copied grid saves nothing until a cell is changed; then the language is Translated and the site shows it".
  - "a changed source cell makes the table Outdated, the reference card names the cell's words, and Still correct clears it".
  - "Suggest update offers a table of the source's shape and Use puts it in the grid" (stub provider).
  - "the translation tab's own grid has all the controls" (rows can differ from the source's).

- [ ] **Step 2–4:** fail, implement, pass (plus `test/models/concerns test/services/translation_state_parity_test.rb test/components/admin/editor_screen/reference_card_component_test.rb`)

- [ ] **Step 5: Commit** — `feat: a table per language on the translation tab`

---

### Task 8: The site in the browser

**Files:**
- Test: `test/system/table_block_test.rb` (public)

- [ ] **Step 1: Write the tests**
- "a wide table at a phone's width scrolls inside its box while the page does not" (resize to 375px in an `ensure`-restored block; `document.documentElement.scrollWidth <= innerWidth`; the box's `scrollWidth > clientWidth`; the header column's left edge stays put after scrolling the box).
- "the fade shows on the side that has more, and on neither when everything fits".
- "in both schemes the header, cells and caption are drawn in the table's tokens" (computed colours equal the resolved tokens, page and strong band).
- "a long word breaks inside its cell".

- [ ] **Step 2:** run; fix in `table.css` only; commit — `test: the table on the site, at a phone's width and in both schemes`

---

### Task 9: Documents

**Files:**
- Modify: `docs/reference/content-blocks-and-types.md` (a "The Table block" section after the Note's; the recipe's list entry; `body_content` in "Adding a block type"), `docs/reference/rich-text.md` (the table nodes, the body content rule, Markdown tables with `tables:`), `docs/reference/translations.md` (a table per language, the starting copy, the AI shape check), `CLAUDE.md` (one rule in "Rules a change can break silently" naming the guards of decision 2 and the limits, and the reference index line for the table's files), the spec's "As built", `docs/roadmap.md` (the Table block shipped; the docs site's "Tables … (open)" line answered)
- Test: `PGGSSENCMODE=disable bin/rails test test/lib` (the guards read `CLAUDE.md` and `docs/reference`)

- [ ] Write, run `test/lib`, commit — `docs: the Table block`

The whole-branch check (rubocop, brakeman, bundler-audit, importmap audit, zeitwerk, the unit suite, the browser suite, `bin/theme-build-check`) is the controller's, after the final review.
