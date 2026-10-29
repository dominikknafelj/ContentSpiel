# Handoff v3: CS Studio (Content·Spiel backend) — UX & design pass

## Overview
A review of all 33 screenshots of the current backend (`uploads/cs-studio/01–33`) and a redesign that keeps the existing structure (sidebar + content, page tree, side-by-side translation) but fixes bugs, removes noise and aligns everything to the Content·Spiel tokens. Work through the **Global changes** first, then the screens in the priority order given.

## About the design files
The `.dc.html` files in this folder are **design references built in HTML**. They show the intended look and behaviour; they are not production code. Rebuild them in the existing app: **Rails 8, server-rendered ERB, Tailwind v4, Hotwire (Turbo + Stimulus), no React**. Open any file directly in a browser to see it. Each screen loads `StudioSidebar.dc.html` and `content-spiel.css`.

## Fidelity
**High-fidelity.** Colours, type, spacing, radii and copy are final. Use the tokens (never raw hex) so light and dark both work. Sample content (names, posts, dates) is placeholder.

---

## 1. Tokens and theming
- `content-spiel.css` holds every token as a CSS variable, with light values on `:root, [data-theme=light]` and dark values on `[data-theme=dark]`. Copy it to `app/assets/stylesheets/` (or import it from the Tailwind entry file).
- `content-spiel.tailwind.css` maps the tokens to Tailwind v4 via `@theme inline`, so utilities such as `bg-surface text-ink border-line rounded-cs font-mono text-cat-1` switch theme automatically. **Don't use `dark:` variants for colours.**
- New in this pass: `--cs-chrome` (sidebar/tree background) and `--cs-cat-1…4` (content-type colours).
- **Theme switch:** store `cs-theme` = `light|dark|auto` in localStorage, and resolve `auto` with `prefers-color-scheme`. Add an inline script in `<head>` so the theme is applied before first paint (see the `<helmet>` script in any screen). Replace the "LIGHT MODE" button with the 3-way segmented control at the bottom of the sidebar. The sign-in page gets the same control, top-right.

| Token | Light | Dark | Use |
|---|---|---|---|
| paper | #f5f4f0 | #0f1012 | page ground |
| surface | #ffffff | #17181b | cards, inputs |
| chrome | #ffffff | #131416 | sidebar, page tree |
| sunken | #ecebe6 | #212226 | hover, selected, code |
| ink / dim / meta | #141417 / #55565b / #6c6d72 | #ededee / #a9aaaf / #8e8f95 | text levels |
| line / line-strong | ink 10% / 20% | ink 9% / 18% | dividers / control borders |
| accent | oklch(.50 .12 250) | oklch(.74 .10 250) | primary button, links, focus |
| ok / warn / danger | green 150 / amber 70 / red 25 | lighter variants | Live / scheduled+outdated / destructive |
| cat-1…4 | hues 200 / 300 / 120 / 0 | lighter | Blog / Now update / Resume entry / custom |

**Type:** Archivo 400–700, IBM Plex Mono 400/500 (self-hosted, `fonts/`).
- H1: 26px/600.
- Section titles: 15–16px/600.
- Body: 14–15px.
- Field labels: mono 10px, uppercase, tracking 0.14em, colour `meta`.

**Shape:** radius 2px everywhere; 999px only for avatars, tag chips and toggles. Shadows only on menus and popovers (`--cs-shadow-menu`).

## 2. Global changes (do these first)
1. **Sidebar** (`StudioSidebar.dc.html`): group the 14 items.
   - CONTENT: Dashboard, Pages, Posts, Media, Translations, Tags, Mind graph, Trash.
   - PEOPLE: Users, Groups.
   - SYSTEM: Settings, AI assistant, System status, Audit log.

   Keep the existing Lucide icons (1.5px stroke, `dim`).
   - **Badges:** Translations shows the outstanding count (warn colour), System status shows the warning count, Trash shows the item count.
   - **Quick jump:** add "Jump to… ⌘K" at the top (a Stimulus command palette searching pages, posts and settings).
   - **Account block:** show name, email and role, then Change password and Sign out as small links.
2. **Status chip** (one partial, `_status_chip.html.erb`): an outlined chip, `border line-strong`, radius 2, 12px text, 6px dot. States: Live (`ok`), Draft (`meta`), Scheduled (`warn`), and a separate amber-outlined **"Unpublished changes"**.
   - **Hide the chip for Live** in lists and the tree; show it only for non-Live states. Editors always show it.
3. **Translation chip** (`_translation_chip.html.erb`): mono 10px code. Done = solid `line-strong` border with `ink` text; missing = **dashed** border with `meta` text; outdated = `warn` border with `warn-ink` text and " ↻".
   - **Remove all red from translation states.** Red (`danger`) is only for delete or destroy.
   - Every chip gets a `title` tooltip: "Translated", "Not translated", or "English changed since translation".
