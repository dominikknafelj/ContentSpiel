# Tiptap and Avo Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ActionText/Trix rich text with Tiptap JSON documents per locale (Ruby schema registry, HTML renderer, Markdown for MCP, MediaAsset images, internal links, a Tiptap editor in CS Studio), migrate the existing content, give CS Studio every screen Avo still provides, and remove Avo.

**Architecture:**
- **Rich text (`app/models/rich_text/`):**
  - `RichText::Schema` registers node/mark types;
  - `RichText::Document` wraps a JSON document (validate, `to_html`, `to_markdown`, `from_markdown`, `from_html`);
  - `RichText::HtmlRenderer` renders through the schema, then `RichTextScrubber`, with a cache;
  - `RichText::Markdown` converts both ways with `commonmarker`.
- **Storage:** Post and ContentBlock `body` become Mobility jsonb columns. `MediaAsset` holds rich-text images.
- **Editor:** Tiptap is pinned via importmap (vendored) and mounted by an `admin--rich-text` Stimulus controller into the existing autosave forms.
- **Avo replacement:** CS Studio modules for settings, languages, users, AI-assistant tokens, system status, mind graph, starter pages and related posts. Then the Avo gem and code are deleted.

**Tech Stack:** Rails 8.1, Mobility (jsonb backend), `commonmarker` gem (new), Nokogiri, ActiveStorage, Hotwire/Stimulus, importmap (Tiptap + ProseMirror pinned and vendored), ViewComponent + Lookbook, D3 (`d3-force`, already pinned), Minitest + Capybara.

**Spec:** `docs/superpowers/specs/2026-09-27-tiptap-and-avo-removal-design.md` (binding). Context: the CS Studio spec (`2026-09-27-cs-studio-design.md`), the open types spec, the foundations spec.

## Global Constraints

- Greenfield, no production, and no MCP clients or integrations to keep compatible. Migrations may drop tables.
- **Rich-text fields:** `posts.body` and `content_blocks.body` only (pages have none). Each becomes jsonb `{ locale => tiptap_doc }`, not null, default `{}`, declared with `translates :body` on the default jsonb backend.
- **Built-in node types (exact names):** `doc paragraph heading bulletList orderedList listItem blockquote codeBlock horizontalRule hardBreak text youtube image`.
- **Built-in mark types:** `bold italic strike code link internalLink`.
- **Node attributes:**
  - `heading.level` ∈ 2..4;
  - `youtube.id` matches `/\A[\w-]{11}\z/`;
  - `image` has `asset_id` (existing `MediaAsset`), `alt`, `caption`;
  - `internalLink` has `type` ∈ `page|post` and `id` (existing record);
  - `link.href` scheme ∈ `http https mailto` or relative.
- **Plugin types** use prefixed `owner/name` names; duplicates raise (as in open types). Registration runs in `config/initializers/types.rb`'s `to_prepare`, after a reset.
- **HTML rendering:** escape everything via tag helpers; always pass output through `RichTextScrubber`; unknown types keep their children's text and log; the cache key is `[ "rich_text", document.digest, RichText::Schema.version, locale, preview ]`.
- **Markdown:**
  - CommonMark for standard types;
  - directives `::youtube{id="…"}` and `::image{asset="42" alt="…" caption="…"}` as a paragraph on their own line;
  - internal links as `[text](cs:page/42)` / `[text](cs:post/7)`;
  - unknown directives are kept as text and returned as warnings;
  - JSON → Markdown → JSON is identical for every built-in.
- **MCP:** `body` is Markdown in `create_post`, `update_post` and `get_post`.
- **MediaAsset:** png/jpeg/gif/webp only, max 10 MB, no automatic cleanup (interim).
- **Editor:** no npm and no CDN at runtime. Pins are vendored under `vendor/javascript` via `bin/importmap pin … --download` (or the current importmap equivalent that vendors). Trix and `@rails/actiontext` are removed from the admin.
- **CS Studio patterns apply:**
  - `Admin::BaseController`, `admin_locale`, `admin_url_options`;
  - autosave (`admin--autosave`, `Admin::AutosaveResponses#autosave_stream`);
  - `Admin::FileParams` for any file input;
  - explicit-remove pattern for attachments;
  - exact status texts;
  - writes only through services;
  - view components with Lookbook previews;
  - modules column entries with icons;
  - `Current.channel = :admin`.
- **Avo removal:** after it, `grep -rniw "avo" app config lib test db/seeds.rb Gemfile` returns nothing, and `grep -rn "Avo\|mount_avo\|avo\." app config lib test` returns nothing.
- **Existing rules:**
  - public URLs only via `PublicSite::Urls`;
  - public text via `Locales.read`;
  - no new integer enums;
  - no Page/Post fixtures (use `test/support/content_helper.rb`);
  - test-only types via `with_test_types` with `test/…` names;
  - long, load-bearing comments.
