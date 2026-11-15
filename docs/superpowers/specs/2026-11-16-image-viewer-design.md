# The image viewer: a note's picture opened over CS Studio

Status: designed (Design System card **ImageViewer**, added at v237, "Decided,
not built", 2026-11-15). The look and the words are the card's; this file
settles the behaviour the card leaves open. Each such answer is marked
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
- `Admin::Ui::GifComponent` **(call)** with `admin--ui--gif` (moved from
  `admin--notes--gif`): the GIF still and its Play / Pause. The card moves the
  behaviour and its words to `admin.components.ui.gif`; under the component
  contract a key scope under `admin.components.ui` is a component's, so the
  still, the canvas and the button become one shared component that the
  thread's tile and the viewer's stage both draw (one part for one job).
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
  (the card's rule), by element, which a live refresh keeps
  (`note_files_test.rb`, "a live refresh keeps a message's pictures as the
  elements they were"). If that element is gone, the focus goes to the first
  `[data-image-viewer-item]` with the same `href`, else to the thread
  (`#note-thread-<id>`) when it is still drawn, else where the browser puts it
  **(call)**. The viewer gives it explicitly, because Safari does not focus a
  clicked link.
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
slow picture never stands under the next one's name; the stage is the sunken
ground until it loads (its look is a design request, §6).

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
secondary buttons, then Open original and Download. The stage's round arrows
are not drawn at that width. No swipe (the card's decision 5).

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
`position` ("%{index} of %{count}"), `open_original`, `download`, `failed`;
plus **`stepped` "%{name}, %{position}"** **(call)**, the live region's
sentence. `admin.components.ui.gif`: `play`, `pause` (moved from
`notes_screen.files`). `admin.components.notes_screen.files.view` "View
%{name}" replaces `open`. Close is the Dialog's.

## 6. Design requests

What the card does not show, for the design agent; nothing here is designed
by the build, which draws the plain fallback named in brackets.

1. **Loading:** a slow picture's stage (a busy mark, after how long) [the
   sunken stage, nothing on it].
2. **The arrows' and Open original's icons:** the card draws the glyphs ←, →
   and ↗; whether they are the Lucide `arrow-left`, `arrow-right` and
   `arrow-up-right` of the icon set [the Lucide icons; `arrow_right` and
   `arrow_up_right` join `admin/shared/_icon`].
3. **A disabled round arrow** on the stage: the card draws only the enabled
   look [the Button's disabled tokens on the round frame].
4. **A long name on a phone** in the head beside the facts: whether the facts
   wrap under the name or are dropped [the name truncates, the facts keep
   their width].
5. **The GIF part's card:** `Admin::Ui::GifComponent` needs naming in a card's
   Code section (ImageViewer's or StudioNotesThread's) [listed in
   `DesignSystemEntries::NOT_YET` with that reason].
6. **The phone's safe areas** (the notch and the home bar) in a full-screen
   viewer [`env(safe-area-inset-*)` padding on the head and the foot].
7. **A picture smaller than the stage** on the sunken ground: whether it gets
   the thread's placeholder gradient behind a transparent picture [no
   gradient, the sunken ground].

## 7. Permissions, audit, live editing

No new permission, route, audit event or write. Opening a picture is a read
of the notes action, as the thumbnail's own load is. Live refresh is untouched;
the viewer only reads the thumbnails it finds.

## 8. The guide and the release

`CHANGELOG.md`, "Unreleased": Added, the image viewer; Changed, a note's
picture opens in the viewer and ⌘-click or Open original opens a tab. The
editors' guide page on notes changes its line on pictures (a docs PR,
"Documentation" in the pull request). No migration, no new top-level name.
