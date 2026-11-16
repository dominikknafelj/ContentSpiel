# The Gallery block: a list of library images, as a grid or a carousel

Status: built (plan `docs/superpowers/plans/2026-11-16-gallery-block.md`). Where the build left this text, §20 "As built" says so; the description of the code as it is lives in `docs/reference/content-blocks-and-types.md`, "The Gallery block". The behaviour is settled here; the looks are the
Design System's cards **StudioGallery** (CS Studio) and **SiteGallery** (the
public site, the default theme), version `1794862802-0737` (v253) (§16). A card's
word wins over this file's; on behaviour this file wins, and where the two
differed the ruling is in §19. A word the cards do not give is marked "(not on
the card)". An answer marked **(call)** is the planner's recommendation, for
the owner to overrule; the owner's questions are in one place, §18. The plan is
`docs/superpowers/plans/2026-11-16-gallery-block.md`. It follows "Adding a
block type" (`docs/reference/content-blocks-and-types.md`) step by step (§14),
and advances #116 (a schema field that refers to library images).

## 1. Why

The owner asked on 2026-11-14 for "one block holding a list of images" (the
roadmap's catalogue, item 2, D4: "to decide: grid or lightbox, a caption and alt
text per image and language, choosing and ordering several images, with #116"),
and on 2026-11-16: "Also think about the image carousel for the frontend."
Today a page shows several images only as several Image blocks, or a section of
Image blocks in columns: no order of their own, no carousel, a card per image in
the editor.

#116 names why this is not a matter of storing ids in `settings`: images held
that way are not counted as used, can be deleted while a live page shows them,
are not protected through the published copy, and have no picker. So the block
brings the field type #116 asks for, and the CMS's image-safety rules learn to
read it by its type.

## 2. Goals, non-goals, anti-goals

**Goals.**
- A block holding an ordered list of up to 60 library images, each with a
  caption per language and an alt text that is the library image's unless the
  editor overrides it, per language.
- Chosen with the media picker, several at once or a whole folder at once,
  reordered by drag and by the keyboard, removed one by one.
- Drawn as a grid or a carousel, the editor's choice. The carousel follows the
  WAI-ARIA APG carousel pattern, works by buttons, a slide picker, the keyboard,
  swipe and scroll-snap, and without its script as a scroll-snap row.
- Served at the widths the library makes, lazily, with no layout shift.
- Themable through the theme contract: tokens, the template, and the script's
  markup.
- The images are protected like a hero's or an Image block's: counted as used,
  kept out of the trash while shown, restored with their page.

**Non-goals.**
- A lightbox (§7.7, call).
- Autoplay (§7.6, call).
- Per-image links.
- Cropping or a focal point per image (the roadmap's "Cropping and a focal
  point"): the frame crops at the centre.
- A single-image field type `:media` and image fields for post types (#116's
  rest, §3.4).
- AI translation of the gallery's texts in this build (§3.3, owner question).

**Anti-goals.**
- An image a live page shows that can be moved to the trash or deleted.
- A carousel that moves by itself, or moves under reduced motion with an
  animation.
- A carousel whose height jumps between slides, or a grid whose rows jump as
  images load.
- A carousel that is unusable without its script, or a script that leaves its
  words or state behind in Turbo's cache.
- A second path that writes which images a page uses beside the usage index.

## 3. Where each value is stored (step 0)

### 3.1 The fields

No column, no migration, no new service (step 0's preference). All in the
block's `settings` and `translated_settings`:

| Field | Type | Translated | What |
|---|---|---|---|
| `layout` | `:select` `{ "grid" => "Grid", "carousel" => "Carousel" }`, `control: :segmented`, default `"grid"` | no | the public layout |
| `ratio` | `:select` `{ "3:2", "4:3", "1:1" => "Square", "16:9" }`, default `"3:2"`, `label: "Shape"` | no | every frame's shape |
| `fit` | `:boolean`, `label: "Show whole images"` | no | false: each image fills its frame, cropped at the centre; true: each image is shown whole inside its frame, on the stage colour |
| `label` | `:string`, `max: 80`, `help: :"gallery.label_help"`, `placeholder_public: "blocks.gallery.label"` | yes | the gallery's name for a screen reader (the carousel's and the grid's accessible name), "Image gallery" in the visitor's language when blank |
| `images` | **`:media_list`** (new), `max: 60` | no | the ordered library image ids |
| `texts` | **`:media_texts`** (new), `of: :images`, `max: 1000` | yes | per image, per language: `{ "<asset id>" => { "caption" => String, "alt" => String } }` |

**The default layout is the grid (call):** it draws without a script, moves
nothing, and shows every image at once; a carousel is one press away. **The
ratio is always set (call):** "keep each image's own" was the alternative, and
it makes a ragged grid and a carousel whose height jumps from slide to slide,
the layout shift the owner ruled out; `fit` gives the uncropped look inside a
steady frame.

**An image appears once in a gallery (call).** The list is unique; adding an
image that is already there is a no-op the picker shows (its tile is marked
"In the gallery" and cannot be chosen, §10.4). That lets the
texts be keyed by the image's id, so reordering moves no text, and nothing
needs an item id of its own.

### 3.2 The two new field types (#116)

Registered in `ContentModel::FieldTypes`, after `:form`:

- **`:media_list`**: an ordered Array of positive Integers (library image ids).
  Its cast takes an Array or a JSON String of one (the card's hidden input),
  keeps positive integers, drops duplicates keeping the first, and answers nil
  for anything else or an empty list. `max:` is the most images (refused,
  never cut: `:too_many_images`, "holds more than %{count} images"). Not
  translatable; audited `:value`; never `translated: true` (refused at
  registration: one order for every language).
- **`:media_texts`**: a Hash from a library image id (a String of digits) to
  `{ "caption", "alt" }`, each a String, outer white space taken off, blank
  ones dropped, an image with neither dropped. `of:` names the `:media_list`
  field it describes, checked by the type's `finish` once every field is
  declared (as `:mermaid`'s `drawing:` is): a `:media_list` of the same
  definition, refused otherwise. `max:` is the most characters of one text
  (`:too_long`). Must be `translated: true` (refused without). Tracked (a
  translation state of its own); **not translatable** in this build (§3.3);
  audited `:value`.
- **A new question every field type answers: `media_ids`**, `->(value) {
  Array<Integer> }`, the library images a value refers to; `[]` for every type
  but `:media_list` (a `FieldType` default, so the sixteen built-ins say
  nothing new). The usage index, the published copy's images, the choosing
  check and the tile's thumbnail ask every field of a definition through it,
  never a type's name (`test/lib/field_type_branches_test.rb` holds that).
- **Both are a built-in block type's alone** (`FieldTypes::BLOCK_ONLY`): a post
  type may not declare them ("the post editor has no picker for a list of
  images yet, and `Posts::Save` does not run the choosing check for one"), nor
  an outside block type ("its input is the Gallery card's own rows"). Both
  reasons are seams, named in #116's rest (§3.4).

### 3.3 Translations

`texts` is one translated field, so it has one translation state per
language (`Translations::Tracker`): German is *missing* while English has texts
and German none, *outdated* when English's texts change after German's were
written. **A partial translation reads as translated (limit):** German with two
of five captions is not marked missing; a state per image would need the
tracker to know a field's parts. Named in the roadmap with the AI half below.

**Not offered to AI translation in this build (call, owner question):**
`AI::Translate` sends a field as one String or one rich-text body; a Hash of
texts needs it to flatten `texts.<id>.caption` into fields of their own and put
them back. A follow-up, named in the roadmap. "Translate all" leaves the
gallery's texts out, as it leaves a Code block's code out.

### 3.4 Why not the alternatives

- **A container of Image blocks** (a section of one lane accepting only Image
  blocks): every image's alt, caption, usage, choosing, trash and translation
  would come free. Rejected: a container cannot stand in a section's column (a
  section holds no container), which is where a two-column page wants its
  gallery; sixty images would be sixty cards and autosaving forms; and "a
  block changes container in three places and no other" would gain a fourth.
- **A `groups` field** of an image and its texts: a group's subfields are not
  translated per language (a translated `groups` field is a whole list per
  language, so the order and the images would differ by language).
- **Ids in `settings` as plain integers**: what #116 exists to stop.
- **#116's rest**: the single-image `:media` field type, image fields on post
  types, and an outside type's use of these two are left open. The Image and
  Card blocks keep the `image` column (`uses :image`): a new built-in with one
  image would use `:media` when it is built. #116 stays open with this noted.

## 4. The images are references

What protects a hero's image protects a gallery's, by the field's type:

- **Choosing** (`Media::Choosing`, from `ContentBlocks::Save`, for every
  `media_ids`-answering field of the block's definition): ids that are in the
  list now and were not in the stored list need `media.upload` (denied before
  anything is looked up) and must be kept library images, else the field's
  error "has an image that doesn't exist" and nothing is written. Ids already
  stored, a reorder and a removal need only the edit right the save already
  checked. A trashed image reads as missing, as for a hero.
- **The usage index** (`Media::UsageIndex.refresh(block)`, already called in the
  save's transaction): one row per image of the list, role **`block_field`**
  (a new entry of `Media::Usage::ROLES`), `locale` nil, owner the block, only
  for ids that exist (one query, as rich text's rows are). So "Used on", the
  "Unused" segment, `Trash::Move`'s refusal while a kept owner uses the image,
  `Trash::Purge`'s "only when no usage row points at it" and
  `Trash::Restore`'s "restore every trashed image the record's rows still
  name" all count a gallery's images with nothing of their own.
- **The published copy** (`Media::UsageIndex.asset_ids_in(version)`): a copy's
  blocks name their images through the same question, reading each copied
  block's `settings` with its type's definition, so an image only the published
  gallery still shows stays protected (role `published`) until the changes are
  published.
- **No foreign key** can point into jsonb: the protection is the usage rows,
  as for an image inside rich text (`docs/reference/media.md`, "References and
  usages"). An id written around the services (a console write) that names
  nothing is skipped when drawn and has no row.
- **The content version**: a library edit of an image a live gallery shows
  bumps it through `Media::Usage.shown_publicly` (the block's rows), unchanged.

## 5. The definition

```ruby
BlockTypes.register :gallery do |t|
  t.label "Gallery"
  t.icon "images", family: :media           # a new entry of ICONS (StudioGallery, D1)
  t.field :layout, :select, options: LAYOUTS, default: "grid", control: :segmented
  t.field :ratio, :select, options: RATIOS, default: "3:2", label: "Shape"
  t.field :fit, :boolean, label: "Show whole images"
  t.field :label, :string, translated: true, max: LABEL_LENGTH, help: :"gallery.label_help", placeholder_public: "blocks.gallery.label"
  t.field :images, :media_list, max: MAX_IMAGES
  t.field :texts, :media_texts, translated: true, of: :images, max: TEXT_LENGTH
  t.component Blocks::GalleryComponent
  t.theme_methods :block, :page, :layout, :ratio, :fit, :label, :items, :sizes, :string, :pattern
  t.tokens themed: %w[gallery-stage gallery-control gallery-control-ink gallery-control-edge gallery-pick gallery-pick-current], fixed: %w[gallery-gap]
  t.stylesheet "gallery.css"
  t.summary ->(block, locale:) { Gallery.summary(block, locale: locale) }
  t.preview ->(block, locale:) { Gallery.preview(block, locale: locale) }
  t.search_text ->(block, locale:) { Gallery.search_text(block, locale: locale) }
  t.read_only_actions …                     # the card script's reading actions, if any (§10)
  t.sample images: 3, settings: { "layout" => "carousel", "ratio" => "4:3" }, translations: { … }, shows: [ … ]
end
```

`MAX_IMAGES = 60`, `LABEL_LENGTH = 80`, `TEXT_LENGTH = 1000`, all on
`BlockTypes::Gallery`. The token names are SiteGallery's ("The tokens"), the
seven above; a token's name is a promise from the day it ships. **No token is
named `gallery-frame`**: the outside test type
`gallery/album` (`test/support/gallery_album.rb`) declares it, its owner
`gallery` sharing the prefix the built-in uses, as a gem owner `card` would
share the Card's.

**The name `gallery`.** It is no constant of the application, and must not
become one: the type's helpers are `BlockTypes::Gallery`'s module methods and
`Blocks::GalleryComponent`'s, never a top-level `Gallery::` (which would refuse
a gem owner `gallery` at boot, `TopLevelNames.owners`, and break the outside
test type). Several tests use `"gallery"` today as the name of a block type
that is not registered (`test/integration/public_blocks_test.rb`,
`test/models/built_in_types_test.rb`, `test/models/audit/sentence_test.rb`):
they are renamed to a name nothing will register (`retired_widget`) before the
type exists, the case the reference's step 2 warns of.

## 6. Layouts, the frame and the limits

- **Grid:** every image in a frame of the set ratio, in rows; the number of
  columns is the theme's. The default theme's (SiteGallery, D7): the block is a
  size container (`container-type: inline-size`), one column below 320px of
  its width, two from 320px, three from 640px, so a phone draws one and a
  section's half column (352px, 328px in a band) two (§19, §20); the gap
  `--th-gallery-gap`.
  Captions under their image.
- **Carousel:** one image at a time at the block's width, in a frame of the set
  ratio, the caption under it; the other images are a scroll away (§7).
- **The frame** is the set ratio in both layouts, with `object-fit: cover`
  (cropped at the centre) or, with `fit`, `contain` on `--th-gallery-stage`.
  The ratio and the fit are classes built from the settings
  (`content-block--gallery--ratio-3-2`, `content-block--gallery--fit`), plain
  rules in `gallery.css` (a class built from data, which no utility scan sees).
- **Limits (call):** 60 images; a label of 80 characters; a caption or an alt
  text of 1,000 characters. A gallery with no image draws nothing on the site
  (`render?` false) and says "Empty" on its tile.

## 7. The public page

### 7.1 Widths, loading, no layout shift

Every image is drawn by `Media::PictureComponent` (one `<img>`, its `width` and
`height`, the library's widths as `srcset`, the preview under it while they
load), lazy (the default), so the widths are the ones the library already
makes (`docs/reference/media.md`, "What a page draws"). `sizes` is the block's
width (`Blocks::ImageComponent.sizes_for(block)`, the content column or the
section column's share) divided by how many images a row holds.
`sizes(per_row:)` takes an Integer, or a Hash of the block's least width in
pixels to the images a row holds there: `sizes(per_row: 1)` for the carousel,
`sizes(per_row: Blocks::GalleryComponent::GRID_COLUMNS)` (`{ 0 => 1, 320 =>
2, 640 => 3 }`) for the default grid, a theme with another grid passing its
own. Each width `sizes_for` names is divided by the count for that width: a
fixed width in pixels by the count its own width takes, a width relative to
the viewport (`100vw`, `50vw`) by the count of the narrowest block it can be,
which is one. The top-level block is `Blocks::SectionComponent::CONTENT_WIDTH`
(736px) wide, a section column its share of it, and one image asks
`round((W - (n - 1) * gap) / n)` for a block of width W holding n columns with
the gap `--th-sp-3` (14px): `(736 - 2 * 14) / 3 = 236`, so the default grid at
the top level asks `(min-width: 768px) 236px, 100vw`. It may ask for more
pixels than a row draws, never fewer (§19). Nothing shifts: every
frame has its `aspect-ratio` before any image arrives, and a carousel's slides
are all in the document from the start, so the row's height is set at once.
**No image is eager (call):** a gallery is rarely the first thing on a page; the
hero is the page's eager image.

### 7.2 The grid

A list (`<ul>`) of figures, each its image and its `<figcaption>` when the
caption is not blank in the language shown (the site's fallback applies). No
script. The list is named by the gallery's label.

### 7.3 The carousel: the APG pattern

The pattern is the APG's basic carousel with a slide picker (not the tabbed
one: its hidden tab panels would undo the scroll-snap row that works without a
script). In document order:

1. **The carousel**: an element with `aria-roledescription` the visitor's word
   for "carousel" and `aria-label` the gallery's label.
2. **The controls**, before the slides: Previous and Next, buttons named in the
   visitor's language ("Previous image", "Next image"), each `aria-controls`
   the track. **No rotation control**, since nothing rotates (§7.6).
3. **The track**: the slides in a row, `overflow-x: auto` with
   `scroll-snap-type: x mandatory`, focusable (`tabindex="0"`, named "Images")
   so the arrow keys scroll it with no script, and so a scrollable region is
   reachable by the keyboard.
4. **Each slide**: `role="group"`, `aria-roledescription` the word for "slide",
   `aria-label` "3 of 12" in the visitor's language; its figure and caption.
   A slide holds nothing focusable (the image is no link, the caption is
   text), so a slide out of view needs no `inert`.
5. **The position**, "3 of 12", visible, not a live region.
6. **The slide picker** (call): one button per image ("Show image 3",
   `aria-current="true"` on the current one) for a gallery of **12 images or
   fewer**; above twelve, none: the position, the buttons and the scroll do it,
   and 60 dots is no picker. In the default theme the picker is dots
   (SiteGallery, D6; §7.8).
7. **A status**, visually hidden, `aria-live="polite"`, written only when a
   button or a key moved the carousel ("Image 3 of 12"), never on a free
   scroll or a swipe, which would talk over the person's own gesture (call).

A carousel of **one image** draws that slide alone: no controls, no position,
no picker, no `aria-roledescription`, no script attached (call).

### 7.4 Without the script

What only the script makes work is `hidden` in the markup and shown at
`connect` (step 7's rule): the controls, the position, the picker and the
status. Without the script the carousel is the track alone: a horizontal
scroll-snap row a person scrolls by touch, by a trackpad, by the scrollbar and
by the arrow keys on the focused track, each slide snapping into place. It
works as it is; the script adds buttons, the position and the picker.

### 7.5 The script: `gallery-carousel`

`app/javascript/controllers/gallery_carousel_controller.js`, identifier
`gallery-carousel`, at the top level of `controllers/` and in `PUBLIC_ONLY`
(`app/javascript/controllers/index.js`), so a visitor's page runs it and CS
Studio never imports it (its preview draws the public page, which does).

- **Where it is:** an `IntersectionObserver` on the slides with the track as
  its root marks the current slide (the one most in view); a scroll, a swipe,
  a button and a key all end in the same reading, so the position, the
  picker's `aria-current` and the buttons' `disabled` follow whatever moved it.
- **Previous and Next** move one slide; **disabled at the ends, never wrapping**
  (call: wrapping a scroll row jumps across every slide). When a press disables
  the focused button, the focus moves to the other one, never to `<body>`.
- **A picker button** shows its slide.
- **Keys**, on the track and on the controls: Left and Right move one slide,
  Home and End go to the first and the last, each only without a modifier
  (Alt+Left is the browser's Back). **In a right-to-left page the arrow keys
  follow the screen (call):** Left is the next image; Previous and Next keep
  their reading-order meaning. Moving computes the scroll from the slides'
  rectangles, never from `scrollLeft` signs, which differ in right-to-left
  rows.
- **Motion:** a move scrolls smoothly only under
  `prefers-reduced-motion: no-preference`, otherwise at once; `gallery.css`
  sets `scroll-behavior: smooth` under the same query only.
- **Swipe** is the browser's own scroll with snap: no touch handlers.
- **Its state** is written on its element as `data-gallery-carousel-state`:
  `first`, `middle`, `last` (a theme's stylesheet may read it).
- **Take-back:** at `disconnect` it disconnects the observer, removes the
  listeners and puts back what the server drew (`hidden` on what it showed,
  the status empty, the position the first slide's, no state); nothing is
  taken back at `turbo:before-cache`, which Turbo also runs for a page it does
  not leave, so a copy shown again is decided afresh by `connect`. The
  elements are kept in fields at `connect`, not read through targets at
  `disconnect`.
- **Words** come from the markup (the server's `public.blocks.gallery.*` in the
  visitor's language, on the element's values); the script holds no English.

### 7.6 Autoplay (call: none)

None in this build. A carousel that moves by itself fails people who read
slowly, distracts everyone else, and needs a rotation control, a pause on hover
and on focus, and a stop under reduced motion to be acceptable. If it is asked
for later, its rules are already the APG's and the owner's: off by default; a
visible Pause/Play first among the controls; it stops on hover, on focus
inside the carousel and for good once a person presses anything; it never runs
under reduced motion; at least five seconds a slide; the live region off while
it rotates. Owner question (§18).

### 7.7 A lightbox (call: not now)

No enlarged view. The image viewer (`2026-11-16-image-viewer-design.md`) is CS
Studio's (`Admin::Ui::ImageViewerComponent`) and never reaches a public page.
A public viewer later would reuse its ideas (one dialog, stepping through the
gallery's images, the focus back to the image that opened it, Escape, nothing
left in Turbo's cache) as a public component and script of its own, behind a
setting of the block. Owner question (§18).

### 7.8 The default theme's look (SiteGallery, D6 and D7)

- **The frame:** the block's width at the set ratio (`aspect-ratio`),
  `--th-radius`, `overflow: hidden`; the image `object-fit: cover`, or
  `contain` on `--th-gallery-stage` with "Show whole images". A slide is 100%
  wide with **no peek**: the buttons and the dots say there is more, and
  without the script the scrollbar does.
- **Previous and Next:** 44px circles over the frame's sides, centred on the
  frame's height (never on the caption), 10px in; the ground
  `--th-gallery-control`, the arrow `--th-gallery-control-ink`, a 20px Lucide
  chevron at stroke 2, the edge `box-shadow: 0 0 0 1px
  var(--th-gallery-control-edge), var(--th-shadow-menu)` (the shadow is depth
  only). Disabled at an end: the arrow `--th-meta`, the edge
  `--th-line` with no shadow, `disabled`. The focus ring is the site's: 2px
  `--th-accent`, 2px out. They come first in the document (`controls`) and
  stand over the frame by `position: absolute` in a box of the frame's ratio.
- **The caption:** 8px under the frame, 13px/1.5, `--th-meta`, `--th-dim` on a
  tinted band, `--th-on-band-strong-dim` on a strong one, as the Image
  block's.
- **The foot,** 10px under the caption: the dots centred, the position at the
  inline end (13px `--th-meta`, tabular figures, in a 4.5em box aligned to the
  end; an empty box of the same width at the start keeps the dots centred).
- **The dots:** each a 24×24 button (the 2.5.8 target); at rest an 8px ring
  of 1.5px `--th-gallery-pick`; the current one a 20×8 pill filled
  `--th-gallery-pick-current`, with `aria-current="true"`. Above twelve images
  there are none: the position alone.
- **Right to left:** Previous stands at the right with its chevron mirrored,
  the position at the inline end (the left), the arrow keys follow the screen
  (§7.5).
- **A phone:** the same at 343px; the buttons stay 44px.
- **Without the script:** the track alone, `scroll-snap-type: x mandatory`,
  `scrollbar-width: thin`, focusable and named "Images"; the controls, the
  foot and the status stay `hidden`. With the script
  (`[data-gallery-carousel-state]`) the track's scrollbar is `none`.
- **The grid:** §6; each figure its frame (cover, or contain on the stage)
  and its caption as the carousel's.
- **Dark:** tokens only. The control is a light disc over the image in the
  light scheme and a dark one (`--th-surface` dark) in the dark scheme.
- **The default template's class names** (the default theme's own, not on the
  contract's list): `content-block content-block--gallery` with
  `content-block--gallery--grid` or `--carousel`, `--ratio-3-2` (and
  `-4-3`, `-1-1`, `-16-9`), `--fit`; the parts `content-block--gallery__track`,
  `__slide`, `__frame`, `__caption`, `__controls`, `__button` (with
  `__button--previous`, `__button--next`), `__foot`, `__position`, `__picks`,
  `__pick`, `__status`, `__grid`, `__item`.

## 8. The theme contract

- **The component's line** (`Theme::Contract.components`, the ledger, the
  reference's components table): `blocks/gallery_component` with `block`,
  `page`, `layout` ("grid" or "carousel"), `ratio` (the stored ratio, "3:2"),
  `fit` (true or false), `label` (the gallery's name in the language shown,
  else the visitor's word), `items`, `sizes`, `string` and `pattern`.
- **`items`**: an Array, in the gallery's order, of the images that can be
  drawn (an id that names no image, or an image whose file is gone, is
  skipped), each a value with `index` (1-based), `picture` (a Hash whose keys
  are `Media::PictureComponent`'s: `asset`, `alt`, `sizes`, so
  `<%= render Media::PictureComponent.new(**item.picture) %>`, as the Card's
  `image` is) and `caption` (the caption in the language shown with the site's
  fallback, or nil). `alt` is the gallery's override in the language shown,
  else the library image's, interleaved per language
  (`Media::Asset#alt_text(override:)`, handed the override as
  `{ locale => alt }`).
- **The caption has no library default (call).** Unlike the Image block, a
  gallery's caption is its own: the owner named "a caption per language" for
  the gallery and "alt from the library by default" for the alt. A gallery
  whose captions appear under some images and not others, because some library
  images happen to carry one, is a set nobody wrote. The card offers the
  library's caption as a starting text: "Use library caption" fills the field
  once, and the field stays the gallery's own (§10.3). Owner question (§18).
- **`sizes(per_row: 1)`**: an Integer or a Hash of least widths to counts,
  §7.1.
- **`pattern(key)`**: a public sentence of `position` or `moved` uninterpolated,
  its `%{index}` and `%{count}` left for the script to fill in; the template
  writes it into the script's two values. `string(key, **values)` is never
  called with a value missing.
- **`string(key)`**: a public word in the visitor's language, English the
  fallback (`public.blocks.gallery.*`: `label` "Image gallery", `carousel`
  "carousel", `slide` "slide", `position` "%{index} of %{count}", `track`
  "Images", `previous` "Previous image", `next` "Next image", `show` "Show image
  %{index}", `moved` "Image %{index} of %{count}").
- **The tokens** (`t.tokens`; SiteGallery's table). The page's values stand
  in `tokens.css`, declared on `:root` and resolved there, so a band that
  re-values `--th-ink` does not reach a token that sits on the image; a tinted
  band's and a strong band's own values stand in `sections.css`
  (`.content-section--tinted`, `.content-section--strong`):

  | Token | Page, light and dark | Tinted band | Strong band | What |
  |---|---|---|---|---|
  | `--th-gallery-stage` | `var(--th-sunken)` | the same | `color-mix(in oklab, var(--th-on-band-strong) 10%, var(--th-band-strong))` | the ground behind a fitted image |
  | `--th-gallery-control` | `color-mix(in oklab, var(--th-surface) 92%, transparent)` | the same | the same (it sits on the image) | a Previous or Next button's ground |
  | `--th-gallery-control-ink` | `var(--th-ink)` | the same | the same | its arrow |
  | `--th-gallery-control-edge` | `var(--th-ink)` | the same | the same (it sits on the image) | a button's edge, drawn as a 1px ring of `box-shadow` |
  | `--th-gallery-pick` | `var(--th-meta)` | `var(--th-dim)` | `var(--th-on-band-strong-dim)` | a dot's ring at rest |
  | `--th-gallery-pick-current` | `var(--th-ink)` | the same | `var(--th-on-band-strong)` | the current dot |
  | `--th-gallery-gap` (fixed) | `var(--th-sp-3)` (14px) | | | the grid's gap |

  Contrast is measured on the page, a tinted band and a strong band, both
  schemes (`design_tokens_test.rb`): a button's arrow on its ground at 4.5:1,
  a button's edge on its ground and a dot's ring on paper, a tinted band and a
  strong band at 3:1.
- **The script's markup** (`Theme::Contract::SCRIPTS["gallery-carousel"]`, the
  ledger's `SCRIPTS`, the reference's Scripts table): targets `track`, `slide`,
  `previous`, `next`, `position`, `pick`, `status`, `controls`; values
  `position` and `moved` (the two sentences with `%{index}` and `%{count}`);
  states `first`, `middle`, `last`; no parts, no answer. These are the
  template's **named parts**: a theme that replaces the template keeps them and
  the script works; the default template's class names are the default theme's
  own, not on a list (§7.8 names them).
- **The reference** (`docs/reference/theming.md`): the component's row, the
  tokens' rows, the script's row, and a section "The Gallery block" (what the
  template is handed, what it must keep: the track focusable and named, the
  slides' group role and label, the controls hidden in the markup, the caption
  printed through ERB's escaping, the picker only up to twelve).
- **A fixture theme**, `test/fixtures/themes/gallery`, whose template is
  written from that section alone (`with_gallery_theme`), drawn and driven by
  the script in a test.
- **The release note** with the ledger's lines: Added the Gallery block's
  component line, its seven tokens and the `gallery-carousel` script.

## 9. Search

`t.search_text`: for each image of the list whose file is attached, its caption
and its alt override in that language, read from the copy with the fallback-aware
reader, as the Image block gives its own caption and alt. The library image's
own alt is not searched: it is the asset's, read live and in no copy
(`BlockTypes::Image.search_text`'s reason). No `SiteSearch::Documents::REVISION`
bump: no stored document holds a gallery yet. A case in
`test/models/site_search/block_text_test.rb`.

## 10. The editor (StudioGallery, D1 to D5)

### 10.1 The icon (D1)

Lucide **`images`** (two stacked frames), a new entry `images` of
`BlockTypeDefinition::ICONS` and of the `_icon` partial, on the **media** chip
(`cs-ic-media` on `cs-ic-media-bg`), beside the Image and Card blocks. Its
drawing, at the partial's stroke of 1.5: `<path d="M18 22H4a2 2 0 0 1-2-2V6"/>
<path d="m22 13-1.296-1.296a2.41 2.41 0 0 0-3.408 0L11 18"/> <circle cx="12"
cy="8" r="2"/> <rect width="16" height="16" x="6" y="2" rx="2"/>`.

### 10.2 The card's controls (D2)

- **One row:** Layout (`control: :segmented`, "Grid" / "Carousel", its
  visible legend), then Shape (the select well: "3:2", "4:3", "Square",
  "16:9") filling the rest. The two wrap onto two lines below 420px of the
  card. The row is drawn for a `control: :segmented` select followed directly
  by another `:select`, judged from the fields and never from the type's name,
  and wraps by `flex-wrap` and the fields' least widths, not a size container:
  no size container stands inside the post form ("Rules a change can break
  silently", `docs/reference/design-system.md`).
- **Then** the switch "Show whole images" (ChoiceFields), with no label above.
- **Then** Label, full width, its placeholder the visitor's word ("Image
  gallery"), and the help line under it: "What a screen reader calls the
  gallery. Leave it blank for “Image gallery” in each visitor's language."
  (`admin.components.fields.gallery.label_help`, its "Image gallery" the
  `%{placeholder}` the Search block's help line takes, so another editing
  language reads its own visitor's word).
- **Then** the Images section, under a `cs-line` rule with 12px above it: the
  heading "Images" (14px/600) and, at the right, "12 of 60" (`text-small
  cs-meta`).

### 10.3 The image rows (D3)

- **The rows are the `texts` field's input** (`Admin::Fields::MediaTextsField`):
  one row per image of the list, in its order. **The list is the `images`
  field's input, the hidden variant** (`Admin::Fields::MediaListField`,
  `hidden?` true, as the Diagram block's drawing is): a hidden input holding
  the ids as JSON, written by the rows' script and dispatched as `input`, so
  the card's autosave sends the list and the texts together through
  `app/javascript/saving/queue.js`. A reorder is a change of a field, not a
  block move: no new write path.
- **An input learns its sibling's value**: `Admin::Ui::FieldComponent` hands
  every input the values being drawn (`values:`, the block's `FieldSet` for
  that language), so the texts input reads the list it describes (`of:`). A
  generic addition, unused by every other input.
- **A row:** a `cs-paper` tile (`rounded-tile`, `p-2`, 8px apart), a grid of
  `20px 96px 1fr 28px`, gap 10:
  1. **the drag handle,** the block list's grip, `cs-meta`, a button named
     "Move %{title}";
  2. **the thumbnail,** 96px at 4:3, `rounded` 8px, the library's 480 width
     (`Media::Asset#thumbnail_url`);
  3. **two fields, stacked:** Caption (a one-line well that grows) and Alt
     text (a well), for the language being edited. Alt's placeholder is the
     library image's alt in that language; with no library alt either, it
     reads "No alt text in the library" and the well's bottom edge is
     `cs-warn` (the panel's `.admin-media-alt-warn`). A blank caption whose
     library image has one shows a tertiary "Use library caption" at the right
     of the Caption label: it fills the field, which stays editable and the
     gallery's own;
  4. **Remove,** a 28px icon button (×, `cs-dim`), named "Remove %{title}". It
     applies at once (autosaved), with no confirm.
- **Keyboard moves on the handle,** as the block list's: Space or Enter picks
  the row up (it lifts to elevation 4 on `cs-tile-raised` with a 2px accent
  outline inside); Up and Down move it; Space drops it; Escape puts it back.
  Each step is said in a polite status: "Picked up forest-path.jpg, image 2 of
  12. Up and Down Arrow move it, Space drops it, Escape puts it back.",
  "Moved to 3 of 12.", "Dropped at 3 of 12.", and on Escape "Cancelled.
  forest-path.jpg is back where it was." (not on the card: the block list's
  sentence).
- **Drag** goes through `loadSortable()` (`app/javascript/editor/drag.js`, the
  one SortableJS loader) with the row as the dragged unit (elevation 4).
- **A missing image** (an id whose image is gone, trashed or purged): the
  thumbnail box is `cs-sunken` with Lucide `image-off` in `cs-meta` (a new
  `:image_off` of the `_icon` partial); in place of the fields, "This image is
  no longer in the library" (14px/500) and, in `text-small cs-warn-ink`, "It
  isn't shown on the site. Remove it, or leave it until someone restores the
  image."; Remove as usual.
- **Under the rows:** "Add images" and "Add a folder" (the folder icon), small
  secondaries, then "12 of 60 images" at the right. "Add a folder" is drawn
  only when the library has a folder (`Media::Folder.exists?`, one query per
  card drawn). Both open the picker for several images (§10.4); "Add a
  folder" opens it with the focus on its list of places, where a folder is
  chosen (not on the card: what it opens beyond the picker).
- **The limit reached:** both buttons `aria-disabled` (sunken, `cs-meta`), and
  the line "A gallery holds at most 60 images. Remove one to add another."
  under them.
- **Empty:** a dashed `cs-line-strong` box (`rounded-tile`, `p-5`, centred,
  `text-sm cs-dim`): "No images yet. Add them from the library, in the order
  the site shows them." with the two buttons, secondary (the editor's
  primaries are Publish and + Add block).
- **On a translation tab:** the heading row reads "12 images · the list is
  changed in English", in the default language's name; the rows have no
  handle and no Remove; each field has its reference above it, `text-label
  cs-meta`, one line, truncated: "English: The harbour at dusk, from the north
  pier" (the translation pair's reference, shown inline,
  `MediaTextsField.reference?` false: the rows draw their own); the alt's
  placeholder is the library alt in this language. No control changes the
  list there.
- **Held** (someone else's form, `HeldFields`): the rows are read-only, as
  every held field.
- **The rows' script**, `admin--editor--gallery`
  (`app/javascript/controllers/admin/editor/gallery_controller.js`): opens the
  picker for several images, adds what it hands back (skipping images already
  there, stopping at 60), removes, reorders by drag and by the keyboard moves,
  fills a caption from the library's, and writes the hidden list. Its actions
  write, so none is in `read_only_actions`, and the count in
  `docs/reference/live-editing.md` stays.

### 10.4 The picker, several at once (D4)

A change to `Admin::Ui::MediaPickerComponent`'s contract, whose limit "It
hands back one image: several cannot be chosen." goes.

- **The opening:** the opener asks with `detail: { opener, multiple: true,
  max:, chosen: [ids] }`, `max` what the gallery still takes. Every other
  opener (the hero, the Image and Card blocks, the rich-text editor) is
  unchanged: one image, "Use image", and `media-picker:picked` with that
  image's keys `{ id, url, title, alt, caption }`.
- **The title** reads "Add images" for a multiple opening. The footer's
  primary is "Add 3 images" ("Add images", disabled, at none chosen), and the
  status reads "3 selected · the gallery takes 48 more".
- **A chosen tile:** the accent outline and, at its top left, its order: a
  22px accent pill with `cs-on-accent` 12px/600 numerals and a 2px surface
  ring. Unchoosing renumbers the rest. The tile stays a button with
  `aria-pressed`, its name ending ", chosen 2nd". The choice and its order
  survive a search, a segment, a page and a place. Use adds them in that
  order: `media-picker:picked` carries `items: [{ id, url, title, alt,
  caption }]`.
- **Already in the gallery:** the thumbnail desaturated (`saturate(.35)`, no
  opacity), a `cs-surface` pill at the top left with a check and "In the
  gallery" (11px, `cs-dim`); the tile is `aria-disabled` with that
  description.
- **The limit:** when the choices reach what the gallery takes, the other
  tiles turn `aria-disabled`, and the status says "The gallery takes no more:
  60 images."
- **A whole folder** (needs folders, built: §17): in a folder's place, a row
  above the grid holds the folder mark, its name, "34 images" (`cs-meta`, the
  folder's own kept images, `Media::FolderCounts`) and, at the right, a small
  secondary "Add all 31 new images in this folder", the number counting the
  folder's images not yet in the gallery. When more are new than the gallery
  takes: "Add the first 12 of 31 new images", in **upload order, oldest first
  (call)**: a batch from a camera goes up in shot order, and the editor
  reorders after. Pressing it adds them and closes the picker; the row is
  hidden when nothing is new, and in a single opening, and in All media and
  Not in a folder. The images are answered by `GET /media_folders/:id/images`
  (§10.6).

### 10.5 The tile (D5)

- **One thumbnail,** the first image that exists, as the tile's inline size-6
  thumbnail before the words (v246: no 72px box), through the tile's generic
  thumbnail, which learns to take the first existing id of a `media_ids` field
  where a type has no `image` column. No strip: the summary says the count.
  With no image the tile says "Empty" and draws no thumbnail.
- **The summary line** (`summary`): "Carousel · 12 images" / "Grid · 1 image",
  or "Empty" with no image. **The preview** (`preview`): the label as the
  heading when one is written, so the tile's name reads "Gallery · Harbour
  walk".
- **The hint:** the warn badge (the media grid's "No alt" look,
  `Admin::Ui::BadgeComponent` `tone: :warn`) "3 without alt", counting the
  images whose alt is blank in this language, the override and the library's
  both. The tile's closed set of summary parts gains the kind `:warn`, drawn
  as that badge after the line.
- **Live editing, autosave, the base, the stale check, the claim and the hold**
  are the card's and need nothing; they are tested for the type all the same.

### 10.6 The folder's images

`GET /media_folders/:id/images?limit=L&except=1,2,3` (`as:
:media_folder_images`, `Admin::MediaFoldersController#images`) answers JSON
`{ total:, items: [{ id, url, title, alt, caption }] }`: `total` the kept
images directly in the folder whose ids are not in `except`, `items` the
oldest `limit` of them by id (`limit` capped at
`BlockTypes::Gallery::MAX_IMAGES`; `except` at most `MAX_IMAGES` ids, anything
that is no whole number dropped). The folder is read through
`Media::FolderTree.load` and `Media::Place.parse(params[:id], tree:)`, its
images through `Place#narrow(Media::Asset.kept)`, so a subfolder's images are
never among them. It needs `media.upload` (the picker's own gate), asked
before any folder is looked up; a folder the tree does not hold is a 404. The
controller's `media.manage` gate stays on its writes alone.

## 11. The sample and the showcase

- **The sample** gains one key, `images:` (an Integer), as `image: true` and
  `form: true` are: the shared tests make that many library images and hand
  their ids in order, and `ContentModel::SampleBlock.arguments(…,
  media_asset_ids:)` writes them into the type's `:media_list` field and
  re-keys the sample's `texts`, which are written by **position** ("1", "2",
  "3") because ids are not known when a type is declared; a sample that asks for
  images it was not handed, or names a position past them, raises. The
  completeness test ("a sample fills every column its type uses and every field
  of its schema") counts the list as filled by `images:`.
- The Gallery's sample: three images, a carousel at 4:3, a label and captions
  and an alt override in en, de and es; `shows` the English label, a caption,
  and `alt="…"` of the override, so the canary and the scaffold compare
  values, not a class name.
- **The showcase** (`db/seeds/showcase.rb`): `DevelopmentShowcase.call` makes
  the gallery's three images (three tinted PNGs made with libvips, uploaded
  through `Media::Upload` and titled "Showcase image 1" to "3", so a carousel
  visibly steps; found again by that title on a later run, since
  `Media::Upload` never dedupes) and draws the Gallery
  from its sample in every layout and band as every type is, plus once more as a
  grid (`settings: { "layout" => "grid" }`, as the Note's kinds are drawn from
  one sample).

## 12. Strings

- Public words: `config/locales/public.en.yml`, `public.blocks.gallery.*` (§8),
  read through `string`.
- CS Studio, `config/locales/admin/fields.en.yml` (StudioGallery, "Words"):
  - `admin.components.fields.gallery.label_help` "What a screen reader calls
    the gallery. Leave it blank for “%{placeholder}” in each visitor's
    language." (the card's sentence, its "Image gallery" the placeholder);
  - `admin.components.fields.media_list.display` one "1 image", other
    "%{count} images" (not on the card as a key: the card's "12 images", the
    read-only display every field type has);
  - `admin.components.fields.media_texts.*`, every other word of the card and
    its rows: `images` "Images", `count` "%{count} of %{max}", `count_line`
    "%{count} of %{max} images", `add` "Add images", `add_folder` "Add a
    folder", `limit` "A gallery holds at most %{max} images. Remove one to add
    another.", `empty` "No images yet. Add them from the library, in the order
    the site shows them.", `caption` "Caption", `alt` "Alt text",
    `use_library_caption` "Use library caption", `no_library_alt` "No alt text
    in the library", `remove` "Remove %{title}", `move` "Move %{title}",
    `picked_up` "Picked up %{title}, image %{position} of %{count}. Up and Down
    Arrow move it, Space drops it, Escape puts it back.", `moved` "Moved to
    %{position} of %{count}.", `dropped` "Dropped at %{position} of
    %{count}.", `cancelled` "Cancelled. %{title} is back where it was." (not on
    the card), `missing` "This image is no longer in the library",
    `missing_hint` "It isn't shown on the site. Remove it, or leave it until
    someone restores the image.", `translation_list` "%{count} images · the
    list is changed in %{language}" (one: "1 image · …", not on the card),
    `reference` "%{language}: %{text}".
- CS Studio, `config/locales/admin/ui.en.yml`,
  `admin.components.ui.media_picker`: `title_multiple` "Add images";
  `add_count` zero "Add images" (the card's word at none chosen), one "Add 1
  image", other "Add %{count} images"; `takes` "%{count} selected · the
  gallery takes %{left} more"; `full` "The gallery takes no more: %{max}
  images."; `in_gallery` "In the gallery"; `chosen_order` "%{name}, chosen
  %{ordinal}" with `ordinal` one "%{count}st", two "%{count}nd", few
  "%{count}rd", other "%{count}th", chosen by `Intl.PluralRules`' ordinal type
  (not on the card: the card gives ", chosen 2nd" only); `folder_count` one
  "1 image", other "%{count} images" (not on the card as a key: "34 images");
  `add_folder` one "Add the 1 new image in this folder" (not on the card),
  other "Add all %{count} new images in this folder"; `add_folder_first` "Add
  the first %{count} of %{total} new images".
- CS Studio, `config/locales/admin/editor_screen.en.yml`,
  `admin.components.editor_screen.tile_summary.types.gallery`: `grid` one
  "Grid · 1 image", other "Grid · %{count} images"; `carousel` one "Carousel ·
  1 image", other "Carousel · %{count} images"; `empty` "Empty";
  `without_alt` "%{count} without alt".
- The new files join `CONVERTED` in `test/lib/admin_i18n_test.rb`.
- The type's label and the selects' choices are literals of the definition, as
  every type's are.

## 13. MCP and the audit log

MCP has no block tools: nothing changes there. `get_media_tool`'s usages count a
gallery's page through the usage rows, unchanged in shape. The audit log
records the block's saves as `block.updated` (the list and the texts in
`field_changes` as values: ids and words).

## 14. "Adding a block type", step by step

| Step | For the Gallery |
|---|---|
| 0. Where values are stored | §3: settings and translated settings; no column, migration or service |
| 1. Generate | `bin/rails generate block_type gallery`, after renaming the tests' `"gallery"` stand-ins; its initializer line then moved to stand after the Image block's, so the picker lists the two together (call; the ledger follows that order); red until step 9: the ledger and 9a |
| 2. The definition | §5; `search_text` decided (§9) with its case in `block_text_test.rb`; `preview` held by `assert_preview_shows_a_sample_value`; the sample (§11) |
| 3. A new field type | `:media_list` and `:media_texts` (§3.2), each with its entry, its input and its tests; the option `of:` reused, `max:` per type |
| 4. What is no component's business | `BlockTypes::Gallery.summary`, `.preview`, `.search_text` (module methods); `Gallery`'s items are built by the component from the block, the asset lookup one query (no new top-level name) |
| 5. The public component | §7, §8: `Blocks::GalleryComponent`, its template, `gallery.css`, its tokens in `tokens.css` and `sections.css`, contrast, the Lookbook preview |
| 6. Strings | §12 |
| 7. A public script | §7.5: `gallery-carousel`, a case in `public_javascript_test.rb`, `test/system/gallery_block_test.rb` |
| 8. The editor | §10: the inputs, the rows' script, the tile, the icon `images`; cases in the card, tile, held-fields and content-blocks tests; `test/system/admin/gallery_block_test.rb` |
| 9. The ledger and the reference | the component line, the seven tokens and the script, with the release note; `theming.md`'s tables and section; the fixture theme |
| 9a. The component's contract | `include Blocks::Contract`; `interface:` the theme methods, `words:` the nine keys, `motion: :reduced` (a smooth scroll only without reduced motion), `widths: :from_container`, its limits (60 images, the picker to twelve, no lightbox, no autoplay) |
| 10. The documents | `content-blocks-and-types.md` (a section, the list at its top), `media.md` (the role `block_field`, field-derived usages), `CLAUDE.md` (the index and the rules below), the roadmap ("Shipped", #116's rest, the AI and partial-state follow-ups), the spec's "As built" |
| 11. The whole check | `bin/ci` |

## 15. Guards (as the Code block has them) and what no test holds

Held by a test:
- The theming reference's Gallery tables name exactly the component's methods,
  its tokens, its words and the script's markup
  (`test/lib/theming_reference_test.rb`: "the Gallery block's tables name
  exactly the methods of its entry, its nine words and what the carousel script
  reads").
- A theme replaces the template from the reference alone, and the script works
  on its markup (`test/integration/theme_pages_test.rb` and
  `test/system/gallery_block_test.rb`).
- A caption that looks like markup is text (`gallery_component_test.rb`).
- A public page with a carousel carries `gallery-carousel` and no admin script
  (`test/integration/public_javascript_test.rb`).
- Every gallery token is defined in both schemes and readable on every ground
  (`test/integration/design_tokens_test.rb`).
- No file outside the field-type registry branches on `media_list` or
  `media_texts` (`test/lib/field_type_branches_test.rb`): the usage index,
  the choosing check and the tile ask `media_ids`.
- An image a live gallery shows cannot be trashed, and is restored with its
  page (`test/models/media/usage_index_test.rb`, `test/services/trash/`).

**No guard**, for `CLAUDE.md`'s list:
- A theme's own Gallery template that drops the track's `tabindex` and name,
  the slides' group role and label, or the `hidden` on its controls: the theme
  check reads names, not markup's meaning.
- What `gallery-carousel` writes into a page it takes back: browser tests only.
- `sizes(per_row:)` handed counts other than what the theme's grid draws:
  the browser then fetches a wider or narrower width than needed.
- A change of what `search_text` gives without a bump of
  `SiteSearch::Documents::REVISION`.

## 16. The design answers

The Design System (`https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT`,
version `1794862802-0737` (v253)) holds both cards:

- **StudioGallery** (CS Studio): D1 the icon (§10.1), D2 the card's controls
  (§10.2), D3 the image rows (§10.3), D4 the picker choosing several and a
  whole folder (§10.4), D5 the tile (§10.5), D8 the cards themselves; its
  "Words" are §12's. The MediaPicker and StudioMediaGrid cards point to it.
- **SiteGallery** (the public site, the default theme): D6 the carousel and D7
  the grid (§6, §7.8), the seven tokens with their values (§8), the named parts
  and the default template's class names (§7.8, §8), accessibility and dark.

`test/support/design_system_entries.rb` gains `StudioGallery` and
`SiteGallery` in `ENTRIES`, its `VERSION` `1794862802-0737` (v253). A look this file
or the plan needs that neither card gives goes back to the design agent, never
decided here.

## 17. Order and folders

Folders were built first (owner ruling, folders spec §20, 7), on the base
branch (`media-folders-gallery`, pull request #278): `Media::Folder`,
`Media::FolderTree`, `Media::Place`, `Media::FolderCounts`, the picker's places
(`app/views/admin/media/picker.html.erb`, `FolderTreeComponent` with `mode:
:picker`, `#media-picker-place`) and `docs/reference/media.md`, "Folders". So
"Add a whole folder" is part of the build (§10.4, §10.6). Nothing else of the
block knows folders: moving an image between folders changes no gallery, and
the folders' limits (one folder per image, four levels, 1,000 folders, 200
images a move) touch nothing here.

## 18. For the owner

The gallery's own open questions. Each stands as the planner's recommendation
until the owner overrules it:

1. **Autoplay:** none in this build (§7.6). Wanted later?
2. **A lightbox:** not now (§7.7). Wanted, and in this block or as a setting?
3. **Captions with no library default** (§8): a gallery shows only its own
   captions; the card offers "Use library caption" as a start. Or should a
   gallery show a library caption where its own is blank, as the Image block
   does?
4. **AI translation of the captions** (§3.3): a follow-up, not this build.
5. **The numbers:** at most **60** images; a slide picker up to **12**; the
   **grid** the default layout; **3:2** the default shape.

The other calls, which the owner may also overrule: an image appears once in a
gallery (§3.1); a partial translation reads as translated (§3.3); no image is
eager (§7.1); the status speaks only after a button or a key (§7.3); a
carousel of one image attaches no script (§7.3); Previous and Next never wrap
(§7.5); in a right-to-left page the arrow keys follow the screen (§7.5); a
whole folder is added oldest first (§10.4); the Gallery stands after the
Image block in the picker (§14).

Ruled already, and not open: folders first, and the folders' limits (folders
spec §20).

## 19. Where the cards and this file differed

A card's word wins; on behaviour this file wins. Each conflict and its ruling:

- **`sizes` in a grid.** SiteGallery's D7 says `per_row: 3` "slightly
  over-asks in a two-column container". It under-asks there (a third of the
  width for an image drawn at half), and on a phone, where the grid is one
  column, it asks for a third of the width: the images would be blurred. §7.1's
  behaviour (the block's width divided by the images a row holds, at the
  widths the library makes) wins: `sizes(per_row:)` takes a Hash of least
  widths to counts, and a viewport-relative width takes one a row, so it may
  over-ask, never under-ask. The method keeps its name and its Integer form.
- **The button's edge at 3:1.** SiteGallery's edge `--th-line-strong` is a
  1.5:1 hairline; v245 answered: the edge is `--th-gallery-control-edge`
  (`var(--th-ink)`, a seventh token), drawn as a ring of `box-shadow` with
  `--th-shadow-menu` for depth only, and measured at 3:1 on the control.
- **The position in a right-to-left page.** SiteGallery says "the start (the
  left)"; the left is the inline end in a right-to-left page, which is where
  its preview draws it. It is the inline end in both directions, from one
  document order.
- **The tile's hint.** The design request had "3 without alt" as a meta-coloured hint;
  StudioGallery draws it as the warn badge. The card wins: the tile's closed
  set of summary parts gains `:warn`.
- **The tile's words.** The plan had `grid`, `carousel`, `images` and
  `no_alt`; StudioGallery's are `grid` and `carousel` with the count in them,
  `empty` and `without_alt` (§12).
- **The label's help key.** The first draft named `help: :gallery_label`; the card gives the
  words. The key follows the Search block's (`:"gallery.label_help"`, with
  `%{placeholder}`), which reads the card's words in English and the visitor's
  word in another editing language.
- **"Add a folder" in the card.** §10.3 names it; StudioGallery draws it only
  when the library has a folder, and says what it does only through D4's
  folder row. It opens the multiple picker with the focus on the places (not
  on the card).
- **"Add all N images in this folder".** The design request counted every
  image of the folder; StudioGallery counts only the images not yet in the gallery and offers "the
  first 12 of 31" past the limit. The card wins: §10.6's endpoint takes
  `except` and answers `total`.
- **A section's half column.** v245 set the thresholds at 360px and 640px;
  v253 (`1794862802-0737`) moved the first to 320px (one column below 320px of
  the block, two from 320px, three from 640px), because a half column is
  drawn narrower than its share of the 736px content column
  (`Blocks::SectionComponent::CONTENT_WIDTH`): 352px (less the 32px gap), and
  328px in a tinted or strong band (less its 1.5rem each side). Both draw
  two.
- **Design System v245** answered the two open questions: the button's edge
  and the grid's thresholds.

## 20. As built

Where the build left this text. Everything else stands as written; the
description of the code is `docs/reference/content-blocks-and-types.md`, "The
Gallery block".

- **The Design System is v253 (`1794862802-0737`).** After v245 it answered the
  tile (v246: the inline size-6 thumbnail, no 72px box, §10.5), the picker's
  zero status, its tile at the limit and a chosen tile's name (v249, §10.4),
  the card's screen-reader status, the field radius, the shared Remove and
  the line shown without upload rights (v251, §10.3), and the grid's first
  threshold at 320px (v253, §19).
- **`sizes(per_row:)` takes an Integer or a Hash** of least block widths to
  counts (`Blocks::GalleryComponent::GRID_COLUMNS`, `{ 0 => 1, 320 => 2, 640 =>
  3 }`); a width relative to the viewport takes the narrowest block's count, so
  it may over-ask and never under-asks (§19). A width in pixels is divided at
  the width the block is drawn at, not at the image's hint: at the top level
  `SectionComponent::CONTENT_WIDTH` (736px, not the 768px breakpoint), in a
  section column `SectionComponent.column_width` (its share of 736px less the
  32px gaps and a content-width band's 1.5rem each side, `COLUMN_GAP` and
  `BAND_PADDING`, held to `sections.css`). A half column is drawn at 352px
  (328px in a band) and draws two images a row, each asking 169px (157px).
- **The position stands at the inline end in both directions**, from one
  document order (§19).
- **The tile's words** are the card's: `grid`, `carousel` (each with the count
  in it, one and other), `empty` and `without_alt` (§12); the alt counted is the
  one a visitor is given in the language shown, the override and the library's
  interleaved per language (`Media::Asset#alt_text`).
- **The label's help** is `help: :"gallery.label_help"`, which takes the
  placeholder as the Search block's does.
- **The folder's images** answer `{ total, items }` and take `limit` and
  `except` (§10.6); the controller reads the folder through
  `Media::FolderTree.load` and `Media::Place`.
- **"Add a folder"** opens the same picker with the focus on its list of places.
  Its row hands back the chosen tiles first, then the folder's oldest new
  images; it asks again whenever the choice changes.
- **A multiple picker's uploads** join the choice in the order they finish, up
  to the limit.
- **A duplicate** is checked as an Image block's duplicate is: it needs
  `media.upload`, and a missing or trashed image in the copied list refuses the
  copy with the field's error.
- **The choosing check** is keyed `settings.images`, like every schema field's
  error, and reads before the transaction with no lock; no task writes the
  settings row.
- **Pluralisation of an ordinal** ("chosen 2nd") is `Intl.PluralRules`' ordinal
  type, asked through an `ordinal: true` option of `i18n/messages.js`.
- **The tile's closed set of summary parts gains `:warn`** (§19), and the
  tile's `summary` of an outside type may use it too.
- **The block card draws a segmented select and the select after it as one row**
  (`Admin::Fields::Base.opens_row?` and `fills_row?`), by `flex-wrap` and least
  widths.
- **The tokens are declared in `tokens.css` and resolved there**; only the
  tinted and strong bands' own values are in `sections.css`. There are seven,
  six themed and `--th-gallery-gap` fixed.
- **The carousel's script is preloaded on CS Studio pages** as the Search
  block's is: public-only controllers are preloaded by every entry point and
  imported and registered by `site` alone.
- **The panel's word for role `block_field`** is the block type's label as
  "%{type} block" ("Gallery block"), "Block" once the type is gone (not on the
  card).
- **A test's stand-in for an unregistered type is `retired_widget`**, which
  frees the name `gallery` for the built-in.
- **The showcase's three images** are uploaded through `Media::Upload` and found
  by title on a second run.
- **What the spec left to the owner stays** (§18): no autoplay, no lightbox,
  no library caption by default, no AI translation of the captions, 60 images,
  twelve dots, the grid by default and 3:2. The limits the build found are
  rows of `docs/roadmap.md`, "Known gaps", "Gallery block".
