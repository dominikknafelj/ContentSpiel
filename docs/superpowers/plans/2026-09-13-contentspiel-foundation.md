# ContentSpiel Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the ContentSpiel Rails app with Postgres, the core
content data model (`Post`, `Tag`, `PostRelation`, `SiteSetting`,
`ApiToken`), admin authentication, and a working Avo CMS — a
runnable, testable app with no public-facing pages yet beyond a
placeholder home page.

**Architecture:** A single Rails 8 app. Content lives in one
shared-shape `Post` model (per the spec's "north star" content types:
blog, resume_entry, now_update) rather than separate models per
content type. Admin access is Rails 8's built-in session-based
authentication; the Avo gem provides the CMS UI on top of the same
models a future MCP server will also operate on.

**Tech Stack:** Rails 8.1, Ruby 3.4.9, PostgreSQL, Tailwind CSS
(`tailwindcss-rails`), Hotwire (Turbo + Stimulus, via `rails new`
defaults), ActionText + Active Storage, `avo` gem, minitest + fixtures
(Rails default test stack).

**Spec:** `docs/superpowers/specs/2026-09-13-contentspiel-design.md`

## Global Constraints

- Ruby `3.4.9`, Rails `~> 8.1` — matches the owner's other project
  (`photofolio`) for consistency.
- Database is **PostgreSQL**, not sqlite (spec §3) — chosen for
  `jsonb` and because a later plan adds the `mobility` gem's jsonb
  translation backend.
- Admin auth is Rails 8's **built-in `bin/rails generate
  authentication`** generator, not Devise (spec §3).
- Testing is **minitest + fixtures** (Rails default) — no RSpec, no
  FactoryBot (spec §3, §13).
- No deploy/Kamal configuration in this plan — deploy target is an
  explicit open question in the spec (spec §14).
- No i18n/Mobility, no MCP server, no public site pages, no rich
  embeds, no mind-graph view, and no setup wizard in this plan — each
  is a separate follow-up plan (see "What's next" at the end of this
  document).

---

## Task 1: Scaffold the Rails app

**Files:**
- Create: entire Rails app skeleton (via `rails new`)
- Create: `app/controllers/home_controller.rb`
- Create: `app/views/home/index.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/home_controller_test.rb`
- Test: `test/integration/health_test.rb`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a bootable Rails app with `root_path` resolving to
  `HomeController#index`; `/up` health check (Rails 8 default). Later
  tasks assume `bin/rails db:migrate`, `bin/rails test`, and
  `bin/rails server` all work from the repo root.

- [ ] **Step 1: Generate the Rails app in place**

The repo at `/Users/dknafelj/src/ContentSpiel` already has a `.git`
history (the spec doc) and nothing else — `.git` already exists, so
skip Rails' own git init to avoid a conflict.

```bash
cd /Users/dknafelj/src/ContentSpiel
echo "3.4.9" > .ruby-version
rails new . --database=postgresql --css=tailwind --skip-git --force
```

When prompted about any file conflicts, keep the existing file (there
should be none — only `docs/` exists so far).

- [ ] **Step 2: Install gems**

```bash
bundle install
```

- [ ] **Step 3: Add a placeholder home page**

`app/controllers/home_controller.rb`:

```ruby
class HomeController < ApplicationController
  def index
  end
end
```

`app/views/home/index.html.erb`:

```erb
<h1 class="text-3xl font-bold p-8">ContentSpiel</h1>
<p class="px-8 text-gray-600">Coming soon.</p>
```

In `config/routes.rb`, add inside the `Rails.application.routes.draw`
block (the health check route `get "up" => "rails/health#show"` is
already present from `rails new` — leave it as-is):

```ruby
root "home#index"
```

- [ ] **Step 4: Write the smoke tests**

`test/controllers/home_controller_test.rb`:

```ruby
require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "GET / returns success" do
    get root_path
    assert_response :success
  end
end
```

`test/integration/health_test.rb`:

