# Editor Experience & Public Demo Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the public site render what editors configure in Claude Design's demo look (with backend and frontend CSS fully independent), and make the Avo admin usable by a non-technical editor.

**Architecture:** A second, isolated Tailwind build (`theme-default.css`) serves the public views, with its own `--th-*` tokens; the product build (`tailwind.css`) only scans product views. Models gain a `Publishable` concern, per-locale slug generation, typed resume fields and alt texts; the public controller gains a signed-in preview mode. The Avo side gets two small Stimulus controllers (type-dependent fields, inline block editor), status badges and publish actions, a dashboard, and a "Connect an AI assistant" page — all within Avo Community.

**Tech Stack:** Rails 8.1.3.1, Ruby 3.4.9, PostgreSQL, Mobility 1.3 (jsonb + action_text backends), closure_tree, Avo 4.2.4 Community, Hotwire (Turbo + Stimulus via import maps), Tailwind v4 via tailwindcss-rails 4.6 + tailwindcss-ruby, Propshaft, Minitest + fixtures, Capybara/Selenium headless Chrome.

**Spec:** `docs/superpowers/specs/2026-09-26-setup-wizard-design.md` — §9 (public demo theme, independent stylesheets) and §10 (editor experience). Background: `docs/product/2026-09-26-backend-product-review.md`.

## Global Constraints

- No new gems, no Avo paid add-ons (`avo-menu`, `avo-nested`, `avo-authorization`, dashboards).
- Minitest + fixtures only; no mocking library (Minitest 6 has no `stub`).
- JS is import maps + Stimulus. Controllers used on **public/product** pages live in `app/javascript/controllers/` (auto-registered). Controllers used **inside Avo** must also be registered in `app/javascript/avo.custom.js` via `window.Stimulus.register(...)`, like `pages-tree`.
- **CSS independence:** product views (`setup/`, `sessions/`, `passwords/`, `layouts/setup`, `layouts/product`, `setup_helper.rb`) are styled only by `app/assets/tailwind/application.css` → `tailwind.css` with `--cs-*` tokens; public views (`pages/`, `content_blocks/`, `layouts/application`, `layouts/public/`, `theme_helper.rb`) only by `app/assets/tailwind/themes/default/theme.css` → `theme-default.css` with `--th-*` tokens. The only shared view files are `app/views/shared/_theme_head.html.erb` and `_theme_toggle.html.erb`.
- Fonts are the `font-cs` / `font-cs-mono` utilities (never override Tailwind's `font-sans`/`font-mono`). `color-scheme` is only ever applied per layout `<body>` (`scheme-light dark:scheme-dark`).
- Translated attributes are Mobility jsonb: never `where(slug: …)` on them — use `.i18n` inside `Mobility.with_locale`, or `->>` SQL, as the existing code does.
- Match the codebase's comment convention: non-obvious invariants get a short load-bearing comment; keep existing ones intact.
- Commit messages: conventional (`feat|fix|ref|style|docs|test|chore`), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Sandbox notes (this machine only): full suite = `PARALLEL_WORKERS=1 bin/rails test`; single system test = `bin/rails test test/system/<file>` (not `test:system TEST=`); no `timeout` binary (use `perl -e 'alarm 300; exec @ARGV' <cmd>`); if `bin/rails db:migrate` hangs use `bin/rails runner 'ActiveRecord::Base.connection_pool.migration_context.migrate'` then `bin/rails runner 'ActiveRecord::Tasks::DatabaseTasks.dump_schema(ActiveRecord::Base.connection_db_config)'`. After view/CSS changes run `bin/rails tailwindcss:build` (which also builds the theme after Task 5).

## Review Focus

1. **A page save that fails validation after the editor added and typed into new blocks** must re-render with the typed text intact (new rows use a timestamp index). Test: Task 13.
2. **Post-list tag filter typed/selected with different case** ("Rails" vs stored "rails") still filters. Test: Task 2.
3. **Language switcher on a post with no German slug** must link to a URL that actually resolves (falls back to the English slug). Test: Task 6.
4. **Social links with odd URLs** — `HTTPS://` uppercase accepted, `javascript:` and unparsable URLs dropped without raising. Test: Task 6.
5. **Anonymous visitors never see unpublished content, including via a locale prefix (`/de/…`)**, while a signed-in preview response is `no-store`. Test: Task 8.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/concerns/publishable.rb` | `published` scope, `status`, `publish_now!`, `unpublish!` for Post and Page |
| `app/models/concerns/slug_generation.rb` | Fills blank per-locale slugs from per-locale titles |
| `app/models/public_path.rb` | Public URL of a Page/Post in a locale (used by Avo "View on site") |
| `app/models/{post,page,content_block,api_token}.rb` | Use the concerns; tag filter; resume `store_accessor`s; `alt`/`hero_alt`; token `status` |
| `db/migrate/20260927090000_add_alt_texts.rb` | `content_blocks.alt`, `pages.hero_alt` jsonb |
| `app/assets/tailwind/application.css` | Product entry, `source(none)` + product `@source`s |
| `app/assets/tailwind/themes/default/{theme,tokens,prose}.css` | Public theme entry, `--th-*` tokens, `.cs-prose` |
| `lib/tasks/theme_css.rake`, `Procfile.dev` | Build/watch the theme stylesheet |
| `app/views/layouts/product.html.erb` | Sign-in / password reset layout |
| `app/views/layouts/application.html.erb`, `app/views/layouts/public/_{header,footer,language_switcher,preview_banner}.html.erb` | Public layout |
| `app/helpers/theme_helper.rb` | Public-theme view helpers |
| `app/views/pages/*`, `app/views/content_blocks/**` | Public page and block templates |
| `app/controllers/pages_controller.rb` | Signed-in preview |
| `app/javascript/controllers/{type_fields,block_editor,clipboard}_controller.js` | Avo form behaviour |
| `app/avo/resources/*`, `app/avo/actions/{publish_now,unpublish,revoke_api_token}.rb` | Admin fields and actions |
| `app/views/avo/resource_tools/_nested_content_blocks.html.erb`, `app/views/avo/partials/_content_block_row.html.erb` | Block editor markup |
| `app/controllers/avo/tools_controller.rb`, `app/views/avo/tools/{dashboard,ai_assistant,ai_assistant_token}.html.erb`, `app/views/avo/sidebar/items/*` | Dashboard, AI assistant page |

---

# Part A — Model groundwork & bugfixes

Branch: `editor-experience` (already checked out; do not switch).

### Task 1: Slugs generated per locale for pages and posts

**Files:**
- Create: `app/models/concerns/slug_generation.rb`, `test/models/slug_generation_test.rb`
- Modify: `app/models/page.rb`, `app/models/post.rb`

**Interfaces:**
- Produces: `SlugGeneration` concern with private `fill_blank_slugs_from_titles` (before_validation). Pages/Posts no longer need a slug typed by hand.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/slug_generation_test.rb
require "test_helper"

class SlugGenerationTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "a new page gets a slug per locale from that locale's title" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About Us", title_de: "Über uns")

    assert_equal "about-us", page.slug_en
    assert_equal "uber-uns", page.slug_de
    assert_nil page.slug_es
  end

  test "an existing slug is never overwritten when the title changes" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About", slug_en: "who-we-are")
    page.update!(title_en: "About the team")

    assert_equal "who-we-are", page.reload.slug_en
  end

  test "a translation added later gets its slug on update" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About")
    page.update!(title_de: "Über")

    assert_equal "uber", page.reload.slug_de
  end

  test "the root page keeps its empty slug" do
    assert_equal "", @root.reload.slug_en
  end

  test "a post gets a slug per locale too" do
    post = Post.create!(content_type: :blog, title_en: "Hello World", title_de: "Hallo Welt")

    assert_equal "hello-world", post.slug_en
    assert_equal "hallo-welt", post.slug_de
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/models/slug_generation_test.rb`
Expected: FAIL/ERROR — `Slug can't be blank` on the first page create; `slug_de` nil on the post.

- [ ] **Step 3: Implement**

`app/models/concerns/slug_generation.rb`:

```ruby
# Fills each locale's blank slug from that locale's title (spec §10.1), so an
# editor never has to type a URL segment. Reads the raw jsonb title hash rather
# than the Mobility reader, which would fall back to English and hand German a
# copy of the English slug. Never overwrites a slug that is already set --
# changing a published page's URL must stay a deliberate act.
module SlugGeneration
  extend ActiveSupport::Concern

  included do
    before_validation :fill_blank_slugs_from_titles
  end

  private

  def fill_blank_slugs_from_titles
    return unless generates_slugs?

    titles = read_attribute(:title).to_h
    ::Mobility.available_locales.each do |locale|
      accessor = ::Mobility.normalize_locale_accessor(:slug, locale)
      title = titles[locale.to_s]
      next if public_send(accessor).present? || title.blank?

      public_send("#{accessor}=", title.parameterize)
    end
  end

  def generates_slugs?
    true
  end
end
```

In `app/models/page.rb`: add `include SlugGeneration` right after `extend Mobility`, and add in the `private` section:

```ruby
  # The homepage's slug is "" by design (see `path_segment_pages`).
  def generates_slugs?
    parent_id.present?
  end
```

In `app/models/post.rb`: add `include SlugGeneration` after `extend Mobility`; delete `before_validation :generate_slug_from_title, on: :create` and the private `generate_slug_from_title` method (and its comment).

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/models/slug_generation_test.rb test/models/post_test.rb test/models/page_test.rb`
Expected: PASS. Then `PARALLEL_WORKERS=1 bin/rails test` — green (fix any test that asserted "Slug can't be blank" on a *page* by giving it no title instead, and say so in your report).

- [ ] **Step 5: Commit**

```bash
git add app/models test/models
git commit -m "$(cat <<'EOF'
fix: generate page and post slugs per locale from titles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 2: Post-list tag filter

**Files:**
- Modify: `app/models/content_block.rb` (`listed_posts`)
- Test: `test/models/content_block_test.rb` (append)

**Interfaces:**
- Produces: `ContentBlock#listed_posts` honours `settings["tag"]` (case-insensitive tag name).

- [ ] **Step 1: Write the failing test** (append inside the class)

```ruby
  test "a post list filtered by tag lists only posts with that tag, ignoring case" do
    page = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    rails = Tag.create!(name: "rails")
    tagged = Post.create!(content_type: :blog, title: "Tagged", published_at: 1.day.ago)
    tagged.tags << rails
    Post.create!(content_type: :blog, title: "Untagged", published_at: 1.day.ago)
    block = page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "tag" => "Rails" })

    assert_equal [ tagged ], block.listed_posts.to_a
  end
```

- [ ] **Step 2: Run it** — `bin/rails test test/models/content_block_test.rb` → FAIL (both posts listed).

- [ ] **Step 3: Implement** — replace the body of `listed_posts` (keep its comment, add one line about the tag):

```ruby
  def listed_posts
    scope = Post.published
    content_type = settings["content_type"]
    scope = scope.where(content_type: content_type) if content_type.present?

    # Tag names are matched case-insensitively: editors type "Rails" for a tag
    # stored as "rails".
    tag = settings["tag"]
    if tag.present?
      scope = scope.where(id: PostTag.joins(:tag).where("LOWER(tags.name) = ?", tag.downcase).select(:post_id))
    end

    scope
  end
```

- [ ] **Step 4:** `bin/rails test test/models/content_block_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `fix: apply the post list tag setting` (+ trailer).

### Task 3: `Publishable` status and preview-aware lookups

**Files:**
- Create: `app/models/concerns/publishable.rb`, `test/models/publishable_test.rb`
- Modify: `app/models/post.rb`, `app/models/page.rb`, `app/models/content_block.rb`

**Interfaces:**
- Produces: `Publishable` (included in Post, Page): scope `published`; `#status` → `"draft" | "scheduled" | "live"`; `#live?`; `#publish_now!`; `#unpublish!`. `Page.find_by_full_path(locale, path, include_unpublished: false)`. `ContentBlock#listed_posts(include_unpublished: false)`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/publishable_test.rb
require "test_helper"

class PublishableTest < ActiveSupport::TestCase
  test "status follows published_at" do
    assert_equal "draft", Post.new(published_at: nil).status
    assert_equal "scheduled", Post.new(published_at: 1.day.from_now).status
    assert_equal "live", Post.new(published_at: 1.minute.ago).status
    assert_equal "live", Page.new(published_at: 1.minute.ago).status
  end

  test "publish_now! and unpublish! set and clear published_at" do
    post = Post.create!(content_type: :blog, title: "Draft")
    post.publish_now!
    assert post.reload.live?

    post.unpublish!
    assert_equal "draft", post.reload.status
  end

  test "find_by_full_path only includes unpublished pages when asked" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(parent: root, page_type: :standard, title: "Draft")

    assert_nil Page.find_by_full_path("en", "/draft")
    assert_equal "Draft", Page.find_by_full_path("en", "/draft", include_unpublished: true).title
  end

  test "listed_posts includes unpublished posts only when asked" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    block = root.content_blocks.create!(block_type: :post_list, position: 0)
    scheduled = Post.create!(content_type: :blog, title: "Soon", published_at: 1.day.from_now)

    assert_not_includes block.listed_posts, scheduled
    assert_includes block.listed_posts(include_unpublished: true), scheduled
  end
end
```

- [ ] **Step 2:** `bin/rails test test/models/publishable_test.rb` → ERROR (`status` undefined).

- [ ] **Step 3: Implement**

`app/models/concerns/publishable.rb`:

```ruby
# `published_at` doubles as draft/schedule flag (spec §10.4): nil is a draft,
# a future time is scheduled, now or past is live. The `published` scope is
# what the public site serves; a beginless range compiles to
# `published_at <= now()`, which drops both NULLs and future dates.
module Publishable
  extend ActiveSupport::Concern

  STATUSES = %w[draft scheduled live].freeze

  included do
    scope :published, -> { where(published_at: ..Time.current) }
  end

  def status
    if published_at.nil?
      "draft"
    elsif published_at > Time.current
      "scheduled"
    else
      "live"
    end
  end

  def live?
    status == "live"
  end

  def publish_now!
    update!(published_at: Time.current)
  end

  def unpublish!
    update!(published_at: nil)
  end
end
```

In `post.rb` and `page.rb`: `include Publishable` (after `extend Mobility`) and delete each model's own `scope :published, …` line — move Page's explanatory comment about the scope into nothing (the concern's comment covers it).

`page.rb` — change `find_by_full_path` (keep its comment, add one sentence: "Preview (signed-in editors) passes `include_unpublished: true`."):

```ruby
  def self.find_by_full_path(locale, path, include_unpublished: false)
    scope = include_unpublished ? all : published
    scope.where("cached_paths ->> ? = ?", locale.to_s, path).order(:id).first
  end
```

`content_block.rb` — first line of `listed_posts` becomes:

```ruby
  def listed_posts(include_unpublished: false)
    scope = include_unpublished ? Post.all : Post.published
```

- [ ] **Step 4:** `bin/rails test test/models/publishable_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: add publishable status and preview-aware lookups` (+ trailer).

### Task 4: Typed resume fields and alt texts

**Files:**
- Create: `db/migrate/20260927090000_add_alt_texts.rb`, `test/models/resume_fields_test.rb`
- Modify: `app/models/post.rb`, `app/models/content_block.rb`, `app/models/page.rb`, `db/schema.rb`

**Interfaces:**
- Produces: `Post#company`, `#role`, `#start_date`, `#end_date`, `#role_type` (strings in `metadata`); `Post::ROLE_TYPES` = `{ "ic" => "Individual contributor", "lead" => "Lead", "manager" => "Manager", "freelance" => "Freelance" }`; `ContentBlock#alt` and `Page#hero_alt` (translated, per-locale accessors `alt_en`, `hero_alt_de`, …).

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/resume_fields_test.rb
require "test_helper"

class ResumeFieldsTest < ActiveSupport::TestCase
  test "resume fields are stored in metadata" do
    post = Post.create!(content_type: :resume_entry, title: "Engineer",
      company: "Acme", role: "Backend", start_date: "2023-01-01", end_date: "", role_type: "lead")

    assert_equal({ "company" => "Acme", "role" => "Backend", "start_date" => "2023-01-01",
                   "end_date" => "", "role_type" => "lead" }, post.reload.metadata)
    assert_equal "Acme", post.company
  end

  test "role_type must be one of the known types when present" do
    post = Post.new(content_type: :resume_entry, title: "X", role_type: "wizard")

    assert_not post.valid?
    assert post.errors[:role_type].any?
  end

  test "alt texts are translated" do
    root = Page.create!(page_type: :landing, title: "Home", slug: "", published_at: Time.current,
      hero_alt_en: "A desk", hero_alt_de: "Ein Schreibtisch")
    block = root.content_blocks.create!(block_type: :image, position: 0, alt_en: "Chart", alt_de: "Diagramm")

    assert_equal "Ein Schreibtisch", Mobility.with_locale(:de) { root.reload.hero_alt }
    assert_equal "Diagramm", Mobility.with_locale(:de) { block.reload.alt }
  end
end
```

- [ ] **Step 2:** `bin/rails test test/models/resume_fields_test.rb` → ERROR (unknown attribute `company`).

- [ ] **Step 3: Implement**

Migration (same column definition as `content_blocks.caption`):

```ruby
class AddAltTexts < ActiveRecord::Migration[8.1]
  def change
    add_column :content_blocks, :alt, :jsonb, default: {}, null: false
    add_column :pages, :hero_alt, :jsonb, default: {}, null: false
  end
end
```

Run `bin/rails db:migrate` (sandbox fallback in Global Constraints); confirm `db/schema.rb` gained both columns.

`post.rb` (after the enum):

```ruby
  # Resume entries' structured fields (spec §10.3), kept in the existing
  # `metadata` jsonb so no migration is needed and other content types ignore
  # them. Dates stay ISO strings ("2023-01-01"); an empty end date means
  # "current role".
  ROLE_TYPES = {
    "ic" => "Individual contributor", "lead" => "Lead",
    "manager" => "Manager", "freelance" => "Freelance"
  }.freeze

  store_accessor :metadata, :company, :role, :start_date, :end_date, :role_type

  validates :role_type, inclusion: { in: ROLE_TYPES.keys }, allow_blank: true
```

`content_block.rb`: `translates :caption` → `translates :caption, :alt`.
`page.rb`: add `:hero_alt` to the `translates :title, :slug, …` list.

- [ ] **Step 4:** `bin/rails test test/models/resume_fields_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: add typed resume fields and translated alt texts` (+ trailer).

---

# Part B — Public demo theme (§9)

### Task 5: Independent product and theme stylesheets

**Files:**
- Create: `app/assets/tailwind/themes/default/theme.css`, `tokens.css`, `prose.css`; `lib/tasks/theme_css.rake`; `app/views/layouts/product.html.erb`
- Modify: `app/assets/tailwind/application.css`, `Procfile.dev`, `app/views/layouts/application.html.erb` (stylesheet tag only), `app/views/layouts/setup.html.erb` (stylesheet tag only), `app/controllers/sessions_controller.rb`, `app/controllers/passwords_controller.rb`, `test/integration/design_tokens_test.rb`

**Interfaces:**
- Produces: `builds/theme-default.css` (utilities keyed on `--th-*` tokens, same utility names as the product build: `bg-paper`, `text-ink`, `font-cs`, …, plus `.cs-prose`); rake `theme_css:build` / `theme_css:watch`, run automatically after `tailwindcss:build`; layout `product`.

- [ ] **Step 1: Write the failing test** — replace `test/integration/design_tokens_test.rb`'s body with:

```ruby
require "test_helper"

# Backend (product UI) and frontend (public theme) CSS are two separate builds
# (spec §9): each carries its own tokens and only the classes its own views use.
class DesignTokensTest < ActionDispatch::IntegrationTest
  test "the product build carries product tokens and no theme tokens" do
    css = stylesheet("tailwind.css")

    assert_includes css, "--cs-paper"
    assert_not_includes css, "--th-"
    assert_not_includes css, "cs-prose"
  end

  test "the theme build carries theme tokens and no product tokens or product-only classes" do
    css = stylesheet("theme-default.css")

    assert_includes css, "--th-paper"
    assert_includes css, "cs-prose"
    assert_not_includes css, "--cs-"
    # `md:w-56` is only used by the setup wizard's layout.
    assert_not_includes css, "md\\:w-56"
    assert_includes stylesheet("tailwind.css"), "md\\:w-56"
  end

  test "both builds point at the digested, served font files" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    assert_includes stylesheet("tailwind.css"), font_path
    assert_includes stylesheet("theme-default.css"), font_path
    get font_path
    assert_response :success
  end

  test "the public layout links only the theme stylesheet" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    get "/"

    assert_select "link[rel=stylesheet][href*='theme-default']"
    assert_select "link[rel=stylesheet][href*='/tailwind-']", count: 0
  end

  test "sign-in uses the product layout and stylesheet" do
    get new_session_path

    assert_select "link[rel=stylesheet][href*='/tailwind-']"
    assert_select "link[rel=stylesheet][href*='theme-default']", count: 0
    assert_includes response.body, 'localStorage.getItem("cs-theme")'
  end

  private
    def helpers = ActionController::Base.helpers

    def stylesheet(name)
      get helpers.asset_path(name)
      assert_response :success
      response.body
    end
end
```

- [ ] **Step 2:** `bin/rails tailwindcss:build && bin/rails test test/integration/design_tokens_test.rb` → FAIL (no `theme-default.css`).

- [ ] **Step 3: Implement**

`app/assets/tailwind/application.css` (product entry) — replace the whole file:

```css
/* Product UI (setup wizard, sign-in, password reset). `source(none)` +
   explicit @source paths keep this build blind to the public theme's views,
   so the two stylesheets stay independent (spec §9). */
@import "tailwindcss" source(none);
@source "../../views/setup";
@source "../../views/sessions";
@source "../../views/passwords";
@source "../../views/shared";
@source "../../views/layouts/setup.html.erb";
@source "../../views/layouts/product.html.erb";
@source "../../helpers/setup_helper.rb";
@import "./content-spiel.tailwind.css";
```

`app/assets/tailwind/themes/default/tokens.css` — a copy of `app/assets/tailwind/content-spiel.css` with every `--cs-` renamed to `--th-` (all occurrences, including `--cs-font`/`--cs-mono`/sizes/spacing), the header comment replaced by:

```css
/* The public default theme's own tokens (spec §9). Deliberately a copy of
   the product tokens with a `--th-` prefix, not an import: the public site and
   the product UI must be restylable independently. */
```

Keep the `@font-face` rules and the bare font filenames unchanged.

`app/assets/tailwind/themes/default/theme.css`:

```css
/* Public default theme (Claude Design "Demo Site"). Scans only the public
   views; see app/assets/tailwind/application.css for the product side. */
@import "tailwindcss" source(none);
@source "../../../../views/pages";
@source "../../../../views/content_blocks";
@source "../../../../views/layouts/application.html.erb";
@source "../../../../views/layouts/public";
@source "../../../../views/shared";
@source "../../../../helpers/theme_helper.rb";
@import "./tokens.css";

@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));

