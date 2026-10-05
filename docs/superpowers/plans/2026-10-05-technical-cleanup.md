# Technical cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pay the technical debt that grows with every feature: a test suite that hides JavaScript errors and covered buttons and waits on sleeps; no i18n key scheme; no enforced dependency direction; a service contract checked by grep; access-control data shapes the screens can't show; URL sync and a public cache key that move on every write.

**Architecture:** Eighteen tasks in one PR, ordered so the test and structure work (Tasks 1–8) lands before the data work (Tasks 9–16), then the `CLAUDE.md` split and a sweep. Each task is implemented, reviewed and, where it changes behaviour, written test-first.

**Tech Stack:** Rails 8.1, Postgres 17, Minitest with fixtures and `ContentHelper`, system tests on Capybara + Cuprite (Ferrum), ViewComponent 4.15 with Lookbook previews, Hotwire (Turbo 2.0.23, Stimulus) through importmap, Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-10-05-technical-cleanup-design.md`. Its §10 (amendments from the code inventory) overrides the sections above it. Executors read the spec section each task names.

**Inventories:** three fact sheets written while planning, placed in the execution workspace as `cleanup-inventory-A.md` (test harness, services, dependencies), `-B.md` (strings, `queue.js`, `CLAUDE.md`) and `-C.md` (access control, tokens, locales, paths, content version). They quote the code as it was at `715b403`; where they and the code differ, the code wins.

## Global Constraints

- Prefix every test command with `PGGSSENCMODE=disable`. Full system suite: `bin/rails tailwindcss:build`, then `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system`. Never two test runners on the shared test databases at once.
- CI's headless Chrome cannot hover: no system test waits for an element revealed only by a `hover:` style.
- A system test that resizes the window restores it in `ensure`.
- Commits follow conventional commits (`feat|fix|ref|style|docs|test|chore`) and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.
- No new `Admin::<Domain>` namespace that shadows a top-level module (`test/lib` guards it). No colour literal, inline handler or `mx-auto` in the admin sources (`test/lib/admin_design_rules_test.rb`, `inline_handlers_test.rb`).
- Every write goes through an `ApplicationService`; a controller never writes a record.
- Never render, log or audit any part of an API key or token.
- A refactor task (5, 8, 17) changes no behaviour: the existing suites pass with no edited assertion, or the edit carries a stated reason in the task report.
- A behaviour task (9–16) is test-first: the new test fails on the old code, and the report quotes the red run.
- **Stop rule (Tasks 1 and 2):** more than twelve distinct findings: stop, report the list, wait.
- If a full system run shows a failure or error: name the test, run it alone several times, say whether it is deterministic and whose it is. Never report "a re-run was clean" without the name.

## Review Focus

Inputs and conditions the spec implies and no task's happy path exercises, most likely to bite first. Each has its test in the task named.

1. **A page moved, renamed, trashed and restored in sequence** must leave `public_paths` identical to a full rebuild, with every old URL a redirect and no `(locale, path)` holding two current rows. Task 15's parity test.
2. **A change made around model callbacks** (`update_all` in `Trash::Move`, `touch_all` in the tag services, a processed image variant) must still move the content version, or a visitor sees a stale page. Task 16's enumeration test and its guard.
3. **A scheduled post reaching its time with no write at all** must change the public ETag. Task 16.
4. **A group form posted exactly as rendered by a non-owner manager**, with a carried removed type and a redundant page root, must still change nothing after dormant names are judged as stored and the stale base is added. Tasks 10 and 11 extend the existing as-rendered tests.
5. **A JavaScript error thrown by a page the test has already left**, or by Turbo's own aborted frame fetch, must not fail an unrelated test, while an error on the page under test must. Task 1.

## Decisions

Made while planning, from the inventories. They refine the spec; none changes what the user approved.

| # | Decision |
|---|---|
| D1 | JavaScript errors are collected by a module prepended to `Ferrum::Page` and asserted empty in `teardown`. The driver's `js_errors` stays `false` (it raises asynchronously in the main thread). |
| D2 | `press` becomes native. `press_by_script(label)` is the named escape, each use commented. |
| D3 | One `assert_eventually(wait: 8, message:)` in `ApplicationSystemTestCase`; the two local copies with `timeout:` and the two `await_js` copies and `wait_until` are folded into it and one shared `await_js(condition, wait: 5)`. |
| D4 | "Nothing was saved" tests wait for the write queue to settle (`assert_writes_settled`, polling the queue's exported `settled()`), then assert no write. |
| D5 | A wall-clock precondition is an explicit timestamp or `travel_to`; a stub provider's delay is a gate (`Queue`) the test releases. |
| D6 | The behavioural contract lives in `test/services/service_behaviour_contract_test.rb`, with its per-service call factories in `test/support/service_calls.rb`. A service without a factory fails the test. |
| D7 | The dependency guard forbids `…Component` constants, `ApplicationController`, `ActionController`, `url_helpers` and `Rails.application.routes` under `app/models`, `app/queries`, `app/services`. Named exceptions: type definitions registering components; `RichText::HtmlRenderer` and `RichText::BuiltIns` using Action View's tag helpers; `Media::Asset`'s Active Storage URL methods. |
| D8 | Admin components look translations up through `Admin::AdminComponent#t`, which maps a leading-dot key to `admin.components.<component name without _component>.<key>`. |
| D9 | `config.i18n.raise_on_missing_translations = true` in the test environment. |
| D10 | Strings a script shows reach it through a `data-messages` JSON attribute on the controller's element (rendered by the server from the locale file), or a `<template>` for markup. |
| D11 | `queue.js` stays as the façade its four importers use; the concerns move to sibling modules and one shared state module. |
| D12 | Grant uniqueness is the database index plus `Groups::Save` refusing a request that lists one permission twice. No model-level uniqueness validation. |
| D13 | The stale banner for groups and users is Settings' pattern (a fixed message and Reload), shared through one partial. |
| D14 | `PublicSite.bump_version!` is the one bump. Models call it in `after_commit`; services that write around callbacks call it explicitly; a guard test polices those writes. |
| D15 | "Live" for the bump rule is the record's own `published_at` in the past, before or after the change, whatever its ancestors. |
| D16 | The URL-relevant values are captured in `before_save` into an instance variable, as `Page::TreeRanking` already does for the requested position; the availability validation uses the same comparison. |

---

### Task 1: System tests fail on JavaScript errors

**Spec:** §3.1, §10. **Inventory:** A §1.

**Files:**
- Create: `test/support/js_error_collector.rb`
- Modify: `test/application_system_test_case.rb`
- Test: `test/system/js_errors_test.rb`

**Interfaces:**
- Produces: `JsErrorCollector` (prepended to `Ferrum::Page`), with `JsErrorCollector.errors` (an Array of Hashes `{ text:, class_name:, description:, url: }`), `JsErrorCollector.reset!`, and `JsErrorCollector::IGNORED`, an Array of `[matcher_lambda, reason_string]`. `ApplicationSystemTestCase` resets it in `setup` and fails in `teardown` when it is not empty.

