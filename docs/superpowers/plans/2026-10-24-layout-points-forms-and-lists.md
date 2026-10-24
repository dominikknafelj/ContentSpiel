# The layout points, part 1: CS Studio's forms and lists — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first of the spec's three pull requests, "CS Studio's forms and lists" (its sections A and B): the editors' and Settings' forms at 760px with a translation tab's two columns, the slug field without its second address line, Settings' nav, social links, logo and stuck save bar, one translation vocabulary, the Translations table's words and whole-row click, Media without a drop zone once it holds images, two-letter avatars, the post editor's related-posts help, and the reference card's disclosure triangle.

**Architecture:** One CS Studio token pair (`--cs-form-max`, `--cs-form-max-pair`) read by a class on the elements that are already there (`#post-form`, `#page-settings`, `section.admin-content-blocks`, Settings' grid), so the live-editing merge's markup does not change. Everything else is a component, a stylesheet rule or a small Stimulus controller on the screen it belongs to; the one rule that moves to the server is `PersonName.initials`, whose letters the two scripts are now handed. No query changes but one `exists?` on Media's search path.

**Tech Stack:** Rails 8.1, ViewComponent, Tailwind 4 (`tailwindcss-rails`), Stimulus over import maps, Minitest + fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-23-layout-points-design.md` (approved 2026-10-24). Read "What a person gets" A and B, Decisions 1–10, Rulings 1–6, Claude Design's answers O2, O3, O4 and the owner's O1, O7, O9, O11. Sections C (dashboard), D (Mind graph) and E (the public site), Decisions 11–17 and Rulings 5, 7, 8 are the two later plans' and not this one's.

## Global Constraints

- Read `CLAUDE.md` first; its rules bind. Before a task read the reference its area names: `docs/reference/design-system.md` (Tasks 1, 2, 5, 8), `docs/reference/editors-and-translation-pair.md` (Tasks 1–4), `docs/reference/live-editing.md` ("merge.js", Tasks 1 and 3), `docs/reference/save-rule-and-write-queue.md` (Task 8), `docs/reference/settings-languages-ai.md` (Tasks 5–7), `docs/reference/translations.md` (Tasks 9, 10), `docs/reference/media.md` (Task 11), `docs/reference/notes.md` and `docs/reference/presence.md` (Task 12), `docs/reference/i18n.md` (any task adding a key).
- The form width is a token and nowhere else: `--cs-form-max: 760px;` and `--cs-form-max-pair: 1144px;` in `app/assets/tailwind/content-spiel.css`'s `:root` block; no `760px` or `1144px` in the product stylesheet, and no `[760px]` class or `max-width: 760px` in any CS Studio source (a comment may name the number).
- The translation pair (O3): side by side from **824px** of form width (two columns of at least 400px and the gap), columns of **at most 560px**, a **24px** gap between them; stacked below, the original first.
- The editors' header, the notes drawer (400px), the tree-fit rule and `Admin::Shell::TreeDividerComponent`'s figures and the stylesheet's rem literals do not change (Decision 2). The column is left-aligned (O3).
- No new wrapper element around a unit of the editors: a class goes on the element that is there, so every ancestor of a unit keeps its id (`docs/reference/live-editing.md`, CLAUDE.md's merge rule).
- New or changed admin strings are keys in `config/locales/admin/*.en.yml` read with `t(".key")`; a new component file joins `CONVERTED` in `test/lib/admin_i18n_test.rb`.
- Tokens, not colours: a colour literal only in `content-spiel.css`; a control is outlined in `border-field-line`; no text under 11px (the "NONE" square's 9px goes, Ruling 6).
- One vocabulary (O4): ○ Missing, ↻ Outdated, ● Translated.
- Never define an `Admin::` constant named after a top-level domain (`test/lib/admin_namespace_shadow_test.rb`).
- Tests: every command prefixed `PGGSSENCMODE=disable`. One file: `PGGSSENCMODE=disable bin/rails test <path>`; one test: `… -n "/<fragment of its name>/"`. Before any system test: `bin/rails tailwindcss:build && bin/rails theme_css:build`, and **never a build while tests run**; never two test runs at once. The browser suite: `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`, on a quiet machine (`sysctl -n vm.loadavg` first).
- System tests: `press` or a native `click`, no fixed `sleep`; a test that resizes the window puts it back in an `ensure`; an element only a `hover:` style shows is found with `visible: :all`; any JavaScript error fails the test.
- Commits: one per task, conventional subject, never `--no-verify`, ending with exactly:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

- Nothing is pushed. No guide text in this repository: the guide pages are named in the PR's "Documentation" section (Task 13).

### Rulings of this plan

Where the spec left a choice, or its answers moved a number, this plan decides:

1. **O3's numbers replace Decision 1's 1,536px.** A translation tab's column is `--cs-form-max-pair: 1144px` (two 560px columns and a 24px gap); the pair goes side by side from 824px of form width.
2. **Settings stays 760px on its language tabs.** Its card column is one width for four cards; on a translation tab the pair there stacks (824 > 760), as it does in the Media panel.
3. **The cap is a class on existing elements** (`Admin::EditorScreen::FormColumn.classes(locale)`): `admin-form-column`, plus `admin-form-column--pair` on a non-default language.
4. **The dashboard's activity row keeps its own initials until plan 2**, which rewrites that row (Decision 11). This plan changes `PersonName.initials`, so notes, presence, the holder avatar and the hold strip change with it (O9's "notes and presence" half).
5. **The vocabulary's reach.** "Missing" replaces "not translated" in the chip (tooltip and name), the language tabs' screen-reader words and the matrix's cell names; the tabs' outdated words become "outdated" / "Outdated". The chip's outdated tooltip keeps its sentence (it names the language to compare with). The posts list's filter segments ("Needs translation", "Outdated", "Complete") stay: they name sets of posts, not a language's state. No mark, border or layout of the chip or the tabs changes ("What this does not do").
6. **The row's stretched link sits in the action cell, not the sticky title cell** (the spec's Risk): an empty `<a>` with `tabindex="-1"` and `aria-hidden`, `absolute inset-0` against `tr.relative`; the title cell is `z-20`, the cell links `z-10`. "Translate →" is an `aria-hidden` span shown by `opacity` (not `visibility`, which would let clicks through). The title link is named for the action ("Translate: About us", Ruling 4).
7. **The stuck save bar** is found by `-bottom-px` and an `IntersectionObserver` at threshold 1 on the bar; the shadow is a token, `--cs-shadow-stuck`: `0 -6px 16px rgba(20,20,23,0.06)` in light and `rgba(20,20,23,0.12)` in dark (the design's "ink", which in the dark scheme is light and would glow; as `--cs-shadow-menu` does, the dark shadow stays dark).
8. **The social links' marker** is `site_setting[social_links_present]`, and `Values#social_rows` honours it too, so a save refused for another reason keeps a cleared list cleared.
9. **The reference card's triangle shows only where the card folds** (stacked): side by side its summary is inert, so the triangle is hidden there.
10. **Settings' current section**: the last heading whose top is above 40% of the window; on a page that scrolls and is scrolled to its end, the last; on a page that does not scroll, the first. The look is ink text and `inset 2px 0 0 var(--cs-ink)`, drawn from `aria-current="true"` by the stylesheet.
11. **The related-posts help** (O7) reads "Related posts are linked to this one in the Mind graph. The site does not show them yet.", as a key.
12. **Media**: the zone's wrapper is `hidden` when the library holds a kept image; the file input inside it stays the upload controller's `input` target. A library whose images are all in the trash is empty.

## Review Focus

1. **A Settings save refused after every social link was removed** (a blank title, say): the 422 must show no rows, not bring the stored links back (Task 7: `"a refused save after removing every link shows no rows, not the stored ones"`).
2. **A cell's own link under the row's overlay**: a click on "◐ Español" must open Español, not the row's focus language (Task 10: `"a click on an empty part of a row opens the row's language, and a cell's link still opens its own"`).
3. **An empty slug when the editor opens**: before anything is typed the placeholder already says the slug the title will give (Task 3: `"an empty slug says the slug the title will give as soon as the editor opens, and follows the title"`).
4. **A library whose only images are in the trash**: it is empty, so the zone is drawn (Task 11: `"the drop zone is drawn for an empty library"`).
5. **Settings on a window tall enough that nothing scrolls**: "Site" is the current section, not the last one (Task 6: `"on a window where nothing scrolls the first section is current"`).

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `app/assets/tailwind/content-spiel.css` | `--cs-form-max`, `--cs-form-max-pair`; `--cs-shadow-stuck` (light, dark) | 1, 8 |
| `app/assets/tailwind/content-spiel.tailwind.css` | `.admin-form-column`; the pair's 824/560/24; the card's triangle; the nav's current look; the stuck bar; the matrix row's action | 1, 2, 6, 8, 10 |
| `app/components/admin/editor_screen/form_column.rb` (new) | `Admin::EditorScreen::FormColumn.classes(locale)` | 1 |
| `post_form_component.html.erb`, `page_settings_form_component.html.erb`, `app/views/admin/pages/show.html.erb` | wear the column class | 1 |
| `reference_card_component.html.erb` | the summary as an `.admin-disclosure` | 2 |
| `app/components/admin/columns/slug_column_component.{rb,html.erb}`, `app/javascript/controllers/admin/editor/slug_preview_controller.js` | no address line; the placeholder | 3 |
| `related_posts_component.html.erb`, `config/locales/admin/editor_screen.en.yml` | the help text as a key | 4 |
| `app/views/admin/settings/show.html.erb`, `site_card_component.html.erb`, `ai_key_component.html.erb` | 760px, fields fill, no NONE | 5 |
| `app/components/admin/settings_screen/nav_component.html.erb`, `app/javascript/controllers/admin/settings/nav_controller.js` (new) | the current section | 6 |
| `values.rb`, `site_card_component.html.erb`, `app/controllers/admin/settings_controller.rb`, `repeat_rows_controller.js` | "+ Add link", the marker | 7 |
| `app/components/admin/ui/save_bar_component.rb`, `save_bar_controller.js` | `data-stuck` | 8 |
| `config/locales/admin/ui.en.yml`, `translation_screen.en.yml` | the three words | 9 |
| `app/components/admin/translation_screen/state_cell_component.rb` (new), `matrix_component.{rb,html.erb}` | the cell's mark and word; the row | 10 |
| `app/services/media/search.rb`, `app/controllers/admin/media_controller.rb`, `app/views/admin/media/index.html.erb` | `any_images?`; the zone | 11 |
| `app/values/person_name.rb`, `note_threads_controller.rb`, `note_mentions_controller.rb`, `mind_graph/card_notes.js`, `notes/composer_controller.js` | two letters, on the server | 12 |
| `CLAUDE.md`, `docs/reference/*.md`, `docs/roadmap.md`, the spec | documents | 13 |

---

### Task 1: The form column at 760px, and a translation tab's two columns

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (the `:root` block after `--cs-ease`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (the "Side-by-side translation" block, about lines 471–500)
- Create: `app/components/admin/editor_screen/form_column.rb`
- Modify: `app/components/admin/editor_screen/post_form_component.html.erb` (the `form_with … id: "post-form"` class), `app/components/admin/editor_screen/page_settings_form_component.html.erb` (line 1, the `<details>` class), `app/views/admin/pages/show.html.erb` (the `section.admin-content-blocks` class)
- Modify (comments only): `app/components/admin/editor_screen/reference_card_component.rb` (the "880px" sentence), `app/components/admin/media_library/panel_component.rb` (the "narrower than 880px" sentence)
- Test: `test/components/admin/editor_screen/form_column_test.rb` (new), `test/components/admin/editor_screen/post_form_component_test.rb`, `test/components/admin/editor_screen/page_settings_form_component_test.rb`, `test/integration/admin/page_editor_test.rb`, `test/lib/admin_design_rules_test.rb`, `test/system/admin/form_width_test.rb` (new), and the premises of `test/system/admin/translation_layout_test.rb`, `test/system/admin/notes_column_test.rb`, `test/system/admin/media_library_test.rb`, `test/system/admin/rich_text_test.rb`

**Interfaces:**
- Produces: `Admin::EditorScreen::FormColumn.classes(locale) -> String` (`"admin-form-column"` for `::Locales.default`, `"admin-form-column admin-form-column--pair"` otherwise); CSS custom properties `--cs-form-max`, `--cs-form-max-pair`; class `.admin-form-column` (Task 5 reads `--cs-form-max`).

- [ ] **Step 1: Write the failing unit, component and integration tests**

`test/components/admin/editor_screen/form_column_test.rb`:

```ruby
require "test_helper"

# The editors' form column (layout points spec, decisions 1-3): one class for
# the 760px column, and a second one on a translation tab, whose pairs need two
# columns (Claude Design's O3).
class Admin::EditorScreen::FormColumnTest < ActiveSupport::TestCase
  include ContentHelper

  test "the default language's column is the 760px one, any other language's the pair's" do
    with_locales(%w[en de], default: "en")

    assert_equal "admin-form-column", Admin::EditorScreen::FormColumn.classes("en")
    assert_equal "admin-form-column admin-form-column--pair", Admin::EditorScreen::FormColumn.classes("de")
    assert_equal "admin-form-column admin-form-column--pair", Admin::EditorScreen::FormColumn.classes(:de)
  end
end
```

In `post_form_component_test.rb`:

```ruby
  test "the form is the editors' form column: 760px on the default tab, the pair's width on a translation tab, and the header is neither" do
    with_locales(%w[en de], default: "en")
    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: @post, locale: "en") }
    assert_selector "form#post-form.admin-translation-form.admin-form-column:not(.admin-form-column--pair)"
    assert_no_selector ".admin-editor-header.admin-form-column"

    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: @post, locale: "de") }
    assert_selector "form#post-form.admin-form-column.admin-form-column--pair"
  end
```

In `page_settings_form_component_test.rb`:

```ruby
  test "the settings panel is the editors' form column, the pair's on a translation tab" do
    with_locales(%w[en de], default: "en")
    page = create_page(title: "About", published: false)

    render_settings(page)
    assert_selector "details#page-settings.admin-form-column:not(.admin-form-column--pair)"
    render_settings(page, locale: "de")
    assert_selector "details#page-settings.admin-form-column.admin-form-column--pair"
  end
```

In `test/integration/admin/page_editor_test.rb`:

```ruby
  test "the block list is the editors' form column, the pair's on a translation tab" do
    get "/cs-studio/pages/#{@page.id}"
    assert_select "section.admin-content-blocks.admin-form-column:not(.admin-form-column--pair)"

    get "/cs-studio/pages/#{@page.id}?locale=de"
    assert_select "section.admin-content-blocks.admin-form-column.admin-form-column--pair"
  end
```

In `test/lib/admin_design_rules_test.rb`:

```ruby
  # Layout points spec, decision 1: one cap, one place.
  test "the form column's width is a token: 760px and 1144px are written once, in content-spiel.css" do
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    assert_equal 1, tokens.scan("--cs-form-max: 760px;").size
    assert_equal 1, tokens.scan("--cs-form-max-pair: 1144px;").size

    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-form-column\s*\{\s*max-width:\s*var\(--cs-form-max\);\s*\}/, css)
    assert_match(/\.admin-form-column--pair\s*\{\s*max-width:\s*var\(--cs-form-max-pair\);\s*\}/, css)
    assert_match(/@container \(min-width: 824px\)\s*\{\s*\.admin-translation-pair\s*\{\s*grid-template-columns:\s*repeat\(2, minmax\(0, 560px\)\);/m, css)
    assert_no_match(/\b(?:760|1144)px/, css)
    assert_empty design_offences(/\[(?:760|1144)px\]|max-width:\s*(?:760|1144)px/)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/form_column_test.rb test/components/admin/editor_screen/post_form_component_test.rb test/components/admin/editor_screen/page_settings_form_component_test.rb test/integration/admin/page_editor_test.rb test/lib/admin_design_rules_test.rb`
Expected: FAIL — `uninitialized constant Admin::EditorScreen::FormColumn`, the column selectors not found, the token not in `content-spiel.css`.

- [ ] **Step 3: The tokens and the stylesheet**

In `content-spiel.css`'s `:root` block (the one with `--cs-font`), after `--cs-ease`:

```css
  /* The editors' and Settings' form column (layout points spec, decision 1),
     and on an editor's translation tab two 560px columns and their 24px gap
     (Claude Design's O3). Read by `.admin-form-column` and Settings' grid. */
  --cs-form-max: 760px;
  --cs-form-max-pair: 1144px;
```

In `content-spiel.tailwind.css`, after the "Side-by-side translation" comment block, with a comment saying the column is left-aligned and why the class sits on existing elements (Ruling 3):

```css
.admin-form-column { max-width: var(--cs-form-max); }
.admin-form-column--pair { max-width: var(--cs-form-max-pair); }
```

Change the pair's rules to O3's numbers (the comment above them: 880px becomes 824px, "two columns of at least 400px and the gap"):

```css
.admin-translation-pair { display: grid; column-gap: 1.5rem; row-gap: 1rem; grid-template-columns: minmax(0, 1fr); }
@container (min-width: 824px) {
  .admin-translation-pair { grid-template-columns: repeat(2, minmax(0, 560px)); }
  /* the three rules for the reference card's details and summary, as they are */
}
@container (max-width: 823.98px) {
  .admin-translation-pair > .admin-reference-card { order: -1; }
}
```

- [ ] **Step 4: `Admin::EditorScreen::FormColumn` and its three users**

Create `app/components/admin/editor_screen/form_column.rb`: `module Admin::EditorScreen::FormColumn` with `def self.classes(locale)` comparing `locale.to_s` with `::Locales.default`; its comment names the three elements, the merge rule that keeps them free of a wrapper, and O3. Then:
- `post_form_component.html.erb`: `class: "admin-translation-form #{Admin::EditorScreen::FormColumn.classes(locale)} flex flex-col gap-4 …"` on `#post-form`.
- `page_settings_form_component.html.erb`: the `<details id="page-settings">` class gains `#{Admin::EditorScreen::FormColumn.classes(locale)}`.
- `app/views/admin/pages/show.html.erb`: `section.admin-content-blocks` gains `<%= Admin::EditorScreen::FormColumn.classes(admin_locale) %>`.
- The two comments that say 880px say 824px.

- [ ] **Step 5: Run the tests of Step 1**

Run: the command of Step 2.
Expected: PASS.

- [ ] **Step 6: Write the browser tests, and move the premises to 824px**

`test/system/admin/form_width_test.rb`:

```ruby
require "application_system_test_case"

# The editors' form column (layout points spec, A): 760px whatever the window,
# left-aligned in the content column, the header still full width; a
# translation tab two columns of up to 560px (O3). Only layout can show it.
class Admin::FormWidthSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    sign_in_via_form(users(:one))
    @post = create_post(title: "Notes")
    @page = create_page(title: "About")
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } })
  end

  test "at 1600px the post form is 760px wide, starts at the content's left edge, and the header keeps its width" do
    at_1600 do
      visit "/cs-studio/posts/#{@post.id}"
      await_admin_controllers

      form = box("#post-form")
      assert_in_delta 760, form[2] - form[0], 1
      assert_in_delta content_left, form[0], 1
      assert_operator box(".admin-editor-header")[2], :>, 1500
    end
  end

  test "at 1600px the page settings and the block list are 760px wide, one above the other" do
    at_1600 do
      visit "/cs-studio/pages/#{@page.id}"
      await_admin_controllers

      settings = box("#page-settings")
      blocks = box(".admin-content-blocks")
      assert_in_delta 760, settings[2] - settings[0], 1
      assert_in_delta 760, blocks[2] - blocks[0], 1
      assert_in_delta settings[0], blocks[0], 1
    end
  end

  test "at 1600px a translation tab is wider than 760px and at most 1144px, and its pairs sit side by side" do
    at_1600 do
      visit "/cs-studio/posts/#{@post.id}?locale=de"
      await_admin_controllers

      form = box("#post-form")
      assert_operator form[2] - form[0], :>, 760
      assert_operator form[2] - form[0], :<=, 1144
      field = box("[data-field-name='title'] .admin-translation-pair > div:first-child")
      original = box("[data-original-for='title']")
      assert_in_delta field[1], original[1], 4, "the field and its original share a row"
      assert_operator original[2] - original[0], :<=, 561
    end
  end

  private

  def at_1600
    page.driver.resize(1600, 1000)
    yield
  ensure
    page.driver.resize(1400, 1400)
  end

  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def content_left
    page.evaluate_script("(() => { const main = document.querySelector('.admin-shell__main'); return main.getBoundingClientRect().left + parseFloat(getComputedStyle(main).paddingLeft) })()")
  end
end
```

The premises that name 880px now name 824px, and nothing else in them changes: `translation_layout_test.rb` (the class comment and `assert_operator form_width, :<, 824, "the premise: at 1100px the block form is under 824px …"`), `notes_column_test.rb` (the test renamed `"a translation pair stacks, the original first, when the notes column leaves its form under 824px"`, its two `880`s `824`), `media_library_test.rb:97` (`:<, 824`, "narrower than 824px"), and the comment above the narrow test in `rich_text_test.rb`. In `notes_column_test.rb`'s test `"a remembered open lays the next editor out with the column, and a window under 1024px keeps the sheet"`, the last line (`box(".admin-content-blocks")[2] > 800`, which a 760px list no longer reaches) becomes:

```ruby
      blocks = box(".admin-content-blocks")
      assert_in_delta 760, blocks[2] - blocks[0], 1, "no room is kept for the notes: the list is its own 760px"
```

- [ ] **Step 7: Run the browser tests**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/form_width_test.rb test/system/admin/translation_layout_test.rb test/system/admin/notes_column_test.rb test/system/admin/media_library_test.rb test/system/admin/rich_text_test.rb test/system/admin/sections_test.rb test/system/admin/tree_column_test.rb`
Expected: PASS. A premise that fails names the measured width: it is the premise that moved, not the rule (re-read the window it is measured at before changing a number).

- [ ] **Step 8: Commit**

```bash
git add app/assets/tailwind app/components/admin/editor_screen/form_column.rb app/components/admin/editor_screen/post_form_component.html.erb app/components/admin/editor_screen/page_settings_form_component.html.erb app/components/admin/editor_screen/reference_card_component.rb app/components/admin/media_library/panel_component.rb app/views/admin/pages/show.html.erb test
git commit -m "feat: the editors' form column is 760px, and a translation tab two columns of 560px

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 2: The reference card's disclosure triangle (O11, part 1's left-over)

