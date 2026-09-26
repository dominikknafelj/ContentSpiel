# Setup Wizard & Design Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Content·Spiel's design tokens (light/dark) and a token-gated, browser-only setup wizard that takes a fresh install from an empty database to a working site plus admin login.

**Architecture:** PR 1 adds the Claude Design token CSS (self-hosted fonts, Tailwind v4 `@theme inline`) and a `data-theme` light/dark switch without restyling existing pages. PR 2 adds a `setup_completed_at` flag on `SiteSetting`, a route-level redirect into `/setup` while setup is required, a `SetupController` with eight steps backed by small POROs (`Setup`, `Setup::Token`, `Setup::SystemCheck`, `StarterContent`), and Avo counterparts for everything the wizard sets.

**Tech Stack:** Rails 8.1.3.1, Ruby 3.4.9, PostgreSQL, Minitest + fixtures, Hotwire (Stimulus via import maps), Tailwind v4 (`tailwindcss-rails`), Propshaft, Avo 4.2.4 (Community), Active Storage + `ruby-vips`, Solid Queue.

**Spec:** `docs/superpowers/specs/2026-09-26-setup-wizard-design.md` (supersedes §11 of `docs/superpowers/specs/2026-09-13-contentspiel-design.md`).

## Global Constraints

- No new gems. Everything uses what's already in `Gemfile`.
- Minitest + fixtures only — no RSpec, no factories, no Devise, no mocking library (Minitest 6 has no `stub`; make collaborators injectable instead).
- JS is import maps + Stimulus only; controllers in `app/javascript/controllers/*_controller.js` are auto-registered.
- **Theme boundary:** do not restyle public views (`app/views/pages/`, `app/views/content_blocks/`, `app/views/layouts/application.html.erb` body). Only product UI (setup wizard, sign-in, Avo) uses the tokens explicitly.
- The raw MCP token and the setup token are never written to the session, flash, or logs — except the setup token's own boot log line.
- Match the codebase's comment convention: non-obvious invariants get a short explanatory comment (CLAUDE.md "Long, load-bearing code comments").
- Commit messages: conventional (`feat|fix|ref|style|docs|test|chore`), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Feature work goes through PRs; the user merges. **PR 1 must be merged before starting PR 2.**
- Sandbox note (this dev machine only): run the full suite as `PARALLEL_WORKERS=1 bin/rails test` (forked parallel workers hang here; CI is unaffected). If `bin/rails db:migrate` hangs, use `bin/rails runner 'ActiveRecord::Base.connection_pool.migration_context.migrate'` and then `bin/rails runner 'ActiveRecord::Tasks::DatabaseTasks.dump_schema(ActiveRecord::Base.connection_db_config)'`.

## Review Focus

1. **Existing install with users but no `site_settings` row** (the row is created lazily) must not be redirected into the wizard → the migration inserts a completed row. Test: Task 4.
2. **Setup token pasted with surrounding whitespace/newline** (copied from a log line) must be accepted; an empty token rejected. Test: Task 5.
3. **Admin closes the browser mid-way, signs in later** → lands back on the step they asked for, not in Avo. Test: Task 9.
4. **Repeated wrong tokens** → locked out for 3 minutes even if the next attempt is correct; the in-memory rate-limit store must be cleared between tests or unrelated tests start failing. Test: Task 9.
5. **Half-filled social link rows** (a name with no URL) are dropped rather than saved as broken links, and a blank site title is rejected. Test: Task 11.

---

## File Structure

**PR 1 — design tokens**

| File | Responsibility |
|---|---|
| `app/assets/fonts/*.woff2` (6 files) | Self-hosted Archivo 400/500/600/700 + IBM Plex Mono 400/500 |
| `app/assets/tailwind/content-spiel.css` | Raw tokens (`--cs-*`), light + dark values, `@font-face` |
| `app/assets/tailwind/content-spiel.tailwind.css` | Maps tokens into Tailwind `@theme inline` + `dark:` variant |
| `app/assets/tailwind/application.css` | Tailwind entry; imports the two files above |
| `app/views/shared/_theme_head.html.erb` | Inline pre-paint script setting `data-theme` |
| `app/views/shared/_theme_toggle.html.erb` | Light/dark toggle button |
| `app/javascript/controllers/theme_controller.js` | Toggles and persists the theme |
| `app/views/layouts/application.html.erb` | Renders the theme head partial |
| `app/views/sessions/new.html.erb` | Hosts the toggle (product UI) |
| `test/integration/design_tokens_test.rb`, `test/system/theme_toggle_test.rb` | Tests |

**PR 2 — setup wizard**

| File | Responsibility |
|---|---|
| `db/migrate/20260926120000_add_setup_completed_at_to_site_settings.rb` | Column + backfill for existing installs |
| `app/models/setup.rb` | `Setup.required?`, `Setup.complete!` |
| `app/models/setup/token.rb` | Derived/overridable setup token, constant-time check |
| `app/models/setup/system_check.rb` | Four read-only environment checks with injectable probes |
| `app/models/setup/redirect_constraint.rb` | Route constraint: redirect to `/setup` while required |
| `app/models/starter_content.rb` | Idempotent Home page, starter pages and sample posts |
| `config/initializers/setup_token.rb` | Prints the setup token at boot while setup is required |
| `app/controllers/setup_controller.rb` | Step routing, access gate, per-step updates |
| `app/helpers/setup_helper.rb` | Shared class strings + language names for wizard views |
| `app/views/layouts/setup.html.erb`, `app/views/setup/*` | Wizard layout and step views |
| `app/avo/actions/create_starter_pages.rb`, `app/views/avo/tools/system_status.html.erb`, `app/views/avo/sidebar/items/_system_status.html.erb` | Backend counterparts |
| `test/fixtures/site_settings.yml`, `test/test_helpers/setup_test_helper.rb` | Test support |

---

# Part 1 — PR 1: Design tokens & light/dark

Start from an up-to-date `main`: `git checkout main && git pull --ff-only && git checkout -b design-tokens`.

### Task 1: Token CSS and self-hosted fonts

**Files:**
- Create: `app/assets/fonts/archivo-latin-{400,500,600,700}-normal.woff2`, `app/assets/fonts/ibm-plex-mono-latin-{400,500}-normal.woff2`
- Create: `app/assets/tailwind/content-spiel.css`, `app/assets/tailwind/content-spiel.tailwind.css`
- Modify: `app/assets/tailwind/application.css`
- Test: `test/integration/design_tokens_test.rb`

**Interfaces:**
- Produces: Tailwind utilities `bg-paper bg-surface bg-sunken text-ink text-dim text-meta border-line border-line-strong bg-accent hover:bg-accent-hover bg-accent-tint text-on-accent {bg,text,border}-{ok,warn,danger}[-ink|-tint] font-cs font-cs-mono text-display text-h1 text-h2 text-label tracking-mono tracking-wide rounded-cs shadow-menu ease-cs`, and a `dark:` variant keyed on `[data-theme=dark]`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/design_tokens_test.rb
require "test_helper"

# The Content·Spiel design tokens (design spec 2026-09-26 §2) ship as plain CSS
# variables mapped into Tailwind's @theme -- these check the compiled
# stylesheet actually carries them and that Propshaft rewrote the
# self-hosted font URLs to digested asset paths (an unrewritten relative URL
# would 404 in production and silently fall back to system-ui).
class DesignTokensTest < ActionDispatch::IntegrationTest
  test "the compiled stylesheet carries the light and dark token values" do
    get helpers.asset_path("tailwind.css")

    assert_response :success
    assert_includes response.body, "--cs-paper"
    assert_includes response.body, "--cs-accent"
    assert_match(/data-theme=["']?dark/, response.body)
  end

  test "the stylesheet points at the digested font files, which are served" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    get helpers.asset_path("tailwind.css")
    assert_includes response.body, font_path

    get font_path
    assert_response :success
  end

  private
    def helpers = ActionController::Base.helpers
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/design_tokens_test.rb`
Expected: FAIL — `--cs-paper` not in the stylesheet; `asset_path("archivo-…")` raises `Propshaft::MissingAssetError` (or returns an undigested path that 404s).

- [ ] **Step 3: Download the fonts** (open-source, OFL; same files Claude Design used)

```bash
mkdir -p app/assets/fonts
for w in 400 500 600 700; do
  curl -fsSL -o app/assets/fonts/archivo-latin-$w-normal.woff2 \
    https://cdn.jsdelivr.net/npm/@fontsource/archivo@5/files/archivo-latin-$w-normal.woff2
done
for w in 400 500; do
  curl -fsSL -o app/assets/fonts/ibm-plex-mono-latin-$w-normal.woff2 \
    https://cdn.jsdelivr.net/npm/@fontsource/ibm-plex-mono@5/files/ibm-plex-mono-latin-$w-normal.woff2
done
ls -la app/assets/fonts   # expect 6 non-empty .woff2 files
```

- [ ] **Step 4: Add the token files**

`app/assets/tailwind/content-spiel.css` — from Claude Design's `content-spiel.css`, with font URLs changed to bare filenames (Propshaft resolves them against `app/assets/fonts/` and rewrites them to digested paths):

```css
/* Content·Spiel product tokens (Claude Design project "Content Spiel design
   system"). Theme switches on [data-theme] on <html>; see
   app/views/shared/_theme_head.html.erb. Font URLs are bare filenames on
   purpose: Propshaft resolves them against app/assets/fonts and rewrites
   them to digested /assets/... paths. */
@font-face{font-family:"Archivo";font-weight:400;font-display:swap;src:url("archivo-latin-400-normal.woff2") format("woff2")}
@font-face{font-family:"Archivo";font-weight:500;font-display:swap;src:url("archivo-latin-500-normal.woff2") format("woff2")}
@font-face{font-family:"Archivo";font-weight:600;font-display:swap;src:url("archivo-latin-600-normal.woff2") format("woff2")}
@font-face{font-family:"Archivo";font-weight:700;font-display:swap;src:url("archivo-latin-700-normal.woff2") format("woff2")}
@font-face{font-family:"IBM Plex Mono";font-weight:400;font-display:swap;src:url("ibm-plex-mono-latin-400-normal.woff2") format("woff2")}
@font-face{font-family:"IBM Plex Mono";font-weight:500;font-display:swap;src:url("ibm-plex-mono-latin-500-normal.woff2") format("woff2")}

:root, [data-theme="light"] {
  color-scheme: light;
  --cs-paper: #f5f4f0;
  --cs-surface: #ffffff;
  --cs-sunken: #ecebe6;
  --cs-ink: #141417;
  --cs-dim: #55565b;
  --cs-meta: #6c6d72;
  --cs-line: rgba(20,20,23,0.10);
  --cs-line-strong: rgba(20,20,23,0.20);
  --cs-accent: oklch(0.50 0.12 250);
  --cs-accent-hover: oklch(0.45 0.12 250);
  --cs-accent-tint: oklch(0.95 0.025 250);
  --cs-on-accent: #ffffff;
  --cs-ok: oklch(0.52 0.12 150);
  --cs-ok-ink: oklch(0.42 0.11 150);
  --cs-ok-tint: oklch(0.95 0.04 150);
  --cs-warn: oklch(0.55 0.12 70);
  --cs-warn-ink: oklch(0.45 0.11 70);
  --cs-warn-tint: oklch(0.95 0.05 80);
  --cs-danger: oklch(0.53 0.19 25);
  --cs-danger-ink: oklch(0.42 0.15 25);
  --cs-danger-tint: oklch(0.96 0.03 25);
  --cs-ph-a: #dddbd3;
  --cs-ph-b: #c9c7bd;
  --cs-shadow-menu: 0 12px 32px rgba(20,20,23,0.12);
}

[data-theme="dark"] {
  color-scheme: dark;
  --cs-paper: #0f1012;
  --cs-surface: #17181b;
  --cs-sunken: #212226;
  --cs-ink: #ededee;
  --cs-dim: #a9aaaf;
  --cs-meta: #8e8f95;
  --cs-line: rgba(237,237,238,0.09);
  --cs-line-strong: rgba(237,237,238,0.18);
  --cs-accent: oklch(0.74 0.10 250);
  --cs-accent-hover: oklch(0.80 0.09 250);
  --cs-accent-tint: oklch(0.28 0.05 250);
  --cs-on-accent: #0f1012;
  --cs-ok: oklch(0.70 0.13 150);
  --cs-ok-ink: oklch(0.80 0.12 150);
  --cs-ok-tint: oklch(0.28 0.05 150);
  --cs-warn: oklch(0.76 0.13 70);
  --cs-warn-ink: oklch(0.84 0.11 75);
  --cs-warn-tint: oklch(0.30 0.05 70);
  --cs-danger: oklch(0.68 0.17 25);
  --cs-danger-ink: oklch(0.80 0.12 25);
  --cs-danger-tint: oklch(0.29 0.06 25);
  --cs-ph-a: #2a2b2f;
  --cs-ph-b: #1c1d20;
  --cs-shadow-menu: 0 12px 32px rgba(0,0,0,0.5);
}

:root {
  --cs-font: "Archivo", system-ui, sans-serif;
  --cs-mono: "IBM Plex Mono", ui-monospace, monospace;
  --cs-t-display: clamp(34px, 5vw, 60px);
  --cs-t-h1: 28px; --cs-t-h2: 20px; --cs-t-h3: 15px;
  --cs-t-body: 15px; --cs-t-small: 13px; --cs-t-label: 11px;
  --cs-track-mono: 0.14em; --cs-track-wide: 0.18em;
  --cs-sp-1: 4px; --cs-sp-2: 8px; --cs-sp-3: 14px; --cs-sp-4: 22px;
  --cs-sp-5: 34px; --cs-sp-6: 54px; --cs-sp-7: 80px;
  --cs-radius: 2px; --cs-radius-pill: 999px;
  --cs-ease: cubic-bezier(0.22, 1, 0.36, 1);
}
```

`app/assets/tailwind/content-spiel.tailwind.css`:

```css
/* Maps the --cs-* tokens into Tailwind v4. `inline` makes utilities
   reference the runtime variables directly, so every utility flips with
   [data-theme] on <html> alone -- no dark: classes needed for colours. */
@import "./content-spiel.css";

@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));