@theme inline {
  --color-paper: var(--th-paper);
  --color-surface: var(--th-surface);
  --color-sunken: var(--th-sunken);
  --color-ink: var(--th-ink);
  --color-dim: var(--th-dim);
  --color-meta: var(--th-meta);
  --color-line: var(--th-line);
  --color-line-strong: var(--th-line-strong);
  --color-accent: var(--th-accent);
  --color-accent-hover: var(--th-accent-hover);
  --color-accent-tint: var(--th-accent-tint);
  --color-on-accent: var(--th-on-accent);
  --color-ok: var(--th-ok);
  --color-ok-ink: var(--th-ok-ink);
  --color-ok-tint: var(--th-ok-tint);
  --color-warn: var(--th-warn);
  --color-warn-ink: var(--th-warn-ink);
  --color-warn-tint: var(--th-warn-tint);
  --color-danger: var(--th-danger);
  --color-danger-ink: var(--th-danger-ink);
  --color-danger-tint: var(--th-danger-tint);
  --font-cs: var(--th-font);
  --font-cs-mono: var(--th-mono);
  --text-display: var(--th-t-display);
  --text-h1: var(--th-t-h1);
  --text-h2: var(--th-t-h2);
  --text-label: var(--th-t-label);
  --tracking-mono: var(--th-track-mono);
  --tracking-wide: var(--th-track-wide);
  --radius-cs: var(--th-radius);
  --shadow-menu: var(--th-shadow-menu);
  --ease-cs: var(--th-ease);
}

