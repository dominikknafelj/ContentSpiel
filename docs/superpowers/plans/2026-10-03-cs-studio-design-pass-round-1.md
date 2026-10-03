# CS Studio design pass, round 1 (foundations and bugs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put every CS Studio screen into the new shell and onto one set of shared components, fix the eight bugs and the mind-graph layout bug, and rebuild sign-in, password reset and the setup wizard with the tokens.

**Architecture:** Each shared pattern in spec §4 becomes one ViewComponent under `app/components/admin/` (plus a Stimulus controller under `app/javascript/controllers/admin/` where it has behaviour), with a Lookbook preview and a component test. Existing call sites switch to the new components in the same task that builds them; old components are deleted, not kept beside the new ones. Screens keep their current layout in this round; only the shell, the shared parts and the listed bugs change.

**Tech Stack:** Rails 8.1, ViewComponent + Lookbook, Tailwind v4 (`bin/rails tailwindcss:build`), Stimulus via importmap (no npm), Minitest + fixtures, Cuprite system tests.

**Spec:** `docs/superpowers/specs/2026-10-03-cs-studio-design-pass-design.md` (§3, §4, §5.1, §5.5, §6). Visual reference: `docs/design/cs-studio-handoff-v3/` — open the named `.dc.html` file in a browser and copy spacing, sizes and copy from it. The mockups are references, not production code: never copy their inline styles, React-like markup or hex values.

## Global Constraints