4. **Language tabs** (`_language_tabs.html.erb`): underline tabs using each language's own name.
   - **Dots:** none = complete, hollow `meta` ring = missing, solid `warn` = outdated.
   - **Overflow:** more than 4 languages collapse into "+N ▾". Use these tabs in the Page/Post editors, Settings › Site and Media detail.
5. **Content-type dot:** 7px circle in `cat-N` + the type name in `dim`. Replace today's blue/orange dots; the orange clashed with Scheduled.
6. **Form controls:** style native `<select>` (custom chevron, token colours) and replace bare `<input type=file>` ("Choose File No file chosen") with a styled drop zone + "Choose file" button. Use these on Settings › Logo and Media upload.
7. **Filters apply immediately:** remove the Filter buttons (Posts, Media, Audit log). Submit the form on change with Turbo (Stimulus `auto-submit` controller, debounce 250ms on text fields). Keep "Clear" only when a filter is active.
8. **Dates:** show relative time in lists ("2h ago", "yesterday"), with the absolute time in a `title` tooltip. Show the user's display name instead of the email where one exists (see Open decisions).
9. **Empty counts:** never render `! 0` or similar. Hide indicators whose value is zero.

## 3. Bugs found
- **Slug helper shows a double slash:** `//about` (04) and `/de//about` (05). Build the path from the parent path segments and join them without a leading empty segment.
- **"days (0 = never)" wraps** beside the trash-retention input (17, 18). Move the explanation to helper text below the input, and make the input 72px wide.
- **Page tree truncates titles** ("Phot…", "Copy…", "Wor…") because every row shows the status chip and `!` count. This is fixed by global rules 2 and 9, plus a 272px tree column.
- **"Create starter pages" is shown even though pages exist** (03). Show it only when the tree contains just Home.
- **Rich-text toolbar wraps onto two lines** in side-by-side translation (05, 09, 10). Group the tools with separators and move Page/Image/YouTube into an "Insert ▾" menu.
- **The AI suggestion shows the stub output** (`[es] Welcome…`, 10), so the test provider leaks into the UI. Make sure the provider name and model are shown and that the suggestion is editable before use.
- **Disabled "Move to trash" on Media detail** (14): the reason appears below the button in low contrast. Use the help text pattern from `Studio Media.dc.html`, and offer a link to where the image is used.
- **Sign-in doesn't use the tokens** (01): saturated blue, larger radius, heavier heading. Rebuild it with the tokens.

## 4. Screens (priority order)
For each screen, open the matching file next to the old screenshot.

### 4.1 Page/Post editors — `Studio Pages.dc.html`, `Studio Post Editor.dc.html` (old 04, 05, 08–10)
- **Sticky header**, padding 16px 28px 0:
  1. Breadcrumb (12px `meta`) on the left; save state (`SAVED 10:42`, mono 11px), **Preview** (secondary), **Publish changes** (primary) and **⋯** on the right.
  2. H1 + status chip(s).
  3. Public path (mono 12px `dim`), Copy, "View on site ↗".
  4. Language tabs, plus on non-default languages a right-aligned "Suggest translations for N empty fields" with the real count.
- **The ⋯ menu** contains Activity, Schedule…, Discard draft changes, Unpublish, a divider, then Move to trash (`danger`, last). There are no longer five equal buttons.
- **Side-by-side translation:** two equal columns.
  - **Left:** the field.
  - **Right:** a reference card (`paper` bg, `line` border, label `ENGLISH`).
  - **Outdated field:** the card border turns `warn` and the header shows "↻ CHANGED 1 DAY AGO". The body shows a **word diff** of the English change (`<del>` in `danger-ink` on `danger-tint`, `<ins>` in `ok-ink` on `ok-tint`), with buttons "Suggest update" and "Still correct — mark up to date".
  - **Remove** the per-field "Translate" button from the reference card. The suggestion action lives in the header (bulk) and on empty fields.
- **AI suggestion:** an accent-tint box *inside* the field, labelled "SUGGESTED TRANSLATION · EDIT BEFORE USING" with the model name on the right, containing editable text and **Use** (primary small) / **Discard**.
- **Page settings:**
  - Slug gets a prefix cell (`/`, `/de/`) and helper text.
  - Page type shows "Shared by all languages." on translations.
  - SEO stays collapsed.
- **Blocks:**
  - Header: drag handle, type name 14px/600 and ⋯.
  - The Image block's alt text is read-only, with a link to Media ("edit once, used everywhere").
  - "+ Add block" becomes one dashed row with inline type buttons.
- **Tags:** chip input with autocomplete, replacing comma-separated text. Related posts uses the same chip input.

### 4.2 Dashboard — `Studio Dashboard.dc.html` (old 02, 32)
- **Quick create:** one row in a card: title input, type select (Blog post / Now update / Resume entry / Page) and **Create draft**. Remove "New page" and "Upload image" from here.
- **Three cards** (auto-fit, min 300px), each capped at 5 items with a "→" link:
  - **Your drafts:** title, type dot, "edited 2h ago".
  - **Going live next:** date tile (mono month in `warn-ink`, day 18px), title, "in 5 days", plus a one-line hint when the list is short.
  - **Needs translation:** per language, the name, "12 missing · 1 outdated" and a 4px progress bar, followed by the most urgent outdated item.
