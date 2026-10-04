# CS Studio design pass

The "admin polish" sub-project of the own-admin roadmap, slotted before Phase 3 and before the German admin UI. Approved by the user on 2026-10-03. This is the binding spec for the three implementation plans (one per round).

## 1. Purpose

CS Studio works, but it grew screen by screen. A review of 33 screenshots found eight bugs, inconsistent patterns (three kinds of status marker, five equal buttons in the editor header, red used for both "missing" and "delete"), and screens that predate the Content·Spiel tokens.

Claude Design produced a redesign in three rounds of questions and answers. This sub-project rebuilds CS Studio to that design.

**The visual source of truth is the v3 handoff, committed at `docs/design/cs-studio-handoff-v3/`:**
- `README.md`: §1 tokens, §2 global changes, §3 bugs, §4 screens, §5 interactions, §9 answers to the first 18 questions (items A1–11, B12–18), §10 answers to the next 40 (items A1–14, B15–32, C33–40).
- `*.dc.html`: one mockup per screen, opened directly in a browser. `Studio States v3.dc.html` has one card per §10 item. `Content Spiel Design System.dc.html` sections 07–09 hold the shared patterns and the rules.

Where this spec and the handoff disagree, this spec wins. Where the handoff's §10 and its earlier sections disagree, §10 wins. References below look like "handoff §10 A2".

**Success:**
- Every CS Studio screen matches its mockup in both themes, using tokens only.
- The eight bugs in handoff §3 are fixed (the "[es] stub" item is withdrawn; it was test data).
- An editor finds the same status chip, translation chip, language tabs, dialogs, toasts and empty states on every screen.
- Nothing an editor can do today is lost, and no permission rule changes.

## 2. Decisions

From the earlier session (see `docs/product/2026-10-03-cs-studio-design-pass-handoff.md`) and approved on 2026-10-03:

| Topic | Decision |
|---|---|
| Rounds | **Three rounds, one PR each** (§6–§8). |
| Live content | **Edits to a Live item still go live at once.** The editor header is the "no drafts" variant (handoff §9 B15), with room left for "Publish changes" later. |
| User name | **Add an optional `users.name`**, shown wherever a user is named, falling back to the email. |
| Media detail | **A side panel on the Media grid** (`?selected=ID`), not its own page. |
| Word diff | **Store the source text** a translation was made from, so an outdated field can show what changed (§5.2). |
| Translation state | **A stored state per record and language** (§5.3), so percentages, filters and counts can be queried. |
| Settings › Site languages | **One form holds every language's inputs;** tabs only switch which is visible; one Save writes all (handoff §10 B32). |
| Passwords | **At least 12 characters,** as a server rule wherever a password is set (§5.5). |
| Tokens | **A required name** on API tokens (§5.4). |
| AI key date | **Store when the key was saved** (§5.4). |
| ⌘K | **Titles only:** pages, posts, media, settings and a few actions. Full-text admin search stays a separate roadmap item. |
| Invites | **No invite flow here.** The button reads "New user". |
| Mind graph | **Colours, legend, related and tag edges, filter, and the layout bug fix.** No further redesign. |

Rules that do not change:
- AI text is never saved until an editor presses **Use**.
- Per-use alt and caption overrides stay (image block, page hero, rich-text image).
- Permission scopes are per permission.
- "Not found, not forbidden" for records outside a viewer's scope.
- Every write goes through a service with `authorize!` and `record_event`.

## 3. Constraints on the build

- **Stack:** server-rendered ERB and ViewComponents, Tailwind v4, Hotwire. New JS is a Stimulus controller or a vendored importmap pin. No React, no npm.
- **Components:** the handoff's "partials" are built as ViewComponents under `app/components/admin/`, each with a Lookbook preview and a component test.
- **Tokens only:** colours come from tokens; no raw hex and no `dark:` colour variants. From the handoff's CSS take **only** the new tokens (`--cs-chrome`, `--cs-cat-1…6`, and their `--color-*` mappings). Keep the repo's font files, `font-cs`/`font-cs-mono` utilities, `color-scheme` handling and Tailwind entry file as they are.
- **Namespaces:** never define `Admin::Media`, `Admin::Trash`, `Admin::Translations`, `Admin::AI`, `Admin::Ai` or `Admin::Dashboard`. New component namespaces follow the `…Screen` pattern.
- **Forms cannot nest.** Dialog forms and the media picker live once in the layout, outside `#content`.
- **Admin strings stay hard-coded English.** The German admin UI is the next sub-project; write copy so it can be extracted later (no string concatenation of sentence parts where a whole sentence can be one string).
- **Red is only for destructive actions and failures** (handoff §9, rules).
- **Accessibility:** colour is never the only cue; chips carry a glyph and an `aria-label`; dialogs trap focus; drag has a keyboard path.

