# Translation Helpers and AI Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translators see which items are missing or outdated in each language, the site title and tagline become translatable, and editors can request AI translation suggestions that they review before anything is saved.

**Architecture:**
- **Outdated detection.** A model concern, `Translations::Tracker`, records per field and per locale a digest of the primary-language value a translation was saved against, in a jsonb column `translation_sources`.
- **Status.** `Translations::Status` folds that, plus today's required-field check (`Admin::TranslationStatus`, moved), into per-locale status. The result feeds the editor switcher, the posts list, the page tree and a new Translations overview.
- **AI translation.** An `AI::Providers` registry with a built-in Anthropic provider, configured in Settings with an encrypted key. The `AI::Translate` service returns suggestions without saving; the editor shows them with Use / Discard.

**Tech Stack:**
- Rails 8.1, Mobility jsonb, Active Record encryption.
- The official `anthropic` Ruby gem.
- Hotwire (Turbo Streams, Stimulus), Tiptap.
- Minitest with fixtures; Cuprite system tests.

**Spec:** `docs/superpowers/specs/2026-10-02-translation-helpers-design.md`

## Global Constraints

**Translation tracking**
- The primary language is `Locales.default`, read at the time of use. Target languages are `Locales.enabled - [Locales.default]`.
- `translation_sources` is a jsonb column, not null, default `{}`, shaped `{ "field" => { "locale" => "<sha256 hex>" } }`. It lives on `pages`, `posts`, `content_blocks`, `media_assets` and `site_settings`.
- Translated fields:
  - **Page:** `title subtitle meta_title meta_description hero_alt` (never `slug`).
  - **Post:** `title excerpt body`, plus its content type's `translated: true` schema fields.
  - **ContentBlock:** `caption alt body`, plus its block type's `translated: true` schema fields.
  - **Media::Asset:** `alt caption`.
  - **SiteSetting:** `title tagline`.
- Field states: `:missing`, `:unknown` (present but no digest), `:outdated`, `:current`. Record states: `:missing` beats `:outdated` beats `:complete`, and `:unknown` counts as complete. Blocks roll up into their page or post.
- Digest:
  - plain values: `Digest::SHA256.hexdigest(value.to_s.strip)`;
  - rich text: `RichText::Document#normalized.digest`;
  - blank: none.

**AI translation**
- AI text is never saved by the server. Only the editor's **Use** fills the input, which then autosaves as an ordinary edit.
- **Permissions:**
  - `ai.translate` ("Use AI translation", area "Content", action `:translate`, no subject), seeded onto Admin and Editor;
  - configuring AI needs `settings.manage`;
  - requesting a suggestion needs `ai.translate` and the record's edit right.
- **Edit right** of a record:
  - pages and posts: `<prefix>.edit`, plus `<prefix>.publish` if published;
  - blocks: `ContentBlocks::OwnerPermissions#owner_refusal`;
  - images: `media.manage` or the uploader with `media.upload` (`Media::Ownership`);
  - site settings: `settings.manage`.
- **Audit actions:**
  - `ai.translated` (metadata `fields from to provider model characters`, never text);
  - `page.translation_confirmed`, `post.translation_confirmed`, `block.translation_confirmed`, `media.translation_confirmed`, `settings.translation_confirmed`.
- **The AI key:**
  - stored with `encrypts :ai_api_key` and never rendered, logged or audited;
  - added to `Audit::Snapshot::NEVER_STORED` (`ai_api_key`); the existing `_key` filter already covers logs.
- **Request limits:** at most 20 fields and 30,000 characters per AI request. The provider timeout is 60 s. The default model is `claude-sonnet-5`.

**Conventions and process**
- No browser dialogs; use the existing confirm/dialog components.
- Never define `Admin::Translations`, `Admin::AI` or `Admin::Ai` modules that would shadow `::Translations`/`::AI`. Admin components go under `Admin::TranslationScreen::`.
- Every write goes through an `ApplicationService` with `authorize!(` and `record_event(` in `#call`.
- Keep the codebase's comment density: long, load-bearing comments for non-obvious invariants.
- Commits use conventional messages ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.
- Tests: `PARALLEL_WORKERS=1 bin/rails test`, `bin/rails test:system`, `bin/rubocop`.

## Review Focus

