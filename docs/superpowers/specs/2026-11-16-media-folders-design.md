# Media folders: organising the library

Status: designed, not built. The behaviour is settled here; every new screen
element is a design request (§17) for the design agent, and nothing of its look
is decided in this file. An answer marked **(call)** is the planner's
recommendation, for the owner to overrule. The plan is
`docs/superpowers/plans/2026-11-16-media-folders.md`. The Gallery block
(`2026-11-16-gallery-block-design.md`) uses folders for one thing, "add a whole
folder" (§18).

## 1. Why

The owner (2026-11-16): "As for the media gallery: it should allow to organise
media." Folders were asked for on 2026-11-14 too, and the roadmap's Media
library list holds "Folders and tags for organising assets", with the question
to decide first: the need behind them. Today the library is one flat grid of
every kept image, newest first, 48 a page, narrowed by a search (title, alt in
any language, file name) and five segments (`docs/reference/media.md`, "CS
Studio's Media module"). A site with a few hundred images has no place to put
"Client A", "Team photos" or "Event 2026", no way to move a set at once, and the
picker opens on the whole library every time.

The roadmap's own weighing: finding images is served better by tags or
collections (an image in several), while folders win for places people think
in, for permissions per folder and for moving or deleting a set at once. The
owner's word is "organise", which is the second: places. So this is folders,
one per image, and tags for images stay a later, separate step (§3.1).

## 2. Goals, non-goals, anti-goals

**Goals.**
- An editor puts images into named folders, nested up to four levels, and finds
  them there: on the Media screen and in the picker.
- Moving one image, a selection of images, or a folder (with everything in it),
  by drag and by a menu, with the keyboard.
- Uploads land in the folder that is open.
- Every existing image starts outside any folder; nothing else about it changes.
- The audit log, the trash, the live refresh of other tabs and the MCP tools
  know folders.

**Non-goals.**
- Tags or collections for images (an image in several sets): a later step (§3.1).
- Permissions per folder: a named seam, not built (§13).
- Folders for anything but library images (notes' files, the logo).
- A hand order of images inside a folder (§3.4). A gallery has its own order
  (the Gallery block).
- Trashing many images at once from a selection (§5.3, a later step).
- Uploads through MCP (MCP stays read-only over the library).

**Anti-goals** (a failure even if it technically works).
- A folder that changes anything a visitor sees: a folder is an editors' tool;
  it never reaches a public page, an address, an image's widths or the content
  version.
- A move that interrupts someone typing in the image's panel in another tab
  (a 409 under their alt text).
- An image that silently vanishes from every view because its folder went: an
  image is always in a folder that exists or in "Not in a folder".
- A second way to write an image's folder beside the one service (§5).

## 3. The model

### 3.1 One folder per image (call)

`media_assets.folder_id`, nullable: an image is in at most one folder. A folder
is a place, and a place holds a thing once; moving is then one value, deleting
a folder has one answer for its images, and the picker's "where you last were"
is one place. The many-to-many need ("this image is a team photo AND a 2026
photo") is what tags answer, and **library images have no tags today**: the
tags that exist are posts' (`tags`, `post_tags`). The owner's note "tags
already do many-to-many" holds for posts only; tags for images would be a
table `media_asset_tags` on the existing `Tag`, a later step on the roadmap's
row, and nothing here blocks it (§20, question 1).

### 3.2 The table

`media_folders` (`Media::Folder`, `app/models/media/folder.rb`,
`self.table_name = "media_folders"` as `Media::Asset`'s is):

| Column | |
|---|---|
| `name` | string, not null: what the editor typed, outer white space taken off, 1 to 80 characters |
| `parent_id` | bigint, FK to `media_folders`, NO ACTION, nullable (nil: at the top) |
| `created_by_id` | bigint, FK to `users`, `on_delete: :nullify` |
| `created_at`, `updated_at` | |

- A unique index on `(parent_id, lower(name))` with `nulls_not_distinct: true`
  (the shape `media_usages`' index already uses): two folders of one parent
  never share a name whatever its case, and two at the top collide too.
- `media_assets.folder_id`: bigint, FK to `media_folders` `on_delete: :nullify`,
  indexed. The services always move an image before its folder goes (§6.4);
  the nullify is the floor under a console delete, so an image is never left
  pointing at nothing. (This FK points *from* an image; the rule that foreign
  keys *to* library images stay NO ACTION is untouched.)

Names are **not translated (call)**: a folder is an editors' tool, never shown
to a visitor, and an editor reads CS Studio in one language. A plain string
column, no Mobility.

### 3.3 Nesting and its depth (call)

Folders nest, **at most four levels** (`Media::Folder::MAX_DEPTH = 4`; a folder
at the top is level 1): "Clients / Client A / 2026 / Launch" is the deepest
place. Deeper trees are where file managers lose people; four covers a client,
a project, a year and an event. **At most 1,000 folders** on a site
(`Media::Folder::MAX_FOLDERS`), which keeps the whole tree one query and one
small value in memory (`Media::FolderTree`, §3.5), drawn whole like the Pages
tree.

The tree is `parent_id` alone, **not closure_tree (call)**: pages need the
closure table for branch grants and paths; a tree capped at 1,000 rows and four
levels is read whole in one query and walked in Ruby, which also gives the
natural order (§3.4) that SQL would need an ICU collation for.

### 3.4 Order (call)

- **Folders** are listed by name, case-insensitively and with numbers read as
  numbers ("Event 2" before "Event 10"), at every level, in the order the
  tree's value sorts them (`Media::FolderTree`). No hand order: a folder is
  found by its name, as in every file manager, and a position column would be
  one more thing to keep right on every move.
- **Images in a folder** keep the library's order, newest first, as All media
  does. No hand order: the library is a store, and an order that matters to a
  visitor is a gallery's.

### 3.5 Reading the tree

`Media::FolderTree` (`app/values/media/folder_tree.rb`) is built from one query
(`Media::Folder.pluck(:id, :parent_id, :name)`) and answers `roots`,
`children(id)`, `path(id)` (the folders from the top to it), `depth(id)`,
`height(id)` (levels under it, itself included), `descendant_ids(id)`,
`ancestor?(a, of: b)` and `find(id)`. The Media screen, the picker, the move
dialog, the services' checks and MCP all read it; nothing walks the table
recursively in SQL.

## 4. The places

The library has three kinds of place, chosen by one parameter, `folder`, which
every link of the Media screen keeps beside `q`, `filter` and `page`:

| Place | `folder=` | Lists |
|---|---|---|
| **All media** | absent or `all` | every kept image, wherever it is: today's grid, unchanged |
| **Not in a folder** | `none` | kept images with no folder |
| **A folder** | its id | kept images directly in that folder; its subfolders are folders to open, not images listed here |

`Media::Place` (`app/values/media/place.rb`) is the parsed value:
`Media::Place.parse(raw, tree:) -> Media::Place | nil` (`ALL`, `NONE`, or a
folder of the tree; nil for an id that names no folder or anything that is not
a String). On the Media screen an unknown folder is the 404 with "Back to
Media", as a stale `selected=` is today ("not found, not forbidden"); in the
picker it is All media (§8), because a remembered place may have gone.

**Search and segments narrow the place (call).** The place is one set; the
search and the segment narrow it, and the segment counts are the place's
(`Media::Search#counts`, unchanged in shape, its scope the place's). "Search
across folders" is All media: a search typed in a folder narrows that folder,
and the screen offers to run the same search in All media in one press (D11).
Why not search below the folder too: then the counts, the grid and the
segment would describe different sets depending on whether a word is typed.
Why not always the whole library: a person who opened "Client A" and typed
"logo" means Client A's logo. In All media every tile can say which folder it is
in (D11).

**Counts.** `Media::FolderCounts` (`app/queries/media/folder_counts.rb`)
answers `{ all: Integer, none: Integer, folders: { id => Integer } }` from one
grouped query over **kept** images (`Media::Asset.kept.group(:folder_id).count`):
a folder's count is its direct images. A trashed image is in no count, as in the
segments' (`test/integration/trash_visibility_test.rb`, §16).

`?selected=ID` (every link that opens an image: notes, the audit log, ⌘K, the
dashboard, Translations, Undo) keeps working as it is: without `folder` the
grid is All media, as today, and the panel opens beside it.

## 5. Moving images

### 5.1 One write path

`Media::MoveImages.call(asset_ids:, folder:)` (`app/services/media/move_images.rb`,
`folder` a `Media::Folder` or nil for "Not in a folder") is the one writer of
`media_assets.folder_id` after an upload (`Media::Upload` sets it once, §7).
`Media::Save` (the panel's autosave) does not take a folder; the panel moves
through this service like the grid does (D9).

- **Rights:** each image's edit right, as `Media::Save` judges it
  (`Media::Ownership`: `media.manage`, or the image's own uploader holding
  `media.upload`). **All or nothing (call):** if any chosen image is one the
  actor may not move, nothing moves and the answer says how many could not be
  moved ("2 of these images are not yours to move."). A partial move is a
  result a person must then read image by image to understand.
- **At most 200 images a move** (`Media::MoveImages::MAX = 200`); more is a
  refusal before anything is read. The grid shows 48 a page; "select all" (D6)
  selects what is drawn.
- **Kept images only.** A trashed id is the "doesn't exist" failure, as in
  `Media::Choosing`.
- **The target folder is locked `FOR SHARE`** for the transaction, so a delete
  of it waits for the move or the move sees it gone and fails with "That folder
  is gone." (the delete takes the tree's lock, §6.1, and then the folder's row).
- **It does not touch `updated_at` (call).** The write is one `update_all(folder_id:)`
  marked `# version: none (a folder is never drawn on the site)`
  (`test/lib/version_bump_test.rb`). The panel's autosave base is the image's
  `updated_at`; a move that moved it would refuse the alt text someone is
  typing in another tab with a 409, the incident the blob-analysis comment in
  `docs/reference/media.md` records. A move is no edit of the image's text.
- **Audit:** one `media.moved` per image, subject the image,
  `field_changes: { "folder_id" => [old, new] }`, `metadata: { "folder_name" }`
  (the target's name at the time, or nil), never coalesced. `media.moved` joins
  `Audit::Sentence::COUNTED`, so the dashboard reads "moved 12 images to
  “Client A”" (§10).
- **Nothing public moves**: no content version bump, no usage row, no address.

### 5.2 Three ways to ask for it (the looks are D6 to D9)

- **A menu**: "Move to…" on the image's panel and on a selection, opening the
  move dialog (D7), a chooser of the tree plus "Not in a folder".
- **Many at once**: a selection mode on the grid (D6) and "Move N images to…".
- **Drag**: a tile, or the selection, dropped on a folder (or on "Not in a
  folder") in the folder tree (D8). Drag is the mouse's shortcut, never the
  only way: every drag has the menu's equivalent, and a coarse pointer gets the
  menu alone. The existing window-wide file drop (`admin--media--drop`) already
  leaves a drag that began inside the page alone, so dragging a tile never
  shows the upload overlay.

Every move is sent through `app/javascript/saving/queue.js`, as every write of
a CS Studio screen is (CLAUDE.md, "Rules a change can break silently").

### 5.3 Not in this step

Moving to the trash from a selection, and downloading a selection. Named so
the selection mode (D6) leaves room for them.

## 6. Folders: create, rename, move, delete

`Media::SaveFolder.call(folder_or_nil, attributes: { name:, parent_id: })`
creates (nil) or changes one folder; `Media::DeleteFolder.call(folder)`
deletes one. Both need **`media.manage` (call)**: shaping the library is
managing it, and `media.manage` is what Admin and Editor already hold; a person
with `media.upload` alone (an author) uploads into folders and moves their own
images (§5.1) but does not reshape the tree.

### 6.1 The tree's lock

Every write to the tree (create, rename, move, delete) takes
`LOCK TABLE media_folders IN SHARE ROW EXCLUSIVE MODE` first (`# sql:` Arel
has no node for it), so two moves that would make a cycle together (A into B
while B goes into A), or two creates of one name, are decided one after the
other against the tree as it then is. Folder writes are rare; the lock costs
nothing anyone waits for.

### 6.2 Names

Outer white space taken off; 1 to 80 characters; no control characters
(`\p{Cc}`, the rule `:link` uses). A sibling of the same name, in any case, is
refused on the name field: "A folder named “Client A” is already here." The
unique index is the floor; its `ActiveRecord::RecordNotUnique` is rescued into
that same failure.

### 6.3 Moving a folder

A folder moves with everything in it. Refused, nothing written: into itself or
a folder under it ("A folder can't go inside itself."); to a place where it or
the deepest folder under it would be deeper than four levels ("That would nest
folders more than 4 levels deep."); next to a sibling of its name. Audited as
`media_folder.moved`, `field_changes: { "parent_id" => [old, new] }`.

### 6.4 Deleting a folder (call: its contents move up)

Deleting a folder moves its images **and** its subfolders one level up, into
its parent, or out of every folder and to the top when it had none; then the
row goes. Never refused for what it holds: refusing a folder with 300 images
makes a person move them all by hand first, and moving up loses nothing. The
confirm dialog says what moves where (D4: "Its 34 images and 2 folders move to
“Clients”.").

- **The order inside the transaction**: the tree's lock (§6.1), then the
  folder's own row `FOR UPDATE`, then the images, the subfolders and the row.
  A move or an upload into the folder holds the row `FOR SHARE` (§5.1, §7), so
  one waits for the other: a move that commits first has its images moved up
  with the rest, and one that comes after finds the folder gone. Without the
  row lock first, images moved in between the delete's update and its delete
  would fall to "Not in a folder" by the FK's nullify instead of the parent.
- **Trashed images move too**: the update is over every image with the folder's
  id, kept or trashed, so a trashed image restored later comes back to the
  parent, never to "Not in a folder" by the FK's nullify (§9).
- **A subfolder whose name is taken in the parent** takes the first free
  suffix, " 2", " 3", …, the way a restored page's slug takes `-2`. The confirm
  dialog names the renames before the press.
- **One event**, `media_folder.deleted`, on the folder, recorded before the row
  goes (an invitation's withdrawal does the same), `metadata: { "parent_id",
  "moved_image_count", "moved_image_ids", "moved_folder_ids" }`, the image ids
  only for 200 or fewer (the form submissions' delete keeps its ids the same
  way, for 50); no `media.moved` per image (a delete of a folder of 1,000 images
  is not 1,000 rows of the log), and `media_folder.renamed` for each suffixed
  subfolder.
- **No Undo (call).** The trash's Undo restores a record; a folder delete is
  undone by creating the folder again and moving its images back, and the
  event names which they were. A folder in the trash would be a fifth
  trashable kind for a container that is empty by the time it goes; not worth
  it.

### 6.5 Renaming

`media_folder.renamed`, `field_changes: { "name" => [old, new] }`, never
coalesced (each rename is one press, not an autosave).

## 7. The upload target

An upload made while a folder is the place lands in that folder; one made in
All media or Not in a folder lands in no folder. `Media::Upload.call(file:,
folder: nil)`; uploading into a folder needs `media.upload` alone (the folder
is where it goes, not a right). The progress tile goes into the grid as today,
and the folder's count moves with the answer (`Admin::MediaUploadResponses`
answers the folder counts beside the segment counts). The picker's Upload does
the same in the picker's place (§8). The folder named by an upload is read
through the tree and locked `FOR SHARE` like a move's target; a folder deleted
meanwhile is the refusal "That folder is gone." on the file's tile, nothing
stored. `media.uploaded`'s metadata gains `folder_id`.

## 8. The picker

- **It browses folders inside its dialog** (D12): the same three kinds of place,
  the same `folder` parameter on `GET /media?picker=1`, kept by its toolbar's
  form and its page links as `q` and `filter` are.
- **It opens where you last were (call: per browser).** The picker's script
  remembers the last place it showed in `localStorage`
  (`cs.media.picker.place`, a String: `all`, `none` or an id), read and written
  inside `try`/`catch`, and opens its frame at that place; nothing stored, or
  storage refused, is All media. A remembered folder that has gone answers All
  media (§4) and the script forgets it. Per browser, not per person: a server
  column for a convenience is a migration and a write per press; the owner may
  want it per person (§20, question 3).
- Choosing stays one image; several at once is the Gallery block's change to
  the picker.

## 9. Folders and the Trash

- Folders are **not trashable**: a delete is immediate (§6.4), and what it held
  moved up first.
- A trashed image **keeps its folder**; it is in no count and no listing of a
  place, as it is in no segment. Restored, it is back in its folder, or in that
  folder's parent if the folder was deleted meanwhile (§6.4).
- The Trash screen does not show folders; its images tab is unchanged.
- Purging an image needs nothing of folders.

## 10. The audit log

| Action | Subject | Sentence (Audit::Sentence) |
|---|---|---|
| `media_folder.created` | the folder | created the folder “Client A” |
| `media_folder.renamed` | the folder | renamed the folder “Client A” to “Client B” |
| `media_folder.moved` | the folder | moved the folder “Client A” into “Clients” / to the top |
| `media_folder.deleted` | the folder | deleted the folder “Client A” |
| `media.moved` | the image | moved “sunset.jpg” to “Client A” / out of every folder; counted: moved 12 images to “Client A” |

- A folder's label is its name (`Audit::Snapshot.label_for`), its snapshot
  `name` and `parent_id`. Its route is the Media screen at that folder
  (`Audit::Sentence::Route.new(:admin_media_path, [], { folder: id })`); a
  deleted folder's sentence has no link.
- The log's Type filter lists "Media folder".
- Every new action joins `Editing::Signals::SILENT` ("library images and
  folders have no live editor"), since `Editing::Signals.heard` raises for an
  action neither `MAP` nor `SILENT` knows.
- `media.moved` is a change (it is not in `Dashboard::Feed::NOT_A_CHANGE`).

## 11. Live updates for other open tabs

A tab with the Media screen or the picker open learns that the library's shape
changed, through `Live::Signals` (the one sender), on a library-wide stream:

- `Media::LibrarySignals` (`app/models/media/library_signals.rb`) says
  `Live::Signals.later("media:library", { kind: "library", reason:, origin: })`
  with `reason` one of `folders` (any tree write, a delete included) and
  `moved` (images moved). An upload sends nothing: uploads are not live today
  and stay so. `origin`
  is the acting tab's id, so it does not fetch what its own answer drew. Ids
  are allowed by the signal's rules but none is sent: a tab fetches its place
  again, it does not need to know which folder.
- `Media::LibraryChannel` (`app/channels/media/library_channel.rb`) streams
  `media:library` to a subscriber who holds the media kind's read right at
  subscribe time (`RecordKinds.named("media")`: `media.upload`), and rejects
  everyone else alike; `subscribed` is private, as every channel's is.
  **Folders are not a record kind (call)**: no note or presence attaches to a
  folder, and the library-wide stream is open exactly to whoever may open the
  library, which is what an unscoped kind already means.
- What a listening tab does (D13): the folder tree and the counts are fetched
  again through the same `media.upload`-gated GET the screen loads them with
  and replaced, keeping the open branches and the focus; **the grid is not
  replaced under the person**: if the shown place changed, a quiet notice
  offers to show the changes. At most one fetch per two seconds. The picker,
  while open, does the same for its folder list; closed, it loads afresh when
  opened.
- No Turbo page refresh or morph (the guard in `test/lib/notes_guards_test.rb`
  holds); a plain fetch and a replace of the tree's part.

## 12. MCP

- `list_media_tool` gains `folder` (an integer id, or the string `"none"`);
  absent is every folder, as today. An id that names no folder is the tool's
  error "No such folder" (not an empty list, which would read as an empty
  folder). Each entry gains `folder`: `{ id, name, path }` (`path` the names
  from the top joined with " / ") or null.
- `get_media_tool` gains the same `folder`.
- **A new read-only `list_media_folders_tool` (call):** every folder as
  `{ id, name, parent_id, path, image_count }`, in the tree's order, so an agent
  can learn an id to pass to `list_media_tool`. Without it the only way to a
  folder id is an image already in it. `media.upload`, as the other two.
- MCP writes nothing to folders: the library stays read-only there.

## 13. Permissions

No folder is access-controlled in this step: whoever opens the library
(`media.upload`) sees every folder and every image, as today. **The later seam
(named, not built):** a grant scope key `media_folder_ids` (as `page_ids` is for
pages), matched against a folder and the folders under it, which turns the
`media` record kind into a scoped one: `RecordKinds.register "media", scoped:
true`, the library's lists, the picker, ⌘K, MCP and the library stream then
narrowing through `AccessControl.scope`, and "Not in a folder" becoming a place
a scope grants or not. Nothing in this step forecloses it: every list of images
already goes through `Media::Search` or a named scope, and the place is one
value (`Media::Place`) a scope can narrow.

## 14. The migration

`db/migrate/20261116130000_create_media_folders.rb`: the table, its indexes,
`media_assets.folder_id` with its FK and index. **Every existing image starts
in no folder** (the column's nil), so nothing about any image changes and no
data is written. `CHANGELOG.md`, `### Migrations`. Reversible (`down` drops the
column and the table).

## 15. What outside the library depends on its shape (checked)

| Dependent | What it relies on | After folders |
|---|---|---|
| `/media?selected=ID` links: notes inbox (`Admin::NotePathsHelper`), the audit log (`Audit::Sentence` routes), ⌘K (`Jump::Search#media_rows`), the dashboard (`WaitingRowComponent`, `TranslationPanelComponent`), Translations (`MatrixComponent`), Trash's Undo | the panel opens from `selected` | unchanged: no `folder` is All media |
| `Admin::Ui::MediaPickerComponent` and its openers (`Admin::Columns::MediaColumnComponent` for the hero, the Image and Card blocks; the rich-text editor's Image button) | `GET /media?picker=1` lists kept images; `media-picker:picked` hands back one `{ id, url, title, alt, caption }` | the listing gains places (§8); the event is unchanged |
| `Media::Search` (Media screen, `list_media_tool`, ⌘K) | `Media::Search.call(scope, query)` | unchanged; the place is a separate narrowing |
| `Admin::MediaUploadResponses` (the screen's and the picker's uploads) | `counts` in the answer | gains `folder_counts` |
| `Admin::MediaAssetsController` (the picker's upload endpoint) | `Media::Upload.call(file:)` | takes the picker's place |
| `list_media_tool`, `get_media_tool` | their answer's keys | each gains `folder` (additive) |
| `test/integration/trash_visibility_test.rb` | every list over images hides the trash | gains the place listings, the counts and `list_media_folders_tool` |
| `test/lib/component_screens_test.rb` | which screen each component draws | the new components are the Media screen's (`Admin::MediaLibrary::`) |
| `Editing::Signals` (`MAP` + `SILENT` cover every action) | | the five new actions join `SILENT` |
| `Audit::Sentence::ACTIONS`, the log's Type filter | | the new actions and "Media folder" |
| `Admin::Shell::TreeSubjects` | "pages" and "mind_graph" | a third subject only if D1 puts the folders in the shell's tree column |
| the Media screen's view comment ("No tree column: a library image has no tree position of its own") | | rewritten by D1's answer |

Nothing public depends on the library's shape: the public site reads images by
id and by their recorded widths, never by where an editor keeps them. Rich text
names images by id (`::image{asset="42"}`), so moving an image changes no body.

## 16. Guards and tests

New rules, each with its test:
- A folder never reaches the site: `Media::MoveImages`' and `Media::DeleteFolder`'s
  writes on `media_assets` carry `# version: none` (`test/lib/version_bump_test.rb`),
  and no public template or component names `folder` (a case in
  `test/integration/public_blocks_test.rb`: "an image's folder changes nothing a
  visitor is served", a page's body and ETag equal before and after a move).
- The one writer of `folder_id` after an upload is `Media::MoveImages` (and
  `Media::DeleteFolder`'s move up): `test/lib/media_folder_writers_test.rb`, a
  grep of `app/` and `lib/` for `folder_id:` writes outside the two services,
  `Media::Upload` and the migration.
- Every place listing, the counts and the MCP folder tool hide trashed images
  (`test/integration/trash_visibility_test.rb`: "a trashed image is in no
  folder's listing or count, and comes back to its folder").
- The services' rights are behaviour-tested (`test/services/service_behaviour_contract_test.rb`,
  `EXPECTED_SERVICES` and `test/support/service_calls.rb`).

What no test holds goes to `CLAUDE.md`'s "Rules a change can break silently"
(the plan's last task writes it): **no guard** for a new list of images that
forgets the place parameter when it should keep it (a link that drops `folder`
sends a person back to All media); **no guard** that a new image-writing path
(a future MCP upload) sets the folder through `Media::Upload`.

## 17. Design requests

Every element below goes to the design agent before it is built. The plan's
second part waits for the cards; where a card and the spec differ on a word,
the card wins; on behaviour, the spec does.

- **D1, where the folders stand on the Media screen.** The shell's tree column
  (a third `Admin::Shell::TreeSubjects` subject beside "pages" and
  "mind_graph", its fold and words, the StudioTree row with a folder mark), or
  a column of the Media screen's own beside the grid and the rail; how the three
  of them share the width at 1024, 1200 and 1440px, and below 760px of the
  library. Includes the rows "All media" and "Not in a folder", the counts, the
  selected place, folding, the empty tree.
- **D2, creating a folder**: the control, where the new folder's name is typed
  (in place in the tree or a dialog), its errors (taken name, too long, depth).
- **D3, renaming a folder**: the control and its errors.
- **D4, deleting a folder**: the confirm dialog's words, naming what moves where
  and any subfolder that will be renamed.
- **D5, moving a folder**: drag on the tree (drop on a folder, the "top"
  target, refusal looks for a cycle or the depth) and the keyboard's way (a
  "Move to…" on the folder, D7).
- **D6, selecting several images on the grid**: the selection mode and how it
  is entered and left, a tile's selected look (the grid's tiles are links; the
  picker's are pressed buttons), "N selected", select all drawn, clear, the
  actions bar ("Move to…"), and the room left for later actions (§5.3).
- **D7, the "Move to…" dialog**: a chooser of the tree and "Not in a folder",
  the current place marked, unreachable folders (depth, itself) for a folder
  move, the refusal for images not yours to move (§5.1).
- **D8, dragging images and folders**: what is dragged (one tile or the
  selection, the count), the drop target's look, the announcement for a screen
  reader, no drag on a coarse pointer.
- **D9, the image panel's folder**: the line that says where the image is
  ("Clients / Client A") and its "Move to…", for a viewer who may move it and
  one who may not.
- **D10, the place's heading over the grid**: the folder's path (a breadcrumb
  or a heading), its count, whether subfolders also show in the grid as folder
  tiles, the empty folder ("No images in this folder yet" and the upload offer).
- **D11, search in a folder**: the offer to search All media with the same
  words, and in All media whether a tile names its folder.
- **D12, the picker's folders**: how places are browsed inside the 880px dialog
  (a list beside the grid, a select, a breadcrumb), its Upload's target said.
- **D13, the live notice**: the quiet line when another tab changed the shown
  place, its words and its "Show changes".
- **D14, the folder mark**: a new glyph (folder, open folder) for the tree row,
  the move dialog and the panel, in `admin/shared/_tree_glyph` or the icon set.

## 18. With the Gallery block

The Gallery block needs folders for "add a whole folder" only. **Folders first
(call):** it is the owner's newest ask, its first part needs no card, and the
gallery's picker work then builds on a picker that already browses places. If
the gallery lands first, it ships without "add a whole folder" and its plan's
last task adds it when folders merge. Either way the picker is changed by both
plans: this one gives it places and the remembered place; the gallery's gives it
several images at once and "add all images in this folder".

## 19. The guide and the release

- `CHANGELOG.md`, Unreleased: Added, folders in the media library (create,
  rename, move, delete, nesting to four levels; moving images by drag, menu and
  selection; uploads into the open folder; the picker browses folders and opens
  where you last were); MCP's `list_media_folders_tool`, and `folder` on the two
  media tools. Migrations: `20261116130000_create_media_folders`.
- The guide (`contentspiel-docs`), under "Documentation" in the pull request:
  the editors' page on the media library (folders, moving, the picker), the
  administrators' page on groups (who may shape folders: `media.manage`), the
  integrators' MCP page (the new tool and argument).
- No new top-level name (`Media::Folder`, `Media::FolderTree`, `Media::Place`,
  `Media::FolderCounts` and the services are under `Media::`).

## 20. Only the owner can answer

1. **Tags for images.** One folder per image is recommended because tags give
   the many-to-many; but images have no tags today. Should tags for images be
   the next step after folders, or is one folder enough for now?
2. **Who shapes the tree.** `media.manage` (Admin, Editor) creates, renames,
   moves and deletes folders; an author with `media.upload` alone uploads into
   them and moves their own images. Right?
3. **The picker's remembered place** is per browser. Per person (a column on
   the user) instead?
4. **Per-folder permissions** ("a group uses only Client A's images") is the
   roadmap's argument for folders. When is it wanted? §13 keeps the seam open.
5. The numbers: four levels, 1,000 folders, 200 images per move.
