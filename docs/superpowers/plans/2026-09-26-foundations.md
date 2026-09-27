# Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ContentSpiel runtime-configurable languages, one table of public URLs with redirects, one URL builder and resolver, a cookie-less cacheable public site with preview under `/preview`, and service objects as the single write path, while the public site, MCP and Avo keep working.

**Architecture:** Mobility jsonb translations stay; enabled languages move to `site_settings.locales`, read through a `Locales` module. A `public_paths` table (maintained from model callbacks, like `cached_paths` today) holds every page/post URL per language, and old rows become 301 redirects. `PublicSite::Urls` builds links from it, and `PublicSite::Resolver` answers requests from it. `PublicController` serves the site without sessions; `PreviewController` serves drafts behind sign-in. Services under `app/services/` (`Posts::Save`, `Pages::*`, `ContentBlocks::*`, `ApiTokens::*`, `Locales::*`) return a `Result` and are called by MCP, setup, starter content and seeds.

**Tech Stack:** Rails 8.1, Ruby 3.4, Postgres (jsonb), Mobility 1.3 (+ mobility-actiontext), closure_tree 9.8, Minitest + fixtures, Capybara/Selenium for system tests, sitemap_generator, Avo 4 (transitional).

**Spec:** `docs/superpowers/specs/2026-09-26-foundations-design.md` (binding; read the section a task names before starting it).

## Global Constraints

- Greenfield, no production: migrations drop old columns and indexes outright. No backfill and no compatibility shims; derived data is rebuilt (`PublicSite::Paths.rebuild!`).
- Code organisation (spec §3):
  - Concerns in `app/models/concerns/`; model-specific concerns under the model (`Page::TreeRanking`).
  - Services in `app/services/<plural resource>/`.
  - Public-site plain Ruby objects in `app/models/public_site/`.
  - `Locales` at top level.
- Services: `.call(...)` returns `ApplicationService::Result` (`Data.define(:record, :errors)`, `#ok?`). Validation and rule failures come back as an error Result; unexpected exceptions propagate. `authorize!` and `record_event` are no-op attachment points.
- Public reads of translated text go through `Locales.read(record, attribute, locale:)`. Admin, MCP and validations read literal per-locale values with no fallback.
- URL paths are built only by `PublicSite::Urls` (and stored only by `PublicSite::Paths`).
- Don't touch (structure review §6):
  - `Page` callback order: `has_closure_tree` first, `after_save` path/rank callbacks after it, `before_destroy :ensure_no_children, prepend: true`;
  - `update_columns` in cascades;
  - the `where(parent_id:)` query in cascades;
  - routes: `format: false`, two separate catch-alls, 302 for the default-language prefix, `before_action { request.format = :html }`;
  - `Setup::RedirectConstraint` as a route constraint;
  - the MCP controller shape.
- No Page/Post fixtures: build pages and posts in tests through code (the helpers from Task 9 once they exist).
- Long, load-bearing comments are the norm (CLAUDE.md). Match the density of `page.rb`/`routes.rb` for non-obvious logic and keep existing comments accurate when moving code.
- Roadmap guardrails:
  - no new integer enums;
  - no new `has_one_attached` on content models;
  - no new `after_save` side effects other than the path upkeep this spec defines;
  - no hand-built public URLs outside `PublicSite::Urls`.
- Tests:
  - full suite `PARALLEL_WORKERS=1 bin/rails test`;
  - system tests `bin/rails test test/system`, run alone (no other test process at the same time: shared test DB);
  - a single file with `bin/rails test <path>`.
- Lint: `bin/rubocop` on changed files; `bin/brakeman -q --no-pager` clean.
- Commits: conventional (`feat|fix|ref|test|docs|chore: …`), each ending with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.

## Review Focus

1. **Renaming a page that has descendants and listed posts:** every descendant and post URL changes in every enabled language, each old URL 301s to the new one, and nothing 404s. Pinned in Task 4, step 1 (`test "renaming a listing page moves its posts and redirects the old post URL"`).
2. **A post slug equal to a child page's slug under the same listing page** (`/blog/team` as both a page and a post): the second save fails with a validation error on `slug_<locale>`, never with a raw `ActiveRecord::RecordNotUnique`. Pinned in Task 4, step 1 (`test "a post cannot take a path a child page already holds"`).
3. **A scheduled post going live without any write:** the listing page's ETag changes once the time passes, so caches don't serve the old listing forever. Pinned in Task 6, step 1 (`test "etag changes when a scheduled post goes live"`).
4. **Changing the default language at runtime:** the new default serves unprefixed, the old default gets a `/<code>` prefix, and an explicit prefix naming the new default 302s. No stale `Current.site` inside one test or request. Pinned in Task 5, step 1 (`test "switching the default language flips the prefixes"`).
5. **Disabling and re-enabling a language:** its URLs 404 while disabled and come back unchanged after re-enabling, with slugs not regenerated. Pinned in Task 11, step 1 (`test "disable then enable restores the same URLs"`).

---

### Task 1: `Current.site`, the setup latch, and the `Locales` model

Spec: §4.1, §4.2, §6.1.

**Files:**
- Create: `config/supported_locales.rb`, `app/models/locales.rb`, `db/migrate/20260927100000_add_locales_to_site_settings.rb`, `test/models/locales_test.rb`
- Modify: `config/application.rb`, `app/models/current.rb`, `app/models/site_setting.rb`, `app/models/setup.rb`, `test/models/site_setting_test.rb`, `test/models/setup_test.rb`, every `SiteSetting.instance` call site listed by `grep -rn "SiteSetting.instance" app config lib db/seeds.rb` (except `SiteSetting.instance` itself and `db/seeds.rb`, which may keep it)

**Interfaces:**
- Produces:
  - `::SUPPORTED_LOCALES` (Hash `code => [english_name, native_name]`);
  - `Locales::SUPPORTED`, `Locales.enabled` (Array of String codes, ordered), `Locales.default` (String), `Locales.enabled?(code)` (Boolean), `Locales.name(code, native: false)` (String), `Locales.fallback_chain(code)` (Array of String);
  - `Current.site` (SiteSetting, lazily loaded);
  - `SiteSetting#locale_codes`, `SiteSetting#locale_entry(code)` (Hash or nil);
  - `Setup.reset!`.

- [ ] **Step 1: Write the failing tests**

`test/models/locales_test.rb`:

```ruby
require "test_helper"

class LocalesTest < ActiveSupport::TestCase
  setup do
    Current.reset
    site_settings(:default).update!(default_locale: "de",
      locales: [ { "code" => "de" }, { "code" => "en", "fallbacks" => [ "de" ] }, { "code" => "es" } ])
  end

  test "enabled lists the configured codes in order" do
    assert_equal %w[de en es], Locales.enabled
    assert_equal "de", Locales.default
    assert Locales.enabled?(:en)
    assert_not Locales.enabled?("fr")
  end

  test "fallback chain is own code, configured fallbacks, default, then the rest" do
    assert_equal %w[en de es], Locales.fallback_chain("en")
    assert_equal %w[es de en], Locales.fallback_chain("es")
    assert_equal %w[de en es], Locales.fallback_chain("de")
  end

  test "names come from the supported list" do
    assert_equal "German", Locales.name("de")
    assert_equal "Deutsch", Locales.name("de", native: true)
    assert_equal "XX", Locales.name("xx")
  end

  test "Current.site is reloaded after the site setting changes" do
    assert_equal "de", Current.site.default_locale
    site_settings(:default).update!(default_locale: "en")
    assert_equal "en", Current.site.default_locale
  end
end
```

Add to `test/models/site_setting_test.rb`:

```ruby
test "locales must be supported, unique and include the default" do
  setting = site_settings(:default)
  setting.locales = [ { "code" => "xx" } ]
  assert_not setting.valid?
  assert_includes setting.errors[:locales], "contains an unsupported language: xx"

  setting.locales = [ { "code" => "en" }, { "code" => "en" } ]
  assert_not setting.valid?
  assert_includes setting.errors[:locales], "lists a language twice"

  setting.locales = [ { "code" => "en" } ]
  setting.default_locale = "de"
  assert_not setting.valid?
  assert_includes setting.errors[:default_locale], "must be one of the enabled languages"

  setting.locales = [ { "code" => "en", "fallbacks" => [ "fr" ] } ]
  setting.default_locale = "en"
  assert_not setting.valid?
  assert_includes setting.errors[:locales], "en falls back to a language that isn't enabled: fr"

  setting.locales = []
  assert_not setting.valid?
  assert_includes setting.errors[:locales], "must enable at least one language"
end
```

Add to `test/models/setup_test.rb`:

```ruby
test "required? stops querying once setup is complete and resets when it is undone" do
  site_settings(:default).update!(setup_completed_at: Time.current)
  assert_not Setup.required?
  assert_no_queries { assert_not Setup.required? }

  site_settings(:default).update!(setup_completed_at: nil)
  assert Setup.required?
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/locales_test.rb test/models/site_setting_test.rb test/models/setup_test.rb`
Expected: FAIL (`uninitialized constant Locales`, unknown attribute `locales`).

- [ ] **Step 3: Implement**

`config/supported_locales.rb` defines a plain Ruby constant: `config/` is not autoloaded, and `config/application.rb` needs the list before any model loads. It holds about 40 entries. The list must include at least these codes, in this alphabetical order:

```ruby
# The languages ContentSpiel can serve (spec §4.1): ISO 639-1 code =>
# [English name, native name]. Which of these a site actually publishes is a
# runtime setting (`site_settings.locales`, read through `Locales`); this list
# only bounds what can be enabled. Plain Ruby rather than a YAML file or an
# autoloaded constant because config/application.rb needs it before any model
# loads, to hand Mobility its locale set.
SUPPORTED_LOCALES = {
  "ar" => [ "Arabic", "العربية" ], "bg" => [ "Bulgarian", "Български" ], "ca" => [ "Catalan", "Català" ],
  "cs" => [ "Czech", "Čeština" ], "da" => [ "Danish", "Dansk" ], "de" => [ "German", "Deutsch" ],
  "el" => [ "Greek", "Ελληνικά" ], "en" => [ "English", "English" ], "es" => [ "Spanish", "Español" ],
  "et" => [ "Estonian", "Eesti" ], "fi" => [ "Finnish", "Suomi" ], "fr" => [ "French", "Français" ],
  "he" => [ "Hebrew", "עברית" ], "hi" => [ "Hindi", "हिन्दी" ], "hr" => [ "Croatian", "Hrvatski" ],
  "hu" => [ "Hungarian", "Magyar" ], "id" => [ "Indonesian", "Bahasa Indonesia" ], "is" => [ "Icelandic", "Íslenska" ],
  "it" => [ "Italian", "Italiano" ], "ja" => [ "Japanese", "日本語" ], "ko" => [ "Korean", "한국어" ],
  "lt" => [ "Lithuanian", "Lietuvių" ], "lv" => [ "Latvian", "Latviešu" ], "nb" => [ "Norwegian Bokmål", "Norsk bokmål" ],
  "nl" => [ "Dutch", "Nederlands" ], "pl" => [ "Polish", "Polski" ], "pt" => [ "Portuguese", "Português" ],
  "ro" => [ "Romanian", "Română" ], "ru" => [ "Russian", "Русский" ], "sk" => [ "Slovak", "Slovenčina" ],
  "sl" => [ "Slovenian", "Slovenščina" ], "sr" => [ "Serbian", "Српски" ], "sv" => [ "Swedish", "Svenska" ],
  "th" => [ "Thai", "ไทย" ], "tr" => [ "Turkish", "Türkçe" ], "uk" => [ "Ukrainian", "Українська" ],
  "vi" => [ "Vietnamese", "Tiếng Việt" ], "zh" => [ "Chinese", "中文" ]
}.freeze
```

