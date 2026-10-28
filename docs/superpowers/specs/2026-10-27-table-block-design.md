# The Table block

Status: draft (2026-10-27). The look and the editor are Claude Design's: B4 to B8 of 2026-10-13 (`.superpowers/design-answers/2026-10-13-note-and-table-blocks.md`) as revised on 2026-10-27 (`.superpowers/design-answers/2026-10-27-table-block.md`). The owner's decisions are from the brainstorm of 2026-10-27. Calls marked "(our call)" are this spec's, not the owner's.

## Why

The Code and Note blocks shipped; Table is the last of the fast follow (roadmap item 9, 2026-10-12). A site has no way to show a small table today: an editor fakes one with a list, and the guide's loader flattens a Markdown table into one paragraph per row (`RichText::Markdown`, "degraded a table to one paragraph per row").

## Who it is for, and what it is not

**For** small tables an editor types by hand on a marketing page or in a post: a plan or product comparison, a feature list, key facts, a short schedule (owner: "smaller tables for marketing etc"). General purpose, because the CMS is.

**Not** a spreadsheet: no formulas, no sorting, no filtering, no merged cells, no cell colours, no import from a spreadsheet or a file, no lists, images or paragraphs inside a cell (owner: "nothing complexer" than a Markdown table cell, edited the Confluence way).

