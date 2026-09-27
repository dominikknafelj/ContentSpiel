# Open types: registries, field schemas, components

Sub-project 2 of 7 on the way to ContentSpiel's own admin (`docs/roadmap.md`, Phase 1 "Open types"; structure review #6, #47, #50, §8). Design approved in brainstorming on 2026-09-27. This document is the binding spec for the implementation plan.

## 1. Purpose

Block types (`rich_text`, `image`, `post_list`) and content types (`blog`, `resume_entry`, `now_update`) are currently closed integer enums. Their knowledge is scattered across views, the canonical-URL logic, MCP schemas, starter content, Avo and the mind graph. This sub-project makes types **open**:
- string columns checked against registries;
- one declarative field schema per type;
- reusable field groups ("components");
- rendering through view components that the registry points to.

The admin forms in sub-project 3 are then generated from the schema. Plugins, and later admin-defined types, add types through the same seams.

**Success:**
- The public site, MCP and Avo behave as today.
- A new block or content type is one registration plus one view component. It needs no migration and no enum edit, and it shows up everywhere the built-ins do: rendering, canonical URLs, MCP schemas and Avo options.
- A test-only type proves this.

**Context:** greenfield, no production. Migrations drop and rebuild; there are no compatibility shims.

## 2. Decisions (from brainstorming)

