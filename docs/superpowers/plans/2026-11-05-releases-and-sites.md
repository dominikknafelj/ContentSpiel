# Releases and new sites: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CMS release has a number, notes and an image; one line installs a `contentspiel` command; `contentspiel new | generate | dev | check | upgrade` start, extend, run and update a site without a CMS checkout.

**Architecture:** Everything a command does lives in the CMS image behind one entrypoint, `bin/contentspiel` (Ruby, run by the image). The host side is two POSIX shell files: `install.sh` (puts the wrapper in place) and the wrapper (picks the version, runs the image). Releases are cut through a pull request and published by a workflow on the tag.

**Tech Stack:** Ruby 3.4 / Rails 8.1 (the image), POSIX `sh`, Docker, GitHub Actions, Kamal.

**Spec:** `docs/superpowers/specs/2026-11-05-releases-and-sites-design.md` (approved 2026-11-05; read "Decided with the owner" and "Settled after the builder check").

## Global Constraints

- Versions are `0.x.y`. Tag `v0.5.0`, image tags `0.5.0` and `stable`; commit tags stay.
- The image name is `ghcr.io/dominikknafelj/content_spiel`, one constant (`ContentSpiel::IMAGE`) beside `ContentSpiel::VERSION` in `lib/content_spiel/version.rb`.
- The site's pin is the file `.contentspiel-version`, one line, a version.
- The wrapper and `install.sh`: `#!/bin/sh`, `set -eu`, no `sudo`, readable in one sitting (each under about 120 lines). The wrapper's only network use is image pulls. The install script downloads the wrapper from the same release.
- The wrapper hands every argument to the image's `contentspiel` entrypoint unchanged. That hand-over is the one promise between them, held by a test.
- A generated site holds no secret value: `deploy.yml` names secrets by variable only; no `.kamal/secrets` with values.
- Generic content only: no client site's names, copy or design in the template.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `PGGSSENCMODE=disable` on every test command. Never skip hooks. Implementers do not push.

## Review Focus

1. A host where `~/.local/bin` is not on `PATH`, or Docker is missing or not running: `install.sh` says what to do and exits non-zero without writing half a setup (Task 3 tests both).
2. A file created by the container in the mounted site folder owned by root on Linux: the wrapper runs with the host's uid and gid (Task 3, asserted on the `docker run` line it builds).
3. `contentspiel new` into a folder that exists, or a name that is not a folder name: refused, nothing written (Task 4).
4. `upgrade` when the site is already on `stable`, when the pin is not a version, and when `theme:check` fails under the new image: no pin is moved in the last two, and the first says so (Task 6).
5. A release cut twice for one version, or from a dirty tree: the release command refuses (Task 2).

---

### Task 1: the version and the changelog guard

**Files:** Create `lib/content_spiel/version.rb` (`ContentSpiel::VERSION = "0.1.0"`, `ContentSpiel::IMAGE`), require it from `config/application.rb` beside the other early `lib/` files. Create `bin/changelog-guard`. Modify `.github/workflows/ci.yml` (a step in the `lint` job, pull requests only, `fetch-depth: 0`). Create `.github/pull_request_template.md` with the one checkbox the spec names. Tests: `test/lib/content_spiel/version_test.rb`, `test/lib/changelog_guard_test.rb`.

**Interfaces:** Produces `ContentSpiel::VERSION`, `ContentSpiel::IMAGE`; `bin/changelog-guard BASE_REF` exits 1 naming the file when a guarded file changed and `CHANGELOG.md`'s "## Unreleased" section did not.

Guarded files: `test/support/contract_ledger.rb`, `lib/content_spiel/plugins.rb`, `docs/reference/hosting.md`'s variables section is NOT guarded (prose); environment changes are guarded by the PR template's checkbox only.

- [ ] Tests: "VERSION is three numbers and IMAGE the registry's name"; the guard, run on a throwaway git repo made in the test's tmp dir: a ledger change with no changelog change fails and names the ledger; with a line added under "## Unreleased" it passes; a change of another file passes.
- [ ] See them fail, implement, see them pass.
- [ ] Commit `feat: the CMS's version, and the changelog guard on pull requests`.

