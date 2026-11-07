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

- **Design first.** An implementer who meets a look, a word or a state that neither this plan nor the Design System entry settles stops and reports **NEEDS_CONTEXT**, naming the gap. The design agent updates the Design System artifact first (the entry's "Gaps", marked "Designed, not built"). The answer then goes back to **the same implementer**, never to a new one. No look is decided at review or by the implementer alone. The questions already asked are answered under "Design answers" below; the one still open is sent before its task.
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
  - Two browser files are new, as the spec names them: `test/system/admin/tree_item_parity_test.rb` (Task 13) and `test/system/admin/tree_find_test.rb` (Task 10, my call: the find tests are ten, and `tree_test.rb` stays the moving and folding file). Both are weighed by their count of tests (`bin/test-shard`) and need no `system_test_seconds.yml` entry.
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
   - Task 8 (component): `test "for_page draws the disclosure from the open cookie handed in, folded or open"`.
   - Task 10 (browser): `test "a page saved while the tree is filtered keeps its row filtered and marked"`.
2. **A drop into a branch that hovering opened, then the tree redrawn by the move's answer.**
   - The case: the answer is a server drawing of the whole tree.
   - The expected behaviour: the branch the page was dropped into is drawn open. If the hover's open never reached the cookie, the redraw folds the branch and the moved page vanishes into it.
   - Task 9: `test "a page dropped into a parent that hovering opened is shown there after the tree is redrawn"`, and `test "a page moved into a page with no children is shown under it after the tree is redrawn"`.
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
   - Task 10 (a module test in `tree_find_test.rb`, on `find.js`): `test "matching ignores case and accents, finds a part anywhere, and matches the address only after a slash"`.
   - Task 10 (browser): `test "a title with markup is marked as text"`.

---

## Decisions the spec left open

| Question | Decision | Why |
|---|---|---|
| Where the contract work lands | A third PR first, 5d-0 (above). | It changes nothing visible, it is broad, and the two new components must be born under it. |
| The contract's shape | `ComponentContract` (`app/components/component_contract.rb`) is the common declaration: `accessibility:` (String), `motion:` (`:none` \| `:reduced`), `content_edges:` (subset of `%i[long short none many missing]`), `widths:` (`:container` \| `:fluid` \| `:fixed`), `interface:` (Array of Symbols) and `limits:` (Array of Strings, at least one). `Admin::Ui::Contract` (`app/components/admin/ui/contract.rb`) adds `states:` (Symbols), `keys:` (relative key paths it owns), `slots:` (Symbols), `controller:` (an identifier or nil), `script_states:` (a Hash of a state a script holds to the `[file, test name]` of the browser test that holds it) and `keyboard:` (`[file, test name]`, or nil for a component made before the contract). `Blocks::Contract` (`app/components/blocks/contract.rb`) adds `words:` (the `public.*` keys it reads; an entry ending in `.*` is a prefix read with an interpolated key, such as `public.blocks.note.kinds.*`). It declares no tokens: a block's template draws through shared stylesheets (`prose.css`, `sections.css`, `theme.css`), so a component's tokens cannot be read from one file, and the theme's tokens are already held by the ledger (`THEMED_TOKENS`). Each is `extend`ed on `included`, and a class declares once with `contract(...)`. Both answer `.contract` (a frozen `Data`). No base class. | The owner's: a small common declaration, two modules, no base class. A `Data` is read by the tests and nothing at run time. |
| What "interface" means on each side | Studio: the keywords of `initialize` (`:key`/`:keyreq`), held equal by the shared test. Public: the methods a theme's template may call, held equal to `Theme::Contract.components`' line for the component. | Each side's truth already exists. The declaration repeats it so the entry and the code are read together, and the test keeps them equal. |
| Which states a preview must show | Only the states a static render can draw. `states:` holds those, and each but `hover`, `focus` and `pressed` (pointer and keyboard states) is a preview example **of the same name**. A state a script holds (a dialog's `open`, the find field's `filled`, `filtered` and `no_match`) goes in `script_states:` instead, needs no example, and names the browser test that holds it: the guard checks that the file holds `test "<name>"`. Content edges are declared and documented, and **no guard** checks a preview for them. | The owner's ruling (C17): an example of a script-held state would render the same as `rest`. Edges in every preview would double forty previews for a check a reviewer makes by eye. Said under "Rules a change can break silently". |
| The Design System entry guard | `test/support/design_system_entries.rb` holds three lists. `ENTRIES` is the artifact's component folder names, copied by hand (its comment names the artifact version it was read at, as a provenance stamp, and says it is updated by hand with each change the design agent makes: **(owner)** whether the stamp stays). `COVERED_BY` maps a component whose entry is named otherwise (`"Admin::Ui::ToastRegionComponent" => "Toast"`). `NOT_YET` maps a component with no entry yet to the reason it has none (for example "no entry drawn; the design agent draws it"). The default entry name is the class name without `Admin::Ui::` and `Component`. The guard fails on a component with no entry in any of the three, on a `COVERED_BY` value or derived name not in `ENTRIES`, and on any key of `COVERED_BY` or `NOT_YET` that names no component. | Tests cannot reach the artifact. A list copied by hand, which a test holds to the code both ways, is the ledger pattern (`contract_ledger.rb`). |
| The keyboard test rule | `keyboard:` is required on a component not in `UiContract::MADE_BEFORE_CONTRACT` (the 43 components of `app/components/admin/ui/` when the contract came; its comment says it is frozen and only shrinks) or in `UiContract::KEYBOARD_NOT_YET` (a new component whose keyboard test comes in a later task of the same PR, each with its reason; Task 6 adds `TreeItemComponent`, Task 8 removes it). The file must exist, and must hold `test "<name>"`. An entry of either list that names no component, or a `KEYBOARD_NOT_YET` entry that declares `keyboard:`, fails. | The owner's "for each new shared component", without a red commit between a component and its keyboard test (C2). |
| Owned keys | `keys:` equals the leaf paths under `admin.components.ui.<name>` in `ui.en.yml`. A Hash whose keys are only plural categories (`one`, `other`) is one leaf. A key declared and missing fails, and so does a key present and undeclared. | Holds the entry's "words it owns" to the file. |
| The cookie's format | `cs_tree_open` is a list of page ids joined by `.`. An id is opened beyond the default, and `-` before an id means folded where the default or the open path would show it. Example: `12.40.-7`. At most `TreeOpenSet::LIMIT = 300` entries, the oldest dropped first. `path=<ADMIN_PATH>` so the public site is never sent it, `SameSite=Lax`, `max-age` one year, and `Secure` on https. | Plain digits need no escaping and no JSON. The admin path keeps it off `Cookieless`' public wall altogether. 300 ids at about 7 characters fit the 4KB cookie. |
| When a branch is open | `open?(page)`: `true` if the page is an ancestor of the selected page; else `false` if folded holds the page; else `true` for the root; else whether opened holds it. So a drawing never hides the selected row. A fold of a path ancestor holds within the page view only: on every arrival at a page (the tree controller's `connect`, `follow`, the graph's `mark(id)`), the folded entries of that page's ancestors are dropped (`forgetFolds`): "if the person folds an ancestor of the open page, it stays folded until they navigate" (tree review). | One rule for the server, `open_set.js` and the graph. The path is a view state and is never written as an open. Checking the path first is C14's fix: with folds first, a full load under a folded ancestor drew the selected row hidden. |
| Junk in the cookie | `TreeOpenSet.parse(raw, readable_ids:)`, called inside `TreeComponent` with its visible ids (the views hand it the raw cookie, `open_cookie:`): a token that is not `-?\d+`, an id not among `readable_ids` (context-only ids are readable for this purpose: they fold too), and anything past `LIMIT` set nothing. A raw value over 4,096 bytes is ignored whole. | The spec's "a stored id that is no page the viewer reads sets nothing", and the width's rule for junk. |
| The topic folder | `app/javascript/tree/` (`open_set.js`, `find.js`) with `app/javascript/controllers/admin/tree/disclosure_controller.js` (`admin--tree--disclosure`) and `find_controller.js` (`admin--tree--find`). | `source_layout_test` wants a topic of the module folder's name. Two small shared controllers keep `admin--pages--tree` (374 lines) from growing. |
| Which element is "the tree" | One definition (C12): the tree is the element `aria-controls` names, with `.admin-tree` on it. In Pages it is `ul#tree-list`, and in the graph `ul#mind-graph-tree[role=tree]`. `admin--tree--disclosure` stands on it. `data-tree-open-path` and `data-tree-locale` are on it. `tree:changed`, `tree-find:filtered` and `tree-find:cleared` are dispatched on it, and bubble to the frame's `admin--pages--tree`. | Every script finds the tree the same way. |
| How find and its tree talk | `admin--tree--find` stands on the find component's root. It dispatches `tree-find:filtered` (`{ query, count }`) and `tree-find:cleared` on the tree. It listens for `tree:changed` on the tree, which a tree's owner dispatches after it redraws rows (`admin--pages--tree#rowTargetConnected`, `node_list.js`'s `put`), and applies the current query again. The find controller alone owns Down Arrow and Enter for both trees (C22). Down focuses the first visible match's `[data-tree-focus]`: Pages' title link, or the graph's treeitem (given `tabindex="0"` first). Enter calls `.click()` on it: the link opens in Pages, and in the graph the treeitem's click selects the node and opens its card. `app.js` adds no key handler. | One event each way. No controller reaches into another. |
| The find field's words for the graph | `TreeFindComponent.new(controls:, noun:, moving: false)`. `noun: :pages` reads `label.pages` "Find a page", `placeholder.pages` "Find a page", `count.pages` "%{count} pages match" (`one` "1 page matches"), `none.pages` "No pages match". `noun: :nodes` reads `label.nodes` and `placeholder.nodes` "Find a page, post or tag", `count.nodes` (`one` "1 match", `other` "%{count} matches") and `none.nodes` "Nothing matches" (design answer Q3). `moving: true` (Pages) adds `no_moving` "Clear the search to move pages". `clear` is "Clear". The leaves are ten: the eight of the two nouns, `no_moving` and `clear`. | The spec's six keys, per noun. The graph's list holds posts and tags, so "pages match" would be wrong. |
| "/" when the field cannot be seen | "/" does nothing when the field is not rendered visible (`checkVisibility()` false: a closed drawer below 1024px, a folded column). | Focusing a hidden field strands the keyboard. The drawer's button is the way in. |
| A find's last line in the graph | "Search the whole site for “%{query}”" is a button after the tree, outside `role="tree"`, shown while the field holds text. Pressing it runs `PostGraph::Search` through `search/suggestions.js` (as `search_box.js` does today) and shows the grouped results in the list's region in place of the tree. The look is design answer Q3, written into Task 15. | The spec's "the server search as the list's last line". The results keep today's links and grouping, and `search_box.js`'s popover goes. |
| The graph's groups in an APG tree | One `role="tree"` (named by the list's label). Its level-1 `treeitem`s are the group headings ("Pages · 9", "Posts · 13", "Tags · 4", "Post types · 2"), open by default, folded by ←/→ and their disclosure, **not stored**. A page row's level is its depth + 2. A post, a tag and a type are level 2, `flat:` rows (no disclosure column). A "+N more" pill is the child of the row it hangs off, which then draws a disclosure, open by default, not stored (design answer Q1, its look in Task 13). The unlisted checkbox stays above the tree. A pill's or the unlisted rows are a second tree under their heading, with Back before it. | The spec asks for one Tab stop, and a heading may not stand inside a `role="tree"`. Folds of things that are not pages are not the person's tree. |
| The column's subject and fold words | `content_for :tree_label` holds the column's subject, `"pages"` (the default) or `"mind_graph"` (`Admin::Shell::TreeSubjects::ALL`, an unknown one raises). The words are `admin.components.shell.tree_subject.<subject>.{hide,show,open,button}`: Pages "Hide page tree", "Show page tree", "Open page tree", "Pages ▾". The graph's are "Hide list", "Show list", "Open list", "List ▾" (design answer Q2). The divider's name and tooltip (`tree_divider.*`, "Page tree width") join the family as `width`: the graph's words are still to ask (Q5, below). `TreeSubjects` also says whether the column fills (`fill: true` for the graph: `.admin-shell__tree--fill`). | The spec's per-screen words. A subject's key family keeps words out of `content_for`. |
| One hide button | `Admin::Shell::TreeHideComponent.new(subject:)` draws the column head's hide button (today inline in `TreeComponent`), and the graph's column head renders it too. `TreeFoldComponent.new(subject:)` reads the same family. | One job, two screens (the same-job audit's rule). |
| The graph's column head | A row with the heading `h2` "Pages, posts and tags" (`mind_graph.show.column_heading`, `text-sm font-semibold text-ink`) and the hide button, then the find field, then the unlisted checkbox (`CheckboxComponent`, label `text-sm`), then the tree (design answer Q3). | It mirrors the Pages head, and the order matches the spec's Tab order. |
| A drop onto a folded parent | Only the spec's rule: a folded parent under a dragged row opens after `OPEN_ON_HOVER_MS = 600`, and that open is written to the open set at once (Review Focus 2). The tree review's "a drop without waiting appends as last child" is not built. | Not in the spec. The 600ms open covers it, and SortableJS cannot drop into a `hidden` list. |
| Where a moved page lands | Every drop and every keyboard nest writes `setOpen(newParent, true)` before the move is sent, whether the parent had children or not (C13). A page moved into a childless page makes that page a parent, which the server's redraw would otherwise draw folded, hiding the page just moved. | Review Focus 2's failure, met by every move and not only by a hover. |
| `nest()` into a folded sibling | It unfolds the sibling (written to the open set, as the person's own open), then nests, and says "Opened %{title}." before the position. | The spec's "opens it and says so". A page put inside a branch is one the person wants to see. |
| `*` in the graph, Alt+click in Pages | Each opens the item's whole branch (every descendant page), written to the open set. | The spec's words ("opens a whole branch"), not APG's "siblings". |

## Design answers

The design agent answered Q1 to Q4 (Design System v79–80; `StudioTree` and `StudioMindGraph`): `.superpowers/sdd/design-answers-5d.md` in this worktree. Each answer is written into its task: Q1 into Tasks 13 and 14, Q2 into Task 12, Q3 into Tasks 10 and 15, Q4 into Task 15. An implementer reads the file beside the task.

One question is still open, and the controller sends it before Task 12:
- **Q5 (Task 12, C29):** the divider's name and tooltip on the graph's column (today "Page tree width"). Default: "List width".

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `app/components/component_contract.rb`, `app/components/admin/ui/contract.rb` (new), `test/support/ui_contract.rb` (new), `test/components/admin/ui/contract_test.rb` (new) | the common and the Studio declaration, the shared contract test | 1 |
| every `app/components/admin/ui/*_component.rb` | its declaration | 1, 2 |
| `test/support/design_system_entries.rb` (new), `test/lib/component_parts_test.rb` (new), the missing tests and previews | the three part guards and the keyboard rule | 3 |
| `app/components/blocks/contract.rb` (new), the 18 ledgered `app/components/blocks/**/*_component.rb` and `app/components/posts/*_component.rb`, `test/values/theme/component_contract_test.rb` (new) | the public contract | 4 |
| `docs/reference/design-system.md`, `theming.md`, `CLAUDE.md`, `CHANGELOG.md` | 5d-0's reference | 5 |
| `app/assets/tailwind/content-spiel.css` (four lengths), `content-spiel.tailwind.css` (`.admin-tree` block), `app/components/admin/ui/tree_item_component.*`, `app/views/admin/shared/_tree_glyph.html.erb` (new), `ui.en.yml` | the shared row | 6 |
| `app/components/admin/pages_screen/tree_{component,node_component,row_component}.*`, `pages_screen.en.yml`, `app/javascript/controllers/admin/pages/tree_controller.js`, `app/queries/page_tree.rb` (`paths`), `test/queries/page_tree_test.rb` (new) | Pages rows on the shared row, its words in keys | 7 |
| `app/values/tree_open_set.rb` (new), `app/javascript/tree/open_set.js` (new), `app/javascript/controllers/admin/tree/disclosure_controller.js` (new), `tree_item_component.html.erb` (the disclosure's action), `app/controllers/admin/pages_controller.rb` (`tree_row_stream`), `app/controllers/admin/tree_controller.rb`, `app/views/admin/pages/_tree.html.erb`, `test/system/tree_test.rb` | folding and the open set | 8 |
| `tree_controller.js` (hover open, `save`'s open, `nest`) | folding and moving | 9 |
| `app/components/admin/ui/tree_find_component.*` (new), `app/javascript/tree/find.js` (new), `app/javascript/controllers/admin/tree/find_controller.js` (new), `tree_component.html.erb`, `tree_controller.js`, `test/system/admin/tree_find_test.rb` (new) | find | 10 |
| `docs/reference/design-system.md`, `cs-studio-shell-and-dashboard.md`, `page-tree-and-routing.md`, `CLAUDE.md`, `CHANGELOG.md` | 5d-1's reference | 11 |
| `app/components/admin/shell/tree_subjects.rb` (new), `tree_hide_component.rb` (new), `tree_fold_component.rb`, `tree_divider_component.rb`, `top_bar_component.*`, `app/helpers/admin/shell_helper.rb` (new), `app/views/layouts/admin.html.erb`, `shell.en.yml`, `content-spiel.tailwind.css` (`.admin-shell__tree--fill`) | the column's subject and words | 12 |
| `app/components/admin/mind_graph_screen/parts_component.*`, `app/views/admin/mind_graph/show.html.erb` (`data-tree-classes`), `app/javascript/mind_graph/node_list.js` | graph rows on the shared row | 13 |
| `node_list.js`, `app/javascript/mind_graph/app.js`, `selection.js`, `app/controllers/admin/mind_graph_controller.rb`, `test/support/mind_graph_system_test_case.rb` (`list_item`) | the APG tree, its folding and the shared open set | 14 |
| `show.html.erb`, `app/javascript/controllers/admin/mind_graph/graph_controller.js` (`reset`), `app.js`, `search_box.js`, `mind_graph.en.yml` | the list on the left with find | 15 |
| `docs/reference/*`, `CLAUDE.md`, `CHANGELOG.md` | 5d-2's reference, the Design System cards | 16 |

---

# PR 5d-0: the component contract

### Task 1: The contract's modules and the shared contract test

**Files:**
- Create `app/components/component_contract.rb`. The common declaration's six keywords, each validated (`ArgumentError` naming the keyword and the class), with the constants `EDGES`, `WIDTHS` and `MOTION`.
- Create `app/components/admin/ui/contract.rb`: `Admin::Ui::Contract`, built on `ComponentContract`. It defines `STATES_NOT_PREVIEWED = %i[hover focus pressed]`. A state a script holds is never in `states:`, only in `script_states:`.
- Create `test/support/ui_contract.rb`, `module UiContract`, like `BlockSamples`:
  - `ui_components` is every class of `app/components/admin/ui/*_component.rb`, derived from the files.
  - `assert_contract(klass, source: nil)` runs the checks of Step 1. `source:` is the text read for the controller check, the component's own files when nil.
  - `MADE_BEFORE_CONTRACT` holds the 43 class names of the components there when the contract came. Its comment says it is frozen and only shrinks.
  - `KEYBOARD_NOT_YET` (empty here) is the keyboard rule's list for a new component whose keyboard test comes later in the same PR, each entry with its reason.
  - `UNDECLARED` holds the components not declared yet: every one but the five of this task. Task 2 empties it and deletes it.
- Create `test/components/admin/ui/contract_test.rb`.
- Declare `Admin::Ui::ButtonComponent`, `StatusChipComponent`, `DialogComponent`, `ListStateComponent` and `SlotComponent` (a button, a chip, a component with a controller, one with no words, one with a slot registry).
- Modify `test/test_helper.rb`: `require_relative "support/ui_contract"` beside `support/block_samples`. Task 3 adds `support/design_system_entries` the same way.

**Interfaces:**
- Produces `ComponentContract`:
  - `self.included(base)` extends `base` with `contract(**declared)` and `contract`.
  - `contract(...)` with arguments stores a frozen `Data` of every declared keyword. Without arguments it answers the stored declaration, or nil.
  - `ComponentContract::COMMON = %i[accessibility motion content_edges widths interface limits]`.
- Produces `Admin::Ui::Contract`: `include Admin::Ui::Contract` gives `contract(states:, keys:, slots:, controller:, script_states: {}, keyboard: nil, **common)`. It answers the same `Data` with the Studio keywords.
- Produces `UiContract#assert_contract(klass)` and `UiContract#ui_components -> Array<Class>`, used by Tasks 2, 3, 6 and 10.

- [ ] **Step 1: Write the failing tests** in `contract_test.rb`:
  - `test "every Admin::Ui component includes the contract and declares it, but the ones not declared yet"`. Iterate `ui_components - UNDECLARED`, and `assert_contract` each.
  - `test "the undeclared list names only components, and none that declares"`.
  - `test "the contract's interface is the component's keywords"`. In `assert_contract`, it is `klass.instance_method(:initialize).parameters` filtered to `:key`/`:keyreq`, compared as sorted Arrays to `interface`.
  - `test "the contract's slots are the component's slots"`: compare against `klass.registered_slots.keys`.
  - `test "the contract's keys are the leaves the component owns in ui.en.yml"`. The scope is `admin.components.ui.<underscored name without _component>`. Plural Hashes count as one leaf, and a component with none declares `[]`.
  - `test "the contract's controller exists and is named in the component's own source"`. The file is `app/javascript/controllers/<identifier with -- as / and - as _>_controller.js`, and the identifier appears in the component's `.rb` or `.html.erb`.
  - `test "a script-held state names a browser test that is there"`: each `script_states:` value's file exists and holds `test "<name>"`, and no state is in both `states:` and `script_states:`.
  - `test "the contract can fail"`. The samples are named classes defined in the test file (`UiContractSampleComponent < Admin::AdminComponent`, with `def initialize(a:)`), so the keys check has a scope and the controller check is handed its text by `source:`. A declaration of `interface: [:b]` gives `assert_raises(Minitest::Assertion) { assert_contract(UiContractSampleComponent, source: "") }` with the message naming `interface`. The same for a key declared and missing (with `I18n.backend.store_translations` for the sample's scope, `I18n.reload!` in `teardown`), for a slot left out, and for a `script_states:` test name the file does not hold.
  - In `component_contract_test.rb` (new, `test/components/component_contract_test.rb`): `test "a declaration with an unknown edge, width or motion, or no limit, is refused by name"`.
- [ ] **Step 2: Run them, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/contract_test.rb test/components/component_contract_test.rb`. Expected: `NameError: uninitialized constant Admin::Ui::Contract`.
- [ ] **Step 3: Implement** the two modules, the support module and the five declarations. A declaration sits under the class comment, and its `accessibility:` is one sentence: role, name, keyboard.
- [ ] **Step 4: Run** the two files, then `test/lib/source_layout_test.rb test/lib/admin_namespace_shadow_test.rb`, then `bin/rails zeitwerk:check`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep over the changed files. Check `pgrep`. Commit `feat: a shared component declares its contract, and a shared test holds it` (body: `Advances #117`).

---

### Task 2: Every Admin::Ui component declares its contract

**Files:**
- Modify the other 38 `app/components/admin/ui/*_component.rb`: one `contract(...)` each, from reading the component, its template, its test and its keys.
- Modify `test/support/ui_contract.rb`: `UNDECLARED` goes, and so does its test in `contract_test.rb`. The first test is renamed `test "every Admin::Ui component includes the contract and declares it"`.
- Interface mismatches found are fixed in the declaration, never by changing a component's signature.

- [ ] **Step 1: Make the test red for every component.** Delete `UNDECLARED` and its test. Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/contract_test.rb`. Expected: FAIL, naming 38 components.
- [ ] **Step 2: Declare each.** `states:` are those a static render draws: a chip's statuses, a save status's `idle saving saved error stale held saved_over offline retrying signed_out forbidden` (each is drawn by an argument), `rest`, and the pointer states where it is pressable. A state only a script reaches (a dialog's `open`, a menu's `open`, a toast's `dismissed`) goes in `script_states:` with the existing browser test that holds it (for a dialog, `test/system/dialog_test.rb`; the implementer names the test by reading the file).
- [ ] **Step 3: Run** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/components/previews_test.rb test/lib`. Expected: PASS.
- [ ] **Step 4: Comments and commit.** Run the comment grep over the changed files. Most of them carry a "design pass spec §" line: rewrite those lines. Check `pgrep`. Commit `feat: every shared component declares its contract` (body: `Advances #117`).

---

### Task 3: The part guards: a test, a preview per state, a Design System entry, a keyboard test

**Files:**
- Create `test/support/design_system_entries.rb` (`module DesignSystemEntries`; `ENTRIES`, `COVERED_BY`, `NOT_YET`).
  - `ENTRIES` is the 69 folder names of the artifact's `project/components/`, copied from the artifact's file listing (the controller hands the list to the implementer). The comment gives the artifact version as a provenance stamp, and says the list is updated by hand.
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
  - `test "every Admin::Ui component has a Design System entry, or is listed with the reason it has none"`.
  - `test "the entries' lists name only components and entries"`: a stale `COVERED_BY` or `NOT_YET` key fails, and so does a `COVERED_BY` value not in `ENTRIES`.
  - `test "a shared component made after the contract names its keyboard browser test, and the test is there"`. A component in `KEYBOARD_NOT_YET` is let through.
  - `test "the keyboard not-yet list names only components that declare no keyboard test"`.
  - `test "the made-before list names only components"`.
  - `test "each part guard can fail"`. Run each guard's matcher over a sample: a fake component name with no test file, a states list with an example missing, a name with no entry. Each must be reported.
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/lib/component_parts_test.rb`. Expected: FAIL, naming the 3 tests, the 10 previews and the examples that are missing.
- [ ] **Step 3: Implement** the lists, the tests and the previews.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/lib test/components`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `test: every shared component has a test, a preview of each state and a Design System entry`.

---

### Task 4: The public contract, read against the theme contract

**Files:**
- Create `app/components/blocks/contract.rb`: `Blocks::Contract` on `ComponentContract`, with `contract(words:, **common)`. Its comment says that `Posts::` components include it too, that a gem's component may, and that it changes nothing a template sees.
- Modify the built-in public components the ledger lists (`ContractLedger::COMPONENTS`: nine blocks, five form inputs, four post components) to include it and declare.
  - `interface:` is the ledger's line for the component.
  - `words:` is the `public.*` keys it reads (`Blocks::CodeComponent#string`'s four, the form's, `site_string`'s through `PublicStrings.read`).
- Create `test/values/theme/component_contract_test.rb`.

- [ ] **Step 1: Write the failing tests:**
  - `test "every built-in component a theme may replace declares the public contract"`. These are the keys of `ContractLedger::COMPONENTS`, constantized.
  - `test "a component that declares the public contract is one a theme may replace"`. Scan `app/components/{blocks,posts}` for `include Blocks::Contract`. Each must be in `Theme::Contract.components`.
  - `test "a public component's interface is its line in the theme contract"`.
  - `test "a public component's words are the public keys its own files read, and each exists in English"`.
    - The keys read are found in the component's `.rb` and its default template: `string(:x)` and `fixed_word(:x, scope: "…")` with the file's own `scope:` literal, `site_string(:x)` (`public.site.x`) and `PublicStrings.read("…")` with a literal.
    - A read with an interpolated key (`"public.blocks.note.kinds.#{kind}"`) is matched by a declared prefix entry (`public.blocks.note.kinds.*`).
    - Each key found is declared, each declared key or prefix is found, and each declared key resolves in `config/locales/public.en.yml`. So `[]` fails where the files read a word, and so does drift.
  - `test "the public contract can fail"`. A declaration with an interface that drops a method, one with a word the files do not read, and one that leaves out a word they do, are each reported by name.
  - The tokens are not held per component (decisions table). `theming.md` says so under its "Rules a change can break silently" (Task 5).
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
  - `MADE_BEFORE_CONTRACT`, `KEYBOARD_NOT_YET` and the keyboard rule;
  - `states:` against `script_states:` (a static render against a script, and the browser test that holds the latter);
  - that `design_system_entries.rb` is a hand copy of the artifact's list;
  - the review checklist (FoundationComponentContract's "Review checklist", whole);
  - a line under "Rules a change can break silently": **no guard** checks a preview for content edges, or that a Design System entry's text says what the declaration says.
- Modify `docs/reference/theming.md`, "Block and post templates: `Theme#component_for`" (the paragraph that begins "So the replaceable components are exactly those"): a paragraph on `Blocks::Contract`, its test, and that the declaration is not part of what a theme sees. Under its "Rules a change can break silently": **no guard** holds a public component's tokens to its declaration, because its template draws through shared stylesheets. The theme's tokens are held by the ledger.
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

  Put it beside the other lengths, with a comment that says the step is the children list's 13px margin, its 1px guide and its 6px padding.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`. Add one `.admin-tree` block after the tree column's rules. `.admin-tree-row--selected` moves into it, so there is one block.
  - **The row.** `.admin-tree-row`: flex, centred, `min-height: var(--cs-tree-row)`, `padding-inline: 4px 8px`, `border-radius: var(--cs-radius)`, hover `--cs-sunken`. Its parts:
    - `__disclosure`: `width: var(--cs-tree-disclosure)`, the row's height, chevron `--cs-meta`, ink on hover, turned 90° when `[aria-expanded="true"]` (120ms `--cs-ease`, none under reduced motion). An empty box on a leaf. None under `.admin-tree-row--flat`.
    - `__mark`: `width: var(--cs-tree-mark)`, `margin-inline-end: 8px`, `--cs-meta`, ink when selected.
    - `__title`: `text-small` (13px / 20px), 400, ink, one line, truncated; `--cs-meta` when `--context-only`.
    - `__trailing`: inline-flex, `gap: 6px`, `margin-inline-start: 6px`.
    - `__count`: `text-count`, `tabular-nums`, `min-width: 14px`, right-aligned, `--cs-meta`.
  - **What rests hidden** (C10: the row carries no `group/node` utility any more). `.admin-tree-row__reveal` is visually hidden at rest by a clip in this block (never `sr-only` and never `hidden`, so a screen reader still hears it). It is shown when its row is `:hover` or `:focus-within`, under `@media (any-pointer: coarse)`, and on the selected row. `.admin-tree-row__count` takes it, and is also shown at rest on a folded parent (`.admin-tree-row:has(> .admin-tree-row__disclosure[aria-expanded="false"])`, and `[role="treeitem"][aria-expanded="false"] > .admin-tree-row`). The opacity parts ("+", the handle) take `.admin-tree-row__reveal-opacity`: opacity 0 at rest, 1 under the same conditions.
  - **The step.** `.admin-tree__children`: `margin-inline-start: 13px; border-inline-start: 1px solid var(--cs-line-strong); padding-inline-start: 6px`. The list also carries `data-tree-children`, a hook for the scripts and never a selector of this block.
  - **The handle** (C9). `.admin-tree-node__handle`, the name `tree_controller.js` already uses: `position: absolute; inset-block: 0; inset-inline-start: calc(-1 * var(--cs-tree-step)); width: var(--cs-tree-step)`, on `--cs-chrome`, `--cs-meta`, with `.admin-tree-row__reveal-opacity`. It is written here, read by Task 7.
  - **Focus.** On the row: `:has(:focus-visible)`, and `[role="treeitem"]:focus-visible > .admin-tree-row`, a 2px `--cs-accent` outline at −2px. The treeitem's own outline is none.
  - **Selection.** `.admin-tree-row--selected`: `background: var(--cs-sunken)`, `box-shadow: inset 3px 0 0 var(--cs-accent)`, and its title 600.
  - **The match.** `.admin-tree mark`: `background: var(--cs-accent-tint); color: inherit; border-radius: var(--cs-radius)`.
- Create `app/views/admin/shared/_tree_glyph.html.erb`, with `name:` `:chevron`, `:page` or `:home`. It draws the 12px chevron (stroke 1.6) and the 14px page and home glyphs (stroke 1.3), `aria-hidden`. `_icon.html.erb` is not changed: the glyphs are the tree's own sizes and strokes.
- Create `app/components/admin/ui/tree_item_component.{rb,html.erb}`, with its contract: `keyboard: nil`. Its keyboard test is written in Task 8 with the controller.
- Modify `test/support/ui_contract.rb`: `KEYBOARD_NOT_YET` gains `"Admin::Ui::TreeItemComponent" => "its disclosure folds by keyboard once its controller exists"` (C2). Task 8 removes the entry.
- Modify `config/locales/admin/ui.en.yml`: `tree_item.fold` "Fold %{title}", `tree_item.unfold` "Unfold %{title}". `opened` comes in Task 9 with its reader.
- Create `test/components/admin/ui/tree_item_component_test.rb` and `test/components/previews/admin/ui/tree_item_component_preview.rb`. The examples: `rest`, `selected`, `folded`, `open`, `leaf`, `context_only`, `flat`, `root`, `long_title` (a 60-character German title).
- Modify `test/support/design_system_entries.rb`: `COVERED_BY` gains `"Admin::Ui::TreeItemComponent" => "StudioTree"`.
- Modify `test/lib/admin_contrast_test.rb`: the regex of "the selected row's accent bar is 3:1 or better on its sunken ground and on the chrome" (line 84) pins a rule that holds only `box-shadow`. It becomes: the `.admin-tree-row--selected` rule contains `box-shadow: inset 3px 0 0 var(--cs-accent)` and `background: var(--cs-sunken)`, in any order (C11).
- Test: `test/lib/admin_design_rules_test.rb`, `test/lib/admin_contrast_test.rb`, `test/lib/component_parts_test.rb`, `test/components/admin/ui/contract_test.rb`, `test/lib/source_layout_test.rb`.

**Interfaces:**
- Produces `Admin::Ui::TreeItemComponent.new(id:, title:, parent: false, folded: false, controls: nil, selected: false, context_only: false, flat: false, root: false, path: nil, node_id: nil, data: {})`.
  - `id` is the row's DOM id. `path` becomes `data-tree-path` (the address for a "/" find). `node_id` becomes `data-tree-id` on the row (the bare page id, Task 8's DOM contract). `data` is merged onto the row: behaviour hooks only, and a `class` key raises `ArgumentError`.
  - Slots: `renders_one :handle`, `renders_one :mark` (default: the page glyph, or the home glyph when `root:`), `renders_one :title` (required, the link or the label, with `CLASSES[:title]` applied by the component around it; the link is the screen's and carries `data-tree-focus`), `renders_one :state`, `renders_many :trailing`.
  - The disclosure, drawn when `parent:` and not `flat:`, is a `<button type="button" class="admin-tree-row__disclosure" aria-expanded aria-controls=<controls> aria-label=<fold|unfold>>` with **no `data-action`**. Task 8 adds `data-action="admin--tree--disclosure#toggle"` with the controller, because `source_layout_test` fails on an identifier with no controller file (C1). The row carries `data-tree-row` and `data-tree-title` (the whole title, for find).
- Produces `TreeItemComponent::CLASSES` (frozen): `{ tree: "admin-tree", row:, row_selected:, row_context_only:, row_flat:, disclosure:, mark:, title:, trailing:, count:, reveal:, reveal_opacity:, handle: "admin-tree-node__handle", children: "admin-tree__children" }` (C7, C9, C10). Every value is a class of the `.admin-tree` block, never a utility. Task 7 and Task 13 read it.

- [ ] **Step 1: Write the failing tests.**
  - `tree_item_component_test.rb`:
    - `test "only the selected row is semibold, and the selection is the class the tree's script moves"`
    - `test "a parent draws a disclosure button that names its branch and says whether it is open; a leaf keeps an empty column; a flat row has none"`
    - `test "a folded parent says so and controls its children's list"` (`aria-expanded="false"`, `aria-controls`)
    - `test "a context-only row is meta, with no link and no handle drawn by the screen"`
    - `test "the root draws the home glyph and other rows the page glyph, both hidden from a screen reader"`
    - `test "the slots are drawn in their order: handle, disclosure, mark, title, state, trailing"`
    - `test "a screen cannot hand the row a class"`
    - `test "every CLASSES value is a class of the .admin-tree block"`. Each value is found as a class selector in `content-spiel.tailwind.css`, comments stripped.
  - `admin_design_rules_test.rb`:
    - `test "a tree's geometry is its four tokens, written once"`.
      - Each `--cs-tree-*` is defined once, on `:root`, in `content-spiel.css`.
      - The `.admin-tree__children` rule's margin, guide and padding are read as pixels, and their sum equals `--cs-tree-step`'s value (C6: 13 + 1 + 6 = 20, so a changed step or a changed padding fails).
      - No `ml-`, `pl-`, `padding-inline-start` or `paddingInlineStart` stands in `app/components/admin/pages_screen/tree_*`, `app/components/admin/ui/tree_item_component.*` or `app/javascript/mind_graph/node_list.js`, **comments stripped** (`<%# %>`, `#`, `//` and `/* */`; C3).
    - `test "the match's tint is the tree's own rule, with the title's ink"`. Assert the `.admin-tree mark` rule uses `--cs-accent-tint` and `color: inherit`. No `bg-accent-tint` utility stands in the tree files, named in `TREE_FILES` (the four `pages_screen/tree_*` components, `tree_item_component.*`, `tree_find_component.*` once it exists, and `node_list.js`; C4).
    - Both tests let through `TREE_RULES_NOT_YET = { "app/components/admin/pages_screen/tree_node_component.html.erb" => "the Pages rows are not on the shared row yet", "app/javascript/mind_graph/node_list.js" => "the graph's list is not on the shared row yet" }` (C5: each value is a reason, never a task number). Task 7 deletes the first entry, and Task 13 the second with the constant. Its staleness test is `test "a tree-rules exception that no longer breaks a rule fails"`.
    - `test "the tree's rules are one block"`: `.admin-tree-row--selected` is defined once, inside the block.
  - `admin_contrast_test.rb`:
    - `test "a tree's guide stays a hairline: --cs-line-strong on the chrome is under 3:1 in both schemes"`
    - `test "a tree's disclosure, mark and count read on the chrome and on sunken: 4.5:1 or better in both schemes"` (`--cs-meta` and `--cs-ink`)
    - The selected-bar test with its new regex (above).
    - `test "a match's tint keeps the title's ink at 4.5:1 or better in both schemes"` (14.5 / 11.4:1 expected)
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/tree_item_component_test.rb test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** The component has no script of its own, and no controller is named in its markup until Task 8.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. Expected: PASS, `source_layout_test.rb` and `component_parts_test.rb` included.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the shared tree row, its four lengths and the .admin-tree block`.

---

### Task 7: Pages rows on the shared row; the tree's words in keys

**Files:**
- Modify `app/components/admin/pages_screen/tree_row_component.{rb,html.erb}`. The row renders through `TreeItemComponent`:
  - `id: dom_id`, `title:`, `parent: child_count.positive?`, `folded: false` (Task 8 reads the open set), `controls: "tree-children-#{page.id}"`, `selected: selected?`, `context_only:`, `root: root?`, `node_id: page.id`, `path: <the page's public path in the editing language, nil without one>`, `data: { "admin--pages--tree-target": "row", "page-id": page.id }` (not on a context-only row).
  - Slots: `with_handle` (the "⠿" button, unchanged in behaviour, with `CLASSES[:handle]` and its rule from Task 6 in place of `absolute inset-y-0 -left-4 w-4 … group-hover/node:opacity-100`), `with_title` (the link with `data-tree-focus`, or the context-only span), `with_state` (`TreeStateMarkComponent`), and `with_trailing` for the translation markers, the `tree.row.markers` slot, the count (`CLASSES[:count]` with `CLASSES[:reveal]`, `data-child-count`) and "+" (`CLASSES[:reveal_opacity]`).
  - "+" is shown on any coarse pointer by the block's `@media (any-pointer: coarse)` rule, in place of `pointer-coarse:opacity-100`.
  - `SELECTED_CLASS` becomes `TreeItemComponent::CLASSES[:row_selected]`. `SELECTED_TITLE_CLASS` goes, because the block's selected rule sets the weight.
  - `MARKER_AT_REST` becomes `TreeItemComponent::CLASSES[:reveal]` (C10): the `group-hover/node:` and `group-focus-within/node:` utilities have no `group/node` to read once the row is the shared row. The selected row shows its markers through the block's rule, so `mark()` keeps toggling the class as it does today.
  - The public path comes from a new read, `PageTree.paths(ids, locale:) -> Hash{Integer => String}`, in `app/queries/page_tree.rb`. It is one statement over `PublicPath`, for the pages' rows in the editing language. Its line says what it answers. `TreeComponent` calls it once for the readable rows, and `for_page` calls it once for its page. Test: `test/queries/page_tree_test.rb`, `test "paths are each page's address in the language, in one statement"`.
  - The class comment is rewritten under the comment rule.
- Modify `tree_node_component.{rb,html.erb}`. The children `<ul>` carries `id="tree-children-<id>"`, `data-tree-children` and `CLASSES[:children]`, in place of `ml-2 … border-l border-line pl-[7px]`. The `<li>` carries `data-tree-node`.
- Modify `tree_component.{rb,html.erb}`, converted to keys whole:
  - `tree.heading` "Pages", `.new_page` "+ New page", `.more_actions` "More page actions", `.starter_pages` "Create starter pages", `.drag_help`, `.empty` "No pages yet.".
  - The frame gains `data-messages` with `components.pages_screen.tree.moves.{picked_up,dropped,position,cancelled}` and `components.pages_screen.tree_row.untitled`.
  - The `admin--pages--tree-selected-title-class` attribute goes.
  - The `<ul>` root, which already carries `.admin-tree`, gets `id="tree-list"`. It is "the tree" of the decisions table (C12).
- Modify `app/javascript/controllers/admin/pages/tree_controller.js`:
  - The announcements read `messages(this.element).t("components.pages_screen.tree.moves.picked_up", { title, position })` etc.
  - `titleOf` falls back to `tree_row.untitled`, and reads `[data-tree-title]`.
  - `focusHandle` and `titleOf` find their parts by `[data-tree-row]`, not `:scope > div`.
  - The `selectedTitle` class goes.
- Modify `config/locales/admin/pages_screen.en.yml` with the keys above.
- Modify `test/lib/admin_design_rules_test.rb`: `TREE_RULES_NOT_YET` loses its `tree_node_component.html.erb` entry.
- Create `test/components/previews/admin/pages_screen/tree_row_component_preview.rb`. The examples: rest, selected, context-only, draft, scheduled, changes, markers, a long German title.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `tree_component.rb`, `tree_component.html.erb` and `tree_controller.js`.
- Create `test/queries/page_tree_test.rb` (the `paths` test above).
- Test: `test/components/admin/pages_screen/tree_component_test.rb`, `test/components/admin/pages_screen/tree_row_component_test.rb`, `test/integration/admin/pages_tree_row_test.rb`, `test/lib/script_messages_test.rb`, `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/admin/tree_column_test.rb`.

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
  - `test/system/tree_test.rb` (the keyboard drag file): `test "a picked-up row is announced in the page's words"`. Use German strings stored for the four `moves` keys in the test, `visit_screen`, pick up with Space, and assert the announcer's text.
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/components/admin/pages_screen test/lib/admin_i18n_test.rb`.
- [ ] **Step 3: Implement.** Search the tests and `app/` by hand for `ml-2`, `pl-[7px]`, `SELECTED_TITLE_CLASS`, `selectedTitle`, `:scope > div`, `"Pages"` near the tree, `Picked up`, `Dropped`, `Position ` and `No pages yet.`, and fix each hit in this task.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib test/queries/page_tree_test.rb test/integration/admin/pages_tree_row_test.rb test/integration/admin/tree_test.rb`. Then build, and run one at a time: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/admin/tree_fold_test.rb`, `test/system/admin/presence_lists_test.rb`, `test/system/admin/drafts_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. `tree_row_component.*` and `tree_component.*` carry "T2", "handoff §10" and "Claude Design, 2026-10-13". Check `pgrep`. Commit `feat: the page tree's rows are the shared row, and its words are keys` (body: `Advances #117`).

---

### Task 8: Folding and the open set

**Files:**
- Create `app/values/tree_open_set.rb`:
  - `TreeOpenSet::COOKIE = "cs_tree_open"`, `LIMIT = 300`, `MAX_BYTES = 4_096`.
  - `TreeOpenSet.parse(raw, readable_ids:) -> TreeOpenSet`.
  - `#open?(id, root:, on_path:) -> Boolean`, by the rule in the decisions table (the path first: C14).
  - `#to_s -> String`, the normalised value, read by the graph in Task 14.
  - `TreeOpenSet::EMPTY`.
- Modify `TreeComponent`, `TreeNodeComponent` and `TreeRowComponent`:
  - `TreeComponent.new(..., open_cookie: nil)` takes the raw cookie and parses it in `load_visible`, with the `visible_ids` it already computes (C15). It works out the selected page's ancestor ids once, from `children_by_parent`.
  - Each node gets `folded: !open_set.open?(page.id, root:, on_path:)`. A folded node's children `<ul>` is `hidden`, and its `<li>` carries `data-folded`. The root's `<li>` carries `data-tree-root`, and each ancestor of the selected page carries `data-tree-on-path`.
  - `TreeRowComponent.new(..., folded: false)` and `for_page(page, selected:, locale:, url_options:, open_cookie:)`. `for_page` parses the cookie with the page's id and `page.ancestor_ids` as `readable_ids`, and reads those ancestors for `on_path`.
- Modify every caller of `TreeComponent.new` and `for_page` (`grep -rn "TreeComponent.new\|for_page(" app`: `app/views/admin/pages/_tree.html.erb`, `Admin::PagesController#tree_row_stream`, `Admin::TreeController#update`'s redraw). Each passes `open_cookie: cookies[TreeOpenSet::COOKIE]`.
- Modify `app/components/admin/ui/tree_item_component.html.erb`: the disclosure gains `data-action="admin--tree--disclosure#toggle"` (C1).
- Modify `test/support/ui_contract.rb` and `tree_item_component.rb`: `KEYBOARD_NOT_YET` loses `TreeItemComponent`, which declares `keyboard: ["test/system/admin/tree_test.rb", "a row's disclosure folds and unfolds its branch by mouse and by keyboard"]` (C2).
- Create `app/javascript/tree/open_set.js`, the cookie's one writer:
  - `readOpenSet(seed = null) -> { opened: Set<string>, folded: Set<string> }`. It reads `seed` (a string in the cookie's format: the graph's `data-tree-open`, Task 14) when one is given, else the cookie.
  - `setOpen(tree, id, open, { openByDefault }) -> void`. Opening drops `id` from folded, and adds it to opened unless `openByDefault`. Folding is the mirror. It reads the cookie as it stands, then writes it.
  - `forgetFolds(tree, ids) -> void`.
  - It writes `cs_tree_open` with the path read from the tree's `data-tree-open-path`, `SameSite=Lax`, `max-age=31536000`, `Secure` on https, keeping the newest `LIMIT` entries.
  - `openPathIn(tree, id) -> void`, by the DOM contract below.
- Create `app/javascript/controllers/admin/tree/disclosure_controller.js` (`admin--tree--disclosure`), on the tree (`ul#tree-list`; C12).
  - `toggle(event)` sets the button's `aria-expanded` and its label (`fold`/`unfold` from `data-messages`), the `aria-controls` list's `hidden`, and the node's `data-folded`.
  - Alt+click opens the whole branch.
  - Each toggle a person makes is written through `setOpen`, with `openByDefault` true on a node with `data-tree-root` or `data-tree-on-path`.
  - It dispatches `tree:changed` on the tree after any toggle.
- Modify `app/javascript/controllers/admin/pages/tree_controller.js`:
  - `connect` (C14) and `follow` call `openPathIn(tree, openPageId)`, which also forgets the folds on that path. They then scroll the selected row into view inside `#tree-column` (its `scrollTop`, as `node_list.js`' `mark` does), never with `scrollIntoView`.
  - `rowTargetConnected` dispatches `tree:changed` on the row's `.closest(".admin-tree")` (C12).
- Modify `tree_component.html.erb`:
  - `ul#tree-list` gains `data-controller="admin--tree--disclosure"`, `data-tree-open-path="/<%= ContentSpiel::ADMIN_PATH %>"`, and `data-messages` with `components.ui.tree_item.{fold,unfold}`.
  - The constant is `"cs-studio"` without a slash, so the slash is written here.
- Modify `test/system/tree_test.rb` (C25). Its tests that pick up a page two levels down ("ArrowRight nests a page under the one above and ArrowLeft moves it out again", "ArrowLeft moves a nested page out one level, after its old parent") first open that page's branch through its disclosure, by mouse.
- Modify `test/lib/admin_design_rules_test.rb` (below) and `test/lib/admin_i18n_test.rb` (`CONVERTED` gains `open_set.js` and `disclosure_controller.js`).
- Create `test/values/tree_open_set_test.rb`.
- Test: `test/components/admin/pages_screen/tree_component_test.rb`, `test/components/admin/pages_screen/tree_row_component_test.rb`, `test/integration/admin/pages_tree_row_test.rb`, `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`.

**Interfaces:**
- Produces `TreeOpenSet` (above) and `open_set.js` (above), used by Tasks 9, 10, 14 and 15.
- **The tree's DOM contract** (C20), held by both trees and read by `openPathIn`, `find.js` and the disclosure controller:
  - The tree is the element with `.admin-tree` that `aria-controls` names. It carries `data-tree-open-path` and `data-tree-locale`.
  - A node is `[data-tree-node]`. Its row is `[data-tree-row][data-tree-id=<bare page id>][data-tree-title]`, and `[data-tree-path]` where it has an address. Its children list is `[data-tree-children]`.
  - A node's parent is the closest `[data-tree-node]` above it. The root node carries `data-tree-root`, and the selected page's ancestors carry `data-tree-on-path`.
  - The element holding `aria-expanded` is the node itself when it is a `[role="treeitem"]` (the graph), else its row's `.admin-tree-row__disclosure` (Pages).
  - The element find focuses is `[data-tree-focus]`.

- [ ] **Step 1: Write the failing tests.**
  - `tree_open_set_test.rb`:
    - `test "an opened id opens a branch the default folds, and a folded one folds the root"`
    - `test "the path to the selected page is open whatever the folds say"` (C14)
    - `test "junk, an id the viewer does not read, a value over 4KB and entries past the limit set nothing"`: `"abc.12x.-"`, `"999999"` not readable, `"1." * 3000`.
    - `test "to_s gives back only what it kept, in its order"`
  - `tree_component_test.rb`:
    - `test "Home is open and its children shown; every deeper branch is folded, with hidden children"` (C35)
    - `test "the open path to the selected page is drawn open, even under a folded ancestor"` (C14)
    - `test "the cookie's opens and folds are honoured, and junk in it is ignored"`
  - `tree_row_component_test.rb`: `test "for_page draws the disclosure from the open cookie handed in, folded or open"` (Review Focus 1).
  - `pages_tree_row_test.rb` (integration): `test "a settings save's row answer reads the open set from the cookie"`. Send the cookie, save, and assert the stream's row has `aria-expanded="false"`. The file's statement-count test still passes: `PageTree.paths` and `ancestor_ids` add a fixed number.
  - `admin_design_rules_test.rb`: `test "the open set has one writer"`. Comments are stripped first (C37).
    - `document.cookie` appears in `app/javascript` only in `tree/open_set.js`.
    - `cs_tree_open` appears in `app/javascript` only there, and in Ruby only in `tree_open_set.rb`.
    - No Ruby line writes a cookie that names `cs_tree_open` or `TreeOpenSet::COOKIE` (`cookies[…] =`, `cookies.permanent[…] =`, `cookies.delete`). The session cookie's write in `authentication.rb` names neither, and is not matched.
    - The test's own samples are each reported: a script line `document.cookie = "x"` in another file, and a Ruby line `cookies[TreeOpenSet::COOKIE] = "1"`.
    - "the tree's width and fold are written by the head script and the tree-width controller alone" still passes.
  - `test/system/admin/tree_test.rb` (`visit_editor` on a page two levels down):
    - `test "a row's disclosure folds and unfolds its branch by mouse and by keyboard"`: click; then Tab to it and Enter, then Space; check `aria-expanded`, the list's `hidden` and the label "Unfold …".
    - `test "a fold is kept across a reload and a Turbo visit, drawn folded from the first paint"`. After the reload, assert the first `turbo:load` already finds the branch `hidden` (a `MutationObserver` installed by `page.driver.browser.evaluate_on_new_document` records any change of the list's `hidden`, and finds none).
    - `test "a full load of a page under a folded ancestor draws its path open and its row selected, and the fold is forgotten"` (C14). Fold the open page's grandparent, reload, assert the row is visible and selected, and that the cookie no longer folds the grandparent.
    - `test "Alt+click opens the whole branch"`
    - `test "Back to a page whose branch was folded opens its path and selects its row, scrolled into the column"` (extends "Back to a page opened from the tree…"). The column's `scrollTop` changed, and the window's `scrollY` did not.
    - `test "a folded parent shows its subpage count at rest"`
- [ ] **Step 2: Run, and verify they fail.** Run `PGGSSENCMODE=disable bin/rails test test/values/tree_open_set_test.rb test/components/admin/pages_screen test/integration/admin/pages_tree_row_test.rb test/lib/admin_design_rules_test.rb`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the unit tests above and `test/lib`. Then build, and run one at a time: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/admin/tree_fold_test.rb`, `test/system/admin/editor_header_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the page tree's branches fold, and a person's folds are kept in a cookie`.

---

### Task 9: Folding and moving

**Files:**
- Modify `app/javascript/controllers/admin/pages/tree_controller.js`:
  - SortableJS `onMove(event)` starts a timer of `OPEN_ON_HOVER_MS = 600` when `event.related` is a folded node's row. The timer is cancelled when the row changes, and on `onEnd`. When it runs out, the node unfolds through `setOpen` and takes `.admin-tree-drop-target` while the row is over it.
  - `save(item, list, index, origin)`, the one place a move is sent, first writes `setOpen(tree, list.dataset.parentId, true, { openByDefault })` for the list's parent (C13). So the move's redraw draws the new parent open, whether it had children before or not: a hover-opened parent, a page the drop made a parent, and a `nest()` into a childless sibling alike.
  - `nest(row)`: when the sibling above is folded, it unfolds it the same way first, then announces `messages.t("components.ui.tree_item.opened", { title })`, followed by the position.
  - Every Sortable stays created for every list, hidden ones too. The tests prove a hidden list that becomes visible takes a drop.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`, inside the `.admin-tree` block: `.admin-tree-drop-target > .admin-tree-row` is `--cs-sunken` with `box-shadow: inset 0 0 0 1.5px var(--cs-field-line)`.
- Modify `config/locales/admin/ui.en.yml`: `tree_item.opened` "Opened %{title}." Modify `TreeItemComponent`'s contract `keys:` to add `opened`. The tree's `data-messages` gains it.
- Test: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`.

- [ ] **Step 1: Write the failing tests.**
  - `test/system/admin/tree_test.rb`:
    - `test "dragging a page over a folded parent opens it after a moment, and the page drops among its children"`. The drag uses Cuprite's mouse with steps, as "dragging a page onto another node…" does. Wait for the list not to be `hidden` (`assert_eventually`), then drop. Check the database and the tree.
    - `test "a page dropped into a parent that hovering opened is shown there after the tree is redrawn"` (Review Focus 2). After the move's stream replaces `#tree`, the parent is `aria-expanded="true"` and the moved row is visible. The cookie holds the parent's id.
    - `test "a drag that leaves a folded parent before the moment does not open it"`
    - The existing drag tests pass unchanged on an unfolded path. Each one that drops into a deeper branch opens it first through the disclosure, by mouse.
  - `test/system/tree_test.rb`:
    - `test "moving a page right into a folded sibling opens it and says so"`. Keyboard: Space, →. The announcer starts with "Opened <title>.", the sibling is open, and Space drops.
    - `test "a page moved into a page with no children is shown under it after the tree is redrawn"` (C13). With the keyboard (Space, →, Space) under a childless sibling: after the stream, the sibling is a parent with `aria-expanded="true"`, and the moved row is visible. Without the write in `save`, the redraw folds the new parent and the test fails.
- [ ] **Step 2: Run, and verify they fail** (after a build): the two files.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** one at a time: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb` (its Undo test included). Also `test/lib/editing_tab_header_test.rb` (the move's send is unchanged). Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: a folded branch opens under a dragged page, and a moved page's new parent stays open`.

---

### Task 10: The find field, on the Pages tree

**Files:**
- Create `app/components/admin/ui/tree_find_component.{rb,html.erb}`, with its contract:
  - `states: %i[rest]` (the one a static render draws) and the pointer state `focus`.
  - `script_states: { filled: ["test/system/admin/tree_find_test.rb", "typing narrows the tree to matches and their paths, marks them, and Escape gives back the person's folds"], filtered: [same], no_match: ["test/system/admin/tree_find_test.rb", "no match says No pages match, and no tree is shown"] }` (C17).
  - `keys:` its ten leaves: `label`, `placeholder`, `count` and `none`, each for `pages` and `nodes`, then `no_moving` and `clear` (C18).
  - `controller: "admin--tree--find"`.
  - `keyboard: ["test/system/admin/tree_find_test.rb", "/ focuses the field, Down Arrow reaches the first match, Enter opens it"]`.
  - Its markup:
    - `div[role=search]`, then a real `label.sr-only`, then `input[type=search]` (`.admin-well`, 32px, magnifier, `aria-controls`, `aria-keyshortcuts="/"`, `autocomplete="off"`).
    - The `/` hint (`text-count`, a `--cs-line-strong` edge, `rounded-cs`) while it is empty, and Clear (`ButtonComponent`, `icon: :x`, `:tertiary`, `size: :small`) while it holds text. Both are toggled by the controller through `hidden`.
    - The status line `p[role=status][aria-live=polite]` (`text-small text-meta`, the figure in `text-dim` 500).
    - `data-messages` with its own keys.
- Create `app/javascript/tree/find.js`:
  - `normalise(text, locale)`: NFD, combining marks dropped, `toLocaleLowerCase`.
  - `matchesTitle(title, query, locale)` and `matchesPath(path, query)`, used when the query starts with "/".
  - `filterTree(tree, query, { locale }) -> { count }`, over the DOM contract of Task 8:
    - a node is shown when it or a descendant matches, else `hidden`;
    - a branch holding a match is shown open (its children list un-`hidden`, its `aria-expanded` element `true`, its node `data-filter-open`), never through the open set;
    - the matched part of `[data-tree-title]`'s text is wrapped in `<mark>` built with `textContent` only.
  - `clearFilter(tree)`: it takes back every `hidden` and every `<mark>` the filter wrote, and gives each branch the state of `readOpenSet()` and the path (through `openPathIn`).
- Create `app/javascript/controllers/admin/tree/find_controller.js` (`admin--tree--find`):
  - The tree is `document.getElementById(field.getAttribute("aria-controls"))` (C12). Its `data-tree-locale` is the language to match in.
  - `input` filters at once. The status line's words are written 300ms after the last keystroke ("%{count} pages match", "No pages match"). With `moving`, it adds the `no_moving` sentence while the filter is on.
  - It dispatches `tree-find:filtered` and `tree-find:cleared` on the tree, and listens for `tree:changed` on the tree, which applies the current query again.
  - "/" on `keydown@document`, unless the target is an `input`, `textarea`, `select`, `[contenteditable]` or inside a `dialog[open]`, a modifier is held, or the field is not visible.
  - **Down Arrow and Enter, for both trees** (C22). Down focuses the first visible match's `[data-tree-focus]`; where that is a `[role=treeitem]` it first moves the tree's roving `tabindex="0"` to it. Up Arrow from the first match goes back to the field. Enter calls `.click()` on the first match's `[data-tree-focus]`. Nothing else in either screen handles these keys for find.
  - Escape on a non-empty field: `preventDefault` and `stopPropagation`, then clear, `clearFilter`, the focus stays in the field, and the selected row is scrolled back inside the column. On an empty field Escape is not taken.
  - `turbo:before-cache@document` clears the field, its hint, its status line and the filter. It is the one writer that cleans the field (C34).
- Modify `app/components/admin/pages_screen/tree_component.html.erb`: `TreeFindComponent.new(controls: "tree-list", noun: :pages, moving: true)` stands under the head and above `#tree-status`. `ul#tree-list` gains `data-tree-locale` (the editing language).
- Modify `app/javascript/controllers/admin/pages/tree_controller.js`. On `tree-find:filtered`, which bubbles from the tree to the frame:
  - every Sortable takes `option("disabled", true)`;
  - the tree, `ul#tree-list.admin-tree`, takes `data-filtered` (C8);
  - `key()` refuses a pick-up.

  On `tree-find:cleared` they come back.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`, inside the `.admin-tree` block: `.admin-tree[data-filtered] .admin-tree-node__handle { display: none }`, which takes the handles out of the page and of the Tab order.
- Modify `config/locales/admin/ui.en.yml`. It gains `tree_find.*`, with the words of the decisions table. The node words are design answer Q3: "Find a page, post or tag", "1 match" / "%{count} matches", "Nothing matches".
- Modify `test/support/design_system_entries.rb` (`COVERED_BY` `"Admin::Ui::TreeFindComponent" => "StudioTree"`), `test/lib/admin_design_rules_test.rb` (`TREE_FILES` gains `tree_find_component.*`) and `test/lib/admin_i18n_test.rb` (`CONVERTED` gains `find.js`, `find_controller.js` and the component).
- Create `test/components/admin/ui/tree_find_component_test.rb`, `test/components/previews/admin/ui/tree_find_component_preview.rb` (the example `rest`), and `test/system/admin/tree_find_test.rb`.
- `find.js`' matching test goes into `tree_find_test.rb` as one module test: `import("tree/find")` in the browser from the editor, the pattern `test/system/admin/editor_modules_test.rb` uses, since the project has no JavaScript test runner.

**Interfaces:**
- Produces `Admin::Ui::TreeFindComponent.new(controls:, noun: :pages, moving: false)` (`NOUNS = %i[pages nodes]`) and `admin--tree--find`, with the events above. Task 15 renders it with `noun: :nodes` and `controls: "mind-graph-tree"`.
- Produces `tree/find.js`' `normalise`, `filterTree` and `clearFilter`. Task 15's graph uses them through the same controller.

- [ ] **Step 1: Write the failing tests.**
  - `tree_find_component_test.rb`:
    - `test "a search landmark with a real label, aria-controls naming the tree and / as its shortcut"`
    - `test "the nouns pick their words"`
    - `test "Clear the search to move pages is offered only where the tree moves"`
  - `test/system/admin/tree_find_test.rb` (`visit_editor`):
    - `test "typing narrows the tree to matches and their paths, marks them, and Escape gives back the person's folds"`. A branch that was folded is shown during the filter and folded again after. The cookie is unchanged by the filter.
    - `test "no match says No pages match, and no tree is shown"`
    - `test "drag is off while filtered and the line says why"`: no handle is in the page, Space on a row's link picks nothing up, and the line holds "Clear the search to move pages". "+" is still there.
    - `test "/ focuses the field, Down Arrow reaches the first match, Enter opens it"`
    - `test "the count is said once, after the typing stops"`. The status line's text changes once for "trans" typed one key at a time, by a `MutationObserver` count.
    - `test "a page saved while the tree is filtered keeps its row filtered and marked"` (Review Focus 1). Filter, change the open page's title in its settings so it still matches, and wait for SAVED. The redrawn row has its `<mark>`, and the hidden rows stay hidden.
    - `test "Back after a find shows the whole tree, an empty field and no marks"` (Review Focus 3)
    - `test "a slash typed into a field or the rich-text body stays a slash, and Escape in the empty field closes the drawer"` (Review Focus 4). Type "/" in the title field and in a rich-text block: the value holds "/", and the find field is not focused. At 900px, open the drawer, focus the empty field, and press Escape: the drawer closes.
    - `test "a title with markup is marked as text"` (Review Focus 5)
    - The module test: `test "matching ignores case and accents, finds a part anywhere, and matches the address only after a slash"` (Review Focus 5). `normalise("Über uns")` contains `normalise("uber")` and `normalise("ÜBER")`. "/install" matches the path `/docs/install` and not a title "install". "page" matches no address.
- [ ] **Step 2: Run, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. Then build, and run one at a time: `test/system/admin/tree_find_test.rb`, `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/command_palette_test.rb` (⌘K unchanged), `test/system/admin/editor_fields_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: a find field narrows the page tree to the matches and their paths`.

---

### Task 11: 5d-1's reference, CLAUDE.md and the pull request

**Files:**
- Modify `docs/reference/design-system.md`. Add a part "Tree":
  - the row and its slots, `CLASSES`, the four lengths and the step;
  - parents never bolder, the selection, the match as the tint's fourth named use;
  - the two semantics, and why Pages is never `role="tree"`;
  - folding and the open set, its one writer, and the path as a view state;
  - find and drag off while filtered;
  - one sentence on where find would move (C16): it runs on the client over the drawn rows, because the tree draws every readable page. Above about 2,000 pages, the cost of drawing the tree at all, a find would ask the server instead (a read-scoped endpoint on `Admin::TreeController`, trashed pages hidden, answering ids and their ancestors). It is not built, because no site is near that size. No constant holds the figure.

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

Before dispatch: Q5 (the divider's words on the graph's column).

**Files:**
- Create `app/components/admin/shell/tree_subjects.rb`. `Admin::Shell::TreeSubjects::ALL = { "pages" => { fill: false }, "mind_graph" => { fill: true } }` and `.fetch(name)`, which raises on an unknown subject.
- Create `app/components/admin/shell/tree_hide_component.rb` (the head's button, moved out of `tree_component.html.erb` whole, reading `tree_subject.<subject>.hide`). Create `test/components/admin/shell/tree_hide_component_test.rb`.
- Modify `app/components/admin/shell/tree_fold_component.rb`: `new(subject:)`, which reads `tree_subject.<subject>.show`.
- Modify `app/components/admin/shell/tree_divider_component.rb`: `new(subject:)`. Its name and tooltip read `tree_subject.<subject>.width` and `.width_tooltip`. Pages keeps "Page tree width" and "Tree width %{width}px. Arrow keys to resize."; the graph's are Q5's answer (default "List width" and "List width %{width}px. Arrow keys to resize.").
- Modify `app/components/admin/shell/top_bar_component.{rb,html.erb}`, converted to keys whole: "Open navigation", "Jump to…", and the tree button (`.open` as its name, `.button` as its words) per subject. `TopBarComponent.new(tree:)` takes the subject or nil. Its comments are rewritten for two screens (C36).
- Create `app/helpers/admin/shell_helper.rb` with `admin_tree_subject -> String`: `content_for(:tree_label).presence || "pages"`, through `TreeSubjects.fetch`.
- Modify `app/views/layouts/admin.html.erb`:
  - the aside gains `admin-shell__tree--fill` when the subject fills;
  - the subject goes to the top bar, the fold strip and the divider;
  - its comment "content_for :tree is never set outside" Pages is rewritten: the column holds what a screen puts in `content_for :tree`, today the Pages tree and the mind graph's list (C36).
- Modify `app/components/admin/pages_screen/tree_component.html.erb` (renders `TreeHideComponent.new(subject: "pages")`).
- Modify `config/locales/admin/pages_screen.en.yml`: `tree.hide` goes, with its last reader.
- Modify `config/locales/admin/shell.en.yml`:
  - `tree_subject.pages.{hide,show,open,button,width,width_tooltip}`: "Hide page tree", "Show page tree", "Open page tree", "Pages ▾", and the divider's two.
  - `tree_subject.mind_graph.*`: "Hide list", "Show list", "Open list", "List ▾" (design answer Q2), and Q5's two.
  - `top_bar.*`.
  - `tree_fold.show` and `tree_divider.{label,tooltip}` are deleted, with their last readers (C29).
- Modify `app/assets/tailwind/content-spiel.tailwind.css`: `.admin-shell__tree--fill`, from 1024px: `position: sticky; top: var(--admin-top-offset); height: calc(100vh - var(--admin-top-offset)); overflow-y: auto`.
- Modify `test/lib/admin_i18n_test.rb`: `CONVERTED` gains `top_bar_component.{rb,html.erb}`, `tree_subjects.rb` and `tree_hide_component.rb`.
- Test: `test/components/admin/shell/` (the fold, divider and top bar tests), `test/system/admin/tree_fold_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/shell_test.rb`.

**Interfaces:**
- Produces `Admin::Shell::TreeSubjects`, `TreeHideComponent.new(subject:)`, `TreeFoldComponent.new(subject:)`, `TreeDividerComponent.new(subject:)`, `TopBarComponent.new(tree: subject_or_nil)`, `admin_tree_subject` and `content_for :tree_label`. Task 15 sets `"mind_graph"`.

- [ ] **Step 1: Write the failing tests.**
  - `test "the fold buttons, the divider and the top bar's tree button say what the column holds"`, in the components: subject `mind_graph` reads its own words, and an unknown subject raises.
  - `test "the top bar's words are keys"`
  - `test/system/admin/tree_fold_test.rb`: "the fold buttons say what they control" reads the keys.
- [ ] **Step 2: Run, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for "Pages ▾", "Open page tree", "Open navigation", "Jump to…", "Page tree width" and `tree_fold.show`, and fix each hit in this task.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. Then build, and run one at a time: `test/system/admin/tree_fold_test.rb`, `test/system/shell_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/command_palette_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the tree column's fold words are the screen's, and the top bar's words are keys`.

---

### Task 13: The graph's rows on the shared row

Design answer Q1 applies (`.superpowers/sdd/design-answers-5d.md`). **This task is the look alone. The rows stay buttons in lists, and the semantics change in Task 14.**

**Files:**
- Modify `app/components/admin/mind_graph_screen/parts_component.{rb,html.erb}`: `NAMES` gains `tree-disclosure`, `tree-page-mark` and `tree-home-mark`, rendered from `admin/shared/_tree_glyph`. The disclosure part is an `aria-hidden` span, never a button (C23): in Task 13 it stands inside a row button, and in Task 14 inside a `treeitem`, which holds no control. The component's comment and its preview gain them.
- Modify `app/views/admin/mind_graph/show.html.erb`: `data-tree-classes="<%= Admin::Ui::TreeItemComponent::CLASSES.to_json %>"` on the graph's element.
- Modify `app/javascript/mind_graph/node_list.js`:
  - The root list takes `CLASSES.tree` (`.admin-tree`; C7).
  - `ROW`, `INDENT`, `ROW_PADDING` and `PILL_INDENT` go, and so does every `style.paddingInlineStart`.
  - A row is built from `classes` (handed in as `treeClasses`) and the parts:
    - in the disclosure box, a disclosure part on a page with children and on a hub with a pill, open, not foldable until Task 14;
    - in the mark box, a page mark part, or a post's dot, a tag's square, or a hub's canvas;
    - the title in `CLASSES.title`;
    - the chips under the title (unchanged);
    - the figure in `CLASSES.count`, at rest on every row.
  - A post, a tag and a type row is `CLASSES.row_flat` (no disclosure column).
  - A group heading row (Q1): 28px (`CLASSES.row`), the disclosure, its kind's icon chip (`:small`, cloned as today) in the mark box, the words `text-label` 500 `--cs-meta` with the figure after the middle dot as `text-count` (the existing `mind_graph.script.list.<group>` keys), 12px (`--cs-sp-3`) above every heading but the first, and no indent step: a level-2 row starts at the heading's left edge.
  - A page steps `--cs-tree-step` per depth below Home, as in Pages. A pill is its hub's child, one step in, flat, "+92 more" in `text-small` `--cs-accent` (Q1).
  - A page's and a hub's children go in a `ul` with `CLASSES.children` and `data-tree-children`.
  - The marked row takes `CLASSES.row_selected` in place of `aria-[current]:bg-accent-tint aria-[current]:font-semibold`, and keeps `aria-current` until Task 14.
- Modify `app/javascript/mind_graph/app.js`: it reads `data-tree-classes` and hands it to `createList`.
- Modify `test/lib/admin_design_rules_test.rb`: delete `TREE_RULES_NOT_YET` and its staleness test, so the geometry and tint tests read `node_list.js` with no exception.
- Create `test/system/admin/tree_item_parity_test.rb`.
- Test: `test/system/admin/mind_graph_list_test.rb`, `test/system/admin/mind_graph_card_and_list_modules_test.rb`, `test/lib/mind_graph_guards_test.rb`, `test/components/admin/mind_graph_screen/parts_component_test.rb` (its exact `NAMES` test changes here).

**Interfaces:**
- Consumes `TreeItemComponent::CLASSES` (Task 6). `createList(container, { …, treeClasses })` gains `treeClasses`.

- [ ] **Step 1: Write the failing tests.**
  - `tree_item_parity_test.rb`: `test "the Pages tree and the mind graph's list draw one row"`.
    - At 1600×900, measure a Pages row two levels down (`visit_editor`), then the graph's page row at the same depth (`visit_screen admin_mind_graph_path`, wait for `[data-settled]`).
    - Equal (±0.5px): the row's height, the step between a parent's and a child's mark, the title's computed `font-size`, `font-weight` and `color`, the mark's box, the selected row's `box-shadow` and `background-color`.
    - The test's first assertion runs its comparison over two samples that differ in height, and finds the difference.
  - `mind_graph_guards_test.rb`: `test "the graph's list writes no class of its own for a row: every row class is read from data-tree-classes"`.
    - Scan `node_list.js`' string literals for `px-`, `py-`, `text-sm`, `bg-accent-tint` or `font-semibold`.
    - The literals that lay out what is not a row (the unlisted filter's label, the Back button, the error line, the posts link, a heading's wrapper) stand in `LIST_LAYOUT_LITERALS`, each with its reason. Its staleness test fails on an entry the file no longer holds (C24).
    - It fails on any other match, and its sample, a row class written in a string, is reported.
  - `test "every data-tree-classes key the graph reads is one of CLASSES"`. Parse the keys `classes.<key>` read in `node_list.js`, and require them ⊆ `CLASSES.keys`.
  - `mind_graph_list_test.rb`: "in the list's column a row with two chips and a page three levels down each keep room for twenty characters…" keeps its figure at today's 300px column. Task 15 pins it to the tree's default width.
- [ ] **Step 2: Run, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/lib test/components/admin/mind_graph_screen`. Then build, and run one at a time: `test/system/admin/tree_item_parity_test.rb`, `test/system/admin/mind_graph_list_test.rb`, `test/system/admin/mind_graph_card_and_list_modules_test.rb`, `test/system/admin/mind_graph_drawing_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep (`node_list.js` carries "design answer H2", "G5", "H7"; each becomes the rule it names). Check `pgrep`. Commit `feat: the mind graph's list draws the shared tree row`.

---

### Task 14: The graph's list is an APG tree, folding with the shared open set

Design answer Q1 applies.

**Files:**
- Modify `app/javascript/mind_graph/node_list.js`, in one sweep:
  - The groups become one `ul#mind-graph-tree[role=tree].admin-tree` (C20), named by the region's label (`show.list_label`). It carries `data-tree-open-path`, `data-tree-locale` and `data-tree-open`, copied from the graph's element.
  - Each group heading is a level-1 `li[role=treeitem][aria-expanded][data-tree-node]` holding its row and a `ul[role=group][data-tree-children]`. It is never `aria-selected`. → opens it, ← folds it, and Enter or Space toggles it. Its fold is not stored (Q1).
  - Every row is an `li[role=treeitem][data-tree-node]` with `aria-level` and, on a parent, `aria-expanded`, by Task 8's DOM contract. It holds `[data-tree-row][data-tree-id][data-tree-title]` and, for a page, `data-tree-path` from the data. It is its own `[data-tree-focus]`. Its name is today's sentence, as `aria-label`. `aria-selected="true"` is on the marked one, in place of `aria-current`. The root page's node carries `data-tree-root`, and the marked page's ancestors `data-tree-on-path`.
  - The `button`s go. Roving `tabindex`: one item has `0`, the marked one or else the first; the rest have `-1`.
  - The keys, on the tree:
    - ↑/↓ move to the previous or next visible item;
    - → opens a folded parent, or moves to its first child;
    - ← folds an open parent, or moves to its parent;
    - Home and End go to the first and the last visible item;
    - Enter or Space selects and opens the card (`onSelect`, or `onMore` and `onAdd` as the item is);
    - `*` opens the item's whole branch.
  - A click on the disclosure part toggles. A click elsewhere on the row selects. Find's Enter is a `.click()` on the item, and it selects (Task 10).
  - A page's fold: the list seeds its state from the tree's `data-tree-open` (`readOpenSet(seed)`; C21), and writes through `setOpen` with `openByDefault` for the root and the marked page's path. A group's or a hub's fold is a view state only.
  - `mark(id)` opens the marked page's path (`openPathIn`, which forgets its folds), moves `tabindex="0"` to it, and keeps it scrolled into view inside the container.
  - `showRows` and `fail` draw their rows as a second tree, under their heading, with Back before it. Escape on them goes back as today.
  - A redraw (`put`) keeps the roving stop on the same node, else the first, and dispatches `tree:changed` on the tree.
  - Hovering or focusing an item still lights its node (`onHover`, the same listeners on the tree).
- Modify `app/views/admin/mind_graph/show.html.erb`: the graph's element gains `data-tree-open="<%= @tree_open %>"`, `data-tree-open-path` and `data-tree-locale`.
- Modify `app/controllers/admin/mind_graph_controller.rb#show`: `@tree_open = TreeOpenSet.parse(cookies[TreeOpenSet::COOKIE], readable_ids: <the viewer's readable page ids>).to_s`. The ids are one `pluck` through `AccessControl.scope(Current.actor, "pages.read", Page.kept)`, taken only when the viewer reads pages.
- Modify `app/javascript/mind_graph/app.js` and `selection.js` where they call `list.mark` or `list.row`: `row(id)` answers the treeitem.
- Modify `test/support/mind_graph_system_test_case.rb`: it gains `list_item(name)` (`find("[role=treeitem][aria-label^='…']")`), whose comment says why. The list tests that look rows up "as buttons by name" are rewritten on it.
- Test: `test/system/admin/mind_graph_list_test.rb`, `test/system/admin/mind_graph_card_and_list_modules_test.rb`, `test/system/admin/mind_graph_selection_test.rb`, `test/system/admin/mind_graph_notes_test.rb` (the card's return of focus), `test/integration/admin/mind_graph_test.rb`.

**Interfaces:**
- Consumes `readOpenSet`, `setOpen` and `openPathIn` (Task 8). `createList(...)` keeps its return shape: `row(id)` now answers an `li[role=treeitem]`, and the card's return of focus calls `.focus()` on it after setting `tabindex="0"`.
- Produces the tree `ul#mind-graph-tree`, which Task 15's find field names in `controls:`.

- [ ] **Step 1: Write the failing tests.**
  - `mind_graph_card_and_list_modules_test.rb`:
    - `test "the list is one tree: groups at level 1, pages by their depth, posts, tags and types flat at level 2, and the marked node aria-selected"`
    - `test "one Tab stop: the arrows, Home and End move the focus, which skips what is folded or hidden"`
    - `test "→ opens a folded page or goes to its first child, ← folds it or goes to its parent, and * opens the whole branch"`
    - `test "a page's fold in the list is kept in the cookie the Pages tree reads, and a group's fold is not"`
    - `test "the list starts from the open set the server handed it"` (C21). Set the cookie, then change `data-tree-open` on the element before the list draws. The list follows the attribute.
  - `mind_graph_list_test.rb`:
    - `test "Enter or Space on a row opens the node's card and moves the focus to it, and Escape gives it back to the row"`, from "the list is the keyboard path…".
    - `test "selecting a node on the canvas opens its path in the list, marks its row and scrolls the list to it"`
    - `test "a branch folded in the Pages tree is folded in the mind graph's list"` (the shared open set). Fold in Pages, `visit_screen` the graph, and assert `aria-expanded="false"` on that page's item.
  - `test/integration/admin/mind_graph_test.rb`: `test "the graph's open set is the cookie's, without the pages the viewer does not read"`.
  - Every other list test passes on `list_item`.
- [ ] **Step 2: Run, and verify they fail** (after a build): the two modules and list files.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** one at a time: `test/system/admin/mind_graph_list_test.rb`, `test/system/admin/mind_graph_card_and_list_modules_test.rb`, `test/system/admin/mind_graph_selection_test.rb`, `test/system/admin/mind_graph_notes_test.rb`, `test/system/admin/mind_graph_loading_test.rb`, `test/system/admin/tree_item_parity_test.rb`. Then `PGGSSENCMODE=disable bin/rails test test/lib test/integration/admin/mind_graph_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep. Check `pgrep`. Commit `feat: the mind graph's list is an APG tree whose page branches fold with the Pages tree's`.

---

### Task 15: The list on the left, with the find field and the whole-site search

Design answers Q3 and Q4 apply.

**Files:**
- Modify `app/views/admin/mind_graph/show.html.erb`:
  - `content_for :tree_label, "mind_graph"`.
  - `content_for :tree` holds the column, in this order (Q3):
    1. a head: `h2` `t(".column_heading")` "Pages, posts and tags" (`text-sm font-semibold text-ink`) and `TreeHideComponent.new(subject: "mind_graph")`;
    2. `TreeFindComponent.new(controls: "mind-graph-tree", noun: :nodes)`;
    3. `div[data-mind-graph-list][role=region]`, labelled by `show.list_label`, where the unlisted checkbox (`CheckboxComponent`, label `text-sm`) and the tree are drawn by `node_list.js`;
    4. `div[data-mind-graph-search-site][data-url=<the search's address>]`, which holds the last line.
  - The graph's box loses its 300px column and its search block. It is one column at every width (Q4): the focus or opened bar, the legend, the canvas.
  - The fill rule keeps the box window-high from 1024px.
  - The big comment is rewritten for the new layout and Tab order: the column comes first (the sidebar, the find field, the unlisted checkbox, the tree, the last line), then `<main>` (the focus bar, the legend's toggles, the zoom, the canvas, the card).
- Modify `app/javascript/mind_graph/app.js`:
  - The list's container and the last line are found by `document.querySelector("#tree-column [data-mind-graph-list]")` and `"#tree-column [data-mind-graph-search-site]"`, never inside `element`. A screen without the column, which cannot happen on this screen, throws as a missing part does.
  - On `tree-find:filtered` with a query, it shows the last line (Q3): after the tree, outside `role="tree"`, `mt-2`, a `ButtonComponent` tertiary small (its classes from `data-button-classes`), "Search the whole site for “%{query}”" (`mind_graph.script.list.search_site`). It is hidden on `tree-find:cleared`.
  - Pressing the last line runs the search through `search/suggestions.js` and `list.showResults({ query, groups, back })` (new on `createList`). The results replace the tree in the list's region (Q3):
    - Back comes first ("Back to the list", `script.list.back`, tertiary small), and takes the focus when the results show;
    - then `h2` "Whole site: “%{query}”" (`script.list.search_site_heading`, `text-sm font-semibold`);
    - then the groups Pages, Posts and Tags (`script.search.groups.*`), headed as the tree's group headings are (chip and `text-label` `--cs-meta`), but not treeitems;
    - each row is a link on the tree row's geometry (28px, the mark box, the title `text-sm`, a page's path under it in `text-small` `--cs-meta`), hover `--cs-sunken`, a 2px focus outline at −2px;
    - nothing found is `script.search.none`, one dim line;
    - a failure is `script.search.failed` in `--cs-danger-ink`, `role="alert"`;
    - Back and Escape return to the tree with the query kept and the focus on the last line.
  - `app.js` handles no key of the find field: Down and Enter are the find controller's (C22).
  - `destroy()` stops listening outside the element.
- Modify `app/javascript/mind_graph/search_box.js`. Its rendering of a group of results is exported (`renderResults(list, rows, { text, dotClasses })`) for `showResults`. The field, the popover, their Escape and outside-press handling, and the status line go. With the status line goes `mind_graph.script.search.count`, its one reader (C33). Its comment becomes the results' own.
- Modify `app/javascript/controllers/admin/mind_graph/graph_controller.js` `reset()`. It also takes back `#tree-column [data-mind-graph-list]`'s children, and the last line's `hidden` and words. Its comment says why: the column stands outside the controller's element, and Turbo's snapshot keeps it. The find field is the find controller's to clean, never `reset()`'s (C34).
- Modify `config/locales/admin/mind_graph.en.yml`:
  - `script.list.search_site` "Search the whole site for “%{query}”";
  - `script.list.search_site_heading` "Whole site: “%{query}”";
  - `show.column_heading` "Pages, posts and tags";
  - `show.search.*` and `script.search.count` go, with their readers; the rest of `script.search.*` stays (the results' words);
  - the view's `messages_data` list gains the two `search_site` keys and loses `script.search.count`, written out one by one.
- Test: `test/system/admin/mind_graph_search_test.rb` (rewritten), `test/system/admin/mind_graph_list_test.rb`, `test/system/admin/mind_graph_worker_and_back_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/admin/tree_fold_test.rb`, `test/system/admin/mind_graph_loading_test.rb`, `test/system/admin/mind_graph_legend_test.rb`, `test/lib/script_messages_test.rb`.

**Interfaces:**
- Consumes `TreeFindComponent` with `noun: :nodes` (Task 10), `TreeHideComponent` and `content_for :tree_label` (Task 12), `.admin-shell__tree--fill`, and `ul#mind-graph-tree` (Task 14).
- Produces `createList(...).showResults({ query, groups, back }) -> void`.

- [ ] **Step 1: Write the failing tests.**
  - `mind_graph_search_test.rb`, rewritten:
    - `test "the find field narrows the list to the matches and their paths, and the graph is left as it is"`
    - `test "the whole site's search finds a post the graph does not draw and opens its neighbourhood"` (from "search finds a post the global view does not draw…")
    - `test "the whole site's results group pages, posts and tags, show a page's path, say when nothing matches, and Back and Escape return to the list with the query kept"`
    - `test "a failed whole-site search says so and the graph keeps working"`
    - `test "the results are text: a title with markup is not inserted as markup"`
    - `test "leaving the screen aborts a whole-site search still in flight"`
    - The Focus and depth test stays as it is.
  - `mind_graph_list_test.rb`:
    - "the Tab key meets the search first and the list last" becomes `test "the Tab order is the find field, the list, then the legend, the zoom and the canvas"`.
    - "in the list's column…twenty characters" is pinned to the column's default width (17rem at a 16px root).
    - `test "Down Arrow in the find field reaches the first match, and Enter selects it and opens its card"`
  - `tree_column_test.rb`: `test "the mind graph's column takes the tree's width, divider and drag, and its width is the one Pages left"`
  - `tree_fold_test.rb`: `test "the mind graph's column folds to its strip with its own words, and the canvas widens"`
  - `mind_graph_worker_and_back_test.rb`: `test "a mind graph restored from Turbo's cache has no stale rows in the column and an empty find field"` (Review Focus 3). Leave with rows drawn and a query typed, go Back, and assert, before the data arrives, no `[role=treeitem]` in the column, an empty field and no last line.
  - `tree_column_test.rb`: `test "below 1024px the list is the tree drawer, opened by the top bar's List button"` (the owner's open question, default).
- [ ] **Step 2: Run, and verify they fail** (after a build).
- [ ] **Step 3: Implement.** Search the tests and `app/` by hand for `data-mind-graph-search`, `data-mind-graph-results`, `data-mind-graph-status`, `mind-graph-search`, `search.count`, `min-[1100px]:col-start-2` and `300px`, and fix each hit in this task.
- [ ] **Step 4: Run** one at a time: every `test/system/admin/mind_graph_*_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/admin/tree_fold_test.rb`, `test/system/admin/tree_item_parity_test.rb`. Then `PGGSSENCMODE=disable bin/rails test test/lib test/components test/integration/admin/mind_graph_test.rb`. Expected: PASS.
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
    - The graph's fold words, its divider's words and its column head (design answers Q2, Q3, and Q5).
    - The groups as tree items (design answer Q1).
    - Whether `design_system_entries.rb` keeps the artifact version as a provenance stamp (C32).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`: "Tags, related posts and the Mind graph" (the list on the left, the find field, the whole-site search, the keys), with its screenshots retaken.
  - **The Design System cards to redraw**, for the design agent:
    - `StudioTree`: from "Decided, not built" to **Stable**. Its Interface's *(planned)* names become the built ones: `TreeItemComponent.new(id:, title:, parent:, folded:, controls:, selected:, context_only:, flat:, root:, path:, node_id:, data:)`, `CLASSES`, `TreeFindComponent.new(controls:, noun:, moving:)`, `admin--tree--disclosure`, `admin--tree--find`, `tree:changed`, the tree's DOM contract, `TreeOpenSet`, the cookie's format, `TreeSubjects`. `FIND_ON_SERVER_ABOVE` is not built: the threshold is a sentence in the reference. The preview is redrawn from the built rows.
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
  - Task 7: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/admin/tree_fold_test.rb`, `test/system/admin/presence_lists_test.rb`, `test/system/admin/drafts_test.rb`;
  - Task 8: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/admin/tree_column_test.rb`, `test/system/admin/tree_fold_test.rb`, `test/system/admin/editor_header_test.rb`;
  - Task 9: `test/system/admin/tree_test.rb`, `test/system/tree_test.rb` (its Undo test included);
  - Task 10: `test/system/admin/tree_find_test.rb`, `test/system/admin/tree_test.rb`, `test/system/tree_test.rb`, `test/system/command_palette_test.rb`, `test/system/admin/editor_fields_test.rb`.
- 5d-2: as each task lists, and every `test/system/admin/mind_graph_*` file in Task 15.

**Likely to change, left to CI:** `test/system/admin/notes_markers_test.rb` (the tree's markers), `test/system/admin/languages_test.rb` (titles in another editing language), `test/system/theme_toggle_test.rb` (the tree in dark), `test/system/admin/view_only_test.rb` (context-only rows), `test/system/admin/trash_test.rb` (a trashed page leaves the tree). A CI failure is fixed in the task that owns the file.

## Pre-flight

Done while writing this plan, then by the scan of 2026-11-07 (`.superpowers/sdd/preflight-5d.md`, C1–C37, each resolved in the task named there).

- **The plan against itself.**
  - `TreeItemComponent`'s keys: `fold` and `unfold` in Task 6, `opened` in Task 9, each with its reader and its contract line.
  - `TreeItemComponent`'s disclosure gets its `data-action` and its `keyboard:` in Task 8, with the controller and the test. Until then it is in `KEYBOARD_NOT_YET`.
  - `tree.hide` moves from `pages_screen.en.yml` to `shell.en.yml` only in Task 12, which deletes its last reader there, and also deletes `tree_fold.show` and `tree_divider.*`.
  - `SELECTED_TITLE_CLASS` and the `selectedTitle` Stimulus class go together in Task 7, and `MARKER_AT_REST` becomes `CLASSES[:reveal]`.
  - `TREE_RULES_NOT_YET` is written in Task 6, loses its Pages entry in Task 7, and is deleted in Task 13. Its staleness test makes it impossible to forget.
  - `UNDECLARED` is written in Task 1 and deleted in Task 2.
  - The field is cleaned by the find controller alone, and `reset()` takes back only the list and the last line.
- **One block, not two.**
  - The `.admin-tree` rules, `.admin-tree-row--selected` included, are one block (Task 6's test "the tree's rules are one block"). Tasks 9 and 10 add `.admin-tree-drop-target` and `[data-filtered]` inside it.
  - `.admin-shell__tree--fill` is the shell's, beside `.admin-shell__tree`, and is written once in Task 12.
  - The four lengths are written once on `:root` (Task 6's test).
- **Keys before their reader.** Every key arrives in the task whose code reads it. `script.list.search_site` and `search_site_heading` arrive in Task 15, and `show.search.*` is deleted in Task 15 with its reader.
- **Tests a mutation would not fail.**
  - Each contract and part guard has a "can fail" test over a sample (Tasks 1, 3, 4).
  - The parity test compares two different samples first (Task 13).
  - The open-set writer guard reports a sample in JavaScript and one in Ruby (Task 8).
  - The geometry test sums the step's three pixel values against the token, not a `calc()` of the token (Task 6).
  - The moved-page test fails without `save`'s open (Task 9), and the full-load test fails with the folds checked first (Task 8).
  - The public words test reads the files, so `[]` or drift fails (Task 4).
  - The class guard on `node_list.js` reports a sample (Task 13).
  - The "first paint" fold test watches for a change of `hidden`, not the end state (Task 8).
  - The count test counts the status line's changes, not its final text (Task 10).
  - The keys tests swap in a stored translation (Task 7).
- **Guard lists.**
  - `CONVERTED` grows in Tasks 7, 8, 10 and 12, each with its own files.
  - `COVERED_BY` grows in Tasks 6 and 10. `KEYBOARD_NOT_YET` gains TreeItem in Task 6 and loses it in Task 8.
  - `LIST_LAYOUT_LITERALS` (Task 13) has its staleness test.
  - `TINT_PAIR_ALLOWED` and `ACCENT_FILL_ALLOWED` are unchanged: the graph stops using `bg-accent-tint` (it was not an allowance), and the match's tint is a stylesheet rule.
- **History comments.** Every task ends on the grep in "Comment rule".
