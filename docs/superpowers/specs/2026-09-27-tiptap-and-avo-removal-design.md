# Tiptap rich text and Avo removal

Sub-project 4 of the own-admin roadmap, merged with the Avo removal the user pulled forward (see §2). Design approved in brainstorming on 2026-09-27. This document is the binding spec for the implementation plan.

## 1. Purpose

- **Rich text becomes structured.** Every rich-text field stores a Tiptap/ProseMirror JSON document per language instead of ActionText/Trix HTML:
  - HTML is rendered on the server through a node/mark schema registry that plugins can extend;
  - AI/MCP read and write rich text as Markdown with directives for custom nodes;
  - the editor in CS Studio is Tiptap.
- **Avo goes away.** Everything only Avo offered gets a CS Studio screen, Avo's hidden rules move into models, services and tests, and the gem is removed.

**Success:**
- Editors write formatted text with YouTube embeds, images (with alt and caption) and internal links that survive renames.
- Public pages render it with the existing security guarantees.
- MCP clients exchange Markdown.
- Existing content is migrated.
- CS Studio covers settings, languages, users, AI-assistant tokens, system status, the mind graph, starter pages and post relations.
- No Avo code remains.

**Context:** greenfield, no production. One branch, one PR. Interim states are acceptable when tracked in `docs/roadmap.md`.

## 2. Decisions (from brainstorming)

| Decision | Chosen | Rejected |
|---|---|---|
| Avo during this change | **Remove Avo in this sub-project** (user). | Read-only Avo bodies; a Trix→JSON bridge in Avo. |
| Avo features to replace | **All of them:** settings (+ languages), users, API tokens, system status, mind graph, starter pages, and post relations editing. | Dropping mind graph/starter pages; settings + tokens only. |
| Node types v1 | Standard set (paragraph, heading H2–H4, bold, italic, strike, code, link, bullet/ordered list, blockquote, code block, horizontal rule, hard break) plus custom `youtube`, `image`, `internalLink`. | YouTube only; plus tables/alignment/underline. |
| Architecture | Own `RichText::Schema` registry and Ruby renderers; jsonb per locale; `commonmarker` for Markdown; `MediaAsset` for images; Tiptap via import maps. | Storing JSON + HTML; a third-party Ruby Tiptap gem. |

## 3. Rich-text core

### 3.1 Storage

- `posts.body` and `content_blocks.body` (the only rich-text fields; pages have none) become jsonb columns (`{ locale => tiptap_doc }`, not null, default `{}`), declared with `translates :body` on the default jsonb backend.
- `mobility-actiontext` and the ActionText tables are removed after the migration (§5).
- **`RichText::Document`** (value object around a document Hash):
  - `.new(hash)`, `.empty`
  - `#blank?` (no text and no embeds)
  - `#digest`
  - `#to_html(locale:, urls:)`
  - `#to_markdown`
  - `.from_markdown(string)`
  - `.from_html(string)` (migration)
  - `#validate(schema)`, which returns error messages
- The models expose `record.body_document(locale:)`. `Locales.read(record, :body)` returns a `RichText::Document` and falls back per language when the document is blank.

### 3.2 Schema registry (`app/models/rich_text/`)

- **Registration:** `RichText::Schema.register_node(name) { |n| … }` and `RichText::Schema.register_mark(name) { |m| … }`. Each type declares:
  - `attributes` (name, type, required, allowed values);
  - `html` (a renderer receiving the node, its rendered children and a context with `locale` and `urls`);
  - `markdown_out` / `markdown_in` (standard types use CommonMark; custom nodes use a directive `::name{key="value" …}`).
- **Built-ins:**
  - nodes: `doc paragraph heading bulletList orderedList listItem blockquote codeBlock horizontalRule hardBreak text youtube image`;
  - marks: `bold italic strike code link internalLink`.
- **Where registration happens:** built-ins register in the existing types initializer (`to_prepare`, reset first). Plugin types use prefixed `owner/name` names, as in open types, and duplicates raise.
- **Versioning:** `RichText::Schema.version` is a digest of the registered types. It feeds the render cache key.

