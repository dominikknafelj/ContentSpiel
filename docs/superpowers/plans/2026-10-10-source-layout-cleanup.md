# Source Layout Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every CS Studio screen the same shape in components, browser scripts and locale files, with no change of behaviour.

**Architecture:** Files move; the names that follow from a file's place (a component's class, a Stimulus identifier, a translation scope) are rewritten everywhere by two small scripts kept in `script/layout/` for the length of the branch and deleted in the last task. Guards go in first, moves follow one group at a time, each proven by the existing tests for that group.

**Tech Stack:** Rails 8.1, ViewComponent, Stimulus through importmap-rails, Tailwind v4, Minitest, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-10-source-layout-cleanup-design.md`. Where this plan's tables differ from the spec's (§3, §4), this plan wins: the spec said the plan re-counts users and corrects the tables by the rule, and that count was done when this plan was written (the shared script topic is `ui`, to match `Admin::Ui`; a `shell` topic holds what only the layout uses).

## Global Constraints

- No change a person could see and no change to what any test asserts: only paths, class names, identifiers and translation scopes change. A test's assertion that names one of those is updated to the new name and nothing else.
- Every test command is prefixed `PGGSSENCMODE=disable`. System tests need `bin/rails tailwindcss:build` first and run with `PARALLEL_WORKERS=6`. Never two test runners at once. System test files are run with `bin/rails test <files>` (`bin/rails test:system <files>` ignores the files).
- Moves use `git mv`, so history follows the file.
- Nothing is loose in `app/components/admin/` but `admin_component.rb`; nothing is loose in `app/javascript/controllers/admin/`.
- Controllers stay under `app/javascript/controllers/admin/`: the registrar (`app/javascript/controllers/index.js`, `admin.js`) and the import map's `preload: "admin"` hang on that path, and `test/integration/public_javascript_test.rb` must stay green without being edited.
- `app/components/admin/fields/` and `columns/`, `app/controllers/admin/`, the helpers and the oversized files are not touched except for the names rewritten inside them.
- Commit subjects are conventional (`ref: …`, `test: …`, `docs: …`) and every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```
- Push nothing. Delete nothing outside the worktree. Dispatch no subagents.

## Review Focus

1. **A control that silently does nothing.** A `data-controller`, `data-action` or `data-…-target` left with an old identifier does not raise: the control is dead. Net: the guard of Task 1 (every identifier in `app/` has a controller file), extended in Task 8 to actions, targets, values and params.
2. **An event nobody hears.** Controllers talk through events named by identifier (`admin--notes-live:delivery`, heard by `admin--notes-alert`). A rename on one side only breaks the pair with no error. Net: Task 1's guard scans `"<identifier>:<event>"` strings in scripts and `data-action` values against the dispatching controller's new identifier.
3. **A style that no longer matches.** `app/assets/tailwind/content-spiel.tailwind.css` selects by `[data-controller~="admin--…"]` and `[data-admin--…]` in 14 places. Net: the stylesheets are in the rewrite's file set, and the guard scans them.
4. **A string that raises only in tests of that screen.** A moved component's translation scope moves; a key left behind raises `I18n::MissingTranslationData` in the test environment only when that component renders. Net: Task 2 adds a test that every `t(".key")` in a component under `app/components/admin` resolves.
5. **CS Studio's scripts reaching a public page.** Net: `test/integration/public_javascript_test.rb`, unedited, run in every script task.

---

### Task 1: Nets before anything moves, and the two rewrite tools

**Files:**
- Create: `test/lib/source_layout_test.rb`
- Create: `script/layout/identifiers.rb`, `script/layout/constants.rb`
- Read: `app/javascript/controllers/index.js`, `app/javascript/admin.js`, `config/importmap.rb`

**Interfaces:**
- Produces: `SourceLayoutTest` (later tasks add tests to it); `ruby script/layout/identifiers.rb OLD=NEW …` and `ruby script/layout/constants.rb Old::Const=New::Const …`, both idempotent, both printing each file they change and a section `REVIEW:` of lines a person must look at.

- [ ] **Step 1: Write the guard for identifiers, true today**

```ruby
# test/lib/source_layout_test.rb
require "test_helper"

# Where a screen's parts live (docs/superpowers/specs/2026-10-10-source-layout-cleanup-design.md).
# A Stimulus identifier follows its controller's path, and a name left behind
# by a move does not raise: the control is just dead. So every identifier the
# app writes must have a controller file.
class SourceLayoutTest < ActiveSupport::TestCase
  ROOT = Rails.root
  CONTROLLERS = ROOT.join("app/javascript/controllers")
  SOURCES = %w[app/components app/views app/helpers app/javascript app/assets/tailwind].freeze
  TOKEN = /(?<![a-z0-9-])admin--[a-z0-9]+(?:-{1,2}[a-z0-9]+)*/

  def self.identifiers
    Dir[CONTROLLERS.join("**/*_controller.js")].map do |path|
      Pathname(path).relative_path_from(CONTROLLERS).to_s.delete_suffix("_controller.js").gsub("/", "--").tr("_", "-")
    end
  end

  # The identifier a token belongs to: the longest one it equals or extends with "-".
  def self.owner(token, identifiers)
    identifiers.select { |id| token == id || token.start_with?("#{id}-") }.max_by(&:length)
  end

  test "every admin identifier written in the app has a controller file" do
    identifiers = self.class.identifiers
    orphans = SOURCES.flat_map { |dir| Dir[ROOT.join(dir, "**/*.{rb,erb,js,css}")] }.flat_map do |path|
      File.read(path).scan(TOKEN).uniq.reject { |token| self.class.owner(token, identifiers) }.map { |token| "#{Pathname(path).relative_path_from(ROOT)}: #{token}" }
    end
    assert_empty orphans, "identifiers with no controller file:\n#{orphans.join("\n")}"
  end

  test "the guard's own matching: an identifier, its targets and values, and a stranger" do
    ids = %w[admin--notes admin--notes-live]
    assert_equal "admin--notes-live", self.class.owner("admin--notes-live-unread-url-value", ids)
    assert_equal "admin--notes", self.class.owner("admin--notes-target", ids)
    assert_nil self.class.owner("admin--nothing", ids)
  end
end
```

