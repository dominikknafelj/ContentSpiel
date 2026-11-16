# The Gallery block: a list of library images, as a grid or a carousel

Status: designed, not built. The behaviour is settled here; every new screen
element, the public carousel's look included, is a design request (§16), and
nothing of a look is decided in this file. An answer marked **(call)** is the
planner's recommendation, for the owner to overrule. The plan is
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
| `label` | `:string`, `max: 80`, `help: :gallery_label`, `placeholder_public: "blocks.gallery.label"` | yes | the gallery's name for a screen reader (the carousel's and the grid's accessible name), "Image gallery" in the visitor's language when blank |
| `images` | **`:media_list`** (new), `max: 60` | no | the ordered library image ids |
| `texts` | **`:media_texts`** (new), `of: :images`, `max: 1000` | yes | per image, per language: `{ "<asset id>" => { "caption" => String, "alt" => String } }` |

**The default layout is the grid (call):** it draws without a script, moves
nothing, and shows every image at once; a carousel is one press away. **The
ratio is always set (call):** "keep each image's own" was the alternative, and
it makes a ragged grid and a carousel whose height jumps from slide to slide,
the layout shift the owner ruled out; `fit` gives the uncropped look inside a
steady frame.

**An image appears once in a gallery (call).** The list is unique; adding an
image that is already there is a no-op the picker shows (D4). That lets the
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
  t.icon "images", family: :media           # a new entry of ICONS (D1)
  t.field :layout, :select, options: LAYOUTS, default: "grid", control: :segmented
  t.field :ratio, :select, options: RATIOS, default: "3:2", label: "Shape"
  t.field :fit, :boolean, label: "Show whole images"
  t.field :label, :string, translated: true, max: LABEL_LENGTH, help: :gallery_label, placeholder_public: "blocks.gallery.label"
  t.field :images, :media_list, max: MAX_IMAGES
  t.field :texts, :media_texts, translated: true, of: :images, max: TEXT_LENGTH
  t.component Blocks::GalleryComponent
  t.theme_methods :block, :page, :layout, :ratio, :fit, :label, :items, :sizes, :string
  t.tokens themed: %w[gallery-stage gallery-control gallery-control-ink gallery-pick gallery-pick-current], fixed: %w[gallery-gap]
  t.stylesheet "gallery.css"
  t.summary ->(block, locale:) { Gallery.summary(block, locale: locale) }
  t.preview ->(block, locale:) { Gallery.preview(block, locale: locale) }
  t.search_text ->(block, locale:) { Gallery.search_text(block, locale: locale) }
  t.read_only_actions …                     # the card script's reading actions, if any (§10)
  t.sample images: 3, settings: { "layout" => "carousel", "ratio" => "4:3" }, translations: { … }, shows: [ … ]
