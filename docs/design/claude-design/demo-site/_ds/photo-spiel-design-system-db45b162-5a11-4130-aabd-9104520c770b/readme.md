# Photo·spiel — Design System

The canonical visual language for **Photo·spiel**, Dominik Knafelj's photography
portfolio — armour, aviation and fortification, museum & field, Washington DC
area. Theme name: **VANTAGE** — a stark, cinematic, edge-to-edge contact-sheet
aesthetic on true black. This is the source of truth for tokens, brand, reusable
components, and full-screen recreations of the public site and admin.

Link `styles.css` (a list of `@import`s) to inherit every token and webfont.

---

## Sources

This system was extracted from the design handoff and HTML/CSS/JS prototypes for
the Photo·spiel redesign (theme **VANTAGE**), and the production Rails 8 + Hotwire
+ Tailwind app it shipped into (deployed at **photo-spiel.com**).

- Reference prototypes (public + admin), provided as a read-only codebase mounted at `design/`:
  - Public: `design/reference/Photospiel.html` · `styles.css` · `app.js` · `tweaks.js` · `image-slot.js`
  - Admin: `design/reference/Admin.html` · `admin.css` · `admin.js`
  - Assets: `design/reference/assets/` (Dominik's screenshot crops — placeholders for real photos)
- Prior design-system folder: `design/design-system/` (tokens, `foundations.html`, `components.html`, fonts).
- Handoff + implementation notes: `design/README.md`, `design/IMPLEMENTATION.md`.
- Production screenshots: `design/screenshots/` (real, copyrighted photos — not shipped here).

The reader is not assumed to have access to these; they are recorded for provenance.

---

## Brand

**Wordmark:** `PHOTO·SPIEL` — Archivo 600, uppercase, wide tracking, separated by
a **middot `·` (U+00B7)** that echoes the `photo-spiel.com` domain. A hairline
rule sits beneath it, and under that the credit line **`by Dominik`** in small
wide-tracked mono. One signed lockup — never a title plus a tagline. Left-aligned
in structural contexts; centered only in centered layouts. See `components/brand/`.

**Positioning line:** `PHOTOGRAPHER · WASHINGTON DC → THE FIELD`.

**Tone:** stark, cinematic, editorial, austere. The work is the subject; the
chrome gets out of the way.

---

## Content fundamentals (voice)

- **First person, spare.** "Hi, I'm Dominik. Every photo here was shot, edited and
  printed by me." Warm but unembellished. "No stock, no AI, no studio."
- **Mono is the technical register.** EXIF, locations, counts, dates, labels are
  all IBM Plex Mono, uppercase, wide-tracked — they read as instrumentation:
  `f/2.8 · 1/125s · ISO 800 · 35MM`, `42 FRAMES`, `BOVINGTON`.
- **Uppercase structural headlines**, often with a `·`-joined index line above
  (`PORTFOLIO · 2024–2026`, `01 — STATEMENT`).
- **No emoji. No exclamation marks. No marketing fluff.** Subjects are named
  plainly: Wotan, Jagdpanther, Flak 88, Kehlsteinhaus.
- **Casing:** Title Case for album names; lowercase for tags (`tank`, `germany`,
  `battlefield`). Sentence case for body and descriptions. ALL-CAPS only for the
  mono meta layer and structural headlines.
- **Em dash for asides**, middot `·` to join meta, arrow `→` for movement
  (DC → the field).

---

## Visual foundations

**Color.** True-black ground (`--bg #060607`) so photographs glow. Text is a
near-white (`--fg #f5f5f6`) stepping down through `--fg-dim` / `--fg-faint` for
hierarchy. The accent is **cold steel-blue** (`oklch(0.74 0.10 236)`), used
sparingly for active states, links, hover numerals, focus rings and the mono
index lines; **amber** (`oklch(0.76 0.14 62)`) is the photographer's saved default
and the admin's primary-button color. Four accents are selectable
(steel / amber / mono / crimson) via Tweaks and per-album appearance. Status:
`--ok` green (processed/published), `--danger` red (delete).

**Structure = hairlines.** Vantage is **edge-to-edge**: no page padding, no grid
gaps, no rounded corners (`--radius: 0`). Everything is divided by **1px rules** —
`--line` (soft, 10% white) and `--line-strong` (structural, 22% white). The
masonry grid, album grid, header, intro and contact list all butt against these
rules like frames on a contact sheet. The admin softens inputs/buttons by just
2px (`--radius-admin`) for tap clarity; tag pills and toggles are full `999px`.

**Type.** Archivo (grotesk) for everything visual; IBM Plex Mono for the
technical layer. Wide tracking throughout (`--track 0.06em`, `--track-wide
0.18em`). Display headlines are uppercase **700** at `clamp(34px, 5vw, 68px)`,
tracking `-0.01em`. Body 16px / 1.5. Mono labels 10–11px, uppercase, 0.14–0.2em.

**Backgrounds & imagery.** Photographs are the only imagery — cool, slightly
desaturated, cinematic. There are **no decorative gradients, no patterns, no
illustration**. The one "generated" texture is the deterministic 8-tone
placeholder gradient (see Signature systems). Imagery skews warm-museum-light /
cool-steel; never b&w, never heavily filtered.

**Hero = gradient scrim, not a banner.** The featured photo fills a full-width
band; a localized radial dark **pool** (bottom-left) anchors the headline while
the top/right of the frame reveals the image. A subtle `text-shadow` is the safety
net. Never a separate boxed banner that pushes content down. Toggleable
("Headline image").

**Tiles & cards.** A tile is an image (or gradient) with a subtle top light-pool +
bottom vignette, **no border-radius, no drop shadow** — it is bounded only by the
contact-sheet hairlines. On hover it scales `1.035` over `0.7s` and saturates a
touch; the mono caption (title left, frame-number · focal right, number in accent)
fades up `0.35s`. Album covers are 4:3 with a mono frame-count badge
(`rgba(0,0,0,0.45)` + `blur(6px)`, top-right). Cards never have soft shadows or
rounded corners — that's an anti-pattern here.

**Shadows.** Used **only** for true overlays: the lightbox image
(`0 40px 120px`), dropdown menus (`0 24px 60px`), the Tweaks/admin panels
(`0 30px 90px`). Surfaces in flow get hairlines, never shadows.

**Transparency & blur.** Reserved: header/top-bar `backdrop-filter: blur(12px)`
over a `color-mix` of the bg; the count badge `blur(6px)`; the lightbox scrim
`blur(10px)`. Not decorative — it's for legibility over content.

**Film grain.** A fixed full-viewport SVG `feTurbulence` overlay,
`mix-blend-mode: overlay`, opacity `0.05`. Toggleable per album.

**Motion.** Restrained. **One ease** (`cubic-bezier(0.22,1,0.36,1)`), fades and
short translates only. No bounces, no infinite decorative loops on content.
Hover: idle nav `--fg-dim` → `--fg`, active gets an accent underline; buttons
brighten their border to `--fg` (primary brightens `1.08`); toggles slide;
segmented controls invert (white fill, black ink) when on; contact links nudge
`14px` right and go accent. **Press/reduced-motion/print:** entrance effects must
resolve to the visible end-state — the base style is the end state.

---

## Iconography

Deliberately **near-iconless** — the design speaks in type, rules and
photography. Where glyphs appear they are **Unicode**, not an icon set: middot
`·`, arrow `→`, diamond `◆` (the Appearance marker), lightbox chevrons `‹ › ×`,
the `⌘K` search affordance, status dots (CSS circles), the `↗` external-link
mark, the `×` tag-pill remove. **No emoji. No icon font. No hand-drawn SVG.** If a
richer icon need arises in the Rails build, use a thin-stroke set (e.g. Lucide) at
1.5px, monochrome `--fg-dim` — but the default is no icons.

---

## Signature systems

**8-tone placeholder palette (cycled by position).** steel → amber → olive →
charcoal → blue → sepia → graphite → rust. A deterministic repeating pattern that
reads as varied. Used as image **loading state** (gradient under a lazy `<img>`
that fades in on load), **empty-album** ghost frames, and missing covers. Index by
a stable number (grid position or `photo.id % 8`). Implemented in
`components/media/Placeholder.jsx` (`gradientBg(seed)` is exported).

**Per-album appearance.** Each album owns its presentation — headline image,
accent, density, captions, grain — as DB columns read by the album show view. The
Gallery edits a global default; opening an album scopes the Tweaks panel (and the
admin Appearance fieldset's live preview) to that album. Density → masonry column
width: spacious ≈ 360px, standard ≈ 300px, dense ≈ 245px.

**Watermark renditions.** Server-side: the full/`web` variant is watermarked
`© Knafelj` (mono italic, bottom-right); the `thumb` variant is clean. In these
specimens, pass `watermark` to `Placeholder`/`Tile` only on full/lightbox renders.

---

## Index / manifest

**Foundations**
- `styles.css` — entry point; `@import`s the whole token + font closure.
- `tokens/colors.css` · `tokens/typography.css` · `tokens/spacing.css` · `tokens/fonts.css`
- `fonts/` — self-hosted Archivo + IBM Plex Mono `.woff2` (fontsource per-weight, latin + latin-ext).
- `guidelines/*.card.html` — foundation specimen cards (Colors, Type, Spacing, Brand).
- `assets/` — `hero-test.png`, `wotan-grid.png`, `hangar.png` (Dominik's crops — placeholders for real photos).

**Components** (`components/<group>/`, each with `.jsx` + `.d.ts` + `.prompt.md` + a card)
- `brand/` — **Wordmark**
- `buttons/` — **Button** (primary / default / ghost · sizes · disabled)
- `controls/` — **Toggle**, **Segmented**
- `forms/` — **Field**, **Input**, **Textarea**, **Select**, **Checkbox**, **TagInput**
- `media/` — **Placeholder** (+ `gradientBg`), **Tile**, **AlbumCard**
- `data/` — **ExifTable**, **StatusDot**, **CountBadge**, **TagPill**

**UI kits** (`ui_kits/<product>/`)
- `public/` — the Vantage public site: Gallery, Albums, Album show, About, Lightbox.
- `admin/` — the dark CRUD: Photos / Albums / Tags tables, Edit-album Appearance fieldset + live preview + reorder, Edit-photo form + tag input.

**Skill**
- `SKILL.md` — Agent-Skills front matter for using this system in Claude Code.

---

## Using it

**For new mocks / prototypes.** Link `styles.css`, load the compiled
`_ds_bundle.js`, and read components from `window.PhotoSpielDesignSystem_db45b1`.
Keep to the hairline / edge-to-edge structure; don't invent colors, radii or type
outside this system.

**In the Rails app.** Fold the token files into the Tailwind `@theme` / `:root`
and reference via `var(--…)` or arbitrary values (`bg-[var(--bg)]`,
`text-[var(--fg-dim)]`). Self-host the fonts from `fonts/`. The components here are
cosmetic recreations — map them onto your ViewComponents / Stimulus controllers.

---

## Caveats / substitutions

- **Fonts** are the fontsource per-weight `.woff2` files (latin + latin-ext),
  self-hosted in `fonts/` — not the single variable files some older notes named.
  Both Archivo and IBM Plex Mono are SIL OFL 1.1 (free to ship). No substitutions.
- **Imagery** in the kits is the deterministic gradient placeholder plus three of
  Dominik's screenshot crops; real photos replace these in production.
