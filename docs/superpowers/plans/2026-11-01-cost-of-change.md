# Cost of change and the image looks: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ContentSpiel cheaper to change (short `CLAUDE.md`, a stale-stylesheet notice, no silently dropped words, no schema noise, measured test time) and ship the image looks the owner decided.

**Architecture:** Independent commits on one branch. No runtime behaviour changes but the three named: the development notice, the refused key, and the image words and mark. `CLAUDE.md`'s rules move to `docs/reference/`, proven by a one-off script.

**Tech Stack:** Rails 8.1, Minitest, ViewComponent, Tailwind, Postgres 17.

**Spec:** `docs/superpowers/specs/2026-11-01-cost-of-change-design.md` (approved 2026-11-01; image quality stays two fields).

## Global Constraints

- Every test command starts `PGGSSENCMODE=disable`. No build while tests run. The worktree runs `bin/rails db:test:prepare` once.
- The full browser suite is CI's. Run only the browser files a task names, after `bin/rails tailwindcss:build`, with `sysctl -n vm.loadavg` under 6.
- New admin strings are keys. CS Studio uses tokens only. Nothing of any client site enters this repository.
- `Media::PictureComponent` stays one `<img>` with no wrapper and no script.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`. Never skip hooks. Implementers do not push, and do not post on GitHub.

## Review Focus

1. A rule moved out of `CLAUDE.md` whose test citation or "No guard" sentence is lost: Task 6's script must report zero missing, and its check must be able to fail.
2. A caller of `ContentBlocks::Save` that has always sent an extra key under a language (a form's hidden field, the AI Use, MCP) now failing: Task 2's test goes through each real caller.
3. The stale notice on a page in production or test, or a notice that stops a page drawing: Task 1 tests both.
4. The image mark in dark mode or on a theme that overrides `--th-meta`: Task 4 holds the mark's colour to the token in both schemes; a theme override is reported in the reference as not followed.
5. Plural and zero wording on the Images card and System status (1 image, 0 images, made equals total, some failed and some waiting): Tasks 4 and 5 test each.

---

### Task 1: a stale stylesheet says so

**Files:** Modify `lib/theme_folder.rb`, `app/controllers/concerns/public_page_rendering.rb` and whatever draws today's theme refusal on a public page (find it from `Theme.prepare` and `docs/reference/theming.md`). Test `test/integration/theme_pages_test.rb`, `test/lib/` beside the existing theme folder tests.

**Interfaces:** Produces `ThemeFolder#stylesheet_stale?(root) -> Boolean`.

Note: `fingerprint` answers the constant `DEFAULT_FINGERPRINT` for the default theme, so `built?` cannot see a default theme's change. For the default theme, compare the mtime of `app/assets/builds/theme.css` with the newest file under `app/assets/tailwind/themes/default/`. For a configured theme, stale is `!built?(root)`. `fingerprint` digests every file, so cache the answer for about two seconds in development.

- [ ] Write failing tests: "in development a theme changed since its stylesheet was built says so on the public page, naming the rebuild command, and the page still draws"; "a freshly built stylesheet says nothing"; "the default theme's changed stylesheet file says so"; "production and test never say it".
- [ ] Run them: they fail.
- [ ] Implement. Notice in development only, in the same place as the refusal, in the same style, naming `bin/rails tailwindcss:build`. Add the paragraph to `docs/reference/theming.md`.
- [ ] Run the tests and `test/integration/theme_pages_test.rb`: they pass.
- [ ] Commit `feat: in development a stale public stylesheet says so`.

### Task 2: a save never drops words (#147)

**Files:** Modify `app/services/content_blocks/save.rb` (`assign`, around line 240; `TRANSLATED = %i[caption alt body]`). Test `test/services/content_blocks/save_test.rb`.

**Interfaces:** A call with an unknown key answers not ok; `result.errors` names the keys.

- [ ] Write failing tests: `translations: { "en" => { title: "T", text: "X" } }` on a Card answers not ok, the message names `title` and `text`, and nothing is written or audited; `caption`, `alt`, `body` and `settings` under a language still save; an unknown locale and unknown keys inside `settings` behave as before.
- [ ] Run them: they fail.
- [ ] Implement the refusal before anything is written.
- [ ] Find every caller (`grep -rn "ContentBlocks::Save" app lib`). Where a caller sends an extra key, strip it at the caller. Add a test through each caller that sends translations (the block form, AI Use, MCP if it does).
- [ ] Check `Posts::Save` and `Pages::Save` for the same drop. Report only, unless the same bug exists with a caller that hits it today.
- [ ] Run `test/services/content_blocks`, `test/integration/admin/content_blocks_test.rb`, `test/services/ai`: they pass.
- [ ] Commit `fix: a block save refuses translated keys it would drop (#147)`.