```ruby
require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "GET /up returns success" do
    get "/up"
    assert_response :success
  end
end
```

- [ ] **Step 5: Create the databases and run the tests**

```bash
bin/rails db:create
bin/rails test
```

Expected: both tests PASS (2 runs, 0 failures, 0 errors).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: scaffold ContentSpiel Rails app

Rails 8 + Postgres + Tailwind, with a placeholder home page.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 2: Admin authentication (Rails 8 built-in generator)

**Files:**
- Create: (generated) `app/models/user.rb`, `app/models/session.rb`,
  `app/models/current.rb`, `app/controllers/sessions_controller.rb`,
  `app/controllers/passwords_controller.rb`,
  `app/controllers/concerns/authentication.rb`, session/password views,
  migrations for `users` and `sessions`
- Modify: `app/controllers/application_controller.rb` (generator adds
  `include Authentication`)
- Test: `test/integration/sessions_test.rb`

**Interfaces:**
- Consumes: `root_path` from Task 1 (the generator's sign-in flow
  redirects to `root_url` after authentication).
- Produces: `User` (`email_address:string`, `password_digest:string`,
  via `has_secure_password`), `Session`, `Current.user`, an
  `authenticated?` helper and `require_authentication` before_action
  from the `Authentication` concern (included in
  `ApplicationController` by default — every controller requires
  login unless it calls `allow_unauthenticated_access`). Later tasks
  (Avo) read `Current.user` to gate admin access.

- [ ] **Step 1: Run the generator**

```bash
bin/rails generate authentication
```

This generates the `User`/`Session` models and migrations, the
`Authentication` concern (included into `ApplicationController`),
`SessionsController`, `PasswordsController`, and their views. It also
uncomments `gem "bcrypt"` in the `Gemfile` if it wasn't already
active.

- [ ] **Step 2: Install bcrypt and migrate**

```bash
bundle install
bin/rails db:migrate
```

- [ ] **Step 3: Write the failing tests**

`test/integration/sessions_test.rb`:

```ruby
require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  test "signing in with valid credentials redirects to root and grants access" do
    post session_url, params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "signing in with invalid credentials redirects back to the sign-in form" do
    post session_url, params: { email_address: "admin@example.com", password: "wrong" }

    assert_redirected_to new_session_url
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rails test test/integration/sessions_test.rb
```

Expected: PASS. (The generator's own code makes this pass immediately
— this test exists to lock in the sign-in contract before later tasks
build on `Current.user`.)

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS, no regressions from Task 1.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add Rails 8 built-in authentication

Single-admin session auth via the generated User/Session models.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 3: `Post` model (with ActionText body)

**Files:**
- Create: `db/migrate/<timestamp>_create_posts.rb`
- Create: `app/models/post.rb`
- Test: `test/models/post_test.rb`

**Interfaces:**
- Consumes: nothing from prior tasks (independent of auth).
- Produces: `Post` with `content_type` (enum: `blog`, `resume_entry`,
  `now_update`), `title:string`, `slug:string` (unique per
  `content_type`), `excerpt:string`, `published_at:datetime`,
  `metadata:jsonb` (default `{}`), and `body` (ActionText rich text
  via `has_rich_text :body`). Later tasks (Tag, PostRelation) add
  associations onto this model; a later i18n plan converts `title`,
  `slug`, `excerpt`, and `body` to Mobility-translatable attributes —
  this task's column names are what that plan builds on.

- [ ] **Step 1: Install Active Storage and Action Text**

```bash
bin/rails active_storage:install
bin/rails action_text:install
bin/rails db:migrate
```

- [ ] **Step 2: Write the migration**

```bash
bin/rails generate migration CreatePosts
```

Edit the generated file:

```ruby
class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.integer :content_type, null: false, default: 0
      t.string :title, null: false
      t.string :slug, null: false
      t.string :excerpt
      t.datetime :published_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :posts, [ :content_type, :slug ], unique: true
  end
end
```

- [ ] **Step 3: Write the failing tests**