**Anti-goal (the owner's one worry):** a table that breaks the page. Whatever an editor puts in, the page's text column keeps its width and the page itself never scrolls sideways.

## What a person gets

**A visitor** reads a table in the flow of the page: a header row in the body font at weight 600 over a stronger rule, thin lines between rows, no stripes, cells in the column's alignment, and an optional caption under it. A table wider than the column scrolls sideways inside its own box, with a fade on the edge that has more; a header column stays in view while it scrolls. On a tinted band and on a strong band the table follows the band, as a Note does.

**An editor** adds a "Table" block from the picker and types into a grid in the card. A "+" at the end of each row and under each column (on hover or focus, at the grid's edges) adds one, and an "Add row" button under the grid stays for touch. A "⋯" menu per row and per column inserts above or below, moves, aligns (columns: Left, Centre, Right) and deletes; deleting one that has text asks first. Cells take bold, italic, code and links from the inline toolbar, and a line break. "Header row" (on by default) and "First column as header" are toggles in the card's options row. A large table is warned about and still saved.

**A translator** (any editor on a language's tab) sees the default language's table read-only beside this language's own table, which they edit with all the controls: each language's table is its own (owner: "I leave that to the author").

## Decisions

1. **A table is per language, and it is the block's `body`** (our call on the storage; the owner's on per language). The body is already one rich-text document per language (`HasRichTextBody`); the table block's body holds exactly one `table` node and nothing else. So the existing machinery is the table's: the translation pair, the translation state (Missing, Outdated, Translated), AI translation and the Markdown converter (both through Markdown, where a GFM table is a table), the published copy, the audit log's digests, the public render cache. The alternative, a new translated `:table` field type in `settings`, would need each of those taught a new kind of value.
2. **Table nodes are built-in rich-text node types** (`table`, `tableRow`, `tableHeader`, `tableCell`), registered in `RichText::Schema` like every built-in, BUT allowed only in the body of a block type that says so. Every other body (a post's, a text block's, a note's, a section's) refuses a table node on save, by the validation every body already goes through, and the Markdown import keeps degrading a table to paragraphs there as it does today. The table block's body is refused unless it is exactly one table. How a type says so is the builder's (a declaration on the definition is the expected shape, e.g. `t.uses :body, content: :table`), and it is one more thing `BlockTypeDefinition` refuses for an outside type in step 1, as `read_only_actions` is.
3. **A cell holds inline content only:** text with the marks bold, italic, code and link (the link mark as the rich text has it, internal links included) and a hard break. No paragraphs beyond the one a cell needs, no lists, no images, no headings. Refused on save like any off-schema content.
4. **The header row and the header column are the cells' kind:** a first row of `tableHeader` cells is a header row, a first column of them a header column; there is no separate setting. Toggling "Header row" turns that row's cells into headers or back. Each language's table has its own, as everything of it is (a new language copies it).
5. **Alignment is per column, stored on each cell** (an `align` attribute: `left`, `center`, `right`; absent is left). The column's menu sets it for every cell of the column, the header's included; a cell never has an alignment its column does not have (the editor only writes whole columns; the server does not reject a mixed column, it draws what is stored). Markdown's column alignment maps to it both ways.
6. **The caption is the block's translated `caption`** (`uses :caption`), a plain translated field as the Code block's is (no library image behind it, no override, no Reset). On the site it is a real `caption` element at `caption-side: bottom`, small sans in `--th-table-caption`, under the table as the Code and Image blocks' captions are (Claude Design, 2026-10-27, replacing "above"). It names the table and labels the scroll box.
7. **Warn, don't refuse** (owner: "at least warn"). Claude Design's numbers:
   - **a warning from 6 columns:** "7 columns. On a phone, visitors scroll sideways to read this table." (the number is the table's);
   - **a warning from 40 rows:** "45 rows. A long table is easier to read split into several.";
   - both: the two sentences in one alert. One line between the card's header and the grid, the existing warn alert at its small size. The block still saves. The warnings are computed in the browser as the editor types and drawn by the server on render (the same rule, one place each side; our call).
   - **The hard limit, there to protect the server:** 30 columns, 500 rows, 2,000 characters per cell. Over it the save is refused with the form's error, "A table can have at most 30 columns and 500 rows." (and, for a cell, a message naming the 2,000 characters), the text left in the grid, nothing written or audited: as a Code block over its limit.
8. **A new language starts as a copy** of the default language's table: when this language has no table, the server draws the translation tab's grid with the source's table (shape, alignment, header kinds, words) as the editor's starting content, while the form's body field stays EMPTY. The field is written only by the translator's first change, so autosave sends nothing, live refresh sees a clean form and replaces it, and the existing empty-field rules still hold (the field is empty: AI **Translate** is offered, the field's mark is ○ Missing). Until a change is saved the site shows the default language's table (the existing fallback). The caption is not copied: it is a plain translated field and behaves as every one does. (Our call: a copy saved untouched would read as "Translated" with English words in it, and a copy written into the field by a script would count as an edit.)
9. **The translation state and the translation pair are the body's, unchanged** (our call, in place of Claude Design's new Outdated line: the CMS already has one flow for a translated body and the table takes it). The field's mark says ○ Missing, ↻ Outdated or ● Translated once for the whole table; no per-cell marks (shapes can differ). When Outdated, the existing reference card shows what changed in the source (its word diff reads the table's text, cell by cell in reading order, as the source's plain paragraphs), "Still correct — mark up to date" clears it without editing, and AI is offered as **Suggest update** (as **Translate** when the field is empty): a suggestion the translator takes with **Use**, after which autosave writes it, as for a body. AI never saves by itself. A page's own status counts a table as it counts any block's body today (`Translations::Status#block_missing_count` counts a block's required settings only): an untranslated table does not make the page read Missing in the matrix or the switcher, exactly as an untranslated text block does not. Changing that is a rule for every block type and is not this spec's.
10. **AI translation translates the cells and keeps the shape:** the table goes out as a GFM table in Markdown and comes back through `RichText::Document.from_markdown`, as a body does today; a suggestion whose table has another shape than the source's table as it is now is refused as a failed translation, never offered (our call). "Suggest update" translates the source's table as it is now: the suggestion has the source's shape, and **Use** replaces this language's table with it, whatever shape this language had (the translator sees the suggestion before taking it). The provider's limits (`AI::Translate::MAX_FIELDS`, `MAX_CHARACTERS`, the 25 s timeout and the proxy's 75 s, CLAUDE.md's pitfall) stay as they are: a table near the hard limit is over `MAX_CHARACTERS` and is not offered, which is said as it is for a long body.
11. **The grid is a Tiptap editor with the table extension** (`@tiptap/extension-table` and its `prosemirror-tables`, vendored by import map with `preload: "admin"`, CLAUDE.md's pitfall), configured to the block's schema: a table and inline marks only. Its keys are Claude Design's B5: Tab and Shift+Tab to the next and previous cell, Tab in the last cell adds a row; Enter to the cell below; Shift+Enter a line break; the arrow keys leave a cell only at the start or end of its text; Esc leaves the grid. The "+" controls, the menus and the toggles are the CMS's own markup around it, in `admin--editor--table` (a new controller, our name), every string a key.
12. **In the editor, a cell is at least 160px wide**, so four fit the 640px editor column; from five the grid scrolls sideways in its own box with the same edge fade. The grid's cells show the column's alignment; no alignment icon.
13. **A held table is read-only as every held form is** (`HeldFields`): the grid is not editable, the "+" controls, menus and toggles are not drawn, and the toolbar is gone. Any `data-action` the grid's markup carries for reading (scrolling, "Show source") is the type's declared `read_only_actions`, each a method of the controller file (the held-fields test's rule).
14. **The tile and the collapsed card:** the type's icon, Lucide `table` (`t.icon "table"`, `table` added to `BlockTypeDefinition::ICONS`; the tile draws a type's icon before its summary already), then "Table · 4 × 12 · first header words…" (columns × rows, of the language shown); with a caption, the caption in place of the header words. The summary answers text parts only. The picker shows the same icon.
15. **An empty table draws nothing** on the site (no cell with text in the visitor's language and none in the default one), as an empty Note draws nothing.

## The public side

- `Blocks::TableComponent` with `initialize(block:, page:)`. Its template is promised these names and no other (the contract's line, the ledger, a release note): `block`, `page`, `rows` (each row a list of cells; a cell answers `header?`, `align` and `html`, its inline content rendered through the rich-text renderer and safe), `header_row?`, `header_column?`, `column_count`, `caption`. Exact names are the builder's within this list's meaning, written once into the ledger; nothing else of the component may be called by a template (the contract's method guard).
- The default template: a `figure`-free `div.table-scroll` (the scroll box: `overflow-x: auto`, `tabindex="0"`, `role="region"`, labelled by the caption's id, or by the public word "Table" when there is no caption, a key `public.blocks.table.label` read with `PublicStrings.read`), holding `table` with `caption`, `thead` when there is a header row, `th scope="col"` for header-row cells, `th scope="row"` for a header column's cells, `td` for the rest, each with its column's alignment as a class.
- **Cells and text:** padding 10px by 12px; text one step under the body size (`--th-t-small`'s neighbour as the theme defines it: the builder picks the existing size token, no new one); line height 1.5; top-aligned; a long word or address breaks (`overflow-wrap: anywhere`) instead of widening the table; cells wrap.
- **The scroll fade:** on the edge that has more, from `--th-table-ground` to transparent, 24px wide, drawn by CSS (scroll-driven or a background-attachment technique; our call that it needs no script). The header column is `position: sticky` on `--th-table-ground`.
- **Tokens (Claude Design, 2026-10-27), five, themed (light and dark), each defined from a base token as the Note's are:** `--th-table-rule` → `--th-line-strong` (the header rule, 1px), `--th-table-line` → `--th-line` (row lines, 1px), `--th-table-head` → `--th-ink` (header text, weight 600), `--th-table-caption` → `--th-meta`, `--th-table-ground` → `--th-paper` (the fade and the sticky column). Cell text is `--th-ink`. Links and inline code are the rich text's.
- **In a tinted band** only `--th-table-ground` changes, to `--th-band-tinted`. **In a strong band** the table is re-valued in `sections.css` as a Note is: head and cell text `--th-on-band-strong`, caption `--th-on-band-strong-dim`, rule `--th-on-band-strong` at 40%, row lines at 16%, ground `--th-band-strong`.
- **Contrast** (the tokens test): header text, cell text and caption at 4.5:1 against the table's ground on the page, in a tinted band and in a strong band, in both schemes. The rule and the row lines are decoration and are not held to 3:1 (Claude Design dropped its earlier 3:1 rule: the header's weight marks the header, the row lines only guide the eye).
- `app/assets/tailwind/themes/default/table.css` (the type's `stylesheet`), tokens only.

## CS Studio

- **The card:** the options row ("Header row", "First column as header"), the warning line when there is one, the grid with its controls and toolbar, then "Caption". On the translation tab: the source table read-only beside this language's editable table (two columns of up to 560px with a 24px gap, stacked with the source on top when there is no room: the layout the translation pair already has), the state in the card's header, the Outdated line.
- The grid's form field submits the table as the body's JSON as the rich-text field does today; the autosave, the write queue, the stale check, live refresh and holds are the body's, unchanged.
- **Strings are keys** (`config/locales/admin/…`, the component's file), and the script's words come from the server's `data-messages`.

## The data

No column and no migration: `body` and `caption` are `content_blocks` columns already. The type is registered as the Note was:

```ruby
BlockTypes.register :table do |t|
  t.label "Table"
  t.uses :body, :caption              # the body holds exactly one table (decision 2)
  t.component Blocks::TableComponent
  t.theme_methods :block, :page, :rows, :header_row?, :header_column?, :column_count, :caption
  t.tokens themed: %w[table-rule table-line table-head table-caption table-ground]
  t.stylesheet "table.css"
  t.icon "table"
  t.summary ->(block, locale:) { Table.summary(block, locale: locale) }
  t.read_only_actions ...             # what the held grid still needs, if anything (decision 13)
  t.sample translations: { "en" => { body: <a 3 × 3 table with a header row, one bold word, one link, one right-aligned column>, caption: "…" }, "de" => { … }, "es" => { … } }, shows: [ … ]
end
```

The sample's words are what the canary, the scaffold and the shared tests compare: choose them as a hand-written row would be (CLAUDE.md, "Every block type's sample…").

## What this does not do

- Merged cells, cell colours, sorting, formulas, import from a spreadsheet, lists or images in a cell.
- A table inside any other body (a post, a text block, a note).
- A column width the editor sets.
- A "sticky header row" on long tables (the header column is sticky; a long table's header row scrolls away).
- Numbers right-aligned by default: alignment is the editor's.
- An outside type's own table-like body: the declaration that lets a body hold a table is the CMS's own in step 1.

## Risks

- **The first body that is not free rich text.** The rule that keeps table nodes out of every other body, and the table block's body down to one table, is new; a body that slips through (a Markdown import, an MCP write, an AI translation) would put a table where its renderer and its theme do not expect one. Every write path of a body is in its test.
- **A new editor extension and its dependency** (`prosemirror-tables`), vendored and pinned: an upgrade of Tiptap re-pins it too.
- **Five more tokens and a component's line** are promises to themes from the day they ship.
- **AI translation of a table** depends on the provider returning the same shape; a refused answer is a failed translation the translator sees, never a half-saved table.
- **The fade without a script** depends on CSS the default theme's browsers support; if it does not hold, a few lines of script in the site's entry point are the fallback, and a theme's controller is never needed for it.

## Testing

By the recipe ("Adding a block type", steps 0 to 11); the shared tests build the table from its `sample`, also in a section's column. This block's own:

- the schema rule: a table node refused in every other body, on every write path (the services, the Markdown import, a post through MCP, AI translation); the table body refused with anything but one table, with a cell holding a list or an image, over each hard limit;
- the component: header row, header column, both, neither; each alignment; a caption and none (the scroll box's name); text that looks like markup; a long unbroken word; an empty table; the default language's table where this one has none;
- the public page at the top level and in a section's column, from the published copy; the canary; the contrast pairs (header, cells, caption on three grounds in two schemes);
- Markdown both ways (`RichText::Markdown`): a GFM table with alignment in and out unchanged for the table block's body; a post's body sent through MCP (posts are MCP's only content) still flattens a table into paragraphs, as today. MCP gets no block tools in this spec;
- the translation state: Missing until a translator's change is saved (the copied grid leaves the field empty: no autosave, a clean form for live refresh), Translated after, Outdated after the default language's table is saved again, cleared by "Still correct"; the reference card's diff of a changed cell;
- AI translation: Translate and Suggest update give a suggestion with the source's shape and translated cells, taken with Use; a response of another shape refused and nothing offered;
- the card: the warnings at 6 columns and at 40 rows and not below; the hard limit's refusal with the grid's text kept; the held read-only grid against the server's rendering;
- browser tests: build a table by keyboard (Tab adds a row, Enter, Shift+Enter, the "+" controls, a column's menu: insert, move, align, delete with the confirm), autosave and reload; the translation tab's copy and its state; a second person's read-only grid; the site in both schemes, a wide table scrolling inside its box at a phone's width while the page does not;
- a fixture theme that replaces the template from the reference alone.

## Documentation

In `contentspiel-docs`, after the block ships: `editors/pages/build-a-page-with-blocks.md` (the Table block), the translating pages (a table per language, the copy, the state), `integrators/theming/the-theme-contract.md` (the component's line, the five tokens, the release note), and the loader (`bin/load` writes a Table block for a Markdown table instead of paragraphs).

## As built