1. **Pre-feature translations.** Every German value saved before this feature reads "unknown", not "outdated", so on deploy no field gets flagged (Task 1 test).
2. **Rich-text no-op.** A rich-text change that only normalises (whitespace at mark edges, merged text nodes) doesn't flag the translation as outdated (Task 1 test).
3. **Re-saving the original.** Editing the *German* value of a field records a fresh digest; re-saving the English value unchanged never flags German (Task 1 test).
4. **Use is the only write.** Pressing Translate saves nothing. Only Use, followed by the normal autosave, writes, and the resulting save records a fresh digest (Task 7 and Task 8 tests).
5. **The key stays secret.** The API key never appears in a rendered page, the audit snapshot, a log line, or a re-render after a validation error (Task 5 test).

---

### Task 1: `translation_sources` and `Translations::Tracker`

**Files:**
- Create: `db/migrate/20261002100000_add_translation_sources.rb`
- Create: `app/models/concerns/translations/tracker.rb` (module `Translations::Tracker`)
- Create: `app/models/translations.rb` (module `Translations` with `primary_locale`, `target_locales`, `digest(value)`)
- Modify: `app/models/page.rb`, `post.rb`, `content_block.rb`, `media/asset.rb` (include the tracker and declare their fields)
- Test: `test/models/translations/tracker_test.rb`

**Interfaces:**
- Produces:
  - `Translations.primary_locale -> String`;
  - `Translations.target_locales -> [String]`;
  - `Translations.digest(value) -> String | nil` (a `RichText::Document` is digested via `.normalized.digest`).
  - Model class method `translation_tracked_fields(record) -> [String]` (instance-aware for schema fields).
  - Instance methods:
    - `#translation_value(field, locale)`: the literal per-locale value, with no fallback; a `RichText::Document` for body fields;
    - `#translation_state(field, locale) -> :missing | :unknown | :outdated | :current`;
    - `#confirm_translation(field, locale)`: assigns the current primary digest; the caller saves.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/translations/tracker_test.rb
require "test_helper"

class Translations::TrackerTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  def save_post(post, locale, values) = assert(Posts::Save.call(post, translations: { locale => values }).ok?)

  test "saving a translation records the original's digest; changing the original makes it outdated" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      assert_equal :current, post.reload.translation_state("title", "de")

      save_post(post, "en", { title: "Hello there" })
      assert_equal :outdated, post.reload.translation_state("title", "de")
    end
  end

  test "values saved before the feature are unknown, never outdated" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      post.update_columns(title: { "en" => "Hello", "de" => "Hallo" }, translation_sources: {})
      assert_equal :unknown, post.reload.translation_state("title", "de")
    end
  end

  test "re-saving the original unchanged doesn't flag; editing the translation refreshes it" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "en", { title: "Hello" })
      assert_equal :current, post.reload.translation_state("title", "de")
      save_post(post, "en", { title: "Hi" })
      save_post(post, "de", { title: "Hi (de)" })
      assert_equal :current, post.reload.translation_state("title", "de")
    end
  end

  test "a rich-text change that only normalises doesn't flag the translation" do
    # Save a body in en and de, then save en with a document that differs only by
    # mark-edge whitespace/adjacent text node merges (normalized digest equal) → de stays :current.
  end

  test "clearing a translation removes its entry; missing reads :missing" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "de", { title: "" })
      assert_equal :missing, post.reload.translation_state("title", "de")
      assert_nil post.translation_sources.dig("title", "de")
    end
  end

  test "blocks track caption and schema fields; images track alt and caption" do
    # A rich_text block body and an image block caption in de; a Media::Asset alt in de via Media::Save;
    # each reads :current, then :outdated after the en value changes.
  end

  test "confirm_translation marks an outdated field current without changing the value" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "en", { title: "Hello!" })
      post.reload.confirm_translation("title", "de")
      post.save!
      assert_equal :current, post.reload.translation_state("title", "de")
      assert_equal "Hallo", post.translation_value("title", "de")
    end
  end
end
```

Write out the two placeholder bodies with real data and assertions. For the no-op rich-text case, build the two documents by hand. Their `normalized.digest` values must be equal while their raw hashes differ; assert both conditions in the test itself, so it can't pass vacuously.

- [ ] **Step 2: Run them and see them fail.** `PARALLEL_WORKERS=1 bin/rails test test/models/translations/tracker_test.rb`

- [ ] **Step 3: Implement**

```ruby
# db/migrate/20261002100000_add_translation_sources.rb
# Translation helpers spec §3.1: per field and locale, the digest of the
# primary-language value a translation was last saved against.
class AddTranslationSources < ActiveRecord::Migration[8.1]
  def change
    %i[pages posts content_blocks media_assets site_settings].each do |table|
      add_column table, :translation_sources, :jsonb, null: false, default: {}
    end
  end