### Task 2: cutting a release

**Files:** Create `lib/tasks/release.rake` (`bin/rails 'release:prepare[0.5.0]'`), `.github/workflows/release.yml`. Modify `.github/workflows/image.yml` (nothing but a comment pointing at release.yml, unless the release workflow needs its job reused). Test `test/lib/release_task_test.rb`. Doc: `docs/reference/hosting.md` gains "Releases".

**Interfaces:** Consumes Task 1's `VERSION`. `release:prepare[V]` refuses a dirty tree, a `V` that is not greater than `VERSION`, an existing tag `vV`, and an empty "## Unreleased"; otherwise it writes `VERSION`, renames "## Unreleased" to "## V (YYYY-MM-DD)" with a fresh empty "## Unreleased" above, and prints the `git switch -c release-V`, commit and `gh pr create` commands to run (it runs none: pushing stays the person's).

`release.yml`: on a merge to `main` whose `VERSION` differs from the newest `v*` tag: tag `vV`; retag the commit's amd64 image as `V`; build and push `linux/arm64` from the commit on an `ubuntu-24.04-arm` runner; join both into the manifests `V` and `stable` (`docker buildx imagetools create`); create the GitHub Release with that version's changelog section as notes and `install.sh` and `contentspiel` (Task 3) as assets.

- [ ] Tests of the rake task on a copy of the repo's `CHANGELOG.md` and version file in tmp (each refusal, and the rewrite's exact output).
- [ ] See them fail, implement, see them pass.
- [ ] `actionlint` if installed; else read the workflow against the spec. Note in the report that the workflow is unproven until the first release.
- [ ] Commit `feat: cutting a release: release:prepare and the release workflow`.

### Task 3: the installer and the wrapper

**Files:** Create `install/install.sh` and `install/contentspiel` (the wrapper). Test `test/lib/install_scripts_test.rb` (runs the scripts with a fake `docker` and `curl` first on `PATH`, recording their arguments). `shellcheck` both if installed.

**Interfaces:** The wrapper: version = first line of `./.contentspiel-version` walking up to `/`, else `stable`; runs `docker run --rm -it` (no `-t` when not a terminal) `--user "$(id -u):$(id -g)" -v "$site:/site" -w /site "$IMAGE:$version" contentspiel "$@"`, where `$site` is the folder holding the pin, else the current folder; `contentspiel dev` is the one command it runs differently: `docker compose -f .contentspiel/compose.yml up` (the file Task 5 writes). `install.sh`: checks `docker version` works, downloads `contentspiel` from the same release into `~/.local/bin`, `chmod +x`, says how to add `~/.local/bin` to `PATH` when it is missing.

- [ ] Tests: version from a pin in the folder and in a parent; `stable` without one; arguments handed over unchanged (spaces, quotes, `--flags`); uid and gid on the line; `dev` runs compose; install with no Docker exits 1 and writes nothing; with Docker it writes an executable wrapper; PATH hint shown when missing.
- [ ] See them fail, implement, see them pass.
- [ ] Commit `feat: the installer and the contentspiel wrapper`.

### Task 4: the entrypoint and `new`