- Server-rendered ERB and ViewComponents, Tailwind v4, Hotwire. New JS is a Stimulus controller in `app/javascript/controllers/admin/` (auto-registered as `admin--<name>`) or, for sign-in/setup pages, in `app/javascript/controllers/`. No React, no npm.
- Every new or changed component gets a Lookbook preview in `test/components/previews/admin/` and a test in `test/components/admin/`. `test/components/previews_test.rb` must stay green.
- Tokens only: no raw hex, no `dark:` colour variants. From the handoff CSS take **only** `--cs-chrome`, `--cs-cat-1…6` and their `--color-*` mappings. Keep the repo's font files, `font-cs`/`font-cs-mono`, the `color-scheme` handling and the Tailwind entry file.
- Never define `Admin::Media`, `Admin::Trash`, `Admin::Translations`, `Admin::AI`, `Admin::Ai` or `Admin::Dashboard`. New component namespaces follow the `…Screen` pattern.
- Forms cannot nest. Dialog forms and the media picker live once in the layout, outside `#content`.
- Admin strings stay hard-coded English; write each sentence as one string (no concatenating sentence parts).
- Red (`danger*`) only for destructive actions and failures. Translation states never use red.
- Colour is never the only cue: chips carry a glyph and an `aria-label`; dialogs trap focus; drag has a keyboard path.
- No permission rule changes. Every write goes through an `ApplicationService` with `authorize!` and `record_event`. "Not found, not forbidden" stays.
- Radius is `rounded-cs` everywhere; `rounded-full` only for avatars, tag chips, dots and toggles. Shadows (`shadow-menu`) only on menus, popovers, dialogs and lifted drag rows.
- Field labels: `font-cs-mono text-label uppercase tracking-mono text-meta` (`setup_label_class`).
- Long, load-bearing comments are the norm here: keep the existing ones that still apply, and comment new non-obvious logic at the same density.
- Commits follow conventional commits (`feat|fix|ref|style|docs|test|chore`) and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- After any CSS class change run `bin/rails tailwindcss:build` before system tests (`bin/dev`'s watcher is broken locally).
- Commands: one file `bin/rails test path/to/test.rb`; whole suite `bin/rails test`; system `bin/rails test:system`; lint `bin/rubocop`.

## Review Focus

1. **`localStorage` throws or holds junk** (private window, blocked site data, a stale `cs-theme` value like `"blue"`): the page renders in the OS theme and the switch shows "Auto". Pinned in Task 1.
2. **A user with no grants at all**: the sidebar shows Content with Dashboard and AI assistant's group only; empty groups (People) disappear entirely, the account block reads "No groups", ⌘K returns only what they can read. Pinned in Tasks 12 and 13.
3. **⌘K query with `%`, `_`, `\` or 500 characters**: treated as literal text, truncated to 100 characters, never a wildcard match-all and never a 500. Pinned in Task 13.
4. **A pager page that doesn't exist** (`?page=0`, `?page=abc`, `?page=9999`): shows the first page for junk and an empty-state card with a link back to page 1 for a too-high page; never a 500. Pinned in Task 9.
5. **A password of exactly 12 multibyte characters, and an existing user with an 8-character password**: the first is accepted (characters, not bytes); the second still signs in and can edit their name without being forced to change the password. Pinned in Task 4.

## File structure

New components (each `*.rb` + `*.html.erb` unless noted), all in `app/components/admin/`:

| File | Responsibility |
|---|---|
| `theme_switch_component` | Three-way Light / Dark / Auto segmented control |
| `status_chip_component` | Live / Draft / Scheduled chip (replaces `status_badge_component`) |
| `translation_chip_component.rb` | Done / missing / outdated chip (replaces `translation_screen/state_badge_component`) |
| `language_tabs_component` | Underline language tabs with dots and "+N ▾" (replaces `language_switcher_component`) |
| `content_type_dot_component.rb` | `cat-N` dot or ring + type name |
| `user_name_component.rb` | A user's display name, "a deleted user" or "System" |
| `password_field_component` | Password input with Show/Hide and the four-bar meter |
| `dialog_component` | The one `<dialog>` shell: widths, header, footer, destructive variant |
| `confirm_dialog_component` | Rebuilt on `dialog_component` (same public API plus `destructive:`) |
| `toast_component` | One toast; `toast_region_component` holds the live region |
| `error_summary_component` | The 422 summary box with linked field names |
| `select_component.rb` | Styled native `<select>` |
| `file_drop_component` | Drop zone + "Choose file" |
| `prefix_input_component` | Input with a sunken prefix cell (slug) |
| `menu_component` | Popover panel for ⋯ menus and split buttons |
| `pagination_component` | "51–100 OF 312" + page links |
| `time_ago_component.rb` | Relative time with absolute `title` |
| `save_bar_component` | Sticky "N unsaved changes · Cancel · Save" |
| `shell/sidebar_component` | Groups, badges, ⌘K trigger, account block, theme switch |
| `shell/top_bar_component` | 48px bar for narrow screens |
| `shell/command_palette_component` | The ⌘K dialog |

New Stimulus controllers in `app/javascript/controllers/admin/`: `dialog`, `toast`, `menu`, `auto_submit`, `password_field`, `file_drop`, `save_bar`, `drawer`, `command_palette`, `busy`. `app/javascript/controllers/theme_controller.js` and a new `password_field_controller.js` copy live outside `admin/` because sign-in and setup load `application`, not `admin`.

Other new files: `app/models/pagination.rb` (page-number value object), `app/queries/jump/search.rb`, `app/controllers/admin/jump_controller.rb`, `app/services/users/update_profile.rb`, `app/views/admin/errors/not_found.html.erb`.

---

### Task 1: Tokens and the three-way theme

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css`, `app/assets/tailwind/content-spiel.tailwind.css`
- Modify: `app/views/shared/_theme_head.html.erb`, `app/javascript/controllers/theme_controller.js`
- Create: `app/components/admin/theme_switch_component.rb`, `.html.erb`; `test/components/admin/theme_switch_component_test.rb`; `test/components/previews/admin/theme_switch_component_preview.rb`
- Delete: `app/views/shared/_theme_toggle.html.erb` (its three call sites in `layouts/admin`, `layouts/product`, `layouts/setup` render the component instead)
- Test: `test/integration/design_tokens_test.rb`, `test/system/theme_toggle_test.rb` (rewritten)

**Interfaces:**
- Produces: utilities `bg-chrome`, `bg-cat-1`…`bg-cat-6`, `text-cat-N`, `border-cat-N`. `Admin::ThemeSwitchComponent.new` (no arguments). `<html data-theme="light|dark" data-theme-choice="light|dark|auto">`. `localStorage["cs-theme"]` ∈ `light|dark|auto`.

- [ ] **Step 1: Write the failing token test.** Add to `test/integration/design_tokens_test.rb`:

```ruby
test "the chrome and content-type tokens exist in both themes and map to utilities" do
  css = Rails.root.join("app/assets/tailwind/content-spiel.css").read
  light, dark = css.split('[data-theme="dark"] {', 2)
  %w[--cs-chrome --cs-cat-1 --cs-cat-2 --cs-cat-3 --cs-cat-4 --cs-cat-5 --cs-cat-6].each do |token|
    assert_includes light, "#{token}:", "#{token} missing from the light theme"
    assert_includes dark, "#{token}:", "#{token} missing from the dark theme"
  end
  map = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
  assert_includes map, "--color-chrome: var(--cs-chrome);"
  (1..6).each { |n| assert_includes map, "--color-cat-#{n}: var(--cs-cat-#{n});" }
  refute_match(/color-scheme\s*:/, css.gsub(%r{/\*.*?\*/}m, ""), "color-scheme stays per layout, never global")
end
```

- [ ] **Step 2: Run it.** `bin/rails test test/integration/design_tokens_test.rb` — expect FAIL ("--cs-chrome missing").

- [ ] **Step 3: Add the tokens.** In `content-spiel.css`, inside `:root, [data-theme="light"]` after `--cs-ph-b`:

```css
  --cs-chrome: #ffffff;              /* sidebar / tree column */
  --cs-cat-1: oklch(0.52 0.09 200);
  --cs-cat-2: oklch(0.52 0.11 300);
  --cs-cat-3: oklch(0.52 0.09 120);
  --cs-cat-4: oklch(0.52 0.10 0);
  --cs-cat-5: oklch(0.50 0.08 230);
  --cs-cat-6: oklch(0.54 0.08 95);   /* types 7+ reuse 1-6 as rings */
```

and inside `[data-theme="dark"]`:

```css
  --cs-chrome: #131416;
  --cs-cat-1: oklch(0.74 0.08 200);
  --cs-cat-2: oklch(0.74 0.10 300);
  --cs-cat-3: oklch(0.74 0.09 120);
  --cs-cat-4: oklch(0.74 0.09 0);
  --cs-cat-5: oklch(0.74 0.07 230);
  --cs-cat-6: oklch(0.78 0.08 95);
```

In `content-spiel.tailwind.css`, inside `@theme inline` after the danger lines:

```css
  --color-chrome: var(--cs-chrome);
  --color-cat-1: var(--cs-cat-1);
  --color-cat-2: var(--cs-cat-2);
  --color-cat-3: var(--cs-cat-3);
  --color-cat-4: var(--cs-cat-4);
  --color-cat-5: var(--cs-cat-5);
  --color-cat-6: var(--cs-cat-6);
```

Change nothing else in either file. Run the test: PASS.

- [ ] **Step 4: Write the failing component test** `test/components/admin/theme_switch_component_test.rb`:

```ruby
require "test_helper"

class Admin::ThemeSwitchComponentTest < ViewComponent::TestCase
  test "renders three radio-like buttons in a labelled group" do
    render_inline(Admin::ThemeSwitchComponent.new)
    assert_selector "[role=radiogroup][aria-label='Theme'][data-controller='theme']"
    %w[light dark auto].each do |choice|
      assert_selector "button[role=radio][data-theme-choice-param='#{choice}'][data-action='theme#choose']"
    end
    assert_text "Light"
    assert_text "Dark"
    assert_text "Auto"
  end
end
```

Run: FAIL (uninitialized constant).

- [ ] **Step 5: Build the component.** `theme_switch_component.rb`:

```ruby
module Admin
  # The three-way theme control (design pass spec §4, handoff §1): Light,
  # Dark, or Auto (follow the OS). Which button is "on" is painted by CSS
  # from `<html data-theme-choice>` -- set before first paint by
  # shared/_theme_head -- so the right one is marked before Stimulus
  # connects; `theme_controller.js` only keeps `aria-checked` in step.
  class ThemeSwitchComponent < AdminComponent
    CHOICES = { "light" => "Light", "dark" => "Dark", "auto" => "Auto" }.freeze
  end
end
```

`theme_switch_component.html.erb`:

```erb
<div role="radiogroup" aria-label="Theme" data-controller="theme"
     class="admin-theme-switch inline-flex rounded-cs border border-line-strong p-0.5">
  <% Admin::ThemeSwitchComponent::CHOICES.each do |choice, label| %>
    <%= tag.button label, type: "button", role: "radio", aria: { checked: "false" },
          data: { action: "theme#choose", theme_choice_param: choice, theme_target: "choice" },
          class: "admin-theme-switch__choice cursor-pointer rounded-cs px-2 py-0.5 font-cs-mono text-label uppercase tracking-mono text-meta hover:text-ink" %>
  <% end %>
</div>
```

Add to `app/assets/tailwind/content-spiel.tailwind.css` (below `@theme`), so the active choice needs no JS:

```css
[data-theme-choice="light"] .admin-theme-switch__choice[data-theme-choice-param="light"],
[data-theme-choice="dark"] .admin-theme-switch__choice[data-theme-choice-param="dark"],
[data-theme-choice="auto"] .admin-theme-switch__choice[data-theme-choice-param="auto"] {
  background: var(--cs-sunken);
  color: var(--cs-ink);
}
```

- [ ] **Step 6: Replace `_theme_head`'s script body:**

```js
  (function () {
    var stored = null;
    try { stored = localStorage.getItem("cs-theme"); } catch (e) {}
    var choice = stored === "light" || stored === "dark" ? stored : "auto";
    var prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    var root = document.documentElement;
    root.dataset.themeChoice = choice;
    root.dataset.theme = choice === "auto" ? (prefersDark ? "dark" : "light") : choice;
  })();
```

Keep the partial's comment, extended with one sentence: anything other than `light`/`dark` (missing, `auto`, junk) means Auto.

- [ ] **Step 7: Rewrite `theme_controller.js`:**

```js
import { Controller } from "@hotwired/stimulus"

// The three-way theme switch (Admin::ThemeSwitchComponent). `choice` is what
// the user picked (light | dark | auto) and lives in localStorage and on
// <html data-theme-choice>; `data-theme` is what it resolves to and is what
// the token CSS keys every colour off. shared/_theme_head does the same
// resolution before first paint; this controller handles clicks and, while
// the choice is "auto", follows the OS when it changes.
export default class extends Controller {
  static targets = ["choice"]

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => { if (this.choice === "auto") this.apply("auto") }
    this.media.addEventListener("change", this.onSystemChange)
    this.sync()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onSystemChange)
  }

  choose({ params }) {
    const choice = ["light", "dark", "auto"].includes(params.choice) ? params.choice : "auto"
    try { localStorage.setItem("cs-theme", choice) } catch (e) {}
    this.apply(choice)
  }

  apply(choice) {
    const root = document.documentElement
    root.dataset.themeChoice = choice
    root.dataset.theme = choice === "auto" ? (this.media.matches ? "dark" : "light") : choice
    this.sync()
  }

  sync() {
    this.choiceTargets.forEach((button) =>
      button.setAttribute("aria-checked", String(button.dataset.themeChoiceParam === this.choice)))
  }

  get choice() {
    return document.documentElement.dataset.themeChoice || "auto"
  }
}
```

- [ ] **Step 8: Swap the three call sites** (`render "shared/theme_toggle"` → `render Admin::ThemeSwitchComponent.new`), delete the partial, add the preview:

```ruby
class Admin::ThemeSwitchComponentPreview < ViewComponent::Preview
  def default = render(Admin::ThemeSwitchComponent.new)
end
```

- [ ] **Step 9: Rewrite `test/system/theme_toggle_test.rb`** (keep the file name; replace its tests):

```ruby
require "application_system_test_case"

class ThemeToggleTest < ApplicationSystemTestCase
  test "light, dark and auto each apply, survive a reload, and mark the chosen button" do
    visit admin_sign_in_path
    within("[role=radiogroup][aria-label='Theme']") { press "Dark" }
    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"
    assert_selector "button[role=radio][aria-checked='true']", text: "Dark"

    visit admin_sign_in_path
    assert_selector "html[data-theme='dark'][data-theme-choice='dark']"

    within("[role=radiogroup][aria-label='Theme']") { press "Light" }
    assert_selector "html[data-theme='light'][data-theme-choice='light']"

    within("[role=radiogroup][aria-label='Theme']") { press "Auto" }
    assert_selector "html[data-theme-choice='auto']"
    assert_equal "auto", page.evaluate_script("localStorage.getItem('cs-theme')")
  end

  test "a junk stored value falls back to auto instead of breaking the page" do
    visit admin_sign_in_path
    page.execute_script("localStorage.setItem('cs-theme', 'blue')")
    visit admin_sign_in_path
    assert_selector "html[data-theme-choice='auto']"
    assert_selector "button[role=radio][aria-checked='true']", text: "Auto"
  end
end
```

- [ ] **Step 10: Run.** `bin/rails tailwindcss:build`, then `bin/rails test test/components/admin/theme_switch_component_test.rb test/integration/design_tokens_test.rb test/components/previews_test.rb` and `bin/rails test test/system/theme_toggle_test.rb`. All PASS. Grep for leftovers: `grep -rn "theme_toggle\|theme#toggle" app test` returns nothing.

- [ ] **Step 11: Commit.** `git commit -m "feat: chrome and content-type tokens, three-way theme switch"`

---

### Task 2: `users.name` and one way to name a user

**Files:**
- Create: `db/migrate/<timestamp>_add_name_to_users.rb`; `app/components/admin/user_name_component.rb`; `app/services/users/update_profile.rb`; tests `test/models/user_test.rb` (add), `test/services/users/update_profile_test.rb`, `test/components/admin/user_name_component_test.rb`; preview
- Modify: `app/models/user.rb`, `app/services/users/save.rb` (permit `name`), `app/models/audit/snapshot.rb` only if it lists user attributes explicitly, `app/views/admin/users/{new,edit,index}.html.erb`, `app/views/admin/accounts/edit.html.erb`, `app/controllers/admin/accounts_controller.rb`, `config/routes.rb`, `app/components/admin/dashboard_screen/row_component.rb`, `app/components/admin/trash_screen/row_component.rb`, `app/helpers/admin/audit_events_helper.rb`, `app/views/admin/groups/{edit,_form}.html.erb`, `app/views/admin/api_tokens/index.html.erb`, `app/views/admin/audit_events/index.html.erb`

**Interfaces:**
- Produces: `User#display_name → String` (name if present, else `email_address`). `Admin::UserNameComponent.new(user:, user_id: nil)` → renders the display name; `"a deleted user"` when `user` is nil but `user_id` is present; `"System"` when both are nil. `Users::UpdateProfile.call(user, name:)` → result (`ok?`, `errors`). Route `patch "account/profile" → accounts#update_profile`, helper `admin_account_profile_path`.

- [ ] **Step 1: Failing model test** (append to `test/models/user_test.rb`):

```ruby
test "display_name is the name, or the email when there is none" do
  user = users(:one)
  user.name = nil
  assert_equal user.email_address, user.display_name
  user.name = "   "
  assert_equal user.email_address, user.display_name
  user.name = " Ada Lovelace "
  assert_equal "Ada Lovelace", user.display_name
end

test "name is optional and capped at 120 characters" do
  user = users(:one)
  user.name = "a" * 121
  assert_not user.valid?
  user.name = ""
  assert user.valid?
  assert_nil user.name, "a blank name is stored as nil"
end
```

(Use whichever fixture name exists in `test/fixtures/users.yml`.) Run: FAIL.

- [ ] **Step 2: Migration and model.**

```ruby
class AddNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
  end
end
```

In `User`:

```ruby
  # Optional (design pass spec §5.1): shown wherever a user is named, with
  # the email as the fallback -- `display_name` is the one reader, so no
  # screen decides the fallback for itself.
  normalizes :name, with: ->(name) { name.to_s.strip.presence }
  validates :name, length: { maximum: 120 }

  def display_name = name.presence || email_address
```

Run `bin/rails db:migrate` and the model test: PASS.

- [ ] **Step 3: Failing component test:**

```ruby
require "test_helper"

class Admin::UserNameComponentTest < ViewComponent::TestCase
  test "a user reads as their display name" do
    user = users(:one)
    user.name = "Ada Lovelace"
    render_inline(Admin::UserNameComponent.new(user: user))
    assert_text "Ada Lovelace"
  end

  test "a user id with no surviving user reads as a deleted user" do
    render_inline(Admin::UserNameComponent.new(user: nil, user_id: 999_999))
    assert_text "a deleted user"
  end

  test "no user at all reads as System" do
    render_inline(Admin::UserNameComponent.new(user: nil))
    assert_text "System"
  end
end
```

- [ ] **Step 4: Component.**

```ruby
module Admin
  # The one place a user is named in CS Studio (design pass spec §5.1).
  # Three cases, the same three the dashboard and audit log already told
  # apart: a surviving user (name, else email), a `user_id` whose user is
  # gone (`audit_events` has no FK on it), and no user at all (a trusted nil
  # actor).
  class UserNameComponent < AdminComponent
    def initialize(user:, user_id: nil)
      @user = user
      @user_id = user_id
    end

    def call = content_tag(:span, label, class: "admin-user-name")

    def label
      return @user.display_name if @user
      @user_id ? "a deleted user" : "System"
    end
  end
end
```

- [ ] **Step 5: Switch every reader.** In each file below replace the hand-built `email_address`/"deleted user"/"System" text with `Admin::UserNameComponent.new(user:, user_id:).label` (in Ruby) or `render Admin::UserNameComponent.new(...)` (in ERB); keep the email visible as a second, `text-meta` line only on the users list and group member list, where it identifies the account:
  - `Admin::DashboardScreen::RowComponent#changed_by`
  - `Admin::TrashScreen::RowComponent` ("moved by")
  - `Admin::AuditEventsHelper#audit_actor_label`
  - `admin/audit_events/index.html.erb` (the user filter's option labels)
  - `admin/api_tokens/index.html.erb` ("acts as")
  - `admin/groups/edit.html.erb`, `admin/groups/_form.html.erb` (member labels)
  - `admin/users/index.html.erb` (name line + email line)

  Existing tests pin "by <email>"; they still pass for users without a name. Add one assertion per reader that a named user reads by name (extend `test/components/admin/dashboard_screen/row_component_test.rb` and `test/components/admin/trash_screen/row_component_test.rb` with a `user.update!(name: "Ada Lovelace")` case asserting `"Ada Lovelace"` is shown and the email is not).

- [ ] **Step 6: The user form.** Add a "Name" text input (label "Name", help "Optional. Shown instead of the email.") above Email in `admin/users/new.html.erb` and `edit.html.erb`; permit `:name` in the controller's params and pass it through `Users::Save` (add `name` to the attributes it assigns and to `user_field_changes`). Add to `test/services/users/save_test.rb`:

```ruby
test "saves a name and records it in the event's field changes" do
  actor = users(:one)
  result = Users::Save.call(users(:two), attributes: { name: "Grace Hopper" }, actor: actor)
  assert result.ok?
  assert_equal "Grace Hopper", users(:two).reload.name
  assert_equal [ nil, "Grace Hopper" ], Audit::Event.order(:id).last.field_changes["name"]
end
```

(Match the call shape `Users::Save` already has; read its signature first and adapt the test's arguments, not the service's.)

- [ ] **Step 7: Own profile.** Failing test `test/services/users/update_profile_test.rb`:

```ruby
require "test_helper"

class Users::UpdateProfileTest < ActiveSupport::TestCase
  test "a user changes their own name, audited as user.updated" do
    user = users(:two)
    Current.set(user: user, channel: :admin) do
      result = Users::UpdateProfile.call(user, name: "Grace Hopper")
      assert result.ok?
    end
    assert_equal "Grace Hopper", user.reload.name
    assert_equal "user.updated", Audit::Event.order(:id).last.action
  end

  test "changing someone else's name is refused and logged as a denial" do
    actor, other = users(:two), users(:one)
    Current.set(user: actor, channel: :admin) do
      assert_not Users::UpdateProfile.call(other, name: "Mallory").ok?
    end
    assert_nil other.reload.name
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end

  test "a user with a short legacy password can still change their name" do
    user = users(:two) # fixture digest is for the 8-character "password"
    Current.set(user: user, channel: :admin) do
      assert Users::UpdateProfile.call(user, name: "Still Fine").ok?
    end
  end
end
```

(Set `Current` the way the neighbouring `Users::UpdatePassword` test does if it differs.)

Service:

```ruby
module Users
  # A signed-in user's own profile -- today only the name (design pass spec
  # §5.1). Not `Users::Save`: that one needs `users.manage` and is bounded by
  # what the actor could grant; this is "your own account", open to every
  # user the way `Users::UpdatePassword`'s own-password path is. Anyone
  # else's profile goes through `Users::Save`, so here it is simply refused.
  class UpdateProfile < ApplicationService
    include OwnerProtection

    def initialize(user, name:, actor: Current.actor)
      @user = user
      @name = name
      @actor = actor
    end

    def call
      unless actor.is_a?(User) && actor == @user
        authorize!("users.manage", @user)
        return denied("users.manage", @user)
      end
      @user.name = @name
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      saved ? success(@user) : failure(@user)
    end
  end
end
```

(If `user_field_changes` must be read before `save`, capture it first, as `Users::UpdatePassword` does.) Run `bin/rails test test/services/service_contract_test.rb` too: PASS.

- [ ] **Step 8: Account screen.** Add the route `patch "account/profile", to: "accounts#update_profile", as: :account_profile`, the action:

```ruby
    def update_profile
      result = Users::UpdateProfile.call(Current.user, name: params[:name])
      if result.ok?
        redirect_to admin_account_password_path(**admin_url_options), status: :see_other, notice: "Name saved."
      else
        @profile_errors = result.errors
        render :edit, status: :unprocessable_entity
      end
    end
```

and a "Your name" form above the password form in `admin/accounts/edit.html.erb` (one text input, "Save name" primary button). Add an integration test to `test/controllers/admin/accounts_controller_test.rb`: signed in, `patch admin_account_profile_path, params: { name: "Ada" }` redirects and `Current`'s user has the name; signed out it redirects to sign-in.

- [ ] **Step 9: Run** `bin/rails test test/models/user_test.rb test/services/users test/components/admin test/controllers/admin/accounts_controller_test.rb test/services/service_contract_test.rb` — PASS. `bin/rubocop` clean.

- [ ] **Step 10: Commit.** `git commit -m "feat: optional user name, shown wherever a user is named"`

---

### Task 3: Content-type `colour_index` and the type dot

**Files:**
- Modify: `app/models/content_model/content_type_definition.rb`, `app/models/content_model/registry.rb` (only if the next-free index needs the registry), `test/models/content_model/content_type_definition_test.rb` (or the nearest existing registry test)
- Create: `app/components/admin/content_type_dot_component.rb`, test, preview
- Modify: `app/views/admin/posts/index.html.erb`, `app/components/admin/dashboard_screen/row_component.html.erb` (wherever a content type is shown with a coloured dot or plain label today)

**Interfaces:**
- Produces: `ContentModel::ContentTypeDefinition#colour_index → Integer` (1-based), settable in the registration block via `type.colour_index = 4`. `Admin::ContentTypeDotComponent.new(content_type:)` where `content_type` is a type name String; renders dot/ring + label; an unregistered name renders a `meta` ring and the raw name.

- [ ] **Step 1: Failing tests.**

```ruby
test "built-in content types get colour indexes in registration order" do
  assert_equal [ 1, 2, 3 ], %w[blog resume_entry now_update].map { |name| ContentTypes.fetch(name).colour_index }
end

test "a type may state its own colour index, and the next one skips it" do
  ContentTypes.register("acme/case_study") { |type| type.colour_index = 5 }
  ContentTypes.register("acme/event")
  assert_equal 5, ContentTypes.fetch("acme/case_study").colour_index
  assert_equal 4, ContentTypes.fetch("acme/event").colour_index
ensure
  Rails.application.reloader.prepare!
end

test "a colour index must be a positive integer" do
  assert_raises(ArgumentError) { ContentTypes.register("acme/bad") { |type| type.colour_index = 0 } }
ensure
  Rails.application.reloader.prepare!
end
```

(Use the registry constant and reset idiom the existing content-type tests use — read `test/models/content_types_test.rb` or equivalent first; if they reset with a helper, use that instead of `reloader.prepare!`.)

- [ ] **Step 2: Implement.** In the definition: `attr_accessor :colour_index`; in `finalize!`, validate a stated value (`Integer`, `>= 1`, else `ArgumentError "colour_index must be a positive integer"`). Assign the default in `Registry#register` after the block runs and before `finalize!`, only when the definition responds to `colour_index` and has none: the smallest positive integer not already used by a registered definition. Comment why it lives in the registry (the next free index is a property of the set, not of one definition).

- [ ] **Step 3: Component test.**

```ruby
require "test_helper"

class Admin::ContentTypeDotComponentTest < ViewComponent::TestCase
  test "types 1-6 get a filled dot in their own colour, with the type name" do
    render_inline(Admin::ContentTypeDotComponent.new(content_type: "blog"))
    assert_selector ".admin-type-dot span[aria-hidden=true].bg-cat-1"
    assert_text ContentTypes.fetch("blog").label
  end

  test "an index above six wraps to a ring in the same six hues" do
    component = Admin::ContentTypeDotComponent.new(content_type: "blog")
    assert_equal "bg-cat-1", component.mark_class(1)
    assert_equal "border border-cat-1", component.mark_class(7)
    assert_equal "bg-cat-1", component.mark_class(13)
    assert_equal "border border-cat-6", component.mark_class(12)
  end

  test "an unregistered type still renders, as a neutral ring and its raw name" do
    render_inline(Admin::ContentTypeDotComponent.new(content_type: "gone/type"))
    assert_selector ".admin-type-dot span.border-meta"
    assert_text "gone/type"
  end
end
```

- [ ] **Step 4: Component.**

```ruby
module Admin
  # A content type's colour mark plus its name (design pass spec §4, handoff
  # §9 B13). Six hues: indexes 1-6 are filled dots, 7-12 the same hues as
  # rings, 13+ cycle again -- and the name always accompanies the mark, so
  # colour is never the only cue. The class names are spelled out in full
  # (not interpolated) so Tailwind's scanner sees them.
  class ContentTypeDotComponent < AdminComponent
    FILLED = %w[bg-cat-1 bg-cat-2 bg-cat-3 bg-cat-4 bg-cat-5 bg-cat-6].freeze
    RINGS = [ "border border-cat-1", "border border-cat-2", "border border-cat-3",
              "border border-cat-4", "border border-cat-5", "border border-cat-6" ].freeze

    def initialize(content_type:)
      @name = content_type.to_s
      @definition = ::ContentTypes.find(@name)
    end

    def call
      content_tag(:span, class: "admin-type-dot inline-flex items-center gap-1.5 text-sm text-dim") do
        safe_join([ content_tag(:span, "", class: "h-[7px] w-[7px] shrink-0 rounded-full #{mark}", aria: { hidden: true }), label ])
      end
    end

    def mark_class(index)
      slot = (index - 1) % 12
      slot < 6 ? FILLED[slot] : RINGS[slot - 6]
    end

    private

    def mark = @definition ? mark_class(@definition.colour_index) : "border border-meta"
    def label = @definition ? @definition.label : @name
  end
end
```

(If the definition's human name isn't `#label`, use the reader the posts list uses today.)

- [ ] **Step 5: Use it** in the posts list's Type column and the dashboard row wherever the type is printed; add the preview (one example per index 1–8); run `bin/rails tailwindcss:build`, the three test files and `previews_test.rb`: PASS.

- [ ] **Step 6: Commit.** `git commit -m "feat: content types carry a colour index; one type dot component"`

---

### Task 4: Password rule and the password field

**Files:**
- Modify: `app/models/user.rb`, `db/seeds.rb`, tests that set a password shorter than 12 characters (find with `grep -rn 'password: "' test app/views/setup db`)
- Create: `app/components/admin/password_field_component.rb`, `.html.erb`; `app/javascript/controllers/password_field_controller.js` (outside `admin/`: sign-in and setup load `application` only); tests; preview
- Modify: `app/views/admin/accounts/edit.html.erb`, `app/views/admin/users/new.html.erb`, `app/views/admin/users/edit.html.erb`, `app/views/admin/passwords/edit.html.erb`, `app/views/setup/admin.html.erb`

**Interfaces:**
- Produces: `User::MINIMUM_PASSWORD_LENGTH = 12`. `Admin::PasswordFieldComponent.new(name:, id:, label:, meter: false, autocomplete: "new-password", errors: [], required: true)`. Stimulus `password-field` with targets `input`, `toggle`, `bar` (×4), `hint`, and outlet-free `submit` lookup via `this.element.closest("form").querySelector("[data-password-submit]")`.

- [ ] **Step 1: Failing model tests.**

```ruby
test "a new password needs at least 12 characters" do
  user = users(:one)
  user.password = user.password_confirmation = "elevenchars"
  assert_not user.valid?
  assert_equal [ "Use at least 12 characters." ], user.errors[:password]
  user.password = user.password_confirmation = "twelve chars"
  assert user.valid?
end

test "twelve multibyte characters are enough: the rule counts characters, not bytes" do
  user = users(:one)
  user.password = user.password_confirmation = "üüüüüüüüüüüü"
  assert user.valid?
end

test "a user whose stored password is shorter still authenticates and saves other changes" do
  user = users(:one) # fixture digest is for "password"
  assert user.authenticate("password")
  assert user.update(name: "Unchanged password")
end
```

- [ ] **Step 2: Implement.** In `User`:

```ruby
  MINIMUM_PASSWORD_LENGTH = 12

  # Design pass spec §5.5. `allow_nil` is what keeps existing shorter
  # passwords working: `password` is only non-nil while one is being set,
  # so the rule applies to setup, new user, change and reset -- never to a
  # save that leaves the password alone.
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH, message: "Use at least 12 characters." }, allow_nil: true
```

The message must read exactly "Use at least 12 characters." wherever it's shown: check how each form prints `errors[:password]` — if a form prints `full_messages` ("Password Use at least…"), switch that field to print the bare message. Change seeds to `"password12345"` (and the two `puts` lines). Update every test that sets a short password (`grep` above); `sign_in_via_form`'s `"password"` stays, since it authenticates against a fixture digest.

- [ ] **Step 3: Run** `bin/rails test test/models/user_test.rb`, then `bin/rails test` to find tests pinned to short passwords; fix them by lengthening the test's password, never by loosening the rule.

- [ ] **Step 4: Component test.**

```ruby
require "test_helper"

class Admin::PasswordFieldComponentTest < ViewComponent::TestCase
  test "renders a labelled password input with a Show button" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_selector "label[for=password]", text: "New password"
    assert_selector "input#password[type=password][name=password][autocomplete='new-password'][data-password-field-target=input]"
    assert_selector "button[type=button][aria-controls=password][aria-pressed=false]", text: "Show"
    assert_no_selector "[data-password-field-target=bar]"
  end

  test "with a meter it renders four bars and a polite hint" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true))
    assert_selector "[data-password-field-target=bar]", count: 4
    assert_selector "[data-password-field-target=hint][aria-live=polite]", text: "Use at least 12 characters."
  end

  test "errors are printed under the field and tied to it" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", errors: [ "Use at least 12 characters." ]))
    assert_selector "input[aria-invalid=true][aria-describedby~='password-errors']"
    assert_selector "#password-errors", text: "Use at least 12 characters."
  end
end
```

- [ ] **Step 5: Component and controller.** Markup per handoff §9 A10 and `Studio Change Password.dc.html`: the input (`setup_input_class`, `pr-16`) inside a `relative` wrapper with the Show/Hide text button absolutely placed at the right (`font-cs-mono text-label uppercase tracking-mono text-meta hover:text-ink`); below it, when `meter:`, four `h-1 flex-1 rounded-cs bg-line-strong` bars in a `flex gap-1` row and the hint line. Controller:

```js
import { Controller } from "@hotwired/stimulus"

// Show/Hide and the four-bar strength meter (design pass spec §4, handoff
// §9 A10). The meter is a guide, not the rule -- the server's 12-character
// minimum (User::MINIMUM_PASSWORD_LENGTH) is the rule -- so the only thing
// it ever blocks is submitting something the server would refuse anyway.
const LEVELS = [
  { bars: 1, colour: "bg-danger", hint: "Use at least 12 characters." },
  { bars: 2, colour: "bg-warn", hint: "Fair" },
  { bars: 3, colour: "bg-ok", hint: "Good" },
  { bars: 4, colour: "bg-ok", hint: "Strong" },
]
const COLOURS = ["bg-danger", "bg-warn", "bg-ok"]

export default class extends Controller {
  static targets = ["input", "toggle", "bar", "hint"]
  static values = { minimum: { type: Number, default: 12 } }

  connect() { this.measure() }

  toggle() {
    const showing = this.inputTarget.type === "text"
    this.inputTarget.type = showing ? "password" : "text"
    this.toggleTarget.textContent = showing ? "Show" : "Hide"
    this.toggleTarget.setAttribute("aria-pressed", String(!showing))
  }

  measure() {
    if (!this.hasBarTarget) return
    const value = this.inputTarget.value
    const length = Array.from(value).length
    const level = LEVELS[this.level(value, length)]
    this.barTargets.forEach((bar, index) => {
      bar.classList.remove(...COLOURS)
      bar.classList.toggle("bg-line-strong", value === "" || index >= level.bars)
      if (value !== "" && index < level.bars) bar.classList.add(level.colour)
    })
    this.hintTarget.textContent = level.hint
    const submit = this.element.closest("form")?.querySelector("[data-password-submit]")
    if (submit) submit.disabled = length < this.minimumValue
  }

  // 0 too short; then one step per extra character class or 16+ length.
  level(value, length) {
    if (length < this.minimumValue) return 0
    const classes = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter((re) => re.test(value)).length
    const score = (classes >= 3 ? 1 : 0) + (length >= 16 ? 1 : 0)
    return 1 + score
  }
}
```

The input carries `data-action="input->password-field#measure"`, the button `data-action="password-field#toggle"`. Add `app/javascript/controllers` to nothing: `@source "../../javascript/controllers/admin"` in `application.css` does not cover this file, so add `@source "../../javascript/controllers/password_field_controller.js";` there (the bar colours are only named in JS).

- [ ] **Step 6: Use it** on the five forms (meter on: setup admin, new user, change password "New password", reset; meter off: "Current password" and every confirmation field). Mark each form's submit with `data-password-submit`.

- [ ] **Step 7: System test** `test/system/password_field_test.rb`:

```ruby
require "application_system_test_case"

class PasswordFieldTest < ApplicationSystemTestCase
  test "the change-password form shows the meter, toggles visibility and blocks a short password" do
    sign_in_via_form users(:one)
    visit admin_account_password_path
    fill_in "New password", with: "short"
    assert_text "Use at least 12 characters."
    assert_selector "[data-password-submit][disabled]"
    fill_in "New password", with: "a much Longer passw0rd"
    assert_text "Strong"
    assert_no_selector "[data-password-submit][disabled]"
    within(find_field("New password").ancestor(".admin-password-field")) { press "Show" }
    assert_equal "text", find_field("New password")[:type]
  end
end
```

(Use the fixture name of an owner or any user who can sign in.)

- [ ] **Step 8: Run** `bin/rails tailwindcss:build`, component test, system test, full `bin/rails test`: PASS.

- [ ] **Step 9: Commit.** `git commit -m "feat: 12-character password minimum and a password field with Show and meter"`

---

### Task 5: Status chip and translation chip

**Files:**
- Create: `app/components/admin/status_chip_component.rb`, `.html.erb`; `app/components/admin/translation_chip_component.rb`; tests; previews
- Delete: `app/components/admin/status_badge_component.*`, `app/components/admin/translation_screen/state_badge_component.rb`, their tests
- Modify (call sites): `app/views/admin/posts/index.html.erb`, `app/components/admin/record_header_component.{rb,html.erb}`, `app/components/admin/tree_node_component.html.erb`, `app/components/admin/post_form_component.html.erb`, `app/components/admin/dashboard_screen/row_component.html.erb`, `app/components/admin/translation_screen/list_component.html.erb`

**Interfaces:**
- Produces: `Admin::StatusChipComponent.new(status:, at: nil, hide_live: false)` — `status` ∈ `draft|scheduled|live`; `render?` is false when `hide_live && status == "live"`. `Admin::TranslationChipComponent.new(state:, locale:)` — `state` ∈ `:complete|:missing|:outdated`; emits `data-locale` and `data-translation-state` exactly as the old badge did.

- [ ] **Step 1: Failing tests.**

```ruby
require "test_helper"

class Admin::StatusChipComponentTest < ViewComponent::TestCase
  test "each status is an outlined chip with a dot and its name" do
    { "live" => "bg-ok", "draft" => "bg-meta", "scheduled" => "bg-warn" }.each do |status, dot|
      render_inline(Admin::StatusChipComponent.new(status: status))
      assert_selector ".admin-status-chip.border-line-strong[data-status='#{status}']", text: status.humanize
      assert_selector ".admin-status-chip span.#{dot}[aria-hidden=true]"
    end
  end

  test "lists and the tree hide Live" do
    render_inline(Admin::StatusChipComponent.new(status: "live", hide_live: true))
    assert_no_selector ".admin-status-chip"
    render_inline(Admin::StatusChipComponent.new(status: "draft", hide_live: true))
    assert_selector ".admin-status-chip", text: "Draft"
  end

  test "a scheduled chip's tooltip is the scheduled time" do
    render_inline(Admin::StatusChipComponent.new(status: "scheduled", at: Time.zone.local(2026, 10, 5, 9, 30)))
    assert_selector ".admin-status-chip[title='Oct 5, 2026 09:30']"
  end

  test "an unknown status is a programming error" do
    assert_raises(ArgumentError) { Admin::StatusChipComponent.new(status: "archived") }
  end
end
```

```ruby
require "test_helper"

class Admin::TranslationChipComponentTest < ViewComponent::TestCase
  test "done is a solid chip with no glyph" do
    render_inline(Admin::TranslationChipComponent.new(state: :complete, locale: "de"))
    assert_selector ".admin-translation-chip.border-line-strong.text-ink[data-translation-state=complete]", exact_text: "de"
    assert_selector "[role=img][aria-label='Deutsch: translated'][title='Translated']"
  end

  test "missing is dashed with a hollow ring glyph, never red" do
    render_inline(Admin::TranslationChipComponent.new(state: :missing, locale: "de"))
    assert_selector ".admin-translation-chip.border-dashed.text-meta", text: "de ○"
    assert_selector "[aria-label='Deutsch: not translated'][title='Not translated']"
    assert_no_selector "[class*=danger]"
  end

  test "outdated is warn with a refresh glyph and names the source language" do
    render_inline(Admin::TranslationChipComponent.new(state: :outdated, locale: "de"))
    assert_selector ".admin-translation-chip.border-warn.text-warn-ink", text: "de ↻"
    assert_selector "[title='English changed since translation']"
  end
end
```

(The outdated tooltip names `Locales.name(Translations.primary_locale, native: true)`; the test assumes English is the default in the test environment.)

- [ ] **Step 2: Build both.** Status chip template:

```erb
<%= tag.span class: "admin-status-chip inline-flex items-center gap-1.5 rounded-cs border border-line-strong px-2 py-0.5 text-xs text-ink",
      title: title, data: { status: status } do %>
  <%= tag.span "", class: "h-1.5 w-1.5 rounded-full #{dot_class}", aria: { hidden: true } %>
  <%= label %>
<% end %>
```

with the Ruby side carried over from `StatusBadgeComponent` plus `hide_live` and `def render? = !(hide_live && status == "live")`. Translation chip:

```ruby
module Admin
  # One language's translation state (design pass spec §4, handoff §2.3 and
  # §9 B14). Three cues besides colour: the border (solid, dashed, warn), a
  # glyph (none, ○, ↻) and an aria-label -- and no red: a missing
  # translation isn't a failure.
  class TranslationChipComponent < AdminComponent
    STYLES = {
      complete: { classes: "border-line-strong text-ink", glyph: nil },
      missing: { classes: "border-dashed border-line-strong text-meta", glyph: "○" },
      outdated: { classes: "border-warn text-warn-ink", glyph: "↻" }
    }.freeze

    def initialize(state:, locale:)
      @state = state.to_sym
      raise ArgumentError, "unknown translation state #{state.inspect}" unless STYLES.key?(@state)
      @locale = locale.to_s
    end

    def call
      style = STYLES.fetch(@state)
      tag.span(safe_join([ @locale, style[:glyph] ].compact, " "),
        class: "admin-translation-chip inline-flex items-center gap-0.5 rounded-cs border px-1 font-cs-mono text-[10px] uppercase #{style[:classes]}",
        role: "img", title: tooltip, aria: { label: "#{::Locales.name(@locale, native: true)}: #{tooltip.downcase_first}" },
        data: { locale: @locale, translation_state: @state })
    end

    def tooltip
      case @state
      when :complete then "Translated"
      when :missing then "Not translated"
      when :outdated then "#{::Locales.name(::Translations.primary_locale, native: true)} changed since translation"
      end
    end
  end
end
```

Adjust the `aria-label` test expectation if `downcase_first` turns "English changed…" into "english changed…": for `:outdated`, build the label as `"#{name}: outdated"` instead, and assert that.

- [ ] **Step 3: Switch call sites.** Posts list, tree node and dashboard rows pass `hide_live: true`; `RecordHeaderComponent` and `PostFormComponent` (editors) do not. Delete the old components and tests. Update existing tests that select `.admin-…` badge markup or the `✓`/`!` glyphs (`grep -rn "StatusBadge\|StateBadge\|translation_state\|data-status" test`): the `data-status` and `data-translation-state` attributes are unchanged, so most selectors keep working; in the tree, `span[data-status]` now exists only for non-Live pages — update `test/components/admin/tree_component_test.rb` and `test/system/tree_test.rb` assertions that expect a Live chip.

- [ ] **Step 4: Previews** for every state of both; run `bin/rails tailwindcss:build`, `bin/rails test test/components test/integration test/controllers`: PASS.

- [ ] **Step 5: Commit.** `git commit -m "ref: one status chip and one translation chip, no red for translation states"`

---

### Task 6: Language tabs

**Files:**
- Create: `app/components/admin/language_tabs_component.rb`, `.html.erb`; test; preview
- Delete: `app/components/admin/language_switcher_component.*` and its test
- Modify: `app/components/admin/record_header_component.{rb,html.erb}`, `post_form_component.{rb,html.erb}`, `settings_form_component.html.erb`, `media_library/detail_component.html.erb`, `app/views/layouts/admin.html.erb` (if it references the component), `app/components/admin/translation_screen/outdated_note_component.*` and any Turbo Stream that targets `LanguageSwitcherComponent.outdated_marker_id`

**Interfaces:**
- Consumes: `Admin::MenuComponent` is **not** available yet (Task 8); the overflow uses a native `<details>` here and Task 8 restyles it.
- Produces: `Admin::LanguageTabsComponent.new(current:, missing: [], outdated: [], url: ->(code) { "#" }, visible: 4)` and `Admin::LanguageTabsComponent.outdated_marker_id(code)` (same id string as before: `"language-switcher-outdated-#{code}"`, so streams keep working).

- [ ] **Step 1: Failing test.**

```ruby
require "test_helper"

class Admin::LanguageTabsComponentTest < ViewComponent::TestCase
  setup { @url = ->(code) { "/x?locale=#{code}" } }

  test "underline tabs in each language's own name, the current one marked" do
    render_inline(Admin::LanguageTabsComponent.new(current: "de", url: @url))
    assert_selector "nav[aria-label='Languages']"
    assert_selector "[aria-current=true]", text: "Deutsch"
    assert_selector "a[href='/x?locale=en'][data-turbo-frame=_top]", text: "English"
  end

  test "missing is a hollow ring, outdated a solid warn dot, each with screen-reader text and no red" do
    render_inline(Admin::LanguageTabsComponent.new(current: "en", missing: %w[de], outdated: %w[es], url: @url))
    assert_selector "span.border-meta[data-language-state=missing]"
    assert_selector "span.bg-warn[data-language-state=outdated]##{Admin::LanguageTabsComponent.outdated_marker_id('es')}"
    assert_selector ".sr-only", text: "Deutsch: not translated"
    assert_selector ".sr-only", text: "Español: original changed"
    assert_no_selector "[class*=danger]"
  end

  test "more than the visible number collapse into +N, keeping the current language visible" do
    Locales.stub(:enabled, %w[en de es fr it pt]) do
      Locales.stub(:name, ->(code, **) { code.to_s.upcase }) do
        render_inline(Admin::LanguageTabsComponent.new(current: "pt", url: @url, visible: 4))
        assert_selector "nav > ul > li", count: 5 # four tabs + the overflow
        assert_selector "[aria-current=true]", text: "PT"
        assert_selector "details summary", text: "+2"
        assert_selector "details a", count: 2
      end
    end
  end
end
```

- [ ] **Step 2: Build.** Ruby side: carry over `LanguageSwitcherComponent`'s readers, add:

```ruby
    # The first `visible` languages, except that the current one always has
    # a tab: when it would fall into the overflow it takes the last visible
    # slot instead (handoff §10 A13).
    def tabs
      return locales if locales.size <= visible
      shown = locales.first(visible)
      shown[-1] = current unless shown.include?(current) || !locales.include?(current)
      shown
    end

    def overflow = locales - tabs
```

Template: `<nav aria-label="Languages" class="admin-language-tabs border-b border-line"><ul class="flex items-end gap-5">…`; each tab `<li>` holds either a `span[aria-current=true]` (`border-b-2 border-ink pb-2 text-ink font-medium`) or the link (`border-b-2 border-transparent pb-2 text-meta hover:text-ink`, `data-turbo-frame="_top"` — keep the existing comment explaining why); then the state mark: missing → `tag.span "", class: "h-1.5 w-1.5 rounded-full border border-meta", data: { language_state: "missing" }`; outdated → `tag.span "", id: outdated_marker_id(code), class: "h-1.5 w-1.5 rounded-full bg-warn", data: { language_state: "outdated" }`; each followed by its `sr-only` sentence ("Deutsch: not translated" / "Deutsch: original changed"). Overflow: `<li class="relative"><details class="admin-language-tabs__more"><summary class="cursor-pointer list-none pb-2 text-meta hover:text-ink">+N ▾</summary><ul class="absolute right-0 z-20 mt-1 min-w-40 rounded-cs border border-line bg-surface p-1 shadow-menu">…links with the same marks…</ul></details></li>`.

- [ ] **Step 3: Switch the four call sites**, delete the old component and test, and update the "Mark as up to date" stream that removes the outdated marker to use `Admin::LanguageTabsComponent.outdated_marker_id`. Update tests selecting `.admin-language-switcher` (`grep -rn "language-switcher\|LanguageSwitcher" test app`) to `.admin-language-tabs`; the marker id is unchanged.

- [ ] **Step 4: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system` — PASS.

- [ ] **Step 5: Commit.** `git commit -m "ref: language tabs replace the language switcher"`

---

### Task 7: Dialogs

**Files:**
- Create: `app/components/admin/dialog_component.rb`, `.html.erb`; `app/javascript/controllers/admin/dialog_controller.js`; test; preview
- Modify: `app/components/admin/confirm_dialog_component.{rb,html.erb}` and its test
- Modify (remove every inline `onclick="…showModal()"`): `app/views/admin/settings/_ai_key_field.html.erb`, `api_tokens/index.html.erb`, `groups/edit.html.erb`, `tags/index.html.erb`, `users/index.html.erb`, `app/components/admin/block_card_component.html.erb`, `record_header_component.html.erb`, `post_form_component.html.erb`, `media_library/detail_component.html.erb`, `trash_screen/list_component.html.erb`, `trash_screen/row_component.html.erb`

**Interfaces:**
- Produces:
  - `Admin::DialogComponent.new(id:, title:, width: :confirm, destructive: false)` with slots `body` (default content) and `footer`; widths `confirm: 420, form_narrow: 460, form: 560, picker: 880` px.
  - `Admin::ConfirmDialogComponent.new(id:, title:, body: nil, cancel_label: "Cancel", destructive: false)` with slots `confirm_action`, `details` (API unchanged apart from `destructive:`).
  - Opening: `data-action="admin--dialog#open" data-admin--dialog-id-param="<dialog id>"` on any trigger. The layout's `<body>` carries `data-controller="admin--dialog"`, so a trigger anywhere on the page works, including one streamed in later.
  - Helper `dialog_trigger(id) → Hash` in `AdminComponent` and `Admin::BaseHelper` (create if absent): `{ action: "admin--dialog#open", "admin--dialog-id-param": id }`, for `data:`.

- [ ] **Step 1: Failing component tests.**

```ruby
require "test_helper"

class Admin::DialogComponentTest < ViewComponent::TestCase
  test "a titled dialog with a close button, labelled by its title" do
    render_inline(Admin::DialogComponent.new(id: "d1", title: "New post", width: :form)) { "Body" }
    assert_selector "dialog#d1.admin-dialog[aria-labelledby='d1-title'][data-dialog-width=form]"
    assert_selector "#d1-title", text: "New post"
    assert_selector "dialog#d1 form[method=dialog] button[aria-label='Close']"
    assert_text "Body"
  end

  test "an unknown width is a programming error" do
    assert_raises(ArgumentError) { Admin::DialogComponent.new(id: "d", title: "t", width: :huge) }
  end
end
```

Add to `confirm_dialog_component_test.rb`:

```ruby
test "a destructive confirm starts focus on Cancel" do
  render_inline(Admin::ConfirmDialogComponent.new(id: "c1", title: "Delete this tag?", destructive: true)) do |dialog|
    dialog.with_confirm_action { "<button>Delete tag</button>".html_safe }
  end
  assert_selector "dialog#c1[data-dialog-width=confirm][data-destructive]"
  assert_selector "dialog#c1 button[autofocus]", text: "Cancel"
end

test "a non-destructive confirm leaves focus to the first field or button" do
  render_inline(Admin::ConfirmDialogComponent.new(id: "c2", title: "Turn off Deutsch?")) { |d| d.with_confirm_action { "x" } }
  assert_no_selector "dialog#c2 button[autofocus]"
end
```

- [ ] **Step 2: Build `DialogComponent`.** Template:

```erb
<dialog id="<%= id %>" aria-labelledby="<%= id %>-title" data-dialog-width="<%= width %>" <%= "data-destructive" if destructive %>
        class="admin-dialog rounded-cs border border-line-strong bg-surface p-0 text-ink shadow-menu">
  <header class="flex items-center justify-between gap-4 border-b border-line px-5 py-3">
    <h2 id="<%= id %>-title" class="text-base font-semibold"><%= title %></h2>
    <form method="dialog"><button aria-label="Close" class="cursor-pointer rounded-cs px-1 text-meta hover:bg-sunken hover:text-ink">×</button></form>
  </header>
  <div class="admin-dialog__body overflow-y-auto px-5 py-4"><%= content %></div>
  <% if footer? %>
    <footer class="flex justify-end gap-2 border-t border-line px-5 py-3"><%= footer %></footer>
  <% end %>
</dialog>
```

CSS in `content-spiel.tailwind.css` (a native `<dialog>` needs real CSS for its backdrop and max sizes):

```css
.admin-dialog { max-height: 85vh; width: calc(100vw - 32px); margin: auto; }
.admin-dialog[open] { display: flex; flex-direction: column; }
.admin-dialog::backdrop { background: color-mix(in oklab, var(--cs-ink) 38%, transparent); }
.admin-dialog[data-dialog-width="confirm"] { max-width: 420px; }
.admin-dialog[data-dialog-width="form_narrow"] { max-width: 460px; }
.admin-dialog[data-dialog-width="form"] { max-width: 560px; }
.admin-dialog[data-dialog-width="picker"] { max-width: 880px; }
```

`ConfirmDialogComponent` renders a `DialogComponent` (width `:confirm`), body = `body` paragraph + `details`, footer = the Cancel `form[method=dialog]` (button gets `autofocus: destructive`) then `confirm_action`. A native modal `<dialog>` already traps focus and closes on Esc; don't re-implement either.

- [ ] **Step 3: Controller.**

```js
import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> by id (Admin::DialogComponent). One instance on <body>
// serves every trigger on the page -- including ones Turbo streams in
// later -- so no view carries an inline `onclick="…showModal()"` (which a
// strict CSP would refuse anyway). Focus: the browser focuses the
// `autofocus` element if there is one (Cancel, on destructive dialogs),
// else the first focusable -- the dialog's × -- so we move it to the first
// form field when there is one.
export default class extends Controller {
  open(event) {
    const dialog = document.getElementById(event.params.id)
    if (!dialog || dialog.open) return
    event.preventDefault()
    dialog.showModal()
    if (dialog.querySelector("[autofocus]")) return
    const field = dialog.querySelector(".admin-dialog__body :is(input:not([type=hidden]), select, textarea)")
    if (field) field.focus()
  }

  // A click on the backdrop (the <dialog> element itself, outside its
  // content box) cancels, like Esc and ×.
  backdrop(event) {
    if (event.target instanceof HTMLDialogElement) event.target.close()
  }
}
```

`<body data-controller="admin--dialog" data-action="click->admin--dialog#backdrop">` in `layouts/admin.html.erb`. Add `dialog_trigger`.

- [ ] **Step 4: Replace all inline `showModal()` calls** in the eleven files with `data: dialog_trigger(id)`. Every destructive confirm ("Move to trash", "Delete permanently", "Empty trash", "Delete block", "Delete tag", "Delete user", "Delete group", "Revoke", "Remove key") passes `destructive: true` and its confirm button uses `variant: :danger`; change `ButtonComponent`'s `danger` variant to the solid style (`bg-danger text-white hover:opacity-90` — `text-white` is the one literal allowed by handoff §9 A1; add a comment) and add a `ghost` variant (`text-dim hover:bg-sunken hover:text-ink`) used by every dialog's Cancel. Reversible confirms (unpublish, turn off a language) stay `primary`. `media_picker_controller.js` keeps its own `showModal()` (it's JS, not an inline handler) but its dialog element gets `class="admin-dialog"` and `data-dialog-width="picker"`.

- [ ] **Step 5: Guard test** `test/lib/inline_handlers_test.rb`:

```ruby
require "test_helper"

class InlineHandlersTest < ActiveSupport::TestCase
  test "no view or component uses an inline event handler" do
    offenders = Dir[Rails.root.join("app/{views,components}/**/*.{erb,rb}")].select do |path|
      File.read(path).match?(/\bon(click|change|submit|input)\s*[:=]/)
    end
    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end
end
```

- [ ] **Step 6: System test** `test/system/dialog_test.rb`: sign in, open Tags, press a tag's Delete: assert `dialog[open]`, focus is on Cancel (`page.evaluate_script("document.activeElement.textContent.trim()") == "Cancel"`), press Escape (`find("dialog[open]").send_keys(:escape)`), assert `no_selector "dialog[open]"` and the tag still listed; reopen, confirm, assert it's gone.

- [ ] **Step 7: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 8: Commit.** `git commit -m "ref: one dialog component and controller; no inline handlers"`

---

### Task 8: Toasts, menus and the busy button

**Files:**
- Create: `app/components/admin/toast_component.{rb,html.erb}`, `toast_region_component.{rb,html.erb}`, `menu_component.{rb,html.erb}`; `app/javascript/controllers/admin/{toast,menu,busy}_controller.js`; tests; previews
- Delete: `app/components/admin/flash_component.*` and its test/preview
- Modify: `app/views/layouts/admin.html.erb`; `app/views/admin/{posts,trash,pages,media}/index.html.erb`, `app/components/admin/media_library/detail_component.html.erb` (drop their `FlashComponent` renders); `app/controllers/concerns/admin/autosave_responses.rb` or wherever autosave failures are streamed (add an error toast); `app/components/admin/language_tabs_component.html.erb` (overflow becomes a `MenuComponent`)

**Interfaces:**
- Produces:
  - `Admin::ToastComponent.new(message:, kind: :success, action: nil)` — `kind` ∈ `:success|:undo|:warning|:error`; `action` is `{ label:, url:, method: :post }` (Undo/Retry). `role="status"` for success/undo, `role="alert"` for warning/error. Auto-hide: success 4 s, undo 8 s, warning/error never.
  - `Admin::ToastRegionComponent.new(flash:)` — renders `<div id="toasts">` once in the layout with one toast per `flash[:notice]` (success, or undo when `flash[:undo]` is present) and `flash[:alert]` (error).
  - `flash[:undo] = { label:, url:, method: }` replaces the `action:` hash views used to pass to `FlashComponent`.
  - Turbo Stream helper `toast_stream(message, kind: :success, action: nil)` in `Admin::AutosaveResponses` (or a new `Admin::Toasts` concern included in `BaseController`): `turbo_stream.append("toasts", Admin::ToastComponent.new(...))`.
  - `Admin::MenuComponent.new(label:, align: :right, button_class: nil)` with `renders_many :items` (each item is arbitrary content: a `link_to`, a `button_to`, or `with_divider`) — a `<details>`-free popover: button with `aria-haspopup="menu"`/`aria-expanded`, panel `role="menu"`.
  - Stimulus `admin--busy`: on a form with `data-controller="admin--busy"` and a submit carrying `data-admin--busy-target="button" data-busy-label="Testing…"`, disables the button, keeps its width, swaps the label and shows an 11px spinner until the Turbo submit ends.

- [ ] **Step 1: Failing toast tests.**

```ruby
require "test_helper"

class Admin::ToastComponentTest < ViewComponent::TestCase
  test "success is a status that hides after four seconds" do
    render_inline(Admin::ToastComponent.new(message: "Saved."))
    assert_selector ".admin-toast[role=status][data-controller='admin--toast'][data-admin--toast-timeout-value='4000']", text: "Saved."
  end

  test "undo carries its action and stays eight seconds" do
    render_inline(Admin::ToastComponent.new(message: "Moved to trash.", kind: :undo, action: { label: "Undo", url: "/undo", method: :post }))
    assert_selector ".admin-toast[data-admin--toast-timeout-value='8000'] form[action='/undo'] button", text: "Undo"
  end

  test "an error is an alert that stays until dismissed" do
    render_inline(Admin::ToastComponent.new(message: "Couldn't save.", kind: :error))
    assert_selector ".admin-toast[role=alert][data-admin--toast-timeout-value='0']"
    assert_selector ".admin-toast button[aria-label='Dismiss']"
  end

  test "the message is escaped" do
    render_inline(Admin::ToastComponent.new(message: "<b>x</b>"))
    assert_no_selector ".admin-toast b"
    assert_text "<b>x</b>"
  end
end

class Admin::ToastRegionComponentTest < ViewComponent::TestCase
  test "maps notice to success and alert to error, inside one live region" do
    render_inline(Admin::ToastRegionComponent.new(flash: { notice: "Done.", alert: "Failed." }))
    assert_selector "#toasts .admin-toast[role=status]", text: "Done."
    assert_selector "#toasts .admin-toast[role=alert]", text: "Failed."
  end

  test "a notice with an undo becomes an undo toast" do
    render_inline(Admin::ToastRegionComponent.new(flash: { notice: "Moved.", undo: { "label" => "Undo", "url" => "/u", "method" => "post" } }))
    assert_selector "#toasts .admin-toast form[action='/u']"
  end

  test "the region is rendered even when empty, so streams have a target" do
    render_inline(Admin::ToastRegionComponent.new(flash: {}))
    assert_selector "#toasts"
    assert_no_selector ".admin-toast"
  end
end
```

- [ ] **Step 2: Build.** Toast: `class="admin-toast pointer-events-auto flex items-center gap-3 rounded-cs bg-ink px-4 py-2.5 text-sm text-paper shadow-menu"`; action button `font-semibold underline`; Dismiss `×`. Region: `<div id="toasts" class="pointer-events-none fixed inset-x-0 bottom-6 z-50 flex flex-col items-center gap-2" data-turbo-permanent>` — placed in the layout after `<main>`, outside `#content`. `flash[:undo]` round-trips through the session as string keys: read with `flash[:undo]&.with_indifferent_access`.

`toast_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// One toast (Admin::ToastComponent). Hides itself after `timeout` ms (0 =
// stays until dismissed); hovering or focusing pauses the clock so an Undo
// can't vanish under the pointer. At most three are shown: a fourth pushes
// the oldest out.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    const toasts = Array.from(this.element.parentElement.querySelectorAll(".admin-toast"))
    toasts.slice(0, Math.max(0, toasts.length - 3)).forEach((toast) => toast.remove())
    this.start()
  }

  disconnect() { this.pause() }

  start() {
    if (this.timeoutValue > 0) this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  pause() { clearTimeout(this.timer) }

  dismiss() { this.element.remove() }
}
```

Template wires `data-action="mouseenter->admin--toast#pause mouseleave->admin--toast#start focusin->admin--toast#pause focusout->admin--toast#start"`.

- [ ] **Step 3: Switch the flash call sites.** Remove the five `FlashComponent` renders; the layout's `ToastRegionComponent.new(flash: flash)` covers them. Where a controller set a notice plus an action for the view to pass along (trash move: "Undo"), set `flash[:undo] = { label: "Undo", url: …, method: "post" }` in the controller instead. Update tests asserting `.admin-flash` to `#toasts .admin-toast` (`grep -rn "admin-flash\|FlashComponent" test app`). Form errors are never toasts: leave every inline error as is.

- [ ] **Step 4: Menu.** Test:

```ruby
require "test_helper"

class Admin::MenuComponentTest < ViewComponent::TestCase
  test "a button that owns a hidden menu panel" do
    render_inline(Admin::MenuComponent.new(label: "More")) do |menu|
      menu.with_item { "<a href='/a'>Rename</a>".html_safe }
      menu.with_divider
      menu.with_item { "<a href='/b'>Delete…</a>".html_safe }
    end
    assert_selector "[data-controller='admin--menu'] button[aria-haspopup=menu][aria-expanded=false]", text: "More"
    assert_selector "[role=menu][hidden] a", count: 2, visible: :all
    assert_selector "[role=menu] [role=separator]", visible: :all
  end
end
```

Panel classes: `absolute z-30 mt-1 min-w-44 rounded-cs border border-line bg-surface p-1 shadow-menu`; items get `[&_a]:block [&_a]:rounded-cs [&_a]:px-2 [&_a]:py-1 [&_a:hover]:bg-sunken [&_a:focus-visible]:bg-sunken` (same for `button`). Controller: `toggle()` flips `hidden` and `aria-expanded`; open focuses the first item; ArrowDown/ArrowUp move focus between `a, button` in the panel; Escape closes and refocuses the button; a click outside closes (`click@window->admin--menu#closeOutside`). Then replace the language tabs' `<details>` overflow with a `MenuComponent` (label "+N ▾") and update its test's `details` selectors to `[role=menu]`.

- [ ] **Step 5: Busy button.** `busy_controller.js`: on `turbo:submit-start` set `button.style.width = button.offsetWidth + "px"`, `disabled = true`, store and replace the label with `<span class="admin-spinner"></span>` + `dataset.busyLabel`; on `turbo:submit-end` restore. Spinner CSS:

```css
.admin-spinner { width: 11px; height: 11px; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 999px; display: inline-block; animation: admin-spin 0.7s linear infinite; }
@keyframes admin-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .admin-spinner { animation-duration: 2s; } }
```

Apply it to Settings' "Test connection" form (label "Testing…") — the one long-running button today.

- [ ] **Step 6: System test** `test/system/toast_test.rb`: sign in; move a post to the trash from its editor; assert `#toasts .admin-toast` with text matching "trash" and an "Undo" button; press Undo; assert the post is back in the posts list.

- [ ] **Step 7: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 8: Commit.** `git commit -m "feat: toasts replace inline flash; menu and busy-button patterns"`

---

### Task 9: Pagination, relative dates, instant filters, empty states

**Files:**
- Create: `app/models/pagination.rb`; `app/components/admin/pagination_component.{rb,html.erb}`; `app/components/admin/time_ago_component.rb`; `app/javascript/controllers/admin/auto_submit_controller.js`; tests; previews
- Modify: `app/components/admin/empty_state_component.html.erb`; `app/controllers/admin/{media,trash,translations}_controller.rb` and their index views; `app/views/admin/audit_events/index.html.erb` (keeps "Load older", restyled; filters become instant); `app/views/admin/posts/index.html.erb` and `app/views/admin/media/index.html.erb` (instant filters); list views that print a date

**Interfaces:**
- Produces:
  - `Pagination.new(page:, per_page:, total:)` → `#page` (clamped to ≥ 1; junk → 1), `#offset`, `#total_pages`, `#first_item`, `#last_item`, `#out_of_range?` (page > total_pages and total > 0), `#series` (Array of Integers and `:gap`), `#single_page?`.
  - `Admin::PaginationComponent.new(pagination:, url: ->(page) { … })` — `render?` false on a single page.
  - `Admin::TimeAgoComponent.new(time:)` → `<time datetime="…" title="3 Oct 2026, 14:05">2h ago</time>`.
  - Stimulus `admin--auto-submit`: `data-action="change->admin--auto-submit#submit input->admin--auto-submit#submitLater"` on a GET filter form.

- [ ] **Step 1: Failing `Pagination` test** `test/models/pagination_test.rb`:

```ruby
require "test_helper"

class PaginationTest < ActiveSupport::TestCase
  test "the range and offset of a middle page" do
    pagination = Pagination.new(page: 2, per_page: 50, total: 312)
    assert_equal 50, pagination.offset
    assert_equal [ 51, 100 ], [ pagination.first_item, pagination.last_item ]
    assert_equal 7, pagination.total_pages
  end

  test "the last page ends at the total" do
    assert_equal 312, Pagination.new(page: 7, per_page: 50, total: 312).last_item
  end

  test "junk, zero and negative pages mean the first page" do
    [ nil, "", "abc", "0", "-3", "1.5e9x" ].each do |junk|
      assert_equal 1, Pagination.new(page: junk, per_page: 50, total: 312).page, junk.inspect
    end
  end

  test "a page past the end is out of range, not clamped and not an error" do
    pagination = Pagination.new(page: "9999", per_page: 50, total: 312)
    assert pagination.out_of_range?
    assert_equal 9999, pagination.page
  end

  test "an absurdly large page number doesn't overflow the offset" do
    pagination = Pagination.new(page: "9" * 40, per_page: 50, total: 312)
    assert_equal Pagination::MAX_PAGE, pagination.page
  end

  test "the page series keeps the ends and the neighbours, with gaps" do
    assert_equal [ 1, 2, 3, :gap, 7 ], Pagination.new(page: 1, per_page: 50, total: 312).series
    assert_equal [ 1, :gap, 3, 4, 5, :gap, 7 ], Pagination.new(page: 4, per_page: 50, total: 312).series
    assert_equal [ 1, 2, 3 ], Pagination.new(page: 2, per_page: 50, total: 120).series
  end

  test "one page or none is a single page" do
    assert Pagination.new(page: 1, per_page: 50, total: 50).single_page?
    assert Pagination.new(page: 1, per_page: 50, total: 0).single_page?
  end
end
```

- [ ] **Step 2: Implement.**

```ruby
# Page-number pagination for CS Studio lists (design pass spec §4, handoff
# §9 A6): "51-100 OF 312" plus page links, the page in the URL. A value
# object so the arithmetic -- and what junk in `?page=` means -- lives in
# one place instead of once per controller: anything that isn't a positive
# integer is page 1; a page past the end is reported (`out_of_range?`), not
# silently clamped, so the list can say so and link back.
class Pagination
  MAX_PAGE = 1_000_000

  attr_reader :page, :per_page, :total

  def initialize(page:, per_page:, total:)
    @per_page = per_page
    @total = total
    @page = page.to_s.match?(/\A\d+\z/) ? page.to_s.to_i.clamp(1, MAX_PAGE) : 1
  end

  def offset = (page - 1) * per_page
  def total_pages = (total.to_f / per_page).ceil
  def first_item = total.zero? ? 0 : offset + 1
  def last_item = [ offset + per_page, total ].min
  def single_page? = total_pages <= 1
  def out_of_range? = total.positive? && page > total_pages

  # First, last, the current page and one neighbour each side; `:gap` where
  # pages are skipped. At either end the window widens to three.
  def series
    window = ((page - 1)..(page + 1)).to_a
    window = [ 1, 2, 3 ] if page <= 1
    window = ((total_pages - 2)..total_pages).to_a if page >= total_pages
    pages = ([ 1, total_pages ] + window).select { |n| n.between?(1, total_pages) }.uniq.sort
    pages.each_with_object([]) do |n, out|
      out << :gap if out.last.is_a?(Integer) && n > out.last + 1
      out << n
    end
  end
end
```

- [ ] **Step 3: Pagination component test + build.**

```ruby
require "test_helper"

class Admin::PaginationComponentTest < ViewComponent::TestCase
  setup { @url = ->(page) { "/list?page=#{page}" } }

  test "the range on the left and page links on the right" do
    render_inline(Admin::PaginationComponent.new(pagination: Pagination.new(page: 2, per_page: 50, total: 312), url: @url))
    assert_selector "nav[aria-label='Pagination']"
    assert_text "51–100 OF 312"
    assert_selector "a[rel=prev][href='/list?page=1']", text: "Previous"
    assert_selector "a[rel=next][href='/list?page=3']", text: "Next"
    assert_selector "[aria-current=page]", text: "2"
    assert_selector "a[href='/list?page=7']", text: "7"
  end

  test "hidden on a single page" do
    render_inline(Admin::PaginationComponent.new(pagination: Pagination.new(page: 1, per_page: 50, total: 12), url: @url))
    assert_no_selector "nav"
  end

  test "no Previous on the first page, no Next on the last" do
    render_inline(Admin::PaginationComponent.new(pagination: Pagination.new(page: 1, per_page: 50, total: 120), url: @url))
    assert_no_selector "a[rel=prev]"
    assert_selector "a[rel=next]"
  end
end
```

Markup: `nav.flex.items-center.justify-between.border-t.border-line.px-4.py-2`; range `font-cs-mono text-label uppercase tracking-mono text-meta`; links `rounded-cs px-2 py-0.5 text-sm text-dim hover:bg-sunken`, current `bg-sunken text-ink`, gap `…` with `aria-hidden`. Links keep the list's own filters: callers build `url` from `request.query_parameters.merge(page:)`.

- [ ] **Step 4: Switch Media, Trash and Translations to page numbers.** Each controller: compute `total` with a count over the same scoped relation, build `@pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total:)`, load `offset(@pagination.offset).limit(PER_PAGE)`, drop `@has_next`/`@offset`. Notes per controller:
  - **Media:** `filtered_assets.count`.
  - **Trash:** total = sum of the per-model scoped counts; keep the existing merge-sort window (`window = @pagination.offset + PER_PAGE`).
  - **Translations:** the list is filtered in Ruby (interim until round 2's stored state): `total = needing_work.size` — it already walks the full set to fill a late page; keep the existing comment and add one line that round 2 replaces this with a query.
  - **Audit log:** unchanged cursor ("Load older"), restyled as a secondary button centred in the card footer.

  When `@pagination.out_of_range?`, render the list's empty-state card with title "Nothing on this page" and one action, a link "Back to page 1". Integration tests (add to each of `test/controllers/admin/{media,trash,translations}_controller_test.rb`):

```ruby
test "junk and out-of-range page numbers never error" do
  sign_in_as users(:one)
  %w[0 abc -1].each do |junk|
    get admin_media_path(page: junk)
    assert_response :success
  end
  get admin_media_path(page: 9999)
  assert_response :success
end
```

(use the sign-in helper those test files already use; for a list with enough fixtures add `assert_select "a", text: "Back to page 1"` on the 9999 case, otherwise assert only success.)

- [ ] **Step 5: `TimeAgoComponent`.**

```ruby
require "test_helper"

class Admin::TimeAgoComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "recent times read as short relative phrases with the absolute time as tooltip" do
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      {
        20.seconds.ago => "just now", 5.minutes.ago => "5m ago", 2.hours.ago => "2h ago",
        Time.zone.local(2026, 10, 2, 9, 0) => "yesterday", 3.days.ago => "3d ago",
        Time.zone.local(2026, 9, 1, 9, 0) => "1 Sep", Time.zone.local(2025, 9, 1, 9, 0) => "1 Sep 2025"
      }.each do |time, text|
        render_inline(Admin::TimeAgoComponent.new(time: time))
        assert_selector "time[datetime='#{time.iso8601}']", exact_text: text
      end
      render_inline(Admin::TimeAgoComponent.new(time: 2.hours.ago))
      assert_selector "time[title='3 Oct 2026, 12:00']"
    end
  end

  test "a future time reads as an absolute date, and nil renders nothing" do
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      render_inline(Admin::TimeAgoComponent.new(time: Time.zone.local(2026, 10, 5, 9, 30)))
      assert_selector "time", exact_text: "5 Oct, 09:30"
    end
    render_inline(Admin::TimeAgoComponent.new(time: nil))
    assert_no_selector "time"
  end
end
```

Implement with those exact breakpoints: < 1 min "just now"; < 1 h "Nm ago"; < 24 h and same or previous calendar day rule: same day → "Nh ago"; previous calendar day → "yesterday"; < 7 days "Nd ago"; same year "%-d %b"; else "%-d %b %Y"; future → "%-d %b, %H:%M". All in `Time.zone` (the site zone, set by `use_site_time_zone`). Use it for every date column in the posts list, dashboard rows, trash rows, media grid/detail, users list ("last signed in"), tokens ("created", "last used") and audit index. Rendered time is static per request — fine, since lists reload on navigation.

- [ ] **Step 6: Instant filters.** Controller:

```js
import { Controller } from "@hotwired/stimulus"

// Filters apply as you change them (design pass spec §4, handoff §2.7): no
// Filter button. A select or checkbox submits at once; typing waits 250 ms
// so a search doesn't fire per keystroke. `requestSubmit` (not `submit`)
// so Turbo handles it like any other form.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  submit() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }

  submitLater() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() { clearTimeout(this.timer) }
}
```

On the posts, media and audit filter forms: add the controller, `change->…#submit` on selects, `input->…#submitLater` on text inputs, `data-turbo-frame="content"` and `data-turbo-action="replace"`; remove the Filter button but keep a `<noscript>` submit; show a "Clear" link (to the unfiltered path) only when any filter param is present. A text input must keep focus and caret after the frame reloads: give each filter text input a stable `id` and `data-turbo-permanent`.

- [ ] **Step 7: Empty state.** Restyle `EmptyStateComponent` to sit inside a list's card (no dashed border of its own: `px-6 py-12 text-center`, title `text-base font-semibold text-ink`, description `mt-1 text-sm text-meta`, at most one action). Its API is unchanged. In each list view, render it inside the same card element the rows would be in. A filtered list with no matches uses the title "No matches" and a description naming the active filters, with "Clear filters" as the action.

- [ ] **Step 8: System test** `test/system/filters_test.rb`: sign in, open Posts, type part of a fixture post's title in the search field, assert (without pressing anything) that only that post is listed and the field still has focus; pick a status in the select and assert the list changes; press "Clear" and assert both posts are back.

- [ ] **Step 9: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 10: Commit.** `git commit -m "feat: page-number pagination, relative dates, instant filters, in-card empty states"`

---

### Task 10: Form controls and validation

**Files:**
- Create: `app/components/admin/select_component.rb`; `file_drop_component.{rb,html.erb}`; `prefix_input_component.{rb,html.erb}`; `error_summary_component.{rb,html.erb}`; `app/javascript/controllers/admin/file_drop_controller.js`; tests; previews
- Modify: `app/helpers/setup_helper.rb` (`setup_select_class`), every view using a bare `<select>` (list from `grep -rln "select_tag\|<select\|\.select(" app/views app/components`), `app/views/admin/media/index.html.erb` and `app/views/setup/site.html.erb` (file inputs), `app/components/admin/columns/slug_column_component.{rb,html.erb}` (**bug 1**), `app/views/admin/shared/_field_errors.html.erb`, `app/views/admin/users/{new,edit}.html.erb`, `app/views/admin/groups/_form.html.erb`, `app/views/admin/accounts/edit.html.erb`

**Interfaces:**
- Produces:
  - `setup_select_class → String` and CSS class `.cs-select` (custom chevron, token colours).
  - `Admin::SelectComponent.new(name:, options:, selected: nil, id: nil, include_blank: nil, **html)` — `options` as accepted by `options_for_select`.
  - `Admin::FileDropComponent.new(name:, id:, accept: Media::Asset::ALLOWED_CONTENT_TYPES.join(","), multiple: false, hint: nil)`.
  - `Admin::PrefixInputComponent.new(name:, id:, value:, prefix:, errors: [], **html)`.
  - `Admin::ErrorSummaryComponent.new(errors:, field_ids: {})` — `errors` is `{ "field" => ["message", …] }` or an `ActiveModel::Errors`; `field_ids` maps a field to the DOM id its link jumps to.
  - `SlugColumnComponent#prefix → String` ending in exactly one `/`.

- [ ] **Step 1: Bug 1, failing test** (add to `test/components/admin/columns/slug_column_component_test.rb`):

```ruby
test "the URL prefix never doubles the slash, whatever the base looks like" do
  {
    "https://example.com" => "example.com/",
    "https://example.com/" => "example.com/",
    "https://example.com/de" => "example.com/de/",
    "https://example.com/de/" => "example.com/de/",
    "https://example.com/de//" => "example.com/de/",
    "" => "/"
  }.each do |base, prefix|
    component = Admin::Columns::SlugColumnComponent.new(value: "about", base_url: base)
    assert_equal prefix, component.prefix, base.inspect
    render_inline(component)
    assert_no_text "//about"
  end
end
```

Implement:

```ruby
      # The part of the public URL in front of the slug, shown in the prefix
      # cell: host and parent path, ending in exactly one slash. Callers pass
      # bases with and without a trailing slash (the root page's children,
      # a non-default language's prefix), which is how "//about" and
      # "/de//about" got on screen (design pass bug 1).
      def prefix
        base = base_url.to_s.sub(%r{\Ahttps?://}, "").gsub(%r{/+\z}, "")
        "#{base}/"
      end
```

and render the field as `Admin::PrefixInputComponent` (prefix = `prefix`, the input keeping its `**html` data attributes and the `data-admin--slug-preview-target="output"` span moved under it as the full-URL preview line). Also find who builds `base_url` (`grep -rn "base_url:" app`) and fix the source so it never has a trailing slash; keep the defensive `prefix` anyway.

- [ ] **Step 2: Prefix input.** Test:

```ruby
test "a sunken prefix cell joined to the input, one border around both" do
  render_inline(Admin::PrefixInputComponent.new(name: "slug", id: "slug", value: "about", prefix: "example.com/"))
  assert_selector ".admin-prefix-input span.bg-sunken", text: "example.com/"
  assert_selector ".admin-prefix-input input#slug[name=slug][value=about]"
end

test "with errors the wrapper turns danger and the input is described by them" do
  render_inline(Admin::PrefixInputComponent.new(name: "slug", id: "slug", value: "", prefix: "/", errors: [ "can't be blank" ]))
  assert_selector ".admin-prefix-input.border-danger input[aria-invalid=true][aria-describedby='slug-errors']"
end
```

Markup: wrapper `flex rounded-cs border border-line-strong bg-surface focus-within:border-accent`; prefix `shrink-0 border-r border-line bg-sunken px-2.5 py-2 font-cs-mono text-sm text-meta`; input `min-w-0 flex-1 bg-transparent px-2.5 py-2 outline-none`. The prefix cell keeps its sunken ground when invalid.

- [ ] **Step 3: Select.** `.cs-select` in `content-spiel.tailwind.css`:

```css
.cs-select {
  appearance: none;
  border: 1px solid var(--cs-line-strong);
  border-radius: var(--cs-radius);
  background-color: var(--cs-surface);
  color: var(--cs-ink);
  padding: 0.5rem 2rem 0.5rem 0.625rem;
  background-image: linear-gradient(45deg, transparent 50%, var(--cs-meta) 50%), linear-gradient(135deg, var(--cs-meta) 50%, transparent 50%);
  background-position: calc(100% - 15px) 55%, calc(100% - 10px) 55%;
  background-size: 5px 5px, 5px 5px;
  background-repeat: no-repeat;
}
.cs-select:focus-visible { outline: 2px solid var(--cs-accent); outline-offset: 1px; }
.cs-select[aria-invalid="true"] { border-color: var(--cs-danger); }
```

(A CSS-drawn chevron so it takes the token colour in both themes; no image.) `setup_select_class = "cs-select w-full"`. `SelectComponent#call` is `select_tag(name, options_for_select(options, selected), id:, include_blank:, class: [ "cs-select", html[:class] ], **html.except(:class))`. Component test: renders `select.cs-select[name=…]` with the selected option. Then give every existing `<select>` the class (via the helper or the component — don't rewrite working `select_tag` calls beyond adding the class).

- [ ] **Step 4: File drop.** Test:

```ruby
test "a labelled drop zone around a visually hidden file input, with a Choose file button" do
  render_inline(Admin::FileDropComponent.new(name: "file", id: "upload", multiple: true, hint: "PNG, JPEG, GIF or WebP, up to 10 MB"))
  assert_selector ".admin-file-drop[data-controller='admin--file-drop']"
  assert_selector "input#upload[type=file][name=file][multiple].sr-only", visible: :all
  assert_selector "label[for=upload]", text: "Choose file"
  assert_text "PNG, JPEG, GIF or WebP, up to 10 MB"
  assert_selector "[data-admin--file-drop-target=name][aria-live=polite]"
end
```

Markup: zone `rounded-cs border border-dashed border-line-strong px-4 py-6 text-center` (`data-dragging` → `border-accent bg-accent-tint` via `data-[dragging]:…`), text "Drop an image here or", the `label` styled as a secondary button, the chosen file name(s) in the `name` target. Controller: `dragover` (preventDefault, set `data-dragging`), `dragleave`/`drop` (clear), `drop` assigns `event.dataTransfer.files` to the input and dispatches `change`; `change` writes the names ("3 files" for more than one). Use it for the media upload form and setup's logo field. The media screen's existing `admin--media-upload` controller keeps doing the upload; it listens to the same input's `change`.

- [ ] **Step 5: Error summary.** Test:

```ruby
test "a danger-tint box that lists each field's errors as links to the field" do
  render_inline(Admin::ErrorSummaryComponent.new(errors: { "email_address" => [ "has already been taken" ], "password" => [ "Use at least 12 characters." ] },
    field_ids: { "email_address" => "user_email", "password" => "user_password" }))
  assert_selector ".admin-error-summary[role=alert][tabindex='-1'].bg-danger-tint"
  assert_text "2 things need fixing"
  assert_selector "a[href='#user_email']", text: "Email address has already been taken"
  assert_selector "a[href='#user_password']", text: "Use at least 12 characters."
end

test "one error reads in the singular, and no errors render nothing" do
  render_inline(Admin::ErrorSummaryComponent.new(errors: { "name" => [ "is too long" ] }))
  assert_text "1 thing needs fixing"
  render_inline(Admin::ErrorSummaryComponent.new(errors: {}))
  assert_no_selector ".admin-error-summary"
end
```

A message that already starts with a capital letter and ends with a full stop (a whole sentence, like the password rule) is printed as is; otherwise it's prefixed with the humanized field name. Use the two whole-string headings "1 thing needs fixing" / "N things need fixing" (no concatenation). Render it at the top of the explicit-save forms on a 422: users new/edit, groups form, account password/profile. Per-field: update `admin/shared/_field_errors.html.erb` to `text-danger-ink` with a leading "!" and give the invalid input `aria-invalid="true"`, `aria-describedby` and a `border-danger` class.

- [ ] **Step 6: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 7: Commit.** `git commit -m "feat: styled selects, file drop, prefix input, error summary; fix the double slash in slug URLs"`

---

### Task 11: Save bar and drag pattern

**Files:**
- Create: `app/components/admin/save_bar_component.{rb,html.erb}`; `app/javascript/controllers/admin/save_bar_controller.js`; test; preview
- Modify: `app/views/admin/users/{new,edit}.html.erb`, `app/views/admin/groups/_form.html.erb`, `app/views/admin/accounts/edit.html.erb` (the three explicit-save screens that exist today; Settings joins in round 3)
- Modify: `app/javascript/controllers/admin/tree_controller.js`, `blocks_controller.js`; `app/components/admin/tree_node_component.html.erb`, `block_card_component.html.erb`; `app/controllers/admin/tree_controller.rb`, `content_blocks_controller.rb` (Undo toast on drop)

**Interfaces:**
- Consumes: `Admin::ConfirmDialogComponent`, `dialog_trigger`, `toast_stream` (Tasks 7–8).
- Produces: `Admin::SaveBarComponent.new(form_id:, cancel_url:, save_label: "Save")`. Stimulus `admin--save-bar` on the `<form>`; the bar is rendered **inside** the form. Leave dialog id `"leave-dialog"`, rendered once in the layout. Drag CSS classes `.admin-drag-ghost`, `.admin-drag-chosen`.

- [ ] **Step 1: Failing component test.**

```ruby
require "test_helper"

class Admin::SaveBarComponentTest < ViewComponent::TestCase
  test "a hidden sticky bar with a live count, Cancel and Save" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    assert_selector ".admin-save-bar[hidden][data-admin--save-bar-target=bar]", visible: :all
    assert_selector "[data-admin--save-bar-target=count][aria-live=polite]", visible: :all
    assert_selector "a[href='/users']", text: "Cancel", visible: :all
    assert_selector "button[type=submit][form='user-form']", text: "Save", visible: :all
  end
end
```

- [ ] **Step 2: Build.** Bar: `sticky bottom-0 z-20 -mx-6 mt-6 flex items-center justify-end gap-3 border-t border-line bg-surface px-6 py-3`; count `mr-auto font-cs-mono text-label uppercase tracking-mono text-meta`. Controller:

```js
import { Controller } from "@hotwired/stimulus"

// The explicit-save pattern for configuration screens (design pass spec §4,
// handoff §9 B12): the bar appears once something differs from what was
// loaded, counts the changed fields, and leaving with changes asks first.
// A change is counted per *named control*, comparing against a snapshot
// taken on connect -- so changing a field back removes it from the count.
export default class extends Controller {
  static targets = ["bar", "count"]

  connect() {
    this.initial = this.snapshot()
    this.submitting = false
    this.onVisit = (event) => this.guard(event)
    this.onUnload = (event) => { if (this.changes > 0 && !this.submitting) event.preventDefault() }
    document.addEventListener("turbo:before-visit", this.onVisit)
    window.addEventListener("beforeunload", this.onUnload)
    this.refresh()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.onVisit)
    window.removeEventListener("beforeunload", this.onUnload)
  }

  refresh() {
    const count = this.changes
    this.barTarget.hidden = count === 0
    this.countTarget.textContent = count === 1 ? "1 unsaved change" : `${count} unsaved changes`
  }

  markSubmitting() { this.submitting = true }

  guard(event) {
    if (this.changes === 0 || this.submitting || this.leaving) return
    event.preventDefault()
    const dialog = document.getElementById("leave-dialog")
    dialog.querySelector("[data-leave-confirm]").onclick = () => {
      this.leaving = true
      dialog.close()
      window.Turbo.visit(event.detail.url)
    }
    dialog.showModal()
  }

  snapshot() {
    const values = {}
    for (const field of this.element.elements) {
      if (!field.name || field.type === "hidden" || field.type === "submit") continue
      const value = field.type === "checkbox" || field.type === "radio" ? String(field.checked) : field.value
      const key = field.type === "checkbox" || field.type === "radio" ? `${field.name}=${field.value}` : field.name
      values[key] = value
    }
    return values
  }

  get changes() {
    const now = this.snapshot()
    return Object.keys({ ...this.initial, ...now }).filter((key) => this.initial[key] !== now[key]).length
  }
}
```

Wire the form: `data-action="input->admin--save-bar#refresh change->admin--save-bar#refresh turbo:submit-start->admin--save-bar#markSubmitting"`. The Leave dialog in the layout: `ConfirmDialogComponent.new(id: "leave-dialog", title: "Leave without saving?", body: "Your changes on this screen will be lost.", cancel_label: "Stay")` with a primary "Leave" button carrying `data-leave-confirm` (`.onclick` assigned in JS is a property, not an inline handler attribute, so the guard test in Task 7 still passes). Password fields count as changes like any other.

- [ ] **Step 3: Apply** to the users, groups and account forms: give each form an `id`, wrap with the controller, replace its submit row with the bar.

- [ ] **Step 4: System test** `test/system/save_bar_test.rb`: sign in as an owner; open a user's edit screen; assert no visible `.admin-save-bar`; type in Name; assert "1 unsaved change"; clear it back to the original; assert the bar hides; type again and click the sidebar's "Posts"; assert `dialog#leave-dialog[open]`; press "Stay" and assert still on the user form with the typed value; click "Posts" again, press "Leave", assert the posts list.

- [ ] **Step 5: Drag pattern** (handoff §9 A9). CSS:

```css
.admin-drag-ghost { border: 1px dashed var(--cs-line-strong); background: transparent; }
.admin-drag-ghost > * { visibility: hidden; }
.admin-drag-chosen { background: var(--cs-surface); box-shadow: var(--cs-shadow-menu); }
```

Pass `ghostClass: "admin-drag-ghost", chosenClass: "admin-drag-chosen"` to both existing SortableJS setups; the handle gets `hover:text-ink` and its row `hover:bg-sunken`. **Keyboard path:** make each handle a `<button type="button">` with `aria-label="Move <title>"` and `aria-describedby` pointing at one `sr-only` instruction ("Press Space to pick up, arrow keys to move, Space to drop, Escape to cancel."). In `tree_controller.js` and `blocks_controller.js` add a `keydown` action on the handle: Space toggles a `data-picked` state on the row (announced through an `aria-live="assertive"` `sr-only` region: "Picked up About. Position 2 of 5."); while picked, ArrowUp/ArrowDown move the row among its siblings in the DOM (tree only: ArrowRight nests it under the previous sibling, ArrowLeft moves it out one level — only where the mouse path would allow the same drop); Space drops and calls the same save function the SortableJS `onEnd` callback calls; Escape restores the original position without saving. **Undo on drop:** the tree and block reorder responses append `toast_stream("Moved “<title>”.", kind: :undo, action: { label: "Undo", url: <the same move endpoint with the previous parent_id/position, or the previous block order>, method: :post })` — the previous values are read in the controller before calling the service. Undo runs the ordinary `Pages::Move` / `ContentBlocks::Reorder` service again, with their ordinary permission checks.

- [ ] **Step 6: System tests.** Extend `test/system/tree_test.rb`: focus a movable page's handle, send Space, ArrowDown, Space; assert the new order persists after `visit`; assert an Undo toast appeared; press Undo and assert the original order. Same for blocks in the block editor's system test (Space, ArrowUp, Space).

- [ ] **Step 7: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 8: Commit.** `git commit -m "feat: save bar with Leave dialog; drag styling, keyboard path and Undo"`

---

### Task 12: The shell — sidebar, top bar, drawers, 403 and 404

**Files:**
- Create: `app/components/admin/shell/sidebar_component.{rb,html.erb}`, `shell/top_bar_component.{rb,html.erb}`; `app/javascript/controllers/admin/drawer_controller.js`; `app/views/admin/errors/not_found.html.erb`; tests; preview
- Modify: `app/controllers/admin/base_controller.rb` (`MODULES` gets `group:`; 404 rendering), `app/views/layouts/admin.html.erb`, `app/views/admin/errors/forbidden.html.erb`, `app/views/admin/shared/_icon.html.erb` (add `:menu`, `:search`), `test/application_system_test_case.rb` (unchanged selector `nav[aria-label='Modules']` must keep working)

**Interfaces:**
- Consumes: `Admin::ThemeSwitchComponent`, `User#display_name`, `Trash.roots`/`AccessControl.scope(..., trashed: true)`.
- Produces:
  - `MODULES` entries gain `group: :content | :people | :system`, in this order — Content: Dashboard, Pages, Posts, Media, Translations, Tags, Mind graph, Trash; People: Users, Groups; System: Settings, AI assistant, System status, Audit log.
  - `Admin::Shell::SidebarComponent.new(modules:, user:, current_path:, url_options:, trash_count: 0)`; `modules` is `admin_modules` (already permission-filtered).
  - `helper_method :trash_badge_count` in `BaseController` — trashed page roots, posts and images the viewer could act on, counted through the same scopes `Admin::TrashController` lists with.
  - `Admin::Shell::SidebarComponent#role_line → String`: "Owner", or up to two group names then "+N", or "No groups".
  - `<button data-action="admin--command-palette#open">` in the sidebar and top bar (the controller arrives in Task 13; until then the button is inert).
  - `BaseController` renders `admin/errors/not_found` (status 404, admin layout) for `ActiveRecord::RecordNotFound`.

- [ ] **Step 1: Failing sidebar tests** `test/components/admin/shell/sidebar_component_test.rb`:

```ruby
require "test_helper"

class Admin::Shell::SidebarComponentTest < ViewComponent::TestCase
  def modules(*labels) = Admin::BaseController::MODULES.select { |entry| labels.include?(entry[:label]) }

  def render_sidebar(labels:, user: users(:one), trash_count: 0)
    with_request_url "/cs-studio" do
      render_inline(Admin::Shell::SidebarComponent.new(modules: modules(*labels), user: user,
        current_path: "/cs-studio/posts", url_options: {}, trash_count: trash_count))
    end
  end

  test "modules are grouped under Content, People and System, in the design's order" do
    render_sidebar(labels: Admin::BaseController::MODULES.map { |entry| entry[:label] })
    assert_equal %w[Content People System], page.all("nav[aria-label='Modules'] h2").map(&:text)
    content = page.all("nav[aria-label='Modules'] section")[0].all("a").map(&:text).map(&:strip)
    assert_equal [ "Dashboard", "Pages", "Posts", "Media", "Translations", "Tags", "Mind graph", "Trash" ], content
  end

  test "a group with no visible module disappears, heading and all" do
    render_sidebar(labels: [ "Dashboard", "AI assistant" ])
    assert_equal %w[Content System], page.all("nav[aria-label='Modules'] h2").map(&:text)
    assert_no_text "People"
  end

  test "the current module is marked" do
    render_sidebar(labels: %w[Dashboard Posts])
    assert_selector "a[aria-current=page]", text: "Posts"
  end

  test "the trash badge shows a count and hides at zero" do
    render_sidebar(labels: %w[Trash], trash_count: 3)
    assert_selector "a", text: /Trash\s*3/
    render_sidebar(labels: %w[Trash], trash_count: 0)
    assert_no_selector "[data-badge]"
  end

  test "the account block names the user, their email and their role line" do
    user = users(:one)
    user.name = "Ada Lovelace"
    render_sidebar(labels: %w[Dashboard], user: user)
    assert_selector ".admin-account", text: "Ada Lovelace"
    assert_selector ".admin-account", text: user.email_address
    assert_selector ".admin-account a", text: "Change password"
    assert_selector ".admin-account button", text: "Sign out"
  end

  test "the role line: Owner, up to two groups then +N, or No groups" do
    component = ->(user) { Admin::Shell::SidebarComponent.new(modules: [], user: user, current_path: "/", url_options: {}) }
    owner = User.new(owner: true)
    assert_equal "Owner", component.call(owner).role_line
    none = User.new
    assert_equal "No groups", component.call(none).role_line
    many = User.new
    many.define_singleton_method(:groups) { %w[Editor Author Reviewer Guest].map { |name| AccessControl::Group.new(name: name) } }
    assert_equal "Editor, Author +2", component.call(many).role_line
  end

  test "a long name or email truncates instead of widening the sidebar" do
    user = users(:one)
    user.name = "A" * 120
    render_sidebar(labels: %w[Dashboard], user: user)
    assert_selector ".admin-account .truncate[title='#{'A' * 120}']"
  end
end
```

(Adapt `User.new(owner: true)` and `groups` to the model's real attribute and association names.)

- [ ] **Step 2: Build the sidebar** from `StudioSidebar.dc.html`: `nav[aria-label="Modules"]` `flex h-full w-60 flex-col bg-chrome border-r border-line`; top: wordmark ("Content·Spiel", `font-semibold`) and the "Jump to… ⌘K" button (`w-full rounded-cs border border-line-strong px-2 py-1.5 text-left text-sm text-meta`, the `⌘K` hint in `font-cs-mono text-label`); middle (scrolls): one `<section>` per non-empty group, `h2` in the field-label style, links `flex items-center gap-2.5 rounded-cs px-2 py-1.5 text-sm text-dim hover:bg-sunken`, current `bg-sunken text-ink font-medium` + `aria-current="page"` (current = `current_path` starts with the module's path; Dashboard only on an exact match); badge `data-badge` `ml-auto font-cs-mono text-label text-meta`; bottom: the theme switch, then `.admin-account` — name (`truncate text-sm font-medium`), email (`truncate text-xs text-meta`), role line (`font-cs-mono text-label uppercase tracking-mono text-meta`), then "Change password" and "Sign out" as small links (`button_to … method: :delete` for sign out). Keep the layout's comment about `admin_url_options` on module links, moved into the component.

- [ ] **Step 3: `trash_badge_count`.** In `BaseController`:

```ruby
    # The sidebar's Trash badge (design pass spec §4): how many trashed
    # items *this viewer* could act on -- the same delete-right scopes the
    # Trash screen lists with (page branch roots, posts, images), so the
    # number matches what they'd see there. Three COUNTs per CS Studio
    # page load, each on the indexed `trashed_at`.
    def trash_badge_count
      return 0 unless admin_modules.any? { |entry| entry[:path] == :admin_trash_path }
      @trash_badge_count ||= Admin::TrashController::MODELS.keys.sum { |type| Admin::TrashController.listed_scope(type, Current.actor).count }
    end
```

Extract the Trash controller's private `listed(type)` relation into a class method `listed_scope(type, actor)` that both use (don't duplicate the scoping). Test in `test/controllers/admin/trash_controller_test.rb`: with one trashed post the signed-in editor may delete and one they may not, the dashboard's sidebar shows `1`.

- [ ] **Step 4: Layout.** Rewrite `layouts/admin.html.erb`'s body (keep every existing comment that still applies; rewrite the grid comment):

```erb
<body data-admin-locale="<%= admin_locale %>" data-controller="admin--dialog admin--drawer"
      data-action="click->admin--dialog#backdrop keydown.esc@window->admin--drawer#closeAll"
      class="min-h-screen bg-paper font-cs text-ink scheme-light dark:scheme-dark">
  <%= render Admin::Shell::TopBarComponent.new(tree: content_for?(:tree)) %>
  <div class="admin-shell <%= "admin-shell--tree" if content_for?(:tree) %>">
    <div id="sidebar" class="admin-shell__sidebar" data-admin--drawer-target="panel" data-drawer="sidebar">
      <%= render Admin::Shell::SidebarComponent.new(modules: admin_modules, user: Current.user, current_path: request.path,
            url_options: admin_url_options, trash_count: trash_badge_count) %>
    </div>
    <% if content_for?(:tree) %>
      <aside id="tree-column" class="admin-shell__tree" data-admin--drawer-target="panel" data-drawer="tree"><%= yield :tree %></aside>
    <% end %>
    <main class="admin-shell__main min-w-0 p-6">
      <turbo-frame id="content" data-turbo-action="advance"><%= yield %></turbo-frame>
    </main>
  </div>
  <div class="admin-shell__scrim" data-action="click->admin--drawer#closeAll" hidden data-admin--drawer-target="scrim"></div>
  <%= render Admin::ToastRegionComponent.new(flash: flash) %>
  …picker, confirm form, leave dialog as before…
</body>
```

CSS (in `content-spiel.tailwind.css`; breakpoints from handoff §9 A7 — real CSS because the drawer states need attribute selectors):

```css
.admin-shell { display: grid; grid-template-columns: 15rem minmax(0, 1fr); min-height: 100vh; }
.admin-shell--tree { grid-template-columns: 15rem 17rem minmax(0, 1fr); } /* 272px tree column */
.admin-shell__sidebar { position: sticky; top: 0; height: 100vh; }
.admin-shell__tree { border-right: 1px solid var(--cs-line); background: var(--cs-chrome); padding: 1rem; }
.admin-top-bar { display: none; }
.admin-shell__scrim { position: fixed; inset: 0; z-index: 30; background: color-mix(in oklab, var(--cs-ink) 38%, transparent); }

@media (max-width: 1279px) {
  .admin-top-bar { display: flex; }
  .admin-shell { grid-template-columns: minmax(0, 1fr); }
  .admin-shell--tree { grid-template-columns: 17rem minmax(0, 1fr); }
  .admin-shell__sidebar { position: fixed; z-index: 40; top: 0; left: 0; transform: translateX(-100%); transition: transform 0.2s var(--cs-ease); }
  .admin-shell__sidebar[data-open] { transform: none; }
}
@media (max-width: 1023px) {
  .admin-shell--tree { grid-template-columns: minmax(0, 1fr); }
  .admin-shell__tree { position: fixed; z-index: 40; top: 48px; bottom: 0; left: 0; width: 17rem; transform: translateX(-100%); transition: transform 0.2s var(--cs-ease); }
  .admin-shell__tree[data-open] { transform: none; }
}
@media (prefers-reduced-motion: reduce) { .admin-shell__sidebar, .admin-shell__tree { transition: none; } }
```

Top bar (`h-12`, `sticky top-0 z-20 border-b border-line bg-chrome`): ☰ (`aria-label="Open navigation"`, `aria-controls="sidebar"`, `aria-expanded`), the wordmark, a "Pages ▾" button shown only under 1024 when `tree:` (`aria-controls="tree-column"`), and the ⌘K button at the right. `drawer_controller.js`: `toggle({ params: { name } })` sets/removes `data-open` on the panel with that `data-drawer`, shows the scrim, updates the trigger's `aria-expanded`, moves focus into the panel; `closeAll()` closes both and returns focus to the trigger; closes on `turbo:before-visit`, and on `turbo:frame-load` for the tree drawer (a page was picked).

- [ ] **Step 5: 403 and 404.** Restyle `forbidden.html.erb` per `Studio States v3.dc.html` card C33 (centred column, mono "403", `h1` "No access", the message, one link "Back to the dashboard"). New `not_found.html.erb`: mono "404", `h1` "Not found", body "This doesn't exist, or you don't have access to it." (one sentence that never confirms existence), link "Back to the dashboard". In `BaseController`:

```ruby
    # A record outside the viewer's scope and a record that doesn't exist
    # answer identically (access-control design spec §3.3) -- now inside the
    # Studio layout rather than the app's bare 404, so the way on (the
    # sidebar) is still there. Signed-in requests only: authentication runs
    # first, so a signed-out visitor is redirected to sign-in before any
    # lookup can raise.
    rescue_from ActiveRecord::RecordNotFound do
      respond_to do |format|
        format.html { render "admin/errors/not_found", status: :not_found }
        format.any { head :not_found }
      end
    end
```

Check how Turbo-frame and turbo-stream requests fare: a frame request must still get a body containing `<turbo-frame id="content">` (the layout provides it). Integration test `test/integration/admin_not_found_test.rb`:

```ruby
require "test_helper"

class AdminNotFoundTest < ActionDispatch::IntegrationTest
  test "a missing record and an out-of-scope record both get the same Studio 404" do
    sign_in_as users(:two) # an author who can't read every page; adapt to the fixture that has a scoped reader
    get admin_post_path(id: 999_999)
    assert_response :not_found
    missing = response.body
    assert_select "nav[aria-label='Modules']"
    assert_select "h1", "Not found"

    get admin_page_path(pages(:one)) # a page outside this user's scope
    assert_response :not_found
    assert_equal missing.gsub(/nonce="[^"]+"|csrf-token" content="[^"]+"/, ""), response.body.gsub(/nonce="[^"]+"|csrf-token" content="[^"]+"/, "")
  end

  test "an autosave to a missing record still answers 404 without the HTML page" do
    sign_in_as users(:one)
    patch admin_post_path(id: 999_999), params: { post: { title: "x" } }, as: :turbo_stream
    assert_response :not_found
  end
end
```

(Pick fixtures so the second request really is out of scope; if no such fixture pair exists, build the grant in the test the way `test/integration/trash_visibility_test.rb` builds its scoped user.)

- [ ] **Step 6: A user with no grants.** Add to `test/controllers/admin/dashboard_controller_test.rb`:

```ruby
test "a user with no groups sees only the open modules, no empty group headings, and No groups" do
  user = User.create!(email_address: "nobody@example.com", password: "a long enough password")
  sign_in_as user
  get admin_root_path
  assert_response :success
  assert_select "nav[aria-label='Modules'] h2", count: 2 # Content (Dashboard) and System (AI assistant)
  assert_select "nav[aria-label='Modules'] h2", text: "People", count: 0
  assert_select ".admin-account", text: /No groups/
end
```

- [ ] **Step 7: System test** `test/system/shell_test.rb`:

```ruby
require "application_system_test_case"

class ShellTest < ApplicationSystemTestCase
  test "under 1280 the sidebar is a drawer behind the top bar" do
    sign_in_via_form users(:one)
    page.driver.resize(1100, 900)
    assert_selector ".admin-top-bar"
    assert_no_selector "#sidebar[data-open]"
    find("button[aria-label='Open navigation']").click
    assert_selector "#sidebar[data-open]"
    find("body").send_keys(:escape)
    assert_no_selector "#sidebar[data-open]"
    find("button[aria-label='Open navigation']").click
    within("#sidebar") { press "Posts" }
    assert_selector "h1", text: "Posts"
    assert_no_selector "#sidebar[data-open]"
  ensure
    page.driver.resize(1400, 1400)
  end
end
```

`sign_in_via_form` asserts `nav[aria-label='Modules']`, which still exists.

- [ ] **Step 8: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. Fix tests pinned to the old `<ul>` of modules or to "Change password"/"Sign out" markup. PASS.

- [ ] **Step 9: Commit.** `git commit -m "feat: CS Studio shell with grouped sidebar, account block, drawers and in-layout 403/404"`

---

### Task 13: ⌘K "Jump to…"

**Files:**
- Create: `app/queries/jump/search.rb`; `app/controllers/admin/jump_controller.rb`; `app/views/admin/jump/show.html.erb`; `app/components/admin/shell/command_palette_component.{rb,html.erb}`; `app/javascript/controllers/admin/command_palette_controller.js`; tests
- Modify: `config/routes.rb` (`get "jump", to: "jump#show", as: :jump` inside the admin scope), `app/views/layouts/admin.html.erb`

**Interfaces:**
- Consumes: `AccessControl.scope`, `Media::Search`, `can?`, `admin_modules`, `Admin::StatusChipComponent`, `Admin::DialogComponent` styles.
- Produces: `Jump::Search.new(actor:, query:, modules:, url_options: {}).groups → [{ label: String, rows: [{ title:, url:, hint: nil, status: nil }] }]`, at most 5 rows per group, groups in the order Pages, Posts, Media, Settings, Actions, empty groups omitted. `GET /<admin>/jump?q=` renders an HTML fragment (no layout) for the palette's results frame.

- [ ] **Step 1: Failing query test** `test/queries/jump/search_test.rb`:

```ruby
require "test_helper"

class Jump::SearchTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @modules = Admin::BaseController::MODULES
  end

  def search(query, actor: @owner, modules: @modules) = Jump::Search.new(actor: actor, query: query, modules: modules).groups

  test "matches page and post titles in any language, case-insensitively, five per group" do
    7.times { |i| Post.create!(title: "Jumpable #{i}", slug: "jumpable-#{i}", content_type: "blog", author: @owner) }
    groups = search("jumpABLE")
    posts = groups.find { |group| group[:label] == "Posts" }
    assert_equal 5, posts[:rows].size
    assert posts[:rows].all? { |row| row[:title].start_with?("Jumpable") }
  end

  test "an empty query lists modules and actions only" do
    labels = search("").map { |group| group[:label] }
    assert_equal %w[Settings Actions], labels & %w[Pages Posts Media Settings Actions]
  end

  test "LIKE wildcards are literal text, not match-everything" do
    assert_empty search("%").select { |group| %w[Pages Posts Media].include?(group[:label]) }
    assert_empty search("_").select { |group| %w[Pages Posts Media].include?(group[:label]) }
    assert_nothing_raised { search("\\") }
  end

  test "an overlong query is cut to 100 characters instead of failing" do
    assert_nothing_raised { search("a" * 500) }
  end

  test "trashed records and records outside the viewer's scope never appear" do
    visible = Post.create!(title: "Findme kept", slug: "findme-kept", content_type: "blog", author: @owner)
    Post.create!(title: "Findme trashed", slug: "findme-trashed", content_type: "blog", author: @owner, trashed_at: Time.current)
    titles = search("findme").flat_map { |group| group[:rows] }.map { |row| row[:title] }
    assert_equal [ visible.title ], titles

    nobody = User.create!(email_address: "nobody@example.com", password: "a long enough password")
    assert_empty search("findme", actor: nobody, modules: []).flat_map { |group| group[:rows] }.select { |row| row[:title].include?("Findme") }
  end

  test "modules and actions are limited to what the viewer may open" do
    nobody = User.create!(email_address: "nobody2@example.com", password: "a long enough password")
    open_modules = Admin::BaseController::MODULES.select { |entry| entry[:permission].nil? }
    rows = search("", actor: nobody, modules: open_modules).flat_map { |group| group[:rows] }.map { |row| row[:title] }
    assert_includes rows, "Dashboard"
    assert_not_includes rows, "Users"
    assert_not_includes rows, "New page"
  end
end
```

(Create posts/users the way `test/support/content_helper.rb` does if direct `create!` needs more attributes.)

- [ ] **Step 2: Implement `Jump::Search`.**

```ruby
module Jump
  # What ⌘K finds (design pass spec §5.6): titles only -- pages, posts and
  # library images the viewer may read, CS Studio's own modules, and a few
  # actions. Full-text search is a separate roadmap item; this is a way to
  # *go* somewhere, not to find a phrase.
  #
  # Read-scoped the same way every list is (`AccessControl.scope`, kept
  # records only), so a title the viewer couldn't open is never suggested.
  # The query is user text inside a LIKE pattern: `sanitize_sql_like`
  # escapes `%`, `_` and `\`, so "%" searches for a percent sign rather
  # than matching everything.
  class Search
    LIMIT = 5
    MAX_QUERY = 100

    def initialize(actor:, query:, modules:, url_options: {})
      @actor = actor
      @query = query.to_s.strip.first(MAX_QUERY)
      @modules = modules
      @url_options = url_options
    end

    def groups
      [
        group("Pages", page_rows), group("Posts", post_rows), group("Media", media_rows),
        group("Settings", module_rows), group("Actions", action_rows)
      ].compact
    end

    private

    attr_reader :actor, :query, :modules, :url_options

    def group(label, rows) = rows.empty? ? nil : { label: label, rows: rows.first(LIMIT) }
    def blank? = query.empty?
    def pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    def routes = Rails.application.routes.url_helpers

    # `title` is a jsonb of { locale => text }: `title::text ILIKE` matches
    # any language's title in one predicate. It can also match a locale
    # *key* for a one- or two-letter query ("de"); the Ruby-side filter
    # below drops those, and the over-fetch keeps the group full.
    def titled(relation)
      relation.where("#{relation.table_name}.title::text ILIKE ?", pattern).order(updated_at: :desc).limit(LIMIT * 4)
        .select { |record| record.read_attribute(:title).to_h.values.any? { |value| value.to_s.downcase.include?(query.downcase) } }
        .first(LIMIT)
    end

    def page_rows
      return [] if blank?
      titled(AccessControl.scope(actor, "pages.read", Page.all, channel: :admin)).map do |page|
        { title: display_title(page), url: routes.admin_page_path(page, **url_options), status: page.status }
      end
    end

    def post_rows
      return [] if blank?
      titled(AccessControl.scope(actor, "posts.read", Post.all, channel: :admin)).map do |post|
        { title: display_title(post), url: routes.edit_admin_post_path(post, **url_options), status: post.status, hint: post.content_type }
      end
    end

    def media_rows
      return [] if blank? || !AccessControl.holds?(actor, "media.upload", channel: :admin)
      Media::Search.new(query).results.limit(LIMIT).map do |asset|
        { title: asset.title, url: routes.admin_media_path(selected: asset.id, **url_options) }
      end
    end

    def module_rows
      modules.select { |entry| blank? || entry[:label].downcase.include?(query.downcase) }.map do |entry|
        { title: entry[:label], url: routes.public_send(entry[:path], **url_options) }
      end
    end

    ACTIONS = [
      { title: "New page", path: :new_admin_page_path, permission: "pages.create" },
      { title: "New post", path: :new_admin_post_path, permission: "posts.create" },
      { title: "Upload image", path: :admin_media_path, permission: "media.upload" },
      { title: "Change password", path: :admin_account_password_path, permission: nil }
    ].freeze

    def action_rows
      ACTIONS.select { |action| action[:permission].nil? || AccessControl.holds?(actor, action[:permission], channel: :admin) }
        .select { |action| blank? || action[:title].downcase.include?(query.downcase) }
        .map { |action| { title: action[:title], url: routes.public_send(action[:path], **url_options) } }
    end

    def display_title(record) = Locales.read(record, :title, locale: Locales.default).presence || "(untitled)"
  end
end
```

Adapt to the real signatures before running: `AccessControl.scope`/`holds?` argument order, `Media::Search`'s constructor and whether it already excludes trashed assets and takes a base relation, the page/post admin route helpers, and `Locales.read`. The Settings group is CS Studio's modules (handoff groups them as "Settings"); with an empty query it lists them all, capped at five.

- [ ] **Step 3: Controller and view.**

```ruby
module Admin
  # ⌘K's results (design pass spec §5.6). Open to every signed-in user, like
  # the dashboard: there's no permission to check for the endpoint itself,
  # because every row it returns is already narrowed to what this viewer
  # may read (`Jump::Search`). Read-only -- no service, no audit event.
  class JumpController < BaseController
    def show
      @query = params[:q].to_s
      @groups = Jump::Search.new(actor: Current.actor, query: @query, modules: admin_modules, url_options: admin_url_options).groups
      render layout: false
    end
  end
end
```

View: `<turbo-frame id="jump-results">`; each group a `<section>` with its mono-uppercase label and a `<ul role="listbox">` of `<li role="option"><a href=… data-turbo-frame="_top">title … status chip (hide_live: true) … hint</a></li>`; when no group has rows and the query is present: `<p>No results for “<%= @query %>”.</p>` plus, if `can?("posts.create")`, a link "New blog post “<%= @query %>”" to `new_admin_post_path(title: @query)`.

Integration test `test/controllers/admin/jump_controller_test.rb`: signed out → redirect to sign-in; signed in with `q` matching a fixture post → 200 and a link to it; `q=%` → 200 and no post links; a title containing `<script>` is escaped in the output (create a post titled `<script>alert(1)</script>` and assert `response.body` doesn't include the raw tag).

- [ ] **Step 4: Palette component and controller.** Component: a `<dialog id="command-palette" class="admin-dialog admin-palette" data-dialog-width="form">` (CSS: `.admin-palette { margin-top: 10vh; }`) with a search input (`role="combobox"`, `aria-controls="jump-results"`, `aria-expanded="true"`, `aria-label="Jump to…"`, `autocomplete="off"`), and `<turbo-frame id="jump-results" src="…/jump" loading="lazy">`. Controller on `<body>` (add `admin--command-palette` to its `data-controller`):

```js
import { Controller } from "@hotwired/stimulus"

// ⌘K / Ctrl+K "Jump to…" (design pass spec §5.6). The dialog and its
// results frame are rendered once in the layout; typing reloads the frame
// (debounced), arrows move the selection, Enter follows the selected link.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); this.open() }
    }
    window.addEventListener("keydown", this.onKey)
  }

  disconnect() { window.removeEventListener("keydown", this.onKey) }

  get dialog() { return document.getElementById("command-palette") }
  get input() { return this.dialog.querySelector("input") }
  get frame() { return this.dialog.querySelector("turbo-frame") }
  get options() { return Array.from(this.frame.querySelectorAll("[role=option] a")) }

  open() {
    if (this.dialog.open) return
    this.input.value = ""
    this.load()
    this.dialog.showModal()
    this.input.focus()
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 150)
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", this.input.value)
    this.frame.src = url.toString()
  }

  loaded() { this.select(0) }

  move(event) {
    if (!["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) return
    event.preventDefault()
    const options = this.options
    if (options.length === 0) return
    if (event.key === "Enter") return options[this.index]?.click()
    this.select((this.index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length)
  }

  select(index) {
    this.index = index
    this.options.forEach((option, i) => {
      option.parentElement.setAttribute("aria-selected", String(i === index))
      option.classList.toggle("bg-sunken", i === index)
      if (i === index) option.scrollIntoView({ block: "nearest" })
    })
  }
}
```

Wire: input `data-action="input->admin--command-palette#search keydown->admin--command-palette#move"`, frame `data-action="turbo:frame-load->admin--command-palette#loaded"`, `data-admin--command-palette-url-value="<%= admin_jump_path(**admin_url_options) %>"` on body. The dialog closes itself when a result is followed (a `_top` visit replaces the page).

- [ ] **Step 5: System test** `test/system/command_palette_test.rb`:

```ruby
require "application_system_test_case"

class CommandPaletteTest < ApplicationSystemTestCase
  test "⌘K opens, filters, and Enter goes to the first result" do
    post = posts(:one)
    sign_in_via_form users(:one)
    await_admin_controllers
    find("body").send_keys([ :control, "k" ])
    assert_selector "dialog#command-palette[open]"
    find("dialog#command-palette input").set(post.title.first(6))
    assert_selector "#jump-results [role=option][aria-selected=true]", text: post.title
    find("dialog#command-palette input").send_keys(:enter)
    assert_selector "h1", text: post.title
  end

  test "the sidebar button opens it too, and nonsense shows the no-results line" do
    sign_in_via_form users(:one)
    await_admin_controllers
    press "Jump to…"
    find("dialog#command-palette input").set("zzzqqq")
    assert_text "No results for “zzzqqq”."
  end
end
```

(Adjust the final heading assertion to whatever the post editor shows as its title.)

- [ ] **Step 6: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 7: Commit.** `git commit -m "feat: ⌘K jump palette over readable page, post and media titles"`

---

### Task 14: Bugs 2, 3, 4 and 7 — retention label, tree rows, starter offer, media trash reason

**Files:**
- Modify: `app/components/admin/settings_form_component.html.erb` (bug 2)
- Modify: `app/components/admin/tree_node_component.{rb,html.erb}`, `tree_component.html.erb` (bug 3)
- Modify: `app/views/admin/pages/index.html.erb` (bug 4)
- Modify: `app/components/admin/media_library/detail_component.{rb,html.erb}` (bug 7)
- Tests: `test/components/admin/tree_component_test.rb`, `test/components/admin/media_library/detail_component_test.rb`, `test/controllers/admin/pages_controller_test.rb`, a settings form component test

- [ ] **Step 1: Bug 2, failing test** (in the settings form's component test, or a new `test/components/admin/settings_form_component_test.rb` rendered the way its preview renders it):

```ruby
test "the retention input is narrow, with its unit beside it and the explanation below as help" do
  render_inline(build_settings_form) # the same construction the preview uses
  assert_selector "input[name$='[trash_retention_days]'].w-18[aria-describedby$='trash_retention_days_help']"
  assert_selector "[id$='trash_retention_days_help']", text: "Items in the trash are deleted for good after this many days. 0 keeps them until you empty the trash."
  assert_no_text "days (0 = never)"
end
```

Fix: input `class: "#{setup_input_class} w-18"` (72px), the word "days" beside it with `whitespace-nowrap`, and the help paragraph (`mt-1 text-sm text-meta`) below with that exact sentence.

- [ ] **Step 2: Bug 3, failing tests** (tree component test):

```ruby
test "a live page shows no status chip; a draft does" do
  render_tree # the helper this test file already uses
  assert_no_selector "li[data-page-id='#{pages(:live_page).id}'] > div .admin-status-chip"
  assert_selector "li[data-page-id='#{pages(:draft_page).id}'] > div .admin-status-chip", text: "Draft"
end

test "a page without children shows no child count" do
  render_tree
  assert_no_selector "li[data-page-id='#{leaf.id}'] > div [data-child-count]"
  assert_selector "li[data-page-id='#{parent.id}'] > div [data-child-count]", text: parent.children.count.to_s
end

test "the full title is available as a tooltip when the row truncates" do
  render_tree
  assert_selector "li[data-page-id='#{leaf.id}'] > div a[title='#{leaf.title}']"
end
```

(Use the fixtures the file already uses for a live page, a draft page, a leaf and a parent.) Fix: `StatusChipComponent.new(status:, at:, hide_live: true)` (done in Task 5 — keep the `<span data-status>` wrapper only when the chip renders); render `[data-child-count]` only when `child_count.positive?`; add `title: title` to the link; the incomplete-translation marker stays (it's hidden when there's nothing incomplete already). The 272px column came with Task 12.

- [ ] **Step 3: Bug 4, failing test** (pages controller test):

```ruby
test "starter pages are offered only while Home is the only page" do
  sign_in_as users(:one)
  Page.where.not(id: Page.roots.first.id).destroy_all
  get admin_pages_path
  assert_select "button", text: "Create starter pages"

  Pages::Save.call(Page.new(parent: Page.roots.first), attributes: { title: "About", slug: "about" })
  get admin_pages_path
  assert_select "button", text: "Create starter pages", count: 0
end
```

(Create the second page the way other tests in that file do. If destroying fixture pages trips FKs, trash-and-purge through the services or use a fresh set-up like `test/support/content_helper.rb` offers.) Fix in `pages/index.html.erb`:

```erb
<%# Offered only while the site is still empty -- Home and nothing else,
    counting kept pages (design pass bug 4: it used to show whenever the
    starter sections were missing, i.e. on every site that had built its
    own pages instead). `StarterContents::Add` still refuses on its own
    when it isn't permitted or the content exists. %>
<% offer_starter_pages = Page.kept.count == 1 && !StarterContent.added?(locale: Locales.default) && StarterContents::Add.new.permitted? %>
```

Keep the existing comment's permission explanation; replace only the part about when it's offered.

- [ ] **Step 4: Bug 7, failing test** (detail component test):

```ruby
test "an image in use explains why it can't be trashed and links to where it's used" do
  render_inline(build_detail(asset: used_asset)) # as the existing tests build it
  assert_selector "button[disabled][aria-describedby='media-trash-help']", text: "Move to trash"
  assert_selector "#media-trash-help.text-dim", text: "In use on 1 page. Remove it there first."
  assert_selector "#media-trash-help a[href='#media-used-on']", text: "See where it's used"
end
```

Fix: the help line under the button uses `text-sm text-dim` (not `text-meta`: the low contrast was the bug), carries `id="media-trash-help"`, ends with the link to the "Used on" list (give that list `id="media-used-on"`), and the button drops its `title` in favour of `aria-describedby`. `in_use_reason` returns whole sentences for each count shape: "In use on 1 page. Remove it there first." / "In use in N places. Remove it there first." — match whatever kinds `usages_summary` distinguishes, one whole string per case.

- [ ] **Step 5: Run** `bin/rails tailwindcss:build`, the four test files, then `bin/rails test`. PASS.

- [ ] **Step 6: Commit.** `git commit -m "fix: retention label, tree row truncation, starter-pages offer, media trash reason"`

---

### Task 15: Bug 5 — the rich-text toolbar

**Files:**
- Modify: `app/components/admin/columns/rich_text_column_component.html.erb` (toolbar markup), `app/javascript/controllers/admin/rich_text_controller.js`, `app/assets/tailwind/admin-rich-text.css`
- Test: `test/components/admin/columns/rich_text_column_component_test.rb`, the existing rich-text system test

**Interfaces:**
- Consumes: `Admin::MenuComponent` (Task 8).
- Produces: toolbar groups in this order, separated by `[role=separator]`: text style (paragraph/heading select) · Bold, Italic, Strike, Code · Bullet list, Numbered list, Quote, Code block · Link · **Insert ▾** (Page link, Image, YouTube, Divider). Every existing button keeps its `data-action` and `aria-label`.

- [ ] **Step 1: Failing test.**

```ruby
test "the toolbar is one non-wrapping row of grouped tools with an Insert menu" do
  render_inline(build_column) # as the existing tests build it
  assert_selector "[role=toolbar].flex-nowrap"
  assert_selector "[role=toolbar] [role=separator]", minimum: 3
  assert_selector "[role=toolbar] [data-controller='admin--menu'] button[aria-haspopup=menu]", text: "Insert"
  %w[Image YouTube].each do |label|
    assert_selector "[role=toolbar] [role=menu] button", text: label, visible: :all
  end
  assert_no_selector "[role=toolbar] > button", text: "Image"
end
```

- [ ] **Step 2: Restructure the toolbar.** Read the current markup and controller first; move the Page-link, Image, YouTube and Divider buttons into a `MenuComponent` (label "Insert ▾"), unchanged otherwise (same `data-action`s, so the controller's handlers are untouched); wrap the rest in groups with `<span role="separator" aria-orientation="vertical" class="mx-1 h-5 w-px bg-line">` between them; toolbar classes `flex flex-nowrap items-center gap-0.5 overflow-x-auto`. In `rich_text_controller.js`: the active-state loop must still find buttons inside the menu (check its selector — if it uses `:scope > button`, widen it to `button[data-command]`), choosing a menu item closes the menu and returns focus to the editor, and the mousedown-keeps-selection handler must cover the menu's buttons too. If the heading control is separate H2/H3 buttons today, leave them as buttons in the first group — don't invent a select.

- [ ] **Step 3: System test.** In the rich-text system test add: open a post editor in a non-default language at 1400px wide (side-by-side reference shown); assert the toolbar is one row — `page.evaluate_script("(() => { const t = document.querySelector('[role=toolbar]'); const tops = new Set(Array.from(t.children).map(c => c.getBoundingClientRect().top)); return tops.size })()") == 1`; open Insert, choose YouTube, assert its popover/dialog opens as before.

- [ ] **Step 4: Run** `bin/rails tailwindcss:build`, the component test, `bin/rails test:system`. PASS.

- [ ] **Step 5: Commit.** `git commit -m "fix: rich-text toolbar stays on one row, with grouped tools and an Insert menu"`

---

### Task 16: Bug 6 — the AI suggestion box

**Files:**
- Modify: `app/components/admin/translation_screen/suggestion_component.{rb,html.erb}`, `app/javascript/controllers/admin/translate_controller.js`, `app/controllers/admin/translations_controller.rb` (pass provider and model to the component)
- Test: `test/components/admin/translation_screen/suggestion_component_test.rb`, `test/controllers/admin/translations_controller_test.rb`, the translate system test

**Interfaces:**
- Produces: `Admin::TranslationScreen::SuggestionComponent.new(input_id:, locale:, suggestion: nil, warnings: [], error: nil, provider: nil, model: nil)`. A plain suggestion renders in an editable `<textarea data-translate-suggestion-text>`; Use applies the textarea's **current** value. Rich-text suggestions stay a rendered preview (editing happens in the editor after Use).

- [ ] **Step 1: Failing tests.**

```ruby
test "a plain suggestion is editable and names the model that wrote it" do
  render_inline(Admin::TranslationScreen::SuggestionComponent.new(input_id: "post_title", locale: "de", suggestion: "Hallo Welt",
    provider: "anthropic", model: "claude-sonnet-5"))
  assert_selector "[data-translation-suggestion].bg-accent-tint"
  assert_selector "textarea[data-translate-suggestion-text][aria-label='Suggested translation']", text: "Hallo Welt"
  assert_text(/suggested by claude-sonnet-5/i)
  assert_selector "button", text: "Use"
  assert_selector "button", text: "Discard"
end

test "without a model name it just says Suggested translation" do
  render_inline(Admin::TranslationScreen::SuggestionComponent.new(input_id: "post_title", locale: "de", suggestion: "Hallo"))
  assert_text(/suggested translation/i)
end

test "the suggestion text is escaped inside the textarea" do
  render_inline(Admin::TranslationScreen::SuggestionComponent.new(input_id: "t", locale: "de", suggestion: "</textarea><script>x</script>"))
  assert_no_selector "script", visible: :all
end
```

- [ ] **Step 2: Implement.** Box: `mt-2 rounded-cs border border-accent bg-accent-tint p-3 text-sm` — rendered directly under the field's input, inside the field wrapper (it already streams to `SuggestionComponent.dom_id(input_id)`; make sure that target sits inside the field's own wrapper, not after the whole row). Header line in the field-label style: "Suggested by <model>" (one string: `"Suggested by #{model}"`) or "Suggested translation". Plain: `text_area_tag nil, suggestion, rows: [ suggestion.to_s.lines.count, 2 ].max, class: "#{setup_input_class} mt-1", data: { translate_suggestion_text: true }, aria: { label: "Suggested translation" }` (no `name`, so it never feeds autosave). `use_data` no longer carries `translate_text` for plain suggestions. In `translate_controller.js#use`: for `kind === "plain"` read the text from `button.closest("[data-translation-suggestion]").querySelector("[data-translate-suggestion-text]").value`. The controller passes `provider: AI.provider_name, model: AI.model` (use the real readers on `AI`). The model name is configuration, not a secret; never render anything about the key.

- [ ] **Step 3: System test.** In the translate system test: request a suggestion (stub provider), edit the textarea to "Edited by hand", press Use, assert the field's input now holds "Edited by hand" and the autosave indicator reports saved; reload and assert it persisted.

- [ ] **Step 4: Run** `bin/rails tailwindcss:build`, the three test files. PASS.

- [ ] **Step 5: Commit.** `git commit -m "fix: AI suggestions appear inside the field, editable, with the model name"`

---

### Task 17: Mind graph layout bug

**Files:**
- Modify: `app/views/admin/mind_graph/show.html.erb`, `app/javascript/controllers/admin/mind_graph_controller.js`
- Test: `test/system/mind_graph_test.rb` (create if absent)

**Interfaces:**
- Produces: the graph box is `max-w-[960px]`, `h-[560px]`, `overflow-hidden`; every node's centre stays within the SVG's box at all times, including while dragging and after a resize.

- [ ] **Step 1: Failing system test.**

```ruby
require "application_system_test_case"

class MindGraphTest < ApplicationSystemTestCase
  test "the graph keeps to its box and every node stays inside it" do
    sign_in_via_form users(:one)
    visit admin_mind_graph_path
    assert_selector "svg[data-admin--mind-graph-target=svg] circle"
    sleep 1.5 # let the force simulation settle; there is no DOM signal for "cooled down"
    result = page.evaluate_script(<<~JS)
      (() => {
        const svg = document.querySelector("svg[data-admin--mind-graph-target=svg]")
        const box = svg.getBoundingClientRect()
        const outside = Array.from(svg.querySelectorAll("circle")).filter((c) => {
          const r = c.getBoundingClientRect()
          return r.left < box.left - 1 || r.right > box.right + 1 || r.top < box.top - 1 || r.bottom > box.bottom + 1
        }).length
        return { width: box.width, outside }
      })()
    JS
    assert_operator result["width"], :<=, 960
    assert_equal 0, result["outside"]
  end
end
```

(Needs at least two related posts in fixtures; if the fixtures have none, relate two in the test's setup the way the related-posts tests do.)

- [ ] **Step 2: Fix.** View: wrap in `class="max-w-[960px] overflow-hidden rounded-cs border border-line bg-surface"`, SVG `class="block h-[560px] w-full text-ink"`. Controller: in `tick()`, clamp each node before drawing —

```js
    // Keep every node inside the box (design pass round 1): forceCenter
    // only centres the *mean* position, so a strongly repelled or dragged
    // node could drift, or be flung, past the edge -- and the box used to
    // fill the whole content column, so "past the edge" was off-screen.
    const pad = 16
    for (const node of this.nodes) {
      node.x = Math.max(pad, Math.min(this.width - pad, node.x))
      node.y = Math.max(pad, Math.min(this.height - pad, node.y))
    }
```

store `this.width`/`this.height` where the simulation is built, clamp `fx`/`fy` the same way in the drag handler, and add a `ResizeObserver` on the SVG that updates `width`/`height`, re-centres (`forceCenter(width / 2, height / 2)`) and reheats (`alpha(0.3).restart()`); disconnect it in `disconnect()`. Add `forceX(width / 2).strength(0.04)` and `forceY(height / 2).strength(0.04)` only if `d3-force`'s vendored build exports them (check the import line); otherwise the clamp alone is the fix.

- [ ] **Step 3: Run** the system test: PASS. Delete the memory note's entry only after the user confirms the fix on screen (not part of this plan).

- [ ] **Step 4: Commit.** `git commit -m "fix: mind graph keeps to its box and keeps its nodes inside"`

---

### Task 18: Bug 8 — sign-in, password reset and the setup wizard

**Files:**
- Modify: `app/views/layouts/product.html.erb`, `app/views/layouts/setup.html.erb`
- Modify: `app/views/admin/sessions/new.html.erb`, `app/views/admin/passwords/{new,edit}.html.erb`, `app/views/setup/*.html.erb`, `app/helpers/setup_helper.rb`
- Test: `test/controllers/admin/sessions_controller_test.rb`, `test/controllers/admin/passwords_controller_test.rb`, `test/controllers/setup_controller_test.rb`, `test/application_system_test_case.rb` (`sign_in_via_form` labels), `test/system/setup_test.rb`

**Interfaces:**
- Consumes: `Admin::ThemeSwitchComponent`, `Admin::PasswordFieldComponent`, `Admin::ErrorSummaryComponent`, `Admin::ButtonComponent`, `.cs-select`, `Admin::FileDropComponent`.
- Produces: `sign_in_via_form` fills "Email" and "Password" (labels, not placeholders). Reset states: request, sent, form, expired.

- [ ] **Step 1: Failing tests.**

```ruby
# sessions_controller_test.rb
test "sign-in uses the product shell: wordmark, theme switch, labelled fields, token button" do
  get admin_sign_in_path
  assert_select "header a", text: "Content·Spiel"
  assert_select "[role=radiogroup][aria-label='Theme']"
  assert_select "label[for=email_address]", text: "Email"
  assert_select "label[for=password]", text: "Password"
  assert_select "button.bg-accent", text: "Sign in"
  assert_select "a", text: "Forgot your password?"
  assert_no_match(/bg-blue|rounded-(md|lg|xl)/, response.body)
end

# passwords_controller_test.rb
test "after a reset request the page says the same thing whether or not the account exists" do
  post admin_password_path, params: { email_address: users(:one).email_address }
  follow_redirect!
  known = css_select("main").text.squish
  post admin_password_path, params: { email_address: "nobody@example.com" }
  follow_redirect!
  assert_equal known, css_select("main").text.squish
  assert_match "If that address belongs to an account, we've sent a link. It expires in 15 minutes.", known
end

test "an expired or invalid reset link shows the expired state with a way to ask again" do
  get admin_edit_password_path(token: "not-a-token")
  follow_redirect! if response.redirect?
  assert_select "h1", text: "This link has expired"
  assert_select "a", text: "Send a new link"
end

test "the reset form uses the password field with the meter" do
  get admin_edit_password_path(token: users(:one).password_reset_token)
  assert_select "[data-controller='password-field'] [data-password-field-target=bar]", count: 4
end
```

(Adapt route helper names to `config/routes.rb`: `admin_password_path`, `admin_edit_password_path`.)

- [ ] **Step 2: Product layout** per `Studio Sign In.dc.html`: header `flex items-center justify-between px-7 py-5` with the 12px wordmark (`font-cs-mono text-xs uppercase tracking-wide`) linking to the sign-in page and the theme switch at the right, no rule under it; `main` a centred `max-w-sm` column, vertical centre on tall screens (`min-h-[calc(100vh-64px)] flex items-center`), the form in a `rounded-cs border border-line bg-surface p-6` card.

- [ ] **Step 3: Sign-in** : `h1` "Sign in" (`text-h2 font-semibold`), real `<label>`s in the field-label style ("Email", "Password") with `setup_input_class` inputs (placeholders removed — the old placeholders were the accessible names), password via `PasswordFieldComponent` (no meter, `autocomplete: "current-password"`), full-width primary button, "Forgot your password?" link below; a failed sign-in shows one `role="alert"` line in a `bg-danger-tint text-danger-ink` box above the form with the existing message. Update `sign_in_via_form` to `fill_in "Email"` / `fill_in "Password"`.

- [ ] **Step 4: Password reset** per `Studio Password Reset.dc.html`, four states: **request** (email field, "Send reset link", and the hint "No outgoing mail on this site? Ask an owner to set a new password for you, or run `bin/rails users:reset_password` on the server." — use the console command the setup wizard decisions actually ship; `grep -rn "reset" lib/tasks`); **sent** (the neutral sentence from the test; reached by redirect with a param or flash, never by rendering differently for known addresses); **form** (new password with meter + confirmation, submit `data-password-submit`); **expired** (`h1` "This link has expired", body "Reset links work for 15 minutes and only once.", link "Send a new link"). Don't change the controller's token logic or rate limits; only what each outcome renders.

- [ ] **Step 5: Setup wizard** per `Setup Wizard.dc.html`: the same header as sign-in; the step list as a left column of numbered steps (current `text-ink font-medium` with `aria-current="step"`, done steps with a "✓" and `text-dim`, optional marked in mono); each step's form restyled with field-label labels, `setup_input_class` inputs, `.cs-select` selects, `FileDropComponent` for the logo, `PasswordFieldComponent` with the meter on the admin step, `ErrorSummaryComponent` in place of `setup/_errors`, toasts not used here (keep `setup/_flash` but restyle it as an inline `bg-ok-tint`/`bg-danger-tint` box). Buttons: primary "Continue", ghost "Skip" on optional steps, "Back" as a text link. No step is added, removed or reordered, and no field's `name` changes.

- [ ] **Step 6: Tests.** Run the three controller test files and `test/system/setup_test.rb`; update selectors pinned to old copy or placeholders. Add to the setup system test: on the admin step, typing an 8-character password leaves "Continue" disabled and shows "Use at least 12 characters."; a 14-character one enables it.

- [ ] **Step 7: Run** `bin/rails tailwindcss:build`, `bin/rails test`, `bin/rails test:system`. PASS.

- [ ] **Step 8: Commit.** `git commit -m "feat: sign-in, password reset and setup wizard rebuilt with the tokens"`

---

### Task 19: Sweep, docs and visual check

**Files:**
- Modify: `CLAUDE.md`, `docs/roadmap.md`
- Create: `test/lib/admin_design_rules_test.rb`

- [ ] **Step 1: Guard tests for the rules that are easy to break later.**

```ruby
require "test_helper"

# Design pass spec §3: tokens only, red only for destruction and failure,
# and none of the namespaces that shadow top-level modules.
class AdminDesignRulesTest < ActiveSupport::TestCase
  ADMIN_SOURCES = Dir[Rails.root.join("app/{views/admin,views/layouts,views/setup,components/admin,javascript/controllers}/**/*.{erb,rb,js}")]

  test "no raw hex colours and no dark: colour variants in CS Studio" do
    offenders = ADMIN_SOURCES.select do |path|
      source = File.read(path)
      source.match?(/#[0-9a-fA-F]{6}\b/) || source.match?(/\bdark:(bg|text|border|ring|fill|stroke)-/)
    end
    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  test "translation chips and language tabs never use the danger colour" do
    %w[app/components/admin/translation_chip_component.rb app/components/admin/language_tabs_component.html.erb].each do |path|
      assert_no_match(/danger/, Rails.root.join(path).read, path)
    end
  end

  test "the replaced components are gone" do
    %w[status_badge_component.rb language_switcher_component.rb flash_component.rb translation_screen/state_badge_component.rb].each do |file|
      assert_not Rails.root.join("app/components/admin", file).exist?, file
    end
    assert_not Rails.root.join("app/views/shared/_theme_toggle.html.erb").exist?
  end
end
```

Run it; fix whatever it finds (`dark:scheme-dark` is not a colour variant and is allowed by the regexp; an SVG icon's `stroke="currentColor"` is fine).

- [ ] **Step 2: Whole suite.** `bin/rails test`, `bin/rails test:system`, `bin/rubocop`, `bin/brakeman`, `bin/importmap audit` — all green. Run `test/integration/public_javascript_test.rb` specifically: the new `admin/*` controllers must be `preload: "admin"` and absent from public pages, while `password_field_controller.js` and `theme_controller.js` load on sign-in.

- [ ] **Step 3: Visual check.** Start `bin/rails tailwindcss:build && bin/rails theme_css:build && bin/rails server`, sign in as the seeded owner (`admin@example.com` / the seed password), and open each of the 33 screens from `tmp/screenshots/cs-studio/` in light and dark, at 1400px and at 1100px wide. For each: the sidebar groups, account block and theme switch are right; chips, tabs, dialogs, toasts, selects and empty states are the shared ones; nothing overflows horizontally; the eight bugs are gone. Write what doesn't match its mockup into the PR description under "Known differences" (layout changes belong to rounds 2 and 3 and are expected).

- [ ] **Step 4: CLAUDE.md.** Add a "CS Studio design system" subsection under "Admin (CS Studio)" covering: the handoff location and that spec beats handoff; the shared components and what each replaced; the three-way theme (`cs-theme`, `data-theme-choice`); the shell (`MODULES` `group:`, `trash_badge_count`, drawers and their breakpoints, in-layout 403/404); `Pagination`; toasts and `flash[:undo]`; the dialog controller and "no inline handlers" (`test/lib/inline_handlers_test.rb`); the save rule (autosave / save bar / instant); ⌘K (`Jump::Search`, titles only); `users.name`/`display_name`/`Users::UpdateProfile`; `colour_index`; the 12-character password rule; and `test/lib/admin_design_rules_test.rb`. Update the sentences that describe things this round changed (the language switcher, `Admin::FlashComponent`, `Admin::ConfirmDialogComponent`, the 403 page, "prints the user's **email** (`User` has no name column)").

- [ ] **Step 5: Roadmap.** In `docs/roadmap.md`: mark the tree-column/narrow-screen interim state resolved by round 1 (posts pagination still open until round 2); strike the mind-graph layout row as resolved; note round 1 as done in the design-pass row.

- [ ] **Step 6: Commit.** `git commit -m "docs: CS Studio design system notes; guard the design rules"`

---

## Self-review notes

- **Spec §6 coverage:** tokens and theme → Task 1; shell, account block, Trash badge, ⌘K, top bar and drawers, 403/404 → Tasks 12–13; every §4 row → Tasks 1 (theme), 3 (type dot), 4 (password field), 5 (chips), 6 (tabs), 7 (dialog), 8 (toast, menus, busy), 9 (pagination, filters, dates, empty state), 10 (form controls, validation), 11 (save bar, drag), 12 (sidebar, narrow screens, 403/404); `users.name` → Task 2; `colour_index` → Task 3; bugs 1 → Task 10, 2/3/4/7 → Task 14, 5 → Task 15, 6 → Task 16, 8 → Task 18 (with §5.5 in Task 4); mind-graph layout → Task 17.
- **Deferred by the spec, not by this plan:** the chip input with autocomplete (§4 "Form controls") is built in round 2 with the tags and related-posts fields that use it; "pending suggestion box" and "upload progress on a tile" (§4 "Busy and pending") land with the editor (round 2) and Media (round 3). Round 1 ships the busy button. Side-by-side translation stacking under 880px is round 2 (editor body).
- **Order matters:** Tasks 1–4 are independent. 5–6 before 12–14 (chips in tree and palette). 7 before 8, 11, 13. 8 before 6's menu restyle step, 11, 15. 12 before 13.
