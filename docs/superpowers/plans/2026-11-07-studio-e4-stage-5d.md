# CS Studio in E4, Stage 5d (one tree) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Pages tree and the mind graph's list become one tree. They share one 28px row (`Admin::Ui::TreeItemComponent`, one `.admin-tree` block, four length tokens), branches that fold (folded by default, the path to the selection always open, the person's folds kept in the cookie `cs_tree_open`), and one find field (`Admin::Ui::TreeFindComponent`, `tree/find.js`). The mind graph's list moves to the left into the shell's tree column as an APG tree. Before that, a shared component's contract (`Admin::Ui::Contract` and, for a visitor's page, `Blocks::Contract`) is declared and held by tests, so the two new shared components are born under it.

**Architecture:** The row is a server component with five slots. The Pages screen renders it from `TreeRowComponent`. The graph's script builds the same row from `TreeItemComponent::CLASSES` (handed in as `data-tree-classes`) and two cloned parts, never with classes of its own. Folding is a view state drawn by the server from `TreeOpenSet` (the parsed cookie) on the first paint and on every row redraw. After that it is toggled in the browser by `admin--tree--disclosure`, which writes through `tree/open_set.js`, the cookie's one writer. Find runs on the client over the drawn rows (`tree/find.js` under `admin--tree--find`). It talks to its tree by two events, `tree-find:filtered` and `tree-find:cleared`, and hears `tree:changed` when rows are redrawn. The contract is two small modules over one common declaration (`ComponentContract`), read by a shared contract test and three part guards (a component test, a preview per state, a Design System entry).

**Tech Stack:** Rails 8.1, ViewComponent 4 with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Turbo frames and streams, Stimulus over import maps, SortableJS through `loadSortable()`, Minitest with Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06; stage 5d added 2026-11-07). Sections used: "Decided on 2026-11-07" (20–23), the screen table's rows "Page tree" and "Mind graph", "Stage 5" item **5d** in full (its row, step and guide, folding, the cookie open set, the find field, drag off while filtered, the list on the left, the APG tree, 5d-1/5d-2, files, tests, findings, size), "Architecture-review findings", "The guard after E4", "Constraints". The drawing is `StudioTree` in the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). Its "Interface" section is this plan's starting point. Its siblings are `StudioPageTree` and `StudioMindGraph` (their "Gaps" tagged 5d) and `FoundationComponentContract`. Behind it: the tree review of 2026-11-07 (§6 Interface) and the same-job audit (rows 9 and 1).

**Three pull requests, stacked.**
- **PR 5d-0, the component contract,** is Tasks 1–5 on `studio-e4-5d`, made from `main` at 8364a427. It targets `main`.
- **PR 5d-1, the shared row, the Pages tree, folding and find,** is Tasks 6–11 on `studio-e4-5d-tree`, branched from `studio-e4-5d` after Task 5. It targets `studio-e4-5d` until 5d-0 merges, then `main`.
- **PR 5d-2, the mind graph's list on the left, on the shared row,** is Tasks 12–16 on `studio-e4-5d-graph`, branched from `studio-e4-5d-tree` after Task 11. It targets `studio-e4-5d-tree` until 5d-1 merges, then `main`.

**Why a 5d-0 (my call).** The contract's enforcement changes nothing a person sees and touches about sixty component, preview and test files across `app/components/admin/ui/`, `app/components/blocks/` and `app/components/posts/`.
- Put inside 5d-1, it would bury the tree's diff, which the reviewer reads against the drawing.
- Put inside 5d-2, the two new shared components of 5d-1 would be born outside a contract and converted after.
- First and alone, its proof is plain: the guards are green on main's components, and each guard's own "can fail" test is red on a sample.

The public contract goes in the same PR. It shares the common declaration, it is small, and splitting it out would make a fourth PR that changes nothing anyone sees. Cost: 5d grows by about 3 days (5d-0), which the spec's 10 to 11 did not count.

## Global Constraints

