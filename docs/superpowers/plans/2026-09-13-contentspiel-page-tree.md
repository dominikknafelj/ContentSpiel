# ContentSpiel Page Tree & Content Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the public-facing side of ContentSpiel: a `Page` tree
(via `closure_tree`) composed of ordered `ContentBlock` records,
served through a single locale-aware catch-all route, editable in
Avo — plus the Mobility-based i18n infrastructure this plan (and the
original spec) needs, which nothing has installed yet.

**Architecture:** `Page` owns the site's navigation tree; `Post`
(from the Foundation plan) stays a separate, non-tree content type
and is pulled into pages only through a `post_list` `ContentBlock`.
`ContentBlock` is one shared-shape model (`block_type` enum), matching
`Post`'s existing pattern rather than per-type models. Individual
post permalinks are served by the same `Page` that lists them,
falling back from "no Page matches this full path" to "the last
segment is a Post slug under this Page's post_list block."

**Tech Stack:** Adds `mobility` (i18n, jsonb + ActionText backends)
and `closure_tree` (page hierarchy) to the Foundation plan's Rails
8 / Postgres / Avo 4.2.3 stack.

**Spec:** `docs/superpowers/specs/2026-09-13-contentspiel-page-tree-design.md`
(this plan's primary spec) and
`docs/superpowers/specs/2026-09-13-contentspiel-design.md` §12
(the original i18n commitment that Task 1 finally implements)

## Global Constraints

- Ruby `3.4.9`, Rails `~> 8.1`, PostgreSQL — unchanged from the
  Foundation plan.
- Locales: English (default), German, Spanish — matches the original
  spec §12. UI chrome translation (`config/locales/*.yml`) is out of
  scope for this plan; it covers `Post`/`Page`/`ContentBlock` content
  only.
- No new tagging/tree gems beyond `mobility` and `closure_tree` —
  `Tag`/`PostRelation` stay exactly as the Foundation plan built them,
  no gem retrofit.
- `ContentBlock` is one shared-shape model with a `block_type` enum
  (not STI, not per-type models) — matches `Post`'s established
  pattern (page-tree spec §3).
- A `Page` with children cannot be destroyed until its children are
  reparented or destroyed first — no cascading delete of a subtree
  (page-tree spec §8).
- No visual drag-and-drop tree editor, no page versioning, no
  multi-root/multi-site support in this plan (page-tree spec §10).
- Deploy/Kamal configuration remains out of scope, same as the
  Foundation plan.
- Gem/framework DSL that changes across versions (Mobility's backend
  configuration, `closure_tree`'s tree macro options, Avo's
  translated-field UI) must be verified against the actually-installed
  gem version's current docs (via the `context7` MCP tool, or the
  gem's own source/README under the bundle path) before writing code
  that uses it — do not guess at remembered syntax from an unspecified
  version. This mirrors how the Foundation plan's Avo installation
  task was handled.

---

## Task 1: Install Mobility and make `Post` translatable

**Files:**
- Modify: `Gemfile`
- Create: (generated) `config/initializers/mobility.rb`
- Create: `db/migrate/<timestamp>_convert_post_translated_columns_to_jsonb.rb`
- Modify: `app/models/post.rb`
- Modify: `app/avo/resources/post.rb`
- Test: `test/models/post_test.rb` (extended)
- Test: `test/integration/avo_access_test.rb` (extended, or a new
  focused test file if that file is already large)

**Interfaces:**
- Consumes: `Post` as built by the Foundation plan (`content_type`
  enum, `title`/`slug`/`excerpt` string columns, `has_rich_text
  :body`).
- Produces: `Post#title`/`#slug`/`#excerpt`/`#body` become
  locale-aware (reading/writing the current `Mobility.locale`/
  `I18n.locale`'s translation, falling back to the default locale
  `en` when a translation is missing). `Post.available_locales`
  (or equivalent — verify the actual constant/method Mobility
  provides) is `[:en, :de, :es]`. Later tasks (`Page`,
  `ContentBlock`) apply the same jsonb-backend pattern established
  here to their own translated columns — this task is where the
  pattern gets proven out with tests, so later tasks don't need to
  re-derive it.

- [ ] **Step 1: Look up current Mobility docs for the pieces this task needs**

Before writing any code, use `context7` (or the installed gem's own
README/docs under the bundle path) to confirm, for the Mobility
version that `bundle add mobility` actually installs:
1. How to install/configure Mobility in a Rails app (the install
   generator, default backend, available locales, default locale,
   and locale-fallback configuration).
2. The `jsonb` backend's exact column requirements (column name,
   type) and the exact `translates` (or equivalent) class-method call
   for a string attribute.
3. Mobility's backend for ActionText rich text (`body`) — is it
   bundled in the `mobility` gem itself, or a separate gem
   (`mobility-actiontext` or similar)? What's the exact setup call?