### 3.3 Rendering

- **`RichText::HtmlRenderer`** walks the document and emits HTML with Rails tag helpers, so everything is escaped.
- **Links:** `link` hrefs are allowed only for `http`, `https`, `mailto` and relative URLs; anything else renders the text without a link.
- **Internal links:** `internalLink{type, id}` resolves through `PublicSite::Urls#path_for` (preview-aware via the passed `urls`). A missing target renders as text.
- **YouTube:** `youtube{id}` renders the existing YouTube embed markup (moved into a view component) with a youtube-nocookie URL. The ID is validated with `YoutubeEmbed`'s rule.
- **Images:** `image{asset_id, alt, caption}` renders `<figure><img src alt><figcaption>` from the `MediaAsset`. A missing asset renders nothing.
- **Unknown node or mark types:** skipped, with the children's text kept, and logged.
- **Sanitizing:** output still passes through `RichTextScrubber`. CSP `frame-src` is unchanged.
- **Cache:** `Rails.cache.fetch([ "rich_text", document.digest, RichText::Schema.version, locale, preview? ])`.

### 3.4 Markdown (MCP)

- **Reading (JSON → Markdown):**
  - standard nodes become CommonMark;
  - `youtube` → `::youtube{id="…"}`;
  - `image` → `::image{asset="42" alt="…" caption="…"}`;
  - `internalLink` → `[text](cs:page/42)` / `[text](cs:post/7)`.
- **Writing (Markdown → JSON):** `commonmarker` parses the text (the `commonmarker` gem is added to the Gemfile).
  - A paragraph consisting only of a directive line becomes that node.
  - `cs:` links become `internalLink`.
  - Unknown directives stay as text, and the tool response lists them as warnings.
- **Round trip:** JSON → Markdown → JSON is identical for every built-in (tested).
- **MCP tools:** `body` switches from HTML to Markdown in `create_post`, `update_post` and `get_post`. The descriptions document the directives and `cs:` links. There are no MCP clients or integrations yet, so nothing needs a compatibility path.

### 3.5 Validation

`RichText::Document#validate` checks:
- the top node is `doc`;
- node and mark types are registered;
- required attributes are present and values are allowed (heading level 2–4, a valid YouTube ID, an existing `MediaAsset` for `image`, an existing record for `internalLink`).

Models validate every locale's document, with errors on `body`. Services return them like any other validation error.

## 4. Editor and media

### 4.1 Tiptap in CS Studio

- **Pins:** `bin/importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-link` (with their ProseMirror dependencies), vendored under `vendor/javascript` like the existing pins. No npm and no CDN at runtime.
- **`Admin::Columns::RichTextColumnComponent`** renders:
  - a toolbar: bold, italic, strike, code, H2, H3, H4, bullet list, ordered list, quote, code block, rule, link, internal link, image, YouTube;
  - the editor mount;
  - a hidden input holding the document JSON;
  - in a non-default locale, the primary-language document rendered to HTML read-only, plus the `data-translate-slot`.
- **Stimulus `admin--rich-text`:**
  - mounts Tiptap with the extensions and the initial JSON;
  - on update, writes `JSON.stringify(editor.getJSON())` into the hidden input and dispatches `input`, so the existing autosave sends it;
  - destroys the editor on disconnect (Turbo frame swaps).
  - The `trix-change` listener, Trix and `@rails/actiontext` are removed from the admin.
- **Custom extensions** in `app/javascript/rich_text/`:
  - `youtube`: a node, plus a paste rule converting a pasted YouTube URL into the node.
  - `image`: a node with an upload button. It POSTs to `<admin>/media_assets`, then inserts `{asset_id, alt: "", caption: ""}`; a popover edits alt and caption.
  - `internal_link`: a mark with a picker that searches `GET <admin>/link_targets?q=` (pages and posts by title in the admin locale) and stores `{type, id}`.
- **Controllers** (content blocks, posts) parse the hidden JSON and pass it as `translations[locale][:body]`. Services and models validate it (§3.5).

### 4.2 MediaAsset

