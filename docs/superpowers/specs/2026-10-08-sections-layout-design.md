# Sections: blocks that hold blocks

The first of four sub-projects that grew out of the roadmap's "Block and type catalogue" (agreed with the user on 2026-10-08): (1) layout — this spec; (2) the built-in catalogue of blocks, content types and page types; (3) content types defined in the admin; (4) forms, with mail delivery. Each has its own spec, plan and PR. This is the binding spec for one implementation plan and one PR.

**Status: built** (plan `docs/superpowers/plans/2026-10-08-sections-layout.md`). Where the build left this text, §12 "As built" says so; the description of the code as it is lives in `docs/reference/content-blocks-and-types.md`.

## 1. Purpose

A page is a flat, ordered list of blocks. Nothing can sit beside anything else, and nothing can give a stretch of the page its own background. A landing page — a hero, a tinted band of three features, a band of text, a call to action — can't be built.

This sub-project adds one container: a **Section** block that arranges other blocks in columns and gives them a band with its own background and width. It comes before the catalogue because every block in the catalogue is designed differently depending on whether it can sit in a column.

**Success:**
- An editor can build a page of bands, each with one of six column layouts, without code.
- A page without sections looks and edits exactly as today.
- Every per-block mechanism — autosave and its stale check, translation tracking, image protection, media usages, permissions, audit — works for a block in a section exactly as for a block outside one.
- The public page stacks sensibly on a phone and never downloads a desktop-wide image for a narrow column.
- Everything a pointer can do in the editor has a keyboard path.

## 2. Decisions

Agreed on 2026-10-08:

1. **Layout is a block, not a page type or a content type.** A page type says what a page is and what it starts with; a content type says what a post is. Neither arranges.
2. **One container type, one level deep.** A Section holds ordinary blocks; a section never holds a section.
3. **Six layouts:** one column; two, three and four equal columns; one third + two thirds; two thirds + one third. No free widths.
4. **A section has a look:** background (none, tinted, strong) and width (content, full), both from theme tokens. No colour picker.
5. **In the editor, blocks inside a section are tiles, with one block's form open at full width under the columns.** Blocks outside a section stay full cards with their forms open, as today.
6. **Storage: a block points at its section** (approach A). Every block stays its own row and still belongs to the page.
7. Sections exist on pages only. Any block type may go inside a section except Section.

## 3. Data and rules

### 3.1 Storage

- `content_blocks` gains `section_id` (a nullable reference to `content_blocks`, foreign key NO ACTION) and `section_column` (a nullable integer, 1-based). Both are null for a top-level block.
- A section is a block of the new type `section`, registered like the others in `app/models/block_types/`. Its settings: `layout` (`one`, `two`, `three`, `four`, `one_two`, `two_one`), `background` (`none`, `tinted`, `strong`), `width` (`content`, `full`). Defaults: `two`, `none`, `content`.
- `position` is counted per container: the top-level blocks of a page among themselves; the blocks of one column of one section among themselves.
- The registry gains a capability, `:container`, which the Section type declares. Code asks the capability, never the type's name.

### 3.2 Rules the model enforces

- A block whose type is a container has no `section_id` (no section in a section).
- A block's section belongs to the same owner (the same page) and is a container.
- `section_column` is present exactly when `section_id` is, and is within the section's current layout.
- The foreign key keeps a section that still has blocks from being deleted around the service.

### 3.3 Services

Every write goes through the existing `ContentBlocks::*` services, each calling `authorize!(` and `record_event(`; no controller writes a block.

- **Create** (`ContentBlocks::Save` for a new block) takes an optional section and column.
- **Reorder** (`ContentBlocks::Reorder`) takes a container — the page's top level, or a section and a column — and the ids in their new order. A block named there that currently sits in another container is moved into this one. The call carries the container each moved block is expected to be in; if a block is elsewhere, or its section is gone, the call is refused and nothing is written.
- **Destroy** (`ContentBlocks::Destroy`) on a section has two forms: with its blocks, or `keep_blocks: true`, which lifts the blocks to the top level at the section's place, in reading order (column 1's blocks, then column 2's, …), before removing the section.
- **A layout change** to fewer columns (through `ContentBlocks::Save` on the section) moves the blocks of each removed column to the end of the last remaining column, in column order. A layout change never deletes a block. This happens inside the save's transaction.
- **Duplicate** on a section copies the section and every block in it.
- Each of these is one audit event on the page's own log, naming the section where one is involved.

### 3.4 What does not change

- A block in a section still has the page as its `owner`, so `ContentBlocks::OwnerPermissions`, the "editing a published page needs `publish`" rule, autosave with `base_updated_at`, translation tracking, the image foreign key and media usages apply unchanged.
- `page.content_blocks` is still every block of the page. A new association or scope gives the top-level blocks; another gives a section's blocks by column.
- A post-list block in a column still feeds `public_paths` for the posts it lists.
- A section has no translatable content and adds nothing to `translation_states`.
- The public content version moves as it does for any block write.