- **Recent activity:** a single feed that replaces the two near-identical lists. Each row is an avatar (round = person, square accent = MCP agent), a sentence, a status chip only if not Live, and relative time. "Full audit log →".

### 4.3 Posts — `Studio Posts.dc.html` (old 07)
- **New post:** a split button, "New blog post" + ▾ for the other types.
- **Toolbar:** search, scope segmented control with counts (All/Live/Drafts/Scheduled), then dropdowns for Type, Tag and Translation. All apply instantly.
- **Columns:** checkbox, Title + path (mono 11px), Type (dot), Status, Translations (chips), Updated (relative), ⋯.
- **Bulk bar** (accent-tint) when rows are selected: Publish, Move to trash, Clear. (Bulk translate removed, §10 A3.)

### 4.4 Translations — `Studio Translations.dc.html` (old 16)
- **One matrix** instead of one page per language: rows are items, columns are languages, with a type filter.
- **Summary cards:** one per language, with % done, a bar and counts.
- **Sort order:** outdated items first, since they are already visible on the site. Each row's CTA says "Review changes →" for outdated items and "Translate →" otherwise.

### 4.5 Settings — `Studio Settings.dc.html` (old 17, 18, 19)
- **Layout:** in-page left nav (Site, Languages, Publishing, AI translation), one card per section, and **one sticky save bar for the whole screen** (see §9, B12). Settings stops autosaving.
- **Languages** moves into Settings (merge screen 19):
  - Rows: drag handle (order), name + path, a **Default** radio and a single **"Falls back to"** select (replaces the ambiguous checkboxes), plus "Turn off…".
  - Turning a language off is neutral and opens a confirmation explaining that its content is kept.
- **Social links:** start with one row plus "+ Add link"; each row has ×.
- **AI translation:**
  - The API key shows as a chip: "Key saved · added 2 Oct" with Replace/Remove. Never render any part of the key.
  - "Test connection" shows the result inline, e.g. `CONNECTED · 412 MS`.

### 4.6 Media — `Studio Media.dc.html` (old 13, 14, 31)
- **Layout:** grid + **right-hand detail panel**; media detail no longer opens a separate page.
- **Uploading:** dropping anywhere on the page uploads, and "Upload images" sits in the header.
- **Filter segments:** All / Unused / Missing alt / Untranslated, with counts.
- **Tile chips:** `NO ALT` (warn) and `UNUSED`.
- **Detail panel:** preview, file info (mono), language tabs, Title, Alt text (warn border when empty), Caption, Used on, and Move to trash with help text.
- **Media picker (31):** reuse the same grid and filters inside the modal. Search is instant.

### 4.7 Groups — `Studio Group Edit.dc.html` (old 23, 24)
- **Permission matrix:** replace the long checkbox list with a matrix. Rows are Posts and Pages; columns are Read/Create/Edit/Publish/Move/Delete.
  - Each box's `title` is the key (`posts.publish`).
  - The scope sits on the right of each row ("All content types ▾", "Own only" / "All pages ▾").
- **Other permissions:** Content, Administration and Oversight as toggle lists.
- **Members:** a chip multi-select, with owners excluded and the reason given.
- **Save bar:** sticky, with an unsaved-change count.
- **Groups list (23):** keep the current list but make each row clickable, removing the Edit buttons.

### 4.8 AI assistant — `Studio AI Assistant.dc.html` (old 25)
- **Numbered flow:**
  1. Create a token: name + group + Create. A one-line description of the selected group appears below the select.
  2. Add it to your assistant: URL and config, **each with Copy**.
- **After creating a token:** show a warn box, "Copy this token now. It won't be shown again.", with the raw token and Copy. The token is also filled into the config JSON for this page view.
- **Tokens table:** Name, Group, masked token, Last used and Revoke.

### 4.9 Trash, Users, Tags, Audit log, System status
- **Trash** (`Studio Trash.dc.html`):
  - Counts on the tabs.
  - "Empty trash…" moves to the header as a secondary button in `danger` text.
  - Rows show "You · 3h ago" and `IN 30 DAYS`, with Restore (secondary) and a "Delete now…" text button.
  - Page rows say "Includes 1 subpage: …".
- **Users** (`Studio Users.dc.html`):
  - Rows are clickable, showing avatar, name or email, an OWNER tag, group chips and last sign-in.
  - Delete moves to the edit page.
  - The header button becomes "New user" (no invite flow, §10 A11).
  - User edit/new (21, 22): group checkboxes become cards with descriptions in a 2-column grid. Owner is separated at the bottom.
- **Tags** (`Studio Tags.dc.html`):
  - Rename inline by clicking the name.
  - The post count links to the filtered Posts list.
  - Delete and "Merge into…" go in the ⋯ menu, removing the red Delete buttons.