end
```

`MAX_IMAGES = 60`, `LABEL_LENGTH = 80`, `TEXT_LENGTH = 1000`, all on
`BlockTypes::Gallery`. The token names are proposals, settled by the public
look's card (D6) before the build: a token's name is a promise from the day it
ships. **No token is named `gallery-frame`**: the outside test type
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
  columns at each width is the default theme's (D7), and a theme's. Captions
  under their image.
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
section column's share) divided by how many images a row holds:
`sizes(per_row: 1)` for the carousel and `sizes(per_row: 3)` for the default
grid, a theme with another grid passing its own count. Nothing shifts: every
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
   and 60 dots is no picker. Whether the picker is dots, numbers or thumbnails
   is D6.
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
  listeners and puts `hidden` back on what it showed; at `turbo:before-cache`
  it empties the status and resets the position's words, leaving `hidden`
  alone (the Code block's copy script's two incidents). A slide it needs at
  `disconnect` is kept in a field, not read through a target.
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

## 8. The theme contract

- **The component's line** (`Theme::Contract.components`, the ledger, the
  reference's components table): `blocks/gallery_component` with `block`,
  `page`, `layout` ("grid" or "carousel"), `ratio` (the stored ratio, "3:2"),
  `fit` (true or false), `label` (the gallery's name in the language shown,
  else the visitor's word), `items`, `sizes` and `string`.
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
  images happen to carry one, is a set nobody wrote. The card can offer the
  library's caption as a starting text (D3). Owner question (§18).
- **`sizes(per_row: 1)`**: §7.1.
- **`string(key)`**: a public word in the visitor's language, English the
  fallback (`public.blocks.gallery.*`: `label` "Image gallery", `carousel`
  "carousel", `slide` "slide", `position` "%{index} of %{count}", `track`
  "Images", `previous` "Previous image", `next` "Next image", `show` "Show image
  %{index}", `moved` "Image %{index} of %{count}").
- **The tokens** (`t.tokens`, values in both blocks of `tokens.css` from base
  tokens where one is right, a strong band's in `sections.css`):
  `--th-gallery-stage` (the ground behind a fitted image), `--th-gallery-control`
  and `--th-gallery-control-ink` (a button's ground and its arrow),
  `--th-gallery-pick` and `--th-gallery-pick-current` (a picker button at rest
  and current), fixed `--th-gallery-gap`. Contrast is measured on the page, a
  tinted band and a strong band, both schemes (`design_tokens_test.rb`): a
  button's arrow on its ground at 4.5:1, a button's and a picker's edge on each
  ground at 3:1.
- **The script's markup** (`Theme::Contract::SCRIPTS["gallery-carousel"]`, the
  ledger's `SCRIPTS`, the reference's Scripts table): targets `track`, `slide`,
  `previous`, `next`, `position`, `pick`, `status`, `controls`; values
  `position` and `moved` (the two sentences with `%{index}` and `%{count}`);
  states `first`, `middle`, `last`; no parts, no answer. These are the
  template's **named parts**: a theme that replaces the template keeps them and
  the script works; the default template's class names are the default theme's
  own, not on a list.
- **The reference** (`docs/reference/theming.md`): the component's row, the
  tokens' rows, the script's row, and a section "The Gallery block" (what the
  template is handed, what it must keep: the track focusable and named, the
  slides' group role and label, the controls hidden in the markup, the caption
  printed through ERB's escaping, the picker only up to twelve).
- **A fixture theme**, `test/fixtures/themes/gallery`, whose template is
  written from that section alone (`with_gallery_theme`), drawn and driven by
  the script in a test.
- **The release note** with the ledger's lines: Added the Gallery block's
  component line, its six tokens and the `gallery-carousel` script.

## 9. Search

`t.search_text`: for each image of the list whose file is attached, its caption
and its alt override in that language, read from the copy with the fallback-aware
reader, as the Image block gives its own caption and alt. The library image's
own alt is not searched: it is the asset's, read live and in no copy
(`BlockTypes::Image.search_text`'s reason). No `SiteSearch::Documents::REVISION`
bump: no stored document holds a gallery yet. A case in
`test/models/site_search/block_text_test.rb`.

## 10. The editor (looks: D2 to D5)

- **The card** draws the fields in order. `layout`, `ratio`, `fit` and `label`
  are ordinary inputs. **The image rows are the `texts` field's input**
  (`Admin::Fields::MediaTextsField`): one row per image of the list, in its
  order, with its thumbnail, its caption and its alt override for the language
  being edited (the library image's alt in that language as the alt's
  placeholder), and on the default language's tab the controls that change the
  list: Add images, Add a folder, a drag handle and keyboard moves, Remove.
- **The list is the `images` field's input, the hidden variant**
  (`Admin::Fields::MediaListField`, `hidden?` true, as the Diagram block's
  drawing is): a hidden input holding the ids as JSON, written by the rows'
  script and dispatched as `input`, so the card's autosave sends the list and
  the texts together through `app/javascript/saving/queue.js`. A reorder is a
  change of a field, not a block move: no new write path.
- **An input learns its sibling's value**: `Admin::Ui::FieldComponent` hands
  every input the values being drawn (`values:`, the block's `FieldSet` for
  that language), so the texts input reads the list it describes (`of:`). A
  generic addition, unused by every other input.
- **On a translation tab** the list is shown read-only ("12 images",
  `MediaListField.display`) and the rows are the texts of that language, with
  the default language's caption and alt as each row's reference
  (`MediaTextsField.reference?` false: the rows draw their own), and no
  control that changes the list.
- **The rows' script**, `admin--editor--gallery`
  (`app/javascript/controllers/admin/editor/gallery_controller.js`): opens the
  picker for several images, adds what it hands back (skipping images already
  there, stopping at 60), removes, reorders by drag through `loadSortable()`
  (`app/javascript/editor/drag.js`, the one SortableJS loader) and by keyboard
  moves on the handle, and writes the hidden list. Its actions write, so none is
  in `read_only_actions`: in a form someone else holds (`HeldFields`) the rows
  are read-only. Then the count in `docs/reference/live-editing.md` stays.
- **The picker, several at once** (a change to `Admin::Ui::MediaPickerComponent`'s
  contract, whose limit "It hands back one image" goes): the opener asks with
  `detail: { opener, multiple: true, max:, chosen: [ids] }`; tiles toggle; the
  images already in the gallery are marked and not chosen again; Use adds them
  in the order they were chosen; `media-picker:picked` carries `items: [{ id,
  url, title, alt, caption }]` for a multiple opening, and the one image's keys
  as today for every other opener (the hero, the Image and Card blocks, the
  rich-text editor are untouched).
- **Add a whole folder** (needs folders): in a folder, the picker offers to add
  all of its images, in **upload order, oldest first (call)**: a batch from a
  camera goes up in shot order, and the editor reorders after; up to what the
  gallery still takes. `GET /media_folders/:id/images` answers them as the
  picker's items, kept images directly in the folder, `media.upload`.
- **The tile** (step 8): its `summary` is the layout's word and the count
  ("Carousel · 12 images"), "Empty" with none, and a hint "3 without alt" when
  images have no alt in that language (the library's or the override); its
  `preview` the label as the heading when one is written. **Its thumbnail** is
  the first image's, through the tile's generic thumbnail, which learns to take
  the first id of a `media_ids` field where a type has no `image` column. Whether
  it shows one or a strip is D5.
- **Live editing, autosave, the base, the stale check, the claim and the hold**
  are the card's and need nothing; they are tested for the type all the same.

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
  the gallery's three images (three tinted PNGs made with libvips, titled
  "Showcase image 1" to "3", so a carousel visibly steps) and draws the Gallery
  from its sample in every layout and band as every type is, plus once more as a
  grid (`settings: { "layout" => "grid" }`, as the Note's kinds are drawn from
  one sample).

## 12. Strings

- Public words: `config/locales/public.en.yml`, `public.blocks.gallery.*` (§8),
  read through `string`.
- CS Studio: the card's under `admin.components.fields.media_texts.*` and
  `media_list.*` (`config/locales/admin/fields.en.yml`), the help line
  `admin.components.fields.gallery_label` ("What a screen reader calls the
  gallery. Leave it blank for “Image gallery” in each visitor's language."),
  the tile's under `admin.components.editor_screen.tile_summary.types.gallery`,
  the picker's new words under `admin.components.ui.media_picker`. The new files
  join `CONVERTED` in `test/lib/admin_i18n_test.rb`.
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
| 8. The editor | §10: the inputs, the rows' script, the tile, the icon (D1); cases in the card, tile, held-fields and content-blocks tests; `test/system/admin/gallery_block_test.rb` |
| 9. The ledger and the reference | the component line, the six tokens and the script, with the release note; `theming.md`'s tables and section; the fixture theme |
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
- `sizes(per_row:)` handed a count other than what the theme's grid draws:
  the browser then fetches a wider or narrower width than needed.
- A change of what `search_text` gives without a bump of
  `SiteSearch::Documents::REVISION`.

## 16. Design requests

Each goes to the design agent before its part is built; the plan's second part
waits for the cards.

- **D1, the block's icon**: a new entry of `BlockTypeDefinition::ICONS` (the
  Lucide `images`, or another), on the media family's chip.
- **D2, the card's controls**: Layout (segmented), Shape, "Show whole images"
  and the label with its help line: their arrangement in the card.
- **D3, the image rows**: the row (thumbnail, caption, alt override with the
  library's alt as placeholder, the library caption offered as a start or not),
  the drag handle and the keyboard moves, Remove, a missing image's row (an id
  whose image is gone), the empty card and its first action, "Add images",
  "Add a folder", the count against 60 and the limit reached, and the rows on a
  translation tab with the default language's texts as their reference.
- **D4, the picker choosing several**: a tile's chosen look and its order, the
  images already in the gallery, the footer ("4 selected · Add 4 images"), the
  limit reached, and "Add all N images in this folder" (with folders).
- **D5, the tile**: its line, its hint for missing alt texts, and one thumbnail
  or a strip.
- **D6, the public carousel, the default theme's**: the frame, Previous and
  Next (over the image or under it, their size for a finger), the position, the
  slide picker (dots, numbers or thumbnails; up to twelve), the caption's
  place, whether the next slide peeks in, the focus rings, the stage colour with
  "Show whole images", narrow widths, a section's column, tinted and strong
  bands, dark, a right-to-left page, and the look without the script. The six
  tokens' names and values come from this card.
- **D7, the public grid, the default theme's**: columns at each width and in a
  section's column, the gap, captions, the fitted look.
- **D8, the Design System cards**: the Gallery block's card and tile in CS
  Studio, the picker's several-at-once state, and a public card for the
  carousel and the grid.

## 17. Order and folders

The block needs the folders spec (`2026-11-16-media-folders-design.md`) for
"add a whole folder" alone. **If folders land first** (recommended), the plan's
tasks run in order and the folder task is part of the build. **If the gallery
lands first**, everything but that task ships; the task waits for the folders'
`Media::FolderTree`, `Media::Place` and the picker's places, and the picker's
"Add all N images in this folder" is drawn only where the picker shows a
folder. Nothing else of the block knows folders: moving an image between
folders changes no gallery.

## 18. Only the owner can answer

1. **Autoplay**: none in this build (§7.6). Wanted later?
2. **A lightbox**: not now (§7.7). Wanted, and in this block or as a setting?
3. **Captions without a library default** (§8): right, or should a gallery
   show a library caption where its own is blank, as the Image block does?
4. **AI translation of the captions** (§3.3): a follow-up, or part of the first
   build?
5. **The numbers**: 60 images, a slide picker up to 12, the grid as the
   default layout, 3:2 as the default shape.
6. **Which first**: folders or the gallery (§17).