- **Tests:** `PARALLEL_WORKERS=1 bin/rails test`; `bin/rails test test/system` alone; system tests use scripted clicks (`press`) and `execute_script` for drags.
- **Lint:** `bin/rubocop` (whole repo), `bin/brakeman -q --no-pager`, `bin/rails zeitwerk:check`, `bin/bundler-audit`, `bin/importmap audit`.
- **Commits:** conventional, each ending with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.

## Review Focus

1. **A pasted `<script>`, `javascript:` link or foreign iframe inside a document** (via the editor JSON, MCP Markdown or migrated HTML) must never reach public HTML. Pinned in Task 2 (`test "hostile documents render inert"`) and Task 6 (`test "migrated hostile HTML stays inert"`).
2. **A document referencing a deleted `MediaAsset` or a deleted internal-link target:** renders without error (nothing, or plain text) on the public site and in the admin original. Pinned in Task 2 (`test "missing asset and missing link target render gracefully"`).
3. **Markdown written by an AI** with unusual but valid CommonMark (nested lists, code fences containing `::youtube{…}` text, emphasis inside links) round-trips without turning code into directives. Pinned in Task 3 (`test "directive-looking text inside code stays code"`).
4. **Switching the editor language** while an autosave of the other language's document is in flight: the saved language is the one the form was rendered for, never the new one. Pinned in Task 5 (`test "the body param saves into the locale of the form"`).
5. **Deleting the last user, or the currently signed-in user:** the last user is refused. Deleting yourself signs you out safely (no 500 on the next request). Pinned in Task 8 (`test "deleting yourself signs you out"`).

---

### Task 1: RichText schema, document and validation

Spec: §3.1 (Document), §3.2, §3.5.

**Files:**
- Create:
  - `app/models/rich_text.rb` (namespace module + `YOUTUBE_ID_PATTERN = /\A[\w-]{11}\z/`)
  - `app/models/rich_text/schema.rb`, `app/models/rich_text/node_type.rb`, `app/models/rich_text/mark_type.rb`, `app/models/rich_text/document.rb`
  - `app/models/rich_text/built_ins.rb` (registers the built-ins)
- Modify: `config/initializers/types.rb` (reset `RichText::Schema` and call `RichText::BuiltIns.register`)
- Test: `test/models/rich_text/schema_test.rb`, `test/models/rich_text/document_test.rb`

**Interfaces:**
- **Produces:**
  - `RichText::Schema.register_node(name) { |n| … }` and `register_mark(name) { |m| … }`, which return the type. A name must match `/\A[a-z][A-Za-z0-9]*(\/[a-z][A-Za-z0-9_]*)?\z/` (camelCase built-ins like `bulletList`; plugins `owner/name`). A duplicate raises `RichText::DuplicateType`.
  - `RichText::Schema.node(name)` / `.mark(name)` (nil when unknown), `.reset!`, `.version` (a digest of registered names + attribute specs).
  - Type DSL: `attribute(name, type = :string, required: false, in: nil, format: nil, validate: ->(value) { … })`, `html { |node, children, ctx| … }` (a block returning a SafeBuffer), `markdown_out { |node, children, ctx| … }`, `markdown_in` (reserved for custom directive parsing: `directive "youtube"`).
  - `RichText::Document.new(hash_or_nil)`: `#to_h`, `#blank?`, `#digest` (SHA256 of canonical JSON), `#validate` (Array of message Strings), `.empty` (`{ "type" => "doc", "content" => [] }`).
  - Built-in attribute rules: see Global Constraints. The `image.asset_id` and `internalLink` existence checks use `MediaAsset.exists?` / `Page.exists?` / `Post.exists?`. MediaAsset arrives in Task 4, so guard with `defined?(MediaAsset)` until then and remove the guard in Task 4.

- [ ] **Step 1: Write the failing tests**

`test/models/rich_text/document_test.rb`:

```ruby
require "test_helper"

class RichText::DocumentTest < ActiveSupport::TestCase
  def doc(*content) = RichText::Document.new("type" => "doc", "content" => content)
  def para(text) = { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] }

  test "blank and digest" do
    assert RichText::Document.empty.blank?
    assert RichText::Document.new(nil).blank?
    assert_not doc(para("Hi")).blank?
    assert_equal doc(para("Hi")).digest, doc(para("Hi")).digest
    assert_not_equal doc(para("Hi")).digest, doc(para("Ho")).digest
  end

  test "a valid document has no errors" do
    heading = { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "T" } ] }
    bold = { "type" => "text", "text" => "b", "marks" => [ { "type" => "bold" } ] }
    assert_empty doc(heading, { "type" => "paragraph", "content" => [ bold ] }).validate
  end

  test "unknown types, bad attributes and a wrong root are errors" do
    assert_includes RichText::Document.new("type" => "paragraph").validate.join, "doc"
    assert doc({ "type" => "marquee" }).validate.any? { |message| message.include?("marquee") }
    assert doc({ "type" => "heading", "attrs" => { "level" => 1 } }).validate.any? { |message| message.include?("level") }
    assert doc({ "type" => "youtube", "attrs" => { "id" => "not-valid" } }).validate.any? { |message| message.include?("youtube") }
    link = { "type" => "text", "text" => "x", "marks" => [ { "type" => "link", "attrs" => { "href" => "javascript:alert(1)" } } ] }
    assert doc({ "type" => "paragraph", "content" => [ link ] }).validate.any? { |message| message.include?("href") }
  end
end
```