- **Audit log** (`Studio Audit Log.dc.html`, old 28, 29):
  - Group entries under day headers.
  - Write a human sentence ("You published *Now: shipping translations*") with the raw key in mono on the right.
  - Add an ADMIN/MCP channel chip (MCP in accent).
  - Filters become one row of dropdowns, with a date-range preset instead of two date inputs.
  - The event detail page (29) shows field diffs using the same diff style as 4.1.
- **System status** (`Studio System Status.dc.html`, old 27):
  - Show a summary line ("3 of 4 checks passed · last run 17:30").
  - Warnings go first, with a status chip.
  - Console commands go in a code box with Copy, plus a docs link.
- **Mind graph** (26, `Studio Mind Graph.dc.html`):
  - Colour nodes with `--cs-cat-*` and add a legend.
  - Draw edges for related posts.
  - Empty state: "Link posts with Related posts to see connections."
- **Change password** (30): see `Studio Change Password.dc.html` and §9.
- **New page / New post** (06, 11): modals, see `Studio Modals.dc.html`. New post preselects the type from the Posts split button.

## 5. Interactions and states
- **Focus:** 1px `accent` border + 3px `accent-tint` ring on inputs, and a visible focus ring on buttons and links.
- **Hover:**
  - List rows get `paper` background (on `surface` cards).
  - Nav items get `sunken`.
  - Primary buttons switch to `accent-hover`.
- **Motion:** only `--cs-ease` (cubic-bezier(.22,1,.36,1)), 150–200ms, for toggles, menus and the tree selection.
- **Confirmations** (use a Turbo confirm modal, not the browser default): Delete now, Empty trash, Turn off language, Revoke token, Unpublish.
- **Publish model:** see Open decisions. In the mocks, a Live item with edits shows "Unpublished changes" and **Publish changes** is enabled; otherwise the primary button reads "Publish" (Draft) or is disabled (Live, no changes).

## 6. Open decisions (confirm with the product owner)
1. **Draft changes on live content.** Today, edits to a Live page appear on the site immediately ("Live — changes appear on the site as you edit"). The design assumes edits are saved as a draft revision and published with **Publish changes**. If that's out of scope, keep live editing but keep the save indicator and make Activity → restore easy to reach.
2. **User display name.** The design shows names where available, so add an optional `name` to User and fall back to the email.
3. **Media detail as a side panel** instead of its own page (deep links can use `?selected=ID`).

## 7. Files
- **Screens:**
  - `Studio Sign In.dc.html` · `Studio Dashboard.dc.html` · `Studio Pages.dc.html` (prop `lang`: en/de/es)
  - `Studio Posts.dc.html` · `Studio Post Editor.dc.html` (prop `lang`) · `Studio Translations.dc.html`
  - `Studio Media.dc.html` · `Studio Settings.dc.html` · `Studio Group Edit.dc.html`
  - `Studio AI Assistant.dc.html` (prop `created`) · `Studio Trash.dc.html` · `Studio Users.dc.html`
  - `Studio Tags.dc.html` · `Studio Audit Log.dc.html` · `Studio System Status.dc.html`
- **Shared:** `StudioSidebar.dc.html`, `content-spiel.css`, `content-spiel.tailwind.css`, `fonts/`
- **System reference:** `Content Spiel Design System.dc.html` (section 07 "Studio patterns" covers chips, tabs, type colours and editor actions)

## 8. Suggested order of work
Each step can be its own PR.
1. Tokens, theme script and the sidebar.
2. Shared partials: status chip, translation chip, language tabs, select and file input.
3. Bugs from section 3.
4. Editors.
5. Dashboard and Posts.
6. Translations.
7. Settings + Languages.
8. Media.
9. Groups and AI assistant.
10. The remaining list screens.


---

## 9. Round 2: answers to the implementation questions

New in the design system page: **section 07** gained Translation chips (accessible), Content types (open registry), Editor header without drafts, Narrow screens and Save behaviour. **Section 08 · Overlays, feedback & states** is new and covers modals, the command palette, toasts, validation, busy/pending, pagination, open menus, drag & drop, the password field and empty states. The rules are now section 09.

### A. Patterns
1. **Modal/dialog.** DS 08 and `Studio Modals.dc.html` (switch with the tab row or the `modal` prop: new post, new page, media picker, ⌘K, and the confirm dialogs Delete now, Empty trash, Language off, Default language, Revoke token, Unpublish, Unsaved).
   - **Overlay:** ink 38% over the page, no blur.
   - **Widths:** 420 confirm, 560 form, 880 picker; max-height 85vh, and the body scrolls.
   - **Header:** 16px/600 title + ×. **Footer:** right-aligned, Cancel (ghost) then the action.
   - **Destructive:** solid `danger` with white text, and the label repeats the verb.
   - **Focus and keys:** focus starts on Cancel for destructive dialogs and on the first field for forms. Esc and × cancel.
   - **Turn off language and Unpublish** are reversible, so they use primary, not danger.