- [ ] **Step 1: Write the failing tests** in `test/system/js_errors_test.rb`:

```ruby
require "application_system_test_case"

class JsErrorsTest < ApplicationSystemTestCase
  test "an uncaught error on the page is collected" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("setTimeout(() => { throw new Error('boom from the page') }, 0)")
    assert_eventually(message: "the error was never collected") { JsErrorCollector.errors.any? }
    assert_match "boom from the page", JsErrorCollector.errors.first[:description]
  ensure
    JsErrorCollector.reset! # this test's error is the subject, not a failure
  end

  test "an unhandled rejection is collected" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("Promise.reject(new Error('rejected on the page'))")
    assert_eventually(message: "the rejection was never collected") { JsErrorCollector.errors.any? }
  ensure
    JsErrorCollector.reset!
  end

  test "Turbo's aborted frame fetch is ignored, with its reason on record" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script(<<~JS)
      const error = new DOMException("The user aborted a request.", "AbortError")
      Promise.reject(error)
    JS
    sleep 0.3 # sleep: proves an absence; no event marks an error that was dropped
    assert_empty JsErrorCollector.errors
    assert JsErrorCollector::IGNORED.all? { |_matcher, reason| reason.present? }
  end
end
```

- [ ] **Step 2: Run them, expect failure** (`NameError: uninitialized constant JsErrorCollector`):
`PGGSSENCMODE=disable bin/rails test test/system/js_errors_test.rb`

- [ ] **Step 3: Write the collector.** `test/support/js_error_collector.rb`: a module with a class-level, mutex-guarded `errors` array, `reset!`, `IGNORED = [ [ ->(details) { details.dig("exception", "className") == "DOMException" && details.dig("exception", "description").to_s.start_with?("AbortError") }, "Turbo: a <turbo-frame> disconnected mid-load aborts its fetch and the AbortError escapes unhandled" ] ]`, and a prepended `subscribe` that calls `super` and then `on("Runtime.exceptionThrown") { |params| JsErrorCollector.record(params["exceptionDetails"]) }`. `record` drops a detail any `IGNORED` matcher accepts and otherwise appends `{ text:, class_name:, description:, url: }`. Prepend it where `StaleNodeAtOnce` is prepended, with a comment explaining why the driver's own `js_errors` stays off (it raises in the main thread at an arbitrary line).

- [ ] **Step 4: Wire it into the base class.** In `ApplicationSystemTestCase`: `setup { JsErrorCollector.reset! }` and a `teardown` that does `errors = JsErrorCollector.errors.dup; JsErrorCollector.reset!; flunk("JavaScript errors on the page:\n" + errors.map { |e| "  #{e[:description] || e[:text]} (#{e[:url]})" }.join("\n")) if errors.any? && passed?`. Rewrite the `js_errors: false` comment to say what now catches errors.

- [ ] **Step 5: Run the three tests, expect PASS.**

- [ ] **Step 6: Run the full system suite and list what it surfaces.** For each distinct error: fix the application, or add an `IGNORED` entry with a reason if the application cannot prevent it. **Stop rule:** more than twelve distinct errors → stop and report the list. Record every finding and its fix in the task report.

- [ ] **Step 7: Full system suite green; commit.**
`test: system tests fail on JavaScript errors` (application fixes as separate `fix:` commits, one per finding).

---

### Task 2: Native clicks by default

**Spec:** §3.2, §10. **Inventory:** A §2.

**Files:**
- Modify: `test/application_system_test_case.rb`, and each system test whose press then fails
- Test: `test/system/press_helper_test.rb`

**Interfaces:**
- Consumes: Task 1's collector (already active).
- Produces: `press(label)` clicks natively (`find(:link_or_button, label).click`). `press_by_script(label)` keeps the scripted click. `press_insert` opens the Insert menu natively and presses the item natively.

- [ ] **Step 1: Write the failing test** `test/system/press_helper_test.rb`: sign in, visit the dashboard, inject a fixed full-viewport `<div>` over the page with `page.execute_script`, then `assert_raises(Capybara::Cuprite::MouseEventFailed) { press "Create draft" }`; and a second test that `press_by_script "Create draft"` on the same covered button raises nothing.

- [ ] **Step 2: Run, expect the first test to fail** (the scripted click succeeds on a covered button).

- [ ] **Step 3: Change the helpers.** `press` → native; add `press_by_script` with the old body and a comment listing its legitimate uses (an element inside a closed menu the test reaches by other means; a control shown only by a `hover:` style; a same-tick race a test builds on purpose). Update `press_insert` and the comment block above `press` (it explains a Selenium-era reason that no longer holds).