## 4. Shared patterns (built once, used everywhere)

Each is a component with a preview. The handoff reference says where it's drawn.

| Pattern | What it is | Handoff |
|---|---|---|
| Tokens and theme | `--cs-chrome`, `--cs-cat-1…6`; theme `light / dark / auto` in `localStorage["cs-theme"]`, resolved before first paint; a three-way control in the sidebar and on sign-in | §1 |
| Sidebar | Three groups (Content, People, System); a group with no visible item disappears; a Trash count badge for items the viewer can act on; "Jump to… ⌘K"; an account block with name, email and "Owner" / up to two group names "+N" / "No groups" | §2.1, §10 B15–16 |
| Status chip | Outlined chip with a dot: Live, Draft, Scheduled. Hidden for Live in lists and the tree; always shown in editors | §2.2 |
| Translation chip | Done (solid border), missing (dashed + ○), outdated (warn + ↻); a tooltip and an `aria-label` | §2.3, §9 B14 |
| Language tabs | Underline tabs with each language's own name; hollow ring = missing, solid warn dot = outdated; more than four collapse into "+N ▾" | §2.4, §10 A13 |
| Content-type dot | A dot in `cat-N` plus the type name; types 7–12 use rings; each type carries a `colour_index` set where it's registered | §2.5, §9 B13 |
| Form controls | Styled select; file drop zone with "Choose file"; password field with Show/Hide and a four-bar meter; chip input with autocomplete; prefix-cell input (slug) | §2.6, §9 A8, A10 |
| Dialog | Widths 420 / 460 / 560 / 880; destructive variant; focus rules; replaces every inline `showModal()` call | §9 A1 |
| Toast | Inverted, bottom-centre, with Undo and Retry variants; `notice` → success, `alert` → error; never for form errors | §9 A3 |
| Validation | Error summary with linked field names, plus per-field errors | §9 A4 |
| Busy and pending | Busy button; pending suggestion box; upload progress on a tile | §9 A5 |
| Pagination | A footer row "51–100 OF 312" with page links; 50 rows (48 media tiles); the audit log keeps "Load older" | §9 A6 |
| Menus | One popover panel style for ⋯ menus, split buttons and overflow | §9 A8 |
| Drag | Handle, lifted row, drop line, nest target, keyboard path, Undo toast on drop | §9 A9 |
| Empty state | Inside the card where rows would be; at most one action | §9 A11 |
| Save bar | Sticky "N unsaved changes · Cancel · Save" for configuration screens; a Leave dialog on navigation with changes | §9 B12 |
| Filters | Apply on change (debounced 250 ms for text); "Clear" only when a filter is active | §2.7 |
| Dates | Relative in lists with the absolute time in a tooltip, in the site time zone | §2.8 |
| Narrow screens | Drawer sidebar under 1280; tree drawer under 1024; side-by-side translation stacks under 880 (container query) | §9 A7 |
| 403 and 404 | Inside the Studio layout; the 404 never confirms a record exists | §10 C33 |

**The save rule** (handoff §9 B12):
- **Autosave:** content. Page and post editors, blocks, media metadata, tag rename, tree and block order.
- **Explicit save bar:** configuration. Settings, Groups, Users, Change password.
- **Instant with a confirm:** single actions. Publish, trash, restore, revoke, language off.

## 5. Data and behaviour changes

Everything else in this pass is presentation. These are the changes underneath.

### 5.1 Names and small columns

- `users.name` (string, nullable). `User#display_name` returns the name, else the email. Every "by …", the sidebar, the users list, the dashboard and the audit log use it. Edited on the user form and by the user in their account screen.
- `ContentModel` type definitions get `colour_index` (1-based, in registration order for built-ins; a plugin type states its own or gets the next free one).

