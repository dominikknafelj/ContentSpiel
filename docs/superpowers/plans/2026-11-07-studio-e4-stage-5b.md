# CS Studio in E4, Stage 5b (the posts list and Tags) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The posts list, its New post dialog and the Tags screen take E4. On the posts list the toolbar keeps search and the segments, and the Type, Tag and Translation filters stand in a rail beside the list once the list has 1200px, above the list below that, still one filter form. The New post dialog is a field and a button. On Tags a row is a name, a count with a usage bar in the structure hue and a Details link; a detail rail shows the chosen tag, its posts, and Merge into… and Delete tag…, which leave the ⋯ menu and open the two dialogs that exist. Tags has no primary button.

**Architecture:** Both rails are one new shared layout, `.admin-list-rail`. It is a container of the list's own width that docks at the editors' and the dashboard's 1200px, on their three width tokens and the rail's ground, elevation and radius, with no tabs and no script. The posts filter form is one `<form>` drawn `display: contents`, so its bar and its rail panel are two grid items of one form. The tag detail is a Turbo frame, `tag-detail`, loaded from `GET /tags/:id`. It is redrawn by Turbo Streams (a rename, a delete), never reloaded. The posts list's reads leave the controller for `Posts::List` (`app/queries/posts/list.rb`). The Tags rail asks it for a tag's posts, so the rail's posts, its count and its "Show all" link agree with the list they open by construction. A record's state in a list (no chip for Live, Draft or Scheduled, the unpublished chip on a changed live record) is one component, `Admin::Ui::ListStateComponent`, which the posts table and the Tags rail both draw.

**Tech Stack:** Rails 8.1, ViewComponent with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Turbo frames and streams, Stimulus over import maps, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). Sections used: the front matter and "Decided on 2026-11-06" (12, 13), "The design, as decided" (tokens, the icon hue map, buttons, the four roles and status), the screen table's rows "Posts list, New post dialog" and "Tags", "The rule for a screen the artifact does not draw" (rules 2, 3 and 5), "Stage 5", item **5b** in full, "Architecture-review findings", "The guard after E4" and "Constraints". The drawing is `StudioCalmE4More` in the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). The artifact could not be read while this plan was written. Every look the spec does not settle is marked **(owner)**, with the default the build goes ahead on.

**Two pull requests, stacked.**
- **PR 5b-1, the posts list,** is Tasks 1–4 on branch `studio-e4-5b`, made from `main` at f5106435. It targets `main`.
- **PR 5b-2, Tags,** is Tasks 5–7 on `studio-e4-5b-tags`, branched from `studio-e4-5b` after Task 4. It targets `studio-e4-5b` until 5b-1 merges, then `main`.

