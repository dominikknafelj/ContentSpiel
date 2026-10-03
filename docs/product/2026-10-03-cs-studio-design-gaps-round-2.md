# CS Studio design handoff v2 — round-2 gaps

Written 2026-10-03. Read-only analysis of `tmp/design/design_handoff_cs_studio_v2/` (README + mocks) against the code at main `395ae29`. Mock names below drop the `.dc.html` suffix.

## A. Conflicts with how the app works or with product decisions

1. **Image alt text is a per-use override, not read-only.**
   - Question: An image block, a page hero and a rich-text image each have their own optional alt (and caption) that overrides the library default for that one use, per language. How should the field look: editable, with the library text as placeholder and a "from Media" hint when empty? Or do you propose removing per-use overrides (a product change)?
   - Evidence: README §4.1 "Image block's alt text is read-only, with a link to Media"; `Studio Pages` block shows "ALT TEXT · FROM MEDIA LIBRARY … Edit alt text once in Media". Code: `content_blocks.alt`/`caption`, `pages.hero_alt` (`db/schema.rb:110-112,174`); `block_card_component.html.erb:67-71` and `page_settings_form_component.html.erb:57-59` render editable alt with the asset default as placeholder; rich-text node `alt`/`caption` (`app/javascript/rich_text/image.js:46-54`); resolution order in CLAUDE.md "Media library".
   - Blocks: image block card, hero field, rich-text image popover.

2. **Permission scopes are per permission, not per row.**
   - Question: Each of the 11 post/page permissions carries its own scope (content types, "own only", page branches). The seeded Author group is `posts.read` + `posts.create` unscoped and `posts.edit` own-only. One scope control per row can't express that. The footnote says "open a scope to set it per action" but that state isn't drawn. Please draw: the per-action scope editor, a row with mixed scopes, the page-branch picker (a tree of pages; ticking one includes its subtree), and the multi-select of content types.
   - Evidence: `Studio Group Edit` matrix: `row('Posts','posts','All content types', hasOwn…)`, one scope per row. Code: `access_control_grants.scope` per grant (`db/schema.rb:17-20`); `AccessControl::Seeds` Author (`app/models/access_control/seeds.rb`); today's per-permission scope UI and branch picker in `permission_matrix_component.html.erb`.
   - Also undrawn in the same matrix (exist today): a ticked box the current user may not hand out (shown ticked but disabled), the warning for a grant whose content type no longer exists, and "A page you can't open (kept)" inside the branch picker.
   - Blocks: the whole Group edit screen.

