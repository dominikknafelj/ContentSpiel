# Contributing to ContentSpiel

Thank you for wanting to help. This page says how a change gets in.

## Before you start

- **A bug:** open an issue with what you did, what you expected and what
  happened instead. A security problem is never an issue: see `SECURITY.md`.
- **A feature or a larger change:** open an issue first and describe it. A
  change that has been agreed on is much more likely to be merged than one that
  arrives as a finished pull request.

## Setting up

The README's "Getting started" is the whole setup: Postgres in Docker, then
`bin/setup`. Read `CLAUDE.md` before you change anything. It holds the
commands, the conventions and the rules no test holds, and it points to the file in `docs/reference/` that explains the part you are
about to change.

## Making the change

- Follow what the code around you does: its naming, its idioms and its long
  comments, which record why something is the way it is. Keep them when you
  change the code.
- Minitest and fixtures, no RSpec. Import maps, no npm. Tailwind for styles.
- A string a person reads in CS Studio is a translation key, not a literal
  (`docs/reference/i18n.md`).
- Add or change tests with the code. A rule that a change can break silently
  gets a guard test, as the ones `docs/reference/` names.

## Checking it

Run `bin/ci` before you open a pull request. It runs what CI runs, and the seed,
which CI does not, one step after another (`config/ci.rb`): setup, RuboCop,
the changelog guard, the gem, import map and Brakeman scans, the unit tests,
the browser tests, the seed and the theme build check. The changelog guard compares with `origin/main`, so
fetch it first. The browser tests need a quiet machine; on a laptop cap them
with `PARALLEL_WORKERS=6 bin/ci`. CI runs all of it but the seed again for
every pull request.

## The pull request

- One change per pull request, on a branch of its own.
- Commit messages follow conventional commits: `feat:`, `fix:`, `docs:`,
  `test:`, `style:`, `ref:`, `chore:`.
- Describe what changes for the person who uses it, and how you checked it.
- End the description with a **Documentation** section: the pages of the user
  guide your change affects, or "none". A change to what an editor sees or
  does needs its guide page updated before it is released.

## Themes and block types

A site's look is a theme folder outside this repository
(`docs/reference/theming.md`), and a gem can add block types through
`ContentSpiel::Plugins` (`docs/reference/content-blocks-and-types.md`). Often
that is the better place for a change than the CMS itself.

## Licence

By contributing you agree that your contribution is released under the MIT
licence in `LICENSE`, as the rest of the project is.
