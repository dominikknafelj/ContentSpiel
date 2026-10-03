# CS Studio design pass — session handoff

Written 2026-10-03 from a Claude Code session that ran in the photofolio repo by mistake. It carries everything a new session in this repo needs to continue. Nothing here is implemented yet; no app code has changed.

## Where things stand

1. A previous session took 33 screenshots of CS Studio (`tmp/screenshots/cs-studio/01–33`).
2. Claude Design reviewed them and produced a handoff, **v1** (`~/Downloads/Content Spiel design system.zip`; extracted copy in `tmp/design/design_handoff_cs_studio_v1/`, not tracked). Start with its `README.md`.
3. The handoff was read against the code. Gaps went into `docs/product/2026-10-03-cs-studio-design-gaps.md` and were posted to Claude Design in the "Content Spiel design system" project (https://claude.ai/design/p/dd6bda29-ca72-4e73-8a55-de40f9a18257).
4. Claude Design answered all 18 gap items and produced **"CS Studio handoff v2"**. It is a download button in that project's chat and **has not been downloaded yet**. Its reply said a background check was still reviewing the files.
5. **Update, later on 2026-10-03 (this repo's session):** v2 was downloaded and extracted to `tmp/design/design_handoff_cs_studio_v2/`. It was read against the code again; 40 remaining gaps went into `docs/product/2026-10-03-cs-studio-design-gaps-round-2.md` and were posted to the same Claude Design project. Claude Design answered all 40 and produced **"CS Studio handoff v3"**, extracted to `tmp/design/design_handoff_cs_studio_v3/` (README section 10 has one answer per item, A1–C40; new mock `Studio States v3.dc.html`, one card per item). v3 is the package to build from.
6. The spec has not been started. Open product decisions for the user, from v3's "[You decide]" items: store the per-field source text (word diff for outdated translations), a stored translation-state table (percentages, Posts/Media translation filters, dashboard card), the 12-character password rule, a required token name, `api_key_saved_at`, and the Settings › Site all-languages-in-one-form approach.

## Next steps

1. Download the v2 package from the Claude Design project and extract it (e.g. to `tmp/design/design_handoff_cs_studio_v2/`). Read its README section 9 first: one answer per gap item, keyed A1–11 and B12–18.
2. Write the spec under `docs/superpowers/specs/` (brainstorming skill, architectural path), then get the user's review.
3. After approval, write the plan under `docs/superpowers/plans/`.

## Decisions the user has made

- **Slot in the roadmap:** do this now, as the "admin polish" sub-project, before Phase 3 and before the German admin UI.
- **Process:** spec, then plan, then build.
- **Draft revisions on live content:** decide later. Build with today's behaviour (edits to a Live item go live at once) and leave room in the editor header for "Publish changes".
- **User display name:** yes, add an optional `name` to `User`, falling back to the email.
- **Media detail:** becomes a side panel on the Media grid (deep link `?selected=ID`).
- **Slicing:** proposed three rounds, one PR each. The user was asked and did not object, but **did not confirm explicitly**; confirm it in the spec review.
  - Round 1: tokens, theme switch, sidebar, shared chips/tabs/form controls, the bugs.
  - Round 2: page and post editors, dashboard, posts list, translations matrix.
  - Round 3: settings with languages, media, groups, AI assistant, the remaining list screens.

Assumptions made, not confirmed by the user:

- ⌘K quick jump searches titles of pages, posts and settings only. Full-text admin search stays the separate roadmap item.
- "Invite user" only renames the header button. The invite-link flow stays the separate roadmap item (Invites).
- Mind graph gets the colours, the legend and the layout bug fix, with no redesign.

## What v2 changed (from Claude Design's reply, files not yet read)

- README section 9 answers each gap item and lists the new mockups.
- Design system page: section 06 was never missing; it was "Tailwind & Avo mapping" and is now "Tailwind mapping". A new section 08 draws dialogs, the ⌘K palette, toasts, validation, loading states, pagination, open menus, drag states, the password field and empty states. The rules moved to section 09.
- Save rule: content autosaves; settings-type screens get one sticky save bar (replacing "one Save per section").
- Editor header: the default is now the "edits go live straight away" variant; a drafts switch shows the future "Publish changes" header.
- API key: no part of a key or token is shown after creation. The chip reads "Key saved · added 2 Oct".
- Content-type colours: `--cs-cat-5` and `--cs-cat-6` added; from the 7th type on the six colours are reused as hollow rings.
- Translation chips: missing is a dashed border plus a ○ glyph; done has no check mark.
- New rule: red is only for destructive actions and failures.
- Narrow-screen breakpoints added. Setup wizard restyled to match sign-in, with Show/Hide and a 4-bar strength meter. Mockups added for the screens that had none.

## How the handoff maps onto the code

Read from source on 2026-10-03 (main at `395ae29`); nothing was run in a browser.

### Admin structure

- **Layout:** `app/views/layouts/admin.html.erb` is the whole shell: modules nav, optional tree column (`content_for :tree`), and `<main>` wrapping `<turbo-frame id="content">`. Sign-in and password reset use `app/views/layouts/product.html.erb`.
- **Sidebar:** inline in the layout, no partial or component. Items come from `Admin::BaseController::MODULES` (`app/controllers/admin/base_controller.rb:45-61`), filtered by `admin_modules`. Today it is a flat list of 14 with no groups, no badges and no account block; the footer holds the theme toggle, "Change password" and "Sign out". Languages is not a nav item; it lives at `settings/languages`.
- **Icons:** hand-inlined SVGs in `app/views/admin/shared/_icon.html.erb` (one `case`, raises on an unknown name). No icon gem.
- **Page tree:** `Admin::TreeComponent` and `Admin::TreeNodeComponent`. The column is `18rem` (`lg:grid-cols-[16rem_18rem_1fr]`). Each row always renders the status badge (including Live), the `!` translation marker and the child count (including `0`). Drag and drop is the `admin--tree` Stimulus controller (SortableJS).
- **Views:** screens are ERB under `app/views/admin/*`; reusable pieces are ViewComponents under `app/components/admin/` (base `Admin::AdminComponent`), namespaces `Admin::`, `Admin::Columns::`, `Admin::Fields::`, `Admin::DashboardScreen::`, `Admin::MediaLibrary::`, `Admin::TranslationScreen::`, `Admin::TrashScreen::`, plus `Media::PickerComponent`.
- **Shared class strings:** `SetupHelper` (`setup_input_class`, `setup_label_class`, `setup_primary_button_class`, `setup_secondary_link_class`).
- **Routes:** `config/routes.rb:26-244`.

### Tokens and theming

- `app/assets/tailwind/content-spiel.css` has no `--cs-chrome` and no `--cs-cat-*` today. No existing token value differs from the handoff.
- **Take from the handoff only the new tokens** (`--cs-chrome`, `--cs-cat-*`, and their `--color-*` mappings). Do not take the rest of its `content-spiel.css` / `content-spiel.tailwind.css`, because it:
  - sets `color-scheme` inside the token blocks (the repo sets it per layout, and a comment forbids it in the token file);
  - renames the font files (`fonts/archivo-400-normal-latin.woff2`), which breaks Propshaft resolution of `archivo-latin-400-normal.woff2`;
  - maps `--font-sans` / `--font-mono` instead of `font-cs` / `font-cs-mono` (the repo comment says that restyles public and auth pages through preflight);
  - adds `@import "tailwindcss"`, which conflicts with `source(none)` in `application.css`.
- **Theme switch today:** `app/views/shared/_theme_head.html.erb` (nonce'd inline script, reads `localStorage["cs-theme"]`), `_theme_toggle.html.erb` (two-state button), `app/javascript/controllers/theme_controller.js`. There is no `auto` state. `test/system/theme_toggle_test.rb` clicks "Light mode" / "Dark mode".
- **Builds:** the admin build is `app/assets/tailwind/application.css` (`source(none)` plus explicit `@source` lines; new view or component directories need one). The public theme is a separate build.

### Shared UI pieces today

- **Status:** `Admin::StatusBadgeComponent`. Already an outlined chip with a dot; no hide-when-Live option. Used in the tree node, record header, post form, posts index and dashboard row.
- **Translation chips:** `Admin::TranslationScreen::StateBadgeComponent`. Missing is red today. The tree has its own `!` marker (`tree_node_component.html.erb:26-33`).
- **Language tabs:** `Admin::LanguageSwitcherComponent` (mono uppercase links, red dot for missing, no overflow). Used in `record_header_component`, `post_form_component`, `settings_form_component` and `media_library/detail_component`.
- **Content-type dot:** inline `style` with a hex colour from the type definitions (`app/models/content_types/blog.rb`, `now_update.rb`, `resume_entry.rb`), at `app/views/admin/posts/index.html.erb:~83`. The mind graph uses the same colours.
- **Selects:** native, `setup_input_class`, no custom chevron.
- **File inputs:** bare, in `app/views/admin/media/index.html.erb:20`, the `Media::PickerComponent` upload tab, and the logo (`admin/shared/_image_upload_field.html.erb`, `Admin::Columns::ImageColumnComponent`).
- **Confirmations:** `Admin::ConfirmDialogComponent` (native `<dialog>`), opened by inline `onclick="…showModal()"` at 12 call sites. No `data-turbo-confirm` anywhere.
- **Flash and empty state:** `Admin::FlashComponent` and `Admin::EmptyStateComponent` exist.
- **Dates:** absolute `strftime` almost everywhere; only `trash_screen/row_component.html.erb:26` is relative with a title.
- **Pagination:** Media, Trash, Audit log and Translations use offset Previous / Next. The posts list is unpaginated (`posts_controller#index` calls `.to_a`). No pagination gem.

### Per screen

Stimulus controllers are in `app/javascript/controllers/admin/`.

| Screen | Controller | Views / components |
|---|---|---|
| Sign-in | `sessions_controller` | `views/admin/sessions/new.html.erb` (product layout) |
| Dashboard | `dashboard_controller` | `dashboard/show`; `DashboardScreen::{QuickCreate,Column,Row}Component` |
| Pages editor | `pages_controller`, `content_blocks_controller`, `tree_controller` | `pages/{index,show,new}`; `RecordHeaderComponent`, `PageSettingsFormComponent`, `Columns::*`, `BlockCardComponent`, `BlockPickerComponent`, `SaveStatusComponent` |
| Posts list | `posts_controller#index` | `posts/index.html.erb` |
| Post editor | `posts_controller` | `PostFormComponent`, `TagInputComponent`, `RelatedPostsComponent`, `FieldComponent` + `Fields::*` |
| Translations | `translations_controller`, `translation_confirmations_controller` | `translations/index`; `TranslationScreen::ListComponent` |
| Settings | `settings_controller` | `settings/show`, `_ai_key_field`, `_ai_test_result`; `SettingsFormComponent` |
| Languages | `languages_controller` | `languages/index.html.erb` |
| Media | `media_controller`, `media_assets_controller` | `media/{index,show,picker}`; `MediaLibrary::{Grid,Detail}Component`; `Media::PickerComponent` (rendered once in the layout) |
| Groups | `groups_controller` | `groups/{index,_form,edit,new}`; `PermissionMatrixComponent` |
| Users | `users_controller` | `users/{index,edit,new,_access_fields}` |
| Tags | `tags_controller` | `tags/index` |
| Trash | `trash_controller` | `trash/index`; `TrashScreen::{List,Row}Component` |
| Audit log | `audit_events_controller` | `audit_events/{index,show}`; `AuditChangesComponent` |
| System status | `system_status_controller` | `system_status/show` → shared `setup/_system_check_results` |
| AI assistant | `api_tokens_controller` | `api_tokens/{index,create,_connection}` |
| Mind graph | `mind_graph_controller` | `mind_graph/show` (d3-force) |
| Change password | `accounts_controller` | `accounts/edit` |
| New page / post | `pages#new`, `posts#new` | full frame pages today, not modals |

Details the spec needs:

- **Two editor headers.** `record_header_component.html.erb` (pages) shows Preview, Activity, Publish now, Unpublish, Schedule… and Move to trash as equal buttons. The post editor does not use it; `post_form_component.html.erb` (169 lines) has its own copy. Build the new header once and use it for both.
- **Rich-text toolbar:** `Columns::RichTextColumnComponent::TOOLBAR` (`rich_text_column_component.rb:61-78`), 16 flat buttons in a `flex-wrap` container (Tiptap 3).
- **Side-by-side original:** `plain_column_component.html.erb` and `rich_text_column_component.html.erb`, `grid md:grid-cols-2`. The reference card holds the per-field Translate button today.
- **Tags input:** datalist autocomplete over comma-separated text, not chips.
- **Permission "matrix":** `PermissionMatrixComponent` is a nested checkbox list today.
- **Settings:** one autosaving form, no in-page nav; the AI key is a separate form. Social links are fixed rows.

### The handoff's eight bugs

1. **Double slash in the slug helper:** `app/components/admin/columns/slug_column_component.html.erb:16` renders `<%= base_url %>/`; Home's path is `"/"` (`app/models/public_site/paths.rb:200`), giving `//about` and `/de//about`. The component has an unused `preview_url` that already chomps the slash. Callers: `page_settings_form_component.rb:93`, `post_form_component.rb:156`.
2. **"days (0 = never)" wraps:** `app/components/admin/settings_form_component.html.erb:56-60`.
3. **Tree truncation:** `tree_node_component.html.erb` always renders the badge, the `!` and the child count.
4. **Starter pages offered when pages exist:** `app/views/admin/pages/index.html.erb:16`, with `StarterContent#added?` (`app/models/starter_content.rb:90-95`) true only when every starter page exists. Rendered twice (the "More" menu and the empty state).
5. **Toolbar wraps:** the flat `TOOLBAR` plus `flex-wrap` (above).
6. **AI suggestion:** `translation_screen/suggestion_component.{rb,html.erb}` is read-only, sits outside the field, and is not passed the provider or model. **The `[es] …` text is not a production leak:** it comes from a `StubProvider` registered only in tests (`test/system/admin/translations_test.rb:27`, `test/integration/admin/translation_suggestions_test.rb:24`).
7. **Media "Move to trash" reason:** `media_library/detail_component.html.erb:~73-75`. The "Used on" list already sits just above it.
8. **Sign-in styling:** `app/views/admin/sessions/new.html.erb` uses raw scaffold classes (`bg-blue-600`, `rounded-md`, …). `passwords/{new,edit}` were not checked for the same.

### Data model

- `User` has no `name` column (`db/schema.rb:284-291`).
- Languages are not a table: `site_settings.locales` is a jsonb array whose order is the language order; `default_locale` is a string column. Fallbacks are an array per entry, read by `Locales.fallback_chain` (`app/models/locales.rb:28-32`). A single "Falls back to" select writes a one-element array; no schema change.
- The default language is changed in Settings today, not on the Languages screen.
- No command palette or global search exists.

### Tests

- Minitest with fixtures. System tests in `test/system/admin/` (17 files), Cuprite. Integration tests in `test/integration/admin/` (30 files) carry most admin coverage. Component tests in `test/components/admin/**`; Lookbook previews in `test/components/previews/` (52 files), smoke-tested by `previews_test.rb`.
- Tests that pin current UI text: `sign_in_via_form` (placeholders "Enter your email address" / "Enter your password", `nav[aria-label='Modules']`), `theme_toggle_test.rb`.

### Constraints

- Importmap only: new JS is a Stimulus controller or a vendored pin.
- The UI kit is ViewComponents; every component has a Lookbook preview and a component test (cs-studio spec §4.3, §9). Build the handoff's "partials" (`_status_chip.html.erb` and friends) as components.
- Never define `Admin::Media`, `Admin::Trash`, `Admin::Translations`, `Admin::AI` or `Admin::Ai`.
- Colours come from tokens; no `dark:` colour variants.
- Forms cannot nest: the confirm form and the media picker live once in the layout, outside `#content`.
- Links inside `#content` that must refresh the tree use `data-turbo-frame="_top"`; nav links thread `admin_url_options` to keep the editing locale.
- Admin strings are hard-coded English (admin i18n is a later roadmap item).
- Long, load-bearing code comments are the norm; match that density.

## Roadmap items this pass touches

- **Closes interim states:** tree column polish, posts list pagination, drag reorder for languages.
- **Absorbs "Could" items:** audit-event feed on the dashboard, inline page quick create, side-by-side translate mode.
- **Fixes:** the open mind-graph layout bug (nodes animate outside the box).
- **Overlaps, keep scoped:** admin global search (⌘K), Invites ("Invite user" button).
- **Depends on later work:** "Unpublished changes" and "Publish changes" need pending revisions (Phase 3 versioning).

Update `docs/roadmap.md` when the spec lands.
