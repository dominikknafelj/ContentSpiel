# An image on the Card block (#144)

The owner, 2026-11-01: "i follow your suggestions". Every decision here is the implementer's, for the owner to overrule in the pull request.

## Why

A site showing projects needs cards with a picture, a title, a text and a link. Today such a card is rebuilt from a Section and Rich text blocks.

## What

- A Card has an optional library image, chosen with the picker the Image block uses. It declares `uses` for the image slot and its alt override, storing `content_blocks.media_asset_id` and the translated `alt`, so `Media::Choosing`, usages, the published copy, trash and the database's foreign key all work as for an Image block. No migration if those columns serve, and no new field type (#116 stays open).
- The icon stays. A card may have both; the theme decides what to draw. The default theme draws both, the image above the icon.
- **Default look:** the image above the title, the card's full inner width, at its own proportions with `width` and `height` reserved, in `Media::PictureComponent` (one `<img>`, no wrapper). No cropping and no forced ratio.
- **Drawn when:** a title, a text or an image exists. An icon or a link alone still draws nothing.
- **One link per card:** the link stays on the title; with no title on the text (as today); with neither, on the image, and then its alt text is the link's name. An image with a title is not a second link.
- **Alt:** the block's alt override, else the library's, as the Image block. An image without alt under a link with no words is reported in the editor as the Image block reports missing alt, if it does; no new refusal.
- **Editor:** the card's image control is the Image block's, above the icon; the tile shows the words as today, or the image's title when there are none. A held card is read-only.
- **Theme contract:** `image` joins the Card's `theme_methods`, as a value a template hands to or tests with the same shape the Image block's template uses; a ledger line and a `CHANGELOG.md` release note. A theme's Card template without it keeps working.
- **Translation:** the image is shared by every language, the alt is translated, as the Image block.

## Constraints

Standing rules of `CLAUDE.md` and the reference files for content blocks, media and theming: the sample fills what the type uses, the canary and scaffold stay green, no public reader reads rows, an image a copy shows is in use. New admin strings are keys. Generic fixtures only.

## Documentation

Guide: `editors/pages/build-a-page-with-blocks.md`, `integrators/theming/the-theme-contract.md`, `rendering-blocks-and-pages.md`, `quick-start.md`, and `docs/reference/theme-choices.md`'s "not built" line goes. Design System: SiteCard page.

## Left to the builder

The `sizes` value, spacing inside the default card (tokens only), and where the image control sits if the card's form makes "above the icon" awkward.