4. How to validate uniqueness of a translated (jsonb-backed) attribute
   — Rails' built-in `uniqueness:` validator queries a real DB
   column directly and won't work correctly against a jsonb-backed
   virtual attribute; Mobility documents its own querying interface
   (commonly exposed as an `i18n` query scope) for this. Confirm the
   actual current mechanism.

Use exactly what you find — don't guess at remembered syntax from an
unspecified version.

- [ ] **Step 2: Install Mobility**

```bash
bundle add mobility
bin/rails generate mobility:install
```

Configure (in whatever the generated initializer's current format
is): available locales `%i[en de es]`, default locale `:en`,
fallback to the default locale when a translation is missing —
per the docs you looked up in Step 1.

- [ ] **Step 3: Write the failing tests for translated attributes**

`test/models/post_test.rb` — add:

```ruby
test "title, slug, and excerpt are independently translatable per locale" do
  post = Post.create!(content_type: :blog, title: "Hello World")

  Mobility.with_locale(:de) { post.update!(title: "Hallo Welt", slug: "hallo-welt") }
  Mobility.with_locale(:es) { post.update!(title: "Hola Mundo", slug: "hola-mundo") }

  assert_equal "Hello World", post.title
  assert_equal "hello-world", post.slug
  Mobility.with_locale(:de) do
    assert_equal "Hallo Welt", post.title
    assert_equal "hallo-welt", post.slug
  end
  Mobility.with_locale(:es) do
    assert_equal "Hola Mundo", post.title
    assert_equal "hola-mundo", post.slug
  end
end

test "falls back to the default locale when a translation is missing" do
  post = Post.create!(content_type: :blog, title: "Hello World")

  Mobility.with_locale(:de) do
    assert_equal "Hello World", post.title
  end
end

test "slug uniqueness is scoped to content_type and locale, not shared across locales" do
  Post.create!(content_type: :blog, title: "Hello World")

  Mobility.with_locale(:de) do
    other = Post.new(content_type: :blog, title: "Something Else", slug: "hello-world")
    assert other.valid?, "a slug used in one locale must not block the same slug in another locale"
  end
end

test "body is independently translatable per locale" do
  post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")

  Mobility.with_locale(:de) { post.update!(body: "<p>Hallo</p>") }

  assert_includes post.body.to_plain_text, "Hi"
  Mobility.with_locale(:de) do
    assert_includes post.body.to_plain_text, "Hallo"
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
bin/rails test test/models/post_test.rb
```

Expected: FAIL — `title`/`slug`/`excerpt` are still plain string
columns with no per-locale storage, so the German/Spanish
assertions fail.

- [ ] **Step 5: Write the migration**

Convert `title`, `slug`, `excerpt` from `string` to the column
type/shape the jsonb backend needs (per Step 1's findings — this is
very likely `jsonb`, matching the column-per-attribute convention).
There is no real production data yet (the Foundation plan only just
shipped), so a straight column-type conversion is fine — no data
migration needed.

```bash
bin/rails generate migration ConvertPostTranslatedColumnsToJsonb
```

Write the migration to change `posts.title`, `posts.slug`, and
`posts.excerpt` to the type the backend requires, using
`ActiveRecord::Migration[8.1]`. Since the exact backend column
convention depends on Step 1's findings, confirm the migration you
write matches it exactly (e.g. if the backend expects a jsonb column
per attribute with the same name, `change_column :posts, :title,
:jsonb, ... default: {}` for each of the three columns).

- [ ] **Step 6: Update the `Post` model**

Add the Mobility setup found in Step 1 to `app/models/post.rb` (e.g.
`extend Mobility`, `translates :title, :slug, :excerpt, backend:
:jsonb`, and the ActionText backend call for `body`) above the
existing `enum :content_type, ...` line. Update the slug uniqueness
validation to use Mobility's documented approach for validating a
translated attribute's uniqueness, scoped to `content_type` **and**
the current locale (a slug can repeat across locales, per the test in
Step 3, but must stay unique within one locale + content_type).

- [ ] **Step 7: Run tests to verify they pass**

```bash
bin/rails test test/models/post_test.rb
```

Expected: PASS.

- [ ] **Step 8: Update the Avo `Post` resource for locale editing**

Using the current Avo 4.2.3 + Mobility integration approach (look
this up specifically — Avo may need explicit configuration to show a
locale switcher on translated fields; check Avo's docs/gem source for
"Mobility" or "translatable" support), update
`app/avo/resources/post.rb` so `title`/`slug`/`excerpt`/`body` are
editable per-locale in the admin.