@import "./prose.css";
```

`app/assets/tailwind/themes/default/prose.css`:

```css
/* Element styles for ActionText rich text on the public site (editors write
   in Trix, so there are no classes to hang utilities on). */
.cs-prose { line-height: 1.7; color: var(--th-ink); }
.cs-prose > * + * { margin-top: 1em; }
.cs-prose h1, .cs-prose h2, .cs-prose h3 { font-weight: 600; line-height: 1.25; margin-top: 1.6em; }
.cs-prose h1 { font-size: var(--th-t-h1); }
.cs-prose h2 { font-size: var(--th-t-h2); }
.cs-prose a { color: var(--th-accent); text-decoration: underline; text-underline-offset: 2px; }
.cs-prose a:hover { color: var(--th-accent-hover); }
.cs-prose ul { list-style: disc; padding-left: 1.25em; }
.cs-prose ol { list-style: decimal; padding-left: 1.25em; }
.cs-prose blockquote { border-left: 2px solid var(--th-line-strong); padding-left: 1em; color: var(--th-dim); }
.cs-prose pre { font-family: var(--th-mono); background: var(--th-sunken); padding: 1em; overflow-x: auto; border-radius: var(--th-radius); }
.cs-prose code { font-family: var(--th-mono); font-size: 0.9em; }
.cs-prose img { max-width: 100%; height: auto; border-radius: var(--th-radius); }
.cs-prose figcaption { font-family: var(--th-mono); font-size: var(--th-t-label); color: var(--th-meta); margin-top: 0.5em; }
.cs-prose iframe { width: 100%; aspect-ratio: 16 / 9; border: 0; }
```

`lib/tasks/theme_css.rake`:

```ruby
# tailwindcss-rails 4.6 builds exactly one entry (app/assets/tailwind/
# application.css). The public theme is a second, independent entry (spec §9),
# built with the same Tailwind executable and chained onto
# `tailwindcss:build` -- so assets:precompile, test:prepare, CI and the Docker
# build all produce both stylesheets.
require "tailwindcss/ruby"

module ThemeCss
  module_function

  def command
    [
      Tailwindcss::Ruby.executable,
      "-i", Rails.root.join("app/assets/tailwind/themes/default/theme.css").to_s,
      "-o", Rails.root.join("app/assets/builds/theme-default.css").to_s,
      "--minify"
    ]
  end
end

namespace :theme_css do
  desc "Build the public default theme stylesheet"
  task build: :environment do
    system(*ThemeCss.command, exception: true)
  end

  desc "Watch and rebuild the public default theme stylesheet"
  task watch: :environment do
    system(*ThemeCss.command, "-w", exception: true)
  end
end

Rake::Task["tailwindcss:build"].enhance { Rake::Task["theme_css:build"].invoke }
```

`Procfile.dev` — add a line: `theme: bin/rails theme_css:watch`.

`app/views/layouts/application.html.erb` — replace `<%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>` (and its comment) with:

```erb
    <%# The public theme only (spec §9) -- never the product stylesheet. %>
    <%= stylesheet_link_tag "theme-default", "actiontext", "data-turbo-track": "reload" %>
```

`app/views/layouts/setup.html.erb` — replace its `stylesheet_link_tag :app, …` with `<%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>`.

`app/views/layouts/product.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
  <head>
    <title><%= content_for(:title) || "Sign in" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= render "shared/theme_head" %>
    <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <%# Product UI layout for sign-in and password reset: product stylesheet,
      no public header/footer. color-scheme stays scoped to this body. %>
  <body class="min-h-screen bg-paper font-cs text-ink scheme-light dark:scheme-dark">
    <div class="mx-auto flex max-w-xl flex-col gap-6 px-4 py-16">
      <div class="flex justify-end"><%= render "shared/theme_toggle" %></div>
      <main><%= yield %></main>
    </div>
  </body>
</html>
```

`sessions_controller.rb` and `passwords_controller.rb`: add `layout "product"` under the class line.

- [ ] **Step 4:** `bin/rails tailwindcss:build && ls app/assets/builds/` (expect `tailwind.css` and `theme-default.css`) `&& bin/rails test test/integration/design_tokens_test.rb` → PASS. Then `PARALLEL_WORKERS=1 bin/rails test` and `bin/rails test test/system` → green (if a sign-in or wizard test depended on the old layout, fix it minimally and report).

- [ ] **Step 5: Commit** — `feat: split product and public theme stylesheets` (+ trailer).

### Task 6: Public layout — header, language switcher, footer, document title

**Files:**
- Create: `app/helpers/theme_helper.rb`, `app/views/layouts/public/_header.html.erb`, `_language_switcher.html.erb`, `_footer.html.erb`, `test/integration/public_theme_test.rb`
- Modify: `app/views/layouts/application.html.erb` (body), `app/helpers/pages_helper.rb`, `app/views/pages/_seo_meta.html.erb`, `test/integration/pages_routing_test.rb` (title assertions), `test/system/theme_toggle_test.rb`

**Interfaces:**
- Consumes: `page_url_path`, `post_url_path`, `seo_title` (PagesHelper); `SiteSetting.instance`; `SetupHelper::LANGUAGE_NAMES`.
- Produces: `ThemeHelper#theme_site`, `#safe_social_links`, `#navigation_pages`, `#home_url_path`, `#language_links(page, post)` → array of `ThemeHelper::LanguageLink(code, name, path, current)`; `PagesHelper#document_title(page, post: nil)`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/public_theme_test.rb
require "test_helper"

class PublicThemeTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(title: "Dana's Notes", social_links: {
      "GitHub" => "HTTPS://github.com/dana", "Mail" => "mailto:dana@example.com",
      "Evil" => "javascript:alert(1)", "Broken" => "ht tp://nope"
    })
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @about = Page.create!(parent: @root, page_type: :standard, title_en: "About", title_de: "Über", published_at: Time.current)
    Page.create!(parent: @root, page_type: :standard, title: "Secret draft")
  end

  test "the header shows the site title and published top-level pages" do
    get "/"

    assert_select "header a", text: "Dana's Notes"
    assert_select "header nav a[href='/about']", text: "About"
    assert_select "header nav a", text: "Secret draft", count: 0
  end

  test "the footer shows only safe social links and the theme toggle" do
    get "/"

    assert_select "footer a[href='HTTPS://github.com/dana']", text: "GitHub"
    assert_select "footer a[href='mailto:dana@example.com']", text: "Mail"
    assert_select "footer a", text: "Evil", count: 0
    assert_select "footer a", text: "Broken", count: 0
    assert_select "footer [data-controller=theme]"
  end

  test "the language switcher links the current page in every locale" do
    get "/about"

    assert_select "[aria-label=Language] a[href='/about'][aria-current=true]", text: "en"
    assert_select "[aria-label=Language] a[href='/de/uber']", text: "de"
    assert_select "[aria-label=Language] a[href='/es/about']", text: "es"
  end

  test "the switcher link for a post without a German slug still resolves" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title_en: "Hello", published_at: 1.day.ago)

    get "/blog/hello"
    german = css_select("[aria-label=Language] a[hreflang=de]").first["href"]

    get german
    assert_response :success
    assert_includes response.body, "Hello"
  end

  test "the document title includes the site name" do
    get "/about"
    assert_includes response.body, "<title>About – Dana&#39;s Notes</title>"

    get "/"
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/public_theme_test.rb` → FAIL (no header/footer).

- [ ] **Step 3: Implement**

`app/helpers/theme_helper.rb`:

```ruby
# View helpers for the public default theme (spec §9). Everything the public
# layout shows comes from SiteSetting and the page tree, so editors' settings
# have a visible effect.
module ThemeHelper
  SAFE_LINK_SCHEMES = %w[http https mailto].freeze

  LanguageLink = Data.define(:code, :name, :path, :current)

  # Memoized under a theme-specific ivar: controllers (e.g. SetupController)
  # use @site_setting themselves.
  def theme_site
    @theme_site ||= SiteSetting.instance
  end

  # Social links become real hrefs here for the first time, so only
  # http/https/mailto URLs render -- a `javascript:` link typed into the
  # settings must never reach the page.
  def safe_social_links
    theme_site.social_links.to_h.select { |_name, url| safe_link?(url) }
  end

  def safe_link?(url)
    scheme = URI.parse(url.to_s.strip).scheme
    scheme.present? && SAFE_LINK_SCHEMES.include?(scheme.downcase)
  rescue URI::InvalidURIError
    false
  end

  def theme_root_page
    return @theme_root_page if defined?(@theme_root_page)

    @theme_root_page = Page.find_by(parent_id: nil)
  end

  def navigation_pages
    theme_root_page ? theme_root_page.children.published.to_a : []
  end

  def home_url_path
    theme_root_page ? page_url_path(theme_root_page) : "/"
  end

  # The current page -- or, at a permalink, the current post -- in each
  # locale. A post's slug is read inside that locale, falling back to the
  # default-locale slug exactly as the router does.
  def language_links(page, post = nil)
    return [] if page.nil?

    I18n.available_locales.map(&:to_s).map do |code|
      path = I18n.with_locale(code) { post ? post_url_path(page, post, code) : page_url_path(page, code) }
      LanguageLink.new(code:, name: SetupHelper::LANGUAGE_NAMES.fetch(code, code.upcase), path:,
        current: code == I18n.locale.to_s)
    end
  end
end
```

`pages_helper.rb` — add (public):

```ruby
  # "<page or post> – <site>" in the browser tab; the homepage is the site
  # name alone, and an explicit meta title is taken as written.
  def document_title(page, post: nil)
    site_title = SiteSetting.instance.title
    return page.meta_title if post.nil? && page.meta_title.present?
    return site_title if post.nil? && page.root?

    "#{seo_title(page, post: post)} – #{site_title}"
  end
```

`_seo_meta.html.erb` — change `<% content_for :title, title %>` to `<% content_for :title, document_title(page, post: post) %>` (og:title keeps `title`).

`app/views/layouts/application.html.erb` — replace the whole `<body>…</body>`:

```erb
  <body class="min-h-screen bg-paper font-cs text-ink scheme-light dark:scheme-dark">
    <div class="mx-auto max-w-3xl px-4">
      <%= render "layouts/public/header" %>
      <%= yield :preview_banner %>
      <main class="py-12"><%= yield %></main>
      <%= render "layouts/public/footer" %>
    </div>
  </body>
```

`layouts/public/_header.html.erb`:

```erb
<header class="flex flex-wrap items-center justify-between gap-4 border-b border-line py-5">
  <%= link_to home_url_path, class: "flex items-center gap-3 font-semibold text-ink" do %>
    <% if theme_site.logo.attached? %>
      <%= image_tag theme_site.logo, alt: "", class: "h-8 w-auto" %>
    <% end %>
    <span><%= theme_site.title %></span>
  <% end %>

  <nav aria-label="Main" class="flex flex-wrap items-center gap-5 text-sm">
    <% navigation_pages.each do |nav_page| %>
      <%= link_to nav_page.title, page_url_path(nav_page), class: "text-dim hover:text-ink",
            aria: { current: ("page" if nav_page == @page) } %>
    <% end %>
    <%= render "layouts/public/language_switcher" %>
  </nav>
</header>
```

`layouts/public/_language_switcher.html.erb`:

```erb
<%# Up to three languages as inline codes; more collapse into a <details>
    menu, which needs no JavaScript. %>
<% links = language_links(@page, @post) %>
<% if links.size > 1 %>
  <% if links.size <= 3 %>
    <ul aria-label="Language" class="flex items-center gap-1 font-cs-mono text-label uppercase tracking-mono">
      <% links.each do |link| %>
        <li>
          <%= link_to link.code, link.path, hreflang: link.code, lang: link.code,
                aria: { current: ("true" if link.current) },
                class: link.current ? "rounded-cs bg-ink px-1.5 py-0.5 text-paper" : "rounded-cs px-1.5 py-0.5 text-dim hover:text-ink" %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <details class="relative font-cs-mono text-label uppercase tracking-mono">
      <summary class="cursor-pointer text-dim hover:text-ink"><%= I18n.locale %></summary>
      <ul aria-label="Language" class="absolute right-0 z-10 mt-2 rounded-cs border border-line bg-surface p-2 shadow-menu">
        <% links.each do |link| %>
          <li><%= link_to link.name, link.path, hreflang: link.code, lang: link.code,
                    aria: { current: ("true" if link.current) }, class: "block px-2 py-1 hover:text-ink" %></li>
        <% end %>
      </ul>
    </details>
  <% end %>
