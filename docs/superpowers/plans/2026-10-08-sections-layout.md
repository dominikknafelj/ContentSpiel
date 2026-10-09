# Sections: blocks that hold blocks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one container block, the Section, which arranges a page's other blocks in one of six column layouts inside a band with its own background and width, edited in CS Studio as lanes of tiles with one block's form open under them.

**Architecture:** A block points at its section (`content_blocks.section_id`, `section_column`); every block stays its own row and still belongs to the page, so autosave, the stale check, translation tracking, image protection, media usages, permissions and audit apply to a block in a section unchanged. Everything that walks a page's blocks in display order goes through one value object, `BlockOutline`, built from the page's already-loaded blocks. In the editor every block's form is rendered with the page and one per section is shown at a time, so opening, closing and switching a form never removes an autosave form from the document and never needs a request; every structural change (add, move, fold, lift, delete) is an `ApplicationService` write sent through the existing write queue.

**Tech Stack:** Rails 8.1, Postgres 17, Minitest with fixtures and `ContentHelper`, system tests on Capybara + Cuprite, ViewComponent with Lookbook previews, Hotwire (Turbo, Stimulus) through importmap, SortableJS (already pinned), Tailwind v4 (two builds: the product UI and the public default theme).

**Spec:** `docs/superpowers/specs/2026-10-08-sections-layout-design.md`. Executors read the spec section each task names, and the reference file `CLAUDE.md`'s index names for the code they touch.

## Spec questions

Places where the spec assumes something the codebase does not have. The plan follows the recommendation given; the owner can overrule any of them.

| # | The spec says | The codebase has | Recommendation (planned) |
|---|---|---|---|
| Q1 | §3.5: "The block tools in `app/mcp/` gain the optional section and column on create and move, and report them on read." | No block or page tool exists. `app/mcp/mcp/tools/` holds six tools: `create_post`, `get_post`, `list_posts`, `update_post`, `get_media`, `list_media`. MCP cannot read or write a page at all. | Build no MCP tool here: page and block tools are a new MCP surface (scopes, serialiser, Markdown for blocks) and deserve their own spec. Task 11 adds a roadmap row, "MCP page and block tools, with a block's section and column". |
| Q2 | §3.3: "Duplicate on a section copies the section and every block in it", and "Each of these is one audit event". | Duplicate is not a service: `Admin::ContentBlocksController#duplicate` builds the copy itself, saves it through `ContentBlocks::Save` (`block.created`) and places it through `ContentBlocks::Reorder` (`block.reordered`): two events for one block today. | A new service `ContentBlocks::Duplicate` (Task 4) that copies through `ContentBlocks::Save`, so the image-choice rule, usage rows and translation state stay in one place. A duplicated section therefore records `block.created` for the section and for each copied block, plus the one `block.reordered`: not one event. The other writes (move, both deletes, a layout fold) are one event each. |
| Q3 | §3.2: "The foreign key keeps a section that still has blocks from being deleted around the service." | `Page has_many :content_blocks, -> { order(:position) }, dependent: :destroy`, which `Trash::Purge` relies on, destroys a page's blocks one statement at a time in `position` order. With a NO ACTION self-reference a section is deleted before its blocks and the purge fails. | `Page` destroys the blocks that sit in a section first (a `before_destroy` declared above the association, Task 1). The foreign key still refuses a bare `section.destroy`. |
| Q4 | §5.1: "A block's component does not know it is in a column", and §3.4: a post-list block in a column still serves its posts' permalinks. | `pages/show.html.erb` swaps the matched listing block for the post's detail component inline, from `@post` and `@post_list_block`; a component is built with `new(block:, page:)` and sees neither. | The dispatch moves into one helper, `ThemeHelper#render_block(block)`, which the page view and `Blocks::SectionComponent` both call (Task 1). The image component reads `block.section` to pick its `sizes` (§5.4); nothing else in a block's component looks at the section. |
| Q5 | §4.4 implies today's Undo toast after a reorder. | The Undo is a PATCH of the previous top-level order. | Undo is offered only for a reorder inside the top level that moved no block between containers. A move into, out of or inside a section has no Undo (a roadmap row, Task 11). |

## Decisions made while planning

| # | Decision | Why |
|---|---|---|
| D1 | Names: `belongs_to :section` and `has_many :section_blocks` on `ContentBlock`; scopes `ContentBlock.top_level` and `ContentBlock.in_column(section, column)`; `ContentBlock#container?` and `#column_count`; `BlockOutline` (`app/values/block_outline.rb`) with `top_level`, `columns(section)`, `blocks_in(section)`, `reading_order`. | A scope answers a query; the outline answers "in display order" from the association both page controllers already preload, so a render costs no extra query. |
| D2 | The column count comes from the type definition (`t.columns ->(settings) { ... }` on `ContentModel::BlockTypeDefinition`), and a `:container` type without it fails at registration. | Code asks the capability and the definition, never `block_type == "section"` (spec §3.1). |
| D3 | The open form is not fetched. Every block's form in a section is rendered with the page inside a hidden panel under the lanes, and `admin--section` shows one at a time. | A form that is never removed keeps its `admin--autosave` registration and its save state (paused by a 409, failed, debounced), so nothing has to be drained before a switch; a page of full cards already renders every form today. |
| D4 | The panel is `Admin::BlockCardComponent` drawn with `placement: :panel` (no handle, no menu, a "Text · column 2" header and Close), not a new form component. | The card is the block's own form; extracting it would mean converting its English literals in this sub-project. |
| D5 | A section's layout, background and width are fields of the section's own `admin--autosave` form in its header: layout is an `Admin::MenuComponent` of six diagrams writing a hidden input, background and width are `.cs-select`s. | The section's settings then carry `base_updated_at` and are refused when stale like any block's, with no new endpoint. |
| D6 | `ContentBlocks::Reorder.call(page, ordered_ids, section: nil, column: nil, moved_from: {}, actor:)`; on the wire `{ ids: [...], section_id:, column:, moved_from: { "<block id>": { section_id:, column: } } }`. | One call per drop: the target container's new order, plus where each block that came from elsewhere is expected to be (spec §3.3). The two-argument form is today's call. |
| D7 | No new audit action. `block.reordered` (subject: the page) gains metadata `section_id`, `column`, `moved_block_ids`; `block.deleted` on a section gains `deleted_block_ids` or `kept_block_ids`; `block.updated` on a section gains `folded_block_ids`. | `Audit::Sentence::BLOCK_ACTIONS` and the dashboard's verb list stay as they are; the metadata names the section. |
| D8 | A move between containers re-renders only the moved block (card to tile and panel, or back). Before it is queued every autosave form on the screen is told to send what it holds, and a block whose form did not end clean (a 409, an error) is not moved: it goes back and a toast says to reload or fix it first. | The re-render replaces that block's form; text a 409 bar promised to keep must not vanish with it. A move inside one container moves the element only, as today. |
| D9 | A tile's grip is pointer-only (a `<span aria-hidden>`); the keyboard path for a tile is its ⋯ menu. A top-level card keeps today's Space-and-arrows handle. | The menu covers every move (spec §4.4); a second keyboard model across lanes would be new, untested interaction on the most delicate code. |
| D10 | "Move to column…" and "Move into section…" open one dialog per page (`#move-block-dialog`), whose `<select>` is filled in the browser from the sections and lanes on screen when it opens. | Sections come and go without the other cards being re-rendered, so a server-rendered list of targets would go stale. |
| D11 | Breakpoints. Public: a section's grid is one column below `30rem` of its own width, the multi-column layout from `30rem`, and four columns are two by two from `30rem` and four across from `44rem`. Editor: lanes stack below `40rem` of the section card's width. All are container queries. | The public content column is 736px inside `max-w-3xl`, so four across must fit under it; 640px is where four lanes of tiles stop being readable. |
| D12 | `full` width breaks the band out of the layout's `max-w-3xl` column with `margin-inline: calc(50% - 50vw)` and puts the content back with `padding-inline: calc(50vw - 50%)`; `<body>` gets `overflow-x: clip`. | The layout stays one centred column for every other page; no public layout restructure. |
| D13 | Image `sizes` in a column: `(min-width: 768px) <column px>, (min-width: 480px) <column vw>, 100vw`, from the column's share of 736px. An image inside a rich-text block in a column keeps the content-width `sizes`. | The rich-text render is cached by document digest and cannot vary by placement; that gap goes on the roadmap. |
| D14 | Structural writes take the owner's row lock first (`ContentBlocks::Structure#lock_owner`): a save that creates into a section or changes a section's layout, every reorder that names a section, a section's delete and every duplicate. A save of a block outside any section is untouched. | A fold racing an add into the folded column would otherwise leave a block in a column that no longer exists. |
| D15 | `ContentBlock#section_rules` runs only when the block is new or its `section_id`, `section_column` or `block_type` changed. | A block inside a section whose type is no longer registered must still autosave. |

## Global Constraints

- Work only in `/Users/dknafelj/src/ContentSpiel-sections` on branch `sections-layout`. Never push, merge or skip a hook.
- Prefix every test command with `PGGSSENCMODE=disable`. System tests: `bin/rails tailwindcss:build` first, then `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system ...`. Never two test runners on the shared test databases at once.
- **A page without sections looks and edits exactly as today after every task**: the existing suites pass with no edited assertion, or the edit carries a stated reason in the task report.
- Tests are Minitest with fixtures and `ContentHelper` (`create_page`, `create_post`, `create_media_asset`, `rich_doc`); no factories, no RSpec.
- System tests: no fixed `sleep` without `# sleep: <reason>`; wait with `assert_eventually`, `await_js`, `assert_writes_settled`, `await_frames`; a click is `press` or a native `.click`; a JavaScript error fails the test; a control shown only by `hover:` is clicked with `visible: :all`; a resized window is put back in `ensure`.
- Every write goes through an `ApplicationService` that calls `authorize!(` and `record_event(` (or says `# audit: none (reason)`); a controller never writes a record. A new or changed service has its entry in `EXPECTED_SERVICES` and `test/support/service_calls.rb`.
- A block in a section keeps the page as its `owner`. Code asks `capability?(:container)`, never the type's name.
- The foreign key on `section_id` is NO ACTION (the default), never `on_delete: :restrict` or `:cascade`.
- Every move, add, delete and autosave on the editor screen is sent through `app/javascript/autosave/queue.js` (`enqueue` or `holdTurboRequest`), never a `fetch` beside it.
- Queries are Active Record, then Arel through `SqlNodes`, then SQL with `# sql: <reason>`. A write around callbacks (`update_columns`, `update_all`, `delete_all`) bumps the public version or says `# version: none (reason)` on its line.
- New admin strings are keys in `config/locales/admin/components.en.yml`, read with `t(".key")` in a component and `messages(element).t(key)` in a script; counts use `one:`/`other:`. New components and scripts join `CONVERTED` in `test/lib/admin_i18n_test.rb`.
- CS Studio sources use tokens: no hex, `rgb()` or `hsl()`, no `dark:` variant but `dark:scheme-dark`, no `mx-auto`, no inline event handler. Public colours are `--th-*` tokens declared in `app/assets/tailwind/themes/default/tokens.css`, each with its dark value.
- No `Admin::<Domain>` namespace: the new components live under `Admin::EditorScreen::`.
- Models, queries, values and services name no component, controller or route, except a block type registering its component.
- Long comments that record why are the norm here: every new rule in a model, service or script carries one.
- Commits follow this repo's conventional commits (`feat|fix|ref|style|docs|test|chore: lower-case sentence`) and end with exactly these two trailer lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`

## Review Focus

Conditions the spec implies and no happy path exercises, most likely to bite first. Each has its test in the task named.

1. **A post's permalink whose listing block sits in a column** must show the post in place of that listing, with the section's other blocks around it, not the listing again. Task 1.
2. **A form paused by "Changed elsewhere" is closed, another tile is opened, and the first is opened again**: the typed text and the status line must still be there, and nothing is sent for it. Task 2.
3. **Escape pressed inside a menu or a suggestion list of the open form** must close that, not the form. Task 2.
4. **A block whose form holds an unsaved or refused edit is dragged out of its section** (the move re-renders it): the edit must be saved first, or the block must stay where it was with its text. Task 7.
5. **Two tabs: one folds a section to fewer columns while the other adds into, or drops into, the last column**: the second write is refused with a message and the lanes are redrawn; no block ends in a column that does not exist. Tasks 3, 4 and 5.

## File structure

New files, and what each is for:

- `db/migrate/20261008100000_add_section_to_content_blocks.rb`: the two columns, the foreign key, two check constraints, one index.
- `app/models/block_types/section.rb`: the Section type: its three settings, `:container`, its column count.
- `app/values/block_outline.rb`: a page's blocks in display order (top level, a section's columns, reading order).
- `app/services/content_blocks/structure.rb`: what the structural services share (`lock_owner`, renumbering a container).
- `app/services/content_blocks/duplicate.rb`: the copy of a block, or of a section with its blocks.
- `app/components/blocks/section_component.{rb,html.erb}`: the public `<section>` and its grid.
- `app/components/admin/editor_screen/section_card_component.{rb,html.erb}`: the section's card: header, settings form, lanes, panels.
- `app/components/admin/editor_screen/section_lanes_component.{rb,html.erb}`: the row of lanes, re-rendered on its own after a layout change.
- `app/components/admin/editor_screen/block_tile_component.{rb,html.erb}` and `tile_summary_component.{rb,html.erb}`: a tile and its one line of content.
- `app/components/admin/editor_screen/move_dialog_component.{rb,html.erb}`: the one "Move block" dialog.
- `app/javascript/controllers/admin/section_controller.js`: one form open per section.
- `app/assets/tailwind/themes/default/sections.css`: the public grid, bands and breakpoints.

Changed files that carry most of the work: `app/models/content_block.rb`, `app/models/page.rb`, `app/services/content_blocks/{save,reorder,destroy}.rb`, `app/controllers/admin/content_blocks_controller.rb`, `app/components/admin/block_card_component.{rb,html.erb}`, `app/components/admin/block_picker_component.{rb,html.erb}`, `app/javascript/controllers/admin/blocks_controller.js`, `app/views/admin/pages/show.html.erb`, `app/views/pages/show.html.erb`, `app/helpers/theme_helper.rb`.

---

### Task 1: The data layer — a block's section and column, the Section type, the outline

**Spec:** §3.1, §3.2, §3.4, §3.6, §5.1 (minimal), Q3, Q4. **Read first:** `docs/reference/content-blocks-and-types.md`, `docs/reference/trash.md`, the comments in `app/models/content_block.rb`.

After this task a section can exist in the database and is rendered, read and destroyed correctly everywhere, but nothing in CS Studio can create one: the block picker leaves container types out until Task 5.

**Files:**
- Create: `db/migrate/20261008100000_add_section_to_content_blocks.rb`, `app/models/block_types/section.rb`, `app/values/block_outline.rb`, `app/components/blocks/section_component.rb`, `app/components/blocks/section_component.html.erb`
- Modify: `app/models/content_block.rb`, `app/models/content_model/block_type_definition.rb`, `config/initializers/types.rb`, `app/models/page.rb` (above `has_many :content_blocks`), `app/models/audit/snapshot.rb` (the `Page` branch of `serialize`), `app/services/content_blocks/reorder.rb`, `app/controllers/admin/content_blocks_controller.rb`, `app/components/admin/block_picker_component.rb`, `app/helpers/theme_helper.rb`, `app/views/pages/show.html.erb`, `app/views/admin/pages/show.html.erb`, `db/schema.rb` (by the migration)
- Test: `test/models/content_block_test.rb`, `test/models/block_outline_test.rb` (new), `test/models/built_in_types_test.rb`, `test/services/content_blocks/reorder_test.rb`, `test/integration/public_blocks_test.rb`, `test/integration/trash_visibility_test.rb`, `test/components/admin/block_picker_component_test.rb`

