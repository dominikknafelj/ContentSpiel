# Translation helpers and AI translation

Sub-project 6e of the own-admin roadmap, built after 6c (dashboard, PR #33). Approved in brainstorming on 2026-10-02. This is the binding spec for the implementation plan.

## 1. Purpose

CS Studio already supports translators in three ways (sub-projects 1–4):
- it shows the primary-language original beside every translated field, with an empty `data-translate-slot` reserved per field;
- it marks a language in the editor's switcher when required fields are empty;
- it generates slugs per language.

Four things are still missing:
- **A.** A translator can't see which items are incomplete in a language without opening each one.
- **B.** Nothing tells them that a translation is out of date after the original changed.
- **C.** The site title and tagline aren't translatable, so the German site shows an English tagline.
- **D.** The reserved "Translate" slot is empty.

**Success:**
- A translator opens a Translations overview for German and sees every page, post and image that is missing or outdated in German, with links into the editor.
- After someone edits the English title of a translated post, the German title shows "Original changed since this was translated" until it's revised or marked up to date.
- `/de` shows the German tagline.
- An editor with `ai.translate` presses **Translate** on a field, reviews the suggestion, and presses **Use**, which autosaves it. Nothing machine-written is saved without that click.

## 2. Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Scope | **A + B + C + D**: status in lists and an overview, outdated detection, translatable site title and tagline, AI translate. If the plan grows too large, ship two PRs: A–C, then D. |
| AI provider | **A pluggable `AI::Providers` registry with one built-in, Anthropic Claude.** Provider, API key (encrypted) and model are set in Settings. |
| Applying AI text | **A suggestion first**, with Use / Discard. Only Use fills the field, which then autosaves. "Translate empty fields" suggests in bulk, with "Use all". |
| Who may use it | **A new `ai.translate` permission** (Admin, Editor) plus the record's edit right. Configuration needs `settings.manage`. Every request is audited, without the text. |
| Outdated detection | **Per field, by a digest of the original**: `translation_sources` jsonb. Values saved before this feature count as "unknown", never outdated. |

## 3. Translation tracking (B)

### 3.1 Data

Each translatable model gets `translation_sources`, a jsonb column, not null, default `{}`, shaped `{ "field" => { "locale" => "sha256-hex" } }`. The models are:
- `pages`
- `posts`
- `content_blocks`
- `media_assets`
- `site_settings`

"Translated fields":
- **Page:** `title`, `subtitle`, `meta_title`, `meta_description`, `hero_alt`. Not `slug`, which is generated per language.
- **Post:** `title`, `excerpt`, `body`, plus translated fields of its content type's schema.
- **ContentBlock:** `caption`, `body`, plus translated fields of its block type's schema.
- **Media::Asset:** `alt`, `caption`.
- **SiteSetting:** `title`, `tagline` (§5).

The concern reads the list from each model's own `translates`/schema definitions. It must not be hard-coded twice.

### 3.2 `Translations::Tracker` (model concern)

- **Primary language:** `Locales.default`, read at save time. Targets are the other `Locales.enabled`.
- **Digest:**
  - plain values: SHA-256 of the stripped string;
  - rich text: SHA-256 of the canonical JSON of `RichText::Document#normalized`, so a pure formatting no-op doesn't change it;
  - blank: no digest.
- **On save, a `before_save` for each translated field and target locale whose value changed:**
  - if the value is now present, store the **current** primary-language digest for that field;
  - if it's now blank, delete the entry.
  - Changes to the primary-language value itself never touch `translation_sources`.
- **`#translation_state(field, locale)`** returns:
  - `:missing` if the target value is blank;
  - `:unknown` if it's present but has no digest (saved before this feature, or never translated through CS Studio);
  - `:outdated` if the digest differs from the current primary digest;
  - otherwise `:current`.
  - Asked for the primary locale itself, it returns `:current`, or `:missing` if blank.
- **`#confirm_translation!(field, locale)`** stores the current primary digest without changing the value. It's called only from the confirm service (§3.4).

### 3.3 `Translations::Status`

- `Translations::Status.for(records, locales: Locales.enabled - [Locales.default])` returns `{ record => { locale => :complete | :missing | :outdated } }`.
- **`:missing`:** a *required* translated field is blank. This is the same rule as today's switcher dot; reuse that code, don't duplicate it.
- **`:outdated`:** otherwise, if any translated field is `:outdated`.
- **`:complete`:** neither. `:unknown` fields count as complete.
- **Pages and posts include their blocks:** the worst block state wins, with missing over outdated over complete.
- **Images and the site settings** stand alone.
- **Batched:** one query loads the listed records' blocks, so a list of N records costs a constant number of queries.

### 3.4 Confirming

- `Translations::Confirm.call(record, field:, locale:)` needs the same right as editing that record in that state:
  - `pages.edit`/`posts.edit` plus `publish` when published (the existing autosave rule, `ContentBlocks::OwnerPermissions` for blocks);
  - `media.manage` or uploader for images;
  - `settings.manage` for the site settings.
- It records `<subject>.translation_confirmed` (field, locale).

## 4. Status in CS Studio (A)

- **Editor:**
  - **Switcher:** the language switcher shows two states per language, "missing" (the existing dot) and "outdated" (a second marker with its own label for screen readers).
  - **Field notes:**
    - each `:outdated` field shows "Original changed since this was translated", with a **Mark as up to date** button, next to the original text;
    - `:unknown` shows nothing.
  - **Where:** this applies to the page form, the post form, the block cards, the media detail panel and Settings.
- **Posts index:** a "Languages" column with a small badge per target language: ✓ complete, ! missing, ↻ outdated. Each badge has a title and an accessible label.
- **Page tree:** a single marker on a page that isn't complete in some language, with a tooltip listing them.
- **Translations overview:**
  - `Admin::TranslationsController#index` at `/<admin>/translations?locale=xx`.
  - Its locale tabs list the non-default enabled languages.
  - It lists readable pages, posts and images that are `:missing` or `:outdated` in that language, grouped by type, with their state and a link to the editor in that locale. Paging follows the Media module (about 50 per page).
  - It's read-scoped through `AccessControl.scope`, so trashed items are excluded.
  - Its sidebar entry "Translations" shows for `pages.read` or `posts.read`, and only when more than one language is enabled.

## 5. Translatable site title and tagline (C)

- `SiteSetting` `translates :title, :tagline` (Mobility jsonb, same backend and fallbacks).
- **Migration:** convert both columns to jsonb, moving the current string into `{ default_locale => value }`. Its `down` restores the default-locale string.
- **Validation:** the title must be present in the default locale.
- **Settings form:** the language switcher, the original beside each field, and Translate and status like other forms.
- **Readers:** the public layout and header, meta tags, the sitemap and setup read them in the current locale with fallback. Grep for `site.title`/`tagline` and `Current.site.title`.
- **Setup:** the setup wizard writes the default locale.

## 6. AI translation (D)

### 6.1 Providers

- `AI::Providers` is a registry:
  - `register(name, klass)`;
  - built-in names are unprefixed, plugin names `owner/name`, and a duplicate raises `AI::DuplicateProvider`;
  - it's reset and re-registered in `config/initializers/types.rb`'s `to_prepare`.
- **Interface:** `#translate(texts:, from:, to:, format:)`.
  - `texts` is an Array of Strings; `format` is `:plain` or `:markdown`.
  - It returns an Array of translated Strings, in the same order and of the same length.
  - It raises `AI::Error` with a user-facing message.
  - `#test_connection` returns true or raises `AI::Error`.
- **Built-in `anthropic` (`AI::Providers::Anthropic`):**
  - uses the official `anthropic` Ruby gem (added to the Gemfile);
  - the model comes from Settings, default `claude-sonnet-5`.
  - **Request:** one Messages API request per call, with a fixed system prompt:
    - translate faithfully from `<from>` to `<to>`;
    - keep tone and proper names;
    - keep Markdown structure, `::directive{…}` lines and `cs:` link targets unchanged;
    - return only the translations.
  - **Response:** each text is sent with a numbered delimiter, and the response is parsed back into the same count. A count mismatch raises `AI::Error`.
  - **Timeout:** 60 s.
  - **Errors:** authentication, rate-limit, overload and network errors map to clear messages.

### 6.2 Settings ("AI assistant" section)

- New `site_settings` columns:
  - `ai_provider` (string, nullable);
  - `ai_model` (string, nullable);
  - `ai_api_key` (text, nullable, `encrypts :ai_api_key`).
- **Active Record encryption keys** are configured through credentials or environment:
  - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `..._DETERMINISTIC_KEY`, `..._KEY_DERIVATION_SALT`;
  - with fixed values in `config/environments/test.rb` and generated values for development;
  - setup is documented in CLAUDE.md and the deploy notes.
- **The key is never rendered.** The form shows "API key: set" with a **Replace** field, or an empty field when unset. Submitting a blank value keeps the stored key, and a **Remove key** action clears it.
- `AI.configured?` is true when there's a provider, a registered provider class and a key.
- **Test connection** (`settings.manage`) calls `#test_connection` and shows OK or the error inline.
- `ai_api_key` stays out of logs: the existing `_key` filter already matches it. It's also added to `Audit::Snapshot`'s `NEVER_STORED`, so `settings.updated` records "AI key changed" without the value.

### 6.3 `AI::Translate`

- `AI::Translate.call(record, fields:, to:, actor:)`.
- **Authorization:**
  - `authorize!("ai.translate", nil)`;
  - plus the record's edit right, as in §3.4.
  - It refuses if `!AI.configured?` or if `to` is the default locale.
- **Batching:**
  - it reads the primary-language values of `fields`, skipping blank ones;
  - rich-text bodies go as `Document#to_markdown`, format `:markdown`;
  - the cap is 20 fields and 30,000 characters per call; above it, it fails with "Too much at once — translate in parts".
  - It calls the provider once.
- **Output:**
  - it returns `{ field => suggestion }`;
  - a rich-text suggestion is a `RichText::Document` parsed with `from_markdown`, its warnings returned alongside;
  - **nothing is saved**.
- **Audit:**
  - on success, `ai.translated` with subject = record and metadata `{ fields:, from:, to:, provider:, model:, characters: }`, with no text;
  - on a provider error, no event.
- It's an `ApplicationService`, so `authorize!` and `record_event` appear in `#call`.

### 6.4 Editor UI

- **Visibility:** every translated input in a non-default language, whose record the actor may edit, gets a **Translate** button in its `data-translate-slot` when `AI.configured?` and `can?("ai.translate")`.
- **Request:** `POST /<admin>/translations/suggest` with record type, id, fields and locale (`Admin::TranslationsController#suggest`). It answers with Turbo Streams that put a suggestion box under each field: the suggested text, or a rendered preview for rich text, plus **Use** and **Discard**.
- **Use:**
  - a plain field: copies the text into the input and triggers that form's normal autosave;
  - a rich-text body: loads the suggested document into that block's or post's Tiptap editor, which autosaves.
  - The saved change is an ordinary edit by the user (with a fresh digest, §3.2).
- **Discard:** removes the box.
- **Bulk:**
  - **Translate empty fields** sits in the editor header of a non-default language.
  - It requests every `:missing` translated field of the record and its blocks, splitting into several calls by the cap.
  - When all suggestions are in, a **Use all** button appears.
- **States and errors:**
  - a spinner shows while a request runs;
  - a provider error, timeout or refusal shows inline under the button;
  - rich-text repair warnings show in the suggestion box.

## 7. Permissions and audit

| Action | Needs |
|---|---|
| See status and the overview | read rights (scoped) |
| Mark as up to date | the record's edit right (§3.4) |
| Request an AI suggestion | `ai.translate` + the record's edit right |
| Use a suggestion | the ordinary autosave rights |
| Configure AI, test the connection | `settings.manage` |

- **New permission:** `ai.translate` ("Use AI translation", area "Content"). It's seeded onto Admin and Editor by a data migration, mirroring `GrantMediaManageToBuiltInGroups`, and by `AccessControl::Seeds`. Fixtures are updated.
- **New audit actions:**
  - `ai.translated`;
  - `page.translation_confirmed`, `post.translation_confirmed`, `block.translation_confirmed`, `media.translation_confirmed`, `settings.translation_confirmed`.

## 8. Testing

- **Tracker:**
  - saving a target field records the digest;
  - changing the original makes it `:outdated`;
  - a no-op rich-text change doesn't;
  - clearing removes the entry;
  - values from before the feature are `:unknown`;
  - confirming clears the outdated state;
  - changing the default locale in Settings is handled. A field is then judged against the new primary, and digests recorded against the old primary read as outdated; this is accepted and documented.
- **Status:**
  - each state, and the precedence between them;
  - block roll-up;
  - batched, with a constant query count for 1 vs 20 records.
- **UI:**
  - the posts index column and the tree marker;
  - the overview (scoping, no trashed items, locale filter, paging);
  - the switcher's two states;
  - the outdated note and the Mark as up to date flow;
  - the sidebar entry with only one language enabled.
- **Site title and tagline:**
  - the migration up and down;
  - the public `/de` tagline and the fallback;
  - per-locale editing in Settings;
  - setup writes the default locale.
- **Providers:**
  - the registry;
  - `Anthropic`, against a stubbed HTTP layer: the request body (model, system prompt, numbered texts), parsing, a count mismatch, and error mapping including the timeout;
  - Markdown rich text keeps images and links.
- **`AI::Translate`:**
  - without `ai.translate`, or without the edit right, it's denied;
  - not configured: it refuses;
  - the default locale as target: it refuses;
  - it saves nothing;
  - audit metadata, with no text;
  - the cap;
  - a provider error leaves no event.
- **Settings:**
  - the key is encrypted at rest (the raw column isn't the key);
  - it's never rendered;
  - a blank submit keeps it, and Remove clears it;
  - it's never in the audit snapshot or in logs;
  - the test connection result shows inline.
- **System tests (Cuprite, a stub provider registered in tests):**
  - translate a German title, press Use, see it saved;
  - Translate empty fields, then Use all;
  - edit the English title, see the German field flagged, Mark as up to date clears it;
  - the overview lists the missing item.

## 9. Out of scope

Recorded in `docs/roadmap.md`:
- a monthly AI budget;
- more built-in providers (an OpenAI-compatible one);
- AI for excerpts, alt text and summaries;
- background whole-site translation;
- translation memory and glossary;
- a side-by-side translate mode;
- AI tools over MCP (MCP clients are already AIs).

## 10. Amendments

Behaviour-changing rulings made during implementation (plan `docs/superpowers/plans/2026-10-02-translation-helpers.md`, ledger `.superpowers/sdd/2026-10-02-translation-helpers/progress.md`). Where one contradicts the text above, the amendment wins.

**Tracking (§3)**
- **Tracked columns are derived, not listed.** `Translations::Tracker` tracks the model's own Mobility `translates` names (`mobility_attributes`) minus `except:` (default `slug`), plus the `translated: true` fields of the schema reader named by `tracks_translations schema:`. §3.1's per-model lists describe the result, not a second source. The method is `confirm_translation` (no bang, the caller saves), not `confirm_translation!`.
- **Every stored non-primary locale is tracked**, not only the enabled ones, so a language disabled and re-enabled later keeps its digests.
- **Group fields are digested as canonical JSON.** A translated schema group field's value (a Hash/Array) is digested with its keys sorted at every level. Postgres jsonb reorders keys, and a key-order difference alone must not read as an edit.
- **`translation_sources` is kept out of audit `field_changes`** (`IGNORED_CHANGES`) but stays in the snapshot. It's bookkeeping, not an edit anyone made.
- **A cleared original reads `:unknown`, not `:outdated`.** When the primary value is blank there's nothing to compare against, and an outdated note would offer "Mark as up to date" for an original that doesn't exist.

**Status (§3.3, §4)**
- **Images can be `:missing`.** An image is missing in a language when its original has alt text and that language's alt is blank. Alt plays the title's part, and the caption stays optional. Without this an untranslated image could never be missing (nothing about it is required), so it would never show up in the overview. An image without an original alt has nothing to translate and is complete everywhere.
- **The site settings are missing where the site title is blank.** The tagline stays optional.
- **The switcher shows missing and outdated independently.** A language can show both markers at once. §3.3's precedence (missing beats outdated) only applies to the single record state used by lists, the tree and the overview.
- **Mark as up to date writes with `update_columns`.** Only `translation_sources` changes: no callbacks run and `updated_at` doesn't move, so the editor's next autosave isn't reported as "Changed elsewhere". The button sits inside the autosave form, but it posts the layout's separate confirm form through the `form=` attribute, because forms can't nest.

**Site title and tagline (§5)**
- **Changing the default language copies the title and tagline from the old default when the new one has none.** Otherwise the title-in-default-locale validation would refuse the change in both the setup wizard and Settings. Cost: the new default shows the old language's title until someone edits it. `SiteSetting` answers the tracker's primary/target locale hooks from its own columns to avoid recursion through `Locales`.
- **The Settings form posts its own editing language** (`?locale=`) and re-renders when the default language changes. Before this, later autosaves after a default-language change wrote the stale title into the new default. `Settings::Save` ignores `title`/`tagline` given through `attributes:`; they arrive per locale through `translations:` only.

**AI (§6)**
- **The API key has its own small form** with Save key and Remove key. It isn't part of the settings autosave, so a half-typed key is never saved. Remove key asks through the existing confirm dialog component (`Admin::ConfirmDialogComponent`).
- **Whether a key is set is known without decrypting it** (`SiteSetting#ai_api_key_set?` reads the stored ciphertext). Lost or rotated encryption keys therefore never break the Settings screen. Remove and replace still work, and a provider call with an unreadable key fails with "The stored API key can't be read — enter it again in Settings." There's no boot-time check for missing encryption keys: a production server without them fails when someone saves a key, and not before.
- **The Anthropic client uses `max_retries: 0` and a pinned `base_url`.** One click can't block for 3 × 60 s, and the environment can't redirect the key to another host. Cost: a transient provider error isn't retried; the user presses Translate again.
- **Responses are trimmed of leading and trailing newlines only, never indentation.** An empty translation of a non-blank original raises `AI::Error`.
- **The per-request cap is 20 fields and 12,000 characters** (not 30,000), so one request reliably finishes inside the 60 s timeout. "Translate empty fields" splits on the client into requests of one record each, within the caps, sent one after another; a failed part doesn't discard the others. A single field larger than the cap is sent alone and gets "Too much at once — translate in parts" under it.
- **"Empty" means empty in the editor now**, not `:missing` at page load. Fields typed into or filled by Use since the page loaded are skipped, and only fields with a Translate button (ones this viewer may edit and translate) are considered.
- **`ai.translated` has no snapshot** (`record_event(..., snapshot: nil)`), so no original text reaches the audit log. Its `subject_label` is the record's title, as on every event for that record: that's the record's name, not the text that was sent. An original that isn't text is skipped like a blank one. If every requested original is blank, the call succeeds with no provider call and no event.
- **The suggest endpoint names inputs and refuses a request with nowhere to answer.** Besides `fields[]` it takes `inputs[field]`, the DOM id of the input each suggestion is for (matched against `/\A[A-Za-z][\w-]*\z/`, echoed back as the stream target). A field without a valid id gets no stream. If no requested field has one, the answer is a bare 422 before `AI::Translate` runs: no provider call and no `ai.translated` event. A client-side error box (an answer that isn't a stream, or a network failure) has the same `type="button"` Dismiss as the server-rendered one.

**Known limitation**
- **Changing the default language to a third language flags every translation as outdated.** `translation_sources` records the digest of the original but not which language that original was in. When the default moves (en → de, with es translated from en), every es digest is compared against the new German original and differs. This is tracked in `docs/roadmap.md`.
