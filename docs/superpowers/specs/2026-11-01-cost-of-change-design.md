# Cost of change, and the image looks the owner decided

Decided by the owner 2026-11-01 ("ok" to the scope below). One pull request, on `main` after #108, in separate commits per part so each can be reviewed alone. It closes #109, #147 and #148. It does not close #118, #133 or #134: part 5 measures first.

## Why

ContentSpiel gets dearer to change with every feature, and the evidence of 2026-11-01 says where:

- `CLAUDE.md` is about 29,000 words, loaded whole into every session and every agent. About 214,000 words of docs sit beside it.
- CI takes about 9.5 minutes, and the unit suite alone takes those 9.5.
- A theme author (a real theme built beside the CMS) lost time to a stale stylesheet that looked like a theme bug, to a save that reported success and dropped the words, to long reference files that mix what an author needs with CMS internals, and to a migration that rewrote `db/schema.rb`.
- Production telemetry (the documentation site, 24 hours, little traffic) shows no bottleneck: public pages 93 ms typically, 266 ms at the 95th percentile. So this work does not touch runtime performance.

The image looks are here because the owner answered the Design System's last questions and asked for them in this one follow-up.

## Goals

1. An agent or a person starts from a short `CLAUDE.md` and finds the rule they need in the reference file for what they touch, with no rule lost.
2. A theme author is told when their stylesheet is stale, is never told a save worked when it dropped words, and has one page to start from.
3. A local migration leaves no formatting noise in `db/schema.rb`.
4. We know where test time goes, and decide #118, #133 and #134 from that.
5. The image screens read as the owner decided.

## Non-goals

