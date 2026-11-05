# Releases and new sites

Owner, 2026-11-05: "yes" to the outline in chat. Closes #110 and #115.

## Why

The owner runs several sites on one server, one deployment per site: the documentation site and Studio Nordlicht now, a personal page next. Today a site pins a CMS commit (`CMS_REVISION`, a 40-character id the image is tagged with) and is started by hand from a checkout of the CMS. Neither scales to a third site, and neither tells a site's owner what changed between two commits or whether their theme survives it.

A new site, and an update of one, must be doable two ways: by a person at a terminal, and by an AI tool such as Claude Code following the same steps from the same page. If an agent can follow it without guessing, so can a person.

## Goals

1. A CMS release has a number, notes, and an image of the same number.
2. One line installs a `contentspiel` command on a machine that has Docker and nothing else.
3. `contentspiel new my-site` writes a site folder that builds, passes `theme:check` and boots, with no CMS checkout.
4. A site names its CMS version in one file, and `contentspiel` inside that folder uses that version.
5. `contentspiel upgrade` shows what changed, moves the pin, and checks the theme against the new version before anything is deployed.
6. A theme can be worked on locally against the pinned CMS with no CMS checkout.

## Non-goals

- Automatic updates, a version picker, several sites from one command.
- Deploying for the owner: `kamal deploy` stays the owner's.
- A plugin's own versioning (`requires: "~> 0.4"` in a hook), System status showing the version, and MCP reporting it: #110's "later" items, left as a follow-up.
- Windows.

## Anti-goals

- A generated site that does not build: the template is built and booted in the CMS's CI so it cannot rot.
- An upgrade that deploys a theme the new CMS refuses: the check runs before the pin is committed.
- An install script nobody can read, or one served from a moving branch.

## Decided with the owner

- **Releases.** `0.x.y` before 1.0. A breaking change to what themes or plugins rely on (the theme contract, the plugin hooks, an environment variable, a migration that needs action) raises the minor number; anything else raises the patch. A release is a git tag `v0.5.0`, a GitHub Release whose notes are that version's section of `CHANGELOG.md` with breaking changes first, and the CMS image tagged `0.5.0` beside the commit tags it has today. One command cuts a release: it moves the version, dates the changelog's "Unreleased" section, and tags; CI builds and publishes the image and the Release from the tag.
- **Install.** `curl -fsSL https://github.com/dominikknafelj/ContentSpiel/releases/latest/download/install.sh | sh`. The script is a release asset, short enough to read, and the guide shows how to download and read it first. It checks for Docker, writes a small `contentspiel` command into `~/.local/bin` (saying how to put it on `PATH` if it is not), and stops.
- **The command** is a thin shell wrapper that runs the CMS image (`docker run --rm`, the current folder mounted) at a version: inside a site folder, the version in its `.contentspiel-version`; outside one, the newest release. So two sites can be on two versions.
- **`contentspiel new my-site`** writes a theme folder (from the default theme, as `theme:new` does), the site's `Dockerfile` building on the pinned image, a Kamal `config/deploy.yml` with placeholders (address, server, registry, the theme path), a place for seed content, `.contentspiel-version`, and a README that is also the page an AI tool follows.
- **Generators** add pieces to a site the way `rails generate` does, starting with what a theme declares: a section style and a page template, each written into `theme.yml` and its template. Which generators come first is the builder's, beside `theme:check`.
- **`contentspiel upgrade`** shows the release notes between the site's version and the newest (breaking changes first), moves `.contentspiel-version`, and runs `theme:check` with the new image. The owner then commits and runs `kamal deploy`; migrations run at deploy as now. Its output says exactly what changed and what to fix, so an AI tool can do an upgrade as a person would.
- **Going back:** set the pin back. That is safe only for a release with no migration, and the release notes say which ones have one.

## Calls made in writing this (the owner may overrule)

