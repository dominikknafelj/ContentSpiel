# The image viewer: a note's picture opened over CS Studio

Status: designed (Design System cards **ImageViewer** and **Gif**, v240,
version `1794783995-dc63`, "Decided, not built"; the design requests of §6
were answered there 2026-11-16). The look and the words are the cards'; this
file settles the behaviour the cards leave open. Each such answer is marked
**(call)**: the planner's recommendation, for the owner to overrule. The plan
is `docs/superpowers/plans/2026-11-16-image-viewer.md`.

## 1. Why

A picture in a note is drawn at most at the message's width, and a click opens
it in a new tab (`docs/reference/notes.md`, "Files": "there is no lightbox").
A screenshot in a 400px rail is unreadable, and a new tab for every look loses
the thread. Nothing in CS Studio enlarges a picture today (the card checked the
media library's detail, the picker, the image field and the rich-text image
dialog), so this is the first viewer, built shared (`Admin::Ui::`) so the media
library's detail can use it later.

## 2. Goals, non-goals

- **Goal:** a plain click on a note's picture (PNG, JPEG, GIF, WEBP) opens it
  in one dialog over the screen, fitted to the window, with its name and facts,
  stepping through the same message's pictures, with Open original and
  Download.
- **Non-goals (the card's "Can't"):** editing, cropping, annotating; zoom or
  pan; stepping across messages; a swipe on a phone; the media library's
  detail (a later step, which then renders the same component).
- **Anti-goal:** a new route or a second address for a picture. The viewer
  shows the address the thumbnail already loaded (`admin_record_note_file_path`),
  so no Active Storage URL is ever rendered (decision D15 holds) and the
  access chain of `Admin::NoteFilesController#show` stays the only read.

## 3. The parts

- `Admin::Ui::ImageViewerComponent.new`: no arguments, rendered once in
  `app/views/layouts/admin.html.erb` beside the leave dialog and the media
  picker. It draws `Admin::Ui::DialogComponent` at a new width step `viewer`
  (`min(1100px, 100vw - 32px)` wide, `100dvh - 48px` tall; under 640px the
  whole screen), with the facts in a new header slot, the stage, the arrows,
  the position, Open original, Download and a hidden warn notice.
- `admin--ui--image-viewer` on the viewer's dialog: opens, steps, closes,
  takes back.
- `Admin::Ui::GifComponent.new(src:, name:, placement: :tile | :stage)` with
  `admin--ui--gif` (moved from `admin--notes--gif`, no alias): the GIF still
  and its Play / Pause, on its own card (Gif). The owner ruled one shared
  component right: the thread's tile and the viewer's stage both draw it (one
  part for one job). `:tile` draws the picture as a link to `src` in a new tab
  and the label "GIF · %{name}" at its bottom left; `:stage` draws the picture
  bare and no label (the viewer's head names the file). Its words are
  `admin.components.ui.gif`: `play`, `pause`, `label`. Play carries the Lucide
  `play`, Pause the Lucide `pause`.
- The trigger: the existing thumbnail link, unchanged as a link
  (`target="_blank"`), marked `data-image-viewer-item` with `data-name` and
  `data-facts`; its title becomes "View %{name}".

## 4. Behaviour

### Opening

Only a plain primary click opens the viewer: `button === 0` and none of
⌘, Ctrl, Shift, Alt. Any other click, a middle click and the context menu are
the browser's. Enter on a focused thumbnail is a plain click, so the keyboard
opens it too. Without the script the link opens the picture in a new tab, as
today.

### Several images (call)

A **group is one message's pictures**, in document order, and documents (PDF,
text, Office) are never in it. The group is read from the trigger's own files
container (`[data-note-files]`, which carries `data-image-viewer-group` with
the message's id), not from the whole document: a message drawn twice on one
page (a thread in the rail and the same thread elsewhere) is never counted
twice. The group is **read once, at opening**, as a list of
`{ href, name, facts, gif }`; a live refresh that adds or removes files while
the viewer is open changes nothing in it until the next opening. The arrows
are disabled at the ends, never wrapped (the card's decision 4), and absent
with one picture.

### Keyboard and focus (call where marked)

- On opening the focus goes to **Next when it is enabled, else Previous, else
  Close** (the card says Next or Close; opening on the last picture of three
  makes Next disabled, so Previous is the call).
- ← and → step while the viewer is open, from any element in it, and only
  without a modifier: Alt+← and ⌘← are the browser's Back and are never taken
  **(call)**. Home, End and other keys do nothing new.
- When a step disables the focused arrow (Next at the last picture), the focus
  moves to the other arrow, never to `<body>` **(call)**.
- Tab order: Close, Previous, Next, Open original, Download (the phone's foot
  arrows replace the stage's: only one pair is drawn at a width).
- On close the focus goes back to **the thumbnail that opened the viewer**
  (the card's rule, confirmed by the owner), by element, which a live refresh keeps
  (`note_files_test.rb`, "a live refresh keeps a message's pictures as the
  elements they were"). If that element is gone, the focus goes to the first
  `[data-image-viewer-item]` with the same `href`, else to the thread
  (`#note-thread-<id>`) when it is still drawn, else where the browser puts it
  **(call)**. A closed `<details>` around it (a live refresh can fold the
  message into "Show N more") is opened first, or the focus would fall to
  `<body>` (`image_viewer_test.rb`, "a live refresh of the thread under an
  open viewer…"). The viewer gives it explicitly, because Safari does not
  focus a clicked link.
- A step is announced politely: "hero-phone-3.png, 3 of 3", from a visually
  hidden live region the viewer writes on a step only (the opening is the
  dialog's own name). The visible "3 of 3" is not a live region, so nothing is
  said twice.

### Escape

Escape is the native dialog's cancel and closes the viewer alone. The viewer
is rendered in the layout, outside every rail panel, slide-over and sheet, so
the notes drawer's `keydown.esc` (on its panel) and the media rail's
`#escape` (on the rail) never see the key, and the notes slide-over or sheet
under the viewer stays open with its thread **(call: one Escape, one layer)**.
Close and a press on the backdrop close it too (the Dialog's rules). A press on
the stage outside the picture does not close it **(call)**: on a phone the
stage is the whole screen, and a missed tap must not lose the place.

### A GIF's play and pause

Without reduced motion a GIF plays in the viewer as in the thread. With it,
the viewer shows the still (its first frame on the canvas) under Play, as the
thread does, and Play reads Pause while it moves. **Each opening and each step
starts a GIF still** **(call)**: the thread tile's state is not carried into
the viewer and the viewer's is not carried back. Pause sits bottom-right while
playing, as in the thread.

### Reduced motion

The viewer has no transition of its own: no fade or slide between pictures,
under any setting **(call: the card asks for none under reduced motion and
draws none otherwise)**. A step swaps the picture at once. The only motion it
holds is the Button press it draws (`motion: :reduced`) and a GIF, held still
as above.

### What a person without access sees

- A person who may not read the record never has a thumbnail: the thread is
  not drawn for them, so there is nothing to open. The viewer's markup in the
  layout is empty and holds nothing of anyone's notes.
- A person who loses the right, or whose file was deleted, while the page is
  open: the picture's request is answered 404 by the same lookup chain, and
  the stage shows the warn notice "This image couldn't be shown here. Open the
  original, or download it." with Open original and Download still offered
  (they lead to the same 404, in a tab or as a failed download). The name and
  facts stay those read at opening. No 304 is ever given to such a person: the
  notes action answers the 304 only at the end of its lookup.
- A picture whose bytes the browser cannot draw (a corrupt file under an
  allowed type) shows the same notice.

### Loading

The previous picture is taken off the stage the moment a step starts, so a
slow picture never stands under the next one's name; the stage is the plain
sunken ground. If the new picture has not loaded (nor failed) **400 ms** after
the step or the opening, the shared spinner (`.admin-spinner`, `aria-hidden`)
shows centred with "Loading…" under it (13px `cs-meta`), in a `role="status"`
box; it goes the moment the picture loads or fails, at the next step and at
the take-back. Nothing shows before 400 ms, so a cached picture never
flickers. Under reduced motion the spinner turns at its slow rate (the
spinner's own rule).

### The ground behind a picture

The stage stays `cs-sunken`. The picture stands at its own size, centred and
never enlarged, on a light checkerboard drawn behind **the picture's own box
only**: 8px squares of `#ffffff` and `#e7e9ef`, the same in both schemes, so
a transparent picture (a dark logo) always shows and an opaque one covers it.
No placeholder gradient.

### Turbo's cache and take-back

At `turbo:before-cache` and at `disconnect` the viewer closes its dialog,
removes the picture's `src`, empties the title, facts, position and live
region, hides the notice, drops the group and the opener, and the GIF part
clears its canvas and is no longer playing. A Back visit therefore never shows
an open or a stale viewer. The links keep `data-turbo="false"`, so Turbo never
prefetches a picture on hover.

### The phone layout

Under 640px (a viewport query, since a modal dialog is sized by the viewport)
the dialog is the whole screen (`100vw` by `100dvh`, no radius, no shadow),
the stage comes first, and the foot is two rows: ← "2 of 3" → as small
secondary buttons (the icon alone, named by their keys), then Open original
and Download. The stage's round arrows are not drawn at that width. No swipe
(the card's decision 5).

The head is two lines: the name (15px, weight 600) on its own line, truncated
with an ellipsis; the facts (12px `cs-meta`) under it, never dropped; Close at
the right of both. The full name stays the dialog's accessible name.

The safe areas: the head's `padding-top: max(12px, env(safe-area-inset-top))`,
the foot's `padding-bottom: max(12px, env(safe-area-inset-bottom))`, and the
head, the stage and the foot `padding-inline: max(16px,
env(safe-area-inset-left))` on the left and the same with `-right` on the
right; the stage's ground runs edge to edge under them.

### The theme fade and the layers

The viewer uses tokens only, sets no `view-transition-name` and no
transition, so a theme change while it is open fades with the rest of the
document (the root's view transition draws the top layer too). It is a native
modal and so stands in the top layer with no `z-index`; the stage's arrows
come after the picture in the markup and need none. Should one be needed it is
`--cs-z-raised` inside the stage's own `isolate`, never a raw value
(`test/lib/admin_design_rules_test.rb`).

## 5. Words

The card's, under `admin.components.ui.image_viewer`: `previous`, `next`,
`position` ("%{index} of %{count}"), `open_original`, `download`, `failed`,
`loading` ("Loading…"); plus **`stepped` "%{name}, %{position}"** **(call)**,
the live region's sentence. `admin.components.ui.gif`: `play`, `pause` and
`label` ("GIF · %{name}"), moved from `notes_screen.files` (`play`, `pause`,
`gif`). `admin.components.notes_screen.files.view` "View
%{name}" replaces `open`. Close is the Dialog's.

## 6. The design's answers

The design requests this spec raised were answered on the cards (ImageViewer,
"Settled 2026-11-16"; Gif), version `1794783995-dc63`, and are written into
§3 and §4 above:

1. **Loading:** the spinner and "Loading…" after 400 ms (§4, "Loading"), new
   key `admin.components.ui.image_viewer.loading`.
2. **Icons:** the Lucide `arrow-left`, `arrow-right` and `arrow-up-right`
   through `admin/shared/_icon` (`arrow_right` and `arrow_up_right` join it;
   `arrow_left` is there), 18px on the round stage buttons, 16px in the foot.
3. **A disabled round arrow** keeps its 40px circle and its place:
   `cs-sunken` ground, the arrow in `cs-meta`, a 1px `cs-line` edge, no
   shadow, `cursor: not-allowed`, and the real `disabled` attribute.
4. **A long name on a phone:** the two-line head (§4, "The phone layout").
5. **The GIF part:** `Admin::Ui::GifComponent` on its own card, Gif (§3).
6. **The safe areas:** §4, "The phone layout".
7. **The ground behind a picture:** the checkerboard behind the picture's own
   box (§4, "The ground behind a picture").

Where the ImageViewer card says the visible position is the polite live
region, this spec's behaviour holds: the announcement is a visually hidden
region written on a step only, so nothing is said twice (§4, "Keyboard and
focus").

## 7. Permissions, audit, live editing

No new permission, route, audit event or write. Opening a picture is a read
of the notes action, as the thumbnail's own load is. Live refresh is untouched;
the viewer only reads the thumbnails it finds.

## 8. The guide and the release

`CHANGELOG.md`, "Unreleased": Added, the image viewer; Changed, a note's
picture opens in the viewer and ⌘-click or Open original opens a tab. The
editors' guide page on notes changes its line on pictures (a docs PR,
"Documentation" in the pull request). No migration, no new top-level name.