<% end %>
```

`layouts/public/_footer.html.erb`:

```erb
<footer class="mt-16 flex flex-wrap items-center justify-between gap-4 border-t border-line py-6 font-cs-mono text-label uppercase tracking-mono text-meta">
  <p>© <%= Time.current.year %> <%= theme_site.title %></p>
  <% links = safe_social_links %>
  <% if links.any? %>
    <ul class="flex flex-wrap gap-4">
      <% links.each do |name, url| %>
        <li><%= link_to name, url, rel: "me noopener", class: "hover:text-ink" %></li>
      <% end %>
    </ul>
  <% end %>
  <%= render "shared/theme_toggle" %>
</footer>
```

`test/integration/pages_routing_test.rb` — update the document-title assertions to the new format: the fixture site title is `Test Site`, so `<title>Home</title>` → `<title>Test Site</title>`, `<title>About</title>` → `<title>About – Test Site</title>`, `<title>My First Post</title>` → `<title>My First Post – Test Site</title>`, `<title>Ueber mich</title>` → `<title>Ueber mich – Test Site</title>`; leave the explicit-meta-title case (`ContentSpiel — Home`) as is. Adjust any other title assertion the suite reports the same way.

`test/system/theme_toggle_test.rb` — add a second test (same pattern as the existing one, which stays):

```ruby
  test "the public site's toggle flips the theme and survives a reload" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    visit "/"
    initial = current_theme
    other = initial == "dark" ? "light" : "dark"

    within("footer") { click_on(initial == "dark" ? "Light mode" : "Dark mode") }
    assert_equal other, current_theme

    visit "/"
    assert_equal other, current_theme
  end
```

- [ ] **Step 4:** `bin/rails tailwindcss:build && bin/rails test test/integration/public_theme_test.rb test/integration/pages_routing_test.rb && bin/rails test test/system/theme_toggle_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: add the public theme header, footer and language switcher` (+ trailer).

### Task 7: Page hero, content blocks and post detail in the demo look

**Files:**
- Create: `app/views/content_blocks/post_list/_blog.html.erb`, `_resume.html.erb`, `_now.html.erb`, `test/integration/public_blocks_test.rb`
- Modify: `app/views/pages/show.html.erb`, `app/views/content_blocks/_rich_text.html.erb`, `_image.html.erb`, `_post_list.html.erb`, `_post_list_detail.html.erb`, `app/helpers/theme_helper.rb`

**Interfaces:**
- Consumes: `Post::ROLE_TYPES`, `Post#company/role/start_date/end_date/role_type`, `ContentBlock#alt`, `Page#hero_alt`, `theme_site`.
- Produces: `ThemeHelper#post_date(post)` (e.g. "12 Sep 2026" or nil), `#resume_period(post)` (e.g. "2023 – now").

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/public_blocks_test.rb
require "test_helper"

class PublicBlocksTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(tagline: "Writing about Rails")
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "the homepage shows the tagline eyebrow and rich text in prose" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: "<p>Hello there</p>")
    get "/"

    assert_includes response.body, "Writing about Rails"
    assert_select ".cs-prose", text: /Hello there/
  end

  test "an image block renders its alt text and caption" do
    block = @root.content_blocks.create!(block_type: :image, position: 0, caption: "Our studio", alt: "A bright room")
    block.image.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "icon.png")
    get "/"

    assert_select "img[alt='A bright room']"
    assert_select "figcaption", text: /Our studio/
  end

  test "blog rows show date, excerpt and first tag" do
    post = Post.create!(content_type: :blog, title: "Notes on Hotwire", excerpt: "What stayed simple",
      published_at: Time.zone.local(2026, 9, 12))
    post.tags << Tag.create!(name: "rails")
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    get "/"

    assert_includes response.body, "12 Sep 2026"
    assert_includes response.body, "What stayed simple"
    assert_select "li", text: /rails/
  end

  test "resume rows show company, role type and period" do
    Post.create!(content_type: :resume_entry, title: "Staff Engineer", company: "Acme", role_type: "lead",
      start_date: "2023-01-01", end_date: "", published_at: 1.day.ago)
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    get "/"

    assert_includes response.body, "Acme"
    assert_includes response.body, "Lead"
    assert_includes response.body, "2023 – now"
  end

  test "a now list shows the latest update's text" do
    Post.create!(content_type: :now_update, title: "Now", body: "<p>Training for a half marathon</p>", published_at: 1.day.ago)
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "now_update" })
    get "/"

    assert_includes response.body, "Training for a half marathon"
  end

  test "a post detail shows date, excerpt and tags" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    post = Post.create!(content_type: :blog, title: "Hello", excerpt: "Short summary",
      published_at: Time.zone.local(2026, 9, 12), body: "<p>Body text</p>")
    post.tags << Tag.create!(name: "hotwire")
    get "/blog/hello"

    assert_includes response.body, "12 Sep 2026"
    assert_includes response.body, "Short summary"
    assert_includes response.body, "hotwire"
    assert_select "article .cs-prose", text: /Body text/
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/public_blocks_test.rb` → FAIL.

- [ ] **Step 3: Implement**

`theme_helper.rb` — add:

```ruby
  def post_date(post)
    post.published_at&.strftime("%-d %b %Y")
  end

  # Resume periods show years only; an empty end date is the current role.
  def resume_period(post)
    start_year = post.start_date.to_s[0, 4].presence
    end_year = post.end_date.to_s[0, 4].presence || "now"
    start_year ? "#{start_year} – #{end_year}" : end_year
  end
```

`pages/show.html.erb` — replace the `<% if @post.nil? %> … <% end %>` hero block with (keep the comments above/below; keep the `subtitle` class and the `page-children` nav hooks):

```erb
<% if @post.nil? %>
  <header class="mb-12">
    <% if @page.root? && theme_site.tagline.present? %>
      <p class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= theme_site.tagline %></p>
    <% end %>
    <h1 class="mt-3 font-semibold leading-tight tracking-tight <%= @page.root? ? "text-display" : "text-h1" %>"><%= @page.title %></h1>
    <% if @page.landing? %>
      <% if @page.subtitle.present? %>
        <p class="subtitle mt-4 max-w-2xl text-lg text-dim"><%= @page.subtitle %></p>
      <% end %>
      <%= image_tag @page.hero_image, alt: @page.hero_alt.to_s, class: "mt-8 w-full rounded-cs" if @page.hero_image.attached? %>
    <% end %>
  </header>
<% end %>
```

and restyle the children nav (same markup, classes only):

```erb
  <nav class="page-children mt-12 border-t border-line pt-6">
    <ul class="space-y-2">
      <% @page.children.published.each do |child| %>
        <li><%= link_to child.title, page_url_path(child), class: "text-accent underline underline-offset-2 hover:text-accent-hover" %></li>
      <% end %>
    </ul>
  </nav>
```

`_rich_text.html.erb`:

```erb
<div class="content-block content-block--rich-text cs-prose my-8">
  <%= block.body %>
</div>
```

`_image.html.erb`:

```erb
<% if block.image.attached? %>
  <figure class="content-block content-block--image my-10">
    <%= image_tag block.image, alt: block.alt.to_s, class: "w-full rounded-cs" %>
    <% if block.caption.present? %>
      <figcaption class="mt-2 font-cs-mono text-label uppercase tracking-mono text-meta"><%= block.caption %></figcaption>
    <% end %>
  </figure>
<% end %>
```

`_post_list.html.erb` — keep the leading comment and the `posts` query lines, then:

```erb
<section class="content-block content-block--post-list my-12 border-t border-line pt-6">
  <% case block.settings["content_type"] %>
  <% when "now_update" %>
    <%= render "content_blocks/post_list/now", posts: posts, page: page %>
  <% when "resume_entry" %>
    <%= render "content_blocks/post_list/resume", posts: posts, page: page %>
  <% else %>
    <%= render "content_blocks/post_list/blog", posts: posts, page: page %>
  <% end %>
</section>
```

`post_list/_blog.html.erb`:

```erb
<ul>
  <% posts.each do |post| %>
    <li class="grid grid-cols-[7rem_1fr_auto] gap-4 border-b border-line py-4">
      <span class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= post_date(post) %></span>
      <div>
        <%= link_to post.title, post_url_path(page, post), class: "font-semibold text-ink hover:text-accent" %>
        <% if post.excerpt.present? %><p class="mt-1 text-sm text-dim"><%= post.excerpt %></p><% end %>
      </div>
      <span class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= post.tags.first&.name %></span>
    </li>
  <% end %>
</ul>
```

`post_list/_resume.html.erb`:

```erb
<ul>
  <% posts.each do |post| %>
    <li class="grid grid-cols-[7rem_1fr_auto] gap-4 border-b border-line py-4">
      <span class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= resume_period(post) %></span>
      <div>
        <%= link_to post.title, post_url_path(page, post), class: "font-semibold text-ink hover:text-accent" %>
        <% if post.company.present? %><p class="mt-1 text-sm text-dim"><%= post.company %></p><% end %>
      </div>
      <span class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= Post::ROLE_TYPES[post.role_type] %></span>
    </li>
  <% end %>
</ul>
```

`post_list/_now.html.erb`:

```erb
<% latest = posts.first %>
<% if latest %>
  <div class="grid gap-6 md:grid-cols-[10rem_1fr]">
    <div class="font-cs-mono text-label uppercase tracking-mono text-meta">
      <p>Now</p>
      <p>Updated <%= post_date(latest) %></p>
    </div>
    <div class="cs-prose text-lg"><%= latest.body %></div>
  </div>
<% end %>
```

`_post_list_detail.html.erb` — keep the comment, replace the article:

```erb
<article class="content-block content-block--post-list-detail">
  <p class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= post_date(post) %></p>
  <h1 class="mt-3 text-h1 font-semibold leading-tight tracking-tight"><%= post.title %></h1>
  <% if post.excerpt.present? %><p class="mt-4 text-lg text-dim"><%= post.excerpt %></p><% end %>
  <div class="cs-prose mt-8"><%= post.body %></div>
  <% if post.tags.any? %>
    <ul class="mt-10 flex flex-wrap gap-3 font-cs-mono text-label uppercase tracking-mono text-meta">
      <% post.tags.each do |tag| %><li><%= tag.name %></li><% end %>
    </ul>
  <% end %>
</article>
```

- [ ] **Step 4:** `bin/rails tailwindcss:build && bin/rails test test/integration/public_blocks_test.rb` → PASS; full suite + `bin/rails test test/system` green.

- [ ] **Step 5: Commit** — `feat: render pages, blocks and posts in the demo theme` (+ trailer).

### Task 8: Signed-in preview and "Edit this page"

**Files:**
- Create: `app/views/layouts/public/_preview_banner.html.erb`, `test/integration/preview_test.rb`
- Modify: `app/controllers/pages_controller.rb`, `app/views/pages/show.html.erb` (top), `app/views/layouts/public/_footer.html.erb`

**Interfaces:**
- Consumes: `Page.find_by_full_path(..., include_unpublished:)`, `ContentBlock#listed_posts(include_unpublished:)`, `#status`, `authenticated?` (Authentication concern, available in controllers and as a helper).
- Produces: `@preview_status` (`"draft"`/`"scheduled"` or nil) in PagesController views.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/preview_test.rb
require "test_helper"