end
```

```ruby
# app/models/translations.rb
# Shared helpers for translation tracking (translation helpers spec §3).
module Translations
  module_function

  def primary_locale = Locales.default.to_s
  def target_locales = Locales.enabled.map(&:to_s) - [ primary_locale ]

  # A digest of an original value, or nil for a blank one. Rich text is
  # digested after `normalized`, so a change that only normalises (edge
  # whitespace, merged text nodes) isn't a change.
  def digest(value)
    case value
    when RichText::Document then value.blank? ? nil : value.normalized.digest
    else value.to_s.strip.presence && Digest::SHA256.hexdigest(value.to_s.strip)
    end
  end
end
```

```ruby
# app/models/concerns/translations/tracker.rb
module Translations
  # Records, per translated field and target locale, which version of the
  # primary-language original a translation was saved against (spec §3.2),
  # so a later change to the original can flag the translation as outdated.
  #
  # Only a target-locale value that *changed in this save* gets a fresh
  # digest; a change to the primary value itself never touches the record's
  # sources -- that's exactly what makes the other locales outdated. Values
  # that predate this feature have no digest and read `:unknown`, never
  # `:outdated` (Review Focus 1).
  module Tracker
    extend ActiveSupport::Concern

    included do
      before_save :record_translation_sources
    end

    def translation_state(field, locale)
      locale = locale.to_s
      value = translation_value(field, locale)
      return :missing if blank_translation?(value)
      return :current if locale == Translations.primary_locale

      recorded = translation_sources.dig(field.to_s, locale)
      return :unknown if recorded.nil?

      recorded == Translations.digest(translation_value(field, Translations.primary_locale)) ? :current : :outdated
    end

    def confirm_translation(field, locale)
      store_translation_source(field.to_s, locale.to_s)
    end

    private

    def record_translation_sources
      @translation_snapshot ||= {}
      self.class.translation_tracked_fields(self).each do |field|
        Translations.target_locales.each do |locale|
          next unless translation_value_changed?(field, locale)

          if blank_translation?(translation_value(field, locale))
            remove_translation_source(field, locale)
          else
            store_translation_source(field, locale)
          end
        end
      end
    end

    def store_translation_source(field, locale)
      digest = Translations.digest(translation_value(field, Translations.primary_locale))
      sources = translation_sources.deep_dup
      if digest
        (sources[field] ||= {})[locale] = digest
      else
        sources[field]&.delete(locale)
      end
      self.translation_sources = sources.compact_blank
    end

    def remove_translation_source(field, locale)
      sources = translation_sources.deep_dup
      sources[field]&.delete(locale)
      self.translation_sources = sources.compact_blank
    end

    def blank_translation?(value) = value.respond_to?(:blank?) ? value.blank? : value.nil?
  end
end
```

Each model defines:
- `self.translation_tracked_fields(record)`: column fields, plus `record.definition&.fields&.select(&:translated?)&.map { |f| f.name.to_s }`, plus `"body"` where it has a rich-text body.
- `#translation_value(field, locale)`: a literal per-locale read:
  - column fields: `read_attribute(field).to_h[locale]`;
  - body: the stored per-locale document via `HasRichTextBody`'s literal reader (find it);
  - schema fields: `settings_object(locale:)`/`fields(locale:)` and then `public_send(name)`.