`config/application.rb`: add `require_relative "supported_locales"` after `require_relative "boot"`. **Leave `config.i18n.available_locales = %i[en de es]` and the fallbacks for now.** Widening to `SUPPORTED_LOCALES` happens in Task 11, once every loop reads `Locales.enabled`. Update the comment above it to say so.

Migration `db/migrate/20260927100000_add_locales_to_site_settings.rb`:

```ruby
class AddLocalesToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :locales, :jsonb, null: false,
      default: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ]
  end
end
```

Run `bin/rails db:migrate` and commit `db/schema.rb`.

`app/models/current.rb`:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :site
  delegate :user, to: :session, allow_nil: true

  # The site's settings row, loaded at most once per request (spec §6.1) --
  # every public link, locale check and fallback read goes through it, and
  # `SiteSetting.instance` is a query per call. Outside a request (console,
  # jobs, MCP) the same memo applies until something resets it; SiteSetting
  # resets it after every committed change so a stale copy never outlives a
  # write in the same process.
  def site
    super || (self.site = SiteSetting.instance)
  end
end
```

`app/models/site_setting.rb`: add the validations and helpers, keep `instance`, and add the after-commit resets:

```ruby
validate :locales_are_well_formed
validate :default_locale_is_enabled
after_commit :reset_cached_state

def locale_codes
  Array(locales).map { |entry| entry["code"].to_s }
end

def locale_entry(code)
  Array(locales).find { |entry| entry["code"].to_s == code.to_s }
end

private

def locales_are_well_formed
  codes = locale_codes
  return errors.add(:locales, "must enable at least one language") if codes.empty?

  unsupported = codes - ::SUPPORTED_LOCALES.keys
  errors.add(:locales, "contains an unsupported language: #{unsupported.join(', ')}") if unsupported.any?
  errors.add(:locales, "lists a language twice") if codes.uniq.size != codes.size

  Array(locales).each do |entry|
    missing = Array(entry["fallbacks"]).map(&:to_s) - codes
    errors.add(:locales, "#{entry['code']} falls back to a language that isn't enabled: #{missing.join(', ')}") if missing.any?
  end
end

def default_locale_is_enabled
  errors.add(:default_locale, "must be one of the enabled languages") unless locale_codes.include?(default_locale.to_s)
end

# Both caches hold a copy of this row's state: Current.site the whole row,
# Setup's latch whether setup is done. Resetting after commit (not after
# save) so a rolled-back change never leaves them pointing at data that no
# longer exists.
def reset_cached_state
  Current.site = nil
  Setup.reset!
end
```

Remove the old `validates :default_locale, inclusion:` line and its comment, and fold the comment's point into `default_locale_is_enabled`.

`app/models/locales.rb`:

```ruby
# The site's languages (spec §4): which are enabled, in what order, which is
# the default, and what each falls back to when a translation is missing.
# Everything reads `Current.site`, so a change in the settings takes effect on
# the next request without a deploy.
module Locales
  SUPPORTED = ::SUPPORTED_LOCALES

  module_function

  def enabled
    Current.site.locale_codes
  end

  def default
    Current.site.default_locale.to_s
  end

  def enabled?(code)
    code.present? && enabled.include?(code.to_s)
  end

  def name(code, native: false)
    entry = SUPPORTED[code.to_s]
    entry ? entry[native ? 1 : 0] : code.to_s.upcase
  end

  # The order translations are tried in for `code`: the language itself, the
  # fallbacks configured for it, the site's default language, then every other
  # enabled language in order -- so a page titled only in German still shows
  # *something* in Spanish rather than a blank heading.
  def fallback_chain(code)
    configured = Array(Current.site.locale_entry(code)&.fetch("fallbacks", nil)).map(&:to_s)
    ([ code.to_s ] + configured + [ default ] + enabled).uniq
  end
end
```

`app/models/setup.rb`:

```ruby
module Setup
  # Once setup is done it stays done, so this stops querying after the first
  # "no" (spec §6.1) -- every request passes through
  # Setup::RedirectConstraint. SiteSetting resets the latch after any commit,
  # which covers tests that un-complete setup, and a console session that does.
  def self.required?
    return false if @completed

    completed = SiteSetting.where.not(setup_completed_at: nil).exists?
    @completed = true if completed
    !completed
  end

  def self.reset!
    @completed = nil
  end
  # complete! unchanged
end
```

Replace `SiteSetting.instance` with `Current.site` in every app/config call site found by `grep -rn "SiteSetting.instance" app config`. That covers the tools, setup controller, helpers, sitemap, slug_generation, Avo action/controller, and `Setup.complete!`. `db/seeds.rb` keeps `SiteSetting.instance` (it runs outside requests and creates the row). `ThemeHelper#theme_site` becomes `Current.site`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/locales_test.rb test/models/site_setting_test.rb test/models/setup_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. If an existing test changes the site setting through `update_columns` and then reads stale values, change it to `update!`. Don't add resets to production code.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add runtime locale settings and Current.site"
```

---

### Task 2: One fallback reader, literal Mobility reads, `LocalizedSlug`

Spec: §4.3, §3 (`LocalizedSlug`).

**Files:**
- Modify: `config/application.rb` (drop `config.i18n.fallbacks`), `config/initializers/mobility.rb`, `app/models/locales.rb`, `app/helpers/theme_helper.rb`, `app/views/content_blocks/_rich_text.html.erb`, `app/views/content_blocks/_post_list_detail.html.erb`, `app/views/content_blocks/post_list/_now.html.erb`, `app/models/page.rb`, `app/models/post.rb`, `app/models/starter_content.rb`, `app/avo/resources/page.rb`, `app/avo/resources/post.rb`, `app/avo/resources/content_block.rb`, `app/avo/resource_tools/nested_content_blocks.rb`, `app/avo/resources/site_setting.rb`, `app/views/setup/languages.html.erb`, `app/helpers/setup_helper.rb`
- Rename: `app/models/concerns/slug_generation.rb` → `app/models/concerns/localized_slug.rb`, `test/models/slug_generation_test.rb` → `test/models/localized_slug_test.rb`
- Test: `test/models/locales_test.rb`, `test/integration/locale_fallback_test.rb`

**Interfaces:**
- Consumes: `Locales.enabled`, `Locales.fallback_chain` (Task 1).
- Produces:
  - `Locales.read(record, attribute, locale: I18n.locale)` returns the first present value along the fallback chain, or nil;
  - `LocalizedSlug`: `localized_slug scope: :parent_id | :content_type` class macro (generation + per-locale presence + per-scope uniqueness), `#fill_blank_slugs(locales = Locales.enabled)` (public, used by `Locales::Enable` in Task 11).

- [ ] **Step 1: Write the failing tests**

Add to `test/models/locales_test.rb`:

```ruby
test "read walks the fallback chain and plain readers no longer fall back" do
  site_settings(:default).update!(default_locale: "de")
  post = Mobility.with_locale(:de) { Post.create!(content_type: :blog, title: "Hallo") }

  assert_nil Mobility.with_locale(:en) { post.title }
  assert_equal "Hallo", Locales.read(post, :title, locale: "en")
  assert_nil Locales.read(nil, :title)
end

test "read falls back for rich text bodies too" do
  site_settings(:default).update!(default_locale: "de")
  post = Mobility.with_locale(:de) { Post.create!(content_type: :blog, title: "Hallo", body: "<p>Text</p>") }

  assert_includes Locales.read(post, :body, locale: "es").to_s, "Text"
end
```