### 3.5 MCP

The block tools in `app/mcp/` gain the optional section and column on create and move, and report them on read, so an AI client can build a page with sections. Their current shape is confirmed when the plan is written.

### 3.6 Existing data

No content migration: every existing block has a null section and stays where it is.

## 4. The editor

### 4.1 The section card

- A section is a card in the page's block list with a framed, tinted look that sets it apart from an ordinary block card.
- Header: the drag handle, the name "Section", and three controls — layout (a menu of six small diagrams), background and width (short menus of named choices).
- The ⋯ menu: Move up, Move down, Duplicate, "Remove section, keep blocks", "Delete section and its blocks…" (a confirmation that names how many blocks go with it).
- Collapsed, the card is one line: "Section · 3 columns · 5 blocks".

### 4.2 Tiles

- Each column is a lane of tiles. A tile shows the block's type and one line of its content: the start of a text, an image's file name with a small thumbnail, a post list's filter.
- A tile marks what needs attention as a card does: a missing image, a validation error, a type that is no longer registered.
- Each lane ends with "+", which opens the block picker without Section.

### 4.3 Editing a block

- Clicking a tile opens that block's form at full width under the row of lanes, headed "Text · column 2". It is the block's own form, with the same autosave and save status as a card's.
- One form is open per section. Opening another tile closes the first; an edit not yet sent is sent first, through the write queue.
- A block just added opens at once.
- Escape, or a click on the open tile, closes the form.

### 4.4 Moving blocks

- Drag a tile within its lane, to another lane, or out of the section into the page's list. Drag a top-level card into a lane.
- Every move is also in the ⋯ menu: Move up, Move down, "Move to column…", "Move out of section"; a top-level block's menu gains "Move into section…" when the page has a section.
- A lane does not accept a section.
- Every move is sent through `app/javascript/autosave/queue.js`, one at a time, like today's reorder.

### 4.5 Translation view

In the side-by-side translation view a section is a plain group heading, and its blocks are listed in reading order, column by column, each with its pair of fields.

### 4.6 Small screens

Below the width where the lanes fit side by side, the lanes stack in the editor, each with its column label.

### 4.7 Strings

Every new string is a key in `config/locales/admin/`, and the new components and scripts join `CONVERTED` in `test/lib/admin_i18n_test.rb`.

## 5. The public page

### 5.1 Rendering

- A page renders its top-level blocks in order. A section renders as a `<section>` element holding a grid; each column renders its blocks in order with the components that render them at the top level.
- A block's component does not know it is in a column. It adapts through CSS.

### 5.2 Layouts

- On a narrow container every layout is one column, in reading order.
- Four columns are two by two at a medium width before stacking.
- Breakpoints follow the section's own width (CSS container queries), not the window's.

### 5.3 Background and width

- `tinted` and `strong` are two theme tokens, with their dark-mode values. Text and links in a `strong` section take the contrasting tokens.
- `full` runs the band edge to edge with its content aligned to the page's content width; `content` keeps the band within the content width.
- Adjacent sections with the same background join without a gap.

### 5.4 Images

An image block in a column asks for a smaller variant: the `sizes` hint is derived from the section's layout.

### 5.5 Empty parts

- An empty column keeps its place.
- A section with no blocks renders nothing.

### 5.6 Semantics

A section has no heading of its own and is a plain grouping element, not a named landmark.

### 5.7 Caching and preview

Nothing new: the content version and render cache cover a section as part of its page, and the preview renders sections as the public page does.

## 6. Errors and edge cases

- A stale save of a block in a section is refused with the usual 409 and shown on the open form.
- A move whose block is no longer where the caller thought, or whose section is gone, is refused and the list reloads.
- An add into a column a concurrent layout change removed is refused with a message, and the view reloads.
- A section whose type is no longer registered shows the "Unavailable type" card with its blocks listed under it, so they can be moved out or deleted.
- A block of an unregistered type inside a section is an "Unavailable type" tile with Delete as its only action. (As built it keeps its move items too: §12.)

## 7. Tests

- **Model:** the rules of §3.2 and ordering per container.
- **Services:** create into a column; every kind of move, including the refusal; both deletes; a layout change that folds columns; duplicating a section. Each new or changed service entry in `EXPECTED_SERVICES` and `test/support/service_calls.rb`.
- **Derived rows:** a post-list block in a column and `public_paths` (`test/models/public_site/paths_test.rb`); an image in a column and `media_usages`; a text in a column and `translation_states` (`test/services/translation_state_parity_test.rb`).
- **Public page:** the markup of each layout, stacking order, background and width, image `sizes`, an empty column, an empty section.
- **Editor (system):** adding a section and blocks into columns; opening a tile, typing, the autosave landing; switching tiles mid-edit without losing text; dragging between lanes and out of the section; the same moves from the menu by keyboard; a layout change to fewer columns; both deletes; the translation view.
- **Trash:** a trashed image in a column; a page with sections trashed and restored (`test/integration/trash_visibility_test.rb`).