@theme inline {
  --color-paper: var(--cs-paper);
  --color-surface: var(--cs-surface);
  --color-sunken: var(--cs-sunken);
  --color-ink: var(--cs-ink);
  --color-dim: var(--cs-dim);
  --color-meta: var(--cs-meta);
  --color-line: var(--cs-line);
  --color-line-strong: var(--cs-line-strong);
  --color-accent: var(--cs-accent);
  --color-accent-hover: var(--cs-accent-hover);
  --color-accent-tint: var(--cs-accent-tint);
  --color-on-accent: var(--cs-on-accent);
  --color-ok: var(--cs-ok);
  --color-ok-ink: var(--cs-ok-ink);
  --color-ok-tint: var(--cs-ok-tint);
  --color-warn: var(--cs-warn);
  --color-warn-ink: var(--cs-warn-ink);
  --color-warn-tint: var(--cs-warn-tint);
  --color-danger: var(--cs-danger);
  --color-danger-ink: var(--cs-danger-ink);
  --color-danger-tint: var(--cs-danger-tint);
  --font-cs: var(--cs-font);
  --font-cs-mono: var(--cs-mono);
  --text-display: var(--cs-t-display);
  --text-h1: var(--cs-t-h1);
  --text-h2: var(--cs-t-h2);
  --text-label: var(--cs-t-label);
  --tracking-mono: var(--cs-track-mono);
  --tracking-wide: var(--cs-track-wide);
  --radius-cs: var(--cs-radius);
  --shadow-menu: var(--cs-shadow-menu);
  --ease-cs: var(--cs-ease);
}
```

`app/assets/tailwind/application.css` (replace the whole file):

```css
@import "tailwindcss";
@import "./content-spiel.tailwind.css";
```

Note: the fonts deliberately get their own keys (`font-cs`, `font-cs-mono`) instead of overriding Tailwind's `--font-sans`/`--font-mono`. Overriding those would change Preflight's `--default-font-family` and restyle every public page, which spec §2 ("no restyle") and the theme boundary forbid. Product UI opts in with `font-cs` / `font-cs-mono`.

- [ ] **Step 5: Rebuild and run the test**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/design_tokens_test.rb`
Expected: PASS (2 runs). If the font assertion fails because the URL wasn't rewritten, check `app/assets/builds/tailwind.css` for `url("archivo-latin-400-normal.woff2")` — Propshaft only rewrites URLs whose file exists under an asset load path; confirm `app/assets/fonts` contains the file.

- [ ] **Step 6: Commit**

```bash
git add app/assets/fonts app/assets/tailwind test/integration/design_tokens_test.rb
git commit -m "$(cat <<'EOF'
feat: add Content·Spiel design tokens and self-hosted fonts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 2: Light/dark switch

**Files:**
- Create: `app/views/shared/_theme_head.html.erb`, `app/views/shared/_theme_toggle.html.erb`, `app/javascript/controllers/theme_controller.js`
- Modify: `app/views/layouts/application.html.erb` (head), `app/views/sessions/new.html.erb` (top of the container)
- Test: `test/integration/design_tokens_test.rb` (add one test), `test/system/theme_toggle_test.rb`

**Interfaces:**
- Consumes: token CSS from Task 1.
- Produces: partials `shared/theme_head` (render inside every product `<head>` before stylesheets) and `shared/theme_toggle` (a button labelled "Dark mode"/"Light mode"); `localStorage` key `cs-theme` with values `light`/`dark`.

- [ ] **Step 1: Write the failing tests**

Append to `test/integration/design_tokens_test.rb` (inside the class, above `private`):

```ruby
  test "pages set the theme before first paint" do
    get new_session_path

    assert_includes response.body, 'localStorage.getItem("cs-theme")'
    assert_includes response.body, 'data-controller="theme"'
  end
```

```ruby
# test/system/theme_toggle_test.rb
require "application_system_test_case"

class ThemeToggleTest < ApplicationSystemTestCase
  test "the toggle switches to dark and the choice survives a reload" do
    visit new_session_path
    assert_equal "light", current_theme

    click_on "Dark mode"
    assert_equal "dark", current_theme

    visit new_session_path
    assert_equal "dark", current_theme
    assert_button "Light mode"
  end

  private
    def current_theme = page.evaluate_script("document.documentElement.dataset.theme")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/design_tokens_test.rb && bin/rails test:system TEST=test/system/theme_toggle_test.rb`
Expected: FAIL — script not in body; `current_theme` is `nil`; no "Dark mode" button.

- [ ] **Step 3: Implement**

`app/views/shared/_theme_head.html.erb`:

```erb
<%# Runs before the stylesheet paints anything: an explicit choice stored by
    theme_controller.js wins, otherwise the OS preference. localStorage can
    throw (private windows, blocked site data), so reading it is guarded and
    the page still renders -- in the OS theme -- without it. %>
<script>
  (function () {
    var stored = null;
    try { stored = localStorage.getItem("cs-theme"); } catch (e) {}
    var prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    document.documentElement.dataset.theme =
      stored === "light" || stored === "dark" ? stored : (prefersDark ? "dark" : "light");
  })();
</script>
```

`app/views/shared/_theme_toggle.html.erb`:

```erb
<button type="button" data-controller="theme" data-action="theme#toggle"
  class="rounded-cs border border-line-strong px-3 py-1 font-cs-mono text-label uppercase tracking-mono text-dim hover:bg-sunken">
  <span data-theme-target="label">Dark mode</span>
</button>
```

`app/javascript/controllers/theme_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Flips data-theme on <html> (the token CSS keys every colour off it) and
// remembers the choice; app/views/shared/_theme_head.html.erb re-applies it
// before first paint on the next full page load.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    this.render()
  }

  toggle() {
    const next = this.current === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    try { localStorage.setItem("cs-theme", next) } catch (e) {}
    this.render()
  }

  get current() {
    return document.documentElement.dataset.theme
  }

  render() {
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.current === "dark" ? "Light mode" : "Dark mode"
    }
  }
}
```

In `app/views/layouts/application.html.erb`, add directly after `<%= csp_meta_tag %>`:

```erb
    <%= render "shared/theme_head" %>
```

In `app/views/sessions/new.html.erb`, add as the first child inside `<div class="mx-auto md:w-2/3 w-full">`:

```erb
  <div class="mb-6 flex justify-end"><%= render "shared/theme_toggle" %></div>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/design_tokens_test.rb && bin/rails test:system TEST=test/system/theme_toggle_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/shared app/javascript/controllers/theme_controller.js app/views/layouts/application.html.erb app/views/sessions/new.html.erb test/integration/design_tokens_test.rb test/system/theme_toggle_test.rb
git commit -m "$(cat <<'EOF'
feat: add light/dark theme switch driven by data-theme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 3: Verify and open PR 1

- [ ] **Step 1: Full verification**

Run each; all must be clean:
```bash
PARALLEL_WORKERS=1 bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman -q --no-pager
bin/importmap audit
```

- [ ] **Step 2: Manual check** — `bin/dev`, open http://localhost:3000/session/new, toggle Dark mode, reload, confirm the choice persists and fonts load (DevTools Network: `archivo-latin-*.woff2` → 200).

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin design-tokens
gh pr create --title "Add design tokens and light/dark switch" --body "$(cat <<'EOF'
## Summary
- Content·Spiel design tokens from Claude Design (light + dark), mapped into Tailwind v4 `@theme inline`
- Self-hosted Archivo + IBM Plex Mono (Propshaft-digested)
- `data-theme` light/dark switch: OS preference by default, explicit choice persisted, applied before first paint
- No restyle of existing pages (spec 2026-09-26 §2); public site only picks up the new default font