Add a request test (in `test/integration/avo_access_test.rb` or a new
file if that one is already large) that signs in, visits the `Post`
edit form, and asserts the response is successful and that some
locale-switching UI element the current Avo/Mobility integration
produces is present (name the actual element you find — don't guess).

- [ ] **Step 9: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS, no regressions.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: install Mobility and make Post content translatable

Implements the original spec's i18n commitment (section 12), deferred
out of the Foundation plan. title/slug/excerpt use Mobility's jsonb
backend; body uses its ActionText backend. Slug uniqueness is now
scoped to content_type + locale.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 2: `Page` model (tree, no content blocks yet)

**Files:**
- Modify: `Gemfile`
- Create: `db/migrate/<timestamp>_create_pages.rb`
- Create: (closure_tree generator output, if any additional
  migration it needs)
- Create: `app/models/page.rb`
- Test: `test/models/page_test.rb`

**Interfaces:**
- Consumes: Mobility's `translates`/jsonb-backend pattern from Task
  1; Active Storage (already installed by the Foundation plan) for
  `hero_image`.
- Produces: `Page` with `parent`/`children` (closure_tree),
  `page_type` (enum: `standard`, `landing`), translatable
  `title`/`slug`/`subtitle`/`meta_title`/`meta_description`,
  `hero_image` (Active Storage attachment), `published_at`. Exactly
  one root (`parent: nil`) may exist. A `Page` with children refuses
  to be destroyed. Task 3 adds the per-locale cached path on top of
  this; Task 4 adds `content_blocks` to it.

- [ ] **Step 1: Look up current closure_tree docs**

Use `context7` or the installed gem's README to confirm the exact
tree-declaring macro (e.g. `has_closure_tree`) and its options for:
sibling ordering (a column it manages for you), and how to get
`parent`/`children`/ancestor-list accessors. Confirm whether it
provides any built-in `dependent:` delete behavior — **do not use
a cascading destroy option**; this task implements its own
children-block on destroy instead (see Step 6).

- [ ] **Step 2: Install closure_tree**

```bash
bundle add closure_tree
```

- [ ] **Step 3: Write the migration**

```bash
bin/rails generate migration CreatePages
```

```ruby
class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.integer :page_type, null: false, default: 0
      t.string :title, null: false
      t.string :slug, null: false
      t.string :subtitle
      t.string :meta_title
      t.string :meta_description
      t.datetime :published_at

      t.timestamps
    end
  end
end
```

Then run whatever additional migration `closure_tree`'s own
generator/setup requires for its hierarchy table and ordering column
(per Step 1's findings) — apply it as its own migration file rather
than hand-editing the one above.

Convert `title`, `slug`, `subtitle`, `meta_title`, `meta_description`
to the jsonb (or whatever Task 1 established) column type/shape for
Mobility, in the same migration or a follow-up one — be consistent
with Task 1's approach.

- [ ] **Step 4: Write the failing tests**

`test/models/page_test.rb`:

```ruby
require "test_helper"

class PageTest < ActiveSupport::TestCase
  test "title is required" do
    page = Page.new(page_type: :standard)
    assert_not page.valid?
    assert_includes page.errors[:title], "can't be blank"
  end

  test "a page can have a parent and children" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert_equal root, child.parent
    assert_includes root.children, child
  end

  test "only one page may have no parent" do
    Page.create!(page_type: :standard, title: "Home", slug: "")
    second_root = Page.new(page_type: :standard, title: "Also Home", slug: "also-home")

    assert_not second_root.valid?
    assert_includes second_root.errors[:base], "a root page already exists"
  end

  test "slug is unique among siblings, scoped to locale" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    duplicate = Page.new(page_type: :standard, title: "Also About", slug: "about", parent: root)

    assert_not duplicate.valid?
  end

  test "the same slug is allowed under a different parent" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section_a = Page.create!(page_type: :standard, title: "Section A", slug: "section-a", parent: root)
    section_b = Page.create!(page_type: :standard, title: "Section B", slug: "section-b", parent: root)
    Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section_a)
    other_team = Page.new(page_type: :standard, title: "Team", slug: "team", parent: section_b)

    assert other_team.valid?
  end

  test "a page with children cannot be destroyed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert_not root.destroy
    assert_includes root.errors[:base], "cannot delete a page that still has children"
    assert Page.exists?(root.id)
  end

  test "a childless page can be destroyed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert child.destroy
  end
end
```

- [ ] **Step 5: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/page_test.rb
```

Expected: FAIL with `uninitialized constant Page`.

- [ ] **Step 6: Implement the model**

`app/models/page.rb` — use the exact closure_tree macro/options
found in Step 1 for the tree declaration, plus:

```ruby
class Page < ApplicationRecord
  extend Mobility
  translates :title, :slug, :subtitle, :meta_title, :meta_description, backend: :jsonb

  has_one_attached :hero_image

  enum :page_type, { standard: 0, landing: 1 }

  validates :title, presence: true
  validate :only_one_root_page, on: :create
  validate :slug_unique_among_siblings
  before_destroy :ensure_no_children

  private

  def only_one_root_page
    if parent_id.nil? && Page.where(parent_id: nil).exists?
      errors.add(:base, "a root page already exists")
    end
  end

  def slug_unique_among_siblings
    scope = Page.where(parent_id: parent_id)
    scope = scope.where.not(id: id) if persisted?
    if scope.to_a.any? { |sibling| sibling.slug == slug }
      errors.add(:slug, "has already been taken among sibling pages")
    end
  end

  def ensure_no_children
    if children.any?
      errors.add(:base, "cannot delete a page that still has children")
      throw :abort
    end
  end
end
```

Adjust the tree declaration line (`has_closure_tree` or whatever
Step 1 found) to sit above `enum :page_type, ...`, and adjust
`slug_unique_among_siblings`'s iteration if closure_tree's `children`
accessor works differently than assumed above — the requirement is:
compare against each sibling's *translated* slug in the current
locale, not a raw DB column comparison, since `slug` is now
Mobility-backed.

- [ ] **Step 7: Run tests to verify they pass**

```bash
bin/rails test test/models/page_test.rb
```

Expected: PASS.

- [ ] **Step 8: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS, no regressions.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add Page tree model

closure_tree-backed hierarchy, translatable title/slug/subtitle/meta
fields, single-root and childless-destroy-only validations, per
page-tree design spec section 3.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 3: Per-locale cached page paths

**Files:**
- Create: `db/migrate/<timestamp>_add_cached_paths_to_pages.rb`
- Modify: `app/models/page.rb`
- Test: `test/models/page_test.rb` (extended)

**Interfaces:**
- Consumes: `Page`'s tree/ancestor accessors from Task 2.
- Produces: `Page#full_path(locale)` returning the page's complete
  URL path (e.g. `/about/team`) in the given locale, backed by a
  `cached_paths` jsonb column (`{"en" => "/about/team", "de" =>
  "/ueber-uns/team"}`) recomputed whenever the page's own slug or
  parent changes. `Page.find_by_full_path(locale, path)` is the
  lookup Task 5's router uses.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration AddCachedPathsToPages
```

```ruby
class AddCachedPathsToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :cached_paths, :jsonb, null: false, default: {}
  end
end
```

- [ ] **Step 2: Write the failing tests**

Add to `test/models/page_test.rb`:

```ruby
test "full_path is computed from the page's own slug for a root page" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "")

  assert_equal "/", root.full_path(:en)
end

test "full_path concatenates ancestor slugs" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "")
  section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
  leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

  assert_equal "/about/team", leaf.full_path(:en)