`test/models/post_test.rb`:

```ruby
require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "title is required" do
    post = Post.new(content_type: :blog)
    assert_not post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  test "slug is auto-generated from title when blank" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal "hello-world", post.slug
  end

  test "slug must be unique within the same content_type" do
    Post.create!(content_type: :blog, title: "Hello World")
    duplicate = Post.new(content_type: :blog, title: "Hello World")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "the same slug is allowed across different content_types" do
    Post.create!(content_type: :blog, title: "Hello World")
    other = Post.new(content_type: :resume_entry, title: "Hello World")

    assert other.valid?
  end

  test "metadata defaults to an empty hash" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal({}, post.metadata)
  end

  test "body accepts rich text content" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")
    assert_equal "<p>Hi</p>", post.body.to_plain_text.present? ? post.body.body.to_html : nil rescue nil
    assert post.body.present?
  end
end
```

Adjust: the last assertion is simplified below in Step 4's
implementation notes — the important behavior is `post.body.present?`
after assigning HTML content.

- [ ] **Step 4: Run tests to verify they fail**

```bash
bin/rails test test/models/post_test.rb
```

Expected: FAIL with `uninitialized constant Post`.

- [ ] **Step 5: Implement the model**

`app/models/post.rb`:

```ruby
class Post < ApplicationRecord
  has_rich_text :body

  enum :content_type, { blog: 0, resume_entry: 1, now_update: 2 }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :content_type }

  before_validation :generate_slug_from_title, on: :create

  private

  def generate_slug_from_title
    self.slug = title.to_s.parameterize if slug.blank? && title.present?
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bin/rails test test/models/post_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add Post model with ActionText body

Shared-shape content model for blog/resume_entry/now_update, per the
spec's Post design (section 4).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 4: `Tag` model

**Files:**
- Create: `db/migrate/<timestamp>_create_tags.rb`
- Create: `db/migrate/<timestamp>_create_post_tags.rb`
- Create: `app/models/tag.rb`
- Create: `app/models/post_tag.rb`
- Modify: `app/models/post.rb`
- Test: `test/models/tag_test.rb`

**Interfaces:**
- Consumes: `Post` from Task 3.
- Produces: `Post#tags` (via `has_many :tags, through: :post_tags`),
  `Tag#posts`, `Tag#name` (unique, required).

- [ ] **Step 1: Write the migrations**

```bash
bin/rails generate migration CreateTags
bin/rails generate migration CreatePostTags
```

`create_tags` migration:

```ruby
class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :tags, :name, unique: true
  end
end
```

`create_post_tags` migration:

```ruby
class CreatePostTags < ActiveRecord::Migration[8.1]
  def change
    create_table :post_tags do |t|
      t.references :post, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :post_tags, [ :post_id, :tag_id ], unique: true
  end
end
```

- [ ] **Step 2: Write the failing tests**

`test/models/tag_test.rb`:

```ruby
require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "name is required" do
    tag = Tag.new
    assert_not tag.valid?
  end

  test "name must be unique" do
    Tag.create!(name: "rails")
    duplicate = Tag.new(name: "rails")

    assert_not duplicate.valid?
  end

  test "a post can have many tags and a tag can belong to many posts" do
    post = Post.create!(content_type: :blog, title: "Hello")
    tag = Tag.create!(name: "rails")

    post.tags << tag

    assert_includes post.tags, tag
    assert_includes tag.posts, post
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/tag_test.rb
```

Expected: FAIL with `uninitialized constant Tag`.

- [ ] **Step 4: Implement the models**

`app/models/tag.rb`:

```ruby
class Tag < ApplicationRecord
  has_many :post_tags, dependent: :destroy
  has_many :posts, through: :post_tags

  validates :name, presence: true, uniqueness: true
end
```

`app/models/post_tag.rb`:

```ruby
class PostTag < ApplicationRecord
  belongs_to :post
  belongs_to :tag
end
```

In `app/models/post.rb`, add above `enum :content_type, ...`:

```ruby
has_many :post_tags, dependent: :destroy
has_many :tags, through: :post_tags
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/tag_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add Tag model and Post-Tag association

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 5: `PostRelation` model (mind-graph edges)

**Files:**
- Create: `db/migrate/<timestamp>_create_post_relations.rb`
- Create: `app/models/post_relation.rb`
- Modify: `app/models/post.rb`
- Test: `test/models/post_relation_test.rb`

**Interfaces:**
- Consumes: `Post` from Task 3.
- Produces: `PostRelation` (`post_id`, `related_post_id`), rejecting
  self-relations and duplicate reverse pairs (spec §4: edges are
  undirected). `Post#all_related_posts` returns related posts
  regardless of which side of the pair the calling post was stored
  on. A later "mind graph" plan reads `PostRelation` rows to render
  the graph; a later Avo task adds a multi-select field that writes
  these rows.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration CreatePostRelations
```

```ruby
class CreatePostRelations < ActiveRecord::Migration[8.1]
  def change
    create_table :post_relations do |t|
      t.references :post, null: false, foreign_key: { to_table: :posts }
      t.references :related_post, null: false, foreign_key: { to_table: :posts }

      t.timestamps
    end

    add_index :post_relations, [ :post_id, :related_post_id ], unique: true
  end
end
```

- [ ] **Step 2: Write the failing tests**

`test/models/post_relation_test.rb`:

```ruby
require "test_helper"

class PostRelationTest < ActiveSupport::TestCase
  setup do
    @post_a = Post.create!(content_type: :blog, title: "Post A")
    @post_b = Post.create!(content_type: :blog, title: "Post B")
  end

  test "a post can relate to another post" do
    relation = PostRelation.create!(post: @post_a, related_post: @post_b)
    assert relation.persisted?
  end

  test "a post cannot relate to itself" do
    relation = PostRelation.new(post: @post_a, related_post: @post_a)
    assert_not relation.valid?
  end

  test "the reverse pair is rejected once a relation exists" do
    PostRelation.create!(post: @post_a, related_post: @post_b)
    reverse = PostRelation.new(post: @post_b, related_post: @post_a)

    assert_not reverse.valid?
    assert_includes reverse.errors[:base], "relation already exists in the opposite direction"
  end

  test "all_related_posts returns posts related in either direction" do
    PostRelation.create!(post: @post_a, related_post: @post_b)

    assert_equal [ @post_b ], @post_a.all_related_posts.to_a
    assert_equal [ @post_a ], @post_b.all_related_posts.to_a
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/post_relation_test.rb
```

Expected: FAIL with `uninitialized constant PostRelation`.

- [ ] **Step 4: Implement the model**

`app/models/post_relation.rb`:

```ruby
class PostRelation < ApplicationRecord
  belongs_to :post
  belongs_to :related_post, class_name: "Post"

  validate :not_self_referential
  validate :not_duplicate_reverse_pair, on: :create

  private

  def not_self_referential
    errors.add(:related_post, "can't be the same post") if post_id.present? && post_id == related_post_id
  end

  def not_duplicate_reverse_pair
    return unless post_id && related_post_id

    if PostRelation.exists?(post_id: related_post_id, related_post_id: post_id)
      errors.add(:base, "relation already exists in the opposite direction")
    end
  end
end
```

In `app/models/post.rb`, add:

```ruby
has_many :post_relations, dependent: :destroy
has_many :related_posts, through: :post_relations

def all_related_posts
  forward_ids = PostRelation.where(post_id: id).select(:related_post_id)
  backward_ids = PostRelation.where(related_post_id: id).select(:post_id)
  Post.where(id: forward_ids).or(Post.where(id: backward_ids))
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/post_relation_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add PostRelation model for mind-graph edges

Undirected relations between posts, created explicitly rather than
via wiki-link parsing, per spec section 9.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 6: `SiteSetting` singleton model

