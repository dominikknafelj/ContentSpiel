# Image viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A plain click on a note's picture opens it in one shared dialog over CS Studio, fitted, named, stepping through the message's pictures, with Open original and Download.

**Architecture:** `Admin::Ui::ImageViewerComponent` is drawn once in the admin layout on `Admin::Ui::DialogComponent` at a new `viewer` width step. Its controller `admin--ui--image-viewer` listens for plain clicks on `[data-image-viewer-item]` links (the note thumbnails, which stay links), reads the message's pictures once, and fills the stage. The GIF still and Play move into a shared `Admin::Ui::GifComponent` with `admin--ui--gif`, drawn by the thread's tile and by the viewer's stage.

**Tech Stack:** Rails 8.1, ViewComponent, Stimulus (import maps), Tailwind (`tailwindcss-rails`), Minitest, Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-16-image-viewer-design.md` (the behaviour, with the planner's calls marked). **Design:** the Design System artifact `https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT`, version `1794783995-dc63` (v240), cards **ImageViewer** and **Gif** (`project/components/ImageViewer/README.md`, `project/components/Gif/README.md` and their `preview.html`; read with the Artifact tool, `action: "read"`, `path`). The ImageViewer card's "Settled 2026-11-16" answers the design requests; they are written into the spec's §3, §4 and §6 and into the tasks below. Where the cards and this plan differ on a word or a look, the cards win; on behaviour, the spec wins.

## Global Constraints

- Read `CLAUDE.md`; before a test `docs/reference/writing-tests.md`, before a browser test `test/system/README.md`. Browser tests run one file at a time on a quiet machine (`sysctl -n vm.loadavg` well under the core count), after `bin/rails tailwindcss:build`; never a build while tests run. A new worktree runs `bin/rails db:test:prepare` once.
- Components: `app/components/admin/ui/image_viewer_component.{rb,html.erb}` and `app/components/admin/ui/gif_component.{rb,html.erb}`, each including `Admin::Ui::Contract` with the full declaration. Scripts: `app/javascript/controllers/admin/ui/image_viewer_controller.js` (`admin--ui--image-viewer`) and `app/javascript/controllers/admin/ui/gif_controller.js` (`admin--ui--gif`); `app/javascript/controllers/admin/notes/gif_controller.js` is deleted, with no alias.
- Every word a person reads is a key. `admin.components.ui.image_viewer`: `previous` "Previous image", `next` "Next image", `position` "%{index} of %{count}", `open_original` "Open original", `download` "Download", `failed` "This image couldn't be shown here. Open the original, or download it.", `loading` "Loading…", `stepped` "%{name}, %{position}". `admin.components.ui.gif`: `play` "Play", `pause` "Pause", `label` "GIF · %{name}". `admin.components.notes_screen.files.view` "View %{name}" replaces `open`; `play`, `pause` and `gif` leave `notes_screen.files`. The ui keys go in `config/locales/admin/ui.en.yml`, the notes key stays in `config/locales/admin/notes.en.yml`. Script words reach the script through the server's `data-messages` (`messages(element).t(key)`).
- Every new component and template joins `CONVERTED` in `test/lib/admin_i18n_test.rb`.
- Every address of a note's file is `admin_record_note_file_path`; no Active Storage URL, no new route, no variant.
- No `z-index` but a `--cs-z-*` token (and none is expected: the dialog is in the top layer). No transition or animation of the viewer's own, no `view-transition-name`; tokens only, so the theme fade covers it.
- One primary per area: the viewer has none (Download is secondary, Open original tertiary, the phone's arrows small secondary).
- Comments state invariants, never history. No compatibility code. Long comments where the logic is not obvious (match `files_component.rb`'s density).
- `test/support/design_system_entries.rb`: `VERSION = "1794783995-dc63"`; `ENTRIES` gains `Gif` (Task 2) and `ImageViewer` (Task 3), nothing else (the cards `SiteSearchMatches` and `SiteSearchSuggest` belong to the `search-2` branch, and a merge with main sorts them out); `NOT_YET` stays empty.
- Commits by explicit path, conventional messages, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`.