2. **Command palette.** DS 08 + `Studio Modals.dc.html` (⌘K tab; type to filter, clear the query to see grouping, type nonsense for no results).
   - **Placement:** opens 8–12vh from the top.
   - **Groups:** Pages, Posts, Media, Settings, Actions; max 5 rows per group.
   - **Selection:** the first row is selected on open (sunken + ↵ hint).
   - **Rows:** only non-Live statuses show.
   - **No results:** names the query and offers "New blog post “…”".
3. **Toasts.** Inverted (ink ground, paper text), bottom-centre of the content column, max 3.
   - **Timing:** success hides after 4s and Undo after 8s; warning and error stay until dismissed (error has Retry).
   - **Flash mapping:** notice → success, alert → error.
   - **Never** used for form errors.
4. **Validation.** Server-rendered after a failed submit (422).
   - **Summary:** a `danger-tint` box with linked field names.
   - **Fields:** 1px `danger` border, message in `danger-ink` with “!” below, aria-describedby.
   - **Drawn for:** slug prefix field (prefix cell keeps its sunken ground), select, chip input (the invalid chip turns danger-tint) and rich text (whole editor border).
5. **Loading.**
   - **Busy button:** same width, 11px spinner, "Testing…", disabled.
   - **Pending suggestion:** accent-tint box with spinner, elapsed seconds, two skeleton bars and Cancel. At 25s it shows "No suggestion after 25 seconds. Try again".
   - **Bulk suggest:** the header button becomes "Suggesting 2 of 5 fields" + progress bar + Cancel; each pending field shows the pending box.
   - **Upload:** a 3px accent bar along the bottom of the tile + %, and failed tiles stay with Remove.
6. **Pagination.** A footer row in the table card: "51–100 OF 312" left, ‹ Previous 1 2 3 … 7 Next › right.
   - **Page size:** 50 rows; Media uses 48 tiles.
   - **URL:** page is a URL param.
   - **Single page:** the pager is hidden.
   - **Audit log** keeps "Load older" (cursor).
7. **Narrow screens.** Studio is desktop-first but not desktop-only.
   - **≥1280:** as drawn.
   - **1024–1279:** the sidebar becomes a drawer behind a 48px top bar (☰, wordmark, ⌘K), and the Media panel overlays the grid.
   - **768–1023:** the page tree becomes a "Pages ▾" drawer, and tables scroll with a sticky title column.
   - **Translation stacking:** side-by-side translation **stacks** (reference above field, collapsible) when the main column is under 880px (container query).
   - **<768:** usable but not a design target.
8. **Open menus.** DS 08 shows the Posts split menu, the +N language overflow (with state dots + "Manage languages…"), tag autocomplete (with counts + "Create tag “…”"), members multi-select (checkboxes, owners disabled with reason) and the Tags row menu (Rename, Merge into…, Show posts, divider, Delete…).
   - **Shared panel:** surface, 1px line, menu shadow, 2px radius, 4px padding.
   - **States:** keyboard focus = sunken.
9. **Drag.**
   - **Handle hover:** handle turns ink, row sunken.
   - **Dragging:** a lifted copy with menu shadow follows the pointer, and the origin becomes a dashed slot.
   - **Between rows:** a 2px accent line with a ring, indented to the target depth.
   - **Nest:** accent tint + outline on the target row.
   - **Keyboard:** Space to pick up and drop, arrows to move and change depth, Esc to cancel.
   - **Saving:** autosaves on drop with an Undo toast.
10. **Password field.**
    - **Show/Hide:** a text button inside the input.
    - **Meter:** 4 bars. Too short (<12, 1 red bar, submit disabled), Fair (2 amber), Good (3 green), Strong (4 green).
    - **Where:** the setup wizard admin step now has it, and so do Change password, the reset form and User new.
11. **Empty states.** DS 08 covers no posts, no filter results (names the filters + Clear filters), empty media library, empty trash, everything translated and no audit events in range.
    - **Placement:** inside the card where the rows would be.
    - **Content:** at most one action, no illustrations.

### B. Rules
12. **Save rule.**
    - **Autosave** for content: editors, blocks, media metadata, tag rename, tree/block order. It saves 800ms after typing and on blur; indicator SAVING… → SAVED 10:42 → on failure NOT SAVED · Retry + error toast. No leave warning.
    - **Explicit save** for configuration: Settings (all sections incl. Languages), Groups, Users, AI tokens, Change password. One sticky save bar per screen ("2 unsaved changes · Cancel · Save"); leaving with changes opens the Leave dialog.
    - **Instant** for single actions with their own button (publish, trash, restore, revoke, language off), with a confirm where listed and then a toast.
    - **Mocks updated:** Settings now uses the sticky bar.
13. **Content-type colours.** Tokens are now `--cs-cat-1…6`, new in `content-spiel.css` and the Tailwind file, light and dark.
    - **colour_index:** each type stores one, assigned in creation order.
    - **Marks:** types 1–6 get filled dots, 7–12 the same hues as rings, and 13+ cycle again.
    - **Labels:** the type name always accompanies the dot.