### Task 3: `db/schema.rb` noise

**Files:** Possibly a new migration, `db/schema.rb`, `CONTRIBUTING.md`.

The likely two are `note_threads_state` and `presence_marks_state_known` (`db/schema.rb:289,388`: `state::text = ANY (ARRAY[...])`). Verify: others may differ.

- [ ] On the pinned Postgres 17, run `bin/rails db:migrate` then `git diff db/schema.rb`, and record the result. If no diff here, say so: then the noise is another version's.
- [ ] If a form dumps alike, rewrite the constraints in a migration so a dump is stable, and show a second migrate gives no diff. Otherwise add two lines to `CONTRIBUTING.md`: dump on the pinned version and revert the noise.
- [ ] Stop after one attempt at each: report and leave it rather than grow this.
- [ ] Run `test/lib/built_in_data_test.rb` and any test of those constraints: they pass.
- [ ] Commit `chore: db/schema.rb dumps without noise` (or `docs:` for the note).

### Task 4: the image looks on the site and the card

**Files:** Modify `app/assets/tailwind/themes/default/images.css`, `app/components/admin/settings_screen/images_card_component.{rb,html.erb}`, `images_dialog_component.{rb,html.erb}`, `config/locales/admin/settings_screen.en.yml`, `docs/reference/media.md`. Test `test/system/image_box_test.rb`, `test/integration/design_tokens_test.rb`, `test/components/admin/settings_screen/`, `test/integration/admin/settings*`.