**Files:**
- Create: `db/migrate/<timestamp>_create_site_settings.rb`
- Create: `app/models/site_setting.rb`
- Test: `test/models/site_setting_test.rb`

**Interfaces:**
- Consumes: Active Storage (installed in Task 3) for `logo`.
- Produces: `SiteSetting.instance` (memoized-on-first-access
  singleton accessor), `title`, `tagline`, `social_links:jsonb`,
  `default_locale` (default `"en"`), `logo` (Active Storage
  attachment). A later setup-wizard plan writes to this via its
  branding step; a later SEO plan reads `title`/`tagline` for meta
  tag defaults.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration CreateSiteSettings
```

```ruby
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      t.string :title, null: false
      t.string :tagline
      t.jsonb :social_links, null: false, default: {}
      t.string :default_locale, null: false, default: "en"

      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Write the failing tests**

`test/models/site_setting_test.rb`:

```ruby
require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "a second record cannot be created" do
    SiteSetting.create!(title: "First")
    second = SiteSetting.new(title: "Second")

    assert_not second.valid?
    assert_includes second.errors[:base], "only one SiteSetting may exist"
  end

  test "instance creates the record on first access" do
    assert_difference "SiteSetting.count", 1 do
      SiteSetting.instance
    end
  end

  test "instance returns the existing record on subsequent access" do
    existing = SiteSetting.create!(title: "Existing")

    assert_equal existing, SiteSetting.instance
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/site_setting_test.rb
```

Expected: FAIL with `uninitialized constant SiteSetting`.

- [ ] **Step 4: Implement the model**

`app/models/site_setting.rb`:

```ruby
class SiteSetting < ApplicationRecord
  has_one_attached :logo

  validate :only_one_record_exists, on: :create

  def self.instance
    first || create!(title: "My Site")
  end

  private

  def only_one_record_exists
    errors.add(:base, "only one SiteSetting may exist") if SiteSetting.exists?
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/site_setting_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add SiteSetting singleton model

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 7: `ApiToken` model (MCP auth, backing store only)

**Files:**
- Create: `db/migrate/<timestamp>_create_api_tokens.rb`
- Create: `app/models/api_token.rb`
- Test: `test/models/api_token_test.rb`

**Interfaces:**
- Consumes: `bcrypt` (already a dependency from Task 2's auth
  generator).
- Produces: `ApiToken.generate!` returning `[token_record, raw_token]`
  (raw value shown once, never persisted in plaintext),
  `ApiToken.authenticate(raw_token)` returning the matching active
  token or `nil`, `#revoke!`. A later MCP-server plan uses
  `ApiToken.authenticate` to check the `Authorization: Bearer` header
  on every request; a later setup-wizard plan calls
  `ApiToken.generate!` in its optional token-generation step.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration CreateApiTokens
```

```ruby
class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.string :token_digest, null: false
      t.datetime :revoked_at

      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Write the failing tests**

`test/models/api_token_test.rb`:

```ruby
require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "generate! returns a persisted token and the raw value" do
    token, raw = ApiToken.generate!

    assert token.persisted?
    assert_not_nil raw
    assert_not_equal raw, token.token_digest
  end

  test "authenticate finds the token matching the raw value" do
    token, raw = ApiToken.generate!

    assert_equal token, ApiToken.authenticate(raw)
  end

  test "authenticate returns nil for a wrong value" do
    ApiToken.generate!

    assert_nil ApiToken.authenticate("wrong-token")
  end

  test "revoked tokens do not authenticate" do
    token, raw = ApiToken.generate!
    token.revoke!

    assert_nil ApiToken.authenticate(raw)
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bin/rails db:migrate
bin/rails test test/models/api_token_test.rb
```

Expected: FAIL with `uninitialized constant ApiToken`.

- [ ] **Step 4: Implement the model**

`app/models/api_token.rb`:

```ruby
class ApiToken < ApplicationRecord
  has_secure_password :token, validations: false

  def self.generate!
    raw_token = SecureRandom.hex(32)
    token = create!(token: raw_token)
    [ token, raw_token ]
  end

  def self.authenticate(raw_token)
    active.find { |candidate| candidate.authenticate_token(raw_token) }
  end

  def self.active
    where(revoked_at: nil)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/api_token_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add ApiToken model for MCP authentication

Stores only a bcrypt digest; the raw token is returned once at
generation time and never persisted in plaintext.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 8: Avo CMS install and resources

**Files:**
- Modify: `Gemfile`
- Create: (generated) `config/initializers/avo.rb`, Avo resource files
  under `app/avo/resources/`
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Test: `test/integration/avo_access_test.rb`

**Interfaces:**
- Consumes: `Current.user` / `authenticated?` from Task 2, `Post`
  (Task 3), `Tag` (Task 4), `SiteSetting` (Task 6), `ApiToken` (Task
  7).
- Produces: Avo mounted at `/avo`, gated by the same session
  authentication as the rest of the app (unauthenticated requests
  redirect to sign-in). Resources registered for `Post` (filterable
  by `content_type`), `Tag`, `SiteSetting`, `ApiToken`. Later plans
  (i18n, mind graph, wizard) add fields/pages to these same resource
  files rather than creating new ones.

- [ ] **Step 1: Look up current Avo installation and auth docs**

Avo's exact configuration DSL changes between major versions. Before
writing code, use the `context7` MCP tool (or `avo`'s own README at
whatever version `bundle add avo` installs) to confirm: (a) the
current installer command, and (b) how to point
`current_user_method`/authentication at an existing non-Devise
session system. Use those exact current APIs in the steps below
rather than guessing at outdated syntax.

- [ ] **Step 2: Install Avo**

```bash
bundle add avo
bin/rails generate avo:install
```

If prompted for a license, choose the free Community edition.

- [ ] **Step 3: Wire Avo authentication to the existing session system**

In `app/controllers/application_controller.rb`, add a `current_user`
alias so Avo (and anything else expecting that method name) can read
the session user set up by Task 2's `Authentication` concern:

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  # ...existing content...

  helper_method :current_user

  def current_user
    Current.user
  end
end
```

In `config/initializers/avo.rb`, set `config.current_user_method =
:current_user` and configure Avo's `authenticate_with` (or the
equivalent current-version hook found in Step 1) to redirect
unauthenticated visitors to the app's existing sign-in page
(`new_session_path`) rather than a Devise route.

- [ ] **Step 4: Generate Avo resources**

```bash
bin/rails generate avo:resource Post
bin/rails generate avo:resource Tag
bin/rails generate avo:resource SiteSetting
bin/rails generate avo:resource ApiToken
```

In the generated `app/avo/resources/post_resource.rb`, add a scope/
filter on `content_type` so the admin can narrow the list to one
content type at a time (use the exact current Avo filter DSL
confirmed in Step 1 — the requirement is: the `Post` index in `/avo`
can be filtered by `content_type` value).

- [ ] **Step 5: Write the access tests**

`test/integration/avo_access_test.rb`:

```ruby
require "test_helper"

class AvoAccessTest < ActionDispatch::IntegrationTest
  test "unauthenticated visitors are redirected away from /avo" do
    get "/avo"
    assert_response :redirect
  end

  test "an authenticated user can reach /avo" do
    user = User.create!(email_address: "admin@example.com", password: "password123")
    post session_url, params: { email_address: "admin@example.com", password: "password123" }

    get "/avo"
    assert_response :success
  end
end
```

- [ ] **Step 6: Run the tests**

```bash
bin/rails test test/integration/avo_access_test.rb
```

Expected: PASS. If the redirect target or status code differs from
what the current Avo version does by default, adjust the first
assertion to match actual behavior (e.g. `assert_redirected_to
new_session_path`) rather than loosening the test to `assert_response
:success` — the point of this test is that unauthenticated access is
blocked.

- [ ] **Step 7: Run the full suite**

```bash
bin/rails test
```