- No change to a rule's meaning, to any guard test's behaviour, or to runtime performance.
- No rewrite of the reference files beyond receiving moved rules (#119 stays open).
- No new theme tooling such as a `theme:dev` watcher: `bin/dev` already watches; the warning is the cheap fix.
- No test-suite speed work in this PR beyond the measurement.
- Cards with images and page links (#144, #145, #146) come after this PR.

## Anti-goals

- A rule that silently disappears. Moving is fine; losing is the failure this part can cause, and nothing would fail loudly.
- A shrunk `CLAUDE.md` that drops the unguarded rules, which are the ones that need a reader most.

## Part 1: shrink CLAUDE.md (#109)

`CLAUDE.md` keeps: what the repository is, setup and commands, the reference index, the conventions, and every rule with **no guard** (the issue counts about 30), each still in full. A rule a guard holds moves whole, wording and test citations intact, to the reference file the index names for it, and leaves at most one line in `CLAUDE.md`. The long test-writing paragraph in "Setup & Commands" moves to a new `docs/reference/writing-tests.md`, with a one-line pointer and the index gaining a line. The `Admin::` constants bullet becomes two sentences pointing at `test/lib/admin_namespace_shadow_test.rb`.

A rule that is partly guarded and partly not (many end "**No guard** for …") moves whole to its reference file, and `CLAUDE.md` keeps one or two sentences that say the unguarded part so they read alone, naming the reference file. They may be reworded for that; the original sentence stays word for word in the reference file. (Implementer's call: orphaned tails would be unreadable.)

Target: under 5,000 words. It is a target, not a limit: an unguarded rule is never cut to reach it.

**Done when** a script run for the PR, and its output in the PR, shows every test name and every `No guard` sentence cited in the old `CLAUDE.md` is present in the new `CLAUDE.md` or in a `docs/reference/` file. The script is a one-off in the PR's description and is not committed. `test/lib/source_layout_test.rb` and `test/lib/theming_reference_test.rb`, which read these files, stay green. Comments in code and tests that say `CLAUDE.md, "Rules a change can break silently"` are updated where the rule moved (the builder's search; a stale pointer is minor, a broken guard is not).

`docs/getting-started.md`, nested `CLAUDE.md` files and the review rule that #109 also suggests are left out, and the issue is closed with a comment saying so, or a smaller issue is opened for them (the builder's call).

## Part 2: a stale stylesheet says so (Nordlicht, item 1)

In development, when the built stylesheet's stamp no longer matches the theme in use (`ThemeFolder#built?`, the check production already boots under, if its fingerprint covers the files the build reads; otherwise the stylesheet is compared with the newest of those files, a `theme.yml` and templates included), for a theme folder and for the default theme alike, the public page says so, in the same place and way a theme refusal already says why on every public page (`Theme.prepare`, `docs/reference/theming.md`), naming the command that rebuilds. It never stops a page drawing, and production and test never see it. The check costs a few `stat`s; if the builder finds it noticeable per request, it may be cached for a second or two.

Tested with the default theme and a copied theme (`with_theme_copy`): stale says it, fresh does not, production does not.

## Part 3: a save never drops words silently (#147)

`ContentBlocks::Save` refuses a key under `translations[locale]` that it would otherwise drop (anything but the translated columns, `body` and `settings`; an unknown locale and unknown keys inside `settings` keep today's behaviour, as implementer's call), answering not ok with an error that names the keys, as #147 asks ("Done when" there: the call answers not ok and names `title` and `text`). Check every caller, the block forms, duplicate, discard, the AI Use and the MCP path, so none now fails for a key it sends and has always had dropped: such a key is removed at the caller. The same `assign` shape in other services is checked and reported, not changed, unless it has the same bug.

A seed example for a block with translated settings goes into the guide with part 4.

## Part 4: a theme author's one page, and the guide (#148)

- **Quick start:** one page in the guide (`contentspiel-docs`, `integrators/theming/`) of about a screen or two: `theme.yml`, template locals, the Section and Card method tables or links to them, seeding with the `settings:` example and the `.to_h` note on a rich-text body, and the rebuild. `what-a-theme-is.md` links to it.
- **#148:** the guide's example `icons/` folder no longer collides with the CMS's `calendar.svg` and `check.svg`. Verify the collision first, then rename the example, and document the rule if a theme's asset name can shadow the CMS's at all.

These are guide changes: a separate commit in `~/src/contentspiel-docs`, which the implementer may edit and commit but not push; the controller pushes after the merge as usual. Generic examples only: no agency's theme, classes or colours.

## Part 5: measure the tests, then decide #118, #133, #134

Measure, do not change. One unit-suite run and one browser-suite run with per-test times, taken from a CI run on a throwaway commit or by CI's own output, not from a local browser run (`test/system_test_seconds.yml` is an acceptable source for per-file browser times), reporting: the slowest 20 files in each; the share of browser-suite time spent signing in through the form (which decides #134); how many guard tests failed in the last 20 merged PRs' history for a line that only moved, as far as commits can show it (which decides #118); and why the unit suite takes 9.5 minutes on CI (boots, migrations, production-boot tests, parallel workers on two cores).

The result goes in the PR body as a short table with a recommendation per issue, and the controller posts it as a comment on #118, #133 and #134. The owner decides; nothing is built from it here.

## Part 6: `db/schema.rb` noise

A local `db:migrate` rewrites two check constraints with formatting differences only, probably by Postgres version (`docker-compose` pins 17; a contributor's or site's own Postgres may differ). Find which constraints and why. The bar is a migrate on the pinned Postgres 17 writes no diff, and another version is tried only if one is at hand. Fix it by rewriting the constraints in the form every version dumps alike or, if no such form exists, by dumping on one pinned version and saying so in `CONTRIBUTING.md`. If neither is reachable cheaply, report and leave it: this part must not grow into a schema tooling project.

## Part 7: the image looks

`docs/reference/media.md` and the Design System's Image loading page govern. Most of this already exists from #107 with placeholder words, so this part changes words and small layout, and no behaviour unless named.

- **The empty box:** `img[data-image-empty]` gets a 28px image mark at its centre, in `th-meta`, on the sunken ground. `Media::PictureComponent` stays one `<img>` with no wrapper and no script (a guarded rule), so the mark is a centred, non-repeating CSS background in `app/assets/tailwind/themes/default/images.css`. A data-URI SVG cannot read a token, so the builder picks a way that follows `--th-meta` in both schemes (for instance one value per scheme, held to the token's value by a test), and it never draws on a missing image's placeholder.
- **Settings → Images card** (`Admin::SettingsScreen::ImagesCardComponent`, `images_dialog_component`, `config/locales/admin/settings_screen.en.yml`):
  - AVIF note: "Smaller files, slower to make; very old browsers show no image." The sentence that animated images are always WebP stays, as a second sentence: it is true and otherwise unsaid.
  - The progress line becomes "12 images were made with other settings" (with singular, and nothing shown when none), the count being the images not made with the saved settings.
  - Regenerate's confirmation: "Remake 12 images? This runs in the background and can take a few minutes."
  - While it runs: "Regenerating: 5 of 12". Whether the card refreshes by itself or on reload is the builder's: if the page already has no live refresh, it says the count as of the page's load, and no new polling is added.
  - Failures: "2 could not be made", linking to System status.
  - **Quality stays two fields, WebP and AVIF, with their defaults of 75 and 50.** The owner approved a recommendation that said one field, default 80, written without looking at the built card. The same number means a different quality in each format, so one field would be wrong for whichever format it was not tuned for. **Awaiting the owner's confirmation before the build.** The controller corrects the Design System page.
- **System status's Images row** (`Setup::SystemCheck#images`): "All images are ready." / "8 images are still being made." / "2 images could not be made." (a warning). When some are being made and some failed, both sentences show. Whether a row that is only still making images is `:warning` as now is unchanged.
- **Download original** (`Admin::MediaLibrary::PanelComponent`): a plain text link under the file details, with one small line under it: "Only editors can download the original."

The Design System's Image loading page is updated to "built" when merged; design questions found on the way are reported, not decided.

## Constraints

Standing project rules apply: `CLAUDE.md`'s rules and guards, new admin strings as keys, tests first, CS Studio tokens only, `PGGSSENCMODE=disable` on every test command, browser suite left to CI. Nothing of any client site enters this repository: fixtures are generic. Fixes are done by subagents; the owner merges.

## Architecture review findings

Closes #109. Takes #118, #133, #134 only as far as measuring. Touches #119 (reference files receive moved rules; no split). Leaves the rest.

## Documentation

Guide pages: `administrators/site/site-settings.md`, `administrators/operations/system-status.md`, `editors/media/the-media-library.md`, the new quick start, and `integrators/theming/build-a-theme.md` for #148.

## Left to the builder

Commit order and task split; which reference file receives a rule the index does not clearly place; how the stale check is cached; the mark's exact drawing, as long as it is the Design System's image mark.
