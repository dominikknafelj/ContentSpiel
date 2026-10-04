# CS Studio design pass, round 2 (editors, dashboard, posts, translations) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the page and post editors, the page tree, the dashboard, the posts list and the Translations screen to the v3 handoff, on top of two data changes (stored translation source text, stored translation state), and close the departures Claude Design found in the built round 1.

**Architecture:** Round 1's shared components stay the building blocks; this round composes them into screens and adds the few that were deferred (chip input, pending suggestion box, checkbox). Two data changes land first because later tasks read them: `translation_sources` entries gain the source text so an outdated field can show a word diff, and a `translation_states` table replaces `Translations::CachedStatus` so lists, counts and filters are queries. Every write still goes through its service; the state table is refreshed inside the same transaction.

**Tech Stack:** Rails 8.1, ViewComponent + Lookbook, Tailwind v4 (`bin/rails tailwindcss:build`), Stimulus via importmap (no npm), Minitest (no fixtures for content: `ContentHelper`), Cuprite system tests.

**Spec:** `docs/superpowers/specs/2026-10-03-cs-studio-design-pass-design.md` — §3, §4, §5.2, §5.3, §5.6 and §7 (which now includes two "Carried over from round 1" lists). Visual reference: `docs/design/cs-studio-handoff-v3/` — `Studio Pages.dc.html`, `Studio Post Editor.dc.html`, `Studio Dashboard.dc.html`, `Studio Posts.dc.html`, `Studio Translations.dc.html`, `Studio Modals.dc.html`, `Studio States v3.dc.html`, `StudioSidebar.dc.html`, `Studio Sign In.dc.html`, `Studio Password Reset.dc.html`; README §4.1–4.4, §9, §10. Open a mockup in a browser and copy sizes, spacing and copy from it; never its inline styles, hex values or markup.

**Code inventory:** the controller hands each implementer the relevant section of a code inventory (signatures, template outlines, routes, services, tests) taken at the start of this round. It is a snapshot: where it and the code disagree, the code wins.

## Global Constraints

- Server-rendered ERB and ViewComponents, Tailwind v4, Hotwire. New JS is a Stimulus controller in `app/javascript/controllers/admin/` (identifier `admin--<name>`). No React, no npm.
- Every new or changed component has a Lookbook preview in `test/components/previews/admin/` and a test in `test/components/admin/`.
- Tokens only: no raw colour literals and no `dark:` variants (`test/lib/admin_design_rules_test.rb` enforces both). Red (`danger*`) only for destructive actions and failures; translation states never use red.
- Never define `Admin::Media`, `Admin::Trash`, `Admin::Translations`, `Admin::AI`, `Admin::Ai` or `Admin::Dashboard`. Screen components live under `Admin::…Screen::` (`Admin::EditorScreen::`, `Admin::DashboardScreen::`, `Admin::PostsScreen::`, `Admin::TranslationScreen::`).
- Forms cannot nest. Dialog forms live once in the layout or as siblings of the editor form, and reach the form's fields with the `form=` attribute where needed.
- No inline event handlers (`test/lib/inline_handlers_test.rb`). Dialogs open with `data: dialog_trigger(id)`.
- Admin strings stay hard-coded English, each sentence one string.
- No permission rule changes. Every write goes through an `ApplicationService` with `authorize!` and `record_event` (`test/services/service_contract_test.rb`). Out-of-scope records are "not found", never "forbidden". Trashed records stay hidden at every list, search and picker (`test/integration/trash_visibility_test.rb` — add each new one).
- AI text is never saved until an editor presses **Use**. No part of an API key is rendered, logged or audited.
- Edits to a Live item still go live at once (spec §2): the editor header is the "no drafts" variant.
- Content is created in tests with `ContentHelper` (`create_page`, `create_post`, `create_media_asset`, `rich_doc`, `with_locales`); integration tests sign in with `sign_in_as(users(:one))`, system tests with `sign_in_via_form(users(:one))`. This Minitest has no `stub`.
- Prefix every test command with `PGGSSENCMODE=disable`. Run `bin/rails tailwindcss:build` before system tests. Never run tests in the background.
- Edit `app/assets/tailwind/content-spiel.tailwind.css` with targeted edits only; never rewrite it.
- Long, load-bearing comments are the norm: keep the ones that still apply, correct the ones your change makes false, and comment new non-obvious logic at the same density.
- Commits: conventional subjects, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Old and mixed `translation_sources` entries.** A record saved before this round has digest-only entries; after one field is re-saved it has both shapes. Every reader must treat a digest-only entry as "no stored source" (state unchanged, no diff, the plain outdated card) and never raise. Pinned in Task 1.
2. **Bulk actions over a mixed selection.** Some ids the viewer may publish, some they may only read, one trashed since the list loaded, one that doesn't exist, one outside their scope. Each permitted record is acted on, each refused one is counted and named, missing and out-of-scope ids are counted together as "not found", and nothing is acted on twice. Pinned in Task 17.
3. **Scheduling at a bad time.** A time in the past, exactly now, blank, unparseable, or inside a daylight-saving gap in the site time zone: the past and "now" answer "Pick a time in the future.", junk answers "Choose a date and time", and a gap time resolves the way `Time.zone.parse` resolves it, never a 500. Pinned in Task 5.
4. **The state table drifting from the truth.** Any write path that forgets `StateIndex.refresh` leaves chips, counts and filters wrong with no error. Pinned in Task 2 by a parity test over every service that can change a translation state, and by `translations:reindex` matching `Translations::Status` afterwards.
5. **Very long text in the word diff.** A 20,000-word body changed in one place must render a diff (or the "too long to compare" line) in well under a second and never hang the editor. Pinned in Task 1.

## File structure

New (each component `*.rb` + `*.html.erb` unless noted):

| File | Responsibility |
|---|---|
| `app/models/translations/source.rb` | Value object for one `translation_sources` entry, reading both shapes |
| `app/models/translations/source_diff.rb` | Word diff between a stored source text and the current original |
| `app/models/translations/state.rb` + migration | `translation_states` row |
| `app/models/translations/state_index.rb` | Refresh, rebuild and read the stored states |
| `lib/tasks/translations.rake` | `translations:reindex` |
| `app/components/admin/checkbox_component.rb` | Token-styled checkbox |
| `app/components/admin/chip_input_component` + `admin--chip-input` | Chip input with autocomplete (tags, related posts) |
| `app/components/admin/editor_screen/header_component` | The one editor header for pages and posts |
| `app/components/admin/editor_screen/schedule_dialog_component` | Schedule dialog (460) |
| `app/components/admin/editor_screen/changed_elsewhere_component` | The warn bar under the header |
| `app/components/admin/editor_screen/reference_card_component` | The original beside a translated field, incl. the outdated card with the diff |
| `app/components/admin/editor_screen/shared_fields_component` | "Shared fields (N)" row on translation tabs |
| `app/components/admin/translation_screen/pending_component` | Pending suggestion box |
| `app/components/admin/editor_screen/new_page_dialog_component`, `new_post_dialog_component` | New page / New post dialogs |
| `app/queries/dashboard/activity.rb` | Content-only, read-scoped audit feed |
| `app/components/admin/dashboard_screen/{card,activity_row,translation_card}_component` | Dashboard cards and feed rows |
| `app/components/admin/posts_screen/{toolbar,table,bulk_bar}_component` + `admin--bulk-select` | Posts list |
| `app/services/posts/bulk.rb` | Runs `Posts::Save` / `Trash::Move` over a selection |
| `app/components/admin/translation_screen/{matrix,summary_card}_component` | Translations matrix |