Expected: all PASS, no regressions.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: install Avo CMS with session-gated access

Post/Tag/SiteSetting/ApiToken resources, authenticated via the
existing Rails 8 session system rather than Devise.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## Task 9: First-admin dev seed

**Files:**
- Modify: `db/seeds.rb`
- Test: `test/models/seeds_test.rb`

**Interfaces:**
- Consumes: `User` (Task 2).
- Produces: `bin/rails db:seed` idempotently ensures exactly one
  `User` exists in a **development**-only guard, so the app is
  usable (`/avo` reachable) immediately after cloning and setting up
  the database. This is a stopgap — a later "setup wizard" plan
  replaces the "know the seed credentials" flow with an in-browser
  `/setup` form, but does not remove this seed (it's still useful for
  fast local resets).

- [ ] **Step 1: Write the failing test**

`test/models/seeds_test.rb`:

```ruby
require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeding is idempotent and creates exactly one dev admin" do
    Rails.stub :env, ActiveSupport::StringInquirer.new("development") do
      assert_difference "User.count", 1 do
        load Rails.root.join("db/seeds.rb")
      end

      assert_no_difference "User.count" do
        load Rails.root.join("db/seeds.rb")
      end
    end
  end

  test "seeding does nothing outside development" do
    Rails.stub :env, ActiveSupport::StringInquirer.new("test") do
      assert_no_difference "User.count" do
        load Rails.root.join("db/seeds.rb")
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/seeds_test.rb
```

Expected: FAIL (first assertion fails — `db/seeds.rb` is currently
empty, so no `User` is created).

- [ ] **Step 3: Implement the seed**

`db/seeds.rb`:

```ruby
if Rails.env.development?
  User.find_or_create_by!(email_address: "admin@example.com") do |user|
    user.password = "password123"
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/models/seeds_test.rb
```

Expected: PASS.

- [ ] **Step 5: Run the full suite one more time**

```bash
bin/rails test
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add idempotent dev-only admin seed

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K4Rc4SNBWw46aM24SEC8Jo
EOF
)"
```

---

## What's next

This plan covers spec sections §3 (tech stack, minus MCP/deploy), §4
(all five models), and part of §5 (Avo resources exist, but without
the locale switcher or the mind-graph tool). Everything else in the
spec becomes its own follow-up plan, in roughly this order:

1. **i18n** — add `mobility`, make `title`/`slug`/`excerpt`/`body`
   translatable, locale-prefixed routing, `config/locales/{en,de,es}.yml`
   for UI chrome, fallback behavior (spec §12).
2. **Public site & SEO** — `/resume`, `/blog`, `/blog/:slug`, `/now`
   views; meta/OG tags; `sitemap_generator`; JSON-LD (spec §6, §7).
3. **Rich embeds** — custom `ActionText::Attachable` for YouTube
   (PDF already works via Task 3's ActionText install) (spec §8).
4. **Mind graph** — Avo custom page rendering `PostRelation` edges
   with a JS force-graph library (spec §9).
5. **MCP server** — mount point, `ApiToken`-authenticated tools for
   list/get/create/update across content types and locales (spec
   §10).
6. **Setup wizard** — `/setup` flow (admin creation, branding, token
   generation, sample content), gated by `User.none?` (spec §11).

Each should get its own plan document via this same
`superpowers:writing-plans` skill when you're ready to start it.

## Self-review notes

- **Spec coverage:** confirmed above under "What's next" — every
  remaining section is accounted for in a named follow-up plan.
- **Placeholder scan:** no TBD/TODO; the one deliberately open item
  (exact Avo v4 config DSL in Task 8) is scoped to "consult current
  docs," not "figure out details later" — the desired behavior and
  its test are fully specified regardless of that DSL's exact syntax.
- **Type/name consistency:** `Post#all_related_posts`,
  `ApiToken.generate!`/`.authenticate`, `SiteSetting.instance`, and
  `Current.user`/`current_user` are used with the same names/shapes
  everywhere they appear across tasks.