end

test "full_path differs per locale when slugs are translated" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "")
  page = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
  Mobility.with_locale(:de) { page.update!(title: "Ueber uns", slug: "ueber-uns") }

  assert_equal "/about", page.full_path(:en)
  assert_equal "/ueber-uns", page.full_path(:de)
end

test "find_by_full_path locates the matching page" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "")
  page = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

  assert_equal page, Page.find_by_full_path(:en, "/about")
  assert_nil Page.find_by_full_path(:en, "/does-not-exist")
end

test "updating a slug recomputes cached_paths for the page and its descendants" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "")
  section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
  leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

  section.update!(slug: "company")

  assert_equal "/company", section.reload.full_path(:en)
  assert_equal "/company/team", leaf.reload.full_path(:en)
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/page_test.rb
```

Expected: FAIL — `full_path`/`find_by_full_path` don't exist yet.

- [ ] **Step 4: Implement path computation**

Add to `app/models/page.rb`:

```ruby
after_save :recompute_cached_paths, if: :saved_change_to_slug_or_parent?

def full_path(locale)
  cached_paths.fetch(locale.to_s) { compute_full_path(locale) }
end

def self.find_by_full_path(locale, path)
  find { |page| page.full_path(locale) == path } # placeholder shape — replace below
end
```

Replace that placeholder `find_by_full_path` body with a real
implementation: recomputing `full_path` for every `Page` to find a
match does not scale and is not what "Produces" above promises.
Instead, query directly against the `cached_paths` jsonb column for
the given locale key equal to `path` (e.g. `Page.where("cached_paths
->> ? = ?", locale.to_s, path).first`), relying on the cache this
task maintains rather than recomputing on every lookup. Implement
`compute_full_path(locale)` by walking `self_and_ancestors` (or
whatever closure_tree's ancestor-listing accessor is, from Task 2's
Step 1 findings) in root-to-leaf order and joining their
locale-specific slugs with `/`, with the root page contributing an
empty segment (so a root's own path is `/`, and a child of root is
`/<child-slug>`, not `//<child-slug>`).

Implement `recompute_cached_paths` to compute and save `cached_paths`
for every locale in `Page.available_locales` (or however Task 1's
Mobility config exposes the configured locale list) for `self` and
every descendant (since an ancestor's slug change shifts every
descendant's path too) — using `update_columns` to avoid re-triggering
this same callback recursively.

`saved_change_to_slug_or_parent?` needs to account for `slug` being a
Mobility-backed attribute, not a plain AR column — confirm from Task
1's findings whether Mobility exposes a `saved_change_to_<attr>?`-style
method itself, or whether you need to track this manually (e.g. via
an `around_save` comparing before/after values, or a plain
`after_save` that unconditionally recomputes — simpler, and correct,
just slightly more work than strictly necessary. Prefer correctness
and simplicity here over a cleverness that might not have real
support from Mobility).

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/page_test.rb
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: cache per-locale full paths on Page

Enables O(1) path lookup for routing instead of recomputing ancestor
chains on every request, per page-tree design spec section 3.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 4: `ContentBlock` model

**Files:**
- Create: `db/migrate/<timestamp>_create_content_blocks.rb`
- Create: `app/models/content_block.rb`
- Modify: `app/models/page.rb`
- Test: `test/models/content_block_test.rb`

**Interfaces:**
- Consumes: `Page` from Tasks 2-3; `Post.content_types` (the enum
  from the Foundation plan) to validate `post_list` settings against.
- Produces: `ContentBlock` (`page_id`, `block_type` enum: `rich_text`,
  `image`, `post_list`; `position`; type-specific behavior described
  below). `Page#content_blocks` (ordered by `position`). Task 5's
  renderer iterates `page.content_blocks` and dispatches on
  `block_type`.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration CreateContentBlocks
```

```ruby
class CreateContentBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :content_blocks do |t|
      t.references :page, null: false, foreign_key: true
      t.integer :block_type, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.string :caption

      t.timestamps
    end

    add_index :content_blocks, [ :page_id, :position ]
  end
end
```

Also convert `caption` to whatever Mobility jsonb column shape Task 1
established, since it's translatable (page-tree spec §3).

- [ ] **Step 2: Write the failing tests**

`test/models/content_block_test.rb`:

```ruby
require "test_helper"

class ContentBlockTest < ActiveSupport::TestCase
  setup do
    @page = Page.create!(page_type: :standard, title: "Home", slug: "")
  end

  test "block_type is required" do
    block = ContentBlock.new(page: @page, position: 0)
    assert_not block.valid?
  end

  test "a rich_text block accepts a rich text body" do
    block = ContentBlock.create!(page: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")
    assert block.body.present?
  end

  test "an image block accepts an attached image and a caption" do
    block = ContentBlock.new(page: @page, block_type: :image, position: 0, caption: "A photo")
    block.image.attach(
      io: StringIO.new("fake image data"),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    block.save!

    assert block.image.attached?
    assert_equal "A photo", block.caption
  end

  test "a post_list block's settings content_type must be a real Post content_type" do
    block = ContentBlock.new(page: @page, block_type: :post_list, position: 0, settings: { "content_type" => "not_a_real_type" })
    assert_not block.valid?
    assert_includes block.errors[:settings], "content_type must be one of: #{Post.content_types.keys.join(', ')}"
  end

  test "a post_list block's settings content_type is accepted when valid" do
    block = ContentBlock.new(page: @page, block_type: :post_list, position: 0, settings: { "content_type" => "blog", "limit" => 5 })
    assert block.valid?
  end

  test "Page#content_blocks are ordered by position" do
    ContentBlock.create!(page: @page, block_type: :rich_text, position: 1, body: "second")
    ContentBlock.create!(page: @page, block_type: :rich_text, position: 0, body: "first")

    assert_equal [ 0, 1 ], @page.content_blocks.map(&:position)
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/content_block_test.rb
```

Expected: FAIL with `uninitialized constant ContentBlock`.

- [ ] **Step 4: Implement the model**

`app/models/content_block.rb`:

```ruby
class ContentBlock < ApplicationRecord
  extend Mobility
  translates :caption, backend: :jsonb
  translates :body, backend: :action_text # confirm exact backend call per Task 1's findings

  belongs_to :page

  enum :block_type, { rich_text: 0, image: 1, post_list: 2 }

  has_one_attached :image

  validates :block_type, presence: true
  validate :post_list_settings_reference_a_real_content_type, if: :post_list?

  private

  def post_list_settings_reference_a_real_content_type
    content_type = settings["content_type"]
    return if content_type.blank?

    unless Post.content_types.key?(content_type)
      errors.add(:settings, "content_type must be one of: #{Post.content_types.keys.join(', ')}")
    end
  end
end
```

In `app/models/page.rb`, add:

```ruby
has_many :content_blocks, -> { order(:position) }, dependent: :destroy
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/content_block_test.rb
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add ContentBlock model

Shared-shape rich_text/image/post_list blocks ordered within a Page,
matching Post's existing single-model-plus-enum pattern, per
page-tree design spec section 3.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 5: Public routing and rendering (list view)

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/pages_controller.rb`
- Create: `app/views/pages/show.html.erb`
- Create: `app/views/content_blocks/_rich_text.html.erb`
- Create: `app/views/content_blocks/_image.html.erb`
- Create: `app/views/content_blocks/_post_list.html.erb`
- Test: `test/integration/pages_routing_test.rb`

**Interfaces:**
- Consumes: `Page.find_by_full_path` (Task 3), `Page#content_blocks`
  (Task 4), `Post` (Foundation plan).
- Produces: `GET /:locale/*path` renders the matching `Page`, in
  order, as its content blocks. `GET /` (no locale prefix) redirects
  to the default locale's root. Task 6 adds the single-post-detail
  fallback on top of this controller.

- [ ] **Step 1: Write the failing tests**

`test/integration/pages_routing_test.rb`:

```ruby
require "test_helper"

class PagesRoutingTest < ActionDispatch::IntegrationTest
  test "the root page renders at the locale root" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    ContentBlock.create!(page: root, block_type: :rich_text, position: 0, body: "<p>Welcome</p>")

    get "/en/"

    assert_response :success
    assert_includes response.body, "Welcome"
  end

  test "a nested page renders at its full path" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)
    ContentBlock.create!(page: about, block_type: :rich_text, position: 0, body: "<p>About us</p>")

    get "/en/about"

    assert_response :success
    assert_includes response.body, "About us"
  end

  test "an unmatched path returns 404" do
    get "/en/does-not-exist"

    assert_response :not_found
  end

  test "a page renders its blocks in position order" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    ContentBlock.create!(page: root, block_type: :rich_text, position: 1, body: "<p>Second</p>")
    ContentBlock.create!(page: root, block_type: :rich_text, position: 0, body: "<p>First</p>")

    get "/en/"

    assert_response :success
    assert_operator response.body.index("First"), :<, response.body.index("Second")
  end

  test "a post_list block renders matching posts" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "My First Post", published_at: Time.current)

    get "/en/blog"

    assert_response :success
    assert_includes response.body, "My First Post"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/integration/pages_routing_test.rb
```

Expected: FAIL — no such routes exist yet.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `Rails.application.routes.draw`:

```ruby
get "/", to: redirect("/en/")
get ":locale/*path", to: "pages#show", constraints: { locale: /en|de|es/ }, as: :page, defaults: { path: "" }
```

Rails' glob segment (`*path`) matches an empty string when the route
declares a default for it, so `:locale/*path` with `defaults: { path:
"" }` covers both `/en/` (locale root, `path` is `""`) and
`/en/about` (`path` is `"about"`) through the single route above —
`/` itself is handled by the separate redirect. Step 6's tests
(`/en/`, `/en/about`, and a 404 case) confirm both shapes resolve
correctly; if `/en/` doesn't match as written, that failure is
exactly what Step 6 exists to catch.

- [ ] **Step 4: Implement the controller**

`app/controllers/pages_controller.rb`:

```ruby
class PagesController < ApplicationController
  allow_unauthenticated_access

  def show
    path = "/#{params[:path]}".sub(%r{/+$}, "")
    path = "/" if path.blank?

    @page = Page.find_by_full_path(params[:locale], path)

    if @page.nil?
      render plain: "Not Found", status: :not_found
      return
    end

    render :show
  end
end
```

- [ ] **Step 5: Implement the views**

`app/views/pages/show.html.erb`:

```erb
<% @page.content_blocks.each do |block| %>
  <%= render "content_blocks/#{block.block_type}", block: block %>
<% end %>
```

`app/views/content_blocks/_rich_text.html.erb`:

```erb
<div class="content-block content-block--rich-text">
  <%= block.body %>
</div>
```

`app/views/content_blocks/_image.html.erb`:

```erb
<div class="content-block content-block--image">
  <% if block.image.attached? %>
    <%= image_tag block.image %>
    <p><%= block.caption %></p>
  <% end %>
</div>
```

`app/views/content_blocks/_post_list.html.erb`:

```erb
<div class="content-block content-block--post-list">
  <% posts = Post.where(content_type: block.settings["content_type"]) %>
  <% posts = posts.where(published_at: ..Time.current).order(published_at: :desc) %>
  <% posts = posts.limit(block.settings["limit"]) if block.settings["limit"].present? %>
  <ul>
    <% posts.each do |post| %>
      <li><%= post.title %></li>
    <% end %>
  </ul>
</div>
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bin/rails test test/integration/pages_routing_test.rb
```

Expected: PASS.

- [ ] **Step 7: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: serve the Page tree via a locale-aware catch-all route

Renders a page's content_blocks in order; post_list blocks render a
filtered, published Post listing. Single-post detail resolution is
added in the next task.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 6: Single-post detail fallback

**Files:**
- Modify: `app/controllers/pages_controller.rb`
- Create: `app/views/content_blocks/_post_list_detail.html.erb`
- Test: `test/integration/pages_routing_test.rb` (extended)

**Interfaces:**
- Consumes: `PagesController#show` from Task 5.
- Produces: a path like `/:locale/blog/:post_slug` renders that
  single `Post` (found via the matching `Page`'s `post_list` block's
  `content_type`) inside the same `Page`'s layout, in place of the
  list.

- [ ] **Step 1: Write the failing tests**

Add to `test/integration/pages_routing_test.rb`:

```ruby
test "a trailing slug that matches a post under a post_list block renders that post's detail view" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
  ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
  post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>", published_at: Time.current)

  get "/en/blog/#{post.slug}"

  assert_response :success
  assert_includes response.body, "Full post content"
  assert_not_includes response.body, "<ul>" # the list markup shouldn't also render
end

test "a trailing segment that matches no post under a post_list block, and no Page, is 404" do
  root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)

  get "/en/blog/no-such-post"

  assert_response :not_found
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/integration/pages_routing_test.rb
```

Expected: FAIL — the new "detail" test 404s where it should render,
and the exact-match `blog_page` has no `post_list` block in the first
new test until you add one (it does above) — confirm the failure is
the fallback logic not existing yet, not a test-setup mistake.

- [ ] **Step 3: Implement the fallback**

Modify `app/controllers/pages_controller.rb`:

```ruby
class PagesController < ApplicationController
  allow_unauthenticated_access

  def show
    path = "/#{params[:path]}".sub(%r{/+$}, "")
    path = "/" if path.blank?

    @page = Page.find_by_full_path(params[:locale], path)

    if @page
      render :show
      return
    end

    parent_path, _, candidate_slug = path.rpartition("/")
    parent_path = "/" if parent_path.blank?

    @page = Page.find_by_full_path(params[:locale], parent_path)
    post_list_block = @page&.content_blocks&.find_by(block_type: :post_list)

    if post_list_block
      @post = Post.where(content_type: post_list_block.settings["content_type"])
                  .where(published_at: ..Time.current)
                  .find { |p| p.slug == candidate_slug }
    end

    if @post
      @post_list_block = post_list_block
      render :show
    else
      render plain: "Not Found", status: :not_found
    end
  end
end
```

Update `app/views/pages/show.html.erb` so a `post_list` block renders
its normal list partial unless `@post` is set for **this specific
block** (the block that matched), in which case it renders a detail
partial instead:

```erb
<% @page.content_blocks.each do |block| %>
  <% if @post && block == @post_list_block %>
    <%= render "content_blocks/post_list_detail", post: @post %>
  <% else %>
    <%= render "content_blocks/#{block.block_type}", block: block %>
  <% end %>
<% end %>
```

`app/views/content_blocks/_post_list_detail.html.erb`:

```erb
<article class="content-block content-block--post-list-detail">
  <h1><%= post.title %></h1>
  <%= post.body %>
</article>
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/integration/pages_routing_test.rb
```

Expected: PASS.

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: resolve individual post permalinks through their listing page

No Page node per Post — a post_list block's own Page serves both the
list and each post's detail view, per page-tree design spec section 4.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 7: Avo admin for `Page` and `ContentBlock`

**Files:**
- Create: (generated) `app/avo/resources/page.rb`
- Create: (generated) `app/controllers/avo/pages_controller.rb`
- Test: `test/integration/avo_access_test.rb` (extended)

**Interfaces:**
- Consumes: `Page`/`ContentBlock` from Tasks 2-4; the existing Avo
  auth wiring and `Post` resource pattern from the Foundation plan.
- Produces: `/avo/resources/pages` lets the signed-in admin create
  pages, set a parent (building the tree), pick `page_type`, edit the
  translatable fields, and add/reorder/remove `ContentBlock`s inline.

- [ ] **Step 1: Look up current Avo docs for what this task needs**

Via `context7` or the installed gem's source, confirm the current
Avo 4.2.3 way to: (a) show a `belongs_to`/select field for a
self-referential association (`Page#parent`) restricted to not
include the page itself as an option; (b) show/hide fields
conditionally based on another field's value (`subtitle`/`hero_image`
only when `page_type: landing`); (c) edit a `has_many` association's
records inline within the parent's form (for `content_blocks`), with
reordering.

- [ ] **Step 2: Generate the resource**

```bash
bin/rails generate avo:resource Page
```

- [ ] **Step 3: Configure the resource**

Using the current APIs found in Step 1, edit
`app/avo/resources/page.rb` so it exposes: `parent` (a select of
other pages, excluding `self`), `page_type`, `title`/`slug` (with
locale switching, matching how Task 1 set up `Post`'s translated
fields in Avo), `subtitle`/`hero_image` shown only for
`page_type: landing`, `meta_title`/`meta_description`,
`published_at`, and an inline/nested editor for `content_blocks`
(add, reorder via `position`, remove — each block's `block_type` and
its type-specific fields visible in the nested form).

- [ ] **Step 4: Write the request tests**

Add to `test/integration/avo_access_test.rb` (following that file's
existing sign-in helper pattern):

```ruby
test "an authenticated user can view and create a Page" do
  sign_in_as(users(:one)) # or however the existing tests establish an authenticated session — match the existing pattern in this file exactly

  get "/avo/resources/pages"
  assert_response :success

  get "/avo/resources/pages/new"
  assert_response :success
end

test "an authenticated user can add a content block to a page through Avo" do
  sign_in_as(users(:one))
  page = Page.create!(page_type: :standard, title: "Home", slug: "")

  # Exercise whatever the actual generated nested-association endpoint is
  # for adding a ContentBlock to this Page from Step 1/3's findings —
  # write this against the real route Avo generates, not a guess.
end
```

Fill in the second test's body once Step 1/3 show you the actual
route/params shape Avo's nested editor submits to.

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/integration/avo_access_test.rb
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add Avo admin for the Page tree and content blocks

Parent picker, conditional hero fields, and inline content-block
editing, per page-tree design spec section 5.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 8: SEO tags and sitemap

**Files:**
- Modify: `app/views/pages/show.html.erb` (or extract a layout/head
  partial if that file is getting large)
- Modify: `Gemfile`
- Create: `config/sitemap.rb`
- Test: `test/integration/pages_routing_test.rb` (extended)
- Test: `test/lib/sitemap_test.rb` (or wherever `sitemap_generator`'s
  own testing convention points — confirm via its docs)

**Interfaces:**
- Consumes: `Page#meta_title`/`#meta_description`/`#title` (Task 2),
  `Page.find_by_full_path` and the tree (Tasks 2-3).
- Produces: every page response includes a `<title>`, meta
  description, and Open Graph tags derived from the `Page`; a
  generated `sitemap.xml` lists every published `Page`'s path across
  all three locales.

- [ ] **Step 1: Write the failing test for meta tags**

Add to `test/integration/pages_routing_test.rb`:

```ruby
test "a page's meta_title and meta_description render in the head" do
  root = Page.create!(
    page_type: :standard,
    title: "Home",
    slug: "",
    meta_title: "ContentSpiel — Home",
    meta_description: "The personal site of a software developer.",
    published_at: Time.current
  )

  get "/en/"

  assert_response :success
  assert_includes response.body, "<title>ContentSpiel — Home</title>"
  assert_includes response.body, %(<meta name="description" content="The personal site of a software developer.")
end

test "meta_title falls back to the page's title when blank" do
  Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

  get "/en/"

  assert_includes response.body, "<title>Home</title>"
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/integration/pages_routing_test.rb
```

Expected: FAIL — no meta tags rendered yet.

- [ ] **Step 3: Add the meta tags**

Add a `<title>`/meta-description/OG helper to
`app/views/pages/show.html.erb`'s surrounding layout (or a
`content_for` block the application layout yields), computing from
`@page.meta_title.presence || @page.title` and
`@page.meta_description`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/integration/pages_routing_test.rb
```

Expected: PASS.

- [ ] **Step 5: Install and configure sitemap_generator**

Look up `sitemap_generator`'s current setup docs (via context7 or the
gem's own README) for: the install generator, `config/sitemap.rb`'s
expected format, and its own recommended testing approach.

```bash
bundle add sitemap_generator
bin/rails sitemap:install # or whatever the current generator command is
```

Configure `config/sitemap.rb` to walk `Page.all` (published pages
only — `where(published_at: ..Time.current)`), adding each page's
`full_path` for every locale in `Page.available_locales`.

- [ ] **Step 6: Write a test proving the sitemap includes a page's paths**

Follow `sitemap_generator`'s own recommended test approach (found in
Step 5) to write a test that generates the sitemap for a small set of
pages and asserts each published page's per-locale path is present,
and an unpublished page's path is absent.

- [ ] **Step 7: Run tests to verify they pass**

Run whatever command Step 6's approach specifies.

Expected: PASS.

- [ ] **Step 8: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add per-page SEO meta tags and sitemap generation

Meta title/description/OG tags driven by Page fields; sitemap.xml
walks the published Page tree across all locales, per the original
spec's SEO section and page-tree design spec section 7.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## What's next

This plan covers the page-tree design spec in full (§3-§9) plus the
original spec's deferred i18n commitment (§12). Remaining from the
Foundation plan's original roadmap: rich embeds (YouTube/PDF — a
natural fit as `rich_text` block content once this plan's
`ContentBlock` exists), the admin mind-graph view, the MCP server, and
the setup wizard.

## Self-review notes

- **Spec coverage:** Task 1 covers the original spec's i18n
  commitment; Tasks 2-3 cover page-tree spec §3 (Page); Task 4 covers
  §3 (ContentBlock); Tasks 5-6 cover §4 (routing, including the
  list/detail fallback); Task 7 covers §5 (Avo); Task 8 covers §7
  (SEO) and the sitemap half of §7. §8 (error handling) is covered
  across Tasks 2 (root singleton, destroy guard) and 5 (404s). §9
  (testing) is satisfied by each task's own tests. §10 (out of scope)
  is respected — no drag-and-drop tree UI, no page versioning, no
  multi-root support anywhere in this plan.
- **Placeholder scan:** every step has real code or an explicit,
  narrowly-scoped "verify via current docs" instruction (Mobility,
  closure_tree, Avo-Mobility integration) — each of those still states
  the exact required behavior and test, matching how the Foundation
  plan's Avo task handled the same kind of version-sensitive
  uncertainty. Task 3's `find_by_full_path` step explicitly flags and
  replaces its own initial placeholder-shaped sketch with a real
  requirement, rather than leaving it as the final answer.
- **Type/name consistency:** `Page#full_path`, `Page.find_by_full_path`,
  `Page#content_blocks`, `ContentBlock#block_type`/`#settings`, and
  `Post.content_types` are used identically everywhere they appear
  across tasks.