Add to `test/integration/locale_fallback_test.rb` (follow that file's existing setup style for a `de`-default site):

```ruby
test "a German-only rich text block renders its body on the English page" do
  # de default; child page titled only in German with a rich_text block whose body exists only in de
  # GET /en/<slug> -> the German body text is in the response
end
```

Fill the test in using the file's own helpers: create the page and block with `Mobility.with_locale(:de) { ... }`, then `get "/en/#{slug}"` and `assert_includes response.body, "German body"`.

Rename `test/models/slug_generation_test.rb` → `test/models/localized_slug_test.rb`, rename the class, and add:

```ruby
test "slug uniqueness is enforced per scope and locale through the macro" do
  a = Post.create!(content_type: :blog, title: "Same")
  b = Post.new(content_type: :blog, title: "Same")
  assert_not b.valid?
  assert b.errors[Mobility.normalize_locale_accessor(:slug, :en)].any? { |m| m.include?("EN") }
  assert Post.new(content_type: :now_update, title: "Same").valid?
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/locales_test.rb test/models/localized_slug_test.rb test/integration/locale_fallback_test.rb`
Expected: FAIL (`undefined method read`, uninitialized `LocalizedSlug`, plain reader still falls back).

- [ ] **Step 3: Implement**

1. **Turn off implicit fallbacks.**
   - Delete `config.i18n.fallbacks = [ :en ]` and its comment from `config/application.rb`.
   - In `config/initializers/mobility.rb`, keep the `fallbacks` plugin but make it default to *no* fallback, so plain readers return the literal value while a per-read `fallback:` still works.
   - **Verify against the installed gem** (`bundle show mobility`, `lib/mobility/plugins/fallbacks.rb`) which call achieves "off by default" in 1.3. Candidates: `fallbacks false`, or `fallbacks({})` combined with removing I18n fallbacks.
   - Pin the chosen behaviour with the "plain readers no longer fall back" assertion above.
   - Rewrite the initializer comment: plain readers are literal; public views read through `Locales.read`.
2. **Add `Locales.read`** to `app/models/locales.rb`:

```ruby
# The one fallback-aware reader for public output (spec §4.3): the first
# present value walking `fallback_chain(locale)`. Each step reads the literal
# per-locale value (plain Mobility readers no longer fall back), so a
# translation left blank in German shows the default language's text rather
# than nothing. Works for jsonb attributes and ActionText bodies alike --
# `present?` on a rich text is "has non-blank content".
def read(record, attribute, locale: I18n.locale)
  return nil if record.nil?

  fallback_chain(locale).each do |code|
    value = record.public_send(attribute, locale: code.to_sym)
    return value if value.present?
  end
  nil
end
```

   If the action_text backend doesn't accept `locale:` on its reader, use `Mobility.with_locale(code) { record.public_send(attribute) }` inside the loop. Keep one implementation for both backends.
3. **Point `ThemeHelper#translated` at `Locales.read`.**
   - Its body becomes `Locales.read(record, attribute)`.
   - Delete `translated_fallback_locales` and rewrite the comment: the fallback order now lives in `Locales.fallback_chain`, and bodies are covered.
   - In the three body views, replace `block.body`, `post.body` and `latest.body` with `translated(block, :body)`, `translated(post, :body)` and `translated(latest, :body)`.
4. **`LocalizedSlug`.** Rename the concern to `LocalizedSlug` (`app/models/concerns/localized_slug.rb`) and give it a class macro:

```ruby
module LocalizedSlug
  extend ActiveSupport::Concern

  class_methods do
    # `scope:` names the column two records must share for their slugs to
    # clash: siblings (`parent_id`) for pages, the content type for posts.
    def localized_slug(scope:)
      class_attribute :localized_slug_scope, instance_writer: false, default: scope
      before_validation :fill_blank_slugs
      validate :slug_is_unused_in_every_locale
    end
  end

  # Public so Locales::Enable can fill a newly enabled language's slugs.
  def fill_blank_slugs(locales = Locales.enabled)
    # body of today's fill_blank_slugs_from_titles, iterating `locales`, with
    # the fallback title taken along Locales.fallback_chain(locale) over the
    # raw title hash (own title first, then the chain) instead of
    # blank_slug_fallback_title's default-then-first rule.
  end

  private

  # body of Page#slug_is_unused_among_siblings_in_every_locale /
  # Post#slug_is_unused_in_every_locale, iterating Locales.enabled and
  # scoping by `where(localized_slug_scope => public_send(localized_slug_scope))`.
  def slug_is_unused_in_every_locale; end

  def generates_slugs?
    true
  end
end
```

   Write the two method bodies out in full by moving the existing code, and keep the existing comments with the words adjusted: "SiteSetting#default_locale" → "the locale's fallback chain", and "Mobility.available_locales" → "Locales.enabled". Then:
   - In `Page`: replace `include SlugGeneration` with `include LocalizedSlug` plus `localized_slug scope: :parent_id`, and delete `slug_is_unused_among_siblings_in_every_locale` and its `validate` line.
   - In `Post`: `localized_slug scope: :content_type`, and delete `slug_is_unused_in_every_locale`.
   - Keep `Page#generates_slugs?` (root exemption).
5. **Replace loops over `Mobility.available_locales` / `I18n.available_locales`** with `Locales.enabled` everywhere outside `config/`:
   - `Page#per_locale`
   - `StarterContent.find_in_any_locale`
   - the Avo resources and `nested_content_blocks.rb`: their per-locale tabs/fields, and `site_setting.rb` default-locale options
   - `app/views/setup/languages.html.erb`
   - `ThemeHelper#language_links`

   For `Page#slug_in`: path building must use the literal slug now. Replace the body with `public_send(Mobility.normalize_locale_accessor(:slug, locale))`, and rewrite its comment: every enabled locale has a slug from `LocalizedSlug`, so no fallback is needed.
6. **Language names:** replace `SetupHelper::LANGUAGE_NAMES` with `Locales.name(code, native: true)`. Keep `SetupHelper#language_name` delegating to it, and delete the constant.

- [ ] **Step 4: Run the tests to verify they pass**

Run: the three files from step 2, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. Tests that relied on the plain reader falling back to English must switch to `Locales.read`, or assert the literal value. List each one in your report.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: read public translations along the site's fallback chain"
```

---

### Task 3: `public_paths` for pages

Spec: §5.1, §5.2, §5.4 (pages).

**Files:**
- Create: `db/migrate/20260927110000_create_public_paths.rb`, `app/models/public_path.rb`, `app/models/public_site/paths.rb`, `app/models/concerns/has_public_paths.rb`, `lib/tasks/public_paths.rake`, `test/models/public_site/paths_test.rb`
- Modify: `app/models/page.rb`, `app/controllers/pages_controller.rb` (lookup only), `db/seeds.rb` (call `rebuild!` at the end), `test/models/page_test.rb` (only for removed APIs)

**Interfaces:**
- Consumes: `Locales.enabled`, `LocalizedSlug`.
- Produces:
  - `PublicPath` (AR, polymorphic `record`), scopes `.current`, `.redirects`;
  - `PublicSite::Paths.compute(record)` returns `{ "de" => "/about" | nil, ... }` for enabled locales;
  - `PublicSite::Paths.sync(record)`, `PublicSite::Paths.sync_subtree(page)`, `PublicSite::Paths.rebuild!`, `PublicSite::Paths.current_path(record, locale)` (String or nil);
  - `Page#full_path(locale)`, which now reads `public_paths` and returns nil when the page has no current path;
  - `Page.find_by_public_path(locale, path)`, a temporary lookup used by `PagesController` until Task 6;
  - notification `"public_paths.changed"` with payload `{ record:, locale:, from:, to: }`.

- [ ] **Step 1: Write the failing tests**

`test/models/public_site/paths_test.rb`:

```ruby
require "test_helper"

class PublicSite::PathsTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  def current(record, locale = "en") = PublicSite::Paths.current_path(record, locale)

  test "root is / and children nest in every enabled locale" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)

    assert_equal "/", current(@root)
    assert_equal "/about", current(about)
    assert_equal "/about/team", current(team, "de")
  end

  test "renaming keeps the old path as a redirect and cascades to descendants" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)

    Mobility.with_locale(:en) { about.update!(slug: "company") }

    assert_equal "/company/team", current(team)
    old = PublicPath.find_by(locale: "en", path: "/about/team")
    assert_not old.current
    assert_equal team, old.record
  end

  test "a new page reclaims a path that is only a redirect" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    Mobility.with_locale(:en) { about.update!(slug: "company") }

    fresh = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    assert_equal "/about", current(fresh)
    assert_equal 1, PublicPath.where(locale: "en", path: "/about").count
  end

  test "a sibling cannot take a current path" do
    Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    clash = Page.new(parent: @root, title: "Other", slug: "about")
    assert_not clash.valid?
    assert clash.errors[Mobility.normalize_locale_accessor(:slug, :en)].any?
  end

  test "destroying a page removes its rows" do
    page = Page.create!(parent: @root, title: "Gone", published_at: 1.day.ago)
    page.destroy!
    assert_not PublicPath.exists?(record: page)
  end

  test "changes are announced after commit" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    events = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { events << payload }, "public_paths.changed") do
      Mobility.with_locale(:en) { about.update!(slug: "company") }
    end
    assert_includes events, { record: about, locale: "en", from: "/about", to: "/company" }
  end

  test "rebuild! recreates current rows from slugs" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    PublicPath.delete_all
    PublicSite::Paths.rebuild!
    assert_equal "/about", current(about)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/public_site/paths_test.rb`
Expected: FAIL (`uninitialized constant PublicPath`).

- [ ] **Step 3: Implement**

Migration:

```ruby
class CreatePublicPaths < ActiveRecord::Migration[8.1]
  def change
    create_table :public_paths do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :locale, null: false
      t.string :path, null: false
      t.boolean :current, null: false, default: true
      t.timestamps
    end
    add_index :public_paths, [ :locale, :path ], unique: true
    add_index :public_paths, [ :record_type, :record_id, :locale ], unique: true, where: "current",
      name: "index_public_paths_one_current_per_record_locale"
    add_index :public_paths, [ :record_type, :record_id ]

    remove_index :pages, name: "index_pages_on_cached_path_de"
    remove_index :pages, name: "index_pages_on_cached_path_en"
    remove_index :pages, name: "index_pages_on_cached_path_es"
    remove_index :pages, name: "index_pages_on_parent_id_and_slug_de"
    remove_index :pages, name: "index_pages_on_parent_id_and_slug_en"
    remove_index :pages, name: "index_pages_on_parent_id_and_slug_es"
    remove_column :pages, :cached_paths, :jsonb, default: {}, null: false
  end
end
```

`app/models/public_path.rb`:

```ruby
# One public URL of a page or post in one language (spec §5.1). `current`
# rows are live addresses; the rest are addresses the record used to have,
# kept so old links 301 to where the record lives now. Written only by
# PublicSite::Paths -- never by hand -- so the table always matches the
# slugs and tree it is derived from.
class PublicPath < ApplicationRecord
  belongs_to :record, polymorphic: true

  scope :current, -> { where(current: true) }
  scope :redirects, -> { where(current: false) }
end
```

`app/models/public_site/paths.rb`:

```ruby
# Derives and stores every public URL (spec §5.4). Called from model
# callbacks (HasPublicPaths) rather than from services on purpose: Avo,
# seeds and fixtures-built data all save through ActiveRecord, and every
# one of those writes has to leave the URL table correct.
module PublicSite
  module Paths
    module_function

    def current_path(record, locale)
      PublicPath.current.find_by(record: record, locale: locale.to_s)&.path
    end

    # { locale => path or nil } for every enabled locale. nil means "no URL"
    # (a post nothing lists, a non-root page with a blank slug).
    def compute(record)
      Locales.enabled.index_with { |locale| compute_path(record, locale) }
    end

    def sync(record)
      compute(record).each { |locale, path| write(record, locale, path) }
    end

    # A page and everything below it, top-down, reading each parent's freshly
    # written row. Queried by parent_id rather than through `children`: an
    # association loaded earlier in the request would still hold pre-save
    # slugs (the same reason Page's old cascade queried).
    def sync_subtree(page)
      sync(page)
      Page.where(parent_id: page.id).find_each { |child| sync_subtree(child) }
    end

    def rebuild!
      PublicPath.transaction do
        PublicPath.delete_all
        root = Page.find_by(parent_id: nil)
        sync_subtree(root) if root
      end
    end

    def compute_path(record, locale)
      case record
      when Page then page_path(record, locale)
      end
    end

    def page_path(page, locale)
      return "/" if page.parent_id.nil?

      segment = page.public_send(Mobility.normalize_locale_accessor(:slug, locale))
      parent_path = current_path(page.parent, locale)
      return nil if segment.blank? || parent_path.nil?

      parent_path == "/" ? "/#{segment}" : "#{parent_path}/#{segment}"
    end

    # Moves the record's current row to `path` in `locale`: the old current
    # row stays behind as a redirect; a redirect row already holding `path`
    # (any record's) is dropped so the address can be reused; no path at all
    # removes the record's rows for that locale, since there is nowhere left
    # to redirect them to.
    def write(record, locale, path)
      current = PublicPath.current.find_by(record: record, locale: locale)
      return if current&.path == path

      if path.nil?
        PublicPath.where(record: record, locale: locale).delete_all
      else
        current&.update_columns(current: false, updated_at: Time.current)
        PublicPath.redirects.where(locale: locale, path: path).delete_all
        PublicPath.create!(record: record, locale: locale, path: path, current: true)
      end
      announce(record, locale, current&.path, path)
    end

    def announce(record, locale, from, to)
      ActiveRecord.after_all_transactions_commit do
        ActiveSupport::Notifications.instrument("public_paths.changed", record: record, locale: locale, from: from, to: to)
      end
    end
  end
end
```

`app/models/concerns/has_public_paths.rb`:

```ruby
# Keeps a record's rows in public_paths in step with its slugs (spec §5.4),
# and refuses a slug whose resulting path another record already holds --
# as a form error, before the unique index would reject it as an exception.
module HasPublicPaths
  extend ActiveSupport::Concern

  included do
    has_many :public_paths, as: :record, dependent: :delete_all
    validate :public_paths_are_available
  end

  def full_path(locale)
    PublicSite::Paths.current_path(self, locale)
  end

  private

  def public_paths_are_available
    PublicSite::Paths.compute(self).each do |locale, path|
      next if path.nil?

      taken = PublicPath.current.where(locale: locale, path: path).where.not(record_type: self.class.name, record_id: id).exists?
      next unless taken

      errors.add(Mobility.normalize_locale_accessor(:slug, locale), :taken,
        message: "gives the address #{path}, which is already taken in #{locale.upcase}")
    end
  end
end
```

`compute` on an unsaved page reads the parent's stored path, so validation works before the first save.

In `Page`:
- `include HasPublicPaths` after `has_closure_tree`.
- Replace `after_save :recompute_cached_paths` with `after_save :sync_public_paths`. Keep the same position and comment spirit: it's declared after `has_closure_tree` so it runs after closure_tree's `after_save`. `sync_public_paths` is `PublicSite::Paths.sync_subtree(self)`.
- Delete `full_path`'s old body, `find_by_full_path`, `write_cached_paths`, `paths_under`, `slug_in`, `recompute_cached_paths`, `compute_full_path`, `path_segment_pages`, `build_path` and `per_locale`.
- Move their still-true comments (two-pages-one-URL, `update_columns`, the `where(parent_id:)` query) onto the new code in `PublicSite::Paths`.
- Add a temporary class method, used only by `PagesController` until Task 6:

```ruby
# Temporary bridge for PagesController until PublicSite::Resolver (Task 6).
def self.find_by_public_path(locale, path, include_unpublished: false)
  scope = include_unpublished ? all : published
  scope.where(id: PublicPath.current.where(record_type: "Page", locale: locale.to_s, path: path).select(:record_id)).first
end
```

In `PagesController`, replace both `Page.find_by_full_path` calls with `Page.find_by_public_path`. `pages_helper.rb` keeps working through `page.full_path(locale)`.

`lib/tasks/public_paths.rake`:

```ruby
namespace :public_paths do
  desc "Rebuild every public URL from slugs and the page tree"
  task rebuild: :environment do
    PublicSite::Paths.rebuild!
  end
end
```

Append `PublicSite::Paths.rebuild!` to the end of `db/seeds.rb`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails db:migrate && bin/rails test test/models/public_site/paths_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. Tests that asserted `cached_paths` directly switch to `full_path(locale)`. Post permalinks still work: the listing lookup goes through `Page.find_by_public_path`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: store page URLs per language in public_paths"
```

---

### Task 4: Canonical post URLs

Spec: §5.2 (posts), §5.3, §5.4 (post triggers).

**Files:**
- Create: `db/migrate/20260927120000_drop_post_slug_indexes.rb`
- Modify: `app/models/public_site/paths.rb`, `app/models/post.rb`, `app/models/content_block.rb`, `app/models/page.rb`, `app/controllers/pages_controller.rb`, `test/models/public_site/paths_test.rb`, `test/models/content_block_test.rb`

**Interfaces:**
- Consumes: `PublicSite::Paths` (Task 3).
- Produces:
  - `ContentBlock#lists?(post)` (Boolean);
  - `PublicSite::Paths.canonical_page(post)` (Page or nil);
  - `PublicSite::Paths.sync_posts(content_type)`: syncs posts of that type, or every post when `content_type` is nil;
  - `Post#full_path(locale)` via `HasPublicPaths`.
  - `Post.find_by_localized_slug` is deleted.

- [ ] **Step 1: Write the failing tests**

Add to `test/models/public_site/paths_test.rb`:

```ruby
def listing(parent, title, content_type, tag: nil)
  Page.create!(parent: parent, title: title, published_at: 1.day.ago).tap do |page|
    settings = { "content_type" => content_type }
    settings["tag"] = tag if tag
    page.content_blocks.create!(block_type: :post_list, position: 0, settings: settings)
  end
end

test "a post lives under the first listing page in tree order" do
  blog = listing(@root, "Blog", "blog")
  listing(@root, "Archive", "blog")
  post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

  assert_equal blog, PublicSite::Paths.canonical_page(post)
  assert_equal "/blog/hello", current(post)
end

test "a post nothing lists has no URL" do
  post = Post.create!(content_type: :now_update, title: "Now", published_at: 1.day.ago)
  assert_nil current(post)
end

test "adding a listing block gives existing posts a URL" do
  post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
  listing(@root, "Blog", "blog")
  assert_equal "/blog/hello", current(post)
end

test "renaming a listing page moves its posts and redirects the old post URL" do
  blog = listing(@root, "Blog", "blog")
  post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

  Mobility.with_locale(:en) { blog.update!(slug: "journal") }

  assert_equal "/journal/hello", current(post)
  assert_equal post, PublicPath.redirects.find_by(locale: "en", path: "/blog/hello").record
end

test "a post cannot take a path a child page already holds" do
  blog = listing(@root, "Blog", "blog")
  Page.create!(parent: blog, title: "Team", published_at: 1.day.ago)
  post = Post.new(content_type: :blog, title: "Team")

  assert_not post.valid?
  assert post.errors[Mobility.normalize_locale_accessor(:slug, :en)].any? { |m| m.include?("/blog/team") }
end

test "tag-filtered listings only host matching posts" do
  listing(@root, "Rails", "blog", tag: "rails")
  post = Post.create!(content_type: :blog, title: "Other", published_at: 1.day.ago)
  assert_nil current(post)
end
```

Add to `test/models/content_block_test.rb`:

```ruby
test "lists? matches content type and tag like listed_posts" do
  page = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  block = page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog", "tag" => " Rails " })
  post = Post.create!(content_type: :blog, title: "Hi")
  assert_not block.lists?(post)
  post.tags << Tag.create!(name: "rails")
  assert block.lists?(post.reload)
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/public_site/paths_test.rb test/models/content_block_test.rb`
Expected: FAIL (posts have no rows; `lists?` undefined).

- [ ] **Step 3: Implement**

Migration `db/migrate/20260927120000_drop_post_slug_indexes.rb`:

```ruby
class DropPostSlugIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :posts, name: "index_posts_on_content_type_and_slug_de"
    remove_index :posts, name: "index_posts_on_content_type_and_slug_en"
    remove_index :posts, name: "index_posts_on_content_type_and_slug_es"
  end
end
```

`ContentBlock#lists?(post)`: the same criteria as `listed_posts`, without the published filter:

```ruby
# Whether this block's listing would include `post`, ignoring publication
# (spec §5.3: the canonical page is chosen regardless of state; the resolver
# applies it). Mirrors `listed_posts` exactly -- both must agree on which
# posts a page is responsible for.
def lists?(post)
  return false unless post_list?
  return false if settings["content_type"].present? && settings["content_type"] != post.content_type

  tag = settings["tag"].to_s.strip
  tag.blank? || post.tags.any? { |t| t.name.downcase == tag.downcase }
end
```

`ContentBlock`: add `after_save :sync_listed_post_paths` and `after_destroy :sync_listed_post_paths`. Each calls `PublicSite::Paths.sync_posts(settings["content_type"].presence)` when the block is, or was, a `post_list`. Use `saved_change_to_block_type?` or `block_type_before_last_save` to detect "was".

In `PublicSite::Paths`:

```ruby
# The first page, in tree order (depth-first by sibling position), with a
# post_list block that lists `post` (spec §5.3).
def canonical_page(post)
  pages = ContentBlock.post_list.includes(:page).select { |block| block.lists?(post) }.map(&:page).uniq
  pages.min_by { |page| page.self_and_ancestors.reverse.map { |p| p.position.to_i } }
end

def post_path(post, locale)
  page = canonical_page(post)
  segment = post.public_send(Mobility.normalize_locale_accessor(:slug, locale))
  parent_path = page && current_path(page, locale)
  return nil if parent_path.nil? || segment.blank?

  parent_path == "/" ? "/#{segment}" : "#{parent_path}/#{segment}"
end

def sync_posts(content_type)
  scope = content_type ? Post.where(content_type: content_type) : Post.all
  scope.includes(:tags).find_each { |post| sync(post) }
end
```

Add `when Post then post_path(record, locale)` to `compute_path`, and extend `rebuild!` to call `sync_posts(nil)` after the page tree.

- **`Post`:** `include HasPublicPaths`, `after_save { PublicSite::Paths.sync(self) }`. Tag changes (`post.tags << tag`) don't save the post, so `PostTag` gets `after_commit { PublicSite::Paths.sync(post) }` (create and destroy).
- **`Page`:** after `sync_subtree`, re-sync posts whose canonical page may have moved:

```ruby
types = ContentBlock.post_list.where(page_id: self_and_descendant_ids).map { |b| b.settings["content_type"].presence }
types.include?(nil) ? PublicSite::Paths.sync_posts(nil) : types.uniq.each { |t| PublicSite::Paths.sync_posts(t) }
```

  Run this inside `sync_public_paths`. Moves and reorders change tree order, so on a position or parent change also sync every type listed anywhere: `PublicSite::Paths.sync_posts(nil)` when `saved_change_to_parent_id? || saved_change_to_position?`.
- **Delete `Post.find_by_localized_slug`.** In `PagesController#resolve_post_detail`, keep the "listing page + slug" lookup for now, but find the post through `PublicPath.current.find_by(record_type: "Post", locale:, path: requested_path)` and check that `@post_list_block.listed_posts(...)` includes it. Task 6 replaces this whole method.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails db:migrate && bin/rails test test/models/public_site/paths_test.rb test/models/content_block_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. Routing tests where a post was reachable under a *second* listing page now 404 there. Task 6 turns that into a 301; mark those assertions `skip "301 in Task 6"` with a note, and Task 6 removes the skips. List them in the report.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: give each post one canonical URL per language"
```

---

### Task 5: `PublicSite::Urls`, sitemap, hreflang, language switcher

Spec: §6.2, §6.5.

**Files:**
- Create: `app/models/public_site/urls.rb`, `test/models/public_site/urls_test.rb`, `test/integration/public_urls_guard_test.rb`
- Modify: `app/helpers/pages_helper.rb`, `app/helpers/theme_helper.rb`, `app/controllers/pages_controller.rb` (`redirect_default_locale_prefix`, helper `public_urls`), `config/sitemap.rb`, `app/views/layouts/application.html.erb` (hreflang), views calling `post_url_path(page, post)`, `app/tools/post_serializer.rb` (`url`), `test/lib/sitemap_test.rb`, `test/integration/public_theme_test.rb`, `test/tools/post_serializer_test.rb`

**Interfaces:**
- Consumes: `PublicSite::Paths.current_path`, `Locales`.
- Produces:
  - `PublicSite::Urls.new(preview: false, host: PublicSite::Urls.default_host)`;
  - `#prefix(locale)` (String);
  - `#path_for(record, locale = I18n.locale)` (String or nil);
  - `#url_for(record, locale = I18n.locale)` (String or nil);
  - `#alternates(record)` (Hash locale ⇒ url);
  - `#redundant_prefix?(locale_param)` (Boolean);
  - `PublicSite::Urls.default_host`;
  - helpers `public_urls`, `page_url_path(page, locale = I18n.locale)`, `post_url_path(post, locale = I18n.locale)`. Note that `post_url_path` loses its `page` argument.

- [ ] **Step 1: Write the failing tests**

`test/models/public_site/urls_test.rb`:

```ruby
require "test_helper"

class PublicSite::UrlsTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    @urls = PublicSite::Urls.new(host: "https://example.org")
  end

  test "default locale is unprefixed, others carry their code" do
    assert_equal "/about", @urls.path_for(@about, "en")
    assert_equal "/de/about", @urls.path_for(@about, "de")
    assert_equal "/de/", @urls.path_for(@root, "de")
    assert_equal "https://example.org/de/about", @urls.url_for(@about, "de")
  end

  test "preview urls stay under /preview" do
    urls = PublicSite::Urls.new(preview: true)
    assert_equal "/preview/about", urls.path_for(@about, "en")
    assert_equal "/preview/de/about", urls.path_for(@about, "de")
  end

  test "alternates list every enabled language with a path" do
    assert_equal %w[en de es], @urls.alternates(@about).keys
  end

  test "switching the default language flips the prefixes" do
    site_settings(:default).update!(default_locale: "de")
    urls = PublicSite::Urls.new
    assert_equal "/about", urls.path_for(@about, "de")
    assert_equal "/en/about", urls.path_for(@about, "en")
    assert urls.redundant_prefix?("de")
  end

  test "a record without a path has no url" do
    post = Post.create!(content_type: :now_update, title: "Unlisted")
    assert_nil @urls.path_for(post, "en")
  end
end
```

`test/integration/public_urls_guard_test.rb`:

```ruby
require "test_helper"

# Public paths are built in exactly one place (spec §6.2). A locale prefix
# interpolated anywhere else is the drift this guards against.
class PublicUrlsGuardTest < ActiveSupport::TestCase
  ALLOWED = %w[app/models/public_site/urls.rb].freeze

  test "no hand-built locale prefixes outside PublicSite::Urls" do
    offenders = Dir.glob(Rails.root.join("{app,config}/**/*.{rb,erb}")).filter_map do |file|
      relative = file.delete_prefix("#{Rails.root}/")
      next if ALLOWED.include?(relative)

      relative if File.read(file).match?(%r{"/#\{\s*(locale|code|default_locale)\b})
    end
    assert_empty offenders
  end
end
```

Extend `test/lib/sitemap_test.rb`: the sitemap lists published posts at their canonical URL, and a page entry carries `xhtml:link rel="alternate" hreflang=...` entries. Follow that file's existing parse style.

Add to `test/integration/public_theme_test.rb`: the page `<head>` contains `link[rel=alternate][hreflang=de]` and `[hreflang=x-default]`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/public_site/urls_test.rb test/integration/public_urls_guard_test.rb test/lib/sitemap_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

`app/models/public_site/urls.rb`:

```ruby
# The only place a public URL is built (spec §6.2). Paths come from
# public_paths; this adds the language prefix (none for the site's default
# language) and, for absolute URLs, the host. Memoizes lookups per instance:
# one instance per request renders every nav/listing link off it.
module PublicSite
  class Urls
    def self.default_host
      ENV.fetch("PUBLIC_HOST") { ENV.fetch("SITEMAP_HOST", "https://www.example.com") }
    end

    def initialize(preview: false, host: self.class.default_host)
      @preview = preview
      @host = host
      @paths = {}
    end

    def prefix(locale)
      code_prefix = locale.to_s == Locales.default ? "" : "/#{locale}"
      @preview ? "/preview#{code_prefix}" : code_prefix
    end

    def path_for(record, locale = I18n.locale)
      return nil if record.nil?

      path = @paths.fetch([ record.class.name, record.id, locale.to_s ]) do |key|
        @paths[key] = PublicSite::Paths.current_path(record, locale)
      end
      path && "#{prefix(locale)}#{path}"
    end

    def url_for(record, locale = I18n.locale)
      path = path_for(record, locale)
      path && "#{@host}#{path}"
    end

    def alternates(record)
      Locales.enabled.filter_map { |locale| (url = url_for(record, locale)) && [ locale, url ] }.to_h
    end

    # An explicit prefix naming the current default language: that URL has an
    # unprefixed twin, so PagesController 302s it there (302 because the
    # default can change at runtime).
    def redundant_prefix?(locale_param)
      locale_param.present? && locale_param.to_s == Locales.default
    end
  end
end
```

Then:

1. **Helpers.**
   - `PagesHelper`:
     - `page_url_path(page, locale = I18n.locale)` → `public_urls.path_for(page, locale)`;
     - `post_url_path(post, locale = I18n.locale)` → `public_urls.path_for(post, locale)`;
     - delete `locale_prefix`;
     - `document_title` uses `Current.site.title`.
   - `PagesController` gets `helper_method :public_urls` and `def public_urls = @public_urls ||= PublicSite::Urls.new(host: request.base_url)`.
   - `redirect_default_locale_prefix` uses `public_urls.redundant_prefix?(params[:locale])`. Keep the comment's reasoning.
2. **Views:** update every `post_url_path(page, post)` call to `post_url_path(post)`. Use `grep -rn post_url_path app`.
3. **Language switcher.** `ThemeHelper#language_links(record)` takes the page or post currently shown (callers pass `@post || @page`):

```ruby
def language_links(record)
  return [] if record.nil?

  Locales.enabled.filter_map do |code|
    path = public_urls.path_for(record, code) or next
    LanguageLink.new(code:, name: Locales.name(code, native: true), path:, current: code == I18n.locale.to_s)
  end
end
```

   Update the caller in `_language_switcher.html.erb`.
4. **Layout alternates.** In `app/views/layouts/application.html.erb`, after `<%= yield :head %>`:

```erb
<% if (alternate_record = @post || @page) %>
  <% public_urls.alternates(alternate_record).each do |code, url| %>
    <link rel="alternate" hreflang="<%= code %>" href="<%= url %>">
  <% end %>
  <% if (default_url = public_urls.url_for(alternate_record, Locales.default)) %>
    <link rel="alternate" hreflang="x-default" href="<%= default_url %>">
  <% end %>
<% end %>
```

5. **Sitemap.** Rewrite `config/sitemap.rb`: for every current `PublicPath` whose record is published (page: itself published; post: itself and its canonical page published; the full ancestor rule arrives in Task 6 as `PublicSite::Resolver.visible?`), add the URL built by `PublicSite::Urls.new(host: SitemapGenerator::Sitemap.default_host)`. Include `alternates:` from `urls.alternates(record)`, formatted as sitemap_generator expects: `[{ href:, lang: }]`. Keep the file's comments that still apply, and set `default_host` from `PublicSite::Urls.default_host`.
6. **MCP.** `PostSerializer` gets `url: PublicSite::Urls.new.url_for(post, locale)` (nil when unlisted). Update `test/tools/post_serializer_test.rb`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: the step-2 files, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: build every public URL through PublicSite::Urls"
```

---

### Task 6: `PublicSite::Resolver` and a cookie-less, cacheable `PublicController`

Spec: §6.3, §6.4 (`PublicController`, `PagesController`).

**Files:**
- Create: `app/models/public_site/resolver.rb`, `app/controllers/public_controller.rb`, `app/views/pages/not_found.html.erb`, `test/models/public_site/resolver_test.rb`, `test/integration/public_caching_test.rb`
- Modify: `app/controllers/pages_controller.rb`, `app/models/page.rb` (delete `find_by_public_path`), `app/views/layouts/application.html.erb` (drop `csrf_meta_tags`), `app/views/layouts/public/_footer.html.erb` (drop the edit link), `config/sitemap.rb` (use `Resolver.visible?`), `test/integration/pages_routing_test.rb`, `test/integration/preview_test.rb` (preview tests move to Task 7: mark them `skip "moves to /preview in Task 7"`)

**Interfaces:**
- Consumes: `PublicPath`, `PublicSite::Paths.canonical_page`, `PublicSite::Urls`.
- Produces:
  - `PublicSite::Resolver.new(scope: :published | :preview, urls: PublicSite::Urls.new)`;
  - `#call(locale:, path:)` returns `PublicSite::Resolver::Result` with `#status` (`:found | :redirect | :not_found`), `#record`, `#location`, `#http_status`;
  - `PublicSite::Resolver.visible?(record)` (Boolean: the record and all ancestors, and for a post its canonical page's chain, are published);
  - `PublicController` (base class);
  - `PublicSite.content_version` (String, for ETags).

- [ ] **Step 1: Write the failing tests**

`test/models/public_site/resolver_test.rb`:

```ruby
require "test_helper"

class PublicSite::ResolverTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @published = PublicSite::Resolver.new(scope: :published)
    @preview = PublicSite::Resolver.new(scope: :preview)
  end

  test "finds a published page" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    result = @published.call(locale: "en", path: "/about")
    assert_equal :found, result.status
    assert_equal about, result.record
  end

  test "a published child of a draft parent is hidden publicly but previewable" do
    draft = Page.create!(parent: @root, title: "Draft", published_at: nil)
    child = Page.create!(parent: draft, title: "Child", published_at: 1.day.ago)

    assert_equal :not_found, @published.call(locale: "en", path: "/draft/child").status
    assert_equal child, @preview.call(locale: "en", path: "/draft/child").record
  end

  test "old paths redirect permanently to the current one" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    Mobility.with_locale(:en) { about.update!(slug: "company") }

    result = @published.call(locale: "en", path: "/about")
    assert_equal [ :redirect, "/company", 301 ], [ result.status, result.location, result.http_status ]
  end

  test "a post under a second listing page redirects to its canonical url" do
    %w[Blog Archive].each do |title|
      Page.create!(parent: @root, title: title, published_at: 1.day.ago)
        .content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    end
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    result = @published.call(locale: "en", path: "/archive/hello")
    assert_equal [ :redirect, "/blog/hello", 301 ], [ result.status, result.location, result.http_status ]
  end

  test "drafts are not found publicly and their old paths don't reveal new ones" do
    draft = Page.create!(parent: @root, title: "Secret", published_at: nil)
    Mobility.with_locale(:en) { draft.update!(slug: "renamed") }
    assert_equal :not_found, @published.call(locale: "en", path: "/secret").status
  end

  test "unknown paths are not found" do
    assert_equal :not_found, @published.call(locale: "en", path: "/nope").status
  end
end
```

`test/integration/public_caching_test.rb`:

```ruby
require "test_helper"

class PublicCachingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  test "public pages set no cookies and are publicly cacheable" do
    get "/"
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_includes response.headers["Cache-Control"], "public"
    assert response.headers["ETag"].present?
    assert_select "meta[name=csrf-token]", count: 0
  end

  test "a matching etag gets a 304" do
    get "/"
    get "/", headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
  end

  test "etag changes when a scheduled post goes live" do
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Later", published_at: 1.hour.from_now)
    get "/"
    etag = response.headers["ETag"]

    travel 2.hours do
      get "/", headers: { "If-None-Match" => etag }
      assert_response :success
      assert_includes response.body, "Later"
    end
  end

  test "signed-in visitors get the same anonymous response" do
    sign_in_as(users(:one))
    get "/"
    assert_select "a", text: /Edit this page/, count: 0
  end

  test "unknown paths render the theme 404" do
    get "/nope"
    assert_response :not_found
    assert_select "h1", /not found/i
  end
end
```

Use the real user fixture name from `test/fixtures/users.yml`. `sign_in_as` comes from `test/test_helpers/session_test_helper.rb`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/public_site/resolver_test.rb test/integration/public_caching_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

`app/models/public_site/resolver.rb`:

```ruby
# What a public URL shows (spec §6.3): one indexed lookup in public_paths,
# then the visibility rule for the scope. `:published` needs the record and
# every ancestor page published -- a live page under a draft section is not
# public; `:preview` (signed-in editors) shows everything. Never raises for a
# missing record: a miss is a Result like any other.
module PublicSite
  class Resolver
    Result = Data.define(:status, :record, :location, :http_status) do
      def self.found(record) = new(status: :found, record:, location: nil, http_status: 200)
      def self.redirect(location, http_status = 301) = new(status: :redirect, record: nil, location:, http_status:)
      def self.not_found = new(status: :not_found, record: nil, location: nil, http_status: 404)
    end

    def self.visible?(record)
      pages = case record
      when Page then record.self_and_ancestors
      when Post then (page = PublicSite::Paths.canonical_page(record)) ? page.self_and_ancestors : nil
      end
      return false if pages.nil?
      return false if record.is_a?(Post) && !record.live?

      pages.where.not(id: Page.published.select(:id)).none?
    end

    def initialize(scope:, urls: PublicSite::Urls.new(preview: scope == :preview))
      @scope = scope
      @urls = urls
    end

    def call(locale:, path:)
      row = PublicPath.find_by(locale: locale.to_s, path: path)
      return from_row(row, locale) if row

      listing_fallback(locale, path) || Result.not_found
    end

    private

    def from_row(row, locale)
      return Result.not_found unless visible?(row.record)
      return Result.found(row.record) if row.current

      target = @urls.path_for(row.record, locale)
      target ? Result.redirect(target) : Result.not_found
    end

    # "A listing page's path + a post slug" where the post lives canonically
    # somewhere else: the URL shape every listing page served before posts had
    # one canonical address (spec §5.3), kept alive as a redirect.
    def listing_fallback(locale, path)
      parent_path, _, slug = path.rpartition("/")
      page_row = PublicPath.current.find_by(record_type: "Page", locale: locale.to_s, path: parent_path.presence || "/")
      return nil if page_row.nil? || slug.blank?

      post = Post.where("slug ->> ? = ?", locale.to_s, slug).find { |candidate| page_row.record.content_blocks.any? { |b| b.lists?(candidate) } }
      return nil if post.nil? || !visible?(post)

      target = @urls.path_for(post, locale)
      target && Result.redirect(target)
    end

    def visible?(record)
      @scope == :preview || self.class.visible?(record)
    end
  end
end
```

Add `PublicSite.content_version` in `app/models/public_site.rb`:

```ruby
# A fingerprint of everything a public page can show (spec §6.4). Site-wide
# rather than per record: a page renders the nav, its listings and the
# footer, so a title change on *any* page, a new post or a settings edit
# must invalidate every cached page. The two `published` maxima change when a
# scheduled page or post goes live -- a moment no row is written at.
module PublicSite
  module_function

  def content_version
    [
      Page.maximum(:updated_at), Post.maximum(:updated_at), ContentBlock.maximum(:updated_at),
      ActionText::RichText.maximum(:updated_at), PublicPath.maximum(:updated_at), Current.site.updated_at,
      Page.published.maximum(:published_at), Post.published.maximum(:published_at)
    ].map { |value| value&.to_f }.join("-")
  end
end
```

`app/controllers/public_controller.rb`:

```ruby
# Base for the public site (spec §6.4): no Authentication, no session, no
# CSRF token, no cookies -- the same response for everyone, so a browser or
# CDN may cache it. Preview (signed-in drafts) lives on /preview in its own
# controller for exactly this reason. Everything that varies per visitor
# (the theme toggle) stays in the browser.
class PublicController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  # Same reason as before the split: an Accept header naming another format
  # would otherwise reach a missing template and a 500.
  before_action { request.format = :html }

  helper_method :public_urls

  private

  def public_urls
    @public_urls ||= PublicSite::Urls.new(host: request.base_url)
  end
end
```

`PagesController < PublicController`:
- Drop `allow_unauthenticated_access`, `preview_allowed?`, `mark_preview` and `resolve_post_detail`.
- Keep `redirect_default_locale_prefix` (now through `public_urls.redundant_prefix?`), `render_in_requested_locale`, `effective_locale` (`params[:locale] || Locales.default`) and `requested_path`, with their comments.
- `show`:

```ruby
def show
  result = PublicSite::Resolver.new(scope: :published, urls: public_urls).call(locale: effective_locale, path: requested_path)

  case result.status
  when :found
    assign_record(result.record)
    expires_in 0, public: true, must_revalidate: true
    render :show if stale?(etag: [ result.record, PublicSite.content_version ], public: true)
  when :redirect
    redirect_to result.location, status: result.http_status
  else
    render :not_found, status: :not_found
  end
end

private

# A post renders inside its canonical listing page, as before.
def assign_record(record)
  if record.is_a?(Post)
    @post = record
    @page = PublicSite::Paths.canonical_page(record)
    @post_list_block = @page.content_blocks.find { |block| block.lists?(record) }
  else
    @page = record
  end
end
```

`stale?` answers a matching `If-None-Match` with 304 itself; `render :show` only runs for a stale request. Check that `expires_in` and `stale?(public: true)` together produce `Cache-Control: public, max-age=0, must-revalidate`. The caching test pins it.

Also:
- Create `app/views/pages/not_found.html.erb`: `<h1>` "Page not found" plus a link home, using the public layout and theme classes.
- Delete `Page.find_by_public_path`.
- Delete the `authenticated?` edit link from `_footer.html.erb`.
- Drop `csrf_meta_tags` from `app/views/layouts/application.html.erb`, with a comment on why.
- Delete `<% content_for :preview_banner ... %>` from `pages/show.html.erb`; Task 7 re-adds it for preview.
- `config/sitemap.rb` uses `PublicSite::Resolver.visible?(row.record)`.
- Remove the `skip`s Task 4 added in `pages_routing_test.rb` and assert the 301s.

- [ ] **Step 4: Run the tests to verify they pass**

Run: the step-2 files, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. `preview_test.rb` tests are skipped with the Task 7 note.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: resolve public URLs from public_paths and serve them cookie-less"
```

---

### Task 7: `/preview`

Spec: §6.4 (`PreviewController`, routes).

**Files:**
- Create: `app/controllers/preview_controller.rb`, `app/models/locale_route_constraint.rb`
- Modify: `config/routes.rb`, `app/views/layouts/public/_preview_banner.html.erb`, `app/views/pages/show.html.erb`, `test/integration/preview_test.rb` (rewrite for `/preview`)

**Interfaces:**
- Consumes: `PublicSite::Resolver`, `PublicSite::Urls.new(preview: true)`.
- Produces: routes `preview/:locale(/*path)` and `preview(/*path)` → `preview#show`; `LocaleRouteConstraint.matches?(request)`, which Task 11 reuses for the public routes.

- [ ] **Step 1: Write the failing tests**

Rewrite `test/integration/preview_test.rb`:

```ruby
require "test_helper"

class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @draft = Page.create!(parent: @root, title: "Draft", published_at: nil)
  end

  test "preview requires sign-in" do
    get "/preview/draft"
    assert_redirected_to new_session_path
  end

  test "signed-in editors preview drafts with a banner, no-store and noindex" do
    sign_in_as(users(:one))
    get "/preview/draft"
    assert_response :success
    assert_select "[role=status]", /Draft/
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_select "a[href=?]", "/avo/resources/pages/#{@draft.id}/edit"
  end

  test "links inside a preview stay in preview" do
    sign_in_as(users(:one))
    get "/preview/de/draft"
    assert_response :success
    assert_select "header a[href^='/preview']"
  end

  test "the public URL of a draft still 404s" do
    get "/draft"
    assert_response :not_found
  end
end
```

Adjust the Avo edit path to what `avo.edit_resources_page_path` generates, and the nav selector to the header's real markup.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/integration/preview_test.rb`
Expected: FAIL (no route).

- [ ] **Step 3: Implement**

`app/models/locale_route_constraint.rb`:

```ruby
# Route constraint for a `:locale` segment (spec §4.4): the enabled languages
# are a runtime setting, so a fixed regex in routes.rb can't express them. A
# failed constraint makes the router try the next route, which is what lets
# "/preview/about" fall through to the unprefixed preview route.
module LocaleRouteConstraint
  module_function

  def matches?(request)
    Locales.enabled?(request.path_parameters[:locale])
  end
end
```

`config/routes.rb`: before the two public catch-alls (and after `mcp`/`up`), add:

```ruby
# Signed-in preview of unpublished pages and posts (spec §6.4) -- its own
# URL space, so the public routes below can stay session-free and cacheable.
# Two routes for the same reason the public site has two: an optional
# `(/:locale)` would leave "about" in /preview/about to be read as a locale.
get "preview/:locale(/*path)", to: "preview#show", constraints: LocaleRouteConstraint,
  defaults: { path: "" }, format: false, as: :localized_preview
get "preview(/*path)", to: "preview#show", defaults: { path: "" }, format: false, as: :preview
```

`app/controllers/preview_controller.rb`:

```ruby
# Drafts and scheduled content at their would-be URLs, for signed-in editors
# only (spec §6.4). Renders the public theme's own views so the preview is
# faithful, but never cacheable or indexable, and every link it renders stays
# under /preview.
class PreviewController < ApplicationController
  before_action { request.format = :html }
  around_action :render_in_requested_locale
  helper_method :public_urls

  def show
    result = PublicSite::Resolver.new(scope: :preview, urls: public_urls).call(locale: effective_locale, path: requested_path)
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("X-Robots-Tag", "noindex")

    case result.status
    when :found
      assign_record(result.record)
      @preview_record = @post || @page
      render "pages/show"
    when :redirect
      redirect_to result.location, status: :found
    else
      render "pages/not_found", status: :not_found
    end
  end

  private

  def public_urls
    @public_urls ||= PublicSite::Urls.new(preview: true, host: request.base_url)
  end

  # effective_locale / requested_path / render_in_requested_locale /
  # assign_record: identical to PagesController's. Extract them into a
  # concern `PublicPageRendering` (app/controllers/concerns/) included by both
  # controllers rather than duplicating them.
end
```

Extract `PublicPageRendering` (the four methods plus `around_action`), include it in both controllers, and keep the comments on it.

Preview banner (`_preview_banner.html.erb`), rendered from `pages/show.html.erb` with `content_for :preview_banner` when `@preview_record` is set. It shows:
- the status (`@preview_record.status.humanize`);
- "Edit" → `avo.edit_resources_page_path(@page)` or `avo.edit_resources_post_path(@post)`;
- "View live" → `PublicSite::Urls.new.path_for(@preview_record)` when `@preview_record.live?`.

Keep the existing `role="status"` and theme classes.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/integration/preview_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: move signed-in preview to /preview"
```

---

### Task 8: Service base, `Current.actor`, `Posts::Save`, MCP tools on services

Spec: §7.1, §7.2 (`Posts::Save`), §7.3 (MCP).

**Files:**
- Create: `app/services/application_service.rb`, `app/services/posts/save.rb`, `test/services/posts/save_test.rb`
- Modify: `app/models/current.rb`, `app/models/post.rb` (`enum ... validate: true`), `app/controllers/application_controller.rb` (set actor), `app/controllers/mcp_controller.rb` (set actor), `app/tools/create_post_tool.rb`, `app/tools/update_post_tool.rb`, `test/tools/*`

**Interfaces:**
- Produces:
  - `ApplicationService.call(...)`;
  - `ApplicationService::Result` with `.success(record)`, `.failure(record, errors)`, `#ok?`, `#record`, `#errors` (Array of String);
  - `Current.actor` (User, ApiToken or nil), `Current.channel` (Symbol);
  - `Posts::Save.call(post = Post.new, attributes: {}, translations: {}, actor: Current.actor)`.

- [ ] **Step 1: Write the failing tests**

`test/services/posts/save_test.rb`:

```ruby
require "test_helper"

class Posts::SaveTest < ActiveSupport::TestCase
  test "creates a post with translations in several languages" do
    result = Posts::Save.call(attributes: { content_type: "blog" },
      translations: { "en" => { title: "Hello", body: "<p>Hi</p>" }, "de" => { title: "Hallo" } })

    assert result.ok?
    assert_equal "Hallo", result.record.title(locale: :de)
    assert_equal "hello", result.record.slug(locale: :en)
  end

  test "re-publishing a live post keeps its date; scheduled goes live now" do
    live = Post.create!(content_type: :blog, title: "Live", published_at: 3.days.ago)
    original = live.published_at
    Posts::Save.call(live, attributes: { published: true })
    assert_in_delta original, live.reload.published_at, 1

    scheduled = Post.create!(content_type: :blog, title: "Later", published_at: 1.day.from_now)
    Posts::Save.call(scheduled, attributes: { published: true })
    assert scheduled.reload.live?
  end

  test "published_at wins over published and false unpublishes" do
    post = Post.create!(content_type: :blog, title: "P", published_at: 1.day.ago)
    at = 2.days.from_now.change(usec: 0)
    Posts::Save.call(post, attributes: { published: true, published_at: at })
    assert_equal at, post.reload.published_at

    Posts::Save.call(post, attributes: { published: false })
    assert_nil post.reload.published_at
  end

  test "tag names are found or created case-insensitively" do
    Tag.create!(name: "rails")
    result = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ " Rails ", "ruby" ] },
      translations: { "en" => { title: "Tagged" } })
    assert_equal %w[rails ruby], result.record.tags.map(&:name).sort
    assert_equal 1, Tag.where(name: "rails").count
  end

  test "invalid input comes back as a failed result, nothing saved" do
    result = Posts::Save.call(attributes: { content_type: "nope" }, translations: { "en" => { title: "X" } })
    assert_not result.ok?
    assert result.errors.any? { |message| message.match?(/content type/i) }
    assert_equal 0, Post.count
  end
end
```

Keep the existing `test/tools/*` expectations. Add to `test/tools/update_post_tool_test.rb`: an update with a clashing slug returns an MCP error response whose text names the language.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/posts/save_test.rb`
Expected: FAIL (uninitialized `Posts`).

- [ ] **Step 3: Implement**

`app/services/application_service.rb`:

```ruby
# Base for the write path (spec §7). Admin, MCP, setup and seeds perform the
# same actions through these, so roles, the audit log and versioning get one
# place each to attach -- which is why ContentSpiel goes beyond plain "fat
# models" here. Validation and rule failures come back as a Result, never an
# exception, so every caller branches the same way; anything unexpected
# propagates.
class ApplicationService
  Result = Data.define(:record, :errors) do
    def self.success(record) = new(record:, errors: [])
    def self.failure(record, errors) = new(record:, errors: Array(errors))

    def ok? = errors.empty?
  end

  def self.call(...) = new(...).call

  private

  # Attachment point for policies (sub-project 5). Deliberately permissive.
  def authorize!(_action, _record) = true

  # Attachment point for the audit log (sub-project 5).
  def record_event(_name, **_data) = nil

  def success(record) = Result.success(record)
  def failure(record, errors = record.errors.full_messages) = Result.failure(record, errors)
end
```

`app/models/current.rb`: add `attribute :actor, :channel` and document the channel values `:admin | :mcp | :setup | :console | :system`. `ApplicationController` sets them in a `before_action`: `Current.actor = Current.user; Current.channel = :admin`. `SetupController` overrides the channel with `:setup` and `McpController` with `:mcp`, with the actor set to the authenticated `ApiToken`.

`app/models/post.rb`: `enum :content_type, { blog: 0, resume_entry: 1, now_update: 2 }, validate: true`. An unknown type becomes a validation error instead of an `ArgumentError`.

`app/services/posts/save.rb`:

```ruby
module Posts
  # Creates or updates a post (spec §7.2). Translations arrive per locale so an
  # admin form can save every language tab at once; publishing follows the
  # rules 8a established for MCP.
  class Save < ApplicationService
    TRANSLATED = %i[title slug excerpt body].freeze

    def initialize(post = Post.new, attributes: {}, translations: {}, actor: Current.actor)
      @post = post
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      authorize!(:save, @post)

      saved = Post.transaction do
        assign
        @post.save || raise(ActiveRecord::Rollback)
      end

      return failure(@post) unless saved

      record_event(:post_saved, post: @post)
      success(@post)
    end

    private

    def assign
      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @post.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
      @post.assign_attributes(@attributes.except(:published, :published_at, :tag_names))
      assign_publishing
      assign_tags if @attributes.key?(:tag_names)
    end

    # `published_at` schedules explicitly and wins; `published: true` makes a
    # draft or scheduled post live now but keeps a live post's date (8a);
    # `published: false` unpublishes; absent leaves it alone.
    def assign_publishing
      if @attributes.key?(:published_at)
        @post.published_at = @attributes[:published_at]
      elsif @attributes[:published] == true
        @post.published_at = Time.current unless @post.live?
      elsif @attributes[:published] == false
        @post.published_at = nil
      end
    end

    def assign_tags
      @post.tags = Array(@attributes[:tag_names]).map(&:to_s).map(&:strip).compact_blank.uniq(&:downcase).map do |name|
        Tag.where("LOWER(name) = ?", name.downcase).first || Tag.new(name: name.downcase)
      end
    end
  end
end
```

Check that `@post.tags =` on a persisted post inside the transaction rolls back with it (it writes join rows immediately). If it doesn't, move tag assignment after a successful save, still inside the transaction.

MCP tools become thin wrappers. `CreatePostTool.call`:

```ruby
def self.call(content_type:, title:, body: nil, excerpt: nil, locale: nil, published: false, server_context:)
  locale ||= Locales.default
  result = Posts::Save.call(attributes: { content_type: content_type, published: published },
    translations: { locale => { title: title, body: body, excerpt: excerpt }.compact })
  return error_response(result.errors.to_sentence) unless result.ok?

  data = Mobility.with_locale(locale) { PostSerializer.call(result.record, locale) }
  MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
end
```

(Add a small shared `error_response`, or inline `MCP::Tool::Response.new([...], error: true)` as today.)

- `UpdatePostTool` passes `attributes: { published: }` only when `published` isn't nil, and passes translations for the given locale. Keep the tool descriptions from the last round: live posts keep their date, scheduled posts go live now.
- The `locale` enum in every tool schema becomes `Locales::SUPPORTED.keys`. Schemas are built at class load, so enabled locales can't be used here. The tools reject a locale that isn't enabled with an error response.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services test/tools`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: save posts through Posts::Save, including from MCP"
```

---

### Task 9: Page and block services, `Page::TreeRanking`, content test helpers

Spec: §7.2 (pages, blocks), §3 (`Page::TreeRanking`), §11 (helpers), §7.3 (StarterContent, seeds).

**Files:**
- Create: `app/models/page/tree_ranking.rb`, `app/services/pages/save.rb`, `app/services/pages/move.rb`, `app/services/pages/destroy.rb`, `app/services/content_blocks/save.rb`, `app/services/content_blocks/reorder.rb`, `test/support/content_helper.rb`, `test/services/pages/*_test.rb`, `test/services/content_blocks/*_test.rb`
- Modify: `app/models/page.rb`, `app/models/starter_content.rb`, `db/seeds.rb`, `test/test_helper.rb`, `test/models/starter_content_test.rb`, `test/models/seeds_test.rb`

**Interfaces:**
- Consumes: `ApplicationService`, `Posts::Save` (Task 8).
- Produces:
  - `Pages::Save.call(page = Page.new, attributes: {}, translations: {}, actor:)`;
  - `Pages::Move.call(page, parent:, position:, actor:)`;
  - `Pages::Destroy.call(page, actor:)`;
  - `ContentBlocks::Save.call(block, attributes: {}, translations: {}, actor:)`;
  - `ContentBlocks::Reorder.call(page, ordered_ids, actor:)`;
  - test helpers `root_page`, `create_page(title:, parent: root_page, published: true, **translations)`, `create_post(title:, content_type: "blog", published: true, tags: [])`, `with_locales(codes, default:)`.

- [ ] **Step 1: Write the failing tests**

`test/support/content_helper.rb` (the helpers are what the tests below use):

```ruby
# Builds content through the services (spec §11), so tests exercise the same
# write path as admin, MCP and setup. No Page/Post fixtures: closure_tree
# rows and public_paths would be missing.
module ContentHelper
  def root_page
    Page.find_by(parent_id: nil) ||
      Pages::Save.call(attributes: { published: true }, translations: { Locales.default => { title: "Home", slug: "" } }).record
  end

  def create_page(title:, parent: root_page, published: true, translations: {})
    result = Pages::Save.call(attributes: { parent: parent, published: published },
      translations: { Locales.default => { title: title } }.merge(translations))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def create_post(title:, content_type: "blog", published: true, tags: [])
    result = Posts::Save.call(attributes: { content_type: content_type, published: published, tag_names: tags },
      translations: { Locales.default => { title: title } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def with_locales(codes, default:)
    site_settings(:default).update!(locales: codes.map { |code| { "code" => code } }, default_locale: default)
    PublicSite::Paths.rebuild!
    yield if block_given?
  end
end
```

Include it in `ActiveSupport::TestCase` in `test/test_helper.rb` (`require_relative "support/content_helper"`).

`test/services/pages/move_test.rb`:

```ruby
require "test_helper"

class Pages::MoveTest < ActiveSupport::TestCase
  test "moves a page to a rank under a new parent" do
    a = create_page(title: "A")
    b = create_page(title: "B")
    c = create_page(title: "C", parent: a)

    result = Pages::Move.call(c, parent: root_page, position: 0, actor: nil)
    assert result.ok?
    assert_equal [ c, a, b ], root_page.children.reload.to_a
    assert_equal "/c", c.full_path("en")
  end

  test "refuses the root and moves under itself or a descendant" do
    a = create_page(title: "A")
    child = create_page(title: "Child", parent: a)

    assert_not Pages::Move.call(root_page, parent: a, position: 0, actor: nil).ok?
    assert_not Pages::Move.call(a, parent: child, position: 0, actor: nil).ok?
    assert_not Pages::Move.call(a, parent: a, position: 0, actor: nil).ok?
  end

  test "an out-of-range position is clamped" do
    a = create_page(title: "A")
    create_page(title: "B")
    assert Pages::Move.call(a, parent: root_page, position: 99, actor: nil).ok?
    assert_equal "B", root_page.children.reload.first.title
  end
end
```

`test/services/pages/destroy_test.rb`:

```ruby
require "test_helper"

class Pages::DestroyTest < ActiveSupport::TestCase
  test "refuses the root and pages with children, deletes leaves" do
    parent = create_page(title: "Parent")
    leaf = create_page(title: "Leaf", parent: parent)

    assert_not Pages::Destroy.call(root_page, actor: nil).ok?
    result = Pages::Destroy.call(parent, actor: nil)
    assert_not result.ok?
    assert_includes result.errors, "cannot delete a page that still has children"

    assert Pages::Destroy.call(leaf, actor: nil).ok?
    assert_not Page.exists?(leaf.id)
  end
end
```

`test/services/pages/save_test.rb`: creating with translations in two languages; publishing rules (same assertions as `Posts::Save`); a slug clash returns an error Result naming the language.

`test/services/content_blocks/save_test.rb` and `reorder_test.rb`:
- `Save` appends when `position` is nil.
- A `post_list` block with an unknown content type fails.
- `Reorder` with ids not exactly matching the page's blocks fails and changes nothing.
- `Reorder` with the right ids writes positions `0..n-1`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services`
Expected: FAIL (uninitialized `Pages`).

- [ ] **Step 3: Implement**

1. **`Page::TreeRanking`.** Move `remember_requested_position`, `place_among_siblings` and their `before_save`/`after_save` lines, with the full comment above them, from `page.rb` into `app/models/page/tree_ranking.rb` as `module Page::TreeRanking; extend ActiveSupport::Concern; included do ... end; end`. `include Page::TreeRanking` in `Page` right after `include HasPublicPaths`, which is after `has_closure_tree`. Keep `after_save :sync_public_paths` declared after the TreeRanking include, so paths are computed after siblings are placed. Add a comment saying the order matters.
2. **`Pages::Save`** mirrors `Posts::Save`:
   - translated keys: `title slug subtitle meta_title meta_description hero_alt`;
   - attributes: `parent` (create only; ignored when persisted), `page_type`, `hero_image`, `published`/`published_at` with the same rules.
3. **`Pages::Move`:**

```ruby
module Pages
  # Moves a page to rank `position` under `parent` (spec §7.2). The rank
  # semantics live in Page::TreeRanking; this adds the rules a UI must not be
  # able to break: the homepage stays the root, and a page can't become its
  # own ancestor.
  class Move < ApplicationService
    def initialize(page, parent:, position:, actor: Current.actor)
      @page, @parent, @position, @actor = page, parent, position.to_i, actor
    end

    def call
      authorize!(:move, @page)
      return failure(@page, [ "The homepage can't be moved" ]) if @page.root?
      return failure(@page, [ "A page can't be moved under itself or one of its own subpages" ]) if @parent.self_and_ancestors.include?(@page)

      @page.parent = @parent
      @page.position = @position
      return failure(@page) unless @page.save

      record_event(:page_moved, page: @page)
      success(@page)
    end
  end
end
```

4. **`Pages::Destroy`:** root → failure `"The homepage can't be deleted"`. Otherwise `@page.destroy` returns `success(@page)`, or `failure(@page)` carrying `ensure_no_children`'s error.
5. **`ContentBlocks::Save`:**
   - translated keys: `caption alt body`;
   - attributes: `block_type settings image position`;
   - a nil `position` on a new block becomes `(block.page.content_blocks.maximum(:position) || -1) + 1`.
6. **`ContentBlocks::Reorder`:** the ids must equal `page.content_blocks.pluck(:id)` as a set, otherwise failure `"The new order must list exactly this page's blocks"`. Then `update_columns(position: index)` per block in a transaction. `update_columns` is deliberate: no callbacks, and block order doesn't affect URLs.
7. **`StarterContent`:** `ensure_home!`, `find_or_create_section_page!` and `find_or_create_sample_post!` create through `Pages::Save`, `ContentBlocks::Save` and `Posts::Save` (raise if `!result.ok?`: starter content is fixed input, so a failure is a bug). Lookups stay as they are, iterating `Locales.enabled`.
8. **`db/seeds.rb`:** create pages, blocks and posts through the services. Keep `SiteSetting.instance` and the dev-only guards, and end with `PublicSite::Paths.rebuild!`.
9. **Update tests.** In `test/models/starter_content_test.rb` and `seeds_test.rb`, change only what the move to services changes.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services test/models`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add page and block services and build content through them"
```

---

### Task 10: `ApiTokens::Issue` / `Revoke`

Spec: §7.2 (`ApiTokens`), §7.3 (setup token step, Avo action).

**Files:**
- Create: `app/services/api_tokens/issue.rb`, `app/services/api_tokens/revoke.rb`, `test/services/api_tokens/issue_test.rb`
- Modify: `app/controllers/setup_controller.rb` (`update_mcp_token`), `app/avo/actions/regenerate_api_token.rb`, `app/models/api_token.rb` (`generate!` becomes private to the service: make it a `private_class_method`, or leave it and delete every direct caller)

**Interfaces:**
- Produces: `ApiTokens::Issue.call(user, rotate: false, actor: Current.actor)` returns a Result whose `record` is `[api_token, raw_token]`; `ApiTokens::Revoke.call(token, actor: Current.actor)` returns a Result.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class ApiTokens::IssueTest < ActiveSupport::TestCase
  test "issues a token whose raw value authenticates" do
    result = ApiTokens::Issue.call(users(:one))
    token, raw = result.record
    assert result.ok?
    assert_equal token, ApiToken.authenticate(raw)
  end

  test "rotate revokes the user's active tokens first" do
    old, _ = ApiTokens::Issue.call(users(:one)).record
    ApiTokens::Issue.call(users(:one), rotate: true)
    assert old.reload.revoked_at.present?
  end

  test "revoke stops a token authenticating" do
    token, raw = ApiTokens::Issue.call(users(:one)).record
    assert ApiTokens::Revoke.call(token).ok?
    assert_nil ApiToken.authenticate(raw)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/api_tokens/issue_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

`ApiTokens::Issue#call`, inside a transaction:
- when `rotate`, revoke the user's active tokens;
- `token, raw = ApiToken.generate!(@user)`;
- `record_event(:api_token_issued, token:)`;
- return `Result.success([ token, raw ])`.

`ApiTokens::Revoke` calls `token.revoke!`.

Callers:
- `SetupController#update_mcp_token` becomes `_token, @raw_token = ApiTokens::Issue.call(Current.user).record`.
- The Avo action becomes `_token, raw = ApiTokens::Issue.call(current_user, rotate: true).record`.

`grep -rn "ApiToken.generate!" app` must then find only the service.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/api_tokens test/models/regenerate_api_token_action_test.rb test/integration/setup_optional_steps_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: issue and revoke API tokens through a service"
```

---

### Task 11: Enabling and disabling languages at runtime

Spec: §4.1 (widen available locales), §4.4, §8 (Avo shows enabled only).

**Files:**
- Create: `app/services/locales/enable.rb`, `app/services/locales/disable.rb`, `test/services/locales/enable_disable_test.rb`
- Modify: `config/application.rb` (`available_locales = SUPPORTED_LOCALES.keys`), `config/routes.rb` (public locale route uses `LocaleRouteConstraint`), `app/controllers/setup_controller.rb` + `app/views/setup/languages.html.erb` (write `locales`), `test/system/setup_wizard_test.rb`, `test/integration/setup_site_steps_test.rb` (or wherever the languages step is tested)

**Interfaces:**
- Consumes: `LocalizedSlug#fill_blank_slugs(locales)`, `PublicSite::Paths.rebuild!`, `LocaleRouteConstraint`.
- Produces: `Locales::Enable.call(code, fallbacks: [], actor:)`, `Locales::Disable.call(code, actor:)`.

- [ ] **Step 1: Write the failing tests**

```ruby
require "test_helper"

class Locales::EnableDisableTest < ActiveSupport::TestCase
  setup do
    @about = create_page(title: "About")
  end

  test "enabling a language gives every page and post a URL in it" do
    post = create_post(title: "Hello")
    assert Locales::Enable.call("fr", actor: nil).ok?
    assert_equal "/about", @about.full_path("fr")
    assert_includes Locales.enabled, "fr"
    assert_equal "hello", post.reload.slug(locale: :fr)
  end

  test "disable then enable restores the same URLs" do
    Mobility.with_locale(:de) { @about.update!(slug: "ueber-uns") }
    assert Locales::Disable.call("de", actor: nil).ok?
    assert_nil @about.full_path("de")

    assert Locales::Enable.call("de", actor: nil).ok?
    assert_equal "/ueber-uns", @about.full_path("de")
  end

  test "the default language can't be disabled and unknown codes fail" do
    assert_not Locales::Disable.call(Locales.default, actor: nil).ok?
    assert_not Locales::Enable.call("xx", actor: nil).ok?
  end
end
```

Add an integration test: after `Locales::Enable.call("fr")`, `GET /fr/about` returns 200. After `Locales::Disable.call("fr")`, `GET /fr/about` returns 404: the route constraint fails and `/fr/about` is then looked up as an unprefixed path, which doesn't exist.

Update `test/system/setup_wizard_test.rb`: the languages step now uses `select "Deutsch", from: "Default language"`, leaving the "Additional languages" defaults as they are. Keep `press "Save and continue"`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/locales/enable_disable_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

1. **Widen the locale set.** `config/application.rb`: `config.i18n.available_locales = SUPPORTED_LOCALES.keys.map(&:to_sym)`. Rewrite its comment: Mobility needs every *supported* locale at boot to accept reads and writes; the site's *enabled* ones are a runtime setting (`Locales`). Check that boot time and the test suite stay reasonable. If mobility-actiontext defines per-locale associations for every available locale and that becomes a real problem, report it as DONE_WITH_CONCERNS rather than working around it silently.
2. **`Locales::Enable`:**

```ruby
module Locales
  # Turns a supported language on (spec §4.4): it joins site_settings.locales,
  # every page and post gets a slug in it (from the fallback chain -- existing
  # slugs are never touched, so re-enabling a language restores its old
  # URLs), and public_paths is rebuilt so the new URLs exist immediately.
  class Enable < ApplicationService
    def initialize(code, fallbacks: [], actor: Current.actor)
      @code, @fallbacks, @actor = code.to_s, Array(fallbacks).map(&:to_s), actor
    end

    def call
      site = Current.site
      authorize!(:enable_locale, site)
      return success(site) if site.locale_codes.include?(@code)

      entry = { "code" => @code }
      entry["fallbacks"] = @fallbacks if @fallbacks.any?
      site.locales = site.locales + [ entry ]

      SiteSetting.transaction do
        raise ActiveRecord::Rollback unless site.save

        [ Page, Post ].each do |model|
          model.find_each do |record|
            record.fill_blank_slugs([ @code ])
            record.update_columns(slug: record.read_attribute(:slug)) if record.changed?
          end
        end
        PublicSite::Paths.rebuild!
      end

      return failure(site) if site.errors.any?

      record_event(:locale_enabled, code: @code)
      success(site)
    end
  end
end
```

   `rebuild!` truncates, so redirect history is lost when a language is enabled. Accept that and note it in a comment (greenfield). If that's wrong, the fix is a `sync_all` that keeps redirect rows.
3. **`Locales::Disable`:**
   - the default language → failure `"The default language can't be disabled"`;
   - an unknown or disabled code → success, no-op;
   - otherwise remove the entry (and drop the code from other entries' fallbacks), save, and `PublicPath.where(locale: @code).delete_all`.
4. **Public route constraint.** In `config/routes.rb`, change the public locale route from `constraints: { locale: /en|de|es/ }` to `constraints: LocaleRouteConstraint`, and update its comment: enabled languages are runtime data. The constraint failing must fall through to the unprefixed catch-all; the integration test above pins that.
5. **Setup languages step:**
   - The view gets a `select :default_locale` labelled "Default language": every supported language, native names, current default selected.
   - It also gets a `select :extra_locales, multiple: true` labelled "Additional languages", with the enabled non-default ones selected.
   - `update_languages` writes `locales: [ default, *extras ].uniq.map { { "code" => _1 } }` and `default_locale`, then calls `PublicSite::Paths.rebuild!`.
   - Keep the wording about the unprefixed default.
6. **Avo:** confirm the Avo resources (switched to `Locales.enabled` in Task 2) now show only enabled languages even though 40 are supported. Adjust `test/integration/avo_*` only where tab counts changed.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/locales`, then `PARALLEL_WORKERS=1 bin/rails test`, then `bin/rails test test/system` (alone)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: enable and disable languages at runtime"
```

---

### Task 12 (optional, cut if the branch runs long): move MCP tools under `Mcp::`

Spec: §3 (optional last step).

**Files:**
- Move: `app/tools/*.rb` → `app/mcp/tools/*.rb` (`CreatePostTool` → `Mcp::Tools::CreatePost`, etc.) and `app/tools/post_serializer.rb` → `app/mcp/post_serializer.rb` (`Mcp::PostSerializer`)
- Move: `test/tools/*` → `test/mcp/tools/*`, `test/mcp/post_serializer_test.rb`
- Modify: `app/controllers/mcp_controller.rb` (tool list)

**Interfaces:** produces `Mcp::Tools::{ListPosts,GetPost,CreatePost,UpdatePost}` and `Mcp::PostSerializer`. The MCP tool *names* the client sees must not change. Check how the `mcp` gem derives a tool's name (class name vs. an explicit `tool_name`), and set the name explicitly to today's value if needed.

- [ ] **Step 1: Write the failing test.** Add to `test/integration/mcp_test.rb`: `tools/list` returns the same tool names as before the move. Capture the current names first by running the existing test or reading its assertions.
- [ ] **Step 2: Run it.** `bin/rails test test/integration/mcp_test.rb`. It passes before the move; that is the baseline.
- [ ] **Step 3: Move the files** with `git mv`, rename the classes, set explicit tool names if required, and update `McpController`. `app/mcp/` autoloads as the `Mcp` namespace only if `app/mcp` is a root directory: Rails autoloads `app/*` subdirectories as roots, so `app/mcp/tools/create_post.rb` would be `Tools::CreatePost`. To get `Mcp::Tools::CreatePost`, use `app/mcp/mcp/tools/…` or add `app/mcp` to the autoload paths with namespace `Mcp`. Choose the Zeitwerk-correct layout, verify with `bin/rails zeitwerk:check`, and document the choice in a comment in `config/application.rb` if you add configuration.
- [ ] **Step 4: Run** `bin/rails zeitwerk:check`, `bin/rails test test/mcp test/integration/mcp_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`. Expected: PASS, tool names unchanged.
- [ ] **Step 5: Commit** `git commit -m "ref: move MCP tools under the Mcp namespace"`

---

### Task 13: Final verification

- [ ] **Step 1:** Run `PARALLEL_WORKERS=1 bin/rails test`. Expected: 0 failures, 0 errors, no leftover `skip`s from Tasks 4/6 (`grep -rn "skip \"" test` shows none added by this branch).
- [ ] **Step 2:** Run `bin/rails test test/system` alone. Expected: 0 failures.
- [ ] **Step 3:** Run `bin/rubocop`, `bin/brakeman -q --no-pager`, `bin/bundler-audit`, `bin/importmap audit`, `bin/rails zeitwerk:check`. Expected: all clean.
- [ ] **Step 4:** Run `bin/rails db:reset` (dev), then `bin/rails runner 'puts PublicPath.current.count'`. Expected: seeds build paths, count > 0.
- [ ] **Step 5:** Run `grep -rn "SiteSetting.instance" app config` (expected: only `site_setting.rb` itself and `current.rb`) and `grep -rn "available_locales" app` (expected: none outside comments). Fix and commit anything these turn up.