- **Design first.** An implementer who meets a look, a word or a state that neither this plan nor the Design System entry settles stops and reports **NEEDS_CONTEXT**, naming the gap. The design agent updates the Design System artifact first (the entry's "Gaps", marked "Designed, not built"). The answer then goes back to **the same implementer**, never to a new one. No look is decided at review or by the implementer alone. The questions already known are listed under "Design questions sent before dispatch" below, and the controller sends each before the task named.
- **The public site keeps its look.** In 5d-0 a public component gains only its `contract` declaration: no template, class, token, helper or method a theme can see changes, and `Theme::Contract` and `test/support/contract_ledger.rb` are unchanged (so `bin/changelog-guard` asks nothing of them). In 5d-1 and 5d-2 no file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/posts/`, `app/components/public/`, `app/views/layouts/public/` or `app/views/pages/` changes.
- **CLAUDE.md binds every task.** In particular:
  - `--admin-tree-width` and `data-tree-folded` keep their two writers (the head script and `admin--shell--tree-width`). The open set is a third thing, with one writer of its own (`tree/open_set.js`), and is never written on `<html>`.
  - Whatever a script writes into the page is taken back before Turbo's snapshot. That covers the graph's list, now outside the graph controller's element, and the find field's filter.
  - `PostGraph.node_id`, `mind_graph/ids.js` and the `"tag-"` prefix stay in step. The open set stores a page's bare id and is read and written in the graph through `ids.js`.
  - Whatever can be pressed on the canvas has a row in the list.
  - Every tree move is sent through `saving/queue.js` (`admin--pages--tree#save`), and nothing in this stage sends one beside it.
  - Never define `Admin::<Domain>`. The cookie's reader is `TreeOpenSet` (`app/values/tree_open_set.rb`), never `Admin::Tree…`.
  - A list or count over pages hides trashed records itself. The tree's reads are unchanged (`PageTree.rows`).
- **No admin string is a literal.**
  - A component under `app/components/admin/<folder>/` reads `admin.components.<folder>.*` from `config/locales/admin/<folder>.en.yml`, and a script's words come from `data-messages`.
  - A key is added in the task whose code reads it. A file converted to keys is converted whole, in one task, and joins `admin_i18n_test.rb`'s `CONVERTED` in that task.
  - The keys of the new shared components are `admin.components.ui.tree_item.*` and `admin.components.ui.tree_find.*` in `ui.en.yml`.
- **The component contract binds every shared component from Task 2 on.**
  - A component in `app/components/admin/ui/` includes `Admin::Ui::Contract` and declares it. It has a component test, a Lookbook preview with an example per previewable state, and a Design System entry in `test/support/design_system_entries.rb`.
  - A shared component made after 5d-0 also names its keyboard browser test (`keyboard:`).
  - `TreeItemComponent` and `TreeFindComponent` are such components.
- **The tree's semantics are each screen's.**
  - Pages keeps nested lists with disclosure buttons, and is never `role="tree"`.
  - The graph's list is an APG tree, one Tab stop with roving `tabindex`.
  - Neither semantics is "unified" into the other.
- **Scrolling.** The selected or marked row is scrolled into view inside the column only (the column's `scrollTop`), never with `scrollIntoView`.
- **No Turbo morphing, no `broadcast_refresh`** (`notes_guards_test`). A row is redrawn by its stream (`for_page`), the tree by its move answer.
- **Layers.** No rule of this stage sets a raw z-index. The drag handle keeps its place in the gutter with no z-index. Anything raised takes a `--cs-z-*` token.
- **Comment rule (#117).**
  - A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round ("handoff §10 C34", "T2", "Claude Design, 2026-10-13", "cs-studio spec §4.2", "design pass round 2"), "spec §" or what used to be there.
  - The tree's and the graph list's files carry many such comments, and every task rewrites the comments of the files it changes. Its last step before its commit runs `grep -n "spec §\|handoff §\|Task [0-9]\|round [0-9]\|final review\|(T[0-9])\|Claude Design, 20\|old name\|used to\|no longer" <the files the task changed>`, which prints nothing.
  - The plan's wording ("what the row does today") is never copied into a comment.
- **Tests and the machine.**
  - On macOS every test command is prefixed with `PGGSSENCMODE=disable`.
  - Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file at a time, and only while the one-minute load (`sysctl -n vm.loadavg`, first figure) is under 6.
  - A browser test begins on `visit_screen` or `visit_editor`. A test this stage rewrites moves its bare `visit … await_admin_controllers` onto them.
  - Two browser files are new, as the spec names them: `test/system/admin/tree_item_parity_test.rb` (Task 13) and `test/system/admin/tree_find_test.rb` (Task 10, my call: the find tests are nine, and `tree_test.rb` stays the moving and folding file). Both are weighed by their count of tests (`bin/test-shard`) and need no `system_test_seconds.yml` entry.
  - No task deletes a test file. `mind_graph_search_test.rb` is rewritten in Task 15, not removed.
  - **No test run is left in the background** when a task ends: its last step checks that `pgrep -f "rails test"` prints nothing.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #117").
- A look that a person sees and that neither the spec nor the Design System settles is marked **(owner)** or **(design)**. Each has a default. A **(design)** item goes to the design agent before its task (first rule above). Each PR lists its **(owner)** items under "For the owner to check".

## Review Focus

1. **A row redrawn while its branch is folded or the tree is filtered.**
   - The cases: a settings save's answer (`TreeRowComponent.for_page`) replaces `#tree-row-<id>` while the person has folded that row, or while the find field narrows the tree.
   - The expected behaviour: the row comes back folded as it was, and filtered and marked as the rest.
   - Task 8 (component): `test "for_page draws the disclosure from the open set handed in, folded or open"`.
   - Task 10 (browser): `test "a page saved while the tree is filtered keeps its row filtered and marked"`.
2. **A drop into a branch that hovering opened, then the tree redrawn by the move's answer.**
   - The case: the answer is a server drawing of the whole tree.
   - The expected behaviour: the branch the page was dropped into is drawn open. If the hover's open never reached the cookie, the redraw folds the branch and the moved page vanishes into it.
   - Task 9: `test "a page dropped into a parent that hovering opened is shown there after the tree is redrawn"`.
3. **Back or a Turbo restore after folding or finding.**
   - The cases: a snapshot holds whatever was `hidden` and whatever `<mark>` the filter wrote. The graph's list now stands outside its controller's element.
   - The expected behaviour: Back shows the person's folds, an empty find field, no marks, and no stale graph rows.
   - Task 10: `test "Back after a find shows the whole tree, an empty field and no marks"`.
   - Task 15: `test "a mind graph restored from Turbo's cache has no stale rows in the column and an empty find field"`.
4. **"/" and Escape taken from someone typing.**
   - The case for "/": typed into a page's title, a rich-text body, a contenteditable, a dialog's field or ⌘K's field, it stays a slash.
   - The case for Escape: in an empty find field it is not taken, so the narrow window's drawer still closes.
   - Task 10: `test "a slash typed into a field or the rich-text body stays a slash, and Escape in the empty field closes the drawer"`.
5. **Matching as a person types it.**
   - Case and accents are ignored ("uber" finds "Über uns", "ÜBER" too), anywhere in the title, in the editing language.
   - A query starting with "/" matches the page's address only.
   - A title with markup in it stays text in the `<mark>`.
   - Task 10 (unit, on `find.js` through the modules page): `test "matching ignores case and accents, finds a part anywhere, and matches the address only after a slash"`.
   - Task 10 (browser): `test "a title with markup is marked as text"`.

---

## Decisions the spec left open

| Question | Decision | Why |
|---|---|---|
| Where the contract work lands | A third PR first, 5d-0 (above). | It changes nothing visible, it is broad, and the two new components must be born under it. |
| The contract's shape | `ComponentContract` (`app/components/component_contract.rb`) is the common declaration: `accessibility:` (String), `motion:` (`:none` \| `:reduced`), `content_edges:` (subset of `%i[long short none many missing]`), `widths:` (`:container` \| `:fluid` \| `:fixed`), `interface:` (Array of Symbols) and `limits:` (Array of Strings, at least one). `Admin::Ui::Contract` (`app/components/admin/ui/contract.rb`) adds `states:` (Symbols), `keys:` (relative key paths it owns), `slots:` (Symbols), `controller:` (an identifier or nil) and `keyboard:` (`[file, test name]`, or nil for a component made before the contract). `Blocks::Contract` (`app/components/blocks/contract.rb`) adds `tokens:` (theme token names it draws with) and `words:` (`public.*` keys it reads). Each is `extend`ed on `included`, and a class declares once with `contract(...)`. Both answer `.contract` (a frozen `Data`). No base class. | The owner's: a small common declaration, two modules, no base class. A `Data` is read by the tests and nothing at run time. |
| What "interface" means on each side | Studio: the keywords of `initialize` (`:key`/`:keyreq`), held equal by the shared test. Public: the methods a theme's template may call, held equal to `Theme::Contract.components`' line for the component. | Each side's truth already exists. The declaration repeats it so the entry and the code are read together, and the test keeps them equal. |
| Which states a preview must show | Every declared state but `hover`, `focus` and `pressed` (pointer and keyboard states a static preview cannot hold) is a preview example **of the same name**. Content edges are declared and documented, and **no guard** checks a preview for them. | The owner's "a preview covering its states". Edges in every preview would double forty previews for a check a reviewer makes by eye. Said under "Rules a change can break silently". |
| The Design System entry guard | `test/support/design_system_entries.rb` holds three lists. `ENTRIES` is the artifact's component folder names, copied from version 1794066007-38ee. `COVERED_BY` maps a component whose entry is named otherwise (`"Admin::Ui::ToastRegionComponent" => "Toast"`). `NOT_YET` maps a component with no entry yet to the stage that draws it. The default entry name is the class name without `Admin::Ui::` and `Component`. The guard fails on a component with no entry in any of the three, on a `COVERED_BY` value or derived name not in `ENTRIES`, and on any key of `COVERED_BY` or `NOT_YET` that names no component. | Tests cannot reach the artifact. A list copied by hand, which a test holds to the code both ways, is the ledger pattern (`contract_ledger.rb`). |
| The keyboard test rule | `keyboard:` is required on a component not in `UiContract::MADE_BEFORE_CONTRACT` (the components of `app/components/admin/ui/` at 8364a427, frozen). The file must exist, and must hold `test "<name>"`. A `MADE_BEFORE_CONTRACT` entry that names no component fails. | The owner's "for each new shared component". |
| Owned keys | `keys:` equals the leaf paths under `admin.components.ui.<name>` in `ui.en.yml`. A Hash whose keys are only plural categories (`one`, `other`) is one leaf. A key declared and missing fails, and so does a key present and undeclared. | Holds the entry's "words it owns" to the file. |
| The cookie's format | `cs_tree_open` is a list of page ids joined by `.`. An id is opened beyond the default, and `-` before an id means folded where the default or the open path would show it. Example: `12.40.-7`. At most `TreeOpenSet::LIMIT = 300` entries, the oldest dropped first. `path=<ADMIN_PATH>` so the public site is never sent it, `SameSite=Lax`, `max-age` one year, and `Secure` on https. | Plain digits need no escaping and no JSON. The admin path keeps it off `Cookieless`' public wall altogether. 300 ids at about 7 characters fit the 4KB cookie. |
| When a branch is open | `open?(page)`: `false` if folded holds the page; else `true` for the root; else `true` if the page is an ancestor of the selected page; else whether opened holds it. On a navigation to another page (`follow`, `mark(id)`), the folded entries of that page's ancestors are dropped: "if the person folds an ancestor of the open page, it stays folded until they navigate" (tree review). | One rule for the server, `open_set.js` and the graph. The path is a view state and is never written as an open. |
| Junk in the cookie | `TreeOpenSet.parse(raw, readable_ids:)`: a token that is not `-?\d+`, an id not among `readable_ids` (context-only ids are readable for this purpose: they fold too), and anything past `LIMIT` set nothing. A raw value over 4,096 bytes is ignored whole. | The spec's "a stored id that is no page the viewer reads sets nothing", and the width's rule for junk. |
| The topic folder | `app/javascript/tree/` (`open_set.js`, `find.js`) with `app/javascript/controllers/admin/tree/disclosure_controller.js` (`admin--tree--disclosure`) and `find_controller.js` (`admin--tree--find`). | `source_layout_test` wants a topic of the module folder's name. Two small shared controllers keep `admin--pages--tree` (374 lines) from growing. |
| How find and its tree talk | `admin--tree--find` stands on the find component's root, and `aria-controls` names the tree. It dispatches `tree-find:filtered` (`{ query, count }`) and `tree-find:cleared` on the tree element. It listens for `tree:changed`, which a tree's owner dispatches on the tree element after it redraws rows (`admin--pages--tree#rowTargetConnected`, `node_list.js`'s `put`), and applies the current query again. | One event each way. No controller reaches into another. |
| The find field's words for the graph | `TreeFindComponent.new(controls:, noun:, moving: false)`. `noun: :pages` reads `label.pages` "Find a page", `placeholder.pages` "Find a page", `count.pages` "%{count} pages match" (`one` "1 page matches"), `none.pages` "No pages match". `noun: :nodes` reads "Find a page, post or tag" (label and placeholder, today's search words), "%{count} match" / "%{count} matches", "Nothing matches" **(design)**. `moving: true` (Pages) adds `no_moving` "Clear the search to move pages". `clear` is "Clear". | The spec's six keys, per noun. The graph's list holds posts and tags, so "pages match" would be wrong. |
| "/" when the field cannot be seen | "/" does nothing when the field is not rendered visible (`checkVisibility()` false: a closed drawer below 1024px, a folded column). | Focusing a hidden field strands the keyboard. The drawer's button is the way in. |
| A find's last line in the graph | "Search the whole site for '%{query}'" is a button after the tree, outside `role="tree"`, shown while the field holds text. Pressing it runs `PostGraph::Search` through `search/suggestions.js` (as `search_box.js` does today) and shows the grouped results (Pages, Posts, Tags; links to a local view, a page with its address) in the list's region in place of the tree, under a heading "Whole site: “%{query}”" with "Back to the list" before them. Escape there is the way back, as for a pill's rows **(design)**. | The spec's "the server search as the list's last line". The results keep today's links and grouping, and `search_box.js`'s popover goes. |
| The graph's groups in an APG tree | One `role="tree"` (named by the list's label). Its level-1 `treeitem`s are the group headings ("Pages · 9", "Posts · 13", "Tags · 4", "Post types · 2"), open by default, folded by ←/→ and their disclosure, **not stored**. A page row's level is its depth + 2. A post, a tag and a type are level 2, `flat:` rows (no disclosure column). A "+N more" pill is the child of the row it hangs off, which then draws a disclosure, open by default, not stored **(design)**. The unlisted checkbox stays above the tree. A pill's or the unlisted rows are a second tree under their heading, with Back before it. | The spec asks for one Tab stop, and a heading may not stand inside a `role="tree"`. Folds of things that are not pages are not the person's tree. |
| The column's subject and fold words | `content_for :tree_label` holds the column's subject, `"pages"` (the default) or `"mind_graph"` (`Admin::Shell::TreeSubjects::ALL`, an unknown one raises). The words are `admin.components.shell.tree_subject.<subject>.{hide,show,open,button}`: Pages "Hide page tree", "Show page tree", "Open page tree", "Pages ▾". The graph's are "Hide the list", "Show the list", "Open the list", "List ▾" **(design)**. `TreeSubjects` also says whether the column fills (`fill: true` for the graph: `.admin-shell__tree--fill`). | The spec's per-screen words. A subject's key family keeps words out of `content_for`. |
| One hide button | `Admin::Shell::TreeHideComponent.new(subject:)` draws the column head's hide button (today inline in `TreeComponent`), and the graph's column head renders it too. `TreeFoldComponent.new(subject:)` reads the same family. | One job, two screens (the same-job audit's rule). |
| The graph's column head | A row with the heading `h2` "Pages, posts and tags" (`text-sm font-semibold`, as Pages' "Pages") and the hide button, then the find field, then the unlisted checkbox, then the tree **(design)**. | It mirrors the Pages head, and the order matches the spec's Tab order. |
| A drop onto a folded parent | Only the spec's rule: a folded parent under a dragged row opens after `OPEN_ON_HOVER_MS = 600`, and that open is written to the open set at once (Review Focus 2). The tree review's "a drop without waiting appends as last child" is not built. | Not in the spec. The 600ms open covers it, and SortableJS cannot drop into a `hidden` list. |
| `nest()` into a folded sibling | It unfolds the sibling (written to the open set, as the person's own open), then nests, and says "Opened %{title}." before the position. | The spec's "opens it and says so". A page put inside a branch is one the person wants to see. |
| `*` in the graph, Alt+click in Pages | Each opens the item's whole branch (every descendant page), written to the open set. | The spec's words ("opens a whole branch"), not APG's "siblings". |

## Design questions sent before dispatch

The controller sends each to the design agent before the named task. The default goes ahead only if the answer is "as proposed".

- **Q1 (Task 13):** the graph group heading as a level-1 `treeitem`: its label style ("Pages · 9", icon chip), a disclosure in the disclosure column, the focus ring on it. The hub that gains a pill child draws a disclosure.
- **Q2 (Task 12):** the graph's fold words ("Hide the list", "Show the list", "Open the list", "List ▾").
- **Q3 (Task 15):** the graph's column head ("Pages, posts and tags"), the find field's node words, the last line's look (a tertiary text button, `text-small`, under the tree), the whole-site results view (heading, Back, rows as today's search rows on the column's ground) and the unlisted checkbox in the column.
- **Q4 (Task 15):** the canvas box without its 300px column: one column at every width, the legend first. This is the open owner question's default below 1024px.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/components/component_contract.rb`, `app/components/admin/ui/contract.rb` (new), `test/support/ui_contract.rb` (new), `test/components/admin/ui/contract_test.rb` (new) | the common and the Studio declaration, the shared contract test | 1 |
| every `app/components/admin/ui/*_component.rb` | its declaration | 1, 2 |
| `test/support/design_system_entries.rb` (new), `test/lib/component_parts_test.rb` (new), the missing tests and previews | the three part guards and the keyboard rule | 3 |
| `app/components/blocks/contract.rb` (new), `app/components/blocks/**/*_component.rb`, `app/components/posts/*_component.rb`, `test/values/theme/component_contract_test.rb` (new) | the public contract | 4 |
| `docs/reference/design-system.md`, `theming.md`, `CLAUDE.md`, `CHANGELOG.md` | 5d-0's reference | 5 |
| `app/assets/tailwind/content-spiel.css` (four lengths), `content-spiel.tailwind.css` (`.admin-tree` block), `app/components/admin/ui/tree_item_component.*`, `app/views/admin/shared/_tree_glyph.html.erb`, `_icon.html.erb` (`chevron_right`, `house`), `ui.en.yml` | the shared row | 6 |
| `app/components/admin/pages_screen/tree_{component,node_component,row_component}.*`, `pages_screen.en.yml`, `app/javascript/controllers/admin/pages/tree_controller.js` | Pages rows on the shared row, its words in keys | 7 |
| `app/values/tree_open_set.rb`, `app/javascript/tree/open_set.js`, `app/javascript/controllers/admin/tree/disclosure_controller.js`, `app/controllers/admin/pages_controller.rb` (`tree_row_stream`), `app/views/admin/pages/_tree.html.erb` | folding and the open set | 8 |
| `tree_controller.js` (hover open, `nest`) | folding and moving | 9 |
| `app/components/admin/ui/tree_find_component.*`, `app/javascript/tree/find.js`, `app/javascript/controllers/admin/tree/find_controller.js`, `tree_component.html.erb`, `tree_controller.js` | find | 10 |
| `docs/reference/design-system.md`, `cs-studio-shell-and-dashboard.md`, `page-tree-and-routing.md`, `CLAUDE.md`, `CHANGELOG.md` | 5d-1's reference | 11 |
| `app/components/admin/shell/{tree_subjects,tree_hide_component,tree_fold_component,top_bar_component}.*`, `app/views/layouts/admin.html.erb`, `shell.en.yml` | the column's subject and words | 12 |
| `app/components/admin/mind_graph_screen/parts_component.*`, `app/views/admin/mind_graph/show.html.erb` (`data-tree-classes`), `app/javascript/mind_graph/node_list.js` | graph rows on the shared row | 13 |
| `node_list.js`, `app/javascript/mind_graph/app.js`, `selection.js` | the APG tree, its folding and the shared open set | 14 |
| `show.html.erb`, `app/javascript/controllers/admin/mind_graph/graph_controller.js` (`reset`), `app.js`, `search_box.js`, `mind_graph.en.yml`, `content-spiel.tailwind.css` (`.admin-shell__tree--fill`) | the list on the left with find | 15 |
| `docs/reference/*`, `CLAUDE.md`, `CHANGELOG.md` | 5d-2's reference, the Design System cards | 16 |

---

# PR 5d-0: the component contract

### Task 1: The contract's modules and the shared contract test

**Files:**
- Create `app/components/component_contract.rb`. The common declaration's six keywords, each validated (`ArgumentError` naming the keyword and the class), with the constants `EDGES`, `WIDTHS` and `MOTION`.
- Create `app/components/admin/ui/contract.rb`: `Admin::Ui::Contract`, built on `ComponentContract`. It defines `STATES_NOT_PREVIEWED = %i[hover focus pressed]`.
- Create `test/support/ui_contract.rb`, `module UiContract`, like `BlockSamples`:
  - `ui_components` is every class of `app/components/admin/ui/*_component.rb`, derived from the files.
  - `assert_contract(klass)` runs the checks of Step 1.
  - `MADE_BEFORE_CONTRACT` holds the 43 class names at 8364a427.
  - `UNDECLARED` holds the components not declared yet: every one but the five of this task. Task 2 empties it and deletes it.
- Create `test/components/admin/ui/contract_test.rb`.
- Declare `Admin::Ui::ButtonComponent`, `StatusChipComponent`, `DialogComponent`, `ListStateComponent` and `SlotComponent` (a button, a chip, a component with a controller, one with no words, one with a slot registry).
- Modify `test/test_helper.rb`: `require_relative "support/ui_contract"` beside `support/block_samples`. Task 3 adds `support/design_system_entries` the same way.

**Interfaces:**
- Produces `ComponentContract`:
  - `self.included(base)` extends `base` with `contract(**declared)` and `contract`.
  - `contract(...)` with arguments stores a frozen `Data` of every declared keyword. Without arguments it answers the stored declaration, or nil.
  - `ComponentContract::COMMON = %i[accessibility motion content_edges widths interface limits]`.
- Produces `Admin::Ui::Contract`: `include Admin::Ui::Contract` gives `contract(states:, keys:, slots:, controller:, keyboard: nil, **common)`. It answers the same `Data` with the Studio keywords.
- Produces `UiContract#assert_contract(klass)` and `UiContract#ui_components -> Array<Class>`, used by Tasks 2, 3, 6 and 10.

- [ ] **Step 1: Write the failing tests** in `contract_test.rb`:
  - `test "every Admin::Ui component includes the contract and declares it, but the ones not declared yet"`. Iterate `ui_components - UNDECLARED`, and `assert_contract` each.
  - `test "the undeclared list names only components, and none that declares"`.
  - `test "the contract's interface is the component's keywords"`. In `assert_contract`, it is `klass.instance_method(:initialize).parameters` filtered to `:key`/`:keyreq`, compared as sorted Arrays to `interface`.
  - `test "the contract's slots are the component's slots"`: compare against `klass.registered_slots.keys`.
  - `test "the contract's keys are the leaves the component owns in ui.en.yml"`. The scope is `admin.components.ui.<underscored name without _component>`. Plural Hashes count as one leaf, and a component with none declares `[]`.
  - `test "the contract's controller exists and is named in the component's own source"`. The file is `app/javascript/controllers/<identifier with -- as / and - as _>_controller.js`, and the identifier appears in the component's `.rb` or `.html.erb`.
  - `test "the contract can fail"`. Build an anonymous `Class.new(Admin::AdminComponent)` with `def initialize(a:)`, include the contract, and declare `interface: [:b]`. `assert_raises(Minitest::Assertion) { assert_contract(it) }` with the message naming `interface`. The same for a key declared and missing, and for a slot left out.
  - In `component_contract_test.rb` (new, `test/components/component_contract_test.rb`): `test "a declaration with an unknown edge, width or motion, or no limit, is refused by name"`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/contract_test.rb test/components/component_contract_test.rb`. Expected: `NameError: uninitialized constant Admin::Ui::Contract`.
- [ ] **Step 3: Implement** the two modules, the support module and the five declarations. A declaration sits under the class comment, and its `accessibility:` is one sentence: role, name, keyboard.
- [ ] **Step 4: Run** the two files, then `test/lib/source_layout_test.rb test/lib/admin_namespace_shadow_test.rb`, then `bin/rails zeitwerk:check`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep over the changed files. Check `pgrep`. Commit `feat: a shared component declares its contract, and a shared test holds it` (body: `Advances #117`).

---

### Task 2: Every Admin::Ui component declares its contract

**Files:**
- Modify the other 38 `app/components/admin/ui/*_component.rb`: one `contract(...)` each, from reading the component, its template, its test and its keys.
- Modify `test/support/ui_contract.rb`: `UNDECLARED` goes, and so does its test in `contract_test.rb`.
- Interface mismatches found are fixed in the declaration, never by changing a component's signature.

- [ ] **Step 1: Make the test red for every component.** Delete `UNDECLARED` and its test. Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/contract_test.rb`. Expected: FAIL, naming 38 components.
- [ ] **Step 2: Declare each.** The states come from the component's own (a chip's statuses, a dialog's `open`, a save status's `idle saving saved error stale held saved_over offline retrying signed_out forbidden`), `rest` and the pointer states where it is pressable.
- [ ] **Step 3: Run** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/components/previews_test.rb test/lib`. Expected: PASS.
- [ ] **Step 4: Comments and commit.** Run the comment grep over the changed files. Most of them carry a "design pass spec §" line: rewrite those lines. Check `pgrep`. Commit `feat: every shared component declares its contract` (body: `Advances #117`).

---

### Task 3: The part guards: a test, a preview per state, a Design System entry, a keyboard test

**Files:**
- Create `test/support/design_system_entries.rb` (`module DesignSystemEntries`; `ENTRIES`, `COVERED_BY`, `NOT_YET`).
  - `ENTRIES` is the 69 folder names of the artifact's `project/components/` at version 1794066007-38ee, copied from the artifact's file listing (the controller hands the list to the implementer).
  - `COVERED_BY` and `NOT_YET` are filled by reading each entry's "Code" section. The implementer asks the controller for any entry it cannot read.
  - The file's comment says it is a copy that the design agent's changes reach by hand, as the ledger's do.
- Create `test/lib/component_parts_test.rb`. It holds the three guards and the keyboard rule, each with its "can fail" sample.
- Create the missing component tests: `test/components/admin/ui/rail_tab_component_test.rb`, `slot_component_test.rb`, `toast_region_component_test.rb`. Each holds at least the render of every declared state and its words.
- Create the missing previews in `test/components/previews/admin/ui/`: `avatar`, `insecure_notice`, `library_image`, `mail_failed_notice`, `rail_slot`, `rail_tab`, `slot`, `toast_region`, `tooltip` and `unpublished_chip` (`_component_preview.rb`).
- Rename or add examples in the existing previews so that every previewable declared state is an example of its name. A rename keeps the example's body.
- Test: `test/components/previews_test.rb` (unchanged, still renders every example).

**Interfaces:**
- Produces `DesignSystemEntries.entry_for(klass) -> String | nil`: `COVERED_BY[name]`, else the derived name if it is in `ENTRIES`, else nil. Task 6 adds `"Admin::Ui::TreeItemComponent" => "StudioTree"` and Task 10 adds `TreeFindComponent` to `COVERED_BY`.

- [ ] **Step 1: Write the failing tests** in `component_parts_test.rb`:
  - `test "every Admin::Ui component has a component test"` (`test/components/admin/ui/<name>_test.rb`).
  - `test "every Admin::Ui component's preview has an example for each previewable state it declares"`. Read `"Admin::Ui::#{name}Preview".constantize.examples`, and require `contract.states - STATES_NOT_PREVIEWED` ⊆ the examples.
  - `test "every Admin::Ui component has a Design System entry, or is listed with the stage that draws it"`.
  - `test "the entries' lists name only components and entries"`: a stale `COVERED_BY` or `NOT_YET` key fails, and so does a `COVERED_BY` value not in `ENTRIES`.
  - `test "a shared component made after the contract names its keyboard browser test, and the test is there"`.
  - `test "the made-before list names only components"`.
  - `test "each part guard can fail"`. Run each guard's matcher over a sample: a fake component name with no test file, a states list with an example missing, a name with no entry. Each must be reported.
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/lib/component_parts_test.rb`. Expected: FAIL, naming the 3 tests, the 10 previews and the examples that are missing.
- [ ] **Step 3: Implement** the lists, the tests and the previews.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/lib test/components`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `test: every shared component has a test, a preview of each state and a Design System entry`.

---

### Task 4: The public contract, read against the theme contract

**Files:**
- Create `app/components/blocks/contract.rb`: `Blocks::Contract` on `ComponentContract`, with `contract(tokens:, words:, **common)`. Its comment says that `Posts::` components include it too, that a gem's component may, and that it changes nothing a template sees.
- Modify the built-in public components the ledger lists (`ContractLedger::COMPONENTS`: eight blocks, five form inputs, four post components) to include it and declare.
  - `interface:` is the ledger's line for the component.
  - `tokens:` is the `--th-*` names its default template and stylesheet draw with, each without `--th-`.
  - `words:` is the `public.*` keys it reads (`Blocks::CodeComponent#string`'s four, the form's, `site_string`'s through `PublicStrings.read`).
- Create `test/values/theme/component_contract_test.rb`.

- [ ] **Step 1: Write the failing tests:**
  - `test "every built-in component a theme may replace declares the public contract"`. These are the keys of `ContractLedger::COMPONENTS`, constantized.
  - `test "a component that declares the public contract is one a theme may replace"`. Scan `app/components/{blocks,posts}` for `include Blocks::Contract`. Each must be in `Theme::Contract.components`.
  - `test "a public component's interface is its line in the theme contract"`.
  - `test "a public component's tokens are theme tokens, and its words are public keys that exist in English"`. Check `tokens` ⊆ `Theme::Contract.tokens` (without the prefix), and every `words` key resolves in `config/locales/public.en.yml`.
  - `test "the public contract can fail"`. A declaration with an interface that drops a method, and one with `tokens: %w[nope]`, are each reported by name.
  - `test "the Studio and the public contract share only the common declaration"`. `Blocks::Contract.instance_method`s and `Admin::Ui::Contract`'s have no keyword in common outside `ComponentContract::COMMON`, and neither module is a class.
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/values/theme/component_contract_test.rb`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/values/theme test/lib/theming_reference_test.rb test/integration/theme_pages_test.rb test/integration/block_samples_test.rb`, then `bin/rails theme:check` with the default theme (`THEME_PATH` unset), then `bin/rails zeitwerk:check`. Expected: PASS, and the ledger test unchanged.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: a public component declares its contract, read against the theme contract`.

---

### Task 5: 5d-0's reference, CLAUDE.md and the pull request

**Files:**
- Modify `docs/reference/design-system.md`. Add a part "Component contract":
  - what a shared component declares, and why it is two modules over one declaration;
  - the shared test and the three part guards, each with its test's name;
  - `MADE_BEFORE_CONTRACT` and the keyboard rule;
  - that `design_system_entries.rb` is a hand copy of the artifact's list;
  - the review checklist (FoundationComponentContract's "Review checklist", whole);
  - a line under "Rules a change can break silently": **no guard** checks a preview for content edges, or that a Design System entry's text says what the declaration says.
- Modify `docs/reference/theming.md`, in "A component a theme may replace" (find it by `Theme::Contract.components`): a paragraph on `Blocks::Contract`, its test, and that the declaration is not part of what a theme sees.
- Modify `CLAUDE.md`: the design-system index line names `app/components/component_contract.rb`, `Admin::Ui::Contract`, `test/support/ui_contract.rb` and `design_system_entries.rb`, and the theming line names `Blocks::Contract`.
- Modify `CHANGELOG.md`, `## Unreleased`, Added: a gem's block or form component may include `Blocks::Contract` to declare what it promises. Nothing else changes for a site.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`. Expected: all pass.
- [ ] **Step 3: Write the PR body.**
  - Base: `main`.
  - Findings: Advances #117.
  - "For the owner to check": the 5d-0 split and its 3 days; `NOT_YET`'s components (the design agent draws their entries).
  - Documentation: none (nothing a person sees changes).
- [ ] **Step 4: Check** that `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 5d-0, the component contract, in the reference and CLAUDE.md` (body: `Advances #117`).

---

# PR 5d-1: the shared row, the Pages tree, folding and find

### Task 6: `Admin::Ui::TreeItemComponent`, the four lengths and the `.admin-tree` block

**Files:**
- Modify `app/assets/tailwind/content-spiel.css`. On `:root` only, once:

  ```css
  --cs-tree-row: 28px;
  --cs-tree-disclosure: 20px;
  --cs-tree-mark: 16px;
  --cs-tree-step: 20px;
  ```

  Put it beside the other lengths, with a comment that says the step is 13 + 1 + 6 below.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`. Add one `.admin-tree` block after the tree column's rules. `.admin-tree-row--selected` moves into it, so there is one block.
  - **The row.** `.admin-tree-row`: flex, centred, `min-height: var(--cs-tree-row)`, `padding-inline: 4px 8px`, `border-radius: var(--cs-radius)`, hover `--cs-sunken`. Its parts:
    - `__disclosure`: `width: var(--cs-tree-disclosure)`, the row's height, chevron `--cs-meta`, ink on hover, turned 90° when `[aria-expanded="true"]` (120ms `--cs-ease`, none under reduced motion). An empty box on a leaf. None under `.admin-tree-row--flat`.
    - `__mark`: `width: var(--cs-tree-mark)`, `margin-inline-end: 8px`, `--cs-meta`, ink when selected.
    - `__title`: `text-small` (13px / 20px), 400, ink, one line, truncated; `--cs-meta` when `--context-only`.
    - `__trailing`: inline-flex, `gap: 6px`, `margin-inline-start: 6px`.
    - `__count`: `text-count`, `tabular-nums`, `min-width: 14px`, right-aligned, `--cs-meta`. Visually hidden at rest by a clip in this block, never by `sr-only`. Shown on hover, focus-within, any coarse pointer, and on a folded parent.
  - **The step.** `.admin-tree [data-tree-children]`: `margin-inline-start: 13px; border-inline-start: 1px solid var(--cs-line-strong); padding-inline-start: calc(var(--cs-tree-step) - 14px)`.
  - **Focus.** On the row: `:has(:focus-visible)`, and `[role="treeitem"]:focus-visible > .admin-tree-row`, a 2px `--cs-accent` outline at −2px. The treeitem's own outline is none.
  - **Selection.** `.admin-tree-row--selected`: `--cs-sunken` and `box-shadow: inset 3px 0 0 var(--cs-accent)`, title 600.
  - **The match.** `.admin-tree mark`: `background: var(--cs-accent-tint); color: inherit; border-radius: var(--cs-radius)`.
- Create `app/views/admin/shared/_tree_glyph.html.erb`, with `name:` `:chevron`, `:page` or `:home`. It draws the 12px chevron (stroke 1.6) and the 14px page and home glyphs (stroke 1.3), `aria-hidden`. Modify `_icon.html.erb` only if the partial reuses its paths.
- Create `app/components/admin/ui/tree_item_component.{rb,html.erb}`, with its contract (`keyboard: ["test/system/admin/tree_test.rb", "a row's disclosure folds and unfolds its branch by mouse and by keyboard"]`).
- Modify `config/locales/admin/ui.en.yml`: `tree_item.fold` "Fold %{title}", `tree_item.unfold` "Unfold %{title}". `opened` comes in Task 9 with its reader.
- Create `test/components/admin/ui/tree_item_component_test.rb` and `test/components/previews/admin/ui/tree_item_component_preview.rb`. The examples: `rest`, `selected`, `folded`, `open`, `leaf`, `context_only`, `flat`, `root`, `long_title` (a 60-character German title).
- Modify `test/support/design_system_entries.rb`: `COVERED_BY` gains `"Admin::Ui::TreeItemComponent" => "StudioTree"`.
- Test: `test/lib/admin_design_rules_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/component_parts_test.rb`, `test/components/admin/ui/contract_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::TreeItemComponent.new(id:, title:, parent: false, folded: false, controls: nil, selected: false, context_only: false, flat: false, root: false, path: nil, data: {})`.
  - `id` is the row's DOM id. `path` becomes `data-tree-path` (the address for a "/" find). `data` is merged onto the row: behaviour hooks only, and a `class` key raises `ArgumentError`.
  - Slots: `renders_one :handle`, `renders_one :mark` (default: the page glyph, or the home glyph when `root:`), `renders_one :title` (required, the link or the label, with `CLASSES[:title]` applied by the component around it), `renders_one :state`, `renders_many :trailing`.
  - The disclosure, drawn when `parent:` and not `flat:`, is a `<button type="button" class="admin-tree-row__disclosure" aria-expanded aria-controls=<controls> aria-label=<fold|unfold> data-action="admin--tree--disclosure#toggle">`. The row carries `data-tree-row` and `data-tree-title` (the whole title, for find).
- Produces `TreeItemComponent::CLASSES` (frozen): `{ row:, row_selected:, row_context_only:, row_flat:, disclosure:, mark:, title:, trailing:, count:, children: }`. Every value is a class of the `.admin-tree` block, never a utility. Task 7 and Task 13 read it.

- [ ] **Step 1: Write the failing tests.**
  - `tree_item_component_test.rb`:
    - `test "only the selected row is semibold, and the selection is the class the tree's script moves"`
    - `test "a parent draws a disclosure button that names its branch and says whether it is open; a leaf keeps an empty column; a flat row has none"`
    - `test "a folded parent says so and controls its children's list"` (`aria-expanded="false"`, `aria-controls`)
    - `test "a context-only row is meta, with no link and no handle drawn by the screen"`
    - `test "the root draws the home glyph and other rows the page glyph, both hidden from a screen reader"`
    - `test "the slots are drawn in their order: handle, disclosure, mark, title, state, trailing"`
    - `test "a screen cannot hand the row a class"`
    - `test "every CLASSES value is a class of the .admin-tree block"`. Each value is found as a selector in `content-spiel.tailwind.css`.
  - `admin_design_rules_test.rb`:
    - `test "a tree's geometry is its four tokens, written once"`. Each `--cs-tree-*` is defined once, on `:root`, in `content-spiel.css`. The step's three values sum to `--cs-tree-step`. No `ml-`, `pl-`, `padding-inline-start` or `paddingInlineStart` stands in `app/components/admin/pages_screen/tree_*`, `tree_item_component.*` or `app/javascript/mind_graph/node_list.js`.
      - Two files still indent until their task: `INDENT_NOT_YET = { "app/components/admin/pages_screen/tree_node_component.html.erb" => "Task 7", "app/javascript/mind_graph/node_list.js" => "Task 13" }`. Task 7 deletes the first entry and Task 13 the second, together with the constant. Its staleness test is `test "an indent exception that no longer indents fails"`.
    - `test "the match's tint is the tree's own rule, with the title's ink"`. Assert the `.admin-tree mark` rule uses `--cs-accent-tint` and `color: inherit`, and that no `bg-accent-tint` utility stands in a tree file.
    - `test "the tree's rules are one block"`: `.admin-tree-row--selected` is defined once, inside the block.
  - `admin_contrast_test.rb`:
    - `test "a tree's guide stays a hairline: --cs-line-strong on the chrome is under 3:1 in both schemes"`
    - `test "a tree's disclosure, mark and count read on the chrome and on sunken: 4.5:1 or better in both schemes"` (`--cs-meta` and `--cs-ink`)
    - `test "the selected row's bar is 3:1 or better on sunken in both schemes"`. The existing tree test stays, and it moves here if it is a duplicate.
    - `test "a match's tint keeps the title's ink at 4.5:1 or better in both schemes"` (14.5 / 11.4:1 expected)
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/tree_item_component_test.rb test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** The component has no script of its own. `admin--tree--disclosure` comes in Task 8: until then the disclosure's action names a controller that is not registered, which Stimulus ignores, and no test presses it.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the shared tree row, its four lengths and the .admin-tree block`.

---

### Task 7: Pages rows on the shared row; the tree's words in keys

**Files:**
- Modify `app/components/admin/pages_screen/tree_row_component.{rb,html.erb}`. The row renders through `TreeItemComponent`:
  - `id: dom_id`, `title:`, `parent: child_count.positive?`, `folded: false` (Task 8 reads the open set), `controls: "tree-children-#{page.id}"`, `selected: selected?`, `context_only:`, `root: root?`, `path: <the page's public path in the editing language, nil without one>`, `data: { "admin--pages--tree-target": "row", "page-id": page.id }` (not on a context-only row).
  - Slots: `with_handle` (the "⠿" button, unchanged in behaviour, now at `left: calc(-1 * var(--cs-tree-step))` and `width: var(--cs-tree-step)` from the block's `__handle` rule), `with_title` (the link, or the context-only span), `with_state` (`TreeStateMarkComponent`), and `with_trailing` for the translation markers, the `tree.row.markers` slot, the count (`CLASSES[:count]`, `data-child-count`) and "+".
  - "+" takes `any-pointer-coarse:opacity-100` in place of `pointer-coarse:`.
  - `SELECTED_CLASS` becomes `TreeItemComponent::CLASSES[:row_selected]`. `SELECTED_TITLE_CLASS` goes, because the block's selected rule sets the weight. `MARKER_AT_REST` stays.
  - The public path comes from a new read, `PageTree.paths(ids, locale:) -> Hash{Integer => String}`, in `app/queries/page_tree.rb`. It is one statement over `PublicPath`, for the pages' rows in the editing language. Its line says what it answers. `TreeComponent` calls it once for the readable rows, and `for_page` calls it once for its page. Test: `test/queries/page_tree_test.rb`, `test "paths are each page's address in the language, in one statement"`.
  - The class comment is rewritten under the comment rule.
- Modify `tree_node_component.{rb,html.erb}`. The children `<ul>` carries `id="tree-children-<id>"`, `data-tree-children` and the block's step, in place of `ml-2 … border-l border-line pl-[7px]`. The `<li>` carries `data-tree-node`.
- Modify `tree_component.{rb,html.erb}`, converted to keys whole:
  - `tree.heading` "Pages", `.new_page` "+ New page", `.more_actions` "More page actions", `.starter_pages` "Create starter pages", `.drag_help`, `.empty` "No pages yet.".
  - The frame gains `data-messages` with `components.pages_screen.tree.moves.{picked_up,dropped,position,cancelled}` and `components.pages_screen.tree_row.untitled`.
  - The `admin--pages--tree-selected-title-class` attribute goes.
  - The `<ul>` root gets `id="tree-list"`.
- Modify `app/javascript/controllers/admin/pages/tree_controller.js`:
  - The announcements read `messages(this.element).t("components.pages_screen.tree.moves.picked_up", { title, position })` etc.
  - `titleOf` falls back to `tree_row.untitled`, and reads `[data-tree-title]`.
  - `focusHandle` and `titleOf` find their parts by `[data-tree-row]`, not `:scope > div`.
  - The `selectedTitle` class goes.
- Modify `config/locales/admin/pages_screen.en.yml` with the keys above.
- Modify `test/lib/admin_design_rules_test.rb`: `INDENT_NOT_YET` loses its `tree_node_component.html.erb` entry.
- Create `test/components/previews/admin/pages_screen/tree_row_component_preview.rb`. The examples: rest, selected, context-only, draft, scheduled, changes, markers, a long German title.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `tree_component.rb`, `tree_component.html.erb` and `tree_controller.js`.
- Test: `test/components/admin/pages_screen/tree_component_test.rb`, `tree_row_component_test.rb`, `test/lib/script_messages_test.rb`, `test/system/admin/tree_test.rb`, `tree_column_test.rb`.

**Interfaces:**
- Consumes `TreeItemComponent` (Task 6).
- `TreeRowComponent` keeps `for_page(page, selected:, locale:, url_options:)` and `new(...)` as they are. Task 8 adds `open_set:` to both.
- The children list's id is `"tree-children-#{page.id}"`. Task 8's script and Task 10's find read it through `aria-controls`.

- [ ] **Step 1: Write the failing tests.**
  - `tree_component_test.rb`: the tests on `ml-2 … border-l border-line pl-[7px]` become `test "a level is the tree's step: each children list is a data-tree-children list with no indent class of its own"`. The count tests become `test "the subpage count is the tree's count, hidden at rest by the tree's rule and never removed"`. Add:
    - `test "the head, the drag help and the empty line are keys"`. Store a test string for `admin.components.pages_screen.tree.heading` and `.empty`, and assert both render (`I18n.reload!` in `teardown`).
    - `test "the frame hands the script its move words"`
    - `test "each row carries its title and its address for find"`
  - `tree_row_component_test.rb`: "a selected row differs from an unselected one…" reads `CLASSES[:row_selected]`. Keep "a row alone draws what the row draws in the whole tree", and add `test "a row is the shared row: its parts are TreeItemComponent's classes"`.
  - `script_messages_test.rb` needs no change: it finds `tree_controller.js`' keys in the frame's `data-messages`.
  - `tree_test.rb` (system): `test "a picked-up row is announced in the page's words"`. Use German strings stored for the four `moves` keys in the test, `visit_screen`, pick up with Space, and assert the announcer's text.
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/pages_screen test/lib/admin_i18n_test.rb`.
- [ ] **Step 3: Implement.** Search the tests and `app/` by hand for `ml-2`, `pl-[7px]`, `SELECTED_TITLE_CLASS`, `selectedTitle`, `:scope > div`, `"Pages"` near the tree, `Picked up`, `Dropped`, `Position ` and `No pages yet.`, and fix each hit in this task.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin/pages_test.rb test/integration/admin/tree_test.rb`. Then build, and run one at a time: `tree_test.rb`, `tree_column_test.rb`, `tree_fold_test.rb`, `presence_lists_test.rb`, `drafts_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. `tree_row_component.*` and `tree_component.*` carry "T2", "handoff §10" and "Claude Design, 2026-10-13". Check `pgrep`. Commit `feat: the page tree's rows are the shared row, and its words are keys` (body: `Advances #117`).

---

### Task 8: Folding and the open set

**Files:**
- Create `app/values/tree_open_set.rb`:
  - `TreeOpenSet::COOKIE = "cs_tree_open"`, `LIMIT = 300`, `MAX_BYTES = 4_096`.
  - `TreeOpenSet.parse(raw, readable_ids:) -> TreeOpenSet`.
  - `#open?(id, root:, on_path:) -> Boolean`, by the rule in the decisions table.
  - `#to_s -> String`, the normalised value, read by the graph in Task 14.
  - `TreeOpenSet::EMPTY`.
- Modify `TreeComponent`, `TreeNodeComponent` and `TreeRowComponent`:
  - `TreeComponent.new(..., open_set: TreeOpenSet::EMPTY)` works out the selected page's ancestor ids once, from `children_by_parent`.
  - Each node gets `folded: !open_set.open?(page.id, root:, on_path:)`. A folded node's children `<ul>` is `hidden`, and its `<li>` carries `data-folded`.
  - `TreeRowComponent.new(..., folded: false)` and `for_page(page, selected:, locale:, url_options:, open_set:)`. `for_page` reads the page's ancestors (`page.ancestor_ids`) for `on_path`.
- Modify `app/views/admin/pages/_tree.html.erb` and `Admin::PagesController#tree_row_stream` (and every other caller of `TreeComponent.new` or `for_page`: `grep -rn "TreeComponent.new\|for_page(" app`):
  - Each passes `open_set: TreeOpenSet.parse(cookies[TreeOpenSet::COOKIE], readable_ids: <the tree's visible ids>)`.
  - For `for_page`, `readable_ids` is the page and its ancestors.
  - `TreeController#update`'s redraw passes it too.
- Create `app/javascript/tree/open_set.js`, the cookie's one writer:
  - `readOpenSet() -> { opened: Set<string>, folded: Set<string> }`.
  - `setOpen(id, open, { openByDefault }) -> void`. Opening drops `id` from folded, and adds it to opened unless `openByDefault`. Folding is the mirror.
  - `forgetFolds(ids) -> void`.
  - It writes `cs_tree_open` with the path read from the tree element's `data-tree-open-path`, `SameSite=Lax`, `max-age=31536000`, `Secure` on https, keeping the newest `LIMIT` entries.
- Create `app/javascript/controllers/admin/tree/disclosure_controller.js` (`admin--tree--disclosure`), on the tree element (Pages: the frame).
  - `toggle(event)`: the button's `aria-expanded`, its label's word (`fold`/`unfold` from `data-messages`), the `aria-controls` list's `hidden`, the node's `data-folded`.
  - Alt+click opens the whole branch.
  - Each person's toggle is written through `setOpen`, with `openByDefault` read from `data-tree-root` on the root node and `data-tree-on-path` on the path's nodes. The server draws those, and `follow` moves them.
  - It dispatches `tree:changed` after any toggle.
  - `follow` and the graph open a path through `openPathIn(tree, id)` in `tree/open_set.js`. It shows each ancestor, writes nothing but `forgetFolds`, and moves `data-tree-on-path`.
- Modify `tree_controller.js`:
  - `follow` calls `openPathIn` for the open page, then scrolls the selected row into view inside `#tree-column` (its `scrollTop`, as `node_list.js`' `mark` does), never with `scrollIntoView`.
  - `rowTargetConnected` dispatches `tree:changed`.
- Modify `tree_component.html.erb`: the frame's `data-controller` gains `admin--tree--disclosure`; it gets `data-tree-open-path="/<ADMIN_PATH>"` and `data-messages` gains `components.ui.tree_item.{fold,unfold}`.
- Modify `test/lib/admin_design_rules_test.rb` (below) and `test/lib/admin_i18n_test.rb` (`CONVERTED` gains the two new scripts).
- Test: `test/values/tree_open_set_test.rb` (new), the pages_screen component tests, `test/integration/admin/pages_test.rb`, `test/system/admin/tree_test.rb`.

**Interfaces:**
- Produces `TreeOpenSet` (above) and `open_set.js` (above), used by Tasks 9, 10, 14 and 15.
- `openPathIn(tree: Element, id: string) -> void` lives in `tree/open_set.js`, so the graph imports a module, not a controller.

- [ ] **Step 1: Write the failing tests.**
  - `tree_open_set_test.rb`:
    - `test "an opened id opens a branch the default folds, and a folded one folds the root or the open path"`
    - `test "the path to the selected page is open unless the person folded it"`
    - `test "junk, an id the viewer does not read, a value over 4KB and entries past the limit set nothing"`: `"abc.12x.-"`, `"999999"` not readable, `"1." * 3000`.
    - `test "to_s gives back only what it kept, in its order"`
  - `tree_component_test.rb`:
    - `test "folded by default: Home and its children are drawn open, every deeper branch folded with hidden children"`
    - `test "the open path to the selected page is drawn open"`
    - `test "the cookie's opens and folds are honoured, and junk in it is ignored"`
    - `test "the threshold for a server find is 2,000 pages"`: `assert_equal 2_000, Admin::PagesScreen::TreeComponent::FIND_ON_SERVER_ABOVE`. Add the constant here with its comment (the documented next step, `Admin::TreeController#find`).
  - `tree_row_component_test.rb`: `test "for_page draws the disclosure from the open set handed in, folded or open"` (Review Focus 1).
  - `pages_test.rb` (integration): `test "a settings save's row answer reads the open set from the cookie"`. Send the cookie, save, and assert the stream's row has `aria-expanded="false"`.
  - `admin_design_rules_test.rb`: `test "the open set has one writer"`.
    - `document.cookie` appears in `app/javascript` only in `tree/open_set.js`.
    - `cs_tree_open` appears in `app/javascript` only there, and in Ruby only in `tree_open_set.rb`.
    - No Ruby file sets it (`cookies[...] =` or `cookies.permanent`).
    - The test's own sample, a script line `document.cookie = "x"` in another file, is reported.
    - "the tree's width and fold are written by the head script and the tree-width controller alone" still passes.
  - `tree_test.rb` (system, `visit_editor` on a page two levels down):
    - `test "a row's disclosure folds and unfolds its branch by mouse and by keyboard"`: click; then Tab to it and Enter, then Space; check `aria-expanded`, the list's `hidden` and the label "Unfold …".
    - `test "a fold is kept across a reload and a Turbo visit, drawn folded from the first paint"`. After the reload, assert the first `turbo:load` already finds the branch `hidden` (a `MutationObserver` installed by `page.driver.browser.evaluate_on_new_document` records any change of the list's `hidden`, and finds none).
    - `test "Alt+click opens the whole branch"`
    - `test "Back to a page whose branch was folded opens its path and selects its row, scrolled into the column"` (extends "Back to a page opened from the tree…"). The column's `scrollTop` changed, and the window's `scrollY` did not.
    - `test "a folded parent shows its subpage count at rest"`
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/values/tree_open_set_test.rb test/components/admin/pages_screen test/integration/admin/pages_test.rb test/lib/admin_design_rules_test.rb`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the unit tests above and `test/lib`. Then build, and run one at a time: `tree_test.rb`, `tree_column_test.rb`, `tree_fold_test.rb`, `editor_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the page tree's branches fold, and a person's folds are kept in a cookie`.

---

### Task 9: Folding and moving

**Files:**
- Modify `tree_controller.js`:
  - SortableJS `onMove(event)` starts a timer of `OPEN_ON_HOVER_MS = 600` when `event.related` is a folded node's row. The timer is cancelled when the row changes, and on `onEnd`. When it runs out, the node unfolds through `setOpen` (written: Review Focus 2) and the node takes `.admin-tree-drop-target` while the row is over it.
  - `nest(row)`: when the sibling above is folded, it unfolds it the same way first, then announces `messages.t("components.ui.tree_item.opened", { title })`, followed by the position.
  - Every Sortable stays created for every list, hidden ones too. The tests prove a hidden list that becomes visible takes a drop.
- Modify `content-spiel.tailwind.css`, inside the `.admin-tree` block: `.admin-tree-drop-target > .admin-tree-row` is `--cs-sunken` with `box-shadow: inset 0 0 0 1.5px var(--cs-field-line)`.
- Modify `ui.en.yml`: `tree_item.opened` "Opened %{title}." Modify `TreeItemComponent`'s contract `keys:` to add `opened`. The frame's `data-messages` gains it.
- Test: `test/system/admin/tree_test.rb`.

- [ ] **Step 1: Write the failing tests** (`tree_test.rb`):
  - `test "dragging a page over a folded parent opens it after a moment, and the page drops among its children"`. The drag uses Cuprite's mouse with steps, as "dragging a page onto another node…" does. Wait for the list not to be `hidden` (`assert_eventually`), then drop. Check the database and the tree.
  - `test "a page dropped into a parent that hovering opened is shown there after the tree is redrawn"` (Review Focus 2). After the move's stream replaces `#tree`, the parent is `aria-expanded="true"` and the moved row is visible. The cookie holds the parent's id.
  - `test "moving a page right into a folded sibling opens it and says so"`. Keyboard: Space, →. The announcer starts with "Opened <title>.", the sibling is open, and Space drops.
  - `test "a drag that leaves a folded parent before the moment does not open it"`
  - The existing drag tests pass unchanged on an unfolded path. Each one that drops into a deeper branch opens it first through the disclosure, by mouse.
- [ ] **Step 2: Run, and verify they fail** (after a build): `tree_test.rb`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** one at a time: `tree_test.rb`, `undo_test.rb`. Also `test/lib/editing_tab_header_test.rb` (the move's send is unchanged). Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: a folded branch opens under a dragged page and for a keyboard move into it`.

---

### Task 10: The find field, on the Pages tree

**Files:**
- Create `app/components/admin/ui/tree_find_component.{rb,html.erb}`, with its contract:
  - `states: %i[rest focus filled filtered no_match]`
  - `keys:` the eleven leaves of the noun table plus `no_moving` and `clear`
  - `controller: "admin--tree--find"`
  - `keyboard: ["test/system/admin/tree_find_test.rb", "/ focuses the field, Down Arrow reaches the first match, Enter opens it"]`
  - Its markup:
    - `div[role=search]`, then a real `label.sr-only`, then `input[type=search]` (`.admin-well`, 32px, magnifier, `aria-controls`, `aria-keyshortcuts="/"`, `autocomplete="off"`).
    - The `/` hint (`text-count`, a `--cs-line-strong` edge, `rounded-cs`) while it is empty, and Clear (`ButtonComponent`, `icon: :x`, `:tertiary`, `size: :small`) while it holds text. Both are toggled by the controller through `hidden`.
    - The status line `p[role=status][aria-live=polite]` (`text-small text-meta`, the figure in `text-dim` 500).
    - `data-messages` with its own keys.
- Create `app/javascript/tree/find.js`:
  - `normalise(text, locale)`: NFD, combining marks dropped, `toLocaleLowerCase`.
  - `matchesTitle(title, query, locale)` and `matchesPath(path, query)`, used when the query starts with "/".
  - `filterTree(tree, query, { locale }) -> { count }`. It works over `[data-tree-node]`:
    - a node is shown when it or a descendant matches, else `hidden`;
    - a branch holding a match is shown open (its children list un-`hidden`, its disclosure `aria-expanded="true"`, its node `data-filter-open`), never through the open set;
    - the matched part of `[data-tree-title]`'s text is wrapped in `<mark>` built with `textContent` only.
  - `clearFilter(tree)`: it takes back every `hidden` and every `<mark>` the filter wrote, and gives each branch the state of `readOpenSet()` and the path (through `openPathIn`).
- Create `app/javascript/controllers/admin/tree/find_controller.js` (`admin--tree--find`):
  - `input` filters at once. The status line's words are written 300ms after the last keystroke ("%{count} pages match", "No pages match"). With `moving`, it adds the `no_moving` sentence while the filter is on.
  - It dispatches `tree-find:filtered` and `tree-find:cleared` on the tree.
  - `tree:changed@document` (when the event's target is its tree) applies the current query again.
  - "/" on `keydown@document`, unless the target is an `input`, `textarea`, `select`, `[contenteditable]` or inside a `dialog[open]`, a modifier is held, or the field is not visible.
  - Down Arrow focuses the first visible match's focusable: Pages, its link; the graph, Task 15. Up Arrow from there goes back. Enter opens the first match (Pages: `.click()` on its link).
  - Escape on a non-empty field: `preventDefault` and `stopPropagation`, then clear, `clearFilter`, the focus stays in the field, and the selected row is scrolled back inside the column. On an empty field Escape is not taken.
  - `turbo:before-cache@document` clears (Review Focus 3).
- Modify `tree_component.html.erb`: `TreeFindComponent.new(controls: "tree-list", noun: :pages, moving: true)` stands under the head and above `#tree-status`. The frame's `data-tree-locale` is the editing language.
- Modify `tree_controller.js`:
  - On `tree-find:filtered`, every Sortable takes `option("disabled", true)`, the frame takes `data-filtered`, and `key()` refuses a pick-up. On `tree-find:cleared` they come back.
  - The block's rule `.admin-tree[data-filtered] .admin-tree-node__handle { display: none }` (in `content-spiel.tailwind.css`) takes the handles out of the page and of the Tab order.
- Modify `ui.en.yml` (`tree_find.*`), `test/support/design_system_entries.rb` (`COVERED_BY` `"Admin::Ui::TreeFindComponent" => "StudioTree"`), and `test/lib/admin_i18n_test.rb` (`CONVERTED` gains the two scripts and the component).
- Create `test/components/admin/ui/tree_find_component_test.rb`, `test/components/previews/admin/ui/tree_find_component_preview.rb` (examples per state), and `test/system/admin/tree_find_test.rb`.
- `find.js`' matching test goes into `tree_find_test.rb` as one module test: `import("tree/find")` in the browser from the editor, the pattern `test/system/admin/editor_modules_test.rb` uses, since the project has no JavaScript test runner.

**Interfaces:**
- Produces `Admin::Ui::TreeFindComponent.new(controls:, noun: :pages, moving: false)` (`NOUNS = %i[pages nodes]`) and `admin--tree--find`, with the events above. Task 15 renders it with `noun: :nodes`.
- Produces `tree/find.js`' `normalise`, `filterTree` and `clearFilter`. Task 15's graph uses them through the same controller.

- [ ] **Step 1: Write the failing tests.**
  - `tree_find_component_test.rb`:
    - `test "a search landmark with a real label, aria-controls naming the tree and / as its shortcut"`
    - `test "the nouns pick their words"`
    - `test "Clear the search to move pages is offered only where the tree moves"`
  - `tree_find_test.rb` (system, `visit_editor`):
    - `test "typing narrows the tree to matches and their paths, marks them, and Escape gives back the person's folds"`. A branch that was folded is shown during the filter and folded again after. The cookie is unchanged by the filter.
    - `test "no match says No pages match, and no tree is shown"`
    - `test "drag is off while filtered and the line says why"`: no handle is in the page, Space on a row's link picks nothing up, and the line holds "Clear the search to move pages". "+" is still there.
    - `test "/ focuses the field, Down Arrow reaches the first match, Enter opens it"`
    - `test "the count is said once, after the typing stops"`. The status line's text changes once for "trans" typed one key at a time, by a `MutationObserver` count.
    - `test "a page saved while the tree is filtered keeps its row filtered and marked"` (Review Focus 1). Filter, change the open page's title in its settings so it still matches, and wait for SAVED. The redrawn row has its `<mark>`, and the hidden rows stay hidden.
    - `test "Back after a find shows the whole tree, an empty field and no marks"` (Review Focus 3)
    - `test "a slash typed into a field or the rich-text body stays a slash, and Escape in the empty field closes the drawer"` (Review Focus 4). Type "/" in the title field and in a rich-text block: the value holds "/", and the find field is not focused. At 900px, open the drawer, focus the empty field, and press Escape: the drawer closes.
    - `test "a title with markup is marked as text"` (Review Focus 5)
  - The module test in `tree_find_test.rb`: `test "matching ignores case and accents, finds a part anywhere, and matches the address only after a slash"` (Review Focus 5). `normalise("Über uns")` contains `normalise("uber")` and `normalise("ÜBER")`. "/install" matches the path `/docs/install` and not a title "install". "page" matches no address.
- [ ] **Step 2: Run, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. Then build, and run one at a time: `tree_find_test.rb`, `tree_test.rb`, `command_palette_test.rb` (⌘K unchanged), `editor_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: a find field narrows the page tree to the matches and their paths`.

---

### Task 11: 5d-1's reference, CLAUDE.md and the pull request

**Files:**
- Modify `docs/reference/design-system.md`. Add a part "Tree":
  - the row and its slots, `CLASSES`, the four lengths and the step;
  - parents never bolder, the selection, the match as the tint's fourth named use;
  - the two semantics, and why Pages is never `role="tree"`;
  - folding and the open set, its one writer, and the path as a view state;
  - find and drag off while filtered.

  The accent paragraph names the match. Under "Rules a change can break silently":
  - **No guard** that a third tree renders the component or reads `data-tree-classes`, rather than copying the classes.
  - **No guard** that a script other than `find.js` writes `<mark>` into a tree.
  - The open set's writer guard reads `app/javascript`, and **no guard** reads a theme or a gem.
- Modify `docs/reference/cs-studio-shell-and-dashboard.md` ("The tree's rows", "The tree column"): folding, the cookie, find, the open path on `follow`, the scroll in the column.
- Modify `docs/reference/page-tree-and-routing.md` where it names the tree's rows: a pointer to the design-system part.
- Modify `CLAUDE.md`:
  - the shell index line gains `app/values/tree_open_set.rb`, `app/javascript/tree/` and `controllers/admin/tree/`;
  - under "Page tree's width": the open set is a third piece of the tree's state, with one writer, and is never on `<html>`;
  - a "Rules a change can break silently" line: a branch's fold is written only through `tree/open_set.js`, and the find's unfolds never.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - The page tree's rows are smaller and line up on a guide.
  - A branch folds and unfolds, and opens on the way to the page you are on.
  - Your folds are remembered in this browser.
  - A find field at the top of the tree narrows it to the matching pages.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`.
- [ ] **Step 3: Write the PR body.**
  - Base: `studio-e4-5d`, or `main` once 5d-0 has merged.
  - Findings: Advances #117.
  - "For the owner to check":
    - the 600ms;
    - "/" doing nothing in a closed drawer;
    - the cookie path (a sign-in on another admin path starts unfolded).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`:
    - "The page tree: how your pages are organised" (folding, the find field, moving with folded branches, drag off while filtered);
    - its screenshots, retaken in both themes.
  - The Design System cards the design agent redraws now, from 5d-1's look:
    - StudioTree's Pages part (built);
    - StudioPageTree's Gaps (closed: keys, move words, focus ring, `text-count`, `any-pointer-coarse`, the row preview).
- [ ] **Step 4: Check** that `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 5d-1 in the reference and CLAUDE.md` (body: `Advances #117`).

---

# PR 5d-2: the mind graph's list on the left, on the shared row

### Task 12: The column's subject: per-screen fold words, the top bar in keys, one hide button

Before dispatch: Q2.

**Files:**
- Create `app/components/admin/shell/tree_subjects.rb`. `Admin::Shell::TreeSubjects::ALL = { "pages" => { fill: false }, "mind_graph" => { fill: true } }` and `.fetch(name)`, which raises on an unknown subject.
- Create `app/components/admin/shell/tree_hide_component.rb` (the head's button, moved out of `tree_component.html.erb` whole, reading `tree_subject.<subject>.hide`). Create `test/components/admin/shell/tree_hide_component_test.rb`.
- Modify `tree_fold_component.rb`: `new(subject:)`, which reads `.show`.
- Modify `top_bar_component.{rb,html.erb}`, converted to keys whole: "Open navigation", "Jump to…", and the tree button (`.open` as its name, `.button` as its words) per subject. `TopBarComponent.new(tree:)` takes the subject or nil.
- Modify `app/views/layouts/admin.html.erb`:
  - the subject is `content_for(:tree_label).presence || "pages"`, through a helper `admin_tree_subject` in `app/helpers/admin/shell_helper.rb` (or the helper the layout already uses);
  - the aside gains `admin-shell__tree--fill` when the subject fills;
  - the subject goes to the top bar and the fold strip.
- Modify `tree_component.html.erb` (renders `TreeHideComponent.new(subject: "pages")`) and `pages_screen.en.yml` (`tree.hide` goes to `shell.en.yml`).
- Modify `content-spiel.tailwind.css`: `.admin-shell__tree--fill`, from 1024px: `position: sticky; top: var(--admin-top-offset); height: calc(100vh - var(--admin-top-offset)); overflow-y: auto`.
- Modify `config/locales/admin/shell.en.yml` (`tree_subject.pages.*`, `tree_subject.mind_graph.*`, `top_bar.*`) and `test/lib/admin_i18n_test.rb` (`CONVERTED` gains the top bar and the two new files).
- Test: `test/components/admin/shell/*_test.rb`, `test/system/admin/tree_fold_test.rb`, `shell_test.rb`.

**Interfaces:**
- Produces `Admin::Shell::TreeSubjects`, `TreeHideComponent.new(subject:)`, `TreeFoldComponent.new(subject:)`, `TopBarComponent.new(tree: subject_or_nil)` and `content_for :tree_label`. Task 15 sets `"mind_graph"`.

- [ ] **Step 1: Write the failing tests.**
  - `test "the fold buttons and the top bar's tree button say what the column holds"`, in the components: subject `mind_graph` reads its own words, and an unknown subject raises.
  - `test "the top bar's words are keys"`
  - `tree_fold_test.rb`: "the fold buttons say what they control" reads the keys.
- [ ] **Step 2: Run, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for "Pages ▾", "Open page tree", "Open navigation" and "Jump to…", and fix each hit in this task.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. Then build, and run one at a time: `tree_fold_test.rb`, `shell_test.rb`, `tree_column_test.rb`, `command_palette_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the tree column's fold words are the screen's, and the top bar's words are keys`.

---

### Task 13: The graph's rows on the shared row

Before dispatch: Q1. **This task is the look alone. The rows stay buttons in lists, and the semantics change in Task 14.**

**Files:**
- Modify `app/components/admin/mind_graph_screen/parts_component.{rb,html.erb}`: `NAMES` gains `tree-disclosure` and `tree-page-mark` (and `tree-home-mark`), rendered from `admin/shared/_tree_glyph`. The component's comment and its preview gain them.
- Modify `app/views/admin/mind_graph/show.html.erb`: `data-tree-classes="<%= Admin::Ui::TreeItemComponent::CLASSES.to_json %>"` on the graph's element.
- Modify `app/javascript/mind_graph/node_list.js`:
  - `ROW`, `INDENT`, `ROW_PADDING` and `PILL_INDENT` go, and so does every `style.paddingInlineStart`.
  - A row is built from `classes` (handed in as `treeClasses`) and the parts: a disclosure part on a page with children (open, not foldable until Task 14), a page mark part, or a post's dot, a tag's square, or a hub's canvas in the mark box; the title in `CLASSES.title`; the chips under the title (unchanged); the figure in `CLASSES.count`, at rest on every row.
  - A page's children go in a `ul` with `CLASSES.children` and `data-tree-children`.
  - The marked row takes `CLASSES.row_selected` in place of `aria-[current]:bg-accent-tint aria-[current]:font-semibold`, and keeps `aria-current` until Task 14.
  - No class name is written in the file but the ones read from `classes`, and the layout's of the groups' headings and lines.
- Modify `app.js`: it reads `data-tree-classes` and hands it to `createList`.
- Modify `test/lib/admin_design_rules_test.rb`: delete `INDENT_NOT_YET` and its staleness test, so the geometry test reads `node_list.js` with no exception.
- Create `test/system/admin/tree_item_parity_test.rb`.
- Test: `test/system/admin/mind_graph_list_test.rb`, `mind_graph_card_and_list_modules_test.rb`, `test/lib/mind_graph_guards_test.rb`, `test/components/admin/mind_graph_screen/parts_component_test.rb`.

**Interfaces:**
- Consumes `TreeItemComponent::CLASSES` (Task 6). `createList(container, { …, treeClasses })` gains `treeClasses`.

- [ ] **Step 1: Write the failing tests.**
  - `tree_item_parity_test.rb`: `test "the Pages tree and the mind graph's list draw one row"`.
    - At 1600×900, measure a Pages row two levels down (`visit_editor`), then the graph's page row at the same depth (`visit_screen admin_mind_graph_path`, wait for `[data-settled]`).
    - Equal (±0.5px): the row's height, the step between a parent's and a child's mark, the title's computed `font-size`, `font-weight` and `color`, the mark's box, the selected row's `box-shadow` and `background-color`.
    - The test's first assertion runs its comparison over two samples that differ in height, and finds the difference.
  - `mind_graph_guards_test.rb`: `test "the graph's list writes no class of its own for a row: every row class is read from data-tree-classes"`. Scan `node_list.js` for string literals holding `px-`, `py-`, `text-sm`, `bg-accent-tint` or `font-semibold`. Fail on any, with a sample that does.
  - `test "every data-tree-classes key the graph reads is one of CLASSES"`. Parse the keys `classes.<key>` read in `node_list.js`, and require them ⊆ `CLASSES.keys`.
  - `mind_graph_list_test.rb`: "in the list's column a row with two chips and a page three levels down each keep room for twenty characters…" keeps its figure at today's 300px column. Task 15 pins it to the tree's default width.
- [ ] **Step 2: Run, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin/mind_graph_screen`. Then build, and run one at a time: `tree_item_parity_test.rb`, `mind_graph_list_test.rb`, `mind_graph_card_and_list_modules_test.rb`, `mind_graph_drawing_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep (`node_list.js` carries "design answer H2", "G5", "H7"; each becomes the rule it names). Check `pgrep`. Commit `feat: the mind graph's list draws the shared tree row`.

---

### Task 14: The graph's list is an APG tree, folding with the shared open set

**Files:**
- Modify `node_list.js`, in one sweep:
  - The groups become one `ul[role=tree]`, named by the region's label (`aria-labelledby`, or `aria-label` from today's `list_label`).
  - Each group heading is a level-1 `li[role=treeitem][aria-expanded]` holding its row and a `ul[role=group]`.
  - Every row is an `li[role=treeitem]` with `aria-level` and, on a parent, `aria-expanded`. Its name is today's sentence, as `aria-label`. `aria-selected="true"` is on the marked one, in place of `aria-current`.
  - The `button`s go. Roving `tabindex`: one item has `0`, the marked one or else the first; the rest have `-1`.
  - The keys:
    - ↑/↓ move to the previous or next visible item;
    - → opens a folded parent, or moves to its first child;
    - ← folds an open parent, or moves to its parent;
    - Home and End go to the first and the last visible item;
    - Enter or Space selects and opens the card (`onSelect`, or `onMore` and `onAdd` as the item is);
    - `*` opens the item's whole branch.
  - A click on the disclosure part toggles. A click elsewhere on the row selects.
  - A page's fold uses `open_set.js` (`readOpenSet`, `setOpen` with `openByDefault` for depth 0 and the marked page's path). A group's or a hub's is a view state only.
  - `mark(id)` opens the marked page's path (`openPathIn`), moves `tabindex="0"` to it, and keeps it scrolled into view inside the container.
  - `showRows` and `fail` draw their rows as a second tree, under their heading, with Back before it. Escape on them goes back as today.
  - A redraw (`put`) keeps the roving stop on the same node, else the first, and dispatches `tree:changed` on the tree.
  - Hovering or focusing an item still lights its node (`onHover`, the same listeners on the tree).
- Modify `show.html.erb`: `data-tree-open="<%= TreeOpenSet.parse(cookies[TreeOpenSet::COOKIE], readable_ids: <the viewer's readable page ids>).to_s %>"` and `data-tree-open-path`. The readable ids come from the controller's existing read scope (`Admin::MindGraphController#show` gains one `pluck`, under `pages.read`).
- Modify `app.js` and `selection.js` where they call `list.mark` or `list.row`: `row(id)` answers the treeitem.
- Rewrite the list tests that look rows up "as buttons by name". Each takes `find("[role=treeitem][aria-label^='…']")` through a helper `list_item(name)` in `test/support/mind_graph_helpers.rb` (or the file the mind graph tests share), whose comment says why.
- Test: `test/system/admin/mind_graph_list_test.rb`, `mind_graph_card_and_list_modules_test.rb`, `mind_graph_selection_test.rb`, `mind_graph_notes_test.rb` (the card's return of focus), `test/integration/admin/mind_graph_test.rb`.

**Interfaces:**
- Consumes `readOpenSet`, `setOpen` and `openPathIn` (Task 8). `createList(...)` keeps its return shape: `row(id)` now answers an `li[role=treeitem]`, and the card's return of focus calls `.focus()` on it after setting `tabindex="0"`.

- [ ] **Step 1: Write the failing tests.**
  - `mind_graph_card_and_list_modules_test.rb`:
    - `test "the list is one tree: groups at level 1, pages by their depth, posts, tags and types flat at level 2, and the marked node aria-selected"`
    - `test "one Tab stop: the arrows, Home and End move the focus, which skips what is folded or hidden"`
    - `test "→ opens a folded page or goes to its first child, ← folds it or goes to its parent, and * opens the whole branch"`
    - `test "a page's fold in the list is kept in the cookie the Pages tree reads, and a group's fold is not"`
  - `mind_graph_list_test.rb`:
    - `test "Enter or Space on a row opens the node's card and moves the focus to it, and Escape gives it back to the row"`, from "the list is the keyboard path…".
    - `test "selecting a node on the canvas opens its path in the list, marks its row and scrolls the list to it"`
    - `test "a branch folded in the Pages tree is folded in the mind graph's list"` (the shared open set). Fold in Pages, `visit_screen` the graph, and assert `aria-expanded="false"` on that page's item.
  - `integration/admin/mind_graph_test.rb`: `test "the graph's open set is the cookie's, without the pages the viewer does not read"`.
  - Every other list test passes on `list_item`.
- [ ] **Step 2: Run, and verify they fail** (after a build): the two modules and list files.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** one at a time: `mind_graph_list_test.rb`, `mind_graph_card_and_list_modules_test.rb`, `mind_graph_selection_test.rb`, `mind_graph_notes_test.rb`, `mind_graph_loading_test.rb`, `tree_item_parity_test.rb`. Then `PGGSSENCMODE=disable bin/rails test test/lib test/integration/admin/mind_graph_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the mind graph's list is an APG tree whose page branches fold with the Pages tree's`.

---

### Task 15: The list on the left, with the find field and the whole-site search

Before dispatch: Q3 and Q4.

**Files:**
- Modify `app/views/admin/mind_graph/show.html.erb`:
  - `content_for :tree_label, "mind_graph"`.
  - `content_for :tree` holds the column: a head (`h2` "Pages, posts and tags", `TreeHideComponent.new(subject: "mind_graph")`), then `TreeFindComponent.new(controls: "mind-graph-tree", noun: :nodes)`, then `div[data-mind-graph-list][role=region]` (the label as today), then `div[data-mind-graph-search-site]`, which holds the last line's button and `data-url` (the search's address).
  - The graph's box loses its 300px column and its search block. It is one column at every width: the focus or opened bar, the legend, the canvas.
  - The fill rule keeps the box window-high from 1024px.
  - The big comment is rewritten for the new layout and Tab order: the column comes first (the sidebar, the find field, the unlisted checkbox, the tree, the last line), then `<main>` (the focus bar, the legend's toggles, the zoom, the canvas, the card).
- Modify `app/javascript/mind_graph/app.js`:
  - The list's container and the find field are found by `document.querySelector("#tree-column [data-mind-graph-list]")` and `[data-mind-graph-search-site]`, never inside `element`. A screen without the column, which cannot happen on this screen, throws as a missing part does.
  - On `tree-find:filtered` with a query, it shows the last line "Search the whole site for '%{query}'" (`mind_graph.script.list.search_site`).
  - Pressing the last line runs the search through `search/suggestions.js` and `list.showResults({ query, groups, back })` (new on `createList`). The results are today's grouped links and their marks, under "Whole site: “%{query}”" (`mind_graph.script.list.search_site_heading`), with Back.
  - Enter in the find field selects the first match: `onSelect` and the card.
  - `destroy()` stops listening outside the element.
- Modify `search_box.js`: its rendering of a group of results is exported (`renderResults(list, rows, { text, dotClasses })`) for `showResults`. The field, the popover and their Escape and outside-press handling go. Its comment becomes the results' own.
- Modify `app/javascript/controllers/admin/mind_graph/graph_controller.js` `reset()`. It also takes back `#tree-column [data-mind-graph-list]`'s children, the last line's `hidden` and words, and the find field's value, its hint and its status line. Its comment says why: the column stands outside the controller's element, and Turbo's snapshot keeps it.
- Modify `config/locales/admin/mind_graph.en.yml`:
  - `script.list.search_site` "Search the whole site for '%{query}'";
  - `script.list.search_site_heading` "Whole site: “%{query}”";
  - `show.column_heading` "Pages, posts and tags";
  - `show.search.*` goes with its reader, and `script.search.*` stays (the results' words).
  - The view's `messages_data` list gains the two `search_site` keys, written out one by one.
- Modify `content-spiel.tailwind.css`: the graph's own column rules go, and the fill modifier is Task 12's.
- Modify `test/lib/mind_graph_guards_test.rb` where it reads the list or search hooks inside the element.
- Test: `test/system/admin/mind_graph_search_test.rb` (rewritten), `mind_graph_list_test.rb`, `mind_graph_worker_and_back_test.rb`, `tree_column_test.rb`, `tree_fold_test.rb`, `mind_graph_loading_test.rb`, `mind_graph_legend_test.rb`.

**Interfaces:**
- Consumes `TreeFindComponent` with `noun: :nodes` (Task 10), `TreeHideComponent` and `content_for :tree_label` (Task 12), and `.admin-shell__tree--fill`.
- Produces `createList(...).showResults({ query, groups, back }) -> void`.

- [ ] **Step 1: Write the failing tests.**
  - `mind_graph_search_test.rb`, rewritten:
    - `test "the find field narrows the list to the matches and their paths, and the graph is left as it is"`
    - `test "the whole site's search finds a post the graph does not draw and opens its neighbourhood"` (from "search finds a post the global view does not draw…")
    - `test "the whole site's results group pages, posts and tags, show a page's path, say when nothing matches, and Back and Escape return to the list"`
    - `test "a failed whole-site search says so and the graph keeps working"`
    - `test "the results are text: a title with markup is not inserted as markup"`
    - `test "leaving the screen aborts a whole-site search still in flight"`
    - The Focus and depth test stays as it is.
  - `mind_graph_list_test.rb`:
    - "the Tab key meets the search first and the list last" becomes `test "the Tab order is the find field, the list, then the legend, the zoom and the canvas"`.
    - "in the list's column…twenty characters" is pinned to the column's default width (17rem at a 16px root).
    - `test "Enter in the find field selects the first match and opens its card"`
  - `tree_column_test.rb`: `test "the mind graph's column takes the tree's width, divider and drag, and its width is the one Pages left"`
  - `tree_fold_test.rb`: `test "the mind graph's column folds to its strip with its own words, and the canvas widens"`
  - `mind_graph_worker_and_back_test.rb`: `test "a mind graph restored from Turbo's cache has no stale rows in the column and an empty find field"` (Review Focus 3). Leave with rows drawn and a query typed, go Back, and assert, before the data arrives, no `[role=treeitem]` in the column, an empty field and no last line.
  - `test "below 1024px the list is the tree drawer, opened by the top bar's List button"` (the owner's open question, default). It goes in `tree_column_test.rb` or `mind_graph_list_test.rb`.
- [ ] **Step 2: Run, and verify they fail** (after a build).
- [ ] **Step 3: Implement.** Search the tests and `app/` by hand for `data-mind-graph-search`, `data-mind-graph-results`, `mind-graph-search`, `min-[1100px]:col-start-2` and `300px`, and fix each hit in this task.
- [ ] **Step 4: Run** one at a time: every `mind_graph_*_test.rb`, `tree_column_test.rb`, `tree_fold_test.rb`, `tree_item_parity_test.rb`. Then `PGGSSENCMODE=disable bin/rails test test/lib test/components test/integration/admin/mind_graph_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the mind graph's list stands in the tree column, with the find field and the whole site's search`.

---

### Task 16: 5d-2's reference, CLAUDE.md, the pull request and the Design System cards

**Files:**
- Modify `docs/reference/cs-studio-shell-and-dashboard.md`:
  - "Mind graph": the layout, the column, the find field and the last line, the APG tree and its keys, the Tab order, `reset()` taking back the column.
  - "The tree column": it hosts two screens, and `TreeSubjects`.
  - Its "Rules a change can break silently": `reset()`'s new reach. **No guard** for something new a script writes into the column that `reset()` does not take back.
- Modify `docs/reference/design-system.md`, "Tree", which gains the graph's half (the parts, `data-tree-classes`, the parity test) and "E4: the mind graph" (the list moved).
- Modify `CLAUDE.md`. The "Mind graph" silent rules: the list stands in `#tree-column`, and `reset()` takes it back. The ids rule gains `open_set.js` (it stores bare page ids, read through `ids.js`). The index line gains `TreeSubjects`.
- Modify `CHANGELOG.md`, `## Unreleased`, Changed:
  - The mind graph's list stands on the left, in the tree column, with its width, its fold and its drawer.
  - It is one tree, reached with the arrow keys.
  - Its find field narrows it, and its last line searches the whole site.
  - A page folded in one tree is folded in the other.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.**
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard`.
- [ ] **Step 3: Write the PR body.**
  - Base: `studio-e4-5d-tree`, or `main` once 5d-1 has merged.
  - Findings: Advances #117.
  - **"For the owner"**:
    - **The open question, kept at its default.** Below 1024px the mind graph's list is the tree drawer, as Pages' is: a keyboard user on a narrow window opens the drawer (the top bar's "List ▾") to reach the nodes. The fallback, if this is not acceptable, keeps a stacked list under the canvas below 1024px, at the cost of a second placement rule.
    - The graph's fold words and its column head (Q2, Q3).
    - The groups as tree items (Q1).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`: "Tags, related posts and the Mind graph" (the list on the left, the find field, the whole-site search, the keys), with its screenshots retaken.
  - **The Design System cards to redraw**, for the design agent:
    - `StudioTree`: from "Decided, not built" to **Stable**. Its Interface's *(planned)* names become the built ones: `TreeItemComponent.new(id:, title:, parent:, folded:, controls:, selected:, context_only:, flat:, root:, path:, data:)`, `TreeFindComponent.new(controls:, noun:, moving:)`, `admin--tree--disclosure`, `admin--tree--find`, `tree:changed`, `TreeOpenSet`, the cookie's format, `TreeSubjects`. The preview is redrawn from the built rows.
    - `StudioPageTree`: **retired into StudioTree**. Its entry points to StudioTree, and its Gaps are closed.
    - `StudioMindGraph`: the list on the left. Anatomy, the Tab order, the APG tree, the find field and the last line. Its selected-row Gap is closed.
    - `StudioShell`: the column hosts two screens, the per-screen fold words, and the top bar's keys.
    - `FoundationComponentContract`: from "Decided, not built" to **Stable**. Its planned guards are built, with their test names. `Blocks::Contract` is named.
    - New entries for every component in `DesignSystemEntries::NOT_YET`, and `design_system_entries.rb` brought up to date by hand in the same change.
- [ ] **Step 4: Check** that `pgrep -f "rails test"` prints nothing.
- [ ] **Step 5: Commit** `docs: E4 stage 5d-2 in the reference and CLAUDE.md` (body: `Advances #117`).

---

## Architecture-review findings

Checked against the spec's 5d paragraph (the open `architecture-review` issues on 2026-11-07).

| Issue | Taken | Why |
|---|---|---|
| #117 comments about invariants | advances, every task | the tree's files carry "T2", "handoff §10 C34", "Claude Design, 2026-10-13", "cs-studio spec §4.2"; `node_list.js` carries "design answer H2/G5/H7"; every Admin::Ui component Task 2 touches carries "design pass spec §" |
| #132 split the largest scripts | not taken | its remaining parts are not 5d's files. The new behaviour goes into the `tree` topic's modules, so `admin--pages--tree` does not grow into the next one to split |
| #133 entry cost of a system test | not taken | the rewritten tests begin on `visit_screen` or `visit_editor`, and `list_item` is the one new helper |
| #127 slots fit one shape | not taken | the row's slots are the component's own, and `tree.row.markers` keeps its shape |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file at a time, only while the one-minute load is under 6, each prefixed with `PGGSSENCMODE=disable`.

**The implementer must run:**
- 5d-0: none (no markup changes). `previews_test.rb` and the unit suite hold it.
- 5d-1:
  - Task 7: `tree_test`, `tree_column_test`, `tree_fold_test`, `presence_lists_test`, `drafts_test`;
  - Task 8: `tree_test`, `tree_column_test`, `tree_fold_test`, `editor_test`;
  - Task 9: `tree_test`, `undo_test`;
  - Task 10: `tree_find_test`, `tree_test`, `command_palette_test`, `editor_test`.
- 5d-2: as each task lists, and every `mind_graph_*` file in Task 15.

**Likely to change, left to CI:** `notes_markers_test` (the tree's markers), `languages_test` (titles in another editing language), `theme_toggle_test` (the tree in dark), `view_only_test` (context-only rows), `trash_test` (a trashed page leaves the tree). A CI failure is fixed in the task that owns the file.

## Pre-flight (done while writing this plan)

- **The plan against itself.**
  - `TreeItemComponent`'s keys: `fold` and `unfold` in Task 6, `opened` in Task 9, each with its reader and its contract line.
  - `tree.hide` moves from `pages_screen.en.yml` to `shell.en.yml` only in Task 12, which deletes its last reader there.
  - `SELECTED_TITLE_CLASS` and the `selectedTitle` Stimulus class go together in Task 7.
  - `INDENT_NOT_YET` is written in Task 6, loses its Pages entry in Task 7, and is deleted in Task 13. Its staleness test makes it impossible to forget.
  - `UNDECLARED` is written in Task 1 and deleted in Task 2.
- **One block, not two.**
  - The `.admin-tree` rules, `.admin-tree-row--selected` included, are one block (Task 6's test "the tree's rules are one block"). Tasks 9 and 10 add `.admin-tree-drop-target` and `[data-filtered]` inside it.
  - `.admin-shell__tree--fill` is the shell's, beside `.admin-shell__tree`, and is written once in Task 12.
  - The four lengths are written once on `:root` (Task 6's test).
- **Keys before their reader.** Every key arrives in the task whose code reads it. `script.list.search_site` and `search_site_heading` arrive in Task 15, and `show.search.*` is deleted in Task 15 with its reader.
- **Tests a mutation would not fail.**
  - Each contract and part guard has a "can fail" test over a sample (Tasks 1, 3, 4).
  - The parity test compares two different samples first (Task 13).
  - The open-set writer guard reports a sample line (Task 8).
  - The class guard on `node_list.js` reports a sample (Task 13).
  - The "first paint" fold test watches for a change of `hidden`, not the end state (Task 8).
  - The count test counts the status line's changes, not its final text (Task 10).
  - The keys tests swap in a stored translation (Task 7).
- **Guard lists.**
  - `CONVERTED` grows in Tasks 7, 8, 10 and 12, each with its own files.
  - `COVERED_BY` grows in Tasks 6 and 10.
  - `TINT_PAIR_ALLOWED` and `ACCENT_FILL_ALLOWED` are unchanged: the graph stops using `bg-accent-tint` (it was not an allowance), and the match's tint is a stylesheet rule.
- **History comments.** Every task ends on the grep in "Comment rule".