| Decision | Chosen | Rejected |
|---|---|---|
| Where types come from | Code now (built-ins, later plugins). The field schema is declarative, so admin-defined types (roadmap Phase 3) can feed the same format later. | Both sources now (no admin shell yet). Plain ActiveModel classes per type (admin-defined types would need a second mechanism). |
| Block owner | Polymorphic `owner` now; only `Page` uses it. | Keep `page_id` (a second migration of the table later). A `snippet` block type only (snippets couldn't hold blocks). |
| Type system shape | A registry of definitions + a declarative field schema → `FieldSet` (ActiveModel), with values in jsonb. Existing columns (body, caption, alt, image, title, slug, excerpt) stay as columns that a type opts into. | STI subclasses (admin-defined types can't be classes). Everything in jsonb now (rewrites rich text right before Tiptap replaces it). |
| Field groups | "Components" (Storyblok/Strapi style): a named, reusable field group, embedded once or as a repeatable list. | — |
| View layer | **ViewComponent**. The registry references component classes; Lookbook for previews (dev only). | Partials by naming convention (hidden ivars, no isolated tests). Phlex (a different style from the ERB codebase). |

## 3. Registries and field schema

### 3.1 Definitions and registration

- **Files:** one small definition per built-in type in `app/models/block_types/`, `app/models/content_types/` and `app/models/components/`.
- **Registration:** in `config/initializers/types.rb` inside `Rails.application.config.to_prepare`, so reloading in development re-registers cleanly. The registry is cleared at the start of each `to_prepare` run.
- **Plugins:** they will register through the same calls (the DSL itself is out of scope).

```ruby
BlockTypes.register :post_list do |t|
  t.label "Post list"
  t.field :content_type, :content_type          # blank = every content type
  t.field :tag, :string
  t.field :limit, :integer, min: 1
  t.capability :lists_posts
  t.component Blocks::PostListComponent
end

BlockTypes.register :image do |t|
  t.label "Image"
  t.uses :image, :caption, :alt                  # existing columns this type edits
  t.component Blocks::ImageComponent
end

ContentTypes.register :resume_entry do |t|
  t.label "Resume entry"
  t.color "#…"                                   # mind graph
  t.field :company, :string
  t.field :role_type, :select, options: ROLE_TYPES
  t.field :start_date, :date
  t.field :end_date, :date                        # blank = current role
  t.list_item_component Posts::ResumeRowComponent
  t.detail_component Posts::DetailComponent
  t.starter section: { title: "Resume", slug: "resume" },
            sample: { title: "Your first role", body: "…", fields: { company: "Example Co", … } }
end

Components.register :cta do |c|
  c.label "Call to action"
  c.field :label, :string, required: true
  c.field :url, :url, required: true
end
```

### 3.2 Registry API

- `BlockTypes` / `ContentTypes` / `Components`:
  - `.register(name, &block)`;
  - `.fetch(name)`, which raises `UnknownType` for a name that isn't registered;
  - `.find(name)`, which returns nil;
  - `.names` and `.all`;
  - `BlockTypes.with_capability(:lists_posts)`.
- A definition exposes:
  - `name` and `label`;
  - `fields` (the schema);
  - `uses` (columns it opts into);
  - capabilities;
  - its component classes;
  - the `field_set` class;
  - for content types, also `color` and `starter`.

### 3.3 Field types and options

- **Scalar types:** `string`, `text`, `integer`, `boolean`, `date`, `url`, `select` (`options:` a Hash or Array), `content_type` (must be registered), `tag` (a tag name).
- **Group types:**
  - `component` (`of:` a registered component; one nested object);
  - `components` (`of:`; an ordered list of objects).
- **Options:** `required`, `default`, `min`/`max` (integer), `translated`.
- **Limits:**
  - A component's own fields may not be `component`/`components`, so there is one level of nesting.
  - There are no "dynamic zones" (mixed-type lists). For pages the block list plays that role, and polymorphic owners let other records own blocks later.

### 3.4 `FieldSet`

- **What it builds:** `FieldSet.for(definition)` builds, and caches per definition, an ActiveModel class. It uses `ActiveModel::Attributes` for casting and `ActiveModel::Validations` for `required`, `select` inclusion, `min`/`max`, parseable dates and URLs, registered content types, and nested component validation.
- **Blanks:** blank strings cast to nil and stay nil. This replaces `discard_blank_settings`.
- **Errors:** keyed by path so a form can mark the exact input, e.g. `limit` or `speakers.1.name`. On the owning record they appear as `settings.limit` / `fields.speakers.1.name`.
- **Translated fields:**
  - A `translated: true` field's value is stored per locale.
  - A translated `component`/`components` field is translated **as a whole**: each locale stores its own copy. Fields inside a component are never translated individually.
  - Public reads fall back along `Locales.fallback_chain`, like `Locales.read`; admin and MCP read the literal locale.
- **Serialization:** `to_h` produces plain JSON (string keys; dates as ISO strings; components as hashes/arrays).

## 4. Data model

### 4.1 Migration (drop and rebuild)

- **`content_blocks`:**
  - `block_type` becomes a string, not null;
  - `page_id` is replaced by `owner_type` string + `owner_id` bigint, both not null, with an index on `(owner_type, owner_id, position)`;
  - `settings` stays jsonb (untranslated field values);
  - new `translated_settings` jsonb, not null, default `{}` (`{ locale => { key => value } }`).
- **`posts`:**
  - `content_type` becomes a string, not null, indexed;
  - `metadata` stays jsonb (untranslated field values);
  - new `translated_metadata` jsonb, not null, default `{}`.
- **Existing data:** the dev DB is reset and seeds rebuild. `PublicSite::Paths.rebuild!` runs from seeds as today.

### 4.2 Models

- **`ContentBlock`:**
  - `belongs_to :owner, polymorphic: true`;
  - validates that `block_type` is registered, checked at validation time;
  - `settings_object` returns the type's `FieldSet` instance over `settings` + `translated_settings`, and assignment writes back;
  - validation delegates to it.
  - `listed_posts` and `lists?(post)` move onto the `post_list` definition's `lists_posts` capability. `ContentBlock` delegates for blocks whose type has it; other blocks list nothing.
  - `discard_blank_settings` and the enum-specific `settings` validation go away.
- **`Page`:** `has_many :content_blocks, -> { order(:position) }, as: :owner, dependent: :destroy`. `page_type` stays an integer enum: it is layout, not content, and there are no new enums.
- **`Post`:**
  - validates that `content_type` is registered;
  - `fields` returns the content type's `FieldSet` over `metadata` + `translated_metadata`, with writes going back through it;
  - the resume `store_accessor`s and `Post::ROLE_TYPES` move into the `resume_entry` definition;
  - resume helpers (`resume_period`) read `post.fields`.
- **Unknown stored types** (for example, a removed plugin):
  - the record loads;
  - the public site renders nothing for that block and logs a warning;
  - a post of an unknown type has no public URL (sync ignores it);
  - the admin later shows "unavailable type".

## 5. View layer: ViewComponent

- **Gems:** add `view_component`. Lookbook is dev and test only, mounted at `/lookbook` in development only.
- **Components** live in `app/components/`:
  - `Blocks::RichTextComponent`, `Blocks::ImageComponent`, `Blocks::PostListComponent`;
  - `Posts::BlogRowComponent`, `Posts::ResumeRowComponent`, `Posts::NowComponent`, `Posts::DetailComponent`;
  - a generic `Fields::ComponentValueComponent` for rendering a field group.
- **Inputs:** each component receives explicit, typed inputs, e.g. `block:`, `settings:`, `posts:`, `page:`, `urls:`. Components read no controller instance variables.
- **Behaviour:** the current partials' markup and theme classes move over unchanged; this is a behaviour-preserving port.
- **Dispatch:** `pages/show.html.erb` renders `BlockTypes.fetch(block.block_type).component.new(...)` per block; unknown types render nothing. The post list renders each post through its content type's `list_item_component`. The post detail uses `detail_component`.
- **Themes:** themes replace components through the registry, not the view path (`theme.component_for(:post_list)`, falling back to the default). Only the lookup hook is built now; there are no alternate themes yet.
- **Tailwind:** both builds must scan `app/components`:
  - the public theme build scans the public components (`app/components/blocks`, `app/components/posts`, `app/components/fields`);
  - the product build scans nothing there yet (the admin kit comes in sub-project 3).
- **Previews:** every public component gets Lookbook previews covering each built-in type's typical states.

## 6. Consumers switched to the registries

| Place | Change |
|---|---|
| `pages/show.html.erb` block dispatch | `BlockTypes` component lookup |
| `_post_list.html.erb` + `post_list/_blog/_resume/_now` | `Blocks::PostListComponent` + each content type's `list_item_component` |
| `_post_list_detail.html.erb` | `Posts::DetailComponent` via the content type |
| `PublicSite::Paths.canonical_page`, the resolver's listing fallback, `PublicPageRendering#assign_record` | blocks whose type has `lists_posts`; `lists?` via the capability |
| MCP tools (content_type enum) + `Mcp::PostSerializer` | enum from `ContentTypes.names` (resolved after boot); the serializer emits `fields` (untranslated + the requested locale's translated values) in place of raw `metadata` |
| `StarterContent::SECTIONS` | built from each content type's `starter` declaration |
| Mind graph colours (`mind_graph_controller.js`) | per-type `color`, passed from the view as data |
| Avo: content-type filter, post and block resources, `nested_content_blocks` + `_content_block_row` | options from the registries; block settings inputs rendered from the schema by a small generic field renderer (throwaway until the admin) |
| `ContentBlocks::Save`, `Posts::Save`, `Pages::Save` | string types; `settings`/`fields` assigned through the `FieldSet`; invalid values come back as error Results with per-field keys |
| `db/seeds.rb` | string types, typed fields |

## 7. Error handling

- **Unregistered type on save:** a validation error (`"isn't a registered block type"` / `"… content type"`), which services return as an error Result.
- **Invalid field values:** per-field validation errors keyed by path.
- **`fetch` of an unknown type:** raises `UnknownType`. Rendering and path-sync boundaries use `find` and skip, logging a warning, so a stale record never 500s the public site.
- **Components:** a component registered with nested component fields raises at registration (a developer error, caught at boot).

## 8. Testing

- **Unit:**
  - registries: register, fetch/find, names, capabilities, reset on reload, duplicate registration replaces;
  - `FieldSet` for every field type: casting, blanks → nil, required, select, min/max, dates, URLs, `content_type`, components (single and list), nested error paths, translated fields and fallback reads, `to_h` round trip;
  - each built-in definition;
  - each view component rendered in isolation (`render_inline`).
- **Open-type proof:** a test-only block type and content type (plus a component) registered inside the test. They need no migration, render through their components, get canonical URLs when their block lists posts, appear in MCP schemas, and validate typed fields through services.
- **Regression:** existing public, routing, sitemap, MCP, Avo, service and setup tests stay green. They are adjusted only for `page_id` → `owner`, string types, `post.fields`, and moved partials.
- **Lookbook:** previews render without errors (one smoke test iterating over previews).

## 9. Out of scope

- Admin-defined content types (`content_type_definitions` table and screen), a Phase 3 item. The schema format is ready for it.
- The `ContentSpiel.plugin` DSL, plugin versioning and a sample plugin.
- Snippets and templates as block owners (only the polymorphic column exists).
- Dynamic zones and nested components.
- Tiptap and the rich-text storage change (sub-project 4).
- The admin UI kit as components (sub-project 3).
- Any new built-in block or content types.