- [ ] **Step 4: Run the full system suite.** For every press that now fails: if the element is covered or not visible because of a real layout defect, fix the layout (`fix:` commit, noted as a finding); if the test pressed something a person could not press (a closed menu's item), open the menu first or use `press_by_script` with a comment. **Stop rule** at twelve distinct layout defects.

- [ ] **Step 5: Check the direct scripted clicks** listed in inventory A §2.3 (raw `execute_script("…click()")` outside the helper) the same way: native unless a comment says why not.

- [ ] **Step 6: Full system suite green; commit.** `test: press clicks natively; press_by_script is the named exception`

---

### Task 3: No fixed sleeps

**Spec:** §3.3, §10. **Inventory:** A §3, §4.

**Files:**
- Modify: `test/application_system_test_case.rb`; the system tests listed in inventory A §3; `test/system/admin/translations_test.rb` and `ai_settings_test.rb` (stub providers)
- Create: `test/lib/system_test_sleeps_test.rb`, `test/support/gated_provider.rb`

**Interfaces:**
- Produces in `ApplicationSystemTestCase`: `assert_eventually(wait: 8, message: "condition never became true") { … }` (the only copy); `await_js(condition, wait: 5)` (the only copy); `assert_writes_settled(wait: 8)`, which polls `import("autosave/queue").then((q) => q.settled())` through `evaluate_async_script`.
- Produces `GatedProvider`: a test AI provider whose `translate` and `test_connection` block on a `Queue` until the test calls `GatedProvider.release` (or `.release(error: "…")`); `GatedProvider.reset!` in teardown.

- [ ] **Step 1: Write the guard** `test/lib/system_test_sleeps_test.rb`, in the style of `test/lib/inline_handlers_test.rb`: scan `test/system/**/*.rb` and `test/application_system_test_case.rb` for lines matching `/^\s*sleep\b|[^.\w]sleep\s*[\d(]/`; a line passes only if it contains `# sleep:` followed by a reason of at least ten characters. Failure message lists `file:line` and the line.

- [ ] **Step 2: Run it, expect FAIL** listing the 59 lines.

- [ ] **Step 3: Consolidate the helpers** (D3): delete the local `assert_eventually(timeout:)` in `blocks_test.rb` and `media_picker_test.rb`, the two `await_js` copies and `wait_until`; adapt their callers to the shared signatures. Move the displaced comment above `assert_eventually` back to `await_admin_controllers`.

- [ ] **Step 4: Replace sleeps by kind**, working through inventory A §3's list:
  - (a) waiting for something → a waiting Capybara assertion, `assert_eventually`, `click_frame_link`, or `await_js`.
  - (b) proving nothing happened → `assert_writes_settled` then the negative assertion, where the absence is "no save was sent"; where no event marks the window, keep the sleep at its shortest meaningful length with `# sleep: <reason>`.
  - wall-clock preconditions (`changed_elsewhere_test.rb`, `autosave_unload_test.rb`, `autosave_test.rb`) → set `updated_at` explicitly or `travel_to`, so the one-second tolerance is crossed without waiting.
  - (c) stub provider delays → `GatedProvider`.
- [ ] **Step 5: Run each changed file alone five times** (`for i in 1 2 3 4 5; do PGGSSENCMODE=disable bin/rails test <file> || break; done`); a file that fails once is not done.

- [ ] **Step 6: Guard green, full system suite green; report the wall-clock time of the suite before and after. Commit.** `test: system tests wait on conditions, not sleeps`

---

### Task 4: The service contract, by behaviour

**Spec:** §3.4, §10. **Inventory:** A §5, §6.

**Files:**
- Create: `test/services/service_behaviour_contract_test.rb`, `test/support/service_calls.rb`
- Modify: `test/services/service_contract_test.rb`; `app/services/posts/bulk.rb`, `bulk_restore.rb` (comment wording only); any service the new contract proves wrong

**Interfaces:**
- Produces `ServiceCalls`: `ServiceCalls.for(service_class, test)` returns `{ call: -> { … }, subject: record_or_nil, tables: [Model, …] }` for a valid call of that service against fixtures or `ContentHelper` records; `ServiceCalls::SELF_SERVICE` (the four open-to-self services with their reason) and `ServiceCalls::OWN_RESULT` (the two bulk services with theirs).

- [ ] **Step 1: Write the contract test.** For every class in `ApplicationService.descendants` (after `Rails.application.eager_load!`), define a test `"#{klass} refuses an actor with no grants"`: create a user with no memberships (`User.create!(email_address: "nobody@example.com", password: "a-long-password-1")`); under `Current.set(actor: nobody, channel: :admin)` snapshot `tables.map(&:count)` and `subject&.reload&.attributes`; run `call`; assert `result.denied?`, exactly one new `Audit::Event` with action `access.denied`, and the snapshots unchanged. A class with no `ServiceCalls` entry and in neither exemption list fails with "add a call factory for #{klass} to test/support/service_calls.rb".

- [ ] **Step 2: Tests for the exemptions.** `SELF_SERVICE`: for each, a stranger acting on someone else's record is denied with one `access.denied`, and the owner of the record succeeds. `OWN_RESULT`: called by the no-grants user with real ids, nothing changes, and the result counts every id as not found.

- [ ] **Step 3: Run, expect FAIL** for every service without a factory.

- [ ] **Step 4: Write the factories** for the 33 services (inventory A §5.3 lists each signature and permission). Keep each a few lines; build records with `ContentHelper`.

- [ ] **Step 5: Run.** A service that fails the contract (answers ok, writes, or records no or two denials) is a finding: fix the service, test-first, in its own `fix:` commit. `Users::UpdateProfile`'s discarded `authorize!` (staff review S19) is expected here.

- [ ] **Step 6: Separate the grep's exemptions** in `service_contract_test.rb`: `# audit: none (reason)` skips only the audit check; `# authorize: none (reason)` only the authorisation check; both are matched within the class body, not the whole file. Update the two bulk services' comments accordingly.

- [ ] **Step 7: Unit suite green; commit.** `test: every service is proven to refuse, audit once and change nothing`

---

### Task 5: Dependency direction

**Spec:** §3.5, §10. **Inventory:** A §7, §8.

**Files:**
- Create: `test/lib/dependency_direction_test.rb`; `app/services/starter_contents/ensure_home.rb` (and whatever of `StarterContent`'s orchestration moves with it)
- Modify: `app/models/rich_text/html_renderer.rb`, `rich_text/built_ins.rb`, `rich_text/document.rb` (how a renderer is obtained); `app/models/starter_content.rb`, `app/models/setup.rb`, `app/controllers/setup_controller.rb`, `app/components/admin/tree_component.rb`, `app/services/starter_contents/add.rb`; `app/queries/jump/search.rb`, `app/views/admin/jump/show.html.erb`, `test/queries/jump/search_test.rb`; `app/queries/post_graph.rb`; a new initializer or `config/initializers/types.rb` for the default component renderer

**Interfaces:**
- Produces: `RichText.component_renderer` (a callable `->(component) { html_string }`), assigned in an initializer's `to_prepare` to `->(component) { ApplicationController.render(component, layout: false) }`; `RichText::HtmlRenderer` and `BuiltIns` call it and never name a controller. `Jump::Search` rows carry `route: [name_symbol, args, params]` instead of a built URL; the view resolves it against a fixed allow-list of route names. `PostGraph.new(…, url_for:)` has no default for `url_for:`. `StarterContents::EnsureHome.call` replaces `StarterContent.ensure_home!`; `StarterContent` keeps data and predicates (`added?`) only.

- [ ] **Step 1: Write the guard** `test/lib/dependency_direction_test.rb`: scan `app/models/**/*.rb`, `app/queries/**/*.rb`, `app/services/**/*.rb`, comments stripped, for `/\b[A-Z]\w*Component\b/`, `/\bApplicationController\b/`, `/\bActionController\b/`, `/\burl_helpers\b/`, `/Rails\.application\.routes/`. `ALLOWED` is a Hash of path → reason: `app/models/content_types/*.rb` and `app/models/block_types/*.rb` (type definitions register their components); `app/models/rich_text/html_renderer.rb` and `built_ins.rb` for `ActionController::Base.helpers` only (they build HTML with Action View's tag helpers) — the test still fails those two files on `ApplicationController` and on a `…Component` constant unless the constant is passed to `RichText.component_renderer`; `app/models/media/asset.rb` is not matched by these patterns and needs no entry. Each failure prints `file:line` and the pattern.

- [ ] **Step 2: Run, expect FAIL** listing the inversions in inventory A §7.

- [ ] **Step 3: RichText.** Introduce `RichText.component_renderer`; replace the two `ApplicationController.render` calls. The existing rich-text rendering tests must pass unchanged.

- [ ] **Step 4: StarterContent.** Move every method that calls a save service into `StarterContents::` services (`ApplicationService` subclasses, with `authorize!` and `record_event` as the existing `Add` has; Task 4's contract picks them up and needs a factory each). Update `Setup`, `SetupController`, `Admin::TreeComponent` and the doc comments that name `StarterContent.add_once!`.

- [ ] **Step 5: Jump::Search and PostGraph.** Change the row shape and its one view and test; remove `PostGraph`'s default `url_for:` and pass it from every caller.

- [ ] **Step 6: Guard green; unit and system suites green with no assertion edited** except `test/queries/jump/search_test.rb`'s row shape (state it in the report). Commit. `ref: models, queries and services no longer reach into controllers or routes; a guard keeps it so`

---

### Task 6: The i18n scheme and the shared components

**Spec:** §3.6, §10. **Inventory:** B §1–§3, §7.

**Files:**
- Create: `docs/reference/i18n.md`; `config/locales/admin/components.en.yml`; `test/lib/admin_i18n_test.rb`; `app/helpers/admin/messages_helper.rb`
- Modify: `config/environments/test.rb`; `app/components/admin/admin_component.rb` (the base class; create it and re-parent the admin components if none exists — inventory B §2.0); the sixteen shared components and their templates (inventory B §2); `app/views/layouts/admin.html.erb` (leave dialog, toast templates); `app/javascript/controllers/admin/save_bar_controller.js`, `pending_lock_controller.js`, `chip_input_controller.js`, `autosave_controller.js`, `app/javascript/autosave/order_request.js`; `config/locales/en.yml` (date formats)

**Interfaces:**
- Produces: `Admin::AdminComponent#t(key, **options)`: a key starting with `.` resolves under `admin.components.<demodulized class name, underscored, without the _component suffix>`; any other key is passed to `I18n.t`. `Admin::MessagesHelper#messages_data(scope, *keys)` returns a JSON string of `{ key => I18n.t("#{scope}.#{key}") }` (a pluralised key yields `{ one:, other: }` with `%{count}` left in) for a `data-messages` attribute; scripts read it with a shared `messages(element)` function in `app/javascript/i18n/messages.js` exposing `t(key, { count, …vars })`. Date formats `admin.short` (`"%-d %b"`), `admin.short_with_year` (`"%-d %b %Y"`), `admin.time` (`"%H:%M"`) under `time.formats` / `date.formats`.

- [ ] **Step 1: Write the scheme** in `docs/reference/i18n.md`: the rules of spec §3.6 with one worked example each (a view key, a component key, a JS message, a plural, an interpolated sentence, a controller toast, a date), the file layout under `config/locales/admin/`, and the named out-of-scope items (the Ruby-built sentences; how CS Studio picks its UI language).

- [ ] **Step 2: Turn on missing-key errors** (`config.i18n.raise_on_missing_translations = true` in `config/environments/test.rb`); run the unit suite to confirm nothing depends on a missing key today.

- [ ] **Step 3: Write the guard** `test/lib/admin_i18n_test.rb`: `CONVERTED` lists the converted template and component files. For each: an ERB template may contain no text node with a letter outside an ERB tag, and no `aria-label=`, `title=`, `placeholder=` or `alt=` attribute with a literal letter value; a component `.rb` may contain no string literal with a space and a capital-initial word outside comments, `class:` values, CSS class constants and `data:` keys (the test's own allow-patterns are documented at its top). Converted `.js` files may contain no string literal matching `/[A-Z][a-z]+ [a-z]/` outside comments. Start with `CONVERTED` empty and add each file as it is converted.

- [ ] **Step 4: Convert the shared components** one at a time (inventory B §2 lists every string with its line): add the keys to `components.en.yml`, replace the literals with `t(".key")`, add the file to `CONVERTED`, run that component's test. **The English output stays byte-identical** (curly quotes, ellipses, apostrophes), so every existing test passes unedited; the three hand-built plurals that are wrong today ("1 problems" in `SaveStatusComponent`, `ErrorSummaryComponent#heading`, the chip input's "suggestion(s)") become correct plurals, and the tests that pinned the wrong text are corrected with that reason.

- [ ] **Step 5: Convert the script-shown strings** of the shared layer (inventory B §3): the leave dialog's sentence, the pending-lock hint, the save-status texts duplicated between `SaveStatusComponent` and `autosave_controller.js` (one server source), the chip input's announcements, `order_request.js`'s toasts and the queue's dropped-press toast. Each reaches its script through `messages_data`.

- [ ] **Step 6: A component test for the helper**: `t(".cancel")` in `Admin::ConfirmDialogComponent` reads `admin.components.confirm_dialog.cancel`; a missing key raises.

- [ ] **Step 7: Guard green, unit and system suites green; commit.** `feat: an i18n key scheme for CS Studio, proven on the shared components`

---

### Task 7: The Tags screen converted

**Spec:** §3.6, §10. **Inventory:** B §4.

**Files:**
- Create: `config/locales/admin/tags.en.yml`
- Modify: `app/views/admin/tags/index.html.erb`, `app/controllers/admin/tags_controller.rb`, `app/helpers/admin/tags_helper.rb`, `app/controllers/admin/tag_suggestions_controller.rb`, `app/services/tags/merge.rb` (its three message constants), `app/javascript/controllers/admin/tag_dialogs_controller.js`, `test/lib/admin_i18n_test.rb` (`CONVERTED`)

**Interfaces:**
- Consumes: Task 6's `t` in views (Rails lazy lookup: `admin.tags.index.*`), `messages_data`, the guard's `CONVERTED` list.
- Produces: keys under `admin.tags.index`, `admin.tags.dialogs`, `admin.tags.toasts`, `admin.tags.merge` (the service's messages).

- [ ] **Step 1: Pin the copy first.** Add a helper test `test/helpers/admin/tags_helper_test.rb` (none exists) asserting today's exact sentences for: delete and merge with 0, 1 and many carriers; carriers greater than the readable count (the "including ones in the trash or that you can't open" clause, singular and plural); a viewer without `posts.read`. Run it green against the current helper.

- [ ] **Step 2: Convert.** Move every string in the view, controller, helper, suggestions controller and `Tags::Merge` to `tags.en.yml`; sentences with counts become pluralised keys with interpolation. Keep `“%{name}”` literally in each sentence that names the tag: `admin--tag-dialogs#reword` finds the name by its curly quotes. The script's own strings (the delete-failure toast) come through `messages_data`.

- [ ] **Step 3: Add the files to `CONVERTED`.** Run the helper test from Step 1, `test/integration/admin/tags_test.rb`, `test/system/admin/tags_test.rb`, `test/services/tags/merge_test.rb`: all green with no assertion edited.

- [ ] **Step 4: Guard green; commit.** `feat: the Tags screen reads its copy from the locale file`

---

### Task 8: Split `queue.js`

**Spec:** §3.7. **Inventory:** B §5.

**Files:**
- Create: `app/javascript/autosave/queue_core.js`, `frame_hold.js`, `promotion_hold.js`, `queue_state.js`
- Modify: `app/javascript/autosave/queue.js` (becomes the façade), `config/importmap.rb` only if the directory pin does not already cover the new files with `preload: "admin"`

**Interfaces:**
- Produces: `queue.js` re-exports the same eleven names its four importers use (inventory B §5.3), unchanged. `queue_state.js` holds the state the concerns share (the write count, the queue's tail, the registered forms, the generation bookkeeping, `frameFormRefused`, the promotion record) behind accessor functions. Listener registration order is preserved by importing the modules in today's order from the façade, with a comment saying the order is load-bearing and why.

- [ ] **Step 1: Record the baseline.** Run `test/system/admin/promotion_hold_test.rb`, `autosave_test.rb`, `blocks_test.rb`, `changed_elsewhere_test.rb`, `autosave_unload_test.rb` and `save_bar_test.rb`; note the run and assertion counts.

- [ ] **Step 2: Move the code**, concern by concern (the outline with line ranges is in inventory B §5.2), keeping each function's body and comments intact. The file's long header comment is split so each module carries the part that describes it; the façade keeps the overview.

- [ ] **Step 3: Check the module graph** in a browser console through a system test: `import("autosave/queue")` resolves and exposes the eleven exports; no module is evaluated twice (a top-level counter in a throwaway assertion, removed afterwards).

- [ ] **Step 4: Run the baseline files again: the same run and assertion counts, all green, no assertion edited. Then the full system suite. Commit.** `ref: the write queue as four modules behind the same façade`

---

### Task 9: One grant per permission in a group

**Spec:** §4.1, §10. **Inventory:** C §1.

**Files:**
- Create: `db/migrate/<timestamp>_one_grant_per_permission.rb`, `test/migrations/one_grant_per_permission_test.rb`
- Modify: `db/schema.rb`, `app/services/groups/save.rb`, `test/services/groups/save_test.rb`, `test/models/access_control/checker_test.rb` and any other test that builds two grants for one permission in one group (inventory C surprises 4)

**Interfaces:**
- Produces: a unique index `index_access_control_grants_on_group_id_and_permission` (replacing the non-unique one of the same columns). `Groups::Save` answers `invalid` with the message "<Permission label> is listed twice." when the desired grants name one permission twice. `Groups::Save#live` loses its `claimed` bookkeeping.

- [ ] **Step 1: Write the migration test** (in the style of the existing token-name migration test, inventory C §3.6): at the previous schema version insert a group with (i) two identical-permission grants scoped `{content_types: ["blog"]}` and `{content_types: ["now_update"]}`, (ii) one unscoped and one scoped, (iii) one by content type and one `{own: true}`. Run the migration. Assert one grant each: (i) `{content_types: ["blog", "now_update"]}`, (ii) `{}`, (iii) `{}` and the group's name in the migration's output. Assert a second insert for the same pair raises `ActiveRecord::RecordNotUnique`.

- [ ] **Step 2: Run, expect FAIL** (no migration).

- [ ] **Step 3: Write the migration** (`ActiveRecord::Migration[8.1]`, raw SQL plus plain Ruby over the rows, no application models): merge by the three rules, delete the surplus rows, `remove_index` then `add_index … unique: true`. Reversible down to the non-unique index (the merge itself is not undone; say so in a comment).

- [ ] **Step 4: Service tests first.** In `save_test.rb`: a request listing `posts.edit` twice is `invalid` with the message above, nothing written, no audit event. Rewrite the tests that needed two stored grants for one permission (the "move a removed name between two grants" cases become unreachable: delete them with a comment in the commit message; "grants combine with OR" in `checker_test.rb` is rebuilt with one user in two groups).

- [ ] **Step 5: Implement** the duplicate check in `Groups::Save` (before the authorisation comparisons) and simplify `live`.

- [ ] **Step 6: `bin/rails db:migrate`, schema committed; unit suite green; the groups system tests green. Commit.** `fix: a group holds one grant per permission`

---

### Task 10: Dormant removed-type names judged as stored

**Spec:** §4.2. **Inventory:** C §1.5, §1.6. **Stronger model for the work and its review.**

**Files:**
- Modify: `app/models/access_control.rb` (`can_assign_group?`, `can_manage_group?`, `holds?` via the checker), `app/models/access_control/checker.rb`, `app/services/groups/save.rb` (the member loop), `app/components/admin/permission_matrix_component.rb` and `app/components/admin/groups_screen/*` only where the view-only state follows from the changed predicate
- Test: `test/models/access_control_test.rb` (or the file that holds `can_assign_group?` tests), `test/services/groups/save_test.rb`, `test/services/users/save_test.rb`, `test/services/api_tokens/issue_test.rb`, `test/integration/admin/groups_editor_states_test.rb`

**Interfaces:**
- Consumes: Task 9 (one grant per permission).
- Produces: `AccessControl.can_assign_group?(actor, group, channel:)` and `can_manage_group?` are true only if the actor could grant every grant of the group **as stored** (`LiveGrants#carried_attributes`, gone names included). `AccessControl.holds?(actor, key)` is false for a grant whose named content types are all unregistered.

- [ ] **Step 1: Write the failing tests**, each as a non-owner holding `posts.edit {content_types: ["blog"]}` plus the managing right:
  - `can_assign_group?` is false for a group holding `posts.edit {content_types: ["blog", "retired_type"]}`, and for one holding the dead `{content_types: ["retired_type"]}`; true for an unscoped holder and for an owner.
  - `Users::Save` adding that group to a user is denied with one `access.denied`.
  - `ApiTokens::Issue` binding a token to that group is denied.
  - `Groups::Save` adding a member to that group, grants as rendered, is denied.
  - The group editor renders view-only for that viewer (the existing as-rendered test for an editable form is rebuilt with a viewer whose own grant names the removed type, or who holds the permission unscoped).
  - `holds?("posts.read")` is false for a user whose only `posts.read` grant is `{content_types: ["retired_type"]}`.
- [ ] **Step 2: Run, expect FAIL** on each.
- [ ] **Step 3: Implement.** Change the three predicates to judge `carried_attributes`; `Groups::Save#live`'s exemption (a posted grant exactly equal to a stored one, carried name included, is unchanged) stays as it is.
- [ ] **Step 4: Re-derive the rule in the comment** above `can_assign_group?` and above `live` (this codebase documents such invariants at length), and check every caller in inventory C §1.6 still reads correctly.
- [ ] **Step 5: `test/services/groups*`, `users*`, `api_tokens*`, `access_control_test.rb`, `authorization_matrix_test.rb`, the groups and users integration and system tests green; Task 4's contract green. Commit.** `fix: a removed content type's name in a grant can't be handed on by someone who couldn't grant it`

---

### Task 11: No lost updates on groups and users

**Spec:** §4.3, §10. **Inventory:** C §2.

**Files:**
- Create: `app/views/admin/shared/_stale_banner.html.erb`; `app/controllers/concerns/admin/stale_form.rb`
- Modify: `app/controllers/admin/groups_controller.rb`, `users_controller.rb`, `settings_controller.rb` (use the shared concern and partial; behaviour unchanged); `app/views/admin/groups/_form.html.erb`, `app/views/admin/users/_form.html.erb`, `app/views/admin/settings/show.html.erb`; `app/services/groups/save.rb`, `groups/destroy.rb`, `users/save.rb`, `users/destroy.rb`
- Test: `test/integration/admin/groups_test.rb`, `users_test.rb`, `test/services/groups/save_test.rb`, `test/services/users/save_test.rb`, `test/system/admin/groups_editor_test.rb`

**Interfaces:**
- Produces: `Admin::StaleForm#stale_form?(record, base)` (the `base_older_than?` logic Settings has: a blank or unparseable base is not stale) and `render_stale(template, …)`; the partial `admin/shared/stale_banner` with locals `message:` and `reload_path:`. Forms post `base_updated_at` through the existing `admin/shared/base_updated_at_field` partial. Messages: "This group was changed elsewhere since you opened this screen. Reload to see the latest — your changes are still in the form." and the same with "This user".

- [ ] **Step 1: Write the failing tests.**
  - Service: `Groups::Save` changing only grants, and only members, moves `groups.updated_at`; it moves `users.updated_at` of each member added or removed. `Users::Save` changing only groups moves `users.updated_at` and each gained or lost group's `updated_at`. `Groups::Destroy` moves its former members' `updated_at`; `Users::Destroy` its former groups'.
  - Integration: load the group editor, change the group in a second request (another admin), then PATCH the first form with its old `base_updated_at` → 409, the banner text, the typed values still in the form, nothing written, no audit event. The same for a user. A blank base is not stale. A member added on the group form makes that user's open edit form stale.
  - The existing as-rendered tests (submit exactly as rendered → no change, 303) still pass with the base field present.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the touches inside the services' transactions (`touch` on the record; `where(id: ids).touch_all` for the other side — and note that `touch_all` fires no callbacks, which matters to nothing here), the concern, the partial, and the two controllers' 409 path. Move Settings onto the concern and partial; its own tests pass unedited.
- [ ] **Step 4: System test**: two sessions on one group; the second Save shows the banner and Reload shows the first admin's change.
- [ ] **Step 5: Groups, users and settings tests green; commit.** `fix: a stale group or user save is refused instead of overwriting`

---

### Task 12: The owner flag through one door

**Spec:** §4.4, §10. **Inventory:** C §2.3, §2.6.

**Files:**
- Modify: `app/controllers/admin/users_controller.rb` (`user_params`), `app/services/users/save.rb` (`owner_change?`)
- Test: `test/integration/admin/users_test.rb`, `users_editor_test.rb`, `test/services/users/save_test.rb`

- [ ] **Step 1: Write the failing tests.** Service: `Users::Save` called with `owner: nil` and with `owner: ""` on an owner changes nothing and records no `user.owner_changed`; with `owner: false` it demotes (the real boolean still works). Integration: a PATCH to `users/:id` carrying `user[owner]=1` from an owner does not change the flag and is otherwise an ordinary save.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**: drop `:owner` from `user_params`; `owner_change?` returns false when the attribute is absent, `nil` or `""` (not `blank?`, which is true for `false`).
- [ ] **Step 4: Move the three tests** that pinned owner behaviour on the ordinary PATCH (inventory C §2.6) to the `PATCH users/:id/owner` endpoint where it doesn't already have them; the forged-by-a-non-owner case there still asserts 403 and one `access.denied`.
- [ ] **Step 5: Users tests green; commit.** `fix: only the owner endpoint changes the owner flag`

---

### Task 13: API token lookup by digest

**Spec:** §4.5, §10. **Inventory:** C §3.

**Files:**
- Create: `db/migrate/<timestamp>_api_tokens_lookup_digest.rb`, `test/migrations/api_tokens_lookup_digest_test.rb`
- Modify: `app/models/api_token.rb`, `app/models/audit/snapshot.rb` (`NEVER_STORED`), `db/schema.rb`, `test/fixtures/api_tokens.yml`, `test/models/api_token_test.rb`, `test/services/api_tokens/issue_test.rb`, `test/migrations/add_name_to_api_tokens_test.rb`, `test/models/audit/snapshot_test.rb`, `docs/reference` or `CLAUDE.md` wording is left to Task 17

**Interfaces:**
- Produces: `api_tokens.lookup_digest` (string, not null, unique index). `ApiToken.digest(raw)` → `OpenSSL::Digest::SHA256.hexdigest(raw)`. `ApiToken.authenticate(raw)` → `active.find_by(lookup_digest: digest(raw))`, compared again with `ActiveSupport::SecurityUtils.secure_compare`, nil for a blank token. `ApiToken.generate!(user, group:, name: nil)` keeps its signature and return value (the record with the raw token readable once, as today).

- [ ] **Step 1: Write the failing tests.** Model: a generated token authenticates; a wrong token, a revoked token and a blank string don't; authenticating issues one query whatever the number of active tokens (create 1 and 30, count queries, assert equal). `lookup_digest` never appears in an audit snapshot or field change (extend the loop in `snapshot_test.rb`). Migration test: an active token before the migration is revoked after it, has a `lookup_digest` that no raw token can produce (`"revoked:" + id`), and the migration's output states the count.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration**: add the column nullable, revoke active tokens (`revoked_at = now`), fill every row's `lookup_digest` with `'revoked:' || id`, set not null, add the unique index, remove `token_digest`. Raw SQL.
- [ ] **Step 4: Model**: remove `has_secure_password :token`; generate the raw token as today, store its digest, expose the raw value once.
- [ ] **Step 5: Fix the callers and tests** that built tokens with `token_digest:` (inventory C surprises 13) and the older migration test.
- [ ] **Step 6: MCP integration tests, setup wizard tests, the AI assistant tests green; unit suite green. Commit.** `fix: API tokens are looked up by an indexed digest; existing tokens are revoked`

---

### Task 14: Language changes under a row lock

**Spec:** §4.6, §10. **Inventory:** C §4.

**Files:**
- Modify: `app/services/locales/enable.rb`, `disable.rb`, `make_default.rb`, `configure.rb`, `app/services/settings/save.rb`
- Test: `test/services/locales/*_test.rb`, `test/services/settings/save_test.rb`

- [ ] **Step 1: Write the failing test** for each service: load the site row twice (`a = SiteSetting.find(id)`, `b = SiteSetting.find(id)`); through `a`, enable a language; then call the service under test with `b` as `Current.site`'s stale copy (the services read `Current.site`; set it with `Current.set`). Assert both changes are present afterwards. For `Settings::Save` with `languages:`, the stale copy's order save must fail with "must list exactly the enabled languages" (the list changed under it), not overwrite.
- [ ] **Step 2: Run, expect FAIL** (the second write drops the first).
- [ ] **Step 3: Implement**: in each service the transaction's first statement is `site.lock!` (which reloads the row); the "already enabled / disabled / default" checks and the computation of the new `locales` move inside, after it. In `Settings::Save`, take the lock before assigning attributes (`lock!` raises on a dirty record), and compute `site_part?` / `languages_part?` after it.
- [ ] **Step 4: Locales and settings tests green, `translation_state_parity_test.rb` green; commit.** `fix: two language changes at once can't lose one`

---

### Task 15: URLs synced only when they can have changed

**Spec:** §4.7, §10. **Inventory:** C §5. **Stronger model for the work and its review.**

**Files:**
- Modify: `app/models/concerns/has_public_paths.rb`, `app/models/page.rb`, `app/models/post.rb`, `app/models/public_site/paths.rb`
- Test: `test/models/public_site/paths_test.rb`, `test/models/page_test.rb`, `test/models/post_test.rb`

**Interfaces:**
- Produces: `HasPublicPaths#url_inputs` (a frozen Hash of the values the record's URLs depend on: for a page `slug` as stored jsonb, `parent_id`, `position`, `published_at`, `trashed_at`; for a post `slug`, `content_type`, `published_at`, `trashed_at`, and its tag ids), captured into `@url_inputs_before` in `before_save` and by `after_find`; `#url_inputs_changed?`. `PublicSite::Paths.sync_subtree(page)` and `sync_posts(…)` keep their signatures and become set-based. `PublicSite::Paths.rebuild!` is unchanged and is the reference the parity test compares against.

- [ ] **Step 1: Read first**, in full: the comments in `app/models/page.rb`, `app/models/public_site/paths.rb`, `app/models/page/tree_ranking.rb` and commit `da80c58`. The include order in `page.rb` fixes callback order; closure_tree's `after_save` reloads the record and clears the dirty flags, which is why the capture is in `before_save`.

- [ ] **Step 2: Write the parity test** in `paths_test.rb`: build a tree of about fifteen pages in three languages with listing blocks and posts; apply a scripted sequence through the services (rename a slug in one language, move a branch under another parent, reorder siblings, unpublish and republish a parent, trash a branch, restore it, trash a post, change a post's tags so its canonical listing page changes); after each step assert `PublicPath.order(:record_type, :record_id, :locale, :path).pluck(:record_type, :record_id, :locale, :path, :current)` equals the same pluck taken after `PublicSite::Paths.rebuild!` inside a rolled-back savepoint. Also assert after every step: no `(locale, path)` with two `current: true` rows. Run it **against the current code first**: it must pass (it pins today's behaviour).

- [ ] **Step 3: Write the query-count tests** (using the existing `capture_sql` helper): saving the homepage with only its title changed issues no statement touching `public_paths` or `page_hierarchies`; a slug change on a page with 20 descendants and one with 200 issues the same number of statements; a post save that changes only its excerpt issues none on `public_paths`. Run, expect FAIL.

- [ ] **Step 4: Implement the skip.** Capture `url_inputs` in `before_save` (and `after_find`, so the first save of a loaded record compares against what was loaded); in `after_save`, sync only when the record is new or `url_inputs_changed?`. Apply the same test to `public_paths_are_available` (an existing record whose inputs are unchanged cannot newly clash). Mind `place_among_siblings`, which renumbers `position` with `update_columns` after the capture: compare the requested position, not the renumbered one.

- [ ] **Step 5: Implement the set-based sync.** `sync_subtree`: one query for the subtree (ids, slugs, parent ids, positions, publication, trash state), one for its `public_paths` rows; compute paths in memory top-down; write only the rows that differ, through the existing `write` semantics (the old row becomes `current: false`; a URL another record holds is yielded to it as today). `sync_posts`: `canonical_pages(batch)` once.

- [ ] **Step 6: Run the parity test, the query-count tests, and every existing paths, page, post, trash, tags and public-routing test. All green with no assertion edited.**

- [ ] **Step 7: Full unit and system suites green; commit.** `fix: a page save syncs URLs only when they can have changed, and in a fixed number of queries`

---

### Task 16: A content version that moves only on published changes

**Spec:** §4.8, §4.9, §10. **Inventory:** C §6, §7. **Stronger model for the work and its review.**

**Files:**
- Create: `db/migrate/<timestamp>_create_public_site_versions.rb`, `db/migrate/<timestamp>_add_publication_indexes.rb`, `app/models/public_site/version.rb`, `lib/tasks/public_site.rake`, `test/models/public_site/version_test.rb`, `test/lib/version_bump_test.rb`
- Modify: `app/models/public_site.rb`, `app/models/page.rb`, `post.rb`, `content_block.rb`, `public_path.rb`, `media/asset.rb`, `site_setting.rb`, `post_tag.rb`; an initializer hooking `ActiveStorage::VariantRecord`; the services that write around callbacks (inventory C §6.4: `Trash::Move`, `Trash::Restore`, `Trash::Purge`, `Tags::Rename`, `Tags::Destroy`, `Tags::Merge`, `Locales::Enable`, `Locales::Disable`, `ContentBlocks::Reorder`, `Media::Upload`, `Page::TreeRanking`, `PublicSite::Paths`); `app/controllers/pages_controller.rb`; `app/models/rich_text/schema.rb`, `rich_text/document.rb`; `db/schema.rb`; `test/services/content_blocks/owner_touch_test.rb`, `test/integration/trash_visibility_test.rb`, `test/integration/public_caching_test.rb`

**Interfaces:**
- Consumes: Task 15 (fewer `public_paths` writes).
- Produces: table `public_site_versions` (`id`, `counter bigint not null default 0`, timestamps), one row, created by the migration. `PublicSite::Version.current` → Integer; `PublicSite.bump_version!` → an atomic `UPDATE public_site_versions SET counter = counter + 1` (creating the row if a test database has none) followed by `Current.content_version = nil`. `PublicSite.content_version` → `[ counter, Page.kept.published.maximum(:published_at), Post.kept.published.maximum(:published_at) ]` digested as today; `PublicSite.current_content_version` stays the per-request memo. `Publishable#live_before_or_after_save?` (D15). Indexes: `pages.published_at`, `posts.published_at`, `pages.updated_at`, `posts.updated_at`, `content_blocks.block_type`.

- [ ] **Step 1: Write the enumeration test** `version_test.rb`, one case per row, each asserting whether `PublicSite::Version.current` moved:

| Change (through its service) | Moves? |
|---|---|
| Edit a draft post's title; a draft page's title; a block of a draft page | no |
| Edit a live post's title; a live page's title; a block of a live page | yes |
| Publish, unpublish, schedule (future), trash, restore, purge a post | yes for each except schedule-only on a draft: no |
| Move a live page; rename its slug; reorder live siblings | yes |
| Reorder blocks of a live page; of a draft page | yes; no |
| Upload a library image; edit its alt; trash it; purge it | yes each |
| A variant record created for an image | yes |
| Save the site settings; enable, disable a language; make one default | yes each |
| Rename, merge, delete a tag carried by a live post | yes each |
| Change a live post's tags; a draft post's tags | yes; no |
| Group, user, token changes; an audit event; a translation confirmed on a draft | no |

Plus: the version read costs exactly three queries; two bumps in two threads both count (the increment is atomic); after `travel_to` just past a scheduled post's time, with no write, `PublicSite.content_version` differs.

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Migrations** (the table with its one row; the five indexes, added `algorithm: :concurrently` is not needed with no production — plain `add_index`).

- [ ] **Step 4: Implement** `PublicSite::Version`, `bump_version!`, the new `content_version`, the models' `after_commit` hooks using `live_before_or_after_save?` (for a block: its owner's own publication), the `VariantRecord` hook (`ActiveSupport.on_load(:active_storage_variant_record) { after_commit { PublicSite.bump_version! } }`), and the explicit bumps in the services that write around callbacks.

- [ ] **Step 5: Write the guard** `test/lib/version_bump_test.rb`: in `app/`, any line calling `update_all`, `update_columns`, `update_column`, `touch_all`, `insert_all`, `upsert_all`, `delete_all` or `destroy_all`-less raw SQL writes on `Page`, `Post`, `ContentBlock`, `PublicPath`, `Media::Asset`, `SiteSetting`, `Tag` or `PostTag` (matched by receiver constant or, inside those models, bare calls) must be in a file that also calls `PublicSite.bump_version!`, or carry `# version: none (reason)` on the line. Run it; resolve each hit.

- [ ] **Step 6: The request path.** In `PagesController#show` resolve the record without preloading, call `stale?`, and run the block, asset and variant preload only when rendering. Memoise `RichText::Schema.version` per process until the registry changes, and `Document#digest` per document instance.

- [ ] **Step 7: Rake task** `public_site:bump_version` (prints the new counter).

- [ ] **Step 8: Adapt the tests that assumed any write moves the version** (`owner_touch_test.rb` uses a draft page; `trash_visibility_test.rb`'s version test; `public_caching_test.rb`): give them live records, with that reason in the report. No other assertion changes.

- [ ] **Step 9: Enumeration test, guard, public-caching, rich-text and trash tests green; full unit and system suites green. Commit.** `fix: the public content version moves only when published output can have changed`

---

### Task 17: Split `CLAUDE.md`

**Spec:** §3.8, §10. **Inventory:** B §6.

**Files:**
- Create: `docs/reference/page-tree-and-routing.md`, `content-blocks-and-types.md`, `cs-studio-shell-and-dashboard.md`, `design-system.md`, `save-rule-and-write-queue.md`, `editors-and-translation-pair.md`, `settings-languages-ai.md`, `media.md`, `trash.md`, `access-control-and-audit.md`, `users-groups-tokens.md`, `rich-text.md`, `translations.md` (and `i18n.md` from Task 6); `script/check_claude_split.rb`
- Modify: `CLAUDE.md`; every file that refers to a section of `CLAUDE.md` by name (inventory B §6.5)

**Interfaces:**
- Consumes: Tasks 1–16, each of which has already corrected the passages its change made false (each task's report lists them; apply any that were deferred to here first).

- [ ] **Step 1: Bring the text up to date** before moving it: apply the `CLAUDE.md` corrections Tasks 1–16 reported (test rules, the dependency guard, the i18n scheme, one grant per permission, dormant names, the stale check, the owner endpoint, token digests, the row lock, URL sync, the content version). Verify each sentence you touch against the code.
- [ ] **Step 2: Keep a copy** of that corrected file as the check's input (`tmp/CLAUDE.before.md`, not committed).
- [ ] **Step 3: Move** the description passages by the mapping in inventory B §6.4, paragraph by paragraph. Where a pitfall is the last sentence of a description paragraph (the two-pages-one-URL and nil-position warning, the Accept-header regression, the promoted-visit test trap), the pitfall sentence stays in `CLAUDE.md` under "Pitfalls" and the rest moves. Each reference file starts with one line saying which directories it describes.
- [ ] **Step 4: Write the index** in `CLAUDE.md`: one rule per topic, "Before changing <what>, read `docs/reference/<file>.md`", naming the directories it covers. Keep in `CLAUDE.md`: what the repo is, setup and commands, the test rules and traps, Key Conventions, Pitfalls, the index.
- [ ] **Step 5: Run the check.** `script/check_claude_split.rb tmp/CLAUDE.before.md` splits the old file into sentences (on `. `, `: ` before a list, and list items; code spans kept whole) and asserts each occurs exactly once across the new `CLAUDE.md` and `docs/reference/*.md`, ignoring whitespace and the new connective lines listed in an `ADDED` array at the script's top. Paste its output into the task report. Expected: "0 missing, 0 duplicated".
- [ ] **Step 6: Fix the references** elsewhere that name a `CLAUDE.md` section (code comments, the staff review, the roadmap, the specs): point them at the reference file.
- [ ] **Step 7: Report the sizes** before and after. Commit. `docs: CLAUDE.md keeps the rules; the descriptions move to docs/reference`

---

### Task 18: Sweep

**Spec:** §5 step 18, §7.

**Files:**
- Modify: `docs/roadmap.md`, `docs/reference/*.md`, `docs/superpowers/specs/2026-10-05-technical-cleanup-design.md` (status), anything the checks below turn up

- [ ] **Step 1: Leftovers.** `git grep` returns nothing outside docs history for what this plan removed: `has_secure_password :token`, `token_digest`, `StarterContent.ensure_home!`, `StarterContent.add_once!`, the local `assert_eventually(timeout:` and `wait_until`, `js_errors: false`'s old comment, the non-unique grants index name in code comments. No dead importmap pin, partial, helper or preview.
- [ ] **Step 2: Reference files against the code.** For each `docs/reference/*.md` passage that a task of this plan changed, open the code and confirm the sentence.
- [ ] **Step 3: Roadmap.** Re-read `docs/roadmap.md` immediately before editing (another session may edit it); small targeted edits; commit it alone. Move to Shipped: the technical cleanup, with this spec. Close the rows this plan resolves: under "Before the first deploy", the token digest, lost updates, dormant grant names, grants per permission, the owner flag, guarantees by behaviour, the locales row lock, and performance steps 1 and 2; under Technical health, the dependency inversions, the fixed sleeps, system tests failing on JavaScript errors and clicking natively, the `CLAUDE.md` size row, the `queue.js` part of the split row, the indexes row, `AccessControl.holds?`. Add a row for each interim state the task reports name.
- [ ] **Step 4: Static checks.** `bin/rubocop`, `bin/brakeman --no-pager` (exit 0; a new warning is restructured, not ignored), `bin/importmap audit`, `bin/bundler-audit`.
- [ ] **Step 5: Suites.** The unit suite once; the system suite three times in a row. Every failure named, run alone, explained.
- [ ] **Step 6: Mark the spec** as implemented, with any ruling that changed a decision added to its §10. Commit. `docs: the technical cleanup, swept`