`test/models/rich_text/schema_test.rb`: registration and lookup, a duplicate raises, an invalid name raises, `version` changes when a type is registered, and `reset!` plus `Rails.application.reloader.prepare!` restores the built-ins (all 13 node names and 6 mark names present).

- [ ] **Step 2: Run the tests to verify they fail.** `bin/rails test test/models/rich_text`. They should fail with an uninitialized constant.
- [ ] **Step 3: Implement** the schema, types, document (canonical JSON via `JSON.generate` of a key-sorted deep copy for the digest), recursive validation (walk `content`; validate each mark on text nodes; the text node needs a String `text`) and the built-ins. `html`/`markdown_out` blocks may raise `NotImplementedError` for now (Tasks 2–3 fill them in), but the registrations must exist.
- [ ] **Step 4: Run the tests.** `bin/rails test test/models/rich_text`, then `PARALLEL_WORKERS=1 bin/rails test`. They should pass.
- [ ] **Step 5: Commit** `git commit -m "feat: add the rich-text schema registry and document validation"`

---

### Task 2: HTML rendering

Spec: §3.3.

**Files:**
- Create:
  - `app/models/rich_text/html_renderer.rb`
  - `app/models/rich_text/render_context.rb` (`locale`, `urls`, `preview`)
  - `app/components/rich_text/youtube_component.rb` + `.html.erb` (moved markup from `app/views/youtube_embeds/_youtube_embed.html.erb`)
  - `app/components/rich_text/image_component.rb` + `.html.erb`
  - `test/models/rich_text/html_renderer_test.rb`
- Modify: `app/models/rich_text/built_ins.rb` (fill in the `html` blocks), `app/models/rich_text/document.rb` (`#to_html(locale:, urls:)`)

**Interfaces:**
- **Consumes:** Task 1; `PublicSite::Urls#path_for(record, locale)`; `RichTextScrubber` (app/sanitizers); `MediaAsset` (arrives in Task 4: until then the image html block renders nothing when `MediaAsset` isn't defined; Task 4's test covers the real image).
- **Produces:** `RichText::Document#to_html(locale: I18n.locale, urls: PublicSite::Urls.new)` returns an html_safe String, cached as specified. The renderer is callable as `RichText::HtmlRenderer.new(context).render(document)`.

- [ ] **Step 1: Write the failing tests**

```ruby
require "test_helper"

class RichText::HtmlRendererTest < ActiveSupport::TestCase
  def render(*content, preview: false)
    RichText::Document.new("type" => "doc", "content" => content).to_html(locale: "en", urls: PublicSite::Urls.new(preview: preview))
  end
  def text(value, *marks) = { "type" => "text", "text" => value, "marks" => marks }.compact

  test "standard nodes and marks" do
    html = render(
      { "type" => "heading", "attrs" => { "level" => 3 }, "content" => [ text("Title") ] },
      { "type" => "paragraph", "content" => [ text("a", { "type" => "bold" }), text("b", { "type" => "italic" }), { "type" => "hardBreak" }, text("c", { "type" => "code" }) ] },
      { "type" => "bulletList", "content" => [ { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ text("one") ] } ] } ] },
      { "type" => "blockquote", "content" => [ { "type" => "paragraph", "content" => [ text("q") ] } ] },
      { "type" => "codeBlock", "content" => [ text("x < y") ] },
      { "type" => "horizontalRule" })
    assert_includes html, "<h3>Title</h3>"
    assert_includes html, "<strong>a</strong><em>b</em><br><code>c</code>"
    assert_includes html, "<ul><li><p>one</p></li></ul>"
    assert_includes html, "<pre><code>x &lt; y</code></pre>"
    assert_includes html, "<hr>"
  end

  test "hostile documents render inert" do
    html = render(
      { "type" => "paragraph", "content" => [ text("<script>alert(1)</script>"),
        text("x", { "type" => "link", "attrs" => { "href" => "javascript:alert(1)" } }) ] },
      { "type" => "youtube", "attrs" => { "id" => "\"><iframe src=evil" } })
    assert_not_includes html, "<script>"
    assert_not_includes html, "javascript:"
    assert_not_includes html, "evil"
  end

  test "internal links resolve through public URLs, including preview" do
    page = create_page(title: "About")
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } }
    assert_includes render({ "type" => "paragraph", "content" => [ text("go", link) ] }), %(href="/about")
    assert_includes render({ "type" => "paragraph", "content" => [ text("go", link) ] }, preview: true), %(href="/preview/about")
  end

  test "missing asset and missing link target render gracefully" do
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => 0 } }
    html = render({ "type" => "paragraph", "content" => [ text("gone", link) ] }, { "type" => "image", "attrs" => { "asset_id" => 0 } })
    assert_includes html, "gone"
    assert_not_includes html, "<a"
    assert_not_includes html, "<img"
  end

  test "youtube renders the nocookie embed" do
    assert_includes render({ "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } }), "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
  end

  test "unknown node types keep their text" do
    assert_includes render({ "type" => "marquee", "content" => [ text("kept") ] }), "kept"
  end
end
```