**Files:**
- Modify: `app/components/admin/editor_screen/reference_card_component.html.erb` (the `<summary>`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (inside `@container (min-width: 824px)`)
- Test: `test/lib/admin_design_rules_test.rb` (`"a disclosure's triangle is the stylesheet's, apart from its words, turned when open"`), `test/components/admin/editor_screen/reference_card_component_test.rb`

**Interfaces:**
- Consumes: Task 1's `@container (min-width: 824px)` block.

- [ ] **Step 1: Write the failing tests**

In the design-rules test `"a disclosure's triangle is the stylesheet's, apart from its words, turned when open"`, add `app/components/admin/editor_screen/reference_card_component.html.erb` to the list of paths, and before the list:

```ruby
    # The reference card folds only when stacked; side by side its summary is inert, and shows no triangle.
    assert_match(/\.admin-translation-pair > \.admin-reference-card > details > summary::before\s*\{\s*display:\s*none;/, css)
```

In `reference_card_component_test.rb`:

```ruby
  test "the summary is a disclosure: the triangle, the language, and the change time at the far end" do
    post = create_post(title: "Hello")
    render_inline Admin::EditorScreen::ReferenceCardComponent.new(field: "title", locale: "de", original: "Hello", record: post)

    assert_selector "summary.admin-disclosure > span:first-child", text: Locales.name(Locales.default, native: true)
    assert_no_selector "summary.justify-between"
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/components/admin/editor_screen/reference_card_component_test.rb`
Expected: FAIL — the summary has no `admin-disclosure`, the stylesheet no hiding rule.

- [ ] **Step 3: The summary and the rule**

The summary's class becomes `admin-disclosure cursor-pointer font-cs-mono text-label uppercase tracking-mono text-meta` (no `flex`, `items-baseline`, `justify-between` or `gap-2`: `.admin-disclosure` is the flex row and its 6px gap); the "↻ Changed" span gains `ml-auto`, so the triangle stands before the language and the change time at the far end. In the `@container (min-width: 824px)` block add, with a one-line comment (Ruling 9):

```css
  .admin-translation-pair > .admin-reference-card > details > summary::before { display: none; }
```

- [ ] **Step 4: Run the tests, and the translation layout's browser tests**

Run: the command of Step 2, then (after `bin/rails tailwindcss:build`) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/translation_layout_test.rb`
Expected: PASS ("the stacked original folds away" still clicks the summary).

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/editor_screen/reference_card_component.html.erb app/assets/tailwind/content-spiel.tailwind.css test/lib/admin_design_rules_test.rb test/components/admin/editor_screen/reference_card_component_test.rb
git commit -m "feat: the stacked reference card's summary has the disclosure triangle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 3: The slug line goes; the placeholder says the derived slug

**Files:**
- Modify: `app/components/admin/columns/slug_column_component.html.erb` (remove the `<p>` with `data-slug-preview-base` and the output target, and the comment about it), `app/components/admin/columns/slug_column_component.rb` (its comment)
- Modify: `app/javascript/controllers/admin/editor/slug_preview_controller.js`
- Test: `test/components/admin/columns/slug_column_component_test.rb`, `test/components/admin/editor_screen/page_settings_form_component_test.rb`, `test/system/admin/editor_fields_test.rb`

**Interfaces:**
- Produces: `admin--editor--slug-preview` keeps the targets `title` and `slug` and the action `update` (the held form's allow-list, `HeldFields::CMS_ACTIONS`, is unchanged, Decision 4); the target `output` is gone.

- [ ] **Step 1: Write the failing tests**

In `slug_column_component_test.rb`, replace `"renders the slug input and a live URL preview line"` and the last assertion of `"the slug sits in a prefix input and keeps its data attributes and error slot"` (the `output` target):

```ruby
  test "the address is shown once: the prefix and the slug in the field, and no line under it" do
    render_inline Admin::Columns::SlugColumnComponent.new(value: "about-us", base_url: "https://example.com/company")

    assert_selector "input[type=text][name=slug][value='about-us']"
    assert_selector ".admin-prefix-input span", text: "example.com/company/"
    assert_no_text "example.com/company/about-us"
    assert_no_selector "[data-admin--editor--slug-preview-target=output], [data-slug-preview-base]"
  end
```

In `page_settings_form_component_test.rb`'s `"a live page's settings show its address …"` test, after the draft's slug field assertion:

```ruby
    assert_no_selector "[data-admin--editor--slug-preview-target=output]", visible: :all
```

In `editor_fields_test.rb` (Review Focus 3):

```ruby
  test "an empty slug says the slug the title will give as soon as the editor opens, and follows the title" do
    post = create_post(title: "Notes on Rails", published: false)
    post.update_columns(slug: {}) # version: none (a test's own setup: a draft whose slug was never filled)
    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers

    slug = find("[data-admin--editor--slug-preview-target=slug]")
    assert_equal "", slug.value
    assert_equal "notes-on-rails", slug[:placeholder]

    find("[data-admin--editor--slug-preview-target=title]").set("Hello, World")
    assert_eventually(message: "the placeholder never followed the title") { slug[:placeholder] == "hello-world" }
    assert_writes_settled
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/columns/slug_column_component_test.rb test/components/admin/editor_screen/page_settings_form_component_test.rb`, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editor_fields_test.rb -n "/empty slug/"`
Expected: FAIL — the line is drawn, the placeholder is empty.

- [ ] **Step 3: The component and the controller**

Remove the address line from the template. In `slug_preview_controller.js`: `static targets = ["title", "slug"]`; `connect()` calls `update()`; `update()` sets `this.slugTarget.placeholder` to `slugify` of the title's value (when both targets are there) and writes nothing else; the exported `slugify` is unchanged (the New page dialog imports it). Rewrite the file's comment: the placeholder now carries the one job the line had, the real slug is still the server's (`LocalizedSlug#fill_blank_slugs`), and `connect` runs again whenever a live refresh replaces the form, so a refreshed form has its placeholder too.

- [ ] **Step 4: Run the tests of Step 2, and the held form's and the editors' tests**

Run: the commands of Step 2, then `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/held_fields_test.rb test/components/admin/editor_screen/post_form_component_test.rb test/integration/admin/page_editor_test.rb`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/editing_holds_test.rb test/system/admin/new_record_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/columns app/javascript/controllers/admin/editor/slug_preview_controller.js test
git commit -m "feat: the slug field shows the address once; its placeholder is the slug the title gives

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 4: The related-posts help stops promising the site (O7)

**Files:**
- Modify: `app/components/admin/editor_screen/related_posts_component.html.erb` (line 4, `help:`)
- Modify: `config/locales/admin/editor_screen.en.yml` (a `related_posts:` group under `editor_screen:`)
- Test: `test/components/admin/editor_screen/related_posts_component_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  # The owner's O7: the public post page shows no related posts, so the help does not say it does.
  test "the help says where related posts show: the Mind graph, not yet the site" do
    render_inline Admin::EditorScreen::RelatedPostsComponent.new(post: create_post(title: "Hub"), locale: "en")

    assert_text "Related posts are linked to this one in the Mind graph. The site does not show them yet."
    assert_no_text "end of the article"
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/related_posts_component_test.rb -n "/where related posts show/"`
Expected: FAIL — the old sentence.

- [ ] **Step 3: The key**

Under `admin.components.editor_screen` add, with a comment naming O7:

```yaml
        related_posts:
          help: "Related posts are linked to this one in the Mind graph. The site does not show them yet."
```

and the template's `help:` reads `t(".help")`.

- [ ] **Step 4: Run it to see it pass**

Run: the command of Step 2, then `PGGSSENCMODE=disable bin/rails test test/lib/admin_i18n_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/editor_screen/related_posts_component.html.erb config/locales/admin/editor_screen.en.yml test/components/admin/editor_screen/related_posts_component_test.rb
git commit -m "fix: the related-posts help no longer promises them on the site

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 5: Settings at 760px, its fields filling their card, no "NONE" square

**Files:**
- Modify: `app/views/admin/settings/show.html.erb` (line 30, the grid)
- Modify: `app/components/admin/settings_screen/ai_key_component.html.erb` (line 23, the key input's `max-w-md`)
- Modify: `app/components/admin/settings_screen/site_card_component.html.erb` (the logo's `else` branch and its comment)
- Test: `test/components/admin/settings_screen/site_card_component_test.rb`, `test/system/admin/settings_test.rb`

**Interfaces:**
- Consumes: Task 1's `--cs-form-max`.

- [ ] **Step 1: Write the failing tests**

In `site_card_component_test.rb`, replace `"logo shows a NONE tile without one, and the drop zone with its help"`:

```ruby
  test "without a logo only the drop zone and its hint are drawn: no NONE square" do
    render_card

    assert_no_text "NONE"
    assert_no_selector "[data-field-name=logo] img, [data-field-name=logo] .bg-sunken"
    assert_selector "input[type=file][name='site_setting[logo]']", visible: :all
    assert_text "PNG, JPEG, GIF or WebP. Without a logo the site title is shown."
    assert_no_selector "input[name='site_setting[remove_logo]']", visible: :all
  end
```

In `test/system/admin/settings_test.rb`:

```ruby
  test "at 1600px every card is 760px wide, a text field fills it and Time zone keeps its own width" do
    page.driver.resize(1600, 1000)
    visit admin_settings_path
    await_admin_controllers

    width = ->(selector) { page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().width") }
    %w[#settings-site-card [aria-labelledby=languages] [aria-labelledby=publishing] [aria-labelledby=ai]].each do |card|
      assert_in_delta 760, width.(card), 1, card
    end
    assert_operator width.("#settings-en-title"), :>, 700
    assert_operator width.("#settings-time_zone"), :<=, 384
  ensure
    page.driver.resize(1400, 1400)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen/site_card_component_test.rb`, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/settings_test.rb -n "/760px wide/"`
Expected: FAIL — "NONE" is drawn; the cards are about 900px.

- [ ] **Step 3: The grid, the key and the logo**

- `show.html.erb`: `class="grid grid-cols-1 items-start gap-x-7 gap-y-4 lg:grid-cols-[170px_minmax(0,var(--cs-form-max))]"` (no `max-w-[1100px]`), and its comment says "a card column of `--cs-form-max`" instead of "up to 1100px".
- `ai_key_component.html.erb`: the key input's `max-w-md` becomes `min-w-0 flex-1` (it shares its row with Save key and Cancel, which wrap below it on a narrow card).
- `site_card_component.html.erb`: the logo row draws the `image_tag` only when a logo is attached, and no `else`; the comment above it says "the stored logo, if any".

- [ ] **Step 4: Run the tests of Step 2 and the Settings suites**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen test/integration/admin/settings_test.rb`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/settings_test.rb test/system/admin/ai_settings_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/settings/show.html.erb app/components/admin/settings_screen test
git commit -m "feat: Settings' cards are 760px, the API key fills its row, and no NONE square

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 6: Settings' nav shows the section in view

**Files:**
- Create: `app/javascript/controllers/admin/settings/nav_controller.js`
- Modify: `app/components/admin/settings_screen/nav_component.html.erb`, `app/components/admin/settings_screen/nav_component.rb` (its comment)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (after the shell's rules)
- Test: `test/components/admin/settings_screen/nav_component_test.rb`, `test/system/admin/settings_test.rb`

**Interfaces:**
- Produces: Stimulus identifier `admin--settings--nav`, target `link`, action `reset` (on `turbo:before-cache@document`); `aria-current="true"` on the current link.

- [ ] **Step 1: Write the failing tests**

In `nav_component_test.rb`:

```ruby
  test "the nav is the current-section controller's, and the server marks no link current" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: Admin::SettingsScreen::NavComponent::SECTIONS)

    assert_selector "nav[aria-label='Settings sections'][data-controller='admin--settings--nav'][data-action~='turbo:before-cache@document->admin--settings--nav#reset']"
    assert_selector "a[data-admin--settings--nav-target=link]", count: 4
    assert_no_selector "a[aria-current]"
  end
```

In `test/system/admin/settings_test.rb` (Review Focus 5 is the second):

```ruby
  test "the section in view is the nav's current one, in ink with the bar, and follows the scroll" do
    page.driver.resize(1400, 700)
    visit admin_settings_path
    await_admin_controllers
    nav = "nav[aria-label='Settings sections']"

    assert_selector "#{nav} a[aria-current=true]", text: "Site", count: 1
    look = page.evaluate_script("(() => { const s = getComputedStyle(document.querySelector(#{"#{nav} a[aria-current=true]".to_json})); return [ s.color, s.boxShadow ] })()")
    ink = page.evaluate_script("getComputedStyle(document.body).getPropertyValue('--cs-ink')")
    assert_match(/inset/, look[1])
    assert_equal look[0], page.evaluate_script("(() => { const p = document.createElement('p'); p.style.color = #{ink.strip.to_json}; document.body.append(p); const c = getComputedStyle(p).color; p.remove(); return c })()")

    page.execute_script("document.getElementById('publishing').scrollIntoView({ block: 'start' })")
    assert_selector "#{nav} a[aria-current=true]", text: "Publishing", count: 1
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    assert_selector "#{nav} a[aria-current=true]", text: "AI translation", count: 1
  ensure
    page.driver.resize(1400, 1400)
  end

  test "on a window where nothing scrolls the first section is current" do
    page.driver.resize(1400, 4000)
    visit admin_settings_path
    await_admin_controllers

    assert_selector "nav[aria-label='Settings sections'] a[aria-current=true]", text: "Site", count: 1
  ensure
    page.driver.resize(1400, 1400)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen/nav_component_test.rb`, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/settings_test.rb -n "/current/"`
Expected: FAIL — no controller, no `aria-current`.

- [ ] **Step 3: The controller, the markup and the look**

`nav_component.html.erb`: the `<nav>` carries `data-controller="admin--settings--nav"` and `data-action="turbo:before-cache@document->admin--settings--nav#reset"`; each `<a>` `data-admin--settings--nav-target="link"`. The component's comment adds the current section (Decision 5) and that the links work as before without the script.

`nav_controller.js` (Ruling 10; the comment at its top says what decides "current", that nothing it writes is kept by Turbo's snapshot, and that a heading is found by the link's own fragment):

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "link" ]

  connect() {
    this.headings = this.linkTargets.map((link) => document.getElementById(link.hash.slice(1)))
    this.observer = new IntersectionObserver(() => this.mark(), { threshold: [ 0, 0.25, 0.5, 0.75, 1 ] })
    this.headings.forEach((heading) => { if (heading) this.observer.observe(heading.closest("section") || heading) })
    this.mark()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  reset() {
    this.linkTargets.forEach((link) => link.removeAttribute("aria-current"))
  }

  mark() {
    const root = document.documentElement
    const scrolls = root.scrollHeight > window.innerHeight + 2
    const atEnd = scrolls && window.scrollY + window.innerHeight >= root.scrollHeight - 2
    let current = 0
    this.headings.forEach((heading, index) => { if (heading && heading.getBoundingClientRect().top <= window.innerHeight * 0.4) current = index })
    if (atEnd) current = this.headings.length - 1
    this.linkTargets.forEach((link, index) => {
      if (index === current) link.setAttribute("aria-current", "true")
      else link.removeAttribute("aria-current")
    })
  }
}
```

The stylesheet, with a comment ("the look is read from `aria-current`, so it cannot drift from what a screen reader hears; the selected tree row's ink bar"):

```css
.admin-settings-nav a[aria-current="true"] { color: var(--cs-ink); box-shadow: inset 2px 0 0 var(--cs-ink); }
```

- [ ] **Step 4: Run the tests of Step 2, and the identifier guard**

Run: the commands of Step 2, then `PGGSSENCMODE=disable bin/rails test test/lib/source_layout_test.rb test/lib/inline_handlers_test.rb`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/settings_test.rb test/system/save_bar_test.rb`
Expected: PASS ("the nav's anchors jump within the page without asking or adding history" too).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/admin/settings/nav_controller.js app/components/admin/settings_screen/nav_component.html.erb app/components/admin/settings_screen/nav_component.rb app/assets/tailwind/content-spiel.tailwind.css test
git commit -m "feat: Settings' nav marks the section in view

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 7: Social links start as "+ Add link"

**Files:**
- Modify: `app/components/admin/settings_screen/values.rb` (`social_rows`)
- Modify: `app/components/admin/settings_screen/site_card_component.html.erb` (the fieldset)
- Modify: `app/controllers/admin/settings_controller.rb` (`update`'s `permit`, `site_arguments`)
- Modify: `app/javascript/controllers/admin/settings/repeat_rows_controller.js` (`remove`, the file's comment)
- Test: `test/components/admin/settings_screen/site_card_component_test.rb`, `test/integration/admin/settings_test.rb`, `test/system/admin/settings_test.rb`

**Interfaces:**
- Produces: the form field `site_setting[social_links_present]` = `"1"` inside `#settings-social-links`; `Values#social_rows -> Array<[String, String]>`, empty for a site with no links.

- [ ] **Step 1: Write the failing tests**

In `site_card_component_test.rb`, replace `"the time zone, with its help, and one empty social link row with a template for more"`:

```ruby
  test "the time zone with its help; no social link row without a link, the marker, a template and + Add link" do
    render_card

    assert_selector "select[name='site_setting[time_zone]']"
    assert_text "Used for scheduled publishing."
    assert_no_selector "[data-admin--settings--repeat-rows-target=list] input"
    assert_selector "#settings-social-links input[type=hidden][name='site_setting[social_links_present]'][value='1']", visible: :all
    assert_selector "template#settings-social-link-template", visible: :all
    assert_selector "button[data-action='admin--settings--repeat-rows#add']", text: "+ Add link"
  end
```

In `test/integration/admin/settings_test.rb`, replace `"a single blank row, what removing the last link leaves, clears the stored links"` and `"with no social links the form shows one empty row"`, and add the two the spec's Risks name and Review Focus 1:

```ruby
  test "the fieldset posted with no rows clears the stored links" do
    @site.update!(social_links: { "GitHub" => "https://github.com/dana" })

    save social_links_present: "1"

    assert_response :see_other
    assert_equal({}, @site.reload.social_links.to_h)
  end

  test "a form without the marker and without rows leaves the stored links alone" do
    @site.update!(social_links: { "GitHub" => "https://github.com/dana" })

    save time_zone: "Berlin"

    assert_response :see_other
    assert_equal({ "GitHub" => "https://github.com/dana" }, @site.reload.social_links.to_h)
  end

  test "with no social links the form shows no row, only + Add link" do
    get "/cs-studio/settings"

    assert_select "#settings-social-links [data-admin--settings--repeat-rows-target=list] input", 0
    assert_select "template#settings-social-link-template input[name$='[name]']", 1
    assert_select "button", text: "+ Add link"
  end

  test "a refused save after removing every link shows no rows, not the stored ones" do
    @site.update!(social_links: { "GitHub" => "https://github.com/dana" })

    save social_links_present: "1", translations: { Locales.default => { title: "" } }

    assert_response :unprocessable_entity
    assert_select "#settings-social-links [data-admin--settings--repeat-rows-target=list] input", 0
    assert_equal({ "GitHub" => "https://github.com/dana" }, @site.reload.social_links.to_h)
  end
```

In `test/system/admin/settings_test.rb`, replace `"removing the only social link, then Save, deletes it"`:

```ruby
  test "removing the only social link removes its row, and Save deletes it" do
    site_settings(:default).update!(social_links: { "GitHub" => "https://github.com/dana" })
    visit admin_settings_path
    await_admin_controllers

    find("button[aria-label='Remove link']").click
    assert_selector footer, text: /unsaved change/i
    assert_no_selector "[data-admin--settings--repeat-rows-target=row]"
    assert_selector "button[data-action='admin--settings--repeat-rows#add']:focus"
    press "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal({}, site_settings(:default).reload.social_links.to_h)
    visit admin_settings_path
    assert_no_field "settings-social-0-name"
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/settings_screen/site_card_component_test.rb test/integration/admin/settings_test.rb`
Expected: FAIL — one empty row is drawn; the marker is unknown; the 422 brings the stored link back.

- [ ] **Step 3: The values, the form, the controller and the script**

- `Values#social_rows`: the submitted rows when `submitted` holds `:social_links` or `:social_links_present` (absent rows read as `[]`), else the stored links; no `[ [ "", "" ] ]` fallback. Its comment says why (Ruling 8).
- The fieldset: `<%= hidden_field_tag "site_setting[social_links_present]", "1", id: nil %>` as its first child after the legend, with a comment: "the form says it carries the links, so no rows means none (Decision 6); a client that posts nothing leaves them".
- `SettingsController#update`: `:social_links_present` joins the permitted scalars; `site_arguments` sets `social_link_rows` when `rows_posted?(permitted[:social_links]) || permitted[:social_links_present] == "1"` (`social_link_rows(nil)` is `[]`); the comment above `rows_posted?` names the marker.
- `repeat_rows_controller.js#remove`: always removes the row; the focus goes to the next row's field, else the previous one's, else "+ Add link"; the "last row is cleared" paragraph of the file's comment is replaced by one about the marker.

- [ ] **Step 4: Run the tests of Step 2 and the browser test**

Run: the command of Step 2, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/settings_test.rb`
Expected: PASS ("an added social link is saved with the rest" and "a blank social row counts nothing, a typed label counts one" too).

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/settings_screen app/controllers/admin/settings_controller.rb app/javascript/controllers/admin/settings/repeat_rows_controller.js test
git commit -m "feat: Settings' social links start as + Add link, and removing the last row removes it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 8: A save bar stuck over the content shows it (O2)

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (`--cs-shadow-stuck` in the light and the dark block, beside `--cs-shadow-menu`)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (beside the `body:has(.admin-save-bar) #toasts` rule)
- Modify: `app/components/admin/ui/save_bar_component.rb` (`bar_class`: `bottom-0` becomes `-bottom-px`), `app/components/admin/ui/save_bar_component.html.erb` (comment)
- Modify: `app/javascript/controllers/admin/saving/save_bar_controller.js` (`connect`, `disconnect`)
- Test: `test/components/admin/ui/save_bar_component_test.rb`, `test/system/save_bar_test.rb`

**Interfaces:**
- Produces: `data-stuck` on `.admin-save-bar` while it sticks over the content; token `--cs-shadow-stuck`.

- [ ] **Step 1: Write the failing tests**

In `save_bar_component_test.rb`, line 52's selector becomes `".admin-save-bar.sticky.-bottom-px.z-20.mt-6.bg-paper.py-3:not(.admin-save-bar--contained)"`, and add `assert_no_selector ".admin-save-bar[data-stuck]"` to the first test (the server never draws it).

In `test/system/save_bar_test.rb`:

```ruby
  test "a footer stuck over the fields draws a stronger top edge and a shadow, and at the end of the form neither" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(@owner)
    page.driver.resize(1400, 600)
    visit admin_settings_path
    await_admin_controllers
    bar = ".admin-save-bar"
    look = -> { page.evaluate_script("(() => { const s = getComputedStyle(document.querySelector('.admin-save-bar')); return [ s.borderTopColor, s.boxShadow ] })()") }

    assert_selector "#{bar}[data-stuck]"
    stuck = look.call
    assert_not_equal "none", stuck[1]

    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    assert_no_selector "#{bar}[data-stuck]"
    at_rest = look.call
    assert_equal "none", at_rest[1]
    assert_not_equal stuck[0], at_rest[0], "the top edge is the strong line only while stuck"
  ensure
    page.driver.resize(1400, 1400)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/save_bar_component_test.rb`, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/save_bar_test.rb -n "/stuck over the fields/"`
Expected: FAIL — `bottom-0`, and no `data-stuck`.

- [ ] **Step 3: The tokens, the rule and the observer**

`content-spiel.css`: `--cs-shadow-stuck: 0 -6px 16px rgba(20,20,23,0.06);` in the light block and `--cs-shadow-stuck: 0 -6px 16px rgba(20,20,23,0.12);` in the dark block, with Ruling 7's reason in a comment. The stylesheet, with a comment ("nothing at rest; while stuck over the content, the strong line and a shadow, O2"):

```css
.admin-save-bar[data-stuck] { border-top-color: var(--cs-line-strong); box-shadow: var(--cs-shadow-stuck); }
```

`bar_class` sticks at `-bottom-px`: one pixel below the window's edge, so a bar that sticks is never wholly inside the window. In `connect`, for a bar target that is not `admin-save-bar--contained`:

```js
      this.stuckObserver = new IntersectionObserver(([ entry ]) => {
        this.barTarget.toggleAttribute("data-stuck", entry.intersectionRatio < 1 && entry.boundingClientRect.bottom > entry.rootBounds.bottom)
      }, { threshold: [ 1 ] })
      this.stuckObserver.observe(this.barTarget)
```

and `disconnect` disconnects it. A comment above it: the first callback decides at connect, so a bar taken from Turbo's snapshot with `data-stuck` is decided again.

- [ ] **Step 4: Run the tests of Step 2 and the footers' suites**

Run: the commands of Step 2, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/save_bar_test.rb test/system/admin/settings_test.rb test/system/admin/groups_editor_test.rb test/system/admin/users_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind app/components/admin/ui/save_bar_component.rb app/components/admin/ui/save_bar_component.html.erb app/javascript/controllers/admin/saving/save_bar_controller.js test
git commit -m "feat: a save footer stuck over the content draws a strong top edge and a shadow

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 9: One translation vocabulary: Missing, Outdated, Translated (O4)

**Files:**
- Modify: `config/locales/admin/ui.en.yml` (`translation_chip`, `language_tabs`), `config/locales/admin/translation_screen.en.yml` (`matrix.cell_label.missing`)
- Test: `test/components/admin/ui/translation_chip_component_test.rb`, `test/components/admin/ui/language_tabs_component_test.rb`, `test/components/admin/translation_screen/matrix_component_test.rb`, `test/integration/admin/posts_test.rb` (line 579), `test/integration/admin/translation_status_test.rb` (line 50)

- [ ] **Step 1: Write the failing tests**

- Chip test, `"missing is dashed with a hollow ring …"`: `assert_selector "[aria-label='Deutsch: missing'][title='Missing']"`.
- Language tabs test, `"missing is a hollow ring, outdated a solid warn dot …"`: the four sentences become `"Deutsch: missing"` and `"Español: outdated"`, and `[title='Original changed']` becomes `[title='Outdated']`.
- `posts_test.rb:579`: `[title='Missing'][aria-label='Español: missing']`.
- `translation_status_test.rb:50`: `#language-switcher-outdated-de[title='Outdated']`.
- Matrix test, `"each cell says its state in words, headers are real th elements"`: the item's states become `{ "de" => :complete, "es" => :missing }` plus a second render with `"es" => :outdated`, asserting `a[aria-label='Welcome: Español, missing']` and `a[aria-label='Welcome: Español, outdated']`.

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/ui/translation_chip_component_test.rb test/components/admin/ui/language_tabs_component_test.rb test/components/admin/translation_screen/matrix_component_test.rb test/integration/admin/posts_test.rb test/integration/admin/translation_status_test.rb`
Expected: FAIL — "not translated", "original changed", "Original changed".

- [ ] **Step 3: The words**

`ui.en.yml`: `translation_chip.aria_label.missing: "%{language}: missing"`, `translation_chip.tooltip.missing: "Missing"`; `language_tabs.missing: "%{language}: missing"`, `language_tabs.outdated_title: "Outdated"`, `language_tabs.outdated: "%{language}: outdated"`; a comment above `translation_chip` naming O4's one vocabulary and Ruling 5 (the outdated tooltip keeps its sentence). `translation_screen.en.yml`: `matrix.cell_label.missing: "%{title}: %{language}, missing"`.

- [ ] **Step 4: Run them, and grep for the old words**

Run: the command of Step 2, then `grep -rn "not translated\|original changed\|Original changed" app config test/system test/integration test/components`
Expected: PASS; the grep finds only code comments (a field that "is not translated"), no key and no assertion.

- [ ] **Step 5: Commit**

```bash
git add config/locales/admin test
git commit -m "feat: one translation vocabulary in CS Studio: Missing, Outdated, Translated

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 10: The Translations table: the state as a word, and the whole row opens it

**Files:**
- Create: `app/components/admin/translation_screen/state_cell_component.rb`
- Modify: `app/components/admin/translation_screen/matrix_component.rb` (drop `CTA_REVIEW`, `CTA_TRANSLATE`, `cta`; add `action_kind`, `action`, `open_label`; the class comment), `matrix_component.html.erb` (the body rows)
- Modify: `config/locales/admin/translation_screen.en.yml`, `app/assets/tailwind/content-spiel.tailwind.css`, `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/components/admin/translation_screen/state_cell_component_test.rb` (new), `test/components/admin/translation_screen/matrix_component_test.rb`, `test/integration/admin/translations_overview_test.rb` (lines 65, 67), `test/system/admin/translations_test.rb`

**Interfaces:**
- Consumes: `Admin::Ui::TranslationChipComponent::STYLES` (`:mark` classes or `:glyph`, per state).
- Produces: `Admin::TranslationScreen::StateCellComponent.new(state:, locale:)`, a span with `data-locale`, `data-translation-state`, the chip's mark (`data-translation-mark`) and the word; `MatrixComponent#action_kind(item) -> :review | :translate`.

- [ ] **Step 1: Write the failing tests**

`state_cell_component_test.rb`:

```ruby
require "test_helper"

# A Translations cell (layout points spec, decision 7): the state as the
# chip's mark and a word; the column's header names the language.
class Admin::TranslationScreen::StateCellComponentTest < ViewComponent::TestCase
  test "each state is the chip's mark and its word, and no language code" do
    { complete: "Translated", missing: "Missing", outdated: "Outdated" }.each do |state, word|
      render_inline Admin::TranslationScreen::StateCellComponent.new(state: state, locale: "de")

      assert_selector "span[data-locale=de][data-translation-state=#{state}]", exact_text: (state == :outdated ? "↻#{word}" : word)
      assert_selector "[data-translation-mark=#{state}][aria-hidden=true]", visible: :all
    end
    render_inline Admin::TranslationScreen::StateCellComponent.new(state: :missing, locale: "de")
    assert_selector "[data-translation-mark=missing][class~='border-field-line'][class~='border-[1.5px]']"
    assert_no_selector "[class*=danger]"
  end

  test "an unknown state is refused" do
    assert_raises(KeyError) { render_inline Admin::TranslationScreen::StateCellComponent.new(state: :lost, locale: "de") }
  end
end
```

In `matrix_component_test.rb`, the first two tests' `td a` assertions on the action become (one row shown):

```ruby
    assert_selector "#{row} th[scope=row] a[aria-label='Review changes: Welcome']", text: "Welcome"
    assert_selector "#{row} a[data-translation-row-link][tabindex='-1'][aria-hidden=true][href='/cs-studio/posts/#{@post.id}?locale=es']", visible: :all
    assert_selector "#{row} .admin-translation-row__action[aria-hidden=true]", text: "Review changes →", visible: :all
```

(and `"Translate: Welcome"` / `"Translate →"` in the missing-only test, which loses its `a[aria-label^='Translate: ']` line), and add:

```ruby
  test "a row has one tab stop for its action, the title link; the cells say the state in words" do
    matrix(Item.new(type: "post", record: @post, states: { "de" => :complete, "es" => :missing }))

    assert_selector "#{row} a:not([tabindex='-1'])", count: 3
    assert_selector "#{row} td a [data-translation-state=missing]", text: "Missing"
    assert_no_selector "#{row} .admin-translation-chip"
    assert_selector "tr#{row}.admin-translation-row.relative"
    assert_selector "#{row} td[data-column=type]"
  end
```

`translations_overview_test.rb` lines 65 and 67: `assert_select "#{row("page", missing_page)} .admin-translation-row__action", text: "Translate →"` and the same with `"Review changes →"`.

In `test/system/admin/translations_test.rb` (Review Focus 2), and line 499's `td a` becomes `.admin-translation-row__action` with `visible: :all`:

```ruby
  test "a click on an empty part of a row opens the row's language, and a cell's link still opens its own" do
    post = create_post(title: "Only in English")

    visit "/cs-studio/translations"
    row = "#translation-item-post-#{post.id}"
    assert_selector "#{row} .admin-translation-row__action", text: "Translate →", visible: :all
    find("#{row} td[data-column=type]").click
    assert_current_path "/cs-studio/posts/#{post.id}?locale=de"

    visit "/cs-studio/translations"
    find("#{row} a[aria-label$='Español, missing']").click
    assert_current_path "/cs-studio/posts/#{post.id}?locale=es"
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/translation_screen test/integration/admin/translations_overview_test.rb`
Expected: FAIL — `uninitialized constant Admin::TranslationScreen::StateCellComponent`; the action is a link with its own name.

- [ ] **Step 3: The keys**

In `translation_screen.en.yml`, under `matrix:` beside `cell_label`, and a new group:

```yaml
          # The row's action (layout points spec, B): a word shown while the row is
          # hovered or its title link has the focus, and the title link's name.
          action:
            review: "Review changes →"
            translate: "Translate →"
          open_label:
            review: "Review changes: %{title}"
            translate: "Translate: %{title}"
        # `Admin::TranslationScreen::StateCellComponent`, a cell's word (O4).
        state_cell:
          complete: "Translated"
          missing: "Missing"
          outdated: "Outdated"
```

- [ ] **Step 4: The cell component**

`StateCellComponent < Admin::AdminComponent`, `initialize(state:, locale:)` (`STYLES.fetch` raises `KeyError` for an unknown state), `call` drawing `tag.span` with class `admin-translation-state inline-flex items-center gap-1.5 text-sm` plus `TEXT.fetch(state)` (`complete: "text-ink"`, `missing: "text-meta"`, `outdated: "text-warn-ink"`), `data: { locale:, translation_state: }`, holding the mark (a `tag.span("", class: "inline-block shrink-0 #{style[:mark]}")` or `tag.span(style[:glyph])`, either with `aria: { hidden: true }, data: { translation_mark: state }`) and `t(".#{state}")`. Its comment: the marks are the chip's (`STYLES`) so the two cannot drift, and the chip stays as it is in the posts list (Decision 7). Add `app/components/admin/translation_screen/state_cell_component.rb` to `CONVERTED` (it holds no copy).

- [ ] **Step 5: The row**

`matrix_component.rb`: `action_kind(item)` is `:review` when any state is `:outdated`, else `:translate`; `action(item) = t(".action.#{action_kind(item)}")`; `open_label(item) = t(".open_label.#{action_kind(item)}", title: title(item))`. The class comment describes the row (Decision 8, Ruling 6). The row in `matrix_component.html.erb`:

```erb
<tr id="<%= row_id(item) %>" class="admin-translation-row relative border-b border-line last:border-b-0 hover:bg-paper">
  <th scope="row" class="sticky left-0 z-20 min-w-60 max-w-80 bg-surface p-0 text-left font-medium">
    <%= link_to title(item), focus, class: "relative block truncate px-4 py-2 text-ink hover:underline", aria: { label: open_label(item) }, data: { turbo_frame: "_top" } %>
  </th>
  <td class="px-3 py-2 text-sm text-dim" data-column="type"><%= type_label(item) %></td>
  <% locales.each do |locale| %>
    <td class="px-3 py-2">
      <%= link_to editor_path(item, locale), aria: { label: cell_label(item, locale) }, class: "relative z-10 inline-flex", data: { turbo_frame: "_top" } do %>
        <%= render Admin::TranslationScreen::StateCellComponent.new(state: item.states.fetch(locale), locale: locale) %>
      <% end %>
    </td>
  <% end %>
  <td class="px-4 py-2 text-right text-sm whitespace-nowrap">
    <%# The row's stretched link: no tab stop and nothing for a screen reader (the title link is both), and absolute against the row, not the sticky title cell. %>
    <%= link_to "", focus, tabindex: -1, aria: { hidden: true }, class: "absolute inset-0", data: { turbo_frame: "_top", translation_row_link: "" } %>
    <span class="admin-translation-row__action text-accent" aria-hidden="true"><%= action(item) %></span>
  </td>
</tr>
```

The stylesheet, with a comment (opacity, never visibility: the word sits under the row's link):

```css
.admin-translation-row__action { opacity: 0; }
.admin-translation-row:hover .admin-translation-row__action,
.admin-translation-row:has(th a:focus-visible) .admin-translation-row__action { opacity: 1; }
```

- [ ] **Step 6: Run the tests of Step 2, the i18n and design guards, and the browser tests**

Run: the command of Step 2, then `PGGSSENCMODE=disable bin/rails test test/lib/admin_i18n_test.rb test/lib/admin_design_rules_test.rb test/integration/trash_visibility_test.rb`, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/translations_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/components/admin/translation_screen config/locales/admin/translation_screen.en.yml app/assets/tailwind/content-spiel.tailwind.css test
git commit -m "feat: the Translations table says each state in a word, and the whole row opens it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 11: Media draws its drop zone only for an empty library

**Files:**
- Modify: `app/services/media/search.rb` (a public method after `counts`)
- Modify: `app/controllers/admin/media_controller.rb` (`index`)
- Modify: `app/views/admin/media/index.html.erb` (the `<div>` around `FileDropComponent`, and the comment above it)
- Test: `test/services/media/search_test.rb`, `test/integration/admin/media_test.rb`

**Interfaces:**
- Produces: `Media::Search#any_images?(counts:) -> Boolean`; `@library_has_images` in `Admin::MediaController#index` (not set on the picker path).

- [ ] **Step 1: Write the failing tests**

In `search_test.rb`:

```ruby
  test "any_images? is the kept count without search text, and one query with it: a search that finds nothing still knows" do
    plain = Media::Search.new(actor: @viewer)
    assert plain.any_images?(counts: plain.counts)

    nothing = Media::Search.new(q: "no such image anywhere", actor: @viewer)
    assert_equal 0, nothing.counts[:all]
    assert nothing.any_images?(counts: nothing.counts)

    Media::Asset.update_all(trashed_at: Time.current) # version: none (a test's own setup: the whole library in the trash)
    [ Media::Search.new(actor: @viewer), Media::Search.new(q: "Beach", actor: @viewer) ].each do |search|
      assert_not search.any_images?(counts: search.counts)
    end
  end
```

In `test/integration/admin/media_test.rb` (Review Focus 4 is the first):

```ruby
  test "the drop zone is drawn for an empty library" do
    create_media_asset.update!(trashed_at: Time.current)
    sign_in_as(users(:one))

    get "/cs-studio/media"

    assert_select "[data-media-drop-zone]:not([hidden]) .admin-file-drop input#media-upload-input"
  end

  test "once the library holds an image the zone is hidden, under a search that finds nothing too, and the file input stays" do
    create_media_asset
    sign_in_as(users(:one))

    [ "/cs-studio/media", "/cs-studio/media?q=no+such+image" ].each do |path|
      get path
      assert_select "[data-media-drop-zone][hidden] input#media-upload-input[data-admin--media--upload-target=input]"
      assert_select "button", text: "Upload images"
    end
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/services/media/search_test.rb test/integration/admin/media_test.rb`
Expected: FAIL — `undefined method 'any_images?'`, no `[data-media-drop-zone]`.

- [ ] **Step 3: The question, the controller and the view**

- `Media::Search#any_images?(counts:)`: `counts[:all].positive?` when there is no search text; otherwise `@scope.unscope(:includes).exists?` (one statement, on that path only, Decision 9). Its comment says why the counts cannot answer under a search.
- `Admin::MediaController#index`: after `@counts`, on the screen's path (after the picker's `return`), `@library_has_images = @search.any_images?(counts: @counts)`.
- The view: the zone's wrapper is `<%= tag.div hidden: @library_has_images, data: { media_drop_zone: "" } do %>` around the `FileDropComponent` (the status `<p>` stays outside it, visible to a screen reader); the comment says the zone is the empty library's invitation and the file input stays as the button's and the drop's target (Ruling 12).

- [ ] **Step 4: Run the tests of Step 2 and the browser tests**

Run: the command of Step 2, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/media_library_test.rb test/system/admin/media_picker_test.rb`
Expected: PASS (the upload test attaches to the input of an empty library; the overlay tests drop on the window).

- [ ] **Step 5: Commit**

```bash
git add app/services/media/search.rb app/controllers/admin/media_controller.rb app/views/admin/media/index.html.erb test
git commit -m "feat: Media draws its drop zone only while the library is empty

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 12: Two-letter avatars, one rule on the server

**Files:**
- Modify: `app/values/person_name.rb` (`initials` and its comment)
- Modify: `app/controllers/admin/note_threads_controller.rb` (`index`'s rows), `app/controllers/admin/note_mentions_controller.rb` (its rows)
- Modify: `app/javascript/mind_graph/card_notes.js` (drop `initials`; `thread.initials`), `app/javascript/controllers/admin/notes/composer_controller.js` (`show`: `person.initials`)
- Modify (comments): `app/components/admin/notes_screen/avatar_component.rb`, `app/components/admin/ui/avatar_component.rb`
- Test: `test/values/person_name_test.rb`, `test/components/admin/notes_screen/avatar_component_test.rb`, `test/integration/admin/note_writes_test.rb`, `test/integration/admin/note_mentions_test.rb`, `test/lib/initials_rule_test.rb` (new)

**Interfaces:**
- Produces: `PersonName.initials(text) -> String`: two words give the first character of each; one word gives its first two letters or digits; the JSON rows of `GET …/notes/<type>/<id>/threads` and `…/mentions` carry `"initials"`.

- [ ] **Step 1: Write the failing tests**

In `person_name_test.rb`, replace `"initials are the first character of the first two words as they were written; one word is one letter"` and the `@dana` line of the odd-names test:

```ruby
  test "initials: two words give their first characters, one word its first two letters, as written" do
    assert_equal "DW", PersonName.initials("Dana Weiss")
    assert_equal "dv", PersonName.initials("dana van weiss")
    assert_equal "da", PersonName.initials("dana")
    assert_equal "ad", PersonName.initials("admin")
    assert_equal "au", PersonName.initials("author")
    assert_equal "d", PersonName.initials("d")
  end
```

and in `"initials of odd names: …"`: `assert_equal "da", PersonName.initials("@dana")`, plus `assert_equal "on", PersonName.initials("o'neil")`, `assert_equal "7", PersonName.initials("7")` and `assert_equal "👩‍🚀", PersonName.initials("👩‍🚀")` (the grapheme, `7o`, accent, `@` and blank cases stay).

`avatar_component_test.rb`: the reader's avatar reads `"re"`; the test is renamed `"two initials from a name or from one word; the viewer's own is filled, and it is hidden from a screen reader"`.

`note_writes_test.rb`, in `"a record's open threads as JSON for the mind graph's card …"`: `assert_equal "Da", row["initials"]`; in `"the card's JSON lists only open threads, … names a deleted author as nobody …"`: `assert_equal "ad", body["threads"].last["initials"]` (the card's "a deleted user").

`note_mentions_test.rb`, first test: the two expected hashes gain `"initials" => "DE"` and `"initials" => "on"`.

`test/lib/initials_rule_test.rb`:

```ruby
require "test_helper"

# Layout points spec, decision 10: a person's letters are written once, by
# `PersonName.initials` on the server, and handed to the scripts that draw a
# circle. A source grep for the shape the two copies had (split on white
# space, two words, a first character); a rule written another way is not seen.
class InitialsRuleTest < ActiveSupport::TestCase
  test "no script computes a person's initials: the letters come from PersonName.initials on the server" do
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].select do |path|
      File.read(path).match?(/split\(\/\\s\+\/\)\S*\.slice\(0,\s*2\)/)
    end
    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/values/person_name_test.rb test/components/admin/notes_screen/avatar_component_test.rb test/integration/admin/note_writes_test.rb test/integration/admin/note_mentions_test.rb test/lib/initials_rule_test.rb`
Expected: FAIL — "d" for "dana", no `initials` key, two scripts that compute them.

- [ ] **Step 3: The rule, the data and the scripts**

- `PersonName.initials`: two or more words as today; one word: its graphemes that are a letter, a digit or an emoji (the existing class, `/[\p{L}\p{N}\p{Emoji_Presentation}]/`), the first two of them joined, or the first grapheme when it has none; nothing is `""`. The comment states the new one-word rule and that it is the only copy (Decision 10).
- `note_threads_controller.rb#index`: compute `author` once per row and add `initials: PersonName.initials(author || t("admin.mind_graph.script.card.notes.deleted_user"))`.
- `note_mentions_controller.rb`: each row adds `initials: PersonName.initials(Notes.name_of(user))`.
- `card_notes.js`: the `initials` constant and its comment's "the first letters of the first two words" go; the avatar is `element("span", …, thread.initials)`.
- `composer_controller.js#show`: `avatar.textContent = person.initials`, and the comment above it says the server writes the letters.
- The two avatar components' comments name the new rule.

- [ ] **Step 4: Run the tests of Step 2, and the circles' suites**

Run: the command of Step 2, then `PGGSSENCMODE=disable bin/rails test test/components/admin/presence_screen test/components/admin/editor_screen/holder_avatar_component_test.rb test/components/admin/editor_screen/hold_strip_component_test.rb test/integration/admin/note_names_test.rb test/lib/admin_i18n_test.rb`, then (after the two builds) `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/presence_test.rb test/system/admin/note_composer_test.rb test/system/admin/mind_graph_test.rb`
Expected: PASS. A test that pinned one letter for a one-word name is the rule that moved: write the two letters there, and nothing else.

- [ ] **Step 5: Commit**

```bash
git add app/values/person_name.rb app/controllers/admin/note_threads_controller.rb app/controllers/admin/note_mentions_controller.rb app/javascript/mind_graph/card_notes.js app/javascript/controllers/admin/notes/composer_controller.js app/components/admin/notes_screen/avatar_component.rb app/components/admin/ui/avatar_component.rb test
git commit -m "feat: a one-word name gives two letters in its circle, and only the server writes them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 13: The rules, the references, the roadmap, the spec, the full check and the pull request's text

**Files:**
- Modify: `CLAUDE.md`, `docs/reference/design-system.md`, `docs/reference/editors-and-translation-pair.md`, `docs/reference/settings-languages-ai.md`, `docs/reference/translations.md`, `docs/reference/media.md`, `docs/reference/notes.md`, `docs/reference/presence.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-23-layout-points-design.md`

- [ ] **Step 1: The rules in `CLAUDE.md`**

At the end of the bullet "CS Studio sources use tokens, not colour literals: …" (after its last sentence), add:

```markdown
The editors' and Settings' form column is one token, `--cs-form-max` (760px), and an editor's translation tab `--cs-form-max-pair` (1144px), each written in `content-spiel.css` and nowhere else, and read through `.admin-form-column` (`Admin::EditorScreen::FormColumn.classes`), a class on the elements that are there and never a new wrapper around an editor's unit (`test/lib/admin_design_rules_test.rb`: "the form column's width is a token: 760px and 1144px are written once, in content-spiel.css").
```

In the bullet "A person's name reaches a marker, a tooltip or a circle …", after "never `User#display_name`", add:

```markdown
; and the letters in a circle are `PersonName.initials` (two words, their first characters; one word, its first two letters), on the server, handed to a script as data and never computed by one (`test/values/person_name_test.rb`; `test/lib/initials_rule_test.rb`: "no script computes a person's initials: the letters come from PersonName.initials on the server", a source grep for the shape the old copies had)
```

- [ ] **Step 2: The references**

- `design-system.md`, "Form placement": the column is `--cs-form-max` (760px) on the post form, the page settings, the block list and Settings, left-aligned, `--cs-form-max-pair` on a translation tab; the save footer's stuck edge (`data-stuck`, `--cs-shadow-stuck`, `-bottom-px`); the reference card's summary is an `.admin-disclosure` whose triangle shows only stacked.
- `editors-and-translation-pair.md`, "Translation pair": 824px, two columns of up to 560px, the 24px gap, the 1144px column; the slug field shows the address once and its placeholder is `admin--editor--slug-preview`'s; the related-posts help (O7).
- `settings-languages-ai.md`, the Settings paragraph: the 760px column, `admin--settings--nav` and its rule (Ruling 10), the social links' marker and "+ Add link", no logo square, the key input filling its row.
- `translations.md`, the matrix bullet and the language tabs bullet: the words (O4), `StateCellComponent`, the whole row, the action shown on hover or focus.
- `media.md`, the Media module paragraph: the zone only for an empty library, `Media::Search#any_images?`.
- `notes.md` and `presence.md` ("The name rule is a value"): the two-letter rule and that the threads' and the mentions' JSON carry `initials`.
- Then `grep -n "880\|NONE\|one empty row\|not translated\|original changed\|preview line\|1100px" docs/reference/*.md` and correct each sentence this PR made untrue.

- [ ] **Step 3: The roadmap and the spec**

`docs/roadmap.md`: add a "Shipped" row "Layout points, part 1: CS Studio's forms and lists (form column at 760px, the slug line, Settings' nav, social links, logo and stuck footer, one translation vocabulary, the Translations row, Media's drop zone, two-letter avatars, the related-posts help, the reference card's triangle)" pointing at the spec; in "Contrast and buttons, part 2" strike what shipped and leave the dashboard, the Mind graph and the site, naming the two plans to come; remove the known gap "The reference card's summary has no `admin-disclosure` triangle"; in the polish backlog remove "no active item in the in-page nav" (Settings) and "the big "Choose file" drop zone still drawn above the grid" (Media) and narrow "lists and editors spanning the full width" to the lists; in "Found while writing the guides" the related-posts row says the help was changed and the feature waits for its own spec; add under "Known gaps" "the dashboard's activity row still draws one letter by its own rule (plan 2 of the layout points)".

The spec: add `## As built (part 1, CS Studio's forms and lists)` before "What this does not do", listing the plan's twelve rulings in one line each and the departures from the spec's text (Decision 1's 1,536px is O3's 1,144px; the matrix's missing name now says "missing", O4; the dashboard row's initials wait for part 2).

- [ ] **Step 4: The full check**

Run, in order, each after the previous has finished:

```bash
bin/rubocop
bin/brakeman
bin/rails zeitwerk:check
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test
sysctl -n vm.loadavg
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system
git status --short
```

Expected: rubocop and brakeman clean, zeitwerk fine, every test green, the browser suite in about its usual time (a run twice as long is not a result), and `git status` shows nothing but this task's documents.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs: the form column token and the initials rule in CLAUDE.md, the references, the roadmap and the spec's as built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 6: The pull request's text** (whoever opens the PR uses it; this plan pushes nothing)

```markdown
## Layout points, part 1 of 3: CS Studio's forms and lists

Claude Design's review, part 2 (`docs/superpowers/specs/2026-10-23-layout-points-design.md`, sections A and B), with Claude Design's answers O2–O4 and the owner's O1, O7, O9 and O11.

- **Forms at 760px.** The post form, the page settings, the block list and Settings' cards are at most 760px (`--cs-form-max`), left-aligned; an editor's translation tab is two columns of up to 560px with a 24px gap, side by side from 824px of form width, stacked (original first) below.
- **The slug field** shows the address once; when it is empty its placeholder is the slug the title will give.
- **Settings**: the nav marks the section in view; social links start as "+ Add link" and the last row can be removed; no "NONE" logo square; the API key field fills its row; a save footer stuck over the content draws a strong top edge and a shadow.
- **One translation vocabulary**: ○ Missing, ↻ Outdated, ● Translated, in the chip, the language tabs and the Translations table.
- **Translations**: each cell says its state in a word; a click anywhere in a row opens it; "Translate →" shows on hover or focus and is no longer a second tab stop.
- **Media**: no drop zone once the library holds an image ("Upload images" and the window-wide drop remain).
- **Two-letter avatars** for one-word names, in notes, presence and live editing; the letters are written on the server only.
- **Left-overs**: the related-posts help no longer promises them on the site (O7); the stacked reference card has its disclosure triangle (O11).

Not in this PR: the dashboard (grid, empty lines, collapsed activity, its avatar letters) and the Mind graph (legend, fit) are part 2; the site's captions, subpages list and tags are part 3.

## Documentation

Editors: `editors/pages/build-a-page-with-blocks.md` and `editors/pages/page-settings-and-search-appearance.md` (the narrower column, the slug field without its line), `editors/posts/publish-schedule-and-preview.md` and `editors/posts/posts-and-content-types.md` (the post editor's width and slug field), `editors/translating/keep-translations-up-to-date.md` (the words Missing, Outdated, Translated; the whole row; the action on hover), `editors/translating/write-in-more-than-one-language.md` (the translation tab's two columns; the tabs' words), `editors/media/the-media-library.md` (no drop zone once there are images), `editors/posts/tags-related-posts-and-the-mind-graph.md` (what related posts do: the Mind graph, not yet the site), `editors/working-together/notes-on-content.md` and `editors/working-together/who-else-has-this-open.md` (two letters in a circle). Administrators: `administrators/site/site-settings.md` (the nav's current section, "+ Add link", no NONE square, the width, the stuck save bar).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

---

## Self-review

- **Spec coverage.** A: editors at 760px (Task 1), translation tabs (Task 1, O3), Settings at 760px and fields filling (Task 5, O1), the slug line (Task 3), Settings' nav (Task 6), social links (Task 7), no NONE (Task 5), the save bar (Task 8, O2). B: the Translations words (Tasks 9, 10, O4), the whole row (Task 10), Media (Task 11), two-letter avatars (Task 12; the dashboard row is plan 2's, Ruling 4). O7's help text (Task 4); O11's triangle (Task 2). O11's Mind graph count badges belong with the Mind graph, in plan 2. C, D, E are the later plans'.
- **Steps.** Every test step carries its assertions with the spec's values (760, 1144, 824, 560, the words); code bodies appear only for the decisions a signature leaves open (the stylesheet rules, the nav's rule, the stuck test, the row's markup); the rest is a signature, a file and the values.
- **Names.** `FormColumn.classes` (Task 1) is what the three editors' files call; `--cs-form-max` (Task 1) is Task 5's; Task 1's `@container (min-width: 824px)` block is Task 2's; `StateCellComponent.new(state:, locale:)` and `action_kind` (Task 10) are used only there; `any_images?(counts:)` (Task 11) is the controller's; `social_links_present` is the same name in the view, the controller, `Values` and the tests (Task 7); `data-stuck` and `--cs-shadow-stuck` (Task 8); `initials` is the JSON key in both controllers, both scripts and their tests (Task 12).
- **Review Focus.** Each of the five has its test in its task (7, 10, 3, 11, 6).
- **Proportion.** About as long as the spec's sections A and B and their decisions with every test written out; no product method body beyond the nav's rule and the stylesheet's lines.