## 8. Risk

The tile-and-open-form pattern is new and sits on autosave and the write queue, the most delicate parts of CS Studio. The plan's first task builds that interaction on its own — a section with tiles, one form opening and closing, an edit in flight when the form is switched — before the rest is built around it.

## 9. Documentation

- `docs/reference/content-blocks-and-types.md` gains a "Sections" part.
- `CLAUDE.md` gains the silent-break rules: a block in a section still belongs to the page; a move goes through `ContentBlocks::Reorder` and the write queue; code asks the `:container` capability, not the type name.
- `docs/roadmap.md`: "Block and type catalogue" becomes the four sub-projects named at the top of this spec, in that order.

## 10. Out of scope

- Sections inside sections.
- Free column widths, and more than four columns.
- A custom colour or a background image on a section.
- A heading, an anchor name or spacing options on a section.
- Sections in posts.
- Per-device layouts beyond the built-in stacking.
- Sections shared between pages.

## 11. Notes for the later sub-projects (not part of this one)

- **Catalogue:** target is all three kinds of site (business, portfolio, editorial). Built-in content types suggested: event, person, project, beside blog; resume entry and now update move to an optional "personal site" starter set (to be confirmed). Page types become a registry (the structure review forbids new integer enums). Block designs need a real design pass (an artifact or design canvas, not the local companion).
- **Admin-defined types:** the roadmap's "Custom content types and fields defined in the admin"; DB-backed definitions beside the code registry.
- **Forms:** a form block; fields share the field builder of admin-defined types; submissions, spam protection without a third-party captcha, and mail delivery (not set up yet).

## 12. As built

Where the code differs from this spec or from the decisions of the plan (D1–D15) and its answers to the open questions (Q1–Q5), with the reason. The code is the authority; `docs/reference/content-blocks-and-types.md` and `docs/reference/save-rule-and-write-queue.md` describe it.

**The questions the plan answered**

- **Q1, §3.5 (MCP).** Not built. `app/mcp/` has no page or block tool at all, so "the block tools gain a section and a column" had nothing to extend; page and block tools are a new MCP surface with its own spec (a roadmap row).
- **Q2, §3.3 ("one audit event").** A duplicated section is several events: `ContentBlocks::Duplicate` saves every copy through `ContentBlocks::Save` (a `block.created` each) and places the copy through `ContentBlocks::Reorder` (one `block.reordered`), so the image-choice rule, the usage rows and the translation state are decided in one place. A copy refused for want of permission re-records its `access.denied` outside the rolled-back transaction.
- **Q3, §3.2 (the foreign key).** `Page` destroys the blocks in its sections first, in a `before_destroy` declared ahead of the association: `dependent: :destroy` goes in `position` order and would reach a section before the blocks in it.
- **Q4, §5.1 ("a component does not know it is in a column").** The dispatch is one helper, `ThemeHelper#render_block`, used by the page view and by `Blocks::SectionComponent`. The image component is the one exception: it reads `block.section` for its `sizes`.
- **Q5, §4.4 (Undo).** No Undo for a move into, out of or inside a section; the toast follows only a reorder of the page's own list (a roadmap row).

**Data and services (§3)**

- **The lock (D14) was widened three times.** D14 locked the page's row for structural writes only and left "a save of a block outside any section untouched". As built, every `ContentBlocks::Save`, `Destroy`, `Reorder` and `Duplicate` takes the page's row lock as the first statement of its transaction, and `Tags::Merge#repoint_blocks` and `Trash::Purge#purge_branch` lock their pages (in id order) before any block. Reason: a fold, a lift and the renumbering after one write other blocks' rows — top-level ones included — while holding the page's row, and every block-first writer on the same page (an ordinary autosave, which took the page's row only at `owner.touch`; the plain reorder; the tag merge; a page's destroy) could deadlock against them. "A page without sections edits exactly as today" therefore holds in behaviour, not in statements: each block write issues one more short `SELECT … FOR UPDATE`.
- **The fold is decided from the rows (§3.3).** The spec reads as "a layout change to fewer columns moves the blocks"; comparing the layout before and after on the caller's object is wrong for a second tab's stale copy. The section is re-read under the lock, and every save of a container asks which blocks sit beyond its layout.
- **The fold is its own audit event (D7).** D7 put `folded_block_ids` in the section's `block.updated`. That action coalesces, and a coalesced extension leaves `metadata` as first written, so the ids would be lost in the common flow. A save that folded is recorded with `coalesce: false` (`Audit.record` and `ApplicationService#record_event` gained the keyword); the append-only rules of the log were not widened.
- **A section whose type is gone is deleted from its rows.** `ContentBlocks::Destroy` reads the blocks a block holds from the rows, not from `container?`, so such a section is deleted or lifted instead of raising on the foreign key.
- **Reorder has four refusals**, `STALE`, `NO_COLUMN`, `NESTED` and `NOT_THE_LIST`; the controller reads every reorder parameter as one value or not at all, so a forged array or hash is a refusal, never an error. `Duplicate` re-reads its source under the lock and fails with `GONE`.
- **`BlockOutline#sections`** (D1's list did not name it; the plan's first task built it) was removed: nothing called it.

