# ContentSpiel

ContentSpiel is a content management system built on Rails 8.1. It draws a
public website from a tree of pages, and editors work in its own admin,
CS Studio.

- **Pages in a tree.** Editors build pages from ordered content blocks (rich
  text, images, code, notes, post lists, sections with columns). The same tree
  drives the navigation, the addresses and the sitemap.
- **Posts** of types you define, with tags, related posts and a Mind graph that
  draws how pages, posts and tags connect.
- **Drafts and publishing.** Content saves as you type; a live page changes
  only when someone publishes, at once or at a scheduled time.
- **Languages.** Every text is translated into the languages switched on in
  Settings (38 are supported), by hand or with an AI provider.
- **Working together.** Notes on content, who else has a page open, live
  refresh and edit holds, an audit log, users, groups and permissions.
- **Themes and block types from outside.** A site's look is a theme folder
  beside the CMS, held to a written contract, and a gem can add block types
  through a hook.

## Getting started

```sh
docker compose up -d          # Postgres 17, published on host port 5433
bin/setup --skip-server       # installs gems, prepares the development + test databases
bin/rails db:seed             # creates dev accounts, an owner and an Author-group member (development only -- see db/seeds.rb)
bin/rails server              # or `bin/dev`, which bin/setup runs for you without --skip-server
```

Start the container first: `bin/setup` runs `bin/rails db:prepare`, which fails
with connection refused if Postgres isn't up.

- App: <http://localhost:3000>
- Sign in: <http://localhost:3000/cs-studio/sign-in> (`<ADMIN_PATH>/sign-in`)
- Admin (CS Studio, behind the same sign-in): <http://localhost:3000/cs-studio> (`ContentSpiel::ADMIN_PATH`, configurable via `ADMIN_PATH`)

Run the test suite with `bin/rails test`, and the browser tests with
`bin/rails test:system`.

## Learning the code

`CLAUDE.md` holds the commands and the rules a change can break without a test
failing loudly. `docs/reference/` explains each part of the system, one file
per topic: start with the one that covers what you are about to change.
Hosting a site is `docs/reference/hosting.md`, and writing a theme is
`docs/reference/theming.md`.

## Security and licence

Report a vulnerability privately, as `SECURITY.md` says. ContentSpiel is
released under the MIT licence (`LICENSE`).