- [ ] **Step 2: Run** `bin/rails test test/models/rich_text/html_renderer_test.rb`. It should fail.
- [ ] **Step 3: Implement.**
  - The renderer uses `ActionController::Base.helpers` / `ActionView::Helpers::TagHelper` for tags; components render via `ApplicationController.render(component, layout: false)` or `ViewComponent::Base#render_in` with a view context. Choose one and comment why.
  - Marks nest in their array order.
  - The link scheme check is done by `URI.parse`; a relative href passes.
  - Finally `ActionText::ContentHelper`-style scrubbing: call `Rails::HTML5::SafeListSanitizer.new.sanitize(html, scrubber: RichTextScrubber.new)` (check how `RichTextScrubber` is used today in `config/initializers/action_text.rb`, and reuse the same allowlist).
  - Cache via `Rails.cache.fetch`.
- [ ] **Step 4: Run** the step 2 test, then `PARALLEL_WORKERS=1 bin/rails test`. It should pass.
- [ ] **Step 5: Commit** `git commit -m "feat: render rich-text documents to HTML through the schema"`

---

### Task 3: Markdown both ways

Spec: §3.4.

**Files:**
- Create: `app/models/rich_text/markdown.rb` (`RichText::Markdown.dump(document) → String`, `.load(string) → [RichText::Document, warnings]`), `test/models/rich_text/markdown_test.rb`
- Modify: `Gemfile` (`gem "commonmarker"`), `app/models/rich_text/built_ins.rb` (`markdown_out`, directive parsing), `app/models/rich_text/document.rb` (`#to_markdown`, `.from_markdown` returning the document and the warnings)

**Interfaces:**
- **Produces:** `RichText::Document#to_markdown` → String; `RichText::Document.from_markdown(string)` → `[document, warnings]`, where warnings is an Array of Strings.

- [ ] **Step 1: Write the failing tests**

```ruby
require "test_helper"

class RichText::MarkdownTest < ActiveSupport::TestCase
  def round_trip(document) = RichText::Document.from_markdown(document.to_markdown).first.to_h

  test "every built-in round-trips" do
    page = create_page(title: "About")
    asset = nil # MediaAsset arrives in Task 4; the image case is added there
    document = RichText::Document.new("type" => "doc", "content" => [
      { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Hi" } ] },
      { "type" => "paragraph", "content" => [
        { "type" => "text", "text" => "b", "marks" => [ { "type" => "bold" } ] },
        { "type" => "text", "text" => " and " },
        { "type" => "text", "text" => "link", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } } ] } ] },
      { "type" => "orderedList", "attrs" => { "start" => 1 }, "content" => [ { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "one" } ] } ] } ] },
      { "type" => "codeBlock", "attrs" => { "language" => "ruby" }, "content" => [ { "type" => "text", "text" => "puts 1" } ] },
      { "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } },
      { "type" => "horizontalRule" } ])
    assert_equal document.to_h, round_trip(document)
    assert_includes document.to_markdown, "::youtube{id=\"dQw4w9WgXcQ\"}"
    assert_includes document.to_markdown, "(cs:page/#{page.id})"
  end

  test "directive-looking text inside code stays code" do
    document, warnings = RichText::Document.from_markdown("```\n::youtube{id=\"dQw4w9WgXcQ\"}\n```\n")
    assert_equal "codeBlock", document.to_h["content"].first["type"]
    assert_empty warnings
  end

  test "unknown directives stay as text with a warning" do
    document, warnings = RichText::Document.from_markdown("::gallery{id=\"1\"}\n")
    assert_equal "paragraph", document.to_h["content"].first["type"]
    assert warnings.any? { |warning| warning.include?("gallery") }
  end
