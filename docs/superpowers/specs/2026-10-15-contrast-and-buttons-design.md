# Contrast and buttons

Status: designed, not built (plan `docs/superpowers/plans/2026-10-15-contrast-and-buttons.md`). Source: Claude Design's answers of 2026-10-15 (`.superpowers/design-answers/2026-10-15-contrast-and-icons.md`, C1, C2, D1, D2, D3 and D4), approved by the owner the same day, who split them into two pull requests and the Note block. **This is the first of the two.** Every value below was measured on the code at `5e4db8ac` with the same arithmetic `test/integration/design_tokens_test.rb` uses (WCAG 2.x relative luminance; `oklch()` through Björn Ottosson's matrices; a translucent line painted over the ground it stands on). Where a measured figure differs from the design answer's, the measured one is written and the difference is a Ruling.

## Why

Text in CS Studio and on the site passes almost everywhere. What fails is everything that is not text: an input's edge is 1.5:1 on its card, a selected filter pill is 1.13:1 against the unselected ones, a disabled Save reads as a weak primary, dark mode's four grounds are within 1.1:1 of each other, and a strong band in a dark page is a near-white slab. Design answer C1 puts the line where WCAG 1.4.11 puts it: **a boundary that identifies a control or a state reaches 3:1; a boundary that only groups may stay faint**, a little stronger than now. D1 turns that into one button system, D2 settles light against dark, C2 adds block-type icons and the page tree's state marks.

## What changes, by design answer

### C1. Contrast: CS Studio's tokens (`app/assets/tailwind/content-spiel.css`)

| Token | Light: old → new | Dark: old → new | Measured (new) | Role |
|---|---|---|---|---|
| `--cs-field-line` (new) | — → `#808186` | — → `#74757b` | light 3.53 paper, 3.89 surface, 3.06 sunken; dark 4.23 paper, 3.71 surface, 3.16 sunken | the outline of everything that is pressed or typed into, and the ○ of a missing translation; **3:1 on every ground a control stands on** |
| `--cs-line-strong` | ink 20% → **28%** | ink 18% → **26%** | 1.87 / 2.19 on surface | grouping only: a card, a panel, a table's header rule, a chip that is no control |
| `--cs-line` | ink 10% → **14%** | ink 9% → **13%** | 1.34 / 1.44 on surface | table rows, inner dividers |
| `--cs-sunken` | `#ecebe6` → `#e6e4dd` | `#212226` → `#28292e` | sunken/surface 1.27 light, 1.17 dark | toolbar, hover ground, tinted section card |
| `--cs-meta` | `#6c6d72` → `#5f6065` | `#8e8f95` → `#9c9da3` | light 6.27 surface, 5.70 paper, 4.93 sunken; dark 6.29 surface, 5.37 sunken | labels, dates, counts |
| `--cs-dim` | `#55565b` → `#46474c` | unchanged `#a9aaaf` | light 9.27 surface, 7.28 sunken; dark 7.34 surface | secondary text; stays a step above `meta` |
| `--cs-paper` | unchanged | `#0f1012` → `#0c0d0f` | | |
| `--cs-chrome` | unchanged | `#131416` → `#111214` | | |
| `--cs-surface` | unchanged | `#17181b` → `#1b1c20` | surface/paper 1.14 (was 1.07) | |
| `--cs-cat-5` (D2) | unchanged | `oklch(0.74 0.07 230)` → `oklch(0.74 0.07 260)` | | moves away from `cat-1`'s teal |
| `--cs-graph-page` (new, D2) | `var(--cs-ink)` | `#d9d9dc` | 12.09 on the dark surface | a page's mark on the Mind graph |
| `--cs-graph-tree` (new, D2) | `var(--cs-dim)` | `rgba(169,170,175,0.6)` (dim at 60%) | 9.27 / 3.50 on surface | the Mind graph's tree lines |

Every other CS Studio token keeps its value. `content-spiel.tailwind.css` maps `--color-field-line` and gives `text-label` its weight (`--text-label--font-weight: 500`), so **every mono label is 11px at weight 500** with no class changed.