- **`media_assets`:** `has_one_attached :file`, `content_type`, `byte_size`, `width`, `height`, `created_by_id` (nullable user), timestamps.
- **Rules:** image content types only (png, jpeg, gif, webp); max 10 MB.
- **`Admin::MediaAssetsController#create`** (JSON): returns `{ id, url }` or 422 with errors.
- **Retention:** assets are kept while referenced. There's no automatic cleanup of unreferenced assets yet (an interim state, §8).
- **Relation to open types:** image *blocks* keep their own `image` attachment (open types). Only rich-text images use `MediaAsset` for now. Unifying the two comes with the media library.

### 4.3 Public rendering

Components that render bodies (`Blocks::RichTextComponent`, `Posts::DetailComponent`, `Posts::NowListComponent`, …) call `document.to_html(locale:, urls:)` via `Locales.read`. `urls` is the controller's `public_urls`, so `/preview` keeps its links.

## 5. Migration from ActionText

- **Task:** `bin/rails rich_text:migrate_from_action_text` iterates every `ActionText::RichText` row (record, name, locale) and converts its HTML with `RichText::Document.from_html` (Nokogiri):
  - `p, h2–h4 (h1 → h2, h5/h6 → h4), ul/ol/li, blockquote, pre>code, hr, br, strong/b, em/i, del/s, code, a`;
  - `action-text-attachment` for a YouTube embed → `youtube`;
  - for a blob (image) → a new `MediaAsset` re-attaching the same blob, plus an `image` node (caption from the attachment caption);
  - `a href` pointing at this site's public URL → `internalLink` when `PublicSite::Resolver` resolves it;
  - anything else → its text inside a paragraph.