end
```

Normalise attribute defaults (for example `orderedList.start`, `codeBlock.language`) so the round trip is exact. Document them in `built_ins.rb`.

- [ ] **Step 2: Run** the test. It should fail.
- [ ] **Step 3: Implement.** Run `bundle add commonmarker` (if bundler can't reach rubygems, report BLOCKED). Parse with Commonmarker's AST (`Commonmarker.parse`) and walk the nodes. A paragraph whose sole text matches `/\A::([a-z][\w\/-]*)\{(.*)\}\z/` is a directive, with attributes parsed as `key="value"` pairs.
- [ ] **Step 4: Run** the test, then `PARALLEL_WORKERS=1 bin/rails test`. It should pass.
- [ ] **Step 5: Commit** `git commit -m "feat: convert rich-text documents to and from Markdown"`

---

### Task 4: MediaAsset, upload and link-target endpoints

Spec: §4.2 and the §4.1 endpoints.

**Files:**
- Create:
  - `db/migrate/<ts>_create_media_assets.rb`, `app/models/media_asset.rb`
  - `app/controllers/admin/media_assets_controller.rb` (`create`, JSON), `app/controllers/admin/link_targets_controller.rb` (`index`, JSON)
  - `test/models/media_asset_test.rb`, `test/integration/admin/media_assets_test.rb`, `test/integration/admin/link_targets_test.rb`
- Modify:
  - `config/routes.rb` (admin scope: `resources :media_assets, only: :create`, `get "link_targets"`)
  - `app/models/rich_text/built_ins.rb` (remove the `defined?(MediaAsset)` guards; real image render and validation)
  - add the image round-trip case to `test/models/rich_text/markdown_test.rb` and an image render test to `html_renderer_test.rb`

**Interfaces:**
- **Produces:**
  - `MediaAsset`: `has_one_attached :file`, columns `content_type`, `byte_size`, `width`, `height`, `created_by_id`; `validate :image_type_and_size`; `#url` (`rails_blob_path(file, only_path: true)`).
  - `POST <admin>/media_assets` (multipart `file`) returns `{ id:, url: }` 201 or `{ errors: [...] }` 422.
  - `GET <admin>/link_targets?q=&locale=` returns `[ { type: "page"|"post", id:, title:, path: } ]` (≤ 20, title ILIKE in the locale, sanitised LIKE).

- [ ] **Step 1: Write the failing tests:**
  - model: a png under 10 MB is valid; text/plain is invalid; 11 MB is invalid (stub `byte_size`, or use a generated tempfile);
  - upload: signed in → 201 with the id; signed out → redirect to sign-in; bad type → 422;
  - link targets: finds a page and a post by title; `%` is escaped;
  - renderer: image with alt/caption → `<figure><img … alt="A"><figcaption>C</figcaption></figure>`;
  - markdown: the image directive round-trips.