**The editor (§4, §6)**

- **`section_lanes_stream` became `section_structure_streams`.** The plan's helper redrew the lanes alone. Three things on screen name a block's column — the lanes, each panel's heading and the header's counts — so they are redrawn together, and never a panel.
- **The lanes are redrawn only when the number of columns changed, and the layout menu only when the layout changed.** A save of the background or the width used to replace both, which took the focus off a button someone had just reached and closed an open menu.
- **§6, "the list reloads" after a refused move.** The server still answers a refused structural move with the whole list. The browser draws it only when no autosave form of the block list holds unsaved text; otherwise the block is put back, the alert gains "Reload once your unsaved text is safe" and nothing else changes. Reason: a refusal and a 409 have the same cause (a second editor), so they arrive together, and the 409 bar has promised that typed text stays. The cost: that screen stays behind the server until it is reloaded.
- **§6, "the view reloads" after a refused add.** The section's structure is redrawn (`section_structure_streams`), not the view: a reload would discard every form.
- **Six departures in the drag (D8's code as planned):** a move stands back once for an edit still queued behind it; the queue slot is held until a structural answer is drawn; a queued move whose element is no longer where it was put is dropped; the orders to go back to (`restoreTo`) are kept per container; over a section's card the list sorts a dragged block only from above or below the lanes (`besideSection`); a lane that was only moved with its card keeps its Sortable. Each has a system test in `test/system/admin/sections_test.rb`. Beyond those, the moved element and its panel are `inert` from a crossing move until its answer is drawn, and D8's "every form sends what it holds" also runs before a move along a lane.
- **§6, an unavailable tile's "Delete as its only action".** It keeps Move up, Move down, "Move to column…" and "Move out of section" and has no Duplicate. Reason: it keeps its pointer grip, and §1 gives the keyboard whatever the pointer has; §6 was written before the grip existed on such a tile.
- **§6, a section whose type is gone.** Its lanes are closed (one per stored column, taking no block, sorting nothing), since the server has no column of it; its tiles can be opened, edited, moved out and deleted, not moved along or copied. The card offers one action, "Delete block…", which deletes the section with its blocks; "Remove section, keep blocks" is not offered there although the service honours it.
- **The delete dialog's home (§4.2).** A block's delete dialog is in its tile (or its card), not in its form's panel: a `<dialog>` inside a hidden element is not drawn.
- **§4.3, §4.4.** A top-level card's "Move into section…" is drawn disabled and enabled in the browser while the page has a section a block can go into. A tile's Duplicate does not open the copy's form: §4.3's "opens at once" is for a block just added, and opening a copy would close the form that is open, which may be its source's, mid-edit.
- **Menu moves are announced** in the block list's live region, and the focus rule after a menu move (the block's handle or ⋯; given back after a crossing move only if nothing else has the focus) is new against the spec, which was silent.

**The public page (§5)**

- **The container (D11).** The container-query container is the `<section>`, and a band's side padding moved to `.content-section__inner`: with the padding inside the measured box a content-width band measured 43rem and four columns could never be four across under the 44rem breakpoint.
- **Token re-valuing (§5.3).** A band gives the `--th-*` tokens new values for everything inside it instead of restyling selectors, so blocks added later are right without a rule. In the tinted band `--th-meta` reads as `--th-dim` (plain meta is 4.32:1 on the light tinted band) and `--th-sunken` as `--th-surface`. The lowest contrast pair in use is 4.95:1.
- **§5.5.** An empty column keeps its place while the columns sit side by side and is hidden while they are stacked, where it would be two gaps with nothing between them. A section holding only blocks that draw nothing renders nothing.
- **§6 on the public side.** A section whose type is gone draws its blocks once each, stacked at the content width with no band; an unregistered block in a column is skipped.
- **D13.** An image inside rich text in a column still asks for the content width (a roadmap row).