- **Development without a checkout (#115):** `contentspiel dev` runs the pinned image in development mode with the site's theme folder mounted, Postgres beside it and the stylesheet watch, by a compose file the site template writes. A mounted theme in development does not break "a theme is an image layer" in production.
- **The version lives in one place in the CMS:** `ContentSpiel::VERSION` (in `lib/`, required early, as the other boot-time constants are). The release command writes it; nothing else does.
- **The image's commit tags stay**, for CI and for sites that already pin a commit: the documentation site (`CMS_REVISION`, `CMS_TAG` in its Dockerfile) and Nordlicht move to a version pin when the first release exists, by `contentspiel upgrade` or by hand, documented once in the guide.
- **`CHANGELOG.md`'s sections** stay as they are (Theme contract today) and gain Environment, Migrations needing action and Removed when a change has one; a release's notes are its section. A guard that the contract ledger cannot change without a changelog line is in, as #110 suggests, because a test holds the promise.
- **A pull request template** with one checkbox: "changes the theme contract, a plugin hook, the environment, or needs an upgrade step".
- **The site template is built and booted in CI** with the image of that commit: `new`, `theme:check`, image build, a production boot under it. It runs where the image is built (`image.yml`), so a pull request does not pay for it.
- **The first release** is cut after this lands, as `0.1.0`, with `CHANGELOG.md`'s "Unreleased" as its notes.

## Settled after the builder check (calls made, the owner may overrule)

- **Finding the newest release:** each release also moves an image tag `stable`. Outside a site folder the wrapper runs `:stable`; `upgrade` pulls `:stable` and reads the notes from the `CHANGELOG.md` inside that image, so the only network use is image pulls. The repository and the image package are public (since 2026-10-26), so neither the pull nor the install URL needs a login.
- **Apple Silicon:** release images are built for `linux/amd64` and `linux/arm64`, each on a native GitHub runner, so nothing is emulated (the reason `image.yml` builds one platform today). Commit images stay amd64 only, as now: the server is amd64 and they are what CI and old pins use.
- **The wrapper and the image:** the wrapper is frozen and dumb. It finds the version (the site's `.contentspiel-version`, else `stable`), runs `docker run --rm` with the current folder mounted and the host's uid and gid, and hands every argument to one entrypoint in the image, `contentspiel`. All commands (`new`, `generate`, `upgrade`, `dev`, `check`) live in the image, so they are always the pinned version's. `upgrade` runs in the NEW image. The entrypoint's name and the way arguments are handed over are the one promise the wrapper relies on, written in the release notes' rules and held by a test. `contentspiel dev` is the one command that starts long-running containers: the image writes the compose file and the wrapper runs `docker compose` with it.
- **The release command opens a pull request,** because `main` takes changes only by pull request: it moves `ContentSpiel::VERSION` and dates the changelog on a branch `release-0.5.0`. The owner merges. On that merge, CI tags `v0.5.0`, gives the existing commit image the version and `stable` tags (no rebuild for amd64; arm64 is built from the tag), and creates the GitHub Release from the changelog section.
- **The changelog guard:** a CI step on pull requests, not a Minitest test, compares the branch with its merge base. When `test/support/contract_ledger.rb` (or a plugin hook's file, or the environment's list) changed and `CHANGELOG.md`'s "Unreleased" did not, the step fails with the file it saw. A test cannot see a diff, and a stored digest is satisfied without writing a line.
- **Seed content:** a `seeds/` folder with a README line only. No loader: a "seed once, then the words belong to editors" pattern is its own roadmap item, which Nordlicht's friction log raised.
- **Registry and pins:** the template writes the CMS image's name from a constant in the image (`ghcr.io/dominikknafelj/content_spiel`). The site's own image and registry are placeholders in `deploy.yml`. The generated `deploy.yml` reads `.contentspiel-version` and passes it as the Dockerfile's build argument, so the pin lives in one file. The documentation site and Nordlicht move from `CMS_REVISION` to `.contentspiel-version` by hand, once, with a guide section saying how.

## Constraints

- Docker and a POSIX shell are all the command needs on macOS and Linux. No Ruby on the host.
- Everything the command runs comes from the pinned image: one source of truth, and a site's tools are always its CMS version's.
- The install script and the wrapper are each a single readable file, with `set -eu` and no `sudo`. The install script downloads the wrapper from the same release; the wrapper's only network use is image pulls.
- Secrets: the generated `deploy.yml` names secrets by environment variable only and writes no `.kamal/secrets` with values; the README says where the owner puts them. Never a token in a generated file.
- No client site's content enters the template: generic only.
- Standing project rules: services, guards, tests first, the browser suite in CI, the guide in `contentspiel-docs`.

## Documentation

New guide pages: installing the command, starting a site, upgrading a site (each written so an AI tool can follow it); `integrators/theming/build-a-theme.md` and the quick start point at `contentspiel new` and `contentspiel dev`; the administrators' deploy pages say how a site pins a version.

## Left to the builder

The release command's form (a rake task or a `bin/` script), the wrapper's argument handling, which generators beyond the two named, how `upgrade` reads release notes (from the image, from GitHub, or both), the compose file's details, and the README's wording.