14. **Translation chips.**
    - **Done:** no check mark.
    - **Missing:** dashed border **and** " ○" glyph (matches the hollow tab dot).
    - **Outdated:** " ↻".
    - **Accessibility:** colour is never the only cue, and every chip gets an aria-label ("German: not translated").
    - **Mocks updated:** Posts and Translations.
15. **Editor header without drafts.** Drawn in DS 07 and now the **default** in `Studio Pages` / `Studio Post Editor`; `drafts: true` shows the future variant.
    - **Live:** no primary button and no "Unpublished changes" chip; the indicator reads "● SAVED TO SITE 10:42" in ok-ink. A one-line hint shows under the header: "This page is live. Changes appear on the site as soon as they’re saved."
    - **Draft:** primary **Publish**.
    - **Scheduled:** primary **Publish now** + secondary **Edit schedule**.
    - **⋯ menu:** "Discard draft changes" appears only with drafts.
16. **API key.** Not intended: never render any part of the key. The chip reads "Key saved · added 2 Oct". This is now in the rules.
17. **Default language.** Confirmed: it moves to the Default radio in Settings › Languages and is removed from Site. The radio doesn't change until this dialog is confirmed (`Studio Modals.dc.html` → DEFAULT LANG):
    - **Title:** "Make Deutsch the default?"
    - **Body:** superseded, see §10 A8.
    - **Warning box:** "Deutsch becomes the source language, so every translation into English and Español is marked outdated (14 items)."
    - **Buttons:** Cancel / Change default language.
18. **Section 06.** It existed (Tailwind & Avo mapping) but referenced Avo; it's now "06 · Tailwind mapping" without the Avo column. Sections now run 01–09 without gaps.

### C. New mocks
- `Studio Groups.dc.html`: list with built-in tag, member and token counts; rows link to Group edit.
- `Studio User Edit.dc.html`: `mode` = edit | new.
  - Optional name.
  - Group cards in a 2-col grid with descriptions.
  - Owner separated in a dashed card with "Make owner…".
  - New: password with Show + meter.
  - Edit: "Set a new password…" and the Delete user zone.
  - Sticky save bar.
- `Studio Audit Event.dc.html`:
  - Sentence title.
  - Meta grid: when, who, channel, action key, object, request.
  - Field diff table (before/after, word diff).
  - Collapsible raw JSON.
  - Older/newer navigation.
- `Studio Change Password.dc.html`: current / new (Show + live meter, submit disabled under 12 characters) / confirm, plus a "wrong current password" error via the `wrong` prop.
- `Studio Password Reset.dc.html`: sign-in layout, `step` = request | sent | form | expired. **The step switcher in its header is a review aid only**; production shows the theme switch as on Sign in.
  - **request:** includes a hint for sites without outgoing mail.
  - **sent:** neutral wording that doesn't reveal whether the account exists; the link expires in 15 minutes.
- `Studio Modals.dc.html`: New post (type picker + title + URL preview), New page (title, inside, page type, URL), Media picker (880 wide, search, filters, selectable grid, "Use image"), ⌘K and all confirm dialogs. **The tab row is a review aid only.**
- `Studio Mind Graph.dc.html`:
  - Nodes coloured by type; drafts hollow; size = link count.
  - Tags as small hollow nodes.
  - Related = solid ink edges, shared tag = dashed.
  - Legend panel, a Both / Related only / Tags only filter, and the `empty` prop for the empty state.
- `Setup Wizard.dc.html`: aligned with Sign in.
  - Same header (12px wordmark, 20px 28px padding, no rule).
  - Mono uppercase field labels.
  - Admin password gets Show/Hide + the 4-bar meter.

### Noted from your FYI
- **Components:** ViewComponents + Lookbook instead of ERB partials. Read "partial" in §2 as "component".
- **Tokens:** taking only `--cs-chrome` and `--cs-cat-1…6` from `content-spiel.css`, plus your own font files, `font-cs` utilities and color-scheme handling, is fine.
- **AI suggestion bug:** the "[es] stub" item in §3 is withdrawn.


---

## 10. Round 3: answers to the round-2 gaps (v3)

New file: **`Studio States v3.dc.html`**, one card per item, badged A1–C40. Updated mocks: Group Edit (per-permission scopes), AI Assistant (token table), Setup Wizard (8 steps, system check, free social links), Modals (corrected copy + 7 new confirms), Dashboard, Audit Log, Audit Event, Pages, Posts, Users, User Edit, Groups, Media, Translations, Sidebar, design system rules.

Your four constraints are taken as given. **[You decide]** marks items where I give a recommendation and you can choose otherwise.

