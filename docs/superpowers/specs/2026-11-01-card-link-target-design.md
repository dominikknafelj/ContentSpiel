# A Card link that follows a page or post (#145)

The owner, 2026-11-01: go ahead on the implementer's suggestions. Every decision here is the implementer's, for the owner to overrule in the pull request. It is the roadmap's "Links (D13)" for the Card; a button can use it when one exists.

## Why

A card's link is a stored address, so changing the target page's slug or parent silently breaks it.

## What

- **Stored:** the `:link` field also accepts a reference to one page or post, with no new column and no migration. The form is the builder's, matching how the rich text `internalLink` mark names its target (`{type, id}`); it is refused unless the type and the id are well formed. A typed address stays as it is, and existing values keep working.
- **Same language on every tab:** the reference is shared by every language, as the link is today.
- **Drawn:** the component resolves a reference to the target's current public address in the visitor's language, by the rule `RichText::BuiltIns#render_internal_link` uses, through `PublicSite::Urls`. It does not walk the tree or read a row's slug.
- **Target not public:** trashed, unpublished, scheduled and not yet live, purged, or with no address: the card draws no link and keeps its words. It never raises, and never shows a draft's title or address.
- **Published copy:** a live card's reference comes from its copy, and a target's own published state decides. Publishing, moving or trashing the target must reach a visitor: check that the public content version moves, as it does for a page holding an `internalLink`, and that a cached page or a 304 cannot keep a dead link. This is the likeliest silent bug.
- **Theme contract:** `link` still answers an address string or nil, so a theme needs no change. The promise does not widen, and the reference never reaches a template.
- **Editor:** the link field keeps typing an address and offers search over `Admin::LinkTargetsController`, the rich text picker's list, which shows only what the person may read. A chosen target shows its title with a way to clear it, and a held card shows it read-only. A target that is not public yet shows a quiet note. Report the look as a design question; do not decide more than is needed to work. It is keyboard usable.
- **Tile:** unchanged, but a reference never prints as its raw form anywhere a person reads: tile, audit sentence, translation tab.
- **Duplicate, discard, starter content, MCP:** carry the value as they carry any setting. A deleted target's reference is left stored and draws nothing.

## Non-goals

Links in other block types; `rel` and new-tab options; a list of "what links here"; warning before trashing a linked page.

## Constraints

Standing rules: `:link` remains one registry entry and one field component (`test/lib/field_type_branches_test.rb`); no public reader reads rows; every address comes from `PublicSite::Urls`; a value of the `link?` rule stays safe for a browser. New strings are keys. Plain `fetch` rules for anything in an editor per `docs/reference/editors-and-translation-pair.md` and `save-rule-and-write-queue.md`. Generic fixtures only.

## Documentation

Guide: `editors/pages/build-a-page-with-blocks.md`, `integrators/theming/the-theme-contract.md`. `docs/reference/theme-choices.md`'s "not built" line and the roadmap's Links note. Design System: SiteCard page.

## Left to the builder

The stored form; the picker's markup within CS Studio's tokens; whether a post is offered with a page in one list or as `LinkTargetsController` answers them.