**Interfaces:**
- Produces:
  - Columns `content_blocks.section_id` (bigint, null, FK to `content_blocks`, NO ACTION) and `content_blocks.section_column` (integer, null, 1-based).
  - `BlockTypes::Section` with `LAYOUTS` (`{ "one" => [1], "two" => [1, 1], "three" => [1, 1, 1], "four" => [1, 1, 1, 1], "one_two" => [1, 2], "two_one" => [2, 1] }`, the columns' weights), `BACKGROUNDS = %w[none tinted strong]`, `WIDTHS = %w[content full]`, `.register`, `.weights(layout) -> Array<Integer>`.
  - `ContentModel::BlockTypeDefinition#columns` (a `dsl_attribute` holding a callable `->(settings_hash) { Integer }`).
  - `ContentBlock`: `belongs_to :section`, `has_many :section_blocks` (ordered `section_column, position, id`; no `dependent`), `scope :top_level`, `scope :in_column(section, column)`, `#container? -> Boolean`, `#column_count -> Integer` (0 for a non-container or an unregistered type).
  - `BlockOutline.new(blocks)`: `#top_level -> Array<ContentBlock>`, `#columns(section) -> Array<Array<ContentBlock>>` (one array per column of the section's layout), `#blocks_in(section) -> Array<ContentBlock>` (reading order), `#reading_order -> Array<ContentBlock>` (each top-level block followed by the blocks in it), `#sections -> Array<ContentBlock>`.
  - `ThemeHelper#render_block(block) -> String | nil`.
  - `Admin::ContentBlocksController#top_level_blocks` (private): `@page.content_blocks.top_level.reorder(:position, :id)`.

- [ ] **Step 1: Write the failing model tests.** Append to `test/models/content_block_test.rb`:

```ruby
  def section_on(page, layout: "two", position: 0)
    page.content_blocks.create!(block_type: "section", position: position, settings: { "layout" => layout })
  end

  test "a section's settings default to two columns, no background, content width" do
    section = section_on(create_page(title: "Defaults"), layout: nil)

    assert_equal %w[two none content], section.settings_object.then { |s| [ s.layout, s.background, s.width ] }
    assert_predicate section, :container?
    assert_equal 2, section.column_count
  end

  test "column_count follows the layout, and is 0 for a block that holds nothing" do
    page = create_page(title: "Counts")
    counts = %w[one two three four one_two two_one].map { |layout| section_on(page, layout: layout).column_count }

    assert_equal [ 1, 2, 3, 4, 2, 2 ], counts
    assert_equal 0, page.content_blocks.create!(block_type: "rich_text", position: 9).column_count
  end

  test "a block in a section needs a column of that section's layout" do
    page = create_page(title: "Columns")
    section = section_on(page, layout: "two")

    assert page.content_blocks.build(block_type: "rich_text", section: section, section_column: 2).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section: section, section_column: 3).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section: section, section_column: nil).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section_column: 1).valid?
  end

  test "a section never sits in a section" do
    page = create_page(title: "Nesting")
    outer = section_on(page)
    inner = page.content_blocks.build(block_type: "section", section: outer, section_column: 1)

    assert_not inner.valid?
    assert_includes inner.errors[:section], "can't hold another section"
  end

  test "a block's section is a section of the same page" do
    page = create_page(title: "Here")
    elsewhere = section_on(create_page(title: "There"))
    text = page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_not page.content_blocks.build(block_type: "rich_text", section: elsewhere, section_column: 1).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section: text, section_column: 1).valid?
  end

  test "the database keeps section and column together and refuses to delete a section that holds a block" do
    page = create_page(title: "Database")
    section = section_on(page)
    inside = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    assert_raises(ActiveRecord::StatementInvalid) { ContentBlock.transaction(requires_new: true) { inside.update_columns(section_column: nil) } }
    assert_raises(ActiveRecord::InvalidForeignKey) { ContentBlock.transaction(requires_new: true) { section.destroy } }
  end

  test "a block in a section whose type is gone still saves" do
    page = create_page(title: "Dormant")
    section = section_on(page)
    inside = page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    section.update_columns(block_type: "gone/section")

    assert inside.reload.update(caption: "Still editable")
  end

  test "top_level and in_column narrow a page's blocks" do
    page = create_page(title: "Scopes")
    text = page.content_blocks.create!(block_type: "rich_text", position: 0)
    section = section_on(page, position: 1)
    first = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    second = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 2, position: 0)

    assert_equal [ text, section ], page.content_blocks.top_level.to_a
    assert_equal [ second ], page.content_blocks.in_column(section, 2).to_a
    assert_equal [ first, second ], section.section_blocks.to_a
  end

  test "destroying a page destroys the blocks in its sections first" do
    page = create_page(title: "Doomed")
    section = section_on(page)
    page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    assert_difference -> { ContentBlock.count }, -2 do
      page.reload.destroy!
    end
  end
```

Create `test/models/block_outline_test.rb`:

```ruby
require "test_helper"

class BlockOutlineTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Outline")
    @intro = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "three" })
    @outro = @page.content_blocks.create!(block_type: "rich_text", position: 2)
    @b = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    @a = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0)
    @c = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 3, position: 0)
    @outline = BlockOutline.new(@page.content_blocks.reload)
  end

  test "top level is the blocks outside any section, in position order" do
    assert_equal [ @intro, @section, @outro ], @outline.top_level
    assert_equal [ @section ], @outline.sections
  end

  test "a section's columns are one array per column of its layout, an empty one kept" do
    assert_equal [ [ @a, @b ], [], [ @c ] ], @outline.columns(@section)
    assert_equal [], @outline.columns(@intro)
  end

  test "reading order goes column by column inside a section" do
    assert_equal [ @a, @b, @c ], @outline.blocks_in(@section)
    assert_equal [ @intro, @section, @a, @b, @c, @outro ], @outline.reading_order
  end

  test "a block beyond the layout's last column is still in the section's blocks" do
    @section.update_columns(settings: { "layout" => "one" })
    outline = BlockOutline.new(@page.content_blocks.reload)
    section = outline.top_level.second

    assert_equal [ [ @a, @b ] ], outline.columns(section)
    assert_equal [ @a, @b, @c ], outline.blocks_in(section)
  end

  test "it reads the section of each block without a query" do
    blocks = @page.content_blocks.reload.to_a
    outline = BlockOutline.new(blocks)

    assert_empty capture_sql { outline.reading_order.each(&:section) }
  end
end
```

- [ ] **Step 2: Run them, expect failure** (`"section" isn't a registered block type`, `NameError: uninitialized constant BlockOutline`):
`PGGSSENCMODE=disable bin/rails test test/models/content_block_test.rb test/models/block_outline_test.rb`

- [ ] **Step 3: The migration.**

```ruby
# A block points at its section (sections spec §3.1): `section_id` names a
# block of a container type on the same page, `section_column` the 1-based
# column it sits in; both are null for a top-level block, and `position` is
# counted per container. The foreign key is the default NO ACTION, like the
# keys to `media_assets` (`MediaForeignKeysNoAction` says why not RESTRICT):
# a section that still holds a block can't be deleted around
# `ContentBlocks::Destroy`.
class AddSectionToContentBlocks < ActiveRecord::Migration[8.1]
  def change
    add_reference :content_blocks, :section, null: true, index: false, foreign_key: { to_table: :content_blocks }
    add_column :content_blocks, :section_column, :integer
    add_check_constraint :content_blocks, "(section_id IS NULL) = (section_column IS NULL)", name: "content_blocks_section_and_column_together"
    add_check_constraint :content_blocks, "section_column IS NULL OR section_column >= 1", name: "content_blocks_section_column_from_one"
    add_index :content_blocks, %i[section_id section_column position], name: "index_content_blocks_on_section_and_column_and_position"
  end
end
```

Run `bin/rails db:migrate` and `PGGSSENCMODE=disable bin/rails db:test:prepare`. `db/schema.rb` must show `add_foreign_key "content_blocks", "content_blocks", column: "section_id"` with no `on_delete`.

- [ ] **Step 4: The type.** `app/models/block_types/section.rb`:

```ruby
module BlockTypes
  # A band that arranges other blocks in columns (sections spec §2, §3.1). It
  # holds no content of its own: its three settings say how many columns, and
  # which background and width the band has. The blocks in it are ordinary
  # rows that name it in `content_blocks.section_id`. `:container` is what the
  # rest of the code asks; nothing compares a block's type with "section".
  module Section
    # Layout name => the columns' weights, left to right. Their count is the
    # number of columns; the weights are what the public grid and an image's
    # `sizes` are derived from.
    LAYOUTS = {
      "one" => [ 1 ], "two" => [ 1, 1 ], "three" => [ 1, 1, 1 ], "four" => [ 1, 1, 1, 1 ],
      "one_two" => [ 1, 2 ], "two_one" => [ 2, 1 ]
    }.freeze
    BACKGROUNDS = %w[none tinted strong].freeze
    WIDTHS = %w[content full].freeze

    def self.register
      BlockTypes.register :section do |t|
        t.label "Section"
        t.field :layout, :select, options: LAYOUTS.keys, default: "two", required: true
        t.field :background, :select, options: BACKGROUNDS, default: "none", required: true
        t.field :width, :select, options: WIDTHS, default: "content", required: true
        t.capability :container
        t.columns ->(settings) { weights(settings["layout"]).size }
        t.component Blocks::SectionComponent
      end
    end

    # An unknown or missing layout reads as the default: a stored value this
    # code no longer knows must not take the page down.
    def self.weights(layout) = LAYOUTS.fetch(layout.to_s, LAYOUTS.fetch("two"))
  end
end
```

In `ContentModel::BlockTypeDefinition` add `dsl_attribute :columns` and, at the top of `finalize!`, `raise ArgumentError, "a container block type needs `columns`" if capability?(:container) && columns.nil?` (turn the existing early `return unless capability?(:lists_posts)` into an `if` so both checks run). Register the type in `config/initializers/types.rb` after `BlockTypes::PostList.register`. Add to `test/models/built_in_types_test.rb` a test that `BlockTypes.with_capability(:container).map(&:name) == [ "section" ]` and one that registering a `:container` type without `columns` raises `ArgumentError` (use the registry save-and-restore pattern the neighbouring tests use).

- [ ] **Step 5: The model.** In `app/models/content_block.rb`, below `belongs_to :media_asset`:

```ruby
  # A block in a section (sections spec §3.1) names the section and its
  # 1-based column; both are nil for a top-level block. The block still
  # belongs to the page (`owner`): a section arranges, it owns nothing, which
  # is why every per-block rule -- permissions, autosave, translation
  # tracking, media usages -- reads the same for a block in a column.
  # No `dependent:` on `section_blocks`: a section is emptied or lifted by
  # `ContentBlocks::Destroy`, and the foreign key refuses anything else.
  belongs_to :section, class_name: "ContentBlock", optional: true, inverse_of: :section_blocks
  has_many :section_blocks, -> { order(:section_column, :position, :id) }, class_name: "ContentBlock",
    foreign_key: :section_id, inverse_of: :section

  # Only when the placement itself is new or changed (decision D15): a block
  # inside a section whose type is no longer registered fails every one of
  # these, and must still be editable until someone moves it out.
  validate :section_rules, if: -> { new_record? || section_id_changed? || section_column_changed? || block_type_changed? }

  # The blocks a page shows in its own list; `position` is counted among them.
  scope :top_level, -> { where(section_id: nil) }
  # The blocks of one container: a section's column, or (nil, nil) the top level.
  scope :in_column, ->(section, column) { where(section_id: section, section_column: column) }
```

with the public methods:

```ruby
  # Whether this block holds other blocks: asked of the type's capability,
  # never of its name. False for an unregistered type.
  def container? = definition&.capability?(:container) || false

  # How many columns this block's layout has; 0 for a block that holds none
  # (and for a section whose type is gone, so its blocks all read as strays).
  def column_count = container? ? definition.columns.call(settings) : 0
```

and privately:

```ruby
  def section_rules
    if section_id.nil?
      errors.add(:section_column, "must be blank outside a section") unless section_column.nil?
      return
    end
    return errors.add(:section, "can't hold another section") if container?

    holder = section
    return errors.add(:section, "doesn't exist") if holder.nil?

    errors.add(:section, "isn't a section") unless holder.container?
    errors.add(:section, "is on another page") unless holder.owner_type == owner_type && holder.owner_id == owner_id
    errors.add(:section_column, "isn't a column of this section") unless section_column.is_a?(Integer) && section_column.between?(1, [ holder.column_count, 1 ].max)
  end
```

- [ ] **Step 6: The outline.** `app/values/block_outline.rb`:

```ruby
# A page's blocks in the order a person reads them (sections spec §3.4):
# the top-level blocks by `position`, and inside a section its columns left
# to right, each by `position`. Built from blocks already loaded -- both page
# controllers preload `content_blocks` -- so asking it costs no query, and it
# hands each block its section from the same array, so `block.section`
# costs none either.
class BlockOutline
  def initialize(blocks)
    @blocks = blocks.to_a
    by_id = @blocks.index_by(&:id)
    @inside = @blocks.select(&:section_id).group_by(&:section_id)
    @blocks.each { |block| block.association(:section).target = by_id[block.section_id] if by_id.key?(block.section_id) }
  end

  def top_level = @top_level ||= @blocks.reject(&:section_id).sort_by { |block| [ block.position, block.id ] }

  def sections = top_level.select(&:container?)

  # One array per column of the section's layout; an empty column keeps its
  # place. A block stored beyond the last column is not here (`blocks_in`
  # still lists it): only a layout written around the service leaves one.
  def columns(section)
    Array.new(section.column_count) { |index| blocks_in(section).select { |block| block.section_column == index + 1 } }
  end

  def blocks_in(section)
    (@inside[section.id] || []).sort_by { |block| [ block.section_column, block.position, block.id ] }
  end

  def reading_order = top_level.flat_map { |block| [ block, *blocks_in(block) ] }
end
```

- [ ] **Step 7: Run the model tests.** All pass except "destroying a page destroys the blocks in its sections first" (`ActiveRecord::InvalidForeignKey`).

- [ ] **Step 8: Page destroy order (Q3).** In `app/models/page.rb`, directly ABOVE `has_many :content_blocks`:

```ruby
  # Declared before the association on purpose: `dependent: :destroy` below
  # destroys the blocks one statement at a time in `position` order, and a
  # section deleted before the blocks in it is refused by the foreign key
  # (`content_blocks.section_id`, NO ACTION). So the blocks that sit in a
  # section go first. They are taken from the loaded association, so they are
  # the very objects `Trash::Purge` holds and refreshes afterwards; the pass
  # below meets them again already destroyed, which deletes nothing.
  before_destroy { content_blocks.select(&:section_id).each(&:destroy!) }
```

Run the test again: PASS. If the second pass over an already-destroyed block raises, replace the callback's body with one that reorders the loaded target so those blocks come first (`association(:content_blocks).target = content_blocks.partition(&:section_id).flatten`) and say so in the task report.

- [ ] **Step 9: Reads that mean "the page's own list".**
  - `app/services/content_blocks/reorder.rb`: `blocks = @page.content_blocks.top_level.index_by(&:id)` and `before = @page.content_blocks.top_level.reorder(:position, :id).ids`. Add to `test/services/content_blocks/reorder_test.rb`:

```ruby
  test "the page's own order lists its top-level blocks only" do
    page = create_page(title: "Page")
    text = page.content_blocks.create!(block_type: :rich_text, position: 0)
    section = page.content_blocks.create!(block_type: :section, position: 1)
    inside = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 0)

    assert ContentBlocks::Reorder.call(page, [ section.id, text.id ], actor: nil).ok?
    assert_equal [ section, text ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ section.id, 1, 0 ], inside.reload.then { |block| [ block.section_id, block.section_column, block.position ] }
    assert_not ContentBlocks::Reorder.call(page, [ section.id, text.id, inside.id ], actor: nil).ok?
  end
```

  - `Admin::ContentBlocksController`: add private `def top_level_blocks = @page.content_blocks.top_level.reorder(:position, :id)` and use it for `before` in `reorder`, `after` in `reorder_undo_streams`, `ordered` in `reposition_after` and `insertion_stream`, and `blocks` in `blocks_list_stream` (it is a fresh query each time, so the `.reload`s those lines carry go).
  - `Audit::Snapshot#serialize`, `Page` branch: `"content_block_ids" => BlockOutline.new(record.content_blocks.reorder(:position, :id)).reading_order.map(&:id)`, with a line saying the ids are in reading order and that this is the same list as before for a page without sections.
  - `app/views/admin/pages/show.html.erb`: `blocks = BlockOutline.new(@page.content_blocks).top_level`.
  - `Admin::BlockPickerComponent#types`: `BlockTypes.all.reject { |type| type.capability?(:container) }`, with the comment "until the editor can show a section (sections plan, Task 5)". Add a component test that the picker renders no "Section" button.

- [ ] **Step 10: The public page (Q4).** Write the failing tests in `test/integration/public_blocks_test.rb`:

```ruby
  def section_with_texts(*columns, layout: "two")
    section = @root.content_blocks.create!(block_type: :section, position: 5, settings: { "layout" => layout })
    columns.each_with_index do |(column, text), index|
      @root.content_blocks.create!(block_type: :rich_text, section: section, section_column: column, position: index, body: rich_doc(text))
    end
    section
  end

  test "a section renders its blocks once, inside it, column by column" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Before the band"))
    section_with_texts([ 2, "Right text" ], [ 1, "Left text" ])
    get "/"

    assert_select "section.content-section", 1
    assert_select "section.content-section .content-section__column", 2
    assert_select ".cs-prose", 3
    assert_operator response.body.index("Before the band"), :<, response.body.index("Left text")
    assert_operator response.body.index("Left text"), :<, response.body.index("Right text")
  end

  test "a post's permalink shows the post in place of its listing when the listing sits in a column" do
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: @root, published_at: Time.current)
    section = blog.content_blocks.create!(block_type: :section, position: 0)
    blog.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 0, body: rich_doc("Beside the list"))
    blog.content_blocks.create!(block_type: :post_list, section: section, section_column: 2, position: 0, settings: { "content_type" => "blog" })
    post = create_post(title: "In a column")
    other = create_post(title: "Another post")
    PublicSite::Paths.sync_posts("blog")

    get "/blog/#{post.slug}"

    assert_response :success
    assert_select "h1", text: "In a column"
    assert_includes response.body, "Beside the list"
    assert_not_includes response.body, other.title
  end
```

  Run them: both fail. Then:
  - `app/helpers/theme_helper.rb`: add `render_block(block)`, moving the dispatch out of `pages/show.html.erb` with its comment (the post-detail swap compared against `@post_list_block`; an unregistered type logs the warning and renders nothing):

```ruby
  def render_block(block)
    if @post && block == @post_list_block
      definition = @post.definition
      render Theme.current.component_for(definition, :detail_component).new(post: @post) if definition
    elsif (definition = block.definition)
      render Theme.current.component_for(definition).new(block: block, page: @page)
    else
      Rails.logger.warn("Skipping block #{block.id}: unregistered block type #{block.block_type.inspect}")
      nil
    end
  end
```

  - `app/views/pages/show.html.erb`: the loop becomes `<% BlockOutline.new(@page.content_blocks).top_level.each do |block| %><%= render_block(block) %><% end %>`; the comment above it stays, with one sentence added that a section renders the blocks in it through the same helper.
  - `Blocks::SectionComponent` (the grid, the bands and `render?` come in Task 10):

```ruby
module Blocks
  # A section (`BlockTypes::Section`): a plain grouping element holding one
  # column per column of its layout, each rendering its blocks in order with
  # the components that render them at the top level (`ThemeHelper
  # #render_block`, which is also what swaps a listing for a post's detail).
  class SectionComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def columns = BlockOutline.new(page.content_blocks).columns(block)

    private

    attr_reader :block, :page
  end
end
```

```erb
<section class="content-section">
  <% columns.each do |blocks| %>
    <div class="content-section__column">
      <% blocks.each do |inner| %><%= helpers.render_block(inner) %><% end %>
    </div>
  <% end %>
</section>
```

  If `ApplicationComponent` delegates the theme helpers by name instead of exposing `helpers`, add `render_block` to that list and call it bare.

- [ ] **Step 11: Trash.** Add to `test/integration/trash_visibility_test.rb`, following its own setup and helpers:

```ruby
  test "a page with a filled section is trashed, restored and purged with its blocks" do
    page = create_page(title: "Banded")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    inside = page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0, media_asset: create_media_asset)
    Media::UsageIndex.refresh(inside)

    assert Trash::Move.call(page, actor: nil).ok?
    assert Trash::Restore.call(page.reload, actor: nil).ok?
    assert_equal [ section.id, 2 ], inside.reload.then { |block| [ block.section_id, block.section_column ] }

    assert Trash::Move.call(page.reload, actor: nil).ok?
    assert Trash::Purge.call(page.reload, actor: nil).ok?
    assert_empty ContentBlock.where(id: [ section.id, inside.id ])
    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: inside.id)
  end
```

  (Match the argument forms the neighbouring tests use for the three trash services.)

- [ ] **Step 12: Run what this touches.**
`PGGSSENCMODE=disable bin/rails test test/models test/services/content_blocks test/services/service_behaviour_contract_test.rb test/services/trash test/integration/public_blocks_test.rb test/integration/pages_routing_test.rb test/integration/preview_test.rb test/integration/trash_visibility_test.rb test/integration/admin/content_blocks_test.rb test/integration/admin/audit_events_test.rb test/components test/lib`
Expected: PASS, no existing assertion edited. `bin/rubocop` clean.

- [ ] **Step 13: Commit.**

```bash
git add -A
git commit -m "feat: a block can sit in a section's column — the columns, the Section type, the outline" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 2: The risky interaction on its own — tiles, one open form, a switch mid-edit

**Spec:** §4.1 (the card and its lanes only), §4.2, §4.3, §8, D3, D4. **Read first:** `docs/reference/save-rule-and-write-queue.md` (all of it), the header of `app/javascript/controllers/admin/autosave_controller.js` (`saveStates`, `saveNow`, `flush`, `clean`), `app/components/admin/block_card_component.rb`.

This is the spec's §8: the tile-and-open-form pattern is proved against autosave and the write queue before anything is built around it. A section here is created by a test (or the console); it has no controls, no menu and no "+" yet, and its tiles cannot be dragged. What is proved: every form in a section is in the document and registered with the queue from the start; opening and closing only shows and hides; closing sends what the form holds; a form's save state survives being hidden.

**Files:**
- Create: `app/components/admin/editor_screen/section_card_component.{rb,html.erb}`, `section_lanes_component.{rb,html.erb}`, `block_tile_component.{rb,html.erb}`, `tile_summary_component.{rb,html.erb}`, `app/javascript/controllers/admin/section_controller.js`, `test/components/previews/admin/editor_screen/section_card_component_preview.rb`
- Modify: `app/components/admin/block_card_component.rb` and `.html.erb` (`placement:`), `app/views/admin/pages/show.html.erb`, `app/controllers/admin/content_blocks_controller.rb` (`update`, `block_card_component`, `blocks_list_stream`), `app/assets/tailwind/content-spiel.tailwind.css`, `config/locales/admin/components.en.yml`, `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/components/admin/editor_screen/section_card_component_test.rb` (new), `test/components/admin/block_card_component_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/system/admin/sections_test.rb` (new)