## Test plan
- [ ] `bin/rails test` / `bin/rails test:system` green
- [ ] Toggle on /session/new persists across reloads; fonts load

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
```

- [ ] **Step 4: Wait for the user to merge**, then `git checkout main && git pull --ff-only && git branch -d design-tokens && git push origin --delete design-tokens`.

---

# Part 2 — PR 2: Setup wizard & backend settings

Start: `git checkout main && git pull --ff-only && git checkout -b setup-wizard`.

### Task 4: Setup state (`setup_completed_at`)

**Files:**
- Create: `db/migrate/20260926120000_add_setup_completed_at_to_site_settings.rb`, `app/models/setup.rb`, `test/fixtures/site_settings.yml`, `test/models/setup_test.rb`
- Modify: `db/schema.rb` (generated), `app/models/site_setting.rb`, `test/models/site_setting_test.rb`, `db/seeds.rb`

**Interfaces:**
- Produces: `Setup.required? -> Boolean`; column `site_settings.setup_completed_at`; fixture `site_settings(:default)` (completed); `SiteSetting` validates `title` presence. (`Setup.complete!` is added in Task 7.)

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/setup_test.rb
require "test_helper"
require Rails.root.join("db/migrate/20260926120000_add_setup_completed_at_to_site_settings")

class SetupTest < ActiveSupport::TestCase
  test "setup is not required once completed" do
    assert_not Setup.required?
  end

  test "setup is required while no settings row is completed" do
    site_settings(:default).update!(setup_completed_at: nil)

    assert Setup.required?
  end

  test "setup is required on an empty database" do
    SiteSetting.delete_all

    assert Setup.required?
  end

  test "the backfill completes setup for an existing install with users" do
    site_settings(:default).update!(setup_completed_at: nil)

    run_backfill

    assert_not Setup.required?
  end

  # SiteSetting.instance creates its row lazily, so an existing install can
  # have users but no site_settings row at all.
  test "the backfill creates a completed row when users exist but settings don't" do
    SiteSetting.delete_all

    run_backfill

    assert_not Setup.required?
    assert_equal 1, SiteSetting.count
  end

  test "the backfill leaves a fresh install (no users) in setup" do
    SiteSetting.delete_all
    User.destroy_all

    run_backfill

    assert Setup.required?
  end

  private
    def run_backfill
      ActiveRecord::Migration.suppress_messages { AddSetupCompletedAtToSiteSettings.new.backfill }
    end
end
```

Replace `test/models/site_setting_test.rb` tests that assumed an empty table (the new fixture means a row always exists):

```ruby
  test "a second record cannot be created" do
    second = SiteSetting.new(title: "Second")

    assert_not second.valid?
    assert_includes second.errors[:base], "only one SiteSetting may exist"
  end

  test "instance creates the record on first access" do
    SiteSetting.delete_all

    assert_difference "SiteSetting.count", 1 do
      SiteSetting.instance
    end
  end

  test "instance returns the existing record on subsequent access" do
    assert_equal site_settings(:default), SiteSetting.instance
  end

  test "title is required" do
    setting = SiteSetting.instance
    setting.title = " "

    assert_not setting.valid?
    assert_includes setting.errors[:title], "can't be blank"
  end
```