- `#translation_value_changed?(field, locale)`: compares against `attribute_in_database`/`*_was` for the jsonb column holding that field (`title_was.to_h[locale]`, `translated_settings_was.to_h.dig(locale, name)`, the body column's `_was`). Implement it once in the concern, given a model-provided map `field → [column, path]`.

Read `app/models/concerns/has_rich_text_body.rb` and `content_model/field_set.rb` before writing these readers. They must not use fallback.

- [ ] **Step 4: Run the tests, then the full suite.** `PARALLEL_WORKERS=1 bin/rails test`

- [ ] **Step 5: Commit** `git commit -m "feat: record which original each translation was saved against"`

---

### Task 2: `Translations::Status` and the move of `Admin::TranslationStatus`

**Files:**
- Create: `app/models/translations/status.rb`
- Delete: `app/models/admin/translation_status.rb` (its required-field logic moves into `Translations::Status`)
- Modify: `app/components/admin/record_header_component.rb:100`, `app/components/admin/post_form_component.rb:100` (callers)
- Test: `test/models/translations/status_test.rb` (move the existing `Admin::TranslationStatus` tests here; `grep -rln TranslationStatus test`)

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `Translations::Status.for(records, locales: Translations.target_locales) -> { record => { locale => :complete | :missing | :outdated } }` (batched);
  - `Translations::Status.missing_locales(record) -> [String]` and `.outdated_locales(record) -> [String]` (for the switcher; computed through `.for([record])`);
  - `Translations::Status.field_state(record, field, locale)`, which delegates to `translation_state`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/translations/status_test.rb
require "test_helper"

class Translations::StatusTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  test "missing beats outdated beats complete, per locale" do
    with_locales(%w[en de es], default: "en") do
      post = create_post(title: "Hello")
      Posts::Save.call(post, translations: { "de" => { title: "Hallo" } })
      Posts::Save.call(post, translations: { "en" => { title: "Hello!" } })
      assert_equal({ "de" => :outdated, "es" => :missing }, Translations::Status.for([ post.reload ])[post])
    end
  end

  test "a page's blocks roll up into the page" do
    # Page with title translated in de (current) and a rich_text block whose de body is outdated → page de :outdated;
    # a required translated block field blank in de → :missing (the rule Admin::TranslationStatus had).
  end

  test "images and the site settings have a status too" do
    # Media::Asset alt translated then en changed → :outdated; SiteSetting covered after Task 5 (skip until then
    # only if SiteSetting isn't Tracker-tracked yet — otherwise assert it).
  end

  test "batched: constant queries for 1 vs 20 records" do
    # Measure sql.active_record count for Status.for over 1 and 20 pages-with-blocks; assert equal.
  end

  test "the switcher helpers" do
    # missing_locales / outdated_locales return the right codes for a post.
  end
end
```

Write the placeholders for real. Port every test from the old `Admin::TranslationStatus` tests, so the required-field rule keeps its coverage.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.**
- **Move the rule:** move `page_missing?`, `post_missing?`, `title_blank?` and `required_fields_blank?` into `Translations::Status` as private helpers, with their comments.
- **Field states:**
  - `:missing` for a record and locale is the old rule, OR any tracked required field `:missing`;
  - `:outdated` is any tracked field of the record, or of its blocks, reading `:outdated`.
- **Batching:** load `content_blocks` for all pages and posts in one query (`ContentBlock.where(owner: records).group_by { [_1.owner_type, _1.owner_id] }`), never per record.
- **Callers:** point the two switcher callers at `Translations::Status.missing_locales`/`outdated_locales`.

- [ ] **Step 4: Full suite.** `PARALLEL_WORKERS=1 bin/rails test`

- [ ] **Step 5: Commit** `git commit -m "feat: compute translation status per locale, including outdated"`

---

### Task 3: Editor status and "Mark as up to date"

**Files:**
- Create: `app/services/translations/confirm.rb`
- Create: `app/controllers/admin/translation_confirmations_controller.rb` (`create`: params `record_type`, `record_id`, `field`, `locale`)
- Modify: `config/routes.rb` (`post "translations/confirm", to: "translation_confirmations#create", as: :translation_confirmation`, inside the admin scope)
- Modify: `app/components/admin/language_switcher_component.rb` + `.html.erb` (`outdated:` codes, a second marker with its own `aria`/title text "Original changed")
- Modify: the three "original" renderers (`field_component.html.erb`, `columns/plain_column_component.html.erb`, `columns/rich_text_column_component.html.erb`) to accept `translation_state:` and render the note plus button when `:outdated`
- Modify: page settings form, post form, block card and media detail (pass the state and switcher codes)
- Test: `test/services/translations/confirm_test.rb`, `test/integration/admin/translation_status_test.rb`, component tests

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: `Translations::Confirm.call(record, field:, locale:, actor:)`. The record is a Page, Post, ContentBlock, Media::Asset or SiteSetting.

- [ ] **Step 1: Write the failing tests.** Cover:
  - the service with each record kind;
  - refusal without the edit right, including publish on a published post and a block on a published page;
  - the audit action and metadata;
  - integration: an outdated German title shows "Original changed since this was translated" and the button; posting the confirm form clears it; the switcher shows the outdated marker for `de`;
  - the confirm endpoint 404s for a record outside read scope and 403s for a refused write.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement**

```ruby
module Translations
  # "Mark as up to date" (spec §3.4): the original changed, but the
  # translator judged the translation still right. Stores the current
  # primary digest without touching the value. Needs exactly the right an
  # edit of that record would.
  class Confirm < ApplicationService
    include Media::Ownership
    include ContentBlocks::OwnerPermissions

    EVENT = { "Page" => "page", "Post" => "post", "ContentBlock" => "block", "Media::Asset" => "media", "SiteSetting" => "settings" }.freeze

    def initialize(record, field:, locale:, actor: Current.actor)
      @record, @field, @locale, @actor = record, field.to_s, locale.to_s, actor
    end

    def call
      refused = edit_refusal
      return denied(refused, @record) if refused
      unless @record.class.translation_tracked_fields(@record).include?(@field) && Translations.target_locales.include?(@locale)
        return failure(@record, [ "Nothing to confirm" ])
      end

      @record.class.transaction(requires_new: true) do
        @record.confirm_translation(@field, @locale)
        @record.save!(validate: false)
        record_event("#{EVENT.fetch(@record.class.name)}.translation_confirmed", subject: @record, metadata: { field: @field, locale: @locale })
      end
      success(@record)
    end

    private

    def edit_refusal
      case @record
      when Page, Post
        prefix = @record.is_a?(Page) ? "pages" : "posts"
        return "#{prefix}.edit" unless authorize!("#{prefix}.edit", @record)
        "#{prefix}.publish" if @record.published_at.present? && !authorize!("#{prefix}.publish", @record)
      when ContentBlock then owner_refusal(@record.owner) { |key| authorize!(key, @record) }
      when Media::Asset then "media.manage" unless authorize!("media.manage", @record) || uploader_may_manage?(@record)
      when SiteSetting then "settings.manage" unless authorize!("settings.manage", @record)
      end
    end
  end
end
```

Extract `edit_refusal` into a small module (`Translations::EditRight`) when Task 7 needs it too. Do it here if that's simpler, and name it in the report.

The controller loads the record through the read scope the record's own module uses: `admin_scope` for pages and posts, the block's owner scope, `Media::Asset.kept`, `Current.site`. A miss is 404. On success it streams the replaced field section, or redirects back with a notice. The JS-free form is a `button_to` inside the original box.

- [ ] **Step 4: Full suite.**

- [ ] **Step 5: Commit** `git commit -m "feat: flag outdated translations in the editor and let translators confirm them"`

---

### Task 4: Status in the lists and the Translations overview

**Files:**
- Modify: `app/views/admin/posts/index.html.erb` (lines 94-98: replace the presence dots with a badge per target locale from `Translations::Status.for(@posts)`; the controller computes it once)
- Modify: `app/components/admin/tree_component.rb` / `tree_node_component.rb` + `.html.erb` (an incomplete-locales marker after the status badge; not on context-only rows; precomputed hash passed down)
- Create: `app/controllers/admin/translations_controller.rb` (`index`)
- Create: `app/components/admin/translation_screen/list_component.rb` + `.html.erb`
- Modify: `config/routes.rb` (`get "translations", to: "translations#index", as: :translations`)
- Modify: `app/controllers/admin/base_controller.rb` (`MODULES` entry "Translations" with `permission: %w[pages.read posts.read]` and a new optional `if:` lambda, `-> { Locales.enabled.size > 1 }`; `admin_modules` honours `if:`)
- Test: `test/integration/admin/translations_overview_test.rb`, the posts index and tree tests

**Interfaces:**
- Produces: `admin_translations_path(locale: "de", type: nil, offset: nil)`.

- [ ] **Step 1: Write the failing tests.** Cover:
  - the posts index shows ✓, ! and ↻ badges with accessible labels, and none for the default locale;
  - the tree shows a marker with a tooltip that lists the incomplete locales;
  - the overview:
    - lists missing and outdated pages, posts and images for `locale=de`, grouped, linking to `admin_post_path(post, locale: "de")` and similar;
    - excludes complete and trashed items;
    - is read-scoped (an Author doesn't see others' unreadable posts);
    - pages through results (about 50 per page);
    - redirects an unknown or default `locale` to the first target locale;
  - the sidebar entry is hidden with one enabled language and hidden without read rights;
  - a constant query count for the posts index with 1 vs 20 posts.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.**
- **Overview query:** load readable records in batches (`AccessControl.scope`, `Media::Asset.kept` for `media.upload` holders) and compute `Translations::Status.for`.
- **Filtering in Ruby:** filter in Ruby by state for the chosen locale. Bounding is acceptable at CMS scale; note it in a comment and in the roadmap.
- **Paging:** use the Media module's `limit(N+1)` pattern over the filtered list.

- [ ] **Step 4: Full suite, plus system tests** (the tree is involved).

- [ ] **Step 5: Commit** `git commit -m "feat: show translation status in lists and a translations overview"`

---

### Task 5: Translatable site title and tagline

**Files:**
- Create: `db/migrate/20261002110000_translate_site_title_and_tagline.rb` (string to jsonb `{ default_locale => value }`, with a reversible `down`)
- Modify: `app/models/site_setting.rb` (`translates :title, :tagline`; title present in the default locale; include `Translations::Tracker` with fields `title tagline`)
- Modify: `app/services/settings/save.rb` (`translations:` kwarg, `TRANSLATED = %i[title tagline]`)
- Modify: `app/controllers/admin/settings_controller.rb` (split translated vs untranslated params by `Settings::Save::TRANSLATED`, with `locale` param handling like the page and post controllers)
- Modify: `app/components/admin/settings_form_component.rb` + `.html.erb` (a `locale:` param, the language switcher, `value`/`original` for title and tagline, as in `PageSettingsFormComponent`)
- Modify: the public readers:
  - `layouts/public/_header.html.erb:6` and `_footer.html.erb:2`: `translated(theme_site, :title)`;
  - `pages/show.html.erb:9-10`: `translated(theme_site, :tagline)`;
  - `pages_helper.rb:42`: `Locales.read(Current.site, :title)`.
- Modify: `app/controllers/setup_controller.rb:178` (setup writes the default locale through `translations:`)
- Test: the migration test, `test/integration/public_site_title_test.rb`, settings integration tests, setup tests

- [ ] **Step 1: Write the failing tests.** Cover:
  - the migration up moves the string into the default locale, and down restores it;
  - `/de` shows the German tagline and `<title>`, and a locale without one falls back;
  - Settings in `?locale=de` shows the English original beside the title and saves the German value only;
  - a blank default-locale title is refused;
  - the setup wizard still works and writes the default locale.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.** Grep `\.title\b` and `\.tagline\b` across `app/` and `config/` for every reader of the site's title or tagline, and switch each one to a locale-aware read. The MCP and system-status screens may read it too.

- [ ] **Step 4: Full suite, plus system tests.**

- [ ] **Step 5: Commit** `git commit -m "feat: translate the site title and tagline"`

---

### Task 6: AI providers, Anthropic and the AI settings

**Files:**
- Modify: `Gemfile` (`gem "anthropic"`, the official SDK; run `bundle install`; `bin/bundler-audit`)
- Create: `app/models/ai.rb` (module `AI`: `Error`, `DuplicateProvider`, `configured?`, `provider`)
- Create: `app/models/ai/providers.rb` (registry: `register(name, klass)`, `find(name)`, `names`, `reset!`)
- Create: `app/models/ai/providers/anthropic.rb`
- Modify: `config/initializers/types.rb` (`AI::Providers.reset!` and `AI::Providers.register("anthropic", AI::Providers::Anthropic)` inside `to_prepare`)
- Create: `db/migrate/20261002120000_add_ai_settings_to_site_settings.rb` (`ai_provider` string, `ai_model` string, `ai_api_key` text)
- Create: `db/migrate/20261002120100_grant_ai_translate_to_built_in_groups.rb` (Admin and Editor, the same shape as `GrantMediaManageToBuiltInGroups`)
- Modify: `app/models/access_control/built_ins.rb` (register `ai.translate`)
- Modify: `app/models/access_control/seeds.rb` (Editor gets `ai.translate`)
- Modify: `test/fixtures/access_control/grants.yml` (Editor's hand list)
- Modify: `app/models/site_setting.rb` (`encrypts :ai_api_key`)
- Modify: `app/models/audit/snapshot.rb` (`ai_api_key` in `NEVER_STORED`)
- Modify: `config/application.rb` or an initializer to configure Active Record encryption keys:
  - from `Rails.application.credentials.active_record_encryption` or `ENV["ACTIVE_RECORD_ENCRYPTION_*"]`;
  - **test env:** fixed keys in `config/environments/test.rb`;
  - **development:** fixed dev-only keys in `config/environments/development.rb`, with a comment that they're dev-only;
  - **production:** must come from credentials or ENV, and should raise at boot when missing *only if* an AI key is ever saved (use `config.active_record.encryption` with `support_unencrypted_data = false`; document it in CLAUDE.md and `.kamal/secrets` notes).
- Modify: the settings form (an "AI translation" section: provider `<select>` of `AI::Providers.names`, model text field with placeholder `claude-sonnet-5`, key field showing "API key: set" plus Replace, Remove key, Test connection), the settings controller (blank key keeps the stored one; `remove_ai_key` param; `test_ai_connection` action, `settings.manage`), and `Settings::Save` (permit the AI attributes)
- Test: `test/models/ai/providers_test.rb`, `test/models/ai/providers/anthropic_test.rb`, settings integration tests, the permissions and seeds tests

**Interfaces:**
- Produces:
  - `AI.configured? -> Boolean`;
  - `AI.provider -> instance`, built from `SiteSetting`: `AI::Providers.find(site.ai_provider).new(api_key: site.ai_api_key, model: site.ai_model.presence || "claude-sonnet-5")`;
  - provider instance `#translate(texts:, from:, to:, format:) -> [String]` and `#test_connection -> true`, raising `AI::Error`.
- The Anthropic provider takes `client:` in `initialize`, defaulting to `Anthropic::Client.new(api_key:, timeout: 60)`, so tests inject a fake client.

- [ ] **Step 1: Write the failing tests.** Cover:
  - **Registry:** register, find, duplicate raises, and plugin names must be `owner/name`; mirror `ContentModel::Registry`'s naming rules.
  - **Anthropic, with a fake client object** (no network):
    - the request carries the model, a system prompt containing the from and to language names, and the texts numbered with a delimiter;
    - the response is parsed back into the same count;
    - a count mismatch raises `AI::Error`;
    - SDK errors map to messages (authentication, rate limit, timeout, server).
  - **Markdown format:** the prompt says to keep `::directives` and `cs:` links.
  - **Settings:**
    - the key is saved encrypted (`SiteSetting.connection.select_value("select ai_api_key from site_settings")` isn't the plaintext);
    - the page never contains the key, before or after a 422 re-render;
    - a blank key keeps it, and Remove clears it;
    - the audit snapshot has no `ai_api_key`;
    - Test connection shows OK, or the error, using a stubbed provider registered in the test;
    - `ai.translate` is granted to Admin and Editor, and the migration up and down work.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.** The Anthropic call shape: check the installed gem's README and source (`bundle show anthropic`). The expected form is

```ruby
client.messages.create(model:, max_tokens: 8192, system: SYSTEM_PROMPT % { from:, to: }, messages: [ { role: "user", content: numbered(texts) } ])
```

and the text is read from the response content blocks. Use a delimiter format that can't collide with content, for example `<<<1>>>` … `<<<2>>>`, and verify the count. The system prompt goes in a constant with a comment.

- [ ] **Step 4: Full suite.** Also run `bin/bundler-audit` and `bin/brakeman -q --no-pager`.

- [ ] **Step 5: Commit** `git commit -m "feat: configure an AI provider with an encrypted key"`

---

### Task 7: `AI::Translate`

**Files:**
- Create: `app/services/ai/translate.rb`
- Modify: the shared edit-right module from Task 3 (reuse it)
- Test: `test/services/ai/translate_test.rb` (a stub provider registered as `test/stub` in the test setup and restored in teardown)

**Interfaces:**
- Produces: `AI::Translate.new(record, fields:, to:, actor: Current.actor)`.
  - `#call` returns a `Result`.
  - The instance exposes `#suggestions -> { field => String | RichText::Document }` and `#warnings -> { field => [String] }`.

- [ ] **Step 1: Write the failing tests.** Cover:
  - denied without `ai.translate`, and denied without the edit right (a published post with no publish right; a block's owner; an image not owned);
  - refused when not configured;
  - refused when `to` is the default locale or not enabled;
  - refused over the caps (21 fields, or more than 30,000 characters);
  - blank originals are skipped;
  - **nothing saved:** the record's `updated_at` and values are unchanged;
  - rich text goes as Markdown and comes back as a `RichText::Document`, with images and links kept and warnings passed through;
  - `ai.translated` is recorded with the metadata (fields, from, to, provider, model, characters) and no text: assert the event's snapshot and metadata don't contain the original or the suggestion;
  - a provider error returns a failure with its message, and no event.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.** Use `authorize!("ai.translate", nil)` plus the edit right. Read the originals with `translation_value(field, Translations.primary_locale)`: rich text via `to_markdown` with `format: :markdown`; plain strings as they are. Call the provider once; for mixed formats, call once per format group, at most two calls. Map the results back. Wrap the call in `rescue AI::Error => e` and return `failure(@record, [ e.message ])`.

- [ ] **Step 4: Full suite.**

- [ ] **Step 5: Commit** `git commit -m "feat: suggest AI translations for a record's fields without saving them"`

---

### Task 8: Suggestions in the editor

**Files:**
- Modify: `app/controllers/admin/translations_controller.rb` (add `suggest`: POST, params `record_type`, `record_id`, `fields[]`, `locale`; it loads the record through its read scope, calls `AI::Translate`, and renders Turbo Streams)
- Modify: `config/routes.rb` (`post "translations/suggest", to: "translations#suggest", as: :translation_suggestions`)
- Create: `app/components/admin/translation_screen/suggestion_component.rb` + `.html.erb` (the suggested text, or a rendered preview for rich text, plus Use and Discard; any warnings; an inline error variant)
- Create: `app/javascript/controllers/admin/translate_controller.js` (`preload: "admin"` in importmap):
  - the Translate button posts to the suggest endpoint and shows a spinner;
  - **Use (plain):** sets the field's input value by `id` and dispatches a bubbling `input` event, then removes the box;
  - **Use (rich text):** dispatches a `translate:use` event that `admin--rich-text` handles;
  - **Discard** removes the box.
- Modify: `app/javascript/controllers/admin/rich_text_controller.js` (an `applySuggestion(event)` action: `this.editor.commands.setContent(event.detail.document)`, then `this.writeDocument()`)
- Modify: the three original-box renderers (a Translate button in `data-translate-slot` when `AI.configured? && can?("ai.translate") && editable`; the button carries `record_type`, `record_id`, `field`, `locale` and the target input id)
- Modify: the page, post and settings headers (a "Translate empty fields" button that requests every `:missing` field of the record and its blocks in chunks by the caps, then shows "Use all")
- Test:
  - `test/integration/admin/translation_suggestions_test.rb` (endpoint: streams, 403 without `ai.translate`, 404 out of scope, the error stream, nothing saved);
  - component tests;
  - JS behaviour covered by Task 9's system tests.

- [ ] **Step 1: Write the failing integration tests.**

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.**
- **Suggestion boxes:** each box's DOM id is `translation-suggestion-<input id>`, appended after the field's original box (stream `after` the `[data-translate-slot]` container, or `replace` an empty target rendered there).
- **Use all:** clicks every Use in order. Plain fields first, then rich text, so autosaves queue cleanly; each form's autosave controller serialises its own saves.

- [ ] **Step 4: Full suite.**

- [ ] **Step 5: Commit** `git commit -m "feat: review AI translation suggestions in the editor"`

---

### Task 9: System tests, docs and roadmap

**Files:**
- Create: `test/system/admin/translations_test.rb`, with a stub provider registered for the test that returns `"[de] " + text`
- Modify:
  - `CLAUDE.md`: a "Translations" section covering the tracker, status, overview, site title and tagline, AI providers, `AI::Translate`, the key handling, the encryption keys setup, and the `Admin::TranslationScreen` naming;
  - `docs/roadmap.md`:
    - tick "Translation helpers";
    - mark "In-admin AI assistant" as partially done (translate only);
    - add the out-of-scope rows from spec §9, plus an "overview filters in Ruby — needs a status cache at scale" note;
  - the spec: an "Amendments" section for behaviour-changing rulings.

- [ ] **Step 1: Write the system tests.** Cover:
  - a German title: press Translate, Use, then see "Saved", and the stored value is `[de] Hello`;
  - Translate empty fields, then Use all fills title and excerpt;
  - edit the English title, switch to German, see "Original changed since this was translated", press Mark as up to date, and the note is gone;
  - the overview lists a post missing in German and its link opens the German editor;
  - Settings in German: the tagline's original shows, and a German tagline appears on `/de` after save.

- [ ] **Step 2: Run the system tests twice.**

- [ ] **Step 3: Update the docs.**

- [ ] **Step 4: Full verification**

```bash
PARALLEL_WORKERS=1 bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman -q --no-pager
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
```

- [ ] **Step 5: Commit** `git commit -m "docs: describe translation helpers and AI translation"`