Removed: `Translations::CachedStatus` (+ test), `Admin::TranslationScreen::ListComponent`, `Admin::TagInputComponent`, `Admin::RecordHeaderComponent` (folded into `EditorScreen::HeaderComponent`), the `danger_outline` button variant, `app/views/admin/pages/new.html.erb` and `posts/new.html.erb` as full pages (their routes stay, rendering the dialog's form for non-JS and direct visits).

---

### Task 1: Source text for translations and the word diff

**Files:**
- Create: `db/migrate/<ts>_add_translation_original_changed_at.rb`, `app/models/translations/source.rb`, `app/models/translations/source_diff.rb`, `test/models/translations/source_test.rb`, `test/models/translations/source_diff_test.rb`
- Modify: `app/models/concerns/translations/tracker.rb`, `app/models/translations.rb`, `app/models/rich_text/document.rb` (`#plain_paragraphs`), `app/models/audit/snapshot.rb` (`IGNORED_CHANGES`), `app/services/translations/confirm.rb`, `test/models/concerns/translations/tracker_test.rb` (or the existing tracker test file)

**Interfaces:**
- Produces:
  - `translation_sources` entry, new shape: `{ "digest" => String, "text" => String | Array<String> | nil, "saved_at" => ISO-8601 String }`. Old shape (a bare digest String) stays valid.
  - `Translations::Source.wrap(entry) → Translations::Source | nil` with `#digest`, `#text` (nil for an old entry or a value that isn't text), `#saved_at` (Time or nil), `#stored_text?`.
  - `record.translation_source(field, locale) → Translations::Source | nil`.
  - `translation_original_changed_at` jsonb column (default `{}`, null false) on `pages`, `posts`, `content_blocks`, `media_assets`, `site_settings`: `{ field => ISO-8601 time }`. `record.translation_original_changed_at_for(field) → Time | nil`.
  - `Translations.source_text(value) → String | Array<String> | nil`: a stripped, newline-normalised String for a String; `document.plain_paragraphs` for a `RichText::Document`; nil for anything else (schema group values).
  - `RichText::Document#plain_paragraphs → Array<String>`: one plain-text string per top-level block node, in order, empty ones dropped; an image, YouTube or rule node contributes `"[image]"`, `"[video]"`, `"[rule]"`.
  - `Translations::SourceDiff.call(from:, to:) → Translations::SourceDiff::Result` with `#segments` (Array of `[:equal | :delete | :insert, String]`), `#changed?`, `#formatting_only?` (texts equal although the digests differ), `#too_long?`. `MAX_WORDS = 4000` per side.

- [ ] **Step 1: Failing tests for `Source`.**

```ruby
require "test_helper"

class Translations::SourceTest < ActiveSupport::TestCase
  test "an old entry is a bare digest: no text, no time" do
    source = Translations::Source.wrap("abc123")
    assert_equal "abc123", source.digest
    assert_nil source.text
    assert_nil source.saved_at
    assert_not source.stored_text?
  end

  test "a new entry carries digest, text and when it was saved" do
    source = Translations::Source.wrap("digest" => "abc", "text" => "Hello world", "saved_at" => "2026-10-04T09:30:00Z")
    assert_equal "abc", source.digest
    assert_equal "Hello world", source.text
    assert_equal Time.utc(2026, 10, 4, 9, 30), source.saved_at
    assert source.stored_text?
  end

  test "nothing stored is nil, and junk never raises" do
    assert_nil Translations::Source.wrap(nil)
    assert_nil Translations::Source.wrap("")
    [ 42, [], { "text" => "no digest" }, { "digest" => "d", "saved_at" => "not a time" } ].each do |junk|
      assert_nothing_raised { Translations::Source.wrap(junk)&.saved_at }
    end
    assert_nil Translations::Source.wrap("text" => "no digest")
  end
end
```

- [ ] **Step 2: Implement `Translations::Source`** (`Data.define(:digest, :text, :saved_at)`; `wrap` returns nil for blank, a String → `new(entry, nil, nil)`, a Hash with a present `"digest"` → new with `Time.iso8601` rescued to nil, anything else nil). Comment why both shapes exist (records saved before the design pass keep working and simply have no diff).

- [ ] **Step 3: Failing tracker tests** (add to the tracker's test file; `with_locales(%w[en de])` as that file already does):

```ruby
test "saving a translation stores the original's digest, its text and the time" do
  page = create_page(title: "About us")
  freeze_time do
    Pages::Save.call(page, translations: { "de" => { title: "Über uns" } })
    entry = page.reload.translation_sources.dig("title", "de")
    assert_equal Translations.digest("About us"), entry["digest"]
    assert_equal "About us", entry["text"]
    assert_equal Time.current.iso8601, entry["saved_at"]
  end
  assert_equal :current, page.translation_state(:title, "de")
end

test "an old digest-only entry still reads as current, then outdated, and has no stored text" do
  page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
  page.update_columns(translation_sources: { "title" => { "de" => Translations.digest("About us") } })
  assert_equal :current, page.reload.translation_state(:title, "de")
  assert_not page.translation_source(:title, "de").stored_text?

  Pages::Save.call(page, translations: { "en" => { title: "About the studio" } })
  assert_equal :outdated, page.reload.translation_state(:title, "de")
end

test "a record with both shapes side by side never raises" do
  page = create_page(title: "About us", translations: { "de" => { title: "Über uns", subtitle: "Wer wir sind" } })
  sources = page.translation_sources
  sources["title"]["de"] = sources["title"]["de"]["digest"] # downgrade one entry to the old shape
  page.update_columns(translation_sources: sources)
  page.reload
  assert_nothing_raised { page.class.translation_tracked_fields(page).each { |f| page.translation_state(f, "de") } }
end

test "changing the original records when, per field; changing a translation does not" do
  page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
  assert_nil page.translation_original_changed_at_for(:title)
  travel_to Time.zone.local(2026, 10, 4, 12, 0) do
    Pages::Save.call(page, translations: { "en" => { title: "About the studio" } })
  end
  assert_equal Time.zone.local(2026, 10, 4, 12, 0), page.reload.translation_original_changed_at_for(:title)
  assert_nil page.translation_original_changed_at_for(:subtitle)

  travel_to Time.zone.local(2026, 10, 5, 12, 0) do
    Pages::Save.call(page, translations: { "de" => { title: "Über das Studio" } })
  end
  assert_equal Time.zone.local(2026, 10, 4, 12, 0), page.reload.translation_original_changed_at_for(:title)
end

test "a whitespace-only change to the original is not a change" do
  page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
  Pages::Save.call(page, translations: { "en" => { title: "About us  " } })
  assert_nil page.reload.translation_original_changed_at_for(:title)
  assert_equal :current, page.translation_state(:title, "de")
end

test "rich text stores one plain string per paragraph" do
  post = create_post(title: "Notes")
  Posts::Save.call(post, translations: { "en" => { body: rich_doc("First paragraph.", "Second paragraph.") } })
  Posts::Save.call(post, translations: { "de" => { body: rich_doc("Erster Absatz.") } })
  assert_equal [ "First paragraph.", "Second paragraph." ], post.reload.translation_source(:body, "de").text
end

test "confirming refreshes the stored text and time; the audit event's field changes stay free of bookkeeping" do
  page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
  Pages::Save.call(page, translations: { "en" => { title: "About the studio" } })
  as_owner { Translations::Confirm.call(page.reload, field: :title, locale: "de") }
  assert_equal "About the studio", page.reload.translation_source(:title, "de").text
  assert_equal :current, page.translation_state(:title, "de")
  changed = Audit::Event.where(action: "page.updated").order(:id).last.field_changes.keys
  assert_not_includes changed, "translation_sources"
  assert_not_includes changed, "translation_original_changed_at"
end
```

(Adapt `rich_doc`'s call shape and `as_owner` to the helpers as they exist; if `rich_doc` takes one string, build the two-paragraph document the way the rich-text tests do.)

- [ ] **Step 4: Implement.** Migration adds the column to the five tables in one `change`. In the tracker:
  - `record_translation_sources` writes the new shape for a target-language value that changed: `{ "digest" => Translations.digest(original), "text" => Translations.source_text(original), "saved_at" => Time.current.iso8601 }`; still deletes the entry when the value is now blank.
  - A second `before_save` step, `record_original_changes`: for each tracked field whose **primary-language** value changed by digest (compare the digest of the value in the database with the digest of the value being saved — use the same per-field readers the state check uses, `attribute_in_database` for column-backed fields), set `translation_original_changed_at[field] = Time.current.iso8601`. A create sets nothing.
  - `translation_state` compares against `translation_source(field, locale)&.digest`.
  - `confirm_translation(field, locale)` writes the new shape.
  - `Translations::Confirm` persists `translation_sources` with `update_columns` as before (so `updated_at` doesn't move).
  - Add `"translation_original_changed_at"` beside `"translation_sources"` in `Audit::Snapshot::IGNORED_CHANGES`.
  - Comment the storage cost in the tracker: a body's text is stored once per target language it was translated into; acceptable at CMS scale, and what makes the diff possible.

- [ ] **Step 5: Failing diff tests.**

```ruby
require "test_helper"

class Translations::SourceDiffTest < ActiveSupport::TestCase
  def segments(from, to) = Translations::SourceDiff.call(from: from, to: to).segments

  test "a changed word is a delete followed by an insert, the rest equal" do
    assert_equal [ [ :equal, "We started in a " ], [ :delete, "spare" ], [ :insert, "small" ], [ :equal, " room." ] ],
      segments("We started in a spare room.", "We started in a small room.")
  end

  test "added and removed words at the ends" do
    assert_equal [ [ :equal, "Hello" ], [ :insert, " world" ] ], segments("Hello", "Hello world")
    assert_equal [ [ :delete, "Hello " ], [ :equal, "world" ] ], segments("Hello world", "world")
  end

  test "identical text has no changes and is formatting-only when asked about a changed digest" do
    result = Translations::SourceDiff.call(from: "Same text", to: "Same text")
    assert_not result.changed?
    assert result.formatting_only?
  end

  test "paragraph arrays are compared paragraph by paragraph, with added and removed paragraphs whole" do
    result = Translations::SourceDiff.call(from: [ "One.", "Two." ], to: [ "One.", "Two and a half.", "Three." ])
    assert result.changed?
    assert_includes result.segments, [ :insert, "Three." ]
    assert_includes result.segments, [ :equal, "One." ]
  end

  test "nil on either side means nothing to compare" do
    assert_not Translations::SourceDiff.call(from: nil, to: "x").changed?
    assert_empty Translations::SourceDiff.call(from: nil, to: "x").segments
  end

  test "text past the word cap is not diffed" do
    long = Array.new(Translations::SourceDiff::MAX_WORDS + 1, "word").join(" ")
    result = Translations::SourceDiff.call(from: long, to: long + " more")
    assert result.too_long?
    assert_empty result.segments
  end

  test "a 20,000-word body changed in one place answers quickly" do
    words = Array.new(20_000) { |i| "w#{i % 97}" }
    from = words.each_slice(200).map { |slice| slice.join(" ") }
    to = from.dup
    to[50] = to[50].sub("w3", "changed")
    elapsed = Benchmark.realtime { Translations::SourceDiff.call(from: from, to: to) }
    assert_operator elapsed, :<, 1.0
  end
end
```

- [ ] **Step 6: Implement `SourceDiff`.** Tokenise into words keeping whitespace attached to the following word (`text.scan(/\s*\S+|\s+\z/)`), run a longest-common-subsequence table over the two token arrays, walk it back into runs, and merge adjacent runs of the same kind into one segment. For arrays: pair paragraphs with an LCS over whole-paragraph equality first (so an inserted paragraph doesn't shift every later one), then word-diff only the paragraphs that sit between equal anchors in the same position; an unmatched paragraph is one whole `:delete` or `:insert`; separate paragraphs' segments with `[:equal, "\n"]`. The cap is per paragraph pair for arrays and per text for strings; `too_long?` when any compared pair exceeds it, and then `segments` is empty. Comment the cost: the table is words × words, so the cap bounds it at 16 million cells for the worst pair.

- [ ] **Step 7: Run** `PGGSSENCMODE=disable bin/rails db:migrate`, the three test files, then `PGGSSENCMODE=disable bin/rails test`. PASS. `bin/rubocop` clean.

- [ ] **Step 8: Commit.** `feat: translations remember the source text and when the original changed; word diff`

---

### Task 2: Stored translation state

**Files:**
- Create: `db/migrate/<ts>_create_translation_states.rb` (creates and fills), `app/models/translations/state.rb`, `app/models/translations/state_index.rb`, `lib/tasks/translations.rake`, `test/models/translations/state_index_test.rb`, `test/services/translation_state_parity_test.rb`
- Modify: `app/models/translations/status.rb` (`counts`), the services listed below, `app/components/admin/tree_component.rb`, `app/controllers/admin/posts_controller.rb`, `app/controllers/admin/translations_controller.rb` (reads only; its screen is rebuilt in Task 18)
- Delete: `app/models/translations/cached_status.rb`, `test/models/translations/cached_status_test.rb`

**Interfaces:**
- Produces:
  - Table `translation_states`: `record_type` (string), `record_id` (bigint), `locale` (string), `state` (string: `complete | missing | outdated`), `missing_count` (integer, default 0), `outdated_count` (integer, default 0), timestamps. Unique index on `(record_type, record_id, locale)`; index on `(locale, state)`. No foreign key (polymorphic). `Translations::State` with `self.table_name = "translation_states"`.
  - `Translations::Status.counts(records, locales: Translations.target_locales) → { record => { locale => { state:, missing:, outdated: } } }` — the same roll-up as `.for`, plus how many tracked fields (blocks included) are missing and outdated.
  - `Translations::StateIndex.refresh(record)` — `record` is a Page, Post, Media::Asset or SiteSetting; a ContentBlock refreshes its owner. Upserts one row per target locale and deletes rows for locales that are no longer targets. A trashed record keeps its rows.
  - `Translations::StateIndex.remove(record)` — deletes the record's rows (permanent delete).
  - `Translations::StateIndex.rebuild_all` — recomputes every row; `bin/rails translations:reindex`.
  - `Translations::StateIndex.states_for(records, locales: Translations.target_locales) → { record => { locale => Symbol } }` — one query; a record with no row reads `:complete`.
  - `Translations::StateIndex.counts_for(records) → { record => { locale => { missing:, outdated: } } }`.
  - `Translations::StateIndex.joins(relation, locale:, states:) → relation` — narrows a Page/Post/Media::Asset relation to records whose state in `locale` is one of `states`.
  - `Translations::StateIndex.summary(locale, relations) → { total:, complete:, missing:, outdated: }` over the given read-scoped relations (items, not fields).

- [ ] **Step 1: Failing tests** `test/models/translations/state_index_test.rb`:

```ruby
require "test_helper"

class Translations::StateIndexTest < ActiveSupport::TestCase
  setup { @locales = with_locales(%w[en de es]) } # as the status tests set locales up

  def state(record, locale) = Translations::State.find_by(record_type: record.class.polymorphic_name, record_id: record.id, locale: locale)

  test "a new page is missing in every other language" do
    page = create_page(title: "About")
    assert_equal %w[missing missing], %w[de es].map { |l| state(page, l).state }
    assert_equal 1, state(page, "de").missing_count
  end

  test "translating the title completes that language; changing the original outdates it" do
    page = create_page(title: "About")
    Pages::Save.call(page, translations: { "de" => { title: "Über" } })
    assert_equal "complete", state(page, "de").state
    Pages::Save.call(page, translations: { "en" => { title: "About us" } })
    assert_equal "outdated", state(page.reload, "de").state
    assert_equal 1, state(page, "de").outdated_count
  end

  test "a block's fields count towards its page, and deleting the block takes them away" do
    page = create_page(title: "About", translations: { "de" => { title: "Über" } })
    block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "image", media_asset_id: create_media_asset(alt: "A desk").id }).record
    ContentBlocks::Save.call(block, translations: { "de" => { caption: "Schreibtisch" } })
    ContentBlocks::Save.call(block, translations: { "en" => { caption: "The desk" } })
    assert_equal "outdated", state(page, "de").state
    ContentBlocks::Destroy.call(block)
    assert_equal "complete", state(page, "de").state
  end

  test "confirming an outdated field updates the row" do
    page = create_page(title: "About", translations: { "de" => { title: "Über" } })
    Pages::Save.call(page, translations: { "en" => { title: "About us" } })
    as_owner { Translations::Confirm.call(page.reload, field: :title, locale: "de") }
    assert_equal "complete", state(page, "de").state
  end

  test "trashing keeps the rows, purging removes them" do
    page = create_page(title: "About")
    as_owner { Trash::Move.call(page) }
    assert state(page, "de")
    as_owner { Trash::Purge.call(page.reload) }
    assert_nil state(page, "de")
  end

  test "states_for answers in one query and treats a record with no row as complete" do
    pages = 3.times.map { |i| create_page(title: "P#{i}") }
    Translations::State.where(record_id: pages.last.id).delete_all
    queries = count_queries { @states = Translations::StateIndex.states_for(pages) }
    assert_equal 1, queries
    assert_equal :missing, @states[pages.first]["de"]
    assert_equal :complete, @states[pages.last]["de"]
  end

  test "joins narrows a relation by state in one language" do
    done = create_page(title: "Done", translations: { "de" => { title: "Fertig" } })
    create_page(title: "Todo")
    assert_equal [ done ], Translations::StateIndex.joins(Page.kept.where.not(parent_id: nil), locale: "de", states: %w[complete]).to_a
  end

  test "summary counts items, not fields" do
    create_page(title: "Done", translations: { "de" => { title: "Fertig" } })
    create_page(title: "Todo")
    summary = Translations::StateIndex.summary("de", [ Page.kept.where.not(parent_id: nil) ])
    assert_equal({ total: 2, complete: 1, missing: 1, outdated: 0 }, summary)
  end

  test "rebuild_all repairs rows that drifted and equals Translations::Status" do
    page = create_page(title: "About", translations: { "de" => { title: "Über" } })
    Translations::State.where(record_id: page.id).update_all(state: "missing")
    Translations::State.where(record_id: page.id, locale: "es").delete_all
    Translations::StateIndex.rebuild_all
    truth = Translations::Status.for([ page ])[page]
    assert_equal truth.transform_values(&:to_s), { "de" => state(page, "de").state, "es" => state(page, "es").state }
  end
end
```

(Use the suite's existing query counter; the dashboard and posts tests have one — reuse it rather than writing another. Adapt `create_media_asset`'s arguments.)

- [ ] **Step 2: Parity test** `test/services/translation_state_parity_test.rb` — the guard against a write path that forgets the index:

```ruby
require "test_helper"

# Every service that can change what Translations::Status would answer must
# leave translation_states agreeing with it. One scenario per service; after
# each, the stored rows are compared with a fresh computation.
class TranslationStateParityTest < ActiveSupport::TestCase
  setup { with_locales(%w[en de es]) }

  def assert_parity(*records)
    records.each do |record|
      truth = Translations::Status.for([ record.reload ])[record].transform_values(&:to_s)
      stored = Translations::State.where(record_type: record.class.polymorphic_name, record_id: record.id).pluck(:locale, :state).to_h
      assert_equal truth, stored, "#{record.class.name} ##{record.id} drifted"
    end
  end

  test "pages, posts, blocks, images, settings, confirm, trash and restore all keep the index in step" do
    as_owner do
      page = create_page(title: "About")
      post = create_post(title: "Hello")
      asset = create_media_asset(alt: "A desk")
      assert_parity page, post, asset, Current.site

      Pages::Save.call(page, translations: { "de" => { title: "Über" } })
      Posts::Save.call(post, translations: { "de" => { title: "Hallo" } })
      Media::Save.call(asset, translations: { "de" => { alt: "Ein Schreibtisch" } })
      Settings::Save.call(translations: { "de" => { title: "Seite" } })
      assert_parity page, post, asset, Current.site

      block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" },
        translations: { "en" => { body: rich_doc("Text") } }).record
      assert_parity page
      ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Text DE") } })
      ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Text changed") } })
      assert_parity page
      Translations::Confirm.call(block.reload, field: :body, locale: "de")
      assert_parity page
      ContentBlocks::Destroy.call(block)
      assert_parity page

      Trash::Move.call(post)
      Trash::Restore.call(post.reload)
      assert_parity post
    end
  end

  test "turning a language off, on, and changing the default language re-indexes" do
    as_owner do
      page = create_page(title: "About", translations: { "de" => { title: "Über" } })
      # Use the real services behind Settings › Languages; find them with
      # `ls app/services/languages` and call each the way its own test does.
      disable_language("es")
      assert_equal %w[de], Translations::State.where(record_id: page.id, record_type: "Page").pluck(:locale)
      enable_language("es")
      assert_parity page
      change_default_language("de")
      assert_parity page
    end
  end
end
```

Implement the three private helpers in the test with the actual services. If a media or settings service has a different name or call shape, adapt the call, never the assertion.

- [ ] **Step 3: Implement `Status.counts`, `State`, `StateIndex`.** `refresh` computes through `Status.counts([owner])` and writes with `upsert_all(..., unique_by: %i[record_type record_id locale])`, then deletes rows whose locale isn't in `Translations.target_locales`. `rebuild_all` walks Page, Post, Media::Asset (kept and trashed alike) in batches of 200 plus the SiteSetting row, then deletes rows whose record no longer exists. Comment in `StateIndex`: it is derived data like `public_paths` and `media_usages` — never written by hand, rebuilt by `translations:reindex` whenever it is suspected stale.

- [ ] **Step 4: Call `refresh` inside each service's transaction**, after the record is saved:
  - `Pages::Save`, `Posts::Save`, `Media::Save` (and `Media::Upload` for a new asset), `Settings::Save` → the record.
  - `ContentBlocks::Save`, `ContentBlocks::Destroy` and the duplicate path → the block's owner.
  - `Translations::Confirm` → the record (owner for a block).
  - `Trash::Purge` → `StateIndex.remove` for each destroyed page, post and image.
  - The language services (enable, disable, reorder if it can change targets, default change) → `StateIndex.rebuild_all`. Comment: synchronous and proportional to the site's size; fine while sites are small, and the natural thing to move into a job later.
  - `RichText::ActionTextImport` and `StarterContents::Add` write through the save services already; verify with the parity test rather than adding calls.

- [ ] **Step 5: Migration.** Create the table, then fill it with `Translations::StateIndex.rebuild_all` inside `up` (guarded with `reset_column_information`); `down` drops the table. Rake task:

```ruby
namespace :translations do
  desc "Recompute the stored translation state of every page, post, image and the site settings"
  task reindex: :environment do
    Translations::StateIndex.rebuild_all
    puts "Reindexed #{Translations::State.count} translation state rows."
  end
end
```

- [ ] **Step 6: Switch the readers and delete `CachedStatus`.** `Admin::TreeComponent#translation_states_for` and `Admin::PostsController#index` read `StateIndex.states_for`; the translations controller's `needing_work` becomes `StateIndex.joins(readable(type), locale: @locale, states: %w[missing outdated])` with a real `COUNT` and `offset/limit` (its Ruby batch walk and the comment explaining it go). Remove `CachedStatus`, its test, and every mention in comments and CLAUDE.md is corrected in Task 19. Existing tests for the tree markers, the posts list chips and the translations overview must pass unchanged.

- [ ] **Step 7: Run** the two new test files, `test/models/translations`, `test/integration/admin/{posts,translations,page_editor}_test.rb`, `test/integration/trash_visibility_test.rb`, `test/services/service_contract_test.rb`, then the whole unit suite. PASS.

- [ ] **Step 8: Commit.** `feat: stored translation state replaces the cached status`

---

### Task 3: Round 1 departures — shell, shared parts, sign-in

**Files:**
- Modify: `app/components/admin/shell/sidebar_component.{rb,html.erb}`, `shell/top_bar_component.html.erb`, `shell/command_palette_component.html.erb`, `app/views/admin/jump/show.html.erb`, `app/queries/jump/search.rb`, `app/javascript/controllers/admin/command_palette_controller.js`, `app/components/admin/language_tabs_component.html.erb`, `app/components/admin/save_bar_component.html.erb`, `app/components/admin/button_component.rb`, `app/components/admin/settings_form_component.html.erb` (logo field), `app/components/admin/permission_matrix_component.html.erb` and the users/groups forms (checkboxes), `app/views/layouts/product.html.erb`, `app/views/admin/sessions/new.html.erb`, `app/views/admin/passwords/{new,edit}.html.erb`, `app/components/admin/password_field_component.html.erb`, `app/assets/tailwind/content-spiel.tailwind.css`, every caller of `variant: :danger_outline`
- Create: `app/components/admin/checkbox_component.rb` + test + preview

**Interfaces:**
- Produces:
  - `Admin::CheckboxComponent.new(name:, value: "1", checked: false, id: nil, label: nil, disabled: false, **html)` — a native checkbox with class `cs-checkbox` (accent fill, 2px radius, visible focus ring; unchecked value handled by the caller as today).
  - `Admin::ButtonComponent` variants: `primary`, `secondary`, `ghost`, `danger` (solid, dialog confirms only), `danger_text` (secondary border, `text-danger-ink` label — the trigger for a destructive action). `danger_outline` no longer exists.
  - `Jump::Search#groups` labels and order: `Pages`, `Posts`, `Media`, `Sections` (CS Studio's modules), `Settings` (rows like "Settings › Languages", only for a viewer with `settings.manage` / `languages.manage`), `Actions`.

- [ ] **Step 1: Failing tests.**

```ruby
# test/components/admin/checkbox_component_test.rb
require "test_helper"

class Admin::CheckboxComponentTest < ViewComponent::TestCase
  test "a token-styled native checkbox with its label" do
    render_inline(Admin::CheckboxComponent.new(name: "user[group_ids][]", value: "3", checked: true, id: "group-3", label: "Editors"))
    assert_selector "input#group-3.cs-checkbox[type=checkbox][name='user[group_ids][]'][value='3'][checked]"
    assert_selector "label[for='group-3']", text: "Editors"
  end

  test "disabled is passed through" do
    render_inline(Admin::CheckboxComponent.new(name: "x", disabled: true))
    assert_selector "input.cs-checkbox[disabled]"
  end
end
```

Add to `test/components/admin/button_component_test.rb`:

```ruby
test "danger_text is a secondary button with danger-coloured text; danger_outline is gone" do
  render_inline(Admin::ButtonComponent.new(label: "Move to trash", variant: :danger_text))
  assert_selector "button.border-line-strong.text-danger-ink", text: "Move to trash"
  assert_raises(ArgumentError) { Admin::ButtonComponent.new(label: "x", variant: :danger_outline) }
end
```

Add to `test/components/admin/shell/sidebar_component_test.rb`:

```ruby
test "the wordmark is uppercase with the site name under it" do
  render_sidebar(labels: %w[Dashboard])
  assert_selector ".admin-wordmark", text: "CONTENT·SPIEL"
  assert_selector ".admin-wordmark + .admin-site-name", text: Current.site.title
end

test "a user without a name shows the email once, with the role inline" do
  user = users(:one)
  user.name = nil
  render_sidebar(labels: %w[Dashboard], user: user)
  assert_selector ".admin-account", text: user.email_address, count: 1
  assert_equal 1, page.find(".admin-account").text.scan(user.email_address).size
  assert_selector ".admin-account", text: "Owner"
  assert_no_selector ".admin-account .font-cs-mono", text: /owner/i
end
```

Add to `test/queries/jump/search_test.rb`:

```ruby
test "modules are listed under Sections, and Settings holds settings destinations" do
  groups = search("", actor: @owner)
  assert_includes groups.map { |g| g[:label] }, "Sections"
  settings = groups.find { |g| g[:label] == "Settings" }
  assert_includes settings[:rows].map { |r| r[:title] }, "Settings › Languages"
  assert_not_includes settings[:rows].map { |r| r[:title] }, "Dashboard"
end
```

- [ ] **Step 2: Shell.** Wordmark: `span.admin-wordmark` (`font-cs text-xs font-bold uppercase tracking-wide`, text "CONTENT·SPIEL") and `span.admin-site-name` (`text-[13px] text-dim`, the site title in the default language) in both the sidebar and the top bar. Account block: name line; the email line only when it differs from the name line; then the role text ("Owner", up to two group names "+N", "No groups") in the same sans `text-xs text-meta`, no mono capitals. Sidebar height: the sidebar column is `position: sticky; top: 0; height: 100vh` with its own scroll, and its background fills the whole grid cell (`align-self: stretch` on the cell, `bg-chrome` on the cell, not only on the inner nav) — verify on a page taller than the window in both themes.

- [ ] **Step 3: Overlay, tabs, save bar, buttons, checkboxes.**
  - `.admin-dialog::backdrop` and `.admin-shell__scrim`: `color-mix(in oklab, var(--cs-ink) 38%, transparent)` — check the computed value in a system test against a probe element, since Design read the current one as ~50% grey.
  - Language tab dots: 7px, vertically centred on the label (`inline-flex items-center` on the tab, dot `size-[7px]`).
  - Save bar: sticky to the bottom of `<main>` across its full width (`-mx-6` no longer inside the form column — render it full-bleed with `border-t border-line bg-surface`); the count `text-[13px] text-dim` sans; the button reads "Save".
  - Replace `danger_outline` with `danger_text` at every call site (`grep -rn danger_outline app test`), and the buttons in the CSS guard test.
  - `.cs-checkbox` rule (tokens only: `accent-color: var(--cs-accent)`, `border-radius: var(--cs-radius)`, focus ring) and `CheckboxComponent` used on the users form's group cards, the group form's members and the permission matrix.
  - Settings logo: `Admin::FileDropComponent.new(name: …, id: …, label: "Logo", …)` in place of the native input (the Settings form still autosaves this round; a chosen file must still upload — keep the existing upload path and its test).

- [ ] **Step 4: ⌘K.** Footer hint row inside the dialog ("↑↓ MOVE · ↵ OPEN · ⌘↵ NEW TAB", mono 10px `text-meta`), an "ESC" chip beside the input; rows show `Admin::StatusChipComponent(hide_live: true)` on the right for pages and posts and the selected row a "↵" hint; `⌘/Ctrl+Enter` opens the selected row in a new tab (`window.open(href, "_blank", "noopener")`). `Jump::Search`: rename the modules group to "Sections" and add the "Settings" group (Site, Publishing, Languages, AI translation — each an anchor into the Settings screen, shown only with the permission that section needs). Update the palette's controller and system tests for the renamed group and the new key.

- [ ] **Step 5: Sign-in and reset** per `Studio Sign In.dc.html` / `Studio Password Reset.dc.html`: the form directly on the page, 360px wide, no card; the site name (default-language title) above the heading; heading `text-[28px] font-semibold`; reset heading "Reset password"; Show/Hide `text-xs font-medium text-accent` sans (change it in `PasswordFieldComponent`, so setup and change-password get the same); "Forgot your password?" right-aligned on the Password label row, `text-xs`, not underlined; "← Back to sign in" not underlined (underline on hover only). Update the sessions, passwords and password-field tests for the new markup; keep every non-disclosure assertion.

- [ ] **Step 6: Media picker positioning.** Open the picker in a real browser session (the system test `media_picker_test.rb` at 1400×900, page scrolled down 600px first) and assert the dialog's bounding box lies inside the viewport and the page behind hasn't moved (`window.scrollY` unchanged). If it fails, fix the cause (the `<dialog>` must be opened with `showModal()` from the layout level, not inside a transformed or `contain`-ed ancestor); if it passes, record in the report that Design's screenshot was a capture artefact.

- [ ] **Step 7: Run** `bin/rails tailwindcss:build`, the touched component tests, `test/lib`, `test/queries/jump`, `test/system/{shell,command_palette,dialog,save_bar,password_field}_test.rb`, `test/system/admin/media_picker_test.rb`, then the unit suite. PASS.

- [ ] **Step 8: Commit.** `fix: round 1 departures from the handoff — shell, overlay, save bar, checkbox, palette, sign-in`

---

### Task 4: The editor header

**Files:**
- Create: `app/components/admin/editor_screen/header_component.{rb,html.erb}`, test, preview
- Modify: `app/views/admin/pages/show.html.erb`, `app/components/admin/post_form_component.{rb,html.erb}` (its header markup moves out), `app/components/admin/save_status_component.{rb,html.erb}`, `app/javascript/controllers/admin/autosave_controller.js` (status texts), `app/controllers/admin/{pages,posts}_controller.rb` (none of the actions change; only what `show` renders)
- Delete: `app/components/admin/record_header_component.*` (+ test, preview); move its tests' assertions into the new component's test

**Interfaces:**
- Consumes: `LanguageTabsComponent`, `StatusChipComponent`, `MenuComponent`, `ButtonComponent`, `ConfirmDialogComponent`, `dialog_trigger`, `TimeAgoComponent`, `Translations::Status.switcher_locales`.
- Produces: `Admin::EditorScreen::HeaderComponent.new(record:, locale:, url_options: {})` for a Page or a Post. Public readers the later tasks use: `#editable?`, `#schedule_dialog_id` (`"schedule-<page|post>-<id>"`), `#delete_dialog_id` (unchanged ids `delete-page-<id>` / `delete-post-<id>`), `#save_status_id` (unchanged: `page-save-status` / `post-save-status`). Slots: `suggest` (Task 9 fills it), `notice` (Task 6 fills it). Root element `header.admin-editor-header[data-record-type][data-record-id]`.

- [ ] **Step 1: Failing component tests** (one file; `create_page`/`create_post`, `as_owner`, reader via `users(:reader)`):

```ruby
require "test_helper"

class Admin::EditorScreen::HeaderComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_header(record, locale: "en", actor: users(:one))
    as(actor, channel: :admin) { render_inline(Admin::EditorScreen::HeaderComponent.new(record: record, locale: locale)) }
  end

  test "a draft: breadcrumb, title, Draft chip, Preview and one primary Publish, the rest in the menu" do
    page = create_page(title: "About", published: false)
    render_header(page)
    assert_selector "nav[aria-label='Breadcrumb']", text: "Pages"
    assert_selector "h1", text: "About"
    assert_selector ".admin-status-chip[data-status=draft]"
    assert_selector "a", text: "Preview"
    assert_selector "button.bg-accent", text: "Publish", count: 1
    assert_selector "[role=menu] a", text: "Activity", visible: :all
    assert_selector "[role=menu] button", text: "Schedule…", visible: :all
    assert_selector "[role=menu] button", text: "Move to trash", visible: :all
    assert_no_selector "[role=menu] button", text: "Unpublish", visible: :all
  end

  test "a live record: no primary button, the live hint, Unpublish in the menu, View on site" do
    page = create_page(title: "About", published: true)
    render_header(page)
    assert_no_selector "button.bg-accent"
    assert_selector "[role=status]", text: "This page is live. Changes appear on the site as soon as they’re saved."
    assert_selector "[role=menu] button", text: "Unpublish", visible: :all
    assert_selector "a[href='/about']", text: "View on site"
  end

  test "a scheduled record: Publish now primary and Edit schedule secondary" do
    post = create_post(title: "Later", published: false)
    as_owner { Posts::Save.call(post, attributes: { published_at: 3.days.from_now }) }
    render_header(post.reload)
    assert_selector "button.bg-accent", text: "Publish now"
    assert_selector "button", text: "Edit schedule"
    assert_selector ".admin-status-chip[data-status=scheduled]"
  end

  test "the menu's last item is Move to trash, after a divider; the homepage has it disabled with the reason" do
    render_header(root_page)
    items = page.all("[role=menu] :is(a, button)", visible: :all).map { |i| i.text(:all).strip }
    assert_equal "Move to trash", items.last
    assert_selector "[role=menu] button[disabled][title='The homepage can’t be deleted']", text: "Move to trash", visible: :all
  end

  test "a viewer who can only read sees View only, Preview and Activity, nothing that writes" do
    post = create_post(title: "Read me")
    render_header(post, actor: users(:reader))
    assert_selector "[data-view-only]", text: "View only"
    assert_no_selector "button", text: /Publish|Unpublish|Schedule|Move to trash/, visible: :all
  end

  test "a post shows its type and, unlisted, says so" do
    post = create_post(title: "Loose")
    render_header(post)
    assert_selector ".admin-type-dot"
    assert_text "Not listed on any page yet — add a post list block for this type"
  end
end
```

(The reader fixture needs `audit.view` for Activity; assert Activity only for the owner if the reader lacks it. Adapt the scheduled-post set-up to how the posts tests schedule.)

- [ ] **Step 2: Build the component** from `Studio Pages.dc.html` / `Studio Post Editor.dc.html` (default, `drafts` off) and README §4.1, §9 B15:
  - `header.admin-editor-header` `sticky top-0 z-10 -mx-6 -mt-6 mb-6 border-b border-line bg-paper px-7 pt-4`.
  - Row 1: breadcrumb left (`nav[aria-label="Breadcrumb"]`, 12px `text-meta`: "Pages / <parent titles> /" or "Posts / <type label> /", each crumb a link the viewer may open, plain text otherwise). Right: the save status (`SaveStatusComponent`, mono 11px), **Preview** (secondary link, new tab), the primary button, then the ⋯ `MenuComponent` (`label: "More"`, visually "⋯", `aria-label="More actions"`).
  - Primary button by state: Draft → "Publish"; Scheduled → "Publish now" + secondary "Edit schedule" (`data: dialog_trigger(schedule_dialog_id)`); Live → none. Each is a `button_to` to the existing publish route with `form: { data: { turbo_frame: "_top" } }` (posts too — today the post's lack `_top`, so the sidebar and badge don't refresh).
  - Row 2: `h1` (26px/600, `truncate`) + `StatusChipComponent` (never hidden in an editor) + the View only chip (dashed border) when `!editable?`; posts: `ContentTypeDotComponent` after the chips.
  - Row 3: the public path (mono 12px `text-dim`), Copy, "View on site ↗" when live; a post with no path shows the unlisted sentence.
  - Live hint (`p[role=status]`, 13px `text-dim`): "This page is live. Changes appear on the site as soon as they’re saved." / "This post is live. …".
  - Row 4: `LanguageTabsComponent` left; right-aligned `suggest` slot.
  - Below: `notice` slot.
  - Menu items in order: Activity (link, with `audit.view`), Schedule… (button, `dialog_trigger(schedule_dialog_id)`, with publish right, not when live), Unpublish (button opening a confirm dialog `unpublish-<type>-<id>` — reversible, so `primary`, copy per handoff §10 A8: title "Unpublish this page?", body "It will show “not found” on the site. Subpages also show not found." for a page with kept subpages, "It will show “not found” on the site." otherwise), divider, Move to trash (`text-danger-ink`, opens the existing delete dialog). Keep the homepage's disabled state and reason.
  - The dialogs (delete, unpublish) render as siblings after the header, each with its own `button_to`/form (`turbo_frame: "_top"`).
- [ ] **Step 3: Save status wording.** `SaveStatusComponent`: saved → "SAVED 10:42" and, for a live record, "● SAVED TO SITE 10:42" in `text-ok-ink` (new keyword `live: false`); saving → "SAVING…"; the failure states read "NOT SAVED · Retry" with the Retry part a button that calls `admin--autosave#saveNow`. Mono 11px uppercase. Keep the `stale`, `forbidden`, `signed_out` states and ids. Update the strings duplicated in `autosave_controller.js` (`static texts`) and both tests that pin them; the autosave controller reads a `data-live` flag from the status element to choose the live wording when it writes "SAVING…"-style text itself.
- [ ] **Step 4: Use it** in `pages/show.html.erb` and at the top of `PostFormComponent` (its inline header goes; the form below is untouched in this task). Delete `RecordHeaderComponent`, moving its "View on site is a same-origin path / Copy uses the request origin" tests into the new test file unchanged in meaning.
- [ ] **Step 5: System test** `test/system/admin/editor_header_test.rb`: open a draft page; assert one primary "Publish"; open the ⋯ menu by keyboard (focus, Enter, ArrowDown to "Schedule…"); Escape returns focus to the menu button; press Publish; assert the chip reads Live, the primary button is gone, the hint is shown and the tree no longer shows a Draft chip for that page; open ⋯ → Unpublish → confirm; assert Draft again.
- [ ] **Step 6: Run** `bin/rails tailwindcss:build`, the component test, `test/integration/admin/{page_editor,posts}_test.rb` (update selectors pinned to the old header; keep every assertion's meaning), the new system test, `test/system/admin/{autosave,view_only}_test.rb`. PASS.
- [ ] **Step 7: Commit.** `feat: one editor header for pages and posts — a primary action and a menu`

---

### Task 5: The Schedule dialog

**Files:**
- Create: `app/components/admin/editor_screen/schedule_dialog_component.{rb,html.erb}`, test, preview
- Modify: `app/controllers/admin/{pages,posts}_controller.rb` (`schedule`), `app/services/{pages,posts}/save.rb` (nothing, unless the past-time rule belongs there — see Step 2), `app/components/admin/editor_screen/header_component.html.erb` (renders the dialog; removes the interim `<details>` panel)

**Interfaces:**
- Produces: `Admin::EditorScreen::ScheduleDialogComponent.new(record:, url_options: {}, error: nil)`, dialog id `schedule-<page|post>-<id>`, width `form_narrow` (460). Controller: `schedule` with `params[:published_at]` blank + `params[:remove] == "1"` removes the schedule (back to Draft).

- [ ] **Step 1: Failing integration tests** (add to `page_editor_test.rb`; mirror two of them in `posts_test.rb`):

```ruby
test "scheduling in the past, or for right now, is refused with the dialog's own message" do
  page = create_page(title: "Later", published: false)
  travel_to Time.zone.local(2026, 10, 4, 12, 0) do
    [ "2026-10-04T11:59", "2026-10-04T12:00" ].each do |value|
      post schedule_admin_page_path(page), params: { published_at: value }
      follow_redirect!
      assert_select "dialog#schedule-page-#{page.id} [role=alert]", text: "Pick a time in the future."
      assert_nil page.reload.published_at
    end
  end
end

test "junk and blank answer Choose a date and time; nothing is saved" do
  page = create_page(title: "Later", published: false)
  [ "", "soon", "2026-13-45T99:99" ].each do |value|
    post schedule_admin_page_path(page), params: { published_at: value }
    follow_redirect!
    assert_select "dialog#schedule-page-#{page.id} [role=alert]", text: "Choose a date and time"
    assert_nil page.reload.published_at
  end
end

test "a time inside a daylight-saving gap is accepted the way the site zone resolves it" do
  site_settings(:default).update!(time_zone: "Berlin")
  page = create_page(title: "Later", published: false)
  travel_to Time.utc(2027, 3, 1) do
    post schedule_admin_page_path(page), params: { published_at: "2027-03-28T02:30" } # 02:30 doesn't exist that night in Berlin
    assert_response :see_other
    assert_equal Time.use_zone("Berlin") { Time.zone.parse("2027-03-28T02:30") }, page.reload.published_at
  end
end

test "a valid time schedules, in the site time zone, and Remove schedule goes back to draft" do
  site_settings(:default).update!(time_zone: "Berlin")
  page = create_page(title: "Later", published: false)
  travel_to Time.utc(2026, 10, 4, 10, 0) do
    post schedule_admin_page_path(page), params: { published_at: "2026-10-06T09:00" }
    assert_equal Time.utc(2026, 10, 6, 7, 0), page.reload.published_at
    assert_equal "scheduled", page.status
    post schedule_admin_page_path(page), params: { remove: "1" }
    assert_nil page.reload.published_at
  end
end

test "the dialog names the site time zone and only offers Remove schedule when there is one" do
  site_settings(:default).update!(time_zone: "Berlin")
  page = create_page(title: "Later", published: false)
  get admin_page_path(page)
  assert_select "dialog#schedule-page-#{page.id}", text: /Berlin time \(GMT\+[12]\), the site’s time zone\./
  assert_select "dialog#schedule-page-#{page.id} button", text: "Remove schedule", count: 0
end
```

- [ ] **Step 2: Implement.** The future-time rule lives in the controllers' `schedule` (it is a rule of this dialog, not of saving: `Pages::Save` may legitimately set a past `published_at`, e.g. imports and "Publish now"): parse with `Time.zone.parse` (rescue `ArgumentError`), nil or blank → flash `schedule_error: "Choose a date and time"`; `at <= Time.current` → `"Pick a time in the future."`; then the service as today. `remove=1` → `Pages::Save.call(record, attributes: { published_at: nil })` with notice "Schedule removed". On an error redirect back to the editor with `flash[:schedule_error]`, and render the dialog with `error:` and the attribute `data-admin--dialog-open-on-load` — add to `admin--dialog` a small `connect`-time pass that `showModal()`s any dialog carrying that attribute, so the editor reopens the dialog with its message (toasts are never used for form errors).
- [ ] **Step 3: Component** per `Studio Modals.dc.html` / States B21: title "Schedule publishing"; a `datetime-local` input (label "Date and time", value = the current schedule or tomorrow 09:00 in the site zone, `min` = now); the zone line built as one string from `Current.site.effective_time_zone` ("Berlin time (GMT+1), the site’s time zone." — name from the zone, offset from `formatted_offset` at the chosen default time); the error line `p[role=alert]`; footer: "Remove schedule" bottom-left as a `ghost` submit with `name="remove" value="1"` only when the record is scheduled; right: Cancel (ghost), "Schedule" (primary). One form posting to the existing schedule route, `data-turbo-frame="_top"`.
- [ ] **Step 4: System test** in `editor_header_test.rb`: ⋯ → Schedule… opens the dialog with focus in the date field; submitting a past time reopens the dialog showing "Pick a time in the future."; a future time closes it and the chip reads Scheduled; "Edit schedule" reopens it with "Remove schedule" present.
- [ ] **Step 5: Run** the integration tests for pages and posts, the component test, the system test. PASS.
- [ ] **Step 6: Commit.** `feat: Schedule dialog with the site time zone and a future-time rule`

---

### Task 6: View only, and "Changed elsewhere"

**Files:**
- Create: `app/components/admin/editor_screen/changed_elsewhere_component.{rb,html.erb}`, test, preview
- Modify: `app/controllers/concerns/admin/autosave_responses.rb`, `app/javascript/controllers/admin/autosave_controller.js`, `app/components/admin/save_status_component.rb`, `app/components/admin/page_settings_form_component.html.erb`, `post_form_component.html.erb`, `block_card_component.html.erb`, `block_picker_component.rb`, `columns/rich_text_column_component.html.erb`, `app/assets/tailwind/content-spiel.tailwind.css`

**Interfaces:**
- Consumes: `Dashboard::Feed#last_change`-style lookup → use `Audit::Event` newest for the record (and its blocks) ignoring `access.denied`; `Admin::UserNameComponent`, `TimeAgoComponent`.
- Produces:
  - `Admin::EditorScreen::ChangedElsewhereComponent.new(record:, reload_url:)` → `div#changed-elsewhere.bg-warn-tint[role=alert]` "Changed by <name> <time ago>. Your text is still here so you can copy it; reloading shows the latest version." + a "Reload" link (`data-turbo-frame="_top"`).
  - **Behaviour change:** an autosave sent with a stale base is **not saved** any more. `autosave_stream` answers status 409 with the `:stale` status ("● CHANGED ELSEWHERE", `text-warn-ink`) and a stream that puts the bar into `#editor-notice`; the base field is not advanced. The autosave controller treats 409 as final: it stops queuing saves for that form (`paused`), leaves the fields' local text in place, and does not retry.
  - View only: `fieldset[disabled]` content renders with class `admin-view-only` (sunken, dim); no rich-text toolbar, no drag handles, no block ⋯ menu, no Add block, no autosave controller; the hint line under the header: "You can view this page but not change it." / "…this post…" (and, when the reason is the publish rule, "It is live, and changing a live page needs the right to publish.").

- [ ] **Step 1: Failing tests.** Replace `page_editor_test.rb`'s "a stale base still saves and warns" with:

```ruby
test "a save made on a stale base is refused, names who changed it, and keeps the newer text" do
  page = create_page(title: "About")
  stale = page.updated_at.iso8601(6)
  as(users(:one), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Changed by someone else" } }) }

  patch admin_page_path(page), params: { base_updated_at: stale, page: { subtitle: "My stale edit" } }, as: :turbo_stream
  assert_response :conflict
  assert_equal "Changed by someone else", page.reload.subtitle
  assert_select_in_stream "page-save-status", /CHANGED ELSEWHERE/
  assert_select_in_stream "editor-notice", /Changed by .+Reload/m
  assert_no_match(/page-base-updated-at/, response.body, "the base must not advance, or the next save would overwrite")
end

test "a save on a current base still saves" do
  page = create_page(title: "About")
  patch admin_page_path(page), params: { base_updated_at: page.updated_at.iso8601(6), page: { subtitle: "Fresh" } }, as: :turbo_stream
  assert_response :success
  assert_equal "Fresh", page.reload.subtitle
end
```

Add the same pair for a post and for a block (a block's stale check is against the block's own base; the page-base header logic is unchanged). Component test for the bar (text, role, Reload link). View-only: extend `test/system/admin/view_only_test.rb` — a reader sees the hint, no `[role=toolbar]`, no `.admin-block-card__handle`, no "Add block", and typing is impossible (inputs disabled).

- [ ] **Step 2: Implement the refusal** in `Admin::AutosaveResponses`: a new `stale_base?(record, base_updated_at)` check that the three controllers call **before** the service (`base < record.updated_at`, using the record as loaded); on stale return `render turbo_stream: stale_streams(record, status_id:), status: :conflict` and do not call the service. Rewrite the concern's comment: the old behaviour was "last write wins with a warning"; say why it changed (the handoff's rule: your text stays on screen to copy, Reload discards it — which only makes sense if the stale write didn't happen). No audit event (nothing was attempted through a service; this is optimistic locking, not a denial).
- [ ] **Step 3: Autosave controller.** Accept 409 as a final answer: render the stream, set `this.paused = true`, ignore `queue`/`saveNow` while paused, never copy a base out of a 409. Add `<div id="editor-notice">` under the header (the header's `notice` slot). The block cards' saves use the same path; a paused page-settings form does not pause block forms and vice versa (each form has its own base).
- [ ] **Step 4: View only** per States B19: CSS `.admin-view-only :is(input, textarea, select, .admin-rich-text-editor) { background: var(--cs-sunken); color: var(--cs-dim); }`; templates skip the toolbar, handles, menus and pickers when `!editable?`; the hint is one whole string per case in the header's `notice` slot.
- [ ] **Step 5: System test** `test/system/admin/changed_elsewhere_test.rb`: open a page editor; change the page through the service behind the browser's back; type in Subtitle; assert "CHANGED ELSEWHERE", the bar with the other user's name, that the typed text is still in the field, and that further typing sends no request (poll `page.reload.subtitle` unchanged after 2 s); press Reload; the field shows the other user's text and the bar is gone.
- [ ] **Step 6: Run** the integration tests for pages, posts and content blocks, `test/system/admin/{autosave,view_only,changed_elsewhere}_test.rb`. PASS.
- [ ] **Step 7: Commit.** `feat: a stale autosave is refused and explained; view-only editors are plainly read-only`

---

### Task 7: Side-by-side translation layout

**Files:**
- Create: `app/components/admin/editor_screen/reference_card_component.{rb,html.erb}`, `shared_fields_component.{rb,html.erb}`, tests, previews
- Modify: `app/components/admin/columns/{plain,rich_text,slug}_column_component.html.erb`, `app/components/admin/field_component.html.erb`, `app/components/admin/post_form_component.html.erb`, `page_settings_form_component.html.erb`, `block_card_component.html.erb`, `app/assets/tailwind/content-spiel.tailwind.css`

**Interfaces:**
- Consumes: Task 1 (`translation_source`, `translation_original_changed_at_for`, `SourceDiff`) for the outdated card's content, which Task 8 renders; this task builds the card's current-state variant and the layout.
- Produces:
  - `Admin::EditorScreen::ReferenceCardComponent.new(record:, field:, locale:, original:, kind: :plain | :rich, state: :current | :outdated | :unknown | :missing, confirm: nil)` — root `div.admin-reference-card[data-original-for=<field>][data-translation-state]` with the label (the primary language's own name, uppercase mono), the original text (`p` for plain, rendered HTML for rich), and slots `header_note`, `actions` (Task 8 fills them for outdated).
  - `Admin::EditorScreen::SharedFieldsComponent.new(fields:)` → a collapsed `<details>` "Shared fields (N)" listing each untranslated field's label and value read-only, with the note "Shared by all languages. Edit them on the <primary language> tab."
  - CSS: `.admin-translation-pair` — a container (`container-type: inline-size` on the form column) whose two columns sit side by side at ≥ 880px of container width and stack below it, the reference first and collapsible (`<details open>` when stacked).
  - The per-field "Translate" button no longer renders beside the reference card; the suggestion slot (`admin/shared/_translation_box`) stays under the input (Task 9 decides when a per-field button shows).

- [ ] **Step 1: Failing tests.** Component tests: the card shows the primary language's own name and the original; `data-translation-state`; a rich original is rendered HTML, scrubbed. `SharedFieldsComponent`: "Shared fields (2)", closed by default, both labels inside. Integration (posts test): on a non-default tab, a content type with one translated and two untranslated schema fields shows the translated one as a pair and the other two only inside "Shared fields (2)" — and their inputs are **not** in the form (so a translation-tab autosave can't touch them); on the default tab all three are ordinary inputs. Use `TestTypes` for the content type.
- [ ] **Step 2: Layout.** Each translated field on a non-default tab renders `div.admin-translation-pair` > `div` (label, input, suggestion slot, errors) + `ReferenceCardComponent`. CSS:

```css
.admin-translation-form { container-type: inline-size; }
.admin-translation-pair { display: grid; gap: 1rem; grid-template-columns: minmax(0, 1fr); }
@container (min-width: 880px) {
  .admin-translation-pair { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); }
}
@container (max-width: 879.98px) {
  .admin-translation-pair > .admin-reference-card { order: -1; }
}
```

  The reference card: `rounded-cs border border-line bg-paper p-3`. Put `admin-translation-form` on the page-settings form, the post form and each block card's form. With the reference stacked above, the rich-text toolbar has the full column width, which is what makes it one row (bug 5): keep round 1's wrap as the fallback only.
- [ ] **Step 3: Shared fields.** In `PostFormComponent` and `BlockCardComponent` on a non-default tab: translated schema fields render as pairs; untranslated ones are collected into one `SharedFieldsComponent` after them. Page settings: "Page type" becomes a read-only line "Page type: Standard — Shared by all languages." on translation tabs (no `<select>` in the form). Check the controllers' `update` tolerate the absent keys (they permit, they don't require) and add the test above to prove a translation-tab save leaves shared values untouched.
- [ ] **Step 4: System test** `test/system/admin/translation_layout_test.rb`: at 1400px the title field and its reference sit side by side (their `getBoundingClientRect().top` equal within 4px); at 1100px (main column under 880px) the reference sits above the field and the rich-text toolbar is one row; restore the window in `ensure`.
- [ ] **Step 5: Run** `bin/rails tailwindcss:build`, component tests, `test/integration/admin/{posts,page_editor,content_blocks,translation_status}_test.rb`, `test/system/admin/{translation_layout,rich_text,translations}_test.rb`. PASS.
- [ ] **Step 6: Commit.** `feat: side-by-side translation that stacks when narrow; shared fields collapse`

---

### Task 8: The outdated reference card

**Files:**
- Modify: `app/components/admin/editor_screen/reference_card_component.{rb,html.erb}`, `app/components/admin/translation_screen/outdated_note_component.*` (folded into the card; its `FORM_ID`, `dom_id` and `options_for` move or stay as the card's helpers), `app/controllers/admin/translation_confirmations_controller.rb` (stream targets), `app/assets/tailwind/content-spiel.tailwind.css` (`ins`/`del` styles)

**Interfaces:**
- Consumes: `Translations::Source`, `SourceDiff`, `translation_original_changed_at_for`, `TimeAgoComponent`, the layout's confirm form (`form=` buttons).
- Produces: for `state: :outdated` the card has a warn border, the header "↻ CHANGED <time ago>" (only with a changed-at time), and the body:
  - stored source text → the word diff (`<del>` `text-danger-ink bg-danger-tint`, `<ins>` `text-ok-ink bg-ok-tint` — the one place red marks removed text, per the handoff);
  - `formatting_only?` → the current original + "Formatting changed";
  - `too_long?` → the current original + "The text is too long to compare word by word.";
  - no stored source → the current original + "English changed since this was translated." (the primary language's own name, one string per language name via interpolation of the name only);
  - actions: "Suggest update" (Task 9 wires it; rendered only when AI is configured and the viewer may translate) and "Still correct — mark up to date" (the existing confirm, same route and permission).
  - After confirm, the stream replaces the card with its `:current` variant and removes the tab's outdated marker when no field of that language is outdated any more (existing rule).

- [ ] **Step 1: Failing component tests** — one per body variant, built from real records: save a translation (stores the text), change the original through the service, render the card and assert `del` "spare" / `ins` "small" and the "CHANGED" header with a `<time>`; downgrade the entry to a bare digest and assert the no-source sentence and no `del/ins`; a bold-only change to a rich body asserts "Formatting changed"; text and names escaped (an original containing `<script>` renders as text inside `ins`).
- [ ] **Step 2: Implement** the variants in the card; the diff renders through `safe_join` over segments with `content_tag(:del | :ins | :span, text)` — never `html_safe` on user text. `aria-label` on `del`/`ins` ("removed", "added") so a screen reader hears what changed.
- [ ] **Step 3: Confirmation stream.** `TranslationConfirmationsController#create` replaces `ReferenceCardComponent.dom_id(record, field)` with the current card. Update `test/integration/admin/translation_status_test.rb` for the new target ids; keep every permission and audit assertion.
- [ ] **Step 4: System test** (extend `test/system/admin/translation_status_test.rb`): an outdated title shows the diff; pressing "Still correct — mark up to date" turns the card back to the plain reference, removes the tab's dot, and the page's `updated_at` hasn't moved.
- [ ] **Step 5: Run** component, integration and system tests for translation status. PASS.
- [ ] **Step 6: Commit.** `feat: outdated translations show what changed in the original`

---

### Task 9: Suggestions — pending, bulk, and "Suggest update"

**Files:**
- Create: `app/components/admin/translation_screen/pending_component.{rb,html.erb}`, test, preview
- Modify: `app/components/admin/translation_screen/translate_all_component.{rb,html.erb}`, `translate_button_component.{rb,html.erb}`, `suggestion_component.{rb,html.erb}`, `app/javascript/controllers/admin/translate_controller.js`, `app/controllers/admin/translations_controller.rb` (`suggest` accepts `mode=update`), `app/services/ai/translate.rb` (nothing, unless `mode=update` needs the current translation passed for the "Current: …" line — it is read from the record, not sent to the provider)

**Interfaces:**
- Produces:
  - Header (the editor header's `suggest` slot): `TranslateAllComponent.new(record:, locale:, editable:)` renders "Suggest translations for N empty fields" with the real N (counted server-side over the record's tracked fields and its blocks' that are blank in `locale` and have a non-blank original); hidden at N = 0. While running: "Suggesting 2 of 5 fields", a 4px progress bar, Cancel. Afterwards: "5 suggestions ready · Use all · Discard all".
  - A per-field "Translate" button shows only on an **empty** translated field (inside the field, under the input), not beside filled ones.
  - `Admin::TranslationScreen::PendingComponent` (rendered client-side from a `<template>` in the layout): accent-tint box, spinner, elapsed seconds, two skeleton bars, Cancel; at 25 s: "No suggestion after 25 seconds. Try again" with a Try again button.
  - `SuggestionComponent`: label "SUGGESTED TRANSLATION · EDIT BEFORE USING" with the model name right-aligned; repair notes as `text-warn-ink` lines under the text, before Use / Discard; **Use** is `primary` small. With `mode: :update` it also shows "Current: <the existing translation>" (plain text, truncated to 300 characters, escaped) and Use replaces the field's value.
  - `suggest` accepts `mode=update` for fields that already have a translation (today's rule that only requested fields are translated is unchanged; blank originals are still skipped).

- [ ] **Step 1: Failing tests.** Component: the count ("Suggest translations for 3 empty fields" for a post with title, excerpt and body empty in `de` and present in `en`; nothing rendered at 0; nothing without `ai.translate` or with AI unconfigured). Suggestion: the new label, model name, warnings before the buttons, `mode: :update` shows "Current: Über uns". Integration (`translations` controller test): `mode=update` on a filled field returns a suggestion box containing "Current:"; without `mode=update` a filled field is still translated only if requested (unchanged). Nothing in any response includes the key (`assert_not_includes response.body, "sk-test"` as the existing tests do).
- [ ] **Step 2: Implement the count and the header states.** The count is computed by a small reader on the header component (`Translations::Status`-style walk limited to blank-with-original fields; blocks included); the bulk run keeps round 1's client flow (`translateEmpty` → sequential `request(part)`) and adds: per-field pending boxes inserted from the template before each request, the "Suggesting i of n" line, Cancel (an `AbortController` per run that aborts the in-flight fetch and removes pending boxes — fields already answered keep their suggestions), and the ready line with **Use all** and **Discard all**.
- [ ] **Step 3: Pending box and the 25 s rule.** The client shows elapsed seconds from its own timer; at 25 s (the provider timeout the server already enforces — `test/models/ai/providers/anthropic_test.rb` pins it) the box switches to the timeout sentence. A late answer for a box that timed out is ignored unless the editor pressed Try again. Cancel on a single box aborts that request only.
- [ ] **Step 4: Suggest update.** The outdated card's "Suggest update" is a `button[data-action="admin--translate#translate"]` with `data-translate-mode="update"`; the controller sends `mode=update`; the box appears in the field (same slot), holding the full new text plus the "Current:" line.
- [ ] **Step 5: System test** (extend `test/system/admin/translations_test.rb`; the stub provider): the header says "Suggest translations for 2 empty fields"; pressing it shows two pending boxes, then "2 suggestions ready"; edit one suggestion, press "Use all"; both fields hold the (edited) text and autosave reports saved; reload and assert persisted. A second test: "Discard all" removes every box and saves nothing. A third: with the stub provider made slow (the test file's existing slow-provider hook, or add one to the stub), Cancel removes the pending boxes and no suggestion appears afterwards.
- [ ] **Step 6: Run** component, integration and system tests for translations; `test/models/ai`. PASS.
- [ ] **Step 7: Commit.** `feat: suggestion flow — pending boxes, bulk progress, Use all / Discard all, Suggest update`

---

### Task 10: Editor fields — settings, SEO, hero, content-type fields

**Files:**
- Modify: `app/components/admin/page_settings_form_component.{rb,html.erb}`, `app/components/admin/columns/{slug,plain,media}_column_component.*`, `app/components/admin/field_component.html.erb`, `app/components/admin/fields/{date,boolean,select,group,groups}_field.html.erb`, `app/components/admin/post_form_component.html.erb`
- Create: `app/javascript/controllers/admin/char_count_controller.js`

**Interfaces:**
- Produces:
  - Slug: the prefix cell (round 1) plus help text "The last part of the page’s address. Changing it leaves a redirect from the old address."
  - SEO (collapsed `<details>` "SEO · META TITLE, META DESCRIPTION"): soft counters "42 / 60" and "120 / 160" (`admin--char-count`, counting characters with `Array.from`; over the soft limit the counter turns `text-warn-ink` and says "42 / 60 · long" — never blocks saving). No share image.
  - Hero image (landing pages): thumbnail, **Change** / **Remove**, and the per-page alt override: an input whose placeholder is the library alt in the tab's language (falling back along the chain), help "Empty uses the alt text from Media", and once overridden a "Reset" link plus the library text shown beneath (handoff §10 A1). Same pattern for an image block's alt and caption (Task 12 reuses the partial `admin/shared/_override_field`).
  - Content-type fields: their own group between Excerpt and Body, titled with the type's label (e.g. "RESUME ENTRY FIELDS"); date → a mono `yyyy-mm-dd` text input (`inputmode="numeric"`, `pattern`, placeholder `yyyy-mm-dd`) — still submitted as the same param; boolean → a toggle (`.cs-toggle`, a styled checkbox with `role="switch"`) with its label; select → `.cs-select`; repeatable group → bordered rows with the drag handle, an "×" remove button (`aria-label="Remove <singular>"`) and "+ Add <singular>".

- [ ] **Step 1: Failing tests.** Component tests for `PageSettingsFormComponent` (new file): the slug help; SEO counters with `data-controller="admin--char-count"` and limits 60/160; on a landing page the hero alt input's placeholder equals the asset's alt and "Reset" appears only when the page has its own `hero_alt`. Fields: date renders `input[type=text][pattern][placeholder='yyyy-mm-dd']` with value "2024-01-01"; boolean renders `input.cs-toggle[role=switch]` after a hidden "0"; an invalid date string typed (`2024-13-45`) is a validation error on the field after save, not a 500 (integration, posts test with the resume type).
- [ ] **Step 2: Implement** each piece. "Reset" is a button that empties the override input and dispatches `input` (autosave saves the cleared value); it needs no server route. The date input must keep accepting what `Posts::Save` accepts today; if the model parsed a date-picker value, parse `yyyy-mm-dd` strictly and add a field error "Use the form yyyy-mm-dd" for anything else.
- [ ] **Step 3: System test** (extend `test/system/admin/page_editor`-style file or add `editor_fields_test.rb`): typing a 70-character meta title shows "70 / 60 · long" and still saves; pressing Reset on an overridden hero alt empties it and the placeholder shows the library alt; toggling a boolean saves.
- [ ] **Step 4: Run** component tests, `test/integration/admin/{page_editor,posts}_test.rb`, the system test, `test/system/admin/groups_test.rb` (repeatable groups). PASS.
- [ ] **Step 5: Commit.** `feat: editor fields — slug help, SEO counters, per-use alt with Reset, typed field controls`

---

### Task 11: Chip input — tags and related posts

**Files:**
- Create: `app/components/admin/chip_input_component.{rb,html.erb}`, `app/javascript/controllers/admin/chip_input_controller.js`, `app/controllers/admin/tag_suggestions_controller.rb` (+ route `get "tags/suggest"`), tests, preview
- Modify: `app/components/admin/post_form_component.html.erb`, `app/components/admin/related_posts_component.{rb,html.erb}`, `app/javascript/controllers/admin/related_posts_controller.js` (folded into chip input or kept as a thin adapter), `app/controllers/admin/link_targets_controller.rb` (adds `status` to each row), `app/controllers/admin/posts_controller.rb` (accepts `post[tag_names][]` as well as the comma string)
- Delete: `app/components/admin/tag_input_component.*`, `app/javascript/controllers/admin/tag_input_controller.js`, their tests and preview

**Interfaces:**
- Produces:
  - `Admin::ChipInputComponent.new(name:, id:, label:, chips: [{ value:, label:, hint: nil, dot: nil }], search_url:, create: false, placeholder: nil, errors: [], hidden_note: nil)` — submits one hidden input per chip (`name` is an array name such as `post[tag_names][]`) plus the empty sentinel, so an emptied list saves as empty.
  - `GET /<admin>/tags/suggest?q=` → JSON `[{ value: "rails", label: "rails", hint: "12 posts" }]`, up to 8, prefix match first then substring, case-insensitive, counts over kept posts the viewer can read; requires `posts.read`.
  - Tags: `create: true` adds the row "Create tag “<typed>”" when nothing matches exactly. A typed comma or Enter commits the current text as a chip. Names are compared case-insensitively; a duplicate is not added twice.
  - Related posts: chips show the type dot, the title and "· Draft" / "· Scheduled" when not live; search rows show title + status; the hidden-relations line reads "+2 related posts you can’t open (kept)".
  - Invalid chip (server refused it): the chip turns `bg-danger-tint` and the field's error slot names it.

- [ ] **Step 1: Failing tests.** Component: chips render as `li` with a remove button `aria-label="Remove rails"`, a hidden input each, the sentinel, `role="combobox"` on the text input with `aria-expanded`/`aria-controls`, the listbox empty and hidden. Suggest endpoint: prefix before substring; counts; `%` and `_` literal (`sanitize_sql_like`); a 200-character `q` capped; signed out → redirect; a reader without `posts.read` → 403; tags only on trashed posts count 0 and still appear (a tag exists independently of posts). Posts controller: `post[tag_names][]=Rails&post[tag_names][]=rails&post[tag_names][]=` saves one tag "rails"; a name containing a comma sent as an array element is kept whole (commas only split the legacy string form). Link targets: each row has `status`. Trash visibility: the suggest endpoint and link targets never count or return trashed posts.
- [ ] **Step 2: Build** the component and controller: text input inside the chip row; typing queries `search_url` (150 ms debounce, abort the previous request, ignore answers for an older query); ArrowDown/ArrowUp move the active option (`aria-activedescendant`), Enter picks it (or commits the typed text when `create`), Backspace on an empty input removes the last chip, Escape closes the list; picking or removing dispatches a bubbling `change` so autosave fires, while typing in the search box does not (stop `input` at the component root). All text via `textContent`.
- [ ] **Step 3: Use it** for tags and related posts in the post form; delete the old tag input. Keep `RelatedPostsComponent`'s readers (`related`, `hidden_related_count`, `related_from`) and its "Also related from" line.
- [ ] **Step 4: System test** `test/system/admin/chip_input_test.rb`: type "ra", ArrowDown, Enter → chip "rails", autosave saved, reload → still there; type "brand new", Enter → chip created and, after save, exists as a tag; Backspace removes the last chip and saves; adding a related post shows its type dot and "· Draft"; searching does not trigger a save by itself.
- [ ] **Step 5: Run** component tests, the endpoint tests, `test/integration/admin/{posts,link_targets}_test.rb`, `trash_visibility_test.rb`, the system test. PASS.
- [ ] **Step 6: Commit.** `feat: chip input with autocomplete for tags and related posts`

---

### Task 12: Blocks

**Files:**
- Modify: `app/components/admin/block_card_component.{rb,html.erb}`, `block_picker_component.{rb,html.erb}`, `app/javascript/controllers/admin/blocks_controller.js`, `app/views/admin/pages/show.html.erb`, `app/controllers/admin/content_blocks_controller.rb` (stream targets for the single picker row)
- Create: `app/views/admin/shared/_override_field.html.erb` (from Task 10 if not yet extracted)

**Interfaces:**
- Produces:
  - Card header: drag handle, type name 14px/600 (a button that collapses the body, `aria-expanded`), and a ⋯ `MenuComponent` (`aria-label="Block actions"`): Move up, Move down, Duplicate, divider, "Delete block…" (`text-danger-ink`, opens the confirm). Move up is disabled on the first card, Move down on the last.
  - Delete confirm: title "Delete this block?", body "Blocks don’t go to the trash. This can’t be undone.", destructive, confirm "Delete block".
  - Post list block: its three settings (Type, Tag, Limit) in one row; Tag is a single-value chip input using the tag suggest endpoint (no `create`); Limit a 72px number input; a help line "Shows the newest posts of this type." (one string).
  - Unavailable type: card with `border-danger`, the label "Unavailable type — <name>", the sentence "Its content is kept but can’t be shown or edited.", and only "Delete block…".
  - Image block: thumbnail, Change / Remove, alt and caption as per-use overrides with the library text as placeholder and Reset (the shared partial).
  - One "Add block" row at the end: a dashed row "+ Add block" followed by inline type buttons (Rich text, Image, Post list). The between-cards "+" pickers are removed; a new block is appended and can be moved.

- [ ] **Step 1: Failing tests.** Update `test/components/admin/block_card_component_test.rb` and `block_picker_component_test.rb`: the menu and its items in order; first card's Move up disabled; the unavailable card's sentence and that it has no form; the post-list row; the single picker (`#block-picker-end` only; no `block-picker-after-*`). Integration (`content_blocks_test.rb`): create appends and streams the card before the picker row; the `after_id` param is still honoured by the controller (kept for the keyboard "insert below" that Duplicate uses) but no view sends it except Duplicate.
- [ ] **Step 2: Implement.** The menu's Move up/down keep calling `admin--blocks#moveUp|moveDown`; recompute the disabled state after every reorder (client-side in `reorder()` and server-side when the list re-renders). Removing the nested pickers simplifies `insertion_stream` (no "previous last card regains a trailing picker" replace) — delete that branch and its comment.
- [ ] **Step 3: System tests** (`test/system/admin/blocks_test.rb`, `content_blocks_drag_test.rb`): ⋯ → Move down reorders and offers Undo; ⋯ → Delete block… → confirm removes it; Add block → Image appends a card at the end; the keyboard drag path still works with the new header.
- [ ] **Step 4: Run** component, integration and system tests for blocks and the media picker. PASS.
- [ ] **Step 5: Commit.** `feat: block cards with a menu, one Add block row, post-list settings, unavailable-type card`

---

### Task 13: Rich-text popovers and dialogs

**Files:**
- Modify: `app/javascript/controllers/admin/rich_text_controller.js`, `app/javascript/rich_text/{popover,internal_link,image,youtube}.js`, `app/components/admin/columns/rich_text_column_component.html.erb`, `app/views/layouts/admin.html.erb` (two shared form dialogs), `app/assets/tailwind/admin-rich-text.css`
- Create: `app/components/admin/editor_screen/rich_text_dialogs_component.{rb,html.erb}` (rendered once in the layout)

**Interfaces:**
- Produces (handoff §10 B25):
  - **Link:** an anchored popover with one input that takes a URL or searches pages and posts (`admin_link_targets_path`, rows with title, path and status); choosing a row makes an internal link, typing a URL an external one; "Remove link" when the selection is already a link.
  - **Image:** the 880 media picker, then a 560 dialog (`rich-text-image-dialog`) for alt and caption with the library text as placeholders and "Empty uses the text from Media"; "Insert image" / "Save" when editing an existing image node.
  - **YouTube** and **Page link (embed)**: a 560 form dialog each (`rich-text-youtube-dialog`: one URL or id field with a live "Video id: …" line and the error "That doesn’t look like a YouTube link."; `rich-text-page-dialog`: the page/post search).
  - The dialogs are shared, rendered once in the layout; the controller that opened one receives the result (a `CustomEvent` on the opening editor element), so two editors on a page never cross wires.

- [ ] **Step 1: Failing system tests** (extend `test/system/admin/rich_text_test.rb`): Link — select text, press Link, type "abo", pick "About" → an `internalLink` mark to that page is saved; type "https://example.org" + Enter → a `link` mark; Image — Insert → Image → pick an asset → the 560 dialog opens with the asset's alt as placeholder → "Insert image" → an `image` node with `asset_id` and no override attributes saved; with alt typed, the node carries it; YouTube — the dialog rejects "hello" with the error line and accepts a watch URL; with two rich-text blocks on a page, inserting through the second editor changes only the second.
- [ ] **Step 2: Implement.** Keep `RichText::Document` validation as the server-side rule (unknown attributes refused); the dialogs only gather input. Focus returns to the editor with the selection restored after a dialog closes, including Cancel. Popover and dialogs carry the classes that reset the invalid border (`admin-rich-text-popover` exists; dialogs are outside the field wrappers).
- [ ] **Step 3: Run** `test/system/admin/{rich_text,media_picker,blocks}_test.rb`, `test/components/admin/columns`. PASS.
- [ ] **Step 4: Commit.** `feat: rich-text link popover with search; image, YouTube and page dialogs`

---

### Task 14: The page tree and `/pages`

**Files:**
- Modify: `app/components/admin/tree_component.{rb,html.erb}`, `tree_node_component.{rb,html.erb}`, `app/controllers/admin/pages_controller.rb` (`index`), `app/views/admin/pages/index.html.erb`, `app/javascript/controllers/admin/tree_controller.js`

**Interfaces:**
- Consumes: `Translations::StateIndex.counts_for` (Task 2), the New page dialog id `new-page-dialog` and its `data-new-page-parent-id-param` trigger (Task 15 builds the dialog; until then the "+" keeps linking to `new_admin_page_path(parent_id:)`).
- Produces (handoff §10 B24, C34):
  - Row markers: "↻N" (`text-warn-ink`) for N outdated fields and "○N" (`text-meta`) for N missing, summed over the target languages, no box, hidden at zero; one `role="img"` element each with `aria-label` "3 outdated translations" / "2 missing translations" and a `title` naming the languages ("Deutsch: 2 outdated · Español: 1 outdated").
  - Context-only ancestors: `text-meta`, no link, no handle, `title="You can’t open this page"`.
  - The hover "+" where the viewer may create under that page; no handle where they may not move it.
  - Tree header: "Pages", a "+ New page" button, and a ⋯ menu holding "Create starter pages" while Home is the only kept page.
  - `GET /<admin>/pages`: redirects (303) to Home's editor when the viewer can open it; otherwise renders the empty state "Choose a page from the tree".

- [ ] **Step 1: Failing tests.** Tree component: a page with two outdated fields in `de` and one missing in `es` shows "↻2" and "○1" with the labels above and no "!"; a complete page shows neither; counts come from `counts_for` in one query for the whole tree (query-count assertion with 30 pages equals that with 3). Integration: `get admin_pages_path` as the owner → redirect to `admin_page_path(root_page)`; as a user who can read only a deep branch → 200 with "Choose a page from the tree" and no 404; the starter offer appears in the tree's menu only while Home is the only kept page (reuse round 1's test, new location).
- [ ] **Step 2: Implement.** `TreeComponent` loads `counts_for(visible pages)` once and hands each node its two totals and the per-language breakdown for the tooltip. Remove the boxed "!" marker and `translation_marker_label`. Keep every existing data attribute the tree controller and tests use (`data-page-id`, `data-parent-id`, `data-context-only`, `data-child-count`).
- [ ] **Step 3: Run** `test/components/admin/tree_component_test.rb`, `test/integration/admin/{tree,page_editor,starter_contents}_test.rb`, `test/system/admin/tree_test.rb`. PASS.
- [ ] **Step 4: Commit.** `feat: tree counts for outdated and missing translations; /pages opens Home`

---

### Task 15: New page and New post dialogs

**Files:**
- Create: `app/components/admin/editor_screen/new_page_dialog_component.{rb,html.erb}`, `new_post_dialog_component.{rb,html.erb}`, `app/javascript/controllers/admin/new_record_controller.js`, tests, previews
- Modify: `app/views/layouts/admin.html.erb` (both dialogs once), `app/controllers/admin/{pages,posts}_controller.rb` (`new` renders the same form standalone; `create` accepts `page[page_type]`, `post[title]` prefill, and on failure re-renders the dialog open with errors), `app/components/admin/tree_node_component.html.erb`, `tree_component.html.erb`, `app/views/admin/jump/show.html.erb` ("New post" link), `Jump::Search::ACTIONS`

**Interfaces:**
- Produces:
  - `new-page-dialog` (560): Title; Inside (a `<select>` of pages the viewer may create under, indented by depth, scoped on `pages.create`); Page type (types from `Page.page_types`); a live URL preview ("/services/<slug-from-title>" — the same slugify as `admin--slug-preview`). Opened with `data: dialog_trigger("new-page-dialog").merge("new-page-parent-id-param": id, "new-page-title-param": text)`; the controller presets Inside and Title from those params.
  - `new-post-dialog` (560): a type picker (radio cards with the type dot and label, only types the viewer may create; the first preselected), Title, and the URL preview or "Not listed on any page yet" for a type with no listing page.
  - Rendered only for a viewer who may create at least one page / post type. `GET /pages/new` and `/posts/new` still work without JS (the same form as a page).
  - On success: redirect to the new record's editor (`_top`). On failure: 422 re-rendering the editor shell with the dialog open (`data-admin--dialog-open-on-load`) and an `ErrorSummaryComponent` inside.

- [ ] **Step 1: Failing tests.** Components: Inside lists only pages creatable under (a branch-scoped editor sees only their branch; the root only if allowed); page types present; the post dialog lists only creatable types and nothing for a viewer with none (`render?` false). Integration: `post admin_pages_path` with `page: { title: "Team", parent_id: services.id, page_type: "landing" }` creates a landing page under Services as a draft; a blank title → 422 with the dialog marked open and the summary "1 thing needs fixing"; a forged `parent_id` outside scope → 404 (not 403); a forged `page_type` → 422. Same for posts (type not creatable → 403 through the service's denial, audited once).
- [ ] **Step 2: Build** both dialogs and `admin--new-record` (presets from trigger params, live URL preview with the chosen parent's path prefix, focus on Title). Triggers: the tree header's "+ New page", each row's hover "+" (Inside preset), the pages empty state, ⌘K's "New page" / "New post" actions (they become buttons that open the dialogs instead of links), the dashboard (Task 16) and the posts list (Task 17).
- [ ] **Step 3: System test** `test/system/admin/new_record_test.rb`: hover a tree row, press "+", the dialog opens with Inside = that page; type a title, the URL preview updates; Create → the new page's editor opens and the tree shows it under the right parent; New post: pick "Now update", title, Create → that post's editor.
- [ ] **Step 4: Run** component, integration and system tests; `test/system/command_palette_test.rb`. PASS.
- [ ] **Step 5: Commit.** `feat: New page and New post dialogs`

---

### Task 16: Dashboard

**Files:**
- Create: `app/queries/dashboard/activity.rb`, `app/components/admin/dashboard_screen/{card,activity_row,translation_card}_component.{rb,html.erb}`, tests, previews
- Modify: `app/controllers/admin/dashboard_controller.rb`, `app/views/admin/dashboard/show.html.erb`, `app/queries/dashboard/feed.rb`, `app/components/admin/dashboard_screen/quick_create_component.{rb,html.erb}`, `row_component.*`
- Delete: `Admin::DashboardScreen::ColumnComponent` (+ test) once nothing renders it; `Dashboard::Feed#recently_updated`, `#recently_edited`, `#scheduled` and the queries only they used

**Interfaces:**
- Produces:
  - `Dashboard::Activity.new(actor:, channel: Current.channel, limit: 15).rows → [Row(event:, record:, sentence_parts:, actor_name:, via_token:, at:, span_end:)]` — the newest audit events whose action starts with `page.`, `post.`, `block.` or `media.` (never `access.denied`, `session.*`, `user.*`, `group.*`, `token.*`, `settings.*`), limited to events whose subject (or, for a block, its owner) the viewer may read **now** and that is kept; coalesced rows carry their time span. Constant query count whatever the data size (one limited event query that over-fetches 4×, one read-scope query per subject type, one user preload).
  - Sentences (one whole string per action, record title as a link): "<name> published “<title>”", "… edited …", "… created …", "… scheduled … for 6 Oct", "… unpublished …", "… moved … to the trash", "… restored …", "… uploaded …", "… edited a block on …", "… reordered blocks on …", "… marked a translation of … as up to date". A change through a token: "<user> via <token name>" — token names arrive in round 3, so until then "<user> via an API token" — with a square accent avatar; a person has a round avatar with their initial.
  - Quick create: one row — title input, a type `<select>` (creatable post types plus "Page" when the viewer may create pages), "Create draft". Choosing Page opens `new-page-dialog` with the title carried over and Inside = Home. Hidden entirely when nothing is creatable. "New page" and "Upload image" buttons are gone.
  - Three cards (CSS grid `repeat(auto-fit, minmax(300px, 1fr))`), each at most 5 rows and a "→" link: **Your drafts** (title, type dot, "edited 2h ago"); **Going live next** (date tile: mono month in `text-warn-ink`, day 18px; title; "in 5 days"; "by you" when mine; with fewer than 3 a hint "Schedule a draft to see it here."); **Needs translation** (per target language: its own name, "12 missing · 1 outdated", a 4px progress bar of complete/total, then the most recently changed outdated item as a link) — hidden with one language or when the viewer can read nothing.
  - "Recent activity" replaces "Recently updated" and "Recently edited by you"; footer link "Full audit log →" only with `audit.view`.

- [ ] **Step 1: Failing tests.** `test/queries/dashboard/activity_test.rb`: only content actions; an event about a post the viewer can't read is absent (not "something happened"); a trashed record's older events are absent but its `post.trashed` event… is also absent (the record isn't kept) — pin that; a block edit reads "edited a block on “About”" and links to the page; a coalesced event has both ends of its span; query count is the same for 5 and 60 events (reuse the dashboard test's counter); a nil-actor event reads "System"; a deleted user's reads "a deleted user". Components: card caps at 5 and links on; the translation card's numbers equal `StateIndex.summary`; quick create lists "Page" only with `pages.create` and renders nothing with no rights. Integration (`dashboard_test.rb`): a no-grants user still gets 200 with empty cards and no activity; the old two lists are gone.
- [ ] **Step 2: Implement** `Dashboard::Activity` (comment the over-fetch-then-scope shape and why it stays constant), the three card components and the feed row; slim `Dashboard::Feed` to `drafts` and `going_live_next` (+ `last_change` if still used by the drafts card for "edited … ago"; otherwise remove it and its batched query).
- [ ] **Step 3: System test** (extend `test/system/admin/dashboard_test.rb`): quick-create a blog draft → lands in its editor; choosing "Page" with a typed title opens the New page dialog with that title; the activity feed shows "published" after publishing a draft.
- [ ] **Step 4: Run** query, component, integration and system tests for the dashboard; `trash_visibility_test.rb` (add the activity feed with a kept-vs-trashed pair). PASS.
- [ ] **Step 5: Commit.** `feat: dashboard — one-row quick create, three cards, a content activity feed`

---

### Task 17: Posts list — toolbar, pagination, bulk actions

**Files:**
- Create: `app/components/admin/posts_screen/{toolbar,table,bulk_bar}_component.{rb,html.erb}`, `app/javascript/controllers/admin/bulk_select_controller.js`, `app/services/posts/bulk.rb`, `test/services/posts/bulk_test.rb`, component tests, previews
- Modify: `app/controllers/admin/posts_controller.rb` (`index`, new `bulk` action), `config/routes.rb` (`post "posts/bulk"`), `app/views/admin/posts/index.html.erb`, `app/helpers/admin/list_links_helper.rb` users (pager links)

**Interfaces:**
- Produces:
  - `index` params: `q`, `scope` (`all | live | drafts | scheduled`), `type`, `tag`, `translation` (`needs | outdated | complete`), `page`. 50 per page through `Pagination`. Sorted `updated_at desc, id desc`.
  - Toolbar: search; a segmented control with counts — "All 128 · Live 96 · Drafts 20 · Scheduled 12" (counts respect the other filters, not the scope itself); Type, Tag and Translation `<select>`s; all instant (`admin--auto-submit`), "Clear" when anything is active.
  - Header: a split button — "New blog post" (the default creatable type; opens `new-post-dialog` with that type) + ▾ menu for the other creatable types.
  - Columns: checkbox, Title + path (mono 11px; "Not listed" when none), Type (dot), Status (chip, hidden for Live), Translations (chips, each linking to that language's editor tab), Updated (relative), ⋯ (Open, View on site when live, Move to trash).
  - Bulk bar (accent-tint, appears when rows are selected, `aria-live="polite"`): "3 selected · Publish · Move to trash · Clear". A header checkbox selects the page's rows.
  - `Posts::Bulk.call(action:, ids:, actor: Current.actor) → Result(done:, refused:, not_found:)` — `action` ∈ `"publish" | "trash"`; each record goes through `Posts::Save` / `Trash::Move` with its ordinary permission check and its own audit event; `done`/`refused` are arrays of posts, `not_found` a count (ids that don't exist, are already trashed, or are outside the viewer's read scope). At most 200 ids per call (more → `ArgumentError`, the controller answers 422).
  - `POST /<admin>/trash/restore_many` (`type=post`, `ids[]`) → runs `Trash::Restore` per id; used by the bulk trash's Undo.
  - `POST /<admin>/posts/bulk` (`bulk_action`, `ids[]`) → redirect back to the list (filters kept via `list_params`) with a toast: "Published 3 posts." / "Published 2 posts. 1 was refused: “Title”." / "Moved 3 posts to the trash." with Undo (restoring exactly those moved) / "Nothing was changed. 2 posts were not found."

- [ ] **Step 1: Failing service tests.**

```ruby
require "test_helper"

class Posts::BulkTest < ActiveSupport::TestCase
  include ContentHelper

  test "a mixed selection: each permitted post is acted on once, the rest are reported, nothing is silent" do
    mine = create_post(title: "Mine", published: false)
    theirs = create_post(title: "Theirs", published: false)
    trashed = create_post(title: "Gone", published: false)
    as_owner { Trash::Move.call(trashed) }
    author = users(:author) # the fixture in the Author group (posts.edit own, no posts.publish) — or build one as the access tests do
    mine.update_columns(author_id: author.id)

    result = as(users(:one), channel: :admin) do
      Posts::Bulk.call(action: "publish", ids: [ mine.id, theirs.id, trashed.id, 999_999, mine.id ])
    end
    assert_equal [ mine, theirs ].sort_by(&:id), result.done.sort_by(&:id)
    assert_empty result.refused
    assert_equal 2, result.not_found
    assert_equal 2, Audit::Event.where(action: "post.published").count, "a duplicated id is acted on once"
  end

  test "a viewer who may read but not publish gets every post back as refused, each denial audited" do
    post = create_post(title: "Draft", published: false)
    result = as(users(:reader), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ post.id ]) }
    assert_empty result.done
    assert_equal [ post ], result.refused
    assert_nil post.reload.published_at
    assert_equal 1, Audit::Event.where(action: "access.denied").count
  end

  test "a post outside the viewer's read scope is not found, never refused by name" do
    hidden = create_post(title: "Secret", content_type: "resume_entry")
    scoped = scoped_reader(content_types: %w[blog]) # build as trash_visibility_test builds its scoped user
    result = as(scoped, channel: :admin) { Posts::Bulk.call(action: "trash", ids: [ hidden.id ]) }
    assert_equal 1, result.not_found
    assert_empty result.refused
    assert_not hidden.reload.trashed?
  end

  test "trash moves each post with its own event; already-live posts publish as a no-op that still counts as done" do
    a = create_post(title: "A"); b = create_post(title: "B", published: true)
    as_owner do
      assert_equal 2, Posts::Bulk.call(action: "trash", ids: [ a.id, b.id ]).done.size
    end
    assert_equal 2, Audit::Event.where(action: "post.trashed").count
  end

  test "an unknown action and an oversized selection are programming errors" do
    assert_raises(ArgumentError) { Posts::Bulk.call(action: "delete", ids: [ 1 ]) }
    assert_raises(ArgumentError) { Posts::Bulk.call(action: "publish", ids: (1..201).to_a) }
  end
end
```

- [ ] **Step 2: Implement `Posts::Bulk`.** It is an orchestrator, not a write of its own: load `AccessControl.scope(actor, "posts.read", Post.all)` (kept only) for the unique ids, count the rest as not found, and call the per-record service for each — each in its own transaction, so one failure doesn't undo the others. It must still satisfy the service contract test: call `authorize!` per record through the delegated services and carry an explicit `# audit: none (each record's own service records its event)` comment as the contract allows; if the contract test insists on a literal `authorize!(`, check `posts.read` on each loaded record before delegating. Comment why there's no all-or-nothing: a bulk publish that fails for one post should not unpublish nine.
- [ ] **Step 3: Failing controller tests** (`posts_test.rb`): filters combine and survive in pager links; `scope` counts ignore the scope filter itself; `translation=outdated` lists only posts with an outdated target language (via `StateIndex.joins`); page 2 lists rows 51–100 of 120 and "51–100 OF 120"; junk and out-of-range pages behave as in round 1; the list renders in a constant number of queries for 5 and 60 posts; `post admin_posts_bulk_path` publishes, redirects with the filters, and the toast text matches each of the four shapes; a forged `bulk_action` → 422; trashed posts never listed (`trash_visibility_test.rb`).
- [ ] **Step 4: Build** the three components and `admin--bulk-select` (tracks checked rows, toggles the bar, keeps the header checkbox's `indeterminate` state, clears on page change; the bar's buttons submit one form outside the table with `form=`-less hidden `ids[]` inputs it fills). Undo for a bulk trash restores exactly the moved posts: `flash[:undo]` points at a small route of its own, `POST /<admin>/trash/restore_many` (`ids[]`, `type=post`), which runs `Trash::Restore` per id, each with its ordinary permission check and audit event, and reports through the same toast shapes. `Posts::Bulk` stays at its two actions. Add an integration test for the route: it restores only ids that are trashed posts the viewer may restore, ignores the rest, and a forged id outside scope changes nothing.
- [ ] **Step 5: System test** `test/system/admin/posts_list_test.rb`: select two drafts → the bar says "2 selected"; Publish → toast "Published 2 posts." and both rows lose their Draft chip; select one → Move to trash → toast with Undo → Undo brings it back; the Translation filter narrows the list without a button; the split button's menu opens the New post dialog with the chosen type.
- [ ] **Step 6: Run** service, component, integration and system tests for posts; `service_contract_test.rb`; `trash_visibility_test.rb`. PASS.
- [ ] **Step 7: Commit.** `feat: posts list — toolbar with counts, pagination, bulk publish and trash`

---

### Task 18: Translations matrix

**Files:**
- Create: `app/components/admin/translation_screen/{matrix,summary_card}_component.{rb,html.erb}`, tests, previews
- Modify: `app/controllers/admin/translations_controller.rb` (`index`), `app/views/admin/translations/index.html.erb`
- Delete: `app/components/admin/translation_screen/list_component.*` (+ test)

**Interfaces:**
- Consumes: `Translations::StateIndex` (`states_for`, `joins`, `summary`), `TranslationChipComponent`, `PaginationComponent`, `list_params`.
- Produces (handoff §4.4, §10 B18):
  - `GET /<admin>/translations?type=page|post|media|settings&page=` — no `locale` param any more (an old `?locale=de` link is accepted and ignored).
  - Summary cards, one per target language: its own name, "% done" (complete items / total items the viewer can read), a bar, and "12 missing · 1 outdated".
  - One matrix: rows are items needing work in **any** target language, columns the target languages; each cell a `TranslationChipComponent` that links to that language's editor tab; the row title links to the first outdated language's tab, else the first missing; the row's call to action reads "Review changes →" when anything is outdated, "Translate →" otherwise.
  - Sort: rows with an outdated language first (most recently changed original first), then missing-only rows by `updated_at desc`.
  - A "Site settings" row (title and tagline) at the top when incomplete and the viewer holds `settings.manage`.
  - Type filter (All / Pages / Posts / Images / Site settings), instant; 50 rows per page; empty state "Everything is translated." inside the card.

- [ ] **Step 1: Failing tests.** Components: a summary card's numbers for a seeded mix; the matrix row's link target and CTA for outdated vs missing; a complete language's chip in an incomplete row is the solid "done" chip and still links. Integration (`translations_test.rb`, replacing the per-language tests): rows sorted outdated-first; the Site settings row only with `settings.manage`; a reader sees only what they can read, and the percentages are over that same set; trashed items never appear (`trash_visibility_test.rb`); `?locale=de` still answers 200; page 2; a site with one language redirects to the dashboard as today; query count constant for 5 and 60 rows.
- [ ] **Step 2: Implement.** The rows query: for each type the viewer may read, `StateIndex.joins(readable(type), locale: any target, states: %w[missing outdated])` unioned in Ruby after per-type `COUNT`s the same way the trash list merges its three models (read `Admin::TrashController`'s windowing and reuse the approach: per-type ordered window of `offset + per_page`, merge, slice). `states_for` supplies every cell in one query.
- [ ] **Step 3: System test** (extend `test/system/admin/translations_test.rb`): the matrix lists an outdated post first; clicking its `DE ↻` chip opens the post editor on the German tab with the outdated card; back on the matrix, after marking it up to date the row is gone and the German card's percentage rose.
- [ ] **Step 4: Run** component, integration and system tests for translations. PASS.
- [ ] **Step 5: Commit.** `feat: translations matrix with per-language summary cards`

---

### Task 19: Sweep, docs and visual check

**Files:**
- Modify: `CLAUDE.md`, `docs/roadmap.md`, `test/lib/admin_design_rules_test.rb` (the "replaced components are gone" list)

- [ ] **Step 1: Guard additions.** Extend the "replaced components are gone" test with `record_header_component.rb`, `tag_input_component.rb`, `translation_screen/list_component.rb`, `translation_screen/outdated_note_component.rb` (if folded away), `dashboard_screen/column_component.rb`, and assert `app/models/translations/cached_status.rb` doesn't exist and `danger_outline` appears nowhere under `app/`.
- [ ] **Step 2: Whole suite**, in the foreground, once each: `PGGSSENCMODE=disable bin/rails test`, `PGGSSENCMODE=disable bin/rails test:system`, `bin/rubocop`, `bin/brakeman -q`, `bin/importmap audit`. All green. If the known-flaky "Translate empty fields, then Use all" test fails, rerun its file alone and report both runs — and since Task 9 rewrote that flow, say whether the race the roadmap suspects (a page autosave refused by a block autosave's page touch) can still happen now that a stale save is refused outright (Task 6): if "Use all" can trip its own "Changed elsewhere", that is a bug to fix here, not to note.
- [ ] **Step 3: Visual check.** With a throwaway, uncommitted script, screenshot every screen this round rebuilt (page editor default and German tab at 1400 and 1100, post editor both tabs, an outdated field, a suggestion, the Schedule dialog, the view-only editor, the changed-elsewhere bar, both New dialogs, the dashboard, the posts list with a selection, the translations matrix, sign-in, reset, ⌘K, a confirm dialog, the save bar) in both themes into `tmp/screenshots/cs-studio-after-round-2/`, each file named for its screen. Look at them against the mockups; fix small defects with targeted edits; list what remains under "Known differences" in the report.
- [ ] **Step 4: CLAUDE.md.** Describe the system as it is: the editor header and its states; the save rule's wording; the refused stale save (replace the "stale is only a warning" description wherever it appears, including the dashboard paragraph's sentences about `base_updated_at`); view only; the translation pair layout and shared fields; `translation_sources`' two shapes, `translation_original_changed_at`, `SourceDiff` and its cap; `translation_states`, `StateIndex`, the parity test and `translations:reindex` (and remove every mention of `CachedStatus`); the suggestion flow; the chip input and the tag suggest endpoint; block cards; rich-text dialogs; the tree counts and `/pages`; the New dialogs; `Dashboard::Activity`; the posts list, `Posts::Bulk` and its rules; the translations matrix; the round 1 corrections (`danger_text`, checkbox, palette groups). Correct every sentence this round made false.
- [ ] **Step 5: Roadmap.** Mark round 2 done (PR pending); close the interim rows it resolves (the Translations overview filtering in Ruby, posts pagination, side-by-side translate mode, the audit-event feed, inline page quick create, the toolbar wrap); keep the rows it doesn't (leave guard reach, Firefox drag check, the three small follow-ups unless fixed in passing); add any new interim state this round shipped knowingly (e.g. "<user> via an API token" until token names exist; `StateIndex.rebuild_all` running synchronously on a language change).
- [ ] **Step 6: Commit.** `docs: CS Studio after round 2; guard the removed components`

---

## Self-review notes

- **Spec §7 coverage:** editor header, Schedule dialog, view only, changed elsewhere → Tasks 4–6; editor body (side-by-side + stacking, outdated diff, suggestions, slug prefix, hero, SEO, content-type fields, chips) → Tasks 7–11; blocks → 12; rich text → 13; page tree and `/pages` → 14; New page / New post → 15; dashboard → 16; posts list → 17; translations → 18; data §5.2 → 1, §5.3 → 2; both carried-over lists → 3 (and the translation-stacking and toolbar items → 7, the tree markers → 14).
- **A behaviour change the spec implies but didn't spell out:** Task 6 turns a stale autosave from "saved with a warning" into "refused". The handoff's rule (your text stays so you can copy it; Reload discards it) only makes sense that way; the PR description must say so.
- **Deferred to round 3 by the spec:** token names ("via <token name>"), Settings on the save bar, the media picker's redesign (footer, instant search), upload progress on a tile, the audit log's sentences (Task 16 writes the dashboard's own; round 3 can share them).
- **Order:** 1 → 2 first (data). 3 is independent. 4 before 5, 6, 9. 7 before 8, 9. 2 before 14, 16, 17, 18. 11 before 12 (post-list Tag). 15 before 16 and 17 use its dialogs (14's "+" falls back to the link until 15 lands).