(Keep the file's other tests — `default_locale defaults to en`, the two locale-inclusion tests — unchanged.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/setup_test.rb test/models/site_setting_test.rb`
Expected: FAIL/ERROR — missing migration file (`LoadError`), then `Setup` undefined.

- [ ] **Step 3: Implement**

`db/migrate/20260926120000_add_setup_completed_at_to_site_settings.rb`:

```ruby
class AddSetupCompletedAtToSiteSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :site_settings, :setup_completed_at, :datetime
    backfill
  end

  def down
    remove_column :site_settings, :setup_completed_at
  end

  # Any install that already has a user was set up before the wizard existed
  # and must never be redirected into it. Raw SQL, not models, so this
  # migration keeps working however SiteSetting changes later. The INSERT
  # covers installs where SiteSetting.instance never ran, so no row exists.
  def backfill
    execute <<~SQL
      UPDATE site_settings SET setup_completed_at = NOW()
      WHERE setup_completed_at IS NULL AND EXISTS (SELECT 1 FROM users)
    SQL
    execute <<~SQL
      INSERT INTO site_settings (title, default_locale, social_links, setup_completed_at, created_at, updated_at)
      SELECT 'My Site', 'en', '{}'::jsonb, NOW(), NOW(), NOW()
      WHERE EXISTS (SELECT 1 FROM users) AND NOT EXISTS (SELECT 1 FROM site_settings)
    SQL
  end
end
```

`app/models/setup.rb`:

```ruby
# The first-run setup wizard's state (design spec 2026-09-26 §3). Setup is
# "required" until SiteSetting#setup_completed_at is set -- not while
# `User.none?`, because the wizard creates the admin in step 3 and would
# otherwise lock itself out of every later step.
module Setup
  def self.required?
    !SiteSetting.where.not(setup_completed_at: nil).exists?
  end
end
```

`app/models/site_setting.rb` — add below the existing `validate :only_one_record_exists, on: :create`:

```ruby
  validates :title, presence: true
```

`test/fixtures/site_settings.yml`:

```yaml
# A completed setup, so the rest of the suite isn't redirected into /setup
# (Setup::RedirectConstraint). Tests that need a fresh install clear
# setup_completed_at themselves (see test/test_helpers/setup_test_helper.rb).
default:
  title: Test Site
  default_locale: en
  setup_completed_at: <%= Time.current.to_fs(:db) %>
```

`db/seeds.rb` — change the existing `SiteSetting.instance.tap` block to:

```ruby
SiteSetting.instance.tap do |settings|
  settings.update!(title: "ContentSpiel", tagline: "Notes from building a personal CMS") if settings.title.blank?
  # A seeded dev database is fully set up; never send it into /setup.
  settings.update!(setup_completed_at: Time.current) if settings.setup_completed_at.nil?
end
```

Run the migration (see Global Constraints for the sandbox fallback): `bin/rails db:migrate`. Confirm `db/schema.rb` now has `t.datetime "setup_completed_at"` in `site_settings`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/setup_test.rb test/models/site_setting_test.rb`
Expected: PASS. Then `PARALLEL_WORKERS=1 bin/rails test` — still all green (the fixture keeps everything else unaffected).

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb app/models/setup.rb app/models/site_setting.rb test/fixtures/site_settings.yml test/models/setup_test.rb test/models/site_setting_test.rb db/seeds.rb
git commit -m "$(cat <<'EOF'
feat: track setup completion on SiteSetting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 5: Setup token

**Files:**
- Create: `app/models/setup/token.rb`, `config/initializers/setup_token.rb`, `test/models/setup/token_test.rb`

**Interfaces:**
- Consumes: `Setup.required?` (Task 4).
- Produces: `Setup::Token.value -> String` (24 hex chars, or `ENV["SETUP_TOKEN"]`), `Setup::Token.valid?(candidate) -> Boolean`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/setup/token_test.rb
require "test_helper"

class Setup::TokenTest < ActiveSupport::TestCase
  teardown { ENV.delete("SETUP_TOKEN") }

  test "is derived from the app's secret: 24 hex characters, stable across calls" do
    assert_match(/\A\h{24}\z/, Setup::Token.value)
    assert_equal Setup::Token.value, Setup::Token.value
  end

  test "SETUP_TOKEN overrides the derived value" do
    ENV["SETUP_TOKEN"] = "chosen-by-the-operator"

    assert_equal "chosen-by-the-operator", Setup::Token.value
  end

  test "accepts the token with whitespace copied from a log line" do
    assert Setup::Token.valid?("  #{Setup::Token.value}\n")
  end

  test "rejects a wrong, empty, or missing token" do
    assert_not Setup::Token.valid?("0" * 24)
    assert_not Setup::Token.valid?("")
    assert_not Setup::Token.valid?(nil)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/setup/token_test.rb`
Expected: ERROR — `uninitialized constant Setup::Token`.

- [ ] **Step 3: Implement**

`app/models/setup/token.rb`:

```ruby
# The one-time code /setup asks for before anyone can create the first admin
# (design spec 2026-09-26 §3), so a publicly reachable fresh install can't be
# claimed by whoever finds it first. Derived from secret_key_base rather than
# stored: identical across restarts and Puma workers with nothing to persist,
# and anyone holding secret_key_base already owns the app.
module Setup
  module Token
    PURPOSE = "contentspiel setup token"

    def self.value
      ENV["SETUP_TOKEN"].presence ||
        Rails.application.key_generator.generate_key(PURPOSE, 12).unpack1("H*")
    end

    def self.valid?(candidate)
      ActiveSupport::SecurityUtils.secure_compare(candidate.to_s.strip, value)
    end
  end
end
```

`config/initializers/setup_token.rb`:

```ruby
# Prints the setup token while setup is still required, so whoever deployed
# the app can copy it from the server log into /setup (design spec
# 2026-09-26 §3). after_initialize so app constants autoload; the rescue
# covers boots where the database isn't reachable or migrated yet
# (assets:precompile, db:prepare on a brand-new install).
Rails.application.config.after_initialize do
  next if Rails.env.test?

  begin
    if Setup.required?
      Rails.logger.warn "[ContentSpiel] Setup is not complete. Open /setup and enter this setup token: #{Setup::Token.value}"
    end
  rescue ActiveRecord::ActiveRecordError
    nil
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/setup/token_test.rb`
Expected: PASS (4 runs).

- [ ] **Step 5: Commit**

```bash
git add app/models/setup/token.rb config/initializers/setup_token.rb test/models/setup/token_test.rb
git commit -m "$(cat <<'EOF'
feat: add setup token derived from secret_key_base

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 6: System check

**Files:**
- Create: `app/models/setup/system_check.rb`, `test/models/setup/system_check_test.rb`

**Interfaces:**
- Produces: `Setup::SystemCheck.run(**probes) -> Array<Setup::SystemCheck::Result>` in the order storage, image processing, background jobs, mail. `Result` has `label` (String), `status` (`:ok`/`:warning`), `message` (String), `ok?`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/setup/system_check_test.rb
require "test_helper"

# Probes are injected rather than stubbed: Minitest 6 ships no `stub`, and the
# real probes touch the disk, libvips and Solid Queue.
class Setup::SystemCheckTest < ActiveSupport::TestCase
  test "reports every check, in order" do
    labels = run_check.map(&:label)

    assert_equal [ "File storage", "Image processing", "Background jobs", "Outgoing mail" ], labels
  end

  test "the real storage probe works against the test disk service" do
    assert result("File storage", Setup::SystemCheck.run).ok?
  end

  test "a storage failure is a warning, not an exception" do
    check = result("File storage", run_check(storage_probe: -> { raise Errno::EACCES }))

    assert_equal :warning, check.status
    assert_includes check.message, "writable"
  end

  test "a missing libvips is a warning" do
    check = result("Image processing", run_check(image_probe: -> { raise LoadError }))

    assert_equal :warning, check.status
    assert_includes check.message, "libvips"
  end

  test "jobs are fine when an in-process adapter runs them" do
    assert result("Background jobs", run_check(queue_adapter: "async")).ok?
  end

  test "Solid Queue without a recent worker heartbeat is a warning" do
    check = result("Background jobs", run_check(queue_adapter: "solid_queue", worker_alive_probe: -> { false }))

    assert_equal :warning, check.status
    assert_includes check.message, "SOLID_QUEUE_IN_PUMA"
  end

  test "Solid Queue with a live worker is ok" do
    assert result("Background jobs", run_check(queue_adapter: "solid_queue", worker_alive_probe: -> { true })).ok?
  end

  test "unconfigured mail is a warning that points at the console fallback" do
    check = result("Outgoing mail", run_check(mail_host: "example.com"))

    assert_equal :warning, check.status
    assert_includes check.message, "bin/rails console"
  end

  test "configured SMTP with a real host is ok" do
    check = result("Outgoing mail",
      run_check(mail_delivery_method: :smtp, mail_smtp_address: "smtp.mailgun.org", mail_host: "cms.example.org"))

    assert check.ok?
  end

  private
    def run_check(**overrides)
      defaults = {
        storage_probe: -> { true }, image_probe: -> { true }, worker_alive_probe: -> { true },
        queue_adapter: "async", mail_delivery_method: :smtp, mail_smtp_address: "smtp.example.org",
        mail_host: "cms.example.org"
      }
      Setup::SystemCheck.run(**defaults.merge(overrides))
    end

    def result(label, results) = results.find { |r| r.label == label }
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/setup/system_check_test.rb`
Expected: ERROR — `uninitialized constant Setup::SystemCheck`.

- [ ] **Step 3: Implement**

`app/models/setup/system_check.rb`:

```ruby
# Read-only environment checks shown in the setup wizard and on Avo's System
# status page (design spec 2026-09-26 §4). Never blocking: every failure is a
# warning explaining what won't work and how to fix it. Each probe is a
# callable so tests can swap it; a probe that raises (including LoadError, which
# is what a missing libvips looks like) counts as a failure.
module Setup
  class SystemCheck
    Result = Data.define(:label, :status, :message) do
      def ok? = status == :ok
    end

    STORAGE_PROBE = -> {
      payload = "contentspiel system check"
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(payload), filename: "system-check.txt")
      begin
        blob.download == payload
      ensure
        blob.purge
      end
    }

    IMAGE_PROBE = -> {
      require "vips"
      Vips::Image.black(4, 4).resize(0.5).write_to_buffer(".png").bytesize.positive?
    }

    WORKER_ALIVE_PROBE = -> { SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).exists? }

    def self.run(**options) = new(**options).run

    def initialize(storage_probe: STORAGE_PROBE, image_probe: IMAGE_PROBE, worker_alive_probe: WORKER_ALIVE_PROBE,
      queue_adapter: ActiveJob::Base.queue_adapter_name,
      mail_delivery_method: ActionMailer::Base.delivery_method,
      mail_smtp_address: ActionMailer::Base.smtp_settings[:address],
      mail_host: ActionMailer::Base.default_url_options[:host])
      @storage_probe = storage_probe
      @image_probe = image_probe
      @worker_alive_probe = worker_alive_probe
      @queue_adapter = queue_adapter.to_s
      @mail_delivery_method = mail_delivery_method.to_s
      @mail_smtp_address = mail_smtp_address.to_s
      @mail_host = mail_host.to_s
    end

    def run
      [ storage, image_processing, background_jobs, mail ]
    end

    private
      def storage
        if probe(@storage_probe)
          ok("File storage", "Uploads can be stored and read back.")
        else
          warning("File storage", "Uploads can't be stored, so logos and images will fail. " \
            "Check that the storage directory (storage/ by default) is writable and on a persistent volume.")
        end
      end

      def image_processing
        if probe(@image_probe)
          ok("Image processing", "Images can be resized.")
        else
          warning("Image processing", "Images can't be resized, so image variants and logo resizing will fail. " \
            "Install libvips on the server.")
        end
      end

      def background_jobs
        if @queue_adapter != "solid_queue"
          ok("Background jobs", "Jobs run inside the web process (#{@queue_adapter} adapter).")
        elsif probe(@worker_alive_probe)
          ok("Background jobs", "A Solid Queue worker is running.")
        else
          warning("Background jobs", "No Solid Queue worker has checked in recently, so queued work " \
            "(upload analysis, emails) won't run. Set SOLID_QUEUE_IN_PUMA=1 or run bin/jobs.")
        end
      end

      def mail
        configured = @mail_delivery_method == "smtp" &&
          @mail_smtp_address.present? && @mail_smtp_address != "localhost" &&
          @mail_host.present? && @mail_host != "example.com"

        if configured
          ok("Outgoing mail", "Outgoing mail is configured.")
        else
          warning("Outgoing mail", "Password reset by email isn't configured. To reset a password without email, " \
            "run bin/rails console and User.find_by(email_address: \"you@example.com\").update!(password: \"new password\").")
        end
      end

      def probe(callable)
        callable.call
      rescue StandardError, LoadError
        false
      end

      def ok(label, message) = Result.new(label:, status: :ok, message:)
      def warning(label, message) = Result.new(label:, status: :warning, message:)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/setup/system_check_test.rb`
Expected: PASS (9 runs).

- [ ] **Step 5: Commit**

```bash
git add app/models/setup/system_check.rb test/models/setup/system_check_test.rb
git commit -m "$(cat <<'EOF'
feat: add read-only setup system check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 7: Starter content and `Setup.complete!`

**Files:**
- Create: `app/models/starter_content.rb`, `test/models/starter_content_test.rb`
- Modify: `app/models/setup.rb`, `test/models/setup_test.rb`

**Interfaces:**
- Consumes: `Setup.required?` (Task 4).
- Produces: `StarterContent.ensure_home!(locale:) -> Page`, `StarterContent.create_pages_and_posts!(locale:)`, `StarterContent.added?(locale:) -> Boolean`, `StarterContent::WELCOME_HTML`, `Setup.complete!`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/starter_content_test.rb
require "test_helper"

class StarterContentTest < ActiveSupport::TestCase
  test "ensure_home! creates a published root page with a welcome block" do
    home = StarterContent.ensure_home!(locale: "en")

    assert_nil home.parent_id
    assert home.published_at.present?
    assert_equal [ "rich_text" ], home.content_blocks.map(&:block_type)
    assert_includes home.content_blocks.first.body.to_s, "Welcome to your new site"
  end

  test "ensure_home! keeps an existing homepage and its blocks" do
    existing = Page.create!(page_type: :standard, title: "Mine", slug: "", published_at: Time.current)
    existing.content_blocks.create!(block_type: :post_list, position: 0)

    assert_no_difference [ "Page.count", "ContentBlock.count" ] do
      assert_equal existing, StarterContent.ensure_home!(locale: "en")
    end
  end

  test "create_pages_and_posts! adds Blog, Resume and Now pages with one sample post each" do
    StarterContent.create_pages_and_posts!(locale: "en")

    home = Page.find_by(parent_id: nil)
    slugs = home.children.map(&:slug)
    assert_equal %w[blog now resume], slugs.sort
    assert_equal %w[blog now_update resume_entry], Post.pluck(:content_type).sort
    assert StarterContent.added?(locale: "en")
  end

  test "create_pages_and_posts! writes in the given locale" do
    StarterContent.create_pages_and_posts!(locale: "de")

    assert Mobility.with_locale(:de) { Page.i18n.where(slug: "blog").exists? }
  end

  test "running it twice creates nothing new" do
    StarterContent.create_pages_and_posts!(locale: "en")

    assert_no_difference [ "Page.count", "Post.count", "ContentBlock.count" ] do
      StarterContent.create_pages_and_posts!(locale: "en")
    end
  end

  test "added? is false before starter content exists" do
    assert_not StarterContent.added?(locale: "en")
  end
end
```

Append to `test/models/setup_test.rb` (inside the class, above `private`):

```ruby
  test "complete! creates the homepage and ends setup" do
    site_settings(:default).update!(setup_completed_at: nil)

    Setup.complete!

    assert_not Setup.required?
    assert Page.exists?(parent_id: nil)
  end

  test "complete! is idempotent" do
    site_settings(:default).update!(setup_completed_at: nil)
    Setup.complete!

    assert_no_difference "Page.count" do
      Setup.complete!
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/starter_content_test.rb test/models/setup_test.rb`
Expected: ERROR — `uninitialized constant StarterContent`; `undefined method 'complete!'`.

- [ ] **Step 3: Implement**

`app/models/starter_content.rb`:

```ruby
# The pages and sample posts the setup wizard (and Avo's "Create starter
# pages" action) can add, written in one locale -- the site's default at the
# time. Every method is idempotent: it looks records up first, through
# Mobility's `.i18n` scope, because translated columns are jsonb and a plain
# `where(slug: ...)` would never match (see db/seeds.rb).
module StarterContent
  WELCOME_HTML = "<p>Welcome to your new site. Sign in to the admin to edit this page.</p>".freeze

  SECTIONS = [
    { slug: "blog", title: "Blog", content_type: "blog",
      post: { title: "Hello, world", excerpt: "The first post on this site.",
              body: "<p>This is a sample blog post. Edit or delete it in the admin.</p>" } },
    { slug: "resume", title: "Resume", content_type: "resume_entry",
      post: { title: "Your first role", body: "<p>Describe what you did in this role.</p>",
              metadata: { "company" => "Example Co", "role_type" => "ic", "start_date" => "2024-01-01", "end_date" => "" } } },
    { slug: "now", title: "Now", content_type: "now_update",
      post: { title: "What I'm doing now", body: "<p>Share what you're focused on at the moment.</p>" } }
  ].freeze

  module_function

  # Always run when setup finishes, so "/" is never a 404 on a new site.
  def ensure_home!(locale:)
    Mobility.with_locale(locale) do
      home = Page.find_by(parent_id: nil) ||
        Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
      home.content_blocks.create!(block_type: :rich_text, position: 0, body: WELCOME_HTML) if home.content_blocks.none?
      home
    end
  end

  def create_pages_and_posts!(locale:)
    home = ensure_home!(locale: locale)

    Mobility.with_locale(locale) do
      SECTIONS.each do |section|
        find_or_create_section_page!(home, section)
        find_or_create_sample_post!(section)
      end
    end
  end

  def added?(locale:)
    home = Page.find_by(parent_id: nil)
    return false unless home

    Mobility.with_locale(locale) do
      SECTIONS.all? { |section| Page.i18n.where(slug: section[:slug]).where(parent_id: home.id).exists? }
    end
  end

  def find_or_create_section_page!(home, section)
    Page.i18n.where(slug: section[:slug]).where(parent_id: home.id).first ||
      Page.create!(parent: home, page_type: :standard, title: section[:title], slug: section[:slug],
        published_at: Time.current).tap do |page|
        page.content_blocks.create!(block_type: :post_list, position: 0,
          settings: { "content_type" => section[:content_type] })
      end
  end

  def find_or_create_sample_post!(section)
    attributes = section[:post]
    Post.i18n.where(title: attributes[:title]).where(content_type: section[:content_type]).first ||
      Post.create!(content_type: section[:content_type], published_at: Time.current, **attributes)
  end
end
```

Add to `app/models/setup.rb` inside `module Setup`:

```ruby
  # Finishing the wizard: the homepage always exists afterwards, and setup
  # stops being required. Safe to call twice.
  def self.complete!
    SiteSetting.transaction do
      setting = SiteSetting.instance
      StarterContent.ensure_home!(locale: setting.default_locale)
      setting.update!(setup_completed_at: Time.current) if setting.setup_completed_at.nil?
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/starter_content_test.rb test/models/setup_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/starter_content.rb app/models/setup.rb test/models/starter_content_test.rb test/models/setup_test.rb
git commit -m "$(cat <<'EOF'
feat: add idempotent starter content and Setup.complete!

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 8: Redirect into `/setup` while setup is required

**Files:**
- Create: `app/models/setup/redirect_constraint.rb`, `test/test_helpers/setup_test_helper.rb`, `test/integration/setup_redirect_test.rb`
- Modify: `config/routes.rb` (very top of the `draw` block), `test/test_helper.rb`

**Interfaces:**
- Consumes: `Setup.required?`.
- Produces: `Setup::RedirectConstraint.matches?(request)`, `Setup::RedirectConstraint::EXEMPT_PREFIXES`; test helper `start_fresh_install` (removes all users, un-completes setup, clears the setup rate-limit store once it exists).

- [ ] **Step 1: Write the test helper and the failing test**

`test/test_helpers/setup_test_helper.rb`:

```ruby
module SetupTestHelper
  # A brand-new install: no users, setup not completed.
  def start_fresh_install
    User.destroy_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear if defined?(SetupController::RATE_LIMIT_STORE)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SetupTestHelper
end
```

In `test/test_helper.rb`, add below `require_relative "test_helpers/session_test_helper"`:

```ruby
require_relative "test_helpers/setup_test_helper"
```

```ruby
# test/integration/setup_redirect_test.rb
require "test_helper"

class SetupRedirectTest < ActionDispatch::IntegrationTest
  test "every page redirects to /setup while setup is required" do
    start_fresh_install

    [ "/", "/about", "/de/about", "/avo", "/avo/resources/posts" ].each do |path|
      get path
      assert_redirected_to "/setup", "expected #{path} to redirect to /setup"
    end
  end

  test "non-GET requests are redirected too" do
    start_fresh_install

    post "/avo/resources/posts"

    assert_redirected_to "/setup"
  end

  test "sign-in, health check and the MCP endpoint stay reachable" do
    start_fresh_install

    get "/up"
    assert_response :success

    get new_session_path
    assert_response :success

    post "/mcp"
    assert_response :unauthorized
  end

  test "nothing is redirected once setup is complete" do
    get new_session_path
    assert_response :success

    get "/avo"
    assert_not_equal "/setup", URI.parse(response.location.to_s).path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/setup_redirect_test.rb`
Expected: FAIL — `/` renders or 404s instead of redirecting.

- [ ] **Step 3: Implement**

`app/models/setup/redirect_constraint.rb`:

```ruby
# Sends every request to /setup while setup is required (design spec
# 2026-09-26 §3). A route constraint rather than a before_action so it also
# covers the mounted Avo engine. Exempt: the wizard itself, sign-in and
# password reset (an admin resuming setup), the health check, the MCP
# endpoint (own bearer auth; no tokens exist yet anyway) and Active Storage
# (the logo preview while setup runs). The exemption check runs first so
# those paths never cost a database query.
module Setup
  module RedirectConstraint
    EXEMPT_PREFIXES = %w[/setup /session /passwords /up /mcp /rails/active_storage].freeze

    module_function

    def matches?(request)
      !exempt?(request.path) && Setup.required?
    end

    def exempt?(path)
      EXEMPT_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end
  end
end
```

`config/routes.rb` — insert as the very first lines inside `Rails.application.routes.draw do`, above `mount_avo do`:

```ruby
  # While setup is required, every route below is unreachable (design spec
  # 2026-09-26 §3): these two catch-alls are declared first, so they win over
  # Avo and the public page routes. A lambda, so the constant is only
  # resolved per request (never while routes load during boot).
  constraints(->(request) { Setup::RedirectConstraint.matches?(request) }) do
    match "/", to: redirect("/setup", status: 302), via: :all, as: :setup_required_root
    match "*path", to: redirect("/setup", status: 302), via: :all, format: false, as: :setup_required
  end

```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/integration/setup_redirect_test.rb`
Expected: PASS. Then `PARALLEL_WORKERS=1 bin/rails test` — all green (the completed fixture keeps other tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add app/models/setup/redirect_constraint.rb config/routes.rb test/test_helpers/setup_test_helper.rb test/test_helper.rb test/integration/setup_redirect_test.rb
git commit -m "$(cat <<'EOF'
feat: redirect every request into /setup while setup is required

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 9: `SetupController` skeleton, layout, access gate, token step

**Files:**
- Create: `app/controllers/setup_controller.rb`, `app/helpers/setup_helper.rb`, `app/views/layouts/setup.html.erb`, `app/views/setup/_flash.html.erb`, `app/views/setup/_errors.html.erb`, `app/views/setup/token.html.erb`, `test/integration/setup_access_test.rb`
- Modify: `config/routes.rb`, `test/test_helpers/setup_test_helper.rb`

**Interfaces:**
- Consumes: `Setup.required?`, `Setup::Token.valid?`, `start_fresh_install`.
- Produces: routes `setup_path` (`GET /setup`), `setup_step_path(step)` (`GET`/`PATCH /setup/:step`); `SetupController::STEPS`, `PRE_ADMIN_STEPS`, `OPTIONAL_STEPS`, `RATE_LIMIT_STORE`; helper methods `step_label(step)`, `optional_step?(step)`, `next_step`; view helpers `setup_input_class`, `setup_label_class`, `setup_primary_button_class`, `setup_secondary_link_class`, `language_name(code)`; partials `setup/flash`, `setup/errors` (local `record:`); test helpers `verify_setup_token`, `create_setup_admin(email:)`. Step views for other steps are added in Tasks 10–13; until then those steps raise `ActionView::MissingTemplate` — expected.

- [ ] **Step 1: Write the failing test**

Append to `test/test_helpers/setup_test_helper.rb` inside the module:

```ruby
  def verify_setup_token
    patch setup_step_path("token"), params: { token: Setup::Token.value }
  end

  def create_setup_admin(email: "owner@example.com")
    patch setup_step_path("admin"), params: { user: {
      email_address: email, password: "password123", password_confirmation: "password123"
    } }
  end
```

```ruby
# test/integration/setup_access_test.rb
require "test_helper"

class SetupAccessTest < ActionDispatch::IntegrationTest
  test "/setup is a 404 once setup is complete, even for a signed-in admin" do
    sign_in_as(users(:one))

    get setup_path
    assert_response :not_found

    get setup_step_path("site")
    assert_response :not_found
  end

  test "an unknown step is a 404" do
    start_fresh_install

    get setup_step_path("nope")

    assert_response :not_found
  end

  test "a fresh install starts at the token step" do
    start_fresh_install

    get setup_path

    assert_redirected_to setup_step_path("token")
  end

  test "the token page renders" do
    start_fresh_install

    get setup_step_path("token")

    assert_response :success
    assert_includes response.body, "Setup token"
  end

  test "later steps require the token first" do
    start_fresh_install

    get setup_step_path("admin")

    assert_redirected_to setup_step_path("token")
  end

  test "a wrong token is rejected" do
    start_fresh_install

    patch setup_step_path("token"), params: { token: "wrong" }

    assert_response :unprocessable_entity
    assert_includes response.body, "doesn&#39;t match"
  end

  test "the right token unlocks the next step" do
    start_fresh_install

    verify_setup_token

    assert_redirected_to setup_step_path("system_check")
  end

  test "after the token, steps beyond the admin account stay closed" do
    start_fresh_install
    verify_setup_token

    get setup_step_path("site")

    assert_redirected_to setup_step_path("admin")
  end

  test "repeated wrong tokens lock the form, even for the right token" do
    start_fresh_install

    10.times { patch setup_step_path("token"), params: { token: "wrong" } }
    verify_setup_token

    assert_redirected_to setup_step_path("token")
    assert_equal "Too many attempts. Try again in a few minutes.", flash[:alert]
  end

  test "once an admin exists, the wizard requires signing in" do
    start_fresh_install
    User.create!(email_address: "owner@example.com", password: "password123")

    get setup_step_path("site")

    assert_redirected_to new_session_path
  end

  test "signing in resumes the step that was asked for" do
    start_fresh_install
    User.create!(email_address: "owner@example.com", password: "password123")
    get setup_step_path("site")

    post session_path, params: { email_address: "owner@example.com", password: "password123" }

    assert_redirected_to setup_step_path("site")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/setup_access_test.rb`
Expected: ERROR — `undefined local variable or method 'setup_path'`.

- [ ] **Step 3: Implement**

`config/routes.rb` — add directly above the `post "mcp", to: "mcp#create"` block:

```ruby
  # First-run setup wizard (design spec 2026-09-26 §4). SetupController
  # itself 404s once setup is complete.
  get "setup", to: "setup#index", as: :setup
  get "setup/:step", to: "setup#show", as: :setup_step
  patch "setup/:step", to: "setup#update"

```

`app/controllers/setup_controller.rb`:

```ruby
# The first-run setup wizard (design spec 2026-09-26 §3-§4). Every step
# persists as soon as it's submitted, so an admin who closes the browser can
# sign in again and resume. Access:
#   - no user yet: anyone who entered the setup token this session, and only
#     the steps up to creating the admin;
#   - admin exists: only a signed-in user;
#   - setup completed: 404.
class SetupController < ApplicationController
  STEPS = %w[token system_check admin site languages mcp_token starter_content review].freeze
  PRE_ADMIN_STEPS = %w[token system_check admin].freeze
  OPTIONAL_STEPS = %w[system_check mcp_token starter_content].freeze
  LABELS = {
    "token" => "Setup token", "system_check" => "System check", "admin" => "Admin account",
    "site" => "Site identity", "languages" => "Languages", "mcp_token" => "MCP token",
    "starter_content" => "Starter content", "review" => "Review"
  }.freeze

  # The rate limit needs a real store, and Rails.cache is :null_store in test
  # (every write a no-op, so the limit would never trip there). Per-process
  # memory is enough: setup runs once, against one server.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  allow_unauthenticated_access
  layout "setup"

  before_action :require_setup_pending
  before_action :load_step, only: %i[show update]
  before_action :require_step_access, only: %i[show update]

  rate_limit to: 10, within: 3.minutes, only: :update, store: RATE_LIMIT_STORE,
    if: -> { params[:step] == "token" },
    with: -> { redirect_to setup_step_path("token"), alert: "Too many attempts. Try again in a few minutes." }

  helper_method :step_label, :optional_step?, :next_step

  def index
    redirect_to setup_step_path(first_step)
  end

  def show
    render @step
  end

  def update
    case @step
    when "token" then update_token
    else head :not_found
    end
  end

  private
    def require_setup_pending
      head :not_found unless Setup.required?
    end

    def load_step
      @step = params[:step]
      head :not_found unless STEPS.include?(@step)
    end

    def require_step_access
      if User.none?
        return if @step == "token"
        return redirect_to(setup_step_path("token")) unless session[:setup_token_verified]
        redirect_to(setup_step_path("admin")) unless PRE_ADMIN_STEPS.include?(@step)
      else
        return request_authentication unless authenticated?
        redirect_to(setup_step_path("site")) if %w[token admin].include?(@step)
      end
    end

    def first_step
      return "site" if User.exists?

      session[:setup_token_verified] ? "system_check" : "token"
    end

    def next_step
      STEPS[STEPS.index(@step) + 1]
    end

    def step_label(step) = LABELS.fetch(step)

    def optional_step?(step) = OPTIONAL_STEPS.include?(step)

    def update_token
      if Setup::Token.valid?(params[:token])
        session[:setup_token_verified] = true
        redirect_to setup_step_path("system_check")
      else
        flash.now[:alert] = "That setup token doesn't match. Copy it from the server log."
        render :token, status: :unprocessable_entity
      end
    end
end
```

`app/helpers/setup_helper.rb`:

```ruby
# Class strings shared by the setup wizard's views, kept in one place so the
# steps stay visually consistent. Product UI -- uses the Content·Spiel tokens.
module SetupHelper
  LANGUAGE_NAMES = { "en" => "English", "de" => "Deutsch", "es" => "Español" }.freeze

  def setup_input_class
    "mt-1 block w-full rounded-cs border border-line-strong bg-surface px-3 py-2 text-ink focus:outline-2 focus:outline-accent"
  end

  def setup_label_class
    "block font-cs-mono text-label uppercase tracking-mono text-meta"
  end

  def setup_primary_button_class
    "inline-block cursor-pointer rounded-cs bg-accent px-4 py-2 font-semibold text-on-accent hover:bg-accent-hover"
  end

  def setup_secondary_link_class
    "inline-block cursor-pointer rounded-cs border border-line-strong px-4 py-2 text-ink hover:bg-sunken"
  end

  # Falls back to the code for any locale added to available_locales later.
  def language_name(code)
    LANGUAGE_NAMES.fetch(code.to_s, code.to_s.upcase)
  end
end
```

`app/views/layouts/setup.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
  <head>
    <title><%= content_for(:title) || "Set up ContentSpiel" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= render "shared/theme_head" %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body class="min-h-screen bg-paper font-cs text-ink">
    <div class="mx-auto flex max-w-4xl flex-col gap-8 px-4 py-10 md:flex-row">
      <nav aria-label="Setup steps" class="shrink-0 md:w-56">
        <p class="font-cs-mono text-label uppercase tracking-mono text-meta">ContentSpiel setup</p>
        <ol class="mt-4 space-y-2">
          <% SetupController::STEPS.each_with_index do |step, index| %>
            <%= tag.li class: (step == @step ? "font-semibold text-ink" : "text-dim"), aria: { current: ("step" if step == @step) } do %>
              <span class="font-cs-mono text-meta"><%= index + 1 %></span>
              <%= step_label(step) %>
              <% if optional_step?(step) %>
                <span class="font-cs-mono text-label uppercase tracking-mono text-meta">optional</span>
              <% end %>
            <% end %>
          <% end %>
        </ol>
        <div class="mt-6"><%= render "shared/theme_toggle" %></div>
      </nav>

      <main class="flex-1 rounded-cs border border-line bg-surface p-6">
        <%= render "setup/flash" %>
        <%= yield %>
      </main>
    </div>
  </body>
</html>
```

`app/views/setup/_flash.html.erb`:

```erb
<% if flash[:alert] %>
  <p class="mb-4 rounded-cs border border-danger bg-danger-tint px-3 py-2 text-danger-ink" role="alert"><%= flash[:alert] %></p>
<% end %>
<% if flash[:notice] %>
  <p class="mb-4 rounded-cs border border-ok bg-ok-tint px-3 py-2 text-ok-ink" role="status"><%= flash[:notice] %></p>
<% end %>
```

`app/views/setup/_errors.html.erb`:

```erb
<% if record.errors.any? %>
  <div class="mb-4 rounded-cs border border-danger bg-danger-tint px-3 py-2 text-danger-ink" role="alert">
    <ul class="list-disc pl-5">
      <% record.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

`app/views/setup/token.html.erb`:

```erb
<% content_for :title, "Setup token" %>
<h1 class="text-h1 font-semibold">Enter your setup token</h1>
<p class="mt-2 text-dim">
  To make sure you're the person who deployed this site, copy the setup token from the server log.
  Look for the line starting with <code class="font-cs-mono">[ContentSpiel] Setup is not complete</code>.
</p>

<%= form_with url: setup_step_path("token"), method: :patch, class: "mt-6 space-y-4" do |form| %>
  <div>
    <%= form.label :token, "Setup token", class: setup_label_class %>
    <%= form.text_field :token, required: true, autofocus: true, autocomplete: "off", spellcheck: false,
      class: "#{setup_input_class} font-cs-mono" %>
  </div>
  <%= form.submit "Continue", class: setup_primary_button_class %>
<% end %>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/setup_access_test.rb`
Expected: PASS (11 runs).

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/setup_controller.rb app/helpers/setup_helper.rb app/views/layouts/setup.html.erb app/views/setup test/test_helpers/setup_test_helper.rb test/integration/setup_access_test.rb
git commit -m "$(cat <<'EOF'
feat: add token-gated setup wizard skeleton

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 10: System check and admin account steps

**Files:**
- Create: `app/views/setup/system_check.html.erb`, `app/views/setup/_system_check_results.html.erb`, `app/views/setup/admin.html.erb`, `test/integration/setup_early_steps_test.rb`
- Modify: `app/controllers/setup_controller.rb`, `app/models/user.rb`, `test/models/user_test.rb`

**Interfaces:**
- Consumes: `Setup::SystemCheck.run`, `start_new_session_for` (Authentication concern), Task 9 helpers.
- Produces: partial `setup/system_check_results` (local `results:`), reused by Avo in Task 14; `User` validates `email_address` presence + uniqueness.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/integration/setup_early_steps_test.rb
require "test_helper"

class SetupEarlyStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
  end

  test "the system check lists every check and can be continued" do
    get setup_step_path("system_check")

    assert_response :success
    %w[File\ storage Image\ processing Background\ jobs Outgoing\ mail].each do |label|
      assert_includes response.body, label
    end
    assert_select "a[href=?]", setup_step_path("admin"), text: "Continue"
  end

  test "creating the admin signs them in and moves to site identity" do
    assert_difference "User.count", 1 do
      create_setup_admin
    end

    assert_redirected_to setup_step_path("site")
    assert_equal "owner@example.com", User.last.email_address
  end

  test "a password confirmation mismatch is shown, nothing is created" do
    assert_no_difference "User.count" do
      patch setup_step_path("admin"), params: { user: {
        email_address: "owner@example.com", password: "password123", password_confirmation: "different"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Password confirmation doesn&#39;t match"
  end

  test "a blank email is rejected" do
    patch setup_step_path("admin"), params: { user: { email_address: " ", password: "password123", password_confirmation: "password123" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Email address can&#39;t be blank"
  end

  test "the admin step can't be repeated once an admin exists" do
    create_setup_admin

    get setup_step_path("admin")

    assert_redirected_to setup_step_path("site")
  end
end
```

Append to `test/models/user_test.rb` (inside the class):

```ruby
  test "email address is required and unique" do
    User.create!(email_address: "taken@example.com", password: "password123")

    assert_not User.new(email_address: "", password: "password123").valid?
    assert_not User.new(email_address: "TAKEN@example.com", password: "password123").valid?
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/setup_early_steps_test.rb test/models/user_test.rb`
Expected: FAIL/ERROR — missing templates; `update` returns 404 for `admin`; user validation missing.

- [ ] **Step 3: Implement**

`app/models/user.rb` — add below `normalizes`:

```ruby
  # Presence here so the setup wizard shows a form error; uniqueness backs up
  # the unique index with a readable message instead of an exception.
  validates :email_address, presence: true, uniqueness: true
```

In `SetupController`:

Replace `show` with:

```ruby
  def show
    case @step
    when "system_check" then @results = Setup::SystemCheck.run
    when "admin" then @user = User.new
    end

    render @step
  end
```

Replace `update`'s `case` with:

```ruby
    case @step
    when "token" then update_token
    when "admin" then update_admin
    else head :not_found
    end
```

Add private method:

```ruby
    # The lock closes the window between two browsers submitting this step at
    # the same moment: only the first sees `User.none?` and becomes the admin;
    # the second is sent to sign in.
    def update_admin
      @user = User.new(params.expect(user: [ :email_address, :password, :password_confirmation ]))

      created = User.transaction do
        User.connection.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE")
        User.none? && @user.save
      end

      if created
        start_new_session_for(@user)
        session.delete(:setup_token_verified)
        redirect_to setup_step_path("site")
      elsif User.exists?
        redirect_to new_session_path, alert: "An admin account already exists. Sign in to continue setup."
      else
        render :admin, status: :unprocessable_entity
      end
    end
```

`app/views/setup/_system_check_results.html.erb`:

```erb
<ul class="mt-6 divide-y divide-line border-y border-line">
  <% results.each do |result| %>
    <li class="flex gap-4 py-3">
      <span class="w-20 shrink-0 font-cs-mono text-label uppercase tracking-mono <%= result.ok? ? "text-ok-ink" : "text-warn-ink" %>">
        <%= result.ok? ? "OK" : "Warning" %>
      </span>
      <div>
        <p class="font-semibold"><%= result.label %></p>
        <p class="text-dim"><%= result.message %></p>
      </div>
    </li>
  <% end %>
</ul>
```

`app/views/setup/system_check.html.erb`:

```erb
<% content_for :title, "System check" %>
<h1 class="text-h1 font-semibold">System check</h1>
<p class="mt-2 text-dim">
  These checks don't change anything. A warning tells you what won't work yet —
  you can continue now and fix it later.
</p>

<%= render "setup/system_check_results", results: @results %>

<div class="mt-6 flex gap-3">
  <%= link_to "Continue", setup_step_path(next_step), class: setup_primary_button_class %>
  <%= link_to "Re-run checks", setup_step_path("system_check"), class: setup_secondary_link_class %>
</div>
```

`app/views/setup/admin.html.erb`:

```erb
<% content_for :title, "Admin account" %>
<h1 class="text-h1 font-semibold">Create the admin account</h1>
<p class="mt-2 text-dim">You'll use this account to sign in to the admin.</p>

<%= form_with model: @user, url: setup_step_path("admin"), method: :patch, class: "mt-6 space-y-4" do |form| %>
  <%= render "setup/errors", record: @user %>
  <div>
    <%= form.label :email_address, "Email address", class: setup_label_class %>
    <%= form.email_field :email_address, required: true, autofocus: true, autocomplete: "username", class: setup_input_class %>
  </div>
  <div>
    <%= form.label :password, class: setup_label_class %>
    <%= form.password_field :password, required: true, autocomplete: "new-password", maxlength: 72, class: setup_input_class %>
  </div>
  <div>
    <%= form.label :password_confirmation, "Confirm password", class: setup_label_class %>
    <%= form.password_field :password_confirmation, required: true, autocomplete: "new-password", maxlength: 72, class: setup_input_class %>
  </div>
  <%= form.submit "Create account", class: setup_primary_button_class %>
<% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/setup_early_steps_test.rb test/models/user_test.rb test/integration/setup_access_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/setup_controller.rb app/models/user.rb app/views/setup test/integration/setup_early_steps_test.rb test/models/user_test.rb
git commit -m "$(cat <<'EOF'
feat: add system check and admin account setup steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 11: Site identity and languages steps

**Files:**
- Create: `app/views/setup/site.html.erb`, `app/views/setup/languages.html.erb`, `test/integration/setup_site_steps_test.rb`
- Modify: `app/controllers/setup_controller.rb`

**Interfaces:**
- Consumes: `SiteSetting.instance` (validates title presence — Task 4), `language_name`.
- Produces: params shape `site_setting[title|tagline|logo]`, `site_setting[social_links][][name|url]`, `site_setting[default_locale]`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/setup_site_steps_test.rb
require "test_helper"

class SetupSiteStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the site step renders the current settings" do
    get setup_step_path("site")

    assert_response :success
    assert_select "input[name='site_setting[title]'][value=?]", "Test Site"
  end

  test "saving site identity keeps complete social links and drops half-filled rows" do
    patch setup_step_path("site"), params: { site_setting: {
      title: "Dana's Notes", tagline: "Things I learned",
      social_links: [
        { name: "GitHub", url: "https://github.com/dana" },
        { name: "Mastodon", url: "" },
        { name: "", url: "https://example.org" },
        { name: "", url: "" }
      ]
    } }

    assert_redirected_to setup_step_path("languages")
    setting = SiteSetting.instance
    assert_equal "Dana's Notes", setting.title
    assert_equal "Things I learned", setting.tagline
    assert_equal({ "GitHub" => "https://github.com/dana" }, setting.social_links)
  end

  test "a blank title is rejected" do
    patch setup_step_path("site"), params: { site_setting: { title: " ", social_links: [ { name: "", url: "" } ] } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Title can&#39;t be blank"
  end

  test "choosing the default language" do
    get setup_step_path("languages")
    assert_response :success
    assert_includes response.body, "Deutsch"

    patch setup_step_path("languages"), params: { site_setting: { default_locale: "de" } }

    assert_redirected_to setup_step_path("mcp_token")
    assert_equal "de", SiteSetting.instance.default_locale
  end

  test "an unsupported language is rejected" do
    patch setup_step_path("languages"), params: { site_setting: { default_locale: "fr" } }

    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/setup_site_steps_test.rb`
Expected: ERROR — missing `setup/site` template; PATCH returns 404.

- [ ] **Step 3: Implement**

In `SetupController#show`'s `case`, add:

```ruby
    when "site", "languages" then @site_setting = SiteSetting.instance
```

In `update`'s `case`, add:

```ruby
    when "site" then update_site
    when "languages" then update_languages
```

Add private methods:

```ruby
    def update_site
      @site_setting = SiteSetting.instance

      if @site_setting.update(site_params)
        redirect_to setup_step_path("languages")
      else
        render :site, status: :unprocessable_entity
      end
    end

    # The form always renders a few name/URL rows; a row missing either half
    # is dropped rather than saved as a broken link.
    def site_params
      permitted = params.expect(site_setting: [ :title, :tagline, :logo, social_links: [ [ :name, :url ] ] ])
      rows = Array(permitted.delete(:social_links))
      links = rows.filter_map do |row|
        name, url = row[:name].to_s.strip, row[:url].to_s.strip
        [ name, url ] if name.present? && url.present?
      end
      permitted.merge(social_links: links.to_h)
    end

    def update_languages
      @site_setting = SiteSetting.instance

      if @site_setting.update(default_locale: params.dig(:site_setting, :default_locale))
        redirect_to setup_step_path("mcp_token")
      else
        render :languages, status: :unprocessable_entity
      end
    end
```

`app/views/setup/site.html.erb`:

```erb
<% content_for :title, "Site identity" %>
<h1 class="text-h1 font-semibold">Site identity</h1>
<p class="mt-2 text-dim">How your site introduces itself. You can change all of this later in the admin under Site settings.</p>

<%= form_with model: @site_setting, url: setup_step_path("site"), method: :patch, class: "mt-6 space-y-4" do |form| %>
  <%= render "setup/errors", record: @site_setting %>
  <div>
    <%= form.label :title, "Site title", class: setup_label_class %>
    <%= form.text_field :title, required: true, class: setup_input_class %>
  </div>
  <div>
    <%= form.label :tagline, class: setup_label_class %>
    <%= form.text_field :tagline, class: setup_input_class %>
  </div>
  <div>
    <%= form.label :logo, class: setup_label_class %>
    <%= form.file_field :logo, accept: "image/*", class: "mt-1 block text-dim" %>
  </div>

  <fieldset>
    <legend class="<%= setup_label_class %>">Social links</legend>
    <% links = @site_setting.social_links.to_a %>
    <% rows = links + Array.new([ 4 - links.size, 1 ].max) { [ "", "" ] } %>
    <div class="mt-1 space-y-2">
      <% rows.each do |name, url| %>
        <div class="grid grid-cols-2 gap-2">
          <%= text_field_tag "site_setting[social_links][][name]", name, placeholder: "e.g. GitHub",
            aria: { label: "Network" }, class: setup_input_class %>
          <%= url_field_tag "site_setting[social_links][][url]", url, placeholder: "https://…",
            aria: { label: "URL" }, class: setup_input_class %>
        </div>
      <% end %>
    </div>
  </fieldset>

  <%= form.submit "Save and continue", class: setup_primary_button_class %>
<% end %>
```

`app/views/setup/languages.html.erb`:

```erb
<% content_for :title, "Languages" %>
<h1 class="text-h1 font-semibold">Languages</h1>
<p class="mt-2 text-dim">
  Your site is available in the languages below. Pick the default: it's served without a
  language prefix in the URL (for example <code class="font-cs-mono">/about</code> instead of
  <code class="font-cs-mono">/de/about</code>).
</p>

<%= form_with model: @site_setting, url: setup_step_path("languages"), method: :patch, class: "mt-6 space-y-4" do |form| %>
  <%= render "setup/errors", record: @site_setting %>
  <fieldset class="space-y-2">
    <legend class="<%= setup_label_class %>">Default language</legend>
    <% I18n.available_locales.map(&:to_s).each do |code| %>
      <label class="flex items-center gap-3">
        <%= form.radio_button :default_locale, code %>
        <span><%= language_name(code) %></span>
        <span class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= code %></span>
      </label>
    <% end %>
  </fieldset>
  <%= form.submit "Save and continue", class: setup_primary_button_class %>
<% end %>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/setup_site_steps_test.rb`
Expected: PASS (5 runs).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/setup_controller.rb app/views/setup test/integration/setup_site_steps_test.rb
git commit -m "$(cat <<'EOF'
feat: add site identity and languages setup steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 12: MCP token and starter content steps (optional)

**Files:**
- Create: `app/views/setup/mcp_token.html.erb`, `app/views/setup/mcp_token_created.html.erb`, `app/views/setup/starter_content.html.erb`, `test/integration/setup_optional_steps_test.rb`
- Modify: `app/controllers/setup_controller.rb`

**Interfaces:**
- Consumes: `ApiToken.generate!(user) -> [ApiToken, raw_string]`, `ApiToken.authenticate(raw)`, `StarterContent.create_pages_and_posts!(locale:)`, `Current.user`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/setup_optional_steps_test.rb
require "test_helper"

class SetupOptionalStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the MCP token step can be skipped" do
    get setup_step_path("mcp_token")

    assert_response :success
    assert_select "a[href=?]", setup_step_path("starter_content"), text: "Skip"
  end

  test "generating an MCP token shows it once, bound to the admin, and never in flash" do
    assert_difference "ApiToken.count", 1 do
      patch setup_step_path("mcp_token")
    end

    assert_response :success
    raw = css_select("#mcp-token").first.text.strip
    assert_equal User.find_by(email_address: "owner@example.com"), ApiToken.authenticate(raw).user
    assert_empty flash.to_h
  end

  test "the starter content step can be skipped" do
    get setup_step_path("starter_content")

    assert_response :success
    assert_select "a[href=?]", setup_step_path("review"), text: "Skip"
  end

  test "adding starter content creates the pages in the default language" do
    SiteSetting.instance.update!(default_locale: "de")

    patch setup_step_path("starter_content")

    assert_redirected_to setup_step_path("review")
    assert StarterContent.added?(locale: "de")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/setup_optional_steps_test.rb`
Expected: ERROR — missing templates; PATCH returns 404.

- [ ] **Step 3: Implement**

In `update`'s `case`, add:

```ruby
    when "mcp_token" then update_mcp_token
    when "starter_content" then update_starter_content
```

Add private methods:

```ruby
    # Rendered, not redirected: the raw token exists only in this response and
    # must never pass through the session or flash.
    def update_mcp_token
      _token, @raw_token = ApiToken.generate!(Current.user)
      render :mcp_token_created
    end

    def update_starter_content
      StarterContent.create_pages_and_posts!(locale: SiteSetting.instance.default_locale)
      redirect_to setup_step_path("review"), notice: "Starter content added."
    end
```

`app/views/setup/mcp_token.html.erb`:

```erb
<% content_for :title, "MCP token" %>
<h1 class="text-h1 font-semibold">MCP token <span class="font-cs-mono text-label uppercase tracking-mono text-meta">optional</span></h1>
<p class="mt-2 text-dim">
  AI agents (for example Claude) can manage your posts through this site's MCP server at
  <code class="font-cs-mono">/mcp</code>. They need a token to connect. You can also create one later
  in the admin under API tokens.
</p>

<div class="mt-6 flex gap-3">
  <%= button_to "Generate token", setup_step_path("mcp_token"), method: :patch, class: setup_primary_button_class %>
  <%= link_to "Skip", setup_step_path("starter_content"), class: setup_secondary_link_class %>
</div>
```

`app/views/setup/mcp_token_created.html.erb`:

```erb
<% content_for :title, "MCP token" %>
<h1 class="text-h1 font-semibold">Your MCP token</h1>
<p class="mt-2 text-dim">Copy it now — it's only shown once. If you lose it, generate a new one in the admin.</p>

<pre id="mcp-token" class="mt-4 overflow-x-auto rounded-cs border border-line bg-sunken p-3 font-cs-mono"><%= @raw_token %></pre>

<div class="mt-6">
  <%= link_to "Continue", setup_step_path("starter_content"), class: setup_primary_button_class %>
</div>
```

`app/views/setup/starter_content.html.erb`:

```erb
<% content_for :title, "Starter content" %>
<h1 class="text-h1 font-semibold">Starter content <span class="font-cs-mono text-label uppercase tracking-mono text-meta">optional</span></h1>
<p class="mt-2 text-dim">
  Finishing setup always creates your Home page at <code class="font-cs-mono">/</code>. You can also add:
</p>
<ul class="mt-4 list-disc space-y-1 pl-5 text-dim">
  <li><strong class="text-ink">Blog</strong>, <strong class="text-ink">Resume</strong> and <strong class="text-ink">Now</strong> pages, each listing posts of that type</li>
  <li>one sample post for each, in your default language</li>
</ul>

<div class="mt-6 flex gap-3">
  <%= button_to "Add starter content", setup_step_path("starter_content"), method: :patch, class: setup_primary_button_class %>
  <%= link_to "Skip", setup_step_path("review"), class: setup_secondary_link_class %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/setup_optional_steps_test.rb`
Expected: PASS (4 runs).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/setup_controller.rb app/views/setup test/integration/setup_optional_steps_test.rb
git commit -m "$(cat <<'EOF'
feat: add optional MCP token and starter content setup steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 13: Review and finish

**Files:**
- Create: `app/views/setup/review.html.erb`, `test/integration/setup_finish_test.rb`
- Modify: `app/controllers/setup_controller.rb`

**Interfaces:**
- Consumes: `Setup.complete!`, `StarterContent.added?(locale:)`, `StarterContent::WELCOME_HTML`, `language_name`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/setup_finish_test.rb
require "test_helper"

class SetupFinishTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the review summarises the choices, with edit links" do
    SiteSetting.instance.update!(title: "Dana's Notes", default_locale: "de")

    get setup_step_path("review")

    assert_response :success
    assert_includes response.body, "Dana&#39;s Notes"
    assert_includes response.body, "Deutsch"
    assert_includes response.body, "Skipped"
    assert_select "a[href=?]", setup_step_path("site")
  end

  test "finishing creates the homepage, ends setup and opens the admin" do
    patch setup_step_path("review")

    assert_redirected_to "/avo"
    assert_not Setup.required?

    get "/"
    assert_response :success
    assert_includes response.body, "Welcome to your new site"

    get setup_path
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/setup_finish_test.rb`
Expected: ERROR — missing `setup/review` template; PATCH returns 404.

- [ ] **Step 3: Implement**

In `show`'s `case`, add:

```ruby
    when "review"
      @site_setting = SiteSetting.instance
      @starter_added = StarterContent.added?(locale: @site_setting.default_locale)
```

In `update`'s `case`, add:

```ruby
    when "review" then update_review
```

Add private method:

```ruby
    def update_review
      Setup.complete!
      redirect_to Avo.configuration.root_path, notice: "Setup complete."
    end
```

`app/views/setup/review.html.erb`:

```erb
<% content_for :title, "Review" %>
<h1 class="text-h1 font-semibold">Review</h1>
<p class="mt-2 text-dim">Check your choices. Everything here can also be changed later in the admin.</p>

<dl class="mt-6 divide-y divide-line border-y border-line">
  <% rows = [
       [ "Site title", @site_setting.title, "site" ],
       [ "Tagline", @site_setting.tagline.presence || "—", "site" ],
       [ "Social links", @site_setting.social_links.keys.to_sentence.presence || "None", "site" ],
       [ "Default language", language_name(@site_setting.default_locale), "languages" ],
       [ "Home page", "Always created", nil ],
       [ "Starter content", @starter_added ? "Blog, Resume and Now pages, one sample post each" : "Skipped — Home page only", "starter_content" ]
     ] %>
  <% rows.each do |label, value, step| %>
    <div class="flex items-baseline gap-4 py-3">
      <dt class="w-40 shrink-0 font-cs-mono text-label uppercase tracking-mono text-meta"><%= label %></dt>
      <dd class="flex-1"><%= value %></dd>
      <% if step %>
        <dd><%= link_to "Edit", setup_step_path(step), class: "text-accent underline hover:no-underline" %></dd>
      <% end %>
    </div>
  <% end %>
</dl>

<div class="mt-6">
  <%= button_to "Finish setup", setup_step_path("review"), method: :patch, class: setup_primary_button_class %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails tailwindcss:build && bin/rails test test/integration/setup_finish_test.rb`
Expected: PASS (2 runs).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/setup_controller.rb app/views/setup/review.html.erb test/integration/setup_finish_test.rb
git commit -m "$(cat <<'EOF'
feat: add setup review and finish step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 14: Backend settings in Avo

**Files:**
- Create: `app/avo/actions/create_starter_pages.rb`, `app/views/avo/tools/system_status.html.erb`, `app/views/avo/sidebar/items/_system_status.html.erb`, `test/models/create_starter_pages_action_test.rb`, `test/integration/system_status_test.rb`, `test/integration/avo_site_settings_test.rb`
- Modify: `app/avo/resources/site_setting.rb`, `app/controllers/avo/site_settings_controller.rb`, `app/avo/resources/page.rb`, `app/controllers/avo/tools_controller.rb`, `config/routes.rb` (inside `mount_avo`), `test/integration/avo_access_test.rb:34`

**Interfaces:**
- Consumes: `StarterContent.create_pages_and_posts!(locale:)`, `Setup::SystemCheck.run`, partial `setup/system_check_results`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/create_starter_pages_action_test.rb
require "test_helper"

# Exercised directly, like RegenerateApiTokenActionTest: Avo's action
# dispatch is Avo's own machinery; the resource index smoke test in
# AvoAccessTest covers the wiring.
class CreateStarterPagesActionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  test "creates the starter pages in the site's default language" do
    SiteSetting.instance.update!(default_locale: "es")
    action = Avo::Actions::CreateStarterPages.new(user: @user)

    action.handle(current_user: @user)

    assert StarterContent.added?(locale: "es")
    assert_equal "Starter pages are ready.", action.response[:messages].first[:body]
  end

  test "running it again creates nothing new" do
    Avo::Actions::CreateStarterPages.new(user: @user).handle(current_user: @user)

    assert_no_difference [ "Page.count", "Post.count" ] do
      Avo::Actions::CreateStarterPages.new(user: @user).handle(current_user: @user)
    end
  end
end
```

```ruby
# test/integration/system_status_test.rb
require "test_helper"

class SystemStatusTest < ActionDispatch::IntegrationTest
  test "an unauthenticated request cannot reach the system status page" do
    get "/avo/system_status"

    assert_response :redirect
  end

  test "the system status page shows the same checks as the setup wizard" do
    sign_in_as(users(:one))

    get "/avo/system_status"

    assert_response :success
    assert_includes response.body, "File storage"
    assert_includes response.body, "Background jobs"
  end
end
```

```ruby
# test/integration/avo_site_settings_test.rb
require "test_helper"

class AvoSiteSettingsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "the site settings menu entry opens the settings form directly" do
    get "/avo/resources/site_settings"

    assert_response :redirect
    assert_equal "/avo/resources/site_settings/#{site_settings(:default).id}/edit", URI.parse(response.location).path
  end

  test "social links are edited as name/URL rows" do
    get "/avo/resources/site_settings/#{site_settings(:default).id}/edit"

    assert_response :success
    assert_includes response.body, "Network"
  end
end
```

In `test/integration/avo_access_test.rb`, the index test (line 34) iterates `site_settings`, which now redirects. Change the list to:

```ruby
    %w[posts tags api_tokens pages content_blocks].each do |resource|
```

(Site settings' index behaviour is covered by `AvoSiteSettingsTest` above.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/create_starter_pages_action_test.rb test/integration/system_status_test.rb test/integration/avo_site_settings_test.rb`
Expected: ERROR/FAIL — `Avo::Actions::CreateStarterPages` undefined; `/avo/system_status` 404; settings index renders instead of redirecting; no "Network" label.

- [ ] **Step 3: Implement**

`app/avo/actions/create_starter_pages.rb`:

```ruby
# The setup wizard's optional "Starter content" step, available later from
# the Pages index (design spec 2026-09-26 §5). Idempotent -- existing pages
# and posts are left alone.
class Avo::Actions::CreateStarterPages < Avo::BaseAction
  self.name = "Create starter pages"
  self.standalone = true
  self.message = "Adds Blog, Resume and Now pages (each listing its posts) and one sample post per type, " \
    "in the site's default language. Anything that already exists is left alone."

  def handle(**args)
    StarterContent.create_pages_and_posts!(locale: SiteSetting.instance.default_locale)
    succeed("Starter pages are ready.")
  end
end
```

`app/avo/resources/page.rb` — add inside the class (after `fields`):

```ruby
  def actions
    action Avo::Actions::CreateStarterPages
  end
```

`app/avo/resources/site_setting.rb` — replace `field :social_links, as: :code` with:

```ruby
    field :social_links, as: :key_value, key_label: "Network", value_label: "URL"
```

`app/controllers/avo/site_settings_controller.rb`:

```ruby
# There is only ever one SiteSetting (singleton), so the Settings menu entry
# skips the one-row index and opens its edit form directly.
class Avo::SiteSettingsController < Avo::ResourcesController
  def index
    redirect_to avo.edit_resources_site_setting_path(SiteSetting.instance)
  end
end
```

`config/routes.rb` — inside `mount_avo do`, below the `mind_graph` route:

```ruby

    # The setup wizard's system check, re-runnable later (design spec
    # 2026-09-26 §5).
    get "system_status", to: "tools#system_status", as: :system_status
```

`app/controllers/avo/tools_controller.rb` — add a public action:

```ruby
  # The same read-only checks the setup wizard runs (Setup::SystemCheck).
  def system_status
    @page_title = "System status"
    add_breadcrumb title: "System status"
    @results = Setup::SystemCheck.run
  end
```

`app/views/avo/tools/system_status.html.erb`:

```erb
<div class="flex flex-col">
  <%= render ui.panel(title: "System status", description: "The same checks the setup wizard runs. A warning explains what won't work and how to fix it.") do |panel| %>
    <% panel.with_card do %>
      <%= render "setup/system_check_results", results: @results %>
    <% end %>
  <% end %>
</div>
```

`app/views/avo/sidebar/items/_system_status.html.erb`:

```erb
<%= render Avo::Sidebar::LinkComponent.new label: 'System status', path: File.join(avo.root_path, "system_status") %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/create_starter_pages_action_test.rb test/integration/system_status_test.rb test/integration/avo_site_settings_test.rb test/integration/avo_access_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/avo app/controllers/avo app/views/avo config/routes.rb test/models/create_starter_pages_action_test.rb test/integration/system_status_test.rb test/integration/avo_site_settings_test.rb test/integration/avo_access_test.rb
git commit -m "$(cat <<'EOF'
feat: expose setup settings, starter pages and system status in Avo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

### Task 15: End-to-end system test, verification, PR 2

**Files:**
- Create: `test/system/setup_wizard_test.rb`

- [ ] **Step 1: Write the system test**

```ruby
# test/system/setup_wizard_test.rb
require "application_system_test_case"

class SetupWizardTest < ApplicationSystemTestCase
  setup do
    User.destroy_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear
  end

  test "a fresh install goes from the token to a live homepage" do
    visit "/"
    assert_current_path "/setup/token"

    fill_in "Setup token", with: Setup::Token.value
    click_on "Continue"

    assert_text "File storage"
    click_on "Continue"

    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_on "Create account"

    fill_in "Site title", with: "Dana's Notes"
    click_on "Save and continue"

    choose "Deutsch"
    click_on "Save and continue"

    click_on "Skip"                  # MCP token
    click_on "Add starter content"

    assert_text "Blog, Resume and Now pages"
    click_on "Finish setup"

    assert_current_path %r{\A/avo}
    visit "/"
    assert_text "Welcome to your new site"
  end
end
```

- [ ] **Step 2: Run it**

Run: `bin/rails test:system TEST=test/system/setup_wizard_test.rb`
Expected: PASS. If it fails, fix the product code (not the test) unless the failure is a genuine selector mismatch with the approved views.

- [ ] **Step 3: Full verification**

```bash
PARALLEL_WORKERS=1 bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman -q --no-pager
bin/bundler-audit check --update
bin/importmap audit
```
All must be clean.

- [ ] **Step 4: Manual check** — in a scratch copy of the dev DB (or after `bin/rails runner 'SiteSetting.instance.update!(setup_completed_at: nil); User.destroy_all'` on a throwaway DB — **ask the user before touching their dev data**): start `bin/dev`, confirm the token appears in the log, walk the wizard, toggle dark mode, check `/avo/system_status` and the Settings menu entry.

- [ ] **Step 5: Commit, push, open PR 2**

```bash
git add test/system/setup_wizard_test.rb
git commit -m "$(cat <<'EOF'
test: cover the setup wizard end to end

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git push -u origin setup-wizard
gh pr create --title "Add token-gated setup wizard" --body "$(cat <<'EOF'
## Summary
- `/setup` wizard (spec 2026-09-26): setup token → system check (optional) → admin → site identity → languages → MCP token (optional) → starter content (optional) → review
- `site_settings.setup_completed_at` replaces `User.none?`; existing installs are backfilled as complete
- Every request redirects to `/setup` while setup is required (route constraint, covers Avo); sign-in, `/up`, `/mcp` exempt
- Finishing always creates the Home page; starter pages/posts are optional and idempotent
- Avo: social links as key/value, Settings opens the form directly, "Create starter pages" action, System status page

## Test plan
- [ ] `bin/rails test` / `bin/rails test:system` green
- [ ] Fresh DB: token printed at boot, full wizard walk-through, homepage live afterwards
- [ ] Existing DB: no redirect into `/setup`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
```

- [ ] **Step 6: Wait for the user to merge**, then `git checkout main && git pull --ff-only && git branch -d setup-wizard && git push origin --delete setup-wizard`.