## Review Focus

1. **A modified click or key** (⌘-click, Ctrl-click, Shift-click, middle click; Alt+← / ⌘← for Back) must stay the browser's — Task 4 tests `a modified click on a note's picture opens a tab and not the viewer` and `an arrow with a modifier does not step`.
2. **Two messages with pictures on one page** must stay two groups, and a document in a message is never a step — Task 4 test `the arrows step through one message's pictures only, disabled at the ends, and say the name and position`.
3. **The file gone or the right lost while the viewer is open** must show the notice, not a broken picture — Task 4 test `a picture that can't be loaded says so and keeps Open original and Download`.
4. **The focused arrow disabled by a step** (Next at the last) must hand the focus to the other arrow, never `<body>` — Task 4 test (keyboard) below.
5. **A very long file name** must truncate in the head and stay whole as the dialog's name — Task 3 test `a long name truncates in the head and the title holds it whole`.

---

### Task 1: The Dialog's `viewer` step and its head slot

**Files:**
- Modify: `app/components/admin/ui/dialog_component.rb` (`WIDTHS`, `renders_one :title_aside`, the contract's `slots:`)
- Modify: `app/components/admin/ui/dialog_component.html.erb` (the slot after the `<h2>`, inside the header, before Close)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (beside `.admin-dialog[data-dialog-width="picker"]`, ~line 497)
- Test: `test/components/admin/ui/dialog_component_test.rb`, `test/components/previews/admin/ui/dialog_component_preview.rb`

**Interfaces:**
- Produces: `DialogComponent::WIDTHS[:viewer] == 1100`; `DialogComponent#with_title_aside { ... }`, drawn inside `<header>` right after the `<h2 id="<id>-title">`; the header's `justify-between` becomes a flex row whose Close keeps the far end (`ml-auto` on the close form).

- [ ] **Step 1: Write the failing tests**

```ruby
test "the viewer width step is drawn as data-dialog-width viewer" do
  render_inline(Admin::Ui::DialogComponent.new(id: "v", title: "a.png", width: :viewer))
  assert_selector "dialog#v[data-dialog-width='viewer']", visible: :all
end

test "title_aside renders in the header after the title and before Close, only when given" do
  render_inline(Admin::Ui::DialogComponent.new(id: "v", title: "a.png", width: :viewer)) { |d| d.with_title_aside { "PNG · 1 KB" } }
  assert_selector "dialog header h2#v-title + [data-dialog-title-aside]", text: "PNG · 1 KB", visible: :all
  render_inline(Admin::Ui::DialogComponent.new(id: "w", title: "x"))
  assert_no_selector "[data-dialog-title-aside]", visible: :all
end
```

- [ ] **Step 2: Run** `bin/rails test test/components/admin/ui/dialog_component_test.rb` — Expected: FAIL (unknown width `:viewer`).

- [ ] **Step 3: Implement.** `WIDTHS` gains `viewer: 1100`; the slot is wrapped in `<span data-dialog-title-aside class="shrink-0 text-small text-meta">`. The contract's `slots:` becomes `%i[footer title_aside]`. CSS (one block, commented):
  - `.admin-dialog[data-dialog-width="viewer"] { max-width: 1100px; height: calc(100dvh - 48px); max-height: none; }`
  - its `> .admin-dialog__body { flex: 1 1 auto; min-height: 0; padding: 0; overflow: hidden; display: flex; flex-direction: column; }`
  - its title `h2 { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }` (other dialogs' titles keep wrapping)
  - `@media (max-width: 639px) { … { width: 100vw; max-width: none; height: 100dvh; margin: 0; border-radius: 0; box-shadow: none; } }`
  - the phone's two-line head (the card's answer 4), under the same query: the title and the aside stack in one column (`min-width: 0; flex: 1`), the title 15px weight 600 truncated, the aside 12px `cs-meta` under it, never dropped; Close at the right of both. A `title_aside` that is given wraps with the title in one element (e.g. `<div class="admin-dialog__titles">`) so the stack is possible; a dialog without the slot draws the header as today.
  - the safe areas (answer 6), under the same query, on the viewer step only: the header `padding-top: max(12px, env(safe-area-inset-top))`; the footer `padding-bottom: max(12px, env(safe-area-inset-bottom))`; the header and footer `padding-left: max(16px, env(safe-area-inset-left)); padding-right: max(16px, env(safe-area-inset-right))` (the stage's own inline padding is Task 3's). The layout's `<meta name="viewport">` must carry `viewport-fit=cover` for `env()` to be non-zero; check it, and add it if missing.
  - Add a `viewer` example to the preview (closed, like `form`).

- [ ] **Step 4: Run** `bin/rails test test/components/admin/ui/dialog_component_test.rb test/components/admin/ui/contract_test.rb test/lib/component_parts_test.rb test/lib/admin_design_rules_test.rb` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: the dialog's viewer width step and a slot beside its title`

### Task 2: `Admin::Ui::GifComponent` and `admin--ui--gif`

**Files:**
- Create: `app/components/admin/ui/gif_component.rb`, `app/components/admin/ui/gif_component.html.erb`, `app/javascript/controllers/admin/ui/gif_controller.js`
- Delete: `app/javascript/controllers/admin/notes/gif_controller.js`
- Modify: `app/components/admin/notes_screen/files_component.html.erb` (the GIF branch renders the component), `files_component.rb` (comment), `config/locales/admin/ui.en.yml` (`gif:`), `config/locales/admin/notes.en.yml` (drop `play`, `pause`), `app/assets/tailwind/content-spiel.tailwind.css` (`.admin-note-gif-button` → `.admin-gif-button`, ~line 1645), `test/lib/admin_i18n_test.rb` (`CONVERTED`), `test/support/design_system_entries.rb` (`VERSION`, `ENTRIES`), `app/views/admin/shared/_icon.html.erb` (`pause`, Lucide)
- Test: `test/components/admin/ui/gif_component_test.rb`, `test/components/previews/admin/ui/gif_component_preview.rb`, `test/system/admin/note_files_test.rb`

**Interfaces:** (the Gif card, v240, is the interface; it replaces the earlier `href:` / `renders_one :label` shape)
- Produces: `Admin::Ui::GifComponent.new(src:, name:, placement: :tile, link: {}, **html)`, `placement` one of `:tile` and `:stage` (anything else raises `ArgumentError`). It draws `<div data-controller="admin--ui--gif" data-admin--ui--gif-src-value="<src>" data-admin--ui--gif-gif-value="true" …html>`: the picture holder, then the Play button (targets `button`, `label`, `icon`; `motion-safe:hidden`; `admin-gif-button`; Lucide `play` while still, Lucide `pause` while playing, both through `admin/shared/_icon`, `pause` joining it), then, for `:tile` only, the label `t(".label", name:)` ("GIF · %{name}", bottom left, as the tile's label today). The holder is, for `:tile`, an `<a href=src target=_blank rel=noopener data-turbo=false>` merged with the caller's `link:` attributes (its `title:` and `data:`, which is where the viewer's marks go in Task 4); for `:stage`, a `<span>`; both `relative block min-w-0 max-w-full`, holding the `<img alt=name>` (target `moving`, `load->admin--ui--gif#paint`) and the `<canvas aria-hidden>` (target `still`). `link:` with `:stage` raises `ArgumentError`. `html` passes the frame's own `class:` (appended) and `data:` (merged) through, as `ButtonComponent` does; `html` is not in `interface:`. `src:` may be `nil` (the viewer's empty stage): then the `<img>` has no `src`.
- Produces (script): `admin--ui--gif` with `static values = { src: String, gif: { type: Boolean, default: true } }`. `srcValueChanged(value)`: when the `<img>`'s `src` differs, set it (or remove it for a blank value), put the still back (not playing) and clear the canvas (`width = 0`); when it is the same, do nothing, so a live re-connect keeps a playing GIF playing. `gifValueChanged(value)`: false hides the button and canvas and shows the picture whatever the motion setting (a PNG on the viewer's stage); true restores the still rules. `paint()` and `toggle()` keep their current behaviour, but for the icon, which is swapped (`play` ↔ `pause`) rather than hidden. `disconnect()` and `turbo:before-cache@document` clear the canvas and put the still back.
- Contract: `motion: :reduced`, `content_edges: %i[short long]`, `widths: :from_container`, `interface: %i[src name placement link]`, `states: %i[rest]`, `script_states: { playing: ["test/system/admin/note_files_test.rb", "a GIF plays by itself; with reduced motion it is a still with Play, which turns into Pause"] }`, `keys: %w[play pause label]`, `slots: []`, `controller: "admin--ui--gif"`, `keyboard: ["test/system/admin/note_files_test.rb", "with reduced motion a GIF's Play is the Tab stop after its picture, and Enter plays and pauses it"]`; limits: it draws no still of its own (the browser's first frame, no variant), and what a click on the picture does is the caller's (the tile's link and its `link:` attributes, or none on the stage).
- Design System entry: the card is `Gif`, so `ENTRIES` gains `Gif` and `VERSION` becomes `"1794783995-dc63"` in this task; no `NOT_YET` entry.

- [ ] **Step 1: Write the failing tests.** Component test: `"it draws the picture, a hidden canvas and Play under the gif controller"` (asserts `[data-controller='admin--ui--gif'] img[alt='loop.gif'][data-admin--ui--gif-target='moving']`, `canvas[aria-hidden=true]`, `button`, text "Play"); `"on a tile the picture is a link to it in a new tab carrying the caller's link attributes, on the stage a span"`; `"a tile draws the label GIF · name after the button, the stage none"`; `"an unknown placement, or link: on the stage, raises"`. Browser test (new, `note_files_test.rb`): `with reduced motion a GIF's Play is the Tab stop after its picture, and Enter plays and pauses it` — `visit_editor` the page with the notes open, reduce motion, Tab from the GIF's link (`stop_on`), `page.send_keys(:enter)`, assert "Pause" and the picture shown, Enter again, "Play".
- [ ] **Step 2: Run** `bin/rails test test/components/admin/ui/gif_component_test.rb` — Expected: FAIL (uninitialized constant).
- [ ] **Step 3: Implement** the component, the controller, the `pause` icon, the CSS rename (`.admin-note-gif-button` → `.admin-gif-button`; Pause 8px in from the bottom right, the card's), the keys move (`play`, `pause`, and `gif` as `label`, to `admin.components.ui.gif`), `FilesComponent`'s GIF branch as `render Admin::Ui::GifComponent.new(src: path(a), name:, placement: :tile, link: { title: t(".open", name:) }, class: PICTURE_BOX_CLASS, data: { note_gif: true })`. `design_system_entries.rb`: `VERSION`, `Gif` in `ENTRIES`. Add both files to `CONVERTED`.
- [ ] **Step 4: Run** `bin/rails test test/components/admin/ui/ test/lib/component_parts_test.rb test/lib/admin_i18n_test.rb test/lib/source_layout_test.rb test/lib/component_screens_test.rb test/components/component_contract_test.rb`, then (browser, alone) `bin/rails test test/system/admin/note_files_test.rb` — Expected: PASS, the existing GIF test included.
- [ ] **Step 5: Commit** — `ref: a GIF's still and Play are one shared component, admin--ui--gif`

### Task 3: `Admin::Ui::ImageViewerComponent` in the layout

**Files:**
- Create: `app/components/admin/ui/image_viewer_component.rb`, `app/components/admin/ui/image_viewer_component.html.erb`
- Modify: `app/views/layouts/admin.html.erb` (render it after the media picker, ~line 221), `config/locales/admin/ui.en.yml` (`image_viewer:`), `app/views/admin/shared/_icon.html.erb` (`arrow_right`, `arrow_up_right`, Lucide), `test/lib/admin_i18n_test.rb`, `test/support/ui_contract.rb` (`KEYBOARD_NOT_YET`), `test/support/design_system_entries.rb` (`ENTRIES` gains `ImageViewer`; `VERSION` is already `1794783995-dc63` from Task 2; `SiteSearchMatches` and `SiteSearchSuggest` are NOT added here, they come with the `search-2` branch), `app/assets/tailwind/content-spiel.tailwind.css` (the disabled round arrow, the checkerboard)
- Test: `test/components/admin/ui/image_viewer_component_test.rb`, `test/components/previews/admin/ui/image_viewer_component_preview.rb`, `test/integration/admin/image_viewer_layout_test.rb`

**Interfaces:**
- Consumes: Task 1's `width: :viewer` and `with_title_aside`; Task 2's `GifComponent.new(src: nil, name: "", placement: :stage)`.
- Produces: the markup the controller reads, by id and target (`data-admin--ui--image-viewer-target`): `dialog#image-viewer` (Dialog id `image-viewer`, title blank, `data-controller="admin--ui--image-viewer"`, `data-messages` with `position` and `stepped`); title `#image-viewer-title`; `facts` (in `title_aside`); `stage` (`cs-sunken`, `relative isolate flex-1 min-h-0 grid place-items-center`, padding 16px 64px, 12px under 640px) holding the Gif part (`placement: :stage`) with `data: { "admin--ui--image-viewer-target": "frame", "admin--ui--gif-gif-value": false }` whose `<img>` is also target `picture` with `error->admin--ui--image-viewer#failed load->admin--ui--image-viewer#loaded`, the `notice` (`NoticeComponent.new(tone: :warn)`, `hidden`, the `failed` words), and the `loading` target (`role="status"`, `hidden`, centred: `<span class="admin-spinner" aria-hidden="true">` with the `loading` words under it, 13px `cs-meta`). The stage's padding is 16px 64px, and under 640px `12px max(16px, env(safe-area-inset-right)) 12px max(16px, env(safe-area-inset-left))` (the card's answer 6; its ground runs edge to edge). The picture's own box carries the checkerboard (answer 7): 8px squares of `#ffffff` and `#e7e9ef`, the same in both schemes, behind the `<img>` only (a background on the `<img>` element, e.g. `.admin-image-viewer__stage img`), never on the stage; if `test/lib/admin_design_rules_test.rb` refuses raw colours there, the two colours become tokens in `content-spiel.css` with one value in both schemes; the stage's round arrows `previous` / `next` (40px, `cs-popover`, `shadow-2`, `rounded-full`, a 1px `cs-line` edge, `max-sm:hidden`, `aria-label` the keys, `hidden` until a group has more than one; the Lucide `arrow_left` / `arrow_right` at 18px; disabled (the card's answer 3): the real `disabled` attribute, `cs-sunken` ground, the arrow in `cs-meta`, the 1px `cs-line` edge, no shadow, `cursor: not-allowed`, the same circle in the same place); the foot: `position` (`text-small text-dim tabular-nums mr-auto`), the phone's arrows `phonePrevious` / `phoneNext` (small secondary, `sm:hidden`, the icon alone at 16px, `aria-label` the keys), `original` (`link_to` with `ButtonComponent.classes(:tertiary)`, `target=_blank rel=noopener`, the `arrow_up_right` icon at 16px) and `download` (`ButtonComponent.classes(:secondary)`, `download` attribute); a visually hidden `announcer` (`aria-live=polite`, `sr-only`). The picture: `max-w-full max-h-full w-auto h-auto object-contain`, never enlarged.
- Contract: `accessibility:` "A native modal dialog named by the file name, with Close, Previous image and Next image as buttons, Open original and Download as links, and a polite announcement of the name and position at each step; Escape, Close and the backdrop close it and the focus goes back to the picture that opened it."; `motion: :reduced`; `content_edges: %i[long many missing]`; `widths: :fixed_width`; `interface: %i[]`; `limits:` drawn once by the admin layout and opened only by a plain click on a `[data-image-viewer-item]` link; fitted, no zoom, pan or swipe; steps within the opener's `[data-image-viewer-group]` only, read once at opening; `states: %i[rest]`; `script_states: {}` here (a named test must exist; Task 4 adds `open`, `stepped` and `failed` with its tests); `keys: %w[previous next position open_original download failed loading stepped]`; `slots: []`; `controller: "admin--ui--image-viewer"`; `keyboard: nil` here, with `UiContract::KEYBOARD_NOT_YET["Admin::Ui::ImageViewerComponent"] = "its keyboard test is Task 4's, in this branch"` (`test/support/ui_contract.rb`), emptied in Task 4.

- [ ] **Step 1: Write the failing tests**

```ruby
test "it draws one closed viewer dialog with its stage, arrows, position, actions and announcer" do
  render_inline(Admin::Ui::ImageViewerComponent.new)
  assert_selector "dialog#image-viewer[data-dialog-width='viewer'][data-controller~='admin--ui--image-viewer']", visible: :all
  assert_selector "#image-viewer [data-admin--ui--image-viewer-target='previous'][aria-label='Previous image'][hidden]", visible: :all
  assert_selector "#image-viewer [data-admin--ui--image-viewer-target='next'][aria-label='Next image'][hidden]", visible: :all
  assert_selector "#image-viewer a[data-admin--ui--image-viewer-target='original'][target='_blank']", text: "Open original", visible: :all
  assert_selector "#image-viewer a[data-admin--ui--image-viewer-target='download'][download]", text: "Download", visible: :all
  assert_selector "#image-viewer [data-admin--ui--image-viewer-target='announcer'][aria-live='polite']", visible: :all
  assert_selector "#image-viewer [data-admin--ui--image-viewer-target='notice'][hidden]", text: "This image couldn't be shown here.", visible: :all
  assert_selector "#image-viewer [data-admin--ui--image-viewer-target='loading'][role='status'][hidden] .admin-spinner[aria-hidden='true']", visible: :all
  assert_selector "#image-viewer [data-admin--ui--image-viewer-target='loading']", text: "Loading…", visible: :all
  assert_no_selector "#image-viewer img[src]", visible: :all
end

test "it holds no primary button and no Active Storage address" do
  render_inline(Admin::Ui::ImageViewerComponent.new)
  refute_includes page.native.to_html, "active_storage"
  refute_includes page.native.to_html, Admin::Ui::ButtonComponent.classes(:primary)
end

test "a long name truncates in the head and the title holds it whole" do
  # the h2 is the CSS-truncated title (Task 1) and is the dialog's aria-labelledby
  render_inline(Admin::Ui::ImageViewerComponent.new)
  assert_selector "dialog#image-viewer[aria-labelledby='image-viewer-title'] h2#image-viewer-title", visible: :all
end

# test/integration/admin/image_viewer_layout_test.rb
test "a CS Studio screen draws the viewer once, empty" do
  sign_in_as(users(:one)); get admin_root_path
  assert_select "dialog#image-viewer", 1
  assert_select "dialog#image-viewer img[src]", 0
end
```

- [ ] **Step 2: Run** `bin/rails test test/components/admin/ui/image_viewer_component_test.rb` — Expected: FAIL.
- [ ] **Step 3: Implement** the component, keys, icons, layout line, `CONVERTED`, `KEYBOARD_NOT_YET` entry, entries copy, and a `rest` preview (closed, as the media picker's).
- [ ] **Step 4: Run** `bin/rails test test/components/admin/ui/ test/lib/component_parts_test.rb test/lib/admin_i18n_test.rb test/lib/component_screens_test.rb test/lib/admin_design_rules_test.rb test/components/component_contract_test.rb test/integration` — Expected: PASS.
- [ ] **Step 5: Commit** — `feat: the image viewer's dialog, drawn once in CS Studio's layout`

### Task 4: `admin--ui--image-viewer` and the thumbnails' marks

**Files:**
- Create: `app/javascript/controllers/admin/ui/image_viewer_controller.js`, `test/system/admin/image_viewer_test.rb`
- Modify: `app/components/admin/notes_screen/files_component.html.erb` (`data-image-viewer-group="<message.id>"` on `[data-note-files]`; on each image link, and through the GIF tile's `link:` attributes, `data-image-viewer-item`, `data-name`, `data-facts` (`facts(attachment)`), `data-image-viewer-gif` for a GIF; title `t(".view", name:)`), `files_component.rb` (the comment's "no lightbox" paragraph), `config/locales/admin/notes.en.yml` (`view` for `open`), `app/components/admin/ui/image_viewer_component.rb` (the contract's test names), `test/support/ui_contract.rb` (`KEYBOARD_NOT_YET` empty again), `test/system/admin/note_files_test.rb` (the first test)

**Interfaces:**
- Consumes: Task 3's ids and targets; Task 2's `admin--ui--gif` values (`src`, `gif`) written as attributes on the `frame` target.
- Produces: `admin--ui--image-viewer` with targets `title facts stage frame picture notice loading previous next phonePrevious phoneNext position original download announcer`. `connect()` adds a `click` listener on `document` and `turbo:before-cache` on `document`; `disconnect()` removes both and calls `takeBack()`. Actions on the dialog: `keydown.left->…#previous`, `keydown.right->…#next`, `close->…#closed`; the four arrow buttons `click->…#previous` / `#next`.
  - `open(event)` (the document listener): returns unless `event.button === 0`, no modifier, not `defaultPrevented`, and `event.target.closest("a[data-image-viewer-item]")`. Then `preventDefault`, reads `this.items` = `[...trigger.closest("[data-image-viewer-group]").querySelectorAll("a[data-image-viewer-item]")].map(a => ({ href: a.href, name: a.dataset.name, facts: a.dataset.facts, gif: "imageViewerGif" in a.dataset }))`, `this.index` its own, `this.opener = trigger`; `show(index)`; `showModal()`; focus Next if enabled, else Previous if enabled, else Close.
  - `show(index, { announce })`: hides the notice, writes title, facts, position (`position` key), `original.href`, `download.href` and `download` (the name), the frame's `data-admin--ui--gif-gif-value` and `-src-value`; arrows hidden when one item, `disabled` at the ends; announces `stepped` only when `announce`.
  - `previous(event)` / `next(event)`: a keydown with any modifier returns without `preventDefault`; otherwise steps within bounds and, when the focused arrow became disabled, focuses the other one (the phone pair when that is the drawn pair).
  - Loading (the card's answer 1): `show` hides `loading` and starts a 400 ms timer (clearing any earlier one) that unhides it; `loaded()`, `failed()`, the next `show` and `takeBack()` clear the timer and hide it. A picture already complete when its `src` is written (a cached one) never shows it.
  - `failed()`: shows the notice, hides the picture. `loaded()`: hides the notice.
  - `closed()`: focus the opener if connected, else the first `a[data-image-viewer-item][href="<opener href>"]`, else the opener's thread (`#note-thread-…` read at opening), then `takeBack()` minus the close.
  - `takeBack()`: close if open, blank the gif `src` value, empty title, facts, position and announcer, hide the notice, drop `items` and `opener`.

- [ ] **Step 1: Write the failing browser tests** in `test/system/admin/image_viewer_test.rb` (setup as `note_files_test.rb`'s: a page, a thread, a reply with `tiny.png`, a second PNG and a PDF; a second message with one PNG; `visit_editor` with the notes open):
  - `a plain click on a note's picture opens the viewer with its name, facts and position` — asserts `dialog#image-viewer[open]`, title "tiny.png", facts `PNG · …`, "1 of 2", Open original's `href` equal to the thumbnail's, no new window.
  - `a modified click on a note's picture opens a tab and not the viewer` — `window_opened_by { thumbnail.click(:meta) }`, no `dialog#image-viewer[open]`.
  - `the arrows step through one message's pictures only, disabled at the ends, and say the name and position` — "1 of 2", Previous disabled; Next; "2 of 2", Next disabled, announcer text "<name>, 2 of 2"; never "of 3" (the PDF and the other message are out).
  - `the keyboard reaches a note's picture with Tab, Enter opens the viewer on Next, the arrows step, and Escape gives the focus back to the picture` — `stop_on` the thumbnail, `page.send_keys(:enter)`, focus on Next; `:right` → "2 of 2" and focus on Previous; `:left` → "1 of 2"; `:escape` → closed, `document.activeElement` is the thumbnail, the notes still open.
  - `an arrow with a modifier does not step` — `page.send_keys([:alt, :right])` keeps "1 of 2".
  - `a picture that can't be loaded says so and keeps Open original and Download` — destroy the second file's `ActiveStorage::Attachment` row after the page is drawn (the notes action then answers 404), step to it: the notice text shown, the picture hidden, both links there.
  - `with reduced motion a GIF in the viewer is a still with Play, and each opening starts it still` — open a `small.gif`, Play → Pause, close, open again → Play.
  - `a slow picture shows Loading after 400 ms, a cached one never does` — make the picture's response slow by a test seam the controller reads (for example a `window` override of the delay, or holding the request), never a sleep the test waits out over two seconds; assert the `loading` status absent at once and shown after the delay; then a step back to the loaded picture shows none.
  - `a phone draws the viewer over the whole screen with the arrows in the foot` — a 390×760 window (the helper `notes_drawer_test.rb`'s "under 640px" tests use), the dialog's rect equals the viewport, the stage arrows not visible, the foot's visible.
  - `the viewer is closed and empty in Turbo's snapshot: Back shows no open viewer` — open it, visit another screen through a link, go back: no `dialog#image-viewer[open]`, no `#image-viewer img[src]`.
  Update `note_files_test.rb`'s first test: its name becomes "…, and the picture opens in the viewer through the notes action", its click asserts the viewer and its `window_opened_by` uses Open original.
- [ ] **Step 2: Run** `bin/rails test test/system/admin/image_viewer_test.rb` (alone, quiet machine) — Expected: FAIL (no viewer opens).
- [ ] **Step 3: Implement** the controller and the marks; name the tests in the component's contract (`open`, `stepped`, `failed`, `keyboard`) and empty `KEYBOARD_NOT_YET`.
- [ ] **Step 4: Run** `bin/rails test test/components/admin/ui/contract_test.rb test/lib/component_parts_test.rb test/lib/admin_i18n_test.rb`, then each browser file alone: `test/system/admin/image_viewer_test.rb`, `test/system/admin/note_files_test.rb`, `test/system/admin/notes_drawer_test.rb` — Expected: PASS.
- [ ] **Step 5: Commit** — `feat: a note's picture opens in the image viewer`

### Task 5: Reference, CHANGELOG

**Files:**
- Modify: `docs/reference/notes.md` ("Files": the inline-image sentence and "there is no lightbox" become the viewer; "GIFs and reduced motion" names `admin--ui--gif` and `Admin::Ui::GifComponent`; the header's "Describes" list), `docs/reference/design-system.md` ("Shared components": ImageViewer and Gif; the Dialog's width steps), `app/controllers/admin/note_files_controller.rb` (the comment's "a click opens the same address in a new tab"), `CHANGELOG.md` ("Unreleased": `### Added` the viewer; `### Changed` a note's picture opens in it, ⌘-click or Open original opens a tab)

- [ ] **Step 1:** Write the reference lines (current invariants only: the group is a message's pictures read at opening; one viewer in the layout; the take-back at `turbo:before-cache`; Escape closes the viewer alone).
- [ ] **Step 2: Run** `bin/rails test test/lib` and `bin/rubocop` — Expected: PASS, no offences.
- [ ] **Step 3: Commit** — `docs: the image viewer in the notes and design-system references`

The pull request's "Documentation" names the editors' guide page on notes (its line on pictures).