Why two: the screens are independent for a person, and each is read against its own part of the drawing and its own guide page. 5b-1 carries the refactor (`Posts::List`, whose proof is that the posts list's integration tests pass unchanged) and the shared layout. 5b-2 carries a new endpoint, a frame, a controller and changed delete answers, which a reviewer reads as behaviour. Posts goes first because Tags uses both of its parts: the layout and the query. In the other order Tags would build them, and posts would convert them a second time.

**PR #196 (5a-2, the mind graph's look) is open.** Neither PR here touches a mind graph file. Both touch files #196 also changes: `content-spiel.css` and `content-spiel.tailwind.css` (new tokens and rules in other blocks), `test/lib/admin_contrast_test.rb`, `admin_design_rules_test.rb` and `admin_i18n_test.rb` (list entries and new tests), `CHANGELOG.md`'s `## Unreleased`, `CLAUDE.md`'s index, `docs/reference/design-system.md` and `test/unit_test_seconds.yml`. The conflicts are textual. Whichever PR lands second rebases and keeps both sides' entries. #196 adds `--cs-graph-tag: var(--cs-ic-structure)` for the graph's tags. Task 6 adds `--cs-tag-usage: var(--cs-ic-structure)` for the usage bar: one value, two roles, each token named for its role. #196's list draws a record's state from cloned server parts by the same rule `ListStateComponent` draws (Task 5). That component cannot be cloned by a script, and no task here changes the mind graph to use it.

## Global Constraints

- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/public/`, `app/views/layouts/public/` or `app/views/pages/` changes, and no `th-*` token.
- **CLAUDE.md binds every task:**
  - A record outside the viewer's scope is not found: every post a task lists comes through `AccessControl.scope(Current.actor, "posts.read", …)` (`admin_scope`).
  - A new list over posts hides trashed records itself and joins `test/integration/trash_visibility_test.rb` in the task that adds it.
  - Queries are Active Record, then Arel through `SqlNodes`. A fragment has a name on the model or is a method of `Posts::List`. A SQL string carries `# sql:`.
  - Dependency direction: `Posts::List` knows no component, helper or controller (`test/lib/dependency_direction_test.rb`).
  - Never define `Admin::<Domain>`. The Tags components are `Admin::TagsScreen::`, never `Admin::Tags::`.
- **No admin string is a literal.**
  - A component under `app/components/admin/<folder>/` reads `admin.components.<folder>.*` from `config/locales/admin/<folder>.en.yml`. That means `posts_screen.en.yml` and `tags_screen.en.yml`, which are new, and `editor_screen.en.yml` and `ui.en.yml`, which exist.
  - A view reads its lazy scope: `admin.posts.index.*` in `config/locales/admin/posts.en.yml` (new), and `admin.tags.index.*` in `tags.en.yml`.
  - A script's words come from `data-messages`.
  - A key is added in the task whose code reads it. A file converted to keys is converted whole, in one task, and joins `admin_i18n_test.rb`'s `CONVERTED` in that task. A new component or controller joins it in the task that creates it.
- **Buttons are the shared button.** A link drawn as a button takes `Admin::Ui::ButtonComponent.classes(variant, size:)`. One primary per area: on the posts list it is New post (and its split half), in a dialog its confirm. **Tags draws no primary outside its dialogs.**
- **The rails** (spec rule 5): they dock only by the list's own container at 1200px, never by a window `@media`. Below the threshold they fold back into the page. The rail comes first in the document at every width, so the focus order is the document's and nothing is moved by script.
- **Layers.** No rule of this stage sets a z-index. A native select and the two dialogs (`showModal()`, the top layer) need none. Anything that later raises a popover in a rail takes `--cs-z-popover` (`admin_design_rules_test`'s raw-value guard).
- **Turbo prefetch hazard.** Turbo answers any GET of an address it prefetched in the last 10 seconds with that prefetch, a frame's `reload()` and `Turbo.visit` included. The two rails are checked against it in the decisions table. The rules that come of it are written into the reference in the tasks that need them.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round ("design pass round 2, Task 17", "round 3", "final review C, M7"), "spec §" or what used to be there. The posts and tags files are full of these. Every task rewrites the comments of the files it changes, and its last step before its commit runs `grep -n "spec §\|Task [0-9]\|round [0-9]\|final review\|handoff §" <the files the task changed>`, which prints nothing. The plan's wording ("what `index` does today") is never copied into a comment.
- **Tests and the machine.**
  - On macOS every test command is prefixed with `PGGSSENCMODE=disable`.
  - Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file at a time, and only while the one-minute load (`sysctl -n vm.loadavg`, first figure) is under 6.
  - A browser test begins on `visit_screen` or `visit_editor`. A test this stage rewrites moves its bare `visit … await_admin_controllers` onto `visit_screen`.
  - No new browser file is created: the rail tests join `posts_list_test.rb` and `tags_test.rb`, so `test/system_test_seconds.yml` needs no entry. New unit test files are weighed by their count of tests (`bin/test-shard`) and get no entry in `test/unit_test_seconds.yml`. No task deletes a test file.
  - **No test run is left in the background** when a task ends: its last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #132", "Advances #117").
- A look that a person sees and that the spec does not settle is marked **(owner)**. Each has a default the build goes ahead on, and each PR lists its own under "For the owner to check".

## Review Focus

1. **A tag renamed while its detail is open.** The rail shows the name in its heading, in "Show all N posts"' address and in the two dialogs' triggers. A rename in the row must reach all three without a reload, or "Show all" opens a list filtered by a name that no longer exists. Task 6: "a rename of the chosen tag rewords the rail: its heading, Show all's address and both dialogs".
2. **Deleting the tag the rail shows, and the last tag.** The row goes. The rail goes back to its empty line, not to a detail of a tag that is gone. The focus goes to a neighbouring row. With no tag left, the list's empty state comes from the delete's own answer. Today a `Turbo.visit(location.href)` draws it, which the prefetch hazard can answer with the page from before the delete. Task 6: "deleting the chosen tag from the rail empties the rail and focuses a neighbour; deleting the last one shows the empty state from the answer, with no visit".
3. **A long tag name and long post titles at 360px.** A 50-character name with no space must wrap inside the rail, and post titles must cut with an ellipsis, never widen the rail over the list. Task 6: "a 50-character tag name and long post titles stay inside the rail" (DOM boxes only).
4. **The threshold is the list's own width.** Below 1280px the sidebar is a drawer, so a 1279px window gives the list more room than a 1280px one. A rule written as a window query would dock in the wrong window. Task 2 (posts) and Task 6 (tags): "the rail follows the list's own width: a 1279px window docks it, a 1280px one does not".
5. **A tag filter the select does not know.** `/posts?tag=gone` (a tag deleted or renamed elsewhere, a link from an old toast) filters the list to nothing. If the Tag select silently shows "Any", the person sees an empty list under no filter. Task 2: "a tag filter that names no tag shows that name as the chosen option, so the filter can be seen and cleared".

---

## Decisions the spec left open

| Question | Decision | Why |
|---|---|---|
| How the two rails reuse stage 3's and stage 4's | A third layout, `.admin-list-rail`, in `content-spiel.tailwind.css`. It is `container: admin-list / inline-size`, and docks under `@container admin-list (min-width: 1200px)` with the dashboard's grid: `minmax(0, var(--cs-editor-column)) var(--cs-rail-width)`, `column-gap: var(--cs-rail-gap)`, `justify-content: start`. The docked `.admin-list-rail__rail` is `--cs-rail` with `--cs-shadow-2` and `--cs-radius-rail`, placed `grid-column: 2; grid-row: 1 / span 2`, and everything else falls into column 1 in document order. The threshold test "the editors' rail and the dashboard's dock at one threshold" grows to hold `admin-list` to the same width. | `.admin-rail-grid` is an editor's rail. Its tabs, `admin--ui--rail`'s docked state, the folded variant and the canvas's stacking contexts serve several panels beside a canvas, and a list has one panel and no canvas. The dashboard's rules reach into `.admin-dashboard-panel`. A list rail is the dashboard's grid with one panel, so it takes the grid and the ground, and it is named for lists. The media library's panel (7a) is its next user. |
| "the same filter form" | One `<form id="posts-filters">` with `admin--ui--auto-submit`, drawn `display: contents`. It holds the bar (`div.admin-filter-bar`: search, segments, Clear) and the panel (`fieldset.admin-list-rail__rail.admin-filter-panel`: Type, Tag, Translation), and the list follows it as a sibling. `FilterHelper#filter_form_options` gains `bar: true`. With `bar: false` the form's class is `contents` and the caller draws the bar with `FilterHelper::BAR_CLASS`. | A `form=` attribute would leave the panel's `change` events outside the form, where the controller listens. The editor rail already places items through a `display: contents` form (the post form). The focus is remembered by id inside the form, so it survives a reload in the panel as in the bar. |
| The filter panel's look | Docked: on the rail's ground, under a legend "Filters" (`text-label`), each select full width under a visible label (`text-label text-meta`), one under the other. Below the threshold: a second row under the bar, the three labelled selects side by side, the legend `sr-only`. The blank option reads "All" (Type) or "Any" (Tag, Translation), since the label now names the filter. Every select is 38px (`--cs-control-compact`) in both places **(owner: visible labels; selects, not lists)**. | "The same filter form": the controls stay what they are. A label above the select replaces "Type: All", which read the filter's name inside its value. |
| The toolbar and "the field rules" | Search is a field well (fill and a bottom edge), as `.admin-filter-bar` already draws it. The segmented control keeps its full field-line outline and the inverted selected segment (design answer D1), shared with Media, Translations and the audit log. The split button's main half takes `ButtonComponent.classes(:primary)` in place of `setup_primary_button_class`, and its ▾ half stays the one hand-drawn accent fill named in `ACCENT_FILL_ALLOWED`. | The bar already meets the field rule. A segment look of its own on one screen would split the shared filter bar. The split half is a menu trigger that `ButtonComponent` cannot draw. |
| "the New post dialog is a field and a button" | Read as: Title is the field (first, autofocused, a well, as the New page dialog's), and Create draft is the dialog's one button, primary, with Cancel tertiary. The type's radio tiles become a `Type` select (`.cs-select`, each option with `data-path`), as New page's Inside is. With one creatable type there is no select: a hidden `post[content_type]` carries it, and the note names it ("Created as a blog post draft in English."). **(owner: the select; the type's dot leaves the dialog)** | The tiles were bordered boxes of one weight, which E4 removes. They are the one hand-built control left in `HAND_BUTTON_ALLOWED`. A select makes New post and New page one shape. |
| The New post dialog's words and its script | `NewPostDialogComponent`, `NewPostFormComponent`, `NewPageDialogComponent`, `NewPageFormComponent` and `admin--editor--new-record` are converted to keys in one task. The script's three sentences come from `data-messages` on each dialog's controller element (`components.editor_screen.new_record.{url,not_listed,page_note}`). | The script writes the URL line and the note that the server draws first. If the server's words were keys and the script's were not, a German dialog would change language on the first keystroke. The script is shared by both dialogs, so it is converted once, with both. |
| The posts table | Unchanged but for its Status cell, which draws `ListStateComponent` (Task 5). It and the bulk bar stay unconverted, outside `CONVERTED`. | "The shared chips already carry most of it" (spec 5b). Converting a table nothing else changes is the German UI project's. |
| Tags: how a tag is chosen | Each row ends with a link, "Details" (`ButtonComponent.classes(:tertiary, size: :small)`; `aria-label` "Details of “music”", which keeps the visible word). It targets the frame `tag-detail` (`data-turbo-frame`) with `data-turbo-prefetch="false"`, `href` `admin_tag_path(tag)`. The chosen row has `data-selected` (the posts table's tint, `bg-accent-tint`), and its link `aria-current="true"`. Both are written by `admin--tags--detail`. The row's ⋯ menu goes: Merge and Delete were all it held. **(owner: the word "Details" and its place at the row's end)** | The name is an input, so it cannot be the target that chooses. A frame reloads one panel, not the fifty autosaving forms of a `content` frame visit, which could race a row's save. |
| Tags: the choice and the address | The choice is not in the address. A reload or Back shows the list with nothing chosen. The screen carries `turbo-cache-control: no-cache`, so Back never restores a detail, or a row's `base_updated_at`, from a snapshot. **(owner)** | `?selected=` (Media's way) navigates the whole `content` frame. A frame's `src` is not the page's address, as with the dashboard's Waiting for you. |
| Tags: the prefetch hazard | (1) The detail is never reloaded: a rename's answer replaces `#tag-detail-<id>` by stream, and a delete's answer replaces it with the empty line. (2) Details links carry `data-turbo-prefetch="false"`. The pointer rests on the link it pressed, so Turbo would prefetch it again at once, and a second press after a rename would get the old name. (3) The last delete no longer runs `Turbo.visit(location.href)`, whose address is the sidebar's Tags link's. The answer's stream draws the empty state (`replace "tags-list"`). | Each is a GET whose address equals a visible link's. |
| Posts: the prefetch hazard | Nothing on the posts list reloads the `content` frame. `admin--presence--list` reads `presence_here_path`, another address. A filter form's GET always carries its fields (`?q=&scope=all&type=…`), so it never equals Clear's or the sidebar's bare `/posts`, nor a pager link, which carries `page`. No change. | Checked, as asked. The reference says so, so a later live reload of the list knows the rule. |
| Tags: the rail's content | The heading (`h2`, `tabindex="-1"`, the name, `break-words`). Under it the count line (`tag_posts_label`). Then the posts: at most `DETAIL_POSTS = 8`, newest-changed first, from `Posts::List` with `tag:` the tag's name. Each is a link to the editor with its title cut by an ellipsis and its `ListStateComponent`. Then "Show all 12 posts" (`/posts?tag=<name>`, `_top`) when there are more. Then "Merge into…" (secondary) and "Delete tag…" (tertiary: quiet, since the red is the dialog's confirm). Close is `ButtonComponent` (`icon: :x`, `:tertiary`, `size: :small`). A viewer without `posts.read` gets no count and no posts, and the dialogs' neutral sentences. With nothing chosen, docked, the rail says "Choose a tag to see its posts, merge it or delete it." Below the threshold an unchosen rail takes no room. **(owner: 8 posts; Merge secondary and Delete tertiary; the empty line)** | The spec's "its posts (the posts query by tag)". The count and "Show all" are `Posts::List`'s `counts["all"]` for the same filter, so they are the list's own All count. |
| Tags: the rail below the threshold | The same panel, first in the document, above the table, as a card (`bg-surface shadow-1 rounded-card`). | Spec rule 5: below the threshold the rail folds back into the page. First in the document, as the posts filters are, so a choice made on a phone is seen, and focus order is document order. |
| The usage bar | A 4px bar under the count, `bg-tag-usage` (`--cs-tag-usage: var(--cs-ic-structure)`) on a track of `--cs-paper`. Its width is the row's readable count over the largest readable count on the screen (`style="--usage: 0.42"`, `width: calc(var(--usage) * 100%)`). It is `aria-hidden`, since the count's words say it. There is no bar without `posts.read`, and the track stays empty at 0. Measured: 7.46 / 8.91:1 on the row's surface, 6.78 / 9.91:1 on the track **(owner: the light figure is above the spec's 6.2; the track)**. | The spec's 6.2 / 8.9:1 are floors. The structure hue meets them on both its neighbours, as 5a found for a tag's square. A `--cs-sunken` track (6.14:1) would miss 6.2. |
| The tag row | The name at rest is text (today's rule); on hover it is the well, on focus the well with the 2px accent outline. It is `font-medium` at rest. The row's lines are `border-line` between rows. Columns: Name, Posts (count and bar), save status, Details **(owner)**. | The row and its input "restyled", from E4's field rule: a well is identified by its fill and edge whenever it is pressable, and the resting text look is the screen's decided rename-in-place. |
| A record's state in a list | `Admin::Ui::ListStateComponent.new(record:)` draws `StatusChipComponent.new(status:, at: published_at, hide_live: true)`, then `UnpublishedChipComponent` when `record.unpublished_changes?`. The posts table's Status cell and the Tags rail draw it. | The rule is the posts list's, and the mind graph's list follows it in #196. A third copy in the rail would be a rule held by hand. |
| `GET /tags/:id` and `/tags/suggest` | `resources :tags, only: %i[index show update destroy]`, with `constraints: { id: /\d+/ }` on `show`. `get "tags/suggest"` stays declared before it, and its comment, which says the two cannot collide "since there is no show", is rewritten. A request for it that is not the `tag-detail` frame's is a 303 to `admin_tags_path`. | The detail is a part of the Tags screen, not a page. |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/queries/posts/list.rb` (new), `app/controllers/admin/posts_controller.rb`, `test/queries/posts/list_test.rb` (new) | the posts list's reads | 1 |
| `content-spiel.tailwind.css` (`.admin-list-rail`, `.admin-filter-panel`), `app/helpers/admin/filter_helper.rb`, `app/components/admin/posts_screen/toolbar_component.*`, `app/views/admin/posts/index.html.erb`, `config/locales/admin/posts.en.yml` (new), `posts_screen.en.yml` (new) | the list rail, the filter panel, the posts screen in keys | 2 |
| `app/components/admin/editor_screen/new_{post,page}_{dialog,form}_component.*`, `app/javascript/controllers/admin/editor/new_record_controller.js`, `editor_screen.en.yml` | the New post dialog, both dialogs in keys | 3 |
| `docs/reference/editors-and-translation-pair.md`, `design-system.md`, `CLAUDE.md`, `CHANGELOG.md` | 5b-1's reference | 4 |
| `app/components/admin/ui/list_state_component.*` (new), `posts_screen/table_component.html.erb`, `ui.en.yml` | the shared list state | 5 |
| `app/components/admin/tags_screen/{detail,empty_detail}_component.*` (new), `app/views/admin/tags/{index,show}.html.erb`, `app/controllers/admin/tags_controller.rb`, `app/helpers/admin/tags_helper.rb`, `app/javascript/controllers/admin/tags/{detail,dialogs}_controller.js`, `config/routes.rb`, `content-spiel.css` (`--cs-tag-usage`), `content-spiel.tailwind.css`, `tags.en.yml`, `tags_screen.en.yml` (new) | Tags in E4 and its detail rail | 6 |
| `docs/reference/design-system.md`, `i18n.md`, `CLAUDE.md`, `CHANGELOG.md` | 5b-2's reference | 7 |

---

# PR 5b-1: the posts list

### Task 1: `Posts::List`, the posts list's reads out of the controller (#132)

Nothing a person sees changes. The proof is that `test/integration/admin/posts_list_test.rb` and `posts_test.rb` pass unchanged.

**Files:**
- Create `app/queries/posts/list.rb`.
- Modify `app/controllers/admin/posts_controller.rb`. `SCOPES`, `list_scope`, `base_posts`, `filtered_posts`, `page_of_posts`, `filter_by_scope`, `scope_counts`, `filter_by_translation` and `filter_by_title` move into the query, with their comments rewritten by the comment rule. `index` and `posts_list_path` ask the query. `listed_paths` stays, since it is the page's display and not the list. The class comment's filters paragraph moves to the query, and the controller keeps one line pointing to it.
- Create `test/queries/posts/list_test.rb`.
- Modify `docs/reference/editors-and-translation-pair.md`, "The posts list": its first sentence names `Posts::List` as what reads the rows and counts. This task owns that sentence. Task 4 rewrites the rest of the paragraph.

**Interfaces:**
- Produces `Posts::List`:
  - `Posts::List::SCOPES = %w[all live drafts scheduled]`.
  - `Posts::List.new(posts, filters:, locale:)`. `posts` is the viewer's readable posts, a relation the caller has narrowed (`admin_scope(Post.all)`, which also hides the trashed). `filters` is a Hash with String keys, read from `"scope"`, `"status"` (the old name of `scope`), `"type"`, `"tag"` (a tag's stored name), `"translation"` and `"q"`. A value that is not a String is ignored, as today. `locale` is the editing language, for `q`.
  - `#scope_name -> String`, one of `SCOPES` (`"draft"` reads as `"drafts"`, anything else as `"all"`).
  - `#counts -> { "all" => Integer, "live" =>, "drafts" =>, "scheduled" => }`: one statement, the scope ignored and every other filter applied.
  - `#rows(limit:, offset: 0) -> Array<Post>`, under the scope, ordered `updated_at desc, id desc`.
- `Admin::PostsController` keeps `PER_PAGE` and `LIST_KEYS`. Every `SCOPES` it used reads `Posts::List::SCOPES`.

- [ ] **Step 1: Write the failing query tests** in `test/queries/posts/list_test.rb`, over `AccessControl.scope(users(:one), "posts.read", Post.all)`:
  - `test "the tag filter is the tag's stored name, and a post with another tag or none is left out"`
  - `test "rows are the scope's, newest-changed first, and limit and offset page them"`
  - `test "counts ignore the scope and respect every other filter, in one statement"`. Assert the four numbers, and that `assert_queries_count(1) { list.counts }` holds.
  - `test "a filter that is not a string is no filter, and an unknown scope is all"`. Pass `{ "tag" => ["a"], "scope" => "nope" }`.
  - `test "a trashed post is in no row and no count"`
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/queries/posts/list_test.rb`. Expected: `NameError: uninitialized constant Posts::List`.
- [ ] **Step 3: Move the code.** The bodies move as they are. `params[:x]` becomes `filters["x"]`, `admin_locale` becomes `locale`, and `admin_scope(Post.all)` becomes `posts`. The `tags` subquery and its comment (why not `joins(:tags)`) move whole.
- [ ] **Step 4: Run.** First the query test. Then `PGGSSENCMODE=disable bin/rails test test/integration/admin/posts_list_test.rb test/integration/admin/posts_test.rb test/integration/trash_visibility_test.rb test/lib/dependency_direction_test.rb test/lib/sql_strings_test.rb test/lib/admin_namespace_shadow_test.rb`, then `bin/rails zeitwerk:check`. Expected: PASS, with no change to any integration test.
- [ ] **Step 5: Comments and commit.** Run the comment grep over `posts_controller.rb` and `list.rb`; it prints nothing. Check that `pgrep -f "rails test"` prints nothing. Commit `ref: the posts list's reads are Posts::List` (body: `Advances #132`, `Advances #117`).

---

### Task 2: The list rail, and the posts list on it

**Files:**
- Modify `app/assets/tailwind/content-spiel.tailwind.css`, after the dashboard's block. Add `.admin-list-rail` (the container), `.admin-list-rail__head`, `.admin-list-rail__grid` (one column), the docked block `@container admin-list (min-width: 1200px)` (the grid, the rail's ground and place, the head's `max-width: calc(var(--cs-editor-column) + var(--cs-rail-gap) + var(--cs-rail-width))`) and `.admin-filter-panel`:
  - Below the threshold, `.admin-filter-panel` is a wrapping row with `gap: 0.75rem`, its legend `sr-only`, and `margin-bottom: 1rem`.
  - Docked, it is a column with its legend shown.
  - `.admin-filter-panel` joins `.admin-filter-bar` in the compact-height rule (`select`) and the field-well rule (`:is(.admin-column, …, .admin-filter-bar, …)`).

  `.admin-list-rail__rail` is matched anywhere inside the grid, never as `> .admin-list-rail__rail`, because the posts panel stands inside the `display: contents` form. The block's comment states the container, the threshold kept with the editors' and the dashboard's, the document order and why `display: contents`.
- Modify `app/helpers/admin/filter_helper.rb`. It gains `BAR_CLASS = "admin-filter-bar mb-4 flex flex-wrap items-start gap-3"`, read by `filter_form_options`, and `bar: true`. With `bar: false` the form's class is `contents`. The design-rules test that reads that string from the helper's source still finds it.
- Modify `app/components/admin/posts_screen/toolbar_component.{rb,html.erb}`. It draws the whole filter form: `form#posts-filters` (`bar: false`), which holds `div` with `FilterHelper::BAR_CLASS` (search, segments, Clear) and `fieldset.admin-list-rail__rail.admin-filter-panel` (legend, three labelled selects).
  - `SCOPES` becomes `Posts::List::SCOPES`, labelled by `t(".scopes.<name>")`.
  - `TRANSLATIONS` becomes `%w[needs outdated complete]`, labelled by `t(".translations.<value>")`.
  - `tag_options -> Array<String>` is the tags' names, plus `filters[:tag]` when it is present and not among them (Review Focus 5).
  - Every word is a key. The class comment is rewritten (no "design pass round 2, Task 17, handoff §4.3").
- Modify `app/views/admin/posts/index.html.erb`, converted to keys whole:
  - The page is `div.admin-list-rail` holding `div.admin-list-rail__head` (heading and New post) and `div.admin-list-rail__grid` (the toolbar's form, then the bulk-select wrapper with the list).
  - The split button's main half takes `Admin::Ui::ButtonComponent.classes(:primary)`. The ▾ half's `button_class` is unchanged. The empty state's "+ New post" and "Clear filters" take `.classes(:primary)` and `.classes(:secondary)`.
  - `new_label` reads `t(".new_type_post", type:)` for a one-word type name and `t(".new_type", type:)` otherwise.
  - "No matches." names the filters through `filter_summary` with keyed labels (`t(".filter_names.<name>")`).
  - The header comments are rewritten.
- Create `config/locales/admin/posts.en.yml` (`admin.posts.index.*`) and `config/locales/admin/posts_screen.en.yml` (`admin.components.posts_screen.toolbar.*`). Both carry today's English words; only the selects' blanks change to "All" and "Any".
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `app/views/admin/posts/index.html.erb`, `app/components/admin/posts_screen/toolbar_component.rb` and `.html.erb`.
- Modify `test/components/previews/admin/posts_screen/toolbar_component_preview.rb`: the preview renders the form inside a `.admin-list-rail__grid`, so both the bar and the panel are seen.
- Test: `test/lib/admin_design_rules_test.rb`, `test/components/admin/posts_screen/toolbar_component_test.rb`, `test/integration/admin/posts_list_test.rb`, `test/system/admin/filter_bar_test.rb`, `test/system/admin/posts_list_test.rb`, `test/lib/admin_i18n_test.rb`, `test/lib/source_layout_test.rb`.

**Interfaces:**
- Produces the CSS classes `.admin-list-rail`, `.admin-list-rail__head`, `.admin-list-rail__grid` and `.admin-list-rail__rail`, used again in Task 6, and `.admin-filter-panel`. Produces `FilterHelper::BAR_CLASS` and `filter_form_options(url, frame: "content", bar: true)`.
- `Admin::PostsScreen::ToolbarComponent.new(scope:, counts:, content_types:, tags:, filters:, url_options: {}, locale:)` keeps its signature. Its form's id is `FORM_ID = "posts-filters"`, its panel's legend `t(".filters")` ("Filters").

- [ ] **Step 1: Write the failing tests.**
  - `admin_design_rules_test.rb`:
    - `test "the lists' rail is laid out by the list's own container, from the rail's tokens"`. The same shape as the dashboard's test: `.admin-list-rail { container: admin-list / inline-size; }`; one column below the threshold; one docked block whose grid is the three tokens with `justify-content: start`; `.admin-list-rail__rail` on `--cs-rail`, `--cs-shadow-2` and `--cs-radius-rail` at `grid-column: 2`; no `@media` block names `admin-list-rail`.
    - "the editors' rail and the dashboard's dock at one threshold" becomes `test "the editors' rail, the dashboard's and the lists' dock at one threshold"`. `css.scan(/@container admin-list \(min-width: ([^)]+)\)/)` is exactly `[editor.first]`.
  - `toolbar_component_test.rb`:
    - "search and the three drop-downs are labelled for a screen reader…" becomes `test "search is labelled for a screen reader, and Type, Tag and Translation stand under visible labels in the filter panel, keeping their values"`. Assert `fieldset.admin-filter-panel legend` with "Filters"; `label[for=type]` without `sr-only` and its words; the blanks "All", "Any", "Any"; and the chosen values.
    - `test "one form holds the bar and the panel, drawn as contents, and applies as it changes"`. Assert `form#posts-filters.contents[data-controller='admin--ui--auto-submit']` containing `.admin-filter-bar input#q`, the segments and `.admin-filter-panel select#translation`.
    - `test "a tag filter that names no tag shows that name as the chosen option, so the filter can be seen and cleared"` (Review Focus 5). With `filters: { tag: "gone" }` and tags `[music]`, `select#tag option[selected]` is "gone" and Clear is drawn.
    - The other tests keep their assertions, with their selectors moved inside the form.
  - `posts_list_test.rb` (integration): `test "the posts screen stands in the list rail: the heading row, then one filter form, then the list"`. Assert the order of `.admin-list-rail__head`, `form#posts-filters` and `[data-controller='admin--posts--bulk-select']` inside `.admin-list-rail__grid`, with the panel inside the form. "the split button's divider is the on-accent colour at 40 percent" stays as it is.
  - `filter_bar_test.rb`: `BAR` stays `form.admin-filter-bar` for the other screens. `heights` and `assert_one_height` take `root:` (default `BAR`). For a root that is not a bar, the "is a bar" assertion reads `"#{root} .admin-filter-bar"`. "the posts list's bar: search, segments, three selects and Clear are one height" becomes `test "the posts list's bar and its filter panel: search, segments, Clear and the three selects are one height"`, measured over `form#posts-filters`.
  - `posts_list_test.rb` (system), each starting on `visit_screen`:
    - `test "at 1600px the Type, Tag and Translation filters stand in a rail right of the list, on the rail's ground"`. In DOM boxes: the panel's left is the list's right plus 28 (±1), its width 360 (±1), its computed background `--cs-rail`'s, and the heading row's right is the rail's right.
    - `test "at 1100px the filters stand above the list, under the search and the segments"`. The panel's top is at least the bar's bottom, and its bottom at most the table's top.
    - `test "the rail follows the list's own width: a 1279px window docks it, a 1280px one does not"` (Review Focus 4). Assert the list rail's width first (at least 1200, under 1200), as `dashboard_test` does.
    - `test "the focus goes New post, search, the segments, the rail's Type, Tag and Translation, then the list, and a Type chosen from the keyboard keeps the focus on Type"`, at 1600, with the dashboard test's Tab loop over areas. Then `select` a type by keyboard (`send_keys(:down)` on the focused select). After the list is redrawn, `document.activeElement.id == "type"` and the rows are that type's.
    - The existing tests move to `visit_screen`. "the Translation filter narrows the list without a button" selects by its visible label, `select "Outdated", from: "Translation"`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/components/admin/posts_screen/toolbar_component_test.rb test/integration/admin/posts_list_test.rb`. Expected: FAIL on the missing container block, the missing form id and the labels.
- [ ] **Step 3: Implement.** Search the tests by hand for "Type: All", "Tag: Any", "Translation: Any", `posts-scope-` and `form.admin-filter-bar` near a posts path, and fix each hit in this task.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin/posts_screen test/integration/admin/posts_list_test.rb test/integration/admin/posts_test.rb`.
  - Then `bin/rails tailwindcss:build`, and one at a time: `filter_bar_test.rb`, `posts_list_test.rb`, `drafts_test.rb`, `presence_lists_test.rb` (the posts rows' markers), `unpublished_changes_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep over the changed files. Check `pgrep`. Commit `feat: the posts list's filters stand in a rail beside the list, one form with the search` (body: `Advances #117`).

---

### Task 3: The New post dialog is a field and a button; both new-record dialogs in keys

**Files:**
- Modify `app/components/admin/editor_screen/new_post_form_component.{rb,html.erb}`:
  - Title first: the well, `autofocus`, as New page's.
  - Then `select#new-post-type` (`name="post[content_type]"`, `setup_select_class`, `data-admin--editor--new-record-target="type"`, each `option` with `data-path` when the type is listed), under a visible label `t(".type")`.
  - With one creatable type, `hidden_field_tag "post[content_type]", name, id: TYPE_ID` carries the `type` target and `data-path`, and no label is drawn.
  - The URL line, then the note `t(".note", type: <label downcased>, language: Locales.name(locale))`.
  - `initial_url` reads `t(".url", path:)` or `t(".not_listed")`. The class comment loses "design pass round 2, handoff `Studio Modals.dc.html`" and "final review A, M4".
- Modify `new_post_dialog_component.{rb,html.erb}`: the title, "Loading…", the two failure messages, "Try again", "Cancel" and "Create draft" become keys. The controller's element gains `data-messages="<%= messages_data(*NEW_RECORD_MESSAGES) %>"`.
- Modify `new_page_dialog_component.{rb,html.erb}` the same way, and `new_page_form_component.{rb,html.erb}`: Title, Inside, `GONE`, `initial_url` and `initial_note` become keys. Its look is unchanged.
- Modify `app/javascript/controllers/admin/editor/new_record_controller.js`. A post's path is read from `this.typeTarget`: the `selectedOptions[0]` of a select, or the hidden input itself. Its three sentences come from `messages(this.element).t("components.editor_screen.new_record.url", { path })`, `.not_listed` and `.page_note` (`{ title }`).
- Modify `config/locales/admin/editor_screen.en.yml`: `new_post_dialog.*`, `new_post_form.*`, `new_page_dialog.*`, `new_page_form.*` (beside `template`) and `new_record.{url,not_listed,page_note}`, with today's words.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains the eight component files and `new_record_controller.js`.
- Modify `test/lib/admin_design_rules_test.rb`: `HAND_BUTTON_ALLOWED` loses `"has-checked:border-accent has-checked:bg-accent-tint"`. Without this, "every hand-button allowance is still used" goes red.
- Modify `test/components/previews/admin/editor_screen/new_post_dialog_component_preview.rb`: a scenario with one creatable type.
- Test: `test/components/admin/editor_screen/new_post_dialog_component_test.rb`, `test/integration/admin/new_record_dialogs_test.rb`, `test/integration/admin/access_control_test.rb`, `test/lib/script_messages_test.rb`, `test/lib/admin_i18n_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/system/admin/new_record_test.rb`, `test/system/admin/dashboard_test.rb`.

**Interfaces:**
- `NewPostFormComponent::TYPE_ID = "new-post-type"` is now the select's id, or the hidden input's. `field_ids["content_type"]` still points at it, so the error summary links to the select.
- `NEW_RECORD_MESSAGES = %w[components.editor_screen.new_record.url components.editor_screen.new_record.not_listed components.editor_screen.new_record.page_note]` is a constant of `NewPostDialogComponent`, which `NewPageDialogComponent` reads.

- [ ] **Step 1: Write the failing tests.**
  - `new_post_dialog_component_test.rb`:
    - "a radio card per type with its dot…" becomes `test "the form: Title first, then a labelled Type select with each type's listing path, the URL line and the draft note"`.
    - "a chosen card is bold as well as tinted" becomes `test "with one creatable type there is no select: a hidden input carries the type and the note names it"`.
    - "the first type is preselected unless one is asked for" reads `option[selected]`.
    - `test "the dialog's words are keys: its title, Loading…, its failures, Try again, Cancel and Create draft"`. Store a test string for `admin.components.editor_screen.new_post_dialog.create` with `I18n.backend.store_translations(:en, …)`, restored by `I18n.reload!` in `teardown`, and assert the button reads it, so a literal left in the template fails.
    - `test "the dialog hands the script its three sentences"`. Parse `data-messages`, and assert it holds the three keys with today's words.
  - `access_control_test.rb` line 506: `test "new posts offer only the content types the author may create"` asserts `input[type=hidden][name='post[content_type]'][value='blog']` and no `select#new-post-type`.
  - `new_record_dialogs_test.rb`: the `post[content_type]` create tests are unchanged. A test that reads a radio reads the select.
  - `new_record_test.rb`: "New post: pick a type…" becomes `test "New post: type a title, choose a type, Create opens that post's editor"`. It uses `select ContentTypes.find("now_update").label, from: "Type"`, and asserts that the URL line follows the type (`data-path`) after the change.
  - `dashboard_test.rb` line 13: `select ContentTypes.find("blog").label, from: "Type"`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/new_post_dialog_component_test.rb test/integration/admin/access_control_test.rb test/lib/admin_design_rules_test.rb`.
- [ ] **Step 3: Implement.** Search the tests and `app/` by hand for `post[content_type]` radios, `has-checked:bg-accent-tint` and the dialogs' English words, and fix each hit in this task. `grep -rn "text-\[13px\]" app/components/admin/editor_screen/new_*` prints nothing: the note is `text-small`.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin/editor_screen test/integration/admin/new_record_dialogs_test.rb test/integration/admin/access_control_test.rb`.
  - Then, one at a time after a build: `new_record_test.rb`, `dashboard_test.rb`, `dialogs_hang_test.rb`, `command_palette_test.rb`, `press_helper_test.rb`.
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the New post dialog is a field and a button, and the new-record dialogs speak in keys` (body: `Advances #117`).

---

### Task 4: 5b-1's reference, CLAUDE.md and the pull request

**Files:**
- Modify `docs/reference/editors-and-translation-pair.md`, "The posts list", after Task 1's first sentence: the toolbar's bar and the filter panel in one form, the rail at 1200px of the list's own width, the New post dialog's Title and Type select, and the prefetch check (nothing reloads the list's frame, and a filter's address never equals a link's).
- Modify `docs/reference/design-system.md`. Add a part "E4: the lists' rail": `.admin-list-rail`, its tokens and threshold, why it is neither the editors' grid nor the dashboard's, `display: contents` for one form, the filter panel's two looks, and the rule that a rail is first in the document. Rewrite "Control heights" for the panel. Add a line under "Rules a change can break silently": a new list rail is laid out by `.admin-list-rail` and docks at the one threshold (the test names it).
- Modify `CLAUDE.md`. The editors' index line gains `app/queries/posts/` (the posts list's reads). The design-system line's list gains `.admin-list-rail`. `Admin::PostsController`'s filter sentence, wherever CLAUDE.md quotes it, names `Posts::List`.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - On the posts list, the Type, Tag and Translation filters stand in a rail beside the list in a wide window and in a row above it otherwise, each under its own label.
  - The New post dialog asks for a title and offers the types in a Type list.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Base: `main`.
  - Findings: Advances #132 (`posts_controller.rb`'s list), Advances #117.
  - "For the owner to check":
    - the filter panel's visible labels and its selects;
    - the New post dialog's Type select, which takes away the type's dot;
    - "All" and "Any" as the blanks.
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`:
    - `docs/editors/posts/work-with-many-posts.md` (the filters in the rail);
    - `docs/editors/posts/posts-and-content-types.md` (the New post dialog);
    - screenshots `posts-list-selected` and `new-post-dialog` (`screenshots/recipes.rb`), retaken in both themes, the list also at 1600px.
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 5b-1 in the reference and CLAUDE.md` (body: `Advances #117`).

---

# PR 5b-2: Tags

### Task 5: A record's state in a list is one component

**Files:**
- Create `app/components/admin/ui/list_state_component.{rb,html.erb}`. It has no words of its own, and its chips have theirs.
- Modify `app/components/admin/posts_screen/table_component.html.erb`: its Status cell renders `Admin::Ui::ListStateComponent.new(record: post)` inside its `span`. Nothing else in the table changes.
- Create `test/components/admin/ui/list_state_component_test.rb` and a preview `test/components/previews/admin/ui/list_state_component_preview.rb`, one scenario per state.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `app/components/admin/ui/list_state_component.rb` and `.html.erb`.
- Test: `test/components/admin/posts_screen/table_component_test.rb` (its two state tests, unchanged, now prove the swap), `test/lib/admin_design_rules_test.rb` (`LIVE_SCHEDULED_FILES`: the component draws through the chip, so no list change).

**Interfaces:**
- `Admin::Ui::ListStateComponent.new(record:)`, where `record` answers `status`, `published_at` and `unpublished_changes?`. It renders nothing for a live record without changes (`render?`).

- [ ] **Step 1: Write the failing tests.**
  - `test "a draft and a scheduled record show their chip, a live one none"`
  - `test "a live record with unpublished changes shows the unpublished chip and no Live chip; a draft with a stale mark shows Draft alone"`
  - `test "it draws the shared chips' own markup"`. The inner HTML equals `render_inline` of `StatusChipComponent` (`hide_live: true`) and of `UnpublishedChipComponent` for the same record.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/list_state_component_test.rb test/components/admin/posts_screen test/lib`. Expected: PASS.
- [ ] **Step 5: Commit** `ref: a record's state in a list is Admin::Ui::ListStateComponent`.

---

### Task 6: Tags in E4, with its detail rail

**Files:**
- Modify `config/routes.rb`: `resources :tags, only: %i[index show update destroy], constraints: { id: /\d+/ }`, with `merge` as before. The comment over `tags/suggest` says it is declared first and that `show`'s id is digits.
- Create `app/components/admin/tags_screen/detail_component.{rb,html.erb}` and `empty_detail_component.{rb,html.erb}`, with `config/locales/admin/tags_screen.en.yml` (`admin.components.tags_screen.{detail,empty_detail}.*`) and previews under `test/components/previews/admin/tags_screen/`.
- Create `app/views/admin/tags/show.html.erb`: `turbo_frame_tag "tag-detail"` around the detail. It renders without a layout.
- Modify `app/controllers/admin/tags_controller.rb`:
  - `index` keeps `@readable_counts` and drops `@carrier_counts`, which only the rows' triggers read. It adds `@largest = @readable_counts.values.max.to_i`.
  - `show` answers the `tag-detail` frame, and anything else with a 303 to the list. `Tag.find`, then `Posts::List.new(admin_scope(Post.all), filters: { "tag" => tag.name }, locale: admin_locale)`, then `rows(limit: DETAIL_POSTS)` and `counts["all"]`, and the carriers for that tag (`PostTag.where(tag_id:).count`), all only under `can?("posts.read")`.
  - `update` adds, on a saved rename, `turbo_stream.replace("tag-detail-#{tag.id}", DetailComponent)`.
  - `destroy` adds `turbo_stream.replace("tag-detail-#{tag.id}", EmptyDetailComponent)`. When no tag is left it also adds `turbo_stream.replace("tags-list", <the empty state>)`.
  - The comments lose "cs-studio spec §4.1/§5.3", "round 3 handoff §4.9" and "§7's".
- Modify `app/views/admin/tags/index.html.erb`, rewritten whole:
  - `content_for :head` with `turbo-cache-control: no-cache`, and its reason.
  - `div.admin-list-rail` holding the heading and intro (`.admin-list-rail__head`) and the grid, which holds:
    - first, `section.admin-list-rail__rail.admin-tag-detail` (`aria-label` `t(".rail_label")`, "Tag details"; a heading inside changes with each tag), with `turbo_frame_tag "tag-detail"` holding the `EmptyDetailComponent`;
    - then `div#tags-list`, with the card and its table, or the empty state.
  - Each row: the name's form as before (`font-medium`); the Posts cell with the count link and, under `posts.read`, `span.admin-tag-usage` (track) holding `span.admin-tag-usage__bar` with `style="--usage: <ratio>"`, `aria-hidden`; the save status; and the Details link (`data-tag-details`). The ⋯ menu goes.
  - The two dialogs and `admin--tags--dialogs`' element stay as they are, outside the grid. The grid carries `data-controller="admin--tags--detail"`, with the empty line's `<template>`.
- Modify `config/locales/admin/tags.en.yml`. `index.details` ("Details"), `index.details_label` ("Details of “%{name}”") and `index.rail_label` ("Tag details") are added. `actions_label`, `columns.actions`, `merge_item` and `delete_item` are deleted, since their reader, the row menu, goes in this task. `merge_item` and `delete_item` move as `tags_screen.detail.merge` and `.delete`. `columns.details` (`sr-only`) is added. The file's comment names the detail's scope.
- Modify `app/helpers/admin/tags_helper.rb`: the comment names the detail as the triggers' place. The methods are unchanged.
- Create `app/javascript/controllers/admin/tags/detail_controller.js` (`admin--tags--detail`).
- Modify `app/javascript/controllers/admin/tags/dialogs_controller.js`:
  - the last-tag `Turbo.visit(location.href, { action: "replace" })` and its comment go (the answer draws the empty state), and `Turbo`'s import goes with them if nothing else reads it;
  - the header says the triggers stand in the detail;
  - after a delete the neighbour is found as today.
- Modify `app/assets/tailwind/content-spiel.css`, both schemes: `--cs-tag-usage: var(--cs-ic-structure);`, with a comment saying it is the structure hue at the spec's figure. Modify `content-spiel.tailwind.css`:
  - `--color-tag-usage: var(--cs-tag-usage);` in `@theme`;
  - `.admin-tag-usage` (4px, `--cs-paper`, `--cs-radius` pill) and `.admin-tag-usage__bar` (`width: calc(var(--usage) * 100%)`);
  - `.admin-tag-detail` below the threshold: a card, and `:has([data-tag-detail-empty])` takes no room;
  - in `@container admin-list (min-width: 1200px)`: `.admin-tag-detail` on the rail's ground (through `.admin-list-rail__rail`), with the empty line shown;
  - the resting-text rule of `.admin-tags-table` keeps its comment, rewritten without "handoff §4.9".
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `app/components/admin/tags_screen/detail_component.{rb,html.erb}`, `empty_detail_component.{rb,html.erb}`, `app/views/admin/tags/show.html.erb` and `app/javascript/controllers/admin/tags/detail_controller.js`.
- Modify `test/system/dialog_test.rb`: `open_delete_tag_dialog` presses the row's Details, then the rail's "Delete tag…". Its comment loses "(round 3)".
- Modify `test/integration/trash_visibility_test.rb` (line 841's test): the dialogs' count is read from `GET /tags/:id`'s frame.
- Test: `test/components/admin/tags_screen/detail_component_test.rb` (new), `test/integration/admin/tags_test.rb`, `test/integration/trash_visibility_test.rb`, `test/integration/public_javascript_test.rb` (the Tags screen loads no editor script; unchanged), `test/lib/admin_contrast_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_i18n_test.rb`, `test/lib/source_layout_test.rb`, `test/lib/admin_namespace_shadow_test.rb`, `test/system/admin/tags_test.rb`, `test/system/dialog_test.rb`, `test/system/admin/messages_test.rb`.

**Interfaces:**
- `Admin::TagsScreen::DetailComponent.new(tag:, posts:, count:, carriers:, url_options: {}, locale:)`:
  - `posts` is an Array of `Post`, and `count` and `carriers` are Integers. Without `posts.read` the controller hands `posts: []`, `count: nil`, `carriers: nil`.
  - `FRAME_ID = "tag-detail"`, `DETAIL_POSTS = 8`.
  - Its root is `div#tag-detail-<id>[data-tag-detail-for=<id>]`. The heading is `h2#tag-detail-<id>-name[tabindex=-1][data-tag-detail-heading]`.
  - The triggers carry today's `data-tag-*` (from `TagsHelper`) and `dialog_trigger("merge-tag-dialog" | "delete-tag-dialog")`.
  - Close is `data-action="admin--tags--detail#close"`.
- `Admin::TagsScreen::EmptyDetailComponent.new`: `div#tag-detail-empty[data-tag-detail-empty]` with the line.
- `admin--tags--detail`, on the grid. Targets: `frame` and `empty` (a `<template>`). Actions:
  - `turbo:click->…#chose` (from a `[data-tag-details]` link): `aria-current` and the row's `data-selected` move to the pressed link's row;
  - `turbo:frame-load->…#loaded`: after a press, and only then, the focus goes to `[data-tag-detail-heading]`;
  - `keydown.esc->…#close` on the rail, and Close: the frame loses `src` and holds the template's clone, the marks go, and the focus returns to the pressed link if it is still in the page.

  It never calls `reload()` on the frame. The screen is `no-cache`, so what it writes is in no snapshot.

- [ ] **Step 1: Write the failing tests.**
  - `detail_component_test.rb`:
    - `test "the detail names the tag, counts its posts, lists them newest first with their state, and links Show all to the posts list filtered by it"`
    - `test "Merge into… is a secondary button and Delete tag… a tertiary one, each opening its dialog with the row's facts; nothing is red and nothing is primary"`. Assert the variants' classes from `ButtonComponent.classes`, the `data-admin--ui--dialog-id-param`, `data-tag-id`, `data-tag-delete-text`, and no `bg-accent` and no `danger` class.
    - `test "Show all is drawn only when the tag has more posts than the rail lists"`
    - `test "without posts.read there is no count and no post, and the dialogs' sentences are the neutral ones"`
    - `test "Close is the shared icon button, named Close"`
  - `tags_test.rb` (integration):
    - "a row has a menu with Merge into… and Delete tag… and no red button" becomes `test "a row has no menu: its Details link names the tag, targets the detail frame and is never prefetched"`. Assert `a[data-turbo-frame=tag-detail][data-turbo-prefetch=false][aria-label='Details of “music”']`, and `count: 0` for `[role=menu]` in `tbody`.
    - "the dialogs are filled from each row's trigger with the true carrier count" becomes `test "the detail's triggers carry the true carrier count"`, over `get admin_tag_path(tag), headers: { "Turbo-Frame" => "tag-detail" }`.
    - "the count is what the viewer may read, while the dialogs name every post the action reaches" and "when the column and the dialog agree…" read their dialog sentences from the detail.
    - `test "the detail lists the tag's kept, readable posts, newest first, at most eight, with the posts list's own count"`. Make 11 posts on the tag, one trashed and one out of the viewer's scope. Assert 8 rows, newest-changed first, and "Show all 9 posts", whose 9 equals `Posts::List`'s `counts["all"]` for that `tag`.
    - `test "the detail costs the same statements for a tag on 2 posts as on 20"`
    - `test "GET /tags/:id outside its frame goes back to the list, and an unknown id is a 404"`
    - `test "/tags/suggest is still the suggestions, not a tag"`
    - `test "a rename answers the chosen tag's detail again, by its id"`. The `update` stream holds `turbo-stream[action=replace][target=tag-detail-<id>]` with the new name.
    - `test "a delete answers the empty detail by the tag's id, and the list's empty state when it was the last tag"`. It replaces the existing "deleting answers a toast and leaves the dialog to be closed by the page", whose toast assertion it keeps.
    - `test "each row's usage bar is its readable count over the largest, and there is no bar without posts.read"`. Assert `--usage: 1.0` on the largest, `0.5` on a half, and no `.admin-tag-usage` for a viewer without `posts.read`.
    - `test "the Tags screen draws no primary button outside its dialogs"`. Outside `dialog` elements, no element's `class` holds every class of `ButtonComponent.classes(:primary)`. A sample page with one such link fails the same matcher.
    - `test "the Tags screen is never restored from Turbo's page cache"`: the `turbo-cache-control` meta.
  - `trash_visibility_test.rb`: `test "the Tags rail lists a tag's kept posts and never a trashed one, and counts as the posts list does"`
  - `admin_contrast_test.rb`: `test "a tag's usage bar is 6.2 / 8.9:1 or better on the row and on its track, in both schemes"`. Resolve `--cs-tag-usage` against `--cs-surface` and `--cs-paper`. A figure is a floor to its rounding, so 6.2 is met by 6.15.
  - `admin_design_rules_test.rb`:
    - `test "the usage bar is the structure hue, as a token of its own"`. `--cs-tag-usage: var(--cs-ic-structure);` appears once in each scheme block, and `bg-tag-usage` only in `app/views/admin/tags/index.html.erb`.
    - The list rail test of Task 2 also finds `.admin-tag-detail`'s docked rule inside the one docked block.
  - `tags_test.rb` (system), each starting on `visit_screen admin_tags_path`. A private `details(tag)` presses the row's Details and waits for `#tag-detail-<id>`.
    - The Merge tests ("Merge into… picks a target…", "the one Merge dialog is refilled for each row…") and "after an inline rename the dialogs name the tag by its new name…" open their dialogs through `details(tag)` and the rail's buttons.
    - "Delete tag… asks first, says how many posts are affected, and removes the row" is the same, through the rail.
    - "a delete the server refuses closes the dialog and says so" is the same, through the rail.
    - "after a delete the focus is on a neighbouring row, and deleting the last tag shows the empty state" becomes `test "deleting the chosen tag from the rail empties the rail and focuses a neighbour; deleting the last one shows the empty state from the answer, with no visit"` (Review Focus 2). Assert `#tag-detail-empty`, the focus on the neighbour's name, and, for the last tag, the empty state with `window.__tagsVisit` unset: a `turbo:visit` listener installed before the delete sets it.
    - `test "at 1600px a tag's details stand in a rail right of the list, on the rail's ground"`. The DOM boxes are as in Task 2.
    - `test "at 1100px the details stand above the list as a card, and nothing stands there before a tag is chosen"`
    - `test "the rail follows the list's own width: a 1279px window docks it, a 1280px one does not"` (Review Focus 4)
    - `test "Details moves the focus to the tag's name in the rail, Tab goes through its posts and buttons, and Close and Escape give it back to the row's Details"`. At 1600: press Details on the second row from the keyboard (Enter). `document.activeElement` is the heading, and the row is marked (`aria-current`, `data-selected`). Tab steps through the post links, Show all, Merge into…, Delete tag… and Close, and Enter on Close puts the focus on the row's Details with no mark left. Again with Escape from inside the rail.
    - `test "a rename of the chosen tag rewords the rail: its heading, Show all's address and both dialogs"` (Review Focus 1)
    - `test "a 50-character tag name and long post titles stay inside the rail"` (Review Focus 3). At 1600, every child box of the rail is inside the rail's box.
  - `dialog_test.rb`: no assertion changes. `messages_test.rb` "the tag dialogs' root and an autosaving row…" is unchanged.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/tags_screen test/integration/admin/tags_test.rb test/integration/trash_visibility_test.rb test/lib/admin_contrast_test.rb test/lib/admin_design_rules_test.rb`.
- [ ] **Step 3: Implement.**
  - Search the tests and the docs by hand for `Actions for`, `merge_item`, `delete_item`, `[role=menu] button` near tags, `data-tag-` on a `tr`, `.admin-tags-table tbody tr` and `Turbo.visit(location.href`, and fix each hit in this task.
  - `grep -rn "text-\[13px\]" app/views/admin/tags app/components/admin/tags_screen` prints nothing: the dialog's published-lists line becomes `text-small`.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin test/integration/admin/tags_test.rb test/integration/admin/tag_suggestions_test.rb test/integration/admin/access_control_test.rb test/integration/trash_visibility_test.rb test/integration/public_javascript_test.rb`, then `bin/rails zeitwerk:check`.
  - Then `bin/rails tailwindcss:build`, and one at a time: `tags_test.rb`, `dialog_test.rb`, `messages_test.rb`, `shell_test.rb`, `presence_lists_test.rb`, `chip_input_test.rb` (the merge picker).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep over every changed file. Check `pgrep`. Commit `feat: Tags in E4: a usage bar per tag and a detail rail with its posts, Merge and Delete` (body: `Advances #117`).

---

### Task 7: 5b-2's reference, CLAUDE.md and the pull request

**Files:**
- Modify `docs/reference/design-system.md`. "Tags" is rewritten whole: the row, the usage bar and its token, Details, the detail frame and its streams, the triggers in the rail, no primary. "E4: the lists' rail" (Task 4) gains the tag detail's two looks and `ListStateComponent`. "Rules a change can break silently" gains:
  - the detail frame is redrawn by stream and never reloaded, and a link into it is never prefetched. The integration test names the attribute. **No guard** for a later `reload()`.
  - a record's state in a list is `ListStateComponent`. **No guard** for a list that draws `StatusChipComponent` beside its own unpublished chip.
- Modify `docs/reference/i18n.md`, the paragraph at its line 72: the Tags screen's scopes (`admin.tags.index`, `admin.components.tags_screen`).
- Modify `CLAUDE.md`. The design-system index line names `app/components/admin/tags_screen/` beside "the Tags screen", and `Admin::Ui::ListStateComponent`.
- Modify `CHANGELOG.md`, `## Unreleased`:
  - Changed: on Tags, each tag shows a bar for how many posts use it; Details opens the tag in a panel beside the list (above it in a narrow window) with its newest posts, Merge into… and Delete tag…; the row has no ⋯ menu.
  - Added: `GET <admin>/tags/:id`, the tag panel, which answers only the Tags screen's panel and otherwise sends back to the list.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** the five checks. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Base: `studio-e4-5b`, or `main` once 5b-1 has merged.
  - Findings: Advances #117.
  - "For the owner to check":
    - every **(owner)** of the decisions table that is Tags';
    - the choice not kept in the address;
    - the usage bar's track.
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`: `docs/editors/posts/tags-related-posts-and-the-mind-graph.md` (Tags: Details, the panel, Merge and Delete moved out of ⋯, the usage bar). There is no Tags screenshot recipe; none is added.
- [ ] **Step 4: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 5b-2 in the reference and CLAUDE.md` (body: `Advances #117`).

---

## Architecture-review findings

Checked on 2026-11-07 against every open issue labelled `architecture-review`.

| Issue | Taken | Why |
|---|---|---|
| #132 split the largest scripts and controllers | advances (Task 1): `posts_controller.rb` (616 lines) loses the list's reads to `Posts::List` | 5b changes the posts list and gives its reads a second caller, the Tags rail. The spec's table names "the posts and pages controllers" as remaining. `hold_controller.js`, `table_controller.js`, the rich-text editor controller and `pages_controller.rb` remain |
| #117 comments about invariants | advances, every task | the posts and tags files carry "design pass round 2, Task 17", "round 3 handoff §4.9", "final review A, M4" and "spec §"; each task rewrites the files it touches |
| #127 slots fit one shape | not taken | its first user of a column entry is the posts table's Notes column. 5b changes no column of the table, only the content of its Status cell (Task 5) |
| #133 entry helpers, large system files | not taken | `posts_list_test.rb` (218 lines) and `tags_test.rb` (161) are small. The tests 5b rewrites start on `visit_screen` by the existing convention, which is not the issue's remainder (shorter names) |
| #124 admin scripts on demand | not taken | `admin--tags--detail` is registered as every admin controller is. Lazy registration changes `controllers/index.js`, which no stage changes |
| #122 post lists | not taken | it is the public site's post lists. The rail's capped list is CS Studio's and already reads no bodies |
| #119 the reference docs' structure | not taken | paragraphs of `design-system.md` and `editors-and-translation-pair.md` change, not their structure |
| #112, #114 to #116, #121, #128 to #131, #135 to #138, #140 to #143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time, only while the one-minute load is under 6, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- 5b-1:
  - `filter_bar_test`, `posts_list_test`, `drafts_test`, `presence_lists_test` and `unpublished_changes_test` (Task 2);
  - `new_record_test`, `dashboard_test`, `dialogs_hang_test`, `command_palette_test` and `press_helper_test` (Task 3).
- 5b-2: `posts_list_test` (Task 5's chips); `tags_test`, `dialog_test`, `messages_test`, `shell_test`, `presence_lists_test` and `chip_input_test` (Task 6).

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `tokens_related_posts_and_starter_pages_test` (posts list rows);
- `trash_test` (the posts list's Undo);
- `theme_toggle_test` (the rail's ground in dark);
- `languages_test` (the posts list in another editing language).

A CI failure is fixed in the task that owns the file.

## Pre-flight (done while writing this plan)

- **Red mid-stack.**
  - Task 2 changes the toolbar's markup and fixes, in itself, `toolbar_component_test`, `filter_bar_test` and every system test that read "Type: All" or `form.admin-filter-bar` on posts.
  - Task 3 drops the radio tiles and, in itself, `HAND_BUTTON_ALLOWED`'s entry (its staleness test would fail), `access_control_test` line 506 and `dashboard_test` line 13.
  - Task 6 removes the row menu and, in itself, every test that opens it (`tags_test` both kinds, `dialog_test`, `trash_visibility_test` line 841) and the keys whose last reader it deletes.
  - Task 5's swap is proven by `table_component_test`'s two state tests, unchanged.
- **A file converted in two tasks.**
  - `posts/index.html.erb` and the toolbar are converted and restyled only in Task 2. `tags/index.html.erb` only in Task 6. The four new-record components and their script only in Task 3.
  - `table_component.html.erb` is touched only in Task 5, and only its Status cell.
  - `editors-and-translation-pair.md`'s posts paragraph is split: its first sentence is Task 1's and the rest Task 4's. `design-system.md`'s rail part is created in Task 4 and extended, not rewritten, in Task 7.
- **Keys or CSS before their user.**
  - `.admin-list-rail` and `.admin-filter-panel` come with the posts screen (Task 2), and `--cs-tag-usage` and `.admin-tag-*` with the Tags rows (Task 6).
  - Each key arrives with its reader, and the Tags keys whose reader goes are deleted in the same task.
- **Guard lists.**
  - `CONVERTED` grows in Tasks 2, 3, 5 and 6, each with its own files.
  - `HAND_BUTTON_ALLOWED` shrinks in Task 3. `ACCENT_FILL_ALLOWED`'s posts entry stays, since the ▾ half still carries `bg-accent`.
  - No browser file is created, so `system_test_seconds.yml` needs no change.
  - Every new unit file is weighed by its count, and none is deleted.
- **Tests that a mutation would not fail.**
  - The "no primary on Tags" test has a sample that must fail.
  - The keys test swaps a translation, so a literal fails it.
  - The detail's statement test takes two sizes.
  - The last-tag test proves no visit by a listener, not by the page's look.
  - The threshold tests check the widths first, so a sidebar change fails them by name.
- **History comments.** Every task ends on the grep in "Comment rule".