### 5.2 Source text for outdated translations

Today `translation_sources` holds only a digest per field and language.

- Each entry becomes an object: `{ "digest": …, "text": …, "saved_at": … }`, where `text` is the primary-language value the translation was saved against. For rich text, `text` is the document's plain text per paragraph.
- A reader accepts both shapes, so existing digest-only entries keep working and read as "no stored source".
- Each tracked model also gets `translation_original_changed_at` (jsonb, `{ field => time }`), set when a primary-language value changes.
- **Outdated field with a stored source:** the reference card shows a word diff from the stored text to the current text, and "↻ CHANGED 1 DAY AGO" from the changed-at time.
- **Outdated field without one:** the card shows the current English, a warn border and "English changed since this was translated."
- **Rich text:** diff plain text per paragraph; a formatting-only change says "Formatting changed".
- "Mark as up to date" and saving a translation both refresh the stored text.

### 5.3 Stored translation state

A new table, `translation_states`:

| Column | Notes |
|---|---|
| `record_type` / `record_id` | `Page`, `Post`, `Media::Asset`, `SiteSetting` |
| `locale` | a target language |
| `state` | `complete`, `missing` or `outdated` (the existing precedence) |
| `missing_count` / `outdated_count` | fields in that state, blocks included |

Unique on `(record_type, record_id, locale)`.

- **Written** by `Translations::StateIndex.refresh(record)` inside the same transaction as every save that can change it: the record's own save, a block save or destroy, a confirm, a language being enabled or disabled, and a default-language change (which refreshes everything). It computes through the existing `Translations::Status`.
- **Rebuilt** by `bin/rails translations:reindex`, and by a migration that fills it once.
- **Read** by the posts list (chips and the Translation filter), the page tree markers, the Translations matrix and its summary cards, the dashboard card, and Media's "Untranslated" filter. `Translations::CachedStatus` is removed; the table replaces it.
- **Trashed records** keep their rows but every reader joins kept records only.
- "% done" counts items, not fields.

### 5.4 Tokens and the AI key

- `api_tokens.name` (string, not null). Existing tokens are named "Token 1", "Token 2", … per user by a migration. Required when issuing a token, in CS Studio and in the setup wizard.
- The tokens table shows Name, Acts as, Group, Created, Last used (with IP), Status and Revoke. No part of a token is ever shown after creation.
- A change made through a token reads "<user> via <token name>" with an MCP chip.
- `site_settings.ai_api_key_saved_at` (datetime), set when a key is saved and cleared when it's removed. The chip reads "Key saved · added 2 Oct".

### 5.5 Passwords

`User` validates a minimum of 12 characters whenever a password is set: setup, new user, change, reset. Existing passwords keep working. Error copy: "Use at least 12 characters." Seeds and fixtures get longer passwords.

### 5.6 New behaviour that comes with a screen