- **Writing:** it writes `record.body` for that locale directly (bypassing callbacks except path sync, which bodies don't affect). It prints counts per model plus each unmapped fragment, and never aborts midway.
- **Cleanup:** a follow-up migration drops `action_text_rich_texts` and the `youtube_embeds` table (the `YoutubeEmbed` attachable is replaced by the `youtube` node; its ID rule moves to `RichText`), and removes `mobility-actiontext` and ActionText configuration (`config/initializers/action_text.rb`'s allowlist moves onto the renderer/scrubber). It runs after the task in the same deploy sequence; on greenfield, `bin/rails db:reset` with JSON seeds also works.
- **Writers of JSON:** seeds and starter content write JSON documents (built with small `RichText::Document` builders).

## 6. Replacing Avo

### 6.1 New CS Studio modules

The modules column loses the "(old admin)" group and gains these entries:
- **Settings** (`settings`): title, tagline, logo (with the explicit-remove pattern), social link rows (the `SiteSetting#social_link_rows=` model helper), default language.
- **Languages** (`settings/languages`):
  - enabled languages with fallbacks;
  - "Add language" (supported-language select → `Locales::Enable`);
  - Disable (`Locales::Disable`; the default can't be disabled);
  - edit fallbacks and reorder via a new `Locales::Configure` service.
- **Users** (`users`):
  - list, new (email + password), edit (email, change password);
  - delete, refused for the last user by a new `User#ensure_not_last_owner` (a `before_destroy` rule) and surfaced by a `Users::Destroy` service.
  - Invites stay on the roadmap.
- **Connect an AI assistant** (`api_tokens`):
  - active and revoked tokens with last used and IP;
  - "Create token" → `ApiTokens::Issue` → a one-time reveal page with a copy button, the MCP URL (`PublicSite::Urls.default_host` + `/mcp`) and a client config snippet, served `Cache-Control: no-store`;
  - Revoke → `ApiTokens::Revoke`.
- **System status** (`system_status`): `SystemCheck` results with "Run again".
- **Mind graph** (`mind_graph`):
  - the D3 force graph ported from Avo's tool;
  - data from a new `PostGraph` query (nodes with type colour, edges from `PostRelation`);
  - clicking a node opens the post editor.
- **Starter pages:** a "Create starter pages" action on the Pages home (empty state + menu). It calls `StarterContent.create_pages_and_posts!` and refreshes the tree.
- **Related posts:** a picker in the post editor (search, add, remove) writing through a new `Posts::Save` attribute `related_post_ids`.

### 6.2 Porting Avo's invariants (structure review #40)

Before deleting Avo files, move their behaviour into model, service or CS Studio tests:
- tokens only through `ApiTokens::Issue`;
- the last user can't be deleted;
- the admin is gated while setup is required;
- the site settings singleton;
- the mind graph data;
- the pages-tree reorder semantics, already covered by `Pages::Move`.

### 6.3 Removal

- **Delete:**
  - the `avo` gem and its initializer;
  - `mount_avo` and the Avo routes;
  - `app/avo/`, `app/controllers/avo/`, `app/views/avo/`;
  - the Avo import-map pins (`avo.custom`, `youtube_embed_paste`) and Avo-only JS (`pages_tree_controller.js`, the YouTube paste helper);
  - the Avo YouTube-embed endpoint;
  - Avo-referencing comments;
  - `test/integration/avo_*` (after §6.2).
- **Checks:**
  - `grep -rin "avo" app config lib test db/seeds.rb` is empty, apart from unrelated words; the plan lists the exact grep;
  - `ADMIN_PATH`'s reserved list drops `avo`;
  - sign-in and `after_authentication_url` references to Avo are gone.

## 7. Error handling

- **Invalid document JSON** (malformed, unknown type, bad attributes): a validation error on `body`. Autosave shows `Couldn't save — N problems`, and the stored document is unchanged.
- **A stale image asset or internal-link target:** renders nothing or plain text, and the editor shows a "missing" placeholder.
- **Markdown with unknown directives:** kept as text and reported as warnings in the MCP response. The save succeeds.
- **Upload failures:** shown inline in the editor, and nothing is inserted.
- **Migration:** never aborts. Unmapped fragments are reported and their text is kept.
- **Users:** deleting the last user answers with the service error and a 422.

## 8. Interim states (add to docs/roadmap.md "Known interim states")

- Unreferenced `MediaAsset`s are never cleaned up; image blocks and rich-text images use different storage; there are no responsive variants. All three are closed by the media library (sub-project 6).
- The existing interim states stay: autosave writes live, and deletes are permanent. Remove the "Avo still mounted" row.

## 9. Testing

- **Unit:**
  - schema registry (registration, duplicates, prefixed names);
  - HTML renderer: every node and mark, escaping, link scheme filtering, internal-link resolution incl. preview, unknown types, cache key;
  - Markdown both ways, round trip for every built-in, unknown directives;
  - document validation;
  - the HTML→JSON mapper with fixtures of real Trix output (YouTube attachment, image attachment, nested lists, internal link, unknown tags);
  - `MediaAsset` rules;
  - `Locales::Configure`, `Users::Destroy`, `User#ensure_not_last_owner`, `PostGraph`.
- **Integration:**
  - public rendering from JSON with per-language fallback and preview links;
  - scrubber/CSP regression (foreign iframe blocked);
  - MCP Markdown read/write;
  - the media upload endpoint;
  - link target search;
  - every new CS Studio module (settings incl. logo remove, languages add/disable/fallbacks, users incl. the last-user rule, tokens incl. one-time reveal + `no-store`, system status, mind graph JSON, starter pages, related posts);
  - the migration task on a fixture database;
  - the ported Avo invariants.
- **System** (scripted clicks):
  - type formatted text and autosave;
  - paste a YouTube URL → embed node;
  - upload an image and set alt;
  - insert an internal link;
  - switch language and see the primary original rendered;
  - the mind graph renders.
- **Final:** full suite, system tests, rubocop, brakeman, bundler-audit, importmap audit, zeitwerk, the Avo grep, `db:reset` with JSON seeds.

## 10. Out of scope

- Media library UI (browse/reuse), responsive variants, asset cleanup.
- Tables, alignment, underline.
- Collaborative editing.
- Pending revisions.
- Invites, roles and the audit log (sub-project 5).
- The AI translate action (only the slot exists).
- Unifying image blocks with `MediaAsset`.