Where the new values are drawn:
- **Every control's outline is `border-field-line`**: `setup_input_class`, `setup_select_class` (`.cs-select`), `.cs-toggle`, the chip input's frame, the prefix input, the rich-text toolbar and editor, the notes composer's frame, every search field, the date fields of the audit log, the file drop zone and its button, the secondary and `danger_text` buttons and their hand-written copies (`setup_secondary_link_class`, `rich_text/popover.js`, the notes and translation scripts' buttons), the segmented controls' outer edge, the Mind graph's zoom group, the theme switch's edge, the New post dialog's type cards and the group scope editor's boxes and tri-state marks. The invalid-field rule's fallback (`--cs-field-invalid-border`) falls back to `--cs-field-line`.
- **No text under 11px in CS Studio's markup.** The 24 `text-[10px]` and the 12 mono `text-[11px]` become `text-label` (one of them in `app/javascript/notes/merge.js`, a folder the design rules did not read: they read it from now on); the two 10px counts in `content-spiel.tailwind.css` (a tile's and the tree's notes marker) become `var(--cs-t-label)`. The Mind graph canvas's count font stays 10px (a canvas badge, PR 2's legend work).
- **The translation circle**: a missing translation's ○ is a 7px ring of 1.5px in `--cs-field-line`, in the language tabs (`LanguageTabsComponent`) and in the translation chip (`TranslationChipComponent`, which draws it as an element and no longer as the "○" character); a translated language's chip gains a filled ● in `--cs-ok`. The chip's own border is decoration and stays `line-strong`; missing keeps its dashes, outdated its warn border and ↻.
- **The selected tree row** keeps its weight, gains the sunken ground it never had, and a 2px `--cs-ink` bar on its left edge (14.45:1 light, 12.41:1 dark on sunken).
- **Tables**: row lines `--cs-line`, the header rule `--cs-line-strong`. All six tables already draw it that way; the token values do the rest.

### C1. Contrast: the site's default theme (`app/assets/tailwind/themes/default/`)

Values only; **no token is added, renamed or removed** (`Theme::Contract` is a promise to themes outside this repository).

| Token | Light: old → new | Dark: old → new | Measured (new) |
|---|---|---|---|
| `--th-line` | ink 10% → 14% | ink 9% → 13% | 1.34 / 1.38 on paper |
| `--th-sunken` (and so `--th-band-tinted`) | `#ecebe6` → `#e6e4dd` | unchanged `#212226` | band/page 1.16 light, 1.20 dark |
| `--th-band-strong` (D2) | unchanged `var(--th-ink)` | `#ededee` → `#34353a` | 1.56 against the dark page |
| `--th-on-band-strong` | unchanged | `#0f1012` → `#ededee` | 10.46 on the band, 7.43 on the band's sunken |
| `--th-on-band-strong-dim` | unchanged | `#45464b` → `#c0c1c6` | 6.81 on the band, 4.84 on its sunken |
| `--th-on-band-strong-accent` | unchanged | `oklch(0.45 0.12 250)` → `oklch(0.82 0.09 250)` | 7.05 on the band, 5.01 on its sunken; the band on it 7.05 |

- **Faint text** (mono dates, tags, the footer): `--th-meta` is already 11px (`--th-t-label`) and 4.69:1 (light) / 5.90:1 (dark) on the page; in a tinted band it reads as `--th-dim` (`sections.css`), 5.75:1. The contract now says so ("Tokens" in `docs/reference/theming.md`: `--th-meta` is 4.5:1 on the page and on the tinted band at 11px) and `design_tokens_test.rb` holds it for the default theme, which closes the roadmap's "does not measure the caption's `--th-meta`".
- **A control's outline on the site is `--th-meta`** (3:1 or better: 4.69 / 5.90): the DARK MODE button now, a theme's own controls by the contract's word. `--th-line-strong`'s row in the contract loses "a button's border".
- **A strong band in a dark page is a raised dark ground**, not the light page: a code block inside it is `color-scheme: dark` in both schemes (`sections.css` drops the dark-scheme override), and its seven syntax colours stay the band's one colour and its dim.

### C2. Icons

- **Block types declare their icon**: `t.icon "pilcrow"` in the definition, one of `ContentModel::BlockTypeDefinition::ICONS` (`pilcrow`, `image`, `code_xml`, `posts`, `columns_2`), each a branch of `app/views/admin/shared/_icon.html.erb` (Lucide, 1.5px). Rich text `pilcrow`, Image `image`, Code `code_xml`, Post list `posts` (the sidebar's Posts icon, which now takes `size:`), Section `columns_2`.
- `Admin::EditorScreen::BlockIconComponent` draws it in three places: **the picker**, 16px in `--cs-dim` before the type's name (the end-of-list row and a lane's "+" menu); **the block card's head**, 14px in `--cs-dim` between the drag handle and the name (list, group and panel cards); **a section's tile**, 12px in `--cs-meta` before the summary, where it stands in for the type's name: the name moves into the face as `sr-only` text, so the face's accessible name is "Image photo.jpg" and not the summary alone.
- **The page tree's state marks** (`Admin::PagesScreen::TreeStateMarkComponent`), after the title, only when a page is not simply live: Draft a hollow 6px circle (1.5px `--cs-meta`), Scheduled a filled `--cs-warn` dot, Live with changes a `--cs-dim` dot. Each is `role="img"` with an `aria-label` and a `title` ("Draft"; "Scheduled · 20 Oct 2026, 09:00"; "Unpublished changes"), in the words the status chip and the unpublished chip already use. It replaces the tree's `StatusChipComponent` (the outlined "Draft" and "Scheduled" chips) and the compact `UnpublishedChipComponent` (a warn dot), whose compact mode goes.
- No icon for a post type, none for a page type.

### D1. Buttons and pressable things

- **One primary per screen.** The editors' "Discard changes…" is `:ghost` (it stands beside the primary "Publish changes…").
- **Secondary** (and `danger_text`, `setup_secondary_link_class`, `popover.js`'s copy): `--cs-field-line` border, **hover border `--cs-ink`**, no hover fill.
- **Every hover of `ButtonComponent` is `not-disabled:hover:`**, so a disabled button never reacts; `:not(:disabled)` and not `:enabled`, because the same classes are drawn on links (the 403 and 404 pages, "+ New page", the Mind graph card), which are never `:enabled`.
- **Disabled** (every variant): `bg-sunken text-meta border-line`, no accent, no opacity. Disabled is exempt from 1.4.11; the save bar's "No unsaved changes" says why.
- **Badges** have a sunken fill and no border, so only buttons have an outline: `Admin::Ui::BadgeComponent` (mono label; tones `:neutral` sunken/meta and `:warn` warn-tint/warn-ink) for Settings' DEFAULT, the groups' BUILT-IN, the users' OWNER, a media tile's UNUSED and NO ALT, and a note's "written in" chip; the status chip, the unpublished chip, the no-address chip, the channel chip and the Mind graph card's copy of the status chip lose their border for the same fill.
- **"View on site ↗"** is a normal link: sans 13px `text-accent`, underline on hover.
- **Filter pills** (posts, Media, Translations, and the Trash's tabs, the same control): the group is outlined in `--cs-field-line`; the selected pill is inverted, `bg-ink text-paper` with its count; a selected pill with the keyboard's focus has a `--cs-paper` ring inset 4px (16.71:1 on ink), because the accent ring on ink is 3.07:1 light and **1.96:1 dark**.
- **Rich-text toolbar**: every button in sans (H2, H3, H4 were mono); at rest plain; hover `bg-ink/6` on the sunken toolbar; **active** (`aria-pressed`, `data-active`) a surface fill with a `--cs-field-line` border and ink text (3.06:1 light, 3.16:1 dark against the toolbar), replacing the invisible accent-tint.
- **"+ New page"** (the tree) and **"New note"** (the drawer) are small secondary buttons; New note already was.
- **Mind graph zoom**: 28px high, 13px labels, the percentage 11px mono, the group outlined in `--cs-field-line`.
- **The split button** "New blog post ▾": its divider is 1px `--cs-on-accent` at 40%.
- **The site's Code block Copy**: 12px, a 28px hit area that does not make the strip taller, underline on hover, the theme's focus ring (unchanged).
- **The site's DARK MODE button**: border `--th-meta`, 11px text (already), 28px high. **Language switcher**: each code 11px (already) in `--th-dim` (4.5:1 or better), a 24px hit area, underline on hover; the selected one stays the inverted chip.
- Kept as it is: the Notes button's pressed state (`border-ink` on sunken), the primary's colours, the focus ring.

### D2. Light against dark

The grounds, the selected states, cat-5, the Mind graph's page marks and tree lines, and the strong band: all above. Code blocks and status colours: no change.

### Small fixes

- **"▾PAGE SETTINGS"**: a mono-label `<summary>` draws its own triangle with a 6px gap (`.admin-disclosure`, generated content that a screen reader skips), on Page settings, SEO, Shared fields and the audit event's Snapshot.
- **An empty band draws nothing on the site**: `Blocks::SectionComponent#render?` asks whether any block in it DRAWS something, not whether it holds one.
- **The Post list's Content type select says "All types"** for its empty choice: `blank:` is allowed on a `:content_type` field, and `BlockTypes::PostList` declares it.
- **The gap between a card's header and its first label**: the block card's save status line moves into the card's header row, before the "⋯" menu, as the section card's already is.

## Rulings

Where the design answer is silent, conflicts with itself, or conflicts with the code.

1. **`--cs-field-line` is `#808186` light and `#74757b` dark, not the answer's `#8c8d92` / `#6e6f75`.** The answer's values pass on surface (3.31 / 3.40) but not on the new sunken ground (2.60 / 2.90), where the toolbar's active button and the toolbar's own edge stand, and light `#8c8d92` is 3.01 on paper, a rounding from failing. The adjusted values pass 3:1 on paper, surface and sunken in both schemes.
2. **The dark grounds step 1.14 and 1.17, not "about 1.2".** The answer's values are taken as given and measured; the test holds what they give (surface/paper ≥ 1.12, sunken/surface ≥ 1.15) rather than the approximate figure.
3. **The site's tinted band is 1.16:1 in light, not "at least 1.2:1".** `#e6e4dd` (the answer's own value) measures 1.16 against `#f5f4f0`; a band dark enough for 1.2 (`#e1dfd8`) puts the accent link on it at 4.49:1, under 4.5. Text wins over a grouping boundary; the test holds 1.15. Dark keeps `#212226` (1.20), which is already above the answer's `#1d1e22` (1.15).
4. **The strong band's dark text colours are new values** (`#c0c1c6`, `oklch(0.82 0.09 250)`): with the band dark, the old inverted ones fail, and the answer named only the band. The dim and the accent are chosen to hold 4.5:1 on the band's sunken ground, where code stands (4.84, 5.01).
5. **cat-5 moves in dark only.** The brief says dark; its new hue (`#91acd8`) sits nearer the dark accent (`#79b0e8`). A type dot is never the only cue (it is beside the type's name) and accent means "unread" only on a count pill, so the closeness is accepted and named under Risks.
6. **A block's icon is a declaration of the type** (`t.icon`), read by the picker, the card and the tile. The block types PR made every per-type list a declaration; a `case` on the type's name in three components would undo that, and an outside type could not have one. The names are a closed list on the definition (`ICONS`) because the drawings live in CS Studio's icon partial and a model may not name a view; a test renders every listed name. An outside type may name one of them or none.
7. **A type with no icon keeps its name on the tile** and is drawn without an icon in the picker and on the card. The icon replaces the tile's name only where there is one.
8. **The tree draws at most one state mark per row.** Scheduled wins over "with changes"; such a row's mark is the warn dot named "Scheduled · Unpublished changes". The tree draws no "change scheduled" mark: that state costs a read of the pending copies per tree, which the tree does not do today and this PR does not add.
9. **The marks' words are the status chip's and the unpublished chip's keys**, read by their full names, so a state has one wording in CS Studio.
10. **The native checkbox keeps the browser's outline.** `.cs-checkbox` is a native control whose box the browser draws (`accent-color` only, with the layout's `color-scheme`); no CSS here reaches its unchecked border, and this PR does not measure it. A drawn checkbox is a separate change, named under Known gaps.
11. **Every disabled button looks the same**, whatever its variant, and **a busy button is not a disabled-looking one**: `admin--ui--busy` sets `aria-busy="true"` on the button it disables, and the disabled look is `disabled:not-aria-busy:`, so "Testing…" with its spinner keeps its variant's colours.
12. **Secondary's hover is the ink border only.** The hand-written small buttons that copy the secondary look (the header's and System status's Copy, the notes drawer's narrow-screen button, the GIF button, the translation boxes' buttons, and the buttons built by `notes/merge.js`, `mind_graph/card_notes.js`, `translate_controller.js` and `media/upload_tiles.js`) take the field-line outline now and keep their `hover:bg-sunken`; they move to the ink hover when each becomes a `ButtonComponent`.
13. **The badge rule covers every chip that cannot be pressed**, the status chips included, not only DEFAULT: the answer's reason ("so only buttons have an outline") is true of the outlined Draft chip beside Preview as of DEFAULT. The translation chip keeps its border, because C1 names that border as its decoration and its dashes say "missing". NO ALT becomes the `:warn` badge; D2 calls it fine, and the tint keeps it as visible as its border did.
14. **The Trash's type tabs are filter pills** and are inverted with them.
15. **The whole rich-text toolbar is sans**, not only H2–H4: the answer's reason is that buttons are sans; the glyphs (B, I, •, ❝) read the same in either face.
16. **The tile's and the tree's notes counts become 11px** with every other count (`text-label`); the tile's 18px pill holds them.
17. **The site's control outline is `--th-meta`**, an existing token; the answer's `--th-fg-faint` does not exist, and a new site token would be a new promise.
18. **The Copy button's 28px hit area does not change the strip's height**: its block padding is taken back by a negative block margin of the same size.
19. **An empty band is decided by what its blocks draw.** A section with no block already drew nothing (`render?` since the sections spec); the Home page's empty band holds a block that draws nothing. The section now asks `render_block` of its blocks, in order, until one draws something, so a band with content renders its first drawn block twice (once to ask, once to draw) and an empty one renders nothing. The section's line in the theme contract does not change.
20. **The save status line moves into every block card's header, not only the Rich text card's.** The gap is the status line's reserved line plus the body's gap, in every card; the answer saw it on one. The line keeps its reserved height (the click it protects is still lost when content moves under a press) and costs none in the header, whose height its buttons already set. A long message (stale, saved over) may wrap the header to a second line; those states follow a failed save, never the first save.
21. **The disclosure triangle is drawn in CSS** (`.admin-disclosure::before`, `content: "▸" / ""`), not with an element, so the four summaries keep their text as their only content.

## What is not in this pull request

PR 2: form widths at 760px; the Translations table's words and row click; the Media drop zone; Settings' nav, social links, logo square and save bar; the post editor's duplicated slug line; two-letter note avatars; the Mind graph's legend split, fit and count badges over page cards; the site's captions in sentence case; the "Related" heading; tags as links; the dashboard grid; collapsed activity; Notes for you's unread state; the empty states' wording. Not planned anywhere: the Media thumbnails in dark (D2 asks to verify; they were not yet loaded at capture). Separately: the Note block (D4).

## Risks

- **The theme contract.** Changing a token's VALUE is allowed; renaming or removing one is a breaking change. This PR changes values (`--th-line`, `--th-sunken`, the dark strong band's four) and the descriptions of `--th-line-strong` and `--th-meta`, and adds no `--th-` token. A theme that set its own `--th-band-strong` in dark keeps it, but now inherits the new dark `--th-on-band-strong*` unless it set those too; the release note says so.
- **Every CS Studio screen changes look**, so every screenshot in the guide is stale (the Documentation list below). No behaviour changes except the busy button's `aria-busy` and the status line's place.
- **`bg-ink/6`, `not-disabled:`, `not-aria-busy:` and `--text-label--font-weight`** are Tailwind 4 features; `bin/rails tailwindcss:build` must contain each (the plan's tests read the built stylesheet).
- **cat-5 near the accent in dark** (Ruling 5).
- **The section renders its first drawn block twice**: a Code block's lex is cached, a Post list's query is run twice. Measured by the existing statement tests; accepted for a section.

## Testing

- A shared measuring module (`test/support/contrast_measure.rb`), taken out of `design_tokens_test.rb` and taught `rgba()`, for both tests below.
- **`test/lib/admin_contrast_test.rb`** (new) holds every CS Studio figure above in both schemes: text at 4.5:1 on paper, surface, sunken and chrome; `--cs-field-line` at 3:1 on paper, surface and sunken; the state marks (`ok`, `warn`, `dim`, `meta`) at 3:1 on surface and chrome; the selected row's bar and a selected pill's text and ring; lines and strong lines over their old floors; the dark grounds' steps; the six type hues at 3:1; the Mind graph's page mark and tree line at 3:1. And a sample that shows the measuring fails.
- **`test/integration/design_tokens_test.rb`** gains: `--th-meta` at 4.5:1 on the page and (as the band values it) on the tinted band; `--th-meta` as an outline at 3:1; `--th-line` at its floor; the bands' steps (tinted ≥ 1.15, dark strong between 1.4 and 2.0); the code block in a strong band is dark in both schemes. The existing 42 syntax pairs, the band texts and the focus rings run on the new values.
- **`test/lib/admin_design_rules_test.rb`** gains four guards: a line that draws a pressable or typed-into element (a `hover:`, `focus…:`, `has-checked`, `placeholder:` or `cursor-pointer` class) never uses `border-line-strong` (two named exceptions); no `text-[10px]` and no mono `text-[11px]`; the stylesheet's controls (`.cs-select`, `.cs-toggle`, the invalid-border fallback, the prefix input) use `--cs-field-line`; and every mono-label summary is an `.admin-disclosure`.
- Component tests for the button, the badge, the chips, the translation chip and tabs, the block icon in its three places, the tree's marks and selected row, the segmented class, the toolbar's button; model tests for `t.icon` and `blank:` on `:content_type`; Mind graph module tests with the two new theme keys; system tests for the busy button, the status line in the header (the gap, and a long message in a narrow card), the selected pill's focus ring in both schemes and Copy's 28px target; the disclosure's triangle is a rule of the stylesheet, read by the design rules test.
- The full check: `bin/rubocop`, `bin/brakeman`, the unit suite, the browser suite at `PARALLEL_WORKERS=6`, `bin/theme-build-check`.

## Documentation (the PR's "Documentation" section; pages in `contentspiel-docs`)

Editors (screenshots and words): `editors/getting-started/signing-in-and-finding-your-way.md` (the look, dark mode), `editors/pages/the-page-tree.md` (state marks, the selected row, "+ New page"), `editors/pages/build-a-page-with-blocks.md` (icons in the picker and on cards, the save line in the card's header, Discard changes as a plain button), `editors/pages/arrange-blocks-in-sections.md` (the tile's icon), `editors/pages/the-rich-text-editor.md` (the toolbar's active state), `editors/pages/page-settings-and-search-appearance.md` (the Page settings disclosure), `editors/posts/work-with-many-posts.md` (filter pills, the split button), `editors/posts/publish-schedule-and-preview.md` (Discard changes, the chips), `editors/posts/tags-related-posts-and-the-mind-graph.md` (page marks and tree lines in dark, zoom buttons), `editors/translating/keep-translations-up-to-date.md` (● and ○), `editors/media/the-media-library.md` (filter pills, UNUSED and NO ALT), `editors/trash/the-trash.md` (type tabs), `editors/working-together/notes-on-content.md` (New note). Administrators: `administrators/site/languages.md` (DEFAULT). Integrators: `integrators/theming/the-theme-contract.md` (the changed values, the strong band in dark, `--th-meta` as the faint-text and outline token and its 4.5:1 / 3:1 rule, `--th-line-strong`'s narrower role), `integrators/how-it-works/adding-a-block-type.md` and `integrators/how-it-works/block-types-from-outside.md` (`t.icon` and its names).