3. **Bulk "Translate empty fields…" on Posts has nothing to do under the suggestions-only rule.**
   - Question: AI output is never saved until an editor presses Use on a suggestion in the editor. What does the bulk action do for 5 selected posts: open a review queue, or save machine text directly (a product change we'd need to approve)? If it stays, into which language(s)? Otherwise we drop it from the bulk bar.
   - Evidence: README §4.3 bulk bar; `Studio Posts` "Translate empty fields…". Spec `2026-10-02-translation-helpers-design.md:22,30` ("Nothing machine-written is saved without that click"); `AI::Translate` caps a request at 20 fields / 6,000 characters and runs inside the web request (CLAUDE.md "Translations").
   - Blocks: posts bulk bar. Related: bulk **Publish** needs a rule for rows the user may not publish (permissions are per record).

4. **Word diff and "CHANGED 1 DAY AGO" need the previous English text and a change time; the app stores neither.**
   - Question: For an outdated field we store only a hash of the English the translation was made from. No old text, no per-field change time. What does the reference card show when there is nothing to diff against: plain current English with the warn border and the two buttons? Is the diff a must (then we store the source text per field from now on, and older translations still have none)? And what is diffed for a rich-text body?
   - Evidence: README §4.1 "word diff of the English change"; `Studio Post Editor` "ENGLISH ↻ CHANGED 1 DAY AGO / Welcome to ~~the~~ our new site". Code: `translation_sources` = `{field => {locale => sha256}}` (CLAUDE.md "Tracking"; `db/schema.rb:122,189,231`). State `:unknown` (translated before tracking) never reads outdated.
   - Blocks: side-by-side reference card; "Review changes →" on Translations; dashboard "most urgent outdated item".

5. **Tokens have no name and no stored fragment.**
   - Question: The mocks give a token a name ("claude-desktop") and a masked value (`cs_mcp_••••e4c1`). Tokens are stored hashed with no name. §9 B16 and DS rule 09 say never show any part of a secret. Confirm: (a) drop the masked-token column; (b) add a token name (new field, we agree if you want it, also in the setup wizard); (c) keep today's columns the mock drops: which user the token acts as, Created, Revoked status (revoked tokens stay listed), last-used IP?
   - Evidence: README §4.8 "Tokens table: Name, Group, masked token, Last used"; `Studio AI Assistant` row "claude-desktop Author cs_mcp_••••e4c1 NEVER"; `Setup Wizard` "Token name". Code: `api_tokens` has `token_digest`, `last_used_at`, `last_used_ip`, `revoked_at`, `user_id`, `group_id` only (`db/schema.rb:74-82`); today's table in `app/views/admin/api_tokens/index.html.erb`.
   - Blocks: AI assistant screen, revoke dialog title, setup wizard MCP step.

6. **Who is the actor of an MCP change: the token or its user?**
   - Question: Dashboard and Audit log mocks name the token as the actor ("claude-desktop suggested a translation…", square avatar). The product rule is that a change through a token reads as the token's user, never the token. Proposed: "Mara König via claude-desktop" (needs the name from A5) with the MCP chip. OK? Also, DS rule 09 "Agent-authored content is labelled MCP until a human publishes it" is drawn nowhere outside the activity rows: where does that label appear (posts list, editor header), or is it dropped?
   - Evidence: `Studio Dashboard`/`Studio Audit Log` activity rows; CLAUDE.md "Admin": "a change made through an API token still reads as the token's own user, never the token". Note: `ai.translated` is a CS Studio editor action today, not an MCP tool, so the sample row can't occur.
   - Blocks: activity row component, audit sentence builder.

7. **Dashboard "Recent activity" versus permissions, and the lists it replaces.**
   - Question: The feed is audit-log data. The audit log needs `audit.view` (Admin only) and is not read-scoped by content; the dashboard is open to everyone and each list is scoped to what the viewer may read. Which is intended: (a) feed only for `audit.view` holders, others see today's "Recently changed on the site"; or (b) a content-only feed (no sign-ins, users, settings) limited to readable items for everyone? Also confirm that "Scheduled by you" and "Recently edited by you" are dropped on purpose, and that "Your drafts" keeps today's meaning of "mine" (author, or last changed by me).
   - Evidence: README §4.2; `Studio Dashboard` (3 cards + feed; rows such as "You signed in" appear in the audit mock). Code: `Dashboard::Feed#drafts/scheduled/going_live_next/recently_updated/recently_edited` (`app/queries/dashboard/feed.rb:45-70`); `require_permission("audit.view")` (`audit_events_controller.rb:52`); "Full audit log →" already gated (`dashboard/show.html.erb:40`).
   - Blocks: dashboard.

8. **Confirm-dialog and help copy that describes behaviour the app doesn't have.** Tell us for each whether the copy should change or the behaviour should (the latter is new work):
   - Turn off language: mock says "/es pages redirect to English". App: those URLs answer 404 (`app/services/locales/disable.rb:4-8`).
   - Unpublish: mock says "2 subpages stay live but become unreachable from the menu". App: a live page under a draft page is also "not found" (`app/models/public_site/resolver.rb:2-3`).
   - Default language: mock says "Old English URLs redirect". No redirect is created on a default change today; old unprefixed URLs resolve in the new default language or 404.
   - Delete user (`Studio Users`, `Studio User Edit`): "pages, posts and media are kept and reassigned to you". App: posts keep no author (`posts.author_id` nullify, `db/schema.rb:311`); nothing is reassigned. Reassigning would also hand "own only" rights to the deleter.
   - Groups list: "Delete a custom group … once it has no members or tokens". App: deleting is allowed with members, and revokes the group's tokens (`app/services/groups/destroy.rb`); the confirm says so.
   - Media: "up to 20 MB" (and the "TOO LARGE · 34 MB" tile). Limit is 10 MB (`app/models/media/asset.rb:27`).
   - Media detail, in-use image: "…or trashing will leave an empty block" implies trashing is possible. It is refused while a kept page or post uses the image (CLAUDE.md "Trash").
   - Blocks: copy for seven dialogs/help texts.

9. **Settings + Languages on one save bar cross two permissions and three save models.**
   - Question: Settings needs `settings.manage`, Languages needs `languages.manage`; a user can hold one without the other. Does the merged screen hide the section, or show it read-only? And which Languages actions wait for the bar: reorder and fallback (pending) versus Add, Turn off and the Default radio (each confirmed in a dialog; §9 B12 calls "language off" instant)? What happens to pending changes when an instant action reloads the list?
   - Evidence: README §4.5 and §9 B12 ("Explicit save … Settings (all sections incl. Languages)" and "Instant … language off"); `Studio Settings` single bar "2 unsaved changes". Code: separate controllers and permissions (`languages_controller`, `Locales::Disable` authorises `languages.manage`).
   - Blocks: settings layout and save controller.

10. **API key and "Test connection" inside the save bar.**
    - Question: The key has its own Save key / Remove key form by decision (a half-typed key is never saved), and Test connection tests the *saved* provider, model and key. With one save bar: is Replace still its own immediate save (draw the replace state: input + Save key/Cancel)? And is Test connection disabled, or labelled "tests saved settings", while provider or model have unsaved changes?
    - Evidence: `Studio Settings` chip "Key saved · added 2 Oct · Replace Remove", "Test connection". Spec amendment `…translation-helpers-design.md:296`; `settings_controller.rb:85-90`. "added 2 Oct" needs a stored date we don't have (see C-data list).
    - Blocks: AI translation section.

11. **"Invite user" and other invite wording.**
    - Question: There is no invite flow (a later roadmap item); a user is created with a password the admin shares, as `Studio User Edit` (new) itself draws. May we label the button "New user" and drop the toast "…no invite was sent" and the setup line "You can invite editors…"?
    - Evidence: README §4.9, `Studio Users` header, DS 08 toast, `Setup Wizard` admin step.
    - Blocks: users header copy only.

12. **Password rule "12 or more characters" is new.**
    - Question (for us, then the designer): the app has no minimum length today. Do we adopt 12 as a server rule for setup, user new, change and reset? The meter and the disabled submit depend on it. Also: "Other sessions are signed out" is true today; the reset "expires in 15 minutes" is true.
    - Evidence: DS 08 "Password field"; `Studio Change Password`. Code: `User` has only `has_secure_password` (`app/models/user.rb:1-15`).
    - Blocks: password component.

13. **Language-tab overflow threshold is stated twice, differently.**
    - Question: README §2.4 and DS 07 say tabs collapse after 4; DS rule 09 says "switchers collapse to a dropdown above three". Which?
    - Blocks: language tabs component.

14. **Setup wizard drops the system-check step.**
    - Question: The wizard has 8 steps today: token, **system check** (optional; storage, image processing, mail, jobs), admin, site, languages, MCP token, starter content, review. The mock has 7 and no system check. Keep it (please draw it; it shares its result list with System status) or remove it?
    - Evidence: `Setup Wizard` `ids = ['token','admin','site','languages','mcp','starter','review']`; `setup_controller.rb:9-11`.
    - Blocks: setup wizard.

## B. Still undefined or undrawn

15. **Account block "role".**
    - Question: A user has zero or more groups plus an owner flag; there is no single role. What does the sidebar account block show: "Owner" for owners, else the group names (how many before "+N"), else nothing for a user with no groups?
    - Evidence: README §2.1 "name, email and role"; `StudioSidebar` "one@example.com · Owner"; `Studio Users` puts "Owner" in the GROUPS column as if it were a group. Code: `users.owner` boolean + memberships (`db/schema.rb:36-39,289`).
    - Blocks: sidebar account block, users list group column.

16. **Sidebar badges and groups per viewer.**
    - Question: (a) Are badge counts what the *viewer* can act on (Trash lists only items the viewer may delete; Translations only readable items), or site-wide? (b) Translations is hidden with one language, and most entries are hidden by permission: does a group heading with no visible items disappear (an Author sees CONTENT plus "AI assistant" alone under SYSTEM)? (c) The Translations count and the System status count have no stored value: translation state is computed in Ruby per record, and system checks (storage write, image resize, mail) run live when the page is opened. Is a badge that is cached and a few minutes stale acceptable, or can these two badges go?
    - Evidence: README §2.1 badges; `StudioSidebar` badges `14`, `3`, `1`. Code: `Admin::BaseController::MODULES` permissions and `if: Locales.enabled.size > 1` (`base_controller.rb:45-61`); `SystemStatusController#show` runs `Setup::SystemCheck.run` on each view; CLAUDE.md "Translations overview … filters in Ruby, batch by batch, because there's no stored state".
    - Blocks: sidebar component; also "last run 17:30 / Run checks again" on System status (today every page view is a run).

17. **Translation percentages, counts and the "Translation" filter.**
    - Question: "% done", "12 missing · 1 outdated" (Dashboard card, Translations summary cards), the Posts filter "Translation: Any ▾" with paginated totals, and Media's "Untranslated" count all need a queryable translation state, which doesn't exist yet. Which of these are essential for the first build? What is "% done" measured in (items, or fields)? What does the Dashboard card show with one language enabled (we assume: hidden), and for a viewer who may read nothing?
    - Evidence: `Studio Dashboard` `langs: … pct: '14%'`; `Studio Translations` summary; `Studio Posts` filter; `Studio Media` filter `Untranslated`. Code: as B16(c); `Translations::Status`/`CachedStatus`.
    - Blocks: decides whether this pass includes a stored translation-state table.

18. **Translations matrix: which language does a row open, and where is "Mark as up to date"?**
    - Question: A row has one CTA but a column per language. Does the CTA open the first outdated/missing language, or is each chip a link to that language's editor? Site title/tagline are translated too but appear in no row: add a "Site settings" row?
    - Evidence: `Studio Translations` one `cta` per row; today's overview is per language (`/translations?locale=de&type=`). `SiteSetting` is tracked (CLAUDE.md "Tracking").
    - Blocks: translations screen.

19. **Read-only ("View only") editors.**
    - Question: A user who may read but not edit a page/post gets the editor with all fields disabled, no autosave and a "View only" badge. The same happens for a user with `edit` but not `publish` on a Live item (until draft revisions exist). Please draw: the header (which buttons remain: Preview, Activity?), disabled fields and blocks, and the hint that explains why. Same question for Media detail when the viewer is neither the uploader nor a media manager.
    - Evidence: no mock contains a view-only state. Code: `app/views/admin/shared/_view_only_badge.html.erb`; `editable?` in `post_form_component`, `page_settings_form_component`, `block_card_component`; CLAUDE.md "editing an already-published record needs `publish`".
    - Blocks: both editors, media panel.

20. **Autosave conflict: "Changed elsewhere".**
    - Question: When someone else saved the record since this form loaded, autosave refuses and the indicator reads "Changed elsewhere — reload to see the latest". DS 07 draws only SAVING / SAVED / NOT SAVED · Retry. Please add this state (indicator text, is it a toast or a bar, the Reload action, what happens to the editor's unsaved text).
    - Evidence: `save_status_component.rb:52`; CLAUDE.md "Admin" (`base_updated_at`).
    - Blocks: save-status component.

21. **Schedule… dialog.**
    - Question: "Schedule…" and "Edit schedule" open something that isn't drawn. Needed: date and time input, the note that times are in the site time zone, the "Remove schedule" action, and the validation for a past time.
    - Evidence: README §4.1 ⋯ menu; DS 07 header "Scheduled · Thu 8 Oct 17:30 … Edit schedule"; `Studio Modals` has no schedule tab. Today: inline datetime field + Schedule button (`post_form_component.html.erb:~75-81`).
    - Blocks: editor header.

22. **Page editor fields and blocks that exist but aren't drawn** (`Studio Pages`):
    - **Hero image** in Page settings: chosen image, Change/Remove, per-page alt override (see A1). Mock has none, although `Studio Media` says "Used on: About › Hero image".
    - **Post list block** body: its settings are content type, tag and limit. Mock offers "Post list" in Add block but draws no card.
    - **"Unavailable type" block card**: a block whose type is no longer registered shows a red label and no fields, only Delete.
    - **SEO section expanded**: fields are meta title and meta description. The collapsed label also says "SHARE IMAGE"; the app has no share image. New feature or remove from the label?
    - **Block ⋯ menu** contents (Move up/down? Delete — permanent, blocks don't go to the trash).
    - Evidence: `db/schema.rb:172-189` (no share-image column); `block_types/post_list.rb:10-12`; `block_card_component.html.erb:8-9`.
    - Blocks: page editor.

23. **Post editor: content-type fields.**
    - Question: A content type can define its own fields; Resume entry has Company, Role, Role type (select), Start date, End date, and custom types can add string, text, URL, integer, boolean, date, select, tag and repeatable group fields, some translatable. `Studio Post Editor` draws only a blog post. Where do these fields sit (between Excerpt and Body, as today?), and how do a date field, a boolean and a repeatable group look in the new style, including side by side in a translation?
    - Evidence: `content_types/resume_entry.rb:21-25`; `app/components/admin/fields/*`; `post_form_component.html.erb:142`.
    - Blocks: post editor for 2 of 3 built-in types.

24. **Page tree rows not drawn.**
    - Question: (a) Context-only rows: ancestors the viewer may not open are shown greyed, without link or actions ("You can't open this page"). (b) The per-row "+" (add a page under this one), shown only where the viewer may create: kept, or replaced by "+ New page" plus the modal's INSIDE select? (c) Rows the viewer may not move: no handle? (d) The orange number counts *missing* translations; how is *outdated* shown on a row?
    - Evidence: `Studio Pages` tree (handle, title, Draft chip, number only); `tree_node_component.html.erb:1-5,35-38`.
    - Blocks: tree component.

25. **Rich-text editor popovers.**
    - Question: "Link" and "Insert ▾ → Page / Image / YouTube" each open a small dialog today: URL, internal page/post search, image alt and caption (per-use, see A1), YouTube URL. None is drawn. Use the 560 form dialog, or an anchored popover?
    - Evidence: `rich_text_column_component.html.erb:7,29`; README §3 "Insert ▾".
    - Blocks: rich-text toolbar.

26. **AI suggestions: "Use all", rich-text warnings, and suggest on outdated fields.**
    - Question: After a bulk suggest finishes, today's header offers "Use all"; the v2 header only draws the progress state. Is "Use all" kept, and where? A rich-text suggestion can carry repair warnings ("unknown directive kept as text"): where do they show in the suggestion box? And "Suggest update" on an outdated field: does the suggestion replace the whole existing translation in the same box?
    - Evidence: DS 08 "Busy & pending"; spec `…translation-helpers-design.md:187-194`.
    - Blocks: suggestion component.

27. **Trash rows that aren't drawn.**
    - Question: (a) A subpage trashed as part of a branch and restored alone needs a new parent: today a "Restore under [page ▾]" select in the row. Dialog or inline? (b) "Trashed by unknown" when the user is gone or the system did it. (c) "Delete now…" disabled with its reason (member of another page's trashed branch; image still used). (d) The DELETES column when retention is 0 (never) and on the last day ("today"). (e) "Empty trash…" needs `trash.empty`; others see only their own deletable items.
    - Evidence: `Studio Trash` rows (`by: 'You'`, `IN 30 DAYS` only); `trash_screen/row_component.html.erb:34-48`, `row_component.rb:66,81`.
    - Blocks: trash screen.

28. **Users and User edit: locked states.**
    - Question: Draw or describe: a group card the current admin may not assign (today ticked/unticked but disabled); the Owner zone for the last owner ("can't be demoted") and for a non-owner viewer (can't touch an owner at all); Delete user disabled for the last owner; a user the admin may not manage (their groups exceed the admin's own rights). Also what "Make owner…" confirms, and the reverse ("Remove owner").
    - Evidence: `Studio User Edit` shows only the free case; `users/_access_fields.html.erb:14-39`; CLAUDE.md "Access control" (`Users::OwnerProtection`, `#outranked?`).
    - Blocks: user edit.

29. **Tags "Merge into…" has no rules.**
    - Question: New feature. Confirm: posts of the merged tag get the target tag, the merged tag is deleted, no undo, one audit event; the dialog is a tag picker with a confirm. Is deleting a tag that still has posts allowed (today: yes, with a confirm)?
    - Evidence: README §4.9, DS 08 tag row menu; `tags_controller.rb` has only index/update/destroy.
    - Blocks: tags screen (or we defer Merge).

30. **Audit log details.**
    - Question: (a) Date-range presets: which ones, and is a custom from–to range kept (today: two date inputs)? (b) "Side effect: DE ↻ Deutsch translation marked outdated" is not stored on an event; may we drop it, or compute it only for the newest event of a record? (c) Coalesced events (an autosave burst is one row covering e.g. 16:05–16:31): how is the time span shown in the list and the detail? (d) `access.denied` and `session.failed` rows: sentence and style (warn?).
    - Evidence: `Studio Audit Log` "Last 30 days ▾"; `Studio Audit Event` "Side effect"; `audit_events_controller.rb:118-140`; CLAUDE.md "Audit" (coalescing).
    - Blocks: audit screens.

31. **Dashboard quick create with "Page", and the Posts split menu with "Page".**
    - Question: A page needs a parent. Does "Page" in the quick-create select (and in the New post ▾ menu in DS 08) open the New page modal with the title carried over, or create under Home? Which types show for a user who may create posts but not pages (and the reverse)? With "Upload image" removed from the dashboard, is Media the only upload entry?
    - Evidence: README §4.2; DS 08 "NEW POST ▾ … Page"; `quick_create_component.html.erb:6-23`.
    - Blocks: quick create.

32. **Settings › Site language tabs under one save bar.**
    - Question: Title and tagline are edited one language at a time (the form posts its own `?locale=`). With explicit save, does switching the English/Deutsch/Español tab keep unsaved text of all languages in the page (one Save writes all), or does it trigger the Leave dialog? Same for the in-page left nav: scroll anchors on one long form, or separate pages?
    - Evidence: `Studio Settings` (tabs inside the Site card, one bar); spec amendment `…translation-helpers-design.md:293`.
    - Blocks: settings form structure.

## C. Missing screens or states

33. **Admin "No access" (403) and "Not found" (404) pages.** A user opening an area they lack gets a 403 page inside the admin layout; a record outside their scope is a 404. Neither is drawn. Needed: title, one line, the way on. Evidence: `app/views/admin/errors/forbidden.html.erb`; CLAUDE.md "not found, not forbidden". Blocks: both pages (they inherit the new shell).

34. **Pages screen with no page selected, and the starter-pages offer.** `Studio Pages` always has a page open. Needed: the right-hand column on `/pages` before a selection (today: an empty state), and where "Create starter pages" sits now that §3 limits it to "only Home exists" (today: a "More" menu and the empty state). Evidence: `app/views/admin/pages/index.html.erb:14-31`. Blocks: pages index.

35. **Related posts: hidden relations.** The chip input is drawn empty. Needed: chips for linked posts (title + type dot? status?), the line "+N related posts you can't open" for relations outside the viewer's read scope, and the search result row. Evidence: `Studio Post Editor` "Search posts to link…"; `related_posts_component.html.erb:23`. Blocks: related-posts component.

36. **Media states not drawn.** (a) "Used only by items in the trash" in the Used on list (trashing is then allowed). (b) The picker's upload: the header has an "Upload" button, but not what happens after choosing files inside the modal (progress tiles in the grid, auto-select the new image?). (c) The picker for a user without `media.upload`: they may keep or clear an image but not browse the library. Evidence: `detail_component.html.erb:52`; `Studio Modals` picker; CLAUDE.md "Media library" (`Media::Choosing`). Blocks: media panel and picker.

37. **Group edit: delete, and a custom group.** The mock shows only built-in "Editor". Needed: the Delete group zone for a custom group and its confirm ("Its members lose its permissions, and deleting it revokes N tokens", see A8), and the state where the viewer may not manage this group (it holds grants they couldn't hand out). Evidence: `Studio Group Edit`; `app/views/admin/groups/edit.html.erb:14`; `AccessControl.can_manage_group?`. Blocks: group edit.

38. **Setup wizard details.** Besides the missing system-check step (A14): the starter-content step says "Sample entries are marked as samples and can be deleted in one step"; the app has no sample marker and no one-step delete (new feature, or drop the sentence?). Social links use a platform select here but free "Label" text in `Studio Settings`; the app stores a free name + URL. Which one? Evidence: `Setup Wizard` starter step and `so.p ▾`; `settings_form_component.html.erb:70-73`. Blocks: setup wizard.

39. **Data the mocks show that the app doesn't store.** Confirm each is wanted, so we can add it or drop it:
    - User name: already agreed, will be added.
    - Token name: see A5.
    - "Key saved · added 2 Oct": no date is stored for the key. Add one, or show "Key saved" only?
    - Previous English text and per-field change time: see A4.
    - Translation percentages and counts: see B17.
    - SEO share image: see B22.
    - "Sample" marker on starter content: see C38.
    - Derivable, no question: token last used (`api_tokens.last_used_at`), last sign-in (sessions / `session.created` events), posts per tag, members and tokens per group, missing-alt and unused counts, relative times, trash counts.

40. **Public preview banner** (optional). `/preview` pages show a signed-in banner with Edit and exit links, rendered in the public layout. Not in the handoff; tell us if it should follow the Studio tokens. Evidence: `app/views/layouts/public/_preview_banner.html.erb`.

## Dropped candidates

- **Settings placement (cand. 11, first half):** every setting is placed. Title, tagline, logo, social links, time zone under Site; trash retention under Publishing; default language as the Languages radio; provider, model, key, Test connection under AI translation. Adding a language is drawn ("Choose a language… ▾ Add"; searchable list in the setup wizard).
- **Fallback as one select vs. today's checkboxes:** storage already fits (one-element array); decided in the code map.
- **Multi-file upload errors (cand. 13):** drawn in DS 08 (failed tile "TOO LARGE … Remove"); only the size figure is wrong (A8). **GIF / missing variants:** no UI for it today either.
- **"Last sign-in" (cand. 14):** derivable from `sessions.created_at` / `session.created` audit events.
- **Mind graph tag nodes and Both/Related/Tags filter (cand. 15):** new, but fully drawn with legend and empty state; tags carry no read scope, so nothing to decide.
- **API token created view, language "Turn off" dialog, flash Undo, bulk-suggest progress, setup steps after admin (cand. 17):** all drawn in v2 (`Studio AI Assistant` `created`, `Studio Modals`, DS 08, `Setup Wizard`). Copy issues are in A8; "Use all" is in B26.
- **Default-language dialog claim "every translation is marked outdated":** matches the app (spec amendment line 308).
- **Change password "other sessions are signed out", reset link 15 minutes, "Built-in groups can't be deleted":** all true today.
- **Posts list drops the Tags and Published columns, adds path:** a design choice, no conflict.
- **Content-type `colour_index`:** types are registered in code in a fixed order; we assign the index there.