class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @draft = Page.create!(parent: @root, page_type: :standard, title: "Draft page")
    @blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    @blog.content_blocks.create!(block_type: :post_list, position: 0)
    @scheduled = Post.create!(content_type: :blog, title: "Coming soon", published_at: 2.days.from_now)
  end

  test "anonymous visitors get 404 for drafts and scheduled posts, in any locale" do
    get "/draft-page"
    assert_response :not_found
    get "/de/draft-page"
    assert_response :not_found
    get "/blog/coming-soon"
    assert_response :not_found
  end

  test "signed-in editors preview a draft page with a banner and no caching" do
    sign_in_as(users(:one))
    get "/draft-page"

    assert_response :success
    assert_includes response.body, "Preview · Draft"
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "signed-in editors preview a scheduled post" do
    sign_in_as(users(:one))
    get "/blog/coming-soon"

    assert_response :success
    assert_includes response.body, "Preview · Scheduled"
  end

  test "live pages show an edit link only to signed-in editors, and no banner" do
    get "/blog"
    assert_select "a", text: "Edit this page", count: 0

    sign_in_as(users(:one))
    get "/blog"
    assert_select "a[href='/avo/resources/pages/#{@blog.id}/edit']", text: "Edit this page"
    assert_not_includes response.body, "Preview ·"
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/preview_test.rb` → FAIL.

- [ ] **Step 3: Implement**

`pages_controller.rb` — in `show` and `resolve_post_detail`, pass `include_unpublished: preview_allowed?` to `Page.find_by_full_path` (both calls) and to `@post_list_block.listed_posts(include_unpublished: preview_allowed?)`; after `@page`/`@post` is resolved and before each `render :show`, call `mark_preview`. Add private methods:

```ruby
  # Signed-in editors see unpublished pages and posts at their real URL
  # (spec §10.4); everyone else keeps getting 404 from the published scopes.
  def preview_allowed?
    return @preview_allowed if defined?(@preview_allowed)

    @preview_allowed = authenticated?.present?
  end

  # A preview must never be cached: it shows content visitors can't see.
  def mark_preview
    @preview_status = [ (@post || @page).status, @page.status ].find { |status| status != "live" }
    response.set_header("Cache-Control", "no-store") if @preview_status
  end
```

`layouts/public/_preview_banner.html.erb`:

```erb
<div role="status" class="mt-4 rounded-cs border border-warn bg-warn-tint px-3 py-2 font-cs-mono text-label uppercase tracking-mono text-warn-ink">
  Preview · <%= @preview_status.humanize %> — not visible to visitors
</div>
```

`pages/show.html.erb` — add at the very top:

```erb
<% content_for :preview_banner, render("layouts/public/preview_banner") if @preview_status %>
```

`_footer.html.erb` — add before the theme toggle:

```erb
  <% if authenticated? && @page %>
    <% record = @post || @page %>
    <%= link_to (@post ? "Edit this post" : "Edit this page"),
          (@post ? avo.edit_resources_post_path(record) : avo.edit_resources_page_path(record)),
          class: "hover:text-ink" %>
  <% end %>
```

- [ ] **Step 4:** `bin/rails tailwindcss:build && bin/rails test test/integration/preview_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: let signed-in editors preview unpublished pages and posts` (+ trailer).

---

# Part C — Admin (Avo)

### Task 9: Type-dependent fields, page form cleanup, fixed landing create

**Files:**
- Create: `app/javascript/controllers/type_fields_controller.js`, `test/system/type_fields_test.rb`
- Modify: `app/javascript/avo.custom.js`, `app/avo/resources/page.rb`, `test/integration/avo_page_editing_test.rb`

**Interfaces:**
- Produces: Stimulus `type-fields` (registered for Avo). A resource opts in with `self.stimulus_controllers = "type-fields"`; a field opts in with `html: TypeFields.html(source: :page_type, show_for: %w[landing])`. `TypeFields` module in `app/avo/type_fields.rb` (Zeitwerk: `app/avo/` is autoloaded as the root namespace — if `TypeFields` does not resolve, put it at `app/avo/concerns/type_fields.rb` as `Avo::TypeFields` and reference it that way; report which).

- [ ] **Step 1: Write the failing tests**

In `test/integration/avo_page_editing_test.rb`, replace the test "a standard page's form offers neither subtitle nor hero image" with:

```ruby
  # Always rendered, shown/hidden in the browser by the type-fields controller
  # (spec §10.3) -- a server-side `visible:` lambda evaluated the unsaved
  # record and dropped what the editor typed on the create form.
  test "a standard page's form renders the landing-only fields, marked landing-only" do
    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_includes response.body, %(name="page[hero_image]")
    assert_select "[data-show-for=landing][data-type-source=page_type]", minimum: 2
    assert_select "[data-controller~=type-fields]"
  end

  test "creating a landing page keeps its subtitle and generates its slug" do
    post "/avo/resources/pages", params: { page: {
      parent_id: @root.id, page_type: "landing", title_en: "Campaign",
      subtitle_en: "Big news", hero_alt_en: "Confetti"
    } }

    page = Page.order(:id).last
    assert_equal "Big news", page.subtitle_en
    assert_equal "Confetti", page.hero_alt_en
    assert_equal "campaign", page.slug_en
  end

  test "the page form has no visible position number" do
    get "/avo/resources/pages/#{@about.id}/edit"

    assert_no_match(/<input[^>]*type="number"[^>]*name="page\[position\]"/, response.body)
  end
```

`test/system/type_fields_test.rb`:

```ruby
require "application_system_test_case"