**Interfaces:**
- Consumes: `BlockOutline`, `ContentBlock#container?`, `#column_count`, `#section_column` (Task 1).
- Produces:
  - `Admin::BlockCardComponent.new(..., placement: :list)`, with `:list` (today's card), `:panel` (the open form under the lanes) and `:group` (a plain card, used by Task 9). In `:panel` the wrapper is `<div id="block-<id>-panel" hidden data-block-id="<id>" data-admin--section-target="panel">`; in `:panel` and `:group` there is no handle, no ⋯ menu and no `data-admin--blocks-target="card"`. `Admin::BlockCardComponent.panel_id(block) -> "block-<id>-panel"`, `.panel_title_id(block) -> "block-<id>-panel-title"`.
  - `Admin::EditorScreen::SectionCardComponent.new(page:, section:, outline:, locale:, url_options: {}, first: false, last: false, editable: nil)`. Ids: the card `dom_id(section)`, `.lanes_id(section) -> "section-<id>-lanes"`, `.panels_id(section) -> "section-<id>-panels"`, `.summary_id(section) -> "section-<id>-summary"`.
  - `Admin::EditorScreen::SectionLanesComponent.new(page:, section:, outline:, locale:, url_options: {}, editable:)`; `.lane_id(section, column) -> "section-<id>-lane-<column>"`. Each lane is `<div id=... data-admin--blocks-target="lane" data-section-id data-column>` whose direct children are exactly the tiles.
  - `Admin::EditorScreen::BlockTileComponent.new(page:, block:, locale:, url_options: {}, editable:, open: false)`: `<div id="<dom_id(block)>" class="admin-block-tile" data-block-id data-admin--blocks-target="tile" data-admin--section-target="tile">` holding `<button type="button" class="admin-block-tile__face" aria-expanded="false" aria-controls="block-<id>-panel" data-action="admin--section#toggle">`.
  - `Admin::EditorScreen::TileSummaryComponent.new(block:, locale:, invalid: false)`; `.dom_id(block) -> "block-<id>-tile-summary"`.
  - `admin--section` (Stimulus): targets `tile`, `panel`; actions `toggle`, `close`, `escape`; methods `open(id, { focus })`, `close({ refocus })`.
  - `Admin::ContentBlocksController#card_for(block, first:, last:)` (private): the section card for a container, the block card otherwise.

- [ ] **Step 1: Write the failing system tests.** `test/system/admin/sections_test.rb`:

```ruby
require "application_system_test_case"

# A section in the page editor (sections spec §4): lanes of tiles with one
# block's form open under them. The forms are all in the page from the start
# (hidden), so these tests are about what showing and hiding one does to its
# autosave -- nothing, except that closing sends what it holds.
class Admin::SectionsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Landing")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @left = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
    @right = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0)
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
  end

  def tile(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"
  def face(block) = "#{tile(block)} .admin-block-tile__face"
  def panel(block) = "#block-#{block.id}-panel"
  def caption(block) = "block-#{block.id}-caption"

  # Holds the first PATCH this page sends until `window.__releaseSave()`.
  def hold_first_save
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        const method = (options.method || "GET").toUpperCase()
        if (method === "GET") return originalFetch(url, options)
        window.__writes.push(String(url.url || url))
        if (window.__writes.length > 1) return originalFetch(url, options)
        return new Promise((resolve) => { window.__releaseSave = () => resolve(originalFetch(url, options)) })
      }
    JS
  end

  test "a section shows a tile per block in its lane and no form until a tile is pressed" do
    open_editor

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 1
    assert_selector "#section-#{@section.id}-lane-2 > .admin-block-tile", count: 1
    assert_no_selector panel(@left)
    assert_selector panel(@left), visible: :all

    find(face(@left)).click

    assert_selector panel(@left), text: "Image · column 1"
    assert_selector "#{face(@left)}[aria-expanded='true']"
    assert_no_selector panel(@right)
  end

  test "typing in the open form autosaves like a card" do
    open_editor
    find(face(@left)).click

    fill_in id: caption(@left), with: "A caption from a tile"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_equal "A caption from a tile", @left.reload.caption
  end

  test "opening another tile closes the first and sends an edit still inside its debounce" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Set by code, then the form was switched"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    find(face(@right)).click

    assert_no_selector panel(@left)
    assert_selector panel(@right)
    assert_writes_settled
    assert_equal "Set by code, then the form was switched", @left.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  test "a save in flight when the form is switched lands, and so does the next form's" do
    open_editor
    hold_first_save
    find(face(@left)).click
    fill_in id: caption(@left), with: "First, held on the wire"
    page.execute_script("document.activeElement.blur()")
    await_js "typeof window.__releaseSave === 'function'"

    find(face(@right)).click
    fill_in id: caption(@right), with: "Second, queued behind it"
    page.execute_script("document.activeElement.blur()")
    await_frames # the second save is queued behind the held one, or it would have been sent by now
    assert_equal 1, page.evaluate_script("window.__writes.length"), "the second form's save went out beside the first"

    page.execute_script("window.__releaseSave()")
    assert_writes_settled
    assert_equal [ "First, held on the wire", "Second, queued behind it" ], [ @left.reload.caption, @right.reload.caption ]
    assert_equal 2, page.evaluate_script("window.__writes.length")
  end

  # Review Focus 2.
  test "a form paused by Changed elsewhere keeps its text and its status through a close and reopen" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "The other editor's caption" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8

    find(face(@right)).click
    find(face(@left)).click

    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_field caption(@left), with: "Mine, refused"
    assert_equal "The other editor's caption", @left.reload.caption
  end

  test "Escape and a press on the open tile close the form and give the tile the focus" do
    open_editor
    find(face(@left)).click
    find(id: caption(@left)).send_keys(:escape)

    assert_no_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='false']"
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{face(@left).to_json})")

    find(face(@left)).click
    assert_selector panel(@left)
    find(face(@left)).click
    assert_no_selector panel(@left)
  end

  # Review Focus 3.
  test "Escape inside an open menu of the form closes the menu, not the form" do
    text = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    open_editor
    find(face(text)).click
    menu_button = find("#{panel(text)} [role=toolbar] button[aria-haspopup=menu]", match: :first)
    menu_button.click
    assert_selector "#{panel(text)} [role=toolbar] [role=menu]"

    menu_button.send_keys(:escape)

    assert_no_selector "#{panel(text)} [role=toolbar] [role=menu]"
    assert_selector panel(text)
  end

  test "a page without sections has its cards, no section card and no section controller" do
    plain = create_page(title: "Plain")
    plain.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers

    assert_selector "#content-blocks-list > .admin-block-card", count: 1
    assert_no_selector ".admin-section-card"
    assert_no_selector "[data-controller~='admin--section']"
  end
end
```

- [ ] **Step 2: Run them, expect failure** (no `.admin-block-tile`):
`bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST=test/system/admin/sections_test.rb`

- [ ] **Step 3: `placement:` on the block card.** Write the component tests first, in `test/components/admin/block_card_component_test.rb`:

```ruby
  test "as a panel it is the block's own form with a heading naming its column, hidden, and no card chrome" do
    page = create_page(title: "Panel")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

    render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :panel)

    assert_selector "#block-#{block.id}-panel[hidden][data-admin--section-target='panel'][data-block-id='#{block.id}']", visible: :all
    assert_selector "#block-#{block.id}-panel-title", text: "Image · column 2", visible: :all
    assert_selector "form[action$='/content_blocks/#{block.id}'][data-controller~='admin--autosave']", visible: :all
    assert_selector "#block-#{block.id}-save-status", visible: :all
    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "[data-admin--blocks-target='card']", visible: :all
    assert_selector "button[data-action='admin--section#close']", visible: :all
  end

  test "as a list card it is exactly what it was" do
    page = create_page(title: "List")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "##{ActionView::RecordIdentifier.dom_id(block)}[data-admin--blocks-target='card']"
    assert_no_selector "[data-admin--section-target]"
  end
```

  Then in the component: `initialize(..., placement: :list)` raising `ArgumentError` for anything but `%i[list panel group]`; `def panel? = @placement == :panel`; `def list? = @placement == :list`; `def self.panel_id(block) = "#{error_prefix(block)}-panel"`; `def self.panel_title_id(block) = "#{error_prefix(block)}-panel-title"`; `def wrapper_id = panel? ? self.class.panel_id(block) : dom_id`; `def panel_title = t(".panel_title", type: label, column: block.section_column)`. In the template: the wrapper's `id` is `wrapper_id`; `data-admin--blocks-target="card"` only when `list?`; `hidden` and `data-admin--section-target="panel"` only when `panel?`; the handle and the ⋯ menu only when `list?`; when `panel?` the header is `<h3 id="<%= self.class.panel_title_id(block) %>" class="flex-1 truncate text-sm font-semibold text-ink"><%= panel_title %></h3>` and an `Admin::ButtonComponent` (`variant: :ghost, size: :small`, label `t(".close")`, `data: { action: "admin--section#close" }`); when `:group` the header is the plain label. The body, the form and the delete dialog are untouched. Locale keys under `admin.components.block_card`: `panel_title: "%{type} · column %{column}"`, `close: "Close"`.

- [ ] **Step 4: The tile and its summary.** `TileSummaryComponent` renders `<span id="block-<id>-tile-summary" class="admin-block-tile__summary ...">` with one line and, when something needs attention, a `warn`-token mark with an `aria-label`. What the line is, decided from the definition, never from the type's name:
  - no definition: `t(".unavailable", type: block.block_type)`, attention;
  - `uses_columns` includes `"image"`: with an asset, a 24px thumbnail (`asset.thumbnail_url`, `alt: ""`) and `asset.file.filename.to_s`; without one, `t(".no_image")`, attention;
  - `uses_columns` includes `"body"`: `block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(80)`, or `t(".empty_text")`;
  - `capability?(:lists_posts)`: the content type's label or `t(".any_type")`, then `t(".tag", name: tag)` when a tag is set, joined with " · ";
  - anything else: nothing;
  - `invalid: true` adds `t(".needs_fixing")`, attention.

  `BlockTileComponent` renders the wrapper named under Interfaces, the face button holding the type label (`definition&.label || block.block_type`, `font-semibold`) and the summary component, with `aria-expanded="false"`, `aria-controls`, and `data-action="admin--section#toggle"`. No grip and no menu yet (Tasks 7 and 8). Keys under `admin.components.editor_screen.tile_summary`: `unavailable: "Unavailable type — %{type}"`, `no_image: "No image chosen"`, `empty_text: "Empty text"`, `any_type: "All posts"`, `tag: "tag %{name}"`, `needs_fixing: "Needs fixing"`, `attention: "Needs attention"`.

- [ ] **Step 5: The lanes and the section card.** Component test first (`test/components/admin/editor_screen/section_card_component_test.rb`):

```ruby
require "test_helper"

class Admin::EditorScreen::SectionCardComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @page = create_page(title: "Section card")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    @text = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0, body: rich_doc("Hello from a column"))
    @image = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 3, position: 0)
  end

  def render_card
    outline = BlockOutline.new(@page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @page, section: outline.top_level.first, outline: outline, locale: "en")
  end

  test "it is a card of the block list, framed, with one lane per column and a tile per block" do
    render_card

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@section)}.admin-section-card[data-admin--blocks-target='card'][data-container][data-controller~='admin--section']"
    assert_selector "#section-#{@section.id}-lanes > [data-admin--blocks-target='lane']", count: 3
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", text: "Hello from a column"
    assert_selector "#section-#{@section.id}-lane-2 > *", count: 0
    assert_selector "#section-#{@section.id}-lane-3 > .admin-block-tile", text: "No image chosen"
  end

  test "every block's form is in the panels, hidden" do
    render_card

    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel'][hidden]", count: 2, visible: :all
    assert_selector "#block-#{@text.id}-panel form[data-controller~='admin--autosave']", visible: :all
  end

  test "the header names the section and counts its columns and blocks" do
    render_card

    assert_selector "#section-#{@section.id}-summary", text: "3 columns · 2 blocks"
  end

  test "each lane is labelled with its column for a screen reader and for the stacked layout" do
    render_card

    assert_selector "#section-#{@section.id}-lane-2[aria-label='Column 2']"
  end
end
```

  `SectionLanesComponent`: `<div id="section-<id>-lanes" class="admin-section-lanes" data-columns="<count>">`; per column a wrapper `<div class="admin-section-lane">` holding `<p class="admin-section-lane__label ..."><%= t(".column", number: n) %></p>` and the lane element (`id`, `role="list"`, `aria-label`, the `lane` target, `data-section-id`, `data-column`) with one `BlockTileComponent` per block, each in `role="listitem"` supplied by the tile's own wrapper.

  `SectionCardComponent`: the wrapper `<div id="<%= dom_id %>" data-block-id data-container data-admin--blocks-target="card" data-controller="admin--section" data-action="keydown.esc->admin--section#escape" class="admin-block-card admin-section-card rounded-cs border border-line-strong bg-sunken">`; a header with the drag handle exactly as `BlockCardComponent`'s (same class, `aria-describedby="block-drag-help"`, same two actions, `aria-label` from `t(".move")`) for an editable viewer, the name as the collapse button (`data-action="click->admin--blocks#toggle"`, `aria-expanded="true"`, `aria-controls` the body) reading `t(".name")`, and `<span id="section-<id>-summary">` reading `t(".columns", count:)`, " · ", `t(".blocks", count:)`; the body (`data-block-body`) holding the lanes component and `<div id="section-<id>-panels">` with one `Admin::BlockCardComponent.new(..., placement: :panel)` per `outline.blocks_in(section)`. Keys under `admin.components.editor_screen.section_card`: `name: "Section"`, `move: "Move section"`, `columns: { one: "%{count} column", other: "%{count} columns" }`, `blocks: { one: "%{count} block", other: "%{count} blocks" }`; under `section_lanes`: `column: "Column %{number}"`.

  CSS, in `app/assets/tailwind/content-spiel.tailwind.css` beside the block-card rules, tokens only:

```css
/* A section's lanes (sections spec §4.1, §4.6): side by side while the CARD
   is wide enough, stacked below that with each lane's column label shown.
   The breakpoint is the card's own width, like `.admin-translation-form`. */
.admin-section-card { container-type: inline-size; }
.admin-section-lanes { display: grid; gap: 0.75rem; grid-template-columns: minmax(0, 1fr); }
.admin-section-lane > [data-admin--blocks-target="lane"] { display: flex; flex-direction: column; gap: 0.5rem; min-height: 2.5rem; }
.admin-section-lane__label { display: block; }
@container (min-width: 40rem) {
  .admin-section-lanes { grid-template-columns: repeat(var(--lanes), minmax(0, 1fr)); }
  .admin-section-lane__label { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
}
.admin-block-tile { border: 1px solid var(--cs-line); border-radius: var(--cs-radius); background: var(--cs-surface); }
.admin-block-tile:has(> .admin-block-tile__face[aria-expanded="true"]) { border-color: var(--cs-accent); }
```

  The lanes element sets `style="--lanes: <count>"` (a custom property, not a colour). Add a Lookbook preview of a three-column section with a text, an image and an empty lane, in the style of `block_card_component_preview.rb`.

- [ ] **Step 6: The controller script.** `app/javascript/controllers/admin/section_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// One block's form open per section (sections spec §4.3).
//
// EVERY FORM IS ALREADY IN THE PAGE. A section renders each of its blocks'
// forms as a hidden panel under its lanes (`Admin::BlockCardComponent`,
// `placement: :panel`), and this controller only shows one and hides the
// rest. That is the whole point of the design: a form that is never removed
// stays registered with the write queue (`autosave/queue.js`), keeps its
// debounce timer, its queued or in-flight save and its save state -- paused
// by a 409, failed -- exactly as a card's does, so opening, closing and
// switching need no request and can lose nothing. Do not turn this into
// "fetch the form when its tile is pressed": the form leaving the document
// is what the queue's drain exists to guard against.
//
// CLOSING SENDS. A form being hidden is told to send what it holds now
// (`admin--autosave#saveNow`): an edit inside its debounce is otherwise only
// sent by its timer, a second later, with nothing on screen to say so. An
// unchanged form sends nothing and a paused one refuses, as always.
export default class extends Controller {
  static targets = ["tile", "panel"]

  // A block added to a column opens at once: the server marks its panel
  // `data-open`. Tile and panel arrive in one answer but as two streams, so
  // whichever connects second finds the other.
  tileTargetConnected(tile) { this.openIfNew(tile.dataset.blockId) }
  panelTargetConnected(panel) { this.openIfNew(panel.dataset.blockId) }

  // The open block's panel left (deleted, moved out): nothing is open.
  panelTargetDisconnected(panel) {
    if (panel.dataset.blockId === this.openId) this.openId = null
  }

  openIfNew(id) {
    const panel = this.panelFor(id)
    if (!panel || !this.tileFor(id) || !panel.hasAttribute("data-open")) return
    panel.removeAttribute("data-open")
    this.open(id, { focus: true })
  }

  toggle(event) {
    const id = event.currentTarget.closest("[data-block-id]").dataset.blockId
    if (this.openId === id) this.close()
    else this.open(id)
  }

  open(id, { focus = false } = {}) {
    const panel = this.panelFor(id)
    if (!panel) return
    if (this.openId && this.openId !== id) this.close({ refocus: false })

    panel.hidden = false
    this.faceFor(id)?.setAttribute("aria-expanded", "true")
    this.openId = id
    if (focus) panel.querySelector("input:not([type=hidden]), textarea, select, [contenteditable=true]")?.focus()
  }

  close({ refocus = true } = {}) {
    const id = this.openId
    if (!id) return

    const panel = this.panelFor(id)
    if (panel) {
      this.sendNow(panel)
      panel.hidden = true
    }
    const face = this.faceFor(id)
    face?.setAttribute("aria-expanded", "false")
    this.openId = null
    if (refocus) face?.focus()
  }

  // Escape closes the form -- unless it was meant for something open inside
  // it: a menu, a suggestion list or a dialog closes itself on Escape, and
  // the same key press must not also take the form away.
  escape(event) {
    if (!this.openId || event.defaultPrevented) return
    const target = event.target
    if (target.closest("[role=menu], [role=listbox], dialog[open]")) return
    if (target.closest("[data-controller~='admin--menu']")?.querySelector("[aria-expanded=true]")) return
    if (this.panelFor(this.openId)?.querySelector("[role=listbox]:not([hidden])")) return

    event.preventDefault()
    this.close()
  }

  sendNow(panel) {
    for (const form of panel.querySelectorAll("form[data-controller~='admin--autosave']")) {
      this.application.getControllerForElementAndIdentifier(form, "admin--autosave")?.saveNow()
    }
  }

  panelFor(id) { return this.panelTargets.find((panel) => panel.dataset.blockId === id) }
  tileFor(id) { return this.tileTargets.find((tile) => tile.dataset.blockId === id) }
  faceFor(id) { return this.tileFor(id)?.querySelector(".admin-block-tile__face") }
}
```

  If Escape still closes both a menu and the form in the Review Focus 3 test, read `admin--menu#keydown` and `admin--chip-input`'s Escape branch and match what they leave on the event (the order of listeners: theirs sit on a descendant and run first).

- [ ] **Step 7: Wire the page and the answers.**
  - `app/views/admin/pages/show.html.erb`: build `outline = BlockOutline.new(@page.content_blocks)` once; for each top-level block render `Admin::EditorScreen::SectionCardComponent` when `block.container?` and the locale is the default one, `Admin::BlockCardComponent` otherwise (Task 9 gives a section its translation view; until then a section on a translation tab is the block card it was after Task 1).
  - `Admin::ContentBlocksController`: `card_for(block, first:, last:)` returns the section card (with `BlockOutline.new(@page.content_blocks.reset)`) for a container and `block_card_component` otherwise; `insertion_stream` and `blocks_list_stream` use it.
  - `update`: when `block.section_id`, append `turbo_stream.replace(Admin::EditorScreen::TileSummaryComponent.dom_id(block), Admin::EditorScreen::TileSummaryComponent.new(block: result.record, locale: admin_locale, invalid: !result.ok?))` to the streams (not on the 409 or 410 paths). Integration test in `test/integration/admin/content_blocks_test.rb`:

```ruby
  test "saving a block in a section streams its tile's summary, and a block outside one does not" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "post_list", section: section, section_column: 1, position: 0)
    outside = @page.content_blocks.create!(block_type: "post_list", position: 1)

    patch "#{blocks_path}/#{inside.id}", params: { block: { settings: { limit: "0" } }, base_updated_at: inside.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, "block-#{inside.id}-tile-summary"
    assert_includes response.body, "Needs fixing"

    patch "#{blocks_path}/#{outside.id}", params: { block: { settings: { limit: "3" } }, base_updated_at: outside.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "tile-summary"
  end
```

  - Add the four new components (`.rb` and `.html.erb`) and `app/javascript/controllers/admin/section_controller.js` to `CONVERTED` in `test/lib/admin_i18n_test.rb`.

- [ ] **Step 8: Run.** `PGGSSENCMODE=disable bin/rails test test/components test/integration/admin test/lib`, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST=test/system/admin/sections_test.rb`, then the three suites this could disturb: `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{blocks,autosave,changed_elsewhere,unsaved_order,view_only}_test.rb"`. Expected: PASS with no existing assertion edited.

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: a section in the editor is lanes of tiles with one block's form open under them" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 3: Services I — create into a column, a layout that folds, both deletes of a section

**Spec:** §3.3 (Create, Destroy, a layout change), §3.4, §6 (the add into a removed column), §7 (Services, Derived rows), D7, D14. **Read first:** `docs/reference/access-control-and-audit.md`, the headers of `app/services/content_blocks/save.rb` and `destroy.rb`, `test/support/service_calls.rb` ("HOW TO ADD A SERVICE").

**Files:**
- Create: `app/services/content_blocks/structure.rb`, `test/services/content_blocks/destroy_test.rb`
- Modify: `app/services/content_blocks/save.rb`, `app/services/content_blocks/destroy.rb`, `test/support/service_calls.rb`
- Test: `test/services/content_blocks/save_test.rb`, `test/services/content_blocks/destroy_test.rb`, `test/services/translation_state_parity_test.rb`, `test/models/public_site/paths_test.rb`, `test/models/media/usage_index_test.rb` (or the file that tests `Media::UsageIndex`; find it with `grep -rl "UsageIndex" test/models`)

**Interfaces:**
- Consumes: Task 1's columns, scopes, `container?`, `column_count`, `section_blocks`.
- Produces:
  - `ContentBlocks::Structure` (a module, `private` methods): `lock_owner(owner) -> Integer` (takes the owner's row lock without reloading the object) and `renumber(relation) -> void` (writes `position` 0..n-1 over `relation.reorder(:position, :id)`).
  - `ContentBlocks::Save.call(block, attributes: { ..., section_id:, section_column: }, ...)`: the two keys are read for a NEW block only. A section saved with fewer columns moves the blocks of each removed column to the end of the last remaining one, and its `block.updated` event carries `metadata: { "folded_block_ids" => [...] }`.
  - `ContentBlocks::Destroy.call(block, keep_blocks: false, actor:)`. The `block.deleted` event of a section carries `metadata: { "deleted_block_ids" => [...] }` or `{ "kept_block_ids" => [...] }`.

- [ ] **Step 1: Write the failing service tests.** Append to `test/services/content_blocks/save_test.rb`:

```ruby
  def section_on(page, layout: "three")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => layout } }, actor: nil).record
  end

  def add_to(section, column, type: "rich_text")
    ContentBlocks::Save.call(ContentBlock.new(owner: section.owner), attributes: { block_type: type, section_id: section.id, section_column: column }, actor: nil)
  end

  test "a new block goes to the end of the column it names" do
    page = create_page(title: "Columns")
    section = section_on(page)
    first = add_to(section, 2).record
    second = add_to(section, 2).record
    other = add_to(section, 1).record

    assert_equal [ [ section.id, 2, 0 ], [ section.id, 2, 1 ], [ section.id, 1, 0 ] ],
      [ first, second, other ].map { |block| [ block.section_id, block.section_column, block.position ] }
    assert_equal page, first.owner
  end

  test "a new top-level block is appended among the top-level blocks" do
    page = create_page(title: "Top")
    section = section_on(page)
    3.times { add_to(section, 1) }
    text = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record

    assert_equal [ section, text ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal 1, text.position
  end

  test "a column the section no longer has is refused and nothing is written" do
    page = create_page(title: "Gone column")
    section = section_on(page, layout: "two")

    assert_no_difference -> { ContentBlock.count } do
      result = add_to(section, 3)
      assert_not result.ok?
      assert_not result.denied?
      assert_includes result.errors.to_sentence, "isn't a column of this section"
    end
  end

  test "a section can't be created inside a section, and an existing block's section can't be changed through a save" do
    page = create_page(title: "Rules")
    section = section_on(page)
    assert_not add_to(section, 1, type: "section").ok?

    text = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record
    assert ContentBlocks::Save.call(text, attributes: { section_id: section.id, section_column: 1 }, actor: nil).ok?
    assert_nil text.reload.section_id
  end

  test "a layout with fewer columns moves the removed columns' blocks to the end of the last one, in column order" do
    page = create_page(title: "Fold")
    section = section_on(page, layout: "four")
    keep = add_to(section, 2).record
    third_a = add_to(section, 3).record
    third_b = add_to(section, 3).record
    fourth = add_to(section, 4).record

    result = nil
    assert_difference -> { Audit::Event.where(action: "block.updated").count }, 1 do
      result = ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil)
    end

    assert result.ok?
    assert_equal [ keep, third_a, third_b, fourth ], page.content_blocks.in_column(section, 2).reorder(:position).to_a
    assert_equal [ 0, 1, 2, 3 ], page.content_blocks.in_column(section, 2).reorder(:position).pluck(:position)
    assert_equal [ third_a.id, third_b.id, fourth.id ], Audit::Event.where(action: "block.updated").last.metadata["folded_block_ids"]
    assert_equal 4, ContentBlock.where(section_id: section.id).count
  end

  test "a layout with as many or more columns moves nothing" do
    page = create_page(title: "Widen")
    section = section_on(page, layout: "two")
    block = add_to(section, 2).record

    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one_two" } }, actor: nil).ok?
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    assert_equal [ 2, 0 ], block.reload.then { |b| [ b.section_column, b.position ] }
  end

  test "a save into a column needs the page's edit right like any block" do
    page = create_page(title: "Rights", published: false)
    section = section_on(page)
    nobody = User.create!(email_address: "nobody-columns@example.com", password: "a long enough password")

    result = as(nobody) { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }) }

    assert_predicate result, :denied?
    assert_empty ContentBlock.where(section_id: section.id)
  end
```

Create `test/services/content_blocks/destroy_test.rb`:

```ruby
require "test_helper"

class ContentBlocks::DestroyTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Destroy")
    @before = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @after = @page.content_blocks.create!(block_type: "rich_text", position: 2)
    @right = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0, media_asset: create_media_asset)
    @left_b = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    @left_a = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0)
    Media::UsageIndex.refresh(@right)
  end

  test "a section is deleted with its blocks, as one event naming them" do
    assert_difference -> { ContentBlock.count } => -4, -> { Audit::Event.where(action: "block.deleted").count } => 1 do
      assert ContentBlocks::Destroy.call(@section, actor: nil).ok?
    end

    assert_equal [ @before, @after ], @page.content_blocks.reload.to_a
    assert_equal [ @left_a.id, @left_b.id, @right.id ], Audit::Event.where(action: "block.deleted").last.metadata["deleted_block_ids"]
    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: @right.id)
  end

  test "keep_blocks lifts the blocks to the section's place in reading order, then removes the section" do
    assert_difference -> { ContentBlock.count } => -1, -> { Audit::Event.where(action: "block.deleted").count } => 1 do
      assert ContentBlocks::Destroy.call(@section, keep_blocks: true, actor: nil).ok?
    end

    top = @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ @before, @left_a, @left_b, @right, @after ], top
    assert_equal [ 0, 1, 2, 3, 4 ], top.map(&:position)
    assert top.all? { |block| block.section_id.nil? && block.section_column.nil? }
    assert_equal [ @left_a.id, @left_b.id, @right.id ], Audit::Event.where(action: "block.deleted").last.metadata["kept_block_ids"]
    assert_equal 1, Media::Usage.where(owner_type: "ContentBlock", owner_id: @right.id).count
  end

  test "an empty section, a block in a section and a top-level block are deleted as before" do
    empty = @page.content_blocks.create!(block_type: "section", position: 3)

    assert ContentBlocks::Destroy.call(empty, keep_blocks: true, actor: nil).ok?
    assert ContentBlocks::Destroy.call(@left_a, actor: nil).ok?
    assert ContentBlocks::Destroy.call(@before, actor: nil).ok?
    assert_equal [ @left_b, @right ], @section.section_blocks.reload.to_a
    assert_equal({}, Audit::Event.where(action: "block.deleted").last.metadata)
  end

  test "a live page's version moves when a section is deleted either way" do
    @page.update!(published_at: 1.day.ago)

    assert_changes -> { PublicSite.content_version } do
      ContentBlocks::Destroy.call(@section, keep_blocks: true, actor: nil)
    end
  end
end
```

(If `PublicSite.content_version` is memoised on `Current` in a test, read it the way `test/models/public_site/version_test.rb` does.)

- [ ] **Step 2: Run them, expect failure** (`section_id` ignored; `unknown keyword: :keep_blocks`; `InvalidForeignKey`):
`PGGSSENCMODE=disable bin/rails test test/services/content_blocks`

- [ ] **Step 3: What the structural services share.** `app/services/content_blocks/structure.rb`:

```ruby
module ContentBlocks
  # What the services that change WHERE blocks are share (sections spec §3.3):
  # a create into a column, a move, a fold, a lift, a duplicate.
  module Structure
    private

    # The owner's row lock, taken first (decision D14). Two structural writes
    # on one page then run one after the other, each seeing what the other
    # committed: without it a fold to two columns and an add into column
    # three, started together, both pass their checks and leave a block in a
    # column the section no longer has. `pick`, not `owner.lock!`: the
    # caller's page object, with whatever it has preloaded, is left alone.
    # A save of a block outside any section never comes here.
    def lock_owner(owner)
      owner.class.where(id: owner.id).lock.pick(:id)
    end

    # Positions 0..n-1 over one container, in its current order.
    def renumber(relation)
      relation.reorder(:position, :id).each_with_index do |block, index|
        block.update_columns(position: index) unless block.position == index # version: none (every caller touches the owner, whose after_commit bumps for a live page)
      end
    end
  end
end
```

- [ ] **Step 4: `ContentBlocks::Save`.** `include Structure`. In `call`, first line inside the transaction: `lock_owner(@block.owner) if structural?`, with

```ruby
    # A write that changes where blocks are, or could race one that does: a
    # new block going into a section, and any save of a section (its layout
    # may lose columns).
    def structural? = @block.container? || @attributes[:section_id].present? || (@attributes[:block_type].present? && BlockTypes.find(@attributes[:block_type])&.capability?(:container))
```

  In `assign`: capture `@columns_before = @block.column_count if @block.persisted?` before anything is assigned, and after the `block_type`/`media_asset_id`/`position` line add `@block.assign_attributes(@attributes.slice(:section_id, :section_column)) if @block.new_record?` with the comment that a persisted block changes container only through `ContentBlocks::Reorder`. `assign_position` becomes `@block.position = (@block.owner.content_blocks.in_column(@block.section_id, @block.section_column).maximum(:position) || -1) + 1`: the end of the block's own container. After `@block.save || raise(ActiveRecord::Rollback)`: `folded = fold_removed_columns`, and the event gains `metadata: (folded.any? ? { "folded_block_ids" => folded } : {})` and is recorded when `created || changes.any? || folded.any?`.

```ruby
    # A layout with fewer columns (sections spec §3.3): the blocks of each
    # removed column go to the end of the last remaining one, in column order.
    # A layout change never deletes a block. Inside the save's transaction,
    # under the owner's lock, so no block can arrive in a removed column
    # between the read and the write.
    def fold_removed_columns
      keep = @block.column_count
      return [] unless @columns_before && keep.positive? && keep < @columns_before

      stranded = ContentBlock.where(section_id: @block.id, section_column: (keep + 1)..).reorder(:section_column, :position, :id).to_a
      last = ContentBlock.in_column(@block.id, keep).maximum(:position) || -1
      stranded.each_with_index do |block, index|
        block.update_columns(section_column: keep, position: last + 1 + index) # version: none (the owner is touched below, and a live page's after_commit bumps)
      end
      stranded.map(&:id)
    end
```

- [ ] **Step 5: `ContentBlocks::Destroy`.** `include Structure`; `initialize(block, keep_blocks: false, actor: Current.actor)`. The transaction becomes:

```ruby
      destroyed = ContentBlock.transaction do
        lock_owner(@block.owner) if @block.container?
        inside = @block.container? ? @block.section_blocks.to_a : []
        metadata = {}
        if inside.any?
          metadata = { (@keep_blocks ? "kept_block_ids" : "deleted_block_ids") => inside.map(&:id) }
          @keep_blocks ? lift(inside) : inside.each { |block| block.destroy || raise(ActiveRecord::Rollback) }
        end
        record_event("block.deleted", subject: @block, metadata: metadata)
        @block.destroy || raise(ActiveRecord::Rollback)
        @block.owner.touch
        [ @block, *(inside unless @keep_blocks) ].each { |block| Media::UsageIndex.refresh(block) }
        Translations::StateIndex.refresh(@block)
        renumber(@block.owner.content_blocks.in_column(@block.section_id, @block.section_column)) if inside.any? || @block.section_id
        true
      end
```

  with the existing comments kept on the lines they explain, a class-comment paragraph on the two forms, and:

```ruby
    # "Remove section, keep blocks" (sections spec §3.3): the blocks take the
    # section's place at the top level in reading order -- column 1's, then
    # column 2's -- and everything after them moves down. The section itself
    # still stands at this point; it goes right after, and the positions are
    # closed up once it has.
    def lift(inside)
      top = @block.owner.content_blocks.top_level.reorder(:position, :id).to_a
      at = top.index(@block)
      (top[0...at] + inside + top[at..]).each_with_index do |block, index|
        block.update_columns(section_id: nil, section_column: nil, position: index) # version: none (the owner is touched below, and a live page's after_commit bumps)
      end
    end
```

  (The section keeps `section_id: nil` already, so writing nil to it is harmless; it is destroyed next and `renumber` closes the gap.)

- [ ] **Step 6: Run the service tests: PASS.**

- [ ] **Step 7: The contract.** In `test/support/service_calls.rb` add a builder and three variants (`EXPECTED_SERVICES` is unchanged: no new service yet):

```ruby
    # A draft page with a three-column section holding `count` blocks in
    # column 3: what a fold, a lift and a delete of a section all write.
    def draft_page_with_section(count: 2)
      page = create_page(title: "Section", published: false)
      section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "three" } }).record
      blocks = Array.new(count) do
        ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 3 }).record
      end
      [ page, section, blocks ]
    end
```

```ruby
    "ContentBlocks::Save" => {
      "creating" => lambda { ... },   # as it is
      "creating in a column" => lambda {
        page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }) },
          permission: "pages.edit", on: ContentBlock }
      },
      "folding a section's columns" => lambda {
        _page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one" } }) }, permission: "pages.edit", on: section }
      }
    },
    "ContentBlocks::Destroy" => {
      "a section, keeping its blocks" => lambda {
        _page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Destroy.call(section, keep_blocks: true) }, permission: "pages.edit", on: section }
      },
      "a section with its blocks" => lambda {
        _page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Destroy.call(section) }, permission: "pages.edit", on: section }
      }
    },
```

  Run `PGGSSENCMODE=disable bin/rails test test/services/service_contract_test.rb test/services/service_behaviour_contract_test.rb`: PASS.

- [ ] **Step 8: Derived rows (spec §7).** One test in each file, in that file's own idiom (read its helpers first; the assertions below are what each must say):
  - `test/models/public_site/paths_test.rb`: a `post_list` block created through `ContentBlocks::Save` into a section's column gives a published blog post its URL under that page; folding the section's layout keeps it; `ContentBlocks::Destroy.call(section)` takes it away; after each step the table equals a full rebuild (the file's parity assertion).
  - `test/services/translation_state_parity_test.rb`: with `with_locales(%w[en de], default: "en")`, a rich-text block created in a column and given an English body through `ContentBlocks::Save` makes the page's German state what a block outside a section makes it; lifting the section (`keep_blocks: true`) leaves the state unchanged and deleting the section with its blocks clears it; after each step the stored states equal a recomputation (the file's parity assertion).
  - the `Media::UsageIndex` test file: an image block created in a column through `ContentBlocks::Save` with `media_asset_id` has one `block_image` usage row; the asset cannot be purged while it does (`Trash::Purge` fails as it does for a top-level image block); `ContentBlocks::Destroy.call(section)` removes the row.

- [ ] **Step 9: Run** `PGGSSENCMODE=disable bin/rails test test/services test/models test/lib`. Expected: PASS (`version_bump_test` and `sql_strings_test` included). `bin/rubocop` clean.

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat: a block is created into a column, a narrower layout folds its columns, a section is deleted with or without its blocks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 4: Services II — a move between containers, and Duplicate as a service

**Spec:** §3.3 (Reorder, Duplicate), §6 (a move whose block is elsewhere), Q2, D6, D7. **Read first:** `app/services/content_blocks/reorder.rb`, `Admin::ContentBlocksController#duplicate`, `#copy_translations` and `#reposition_after` with their comments.

**Files:**
- Create: `app/services/content_blocks/duplicate.rb`, `test/services/content_blocks/duplicate_test.rb`
- Modify: `app/services/content_blocks/reorder.rb`, `app/controllers/admin/content_blocks_controller.rb` (`duplicate`, `reorder`'s parameters; `copy_translations` moves out), `test/services/service_behaviour_contract_test.rb` (`EXPECTED_SERVICES`), `test/support/service_calls.rb`
- Test: `test/services/content_blocks/reorder_test.rb`, `test/services/content_blocks/duplicate_test.rb`, `test/integration/admin/content_blocks_test.rb`

**Interfaces:**
- Consumes: `ContentBlocks::Structure#lock_owner`, `#renumber`; `ContentBlocks::Save` with `section_id`/`section_column` (Task 3).
- Produces:
  - `ContentBlocks::Reorder.call(page, ordered_ids, section: nil, column: nil, moved_from: {}, actor: Current.actor)`. `section` is a section's id (or the block); `moved_from` is `{ block_id => { section_id:, column: } }` (string or symbol keys, blank meaning the top level) for every block in `ordered_ids` that is expected to come from another container. Failure messages (constants on the class): `STALE = "The blocks have changed since this screen loaded"`, `NO_COLUMN = "That section or column no longer exists"`, `NESTED = "A section can't go inside a section"`, and today's `"The new order must list exactly this page's blocks"` for a top-level call with no `moved_from`. `Reorder#structure_changed?` is not exposed; the controller tells a structural refusal from a denial by `result.denied?`.
  - `ContentBlocks::Duplicate.call(source, actor: Current.actor) -> Result` whose `record` is the copy (for a section, the new section; its blocks are copied into the same columns in the same order). The copy stands directly after its source in the source's container.
  - Wire format of `PATCH .../content_blocks/reorder`: `ids[]`, `section_id`, `column`, `moved_from[<id>][section_id]`, `moved_from[<id>][column]`.

- [ ] **Step 1: Write the failing tests.** Append to `test/services/content_blocks/reorder_test.rb`:

```ruby
  def banded_page
    page = create_page(title: "Moves")
    top = page.content_blocks.create!(block_type: :rich_text, position: 0)
    section = page.content_blocks.create!(block_type: :section, position: 1, settings: { "layout" => "two" })
    a = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 0)
    b = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 1)
    c = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 2, position: 0)
    [ page, top, section, a, b, c ]
  end

  def placement(block) = block.reload.then { |b| [ b.section_id, b.section_column, b.position ] }

  test "a column is reordered among its own blocks" do
    page, _top, section, a, b, c = banded_page

    assert ContentBlocks::Reorder.call(page, [ b.id, a.id ], section: section.id, column: 1, actor: nil).ok?
    assert_equal [ [ section.id, 1, 1 ], [ section.id, 1, 0 ], [ section.id, 2, 0 ] ], [ a, b, c ].map { |block| placement(block) }
  end

  test "a block moves from one column to another, and the column it left closes up" do
    page, _top, section, a, b, c = banded_page

    result = ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2,
      moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil)

    assert result.ok?
    assert_equal [ [ section.id, 2, 0 ], [ section.id, 1, 0 ], [ section.id, 2, 1 ] ], [ a, b, c ].map { |block| placement(block) }
  end

  test "a block moves out of a section into the page's list, and a top-level block into a column" do
    page, top, section, a, b, c = banded_page

    assert ContentBlocks::Reorder.call(page, [ top.id, section.id, a.id ], moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil).ok?
    assert_equal [ nil, nil, 2 ], placement(a)
    assert_equal [ section.id, 1, 0 ], placement(b)

    assert ContentBlocks::Reorder.call(page, [ c.id, top.id ], section: section.id, column: 2, moved_from: { top.id => { section_id: "", column: "" } }, actor: nil).ok?
    assert_equal [ section.id, 2, 1 ], placement(top)
    assert_equal [ section, a ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ 0, 1 ], page.content_blocks.top_level.reorder(:position).pluck(:position)
  end

  test "a move is one event on the page, naming the section, the column and the block" do
    page, _top, section, a, _b, c = banded_page

    assert_difference -> { Audit::Event.where(action: "block.reordered").count }, 1 do
      ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil)
    end
    event = Audit::Event.where(action: "block.reordered").last
    assert_equal [ "Page", page.id ], [ event.subject_type, event.subject_id ]
    assert_equal({ "section_id" => section.id, "column" => 2, "moved_block_ids" => [ a.id ] }, event.metadata)
  end

  test "a block that is no longer where the caller thought is refused and nothing is written" do
    page, top, section, a, b, c = banded_page
    before = [ top, a, b, c ].map { |block| placement(block) }

    wrong_origin = ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: nil, column: nil } }, actor: nil)
    unannounced = ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, actor: nil)
    incomplete = ContentBlocks::Reorder.call(page, [ a.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil)

    [ wrong_origin, unannounced, incomplete ].each do |result|
      assert_not result.ok?
      assert_not result.denied?
      assert_equal [ ContentBlocks::Reorder::STALE ], result.errors
    end
    assert_equal before, [ top, a, b, c ].map { |block| placement(block) }
  end

  test "a section that is gone, a column it no longer has and a section into a section are refused" do
    page, top, section, a, b, _c = banded_page
    other = page.content_blocks.create!(block_type: :section, position: 2)

    gone = ContentBlocks::Reorder.call(page, [ top.id ], section: 0, column: 1, moved_from: { top.id => { section_id: nil, column: nil } }, actor: nil)
    no_column = ContentBlocks::Reorder.call(page, [ top.id ], section: section.id, column: 3, moved_from: { top.id => { section_id: nil, column: nil } }, actor: nil)
    nested = ContentBlocks::Reorder.call(page, [ a.id, b.id, other.id ], section: section.id, column: 1,
      moved_from: { other.id => { section_id: nil, column: nil } }, actor: nil)

    assert_equal [ ContentBlocks::Reorder::NO_COLUMN ], gone.errors
    assert_equal [ ContentBlocks::Reorder::NO_COLUMN ], no_column.errors
    assert_equal [ ContentBlocks::Reorder::NESTED ], nested.errors
    assert_nil other.reload.section_id
    assert_nil top.reload.section_id
  end

  test "another page's block is never moved in" do
    page, _top, section, a, = banded_page
    foreign = create_page(title: "Elsewhere").content_blocks.create!(block_type: :rich_text, position: 0)

    result = ContentBlocks::Reorder.call(page, [ a.id, foreign.id ], section: section.id, column: 1,
      moved_from: { foreign.id => { section_id: nil, column: nil } }, actor: nil)

    assert_not result.ok?
    assert_nil foreign.reload.section_id
  end
```

  Create `test/services/content_blocks/duplicate_test.rb`:

```ruby
require "test_helper"

class ContentBlocks::DuplicateTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Duplicate")
    @first = @page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("Copied text"))
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "one_two", "background" => "tinted" })
    @last = @page.content_blocks.create!(block_type: "rich_text", position: 2)
    @image = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0, caption: "Kept", media_asset: create_media_asset)
    @text_b = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1, body: rich_doc("Second"))
    @text_a = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0, body: rich_doc("First"))
  end

  test "a top-level block's copy stands right after it, with its content" do
    result = ContentBlocks::Duplicate.call(@first, actor: nil)

    assert result.ok?
    assert_equal [ @first, result.record, @section, @last ], @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal @first.body_document(locale: "en").to_h, result.record.body_document(locale: "en").to_h
  end

  test "a block in a column is copied into the same column, right after it" do
    copy = ContentBlocks::Duplicate.call(@text_a, actor: nil).record

    assert_equal [ @text_a, copy, @text_b ], @page.content_blocks.in_column(@section, 1).reorder(:position).to_a
  end

  test "a section is copied with every block in it, column by column, after the section" do
    result = nil
    assert_difference -> { ContentBlock.count }, 4 do
      result = ContentBlocks::Duplicate.call(@section, actor: nil)
    end
    copy = result.record

    assert_equal [ @first, @section, copy, @last ], @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal({ "layout" => "one_two", "background" => "tinted", "width" => "content" }, copy.settings)
    inside = copy.section_blocks.to_a
    assert_equal [ [ "rich_text", 1, 0 ], [ "rich_text", 1, 1 ], [ "image", 2, 0 ] ], inside.map { |block| [ block.block_type, block.section_column, block.position ] }
    assert_equal [ "First", "Second" ], inside.first(2).map { |block| block.body_document(locale: "en").plain_paragraphs.first }
    assert_equal [ @image.media_asset_id, "Kept" ], [ inside.last.media_asset_id, inside.last.caption ]
    assert_equal 2, Media::Usage.where(media_asset_id: @image.media_asset_id, role: "block_image").count
    assert_equal 3, @section.section_blocks.reload.size
  end

  test "a copy refused part-way leaves nothing behind" do
    # May edit this draft page, may not choose images: the image block's copy is refused.
    result = as(page_editor_without_media) { ContentBlocks::Duplicate.call(@section) }

    assert_predicate result, :denied?
    assert_equal 6, @page.content_blocks.reload.size
  end
end
```

  `page_editor_without_media` is a private helper of this test: a user in a group granted `pages.read` and `pages.edit` and nothing else. Build it the way `test/services/authorization_matrix_test.rb` builds a user with chosen grants (`AccessControl::Group.create!` with `grants`, then the membership), and make the page a draft (`create_page(title: "Duplicate", published: false)` in `setup`) so `pages.publish` is not needed.

- [ ] **Step 2: Run them, expect failure:** `PGGSSENCMODE=disable bin/rails test test/services/content_blocks`

- [ ] **Step 3: `ContentBlocks::Reorder`.** Rewrite `call` around one container; the class comment gains the paragraph below and keeps what it says about `update_columns`.

```ruby
  # ONE CONTAINER PER CALL (sections spec §3.3). `section`/`column` name it:
  # nil and nil the page's own list, otherwise one column of one section.
  # `ordered_ids` is that container's complete new order. An id in it that
  # sits in another container now is MOVED here -- but only if `moved_from`
  # says where the caller believes it is, and it is there. That is the whole
  # guard against a stale screen: a block someone else moved, deleted or
  # folded away in the meantime makes the call a failure (`STALE`,
  # `NO_COLUMN`) and nothing is written; the editor's list is redrawn.
  # A two-argument call is what it always was: the page's top-level order.
```

```ruby
    def initialize(page, ordered_ids, section: nil, column: nil, moved_from: {}, actor: Current.actor)
      @page = page
      @ordered_ids = Array(ordered_ids).map(&:to_i)
      @section_id = (section.is_a?(ContentBlock) ? section.id : section).presence&.to_i
      @column = column.presence&.to_i
      @moved_from = moved_from.to_h.to_h do |id, from|
        from = from.to_h.symbolize_keys
        [ id.to_i, [ from[:section_id].presence&.to_i, from[:column].presence&.to_i ] ]
      end
      @actor = actor
    end

    def call
      refused = owner_refusal(@page) { |key| authorize!(key, @page) }
      return denied(refused, @page) if refused

      problem = nil
      ContentBlock.transaction do
        lock_owner(@page) if structural?
        problem = refusal
        raise ActiveRecord::Rollback if problem

        before = members.reorder(:position, :id).ids
        blocks = @page.content_blocks.where(id: @ordered_ids).index_by(&:id)
        @ordered_ids.each_with_index do |id, index|
          blocks[id].update_columns(section_id: @section_id, section_column: @column, position: index) # version: none (a changed order touches the page below, and a live page's after_commit bumps)
        end
        @moved_from.values.uniq.each { |section_id, column| renumber(@page.content_blocks.in_column(section_id, column)) }

        unless before == @ordered_ids
          @page.touch
          record_event("block.reordered", subject: @page, field_changes: { "content_block_ids" => [ before, @ordered_ids ] }, metadata: metadata)
        end
      end

      problem ? failure(@page, [ problem ]) : success(@page)
    end
```

```ruby
    def structural? = @section_id.present? || @moved_from.any?

    def members = @page.content_blocks.in_column(@section_id, @column)

    # The first reason this call can't be honoured, or nil.
    def refusal
      if @section_id
        section = @page.content_blocks.find_by(id: @section_id)
        return NO_COLUMN unless section&.container? && @column&.between?(1, section.column_count)
      elsif @column
        return NO_COLUMN
      end

      moving = @page.content_blocks.where(id: @moved_from.keys).index_by(&:id)
      return NESTED if @section_id && moving.values.any?(&:container?)

      listed_exactly = @ordered_ids.uniq.size == @ordered_ids.size && @ordered_ids.to_set == (members.ids + @moved_from.keys).to_set
      where_expected = @moved_from.all? { |id, from| moving[id] && [ moving[id].section_id, moving[id].section_column ] == from && from != [ @section_id, @column ] }
      return nil if listed_exactly && where_expected

      structural? ? STALE : "The new order must list exactly this page's blocks"
    end

    def metadata
      return {} unless structural?

      { "section_id" => @section_id, "column" => @column, "moved_block_ids" => @moved_from.keys.presence }.compact
    end
```

  `include Structure`, and the three constants at the top of the class, each with a line saying when it is answered: `STALE = "The blocks have changed since this screen loaded"`, `NO_COLUMN = "That section or column no longer exists"`, `NESTED = "A section can't go inside a section"`. Run the reorder tests: PASS.

- [ ] **Step 4: `ContentBlocks::Duplicate`.**

```ruby
module ContentBlocks
  # Duplicate (cs-studio spec §5.1; sections spec §3.3): a copy of one block
  # directly after it in its own container -- and, for a section, of every
  # block in it, into the same columns in the same order. It used to be built
  # in `Admin::ContentBlocksController#duplicate`; a section's copy is several
  # writes that must all land or none, which is a service's job.
  #
  # Every copy is saved through `ContentBlocks::Save`, so one place decides
  # what a new block needs: the image-choice rule (a copy of an image block
  # needs `media.upload`, `Media::Choosing`), the usage rows, the owner's
  # touch and translation state, and a `block.created` per copy. The copy is
  # then put after its source by `ContentBlocks::Reorder` (`block.reordered`),
  # as it always was. So a duplicated section is several events, not one
  # (sections plan, Q2).
  #
  # What is copied: the type, both halves of its settings, every enabled
  # locale's caption, alt and body, and the image reference -- the copy shows
  # the same library asset; nothing is copied in the library, and the asset
  # can't be deleted while either block uses it.
  class Duplicate < ApplicationService
    include OwnerPermissions
    include Structure

    # audit: none (ContentBlocks::Save records block.created for every copy and ContentBlocks::Reorder block.reordered for its place)

    def initialize(source, actor: Current.actor)
      @source = source
      @actor = actor
    end

    def call
      refused = owner_refusal(@source.owner) { |key| authorize!(key, @source) }
      return denied(refused, @source) if refused

      copy = nil
      stopped = nil
      ContentBlock.transaction do
        lock_owner(@source.owner)
        results = [ save_copy(@source, section_id: @source.section_id, section_column: @source.section_column) ]
        copy = results.first.record
        @source.section_blocks.each { |inner| results << save_copy(inner, section_id: copy.id, section_column: inner.section_column) } if results.first.ok?
        results << place_after_source(copy) if results.all?(&:ok?)
        stopped = results.find { |result| !result.ok? }
        raise ActiveRecord::Rollback if stopped
      end

      stopped || success(copy.reload)
    end

    private

    def save_copy(block, section_id:, section_column:)
      copy = ContentBlock.new(owner: block.owner, block_type: block.block_type, settings: block.settings, translated_settings: block.translated_settings)
      copy_translations(block, copy)
      attributes = { media_asset_id: block.media_asset_id, section_id: section_id, section_column: section_column }.compact
      ContentBlocks::Save.call(copy, attributes: attributes, actor: @actor)
    end

    def place_after_source(copy)
      siblings = @source.owner.content_blocks.in_column(@source.section_id, @source.section_column).reorder(:position, :id).ids - [ copy.id ]
      siblings.insert(siblings.index(@source.id) + 1, copy.id) # version: none (Array#insert, no SQL)
      ContentBlocks::Reorder.call(@source.owner, siblings, section: @source.section_id, column: @source.section_column, actor: @actor)
    end
  end
end
```

  `copy_translations(source, copy)` moves here from the controller word for word, with its comment (`ContentBlocks::Save::TRANSLATED` becomes `Save::TRANSLATED`). A denied nested save comes back as it is (`denied?` true), so the controller's 403 path needs no change. Note for the implementer: a nested `ContentBlocks::Save` opens `transaction(requires_new: true)`, so a failed copy rolls back only its savepoint; the outer `Rollback` is what removes the copies already made.

- [ ] **Step 5: The controller.** `duplicate` becomes:

```ruby
    def duplicate
      source = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless source

      result = ContentBlocks::Duplicate.call(source)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      render turbo_stream: [ *insertion_stream(result.record, source.id), *page_base_streams ], status: :created
    end
```

  keeping the action's comment, minus what moved to the service. `reorder` passes the container through: `ContentBlocks::Reorder.call(@page, params[:ids], section: params[:section_id], column: params[:column], moved_from: params.fetch(:moved_from, {}).to_unsafe_h)` (ids, not attributes: the service casts every value to an integer). `create`'s `reposition_after` is unchanged. Add to `test/integration/admin/content_blocks_test.rb`:

```ruby
  test "duplicating a section streams one card holding the copies of its blocks" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    assert_difference -> { @page.content_blocks.count }, 2 do
      post "#{blocks_path}/#{section.id}/duplicate", as: :turbo_stream
    end
    assert_response :created
    copy = @page.content_blocks.top_level.reorder(:position).last
    assert_includes response.body, "section-#{copy.id}-lane-1"
    assert_includes response.body, "block-#{copy.section_blocks.sole.id}-panel"
  end

  test "a reorder that names a column moves the block and a stale one is a 422" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    block = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 2, moved_from: { block.id => { section_id: "", column: "" } } }, as: :turbo_stream
    assert_response :success
    assert_equal [ section.id, 2 ], block.reload.then { |b| [ b.section_id, b.section_column ] }

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 1, moved_from: { block.id => { section_id: "", column: "" } } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, ContentBlocks::Reorder::STALE
  end
```

  (Send the reorder as the existing reorder tests in this file send theirs; the script will send JSON.)

- [ ] **Step 6: The contract.** Add `ContentBlocks::Duplicate` to `EXPECTED_SERVICES` (alphabetical, after `ContentBlocks::Destroy`) and to `FACTORIES`:

```ruby
    "ContentBlocks::Duplicate" => lambda {
      _page, section, = draft_page_with_section
      { call: -> { ContentBlocks::Duplicate.call(section) }, permission: "pages.edit", on: section }
    },
```

  and to `VARIANTS`, under `"ContentBlocks::Reorder"`:

```ruby
      "moving a block out of a section" => lambda {
        page, section, (block,) = draft_page_with_section
        { call: -> { ContentBlocks::Reorder.call(page, [ section.id, block.id ], moved_from: { block.id => { section_id: section.id, column: 3 } }) },
          permission: "pages.edit", on: page }
      }
```

- [ ] **Step 7: Run** `PGGSSENCMODE=disable bin/rails test test/services test/integration/admin test/lib`, then the block system tests, which cover Duplicate and reorder end to end: `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{blocks,unsaved_order,sections}_test.rb"`. Expected: PASS. If an existing test asserts the exact audit events of a duplicate, they are unchanged (`block.created`, then `block.reordered`); an edit there needs its reason in the report.

- [ ] **Step 8: Commit.**

```bash
git add -A
git commit -m "feat: a reorder names its container and moves a block between them; Duplicate is a service and copies a section with its blocks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 5: Adding — a section from the picker, a block into a lane, the new block opens

**Spec:** §4.2 (the "+" at the end of a lane), §4.3 ("A block just added opens at once"), §6 (an add into a removed column), §2.7. **Read first:** `Admin::BlockPickerComponent` and `Admin::ContentBlocksController#create` with their comments.

**Files:**
- Modify: `app/components/admin/block_picker_component.{rb,html.erb}`, `app/components/admin/editor_screen/section_lanes_component.html.erb`, `app/controllers/admin/content_blocks_controller.rb` (`create`, new private stream helpers), `config/locales/admin/components.en.yml`
- Test: `test/components/admin/block_picker_component_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/system/admin/sections_test.rb`

**Interfaces:**
- Consumes: `ContentBlocks::Save` with `section_id`/`section_column` (Task 3); `admin--section`'s `data-open` rule (Task 2); the component ids of Task 2.
- Produces:
  - `Admin::BlockPickerComponent.new(page:, locale:, url_options: {}, section: nil, column: nil)`. Without a section it is the end-of-list row and lists every type again, containers included. With one it is a lane's "+": an `Admin::MenuComponent` (`label: "+"`, `aria_label: t(".add_to_column", number: column)`, `close_on_select: true`) whose items are `button_to`s for every type that is not a container, each posting `block[block_type]`, `section_id` and `column`; its id is `block-picker-<section id>-<column>`.
  - `POST .../content_blocks` reads `params[:section_id]` and `params[:column]`.
  - `Admin::ContentBlocksController` private helpers: `section_lanes_stream(section)` (replaces `section-<id>-lanes`), `section_count_streams(section)` (replaces `section-<id>-summary`; Task 6 adds the delete dialog's sentence to it), `tile_streams(block, open: false)` (appends the panel to `section-<id>-panels`, then the tile to its lane).

- [ ] **Step 1: Write the failing tests.** In `test/integration/admin/content_blocks_test.rb`:

```ruby
  test "adding into a column streams the panel, then the tile, marked to open, and the section's count" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)

    post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 2 }, as: :turbo_stream

    assert_response :created
    block = section.section_blocks.sole
    assert_equal 2, block.section_column
    panel = response.body.index(%(id="block-#{block.id}-panel"))
    tile = response.body.index(%(id="#{ActionView::RecordIdentifier.dom_id(block)}"))
    assert panel && tile && panel < tile, "the panel must arrive before its tile"
    assert_includes response.body, %(target="section-#{section.id}-panels")
    assert_includes response.body, %(target="section-#{section.id}-lane-2")
    assert_includes response.body, "data-open"
    assert_includes response.body, "1 block"
  end

  test "adding into a column the section no longer has is refused with a message and the lanes as they are" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })

    assert_no_difference -> { ContentBlock.count } do
      post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 4 }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "content-blocks-alert"
    assert_includes response.body, "isn&#39;t a column of this section"
    assert_includes response.body, %(target="section-#{section.id}-lanes")
  end

  test "adding into a section that is gone is refused, and a section can't be added into a section" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)

    post blocks_path, params: { block: { block_type: "image" }, section_id: 0, column: 1 }, as: :turbo_stream
    assert_response :unprocessable_entity
    post blocks_path, params: { block: { block_type: "section" }, section_id: section.id, column: 1 }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal [ section ], @page.content_blocks.reload.to_a
  end

  test "adding a section streams its card with empty lanes" do
    post blocks_path, params: { block: { block_type: "section" } }, as: :turbo_stream

    assert_response :created
    section = @page.content_blocks.sole
    assert_includes response.body, "admin-section-card"
    assert_includes response.body, "section-#{section.id}-lane-2"
  end
```

  In `test/components/admin/block_picker_component_test.rb`: the end-of-list picker has a "Section" button again (replace Task 1's test, saying so in the report); a lane picker (`section:`, `column: 2`) has `button[aria-label='Add a block to column 2']`, one item per non-container type, no "Section", and hidden inputs `section_id` and `column`. In `test/system/admin/sections_test.rb`:

```ruby
  test "a section is added from the picker and a block added to its second lane opens at once" do
    plain = create_page(title: "Built by hand")
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers

    within("#block-picker-end") { press "Section" }
    assert_selector ".admin-section-card [data-admin--blocks-target='lane']", count: 2
    section = plain.content_blocks.sole

    find("#block-picker-#{section.id}-2 button[aria-haspopup=menu]").click
    within("#block-picker-#{section.id}-2") { press "Image" }

    assert_selector "#section-#{section.id}-lane-2 > .admin-block-tile", count: 1
    block = section.section_blocks.reload.sole
    assert_selector "#block-#{block.id}-panel", text: "Image · column 2"
    assert_selector "#section-#{section.id}-summary", text: "2 columns · 1 block"

    fill_in id: "block-#{block.id}-caption", with: "Typed straight away"
    page.execute_script("document.activeElement.blur()")
    assert_writes_settled
    assert_equal "Typed straight away", block.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  test "a second block added to a lane closes the form that was open, saving it" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Held when the next block was added"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    find("#block-picker-#{@section.id}-1 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-1") { press "Rich text" }

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
    assert_no_selector panel(@left)
    assert_writes_settled
    assert_equal "Held when the next block was added", @left.reload.caption
  end
```

- [ ] **Step 2: Run them, expect failure.**

- [ ] **Step 3: The picker.** `types` is `BlockTypes.all` without a section and `BlockTypes.all.reject { |type| type.capability?(:container) }` with one (delete Task 1's comment). `id` is `"block-picker-end"` or `"block-picker-#{section.id}-#{column}"`. The template branches on `section`: the row as it is, or the menu described under Interfaces, each item `button_to type.label, create_path, method: :post, params: { block: { block_type: type.name }, section_id: section.id, column: column }`, styled with the menu-item classes `BlockCardComponent#menu_item_class` uses (copy the string into a constant on the picker). Key: `admin.components.block_picker.add_to_column: "Add a block to column %{number}"`. `SectionLanesComponent` renders it after each lane element, inside the lane's wrapper and outside the lane itself (the lane's children stay exactly the tiles), for an editable viewer.

- [ ] **Step 4: The controller.** `create`:

```ruby
    def create
      section = @page.content_blocks.find_by(id: params[:section_id]) if params[:section_id].present?
      return render(turbo_stream: picker_error_stream([ ContentBlocks::Reorder::NO_COLUMN ]), status: :unprocessable_entity) if params[:section_id].present? && section.nil?

      attributes = { block_type: params.dig(:block, :block_type) }
      attributes.merge!(section_id: section.id, section_column: params[:column]) if section
      result = ContentBlocks::Save.call(@page.content_blocks.new, attributes: attributes)

      if !result.ok?
        streams = [ picker_error_stream(result.errors) ]
        streams << section_lanes_stream(section) if section && !result.denied?
        render turbo_stream: streams, status: failure_status(result)
      elsif section
        render turbo_stream: [ *tile_streams(result.record, open: true), *section_count_streams(section), *page_base_streams ], status: :created
      else
        reposition_after(result.record, params[:after_id])
        render turbo_stream: [ *insertion_stream(result.record, params[:after_id]), *page_base_streams ], status: :created
      end
    end
```

  keeping the action's comment and adding what the section branch does. The helpers:

```ruby
    # A block's two halves inside a section, in the order `admin--section`
    # needs them: the panel (its form) first, then the tile that opens it.
    def tile_streams(block, open: false)
      section = block.section
      panel = Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, placement: :panel, open: open)
      tile = Admin::EditorScreen::BlockTileComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, editable: true)
      [ turbo_stream.append(Admin::EditorScreen::SectionCardComponent.panels_id(section), panel),
        turbo_stream.append(Admin::EditorScreen::SectionLanesComponent.lane_id(section, block.section_column), tile) ]
    end

    def section_lanes_stream(section)
      outline = BlockOutline.new(@page.content_blocks.reset)
      fresh = outline.top_level.find { |block| block.id == section.id }
      turbo_stream.replace(Admin::EditorScreen::SectionCardComponent.lanes_id(section),
        Admin::EditorScreen::SectionLanesComponent.new(page: @page, section: fresh, outline: outline, locale: admin_locale, url_options: admin_url_options, editable: true))
    end

    def section_count_streams(section)
      [ turbo_stream.replace(Admin::EditorScreen::SectionCardComponent.summary_id(section),
        Admin::EditorScreen::SectionCardComponent.summary(section: section, count: section.section_blocks.reset.size)) ]
    end
```

  `Admin::BlockCardComponent` gains `open: false`, which in `:panel` placement adds `data-open` to the wrapper (it stays `hidden`; `admin--section` shows it). `SectionCardComponent.summary(section:, count:)` is a class method returning the small component (or `content_tag`) the card itself renders for `#section-<id>-summary`, so the card and the stream cannot drift: extract it in this step. `editable: true` in the streams is right because the service has just allowed the write.

- [ ] **Step 5: Run** the component, integration and `test/lib` tests, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{sections,blocks}_test.rb"`. Expected: PASS; `blocks_test.rb` unchanged (the end-of-list row has one more button, which no assertion counts; if one does, say so in the report).

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat: a section is added from the picker and a block from the end of a lane, where it opens at once" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 6: The section's own controls — layout, background, width, its menu and both deletes

**Spec:** §4.1, §3.3 (a layout change, Destroy), §6 (a stale save of the section), D5. **Read first:** `docs/reference/design-system.md` (menus, dialogs, buttons), `Admin::MenuComponent`, `Admin::ConfirmDialogComponent`, `Admin::ContentBlocksController#update` and `#destroy`.

**Files:**
- Modify: `app/components/admin/editor_screen/section_card_component.{rb,html.erb}`, `app/javascript/controllers/admin/section_controller.js`, `app/controllers/admin/content_blocks_controller.rb` (`update`, `destroy`, `section_count_streams`), `app/assets/tailwind/content-spiel.tailwind.css`, `config/locales/admin/components.en.yml`
- Test: `test/components/admin/editor_screen/section_card_component_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/system/admin/sections_test.rb`

**Interfaces:**
- Consumes: the fold in `ContentBlocks::Save` and `ContentBlocks::Destroy(keep_blocks:)` (Task 3); `ContentBlocks::Duplicate` (Task 4); `section_lanes_stream`, `section_count_streams` (Task 5); `Admin::BlockCardComponent.error_prefix`, `.panel_title_id`.
- Produces:
  - The section card's settings form: `<form id="section-<id>-form" data-controller="admin--autosave" ...>` PATCHing the block like a card's, with `Admin::BlockCardComponent#form_data`'s four data attributes, the hidden base field `block-<id>-base-updated-at`, a hidden `block[settings][layout]` (`id="block-<id>-layout"`), selects `block[settings][background]` and `block[settings][width]`, the status line `block-<id>-save-status` and the three error slots `Admin::FieldComponent.error_id("block-<id>", name)`.
  - `admin--section#chooseLayout` (action; `data-admin--section-layout-param`).
  - `DELETE .../content_blocks/:id` reads `params[:keep_blocks]`.
  - `SectionCardComponent.delete_count_id(section) -> "section-<id>-delete-count"`; `section_count_streams` replaces it too.

- [ ] **Step 1: Write the failing tests.** Component:

```ruby
  test "the header carries the section's own autosaving form: layout, background, width" do
    render_card

    assert_selector "form#section-#{@section.id}-form[data-controller~='admin--autosave'][action$='/content_blocks/#{@section.id}']"
    assert_selector "input[type=hidden][name='block[settings][layout]'][value='three']", visible: :all
    assert_selector "select[name='block[settings][background]'] option[selected][value='none']"
    assert_selector "select[name='block[settings][width]'] option", count: 2
    assert_selector "button[data-action='admin--section#chooseLayout'][data-admin--section-layout-param]", count: 6, visible: :all
    assert_selector "button[data-admin--section-layout-param='three'][aria-current='true']", visible: :all
    assert_selector "#block-#{@section.id}-save-status"
  end

  test "the menu moves, duplicates, removes keeping the blocks, and deletes behind a dialog that counts them" do
    render_card

    assert_selector "button[data-move='up']", text: "Move up", visible: :all
    assert_selector "form[action$='/content_blocks/#{@section.id}/duplicate']", visible: :all
    assert_selector "form[action$='/content_blocks/#{@section.id}'] input[name='keep_blocks'][value='1']", visible: :all
    assert_selector "#section-#{@section.id}-delete-count", text: "This also deletes the 2 blocks in it.", visible: :all
  end

  test "a viewer who can't edit the page gets no form controls, no menu and no handle" do
    outline = BlockOutline.new(@page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-card__handle"
    assert_no_selector "[aria-label='Section actions']"
    assert_selector "fieldset[disabled] select[name='block[settings][background]']"
    assert_no_selector "form[data-controller~='admin--autosave']"
  end
```

  Integration:

```ruby
  test "a narrower layout answers with the lanes redrawn, the folded blocks' headings and the count" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    moved = @page.content_blocks.create!(block_type: "image", section: section, section_column: 3, position: 0)

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "two", background: "none", width: "content" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal 2, moved.reload.section_column
    assert_includes response.body, %(target="section-#{section.id}-lanes")
    assert_includes response.body, %(target="block-#{moved.id}-panel-title")
    assert_includes response.body, "Image · column 2"
    assert_includes response.body, "2 columns"
  end

  test "a stale save of a section is refused with a 409 and folds nothing" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    moved = @page.content_blocks.create!(block_type: "image", section: section, section_column: 3, position: 0)
    base = section.updated_at.iso8601(6)
    travel(1.minute) { ContentBlocks::Save.call(section, attributes: { settings: { "background" => "tinted" } }, actor: nil) }

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "one" } }, base_updated_at: base }, as: :turbo_stream

    assert_response :conflict
    assert_equal 3, moved.reload.section_column
  end

  test "removing a section and keeping its blocks puts their cards where the section was" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    kept = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    delete "#{blocks_path}/#{section.id}", params: { keep_blocks: 1 }, as: :turbo_stream

    assert_response :success
    assert_nil kept.reload.section_id
    assert_includes response.body, %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(section)}")
    assert_includes response.body, %(id="#{ActionView::RecordIdentifier.dom_id(kept)}")
    assert_includes response.body, "admin-block-card"
  end

  test "deleting a section removes its card, and deleting a block in a section removes its tile and panel and recounts" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    a = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 1)

    delete "#{blocks_path}/#{a.id}", as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(action="remove" target="#{ActionView::RecordIdentifier.dom_id(a)}")
    assert_includes response.body, %(action="remove" target="block-#{a.id}-panel")
    assert_includes response.body, "1 block"

    delete "#{blocks_path}/#{section.id}", as: :turbo_stream
    assert_response :success
    assert_empty @page.content_blocks.reload
  end
```

  System (`sections_test.rb`):

```ruby
  test "choosing a narrower layout folds the second lane into the first without losing the open form" do
    open_editor
    find(face(@right)).click
    fill_in id: caption(@right), with: "Typed before the fold"

    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Layout']").click
    find("button[data-admin--section-layout-param='one']").click

    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 1
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
    assert_selector panel(@right), text: "Image · column 1"
    assert_selector "#section-#{@section.id}-summary", text: "1 column · 2 blocks"
    assert_writes_settled
    assert_equal [ 1, "Typed before the fold" ], @right.reload.then { |block| [ block.section_column, block.caption ] }
    assert_field caption(@right), with: "Typed before the fold"
  end

  test "background and width are saved from the header" do
    open_editor

    select "Tinted", from: "block-#{@section.id}-background"
    select "Full width", from: "block-#{@section.id}-width"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_equal %w[tinted full], @section.reload.settings.values_at("background", "width")
  end

  test "Remove section, keep blocks turns the tiles into cards in reading order" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"

    assert_no_selector ".admin-section-card"
    assert_equal [ @left.id, @right.id ], page.all("#content-blocks-list > .admin-block-card").map { |card| card["data-block-id"].to_i }
    assert_empty @page.content_blocks.where(block_type: "section")
  end

  test "Delete section and its blocks asks first, naming how many blocks go with it" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Section actions']").click
    press "Delete section and its blocks…"

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Delete section" }

    assert_no_selector ".admin-section-card"
    assert_empty @page.content_blocks.reload
  end

  test "the section's name collapses it to one line" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-expanded]", text: "Section").click

    assert_no_selector "#section-#{@section.id}-lanes"
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 2 blocks"
  end
```

- [ ] **Step 2: Run them, expect failure.**

- [ ] **Step 3: The header form.** In `SectionCardComponent`, between the name and the menu, for every viewer (inside `<fieldset disabled class="contents admin-view-only">` and with no `admin--autosave` data when not editable, as `BlockCardComponent` does):
  - the form (`form_with url:, method: :patch, id: "section-<id>-form", class: "flex flex-wrap items-center gap-2", data: form_data`), holding the base field partial, the hidden layout input, and:
  - **Layout:** `Admin::MenuComponent.new(label: t(".layout_label"), aria_label: t(".layout"), align: :left, close_on_select: true)` with one item per `BlockTypes::Section::LAYOUTS` entry: `<button type="button" class="admin-layout-choice ..." aria-current="true|false" data-action="admin--section#chooseLayout" data-admin--section-layout-param="<name>">` containing a diagram and `<span class="sr-only"><%= t(".layouts.#{name}") %></span>`. The diagram is `<span class="admin-layout-diagram" aria-hidden="true">` with one `<span style="flex: <weight>">` per weight; `.admin-layout-diagram { display: flex; gap: 2px; width: 3rem; height: 1.25rem; }` and `.admin-layout-diagram > span { background: var(--cs-line-strong); border-radius: 1px; }`. The menu's button shows the current layout's diagram and the word.
  - **Background** and **Width:** `select_tag "block[settings][background]", options_for_select(BlockTypes::Section::BACKGROUNDS.map { |value| [ t(".backgrounds.#{value}"), value ] }, current), id: "block-<id>-background", class: setup_select_class, "aria-label": t(".background")`, and the same for width.
  - the three error slots (the `admin/shared/field_errors` partial with `Admin::FieldComponent.error_id(error_prefix, name)` and no messages), and `Admin::SaveStatusComponent.new(id: "block-<id>-save-status", state: :idle, live: page.live?)`.

  Keys under `section_card`: `layout: "Layout"`, `layout_label: "Layout"`, `layouts: { one: "One column", two: "Two columns", three: "Three columns", four: "Four columns", one_two: "One third, two thirds", two_one: "Two thirds, one third" }`, `background: "Background"`, `backgrounds: { none: "No background", tinted: "Tinted", strong: "Strong" }`, `width: "Width"`, `widths: { content: "Content width", full: "Full width" }`.

  In `section_controller.js`:

```js
  // The layout menu's pick (sections spec §4.1). The menu is a widget over a
  // hidden input of the section's own autosave form, so the pick is saved the
  // way every field is -- with the section's `base_updated_at`, through the
  // write queue -- and sent at once rather than after the debounce: a layout
  // is one deliberate choice, and its answer redraws the lanes.
  chooseLayout(event) {
    const form = this.element.querySelector("form[id$='-form']")
    const input = form?.querySelector("input[name='block[settings][layout]']")
    if (!input || input.value === event.params.layout) return

    input.value = event.params.layout
    this.application.getControllerForElementAndIdentifier(form, "admin--autosave")?.saveNow()
  }
```

- [ ] **Step 4: `update` for a section.** After the streams are built and before `render`, when `block.container?`:

```ruby
      # A section's save can move blocks (a narrower layout folds its last
      # columns, `ContentBlocks::Save#fold_removed_columns`): the lanes are
      # redrawn from the server -- tiles only, so no form is replaced -- and
      # every block's panel heading is rewritten, since it names the column.
      streams.concat(section_structure_streams(result.record)) if block.container? && result.ok?
```

```ruby
    def section_structure_streams(section)
      titles = section.section_blocks.reset.map do |inner|
        turbo_stream.update(Admin::BlockCardComponent.panel_title_id(inner),
          html: Admin::BlockCardComponent.new(page: @page, block: inner, locale: admin_locale, placement: :panel).panel_title)
      end
      [ section_lanes_stream(section), *titles, *section_count_streams(section), layout_menu_stream(section) ]
    end
```

  `layout_menu_stream` replaces the menu's button and items (`section-<id>-layout-menu`, a wrapper id the card puts around the menu) so `aria-current` and the button's diagram follow; make `panel_title` public. The tiles that `section_lanes_stream` redraws must keep the open one marked: `BlockTileComponent`'s `aria-expanded` is rendered `false`, so `admin--section#tileTargetConnected` also sets `aria-expanded="true"` on the face of the tile whose id is `this.openId`. Add that line and its sentence to the controller's comment.

- [ ] **Step 5: The menu and the deletes.** In the header, for an editable viewer, `Admin::MenuComponent.new(label: "⋯", aria_label: t(".actions"), close_on_select: true)` with: Move up and Move down (the same buttons as a block card's: `data-move`, `click->admin--blocks#moveUp|moveDown`, `disabled` from `first:`/`last:`), Duplicate (`button_to t(".duplicate"), duplicate_path, method: :post`), a separator, `button_to t(".remove_keep"), destroy_path, method: :delete, params: { keep_blocks: 1 }`, and `tag.button t(".delete"), type: "button", data: dialog_trigger(delete_dialog_id)` in `text-danger-ink`. After the body, `Admin::ConfirmDialogComponent.new(destructive: true, id: "delete-section-<id>", title: t(".delete_title"), body: t(".delete_body"))` with a `details` slot holding `<p id="section-<id>-delete-count">` (`t(".delete_count", count:)`, empty when the section holds nothing) and a confirm action that is a `form_with url: destroy_path, method: :delete` around a `:danger` submit `t(".delete_confirm")`. Keys: `actions: "Section actions"`, `move_up: "Move up"`, `move_down: "Move down"`, `duplicate: "Duplicate"`, `remove_keep: "Remove section, keep blocks"`, `delete: "Delete section and its blocks…"`, `delete_title: "Delete this section?"`, `delete_body: "Blocks don’t go to the trash. This can’t be undone."`, `delete_count: { one: "This also deletes the %{count} block in it.", other: "This also deletes the %{count} blocks in it." }`, `delete_confirm: "Delete section"`. `section_count_streams` gains the replace of `delete_count_id(section)`.

  `destroy`:

```ruby
    def destroy
      block = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless block

      section = block.section
      kept = block.container? && params[:keep_blocks].present? ? block.section_blocks.to_a : []
      result = ContentBlocks::Destroy.call(block, keep_blocks: params[:keep_blocks].present?)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      render turbo_stream: [ *removal_streams(block, kept, section), *page_base_streams ]
    end
```

```ruby
    # What leaves the screen with a deleted block: a top-level card; a tile
    # with its panel, and its section recounted; or a section's card --
    # replaced, when its blocks were kept, by their cards in the order they
    # now have at the top level.
    def removal_streams(block, kept, section)
      id = ActionView::RecordIdentifier.dom_id(block)
      if section
        [ turbo_stream.remove(id), turbo_stream.remove(Admin::BlockCardComponent.panel_id(block)), *section_count_streams(section) ]
      elsif kept.any?
        cards = kept.map { |lifted| render_to_string(card_for(lifted.reload)) }
        [ turbo_stream.replace(id, html: helpers.safe_join(cards)) ]
      else
        [ turbo_stream.remove(id) ]
      end
    end
```

  `admin--blocks#refreshMoveState` already runs when the list's children change, so the first and last cards' Move items correct themselves.

- [ ] **Step 6: Run** components, `test/integration/admin`, `test/lib`, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{sections,blocks,changed_elsewhere}_test.rb"`. Expected: PASS.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: a section's header sets its layout, background and width, and its menu duplicates, removes or deletes it" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 7: Moving by drag — within a lane, between lanes, out of a section and into one

**Spec:** §4.4 (drag; "A lane does not accept a section"; the write queue), §6 (a refused move reloads the list), D6, D8, Q5. **Read first:** all of `app/javascript/controllers/admin/blocks_controller.js` (its comments are the specification of `reorder`, `restoreTo` and `putBack`), `app/javascript/autosave/order_request.js`, the "write queue" part of `docs/reference/save-rule-and-write-queue.md`, `test/system/admin/unsaved_order_test.rb`.

**Files:**
- Modify: `app/javascript/controllers/admin/blocks_controller.js`, `app/components/admin/editor_screen/block_tile_component.html.erb` (the grip), `app/controllers/admin/content_blocks_controller.rb` (`reorder`), `app/helpers/admin/messages_helper.rb` or the blocks section's own `data-messages` in `app/views/admin/pages/show.html.erb`, `app/assets/tailwind/content-spiel.tailwind.css`, `config/locales/admin/components.en.yml`
- Test: `test/integration/admin/content_blocks_test.rb`, `test/system/admin/sections_test.rb`

**Interfaces:**
- Consumes: the reorder wire format and `ContentBlocks::Reorder` (Task 4); `tile_streams`, `section_count_streams`, `card_for`, `blocks_list_stream` (Tasks 2, 5); lanes as `data-admin--blocks-target="lane"` with `data-section-id` and `data-column`, tiles as `data-admin--blocks-target="tile"` (Task 2).
- Produces (in `admin--blocks`):
  - `static targets = ["card", "list", "lane", "tile", "announcer"]`.
  - `containers() -> Element[]` (the list, then every lane); `itemsOf(container) -> Element[]` (its direct children that carry `data-block-id`); `placeOf(container) -> { section_id: string|null, column: string|null }`; `itemFor(event) -> Element` (the nearest card or tile).
  - `move(item, from, before) -> Promise` replacing `reorder(before)` as the one sender: `item` the moved element (null for "send the list's order as it is"), `from` the container it left, `before` a snapshot (`Map<Element, Element[]>`) taken before the DOM move. `reorder(before)` stays as a thin wrapper (`this.move(null, null, before && new Map([[this.listTarget, before]]))`) because `drop`, the Undo path and two system tests call it.
  - `snapshot() -> Map<Element, Element[]>`.
  - Message key `components.editor_screen.section_card.unsaved_move`.
- Produces (server): the reorder answer for a move between containers carries the moved block's new representation; a structural refusal carries the whole list.

- [ ] **Step 1: Write the failing tests.** Integration:

```ruby
  test "a move into a column answers with the tile and its panel in place of the card, and no Undo" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    block = @page.content_blocks.create!(block_type: "image", position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 1, moved_from: { block.id => { section_id: "", column: "" } } }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(block)}")
    assert_includes response.body, "admin-block-tile"
    assert_includes response.body, %(target="section-#{section.id}-panels")
    assert_includes response.body, "1 block"
    assert_not_includes response.body, "Undo"
  end

  test "a move out of a section answers with the card in place of the tile and removes the panel" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    block = @page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)

    patch "#{blocks_path}/reorder", params: { ids: [ section.id, block.id ], moved_from: { block.id => { section_id: section.id, column: 1 } } }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(action="remove" target="block-#{block.id}-panel")
    assert_includes response.body, %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(block)}")
    assert_includes response.body, "admin-block-card"
    assert_includes response.body, "0 blocks"
  end

  test "a move between lanes of one section rewrites only the panel's heading" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    block = @page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 2, moved_from: { block.id => { section_id: section.id, column: 1 } } }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "Image · column 2"
    assert_not_includes response.body, %(target="#{ActionView::RecordIdentifier.dom_id(block)}")
  end

  test "a refused move answers 422 with the reason and the whole list as the server has it" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    block = @page.content_blocks.create!(block_type: "image", position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 3, moved_from: { block.id => { section_id: "", column: "" } } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, ContentBlocks::Reorder::NO_COLUMN
    assert_includes response.body, %(action="update" target="content-blocks-list")
  end

  test "a top-level reorder still offers Undo" do
    a = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    b = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ b.id, a.id ] }, as: :turbo_stream

    assert_includes response.body, "Undo"
  end
```

  System (`sections_test.rb`). A drag is driven the way `blocks_test.rb`'s "dragging a block's handle reorders the list" drives it: the element is moved in the DOM as a drop leaves it, then the controller's own sender is called, which is the code a drop's `onEnd` runs. One test below uses the pointer for real.

```ruby
  def blocks_controller = "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller~=\"admin--blocks\"]'), 'admin--blocks')"

  # Moves `block`'s element to the end of `target` (a CSS selector of a lane or
  # the list) and sends it, as a drop there does.
  def drop_into(block, target)
    page.execute_script(<<~JS)
      const controller = #{blocks_controller}
      const item = document.querySelector('[data-block-id="#{block.id}"]:not([data-admin--section-target="panel"])')
      const from = item.parentElement
      const before = controller.snapshot()
      document.querySelector(#{target.to_json}).append(item)
      controller.move(item, from, before)
    JS
  end

  test "a tile dropped in another lane is saved there and its form says the new column" do
    open_editor
    drop_into(@left, "#section-#{@section.id}-lane-2")

    assert_eventually { @left.reload.section_column == 2 }
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 2"
  end

  test "a tile dropped in the page's list becomes a card with its form, and the section recounts" do
    open_editor
    drop_into(@left, "#content-blocks-list")

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}'] form[data-controller~='admin--autosave']"
    assert_no_selector panel(@left), visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 1 block"
    assert_nil @left.reload.section_id
  end

  test "a card dropped in a lane becomes a tile there" do
    card = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    drop_into(card, "#section-#{@section.id}-lane-1")

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile[data-block-id='#{card.id}']"
    assert_selector "#block-#{card.id}-panel", visible: :all
    assert_equal [ @section.id, 1, 1 ], card.reload.then { |b| [ b.section_id, b.section_column, b.position ] }
  end

  # Review Focus 4.
  test "an edit still inside its debounce is saved before its block is moved out of the section" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Typed, then dragged out"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    drop_into(@left, "#content-blocks-list")

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    assert_writes_settled
    assert_equal "Typed, then dragged out", @left.reload.caption
    assert_field caption(@left), with: "Typed, then dragged out"
  end

  # Review Focus 4.
  test "a block whose form was refused stays where it is, with its text, and a toast says why" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8

    drop_into(@left, "#content-blocks-list")

    assert_selector "#toasts", text: "Reload or fix this block before moving it"
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile[data-block-id='#{@left.id}']"
    assert_field caption(@left), with: "Mine, refused"
    assert_equal @section.id, @left.reload.section_id
  end

  # Review Focus 5.
  test "a drop into a column another tab has folded away is refused and the list is redrawn" do
    open_editor
    ContentBlocks::Save.call(@section, attributes: { settings: { "layout" => "one" } }, actor: nil)

    drop_into(@left, "#section-#{@section.id}-lane-2")

    assert_selector "#content-blocks-alert", text: "That section or column no longer exists"
    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 1
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
  end

  test "a section's card can't be dropped into a lane" do
    other = @page.content_blocks.create!(block_type: "section", position: 1)
    open_editor

    allowed = page.evaluate_script(<<~JS)
      (() => {
        const controller = #{blocks_controller}
        const lane = document.getElementById("section-#{@section.id}-lane-1")
        const card = document.querySelector('[data-block-id="#{other.id}"]')
        return controller.accepts(lane, card)
      })()
    JS

    assert_equal false, allowed
  end

  test "the pointer drags a tile from one lane to the other" do
    open_editor
    grip = find("#{tile(@left)} .admin-block-tile__grip")
    target = find("#section-#{@section.id}-lane-2")
    from = grip.native.node.find_position
    to = target.native.node.find_position

    mouse = page.driver.browser.mouse
    mouse.move(x: from[0], y: from[1])
    mouse.down
    6.times do |step|
      mouse.move(x: from[0] + ((to[0] - from[0]) * (step + 1) / 6.0), y: from[1] + ((to[1] - from[1]) * (step + 1) / 6.0))
      sleep 0.08 # sleep: SortableJS samples the pointer on a 50 ms timer of its own; the pointer rests one tick plus margin per step
    end
    await_js "!!document.querySelector('#section-#{@section.id}-lane-2 > .admin-drag-ghost')"
    mouse.up

    assert_eventually { @left.reload.section_column == 2 }
  end
```

  (For the pointer test, read how `test/system/admin/tree_test.rb` gets an element's coordinates for `drag_pointer` and use the same call; `drag_pointer` itself only walks down a column, which is why the walk is written out here.)

- [ ] **Step 2: Run them, expect failure.**

- [ ] **Step 3: The reorder action.** After `result = ContentBlocks::Reorder.call(...)`:

```ruby
      moved = @page.content_blocks.where(id: params.fetch(:moved_from, {}).keys).to_a if result.ok?
```

  and the streams:
  - ok and nothing moved between containers and no `section_id`: today's answer, Undo included (`reorder_undo_streams`).
  - ok otherwise: the status, the page base, `*move_streams(moved, params[:moved_from])`, and no Undo toast (Q5).
  - a denial: today's 403.
  - any other failure: 422 with the status, `picker_error_stream(result.errors)` and, when the request named a section or a `moved_from`, `blocks_list_stream` (spec §6: "the list reloads").

```ruby
    # One moved block's new face (sections spec §4.4): a card that went into a
    # column becomes a tile with its panel; a tile that left its section
    # becomes a card and its panel goes; a tile that changed lanes inside its
    # section keeps both, and only its panel's heading (which names the
    # column) is rewritten. The browser has already moved the element, so the
    # replace lands where it was dropped. Every section that gained or lost a
    # block is recounted.
    def move_streams(moved, origins)
      outline = BlockOutline.new(@page.content_blocks.reset)
      sections = outline.sections.index_by(&:id)
      touched = []

      streams = moved.flat_map do |block|
        from = origins.dig(block.id.to_s, "section_id").presence&.to_i
        touched.push(from, block.section_id)
        dom = ActionView::RecordIdentifier.dom_id(block)
        if from == block.section_id
          [ turbo_stream.update(Admin::BlockCardComponent.panel_title_id(block), html: panel_component(block).panel_title) ]
        elsif block.section_id
          [ turbo_stream.remove(Admin::BlockCardComponent.panel_id(block)),
            turbo_stream.append(Admin::EditorScreen::SectionCardComponent.panels_id(block.section), panel_component(block)),
            turbo_stream.replace(dom, tile_component(block)) ]
        else
          [ turbo_stream.remove(Admin::BlockCardComponent.panel_id(block)), turbo_stream.replace(dom, card_for(block)) ]
        end
      end

      streams + touched.compact.uniq.filter_map { |id| sections[id] }.flat_map { |section| section_count_streams(section) }
    end
```

  with `panel_component(block)` and `tile_component(block)` extracted from Task 5's `tile_streams` (which now calls them).

- [ ] **Step 4: `admin--blocks`.** The changes, each with its comment written at the density of the file:

  - **Containers.** `containers() { return [ this.listTarget, ...this.laneTargets ] }`; `itemsOf(container) { return Array.from(container.children).filter((child) => child.dataset.blockId) }`; `placeOf(container) { return { section_id: container.dataset.sectionId || null, column: container.dataset.column || null } }`; `itemFor(event) { return event.currentTarget.closest('[data-admin--blocks-target="card"], [data-admin--blocks-target="tile"]') }`. `cardFor` stays for the top-level keyboard path.
  - **Sortables.** The list's `Sortable.create` gains `group: { name: "blocks", put: true }`, `draggable: "[data-block-id]"`, `handle: ".admin-block-card__handle, .admin-block-tile__grip"`. `laneTargetConnected(lane)` creates one per lane with the same look and fallback options, `group: { name: "blocks", put: (to, _from, dragged) => this.accepts(to.el, dragged) }`, and stores it in a `WeakMap`; `laneTargetDisconnected(lane)` destroys it (a redrawn lanes row is new elements). `accepts(lane, dragged) { return !dragged.hasAttribute("data-container") }`: a lane does not accept a section. Every Sortable shares `onStart: () => { this.makeCloneInert(); this.dragSnapshot = this.snapshot() }` and `onEnd: (event) => this.move(event.item, event.from, this.dragSnapshot)`.
  - **`snapshot()`** returns `new Map(this.containers().map((container) => [ container, this.itemsOf(container) ]))`.
  - **`move(item, from, before)`** replaces the body of `reorder`. What changes from `reorder`, and nothing else:

```js
  async move(item, from, before = null) {
    this.refreshMoveState()
    const to = item ? item.parentElement : this.listTarget
    const crossing = Boolean(item && from && from !== to)
    if (before && !this.restoreTo) this.restoreTo = before
    this.reordersQueued = (this.reordersQueued || 0) + 1
    // A move between containers re-renders the moved block (card to tile, or
    // back): its form is replaced. So what any form on the screen still holds
    // is sent first -- queued ahead of this move -- and the move is given up
    // if the moved block's own form then did not end clean (see the task).
    if (crossing) this.sendHeldEdits()
    const moved = crossing ? { [item.dataset.blockId]: this.placeOf(from) } : {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    await enqueue(async (isCurrent) => {
      if (crossing && !this.formClean(item.dataset.blockId)) {
        this.reordersQueued -= 1
        if (isCurrent()) { this.putBack(); this.toast("components.editor_screen.section_card.unsaved_move") }
        return
      }
      const sent = this.snapshot()
      const answer = await sendOrder(this.reorderUrlValue, {
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken,
          "X-Page-Base-Updated-At": document.getElementById(this.constructor.pageBaseId)?.value || ""
        },
        body: JSON.stringify({ ids: this.itemsOf(to).map((element) => element.dataset.blockId), ...this.placeOf(to), moved_from: moved })
      })
      this.reordersQueued -= 1
      if (!isCurrent()) return

      if (answer.outcome === "answered") {
        syncBases(answer.text, [ this.constructor.pageBaseId ])
        Turbo.renderStreamMessage(answer.text)
        if (answer.ok) {
          this.restoreTo = this.reordersQueued > 0 ? sent : null
          return
        }
      }

      this.putBack()
      if (answer.outcome !== "answered") orderErrorToast(answer.outcome, "toast-order-error")
    }, { generation: this.generation }).catch(() => {})
  }
```

    `sendHeldEdits()` calls `saveNow()` on the `admin--autosave` controller of every `form[data-controller~='admin--autosave']` inside `this.element`. `formClean(id)` finds the block's form (inside its card, or inside `#block-<id>-panel`) and returns its autosave controller's `clean()`, or `true` when there is none. `toast(key)` clones `#toast-error-template` exactly as `orderErrorToast` does, with `messages(this.element).t(key)`; export a small `errorToast(text, id)` from `autosave/order_request.js` and have `orderErrorToast` use it, so there is one copy of the cloning.
  - **`putBack()`** restores every container of `restoreTo` instead of one list: for each `[container, items]` in the map whose `container.isConnected`, the items still in the document are put back into that container in their old order (`container.append(...items.filter((element) => element.isConnected))`, then any item of the container that was not in the snapshot keeps its place after them). Keep the three sentences of the existing comment about cards streamed in since and a list an Undo redrew; say that a redrawn list or lanes row is new elements, so its entries are skipped by `isConnected`.
  - **`refreshMoveState()`** runs per container over `itemsOf(container)`, and the `MutationObserver` observes `this.element` with `{ childList: true, subtree: true }` filtered to mutations whose target is the list or a lane.
  - **`moveUp` / `moveDown`** use `itemFor(event)` and `itemsOf(item.parentElement)`, take `this.snapshot()` before the DOM move, and call `this.move(item, item.parentElement, before)`; `moved(card, before)` keeps focusing the handle (a tile has none until Task 8 gives it a menu, where focus goes to the menu's button).
  - **The keyboard path** (`key`, `pickUp`, `step`, `drop`, `cancel`) is untouched: it is the top-level cards' and still calls `reorder`.

- [ ] **Step 5: The grip and the look.** `BlockTileComponent`, for an editable viewer, before the face: `<span class="admin-block-tile__grip cursor-grab select-none px-1 text-meta" aria-hidden="true">⠿</span>` (D9: pointer only). CSS: `.admin-section-lane > [data-admin--blocks-target="lane"]` keeps its `min-height` so an empty lane is a drop target; `.admin-section-lane > [data-admin--blocks-target="lane"] > .admin-block-card { font-size: inherit; }` needs nothing more: a card resting in a lane for the moment before its answer is acceptable. Message key under `section_card`: `unsaved_move: "Reload or fix this block before moving it."`, handed to the script by adding `components.editor_screen.section_card.unsaved_move` to a `data-messages` attribute on the blocks `<section>` in `app/views/admin/pages/show.html.erb` (`messages_data(...)`), not to `SCRIPT_MESSAGES` (only this screen needs it).

- [ ] **Step 6: Run** `test/integration/admin`, `test/lib`, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{sections,blocks,unsaved_order,autosave,tree}_test.rb"`. Expected: PASS, with `blocks_test.rb` and `unsaved_order_test.rb` unedited: they are the proof that a page without sections reorders as before.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: a block is dragged within a lane, between lanes, out of a section and into one, through the write queue" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 8: Every move from the menu, by keyboard

**Spec:** §4.4 (the ⋯ menu), §1 ("Everything a pointer can do in the editor has a keyboard path"), §4.2, D9, D10. **Read first:** `Admin::MenuComponent` and `admin--menu`, `Admin::DialogComponent` and `Admin::DialogHelper#dialog_trigger`, `admin--blocks#focusCopy`.

**Files:**
- Create: `app/components/admin/editor_screen/move_dialog_component.{rb,html.erb}`
- Modify: `app/components/admin/editor_screen/block_tile_component.{rb,html.erb}`, `app/components/admin/block_card_component.html.erb` (one menu item), `app/javascript/controllers/admin/blocks_controller.js`, `app/views/admin/pages/show.html.erb`, `config/locales/admin/components.en.yml`, `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/components/admin/editor_screen/block_tile_component_test.rb` (new), `test/components/admin/block_card_component_test.rb`, `test/system/admin/sections_test.rb`

**Interfaces:**
- Consumes: `move(item, from, before)`, `snapshot()`, `itemsOf`, `itemFor`, `refreshMoveState` (Task 7); the delete dialog `delete-block-<id>` that a `:panel` block card renders (Task 2); `ContentBlocks::Duplicate` behind the duplicate route (Task 4).
- Produces:
  - A tile's menu (`aria_label: t(".actions")`, "Block actions"): Move up, Move down (`data-move`, `admin--blocks#moveUp|moveDown`), "Move to column…" (`data-move="column"`, `admin--blocks#askWhere`), "Move out of section" (`admin--blocks#moveOut`), Duplicate, a separator, "Delete block…".
  - A top-level, non-container card's menu gains "Move into section…" (`data-move="into"`, `admin--blocks#askWhere`), disabled while the page has no section.
  - `Admin::EditorScreen::MoveDialogComponent.new`: `#move-block-dialog`, holding `<select data-admin--blocks-target="destination">` and a Move button (`admin--blocks#moveTo`).
  - `admin--blocks`: targets `destination`; actions `askWhere`, `moveTo`, `moveOut`.

- [ ] **Step 1: Write the failing tests.** Component tests: a tile for an editable viewer has the six items and a view-only one has no menu and no grip; a top-level rich-text card has "Move into section…" and a section card does not. System:

```ruby
  def open_menu_by_keyboard(scope)
    button = find("#{scope} button[aria-label='Block actions']")
    button.send_keys(:enter)
    button
  end

  test "Move down and Move up reorder a lane from the keyboard" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor

    open_menu_by_keyboard(tile(@left))
    find("#{tile(@left)} [role=menu] button", text: "Move down").send_keys(:enter)

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ below.id, @left.id ] }
    assert_selector "#{tile(@left)} button[data-move='down'][disabled]", visible: :all
  end

  test "Move to column… moves a tile to the end of the chosen lane" do
    open_editor

    open_menu_by_keyboard(tile(@left))
    find("#{tile(@left)} [role=menu] button", text: "Move to column…").send_keys(:enter)
    within("#move-block-dialog") do
      assert_selector "option", count: 1
      select "Column 2", from: "move-block-destination"
      press "Move"
    end

    assert_eventually { @left.reload.section_column == 2 }
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    assert_selector "#section-#{@section.id}-lane-2 > .admin-block-tile", count: 2
  end

  test "Move out of section puts the block right after the section as a card, with focus on its menu" do
    open_editor

    open_menu_by_keyboard(tile(@left))
    find("#{tile(@left)} [role=menu] button", text: "Move out of section").send_keys(:enter)

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    assert_equal [ @section.id, @left.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_eventually { page.evaluate_script("document.activeElement?.closest('[data-block-id]')?.dataset.blockId") == @left.id.to_s }
  end

  test "Move into section… offers every column of every section, and is disabled without one" do
    card = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "section", position: 2, settings: { "layout" => "three" })
    open_editor

    open_menu_by_keyboard("##{ActionView::RecordIdentifier.dom_id(card)}")
    find("##{ActionView::RecordIdentifier.dom_id(card)} [role=menu] button", text: "Move into section…").send_keys(:enter)
    within("#move-block-dialog") do
      assert_selector "option", count: 5
      select "Section 2 · column 3", from: "move-block-destination"
      press "Move"
    end

    assert_eventually { card.reload.then { |b| [ b.section_id, b.section_column ] } == [ second.id, 3 ] }
    assert_selector "#section-#{second.id}-lane-3 > .admin-block-tile[data-block-id='#{card.id}']"

    plain = create_page(title: "No sections")
    plain.content_blocks.create!(block_type: "image", position: 0)
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers
    assert_selector "button[data-move='into'][disabled]", visible: :all
  end

  test "Duplicate and Delete from a tile's menu" do
    open_editor

    find("#{tile(@left)} button[aria-label='Block actions']").click
    within(tile(@left)) { press "Duplicate" }
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
    assert_selector "#section-#{@section.id}-summary", text: "3 blocks"

    find("#{tile(@left)} button[aria-label='Block actions']").click
    within(tile(@left)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }
    assert_no_selector tile(@left)
    assert_no_selector panel(@left), visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "2 blocks"
  end
```

- [ ] **Step 2: Run them, expect failure.**

- [ ] **Step 3: The tile's menu.** `BlockTileComponent`, after the face, for an editable viewer: `Admin::MenuComponent.new(label: "⋯", aria_label: t(".actions"), close_on_select: true)` with the items listed under Interfaces; Duplicate is `button_to t(".duplicate"), duplicate_path, method: :post`; "Delete block…" is `data: dialog_trigger("delete-block-#{block.id}")`, the dialog the block's panel already renders. A tile of an unregistered type (`block.definition.nil?`) has "Delete block…" as its only item (spec §6). Keys under `admin.components.editor_screen.block_tile`: `actions: "Block actions"`, `move_up: "Move up"`, `move_down: "Move down"`, `move_to_column: "Move to column…"`, `move_out: "Move out of section"`, `duplicate: "Duplicate"`, `delete: "Delete block…"`. In `BlockCardComponent`'s menu, after Move down, for `list?` and `!block.container?`: `tag.button t(".move_into"), type: "button", disabled: true, class: menu_item_class, data: { move: "into", action: "click->admin--blocks#askWhere" }` (`move_into: "Move into section…"`); `refreshMoveState` enables it.

  The duplicate answer for a block in a section: `Admin::ContentBlocksController#insertion_stream` gets its section branch here: `tile_streams` puts the copy at the end of the lane, so for a copy with a `section_id` it returns `[ turbo_stream.append(panels_id, panel_component(copy)), turbo_stream.after(dom_id(source), tile_component(copy)), *section_count_streams(copy.section) ]`. Add the integration test: duplicating a block in a column answers with a tile `after` its source and a panel.

- [ ] **Step 4: The dialog.** `MoveDialogComponent` renders `Admin::DialogComponent.new(id: "move-block-dialog", title: t(".title"))` with a labelled `<select id="move-block-destination" class="<%= setup_select_class %>" data-admin--blocks-target="destination">` (empty: the script fills it) and a footer with Cancel (the dialog's own) and `Admin::ButtonComponent.new(label: t(".move"), variant: :primary, data: { action: "admin--blocks#moveTo" })`. It is rendered once inside the blocks `<section>` in `app/views/admin/pages/show.html.erb`, for an editable viewer, and the `<section>`'s `data-messages` gains `components.editor_screen.move_dialog.column` and `.section_column`. Keys: `title: "Move block"`, `destination: "Move to"`, `move: "Move"`, `column: "Column %{column}"`, `section_column: "Section %{section} · column %{column}"`. If `<dialog>` content rendered inside `#content` is a problem for this layout (the reference says dialogs live in the layout, outside `#content`, because forms can't nest: this one holds no form), keep it in the page; otherwise follow the layout's pattern and reach the select by id instead of by target.

- [ ] **Step 5: The script.**

```js
  // "Move to column…" on a tile and "Move into section…" on a card open the
  // one Move dialog (sections spec §4.4). Its choices are read from the
  // screen as it is NOW -- sections are added and removed without the other
  // cards being redrawn, so a list the server rendered would go stale: for a
  // tile, the other columns of its own section; for a card, every column of
  // every section, numbered as they stand in the list.
  askWhere(event) {
    const item = this.itemFor(event)
    const own = item.closest('[data-admin--blocks-target="lane"]')
    const lanes = own ? this.laneTargets.filter((lane) => lane.dataset.sectionId === own.dataset.sectionId && lane !== own) : this.laneTargets
    const sections = this.cardTargets.filter((card) => card.hasAttribute("data-container")).map((card) => card.dataset.blockId)
    const text = messages(this.element)

    this.asking = item
    this.destinationTarget.replaceChildren(...lanes.map((lane) => {
      const option = document.createElement("option")
      option.value = lane.id
      option.textContent = own
        ? text.t("components.editor_screen.move_dialog.column", { column: lane.dataset.column })
        : text.t("components.editor_screen.move_dialog.section_column", { section: sections.indexOf(lane.dataset.sectionId) + 1, column: lane.dataset.column })
      return option
    }))
    document.getElementById("move-block-dialog").showModal()
  }

  moveTo() {
    const item = this.asking
    const lane = document.getElementById(this.destinationTarget.value)
    document.getElementById("move-block-dialog").close()
    if (!item?.isConnected || !lane) return
    this.relocate(item, () => lane.append(item))
  }

  // Out of its section: directly after the section's card in the page's list.
  moveOut(event) {
    const item = this.itemFor(event)
    const section = item.closest('[data-admin--blocks-target="card"]')
    this.relocate(item, () => section.after(item))
  }

  // The DOM move a drop would have made, then the same request.
  relocate(item, place) {
    const from = item.parentElement
    const before = this.snapshot()
    this.awaitingMoved = item.dataset.blockId
    place()
    this.move(item, from, before)
  }
```

  Import `messages` from `i18n/messages`. Open the dialog the way `admin--dialog` opens one if that controller exposes a function for it (so focus return and the backdrop rule are its own); `showModal()` directly is the fallback. `refreshMoveState` gains: `[data-move="into"]` is disabled unless a card with `data-container` exists; `[data-move="column"]` is disabled when the tile's section has one lane. **Focus:** a move between containers replaces the element, so the focus would fall to `<body>`: extend the observer's handler (beside `focusCopy`) so that when an element with `data-block-id === this.awaitingMoved` is added to the list or a lane, its ⋯ button (`button[aria-haspopup=menu]`) is focused and the note cleared; a move inside one section (no replace) focuses the same button right after `place()`.

- [ ] **Step 6:** Add `block_tile_component.{rb,html.erb}`'s new strings to the locale file, `move_dialog_component.{rb,html.erb}` to `CONVERTED`. Run components, `test/integration/admin`, `test/lib`, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{sections,blocks,dialogs_hang}_test.rb"`. Expected: PASS.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: every block move is in the menu — up, down, to a column, out of a section, into one" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 9: The translation view, small screens, unavailable types

**Spec:** §4.5, §4.6, §6 (the two "Unavailable type" cases), §1 (view only stays view only). **Read first:** `docs/reference/editors-and-translation-pair.md` (Translation pair, View only), `test/system/admin/translation_layout_test.rb`, `test/system/admin/view_only_test.rb`.

**Files:**
- Create: `app/components/admin/editor_screen/section_group_component.{rb,html.erb}`
- Modify: `app/components/admin/editor_screen/section_card_component.{rb,html.erb}` (`.for`, the unavailable form), `app/components/admin/editor_screen/section_lanes_component.{rb,html.erb}`, `app/services/content_blocks/destroy.rb`, `app/views/admin/pages/show.html.erb`, `app/controllers/admin/content_blocks_controller.rb` (`card_for`), `app/javascript/controllers/admin/blocks_controller.js` (`accepts`), `config/locales/admin/components.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/components/admin/editor_screen/section_group_component_test.rb` (new), `test/components/admin/editor_screen/section_card_component_test.rb`, `test/services/content_blocks/destroy_test.rb`, `test/system/admin/sections_test.rb`

**Interfaces:**
- Consumes: `Admin::BlockCardComponent` `placement: :group` (Task 2); `BlockOutline#blocks_in` (Task 1).
- Produces:
  - `Admin::EditorScreen::SectionCardComponent.for(page:, section:, outline:, locale:, **options)`: the group component on a translation tab, the card otherwise. The page view and the controller's `card_for` both call it, and both treat a block as a section when `block.container? || outline.blocks_in(block).any?` (a section whose type is gone still holds its blocks).
  - `Admin::EditorScreen::SectionGroupComponent.new(page:, section:, outline:, locale:, url_options: {}, editable: nil, **)`: `<div id="<dom_id(section)>" data-block-id data-container data-admin--blocks-target="card" class="admin-section-group">`, a heading, and a `:group` block card per block in reading order.
  - `ContentBlocks::Destroy` deletes or lifts what a block holds whether or not its type is still a container.

- [ ] **Step 1: Write the failing tests.** `destroy_test.rb`:

```ruby
  test "a section whose type is gone is still deleted with its blocks" do
    @section.update_columns(block_type: "gone/section")

    assert_difference -> { ContentBlock.count }, -4 do
      assert ContentBlocks::Destroy.call(@section.reload, actor: nil).ok?
    end
  end
```

  `section_group_component_test.rb`: on locale `"de"` (inside `with_locales(%w[en de], default: "en")`), a three-column section with a text in column 1, an image in column 3 and a second text in column 1 renders one `.admin-section-group` whose heading reads "Section", then three `.admin-block-card`s in the order column 1 first, column 1 second, column 3; no `.admin-block-tile`, no `[data-admin--section-target]`, no `.admin-block-card__handle` inside the group; the image card has its translated `alt` field as an `.admin-translation-pair`. `section_card_component_test.rb`:

```ruby
  test "a section whose type is gone is the Unavailable type card with its blocks listed under it" do
    @section.update_columns(block_type: "gone/section")
    render_card

    assert_selector ".admin-section-card.border-danger", text: "Unavailable type — gone/section"
    assert_selector ".admin-block-tile", count: 2
    assert_selector "[data-admin--blocks-target='lane'][data-no-drop]", minimum: 1
    assert_no_selector "form#section-#{@section.id}-form"
    assert_selector "button", text: "Delete block…", visible: :all
  end
```

  System (`sections_test.rb`):

```ruby
  test "on a translation tab a section is a heading over its blocks in reading order, each with its pair of fields" do
    with_locales(%w[en de], default: "en") do
      @left.update!(caption: "Left original")
      @right.update!(caption: "Right original")
      visit "/cs-studio/pages/#{@page.id}?locale=de"
      await_admin_controllers

      assert_selector ".admin-section-group", count: 1
      assert_no_selector ".admin-block-tile"
      cards = page.all(".admin-section-group > .admin-block-card").map { |card| card["data-block-id"].to_i }
      assert_equal [ @left.id, @right.id ], cards
      assert_selector "[data-block-id='#{@left.id}'] .admin-translation-pair", text: "Left original"

      fill_in id: "block-#{@right.id}-caption", with: "Rechts"
      page.execute_script("document.activeElement.blur()")
      assert_writes_settled
      assert_equal "Rechts", Mobility.with_locale(:de) { @right.reload.caption }
    end
  end

  test "below the width where the lanes fit side by side they stack, each under its column's label" do
    open_editor
    original = page.current_window.size
    page.current_window.resize_to(520, 900)

    assert_eventually do
      page.evaluate_script(<<~JS)
        (() => {
          const [first, second] = ["1", "2"].map((n) => document.getElementById("section-#{@section.id}-lane-" + n).getBoundingClientRect())
          return second.top >= first.bottom
        })()
      JS
    end
    assert_selector ".admin-section-lane__label", text: "Column 2"
  ensure
    page.current_window.resize_to(*original) if original
  end

  test "a block of a type that is gone is an Unavailable tile whose only action is Delete" do
    @left.update_columns(block_type: "gone/thing")
    open_editor

    assert_selector "#{tile(@left)}", text: "Unavailable type — gone/thing"
    find("#{tile(@left)} button[aria-label='Block actions']").click
    assert_equal [ "Delete block…" ], page.all("#{tile(@left)} [role=menu] button").map(&:text)
  end

```

  And in `test/system/admin/view_only_test.rb`, whose `setup` signs in `users(:reader)`:

```ruby
  test "a read-only user sees a section's tiles and can open a form, with nothing to change and nothing sent" do
    page_record = create_page(title: "Banded, hands off")
    section = page_record.content_blocks.create!(block_type: "section", position: 0)
    block = page_record.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers

    assert_selector ".admin-block-tile", count: 1
    assert_no_selector ".admin-block-tile__grip"
    assert_no_selector "[id^='block-picker-#{section.id}-']"
    assert_no_selector ".admin-section-card button[aria-label='Section actions']"
    find("##{ActionView::RecordIdentifier.dom_id(block)} .admin-block-tile__face").click
    assert_selector "#block-#{block.id}-panel fieldset[disabled]"
    assert_no_selector "#block-#{block.id}-panel form[data-controller~='admin--autosave']"
  end
```

  (If `users(:reader)` cannot read pages in the fixtures, this test is a 404: then build the viewer as that file's other page tests do, or grant `pages.read` in the test.)

- [ ] **Step 2: Run them, expect failure.**

- [ ] **Step 3: Destroy.** In `ContentBlocks::Destroy`: `inside = @block.section_blocks.to_a` for every block (a block that holds nothing has none) and `lock_owner(@block.owner) if @block.container? || inside.any?`, with a sentence saying a section whose type is no longer registered is no `container?` and still has to take its blocks with it.

- [ ] **Step 4: The translation view.** `SectionGroupComponent`'s template: the wrapper named under Interfaces, `<h3 class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= t(".heading") %></h3>` (`admin.components.editor_screen.section_group.heading: "Section"`), then `outline.blocks_in(section).each` rendering `Admin::BlockCardComponent.new(page:, block:, locale:, url_options:, editable:, placement: :group)`. The group is a `card` target with the section's `data-block-id`, so a reorder of the page's list on a translation tab still names the section; it has no handle and no menu, so it is not moved from that tab (the default-language tab is where structure is edited; one sentence in the component's comment). `SectionCardComponent.for` picks it when `locale.to_s != Locales.default`. In `app/views/admin/pages/show.html.erb` the loop is:

```erb
<% outline.top_level.each_with_index do |block, index| %>
  <% if block.container? || outline.blocks_in(block).any? %>
    <%= render Admin::EditorScreen::SectionCardComponent.for(page: @page, section: block, outline: outline, locale: admin_locale, url_options: admin_url_options, first: index.zero?, last: index == outline.top_level.size - 1, editable: blocks_editable) %>
  <% else %>
    <%= render Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, first: index.zero?, last: index == outline.top_level.size - 1, editable: blocks_editable) %>
  <% end %>
<% end %>
```

  and `card_for` in the controller makes the same choice. `Admin::TranslationScreen::TranslateAllComponent` already walks `record.content_blocks`, every block of the page, so "Suggest translations for N empty fields" counts a block in a column: assert it in `section_group_component_test.rb` or beside the component's own test with one line.

- [ ] **Step 5: The unavailable section.** In `SectionCardComponent`: `def unavailable? = section.definition.nil?`. When unavailable: `border-danger` instead of the framed look, the header is the label `t(".unavailable", type: section.block_type)` (`"Unavailable type — %{type}"`) in `text-danger-ink` and, for an editable viewer, `Admin::ButtonComponent.new(label: t(".delete_block"), variant: :danger_text, size: :small, data: dialog_trigger(delete_dialog_id))` (`delete_block: "Delete block…"`); no handle, no settings form, no menu; the sentence `t(".unavailable_hint")` (`"Its blocks are kept. Move them out or delete them."`); the delete dialog as in Task 6. `SectionLanesComponent`, for a section with `column_count.zero?`, renders one lane per distinct stored `section_column` of its blocks (so a tile's lane still says where the block really is, which `moved_from` needs), each with `data-no-drop` and no "+". `admin--blocks#accepts(lane, dragged)` becomes `!dragged.hasAttribute("data-container") && !lane.hasAttribute("data-no-drop")`, and `askWhere` leaves `data-no-drop` lanes out.

- [ ] **Step 6:** Add the group component's two files to `CONVERTED`. Run components, services, `test/lib`, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system TEST="test/system/admin/{sections,translation_layout,translations,view_only}_test.rb"`. Expected: PASS.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: a section in the translation view, on a narrow screen and when a type is gone" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 10: The public page — the grid, the bands, image sizes

**Spec:** §5 (all of it), §7 (Public page; Trash: a trashed image in a column), D11, D12, D13. **Read first:** `docs/reference/media.md` (the asset, `Media::PictureComponent`), `app/assets/tailwind/themes/default/tokens.css` and `theme.css`, `test/integration/design_tokens_test.rb`, `test/integration/public_theme_test.rb`, `test/integration/preview_test.rb`.

**Files:**
- Create: `app/assets/tailwind/themes/default/sections.css`
- Modify: `app/components/blocks/section_component.{rb,html.erb}`, `app/components/blocks/image_component.{rb,html.erb}`, `app/assets/tailwind/themes/default/tokens.css`, `app/assets/tailwind/themes/default/theme.css`, `app/views/layouts/application.html.erb` (`overflow-x-clip` on `<body>`)
- Test: `test/integration/public_blocks_test.rb`, `test/integration/design_tokens_test.rb`, `test/integration/preview_test.rb`, `test/integration/trash_visibility_test.rb`, `test/components/previews/blocks/` (a preview of the section)

**Interfaces:**
- Consumes: `BlockTypes::Section::LAYOUTS`, `.weights`; `BlockOutline#columns`; `ThemeHelper#render_block`; `block.section` set by the outline (Task 1).
- Produces:
  - `Blocks::SectionComponent`: `#render?` (false with no blocks), `.image_sizes(section, column) -> String`.
  - Markup: `<section class="content-section content-section--<background> content-section--<width>"><div class="content-section__inner"><div class="content-section__grid content-section__grid--<layout>"><div class="content-section__column">…`.
  - Tokens `--th-band-tinted`, `--th-band-strong`, `--th-on-band-strong`, `--th-on-band-strong-dim`, `--th-on-band-strong-accent`, each in the light and the dark block.

- [ ] **Step 1: Write the failing tests.** In `test/integration/public_blocks_test.rb` (`section_with_texts` is Task 1's helper; give it `background:` and `width:` keywords that go into the settings):

```ruby
  test "each layout renders its own grid class and one column element per column, an empty one kept" do
    { "one" => 1, "two" => 2, "three" => 3, "four" => 4, "one_two" => 2, "two_one" => 2 }.each do |layout, count|
      @root.content_blocks.destroy_all
      section_with_texts([ 1, "Only the first column" ], layout: layout)
      get "/"

      assert_select "section.content-section .content-section__grid.content-section__grid--#{layout}", 1
      assert_select "section.content-section .content-section__column", count
      assert_select "section.content-section .content-section__column:first-child .cs-prose", 1
    end
  end

  test "a section is a plain grouping element: no heading of its own, no label, no landmark role" do
    section_with_texts([ 1, "Text" ])
    get "/"

    assert_select "section.content-section[aria-label], section.content-section[aria-labelledby], section.content-section[role]", 0
    assert_select "section.content-section > h1, section.content-section > h2", 0
  end

  test "background and width are classes, and the default is neither band nor full" do
    section_with_texts([ 1, "Plain" ])
    section_with_texts([ 1, "Band" ], background: "strong", width: "full")
    get "/"

    assert_select "section.content-section.content-section--none.content-section--content", 1
    assert_select "section.content-section.content-section--strong.content-section--full", 1
  end

  test "a section with no blocks renders nothing" do
    @root.content_blocks.create!(block_type: :section, position: 0)
    get "/"

    assert_select "section.content-section", 0
  end

  test "an image in a column asks for a column-wide picture, and one outside a section for the content width" do
    asset = create_media_asset
    @root.content_blocks.create!(block_type: :image, position: 0, media_asset: asset)
    three = @root.content_blocks.create!(block_type: :section, position: 1, settings: { "layout" => "three" })
    @root.content_blocks.create!(block_type: :image, section: three, section_column: 2, position: 0, media_asset: asset)
    wide = @root.content_blocks.create!(block_type: :section, position: 2, settings: { "layout" => "one_two" })
    @root.content_blocks.create!(block_type: :image, section: wide, section_column: 2, position: 0, media_asset: asset)
    get "/"

    sizes = css_select("img[sizes]").map { |img| img["sizes"] }
    assert_equal [ Blocks::ImageComponent::SIZES, "(min-width: 768px) 245px, (min-width: 480px) 33vw, 100vw", "(min-width: 768px) 491px, (min-width: 480px) 67vw, 100vw" ], sizes
  end

  test "a page of sections costs no query per section or per block in one" do
    asset = create_media_asset
    build = lambda do |sections|
      @root.content_blocks.destroy_all
      sections.times do |index|
        section = @root.content_blocks.create!(block_type: :section, position: index)
        @root.content_blocks.create!(block_type: :image, section: section, section_column: 1, position: 0, media_asset: asset)
        @root.content_blocks.create!(block_type: :rich_text, section: section, section_column: 2, position: 0, body: rich_doc("Text"))
      end
    end

    build.call(1)
    get "/"
    one = capture_sql { get "/" }.size
    build.call(4)
    get "/"
    four = capture_sql { get "/" }.size

    assert_equal one, four
  end
```

  (If the file's existing N+1 test counts queries another way, count the same way.) In `test/integration/preview_test.rb`, following its own setup: a draft page with a tinted three-column section previews with `section.content-section--tinted` and its three column elements. In `test/integration/trash_visibility_test.rb`: a published page with an image block in a column whose asset is then moved to the trash by the service that file uses renders the section and no `<img>` for it (the same outcome the file pins for a top-level image block; if a trashed image in use cannot be trashed at all, pin that refusal for the block in a column instead). In `test/integration/design_tokens_test.rb`: the five new tokens appear in both the light and the dark block of `tokens.css`, and `sections.css` holds no colour literal (`refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, css)`).

- [ ] **Step 2: Run them, expect failure.**

- [ ] **Step 3: The component.**

```ruby
    # A section with no block renders nothing (sections spec §5.5): an empty
    # band would be a stripe of background with nothing in it. An empty
    # COLUMN keeps its place, so a two-column band with one text stays a
    # half-width text.
    def render? = columns.any?(&:any?)

    def columns = @columns ||= BlockOutline.new(page.content_blocks).columns(block)

    def layout = BlockTypes::Section::LAYOUTS.key?(settings.layout.to_s) ? settings.layout : "two"
    def background = BlockTypes::Section::BACKGROUNDS.include?(settings.background.to_s) ? settings.background : "none"
    def width = BlockTypes::Section::WIDTHS.include?(settings.width.to_s) ? settings.width : "content"

    # The `sizes` of an image in `column` of `section` (sections spec §5.4):
    # the column's share of the 736px content column from 768px of viewport
    # up, its share of the viewport while the columns still sit side by side
    # (from 480px, where `sections.css` unstacks them), and the full width
    # below. A hint for the browser's choice among the `srcset` candidates,
    # not a layout: close is enough, too large only costs bytes.
    CONTENT_WIDTH = 736

    def self.image_sizes(section, column)
      weights = BlockTypes::Section.weights(section.settings["layout"])
      share = weights.fetch(column - 1, weights.first).fdiv(weights.sum)
      "(min-width: 768px) #{(CONTENT_WIDTH * share).round}px, (min-width: 480px) #{(share * 100).round}vw, 100vw"
    end
```

  with `settings = block.settings_object` private. The template is the markup under Interfaces. `Blocks::ImageComponent` gains `def sizes = block.section_id && block.section ? Blocks::SectionComponent.image_sizes(block.section, block.section_column) : SIZES` and its template passes `sizes: sizes`; `SIZES`'s comment gains a sentence that an image in a column is narrower. `block.section` is the object the outline handed over, so this is no query (the last test pins it).

- [ ] **Step 4: The tokens.** In `tokens.css`, in the light block: `--th-band-tinted: var(--th-sunken); --th-band-strong: var(--th-ink); --th-on-band-strong: var(--th-paper); --th-on-band-strong-dim: #c9c8c2; --th-on-band-strong-accent: oklch(0.80 0.09 250);` and in the dark block: `--th-band-tinted: var(--th-sunken); --th-band-strong: #ededee; --th-on-band-strong: #0f1012; --th-on-band-strong-dim: #45464b; --th-on-band-strong-accent: oklch(0.45 0.12 250);`. Each pair must reach 4.5:1 against `--th-band-strong`; extend the contrast check `design_tokens_test.rb` already runs for the preview bar to the hex pairs here, and adjust a value that fails. In `theme.css`'s `@theme inline`: `--color-band-tinted`, `--color-band-strong`, `--color-on-band-strong` mapped to them, and `@import "./sections.css";` after `prose.css`.

- [ ] **Step 5: The stylesheet.** `app/assets/tailwind/themes/default/sections.css`:

```css
/* Sections (sections spec §5): a band holding a grid of columns. Breakpoints
   follow the band's OWN width (container queries), not the window's: the same
   section is narrow in a narrow layout and wide in a wide one. Below 30rem
   every layout is one column in reading order; from 30rem the columns sit
   side by side, four of them two by two; from 44rem four are four across.
   Colours are theme tokens only. */
.content-section { margin-block: 2.5rem; }
.content-section__inner { container-type: inline-size; }
.content-section__grid { display: grid; gap: 2rem; grid-template-columns: minmax(0, 1fr); }
.content-section__column { min-width: 0; }
/* A block's own vertical margin would double inside a grid cell's gap. */
.content-section__column > :first-child { margin-top: 0; }
.content-section__column > :last-child { margin-bottom: 0; }

@container (min-width: 30rem) {
  .content-section__grid--two, .content-section__grid--four { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .content-section__grid--three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .content-section__grid--one_two { grid-template-columns: minmax(0, 1fr) minmax(0, 2fr); }
  .content-section__grid--two_one { grid-template-columns: minmax(0, 2fr) minmax(0, 1fr); }
}
@container (min-width: 44rem) {
  .content-section__grid--four { grid-template-columns: repeat(4, minmax(0, 1fr)); }
}

/* Bands. `content` keeps the band inside the content column; `full` runs it
   edge to edge and puts the content back on the page's content width: the
   negative margin reaches the viewport's edges from the centred column, and
   the same amount of padding brings the inner box back. `<body>` clips the
   scrollbar's width that `100vw` includes. */
.content-section--tinted, .content-section--strong { padding-block: 2.5rem; padding-inline: 1.5rem; }
.content-section--tinted { background: var(--th-band-tinted); }
.content-section--strong { background: var(--th-band-strong); color: var(--th-on-band-strong); }
.content-section--strong :where(a) { color: var(--th-on-band-strong-accent); }
.content-section--strong :where(.text-meta, .text-dim, figcaption) { color: var(--th-on-band-strong-dim); }
.content-section--full { margin-inline: calc(50% - 50vw); padding-inline: calc(50vw - 50%); }

/* Adjacent sections with the same background join without a gap. */
.content-section--tinted + .content-section--tinted,
.content-section--strong + .content-section--strong { margin-top: -2.5rem; }
```

  `.cs-prose` sets its own colours for headings and links: read `prose.css` and, inside `.content-section--strong`, override the custom properties or selectors it uses so text and links take the contrasting tokens (spec §5.3). Add `overflow-x-clip` to the `<body>` class list in `app/views/layouts/application.html.erb`. Add a Lookbook preview under `test/components/previews/blocks/` with the six layouts and the three backgrounds, in the style of the previews already there.

- [ ] **Step 6: Run** `PGGSSENCMODE=disable bin/rails test test/integration test/components test/lib`, then `bin/rails tailwindcss:build` and look at the Lookbook preview in both themes and at 360px, 600px and 1200px of window width: stacked, two by two for four columns, four across; a `strong` band's text and links readable; two tinted bands in a row joined; a `full` band edge to edge with no horizontal scrollbar. Say in the task report what was looked at.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: the public page draws a section as a band with a grid that follows its own width" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 11: Documentation and the full verification

**Spec:** §9, Q1, Q5, D13. **Read first:** `CLAUDE.md` (how a rule and a reference entry are worded), `docs/reference/content-blocks-and-types.md`, `docs/roadmap.md`.

**Files:**
- Modify: `docs/reference/content-blocks-and-types.md`, `docs/reference/save-rule-and-write-queue.md` (one paragraph), `CLAUDE.md`, `docs/superpowers/specs/2026-10-08-sections-layout-design.md` (status line), `docs/roadmap.md` (alone, last)

**Interfaces:**
- Consumes: everything above, as built. Where the code differs from this plan, the documentation follows the code.

- [ ] **Step 1: The reference.** `docs/reference/content-blocks-and-types.md` gains a "## Sections" part in the file's own style (dense paragraphs that name the classes and record why), covering: the two columns and the NO ACTION key, with the page's destroy order (Q3); the `:container` capability and `columns` on the definition; `position` per container, `ContentBlock.top_level` / `in_column`, `BlockOutline` and who uses it (both page views, the audit snapshot, the controller's streams); the model's rules and when they run (D15); the services: create into a column, the fold, `Reorder`'s container and `moved_from` with its refusals, both deletes, `Duplicate` and what it records (Q2), the owner lock (D14), the audit metadata keys (D7); the editor: section card, lanes, tiles, panels, that every form is in the page and why (D3, with the sentence "do not fetch the open form"), `admin--section`, the "+" of a lane, the header form (D5), the one Move dialog (D10), what a move between containers re-renders and the unclean-form rule (D8), the translation view, the unavailable forms; the public side: `render_block`, the markup, the breakpoints (D11), the bands and the breakout (D12), image `sizes` (D13), an empty column and an empty section. Update the file's "Describes:" line and its first paragraph (`block_type` now includes `section`). In `docs/reference/save-rule-and-write-queue.md`, in "The write queue", add that a move between containers is the same hand-built `fetch` inside the queue as a reorder, that it first has every form send what it holds, and that a section's open form is hidden, never removed.

- [ ] **Step 2: `CLAUDE.md`.** Add to "Rules a change can break silently", in the list's wording:
  - A block in a section still belongs to the page: `owner` is the page, `section_id` and `section_column` only place it, and `page.content_blocks` is every block of the page; display order comes from `BlockOutline`, never from `position` alone (`test/models/block_outline_test.rb`).
  - A block changes container only through `ContentBlocks::Reorder` (with `moved_from`), and in the editor only through `admin--blocks#move` inside `app/javascript/autosave/queue.js`; `ContentBlocks::Save` reads `section_id` and `section_column` for a new block only.
  - Code asks `capability?(:container)` and the definition's `columns`, never `block_type == "section"`.
  - The foreign key on `content_blocks.section_id` stays NO ACTION; a section is emptied or lifted by `ContentBlocks::Destroy`, and `Page` destroys the blocks in its sections first.
  - Every block's form in a section is rendered with the page and only shown or hidden by `admin--section`: an open form is never fetched and never removed, because the write queue's guarantees are about forms that are in the document.

  In the reference index, extend the content-blocks entry's file list with `app/values/block_outline.rb`, `app/services/content_blocks/`, `app/components/admin/editor_screen/section_*`, `app/components/blocks/section_component.rb`. In "Key Conventions", in the sentence listing what a system test waits with, nothing changes. Set the spec's status line to "**Status: built** (plan `docs/superpowers/plans/2026-10-08-sections-layout.md`)."

- [ ] **Step 3: Commit the documentation, without the roadmap.**

```bash
git add CLAUDE.md docs/reference docs/superpowers/specs/2026-10-08-sections-layout-design.md
git commit -m "docs: sections — the reference, the rules a change can break silently" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 4: The roadmap, alone.** Another session may be editing `docs/roadmap.md`: run `git fetch origin main` and re-read the file as it is on disk immediately before editing, change only the lines named here, and commit it by itself.
  - Item 2 of the agreed sub-projects, "Block and type catalogue", becomes the four sub-projects of the spec's first paragraph, in that order: (1) layout: sections (this one, marked shipped in the file's own way of marking, with one line saying what it is); (2) the built-in catalogue of blocks, content types and page types; (3) content types defined in the admin; (4) forms, with mail delivery. Keep the candidates and notes the old item listed under the sub-project they belong to (the block, content-type and page-type candidates under 2; the pointers to "Forms" and "Custom content types" fold into 3 and 4), and carry the spec's §11 notes over.
  - New gap rows, in the section of the file where gaps of this kind are listed: MCP page and block tools, with a block's section and column (Q1); no Undo for a move into, out of or inside a section (Q5); an image inside a rich-text block in a column is requested at the content width (D13); a tile has no pick-up-and-arrows keyboard drag, its moves are in the menu (D9); a duplicated section is several audit events (Q2).

```bash
git add docs/roadmap.md
git commit -m "docs: the roadmap — the block and type catalogue is four sub-projects, sections first; five gaps sections leave" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 5: The full verification.** No other test runner may be active on this machine. In order, each must exit 0:

```bash
bin/rubocop
bin/brakeman
bin/rails zeitwerk:check
bin/importmap audit
bin/bundler-audit
PGGSSENCMODE=disable bin/rails test
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system
```

  `config/brakeman.ignore` stays empty. For a failure or error in the system run: name the test, run it alone several times, say whether it is deterministic and whose it is; never report "a re-run was clean" without the name. Then, in a browser against a development server started from this worktree on a free port (not the server running from the other checkout): build a landing page (a hero, a tinted three-column band, a two-thirds band with an image, a strong full-width band), edit it in a second language, view it at phone width, and say in the report what was seen.

- [ ] **Step 6: Commit whatever the verification made you fix**, one `fix:` commit per finding, each with the two trailer lines.

---

## Self-review (run when the plan was written)

**Spec coverage.** §2 decisions 1–7: Tasks 1 (type, one level, six layouts, look, storage), 2 (tiles and the open form), 5 (any type but Section goes into a lane). §3.1: Task 1. §3.2: Task 1 (model rules, the key). §3.3: Tasks 3 (create, fold, both deletes) and 4 (reorder, duplicate); the audit events are D7 and Q2. §3.4: Tasks 1 (owner, scopes, outline, permalink in a column) and 3 (derived rows). §3.5: Q1, no task, a roadmap row in Task 11. §3.6: Task 1 (no content migration; the migration adds nullable columns). §4.1: Tasks 2 (card, lanes) and 6 (controls, menu, collapsed line). §4.2: Tasks 2 (tiles, attention marks), 5 (the "+"), 9 (the unregistered tile). §4.3: Tasks 2 and 5 (opens at once). §4.4: Tasks 7 (drag, a lane refuses a section, the queue) and 8 (the menu). §4.5 and §4.6: Task 9. §4.7: every task that adds a component or script adds its keys and its `CONVERTED` entries. §5.1: Tasks 1 and 10. §5.2–§5.6: Task 10. §5.7: Tasks 1 (the version moves through the existing touch and `after_commit`; Task 3 pins it for a lift) and 10 (preview). §6: the stale save (Task 6), the refused move (Tasks 4, 7), the add into a removed column (Tasks 3, 5), the unavailable section and tile (Task 9). §7: model (1), services (3, 4), derived rows (3), public page (1, 10), editor system tests (2, 5, 6, 7, 8, 9), trash (1, 10). §8: Task 2 is the first work after the data layer. §9: Task 11.

**Review Focus.** Each of the five has a named test: 1 in Task 1 Step 10; 2 and 3 in Task 2 Step 1; 4 in Task 7 Step 1 (two tests); 5 in Task 3 Step 1 (the refused column), Task 4 Step 1 (`NO_COLUMN`), Task 5 Step 1 and Task 7 Step 1 (the folded lane).

**Names across tasks.** `top_level`, `in_column`, `section_blocks`, `container?`, `column_count`, `BlockOutline#top_level/columns/blocks_in/reading_order/sections` (Task 1) are used with those names in Tasks 2–10. `placement: :list/:panel/:group`, `panel_id`, `panel_title_id`, `panel_title` (Task 2; made public in Task 6). `lanes_id`, `panels_id`, `summary_id`, `lane_id` (Task 2), `summary(section:, count:)` (Task 5), `delete_count_id` (Task 6), `SectionCardComponent.for` (Task 9; Tasks 2–8 construct the card directly and Task 9 replaces those calls). `tile_streams` (Task 5) is split into `panel_component` and `tile_component` in Task 7 and reused in Task 8. `ContentBlocks::Reorder::STALE/NO_COLUMN/NESTED` (Task 4) are used in Tasks 5 and 7. `move(item, from, before)`, `snapshot()`, `itemsOf`, `placeOf`, `itemFor`, `accepts` (Task 7) are used in Tasks 8 and 9.