**Files:** Create `bin/contentspiel` (Ruby, the image's entrypoint: `new`, `generate`, `check`, `upgrade`, `dev-files`, `--version`, `help`; unknown → help, exit 2). Create `lib/site_template/` (the files `new` writes, as `.tt` templates) and `lib/content_spiel/site_generator.rb`. Reuse `theme:new`'s copying (call its code, do not copy it). Test `test/lib/site_generator_test.rb`.

**Interfaces:** Consumes `VERSION`, `IMAGE`, the theme scaffold. Produces `ContentSpiel::SiteGenerator.new(path).write` and the folder: `theme/` (as `theme:new`), `Dockerfile` (`ARG CMS_VERSION`, `FROM ${CMS_IMAGE}:${CMS_VERSION}`, the theme copied in, `theme:check` before `assets:precompile`, as the docs site's), `config/deploy.yml` (placeholders for the service, image, server, `PUBLIC_HOST`, the registry; `builder.args.CMS_VERSION` read from `.contentspiel-version`; secrets by name), `.kamal/secrets.example` (names only), `seeds/README.md`, `.contentspiel-version` (= `VERSION`), `.gitignore`, `README.md` (the steps for a person and an AI tool: fill the placeholders, `contentspiel dev`, `contentspiel check`, `kamal setup`/`deploy`, `contentspiel upgrade`).

- [ ] Tests: the folder holds exactly those files; the pin is `VERSION`; no file holds a secret-looking value; an existing folder and a bad name are refused with nothing written; `bin/contentspiel --version` prints `VERSION`; the generated theme passes `Theme::Check`.
- [ ] See them fail, implement, see them pass.
- [ ] Modify the `Dockerfile` so the image's PATH has `/rails/bin` and `contentspiel` runs from any working directory (it changes into `/rails` for Rails and back to `/site` for files).
- [ ] Commit `feat: contentspiel new writes a site that builds on a release`.

### Task 5: `generate`, `check` and `dev`

**Files:** Modify `bin/contentspiel`, `lib/content_spiel/site_generator.rb` or a new `lib/content_spiel/theme_generators.rb`; add `lib/site_template/compose.yml.tt`. Test `test/lib/theme_generators_test.rb`.

**Interfaces:** `contentspiel generate section_style NAME "Label"` and `generate page_template NAME "Label"`: add the entry to `theme/theme.yml` (creating the list if absent, refusing a duplicate name or an invalid one by `Theme::Declarations`' own rule) and write the template or stylesheet stub; `contentspiel check` runs `Theme::Check` on `/site/theme` and exits 1 with its message; `contentspiel dev-files` writes `.contentspiel/compose.yml` (the pinned image in development, theme mounted, Postgres 17, the stylesheet watch, port 3000), which the wrapper's `dev` then runs.

- [ ] Tests: each generator's output passes `Theme::Check`; duplicate and invalid names refused; `check` exits 1 on a broken theme; the compose file names the pinned version and mounts the theme.
- [ ] See them fail, implement, see them pass.
- [ ] Commit `feat: contentspiel generate, check and dev`.

### Task 6: `upgrade`

**Files:** Modify `bin/contentspiel`; create `lib/content_spiel/upgrade.rb`. Test `test/lib/upgrade_test.rb`.

**Interfaces:** Runs in the NEW image (the wrapper pulls `stable` for `upgrade`: add that case to Task 3's wrapper and its test). Reads the site's pin and this image's `CHANGELOG.md`; prints every section newer than the pin, oldest first, with lines under a "Breaking" or "Theme contract" heading first in each; runs `Theme::Check` on `/site/theme`; only when it passes, writes `VERSION` into `.contentspiel-version` and prints the next steps (commit, `kamal deploy`; and, when a section between names "Migrations needing action", that going back is not safe).

- [ ] Tests: already on this version → says so, writes nothing; pin not a version → refused; a failing check → notes and the check's message shown, pin unchanged; success → pin moved, notes in order, the migration warning when present.
- [ ] See them fail, implement, see them pass.
- [ ] Commit `feat: contentspiel upgrade`.

### Task 7: the template is built and booted in CI

**Files:** Modify `.github/workflows/image.yml`: after the push, a job that runs `contentspiel new` from the just-built image into a temp folder, builds that site's image with `CMS_VERSION` set to the commit tag, and boots production under it with dummy secrets until `/up` answers. Test: the workflow itself; note in the report it is proven by the first merge.

- [ ] Write the job; read it against the spec; `actionlint` if installed.
- [ ] Commit `ci: the site template is built and booted with every CMS image`.

### Task 8: documentation

**Files:** `docs/reference/hosting.md` ("Releases", "A site's version", the wrapper's promise); `CHANGELOG.md` "Unreleased" (the entrypoint and the pin as promises); `CLAUDE.md` index line for the new reference part. The guide (`~/src/contentspiel-docs`, commit, no push): install the command, start a site, upgrade a site, move an existing site from `CMS_REVISION` to `.contentspiel-version`; `build-a-theme.md` and the quick start point at `contentspiel new` and `dev`.

- [ ] Write, run the guide's `bin/check`, commit in each repository.