class TypeFieldsTest < ApplicationSystemTestCase
  setup do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign in"
  end

  test "landing-only fields appear when Landing is chosen" do
    visit "/avo/resources/pages/new"
    assert_no_field "Subtitle"

    select "Landing (with hero)", from: "Page type"
    assert_field "Subtitle"
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/avo_page_editing_test.rb && bin/rails test test/system/type_fields_test.rb` → FAIL.

- [ ] **Step 3: Implement**

`app/javascript/controllers/type_fields_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Shows/hides Avo form fields that only apply to some record types (spec
// §10.3). A dependent field's wrapper carries data-show-for="landing" and
// data-type-source="page_type"; the source is the <select> inside the
// wrapper Avo tags with data-field-id="page_type". Hidden fields still
// submit, so nothing typed is lost when the type is switched back.
export default class extends Controller {
  connect() {
    this.refresh = this.refresh.bind(this)
    this.element.addEventListener("change", this.refresh)
    this.refresh()
  }

  disconnect() {
    this.element.removeEventListener("change", this.refresh)
  }

  refresh() {
    this.element.querySelectorAll("[data-show-for]").forEach((wrapper) => {
      const select = this.element.querySelector(`[data-field-id="${wrapper.dataset.typeSource}"] select`)
      if (!select) return
      const visible = wrapper.dataset.showFor.split(" ").includes(select.value)
      wrapper.style.display = visible ? "" : "none"
    })
  }
}
```

`avo.custom.js` — add `import TypeFieldsController from "controllers/type_fields_controller"` and `window.Stimulus.register("type-fields", TypeFieldsController)`.

`app/avo/type_fields.rb`:

```ruby
# Avo `html:` option for a field that only applies to some values of a type
# select (spec §10.3); read by app/javascript/controllers/type_fields_controller.js.
module TypeFields
  module_function

  def html(source:, show_for:)
    data = { show_for: Array(show_for).join(" "), type_source: source.to_s }
    { new: { wrapper: { data: data } }, edit: { wrapper: { data: data } } }
  end
end
```

`app/avo/resources/page.rb`:
- add `self.stimulus_controllers = "type-fields"` under `self.title`.
- add `:hero_alt` per locale to nothing in `extra_params` (top-level fields are permitted by Avo automatically; only nested block attrs live there).
- replace `field :position, as: :number` with `field :position, as: :hidden, only_on: :forms` (comment: "ordering is done in the Pages tree; kept as a hidden input so existing values round-trip").
- replace the page_type field with `field :page_type, as: :select, options: { "Standard" => "standard", "Landing (with hero)" => "landing" }`.
- subtitle field: replace `visible: -> { resource.record&.landing? }` with `visible: -> { view.form? || resource.record&.landing? }, html: TypeFields.html(source: :page_type, show_for: :landing)`.
- inside the tab, after subtitle, add: `field locale_accessor(:hero_alt, locale), as: :text, name: "Hero image alt text", visible: -> { view.form? || resource.record&.landing? }, html: TypeFields.html(source: :page_type, show_for: :landing)`.
- hero_image: same `visible:`/`html:` replacement.
- `field :published_at, as: :date_time, name: "Publish date", help: "Empty = draft. A future date schedules the page."`

- [ ] **Step 4:** `bin/rails test test/integration/avo_page_editing_test.rb && bin/rails test test/system/type_fields_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `fix: keep landing fields on page create and tidy the page form` (+ trailer).

### Task 10: Post form — typed resume fields and readable labels

**Files:**
- Create: `test/integration/avo_post_form_test.rb`
- Modify: `app/avo/resources/post.rb`

**Interfaces:**
- Consumes: `TypeFields.html`, `Post::ROLE_TYPES`, resume `store_accessor`s.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/avo_post_form_test.rb
require "test_helper"

class AvoPostFormTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "the post form offers readable content types and no metadata JSON" do
    get "/avo/resources/posts/new"

    assert_response :success
    assert_select "option", text: "Resume entry"
    assert_not_includes response.body, %(name="post[metadata]")
    assert_select "[data-show-for=resume_entry][data-type-source=content_type]", minimum: 5
  end

  test "resume fields round-trip through the form" do
    post "/avo/resources/posts", params: { post: {
      content_type: "resume_entry", title_en: "Staff Engineer", company: "Acme", role: "Platform",
      start_date: "2023-01-01", end_date: "", role_type: "lead"
    } }

    saved = Post.order(:id).last
    assert_equal "Acme", saved.company
    assert_equal "lead", saved.role_type
    assert_equal "2023-01-01", saved.start_date.to_s
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/avo_post_form_test.rb` → FAIL.

- [ ] **Step 3: Implement** — in `app/avo/resources/post.rb`:
- `self.stimulus_controllers = "type-fields"` under `self.icon`.
- `field :content_type, as: :select, options: { "Blog post" => "blog", "Resume entry" => "resume_entry", "Now update" => "now_update" }` (replaces `enum:`).
- after the tabs, add the resume fields:

```ruby
    resume_only = { visible: -> { view.form? || resource.record&.resume_entry? },
                    html: TypeFields.html(source: :content_type, show_for: :resume_entry) }
    field :company, as: :text, **resume_only
    field :role, as: :text, **resume_only
    field :start_date, as: :date, **resume_only
    field :end_date, as: :date, help: "Leave empty for a current role.", **resume_only
    field :role_type, as: :select, include_blank: true,
      options: ::Post::ROLE_TYPES.invert, **resume_only
```

- delete `field :metadata, as: :code`.
- `field :published_at, as: :date_time, name: "Publish date", help: "Empty = draft. A future date schedules the post."`

(`ROLE_TYPES.invert` gives Avo's `{ "Label" => value }` format.) If Avo's `:date` field submits a format other than `YYYY-MM-DD`, normalise in the model with a `before_validation` that stores `Date.parse(value).iso8601` for non-blank dates and say so in your report.

- [ ] **Step 4:** `bin/rails test test/integration/avo_post_form_test.rb test/integration/avo_access_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: typed resume fields on the post form` (+ trailer).

### Task 11: Status badges, Publish now / Unpublish, View on site, tree status

**Files:**
- Create: `app/models/public_path.rb`, `app/avo/actions/publish_now.rb`, `app/avo/actions/unpublish.rb`, `test/models/public_path_test.rb`, `test/models/publish_actions_test.rb`, `test/integration/avo_status_test.rb`
- Modify: `app/avo/resources/post.rb`, `app/avo/resources/page.rb`, `app/views/avo/tools/_page_node.html.erb`

**Interfaces:**
- Consumes: `#status`, `#publish_now!`, `#unpublish!`, `ContentBlock#listed_posts(include_unpublished:)`.
- Produces: `PublicPath.for(record, locale: SiteSetting.instance.default_locale)` → String or nil.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/public_path_test.rb
require "test_helper"

class PublicPathTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    @blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
  end

  test "pages and listed posts have public paths, prefixed outside the default locale" do
    post = Post.create!(content_type: :blog, title: "Hello")

    assert_equal "/blog", PublicPath.for(@blog)
    assert_equal "/blog/hello", PublicPath.for(post)
    assert_equal "/de/blog/hello", PublicPath.for(post, locale: "de")
  end

  test "a post no list shows has no public path" do
    assert_nil PublicPath.for(Post.create!(content_type: :now_update, title: "Now"))
  end
end
```

```ruby
# test/models/publish_actions_test.rb
require "test_helper"

class PublishActionsTest < ActiveSupport::TestCase
  test "publish now and unpublish act on every selected record" do
    user = users(:one)
    posts = [ Post.create!(content_type: :blog, title: "A"), Post.create!(content_type: :blog, title: "B") ]

    Avo::Actions::PublishNow.new(user: user).handle(records: posts, current_user: user)
    assert posts.all? { |post| post.reload.live? }

    Avo::Actions::Unpublish.new(user: user).handle(records: posts, current_user: user)
    assert posts.all? { |post| post.reload.status == "draft" }
  end
end
```

```ruby
# test/integration/avo_status_test.rb
require "test_helper"

class AvoStatusTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @scheduled = Page.create!(parent: @root, page_type: :standard, title: "Later", published_at: 1.day.from_now)
  end

  test "indexes show the status and actions are offered" do
    get "/avo/resources/pages"
    assert_includes response.body, "scheduled"
    assert_includes response.body, "Publish now"

    Post.create!(content_type: :blog, title: "Draft post")
    get "/avo/resources/posts"
    assert_includes response.body, "draft"
  end

  test "a page's show view links to the public site" do
    get "/avo/resources/pages/#{@scheduled.id}"
    assert_select "a[href='/later']", text: /View on site/
  end

  test "the pages tree labels a scheduled page as scheduled" do
    get "/avo/pages_tree"
    assert_includes response.body, "scheduled"
  end
end
```

- [ ] **Step 2:** `bin/rails test test/models/public_path_test.rb test/models/publish_actions_test.rb test/integration/avo_status_test.rb` → FAIL/ERROR.

- [ ] **Step 3: Implement**

`app/models/public_path.rb`:

```ruby
# The public URL of a Page or Post in a locale (used by the admin's "View on
# site"). Mirrors PagesHelper#page_url_path/#post_url_path, which need a view
# context; the default locale is served unprefixed. A post has no URL of its
# own: it lives under the first page whose post list includes it (drafts and
# scheduled posts included, so the link works as a preview).
module PublicPath
  module_function

  def for(record, locale: SiteSetting.instance.default_locale)
    locale = locale.to_s
    prefix = locale == SiteSetting.instance.default_locale ? "" : "/#{locale}"

    case record
    when Page
      "#{prefix}#{record.full_path(locale)}"
    when Post
      block = ContentBlock.post_list.includes(:page).find do |candidate|
        candidate.listed_posts(include_unpublished: true).exists?(record.id)
      end
      return nil unless block

      base = block.page.full_path(locale)
      base = "" if base == "/"
      "#{prefix}#{base}/#{Mobility.with_locale(locale) { record.slug }}"
    end
  end
end
```

`app/avo/actions/publish_now.rb`:

```ruby
class Avo::Actions::PublishNow < Avo::BaseAction
  self.name = "Publish now"
  self.message = "Makes the selected items visible on the site immediately."

  def handle(records:, **)
    records.each(&:publish_now!)
    succeed("Published.")
  end
end
```

`app/avo/actions/unpublish.rb` — same shape: `self.name = "Unpublish"`, message "Turns the selected items back into drafts; visitors can no longer see them.", `records.each(&:unpublish!)`, `succeed("Unpublished.")`.

Both resources (`post.rb`, `page.rb`):

```ruby
    field :status, as: :badge, options: { success: "live", warning: "scheduled", neutral: "draft" }
    field :view_on_site, as: :text, only_on: :show, as_html: true, name: "On the site" do
      path = ::PublicPath.for(record)
      path ? %(<a href="#{ERB::Util.html_escape(path)}" target="_blank" rel="noopener">View on site ↗</a>) : "Not listed on any page yet"
    end
```

and in `actions` add `action Avo::Actions::PublishNow` and `action Avo::Actions::Unpublish` (Post gets a `def actions` method; Page keeps `CreateStarterPages`).

`_page_node.html.erb` — change the status span to `<%= page.page_type %> · <%= page.status %>`.

- [ ] **Step 4:** run the three test files → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: show publish status and add publish actions in the admin` (+ trailer).

### Task 12: Block editor markup (server side)

**Files:**
- Modify: `app/views/avo/resource_tools/_nested_content_blocks.html.erb`, `app/views/avo/partials/_content_block_row.html.erb`, `app/avo/resource_tools/nested_content_blocks.rb`, `app/avo/resources/page.rb` (`extra_params`), `test/integration/avo_page_editing_test.rb`

**Interfaces:**
- Produces: DOM contract for Task 13's controller —
  - container `[data-controller=block-editor]` with targets `list` and one `template` per block type (`data-block-type="rich_text|image|post_list"`, containing index placeholder `NEW_BLOCK`)
  - each row `[data-block-row]` with `data-persisted="true|false"`, hidden inputs `[data-block-role=position]`, `[data-block-role=destroy]`
  - buttons with `data-action` `block-editor#add` (+`data-block-type`), `#moveUp`, `#moveDown`, `#remove`, `#undo`, `#selectLocale` (+`data-locale`)
  - panes `[data-locale-pane=en|de|es]`
- `NestedContentBlocks#block_type_label(type)`, `#locale_accessors(attribute)` (existing).

- [ ] **Step 1: Write the failing tests** — in `avo_page_editing_test.rb` replace "the page form renders a nested row per content block plus a blank one to add with" and "the nested block row exposes the type-specific and translated fields" with:

```ruby
  test "the block editor renders existing rows and one template per block type" do
    @about.content_blocks.create!(block_type: :rich_text, position: 0)

    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_select "[data-controller=block-editor] [data-block-row]", 1
    %w[rich_text image post_list].each do |type|
      assert_select "template[data-block-type=#{type}]"
    end
    assert_includes response.body, %(name="page[content_blocks_attributes][NEW_BLOCK][block_type]")
  end

  test "rows only render their own type's fields" do
    @about.content_blocks.create!(block_type: :image, position: 0)
    @about.content_blocks.create!(block_type: :post_list, position: 1)

    get "/avo/resources/pages/#{@about.id}/edit"

    assert_includes response.body, %(name="page[content_blocks_attributes][0][image]")
    assert_includes response.body, %(name="page[content_blocks_attributes][0][alt_en]")
    assert_not_includes response.body, %(name="page[content_blocks_attributes][0][settings][content_type]")
    assert_select "select[name='page[content_blocks_attributes][1][settings][content_type]'] option", text: "Blog posts"
    assert_select "select[name='page[content_blocks_attributes][1][settings][tag]']"
    assert_select "input[type=number][name='page[content_blocks_attributes][1][settings][limit]']"
    assert_select "input[type=hidden][name='page[content_blocks_attributes][0][position]']"
  end

  test "a failed save keeps text typed into a new block" do
    put "/avo/resources/pages/#{@about.id}", params: { page: {
      title_en: "",
      content_blocks_attributes: { "1727000000000" => { block_type: "rich_text", position: "0", body_en: "<p>Keep me</p>" } }
    } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Keep me"
  end
```

- [ ] **Step 2:** `bin/rails test test/integration/avo_page_editing_test.rb` → FAIL.

- [ ] **Step 3: Implement**

`nested_content_blocks.rb` — replace `setting_keys` with:

```ruby
  BLOCK_TYPE_LABELS = { "rich_text" => "Text", "image" => "Image", "post_list" => "Post list" }.freeze

  def block_type_label(type)
    BLOCK_TYPE_LABELS.fetch(type.to_s, type.to_s.humanize)
  end
```

`page.rb` `extra_params` — add the alt accessors to the per-locale list: `[ caption_accessor, body_accessor, alt_accessor ]` (same `normalize_locale_accessor(:alt, locale)` pattern).

`_nested_content_blocks.html.erb` (keep the guard and the leading comments; replace the panel body):

```erb
  <%= render ui.panel(
    title: "Content blocks",
    description: "Add, reorder and edit the blocks this page shows. Changes are saved with the page."
  ) do |panel| %>
    <% panel.with_body do %>
      <%# Inline block editor (spec §10.2), driven by block_editor_controller.js.
          New rows are cloned from the <template>s below with a timestamp in
          place of NEW_BLOCK, so they never collide with existing indexes and
          survive a failed save (Rails re-renders them from the in-memory
          association). %>
      <div data-controller="block-editor" class="space-y-4">
        <div class="flex flex-wrap items-center gap-2" role="group" aria-label="Editing language">
          <% ::Mobility.available_locales.each do |locale| %>
            <button type="button" data-action="block-editor#selectLocale" data-locale="<%= locale %>"
              class="rounded border px-2 py-1 text-sm uppercase"><%= locale %></button>
          <% end %>
        </div>

        <div data-block-editor-target="list" class="space-y-4">
          <% blocks.each_with_index do |block, index| %>
            <%= form.fields_for :content_blocks, block, multiple: true, child_index: index do |block_form| %>
              <%= render "avo/partials/content_block_row", f: block_form, tool: tool %>
            <% end %>
          <% end %>
        </div>

        <% ContentBlock.block_types.each_key do |type| %>
          <template data-block-editor-target="template" data-block-type="<%= type %>">
            <%= form.fields_for :content_blocks, ContentBlock.new(block_type: type), multiple: true, child_index: "NEW_BLOCK" do |block_form| %>
              <%= render "avo/partials/content_block_row", f: block_form, tool: tool %>
            <% end %>
          </template>
        <% end %>

        <div class="flex flex-wrap gap-2">
          <% ContentBlock.block_types.each_key do |type| %>
            <button type="button" data-action="block-editor#add" data-block-type="<%= type %>"
              class="rounded border px-3 py-1.5 text-sm font-semibold">+ <%= tool.block_type_label(type) %></button>
          <% end %>
        </div>
      </div>
    <% end %>
  <% end %>
```

`_content_block_row.html.erb` — replace the whole file:

```erb
<%# One block in the page form's inline editor (spec §10.2). Only the
    fields of the row's own type are rendered; the type is fixed per row (to
    change it, delete the block and add another). Translated fields sit in
    per-locale panes that block_editor_controller.js shows one at a time.
    Locals: `f` (fields_for builder over one ContentBlock), `tool`. %>
<% block = f.object %>
<div data-block-row data-persisted="<%= block.persisted? %>" class="rounded-lg border p-4 space-y-4">
  <%= f.hidden_field :block_type %>
  <%= f.hidden_field :position, data: { block_role: "position" } %>
  <% if block.persisted? %>
    <%= f.hidden_field :_destroy, value: "0", data: { block_role: "destroy" } %>
  <% end %>

  <div class="flex items-center justify-between gap-2">
    <strong><%= tool.block_type_label(block.block_type) %></strong>
    <div class="flex items-center gap-1">
      <button type="button" data-action="block-editor#moveUp" aria-label="Move up" class="rounded border px-2">↑</button>
      <button type="button" data-action="block-editor#moveDown" aria-label="Move down" class="rounded border px-2">↓</button>
      <button type="button" data-action="block-editor#remove" data-block-role="remove" class="rounded border px-2">Delete</button>
      <button type="button" data-action="block-editor#undo" data-block-role="undo" class="rounded border px-2" style="display: none">Undo</button>
    </div>
  </div>

  <% if block.errors.any? %>
    <ul class="text-sm text-red-600">
      <% block.errors.full_messages.each do |message| %><li><%= message %></li><% end %>
    </ul>
  <% end %>

  <% case block.block_type %>
  <% when "rich_text" %>
    <% tool.locale_accessors(:body).each do |locale, accessor| %>
      <div data-locale-pane="<%= locale %>">
        <%= f.label accessor, "Text (#{locale.to_s.upcase})", class: "font-semibold" %>
        <%= f.rich_textarea accessor, value: block.public_send(accessor)&.to_trix_html %>
      </div>
    <% end %>
  <% when "image" %>
    <div>
      <%= f.label :image, "Image", class: "font-semibold" %>
      <% if block.image.attached? %>
        <%= image_tag block.image, alt: "", class: "my-2 h-24 w-auto rounded" %>
      <% end %>
      <%= f.file_field :image, accept: "image/*", class: input_classes %>
    </div>
    <% tool.locale_accessors(:caption).each do |locale, accessor| %>
      <% alt_accessor = ::Mobility.normalize_locale_accessor(:alt, locale).to_sym %>
      <div data-locale-pane="<%= locale %>" class="grid gap-4 md:grid-cols-2">
        <div>
          <%= f.label accessor, "Caption (#{locale.to_s.upcase})", class: "font-semibold" %>
          <%= f.text_field accessor, class: input_classes("w-full") %>
        </div>
        <div>
          <%= f.label alt_accessor, "Alt text (#{locale.to_s.upcase})", class: "font-semibold" %>
          <%= f.text_field alt_accessor, class: input_classes("w-full"),
                placeholder: "Describe the image for screen readers" %>
        </div>
      </div>
    <% end %>
  <% when "post_list" %>
    <% settings = block.settings.to_h %>
    <div class="flex flex-wrap gap-4">
      <div>
        <%= label_tag f.field_id(:settings, :content_type), "Show", class: "font-semibold block" %>
        <%= select_tag "#{f.object_name}[settings][content_type]",
              options_for_select([ [ "All types", "" ], [ "Blog posts", "blog" ], [ "Resume entries", "resume_entry" ], [ "Now updates", "now_update" ] ], settings["content_type"]),
              id: f.field_id(:settings, :content_type), class: input_classes %>
      </div>
      <div>
        <%= label_tag f.field_id(:settings, :tag), "Tag", class: "font-semibold block" %>
        <%= select_tag "#{f.object_name}[settings][tag]",
              options_for_select([ [ "Any tag", "" ] ] + Tag.order(:name).pluck(:name, :name), settings["tag"]),
              id: f.field_id(:settings, :tag), class: input_classes %>
      </div>
      <div>
        <%= label_tag f.field_id(:settings, :limit), "Show up to", class: "font-semibold block" %>
        <%= number_field_tag "#{f.object_name}[settings][limit]", settings["limit"], min: 1, placeholder: "All",
              id: f.field_id(:settings, :limit), class: input_classes %>
      </div>
    </div>
  <% end %>
</div>
```

Also update the remaining tests in `avo_page_editing_test.rb` that posted a blank-row index or relied on the old `Body HTML` markup, keeping their intent (they post params directly, so most need no change); list any you changed in your report.

- [ ] **Step 4:** `bin/rails test test/integration/avo_page_editing_test.rb test/integration/avo_access_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: type-specific inline block editor markup` (+ trailer).

### Task 13: Block editor behaviour (Stimulus) and browser test

**Files:**
- Create: `app/javascript/controllers/block_editor_controller.js`, `test/system/block_editor_test.rb`
- Modify: `app/javascript/avo.custom.js`

**Interfaces:**
- Consumes: the DOM contract from Task 12.

- [ ] **Step 1: Write the failing browser test**

```ruby
# test/system/block_editor_test.rb
require "application_system_test_case"

class BlockEditorTest < ApplicationSystemTestCase
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign in"
  end

  test "add, type, reorder and save blocks; the public page reflects them" do
    visit "/avo/resources/pages/#{@root.id}/edit"

    click_on "+ Text"
    all("trix-editor").last.click
    all("trix-editor").last.send_keys("First block")
    click_on "+ Text"
    all("trix-editor").last.click
    all("trix-editor").last.send_keys("Second block")
    all("[data-block-row]").last.click_on("↑")
    click_on "Save"

    visit "/"
    assert_text "Second block"
    assert page.text.index("Second block") < page.text.index("First block")
  end

  test "delete can be undone before saving" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: "<p>Keep</p>")
    visit "/avo/resources/pages/#{@root.id}/edit"

    within(first("[data-block-row]")) { click_on "Delete" }
    within(first("[data-block-row]")) { click_on "Undo" }
    click_on "Save"
    assert_equal 1, @root.content_blocks.reload.count

    visit "/avo/resources/pages/#{@root.id}/edit"
    within(first("[data-block-row]")) { click_on "Delete" }
    click_on "Save"
    assert_equal 0, @root.content_blocks.reload.count
  end
end
```

- [ ] **Step 2:** `bin/rails test test/system/block_editor_test.rb` → FAIL (buttons do nothing).

- [ ] **Step 3: Implement**

`app/javascript/controllers/block_editor_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Inline content-block editor on the Avo page form (spec §10.2). Rows are
// plain nested-attribute fields; this controller only adds rows from
// <template>s, keeps hidden `position` inputs in DOM order, toggles
// `_destroy` with an undo, and shows one locale's panes at a time.
export default class extends Controller {
  static targets = ["list", "template"]

  connect() {
    const first = this.element.querySelector("[data-action~='block-editor#selectLocale']")
    this.locale = first ? first.dataset.locale : null
    this.applyLocale()
    this.renumber()
  }

  add(event) {
    const type = event.currentTarget.dataset.blockType
    const template = this.templateTargets.find((t) => t.dataset.blockType === type)
    if (!template) return
    const html = template.innerHTML.replaceAll("NEW_BLOCK", `${Date.now()}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.applyLocale()
    this.renumber()
  }

  moveUp(event) {
    const row = this.rowFor(event)
    const previous = row.previousElementSibling
    if (previous) this.listTarget.insertBefore(row, previous)
    this.renumber()
  }

  moveDown(event) {
    const row = this.rowFor(event)
    const next = row.nextElementSibling
    if (next) this.listTarget.insertBefore(next, row)
    this.renumber()
  }

  remove(event) {
    const row = this.rowFor(event)
    if (row.dataset.persisted !== "true") {
      row.remove()
      this.renumber()
      return
    }
    this.setRemoved(row, true)
  }

  undo(event) {
    this.setRemoved(this.rowFor(event), false)
  }

  selectLocale(event) {
    this.locale = event.currentTarget.dataset.locale
    this.applyLocale()
  }

  // private

  setRemoved(row, removed) {
    row.querySelector("[data-block-role='destroy']").value = removed ? "1" : "0"
    row.style.opacity = removed ? "0.5" : ""
    row.querySelector("[data-block-role='remove']").style.display = removed ? "none" : ""
    row.querySelector("[data-block-role='undo']").style.display = removed ? "" : "none"
  }

  applyLocale() {
    this.element.querySelectorAll("[data-locale-pane]").forEach((pane) => {
      pane.style.display = pane.dataset.localePane === this.locale ? "" : "none"
    })
    this.element.querySelectorAll("[data-action~='block-editor#selectLocale']").forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.locale === this.locale ? "true" : "false")
    })
  }

  renumber() {
    this.listTarget.querySelectorAll(":scope > [data-block-row]").forEach((row, index) => {
      row.querySelector("[data-block-role='position']").value = index
    })
  }

  rowFor(event) {
    return event.currentTarget.closest("[data-block-row]")
  }
}
```

Note: each row is rendered inside `fields_for`, which may emit a hidden `id` input next to the row div; `renumber` only walks direct children that are rows (`:scope > [data-block-row]`), and `moveUp`/`moveDown` must move the row together with any sibling hidden `id` input. If `fields_for` emits `page[content_blocks_attributes][N][id]` as a *sibling* of the row div (check the rendered HTML), render the id inside the row instead: pass `include_id: false` to both `fields_for` calls in `_nested_content_blocks.html.erb` and add `<%= f.hidden_field :id if block.persisted? %>` at the top of the row partial. Report which you did.

`avo.custom.js` — import and `window.Stimulus.register("block-editor", BlockEditorController)`.

- [ ] **Step 4:** `bin/rails test test/system/block_editor_test.rb` → PASS; `bin/rails test test/system` and full suite green.

- [ ] **Step 5: Commit** — `feat: add, reorder and delete page blocks inline` (+ trailer).

### Task 14: Dashboard home and admin shell

**Files:**
- Create: `app/views/avo/tools/dashboard.html.erb`, `app/views/avo/sidebar/items/_dashboard.html.erb`, `test/integration/avo_dashboard_test.rb`
- Modify: `app/controllers/avo/tools_controller.rb`, `config/routes.rb` (inside `mount_avo`), `config/initializers/avo.rb`, `app/avo/resources/content_block.rb`, `app/avo/resources/user.rb`, `app/avo/resources/api_token.rb` (title only)

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/avo_dashboard_test.rb
require "test_helper"

class AvoDashboardTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    Post.create!(content_type: :blog, title: "Unfinished draft")
    Post.create!(content_type: :blog, title: "Tomorrow's post", published_at: 1.day.from_now)
  end

  test "the admin home is the dashboard" do
    get "/avo"
    follow_redirect! while response.redirect?

    assert_equal "/avo/dashboard", path
  end

  test "the dashboard lists drafts and scheduled items with quick links" do
    get "/avo/dashboard"

    assert_response :success
    assert_includes response.body, "Unfinished draft"
    assert_includes response.body, "Tomorrow&#39;s post"
    assert_select "a[href='/avo/resources/posts/new']", text: /New post/
    assert_select "a[href='/avo/resources/pages/new']", text: /New page/
  end

  test "the sidebar hides content blocks and the admin carries the site title" do
    get "/avo/dashboard"

    assert_select "a[href='/avo/resources/content_blocks']", count: 0
    assert_includes response.body, "Test Site"
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/avo_dashboard_test.rb` → FAIL.