### A. Conflicts
1. **Keep per-use overrides.** The field is editable; the placeholder is the library text (in the tab's language, falling back to default). The help says "Empty uses the alt text from Media"; once overridden, it shows a Reset link plus the library text. Same for caption, page hero and rich-text images. Mock: Pages image block + States A1.
2. **Scopes are per permission.** Group Edit is redrawn as 11 rows (Posts ×5, Pages ×6), each with its own scope chips and "Edit scope".
   - **Posts:** a content-type multi-select (none = all) plus an Own only toggle.
   - **Pages:** a branch tree. Ticking a page includes its subtree. Tri-state: ✓ / – partial / greyed ✓ included.
   - **Drawn:** a mixed-scope row, a locked tick ("You can't grant this", greyed filled box), the removed-type warning (amber, with Remove) and "a page you can't open (kept)".
3. **Bulk translate dropped** from the Posts bulk bar.
4. **Outdated field without a stored source:** the card shows the current English, a warn border, "English changed since this was translated." and Suggest update / Still correct.
   - **[You decide] Diff:** recommended. Store the source text per field when a translation is saved, from now on; older translations get the no-diff card. Rich text: diff the plain text per paragraph; formatting-only changes say "Formatting changed".
   - **Change date:** shown only if you also store `source_changed_at`; otherwise omit it.
5. **Tokens.** (a) Drop the masked column, yes. (b) Add a required token name, yes, in the setup wizard too. (c) Columns: Name, Acts as, Group, Created, Last used (with IP on a second line), Status (Active/Revoked), Revoke…; revoked tokens stay listed, greyed.
6. **Actor.** "Mara König via claude-desktop" with the user's avatar and an MCP chip. The rule "labelled MCP until a human publishes it" is **dropped** (DS rule 09 rewritten).
7. **Dashboard feed, option (b):** content only, limited to items the viewer can read, shown to everyone. Dropping "Scheduled by you" and "Recently edited by you" is intentional:
   - **Going live next:** shows all scheduled items the viewer can read, with "by you" in the meta line.
   - **Your drafts:** keeps today's meaning.
8. **Change the copy, not the behaviour,** for every item. New copy is in Studio Modals and States A8:
   - **Language off:** "not found".
   - **Unpublish:** "subpages also show not found".
   - **Default language:** "Existing links to English pages without /en will open the Deutsch version, or show not found".
   - **Delete user:** "posts are left without an author; their AI tokens stop working". Verify the token part.
   - **Delete group:** allowed with members; revokes its tokens.
   - **Media:** 10 MB, and Move to trash is disabled while the image is in use.
9. **Settings permissions:** hide the sections the viewer can't manage, and their nav links.
   - **Pending (wait for the bar):** Site fields, Publishing, AI provider/model, language order and fallbacks.
   - **Instant with a dialog:** Add language, Turn off, Default. These are **disabled while anything is pending** ("Save or cancel your changes first"), so a reload never drops pending changes.
10. **The API key stays its own immediate form.** Replace shows input + Save key / Cancel. Test connection is disabled while provider or model have unsaved changes, with the hint "Save provider and model first. Tests the saved settings."
11. **No invites:** "New user", and all invite copy is removed (Users, toast, setup).
12. **Yes, adopt 12 characters** as a server rule for setup, new user, change and reset, applied the next time a password is set. Error copy: "Use at least 12 characters."
13. **Both thresholds are right, for different components:** Studio language tabs show 4, then "+N ▾"; the public switcher becomes a dropdown above 3. The rule text is fixed.
14. **Keep the system check** as optional step 02. Drawn in Setup Wizard (`step = system`); it shares rows with System status and never blocks.

### B. Undefined / undrawn
15. **Account block:** "Owner"; otherwise up to 2 group names then "+N"; otherwise "No groups".
16. (a) **Counts:** what the viewer can act on. (b) **Empty headings:** disappear. (c) **Badges:** drop the Translations and System status badges in this build; keep Trash.
17. **[You decide] Translation state.**
    - **Recommended:** a stored per-record × language status (done / missing / outdated) updated on save. "% done" counts items, not fields.
    - **If deferred:** drop the Dashboard card, the summary cards, the Posts Translation filter and Media's Untranslated filter for the first build.
    - **When the card is hidden:** with one language, or when the viewer can read nothing.
18. **Translations matrix:**
    - **Chips:** each chip links to that language's editor tab.
    - **Row title:** opens the first outdated, else the first missing language.
    - **Mark as up to date:** only on the editor's reference card.
    - **Site settings row:** added (title, tagline).
19. **View only:** drawn in States B19.
    - **Header:** "View only" dashed chip, Preview + ⋯ (Activity only).
    - **Hint:** one line explaining why.
    - **Fields:** sunken and dim, with no toolbar, handles, block menus, Add block or autosave.
    - **Media detail:** plain text fields, no trash, and the hint "Only the uploader or a media manager can edit this image."
20. **Changed elsewhere:**
    - **Indicator:** "● CHANGED ELSEWHERE" in warn-ink.
    - **Bar:** a warn-tint bar under the header (not a toast) naming who and when, with **Reload**.
    - **Your text:** autosave pauses; fields keep the local text so it can be copied; Reload discards it.
21. **Schedule dialog** (460):
    - **Fields:** date + time, plus "Berlin time (GMT+1), the site's time zone."
    - **Remove schedule:** bottom-left, only when a schedule exists.
    - **Past time:** the error "Pick a time in the future."
22. **Page editor fields and blocks.**
    - **Hero image:** Change / Remove + per-page alt override.
    - **Post list block:** Type, Tag, Limit.
    - **Unavailable block:** danger border and label, "Its content is kept but can't be shown or edited", Delete block… only.
    - **SEO:** meta title (60) and meta description (160) with soft counters. **Share image is dropped.**
    - **Block ⋯ menu:** Move up, Move down, divider, Delete block… (confirm, because blocks skip the trash).
23. **Content-type fields** sit in their own group between Excerpt and Body.
    - **Inputs:** date = mono yyyy-mm-dd input; boolean = toggle with label; select = styled select; repeatable group = bordered rows with handle and × plus "+ Add …".
    - **Translation tabs:** only translatable fields appear side by side; shared fields collapse into a read-only "Shared fields (N)" row.
24. **Page tree rows.** (a) Context-only ancestors: meta text, no handle or link, with a tooltip. (b) **Keep** the row "+" on hover where the viewer may create; it opens the New page modal with INSIDE preset. (c) No handle when the viewer may not move. (d) Counts: ↻N outdated (warn-ink) and ○N missing (meta). Pages mock updated.
25. **Rich-text popovers.**
    - **Link:** an anchored popover with page/post search or a URL.
    - **Image:** the 880 media picker, then a 560 dialog for alt and caption.
    - **YouTube and Page embed:** a 560 form dialog.
26. **Suggestions.**
    - **Use all:** kept. After a bulk suggest it replaces the progress line: "5 suggestions ready · Use all · Discard all".
    - **Repair notes:** warn-ink lines under the suggestion text, before Use/Discard.
    - **Suggest update:** the box holds the full new text plus "Current: …"; Use replaces the field.
27. **Trash rows.** (a) **Inline** "Restore under [Home ▾]" in the row. (b) "Deleted user" / "System". (c) Delete now… disabled, with the reason as tooltip and second line. (d) NEVER / TODAY. (e) As you describe.
28. **Users: locked states.**
    - **Group card you can't assign:** sunken background, greyed box, "You can't grant this group."
    - **Last owner:** "…can't be removed" and Delete user disabled for the same reason.
    - **Non-owner viewing an owner:** read-only form, "Only owners can change other owners."
    - **User you can't manage:** read-only, "This user has permissions you don't have…"
    - **Owner dialogs:** Make owner and Remove owner are in Studio Modals.
29. **Merge tags** as you describe: a tag picker plus confirm, no undo, one audit event. Deleting a tag that has posts stays allowed with a confirm.
30. **Audit log.** (a) Presets Today / 7 / 30 / 90 days / Custom…, where Custom shows the two date inputs inline. (b) Side effect dropped. (c) "16:05–16:31" in the list; "16:05–16:31 · 12 saves" in the detail, diff first→last. (d) Human sentences, with the security keys in warn-ink.
31. **"Page"** opens the New page modal with the title carried over, INSIDE = Home.
    - **Types:** lists show only types the viewer may create; with none, quick-create is hidden.
    - **Uploads:** Media and the picker are the upload entry points.
32. **[You decide] Settings › Site languages.** Recommended: render all languages' inputs in one form and let tabs only switch visibility; one Save writes all, and switching tabs never triggers the Leave dialog. The nav uses scroll anchors.

### C. Missing screens / states
33. **403 and 404 in the Studio layout:**
    - **403:** "You don't have access to Settings" + "Go to dashboard".
    - **404:** "This page doesn't exist, or you can't open it" + "Back to Pages" (never confirms the record exists).
34. **/pages opens Home** if the viewer can open it; otherwise the empty state "Choose a page from the tree". While Home is the only page, the starter offer sits in that panel and in the tree ⋯ menu.
35. **Related posts:**
    - **Chips:** type dot + title + "· Draft/Scheduled" when not live.
    - **Hidden relations:** "+2 related posts you can't open (kept)".
    - **Search rows:** title + status.
36. **Media.** (a) "Only by items in the trash: …", and trashing is allowed. (b) Picker upload: progress tiles first, and the first finished upload is auto-selected. (c) Without `media.upload`: no picker; Remove only, with a hint.
37. **Custom group:**
    - **Delete zone:** with member and token counts; the confirm is in Modals.
    - **Can't manage:** read-only notice, and the save bar and delete zone are hidden.
38. **Setup.** The sample sentence is replaced; social links are free name + URL.
39. **Data.**
    - **Add:** user name, token name, `api_key_saved_at` (or show "Key saved" alone), and per-field source text.
    - **Optional:** `source_changed_at`.
    - **Decide:** the translation state table.
    - **Drop:** share image and the sample marker.
40. **Preview banner: yes, Studio tokens.** An inverted ink bar fixed at the top of the public layout, 36px: "PREVIEW · About · Draft · Deutsch", Edit, Exit preview.
