# ContentSpiel

ContentSpiel is a content management system built on Rails 8.1. It draws a
public website from a tree of pages, and editors work in its own admin,
CS Studio. It is released as versioned Docker images, and a site is created,
run and upgraded with the `contentspiel` command (latest release:
[v0.3.0](https://github.com/dominikknafelj/ContentSpiel/releases); every change is in the [changelog](CHANGELOG.md)).

**Documentation:** the guide for editors, administrators and integrators is at
<https://content-spiel-docs.studio-nordlicht.agency>. For how the code works,
see [`docs/reference/`](docs/reference/), in this repository, below.

- **Pages in a tree.** Editors build pages from ordered content blocks:
  - rich text, images, code, notes and tables;
  - cards, forms and post lists;
  - sections with columns.

  The same tree drives the navigation, the addresses and the sitemap.
- **Posts** of types you define, with tags, related posts and a Mind graph that
  draws how pages, posts and tags connect.
- **Drafts and publishing.** Content saves as you type; a live page changes
  only when someone publishes, at once or at a scheduled time.
- **Languages.** Every text is translated into the languages switched on in
  Settings (38 are supported), by hand or with an AI provider. Each field
  shows whether its translation is missing or out of date.
- **Working together.**
  - Notes on content, and who else has a page open.
  - Live refresh, and edit holds that one person can take over from another.
  - An append-only audit log, users, groups and permissions scoped to content
    types and branches of the tree.
- **Media and forms.** A media library with responsive image sizes and usage
  tracking. Forms with encrypted submissions, mail delivery, retention and a
  per-visitor limit.
- **Sign-in for the open internet.**
  - Per-account and per-address limits on attempts, a bot check (Cloudflare
    Turnstile) after repeated failures, and a refusal of passwords known
    from leaks (Have I Been Pwned).
  - The same answer whether or not an account exists.
  - Sessions that end when idle or after 14 days, which each person can see
    and end from Your account.
- **Themes and block types from outside.** A site's look is a theme folder
  beside the CMS, held to a written contract. A gem can add block types, form
  field types, form destinations and admin modules through hooks.

## Running a site

Install the command (it needs Docker and touches nothing else):

```sh
curl -fsSL https://github.com/dominikknafelj/ContentSpiel/releases/latest/download/install.sh | sh
contentspiel new my-site      # a site folder: its theme, its deploy file, the version it pins
```

A site pins the CMS release it runs in `.contentspiel-version`.
`contentspiel upgrade` moves it to a newer one and prints the changelog
sections in between. What production asks of its host is in
[`docs/reference/hosting.md`](docs/reference/hosting.md), and step by step in the guide's administrator
pages.

## Working on the CMS

```sh
docker compose up -d          # Postgres 17, published on host port 5433
bin/setup --skip-server       # installs gems, waits for Postgres, prepares the databases, builds the stylesheets
bin/rails db:seed             # dev accounts (an owner and an Author-group member), demo content and /showcase (development only -- see db/seeds.rb)
bin/rails server              # or `bin/dev`, which bin/setup runs for you without --skip-server
```

Start the container first: `bin/setup` waits up to 30 seconds for Postgres and
stops with what to run when it does not answer. A database `bin/setup` creates
is seeded too; `bin/rails db:seed` adds what an existing one lacks, and is safe
to run again. After `bin/dev`, <http://localhost:3000/showcase> draws every
block type in every layout and band.

- App: <http://localhost:3000>
- Sign in: <http://localhost:3000/cs-studio/sign-in> (`<ADMIN_PATH>/sign-in`)
- Admin (CS Studio, behind the same sign-in): <http://localhost:3000/cs-studio> (`ContentSpiel::ADMIN_PATH`, configurable via `ADMIN_PATH`)

Run the test suite with `bin/rails test`, the browser tests with
`bin/rails test:system`, and everything CI runs (and the seed) with `bin/ci`.

## Tests, CI and releases

- **Every pull request runs:**
  - lint (RuboCop);
  - security scans (Brakeman, bundler-audit, importmap audit);
  - a changelog guard;
  - the whole test suite: more than 10,000 tests, unit and integration plus
    headless-Chrome browser tests, in about ten minutes.

  The tests run as 2 unit shards and 6 browser shards with 4 workers each.
  `bin/test-shard` deals the files by the seconds each took in a real CI run
  (`test/*_test_seconds.yml`), so the shards finish together
  ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).
- **Guard tests hold the architecture**, beside the behaviour:
  - the direction of dependencies between layers;
  - a contract for every shared CS Studio component;
  - that a screen's component is drawn by that screen only;
  - words as translation keys, and SQL strings with a reason.
- **Every merge to `main`** builds the production image and pushes it to the
  GitHub container registry ([`image.yml`](.github/workflows/image.yml)). Then it generates a client site with
  that image's own `contentspiel` command and checks it end to end.
- **A release** is a pull request made by `bin/rails 'release:prepare[X.Y.Z]'`.
  Merging it tags `vX.Y.Z` and publishes amd64 and arm64 images as `X.Y.Z` and
  `stable`, with the GitHub Release ([`release.yml`](.github/workflows/release.yml)).

## Learning the code

[`CLAUDE.md`](CLAUDE.md) holds the commands, the conventions and the rules no test holds.
[`docs/reference/`](docs/reference/) explains each part of the system and holds the rules a test
guards, one file per topic: start with the one that covers what you are about to change.
Hosting a site is [`docs/reference/hosting.md`](docs/reference/hosting.md), and writing a theme is
[`docs/reference/theming.md`](docs/reference/theming.md). The guide
(<https://content-spiel-docs.studio-nordlicht.agency>) is the reader's side
of the same system: how to use CS Studio, run a site and build a theme.

## Contributing, security and licence

How a change gets in is [`CONTRIBUTING.md`](CONTRIBUTING.md). Report a vulnerability privately, as
[`SECURITY.md`](SECURITY.md) says. Every release's changes are in
[`CHANGELOG.md`](CHANGELOG.md). ContentSpiel is released under the MIT licence
([`LICENSE`](LICENSE)).