- [ ] **Step 3: Implement**

Route inside `mount_avo do … end` (below `system_status`): `get "dashboard", to: "tools#dashboard", as: :dashboard`.

`tools_controller.rb`:

```ruby
  # The admin's home (spec §10.5): what needs attention, and the two most
  # common "new" actions.
  def dashboard
    @page_title = "Dashboard"
    add_breadcrumb title: "Dashboard"
    @drafts = (Post.where(published_at: nil).to_a + Page.where(published_at: nil).to_a)
      .sort_by(&:updated_at).reverse.first(8)
    @scheduled = (Post.where("published_at > ?", Time.current).to_a + Page.where("published_at > ?", Time.current).to_a)
      .sort_by(&:published_at).first(8)
    @recent = (Post.order(updated_at: :desc).limit(8).to_a + Page.order(updated_at: :desc).limit(8).to_a)
      .sort_by(&:updated_at).reverse.first(8)
  end
```

`dashboard.html.erb`:

```erb
<div class="flex flex-col gap-4">
  <div class="flex gap-2">
    <%= link_to "+ New post", avo.new_resources_post_path, class: "rounded border px-3 py-1.5 font-semibold" %>
    <%= link_to "+ New page", avo.new_resources_page_path, class: "rounded border px-3 py-1.5 font-semibold" %>
  </div>
  <% [ [ "Drafts", @drafts, "Nothing in draft." ], [ "Scheduled", @scheduled, "Nothing scheduled." ], [ "Recently edited", @recent, "Nothing yet." ] ].each do |title, records, empty| %>
    <%= render ui.panel(title: title) do |panel| %>
      <% panel.with_card do %>
        <% if records.empty? %>
          <p class="text-content-secondary"><%= empty %></p>
        <% else %>
          <ul class="divide-y">
            <% records.each do |record| %>
              <li class="flex items-center justify-between gap-4 py-2">
                <%= link_to record.title, record.is_a?(Post) ? avo.edit_resources_post_path(record) : avo.edit_resources_page_path(record), class: "font-medium hover:underline" %>
                <span class="text-xs text-content-secondary">
                  <%= record.model_name.human %> · <%= record.status %><%= " · #{l(record.published_at, format: :short)}" if record.status == "scheduled" %>
                </span>
              </li>
            <% end %>
          </ul>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
</div>
```

`sidebar/items/_dashboard.html.erb`: `<%= render Avo::Sidebar::LinkComponent.new label: 'Dashboard', path: File.join(avo.root_path, "dashboard") %>`

`config/initializers/avo.rb`: set `config.home_path = "/avo/dashboard"` and `config.app_name = -> { SiteSetting.instance.title }` (replacing the commented defaults; the proc is evaluated per request by `Avo::ExecutionContext`).

`content_block.rb`: `self.visible_on_sidebar = false` (comment: blocks are edited inside their page).
`user.rb`: `self.title = :email_address`.
`api_token.rb`: `self.title = -> { "#{record.user.email_address} · #{record.created_at.to_date}" }`.

- [ ] **Step 4:** `bin/rails test test/integration/avo_dashboard_test.rb test/integration/avo_access_test.rb test/integration/setup_finish_test.rb` → PASS (the setup finish redirect to `/avo` still lands in the admin); full suite + `bin/rails test test/system` green.

- [ ] **Step 5: Commit** — `feat: add an admin dashboard and editor-friendly admin shell` (+ trailer).

### Task 15: "Connect an AI assistant" and token management