- [ ] **Step 2: Run it**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/source_layout_test.rb`
Expected: PASS. If the first test lists orphans, each is either a real dead identifier (report it under "Concerns", do not fix behaviour) or prose in a comment: narrow `SOURCES` reading to code only by stripping comment lines (`^\s*(#|//)`) before scanning, and say so in the report.

- [ ] **Step 3: Confirm the facts the moves rely on, and write them in the report**

Run each and record the output:
```bash
bin/rails runner 'puts Rails.application.importmap.to_json(resolver: ActionController::Base.helpers).scan(/"controllers\/admin\/[^"]+"/).first(3)'
grep -rn -- '-outlet' app/components app/views app/javascript | head
grep -rnE 'admin--#\{|admin--\$\{' app test | head
grep -rnE 'Component"\.constantize|Component\'\.constantize' app lib config | head
```
Then make a throwaway nested controller to prove the import map and the registrar handle a subfolder: `mkdir -p app/javascript/controllers/admin/zz && printf 'import { Controller } from "@hotwired/stimulus"\nexport default class extends Controller {}\n' > app/javascript/controllers/admin/zz/probe_controller.js`, run `bin/rails runner 'puts Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)[/controllers\/admin\/zz\/probe_controller[^,]*/]'` (expected: a line holding `controllers/admin/zz/probe_controller`), run `PGGSSENCMODE=disable bin/rails test test/integration/public_javascript_test.rb` (expected: PASS), then `rm -r app/javascript/controllers/admin/zz`. If the nested file is NOT pinned, stop and report BLOCKED with the output: the plan's script tasks depend on it.

- [ ] **Step 4: Write the identifier rewriter**

```ruby
# script/layout/identifiers.rb
# Rewrites Stimulus identifiers after a controller moved. Usage:
#   ruby script/layout/identifiers.rb admin--notes-live=admin--notes--live admin--dialog=admin--ui--dialog
# Idempotent. Deleted in the plan's last task.
require "pathname"

pairs = ARGV.to_h { |arg| arg.split("=", 2) }
abort "usage: identifiers.rb OLD=NEW ..." if pairs.empty? || pairs.any? { |old, new| new.nil? || old.empty? }

ROOT = Pathname(__dir__).join("../..").expand_path
ALL_OLD = Dir[ROOT.join("app/javascript/controllers/admin/*_controller.js")].map { |f| "admin--" + File.basename(f, "_controller.js").tr("_", "-") } | pairs.keys
FILES = Dir[ROOT.join("{app,test,docs,config/locales}/**/*.{rb,erb,js,css,yml,md}")] + [ ROOT.join("CLAUDE.md").to_s ]
# A run of the old one-level form, matched whole (the atomic group forbids a shorter match). A run followed by "--" is already in the new form: leave it.
TOKEN = /(?<![a-z0-9-])(?>admin--[a-z0-9]+(?:-[a-z0-9]+)*)(?!--)/

review = []
FILES.each do |path|
  text = File.read(path)
  changed = text.gsub(TOKEN) do |token|
    owners = ALL_OLD.select { |id| token == id || token.start_with?("#{id}-") }
    owner = owners.max_by(&:length)
    next token unless owner && pairs.key?(owner)

    review << "#{Pathname(path).relative_path_from(ROOT)}: #{token} (could also be #{(owners - [ owner ]).join(', ')})" if owners.size > 1
    pairs.fetch(owner) + token.delete_prefix(owner)
  end
  next if changed == text

  File.write(path, changed)
  puts Pathname(path).relative_path_from(ROOT)
end
puts "REVIEW:", review.uniq
```

- [ ] **Step 5: Write the constant rewriter**

```ruby
# script/layout/constants.rb
# Rewrites a component's class name after it moved. Usage:
#   ruby script/layout/constants.rb Admin::ButtonComponent=Admin::Ui::ButtonComponent
# Rewrites the full name everywhere, and the bare name (`ButtonComponent`,
# as code inside `module Admin` writes it) to the new name without `Admin::`.
# Idempotent. Deleted in the plan's last task.
require "pathname"

pairs = ARGV.to_h { |arg| arg.split("=", 2) }
abort "usage: constants.rb Old::Name=New::Name ..." if pairs.empty?

ROOT = Pathname(__dir__).join("../..").expand_path
FILES = Dir[ROOT.join("{app,test,docs,config,lib}/**/*.{rb,erb,yml,md,rake}")] + [ ROOT.join("CLAUDE.md").to_s ]
review = []
FILES.each do |path|
  text = File.read(path)
  changed = pairs.reduce(text) do |body, (old, new)|
    bare_old = old.delete_prefix("Admin::")
    bare_new = new.delete_prefix("Admin::")
    body = body.gsub(/(?<![\w:])#{Regexp.escape(old)}\b/, new)
    # Bare, and not already qualified: `ButtonComponent.new` inside `module Admin`.
    body.gsub(/(?<![\w:])#{Regexp.escape(bare_old)}\b/) do
      review << "#{Pathname(path).relative_path_from(ROOT)}: bare #{bare_old}"
      bare_new
    end
  end
  next if changed == text

  File.write(path, changed)
  puts Pathname(path).relative_path_from(ROOT)
end
puts "REVIEW:", review.uniq
```

- [ ] **Step 6: Try both tools on nothing and commit**

Run: `ruby script/layout/identifiers.rb admin--zz-none=admin--zz--none` and `ruby script/layout/constants.rb Admin::ZzNoneComponent=Admin::Ui::ZzNoneComponent`
Expected: each prints only `REVIEW:` and `git status --short` shows only the three new files.

```bash
git add test/lib/source_layout_test.rb script/layout
git commit -m "test: a guard that every admin identifier has a controller file, and the two rename tools of the layout cleanup"
```

---

### Task 2: The shared building blocks move to `Admin::Ui`

**Files:**
- Move (each `.rb` with its `.html.erb` and any sidecar of the same basename) from `app/components/admin/` to `app/components/admin/ui/`: `button`, `channel_chip`, `checkbox`, `chip_input`, `confirm_dialog`, `content_type_dot`, `dialog`, `empty_state`, `error_summary`, `field`, `file_drop`, `language_tabs`, `menu`, `pagination`, `password_field`, `save_bar`, `save_status`, `status_chip`, `theme_switch`, `time_ago`, `toast`, `toast_region`, `translation_chip`, `user_name`, `word_diff` (`_component` after each).
- Move their tests `test/components/admin/<name>_component_test.rb` to `test/components/admin/ui/` and their previews `test/components/previews/admin/<name>_component_preview.rb` to `test/components/previews/admin/ui/` (with any preview template folder of the same name).
- Create: `config/locales/admin/ui.en.yml`; Modify: `config/locales/admin/components.en.yml`, `test/lib/admin_i18n_test.rb`, `test/lib/source_layout_test.rb`

**Interfaces:**
- Consumes: `script/layout/constants.rb` (Task 1).
- Produces: `Admin::Ui::<Name>Component` for the 25 names; translation scope `admin.components.ui.<name>`.

- [ ] **Step 1: Add the test that every relative key a component reads exists** (it passes today and must keep passing after each move)

Append to `SourceLayoutTest`:
```ruby
  test "every relative translation key an admin component reads exists" do
    missing = Dir[ROOT.join("app/components/admin/**/*.{rb,erb}")].flat_map do |path|
      relative = Pathname(path).relative_path_from(ROOT.join("app/components/admin")).to_s
      scope = relative.sub(/_component(\.html)?\.(rb|erb)\z/, "").sub(/\.(rb|html\.erb)\z/, "").tr("/", ".")
      File.read(path).scan(/\bt\(\s*["']\.([a-z0-9_.]+)["']/).flatten.uniq.reject { |key| I18n.exists?("admin.components.#{scope}.#{key}", :en) }.map { |key| "#{relative}: .#{key}" }
    end
    assert_empty missing, "keys read but not defined:\n#{missing.join("\n")}"
  end
```
Run: `PGGSSENCMODE=disable bin/rails test test/lib/source_layout_test.rb`. Expected: PASS. A key it lists that is read through a base class (the scope is the subclass's) is a false alarm of this scan: exclude that file by name in the test with a one-line reason, and say so in the report.

- [ ] **Step 2: Move the files**

```bash
mkdir -p app/components/admin/ui test/components/admin/ui test/components/previews/admin/ui
for n in button channel_chip checkbox chip_input confirm_dialog content_type_dot dialog empty_state error_summary field file_drop language_tabs menu pagination password_field save_bar save_status status_chip theme_switch time_ago toast toast_region translation_chip user_name word_diff; do
  for f in app/components/admin/${n}_component.*; do git mv "$f" app/components/admin/ui/; done
  [ -e test/components/admin/${n}_component_test.rb ] && git mv test/components/admin/${n}_component_test.rb test/components/admin/ui/
  for f in test/components/previews/admin/${n}_component_preview*; do [ -e "$f" ] && git mv "$f" test/components/previews/admin/ui/; done
done
git status --short | grep -v '^R' | head
```
Expected: the last command prints nothing but the tool files' absence (only renames).

- [ ] **Step 3: Nest each moved class in `module Ui`**

In each of the 25 `app/components/admin/ui/*_component.rb`, the file reads `module Admin` / `  class XComponent < …` / `end`. Change it to `module Admin` / `  module Ui` / `    class XComponent < …` with the class body indented two more spaces and one more `end`. Comments move with the code they are on. Do the same for the 25 preview classes (`Admin::XComponentPreview` becomes `Admin::Ui::XComponentPreview`) and the test classes' names where they repeat the constant. `bin/rubocop -A app/components/admin/ui test/components/admin/ui test/components/previews/admin/ui` fixes indentation; read its diff.

- [ ] **Step 4: Rewrite the references**

```bash
ruby script/layout/constants.rb $(for n in Button ChannelChip Checkbox ChipInput ConfirmDialog ContentTypeDot Dialog EmptyState ErrorSummary Field FileDrop LanguageTabs Menu Pagination PasswordField SaveBar SaveStatus StatusChip ThemeSwitch TimeAgo Toast ToastRegion TranslationChip UserName WordDiff; do printf 'Admin::%sComponent=Admin::Ui::%sComponent Admin::%sComponentPreview=Admin::Ui::%sComponentPreview ' $n $n $n $n; done)
```
Read every line under `REVIEW:`. A bare name rewritten inside a file that is itself in `Admin::Ui` reads `Ui::XComponent` and still resolves; leave it. A bare name that was NOT the component (a local class of another namespace with the same ending) is put back by hand. `FieldComponent` deserves care: `Admin::Fields::…Field` classes and `Admin::Columns::` are other things and must be unchanged (`git diff --stat app/components/admin/fields app/components/admin/columns` shows only reference lines).

Run: `bin/rails zeitwerk:check`. Expected: "Otherwise, all is good!".

- [ ] **Step 5: Move the strings**

In `config/locales/admin/components.en.yml` the keys under `en.admin.components` for these 25 scopes (`button:`, `channel_chip:` … `word_diff:`; a scope with no strings has no key) move, unchanged, to a new `config/locales/admin/ui.en.yml` under `en.admin.components.ui`, with a header comment in the style of the old file's saying what the file holds. Then:
```bash
grep -rnE 'admin\.components\.(button|channel_chip|checkbox|chip_input|confirm_dialog|content_type_dot|dialog|empty_state|error_summary|field|file_drop|language_tabs|menu|pagination|password_field|save_bar|save_status|status_chip|theme_switch|time_ago|toast|toast_region|translation_chip|user_name|word_diff)\b' app test config docs CLAUDE.md
```
Each hit is an absolute key: insert `ui.` after `admin.components.`. In `test/lib/admin_i18n_test.rb` update the paths in `CONVERTED` (a listed path that does not exist fails, by that test's own rule).

- [ ] **Step 6: Guard that nothing shared is loose, run, commit**

Append to `SourceLayoutTest`:
```ruby
  test "a shared building block lives in admin/ui" do
    assert Dir[ROOT.join("app/components/admin/ui/*_component.rb")].size >= 25
    assert_predicate ROOT.join("app/components/admin/ui/button_component.rb"), :exist?
  end
```
Run: `PGGSSENCMODE=disable bin/rails test test/lib test/components test/helpers test/integration && bin/rubocop && bin/rails zeitwerk:check`
Expected: 0 failures, no offenses. Then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`. Expected: 0 failures.

```bash
git add -A && git commit -m "ref: the shared building blocks of CS Studio live in Admin::Ui"
```

---

### Task 3: The stray components move to their screens

**Files (each with its template, test and preview, as in Task 2):**

| From `app/components/admin/` | To | New class |
|---|---|---|
| `block_card`, `block_picker`, `page_settings_form`, `post_form`, `related_posts` | `editor_screen/` | `Admin::EditorScreen::…Component` |
| `tree`, `tree_node` | `pages_screen/` (new) | `Admin::PagesScreen::…Component` |
| `permission_matrix` | `groups_screen/` | `Admin::GroupsScreen::PermissionMatrixComponent` |
| `mind_graph_legend` | `mind_graph_screen/` (new) | `Admin::MindGraphScreen::LegendComponent` (file `legend_component.rb`) |
| `system_check_row` | `setup_screen/` (new) | `Admin::SetupScreen::SystemCheckRowComponent` |
| `prefix_input` | `ui/` | `Admin::Ui::PrefixInputComponent` |

**Interfaces:**
- Consumes: `script/layout/constants.rb`; Task 2's `ui.en.yml`.
- Produces: the classes above; nothing loose in `app/components/admin/` but `admin_component.rb`.

- [ ] **Step 1: Check the three new namespaces against the shadow guard before moving**

`Admin::PagesScreen`, `Admin::MindGraphScreen`, `Admin::SetupScreen`: none may equal a name at the top of `app/models`, `app/services`, `app/queries`, `app/values`, `app/constraints`. Run `ls app/models app/services app/queries app/values app/constraints | grep -iE '^(pages_screen|mind_graph_screen|setup_screen)'`. Expected: nothing. (`Setup::` exists as a namespace; `Admin::SetupScreen` does not shadow it.)

- [ ] **Step 2: Move, nest and rewrite, one row of the table at a time**

For each row: `git mv` the files (and test and preview) as in Task 2 Step 2; wrap the class in its screen's module as in Task 2 Step 3 (for the legend also rename the class and its files); then run `ruby script/layout/constants.rb Old=New OldPreview=NewPreview` for that row and read `REVIEW:`. `Admin::TreeComponent` and `TreeNodeComponent`: the bare-name rule would also touch `closure_tree` words or a `Tree` in prose: read the diff of every file the tool lists for this row. After each row: `bin/rails zeitwerk:check`.

- [ ] **Step 3: Move the strings**

Each moved component's scope under `en.admin.components` in `components.en.yml` (for `prefix_input`, to `ui.en.yml`) moves to its new scope: `block_card` → `editor_screen.block_card`, `tree_node` → `pages_screen.tree_node`, `mind_graph_legend` → `mind_graph_screen.legend`, and so on by the table. Rewrite absolute keys found by `grep -rnE 'admin\.components\.(block_card|block_picker|page_settings_form|post_form|related_posts|tree|tree_node|permission_matrix|mind_graph_legend|system_check_row|prefix_input)\b' app test config docs CLAUDE.md`. Update `CONVERTED` paths in `test/lib/admin_i18n_test.rb`.

- [ ] **Step 4: Guard, run, commit**

Replace Task 2's "a shared building block lives in admin/ui" test with:
```ruby
  test "nothing is loose in app/components/admin but the base class" do
    loose = Dir[ROOT.join("app/components/admin/*.{rb,erb}")].map { |path| File.basename(path) }
    assert_equal %w[admin_component.rb], loose
  end
```
Run the same four commands as Task 2 Step 6, with the same expectations.

```bash
git add -A && git commit -m "ref: every CS Studio component is in its screen's folder or in Admin::Ui"
```

---

### Task 4: One locale file per screen

**Files:**
- Modify: `config/locales/admin/components.en.yml` (ends empty of screen scopes and is deleted if nothing is left)
- Create: `config/locales/admin/<screen>.en.yml` for each scope left under `en.admin.components` (`audit_screen`, `dashboard_screen`, `editor_screen`, `groups_screen`, `media_library`, `pages_screen`, `posts_screen`, `settings_screen`, `shell`, `tokens_screen`, `translation_screen`, `trash_screen`, `users_screen`, `fields`, `columns`, `mind_graph_screen`, `setup_screen`: only those that have keys)
- Modify: `docs/reference/i18n.md`, the comment in `app/components/admin/admin_component.rb` that names `components.en.yml`, `test/lib/source_layout_test.rb`

**Interfaces:**
- Produces: for every folder under `app/components/admin/` that has strings, `config/locales/admin/<folder>.en.yml` holding exactly `en.admin.components.<folder>`. Existing `notes.en.yml`, `tags.en.yml`, `mind_graph.en.yml`, `layout.en.yml` keep their names and contents (if `mind_graph.en.yml` holds scripts' strings under another scope, the legend's component scope goes in `mind_graph_screen.en.yml`).

- [ ] **Step 1: Record what resolves today**

```bash
bin/rails runner 'flat = ->(h, p = []) { h.flat_map { |k, v| v.is_a?(Hash) ? flat.(v, p + [k]) : [[(p + [k]).join("."), v]] } }; File.write("tmp/i18n_before.txt", flat.(I18n.backend.send(:translations)[:en][:admin]).sort.map { |k, v| "#{k}=#{v.inspect}" }.join("\n"))'
```

- [ ] **Step 2: Split the file**

Move each top-level scope of `en.admin.components` into its own file, keys and comments unchanged, each file opening with one comment line naming the folder it serves.

- [ ] **Step 3: Prove nothing changed**

Run the Step 1 command again writing `tmp/i18n_after.txt`, then `diff tmp/i18n_before.txt tmp/i18n_after.txt`. Expected: no output. Delete both files.

- [ ] **Step 4: Guard and docs**

Append to `SourceLayoutTest`:
```ruby
  test "a locale file of admin components holds one folder's scope" do
    Dir[ROOT.join("config/locales/admin/*.en.yml")].each do |path|
      scopes = (YAML.load_file(path).dig("en", "admin", "components") || {}).keys
      next if scopes.empty?
      assert_equal [ File.basename(path, ".en.yml") ], scopes, "#{File.basename(path)} holds #{scopes.inspect}"
    end
  end
```
If `notes.en.yml` or another existing file holds a component scope under a different file name, the test says so: rename the FILE to its scope only if nothing else refers to the file by name (`grep -rn "notes.en.yml" .`), otherwise list it in the test as a named exception with its reason. Update `docs/reference/i18n.md` and the `AdminComponent` comment to describe one file per folder.

Run: `PGGSSENCMODE=disable bin/rails test test/lib test/components`. Expected: 0 failures.

```bash
git add -A && git commit -m "ref: one locale file per screen folder for CS Studio's components"
```

---

### Task 5: Scripts — `ui`, `shell`, `saving`

**Files** (under `app/javascript/controllers/admin/`; `X_controller.js` → `<topic>/<new>_controller.js`):

| Topic | Controllers (new file name where it changes) | New identifier |
|---|---|---|
| `ui` | `auto_submit`, `busy`, `char_count`, `chip_input`, `clipboard`, `dialog`, `menu`, `toast`, `override_field` | `admin--ui--<name>` |
| `shell` | `command_palette`, `drawer`, `file_drop_guard`, `fragment_links` | `admin--shell--<name>` |
| `saving` | `autosave`, `save_bar`, `queue_hold`, `pending_lock` | `admin--saving--<name>` |

Also: `app/javascript/autosave/` → `app/javascript/saving/` (six modules), with `config/importmap.rb`'s `pin_all_from "app/javascript/autosave", under: "autosave"` becoming `…/saving", under: "saving"` and every `from "autosave/…"` import becoming `from "saving/…"`.

**Interfaces:**
- Consumes: `script/layout/identifiers.rb`; the fact recorded in Task 1 Step 3 that nested controllers are pinned and registered.
- Produces: the identifiers above. Later tasks' controllers that import one of these by path (`controllers/admin/toast_controller`) import the new path.

- [ ] **Step 1: Read before moving `saving`**

Read the header comments of `app/javascript/autosave/queue.js` and `app/javascript/controllers/admin/save_bar_controller.js`, and `docs/reference/save-rule-and-write-queue.md`. List in the report every place they name a controller by identifier or an event by name; those are the lines to check by eye after the rewrite.

- [ ] **Step 2: Move one topic, rewrite, test; then the next**

For `ui`:
```bash
mkdir -p app/javascript/controllers/admin/ui
for n in auto_submit busy char_count chip_input clipboard dialog menu toast override_field; do git mv app/javascript/controllers/admin/${n}_controller.js app/javascript/controllers/admin/ui/; done
ruby script/layout/identifiers.rb admin--auto-submit=admin--ui--auto-submit admin--busy=admin--ui--busy admin--char-count=admin--ui--char-count admin--chip-input=admin--ui--chip-input admin--clipboard=admin--ui--clipboard admin--dialog=admin--ui--dialog admin--menu=admin--ui--menu admin--toast=admin--ui--toast admin--override-field=admin--ui--override-field
grep -rnE 'controllers/admin/(auto_submit|busy|char_count|chip_input|clipboard|dialog|menu|toast|override_field)_controller' app test docs CLAUDE.md config
```
Each hit of the last command is an import or a doc path: insert `ui/`. Read every `REVIEW:` line (an identifier that prefixes another: `admin--dialog` and nothing longer today, but `admin--toast` against a `toast-region` attribute is the kind to look at) and the full diff of `app/assets/tailwind/`.

Run: `PGGSSENCMODE=disable bin/rails test test/lib/source_layout_test.rb test/integration/public_javascript_test.rb test/lib/tailwind_sources_test.rb test/components test/integration`, then `bin/rails tailwindcss:build` and the system files that use these controls: `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/dialog*_test.rb test/system/admin/menu*_test.rb test/system/admin/toast*_test.rb test/system/admin/tags*_test.rb test/system/admin/posts*_test.rb` (use the files that exist: `ls test/system/admin | grep -E 'dialog|menu|toast|tags|posts|chip'`). Expected: 0 failures. Commit: `ref: the shared behaviours of CS Studio's controls are in controllers/admin/ui`.

Repeat the same four moves (mkdir, `git mv`, `identifiers.rb` with one `old=new` per controller of the table, the import-path grep) for `shell` (system files: `ls test/system/admin | grep -E 'shell|drawer|jump|command|sidebar|layout'`) and commit `ref: the shell's behaviours are in controllers/admin/shell`; then for `saving`, together with the `autosave/` → `saving/` folder move and the import map line, and the grep `grep -rnE '"autosave/|from "autosave|app/javascript/autosave' app test docs CLAUDE.md config` (system files: `ls test/system/admin | grep -E 'autosave|save_bar|promotion|stale|leave|queue|settings|users|sections|editor'`), commit `ref: autosave, the save bar and the write queue are one topic, saving`.

- [ ] **Step 3: The whole system suite once for the three topics**

Run: `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`
Expected: 0 failures. A failure here is a missed name: find it with `git grep -nE 'admin--(auto-submit|busy|char-count|chip-input|clipboard|dialog|menu|toast|override-field|command-palette|drawer|file-drop-guard|fragment-links|autosave|save-bar|queue-hold|pending-lock)([^a-z-]|-)' -- app test | grep -v 'admin--\(ui\|shell\|saving\)--'`.

---

### Task 6: Scripts — the editors, media and the mind graph

**Files:**

| Topic | Old file → new file | New identifier |
|---|---|---|
| `editor` | `blocks`, `section`, `slug_preview`, `new_record`, `groups` (the repeating field groups of a block or post form) | `admin--editor--<name>` |
| `pages` | `tree` | `admin--pages--tree` |
| `posts` | `bulk_select` | `admin--posts--bulk-select` |
| `rich_text` | `rich_text` → `rich_text/editor`, `rich_text_dialog` → `rich_text/dialog` | `admin--rich-text--editor`, `admin--rich-text--dialog` |
| `translation` | `translate` | `admin--translation--translate` |
| `media` | `media_drop` → `media/drop`, `media_field` → `field`, `media_panel` → `panel`, `media_picker` → `picker`, `media_select` → `select`, `media_upload` → `upload` | `admin--media--<name>` |
| `mind_graph` | `mind_graph` → `mind_graph/graph` | `admin--mind-graph--graph` |

**Interfaces:**
- Consumes: `script/layout/identifiers.rb`. `app/javascript/rich_text/`, `media/` and `mind_graph/` (plain modules) do not move: they already carry their topic's name.
- Produces: the identifiers above.

- [ ] **Step 1: Move one topic at a time, as in Task 5 Step 2**

For each topic: `mkdir -p`, `git mv` (to the NEW file name where the table renames it), then `identifiers.rb` with one pair per controller. The pairs where one old identifier prefixes another are the dangerous ones here and must be given in ONE call so the longest wins: `admin--rich-text=admin--rich-text--editor admin--rich-text-dialog=admin--rich-text--dialog`; `admin--media-…` six pairs together; `admin--mind-graph=admin--mind-graph--graph`. Read every `REVIEW:` line and decide each by opening the file: `data-admin--rich-text-dialog-id-param` is a param named `dialog-id` of the editor or a param `id` of the dialog; the controller's source (`params.dialogId` or `params.id`) says which.

The mind graph: its controller loads `mind_graph/app` by dynamic `import()`, and `test/integration/public_javascript_test.rb` plus the rule in `CLAUDE.md` require `mind_graph/` to stay `preload: false`. The controller's own file moving does not change that pin; run that test after the move.

After each topic: the unit files of Task 5 Step 2, then that topic's system files (`ls test/system/admin | grep -E '<topic words>'`: for `editor` `editor|blocks|sections|new_|slug`; `pages` `tree|pages`; `posts` `posts|bulk`; `rich_text` `rich_text|link|image`; `translation` `translat`; `media` `media|picker|upload`; `mind_graph` `mind`), then one commit per topic, subject `ref: <topic>'s controllers are in controllers/admin/<topic>`.

- [ ] **Step 2: The whole system suite**

Run: `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`. Expected: 0 failures.

---

### Task 7: Scripts — notes

**Files:**

| Old file | New file | New identifier |
|---|---|---|
| `notes_controller.js` | `notes/drawer_controller.js` | `admin--notes--drawer` |
| `notes_live_controller.js` | `notes/live_controller.js` | `admin--notes--live` |
| `notes_alert_controller.js` | `notes/alert_controller.js` | `admin--notes--alert` |
| `notes_permission_controller.js` | `notes/permission_controller.js` | `admin--notes--permission` |
| `note_composer_controller.js` | `notes/composer_controller.js` | `admin--notes--composer` |
| `note_gif_controller.js` | `notes/gif_controller.js` | `admin--notes--gif` |
| `note_reactions_controller.js` | `notes/reactions_controller.js` | `admin--notes--reactions` |
| `note_refusal_controller.js` | `notes/refusal_controller.js` | `admin--notes--refusal` |
| `note_unsaved_controller.js` | `notes/unsaved_controller.js` | `admin--notes--unsaved` |
| `password_answer_controller.js` | `account/password_answer_controller.js` | `admin--account--password-answer` |

**Interfaces:**
- Consumes: `script/layout/identifiers.rb`.
- Produces: the identifiers above. The presence work that follows this branch builds on `controllers/admin/notes/live_controller.js`.

- [ ] **Step 1: List what talks to what, before moving**

`grep -rnE '"admin--note[s]?[a-z-]*:[a-z-]+"|admin--note[s]?[a-z-]*:[a-zA-Z-]+(->|@)' app/javascript app/components app/views` lists every event dispatched or heard by identifier (`admin--notes-live:delivery`, `admin--notes-alert:settled`, …). Put the list in the report: after the rewrite each pair must name the same new identifier on both sides.

- [ ] **Step 2: Move and rewrite in one call**

`admin--notes` prefixes `admin--notes-live`, `-alert`, `-permission`: all ten pairs go into ONE `identifiers.rb` call. `git mv` first (ten files, to the new names). Then the import-path grep: `grep -rnE 'controllers/admin/(notes|notes_live|notes_alert|notes_permission|note_composer|note_gif|note_reactions|note_refusal|note_unsaved|password_answer)_controller' app test docs CLAUDE.md config` and fix each to the new path (`note_composer_controller` exports `forgetDrafts`, imported by the live controller).

Read EVERY `REVIEW:` line: for `admin--notes-…` the tail decides (`admin--notes-target` is the drawer's target; `admin--notes-live-unread-url-value` is the live controller's value). Then check the Step 1 list pair by pair, and these by eye, because they are not attributes: `localStorage` and `sessionStorage` keys (`cs-notes-open`, `cs-note-draft:`) must be UNCHANGED (they are not identifiers; `git diff | grep -nE 'cs-note'` shows no changed line), and the `BroadcastChannel` name in the alert controller is unchanged.

- [ ] **Step 3: Run notes' tests**

Run: `PGGSSENCMODE=disable bin/rails test test/lib test/integration/admin/note*_test.rb test/integration/admin/notes*_test.rb test/components/admin/notes_screen test/channels`, then `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test $(ls test/system/admin/note*_test.rb test/system/admin/account*_test.rb test/system/admin/mind_graph*_test.rb)`.
Expected: 0 failures. Commit: `ref: notes' controllers are in controllers/admin/notes`.

---

### Task 8: Scripts — the remaining screens, and nothing loose

**Files:**

| Topic | Old file → new file | New identifier |
|---|---|---|
| `groups` | `branch_picker`, `permission_matrix` | `admin--groups--<name>` |
| `settings` | `settings_tabs` → `settings/tabs`, `ai_settings` → `settings/ai`, `repeat_rows`, `sortable_rows` | `admin--settings--tabs`, `--ai`, `--repeat-rows`, `--sortable-rows` |
| `tokens` | `token_reveal` → `tokens/reveal`, `group_hint` | `admin--tokens--reveal`, `admin--tokens--group-hint` |
| `tags` | `tag_dialogs` → `tags/dialogs` | `admin--tags--dialogs` |
| `users` | `password_disclosure` | `admin--users--password-disclosure` |
| `dashboard` | `quick_create` | `admin--dashboard--quick-create` |

Any controller still loose after these (list with `ls app/javascript/controllers/admin/*.js`) is placed by the rule (used by one screen: that screen's topic; by several: `ui`) and named in the report.

- [ ] **Step 1: Move, rewrite, test per topic** as in Task 5 Step 2 (`admin--groups` was the field groups' identifier until Task 6 made it `admin--editor--groups`; confirm no `admin--groups` without `--` is left before using the topic name: `git grep -nE 'admin--groups([^-]|-[a-z])' -- app test`). One commit per topic.

- [ ] **Step 2: Guards for the script layout**

Append to `SourceLayoutTest`:
```ruby
  test "nothing is loose in app/javascript/controllers/admin" do
    assert_empty Dir[CONTROLLERS.join("admin/*.js")].map { |path| File.basename(path) }
  end

  test "a topic's plain modules are in the folder of the same name" do
    topics = Dir[CONTROLLERS.join("admin/*/")].map { |path| File.basename(path) }
    modules = Dir[ROOT.join("app/javascript/*/")].map { |path| File.basename(path) } - %w[controllers]
    strangers = modules - topics - %w[i18n search]
    assert_empty strangers, "module folders with no topic of that name (i18n and search are shared helpers): #{strangers.inspect}"
  end

  test "no identifier of the old one-level form is left" do
    old = /(?<![a-z0-9-])admin--[a-z0-9]+(?:-[a-z0-9]+)*(?![a-z0-9-])/
    left = (SOURCES + %w[test]).flat_map { |dir| Dir[ROOT.join(dir, "**/*.{rb,erb,js,css}")] }.flat_map do |path|
      next [] if path.end_with?("source_layout_test.rb")
      File.read(path).scan(old).uniq.map { |token| "#{Pathname(path).relative_path_from(ROOT)}: #{token}" }
    end
    assert_empty left
  end
```
Also change Task 1's `TOKEN` so that every token must now own a file in the two-level form (the first test already does this through `identifiers`).

- [ ] **Step 3: Run everything**

Run: `bin/rubocop && bin/rails zeitwerk:check && PGGSSENCMODE=disable bin/rails test && bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`
Expected: no offenses, 0 failures in both suites. Commit the guards: `test: nothing is loose among CS Studio's controllers, and no old identifier is left`.

---

### Task 9: The two model oddities, the documents, and the tools go

**Files:**
- Look at: `app/models/admin/field_params.rb`, `app/models/page/tree_ranking.rb`
- Modify: `CLAUDE.md`, `docs/reference/*.md`, `docs/roadmap.md` (alone, in its own commit, re-read first)
- Delete: `script/layout/`

- [ ] **Step 1: `Admin::FieldParams`**

It reshapes request parameters and is used by controllers. If every caller is a controller or a controller concern (`grep -rn "FieldParams" app lib`), move it to `app/controllers/concerns/admin/field_params.rb` with its test, run `bin/rails zeitwerk:check` and `PGGSSENCMODE=disable bin/rails test test/lib/dependency_direction_test.rb test/lib/admin_namespace_shadow_test.rb` and the callers' tests. If a model, query or service calls it, leave it where it is and say why in the report. `Page::TreeRanking` stays: it is the page model's own concern, and a folder of one file beside its model is this codebase's convention (`audit.rb` beside `audit/`).

- [ ] **Step 2: Documents**

The two tools already rewrote names inside `docs/` and `CLAUDE.md`; what is left is prose that describes the layout. In `CLAUDE.md`: the reference index's paths (`app/javascript/controllers/admin/notes*_controller.js` and the like become the topic folders), the "Never define `Admin::Media`…" convention gains `Admin::Ui::` for shared building blocks and names `Admin::PagesScreen::`, `Admin::MindGraphScreen::`, `Admin::SetupScreen::`, and a new convention paragraph after it:

> **Where a script goes.** A topic has one name and up to two folders with it: its Stimulus controllers in `app/javascript/controllers/admin/<topic>/` and its plain modules in `app/javascript/<topic>/`. A controller's identifier follows its path (`admin--notes--live`). A behaviour of a shared control is in `ui`, what only the layout uses in `shell`. Nothing is loose in `controllers/admin/` or in `app/components/admin/` (`test/lib/source_layout_test.rb`).

Check every path the docs name still exists: `grep -ohE '(app|test|config)/[A-Za-z0-9_/.*-]+\.(rb|js|erb|yml|css)' CLAUDE.md docs/reference/*.md | sort -u | while read p; do ls $p >/dev/null 2>&1 || echo "MISSING $p"; done` and fix each MISSING line that this branch caused. In `docs/roadmap.md` (its own commit): the entry that names `admin/blocks_controller.js` and the others to split gets their new paths, and one line under what shipped says the layout cleanup happened and what its guard is.

- [ ] **Step 3: Remove the tools and verify on the last commit**

```bash
git rm -r script/layout && git commit -m "chore: the layout cleanup's rename tools have done their work"
```
Run, one at a time, and put the totals verbatim in the report: `bin/rubocop`; `bin/brakeman`; `bin/bundler-audit`; `bin/importmap audit`; `bin/rails zeitwerk:check`; `PGGSSENCMODE=disable bin/rails test`; `bin/rails tailwindcss:build`; `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`. Expected: clean, 0 failures, and the same number of runs as on `main` plus the tests this plan added (record `main`'s counts from the first task's run for the comparison).
