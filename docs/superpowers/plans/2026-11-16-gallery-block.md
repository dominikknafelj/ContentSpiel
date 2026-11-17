# Gallery Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A built-in Gallery block holding an ordered list of up to 60 library images, each with a caption per language and an alt text that overrides the library's per language, drawn as a grid or as an APG carousel that works without its script; its images protected like a hero's through two new field types (#116).

**Architecture:** No column: the list is a `:media_list` field in `settings`, the texts a translated `:media_texts` field keyed by image id. Every field type answers `media_ids`, which the usage index (rows and copies), the choosing check and the tile's thumbnail ask, never a type's name. The public component hands a theme `items` and the `gallery-carousel` script's markup; the editor's rows are the texts field's input, writing the list's hidden input, through the card's ordinary autosave.

**Tech Stack:** Rails 8.1, Postgres jsonb, ViewComponent, Stimulus (import maps), SortableJS through `loadSortable()`, Minitest, Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-16-gallery-block-design.md`, the binding authority; §n below is its. The recipe is `docs/reference/content-blocks-and-types.md`, "Adding a block type" (spec §14 maps each step to a task here). **Design:** the Design System's cards StudioGallery (CS Studio: D1 to D5, D8) and SiteGallery (the public site: D6, D7), version `1794835099-7966` (v245, spec §16). A card's word wins over this plan's; on behaviour the spec wins, and the conflicts are ruled in spec §19. A word neither card gives is marked "(not on the card)"; a look neither gives goes back to the design agent. **Folders:** built on the base branch (`media-folders-gallery`, #278): `Media::Folder`, `Media::FolderTree`, `Media::Place`, `Media::FolderCounts` and the picker's places. Part two runs in the order 12, 11, 13, 14 (spec §17).

## Global Constraints

- Read `CLAUDE.md`; before a test, `docs/reference/writing-tests.md`, and `test/system/README.md` before a browser test. Before each task, the reference files its files name: `content-blocks-and-types.md` (the whole "Adding a block type"), `media.md` ("References and usages", "What a page draws", "Folders"), `theming.md` (the contract, "The Card block" and "The Code block" as models), `search.md` ("A block type's text"), `design-system.md`, `live-editing.md` (held fields), `i18n.md`.
- A new worktree runs `bin/rails db:test:prepare` and `bin/rails tailwindcss:build` once, never while tests run; `theme_css:watch` reads the types when it starts, so `bin/dev` is started again after Task 7. Browser tests run alone, on a quiet machine.
- The type's name is `gallery`. No top-level constant `Gallery` anywhere (no `app/*/gallery/`, no `Gallery::`): helpers are `BlockTypes::Gallery`'s module methods and `Blocks::GalleryComponent`'s. No token is named `gallery-frame`.
- Constants, exactly: `BlockTypes::Gallery::MAX_IMAGES = 60`, `LABEL_LENGTH = 80`, `TEXT_LENGTH = 1000`, `PICKER_MAX = 12`; `LAYOUTS = { "grid" => "Grid", "carousel" => "Carousel" }`, default `"grid"`; `RATIOS = { "3:2" => "3:2", "4:3" => "4:3", "1:1" => "Square", "16:9" => "16:9" }`, default `"3:2"`; `Blocks::GalleryComponent::GRID_COLUMNS = { 0 => 1, 360 => 2, 640 => 3 }` (the block's width: one column below 360px, two from 360px, three from 640px).
- Field types `:media_list` and `:media_texts`, both in `ContentModel::FieldTypes::BLOCK_ONLY`; `FieldType#media_ids` defaults to `->(_value) { [] }`. Nothing outside the registry branches on either name (`test/lib/field_type_branches_test.rb`).
- The usage role is `block_field`. No foreign key into jsonb; protection is the usage rows.
- **The lock order** (`CLAUDE.md`, "Rules a change can break silently"; `ContentSpiel::LockOrder` checks every statement in development and test): the settings row first (`ContentTypes.hold!`), then the page's or post's row, then block rows, then what is derived from them (`media_usages`, `translation_states`, `published_versions`). Every write of a block in this plan goes through `ContentBlocks::Save`, `Duplicate`, `Destroy` or the trash services, which take `ContentTypes.hold!` and the owner's row first (`ContentBlocks::Structure#lock_owner`); `Media::UsageIndex.refresh` runs inside them, after those locks. The choosing check (Task 4) reads before the transaction and takes no lock, as `Media::Choosing` does for a hero; an image trashed between the check and the write is the hero's own race, named in a comment, and a drawn gallery skips an image that is gone. No new lock. No task opens a transaction of its own that writes or locks a page, post or block row; a test that writes one around the services inside a transaction calls `ContentTypes.hold!` first. A read of `media_assets` or `media_folders` takes no row lock, and no task writes the settings row (so #276's rule, that a transaction holding it `FOR SHARE` never upgrades to an update, is not met here). The rule as checked is `main`'s at 48939d61 (#276, with `test/lib/lock_order_test.rb`): the branch takes `main` before Task 4.
- Public words, `public.blocks.gallery.*` (`position` and `moved` are patterns whose `%{index}` and `%{count}` the script fills in: the component hands them out uninterpolated through `pattern(key)`, which reads `PublicStrings.read` with no values, and `string(key, **values)` is never called with a value missing): `label` "Image gallery", `carousel` "carousel", `slide` "slide", `position` "%{index} of %{count}", `track` "Images", `previous` "Previous image", `next` "Next image", `show` "Show image %{index}", `moved` "Image %{index} of %{count}".
- Theme methods, exactly: `block page layout ratio fit label items sizes string pattern` (`pattern(key)` is what a template writes into the script's `position` and `moved` values); `sizes(per_row:)` takes an Integer or a Hash of least block widths to counts (spec §7.1). Script `gallery-carousel` (SiteGallery, "Named parts"): targets `controls track slide previous next position pick status`, values `position moved`, states `first middle last` on `data-gallery-carousel-state`.
- Tokens (SiteGallery, "The tokens"), seven, exactly: themed `gallery-stage gallery-control gallery-control-ink gallery-control-edge gallery-pick gallery-pick-current`, fixed `gallery-gap`; their values are spec §8's table. `gallery-control-edge` is `var(--th-ink)` on the page, a tinted band and a strong band alike, since the button sits on the image.
- The default template's class names (SiteGallery; spec §7.8): `content-block content-block--gallery`, `--grid` / `--carousel`, `--ratio-3-2` / `-4-3` / `-1-1` / `-16-9`, `--fit`; parts `__track __slide __frame __caption __controls __button __button--previous __button--next __foot __position __picks __pick __status __grid __item`, each as `content-block--gallery__<part>`.
- The carousel never autoplays and never wraps; it moves smoothly only under `prefers-reduced-motion: no-preference`. What only the script makes work is `hidden` in the markup.
- CS Studio strings are keys (`config/locales/admin/fields.en.yml`, `editor_screen.en.yml`, `ui.en.yml`), their words spec §12's (StudioGallery, "Words"); the type's label and select choices are literals of the definition.
- Every write from the browser goes through `app/javascript/saving/queue.js` (the card's autosave). The card script's actions write, so none joins `read_only_actions`.
- Comments state invariants, hazards or reasons, never history or plan steps. No compatibility code.
- `CHANGELOG.md`'s `## Unreleased` gets each task's own line in that task, and every task lists `CHANGELOG.md` in its Files; Task 8's ledger change carries the release note (`bin/changelog-guard` checks `test/support/contract_ledger.rb`).
- Commits by explicit path, conventional messages, each ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```

## Review Focus

1. **An image of the list that is gone** (deleted around the services, or a file that vanished): the site skips it and draws the rest, the positions count only what is drawn, and the card shows a row that says the image is missing — Task 7, `test "an id that names no image is skipped and the positions count what is drawn"`; Task 11, `test "a row for an image that is gone says so and can be removed"`.
2. **A forged list**: a new id without `media.upload` is denied before any lookup; with it, a trashed or missing id is the field's error and nothing is written; a reorder or removal without `media.upload` saves — Task 4, `test "a new id needs media.upload and a kept image, and a reorder or removal needs neither"`.
3. **A carousel of one image**, and a gallery of thirteen: one draws no controls and attaches no script; thirteen draws no picker but the position and the buttons — Task 7, `test "one image draws a slide alone, and thirteen draw the position and no picker"`.
4. **A language with no texts of its own**: captions follow the site's fallback chain, the alt is the library's in that language (not the English override) — Task 7, `test "a language without texts falls back for the caption and takes the library's alt in its own language"`.
5. **A right-to-left page**: Previous and Next keep reading order (Previous at the right, its chevron mirrored), the arrow keys follow the screen, the position stands at the inline end (the left) — Task 8, `test "in a right-to-left page the buttons follow reading order and the arrow keys the screen"`.
6. **A grid's `sizes`**: never fewer pixels than an image is drawn at, a phone's one column included — Task 7, `test "sizes divides each width by the images a row holds there, and never under-asks"`.

---

## Part one: the model and the site

### Task 1: Free the name

**Files:**
- Modify: every test stand-in that relies on `"gallery"` being an unregistered block type or name, found with `grep -rn '"gallery"' test` (today in `test/integration/public_blocks_test.rb`, `test/models/built_in_types_test.rb`, `test/models/audit/sentence_test.rb`) → `"retired_widget"`, its label "Retired widget"; `CHANGELOG.md`

- [ ] **Step 1:** rename each such stand-in; a post or other use of `"gallery"` that does not depend on the name being unregistered stays.
- [ ] **Step 2:** `bin/rails test test/integration/public_blocks_test.rb test/models/built_in_types_test.rb test/models/audit/sentence_test.rb` → PASS.
- [ ] **Step 3: Commit** `test: an unregistered block type's stand-in is retired_widget, freeing gallery`.

### Task 2: Two field types that refer to library images

**Files:**
- Modify: `app/models/content_model/field_type.rb` (`media_ids` with its default and its line in the comment), `app/models/content_model/field_types.rb` (`media_list`, `media_texts` after `:form` in `register_built_ins`; `BLOCK_ONLY` entries), `app/models/content_model/definition.rb` (`#media_ids_in(values) -> Array<Integer>`), `config/locales/admin/fields.en.yml` (`media_list.display` one "1 image", other "%{count} images"), `CHANGELOG.md`
- Create: `app/components/admin/fields/media_list_field.rb` (the hidden variant; `display` the count through `media_list.display`), `app/components/admin/fields/media_texts_field.rb` (a placeholder input drawing nothing but its error slot until Task 11; `display` nil)
- Test: `test/models/content_model/media_list_field_test.rb` (create), `test/models/content_model/media_texts_field_test.rb` (create), `test/models/content_model/field_types_test.rb`, `test/components/admin/fields/field_types_studio_test.rb`, `test/lib/field_type_branches_test.rb`

**Interfaces:**
- Produces: `ContentModel::FieldType#media_ids -> Proc(value) -> Array<Integer>`; `ContentModel::Definition#media_ids_in(values: Hash) -> Array<Integer>` (every field's answer over the untranslated values, in field order, unique).
- Produces: `:media_list` (cast: Array or JSON String → unique positive Integers or nil; `max:` → `:too_many_images`; refuses `translated: true`); `:media_texts` (cast: `{ "<digits>" => { "caption", "alt" } }` stripped, blanks dropped, or nil; needs `translated: true` and `of:` naming a `:media_list` of the definition, checked in `finish`; `max:` per text → `:too_long`); `errors.messages.too_many_images` "holds more than %{count} images" in `config/locales/en.yml`.

- [ ] **Step 1: Write the failing tests:**
  - `media_list_field_test.rb`: `test "a list casts from an array or a JSON string to unique positive ids in order"` (`"[3, 1, 3, -2, \"x\", 4]"` → `[3, 1, 4]`); `test "anything else and an empty list cast to nil"`; `test "more than max images is refused, never cut"`; `test "a translated media list is refused at registration"`; `test "media_ids answers the list's ids and every other type answers none"`.
  - `media_texts_field_test.rb`: `test "texts cast to captions and alts by image id, stripped, blanks dropped"`; `test "a text over max characters is refused as too long"`; `test "of: must name a media list of the same definition, and translated is required"` (finish-time refusals, the type's name first); `test "only a built-in block type may declare either: a content type, a field group and an outside block type may not"`.
  - `field_types_test.rb` ("every registered type answers every question") and `field_types_studio_test.rb` ("every registered type has its input in Admin::Fields and a read-only display") take both in.
- [ ] **Step 2:** run them → FAIL.
- [ ] **Step 3: Implement** the entries (`translatable: false`, `audit: :value`, `tracked` true for `:media_texts` only, not `:media_list`), `media_ids` on `:media_list` only, the two inputs' class methods (`hidden?` true for the list; `reference?` false and `own_label?` true for the texts).
- [ ] **Step 4:** run Step 1's files and `test/lib/field_type_branches_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: the media_list and media_texts field types (#116)`.

### Task 3: Usages and copies by field type

**Files:**
- Modify: `app/models/media/usage.rb` (`ROLES` gains `block_field`), `CHANGELOG.md`, `app/models/media/usage_index.rb` (`#block_field_rows`, joined into `#rows_for` beside `#block_image_rows`; `#asset_ids_in` reads each copied block's settings through its type's `media_ids_in`; an unknown type gives none)
- Test: `test/models/media/usage_index_test.rb`, `test/services/trash/move_test.rb` (or the file the suite keeps `Trash::Move`'s image refusals in), `test/services/trash/restore_test.rb`, `test/models/media/asset_version_test.rb`

**Interfaces:**
- Consumes: Task 2's `Definition#media_ids_in`.
- Produces: usage rows `(asset, "ContentBlock", block.id, "block_field", nil)` for every existing id of a block's media fields.

Tests here register a bare built-in-shaped test block type with a `:media_list` field (the field types are `BLOCK_ONLY`): `BlockTypes.register("test_media_list") { |t| TestTypes.declare(t); … }`, the registry saved before and put back in `ensure` (`BlockTypes.reset!` and `registry_put`), as `test/models/content_model/diagram_drawing_field_test.rb` registers `test_diagram`. Its blocks are written through `ContentBlocks::Save`, which takes the lock order's locks.

- [ ] **Step 1: Write the failing tests:**
  - `usage_index_test.rb`: `test "a block's media list gives one block_field row per existing image"`; `test "an id that names nothing gives no row and does not fail the refresh"`; `test "an image only the published list still shows keeps a published row until the changes are published"`.
  - `trash/move_test.rb`: `test "an image a kept block's media list uses cannot be moved to the trash"`.
  - `trash/restore_test.rb`: `test "restoring a page restores the trashed images its blocks' media lists name"`.
  - `asset_version_test.rb`: `test "an alt change on an image a live page's media list shows moves the content version"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** through `Definition#media_ids_in` and the existing-ids filter `#rich_text_rows` uses; `asset_ids_in` finds a copied block's definition with `BlockTypes.find(block["block_type"])` (nil gives none).
- [ ] **Step 4:** run Step 1's files and `bin/rails test test/models/media/ test/services/trash/` → PASS.
- [ ] **Step 5: Commit** `feat: a block's media fields are usages, in its rows and its copies`.

### Task 4: Choosing images for a list

**Files:**
- Modify: `app/services/media/choosing.rb` (`#media_fields_choice_result(record, definition, new_settings)`), `app/services/content_blocks/save.rb` (call it after `media_choice_result`, before the transaction and before anything is assigned: a read that takes no lock, as `Media::Choosing` reads for a hero today, so the transaction's first lock stays `ContentTypes.hold!` in `lock_owner`; a comment names the race: an image trashed between the check and the write is stored and skipped when drawn, as the hero's is, and no lock is added), `CHANGELOG.md`
- Test: `test/services/content_blocks/save_test.rb`, `test/integration/admin/content_blocks_test.rb`

**Interfaces:**
- Produces: `Media::Choosing#media_fields_choice_result(record, definition, settings) -> Result | nil`: ids in `definition.media_ids_in(settings)` not in `definition.media_ids_in(record.settings_in_database)` (all of them for a new block, so a duplicate needs `media.upload` as an Image block's does) need `media.upload` (denied first) and must be `Media::Asset.kept`; else `record.errors.add(<field name>, "has an image that doesn't exist")` and `failure(record)`.

- [ ] **Step 1: Write the failing tests** (`save_test.rb`, on the test type of Task 3):
  - `test "a new id needs media.upload and a kept image, and a reorder or removal needs neither"` (Review Focus 2: four cases; the denial records one `access.denied` and writes nothing; a trashed id and a missing id are the field's error).
  - `test "the permission is asked before any image is looked up"` (no `media_assets` query before the denial).
  - `content_blocks_test.rb`: `test "a forged list in a block form answers 422 with the field's error and writes nothing"`.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run Step 1's files, `test/services/service_behaviour_contract_test.rb` and `test/lib/lock_order_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: choosing images for a media list needs media.upload and kept images`.

### Task 5: A sample with images, and the showcase's

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb` (`Sample` gains `images:`, an Integer ≥ 0, refused otherwise at registration), `app/models/content_model/sample_block.rb` (`media_asset_ids:`: written into the definition's `:media_list` field in order; the sample's `:media_texts` values re-keyed from positions "1".."n" to the ids; raises when the count differs or a position is past them), `test/support/block_samples.rb` (makes `sample.images` library images), `db/seeds/showcase.rb` (`DevelopmentShowcase.call` makes the images a sample asks for: tinted PNGs from libvips, uploaded through `Media::Upload` and titled "Showcase image N", found again by that title on a later run, since `Media::Upload` never dedupes; the blocks still go through `ContentBlocks::Save`), `test/integration/block_samples_test.rb` (the completeness check counts a media list filled by `images:`), `CHANGELOG.md`
- Test: `test/models/content_model/sample_block_test.rb` (create), `test/models/content_model/block_type_definition_test.rb`, `test/models/seeds_test.rb`

**Interfaces:**
- Produces: `BlockTypeDefinition::Sample#images -> Integer` (0 by default); `ContentModel::SampleBlock.arguments(definition, …, media_asset_ids: [])`.

- [ ] **Step 1: Write the failing tests:** `sample_block_test.rb`: `test "a sample's images fill its media list in order and its texts are re-keyed from positions to ids"`; `test "a sample asking for images it was not handed raises, and so does a position past them"`. `block_type_definition_test.rb`: `test "images: is a count, and anything else is refused with the type's name first"`. `seeds_test.rb`: `test "the showcase makes the images a sample asks for, and a second run makes none"` (with a test type, before the Gallery exists).
- [ ] **Step 2–4:** FAIL, implement, PASS (with `test/integration/block_samples_test.rb`, `test/integration/public_canary_test.rb`).
- [ ] **Step 5: Commit** `feat: a block sample can ask for library images`.

### Task 6: The Gallery's definition, its icon and its tile (steps 1, 2, 4 and part of 8)

**Files:**
- Generate: `bin/rails generate block_type gallery` (writes `app/models/block_types/gallery.rb`, the initializer's line, `app/components/blocks/gallery_component.rb` and `.html.erb`, `app/assets/tailwind/themes/default/gallery.css`, the locale scopes, the Lookbook preview, `test/models/block_types/gallery_test.rb`, `test/components/blocks/gallery_component_test.rb`); then take out `Written by bin/rails generate block_type`
- Modify: `config/initializers/types.rb` (the generator's line moved to stand after `BlockTypes::Image.register`, so the picker lists the Gallery beside the Image block (call): the line is the picker's order, and every list derived from registration follows it, the ledger's included, Task 8), `app/models/block_types/gallery.rb` (spec §5's declaration but `t.tokens`, which Task 7 adds, and with `t.stylesheet "gallery.css"` as the generator writes it: `t.icon "images", family: :media`; `summary`, `preview`, `search_text`, the sample), `app/models/content_model/block_type_definition.rb` (`ICONS` gains `images`, after `image`), `app/views/admin/shared/_icon.html.erb` (`:images`, Lucide `images` at the partial's stroke 1.5: `<path stroke-linecap="round" stroke-linejoin="round" d="M18 22H4a2 2 0 0 1-2-2V6" /><path stroke-linecap="round" stroke-linejoin="round" d="m22 13-1.296-1.296a2.41 2.41 0 0 0-3.408 0L11 18" /><circle cx="12" cy="8" r="2" /><rect width="16" height="16" x="6" y="2" rx="2" />`, with the block types' icons), `app/components/admin/editor_screen/tile_summary_component.rb` (`thumbnail_asset`: the image column's asset, else the first existing id of the definition's media fields; with none, a type whose definition has a media field draws the thumbnail box plain `bg-sunken`; `LOOKS` gains `warn`, a part drawn as `Admin::Ui::BadgeComponent` `tone: :warn` after the line, the media grid's "No alt" look; `drawn` translates the `:warn` part's `:without_alt` key like the `word` and `hint` kinds), `app/components/admin/editor_screen/tile_summary_component.html.erb` (the thumbnail is spec §10.5's box, 72px at 4:3, not the inline `size-6` image; the `:warn` part's badge), `test/models/block_types/note_test.rb` (the built-in order list gains `gallery` where the picker puts it, after the Image block), `CHANGELOG.md`, `config/locales/admin/editor_screen.en.yml` (`tile_summary.types.gallery`: `grid` one "Grid · 1 image", other "Grid · %{count} images"; `carousel` one "Carousel · 1 image", other "Carousel · %{count} images"; `empty` "Empty"; `without_alt` "%{count} without alt"), `config/locales/admin/fields.en.yml` (`gallery.label_help` "What a screen reader calls the gallery. Leave it blank for “%{placeholder}” in each visitor's language.")
- Test: `test/models/block_types/gallery_test.rb`, `test/models/block_types/note_test.rb`, `test/models/built_in_types_test.rb`, `test/models/site_search/block_text_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/components/admin/ui/block_icon_component_test.rb`, `test/models/content_model/block_type_definition_test.rb`

**Interfaces:**
- Produces: `BlockTypes::Gallery.summary(block, locale:) -> Array<part>` (`[[:word, :carousel, { count: 12 }]]`, the layout's key with the count; then `[:warn, :without_alt, { count: 3 }]` when some image has no alt in that language, the override and the library's both blank, read in one query; `[[:word, :empty]]` with none); `.preview(block, locale:) -> ContentModel::Preview | nil` (heading: the label when written); `.search_text(block, locale:) -> Array<String>` (captions and alt overrides of attached images, read with `settings_object(locale:, fallback: true)`).
- Produces: the sample: `images: 3, settings: { "layout" => "carousel", "ratio" => "4:3" }`, translations en/de/es with `label` ("Harbour en"/"de"/"es"), `texts` by position (`"1" => { "caption" => "Gallery caption en", "alt" => "Gallery alt en" }`, `"2" => { "caption" => "Second caption en" }`), `shows: [ "Gallery caption en", %(alt="Gallery alt en"), %(aria-label="Harbour en") ]`.
- Produces: the icon `images` on the media chip; `TileSummaryComponent::LOOKS[:warn]`.

- [ ] **Step 1: Write the failing tests:** `gallery_test.rb`: `test "a gallery is six fields, none required, the list and its texts the only media fields"`; `test "the summary says the layout with the count, Empty with none, and how many have no alt"`. `built_in_types_test.rb`: `test "gallery stands after image in the picker's order"` (`BlockTypes.built_in_names` index of `"gallery"` is image's plus one). `block_text_test.rb`: `test "a gallery gives its captions and alt overrides of images that are there, in the language asked"`. `tile_summary_component_test.rb`: `test "a gallery's tile shows its first image as the thumbnail, and a plain box with none"`; `test "a warn part is drawn as the warn badge after the line"`. `block_type_definition_test.rb` ("every built-in block type declares the family the design gives it") gains `gallery` → `:media`; `block_icon_component_test.rb` ("every icon a block type may name is drawn by the icon partial", "every built-in block type declares its icon") covers `images`.
- [ ] **Step 2:** run them, and `test/values/theme/contract_ledger_test.rb` and `test/values/theme/component_contract_test.rb` → FAIL (the ledger until Task 8, the 9a contract until Task 7: both red by design, the cost of one red guard between two commits).
- [ ] **Step 3: Implement.** Restart `bin/dev` only after Task 7.
- [ ] **Step 4:** run Step 1's files (including `note_test.rb`), `test/models/block_types/samples_preview_test.rb`, `test/integration/block_samples_test.rb` → PASS; between this commit and Task 7's only the task's own named tests must pass (the ledger and 9a stay red).
- [ ] **Step 5: Commit** `feat: the Gallery block's definition, icon and tile`.

### Task 7: The public component, its template and its stylesheet (step 5; SiteGallery D6, D7)

**Files:**
- Modify: `app/components/blocks/gallery_component.rb` and `.html.erb`, `app/assets/tailwind/themes/default/gallery.css`, `tokens.css` (the page's values, both schemes, on the blocks that declare the base tokens; `--th-gallery-control-edge: var(--th-ink)`, the same on the page, a tinted band and a strong band, so `sections.css` does not re-value it), `sections.css` (`.content-section--tinted`: `--th-gallery-pick: var(--th-dim)`; `.content-section--strong`: `--th-gallery-stage: color-mix(in oklab, var(--th-on-band-strong) 10%, var(--th-band-strong))`, `--th-gallery-pick: var(--th-on-band-strong-dim)`, `--th-gallery-pick-current: var(--th-on-band-strong)`), `app/models/block_types/gallery.rb` (`t.tokens themed: %w[gallery-stage gallery-control gallery-control-ink gallery-control-edge gallery-pick gallery-pick-current], fixed: %w[gallery-gap]`; the stylesheet is Task 6's declaration), `config/locales/public.en.yml` (`public.blocks.gallery.*`), `test/components/previews/blocks/gallery_component_preview.rb` (grid and carousel), `db/seeds/showcase.rb` (the Gallery drawn once more as a grid, `settings: { "layout" => "grid" }`, spec §11), `CHANGELOG.md`
- Test: `test/components/blocks/gallery_component_test.rb`, `test/integration/public_blocks_test.rb`, `test/integration/design_tokens_test.rb`, `test/values/theme/component_contract_test.rb`

**Interfaces:**
- Consumes: Task 6's definition.
- Produces: `Blocks::GalleryComponent#items -> Array<Blocks::GalleryComponent::Item>`, `Item = Data.define(:index, :picture, :caption)`; `#sizes(per_row: 1) -> String` (spec §7.1: each width of `Blocks::ImageComponent.sizes_for(block)` divided by the count for it; `per_row` an Integer or a Hash of least block widths to counts; a fixed pixel width W takes the count n of its own width, the largest key of the Hash not above W, a viewport-relative width the count of the narrowest block, `per_row[0]`; the width of a block at the top level is `Blocks::SectionComponent::CONTENT_WIDTH` (736), a section column's is its share, as `SectionComponent.image_sizes` computes it; one image asks `round((W - (n - 1) * gap) / n)` with the grid's gap `--th-sp-3` = 14px, so at the top level `(736 - 2 * 14) / 3 = 236` and `sizes(per_row: GRID_COLUMNS)` is exactly `"(min-width: 768px) 236px, 100vw"`; it never asks for fewer pixels than an image is drawn at; `per_row: 1` is `sizes_for` unchanged); `Item#picture[:sizes]` is `sizes(per_row:)`'s string, so there is one source; `#layout`, `#ratio`, `#fit`, `#label`, `#string(key, **values)`, `#pattern(key)` (the public sentence uninterpolated, for the script's `position` and `moved` values). One query for the assets (`Media::Asset.with_file.where(id:)`).
- Produces: the template's markup per spec §7.2 to §7.4 and §7.8 (the script's targets as `data-gallery-carousel-target`; controls, foot, picker and status `hidden`; the dots only up to `PICKER_MAX`; the classes of the Global Constraints).
- Produces: `gallery.css` per spec §7.8: the frame's ratio and fit as plain rules on the built classes; the grid a size container with one, two and three columns below 360px, from 360px and from 640px of the block; the buttons 44px circles over the frame's sides, 10px in, the edge `box-shadow: 0 0 0 1px var(--th-gallery-control-edge), var(--th-shadow-menu)` (the shadow is depth only; disabled: a `--th-line` edge and no shadow), with a 20px chevron mirrored under `:dir(rtl)`; the caption 8px under the frame, 13px/1.5; the foot 10px under the caption; the dots 24×24 with an 8px ring of 1.5px and a 20×8 current pill; the track `scrollbar-width: thin`, `none` under `[data-gallery-carousel-state]`; `scroll-behavior: smooth` only under `prefers-reduced-motion: no-preference`. Colours only through `--th-*`.
- Produces: `contract(...)` per spec §14 step 9a, `words:` the nine keys.

- [ ] **Step 1: Write the failing tests** (`gallery_component_test.rb` unless named):
  - `test "a grid draws a named list of figures in order, each image through the picture component with its caption"`.
  - `test "a carousel draws the APG roles and names, the controls hidden, the track focusable and named"` (`aria-roledescription` "carousel" and "slide", `aria-label` "1 of 3", `tabindex="0"`, `hidden` on controls, foot, picker, status).
  - `test "one image draws a slide alone, and thirteen draw the position and no picker"` (Review Focus 3).
  - `test "an id that names no image is skipped and the positions count what is drawn"` (Review Focus 1).
  - `test "a language without texts falls back for the caption and takes the library's alt in its own language"` (Review Focus 4).
  - `test "a caption and a label that look like markup are text"`.
  - `test "nothing is drawn for an empty gallery"`; `test "every frame carries its ratio class and the fit class when set"`; `test "sizes divides each width by the images a row holds there, and never under-asks"` (Review Focus 6: the content width with `GRID_COLUMNS` asserting exactly `"(min-width: 768px) 236px, 100vw"`, an equal two-column section's column of 368px (two columns of `(368 - 14) / 2 = 177`) asserting `"(min-width: 768px) 177px, (min-width: 480px) 50vw, 100vw"`, `per_row: 1` equal to `sizes_for`, and `Item#picture[:sizes]` equal to `sizes(per_row:)`).
  - `test "the script's position and moved values are the uninterpolated patterns"` (`data-gallery-carousel-position-value` is `"%{index} of %{count}"`).
  - `public_blocks_test.rb`: `test "a gallery in a section's column asks for its column's share"`.
  - `design_tokens_test.rb`: `test "every gallery token is defined in both schemes and readable on the page, a tinted band and a strong band"` (in both schemes: the arrow on its ground at 4.5:1, `--th-gallery-control-edge` on `--th-gallery-control` at 3:1, and the dots at 3:1 on paper, a tinted band and a strong band).
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run Step 1's files and `test/values/theme/contract_test.rb` → PASS (ledger red until Task 8).
- [ ] **Step 5: Commit** `feat: the Gallery's public component, grid and carousel`.

### Task 8: The carousel's script and the contract's ledger (steps 7 and 9)

**Files:**
- Create: `app/javascript/controllers/gallery_carousel_controller.js`
- Modify: `app/javascript/controllers/index.js` (`PUBLIC_ONLY` gains `controllers/gallery_carousel_controller`), `app/values/theme/contract.rb` (`SCRIPTS["gallery-carousel"]`), `test/support/contract_ledger.rb` (`assert_ledger` compares in order: the component line after `blocks/image_component`'s, the themed tokens before the Code block's `syn-*` and the fixed `gallery-gap` before `diagram-font`, as the registration order of Task 6 puts them; the script after `search-suggest`; the release note in its comment), `CHANGELOG.md` (Added; the ledger's release note: the component line, its seven tokens and the `gallery-carousel` script)
- Test: `test/integration/public_javascript_test.rb`, `test/values/theme/contract_ledger_test.rb`, `test/values/theme/component_contract_test.rb`, `test/system/gallery_block_test.rb`

**Interfaces:**
- Produces: identifier `gallery-carousel`; targets `controls track slide previous next position pick status`; actions `previous`, `next`, `show` (a pick's `data-gallery-carousel-index-param`), `keydown`; `data-gallery-carousel-state` `first | middle | last`; values `position`, `moved` (sentences with `%{index}`, `%{count}`).

- [ ] **Step 1: Write the failing tests:**
  - `public_javascript_test.rb`: `test "a public page with a carousel carries gallery-carousel and no admin script"`.
  - `test/system/gallery_block_test.rb` (on a published page, `visit` through the suite's public helper): `test "next, previous and a pick move one image, disable at the ends and say where we are"`; `test "a disabled button hands the focus to the other one"`; `test "the arrow keys, Home and End move on the track and on the controls, never with a modifier"`; `test "a swipe or a scroll moves the position and the picker but says nothing"`; `test "with reduced motion a move is instant"` (`emulate_media(reduced_motion: "reduce")`, the track's `scrollLeft` final at once); `test "in a right-to-left page the buttons follow reading order and the arrow keys the screen"` (Review Focus 5); `test "without the script the track scrolls and snaps and no control shows"` (the page drawn with JavaScript off, or the controller's import blocked, as `code_block_test.rb` does); `test "back to a cached page the carousel shows no stale words"` (a Turbo visit away and back).
  - the ledger test turns green with the ledger's lines (the 9a contract test is Task 7's and is green already).
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** per spec §7.5 (the observer, the scroll from rectangles, `disconnect` and `turbo:before-cache` take-backs, slides kept in a field). **Step 4:** run Step 1's files and `bin/rails test test/values/theme/` → PASS.
- [ ] **Step 5: Commit** `feat: the gallery-carousel script and the Gallery's line of the theme contract`.

### Task 9: The theming reference and a theme built from it (step 9)

**Files:**
- Modify: `docs/reference/theming.md` (the components table's row, the tokens table's seven rows with spec §8's values, the Scripts table's row, a section "The Gallery block" in the Card's shape: what a theme can do from least to most, what the template is handed (§8's table, `sizes(per_row:)` with its Hash), what a template should keep, the script's markup)
- Create: `test/fixtures/themes/gallery/components/blocks/gallery_component.html.erb` (written from that section alone, by someone who reads only it)
- Modify: `test/support/theme_test_helper.rb` (exists, with the other `with_*_theme` helpers: gains `with_gallery_theme`), `CHANGELOG.md`
- Modify: `test/lib/theming_reference_test.rb` (`test "the Gallery block's tables name exactly the methods of its entry, its nine words and what the carousel script reads"`), `test/integration/theme_pages_test.rb` (`test "a theme replaces the Gallery's template from the contract's names alone, and a theme that does not is drawn the default one"`), `test/system/gallery_block_test.rb` (`test "the carousel script drives a theme's own template"`)

- [ ] **Step 1:** write the tests → FAIL. **Step 2:** write the reference and the fixture. **Step 3:** run `test/lib/theming_reference_test.rb test/integration/theme_pages_test.rb`, then `bin/rails theme:check` on the fixture → PASS. **Step 4: Commit** `docs: the Gallery block in the theme contract, with a theme written from it`.

---

## Part two: the editor (StudioGallery D2 to D5, D8)

**Order:** Task 12 runs before Task 11, since the card's script consumes the picker's several-at-once opening; then 13 and 14. The numbers stay as the spec and the reports name them.

### Task 10: The icon (D1)

Done in Task 6: `test/components/admin/ui/block_icon_component_test.rb` ("every built-in block type declares its icon") is red for a built-in without one, so the icon comes with the definition. Nothing is left here; the number stays so the tasks after it keep theirs.

### Task 11: The card: rows, list and script (D2, D3)

**Files:**
- Modify: `app/components/admin/ui/field_component.rb` (hands every input `values:`, the `FieldSet` drawn; `Admin::Fields::Base#initialize(…, values: nil)`; a shared component: its contract declaration is updated if its interface changes), `app/components/admin/editor_screen/block_card_component.rb` and template (D2: a `control: :segmented` select followed directly by another `:select` stand in one row, `flex flex-wrap items-end gap-x-4`, the second filling the rest with a least width, so the two wrap below about 420px of the card; judged from the fields, never the type's name, and no size container, since none may stand inside the post form), `app/components/admin/fields/media_texts_field.rb` and template (spec §10.2's Images heading with "12 of 60" and §10.3's rows), `media_list_field.rb` and template (the hidden JSON input, its id handed to the rows), `app/views/admin/shared/_icon.html.erb` (`:image_off`, Lucide `image-off`, for a missing image's row), `config/locales/admin/fields.en.yml` (`media_texts.*`, the words of spec §12)
- Create: `app/javascript/controllers/admin/editor/gallery_controller.js` (identifier `admin--editor--gallery`: open the picker with `{ opener, multiple: true, max: MAX_IMAGES - count, chosen }`, "Add a folder" the same with `focus: "places"`; add from the picker's `items`, skip present ids, stop at `MAX_IMAGES`; remove; reorder by drag through `loadSortable()` and by the keyboard moves on the handle with their four sentences in a polite status; "Use library caption"; write the hidden input and dispatch `input`)
- Modify: `test/lib/admin_i18n_test.rb` (`CONVERTED`), `CHANGELOG.md`, `docs/reference/live-editing.md` only if a read-only action is declared (none is)
**Interfaces:**
- Consumes: Task 2's inputs, Task 6's definition, Task 12's `media-picker:open` with `{ opener, multiple: true, max:, chosen:, focus: }` and `media-picker:picked` with `{ items: [{ id, url, title, alt, caption }] }`.
- Produces: `Admin::Fields::Base#values` (the `FieldSet` drawn, nil where no caller hands one); the row's markup the script reads (`data-admin--editor--gallery-target` `row`, `handle`, `list`, `status`, `add`, `addFolder`, `limit`; each row's `data-asset-id`, not on the card).

- Test: `test/components/admin/fields/media_texts_field_test.rb` (create), `test/components/admin/fields/media_list_field_test.rb` (create), `test/components/admin/editor_screen/block_card_component_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`, `test/components/admin/editor_screen/block_samples_card_test.rb`, `test/components/admin/ui/contract_test.rb`, `test/lib/component_parts_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/system/admin/gallery_block_test.rb`

- [ ] **Step 1: Write the failing tests:**
  - `media_texts_field_test.rb`: `test "one row per image of the list in its order, with the language's caption and alt and the library alt as placeholder"`; `test "an image with no alt anywhere says so in the placeholder and marks the well"` ("No alt text in the library"); `test "a blank caption whose library image has one offers Use library caption"`; `test "a translation tab's rows show the default language's texts as reference and no list control"` ("12 images · the list is changed in English", "English: …"); `test "a row for an image that is gone says so and can be removed"` (Review Focus 1); `test "the empty card says so with both buttons, and the limit turns them off and says why"`; `test "Add a folder is drawn only when the library has a folder"`.
  - `block_card_component_test.rb`: `test "a segmented select followed by a select stand in one wrapping row"` (the Gallery's Layout and Shape; the Note block's kind, followed by no select, stands alone).
  - `held_fields_test.rb`: `test "a gallery held by someone else keeps its rows read-only and no list action survives"` (none of `admin--editor--gallery`'s actions on the allow-list).
  - `content_blocks_test.rb`: the type's cases (add from the picker, save, a refused save writes nothing, in a column, a duplicate keeps the list and the usages and needs `media.upload`, delete drops the usages, the stale 409, another tab's hold).
  - `test/system/admin/gallery_block_test.rb` (`visit_editor`): `test "images are added, captioned, reordered by drag and by keyboard, removed, autosaved and kept after a reload"` (the keyboard move's sentences read in the status); `test "a second person's card is read-only"`; `test "the 61st image is not added and the card says the limit"`.
- [ ] **Step 2–4:** FAIL, build to StudioGallery D2 and D3, PASS (with `test/lib/source_layout_test.rb`, `test/lib/admin_design_rules_test.rb`, and, for the shared `FieldComponent`, `test/components/admin/ui/contract_test.rb` and `test/lib/component_parts_test.rb`).
- [ ] **Step 5: Commit** `feat: the Gallery card's rows, list and script`.

### Task 12: The picker chooses several (D4)

**Files:**
- Modify: `app/components/admin/ui/media_picker_component.rb` and template (the contract: the limit "It hands back one image: several cannot be chosen." becomes "It hands back one image, or several in the order chosen when the opener asks for several."; `keys` gains the new words; the title's words `title` or `title_multiple`), `app/javascript/controllers/admin/media/picker_controller.js` (`multiple`, `max`, `chosen` from `detail`; the title, the footer's primary and status per spec §10.4; `picked` with `items` for a multiple opening, the one image's keys otherwise), `app/javascript/controllers/admin/media/select_controller.js` (toggle; the order pill; renumber on unchoosing; the choice kept across the frame's loads, a place's included; present ids marked "In the gallery" and `aria-disabled`; the rest `aria-disabled` at the limit; a chosen tile's name ending through `chosen_order`), `app/javascript/i18n/messages.js` (`t(key, { count, ordinal: true })` picks the category with `Intl.PluralRules(locale, { type: "ordinal" })`), `CHANGELOG.md`, `config/locales/admin/ui.en.yml` (`media_picker.*`: `title_multiple`, `add_count`, `takes`, `full`, `in_gallery`, `chosen_order`, `ordinal`, the words of spec §12)
**Interfaces:**
- Produces: `media-picker:open` takes `detail: { opener, multiple: true, max: Integer, chosen: Array<Integer>, focus: "places" }` (`focus` optional; without it the default focus stays); a multiple opening answers `media-picker:picked` on the opener with `detail: { items: [{ id, url, title, alt, caption }] }` in the order chosen; any other opening is unchanged (`{ id, url, title, alt, caption }`). Its browser tests open it from a stand-in opener that dispatches the event, as the Gallery card does not exist yet.
- Produces: `messages(element).t(key, { count, ordinal: true })`.

- Test: `test/components/admin/ui/media_picker_component_test.rb`, `test/system/admin/media_picker_test.rb`, `test/system/admin/messages_test.rb` (the browser test of `i18n/messages.js`)

- [ ] **Step 1: Write the failing tests:** `test "a multiple opening reads Add images, toggles tiles numbered in the order chosen, keeps the order across searches and places, and hands back items"`; `test "images already in the gallery are marked and not chosen again"`; `test "the choice stops at max and says so"` ("The gallery takes no more: 60 images."); `test "a chosen tile's name says its place in the order"` (", chosen 2nd"); `test "focus: places puts the focus on the places, and without it the default focus stays"`; `test "a single opener still gets one image's keys"` (the hero, the Image block and the rich-text editor's existing tests unchanged); the messages test: `test "an ordinal asks the ordinal rules"`.
- [ ] **Step 2–5:** FAIL, build, PASS (with `test/components/admin/ui/contract_test.rb`, `test/lib/component_parts_test.rb`), **Commit** `feat: the media picker chooses several images for a gallery`.

### Task 13: Add a whole folder (D4)

**Files:**
- Modify: `config/routes.rb` (beside `resources :media_folders`: `get "media_folders/:id/images", to: "media_folders#images", as: :media_folder_images, constraints: { id: /\d+/ }`), `app/controllers/admin/media_folders_controller.rb` (`#images` per spec §10.6: the existing `require_permission("media.upload")` gate (`only: :index`) gains `:images`, so it is asked before any folder is looked up, and the `media.manage` gate's `except:` becomes `%i[index images]`, excluding it; the folder through `Media::FolderTree.load` and `Media::Place.parse(params[:id], tree:)`, nil a 404; `place.narrow(Media::Asset.kept)` less `except`, `total` its count, `items` the oldest `limit` by id, `limit` capped at `BlockTypes::Gallery::MAX_IMAGES`, each `{ id, url: thumbnail_url, title, alt, caption }` in the admin language as the picker's tiles carry them), `app/views/admin/media/picker.html.erb` (in a folder's place, a row above the grid, `hidden`: the folder mark, the folder's name, its count from `@folder_counts` through `folder_count`, and the button, its URL `admin_media_folder_images_path(@place.folder)`), `app/javascript/controllers/admin/media/picker_controller.js` (in a multiple opening, after each frame load at a folder's place: fetch the URL with `limit` = what the gallery takes and `except` = the gallery's ids and the chosen ones; write `add_folder` or `add_folder_first`; show the row when `total` > 0; the press hands back `items` and closes), `config/locales/admin/ui.en.yml` (`media_picker.folder_count`, `add_folder`, `add_folder_first`), `CHANGELOG.md`
- Test: `test/integration/admin/media_folders_test.rb`, `test/system/admin/gallery_block_test.rb`

**Interfaces:**
- Consumes: Task 11's card and script (`admin--editor--gallery` hands `chosen` and `max`), Task 12's multiple opening; the folders' `Media::FolderTree.load`, `Media::Place.parse`/`#narrow`, `Media::FolderCounts` (the picker template's `@folder_counts`, `@folder_tree`, `@place`), `Media::Asset#thumbnail_url`.
- Produces: `GET /media_folders/:id/images?limit=&except=` → `{ total: Integer, items: [{ id, url, title, alt, caption }] }`, `admin_media_folder_images_path`.

- [ ] **Step 1: Write the failing tests:** `media_folders_test.rb`: `test "a folder's images come oldest first, kept only, never a subfolder's, less the ones named, up to the limit"`; `test "a folder's images need media.upload, asked before the folder is looked up, and an unknown folder is a 404"`; browser: `test "a whole folder is added in upload order, skipping images already there, up to the limit"` ("Add all 31 new images in this folder", and past the limit "Add the first 12 of 31 new images"); `test "the folder's row stands only in a multiple opening at a folder with new images"`.
- [ ] **Step 2–5:** FAIL, build, PASS (with `test/integration/admin/media_folders_test.rb`'s existing cases and `test/system/admin/media_picker_test.rb`), **Commit** `feat: add a whole folder to a gallery`.

### Task 14: The documents and the Design System entries (D5, D8)

**Files:**
- Modify: `docs/reference/content-blocks-and-types.md` (a section "The Gallery block"; the type in the list at the top; the two field types under "Field types"; the sample's `images:`; the tile's `:warn` part; the card's segmented row), `docs/reference/media.md` (role `block_field`, usages derived by field type; under "Folders", the picker's several-at-once opening and `GET /media_folders/:id/images`), `CLAUDE.md` (the reference index line for the Gallery's files; the "no guard" rules of spec §15), `docs/roadmap.md` ("Shipped"; #116's rest; AI translation of a gallery's texts; a state per image), the spec's "As built", `CHANGELOG.md`, `test/support/design_system_entries.rb` (`ENTRIES` gains `SiteGallery` and `StudioGallery` in alphabetical place; `VERSION` is `"1794835099-7966"`, the artifact's v245)
- The tile needs no change here: StudioGallery's D5 is one thumbnail, no strip (Task 6).
- Test: `test/lib/source_layout_test.rb`, `test/lib/theming_reference_test.rb`, `test/lib/component_parts_test.rb`

- [ ] **Step 1:** write; **Step 2:** `bin/rails test test/lib/` → PASS; **Step 3:** `bin/ci`, then `bin/theme-build-check` alone → green; **Step 4: Commit** `docs: the Gallery block`. The pull request's "Documentation" names the guide pages: the editors' Gallery page, the media picker's (several images, a whole folder), and the integrators' theming page for the Gallery block (tokens, template, script), with the ledger's release note.
