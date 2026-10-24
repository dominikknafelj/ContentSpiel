# The layout points (Claude Design's review, part 2)

Status: approved by the owner 2026-10-24 ("looks good"); Claude Design's answers and the owner's answers to O1, O7, O9–O11 are in.

Source: Claude Design's answers of 2026-10-15 (`.superpowers/design-answers/2026-10-15-contrast-and-icons.md` in the main checkout): D3 items 2 and 4 to 11, and the "First reply" (the dashboard's grid, Notes for you, empty states, recent activity, the footer links). Part 1 (contrast, buttons, block icons, tree marks, the site's bands) shipped as PR #77 (`2026-10-15-contrast-and-buttons-design.md`). The owner approved the scope of part 2 on 2026-10-15. Every point below was checked against the code at `33284754`, and where the code differs from what the design answer saw, this spec says so.

## Why

Part 1 made every control and state visible. Part 2 is about room and order: fields that run 1,100px wide, a table that repeats the language code under a column named after the language, a drop zone that takes 110px on every visit to a full library, a dashboard whose cards are too narrow to read and whose activity says the same thing four times. And on the site, captions set as labels and a list of links with no heading.

## What was checked

| # | Point | What the code does today | Verdict |
|---|---|---|---|
| 1 | Editors' form width | The post form, the page settings form and the block list fill `<main>`: about 1,110px at a 1,400px window, more on a wider one | As described |
| 2 | Settings' width | The card column is up to **900px** (`max-w-[1100px]` minus the 170px nav), not 550px. Some fields inside are capped narrower: Time zone 384px (`max-w-sm`), the AI key 448px | Different: Settings is wider than 760px, not narrower (open question O1) |
| 3 | Translations table | Each cell is a `TranslationChipComponent`, which writes the language code ("DE ●") under a column headed "Deutsch". The row has a title link, one link per cell and a "Translate →" link | As described |
| 4 | Media drop zone | The zone (`FileDropComponent`) is drawn above the grid on every visit. The full-window overlay already exists: `admin--media--drop` shows "Drop images to upload" over the whole window while files are dragged anywhere on the screen | Half done: only the zone remains |
| 5a | Settings nav | Plain anchor links, no current state, no script | As described |
| 5b | Social links | `Values#social_rows` always returns one empty row, so a site with no links shows two empty fields and a lone ×. The script clears the last row instead of removing it, because a form that posts no rows means "not touched" to the controller (`rows_posted?`) | As described, with a catch (Ruling 6) |
| 5c | "NONE" logo square | A 44px square with `NONE` in 9px mono when there is no logo | As described. Also breaks the 11px rule; the guard only looks for `text-[10px]` |
| 5d | Save bar cuts the last card | The bar is `sticky bottom-0` inside the form, with 24px above it. At the end of the scroll it sits below the last card and covers nothing. While scrolling it covers whatever is under it, as a sticky footer does | Not confirmed in the code (open question O2) |
| 6 | Duplicate slug line | `SlugColumnComponent` draws the address prefix and slug in the field, then the same address again on a line under it. The page settings form uses the same component, so pages have the line too. The line has one use: when the slug field is empty it shows the slug the title will give | As described, on both editors |
| 7 | Note avatars | `PersonName.initials` takes the first letter of the first two words, so a one-word name gives one letter: "admin" and "author" are both "A". The same rule is written twice more in scripts (`mind_graph/card_notes.js`, the composer's mention list) and presence uses it too. The dashboard's activity row draws one letter by its own rule | As described |
| 8a | Mind graph legend | Two `<fieldset>`s (node kinds, line kinds) whose legends "Show" and "Lines" are `sr-only`, then the "Status" link, then the keys as a list, all wrapped in one row | As described: the groups exist for a screen reader, not for the eye |
| 8b | Fit on load | `camera.fit` leaves 40px around the graph but never zooms in further than 1.5 (`MAX_FIT_ZOOM`), so a small graph stays small | As described |
| 9 | Site captions | The Code block's and the Image block's captions are 11px mono, upper case, tracked; a rich-text figure's caption is 11px mono | As described, in three places |
| 10a | "Resume stands alone under a rule" | **This is not related posts.** The public post page draws no related posts at all (`Posts::DetailComponent`; already on the roadmap under "Found while writing the guides"). The lone link under a rule is `nav.page-children` in `pages/show.html.erb`: the listing page's subpages, as underlined body links under a top border with no heading | Different (open question O7) |
| 10b | "Footer links under Test" | The same `nav.page-children`, on Home: the root's subpages under the last block. There is no navigation block type | Different, same fix as 10a |
| 10c | Tags | A list of mono, upper-case, tracked words in `--th-meta`: plain text already, with no border, but set like labels | Partly as described (open question O8) |
| 11a | Dashboard grid | `repeat(auto-fit, minmax(300px, 1fr))`. At a 1,400px window `<main>` is about 1,110px, which already gives three columns; six in a row needs about 1,900px of `<main>` | Different: the review's screenshot was a wider window. The fix is still right (Decision 13) |
| 11b | Recent activity | `Dashboard::Activity` lists audit events. `.updated` events of one subject already coalesce for 10 minutes (`Audit::COALESCE_WINDOW`), but four new blocks are four subjects, so four rows | As described |
| 11c | Notes for you, unread | **Already wired.** An unread row has the accent dot, ink text and a hidden "unread"; the header shows "N NEW" and "Mark all read" while anything is unread. The seed makes no notes, so the screenshot's rows had been read (opening a thread marks it read) | Nothing to build |
| 11d | Empty states | Every card uses `Admin::Ui::EmptyStateComponent` (bold centred title, 48px of padding). "Going live next" adds a hint in another style below, also when it has rows | As described |

Also left for part 2 by part 1, but **not on the approved list**: the Mind graph's count badges drawn over page cards (part 1 "What is not in this pull request"), and the reference card's summary without a disclosure triangle (roadmap, known gaps of part 1). Neither is in this spec; the owner may add them (O11).

## What a person gets

### A. CS Studio's forms

- **Editors at 760px.** In the post editor and the page editor, the form column (the post form; the page settings form, the block list and the picker) is at most 760px wide. Wider windows give the room to the margin on the right. The sticky header keeps its full width. The notes drawer stays a 400px column, and the page tree's fit rule (the editor keeps at least 640px) is unchanged.
- **Translation tabs keep their two columns.** On a language tab other than the default, a translated field is a pair (the field and the original) that sits side by side from 880px of form width. A 760px cap would stack every pair at every width, so on a translation tab the cap is two columns of 760px and their gap (1,536px). See O3.
- **Settings at 760px.** The card column is at most 760px. Fields fill their card, except where a short value keeps its own width (Time zone).
- **The slug line goes.** The address is shown once, in the field and its prefix. When the slug field is empty, its placeholder shows the slug the title will give, kept up to date as the title is typed. Pages and posts alike.
- **Settings' nav shows where you are.** The section in view is marked like a selected item (ink text, a 2px ink bar at its left edge, as the selected tree row) and carries `aria-current="true"`.
- **Social links start as "+ Add link".** With no stored link, no row is drawn, only "+ Add link". Removing the last row removes it.
- **No "NONE" square.** With no logo, only the drop zone and its hint ("Without a logo the site title is shown") are drawn.
- **The save bar** follows O2.

### B. CS Studio's lists

- **Translations: the state as a word.** Each language cell says the state with its mark: "○ Missing", "◐ Outdated", "● Translated" (marks and words: O4). The column header names the language, so the cell no longer repeats it. The cell is still a link to that language's editor, and its accessible name is unchanged ("Title: Deutsch, outdated").
- **Translations: the whole row opens the item.** A click anywhere in a row that is not one of its cell links opens the row's target (the first outdated language, else the first missing one), as the users and groups lists already do (`after:absolute after:inset-0` on the title link). "Translate →" / "Review changes →" is shown only while the row is hovered or its title link has the keyboard focus. It is no longer a link of its own, so a row has one tab stop for its action instead of two.
- **Media: no drop zone once there are images.** When the library holds at least one kept image (whatever the search or filter shows), the zone is not drawn; "Upload images" and the full-window overlay are the ways to upload. An empty library keeps the zone, which is the screen's invitation.
- **Two-letter avatars.** One word gives its first two letters ("admin" is "AD", "author" is "AU"); two words keep their two first letters ("Dana van Weiss" is "DV"). Notes, presence and the dashboard's activity row use the one rule (O9 for the dashboard).

### C. Dashboard

- **At most three cards in a row.** Three columns where `<main>` is at least about 960px wide, two from about 640px, one below. A wider window makes the cards wider, never more of them in a row.
- **Recent activity collapses repeats.** Consecutive events by the same person (and the same token, if any), with the same action, about the same page or post, within 10 minutes of the first, are one row: "You added 4 Code blocks to “Code block demo”". Its time is the last one's, and its tooltip the span, as a coalesced edit's already is.
- **One empty-state look on the dashboard.** An empty card says one line in `text-dim`, left-aligned in the card's padding, with its action (if any) as a link after it. "Going live next" loses its second line (O6 for the words and actions).
- **Notes for you:** no change (11c above).

### D. Mind graph

- **The legend in two labelled groups.** "Show": the node and line checkboxes, with their counts and swatches. "Key": the type dots, Retired type, Pinned, Open notes and the "Status" link that opens the status key. Each group's name is visible, as a mono label before it, and the two groups wrap as two rows when they do not fit in one. The DOM order (toggles, then Status, then the keys) and so the Tab order do not change.
- **Fit fills about 80%.** The first view, and "Fit all", leave 10% of the canvas on each side instead of 40px, and a small graph may be zoomed in up to 3 (it is 1.5 today) to fill that. A graph of one node, or of nodes at one point, is still centred at the cap.

### E. The public site (default theme)

- **Captions are text.** The Code block's, the Image block's and a rich-text figure's caption: `--th-font`, `--th-t-small` (13px), sentence case as typed (no `text-transform`, no tracking), in `--th-meta`. Mono stays for labels: dates, the language label of a code block, tags (O8), the footer.
- **The subpages list is navigation.** `nav.page-children` gets a mono label above it, and its links are set as the header's menu is (`--th-dim`, ink on hover, no underline), one per line. Its words are O7.
- **Tags** follow O8.

## Decisions

1. **One cap, one place.** The 760px is a CS Studio token (`--cs-form-max: 760px`) read by the post form, the page editor's column and Settings' card column. A translation tab reads `--cs-form-max-pair` (2 × 760px plus the pair's 16px gap).
2. **The cap is on the form, not on `<main>`.** The editors' header, the notes drawer and the tree-fit script keep their numbers; `Admin::Shell::TreeDividerComponent`'s constants and the stylesheet's rem literals do not change.
3. **The column is left-aligned**, so the form stays next to the tree and under the header's title (O3 asks to confirm).
4. **The slug line's one job moves to the placeholder.** `admin--editor--slug-preview` writes the placeholder of the slug input instead of an output span, with the same `slugify`. The held form's allow-list does not change: the action keeps its name.
5. **Settings' current section is one small controller**, `admin--settings--nav`, which watches the cards' headings with an `IntersectionObserver` and moves `aria-current` and the look. Without the script the links are as today. Nothing is written into the page that Turbo's snapshot would keep: the server draws no current item, and the script decides at `connect`.
6. **"No links" is said by the form, not by an empty row.** The social links fieldset carries one hidden field (`site_setting[social_links_present]`, or the same idea under a better name) so that a form with no rows means "no links", and the controller stops reading "no rows posted" as "not touched". A script or a client that posts nothing still leaves the links alone, as today.
7. **The matrix's word is the matrix's own.** The chip (`Admin::Ui::TranslationChipComponent`) stays as it is in the posts list's Languages column, where the code is needed because the column holds every language. The matrix draws a cell component of its own with the mark and the word; the marks are the chip's (`STYLES`), so the two cannot drift.
8. **The whole row is the existing stretched-link pattern** (groups and users lists), with the cell links raised above it.
9. **Media asks whether the library holds any kept image.** The toolbar's `@counts` (`Media::Search#counts`) is counted under the typed search, so a search that finds nothing would bring the zone back. When there is no search text its `all` answers the question; with one, one `exists?` over the kept images does (one more statement, on that path only). The view hides the zone's visible part when the answer is yes. The file input stays in the page (the button's `browse` opens it, and the upload controller's `input` target is it).
10. **Initials have one rule, on the server.** `PersonName.initials` gives two letters for a one-word name. The two scripts stop computing initials: the data they draw from carries them (the Mind graph card's notes data, the composer's mention list), written by `PersonName.initials`. The dashboard's activity row calls it too.
11. **Collapsing is the query's job, as data.** `Dashboard::Activity` reads up to four times its row limit of events, joins runs into one `Row` with a `count`, and returns at most 15 rows. The statement count is unchanged; the reading is one `LIMIT` larger. A run is: adjacent in the feed, same `user_id` and `via_label`, same action, same page or post (a block's owner), first to last within `Audit::COALESCE_WINDOW` (10 minutes, the window an edit already coalesces in). `Audit::Sentence` gains a count for the block actions ("added 4 Code blocks to", "edited 3 blocks on"); a run of mixed block types is "4 blocks".
12. **The dashboard's empty line is the card's, not the shared component's.** `Admin::Ui::EmptyStateComponent` is used in 16 places and stays as it is. `Admin::DashboardScreen::CardComponent` draws its own one-line empty state from `empty:` and an optional `empty_action:` (a label and a URL).
13. **Three columns at most** (`grid-cols-1`, then two, then three by container width), replacing `auto-fit`.
14. **The legend's groups are visible headings of the existing fieldsets and list**, not new elements: the `sr-only` legends become visible labels, "Lines" folds into "Show" (one visible label over both fieldsets; each fieldset keeps its own accessible name), and the key list's label becomes "Key". The "Status" link moves into the Key group visually only if it can without changing the DOM order (it already sits between the toggles and the keys).
15. **Fit is the same pure function with new numbers**: padding as a fraction (0.1 of each side) and `MAX_FIT_ZOOM` 3. No measured layout figure is pinned in a test (the Mind graph's testing rule): `camera.fit`'s module tests check the arithmetic on fixed boxes.
16. **The site's changes are values and class names in the default theme only.** No `--th-` token, template path, component method or helper is added, renamed or removed. A theme that replaced `pages/show.html.erb` or a block's template keeps what it drew.
17. **The subpages label is a public string**, a key under `public.` in `config/locales/public.en.yml`, read in the visitor's language with English as the explicit fallback. How a page template reads it without adding a helper to the contract is settled in the plan (the Code block's `string` is a component method; `pages/show` has none). If it needs a helper, that helper is a new name in `Theme::Contract::HELPERS`, which is a promise and a release note: O7 asks whether that is wanted.

## Rulings

1. **Settings is narrowed, not widened.** The design answer read a 550px column; the code gives about 900px. Taking "760px too" at its word makes the two screens agree.
2. **The translation pair is not capped at 760px** (the reason is under A).
3. **The slug line is dropped on pages too**, since it is one component.
4. **The matrix's "Translate →" is no longer a link** (Decision 8): the row's title link carries its name ("Translate: About us"), as the CTA's `aria-label` does today.
5. **The dashboard's hint "Schedule a draft to see it here." goes**, also when the card has one or two rows: it is the second line in another style the answer names.
6. **The "NONE" square's 9px text goes with it**, so nothing in CS Studio is under 11px.
7. **A Mind graph test of the fit waits for nothing new**: the first view is fitted at `[data-settled]`, as today.
8. **The tags' look waits for O8**; if it is not answered, they stay as they are and this spec ships without them.

## Open questions for Claude Design

- **O2. The save bar.** In the code the bar covers nothing at the end of the scroll. Which window and scroll position did the screenshot show? If it is the mid-scroll overlap, should a stuck bar get a shadow or a stronger top edge so it reads as over the content? Recommendation: a top shadow only while stuck (`admin--saving--save-bar` already measures it), nothing at rest.
- **O3. Where the extra width goes.** The answer says "to the notes drawer and the margin". The drawer is a fixed 400px column whose width the tree's fit rule and its script count with. Recommendation: the drawer stays 400px, the margin takes the rest, the column is left-aligned. And on a translation tab: two 760px columns (recommended), or 760px stacked?
- **O4. The matrix's marks and words.** The answer says "○ Missing", "◐ Outdated", "● Done". Part 1 gave outdated the ↻ mark in the chip and the language tabs, and the chip's words are "Translated" / "Not translated" / outdated. Recommendation: one vocabulary in CS Studio: ○ / ↻ / ● with "Missing", "Outdated", "Translated". If ◐ is wanted, should it replace ↻ everywhere?
- **O5. The legend's "Status" link.** It is a key, not a filter. Recommendation: first item of "Key" (it is already after the toggles in the DOM).
- **O6. The dashboard's empty lines and actions.** Recommendation: Your drafts "No drafts." + "Start one" (moves the focus to the quick-create field; no link when there is no quick-create row); Going live next "Nothing scheduled." + "Your drafts →" (the posts list, drafts); Unpublished changes "Nothing waiting to be published."; Needs translation "Nothing to translate."; Notes for you "No notes for you."; Open threads "No open threads."; Recent activity "No recent activity.". Left-aligned or centred?
- **O7. The subpages list.** It is what the review saw as "Resume under a rule" and as "footer links under Test". What should its label say ("Pages", "In this section", "More")? Recommendation: "In this section", mono, as the date above a post's title. And should it show on a post's own page at all? Recommendation: no: on a post page the listing page's subpages are not about the post.
- **O8. Tags on the post page.** Today they are mono capitals, no border, no link. There is no tag page on the public site (no route; a post's address comes from the list blocks that list it), so a link would have to go to a page whose list block filters by that tag, which may not exist or may be several. Recommendation: plain text in this PR, in the small sans size, lower case as stored, after a mono label "Tagged" (`rails, ruby`); links when the site has tag pages.

**Claude Design's answers (2026-10-23, in words; saved in `.superpowers/design-answers/2026-10-23-layout-points.md`):**
- O2: the screenshot was mid-scroll. While the bar is stuck over content: a 1px `--cs-line-strong` top border and a shadow `0 -6px 16px` of ink at 6% (12% in dark); nothing at rest.
- O3: the drawer stays 400px, the margin takes the rest, the form column is left-aligned. A translation tab: two columns of up to 560px with a 24px gap (1,144px); stacked, source above, when two columns of at least 400px do not fit.
- O4: one vocabulary in CS Studio: ○ Missing, ↻ Outdated, ● Translated; the chip's "Not translated" becomes "Missing".
- O5: the Status link is LAST in Key, after the marks, as the text link "Status key…".
- O6: the proposed lines, except "No unpublished changes." and "Start a draft"; left-aligned under the card's title, where the first row would be.
- O7: "In this section", mono; hidden on a post's own page; nothing drawn (no label, no rule) without subpages.
- O8: a mono "Tagged" label, then the tags in the small sans size, lower case as stored, joined by commas, plain text; links once tag pages exist.

## Open questions for the owner

- **O1.** Settings is about 900px today, not 550px. Narrow it to 760px (recommended, Ruling 1), or leave it?
- **O7 (the owner's half).** Related posts are not on the public post page at all, though the editor's help says they "show at the end of the article". Showing them is a feature: related posts are in no published copy (`docs/reference/publishing.md`), so the page would read the rows (a `# public: rows (reason)` line, and the canary test) or the copy would have to hold them, which is a publishing decision. Recommendation: not in this spec; a small spec of its own that decides the copy, with the "Related" label then. Until then, change the help text in the post editor so it stops promising it.
- **O9.** The dashboard's activity row draws one letter today, from the full display name. Use the two-letter rule there too (recommended), even though the rest of CS Studio names people by `display_name`?
- **O10.** Collapse uploads too? Twelve images uploaded in a row are twelve records, so the rule above (one record) keeps twelve rows. Recommendation: yes, "You uploaded 12 images", linking to the library; it is the same flood.
- **O11.** Add the two left-overs of part 1 (count badges over page cards in the Mind graph; the reference card's summary triangle)?

**Owner's answers (2026-10-23):** O1: narrow Settings to 760px. O7: related posts on the site are a spec of their own later; this work changes the post editor's help text so it stops promising them. O9: yes, two letters in the dashboard's activity too. O10: yes, collapse uploads ("You uploaded 12 images"). O11: yes, both left-overs of part 1 are in this work.

## As built (part 1, CS Studio's forms and lists)

Built by `docs/superpowers/plans/2026-10-24-layout-points-forms-and-lists.md`, in thirteen tasks. The plan's twelve rulings, one line each:

1. O3's numbers replace Decision 1's 1,536px: a translation tab's column is `--cs-form-max-pair` (1144px), two 560px columns and a 24px gap, side by side from 824px of form width.
2. Settings stays 760px on its language tabs; its pair stacks there, as it does in the Media panel.
3. The cap is a class on existing elements (`Admin::EditorScreen::FormColumn.classes`: `admin-form-column`, plus `--pair` on a non-default language), never a new wrapper.
4. The dashboard's activity row keeps its own initials until plan 2; `PersonName.initials` changes for notes, presence, the holder avatar and the hold strip.
5. "Missing" replaces "not translated" in the chip, the language tabs' screen-reader words and the matrix's cell names; the posts list's filter segments and the chip's outdated sentence stay.
6. The Translations row's stretched link sits in the action cell, not the sticky title cell; the title cell is `z-20`, the cell links `z-10`, "Translate →" is shown by `opacity`.
7. The stuck save bar is found by `-bottom-px` and an `IntersectionObserver` at threshold 1; its shadow is the token `--cs-shadow-stuck`, dark in both schemes.
8. The social links' marker is `site_setting[social_links_present]`, and `Values#social_rows` honours it, so a refused save keeps a cleared list cleared.
9. The reference card's triangle shows only where the card folds (stacked).
10. Settings' current section is the last heading whose top is above 40% of the window; the last on a page scrolled to its end; the first on a page that does not scroll.
11. The related-posts help (O7) says the posts are linked in the Mind graph and the site does not show them yet.
12. Media's drop zone wrapper is `hidden` once the library holds a kept image; the file input inside it stays the upload target; a library of trashed images is empty.

Departures from the spec's text, and from the plan's:

- Decision 1's 1,536px is O3's 1,144px (ruling 1).
- The matrix's missing name now says "missing" (O4), where the spec had left the old word.
- The dashboard row's initials and the Mind graph's count badges (O11) are plan 2's, by the plan's ruling 4 and its scope note; the dashboard's grid, empty lines and collapsed activity are plan 2's too, and the site (E) is plan 3's.
- Task 6 listens to the window's scroll and resize instead of using an `IntersectionObserver` for the nav (a tall section never crosses a threshold at the 40% line), and its system test uses a 400px window, because at 700px Publishing's heading cannot reach the top and ruling 10 makes the last section current.
- Task 10 adds `isolate` to the matrix's scroll wrapper: ruling 6's `z-20` title cells otherwise painted over the shell's sticky top bar below 1280px.
- Task 10's system test presses the Type cell with a native mouse click, which lands on the stretched link (that is the feature), and a second test holds the top bar over the titles.
- Task 8's stuck edge is a pixel clip (`-bottom-px`); at a fractional browser zoom it may never read as stuck, which was not checked by hand.
- Outdated cells use the chip's own mark, ↻ (O4), not the ◐ of one example in the plan's Review Focus.

## What this does not do

- No related posts on the public site (O7), no tag pages, no navigation block type.
- No change to the posts list's Languages column, the language tabs or the chip.
- No change to the notes drawer's width, the tree's fit rule or the shell's breakpoints.
- No change to the audit log screen: collapsing is the dashboard's.
- Not the Note block (D4), which stays separate.

## Risks

- **Translation tabs at 1,536px.** On a window where the pair just fits, the translation tab is wider than the default tab, so switching tabs moves the column's right edge. Accepted if O3 says so.
- **A three-lane section at 760px** gives lanes of about 230px. Lanes hold tiles (a summary each), which fit; a long summary truncates sooner.
- **The stretched row link and the sticky title column.** The matrix's title cell is `sticky`, and a sticky cell becomes the containing block of the link's `::after`, which would then cover only that cell. The plan must make the row the containing block (or give up the stickiness of that layer); a system test clicks an empty part of a row.
- **"Translate →" on hover.** The CI browser cannot hover: a system test finds it with `visible: :all` (CLAUDE.md).
- **The social links' new hidden field** changes what "no rows" means to the controller. A test posts the form with no rows (links cleared) and one without the field (links kept).
- **Presence circles change too** (Decision 10). Its tests pin initials in places (`test/system/admin/presence_test.rb`, the avatar and holder-avatar component tests).
- **The legend's labels take a little height** on a narrow window; the canvas below takes what is left, so its fit is measured after.
- **The site's captions**: a theme that relied on the default caption being mono keeps its own rule; the release note says the default changed (values only).
- **The dashboard reads more events** (up to 60 instead of 15); the index serves the `ORDER BY … LIMIT` either way.

## Testing

- **Widths**: a system test per screen measures the form column at a 1,600px window (760px on the post editor's default tab, the page editor and Settings), and a translation tab keeps the pair side by side. A design-rules line: the 760px lives in the token only.
- **Slug**: component tests for both editors (no preview line; the placeholder holds the derived slug); a system test types a title into an empty slug's form and reads the placeholder.
- **Settings**: a system test scrolls and reads `aria-current`; integration tests for no row with no links, the empty fieldset posted (links cleared) and the field absent (kept); a component test without "NONE".
- **Translations**: component tests for the cell's mark and word in each state, the cell link's name, one action link per row; a system test clicks an empty part of a row and lands on the focus language.
- **Media**: the zone is drawn for an empty library and not for one with images, also under a search with no results; the existing overlay and upload tests run as they are.
- **Initials**: `test/values/person_name_test.rb` gains one-word cases (and keeps the grapheme, digit and at-sign cases); the card's and the composer's data carry initials; a source test that no script under `app/javascript` computes initials.
- **Activity**: query tests for a run (same person, action, record, within 10 minutes), the run's break at 10 minutes, at another person and at another record, mixed block types, the row limit after collapsing, and the unchanged statement count; sentence tests for the counted wording; the read scope still decides every row.
- **Dashboard**: a component test of the card's empty line and action; a system test of three columns at 1,600px and one at 600px.
- **Mind graph**: the legend component test keeps "every toggle and every key has a swatch" and gains the two visible labels; the existing tab-order and toggle tests run as they are; module tests of `camera.fit` with the new padding and cap.
- **Site**: `test/integration/design_tokens_test.rb` reads the caption rules (sans, `--th-t-small`, no transform); the theme scaffold test (`test/values/theme/scaffold_test.rb`) and the contract ledger stay green, which shows no promise moved; a public page test for the subpages label in English and in a language without a public locale file.
- The full check: `bin/rubocop`, `bin/brakeman`, the unit suite, the browser suite at `PARALLEL_WORKERS=6`, `bin/theme-build-check`.

## Size, and a suggested split

Too big for one pull request: it touches every editor, Settings, Translations, Media, notes and presence, the dashboard's query and sentences, the Mind graph and the public theme. Recommended, in this order:

1. **CS Studio's forms and lists** (A and B): widths, slug, Settings' four, Translations, Media, initials. Screens only, no query.
2. **The dashboard and the Mind graph** (C and D): the grid, empty lines, collapsed activity (a query and `Audit::Sentence`), the legend and fit.
3. **The site** (E): captions, the subpages list, tags. The only one with a theme release note, and the only one that waits on O7 and O8.

Each closes its own lines of `docs/roadmap.md`: "Contrast and buttons, part 2", and from the polish backlog "no active item in the in-page nav" (Settings), "the big Choose file drop zone still drawn above the grid" (Media), "lists and editors spanning the full width" (across screens), "a quieter empty-state line" (Dashboard).

## Documentation (the PR's "Documentation" section; pages in `contentspiel-docs`)

Editors: `editors/getting-started/signing-in-and-finding-your-way.md` (the dashboard: three columns, empty lines, collapsed activity), `editors/pages/build-a-page-with-blocks.md` and `editors/pages/page-settings-and-search-appearance.md` (the narrower column, the slug field without its line), `editors/posts/publish-schedule-and-preview.md` and `editors/posts/posts-and-content-types.md` (the post editor's width and slug field), `editors/translating/keep-translations-up-to-date.md` (the matrix's words, the whole row, the hover action) and `editors/translating/write-in-more-than-one-language.md` (the translation tab's width), `editors/media/the-media-library.md` (no drop zone once there are images), `editors/posts/tags-related-posts-and-the-mind-graph.md` (the legend's Show and Key, Fit; and if O7 changes the help text, what related posts do on the site), `editors/working-together/notes-on-content.md` and `editors/working-together/who-else-has-this-open.md` (two letters in a circle), `editors/getting-started/how-a-site-is-built.md` (the subpages list's label). Administrators: `administrators/site/site-settings.md` (the nav's current section, "+ Add link", no NONE square, the width). Integrators: `integrators/theming/the-theme-contract.md` (the default theme's captions and subpages list changed by value and class only; a helper only if O7 adds one).