Exact words (the spec's, with plurals):
- `avif_note`: "Smaller files, slower to make; very old browsers show no image. Animated images are always made in WebP, at the WebP quality."
- progress: "12 images were made with other settings" / "1 image was made with other settings", with the count `total - made`. Nothing shown when none. "There are no images yet." stays.
- dialog body: "Remake 12 images? This runs in the background and can take a few minutes." / "Remake 1 image? …". The zero case stays as it is.
- while running: "Regenerating: 5 of 12". The card has no live refresh, and adds none: read from the saved counts at page load, shown when a regenerate is in progress (use what `Media::RenditionProgress` and the job state already say; if nothing says a run is in progress, show this line only while images are outstanding after a press, and report the choice).
- failures: "2 could not be made" / "1 could not be made", a link to System status.
- Both quality fields stay.

- [ ] Write failing tests for each string and plural, and for the mark: `img[data-image-empty]` has a centred, non-repeating background, its colour equals `--th-meta` in both schemes, and the element is still one `<img>`.
- [ ] Run them: they fail.
- [ ] Implement. The mark is 28px, the Design System's image mark, one data-URI per scheme.
- [ ] Update the guide-independent reference, `docs/reference/media.md`.
- [ ] Build the CSS, run the named tests: they pass.
- [ ] Commit `feat: the image mark and the Images card's decided words`.

### Task 5: System status and Download original

**Files:** Modify `app/models/setup/system_check.rb` (`images`, around line 302), `app/components/admin/media_library/panel_component.html.erb`, `config/locales/admin/media_library.en.yml`. Test `test/models/setup/system_check_test.rb`, `test/integration/admin/system_status_test.rb`, the panel's component test.

Words: "All images are ready." / "8 images are still being made." / "1 image is still being made." / "2 images could not be made." / "1 image could not be made." Waiting count is `total - made - failed`; when both exist, both sentences show. A row with waiting or failed images stays `:warning`; zero images is "All images are ready." Panel: the existing link under the file details, with `text-sm text-meta` line "Only editors can download the original." (a key).

- [ ] Write failing tests for each state and for the panel's line, then see them fail.
- [ ] Implement.
- [ ] Run the named tests: they pass.
- [ ] Commit `feat: System status's and the media panel's image words`.

### Task 6: shrink CLAUDE.md (#109)

**Files:** Modify `CLAUDE.md`, `docs/reference/*.md`. Create `docs/reference/writing-tests.md`. Update code and test comments that point at a moved rule where a grep finds them.

Follow the spec's Part 1 exactly. Before starting, copy `CLAUDE.md` to `/private/tmp/claude-501/-Users-dknafelj-src-ContentSpiel/dd7bb8f3-e1e2-40d2-a449-0b6c377c5f48/scratchpad/CLAUDE.old.md`.

- [ ] Write the one-off script in the scratchpad: extract from the old file every `` `test/…` `` path, every quoted test name after such a path, and every sentence with "No guard" or "no guard". Report any not found, whitespace-normalised, in the new `CLAUDE.md` plus `docs/reference/*.md`. Prove it can fail by running it on an empty file.
- [ ] Move "Setup & Commands"' test rules to `writing-tests.md`, add its index line and one pointer line.
- [ ] Move each guarded rule whole to the file the index names. Unguarded rules stay whole. A mixed rule moves whole, with one or two standalone sentences left in `CLAUDE.md` naming the file.
- [ ] Replace the `Admin::` bullet with two sentences pointing at `test/lib/admin_namespace_shadow_test.rb`.
- [ ] Run the script: zero missing. Run `wc -w CLAUDE.md`: report it (target under 5,000; never cut an unguarded rule to reach it). Save the output in the report.
- [ ] Run `test/lib/source_layout_test.rb test/lib/theming_reference_test.rb` and the whole of `test/lib`: they pass.
- [ ] Commit `docs: CLAUDE.md holds the index, the commands and the unguarded rules (#109)`.

### Task 7: measure the tests

**Files:** none in the repository. Report `.superpowers/sdd/2026-11-01-cost-of-change/test-times.md`.

- [ ] Run the unit suite locally once with per-test times (`bin/rails test -v`), and read CI's timing for the last green run with `gh run view --log`.
- [ ] From `test/system_test_seconds.yml` and CI's log, list the slowest 20 browser files and unit files.
- [ ] Measure `sign_in_via_form` in one browser run of a small file, multiply by the sign-ins in the suite (a grep), and give its share.
- [ ] Count in `git log` how many merged PRs touched guard tests only to follow a moved line, as far as commits show it.
- [ ] Say why the unit suite takes 9.5 minutes on CI (boots, production-boot tests, workers on two cores).
- [ ] Write a table with a recommendation per #118, #133 and #134. No commit: the controller puts it in the PR body and on the issues.

### Task 8: the guide (after the rest, in `~/src/contentspiel-docs`)

**Files:** a new `docs/integrators/theming/quick-start.md`; modify `what-a-theme-is.md`, `build-a-theme.md`, `administrators/site/site-settings.md`, `administrators/operations/system-status.md`, `editors/media/the-media-library.md`. Follow `docs/STYLE.md`. Commit, do not push (the controller pushes after the merge).

- [ ] Verify #148: does a theme's `assets/images/icons/calendar.svg` collide with the CMS's? Reproduce with `theme:check` on a scratch copy. Rename the guide's example and state the rule.
- [ ] Write the quick start: about two screens. `theme.yml`, template locals, links to the Section and Card tables, the `settings:` seed example, the `.to_h` note, the rebuild and its notice. Generic examples only.
- [ ] Update the three image pages to the decided words.
- [ ] Run `bin/check`: no problems. Commit.

### Task 9: the filter bar's one height (owner delegated to a design agent, 2026-11-01)

Rule (Design System): "Controls in one row share one height. Forms are 42px; a filter bar is 38px, set by the bar, never by a control."

Heights today, from the classes: select 42, search 38, segment 34, "Clear" 42. Text sizes stay 16px and 14px.

Files:
- `content-spiel.css`: `--cs-control-compact: 2.375rem`, written once; the public theme does not import it.
- `Admin::FilterHelper#filter_form_options`: class `admin-filter-bar mb-4 flex flex-wrap items-start gap-3`.
- `content-spiel.tailwind.css`, all under `.admin-filter-bar`:
  - `> div, > fieldset`: `display: flex`.
  - `input:not(.sr-only), select, a.inline-block, button`: `min-height: var(--cs-control-compact); padding-block: 0`; the link and button also `display: inline-flex; align-items: center`.
  - `fieldset label`: `min-height: calc(var(--cs-control-compact) - 2px); padding-block: 0`.
- Use min-height, never a group height: media's segments wrap and the group clips. Posts' segment group gains `flex-wrap`.
- The audit log's subject chip (34px) in its bar is included. Check the translations bar. Standalone segments and Trash tabs stay 34.

The design agent wrote this without rendering it. Verify in a browser test; unlayered CSS beats utilities, so a `py-*` beside `.cs-select` is dead.

Tests: the token is written once (`test/lib/admin_design_rules_test.rb`); a system test measures every control of the bar at one height on Posts, Media, the media picker and the audit log, at a wide window, and that a wrapped row still shows every segment. Update `docs/reference/design-system.md`.