- [ ] **Step 2: Run** them. They should fail.
- [ ] **Step 3: Implement.** Dimensions come from `file.analyze` metadata after attach (they may be nil in tests; that's fine).
- [ ] **Step 4: Run** the tests, then `PARALLEL_WORKERS=1 bin/rails test`. They should pass.
- [ ] **Step 5: Commit** `git commit -m "feat: add media assets and link targets for rich text"`

---

### Task 5: Switch storage to JSON documents; render, save and MCP

Spec: §3.1 storage, §3.4 MCP, §4.3, §4.1 controllers.

**Files:**
- Create: `db/migrate/<ts>_add_json_body_columns.rb`. Add `body_doc` jsonb (default `{}`, not null) to `posts` and `content_blocks`. The ActionText `body` stays readable until Task 6's migration task runs; Task 6 renames `body_doc` → `body` after dropping ActionText.
- Modify:
  - `app/models/post.rb` and `app/models/content_block.rb`: `translates :body_doc` (jsonb), `#body_document(locale:)` → `RichText::Document`, `validate :body_documents_valid` (every locale), plus a writer `#assign_body(document_hash, locale:)`.
  - `app/models/locales.rb`: `Locales.read(record, :body)` returns the `body_document`, falling back per language when blank.
  - `app/components/blocks/rich_text_component.*`, `app/components/posts/detail_component.*`, `app/components/posts/now_list_component.*`, and any other body renderer (`grep -rn ":body\|\.body" app/components app/views`): render `document.to_html(locale:, urls: helpers.public_urls)`.
  - Services `Posts::Save` / `ContentBlocks::Save`: the translated `body` value may be a Hash (JSON document) or a JSON String; parse it and `assign_body`.
  - Admin controllers (`posts`, `content_blocks`): the `body` param is the JSON String from the hidden input.
  - `Admin::Columns::RichTextColumnComponent`: temporarily renders a hidden input with the document JSON, a `<textarea>` fallback that edits Markdown (converted server-side), and the read-only original rendered from the primary-language document. Task 7 replaces this with Tiptap. Keep the component's public interface.
  - MCP `create_post` / `update_post` / `get_post` and `Mcp::PostSerializer`: `body` is Markdown in and out, with warnings added to the tool response text. Update the descriptions (directives, `cs:` links).
  - `app/models/starter_content.rb`, `db/seeds.rb`: bodies are built as documents (`RichText::Document.from_markdown`).
- Test:
  - update the existing body tests (public blocks, preview, posts detail, MCP tools, starter content, seeds) to the new format;
  - add `test/integration/rich_text_body_test.rb` covering public render from JSON with per-language fallback;
  - `test "the body param saves into the locale of the form"`: PATCH a post with `locale: "de"` and a JSON body → only `body_doc["de"]` changes.

**Interfaces:**
- **Consumes:** Tasks 1–4.
- **Produces:**
  - `record.body_document(locale:)`, `record.assign_body(hash, locale:)`;
  - `Locales.read(record, :body)` → `RichText::Document`;
  - services accept `translations[locale][:body]` as Hash or JSON String;
  - MCP body is Markdown.

- [ ] **Steps 1–5:** follow the same TDD cycle.
  - Write the failing tests above.
  - Run them and see them fail.
  - Implement.
  - Run the full suite; existing ActionText-dependent tests must be migrated in this task, not left failing.
  - Commit with `git commit -m "feat: store rich text as JSON documents and render them server-side"`.

---

### Task 6: Migrate ActionText content, then drop ActionText

Spec: §5.

**Files:**
- Create:
  - `app/models/rich_text/html_import.rb` (`RichText::Document.from_html(html, record:)` → `[document, unmapped_fragments]`)
  - `lib/tasks/rich_text.rake` (`rich_text:migrate_from_action_text`)
  - `db/migrate/<ts>_drop_action_text.rb` (drop `action_text_rich_texts` and `youtube_embeds`; rename `body_doc` → `body` on posts and content_blocks)
  - `test/models/rich_text/html_import_test.rb` with fixture HTML strings of real Trix output: YouTube attachment, image attachment, nested lists, internal link, `h1`, unknown tag, script
  - `test/tasks/rich_text_migration_test.rb`
- Modify:
  - `Gemfile` (remove `mobility-actiontext`)
  - `config/initializers/action_text.rb` (delete; move whatever `RichTextScrubber` setup the renderer still needs into `app/sanitizers` or the renderer)
  - models (`translates :body` on jsonb; remove `backend: :action_text`)
  - `app/models/youtube_embed.rb` (delete; `RichText::YOUTUBE_ID_PATTERN` replaces its rule)
  - `app/views/youtube_embeds/` (delete)
  - `config/initializers/mobility.rb` comments
  - every reference to `body_doc` (rename back to `body`)
  - `app/javascript/application.js` / importmap: stop importing `trix` / `@rails/actiontext` (the public site doesn't need them). Keep the pins only if CS Studio still needs them before Task 7; if not, remove them.

**Interfaces:**
- **Produces:** `rich_text:migrate_from_action_text` prints per-model counts and the unmapped fragments, never aborts, and is idempotent (it skips locales that already have a document).

- [ ] **Step 1: Write the failing tests:**
  - importer mapping for each fixture (h1 → h2, h5 → h4, an image attachment → a `MediaAsset` re-attaching the same blob plus an `image` node, a YouTube attachment → a `youtube` node, a link to this site's public URL → `internalLink`, unknown tags → text);
  - `test "migrated hostile HTML stays inert"` (script/iframe/`javascript:` never survive into the document or its rendered HTML);
  - the task over a DB with ActionText rows produces documents and reports unmapped fragments.

  Run this task's tests **before** the drop migration in the test DB. Structure the test to build `ActionText::RichText` rows while the table exists, or unit-test the importer on HTML strings plus a small task test that stubs the source rows. Choose, and explain the choice in the report.
- [ ] **Step 2: Run** them and see them fail.
- [ ] **Step 3: Implement.** Run the task against the dev DB (`bin/rails rich_text:migrate_from_action_text`) and paste the output into the report. Then run the drop migration.
- [ ] **Step 4: Run** `PARALLEL_WORKERS=1 bin/rails test`, `bin/rails db:reset` (seeds build JSON), `bin/rails zeitwerk:check`.
- [ ] **Step 5: Commit** `git commit -m "feat: migrate ActionText bodies to documents and drop ActionText"`

---

### Task 7: The Tiptap editor in CS Studio

Spec: §4.1.

**Files:**
- Modify:
  - `config/importmap.rb` (pins for `@tiptap/core`, `@tiptap/starter-kit`, `@tiptap/extension-link`, `@tiptap/pm/*` or the ProseMirror packages they need, vendored under `vendor/javascript`)
  - `app/components/admin/columns/rich_text_column_component.*` (toolbar, mount, hidden JSON input, read-only original from the rendered primary-language document, translate slot)
  - `app/components/admin/block_card_component.html.erb` / `post_form_component.html.erb` (remove `trix-change`)
  - `app/javascript/controllers/admin/autosave_controller.js` (drop any Trix-specific handling)
- Create:
  - `app/javascript/controllers/admin/rich_text_controller.js` (`admin--rich-text`)
  - `app/javascript/rich_text/youtube.js`, `image.js`, `internal_link.js` (Tiptap extensions)
  - a Lookbook preview for the column
  - `test/system/admin/rich_text_test.rb`

**Interfaces:**
- **Consumes:** the Task 4 endpoints; the Task 5 hidden-input contract (`<input type=hidden name="…[body]">` with document JSON).
- **Produces:** the editor writes `JSON.stringify(editor.getJSON())` into the hidden input and dispatches `input` on the form. The YouTube paste rule matches `youtube.com/watch?v=`, `youtu.be/` and `youtube.com/embed/` URLs and extracts the 11-character id.

- [ ] **Step 1: Write the failing system tests** (scripted clicks):
  - type "Hello", click Bold, type "world" → autosave → the post's document has a bold mark;
  - paste a YouTube URL (dispatch a paste event with `execute_script` if native paste is unreliable) → a youtube node saved;
  - upload `test/fixtures/files/tiny.png` through the image button, set alt "A" → an image node with an `asset_id` and alt "A";
  - insert an internal link to an existing page via the picker → an `internalLink` mark with the page id;
  - in `?locale=de`, the primary original shows the rendered English body.
- [ ] **Step 2: Run** `bin/rails test test/system/admin/rich_text_test.rb`. It should fail.
- [ ] **Step 3: Implement.**
  - **Pinning:** `bin/importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-link --download` (or the version's equivalent). If the network is unavailable, report BLOCKED, and don't hand-write vendored bundles.
  - **Editor lifecycle:** mount in `connect()`, `editor.destroy()` in `disconnect()`.
  - **Image popover and link picker:** small DOM built in JS, using product token classes.
- [ ] **Step 4: Run** the system tests (alone, three times green), then `PARALLEL_WORKERS=1 bin/rails test`, `bin/importmap audit`.
- [ ] **Step 5: Commit** `git commit -m "feat: edit rich text with Tiptap in CS Studio"`

---

### Task 8: Settings, languages, users

Spec: §6.1 (Settings, Languages, Users).

**Files:**
- Create:
  - `app/controllers/admin/settings_controller.rb` (show/update), `app/controllers/admin/languages_controller.rb` (index/create/update/destroy)
  - `app/controllers/admin/users_controller.rb` (index/new/create/edit/update/destroy)
  - `app/services/locales/configure.rb` (fallbacks + order), `app/services/users/save.rb`, `app/services/users/destroy.rb`
  - views/components and Lookbook previews for each screen
  - `test/integration/admin/settings_test.rb`, `languages_test.rb` (admin module, distinct from the existing editor language tests; name it `language_settings_test.rb`), `users_test.rb`
  - `test/services/locales/configure_test.rb`, `test/services/users/destroy_test.rb`, `test/models/user_test.rb` additions
- Modify:
  - `app/models/site_setting.rb` (`social_link_rows=`, moving the row normalisation out of `SetupController`, which then uses it)
  - `app/models/user.rb` (`before_destroy :ensure_not_last_owner`)
  - `app/views/layouts/admin.html.erb` (Settings and Users modules with icons; remove the "(old admin)" settings/users links)
  - `config/routes.rb`

**Interfaces:**
- **Produces:**
  - `Locales::Configure.call(entries, actor:)` (an ordered Array of `{ "code", "fallbacks" }`) → Result; it validates like `SiteSetting#locales`.
  - `Users::Save.call(user = User.new, attributes:, actor:)` → Result (password + confirmation).
  - `Users::Destroy.call(user, actor:)` → Result, failing with "The last user can't be deleted".
  - Deleting yourself is allowed (if not last) and ends your session: the controller terminates the session and redirects to sign-in.

- [ ] **Step 1: Write the failing tests:**
  - settings update (title, tagline, logo upload, logo explicit remove, social link rows, default language restricted to enabled ones);
  - languages: add (fr → `Locales::Enable`), disable (not the default), fallbacks and reorder via `Configure`;
  - users: create, edit, change password, delete another, refuse the last;
  - `test "deleting yourself signs you out"`.
- [ ] **Steps 2–5:** follow the TDD cycle, run the full suite, and commit `git commit -m "feat: add settings, languages and users to CS Studio"`.

---

### Task 9: AI assistant tokens, system status, mind graph, starter pages, related posts

Spec: §6.1 (the remaining modules).

**Files:**
- Create:
  - `app/controllers/admin/api_tokens_controller.rb` (index/create/destroy = revoke), with views: list, one-time reveal with copy button, MCP URL, client config snippet
  - `app/controllers/admin/system_status_controller.rb` (show; re-run via reload)
  - `app/controllers/admin/mind_graph_controller.rb` (show; JSON data embedded as today)
  - `app/queries/post_graph.rb` (or `app/models/post_graph.rb`: `PostGraph.call → { nodes: [{ id, title, content_type, color, url }], edges: [{ source, target }] }`)
  - `app/javascript/controllers/admin/mind_graph_controller.js` (port of `app/javascript/controllers/mind_graph_controller.js`; node click → CS Studio post editor)
  - `app/controllers/admin/starter_contents_controller.rb` (create)
  - `app/components/admin/related_posts_component.*` + the `admin--related-posts` picker (search via `link_targets?type=post`)
  - tests for each
- Modify:
  - `Posts::Save` (`related_post_ids` attribute: replace the post's forward relations; ignore self; unknown ids → error)
  - `app/components/admin/post_form_component.*` (related posts section)
  - `app/views/admin/pages/index.html.erb` (a "Create starter pages" action in the empty state and a menu)
  - layout modules (AI assistant, System status, Mind graph; remove the remaining "(old admin)" links)
  - `config/routes.rb`

**Interfaces:**
- **Produces:**
  - `PostGraph.call`;
  - `Posts::Save` accepts `related_post_ids`;
  - the token reveal response sets `Cache-Control: no-store` and shows the raw token exactly once, never persisted to the flash or session.

- [ ] **Step 1: Write the failing tests:**
  - tokens: create shows the raw token once; reloading doesn't show it again; `no-store`; revoke; the list shows last used/IP; the MCP URL and snippet are present;
  - system status renders the `SystemCheck` results;
  - the mind graph JSON has nodes with colours and edges;
  - starter pages create the sections and refresh the tree (the `_top` redirect);
  - related posts save through the post editor and `Posts::Save` (self and unknown ids handled).
- [ ] **Steps 2–5:** follow the TDD cycle, run the full suite, and commit `git commit -m "feat: add AI assistant tokens, status, mind graph, starter pages and related posts to CS Studio"`.

---

### Task 10: Port Avo's invariants, then remove Avo

Spec: §6.2, §6.3.

**Files:**
- Delete:
  - `app/avo/`, `app/controllers/avo/`, `app/views/avo/`
  - `config/initializers/avo.rb`, `mount_avo` and its block in `config/routes.rb`
  - `gem "avo"` in the Gemfile
  - `pin "avo.custom"`, `pin "youtube_embed_paste"`, `app/javascript/avo.custom.js`, `app/javascript/youtube_embed_paste.js`, `app/javascript/controllers/pages_tree_controller.js`, the old `app/javascript/controllers/mind_graph_controller.js` (replaced in Task 9)
  - `test/integration/avo_*`, `test/models/*_action_test.rb` (Avo actions)
  - any Avo helper references (`app/controllers/concerns/authentication.rb`, `config/initializers/admin_path.rb` reserved list, comments)
- Create: `test/integration/admin/invariants_test.rb` porting the Avo tests' real invariants **before** deleting them:
  - tokens only via `ApiTokens::Issue` (no route creates a token otherwise);
  - the last user can't be deleted;
  - the admin is gated while setup is required;
  - the site settings singleton;
  - the mind graph data;
  - page reorder semantics (already in the `Pages::Move` tests; cross-reference).

- [ ] **Step 1:** Read every `test/integration/avo_*` and `test/models/*_action_test.rb`, list each invariant they assert, and write the ported tests against models, services and CS Studio. They should pass on the current code.
- [ ] **Step 2:** Delete the Avo code and tests listed above, then run `bundle install`.
- [ ] **Step 3:** Run `grep -rniw "avo" app config lib test db/seeds.rb Gemfile` and `grep -rn "Avo\|mount_avo\|avo\." app config lib test`. Both must be empty (report any legitimately unrelated match with a reason).
- [ ] **Step 4:** Run `PARALLEL_WORKERS=1 bin/rails test`, `bin/rails test test/system`, `bin/rails zeitwerk:check`, `bin/importmap audit`, `bin/bundler-audit`. All must be green.
- [ ] **Step 5:** Commit `git commit -m "feat: remove Avo now that CS Studio covers everything"`

---

### Task 11: Roadmap, interim states and final verification

Spec: §8, §9.

- [ ] **Step 1:** Update `docs/roadmap.md`:
  - "Known interim states": remove the Avo row; add "unreferenced MediaAssets are never cleaned up / image blocks and rich-text images use different storage / no responsive variants → media library (sub-project 6)";
  - mark Tiptap and the Avo removal as done in Phase 2;
  - update CLAUDE.md's Admin (Avo) section to describe CS Studio instead. Only change what's now false; keep the style.
- [ ] **Step 2:** Run the full verification:
  - `PARALLEL_WORKERS=1 bin/rails test`
  - `bin/rails test test/system` (alone, twice)
  - `bin/rubocop`
  - `bin/brakeman -q --no-pager`
  - `bin/bundler-audit`
  - `bin/importmap audit`
  - `bin/rails zeitwerk:check`
  - `bin/rails db:reset` (JSON seeds), then `bin/rails runner 'puts Post.first.body_document(locale: "en").to_markdown'`
- [ ] **Step 3:** Commit `git commit -m "docs: record the Tiptap move and Avo removal in the roadmap and CLAUDE.md"`