**Files:**
- Create: `app/views/avo/tools/ai_assistant.html.erb`, `app/views/avo/tools/ai_assistant_token.html.erb`, `app/views/avo/sidebar/items/_ai_assistant.html.erb`, `app/javascript/controllers/clipboard_controller.js`, `app/avo/actions/revoke_api_token.rb`, `test/integration/avo_ai_assistant_test.rb`
- Modify: `app/controllers/avo/tools_controller.rb`, `config/routes.rb` (inside `mount_avo`), `app/avo/resources/api_token.rb`, `app/models/api_token.rb`, `app/javascript/avo.custom.js`, `app/views/setup/mcp_token.html.erb` (copy), `test/integration/avo_api_tokens_test.rb`
- Delete: `app/avo/actions/regenerate_api_token.rb`, `test/models/regenerate_api_token_action_test.rb`

**Interfaces:**
- Produces: `ApiToken#status` → `"active" | "revoked"`; routes `avo.ai_assistant_path` (GET), `avo.ai_assistant_token_path` (POST).

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/avo_ai_assistant_test.rb
require "test_helper"

class AvoAiAssistantTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "the page explains the MCP endpoint and offers a token" do
    get "/avo/ai_assistant"

    assert_response :success
    assert_includes response.body, "http://www.example.com/mcp"
    assert_select "form[action='/avo/ai_assistant/token'][data-turbo=false]"
  end

  test "generating shows the raw token once, uncached, bound to the user" do
    assert_difference "ApiToken.count", 1 do
      post "/avo/ai_assistant/token"
    end

    assert_response :success
    raw = css_select("#mcp-token").first.text.strip
    assert_equal users(:one), ApiToken.authenticate(raw).user
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.body, "Bearer #{raw}"
    assert_empty flash.to_h
  end

  test "revoking a token deactivates it" do
    token, raw = ApiToken.generate!(users(:one))
    Avo::Actions::RevokeApiToken.new(user: users(:one)).handle(records: [ token ], current_user: users(:one))

    assert_nil ApiToken.authenticate(raw)
    assert_equal "revoked", token.reload.status
  end

  test "the token list hides the digest" do
    token, = ApiToken.generate!(users(:one))
    get "/avo/resources/api_tokens/#{token.id}"

    assert_not_includes response.body, token.token_digest
  end
end
```

Replace `test/integration/avo_api_tokens_test.rb`'s first test with:

```ruby
  test "the api tokens index renders and points to the AI assistant page" do
    get "/avo/resources/api_tokens"

    assert_response :success
    assert_not_includes response.body, "Regenerate my API token"
  end
```

- [ ] **Step 2:** `bin/rails test test/integration/avo_ai_assistant_test.rb test/integration/avo_api_tokens_test.rb` → FAIL.

- [ ] **Step 3: Implement**

Routes inside `mount_avo`:

```ruby
    # "Connect an AI assistant" (spec §10.6): the token is revealed once on a
    # full page load, never in a toast.
    get "ai_assistant", to: "tools#ai_assistant", as: :ai_assistant
    post "ai_assistant/token", to: "tools#create_ai_assistant_token", as: :ai_assistant_token
```

`tools_controller.rb`:

```ruby
  def ai_assistant
    @page_title = "Connect an AI assistant"
    add_breadcrumb title: "Connect an AI assistant"
    @mcp_url = "#{request.base_url}/mcp"
    @tokens = Current.user.api_tokens.order(created_at: :desc)
  end

  # Rendered, not redirected, and never cached: the raw token exists only in
  # this response (same rule as the setup wizard's MCP step).
  def create_ai_assistant_token
    @page_title = "Your AI assistant token"
    add_breadcrumb title: "Connect an AI assistant"
    @mcp_url = "#{request.base_url}/mcp"
    _token, @raw_token = ApiToken.generate!(Current.user)
    response.set_header("Cache-Control", "no-store")
    render :ai_assistant_token
  end
```

`ai_assistant.html.erb`:

```erb
<div class="flex flex-col gap-4">
  <%= render ui.panel(title: "Connect an AI assistant",
        description: "AI assistants such as Claude can list, create and edit your posts through this site's MCP server.") do |panel| %>
    <% panel.with_card(padded: true) do %>
      <p>MCP server URL:</p>
      <pre class="my-2 rounded border p-2"><%= @mcp_url %></pre>
      <p class="text-content-secondary">Generate a token, then paste the configuration it shows into your AI client. Each token is shown once.</p>
      <%= button_to "Generate a token", avo.ai_assistant_token_path, method: :post,
            form: { data: { turbo: false } }, class: "mt-4 rounded border px-3 py-1.5 font-semibold" %>
    <% end %>
  <% end %>
  <%= render ui.panel(title: "Your tokens") do |panel| %>
    <% panel.with_card(padded: true) do %>
      <% if @tokens.empty? %>
        <p class="text-content-secondary">No tokens yet.</p>
      <% else %>
        <ul class="divide-y">
          <% @tokens.each do |token| %>
            <li class="flex justify-between py-2">
              <span>Created <%= l(token.created_at, format: :short) %> · <%= token.status %></span>
              <span class="text-content-secondary">Last used <%= token.last_used_at ? "#{time_ago_in_words(token.last_used_at)} ago" : "never" %></span>
            </li>
          <% end %>
        </ul>
        <%= link_to "Manage or revoke tokens", avo.resources_api_tokens_path, class: "mt-2 inline-block underline" %>
      <% end %>
    <% end %>
  <% end %>
</div>
```

`ai_assistant_token.html.erb`:

```erb
<% config = JSON.pretty_generate({ "mcpServers" => { "contentspiel" => {
     "type" => "http", "url" => @mcp_url, "headers" => { "Authorization" => "Bearer #{@raw_token}" } } } }) %>
<%= render ui.panel(title: "Your AI assistant token",
      description: "Copy it now — it won't be shown again. Anyone with this token can edit your posts.") do |panel| %>
  <% panel.with_card(padded: true) do %>
    <div data-controller="clipboard" class="space-y-2">
      <pre id="mcp-token" data-clipboard-target="source" class="rounded border p-2 overflow-x-auto"><%= @raw_token %></pre>
      <button type="button" data-action="clipboard#copy" class="rounded border px-3 py-1.5 font-semibold">Copy token</button>
    </div>
    <p class="mt-4">Client configuration:</p>
    <pre class="rounded border p-2 overflow-x-auto"><%= config %></pre>
    <%= link_to "Done", avo.ai_assistant_path, class: "mt-4 inline-block underline" %>
  <% end %>
<% end %>
```

`clipboard_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Copies the text of the `source` target to the clipboard.
export default class extends Controller {
  static targets = ["source"]

  copy(event) {
    navigator.clipboard?.writeText(this.sourceTarget.textContent.trim())
    event.currentTarget.textContent = "Copied"
  }
}
```

Register it in `avo.custom.js` as `"clipboard"`.

`sidebar/items/_ai_assistant.html.erb`: `<%= render Avo::Sidebar::LinkComponent.new label: 'Connect an AI assistant', path: File.join(avo.root_path, "ai_assistant") %>`

`api_token.rb` model — add `def status = revoked_at ? "revoked" : "active"`.

`app/avo/actions/revoke_api_token.rb`:

```ruby
class Avo::Actions::RevokeApiToken < Avo::BaseAction
  self.name = "Revoke"
  self.message = "The selected tokens stop working immediately."

  def handle(records:, **)
    records.each(&:revoke!)
    succeed("Revoked.")
  end
end
```

`app/avo/resources/api_token.rb` — fields become:

```ruby
    field :id, as: :id
    field :user, as: :belongs_to, readonly: true
    field :status, as: :badge, options: { success: "active", neutral: "revoked" }
    field :created_at, as: :date_time, readonly: true
    field :last_used_at, as: :date_time, readonly: true
    field :last_used_ip, as: :text, readonly: true
```

(the `token_digest` and editable `revoked_at` fields are removed); `actions` becomes `action Avo::Actions::RevokeApiToken`. Delete the RegenerateApiToken action and its model test.

`app/views/setup/mcp_token.html.erb` — change "under API tokens" to "under Connect an AI assistant".

- [ ] **Step 4:** run the two test files, `test/integration/setup_optional_steps_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: replace the token toast with a Connect an AI assistant page` (+ trailer).

### Task 16: Translation helpers

**Files:**
- Create: `app/avo/translation_hints.rb`, `test/integration/avo_translations_test.rb`
- Modify: `app/avo/resources/post.rb`, `app/avo/resources/page.rb`

**Interfaces:**
- Produces: `TranslationHints.help(attribute, locale)` → Avo `help:` lambda (nil for the default locale); `TranslationHints.status(record)` → e.g. `"EN ✓ DE – ES –"`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/avo_translations_test.rb
require "test_helper"

class AvoTranslationsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "indexes show which locales have a title" do
    Post.create!(content_type: :blog, title_en: "Hello", title_de: "Hallo")
    get "/avo/resources/posts"

    assert_includes response.body, "EN ✓ DE ✓ ES –"
  end

  test "non-default locale tabs show the default-locale text as a hint" do
    post = Post.create!(content_type: :blog, title_en: "Hello world", excerpt_en: "Short")
    get "/avo/resources/posts/#{post.id}/edit"

    assert_includes response.body, "EN: Hello world"
    assert_includes response.body, "EN: Short"
  end

  test "excerpt textareas can't collapse" do
    post = Post.create!(content_type: :blog, title: "X")
    get "/avo/resources/posts/#{post.id}/edit"

    assert_select "textarea[name='post[excerpt_de]'][style*='min-height']"
  end
end
```

- [ ] **Step 2:** `bin/rails test test/integration/avo_translations_test.rb` → FAIL.

- [ ] **Step 3: Implement**

`app/avo/translation_hints.rb` (same autoload caveat as `TypeFields` in Task 9 — mirror whatever location worked there):

```ruby
# Translator aids for Avo's per-locale tabs (spec §10.7).
module TranslationHints
  module_function

  # Shows the default locale's value under each non-default-locale field, so
  # translators don't have to switch tabs. The default locale is the site's
  # runtime setting, not I18n.default_locale.
  def help(attribute, locale)
    lambda do
      default = SiteSetting.instance.default_locale
      next nil if locale.to_s == default

      value = record&.public_send(::Mobility.normalize_locale_accessor(attribute, default))
      value = value.to_plain_text if value.respond_to?(:to_plain_text)
      "#{default.upcase}: #{value.to_s.truncate(160).presence || "—"}"
    end
  end

  def status(record)
    ::Mobility.available_locales.map do |locale|
      present = record.public_send(::Mobility.normalize_locale_accessor(:title, locale)).present?
      "#{locale.to_s.upcase} #{present ? "✓" : "–"}"
    end.join(" ")
  end

  # Avo's textarea can render 0px tall inside a hidden tab; a min-height
  # keeps it usable once the tab is shown.
  TEXTAREA_HTML = {
    new: { input: { style: "min-height: 6rem" } },
    edit: { input: { style: "min-height: 6rem" } }
  }.freeze
end
```

In `post.rb` and `page.rb` resources:
- index column: `field :translations, as: :text, only_on: :index, name: "Translations" do ::TranslationHints.status(record) end`
- on every translated field inside the locale tabs add `help: ::TranslationHints.help(:<attribute>, locale)` (title, excerpt, subtitle, meta_title, meta_description, hero_alt; not slug, not body for pages; posts' body may take it too).
- on textarea fields (post excerpt, page meta description) add `html: ::TranslationHints::TEXTAREA_HTML`.

If a field already has `html:` (the landing-only ones), merge the two hashes with `deep_merge`.

- [ ] **Step 4:** `bin/rails test test/integration/avo_translations_test.rb test/integration/avo_post_translations_test.rb` → PASS; full suite green.

- [ ] **Step 5: Commit** — `feat: translation hints and status in the admin` (+ trailer).

### Task 17: Final verification

- [ ] **Step 1:** Run and require all clean:

```bash
bin/rails tailwindcss:build
PARALLEL_WORKERS=1 bin/rails test
bin/rails test test/system
bin/rubocop
bin/brakeman -q --no-pager
bin/bundler-audit check --update
bin/importmap audit
```

- [ ] **Step 2:** Non-destructive smoke check in development: `bin/rails runner 'puts Post.count, Page.count'` and `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/` against a running `bin/dev` if one is up; report results. (Resetting the dev database is allowed for a manual walk-through if needed — project has no production.)

- [ ] **Step 3:** Commit any verification fixes as `fix: …` commits (+ trailer). The controller opens the PR.