- **⌘K palette:** `GET /<admin>/jump?q=` returns up to five rows per group (Pages, Posts, Media, Settings, Actions), read-scoped, titles only.
- **Posts list:** pagination (50), row selection, and a bulk bar with **Publish** and **Move to trash**. Each runs the existing service per record and reports how many succeeded and how many were refused.
- **Dashboard activity feed:** content events only (page, post, block, media), limited to records the viewer can read, shown to everyone. It replaces "Recently updated" and "Recently edited by you". No sign-ins, users or settings.
- **Tags:** "Merge into…" (`Tags::Merge`: the merged tag's posts get the target tag, the merged tag is deleted, one audit event, no undo).
- **Languages:** drag to reorder; a single "Falls back to" select; the default language moves from Site to a Default radio here, confirmed in a dialog.
- **Settings:** stops autosaving and uses the save bar. The AI key keeps its own immediate form. Add language, Turn off and Default are instant actions, disabled while changes are pending.
- **Editor:** a Schedule dialog; the block ⋯ menu (Move up, Move down, Delete block…); the starter-pages offer only while Home is the only page.
- **Media:** drop anywhere to upload; "Missing alt" and "Untranslated" filters; a `NO ALT` chip.
- **Users:** "Make owner…" and "Remove owner…" dialogs over the existing owner rules.
- **Audit log:** day headers, human sentences, date presets, coalesced time spans.
- **Mind graph:** nodes coloured by type, tag nodes, related and shared-tag edges, a filter, a legend, and nodes kept inside the box.
- **Preview banner:** restyled with Studio tokens.

## 6. Round 1: foundations and bugs

One PR. After it, every screen sits in the new shell and uses the shared patterns, but screens keep their current layout.

- **Tokens and theme:** §4 row 1, including the three-way switch (the `theme_toggle` test is rewritten).
- **Shell:** the sidebar component, the account block, the Trash badge, ⌘K, the 48px top bar and drawers for narrow screens, 403 and 404.
- **Shared components:** every row of §4. Existing call sites switch over: status badges, translation badges, the language switcher, confirm dialogs, flash, empty states, selects, file inputs, pagination on Media, Trash, Audit log and Translations.
- **Data:** `users.name` (§5.1), `colour_index` (§5.1).
- **The bugs** (handoff §3):
  1. The double slash in the slug helper.
  2. The wrapping "days (0 = never)" label.
  3. Truncated tree titles (chip hidden for Live, zero counts hidden, 272px column).
  4. The starter-pages offer when pages exist.
  5. The wrapping rich-text toolbar (grouped tools, "Insert ▾").
  6. The AI suggestion box: shown inside the field, editable, with the model name.
  7. The disabled "Move to trash" reason on media.
  8. Sign-in, password reset and the setup wizard rebuilt with tokens, including the password field (§5.5 lands here).
- **Mind graph layout bug** (the open bug in memory): fixed here, since it's a bug; the colours and legend come in round 3.

## 7. Round 2: editors, dashboard, posts, translations

One PR.

- **Editor header:** one component for pages and posts (handoff §4.1, §9 B15), with the ⋯ menu, the Schedule dialog, the view-only state (handoff §10 B19) and the "Changed elsewhere" bar (handoff §10 B20).
- **Editor body:** side-by-side translation with the reference card and the stacking rule; outdated cards with the word diff (§5.2); suggestions inside the field, "Suggest translations for N empty fields", "Use all" and "Discard all" (handoff §10 B26); the slug prefix field; hero image; SEO with soft counters; content-type fields in their own group (handoff §10 B23); tags and related posts as chip inputs (handoff §10 C35).
- **Blocks:** the new card, the ⋯ menu, the post-list block's settings, the unavailable-type card, the single dashed "Add block" row, per-use alt with the library text as placeholder and a Reset link (handoff §10 A1).
- **Rich text:** the grouped toolbar; link popover; image through the media picker then a 560 dialog; YouTube and page embed dialogs (handoff §10 B25).
- **Page tree:** context-only rows, the hover "+", no handle where the viewer can't move, ↻N and ○N counts (handoff §10 B24). `/pages` opens Home (handoff §10 C34).
- **New page and New post** as dialogs.
- **Dashboard:** quick create in one row (with "Page" opening the New page dialog), three cards, and the activity feed (§5.6).
- **Posts list:** split button, toolbar, columns, pagination, selection and the bulk bar (§5.6).
- **Translations:** the matrix, summary cards, sort order and row links (handoff §4.4, §10 B18), including a Site settings row.
- **Data:** §5.2 and §5.3.
- **Carried over from round 1** (Claude Design's review of the built round 1, 2026-10-04; it checked six screens — sign-in, password reset, dashboard, page tree, page editor in German, posts list — and not yet ⌘K, dialogs, toasts, the save bar, drawers or the light theme):
  - **Wordmark:** uppercase "CONTENT·SPIEL" (12px, 700, 0.18em tracking) with the site name beneath in dim 13px.
  - **Account block:** when the name falls back to the email, show the email once; the role sits inline as "Owner" (or up to two group names), not on its own mono line (handoff §10 B15).
  - **Sidebar height:** the sidebar background is full height and sticky on long pages (it stops at the viewport height today).
  - **Language tab dots:** 7px and vertically centred on the label.
  - **Rich-text toolbar:** one row in the side-by-side view too. Round 1 made it wrap inside a narrow column instead of spilling; the stacked translation layout in this round is what gives it the width.
  - **Sign-in and reset:** the form sits directly on the page, 360px wide, with no card; the site name above the heading; heading 28px/600; the reset heading reads "Reset password"; "Show"/"Hide" in 12px/500 sans in the accent colour (as on setup and change password); "Forgot your password?" right-aligned on the Password label row, 12px; links not underlined.
  - The page tree's boxed "!" markers were already this round's work (↻N and ○N, no box, hidden at zero).
- **Carried over from round 1, second review** (Claude Design, 2026-10-04, on 18 more screens: media picker, 404, ⌘K, a confirm dialog, the save bar, the Insert menu, three at 1100px, nine in light theme):
  - **Overlay colour:** the dialog backdrop and the drawer scrim read as about 50% grey; they must be ink at 38%.
  - **Media picker:** verify first — in the screenshot the picker sat at the bottom, cut off, with the page behind shifted down and a black band on top, as if the overlay were inside a scrolled container rather than fixed to the viewport (this may be an artefact of the headless full-height capture; check in a real browser). Then to the handoff: × instead of Cancel at the top, a footer with "N selected · Cancel · Use image", search and filters that apply as you type (no Search button). The picker's redesign itself is round 3; the positioning, if real, is a bug to fix here.
  - **⌘K palette:** a footer hint row ("↑↓ MOVE · ↵ OPEN · ⌘↵ NEW TAB") and an ESC chip; rows show a non-Live status on the right and the selected row a "↵" hint; the group headed "Settings" must not list app sections (Dashboard, Pages, …) — give sections their own group or leave them out, and let "Settings" mean things like "Settings › Languages".
  - **Save bar:** sticky to the bottom of the content area at full content width with a top border (not a block inside the form column); the count in sans 13px dim, not mono capitals; the button reads "Save".
  - **Checkboxes:** a shared, token-styled checkbox (accent fill, 2px radius) instead of native ones (user and group forms).
  - **Destructive trigger buttons:** no red-outline button style — destructive is solid danger inside dialogs and danger-coloured text on a secondary button elsewhere. This replaces round 1's `danger_outline` variant.
  - **Logo field in Settings:** still the native "Choose File" control; it should be the styled file drop (round 1's shared control).
  - **Translation stacking:** at 1100px the main column is about 780px, so side-by-side translation should already stack (under 880px) — this round's stacking rule; it also resolves the toolbar wrap.
  - **Sidebar height:** the same full-height bug shows in light theme.
  - Confirmed as matching: the 404 page, the confirm dialog's width, title and button order, the drawer and top bar, the palette's placement and group order, the retention field.

## 8. Round 3: settings, media, people, system

One PR. **Status: built** (branch `studio-design-round-3`, plan `docs/superpowers/plans/2026-10-04-cs-studio-design-pass-round-3.md`). §12 lists where the build departs from the text below and from the plan's decisions.

- **Settings:** in-page nav, a card per section, the save bar, Languages merged in (§5.6), sections hidden by permission (handoff §10 A9), the all-languages Site form, the AI key chip and its own form, Test connection rules (handoff §10 A10). `ai_api_key_saved_at` (§5.4).
- **Media:** grid plus side panel, filters, tile chips, drop-anywhere upload, the picker reusing the grid (handoff §4.6, §10 C36).
- **Groups:** the list, and the eleven-row permission matrix with per-permission scope editors, the branch tree, locked ticks and the removed-type warning (handoff §10 A2); the delete zone and the can't-manage state (handoff §10 C37).
- **Users:** the list, user edit and new with group cards, the owner zone and locked states (handoff §10 B28).
- **AI assistant:** the numbered flow and the tokens table; `api_tokens.name` (§5.4).
- **Tags:** inline rename, the ⋯ menu, Merge (§5.6).
- **Trash:** counts on tabs, the header "Empty trash…", the new rows including inline "Restore under" (handoff §10 B27).
- **Audit log and event:** §5.6 and handoff §10 B30.
- **System status:** the summary line, warnings first, console commands in a code box with Copy.
- **Mind graph:** colours, legend, edges, filter, empty state.
- **Change password** and the **preview banner**.

## 9. Testing

Each round keeps the suite green and adds:

- **Components:** a test and a Lookbook preview per new or changed component; previews stay covered by the smoke test.
- **Integration:** every screen that changes keeps its permission, 404 and 403 tests; new endpoints (⌘K, bulk actions, merge, the save-bar forms) get their own.
- **Data:** §5.2 (both entry shapes, the diff source, changed-at), §5.3 (every write path refreshes the state; the reindex task; parity with `Translations::Status`), §5.4, §5.5.
- **System (Cuprite):**
  - Round 1: theme switch in three states; ⌘K opens, filters and navigates; a confirm dialog; a toast with Undo; the sidebar drawer at a narrow width.
  - Round 2: the editor header menu and Schedule dialog; a suggestion edited then used; the word diff on an outdated field; bulk publish on the posts list; the matrix linking into the right language.
  - Round 3: Settings save bar and Leave dialog; languages reorder and default change; the media side panel and picker; the permission matrix scope editor; token creation showing the token once.
- **Visual check:** after each round, the 33 screenshots are retaken and compared by eye against the mockups in both themes.
- **Existing tests** that pin old copy or markup (`sign_in_via_form`, the theme toggle, "Delete" labels, flash markup) are updated in the round that changes them.

## 10. Roadmap

Update `docs/roadmap.md` when this spec lands:
- **Closes interim states:** tree column polish, posts list pagination, drag reorder for languages, the translations overview filtering in Ruby, the mind-graph layout bug.
- **Absorbs:** the audit-event feed on the dashboard (content-only form), inline page quick create, side-by-side translate mode.
- **Stays separate:** full-text admin search, invites, pending revisions ("Publish changes"), a public-site language dropdown, share images, a sample marker for starter content, AI in a background job.

## 11. Out of scope

- Draft revisions on live content.
- Any change to permissions, audit rules or the public site's look (except the preview banner).
- Translating the admin UI.
- New AI features.

## 12. Amendments (round 3)

Rulings made while round 3 was built. Each overrides the text above it and the plan's decision of the same number.

- **Instant-action hint (plan D10/D11, handoff §10 A9–A10).** "Save or cancel your changes first." is shown per control, not once per screen: on the AI card the Test connection row and the key row may each show their own hint, and Test connection's more specific "Save provider and model first. Tests the saved settings." wins on its row.
- **Media detail URL (plan D12).** `/media?selected=ID` with a missing, trashed or malformed id is a 404 inside the shell, not the grid without a panel. `GET /media/:id` still redirects there.
- **Media panel at 1024–1279px (handoff §9 A7).** Not built as an overlay. The panel is a 340px column beside the grid from 1024px and stacks under the grid below that.
- **Picker segments (plan D13/D14).** All / Unused / Missing alt / Mine. "Untranslated" is not offered in the picker; "Mine" is kept so nothing the old picker offered is lost.
- **Locked ticks (plan D15, handoff §10 A2).** Superseded by the view-only rule (handoff §10 C37): a stored grant the viewer couldn't hand out makes the whole group view-only, so no stored state shows a locked tick inside an editable form. The locked rendering stays as a defensive fallback. A row carrying a removed content type stays editable with its Remove chip and, for a viewer who couldn't grant the carried scope, the hint "Remove this type before changing the row."; changing such a row without pressing Remove is refused by `Groups::Save`.
- **Saving a user (plan D17/D18).** A successful save stays on the editor with the toast "User saved" (a new user: that user's editor, "User created"), as the group editor does; only a delete returns to the list. An owner can't be created in one step: the owner zone exists on an existing user only.
- **Tag dialogs (plan D20).** The merge and delete dialogs count every post carrying the tag, trashed ones included (what the action touches and what `tag.merged` records), while the list's Posts column counts kept posts the viewer may read.
- **Audit log paging (plan D23).** "Load older" replaces the page (offset paging) rather than appending; "Newer" goes back. Day headers are drawn per page, so a day that crosses the boundary has its header on both.
- **Exit preview (plan D26).** For a record that isn't live, Exit preview goes to CS Studio's list (the pages landing for a page, the posts list for a post), not to the editor — Edit already goes there. A live record's Exit preview goes to its public URL.
- **Save footer (handoff mocks).** As in round 2: Save first, in the form's own column, sticky at the bottom of the window — not the mocks' right-aligned bar across the content area.

- **Default-language count (plan D8).** The dialog's "(N items)" is the number of records that hold a stored translation today — a non-empty `translation_sources` on a kept page, post (their blocks rolled in), image or the settings row (`Translations::StateIndex.translated_record_count`) — not "a `translation_states` row that isn't `missing`": an image without alt text or a page with nothing to translate reads `complete` while holding nothing, and inflated the number.
- **Making a language the default (plan D8).** `Locales::MakeDefault` also clears the *new* default's own stored fallbacks: its "Falls back to" select reads "None (default)" and is disabled, so no screen could clear them afterwards.
- **Default language control (handoff §10, the Default radios).** Not radios: a "Default" tag on the default language's row and a **Make default** button on every other row, each opening the dialog. A radio group changes on every arrow key, so a keyboard user was shown a dialog per key press; a button asks only when pressed.
- **Password reset from the console (System status).** The outgoing-mail warning's command goes through `Users::UpdatePassword`, never `update!` on the model, so the reset is audited and ends that user's sessions.
- **A forged untick of a locked grant (plan D15).** Unticking a grant the viewer couldn't hand out is narrowing, and narrowing is lawful: `Groups::Save` accepts it (given the viewer may manage the group as it stands) rather than answering 403. The locked rendering exists to stop *widening*.
- **An unregistered content type in a grant.** It matches nothing, enforced where access is decided (`AccessControl::Scoping::Condition` intersects a grant's content types with the registered ones), also for a grant that names a gone type beside a live one and for posts that still carry the gone type. A fix made in this round: the comparison used the raw names before, so such a grant still reached leftover posts. The name stays stored and means something again only if its type is registered again.
- **Drop overlay (handoff §9).** "Drop images to upload" covers the whole window, translucent, not only the grid: a file dragged anywhere on the Media screen is an upload.
- **Same-page fragment links (plan Task 1).** A `#fragment` link to a place on the screen that is showing never navigates and adds no history entry, anywhere in CS Studio: the focus is moved to the target by hand (`admin--fragment-links` on `<body>`). A link to the very URL that is showing replaces the history entry instead of adding one.
- **Mind graph cues (plan D27).** Two cues, never the same shape. Status is the outline: solid for a live post, a dashed ring for a draft or scheduled one (the legend's swatch is the same dashed ring). The colour index is the fill, as the content-type dot: 1–6 filled, 7–12 a solid ring; a draft of a 1–6 type keeps a small filled core inside its dashed ring, a draft of a 7–12 type is an empty dashed ring. A type that is no longer registered is a ring in `meta`, told apart from a 7–12 ring by colour only. A tag's label carries its count.
- **Account screen (plan D25).** The name form above the password form, each with its own footer. Save name answers a Turbo Stream that replaces the sidebar's identity lines and shows "Name saved.", so the screen and any typed password stay; Change password is locked while the name is unsaved ("Save or cancel your changes first."); the current password is not counted as a change (a password manager fills it in on load).
- **Sign out.** A full document load (`data-turbo="false"`), not a Turbo submission, so nothing a tab's scripts hold for one user survives into the next sign-in. With unsaved changes the browser's own prompt asks, not the Leave dialog.
- **AI key and the main Save (plan D10).** A key typed into the open entry and not yet saved locks the main footer's Save ("Save or cancel the API key first."); the key's own input and Save key stay usable while the entry holds text even when the main form has unsaved changes, so the two never lock each other. Remove key and Test connection stay under the pending lock.
- **Audit event links (plan D23).** An event's page is found by id whatever filter its URL carries; outside the active filter it redirects (303) to the event's filter-free address. Only a missing id is a 404.
- **Promotion hold (write queue).** A link into the `#content` frame is promoted to a page visit after the frame has rendered, and the navigator drops the answer of a navigator-level form submitted in that window. From the frame's request until the promoted visit has loaded, the write queue holds such a submission — a non-GET, non-dialog Turbo form with `data-turbo-frame="_top"` or outside every frame — and submits it once afterwards (limits: 10 s for the fetch, 500 ms from the render). Frame-level forms inside `#content` are not held. A held form whose screen was replaced is dropped, except a Trash row's restore or purge form (`data-promotion-stand-in`), sent through the one form in the new content with the same action and full payload. A press from a confirm dialog that is then cancelled is never sent. Not covered: a `_top` link clicked during the frame fetch (roadmap).
