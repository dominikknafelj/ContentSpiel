# Media Folders Implementation Plan

> Amended 2026-11-16 to the design answers (Design System v242) and the owner's rulings.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Library images live in named folders, nested up to four levels, one folder per image; editors create, rename, move and delete folders, move images by drag, menu and selection, upload into the open folder, and the picker browses folders and opens where it last was.

**Architecture:** A `media_folders` table with `parent_id` and a nullable `media_assets.folder_id`; the tree is read whole into `Media::FolderTree` (one query, at most 1,000 rows). Three services write: `Media::SaveFolder`, `Media::DeleteFolder`, `Media::MoveImages`, all behind the tree's table lock. The listing's place is one value, `Media::Place`, beside the unchanged `Media::Search`; counts are one grouped query. Other tabs hear "the library changed" through `Live::Signals` on a `media.upload`-gated stream.

**Tech Stack:** Rails 8.1, Postgres 17, ViewComponent, Stimulus (import maps), Action Cable, Minitest, Cuprite for browser tests.

**Spec:** `docs/superpowers/specs/2026-11-16-media-folders-design.md`, the binding authority; §n below is its (§17 the design answers, §20 the owner's rulings). **Design:** the card StudioMediaFolders, D1 to D14, of the CMS Design System v242 (version `1794813077-09f4`, https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT; read it with the Artifact tool's `read`, never a web fetch). Where the card and this plan differ on a word, the card wins; on behaviour, the spec does.

## Global Constraints

- Read `CLAUDE.md`; before a test, `docs/reference/writing-tests.md`, and `test/system/README.md` before a browser test. Before each task, the reference files its files name: `media.md`, `trash.md`, `access-control-and-audit.md`, `design-system.md`, `save-rule-and-write-queue.md`, `notes.md` ("Live delivery", for `Live::Signals`), `presence.md` (the list stream), `cs-studio-shell-and-dashboard.md` (the tree column and its subjects: the Folders column is its third).
- A new worktree runs `bin/rails db:test:prepare` and `bin/rails tailwindcss:build` once, never while tests run. Browser tests run alone, on a quiet machine (`sysctl -n vm.loadavg`).
- Names: model `Media::Folder` (`app/models/media/folder.rb`, `self.table_name = "media_folders"`); `Media::FolderTree`, `Media::Place` (`app/values/media/`); `Media::FolderCounts` (`app/queries/media/`); services `Media::SaveFolder`, `Media::DeleteFolder`, `Media::MoveImages`; `Media::LibrarySignals` (`app/models/media/`); `Media::LibraryChannel` (`app/channels/media/`). No new top-level constant. Never `Admin::Media…` as a module: controllers are `Admin::MediaFoldersController`, `Admin::MediaMovesController`; components `Admin::MediaLibrary::…`.
- The screen's names, exactly: the shell's tree subject `media` (never `media_folders`); the folds' cookie `cs_media_open` (`TreeOpenSet::MEDIA_COOKIE`), written by `tree/open_set.js` alone; the parameters `folder` (the place) and `select` (selection mode); the `localStorage` key `cs.media.picker.place`; the tree glyphs `folder`, `folder_open`, `folder_none`, `media`; the icons `folder`, `folder_input`.
- Constants, exactly: `Media::Folder::MAX_DEPTH = 4`, `Media::Folder::MAX_FOLDERS = 1000`, `Media::Folder::NAME_LENGTH = 80`, `Media::MoveImages::MAX = 200`, `Media::DeleteFolder::IDS_KEPT = 200`.
- The migration is `db/migrate/20261116130000_create_media_folders.rb`. Every existing image keeps `folder_id` nil.
- The parameter is `folder`: absent or `"all"` is All media, `"none"` is Not in a folder, digits a folder's id. Every Media-screen link keeps it beside `q`, `filter` and `page` (`Admin::MediaController#list_query`).
- Rights (owner's ruling, spec §20): folder writes need `media.manage`; a move needs each image's edit right (`Media::Ownership`), all or nothing; viewing and uploading into a folder need `media.upload`. No per-folder access.
- No folder reaches the site: no content version bump, no usage row. Every write on `media_assets` around the callbacks carries `# version: none (a folder is never drawn on the site)`; a move never touches `updated_at`.
- Tree writes take `LOCK TABLE media_folders IN SHARE ROW EXCLUSIVE MODE` first (`# sql:` on its line); a move's or an upload's target folder is read `FOR KEY SHARE`; a delete locks the folder's row `FOR UPDATE` before moving anything.
- Audit actions, exactly: `media_folder.created`, `media_folder.renamed`, `media_folder.moved`, `media_folder.deleted`, `media.moved` (counted). Each joins `Audit::Sentence::ACTIONS` and `Editing::Signals::SILENT`. The audit filter's subject type "Media folder".
- Words are keys: `config/locales/admin/media_library.en.yml` for `Admin::MediaLibrary::*` components; the services' refusal sentences are literals of the services (as `Trash::Restore`'s are) quoted from the spec and the card: "Give the folder a name.", "Use at most 80 characters.", "A folder named “%{name}” is already here.", "A folder can't go inside itself.", "That would nest folders more than 4 levels deep.", "That folder is gone.", "%{count} of these images are not yours to move. Nothing was moved." (one: "1 of these images is not yours to move. Nothing was moved."), "Move at most 200 images at once.", "A site holds at most 1,000 folders.".
- Every write from the browser goes through `app/javascript/saving/queue.js`. No Turbo morphing or page refresh.
- Queries: Active Record, then Arel (`SqlNodes`); the one SQL string is the `LOCK TABLE`.
- Comments state invariants, hazards or reasons, never history or plan steps. No compatibility code.
- `CHANGELOG.md`'s `## Unreleased` gets each task's line in that task; the migration's version under `### Migrations` (`bin/changelog-guard`).
- The words are the card StudioMediaFolders' (v242); a card word wins over the plan's. Every word quoted in Part two is copied from the card; a word the card does not give is marked "(not on the card)" and is the planner's.
- Migrations run against the scratch DB: prefix `DATABASE_URL=postgres://contentspiel:contentspiel@localhost:5433/content_spiel_development_media` to `bin/rails db:migrate`; never migrate content_spiel_development.
- Prefix every test command with PGGSSENCMODE=disable.
- Browser tests begin on `visit_screen` (the Media screen) or `visit_editor` (the picker, which opens from an editor); a drag goes through `loadSortable()` (`editor/drag.js`) so `await_sortables` holds (`test/system/README.md`).
- Commits by explicit path, conventional messages, each ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```

## Review Focus

1. **A folder deleted while another tab moves images into it**: whichever commits first wins whole; the later move answers "That folder is gone." and moves nothing; no image falls to Not in a folder by the FK — Task 4, `test "a move into a folder deleted first moves nothing and says the folder is gone"` and Task 3, `test "a delete waits for a move into the folder and moves those images up too"`.
2. **A forged move of a folder into its own descendant**, or one that would nest five deep: refused, the tree unchanged, nothing audited — Task 2, `test "a folder moved inside itself or below its own subfolder is refused"`, `test "a move whose deepest folder would sit at level 5 is refused"`.
3. **A name that differs from a sibling's only by case or outer spaces** (`"  client a "` beside `"Client A"`): refused on the name field, never a 500 — Task 2, `test "a sibling's name in another case is refused on the name, and the index's race is the same failure"`.
4. **A trashed image in a deleted folder, restored later**: back in the deleted folder's parent — Task 3, `test "a trashed image moves up with the rest and is restored into the parent"`.
5. **The picker's remembered folder deleted meanwhile**, and storage refused: the picker opens on All media with no 404 and forgets it — Task 5, `test "the picker answers All media for a folder that names nothing"`; Task 17, `test "a remembered folder that is gone opens All media and is forgotten"`, `test "storage that throws opens All media and the picker still works"`.
6. **Two cookies, one writer**: `cs_media_open` is written by `tree/open_set.js` alone, a tree cannot make the module write a third cookie, and the Pages tree's folds stay in `cs_tree_open` — Task 9, `test "the open set has one writer"` (widened), `test "a fold is written to the cookie its tree names, and only that one"`; Task 11, `test "a fold is kept in cs_media_open across a visit and leaves the Pages tree's folds alone"`.
7. **A drag refused by the tree** (a folder onto its own branch, too deep, a taken name): no drop target, the reason said, nothing sent — Task 16, `test "a row that cannot take the folder shows no target and says why"`.

---

## Part one: the model, the services and the endpoints

### Task 1: The table, the model and the tree

**Files:**
- Create: `db/migrate/20261116130000_create_media_folders.rb`; `db/schema.rb` by `bin/rails db:migrate`
- Create: `app/models/media/folder.rb`, `app/values/media/folder_tree.rb`
- Modify: `app/models/media/asset.rb` (`belongs_to :folder, class_name: "Media::Folder", optional: true`)
- Modify: `CHANGELOG.md` (`### Migrations`)
- Test: `test/models/media/folder_test.rb`, `test/values/media/folder_tree_test.rb`, `test/migrations/create_media_folders_test.rb`, `test/fixtures/media/folders.yml` (empty unless a test needs rows: build them in tests)

**Interfaces:**
- Produces: `Media::Folder` (`name`, `parent`, `children`, `created_by`, `has_many :assets, class_name: "Media::Asset", foreign_key: :folder_id`); validations: name present after strip ("Give the folder a name."), `<= NAME_LENGTH` ("Use at most 80 characters."), no `\p{Cc}`.
- Produces: `Media::FolderTree.load -> Media::FolderTree`; `#roots -> Array<Node>`; `#children(id) -> Array<Node>`; `#find(id) -> Node | nil`; `#path(id) -> Array<Node>` (top first); `#depth(id) -> Integer` (a top folder is 1); `#height(id) -> Integer` (1 for a leaf); `#descendant_ids(id) -> Array<Integer>`; `#inside?(id, of:) -> Boolean`; `#size -> Integer`; `#ids -> Array<Integer>` (what `TreeOpenSet.parse` is handed as `readable_ids`, Task 11); `#each_in_order -> Enumerator<[Node, depth]>` (the column's and the move dialog's walk); `Node = Data.define(:id, :parent_id, :name)`, `#path_name(id) -> String` (names joined with " / ").

- [ ] **Step 1: Write the failing tests.**
  - `create_media_folders_test.rb` (on `test/support/schema_loaded_database.rb`'s pattern): `test "existing images start in no folder and the migration reverses"`.
  - `folder_test.rb`: `test "a name is stripped, required, at most 80 characters and holds no control character"`; `test "two folders of one parent may not share a name in any case, and two at the top neither"` (the index: `assert_raises(ActiveRecord::RecordNotUnique)` on `insert_all`); `test "deleting a folder around the services leaves its images in no folder"` (the FK's nullify).
  - `folder_tree_test.rb`: `test "the tree is one query and sorts names case-insensitively with numbers as numbers"` (`"Event 10"`, `"event 2"`, `"Alpha"` → `Alpha, event 2, Event 10`; `assert_queries_count(1)`); `test "depth, height, path and descendants"` (four levels); `test "inside? is true for a folder under another and for itself"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/media/folder_test.rb test/values/media/folder_tree_test.rb test/migrations/create_media_folders_test.rb` → FAIL (`uninitialized constant Media::Folder`).
- [ ] **Step 3: The migration.** `create_table :media_folders` (`name` string null false, `parent_id` references `media_folders` with a plain FK, `created_by_id` FK to `users` `on_delete: :nullify`, timestamps); `add_index :media_folders, "parent_id, lower((name)::text)", unique: true, nulls_not_distinct: true, name: "index_media_folders_on_parent_and_name"`; `add_reference :media_assets, :folder, foreign_key: { to_table: :media_folders, on_delete: :nullify }, index: true`. `down` reverses both. Run `DATABASE_URL=postgres://contentspiel:contentspiel@localhost:5433/content_spiel_development_media bin/rails db:migrate`, then `PGGSSENCMODE=disable bin/rails db:test:prepare`.
- [ ] **Step 4: The model and the tree.** The natural order key: `name.downcase.split(/(\d+)/).map { |part| part.match?(/\A\d+\z/) ? [0, part.to_i] : [1, part] }`.
- [ ] **Step 5: CHANGELOG** `### Migrations`: "`20261116130000_create_media_folders`: the table `media_folders` and `media_assets.folder_id`; every existing image starts in no folder."
- [ ] **Step 6:** Step 2's command → PASS; then `PGGSSENCMODE=disable bin/rails test test/models/media/` → PASS.
- [ ] **Step 7: Commit** `feat: media_folders and Media::FolderTree`.

### Task 2: Creating, renaming and moving a folder

**Files:**
- Create: `app/services/media/save_folder.rb`
- Modify: `app/models/media/folder.rb` (`.lock_tree!`)
- Modify: `app/models/audit/sentence.rb` (the four `media_folder.*` actions in `OTHER_VERBS`, label and route), `app/models/audit/filter.rb` (`"Media::Folder" => "Media folder"`), `app/models/audit/snapshot.rb` (a folder's label is its name; snapshot `name`, `parent_id`), `app/models/editing/signals.rb` (`SILENT`: the four with "library folders have no live editor")
- Modify: `test/services/service_behaviour_contract_test.rb` (`EXPECTED_SERVICES`), `test/support/service_calls.rb` (`"Media::SaveFolder"`, `permission: "media.manage"`)
- Test: `test/services/media/save_folder_test.rb`, `test/models/audit/sentence_test.rb`

**Interfaces:**
- Consumes: Task 1's `Media::FolderTree`.
- Produces: `Media::SaveFolder.call(folder = nil, attributes: { name: String, parent_id: Integer | nil }) -> ApplicationService::Result` (`record` the folder; errors on `:name` or `:parent_id`); `Media::Folder.lock_tree! -> nil`.
- Produces: `Audit::Sentence` words "created the folder “%{name}”", "renamed the folder “%{from}” to “%{to}”", "moved the folder “%{name}” into “%{parent}”", "moved the folder “%{name}” to the top", "deleted the folder “%{name}”".

- [ ] **Step 1: Write the failing tests** (`save_folder_test.rb`):
  - `test "a holder of media.manage creates a folder at the top and inside another, each audited once"` (`media_folder.created`, `snapshot["name"]`).
  - `test "media.upload alone may not create, rename or move a folder"` (denied, one `access.denied`, nothing written).
  - `test "a sibling's name in another case is refused on the name, and the index's race is the same failure"` (Review Focus 3; the race by stubbing the pre-check away and catching `RecordNotUnique`).
  - `test "renaming records the old and the new name and is never coalesced"` (two renames within a minute → two `media_folder.renamed` rows).
  - `test "a folder moved inside itself or below its own subfolder is refused"` (Review Focus 2).
  - `test "a move whose deepest folder would sit at level 5 is refused"` (Review Focus 2: a two-level subtree into a level-3 folder).
  - `test "a parent that names no folder is refused on parent_id"`.
  - `test "the 1,001st folder is refused"` (`stub_const(Media::Folder, :MAX_FOLDERS, 2)` or the helper the suite uses for constants).
  - `test "every tree write takes the tree's lock first"` (`assert_sql_order` or the capture helper `writing-tests.md` names: the `LOCK TABLE` statement precedes the insert).
  - `sentence_test.rb`: `test "the folder actions read created, renamed, moved into, moved to the top and deleted"`.
- [ ] **Step 2:** run them → FAIL.
- [ ] **Step 3: Implement** `Media::SaveFolder#call`: `authorize!("media.manage", nil)`; strip the name; `lock_tree!` (the one `# sql:` string); `Media::FolderTree.load` after the lock; the checks in the order of the tests; `save!`; `record_event` with `field_changes` for a rename (`"name"`) or a move (`"parent_id"`), `coalesce: false`; rescue `ActiveRecord::RecordNotUnique` into the name's failure.
- [ ] **Step 4: Audit words, filter, snapshot, SILENT** as in Files.
- [ ] **Step 5:** run Step 1's files, `test/services/service_behaviour_contract_test.rb`, `test/models/editing/signals_test.rb`, `test/models/audit/` → PASS.
- [ ] **Step 6: Commit** `feat: Media::SaveFolder creates, renames and moves a folder`.

### Task 3: Deleting a folder

**Files:**
- Create: `app/services/media/delete_folder.rb`
- Modify: `EXPECTED_SERVICES`, `test/support/service_calls.rb`, `app/models/editing/signals.rb` (`media_folder.deleted`)
- Test: `test/services/media/delete_folder_test.rb`

**Interfaces:**
- Consumes: Task 2's `lock_tree!`.
- Produces: `Media::DeleteFolder.call(folder) -> Result`; `Media::DeleteFolder.preview(folder, tree: Media::FolderTree.load) -> Data(image_count:, folder_count:, renames: Hash{id => new_name}, target: Media::Folder | nil)` (the confirm dialog's words, Task 13).

- [ ] **Step 1: Write the failing tests:**
  - `test "its images and subfolders move one level up and the event names what moved"` (`metadata` keys `parent_id`, `moved_image_count`, `moved_image_ids`, `moved_folder_ids`).
  - `test "at the top, its images go to no folder and its subfolders to the top"`.
  - `test "a subfolder whose name the parent holds takes the next free suffix and is recorded renamed"` ("Logos" beside "Logos" and "Logos 2" → "Logos 3").
  - `test "the image ids are kept for 200 or fewer and only counted above"`.
  - `test "a trashed image moves up with the rest and is restored into the parent"` (Review Focus 4: `Trash::Move`, delete, `Trash::Restore`, `folder_id == parent.id`).
  - `test "a delete waits for a move into the folder and moves those images up too"` (Review Focus 1: two connections; the suite's two-connection helper, else a thread with its own `ActiveRecord::Base.connection_pool.with_connection` holding `FOR KEY SHARE` on the folder while the delete runs; assert the moved image ends in the parent).
  - `test "the writes on media_assets bump no content version and leave updated_at alone"`.
  - `test "media.upload alone may not delete a folder"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** in the order of spec §6.4: tree lock, the folder's row `lock("FOR UPDATE")` (reloaded; gone is "That folder is gone."), `Media::Asset.where(folder_id: folder.id).update_all(folder_id: folder.parent_id)` (`# version: none (a folder is never drawn on the site)`, no `updated_at`), the suffixes, the children's `update_all(parent_id:)`, `record_event("media_folder.deleted", …)` before `destroy!`.
- [ ] **Step 4:** run the file and `test/lib/version_bump_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: Media::DeleteFolder moves a folder's contents up`.

### Task 4: Moving images

**Files:**
- Create: `app/services/media/move_images.rb`
- Modify: `app/models/audit/sentence.rb` (`media.moved` in `COUNTED` and its words), `app/models/editing/signals.rb` (`SILENT`), `EXPECTED_SERVICES`, `test/support/service_calls.rb`
- Create: `test/lib/media_folder_writers_test.rb`
- Test: `test/services/media/move_images_test.rb`, `test/models/audit/sentence_test.rb`

**Interfaces:**
- Produces: `Media::MoveImages.call(asset_ids: Array, folder: Media::Folder | nil) -> Result` (`record` nil; `#moved -> Array<Media::Asset>`).
- Produces: words "moved “%{title}” to “%{folder}”", "moved “%{title}” out of every folder", counted "moved %{count} images to “%{folder}”".

- [ ] **Step 1: Write the failing tests:**
  - `test "an editor moves images into a folder and each gets one media.moved with the folder change"`.
  - `test "an uploader moves their own images, and one image not theirs refuses the whole move"` (the sentence "1 of these images is not yours to move. Nothing was moved.", and with two "2 of these images are not yours to move. Nothing was moved.", the card's D7; nothing written, denial recorded once).
  - `test "more than 200 ids are refused before anything is read"` (`assert_queries_count(0)` after the auth query, or no `media_assets` select).
  - `test "a trashed or missing id is refused as missing and nothing moves"`.
  - `test "a move into a folder deleted first moves nothing and says the folder is gone"` (Review Focus 1).
  - `test "a move touches neither updated_at nor the content version"` (an open panel's base still saves after it: `Media::Save` with the earlier `base_updated_at` succeeds through `Admin::StaleForm`'s check in an integration case in `test/integration/admin/media_test.rb`, `test "a panel's autosave after a move elsewhere is not stale"`).
  - `sentence_test.rb`: `test "media.moved reads moved to a folder or out of every folder, and counted for the dashboard"`.
  - `media_folder_writers_test.rb`: `test "folder_id is written only by the folder services, the upload and the migration"` (grep `app/` and `lib/`, comments stripped as `dependency_direction_test.rb` strips them, for `folder_id:` and `folder:` assignments on `Media::Asset`; allowed: `move_images.rb`, `delete_folder.rb`, `upload.rb`).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement:** the count check; `Media::Asset.kept.where(id:)` (missing → failure); each image's right through `Media::Ownership` (all, then refuse); the target `Media::Folder.lock("FOR KEY SHARE").find_by(id:)`; one `update_all(folder_id:)` with its `# version: none` line; one `record_event("media.moved", subject: asset, field_changes: { "folder_id" => [old, new] }, metadata: { "folder_name" => folder&.name }, coalesce: false)` per image.
- [ ] **Step 4:** run Step 1's files, `test/lib/version_bump_test.rb`, the service contracts → PASS.
- [ ] **Step 5: Commit** `feat: Media::MoveImages, the one writer of an image's folder`.

### Task 5: Places, counts, search and the upload target

**Files:**
- Create: `app/values/media/place.rb`, `app/queries/media/folder_counts.rb`
- Modify: `app/services/media/search.rb` (`place:`), `app/services/media/upload.rb` (`folder:`), `app/controllers/admin/media_controller.rb` (`folder` param: parse, 404 for an unknown one on the screen, All media in the picker; `list_query` keeps `folder`; `create` passes the place's folder), `app/controllers/admin/media_assets_controller.rb` (the picker's place), `app/controllers/concerns/admin/media_upload_responses.rb` (`folder_counts`)
- Test: `test/values/media/place_test.rb`, `test/queries/media/folder_counts_test.rb`, `test/services/media/search_test.rb`, `test/services/media/upload_test.rb`, `test/integration/admin/media_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: Task 1's tree.
- Produces: `Media::Place.parse(raw, tree:) -> Media::Place | nil`; `Media::Place::ALL`, `Media::Place::NONE`; `#folder -> Media::Folder id | nil`; `#to_param -> "all" | "none" | String`; `#narrow(scope) -> ActiveRecord::Relation`; `#all? / #none?`.
- Produces: `Admin::MediaController#place_query(place) -> Hash` (helper method: `q`, `filter`, `folder` of `place`, `locale`; never `page`, `selected` or `select`), beside `list_query`, which keeps `folder` and `page`.
- Produces: `Media::Search.new(q:, filter:, actor:, place: Media::Place::ALL, scope: …)`; counts and results are the place's.
- Produces: `Media::FolderCounts.call -> { all: Integer, none: Integer, folders: Hash{Integer => Integer} }` (kept images, one grouped query).
- Produces: `Media::Upload.call(file:, folder: nil)`; `media.uploaded` metadata `folder_id`.

- [ ] **Step 1: Write the failing tests:**
  - `place_test.rb`: `test "absent and all are All media, none is Not in a folder, an id of the tree is that folder, anything else is nil"` (`["5"]`, `"5x"`, a missing id).
  - `folder_counts_test.rb`: `test "counts are direct kept images per folder, outside any folder and in all, in one query"`.
  - `search_test.rb`: `test "a search and a segment narrow the place, and the counts are the place's"`.
  - `upload_test.rb`: `test "an upload in a folder lands in it and says so in its event"`; `test "an upload into a folder deleted meanwhile is refused and stores nothing"`.
  - `media_test.rb`: `test "the grid lists a folder's own images and not its subfolders'"`; `test "an unknown folder is the 404 with Back to Media"`; `test "the picker answers All media for a folder that names nothing"` (Review Focus 5; the answer marks it `data-media-place-gone`, which Task 17's script reads to forget the place); `test "every link of the grid and the panel keeps folder"`; `test "a link to another place keeps q and filter and drops page"` (`Admin::MediaController#place_query(place)`, the one builder of a link to a place, which Tasks 11 to 17 call); `test "an upload answer carries the folder counts"`; `test "selected without folder opens the panel over All media as before"`.
  - `trash_visibility_test.rb`: `test "a trashed image is in no folder's listing or count, and comes back to its folder"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** the value, the query (`Media::Asset.kept.group(:folder_id).count`, `all` the sum), the search's narrowing (`place.narrow(@scope)` before `matching`), the upload's folder (read `FOR KEY SHARE` in its transaction; gone is "That folder is gone." on `:file`), the controller's parse and `list_query`.
- [ ] **Step 4:** run Step 1's files and `test/services/media/`, `test/integration/admin/media_assets_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: the library's places, their counts and the upload target`.

### Task 6: The library stream for other tabs

**Files:**
- Create: `app/models/media/library_signals.rb`, `app/channels/media/library_channel.rb`
- Modify: `app/services/media/save_folder.rb`, `delete_folder.rb` (`Media::LibrarySignals.changed(reason: "folders")`), `move_images.rb` (`reason: "moved"`)
- Test: `test/models/media/library_signals_test.rb`, `test/channels/media/library_channel_test.rb`

**Interfaces:**
- Produces: `Media::LibrarySignals::STREAM = "media:library"`; `Media::LibrarySignals.changed(reason:) -> nil` (sends `{ kind: "library", reason:, origin: Live::Signals.origin }`, `origin` left out when nil, after the outermost commit).
- Produces: `Media::LibraryChannel` (private `subscribed`: `RecordKinds.named("media")`'s read right held by `subscriber`, else `reject`).

- [ ] **Step 1: Write the failing tests:**
  - `library_signals_test.rb`: `test "a folder write and a move each send one library signal after the commit and none on a rollback"`; `test "the signal names no folder, image or word"` (payload keys exactly `kind`, `reason`, and `origin` when set).
  - `library_channel_test.rb`: `test "a media.upload holder streams the library, anyone else is rejected alike"`; `test "the channel defines no public method"` (the rule `test/channels/live/record_channel_test.rb` applies under `app/channels`).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** through `Live::Signals.later` only (`test/models/notes/signals_test.rb` refuses any other broadcast).
- [ ] **Step 4:** run Step 1's files and `test/models/notes/signals_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: a library-wide live signal for folder changes and moves`.

### Task 7: MCP

**Files:**
- Modify: `app/mcp/mcp/tools/list_media.rb` (`folder` argument, `folder` in each entry, description), `app/mcp/mcp/tools/get_media.rb` (`folder`)
- Create: `app/mcp/mcp/tools/list_media_folders.rb` (`tool_name "list_media_folders_tool"`)
- Modify: `app/controllers/mcp_controller.rb` (register it)
- Test: `test/integration/mcp_media_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Produces: `list_media_tool(folder: Integer | "none")`; an entry's `folder: { id:, name:, path: } | nil`; `list_media_folders_tool() -> [{ id:, name:, parent_id:, path:, image_count: }]` in the tree's order, `media.upload`.

- [ ] **Step 1: Write the failing tests** (`mcp_media_test.rb`): `test "list_media narrows to a folder or to none, and an unknown folder is an error"`; `test "list_media and get_media name each image's folder with its path"`; `test "list_media_folders lists the tree in order with kept image counts and needs media.upload"`; `trash_visibility_test.rb`: `test "list_media_folders counts no trashed image"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement**; the tree read once per call (`Media::FolderTree.load`), the counts from `Media::FolderCounts`.
- [ ] **Step 4:** run (`PGGSSENCMODE=disable bin/rails test …`) `test/integration/mcp_media_test.rb test/integration/mcp_test.rb test/integration/trash_visibility_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: MCP reads folders`.

### Task 8: The endpoints

**Files:**
- Create: `app/controllers/admin/media_folders_controller.rb` (`create`, `update`, `destroy`), `app/controllers/admin/media_moves_controller.rb` (`create`)
- Modify: `config/routes.rb` (beside `resources :media`: `resources :media_folders, only: %i[create update destroy]`, `post "media/move", to: "media_moves#create", as: :media_move`)
- Test: `test/integration/admin/media_folders_test.rb`, `test/integration/admin/media_moves_test.rb`

**Interfaces:**
- Consumes: Tasks 2 to 5.
- Produces: `POST /<ADMIN_PATH>/media_folders` (`media_folder[name]`, `media_folder[parent_id]`), `PATCH /media_folders/:id` (name or parent), `DELETE /media_folders/:id`, `POST /media/move` (`asset_ids[]`, `folder` as the place parameter: `"none"` or an id), each with the screen's place (`place`, the `folder` shown) so the answer can draw it. Turbo Stream answers through responders in `app/controllers/admin/answers/`, the refusal's status `Admin::RefusalStatus`, the toast `Admin::ToastStream`:
  - `Admin::Answers::FolderSaved(folder:, place:)` (create, rename, a folder's move) and `Admin::Answers::FolderDeleted(parent:)`: the Folders column is the shell's tree column, outside `#content`, so a frame answer never redraws it; these replace its part, `#media-folder-tree-part` (`FolderSaved::TREE_TARGET`), and name the place to go to (a create: the new folder; a delete: the parent or All media; a rename or a move: the place shown). Until Task 11 builds `Admin::MediaLibrary::FolderTreeComponent`, the part is an empty `div#media-folder-tree-part` carrying `data-media-go` (the place's URL from `place_query`); Task 11 draws the component there. `FolderDeleted` adds the toast "Folder deleted" (the card's D4). A create and a rename answer no toast (D2).
  - `Admin::Answers::FolderRefused(form:, errors:)`: 422, replaces the dialog's form (`#media-folder-form`) with the errors under the field (Task 13 draws the form).
  - `Admin::Answers::ImagesMoved(assets:, folder:, place:)`: removes the tiles of the moved images when they left the place shown (not in All media), replaces the column's part (its counts) and the place heading's count, and adds the toast "Moved %{count} images to “%{folder}”." (one: "Moved “%{title}” to “%{folder}”." (not on the card); to no folder the folder's words are "Not in a folder" (not on the card)).

- [ ] **Step 1: Write the failing tests:**
  - `media_folders_test.rb`: `test "each action is a 403 before any folder is looked up for someone without media.manage"` (an id that names nothing and one that exists answer alike); `test "a refused name answers 422 with the field's sentence and writes nothing"`; `test "a create answers the column's part with the new folder as the place to go to and no toast"`; `test "delete answers the column's part with the folder's parent as the place and the toast Folder deleted"`; `test "a rename answers the column's part and keeps the place"`.
  - `media_moves_test.rb`: `test "a move answers the column's counts and removes the moved tiles from the place they left"`; `test "a move in All media removes no tile"`; `test "a refused move answers 422 with the sentence and moves nothing"`; `test "a move needs media.upload or media.manage before anything is read"`; `test "a move's toast says how many images went where"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** the controllers (gates as `Admin::MediaController`'s, every write through its service, each action ending in `answer(...)`), and the responders drawing only.
- [ ] **Step 4:** run Step 1's files and `test/integration/admin/media_test.rb` → PASS.
- [ ] **Step 5: CHANGELOG** nothing yet (the endpoints have no screen). **Commit** `feat: the folder and move endpoints`.

---

---

## Part two: the screens (StudioMediaFolders, D1 to D14)

The looks and measures are the card's (StudioMediaFolders; StudioTree, StudioMediaGrid, MediaPicker, StudioShell and FoundationIcons carry its pointer lines); every word below is copied from it unless marked "(not on the card)". Every component is in `Admin::MediaLibrary::` (`app/components/admin/media_library/`, its keys under `admin.components.media_library.*` in `config/locales/admin/media_library.en.yml`): the Media screen and its picker template alone draw them (`test/lib/component_screens_test.rb`: `SCREENS` for the components, `SCREEN_FILES` already names the picker's template). The shared components this part changes (`Admin::Ui::TreeFindComponent`, `TreeItemComponent`, `MediaPickerComponent`) keep their `Admin::Ui::Contract`, updated in the same task. Each new component file joins `test/lib/admin_i18n_test.rb`'s `CONVERTED`. Every Stimulus controller is under `app/javascript/controllers/admin/media/` (identifier `admin--media--<name>`), every write it sends goes through `app/javascript/saving/queue.js`, and whatever it writes into the page it takes back before `turbo:before-cache`.

### Task 9: The open set for two trees

**Files:**
- Modify: `app/javascript/tree/open_set.js`: `const COOKIES = ["cs_tree_open", "cs_media_open"]`; the cookie's name is a parameter, read from the tree each function is handed, `tree.dataset.treeOpenCookie`, and used only when it is on `COOKIES` (a tree without it, or naming another, reads nothing and writes nothing, as one without `data-tree-open-path` writes nothing today). `readOpenSet(tree, seed = null)` (the tree is the new first argument), `setOpen(tree, …)`, `forgetFolds(tree, …)`, `openPathIn(tree, …)` read and write the tree's own cookie. The header comment says "kept per browser in one cookie per tree, `cs_tree_open` (pages, both page trees) and `cs_media_open` (library folders), each named by the tree it folds".
- Modify the callers: `app/javascript/tree/find.js` (`readOpenSet(tree)`), `app/javascript/mind_graph/node_list.js` (`readOpenSet(tree, tree.dataset.treeOpen ?? null)`), `app/javascript/controllers/admin/tree/disclosure_controller.js` (`readOpenSet(this.element)`).
- Modify: `app/values/tree_open_set.rb`: `MEDIA_COOKIE = "cs_media_open"` beside `COOKIE`; its comment: the ids of a tree's nodes (page ids in `COOKIE`, folder ids in `MEDIA_COOKIE`), one format and one rule for both; a folder tree has no root, so its caller passes `root: false`.
- Modify: `app/components/admin/pages_screen/tree_component.html.erb` and `app/views/admin/mind_graph/show.html.erb`: `data-tree-open-cookie="<%= TreeOpenSet::COOKIE %>"` beside `data-tree-open-path`.
- Modify: `test/lib/admin_design_rules_test.rb`: `OPEN_SET_NAMES = /cs_tree_open|cs_media_open|TreeOpenSet::(?:MEDIA_)?COOKIE/`; the script check `/\bdocument\s*\.\s*cookie\b|cs_(?:tree|media)_open/`; the Ruby check matches either literal; the comment above the guard says two cookies, one writer; `test "the open set has one writer"` also asserts `MEDIA_COOKIE = "cs_media_open"` in the reader.
- Test: `test/values/tree_open_set_test.rb`, `test/system/admin/tree_test.rb`

**Interfaces:**
- Produces: `readOpenSet(tree, seed = null) -> { opened, folded }`; every exported function of `tree/open_set.js` that reads or writes the cookie takes the tree first. `TreeOpenSet::MEDIA_COOKIE`. The tree's DOM gains `data-tree-open-cookie`.

- [ ] **Step 1: Write the failing tests:**
  - `admin_design_rules_test.rb`, `test "the open set's writer guard reports each sample"` gains: `"app/javascript/other.js" => %(const name = "cs_media_open"\n)` → offence; `"app/controllers/x.rb" => %(cookies[TreeOpenSet::MEDIA_COOKIE] = "1"\n)` → offence; `"app/views/x.html.erb" => %(data-tree-open-cookie="<%= TreeOpenSet::MEDIA_COOKIE %>"\n)` → none.
  - `test "the open set has one writer"`: the reader names both constants.
  - `tree_open_set_test.rb`: `test "a folder cookie is read as a page cookie is, held to the readable ids, and a folder tree opens no root"`.
  - `tree_test.rb` (`visit_screen`): `test "a fold is written to the cookie its tree names, and only that one"` (fold a Pages branch; `document.cookie` holds `cs_tree_open` and no `cs_media_open`).
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/values/tree_open_set_test.rb` → FAIL.
- [ ] **Step 3: Implement** as in Files. Nothing else of the module's rule changes.
- [ ] **Step 4:** Step 2's command, then `PGGSSENCMODE=disable bin/rails test test/system/admin/tree_test.rb test/system/admin/tree_find_test.rb test/system/admin/mind_graph_list_test.rb test/system/admin/tree_item_parity_test.rb` → PASS (the two page trees fold as before).
- [ ] **Step 5: Commit** `ref: the open set takes its cookie's name from the tree`.

### Task 10: The marks, the shell's third subject and the find's noun (D1, D14)

**Files:**
- Modify: `app/views/admin/shared/_tree_glyph.html.erb`: `:folder` (Lucide folder), `:folder_open` (Lucide folder-open), `:folder_none` (the folder drawn dashed, `stroke-dasharray="2.2 2.2"`), `:media` (the `media` icon's shape at 14px), each 14px, `viewBox="0 0 16 16"`, stroke 1.3, `aria-hidden`, and `data-tree-glyph="<name>"` (Task 11's stylesheet rule reads it); the header comment names them.
- Modify: `app/views/admin/shared/_icon.html.erb`: `:folder` (the panel, the dialogs, a tile's folder line; `size:` as the others) and `:folder_input` (Lucide folder-input, `size-4` in Move to… buttons and menu items).
- Modify: `app/components/admin/shell/tree_subjects.rb`: `"media" => { fill: false }`; its comment names the three.
- Modify: `config/locales/admin/shell.en.yml`, `tree_subject.media`: `hide: "Hide folders"`, `show: "Show folders"`, `open: "Open folders"` (not on the card: the top bar button's name, after "Open page tree"), `button: "Folders"`, `divider: "Folders width"`, `divider_tooltip: "Folders width %{width}px. Arrow keys to resize."`.
- Modify: `app/components/admin/ui/tree_find_component.rb` (`NOUNS = %i[pages nodes folders]`, its comment) and `config/locales/admin/ui.en.yml` `tree_find`: `label.folders` and `placeholder.folders` "Find a folder", `count.folders` one "1 folder matches" / other "%{count} folders match", `none.folders` "No folders match".
- Test: `test/helpers/admin/shell_helper_test.rb`, `test/components/admin/ui/tree_find_component_test.rb`, `test/components/admin/ui/tree_item_component_test.rb`

**Interfaces:**
- Produces: `render "admin/shared/tree_glyph", name: :folder | :folder_open | :folder_none | :media`; `render "admin/shared/icon", name: :folder | :folder_input`; `Admin::Shell::TreeSubjects.fetch("media")`; `Admin::Ui::TreeFindComponent.new(controls:, noun: :folders)`.

- [ ] **Step 1: Write the failing tests:**
  - `shell_helper_test.rb`: `test "the media subject is the Folders column, which does not fill"` (and the existing "every subject has every word" covers its six keys).
  - `tree_find_component_test.rb`: `test "the folders noun says Find a folder and counts folders"`.
  - `tree_item_component_test.rb`: `test "a row's mark can be each folder glyph, silent to a screen reader"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** as in Files.
- [ ] **Step 4:** run Step 1's files, `test/lib/admin_design_rules_test.rb`, `test/components/component_contract_test.rb`, `test/lib/admin_i18n_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: the folder marks, the media tree subject and the folders find`.

### Task 11: The Folders column (D1)

**Files:**
- Create: `app/components/admin/media_library/folder_tree_component.rb` and `.html.erb`: the tree of places, `ul#media-folder-tree.admin-tree` with `data-tree-open-path`, `data-tree-open-cookie="<%= TreeOpenSet::MEDIA_COOKIE %>"` and `data-controller="admin--tree--disclosure admin--media--folders"`, inside `div#media-folder-tree-part` (Task 8's stream target, `FolderSaved::TREE_TARGET`). Rows through `Admin::Ui::TreeItemComponent`: **All media** (`with_mark` the `:media` glyph) and **Not in a folder** (`:folder_none`), each with its count as a trailing (`CLASSES[:count]`); `li` of a `cs-line` rule (6px above and below); then the folders in natural order (`Media::FolderTree#each_in_order`), each with `parent:`/`controls:` for a folder with children, `folded:` from `TreeOpenSet#open?(id, root: false, on_path:)`, `with_mark` both `:folder` and `:folder_open`, its direct count as a trailing and nothing at 0; links (`data-turbo-frame="content"`, `turbo_action: "advance"`) to `admin_media_path(place_query(place))`. With no folders: one `p.text-small.text-dim` under the rule, "No folders yet.". `mode: :screen` here; Task 17 adds `:picker`.
- Create: `app/javascript/controllers/admin/media/folders_controller.js` (on the tree): THE SELECTED ROW IS THE PLACE SHOWN, read from `#content`'s `[data-media-place]` (drawn by the Media screen) after each `turbo:frame-load` of `content` and as rows connect, as `admin--pages--tree#follow` reads `[data-tree-open-page]`: it marks that row (`TreeItemComponent::CLASSES[:row_selected]` as Stimulus classes, `aria-current="page"`), opens the path to it (`openPathIn`), scrolls it into view inside `#tree-column`, and rewrites each row's `href` to the content's `q` and `filter` (`data-media-query`, a JSON object) without `page`. When a part connects with `data-media-go`, it navigates the `content` frame there (`frame.src`, advance) and removes the attribute.
- Modify: `app/views/admin/media/index.html.erb`: for a full answer only (`turbo_frame_request?`, as `admin/pages/_tree`), `content_for :tree_label, "media"` and `content_for :tree` with the head (`h2.flex-1.text-sm.font-semibold.text-ink` "Folders" and `Admin::Ui::TreeHideComponent.new(subject: "media")`), `Admin::Ui::TreeFindComponent.new(controls: "media-folder-tree", noun: :folders)` and the component. `#content`'s view gains `data-media-place` (`place.to_param`) and `data-media-query`. The view comment "No tree column…" is rewritten: the Folders column is the shell's tree column, subject `media`, outside `#content`, drawn for a full answer only, its selection followed by `admin--media--folders`.
- Modify: `app/controllers/admin/media_controller.rb` (`@folder_tree`, `@folder_counts`, `@media_open = TreeOpenSet.parse(cookies[TreeOpenSet::MEDIA_COOKIE], readable_ids: @folder_tree.ids)`), Task 8's responders (`FolderSaved`, `FolderDeleted`, `ImagesMoved` render the component into the part).
- Modify: `app/components/admin/ui/tree_item_component.rb` (its comment: one row of a tree, a page's or a library folder's; `node_id:` a node's bare id), `app/assets/tailwind/content-spiel.tailwind.css` (in the `.admin-tree` block: a mark holding both folder glyphs shows `folder_open` on `.admin-tree-row--selected` and `folder` elsewhere, keyed on `[data-tree-glyph]`; the selected mark `cs-ink`), `config/locales/admin/media_library.en.yml` (`folder_tree.heading: "Folders"`, `all: "All media"`, `none: "Not in a folder"`, `empty: "No folders yet."`), `test/lib/component_screens_test.rb` (`SCREENS`), `test/lib/admin_i18n_test.rb`.
- Test: `test/components/admin/media_library/folder_tree_component_test.rb`, `test/integration/admin/media_test.rb`, `test/system/admin/media_folders_test.rb`, `test/system/admin/tree_column_test.rb`

**Interfaces:**
- Produces: `Admin::MediaLibrary::FolderTreeComponent.new(tree:, counts:, place:, query:, open_set:, manage:, mode: :screen, go_to: nil)` (`query:` `{ q:, filter: }`; `manage:` whether the viewer holds `media.manage`, read by Tasks 13 and 16); `ID = "media-folder-tree"`, `PART_ID = "media-folder-tree-part"`. The rows' data hooks: `data-media-place` (`all`, `none` or the id) on every row; on a folder row `data-media-folder-depth`, `-height`, `-parent` and `-name` (the downcased name), which Tasks 14 and 16 read.

- [ ] **Step 1: Write the failing tests:**
  - component: `test "the column lists All media, Not in a folder, a rule and the folders in natural order, each with its direct count"`; `test "a folder with no images draws no count"`; `test "the place shown is the selected row and its mark is the open folder"`; `test "every row's link keeps q and filter and drops page"`; `test "folds are drawn from cs_media_open, the path to the place open and every other folder folded"`; `test "with no folders the column says No folders yet."`.
  - `media_test.rb`: `test "the Media screen's column is the media subject with the Folders words"`; `test "a frame answer draws no column"`; `test "the content names its place and its query for the column's script"`.
  - browser `media_folders_test.rb` (`visit_screen`): `test "a row opens its place in the content frame and the column follows the selection"`; `test "a fold is kept in cs_media_open across a visit and leaves the Pages tree's folds alone"` (Review Focus 6); `test "Find a folder narrows the rows and says how many match"`; `test "a search typed in the grid is kept by the rows' links"`.
  - `tree_column_test.rb`: `test "the Folders column takes the tree's width, divider and fold"`; `test "below 1024px the folders are the drawer opened by Folders in the top bar"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** as in Files.
- [ ] **Step 4:** run Step 1's files with `test/lib/admin_design_rules_test.rb`, `test/lib/source_layout_test.rb`, `test/lib/component_screens_test.rb`, `test/lib/admin_i18n_test.rb`, `test/system/admin/media_library_test.rb` → PASS.
- [ ] **Step 5: CHANGELOG** Added: "The media library's folders, in the tree column of the Media screen." **Commit** `feat: the Folders column on the Media screen`.

### Task 12: The place heading and search in a folder (D10, D11)

**Files:**
- Create: `app/components/admin/media_library/place_heading_component.rb` and `.html.erb`: in a folder, the breadcrumb (`nav`, `text-small text-meta`, its links in accent, through `place_query`): "All media › Clients › Client A", the last the place itself, unlinked; the `h1` the place's name ("Client A", "All media", "Not in a folder"), its count `text-small text-meta` ("34 images"; one: "1 image" (not on the card)); at the right, Upload images (the header's button moves here from `index.html.erb`). Tasks 13 to 15 add the ⋯ menu and Select. The breadcrumb is drawn for a folder only (not on the card: All media and Not in a folder are places of the top). Its `nav`'s name is "Where you are" (not on the card).
- Modify: `app/views/admin/media/index.html.erb` (the heading replaces the header's `h1`; "Media" stays the page's title, `content_for :title`, and the sidebar's word).
- Modify: `app/components/admin/media_library/grid_component.rb` and template (`place:`, `subfolders:`): an empty folder is `Admin::Ui::EmptyStateComponent` with "No images in this folder yet", "Drop images here, or use Upload images: they go into %{name}." and, when it holds folders, "It holds %{count} folders: %{links}." (one: "It holds 1 folder: %{links}." (not on the card)), each name a link to its place; an empty Not in a folder: "Every image is in a folder.". Subfolders are never tiles.
- Modify: `app/components/admin/media_library/toolbar_component.rb` and template: with a search inside a folder, a line under the filter bar, `text-small text-dim`: "Searching in %{name}." and the link "Search all media for “%{q}” →" (`q` and `filter` kept, `folder` and `page` dropped).
- Modify: `app/components/admin/media_library/tile_component.rb` and template (`folder_path:`): in All media with a search, a tile in a folder adds a third line, the 12px `folder` icon and the folder's name, `text-label text-meta`, truncated, the whole path ("Clients / Client A") its `title`; nothing without a search.
- Modify: `config/locales/admin/media_library.en.yml` (`place_heading.count`, `.breadcrumb_label`; `grid.empty_folder.title`, `.body`, `.holds`; `grid.empty_none`; `toolbar.searching_in`, `toolbar.search_all`).
- Test: `test/components/admin/media_library/place_heading_component_test.rb`, `grid_component_test.rb`, `toolbar_component_test.rb`, `tile_component_test.rb`, `test/integration/admin/media_test.rb`

**Interfaces:**
- Produces: `Admin::MediaLibrary::PlaceHeadingComponent.new(place:, tree:, count:, query:, manage:, upload: true)`; `GridComponent.new(…, place:, subfolders: [])`; `TileComponent.new(…, folder_path: nil)`; `ToolbarComponent.new(…, place:)`.

- [ ] **Step 1: Write the failing tests:**
  - `place_heading_component_test.rb`: `test "a folder's heading is its breadcrumb, its name and its count"`; `test "All media and Not in a folder are named in the h1 with no breadcrumb"`.
  - `grid_component_test.rb`: `test "an empty folder offers the upload into it and links its subfolders"`; `test "an empty Not in a folder says every image is in a folder"`; `test "a folder's subfolders are never tiles"`.
  - `toolbar_component_test.rb`: `test "a search in a folder says where and offers the same words in All media"` (the link carries `q` and `filter`, no `folder`, no `page`).
  - `tile_component_test.rb`: `test "in All media with a search a tile in a folder names it, its path as the title"`; `test "without a search no tile names its folder"`.
  - `media_test.rb`: `test "the page title stays Media and the h1 is the place's name"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with `test/lib/admin_i18n_test.rb`, `test/system/admin/media_library_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: where you are in the library, and searching beyond the folder`.

### Task 13: Creating, renaming and deleting a folder (D2, D3, D4, D10's menu)

**Files:**
- Create: `app/components/admin/media_library/folder_dialog_component.rb` and `.html.erb` (`Admin::Ui::DialogComponent`, `width: :form_narrow`, `ID = "media-folder-dialog"`): title "New folder" or "Rename folder"; the form `#media-folder-form` (Task 8's `FolderRefused` target) with the field "Name" (drawn as the card TextFields draws a field, the admin form classes the Settings forms use; `maxlength` 80; a rename fills it in and selects it), under it, `text-small text-dim` with the `folder` icon, "At the top of the library" or "Inside %{path}" ("Inside Clients / Client A"); the errors under the field (FieldFrame); footer Cancel (tertiary) and **Create folder** or **Rename** (primary).
- Create: `app/components/admin/media_library/delete_folder_dialog_component.rb` and `.html.erb` (`Admin::Ui::ConfirmDialogComponent`, `destructive: true`, `ID = "media-folder-delete-dialog"`), its words from `Media::DeleteFolder.preview`: title "Delete “%{name}”?", the danger button **Delete folder**; the body "Its %{images} and %{folders} move to “%{parent}”. Nothing else is deleted." (with a parent), "Its %{folders} move to the top of the library, and its %{images} to Not in a folder. Nothing else is deleted." (at the top), "It is empty."; each rename "“%{from}” becomes “%{to}”, because “%{parent}” already has a folder of that name."; then "This can't be undone." in `text-small text-dim`. The counts are pluralised keys ("34 images", "2 folders"; one: "1 image", "1 folder" (not on the card)); a part with nothing to move is left out of the sentence ("Its 34 images move to “Clients”. Nothing else is deleted." (not on the card)).
- Create: `app/javascript/controllers/admin/media/folder_dialog_controller.js` (on the dialog): opens for a create with the trigger's parent (`parent-id`, `parent-path` params) or for a rename with the place's folder; sends the form through `saving/queue.js`; on a 422 the replaced form keeps the focus in the field; on success closes (the answer's part navigates, Task 11).
- Modify: `app/components/admin/media_library/folder_tree_component.rb` and template: for `manage:`, the head's "+ New folder" (`Admin::Ui::ButtonComponent`, secondary small, `dialog_trigger(FolderDialogComponent::ID)`, at the top level) and each folder row's "+" on levels 1 to 3 (`with_add(label: "New folder in %{name}")`, a button, the dialog's trigger with the folder as parent); a level-4 row has none.
- Modify: `app/components/admin/media_library/place_heading_component.rb` and template: in a folder, for `manage:`, after the count, the ⋯ `Admin::Ui::MenuComponent` named "Folder actions": "New folder inside…" (levels 1 to 3), "Rename…", then (Task 14) "Move to…", and after a separator "Delete folder…" (danger).
- Modify: `app/views/admin/media/index.html.erb` (both dialogs rendered once, outside `#content`, for `media.manage`).
- Modify: `config/locales/admin/media_library.en.yml` (`folder_tree.new_folder: "New folder"`, `folder_tree.add: "New folder in %{name}"`; `folder_dialog.*`; `delete_folder_dialog.*`; `place_heading.menu: "Folder actions"`, `.new_inside: "New folder inside…"`, `.rename: "Rename…"`, `.delete: "Delete folder…"`; `toast.deleted: "Folder deleted"`).
- Test: `test/components/admin/media_library/folder_dialog_component_test.rb`, `delete_folder_dialog_component_test.rb`, `folder_tree_component_test.rb`, `place_heading_component_test.rb`, `test/integration/admin/media_folders_test.rb`, `test/system/admin/media_folders_test.rb`

**Interfaces:**
- Consumes: Task 8's endpoints and responders; Task 3's `preview`.
- Produces: `FolderDialogComponent.new(folder: nil, parent: nil, tree:, errors: nil)`; `DeleteFolderDialogComponent.new(folder:, preview:)`; the triggers' params `parent-id`, `parent-path`.

- [ ] **Step 1: Write the failing tests:**
  - `folder_dialog_component_test.rb`: `test "the new folder dialog says where the folder goes"` ("At the top of the library", "Inside Clients / Client A"); `test "the rename dialog fills in the name and says Rename"`; `test "a refusal stands under the Name field"` (each of the five sentences).
  - `delete_folder_dialog_component_test.rb`: `test "the body says what moves where for a folder with a parent"`; `test "at the top it says the folders go to the top and the images to Not in a folder"`; `test "an empty folder says It is empty."`; `test "each suffixed subfolder has its sentence"`; `test "it ends This can't be undone."`.
  - `folder_tree_component_test.rb`: `test "New folder and the rows' + are for media.manage, on levels 1 to 3"`.
  - `place_heading_component_test.rb`: `test "the folder menu is for media.manage in a folder, with New folder inside only above level 4"`.
  - browser `media_folders_test.rb`: `test "a folder is created from a row's +, becomes the place, and gets no toast"`; `test "a taken name keeps the dialog open with the error under the field and the focus in it"`; `test "a folder is renamed from the place menu"`; `test "deleting a folder says what moves where, then opens the parent with Folder deleted"`; `test "a folder is created and deleted from the keyboard alone"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with `test/integration/admin/media_folders_test.rb`, `test/system/dialog_test.rb`, `test/lib/admin_i18n_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: creating, renaming and deleting folders`.

### Task 14: Move to… and the panel's Folder row (D7, D9, D5's keyboard way)

**Files:**
- Create: `app/components/admin/media_library/move_dialog_component.rb` and `.html.erb`: the shell, rendered once outside `#content` (`Admin::Ui::DialogComponent`, `width: :form_narrow`, `ID = "media-move-dialog"`, `data:` the controller), its body a `<turbo-frame id="media-move-choices">` loaded on open, and its footer Cancel and **Move here** (primary, disabled until a choice).
- Create: `app/components/admin/media_library/move_choices_component.rb` and `.html.erb` (the frame's body): a field "Find a folder" (a TextFields search field, filtering the rows by name, not on the card: no tree find, the list is a radiogroup); a `role="radiogroup"` named by the dialog's title, in a `cs-line` frame, `rounded-tile`, scrolling at 260px: 32px rows, each a radio with the `folder` icon and its name, stepped 20px a level, every branch open. The first row "Not in a folder" for images, "Top of the library" for a folder. The current place carries the neutral `Admin::Ui::BadgeComponent` "Current" and its radio is disabled. In a folder move, the folder and its branch ("this folder") and every place that would be too deep ("too deep") are disabled, the reason at the row's end in `text-label text-meta` and the radio's `aria-describedby`. A refusal is `Admin::Ui::NoticeComponent.new(tone: :danger)` at the top, which takes the focus: "2 of these images are not yours to move. Nothing was moved." or "That folder is gone.".
- Modify: `app/controllers/admin/media_moves_controller.rb`: `new` (`GET /media/move/new`, `asset_ids[]` or `folder_id`, `media.upload`; a folder move needs `media.manage`), drawing the choices for that subject; `config/routes.rb` (`get "media/move/new", to: "media_moves#new", as: :new_media_move`).
- Create: `app/javascript/controllers/admin/media/move_controller.js` (on the dialog): opens for the trigger's subject (`asset-ids`, `folder-id`, `title` params), sets the dialog's title ("Move %{count} images", "Move “%{title}”", "Move “%{name}”") and the frame's `src`; enables Move here on a choice; submits through `saving/queue.js` to `POST /media/move` (images) or `PATCH /media_folders/:id` with `parent_id` (a folder); on a 422 the refusal notice takes the focus; on success closes.
- Modify: `app/components/admin/media_library/panel_component.rb` and template: a Folder row in the facts (`dl`), after Type and before Uploaded, so between File and Uploaded: `dt` "Folder"; `dd` the path ("Clients / Client A") as a link to that place (`place_query`), then, for a viewer who may move the image (`Media::Ownership`), a tertiary small "Move to…" (the `folder_input` icon), the dialog's trigger for this image. With no folder: "Not in a folder" in `text-meta`. A viewer who may not move it sees the path or "Not in a folder" alone.
- Modify: `place_heading_component` template: the menu's "Move to…" (the `folder_input` icon), the dialog's trigger for the place's folder.
- Modify: `config/locales/admin/media_library.en.yml` (`move_dialog.title.images` one "Move “%{title}”" other "Move %{count} images", `.title.folder: "Move “%{name}”"`, `.find: "Find a folder"`, `.none: "Not in a folder"`, `.top: "Top of the library"`, `.current: "Current"`, `.this_folder: "this folder"`, `.too_deep: "too deep"`, `.cancel: "Cancel"`, `.submit: "Move here"`; `panel.facts.folder: "Folder"`, `panel.no_folder: "Not in a folder"`, `panel.move: "Move to…"`; `place_heading.move: "Move to…"`; the folder move's toast "Moved “%{name}” to “%{parent}”." and "Moved “%{name}” to the top of the library." (both not on the card), drawn by `FolderSaved`).
- Test: `test/components/admin/media_library/move_choices_component_test.rb`, `panel_component_test.rb`, `test/integration/admin/media_moves_test.rb`, `test/system/admin/media_folder_moves_test.rb`

**Interfaces:**
- Produces: `MoveChoicesComponent.new(tree:, subject:, current:)` (`subject:` `{ kind: :images, ids: }` or `{ kind: :folder, folder: }`); `GET /media/move/new`; the trigger params `asset-ids` (comma-joined), `folder-id`, `title`, which Task 15's bar and Task 16 reuse.

- [ ] **Step 1: Write the failing tests:**
  - `move_choices_component_test.rb`: `test "images list Not in a folder first and the tree with every branch open"`; `test "a folder lists Top of the library first"`; `test "the current place is marked Current and cannot be chosen"`; `test "a folder move disables itself, its branch and too-deep places with their reason as the description"`.
  - `panel_component_test.rb`: `test "the Folder row links the path and offers Move to only to a viewer who may move the image"`; `test "an image in no folder reads Not in a folder"`.
  - `media_moves_test.rb`: `test "the choices for images mark the current place and are behind media.upload"`; `test "the choices for a folder need media.manage"`.
  - browser `media_folder_moves_test.rb` (`visit_screen`): `test "the panel's Move to moves the image and keeps the panel open on it"`; `test "a folder moves with the place menu's Move to from the keyboard alone"`; `test "Move here is disabled until a choice"`; `test "a refused move shows the danger notice with the focus on it and moves nothing"`; `test "the toast says where the images went"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with `test/system/dialog_test.rb`, `test/system/admin/media_library_test.rb`, `test/lib/admin_i18n_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: Move to… for images and folders, and the panel's folder`.

### Task 15: Selecting several images (D6)

**Files:**
- Create: `app/components/admin/media_library/selection_bar_component.rb` and `.html.erb`: the bar that replaces the heading's right end, at elevation 3 on `cs-popover`, `rounded-card`, sticky under the top offset: "**%{count} selected**" (the count also announced by an always-present `role="status"` outside the bar, as the posts list's bar does), "Select all %{count}" (tertiary; what the page draws; it reads "All %{count} selected" when all are), "Clear" (tertiary), a spacer kept for "Move to trash…" and "Download" later (spec §5.3), "**Move to…**" (secondary, the `folder_input` icon; Task 14's trigger with the selection's ids), "Done" (tertiary).
- Modify: selection mode is a parameter, `select=1`, of the place's frame (not on the card: the server draws the tiles as buttons, as the picker's are, rather than a script turning links into buttons). `Admin::MediaController#index` reads it (`list_query` keeps it, `place_query` drops it; it drops `selected`, so the panel closes). `PlaceHeadingComponent`: "Select" (secondary small, before Upload images), a frame link to the place with `select=1`; in selection mode the bar instead. `GridComponent`/`TileComponent` (`select:`): each tile a `button` with `aria-pressed`, the 24px `cs-surface` chip at the top left (8px in, `shadow-1`) holding `Admin::Ui::CheckboxComponent` (presentational, `tabindex="-1"`, the button is the control), the accent outline when selected.
- Create: `app/javascript/controllers/admin/media/selection_controller.js` (on the grid's wrapper): a press toggles, Space toggles, Shift+click ticks the range in grid order, Select all ticks the page's tiles, Clear unticks, the status says the count; "Done" and Escape go back to the place without `select` (a frame visit), as does any visit. The selection is the script's, of this page: leaving drops it.
- Modify: `config/locales/admin/media_library.en.yml` (`place_heading.select: "Select"`; `selection.count: "%{count} selected"`, `.select_all: "Select all %{count}"`, `.all_selected: "All %{count} selected"`, `.clear: "Clear"`, `.move: "Move to…"`, `.done: "Done"`).
- Test: `test/components/admin/media_library/selection_bar_component_test.rb`, `tile_component_test.rb`, `test/integration/admin/media_test.rb`, `test/system/admin/media_folder_moves_test.rb`

**Interfaces:**
- Produces: `SelectionBarComponent.new(count_on_page:)`; the `select` parameter; `TileComponent.new(…, select: false)`.

- [ ] **Step 1: Write the failing tests:**
  - `selection_bar_component_test.rb`: `test "the bar counts, selects all drawn, clears, moves and is done"`; `test "the count is announced outside the bar"`.
  - `tile_component_test.rb`: `test "in selection mode a tile is a pressed button with its tick"`.
  - `media_test.rb`: `test "select drops the panel and is dropped by a link to another place"`.
  - browser `media_folder_moves_test.rb`: `test "three images selected move with the dialog from the keyboard alone"`; `test "Shift+click ticks a range in grid order"`; `test "Select all selects what the page draws, then reads All 34 selected"`; `test "Escape, Done and a visit leave selection mode"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with `test/system/admin/media_library_test.rb`, `test/lib/admin_design_rules_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: selecting several images and moving them`.

### Task 16: Dragging images and folders (D5, D8)

**Files:**
- Create: `app/javascript/controllers/admin/media/drag_controller.js` (on the screen's wrapper, around the grid and reaching the column): both drags go through `loadSortable()` (`editor/drag.js`, `forceFallback`, `data-sortable="pending"` then `"ready"`), created only while `matchMedia("(pointer: fine)")` matches (not on the card: the card's "`draggable` only under a fine pointer" is a Sortable created only then), and the folders' only while the find field is empty.
  - Images: a Sortable on the grid with `sort: false`, `group: { name: "media-move", pull: "clone", put: false }`; one tile, or the whole selection when the tile is selected (outside selection mode, or from a selected tile). The fallback clone is hidden and the ghost follows the pointer: a `cs-popover` pill at elevation 4, a 32×24 thumbnail, the title or "%{count} images", and an accent count pill above one (a `<template>` the screen draws).
  - Folders: the gutter handle (`TreeItemComponent` `with_handle`, `media.manage` only) of each folder row.
  - Targets: the tree row under the pointer, found as `admin--pages--tree` finds its drop row; for images a folder or "Not in a folder"; for a folder a folder row (into it) or "All media" (to the top). The target's look is `TreeItemComponent::CLASSES[:drop_target]` (`cs-accent-tint`, a 1px accent outline, the mark in accent, the open folder). A folded row opens after 600ms of hover (`OPEN_ON_HOVER_MS`, the Pages tree's). A row that cannot take a folder (itself, under itself, too deep, a sibling of its name, read from Task 11's `data-media-folder-*`) shows no target: its title and mark `cs-meta`, its count replaced by "too deep", "this folder" or "name taken" (`text-count`), and the polite status says "Can't move “%{name}” there: %{reason}.".
  - The drop sends through `saving/queue.js` (`POST /media/move`, or `PATCH /media_folders/:id`), and the status says "Moved %{count} images to %{folder}." (the screen's polite status; one: "Moved “%{title}” to %{folder}." (not on the card)). The window-wide file drop overlay never shows (a fallback drag fires no file `dragenter`).
- Modify: `folder_tree_component` (the handles for `manage:`; `data-controller` gains the drop hooks), `index.html.erb` (the ghost's `<template>` and the controller), `config/locales/admin/media_library.en.yml` (`drag.count: "%{count} images"`, `drag.moved: "Moved %{count} images to %{folder}."`, `drag.refused: "Can't move “%{name}” there: %{reason}."`, `drag.too_deep: "too deep"`, `drag.this_folder: "this folder"`, `drag.name_taken: "name taken"`), `app/assets/tailwind/content-spiel.tailwind.css` (the ghost pill and the hidden fallback clone).
- Test: `test/components/admin/media_library/folder_tree_component_test.rb`, `test/system/admin/media_folder_drag_test.rb`

- [ ] **Step 1: Write the failing tests:**
  - component: `test "the handle is drawn for media.manage only"`.
  - browser `media_folder_drag_test.rb` (`visit_screen`, `await_sortables`): `test "a tile dragged onto a folder moves, and the counts and the grid follow"`; `test "a selection dragged from a selected tile moves every selected image"`; `test "a drop on Not in a folder takes the image out of every folder"`; `test "a folded row opens after a hover"`; `test "a folder dragged by its handle onto a row moves into it, and onto All media to the top"`; `test "a row that cannot take the folder shows no target and says why"` (Review Focus 7); `test "dragging a tile shows no upload overlay"`; `test "a coarse pointer gets no drag and no handle"` (Cuprite's touch emulation, as `tree_test.rb` does); `test "a search typed in Find a folder stops the folders' drag"`; `test "the move is announced in the polite status"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with `test/system/admin/media_library_test.rb`, `test/system/admin/editor_modules_test.rb` (the Sortable seam) → PASS.
- [ ] **Step 5: Commit** `feat: dragging images and folders onto the Folders column`.

### Task 17: The picker's places (D12)

**Files:**
- Modify: `app/components/admin/media_library/folder_tree_component.rb` (`mode: :picker`): read-only rows (no "+", no handle, no drag); folded as on the screen, but for the path to the place, and its folds are not kept (`data-tree-open-cookie` left out, so `tree/open_set.js` writes nothing for it; not on the card); links into the picker's frame (`data-turbo-frame="media-picker-grid"`, `picker=1`); below 640px a `select` named "Folder" (drawn as the card ChoiceFields draws a select) above the toolbar, the same places indented by level, whose change loads the frame (`admin--media--picker#place`).
- Modify: `app/views/admin/media/picker.html.erb`: the body two columns, the 200px `cs-surface` list with a `cs-line` rule on its right and the grid; the grid at four columns from 1024px, three from 768px, two below. The frame's body names its place on one hidden element inside the frame, `#media-picker-place` (`data-media-place`, `data-media-place-name`, and `data-media-place-gone`, drawn by Task 5); never on the `<turbo-frame>` tag, whose attributes Turbo does not copy from a frame response.
- Modify: `app/components/admin/ui/media_picker_component.rb` and template: before Upload, `text-small text-meta`, "Uploads go into %{name}" or "Uploads go into no folder", the button's `aria-describedby`; its contract's limits gain "It browses the library's places and opens at the last one shown, per browser."; keys in `config/locales/admin/ui.en.yml` (`media_picker.upload_into`, `media_picker.upload_nowhere`).
- Modify: `app/javascript/controllers/admin/media/picker_controller.js`: the remembered place in `localStorage` under `cs.media.picker.place` (`all`, `none` or an id), every read and write in `try`/`catch`; the frame's `src` carries `folder`; after each frame load it stores the place shown, forgets it on `#media-picker-place[data-media-place-gone]`, writes "Uploads go into …" from `data-media-place-name`, selects that row and scrolls it into view; Upload goes to the place (Task 5's `MediaAssetsController`).
- Modify: `config/locales/admin/media_library.en.yml` (`folder_tree.picker_select: "Folder"`).
- Test: `test/components/admin/media_library/folder_tree_component_test.rb`, `test/components/admin/ui/media_picker_component_test.rb`, `test/system/admin/media_picker_test.rb`

- [ ] **Step 1: Write the failing tests:**
  - `folder_tree_component_test.rb`: `test "in the picker the rows are read-only, keep no folds and load the picker's frame"`; `test "the picker's places are also a select named Folder"`.
  - `media_picker_component_test.rb`: `test "Upload says where its files go and is described by it"`.
  - browser `media_picker_test.rb` (`visit_editor`, the picker opened from the Image block): `test "the picker browses into a folder, and opens there the next time"`; `test "a remembered folder that is gone opens All media and is forgotten"` (Review Focus 5); `test "storage that throws opens All media and the picker still works"` (stub `localStorage.getItem` to throw); `test "an upload in the picker lands in the folder shown"`; `test "the remembered place is the selected row, scrolled into view"`; `test "below 640px the places are the select"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with the hero's, the Image block's and the rich-text editor's picker tests unchanged → PASS.
- [ ] **Step 5: CHANGELOG** Added: "The image picker browses folders and opens where you last were." **Commit** `feat: the picker browses folders and opens where you were`.

### Task 18: Live updates on the screen and in the picker (D13)

**Files:**
- Create: `app/controllers/admin/media_folders_controller.rb#index` (`GET /<ADMIN_PATH>/media/folders`, `media.upload`, `folder` and `picker` as the screen's): the column's part (`FolderTreeComponent`, the counts) and, on it, `data-media-place-digest` of the place asked for (`Media::Place#digest`, one aggregate over the place's kept image ids and its path's names through `SqlNodes`) and `data-media-place-gone` when the folder went; `config/routes.rb`.
- Modify: `app/values/media/place.rb` (`#digest`).
- Create: `app/javascript/controllers/admin/media/live_controller.js` (on the screen and on the picker's dialog while open): subscribes to `Media::LibraryChannel` through `live/connection`; on a signal whose `origin` is not this tab, at most one fetch per two seconds of the part, replaced silently (the server draws the folds from `cs_media_open`; the focus kept on the same row by its `data-media-place`); when the digest of the place shown differs from the one it holds, one `Admin::Ui::NoticeComponent.new(tone: :neutral, size: :compact, role: :status)` above the grid, from a `<template>` the screen draws: "Images here changed since you opened this view." and a tertiary small "Show changes", which reloads the place's frame (All media when the part says the folder went) and removes the notice; one notice, never stacked.
- Modify: `app/views/admin/media/index.html.erb`, `picker.html.erb` (the controller, the notice's template, the digest on `#content`'s place), `config/locales/admin/media_library.en.yml` (`live.changed: "Images here changed since you opened this view."`, `live.show: "Show changes"`).
- Test: `test/integration/admin/media_folders_test.rb`, `test/values/media/place_test.rb`, `test/system/admin/media_folders_live_test.rb`

- [ ] **Step 1: Write the failing tests:**
  - `media_folders_test.rb`: `test "the column's part is behind media.upload and lists kept counts"`; `test "the part says when the folder asked for is gone"`.
  - `place_test.rb`: `test "a place's digest changes with a move in or out and a rename on its path, and not with a move elsewhere"`.
  - browser `media_folders_live_test.rb` (two sessions, `visit_screen`): `test "a folder made in one tab appears in the other without a reload, its folds and focus kept"`; `test "images moved out of the shown folder by another tab leave the grid alone and offer to show the changes"`; `test "Show changes reloads the place and removes the notice"`; `test "the notice is never stacked and never in the acting tab"`; `test "the picker, open, shows the same notice above its grid"`.
- [ ] **Step 2–4:** FAIL; implement; run Step 1's files with `test/lib/notes_guards_test.rb`, `test/models/notes/signals_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: other tabs follow the library's folders`.

### Task 19: The documents

**Files:**
- Modify: `docs/reference/media.md` (a section "Folders": the table, the tree, places, the services and their locks, the column, the dialogs, selection, Move to…, drag, the stream, MCP; the Describes line names the new files; a rule under "Rules a change can break silently" naming `test/lib/media_folder_writers_test.rb` and the version-bump marks), `docs/reference/trash.md` (a trashed image keeps its folder), `docs/reference/access-control-and-audit.md` (the five actions), `docs/reference/cs-studio-shell-and-dashboard.md` ("The column hosts two screens" becomes three: the subject `media`, its words, the Folders column; the open set's two cookies), `docs/reference/design-system.md` (the row's glyphs sentence: 12px chevron and plus, 14px page, home, `folder`, `folder_open`, `folder_none` and `media`; the tree row is a page's or a folder's; the `_icon` set's `folder` and `folder_input`; the find's `folders` noun), `CLAUDE.md` (the media index line names the new files; the open-set sentence names both cookies and their one writer; the SortableJS sentence names `admin--media--drag` among the controllers that drag; the rules with no guard from spec §16), `docs/roadmap.md` (Shipped; "Folders and tags" leaves tags; per-folder permissions as a row with spec §13's seam), the spec's "As built", `CHANGELOG.md` (Added).
- Modify: `test/support/design_system_entries.rb`: `VERSION = "1794813077-09f4"`, and `ENTRIES` gains `StudioMediaFolders` only (`StudioGallery` and `SiteGallery` are added by the Gallery block's pull request, which is stacked on this one). Nothing else changes: no test reads `VERSION`, no `COVERED_BY` value leaves `ENTRIES`, and this plan adds no `Admin::Ui` component, so `test/lib/component_parts_test.rb`'s three entry tests stay green; 
- Test: `test/lib/source_layout_test.rb` (identifiers named in the documents exist), `test/lib/component_parts_test.rb`, `test/lib/theming_reference_test.rb` untouched

- [ ] **Step 1:** write the sections and the stamp; **Step 2:** `PGGSSENCMODE=disable bin/rails test test/lib/` → PASS; **Step 3:** `PGGSSENCMODE=disable bin/ci` → green; **Step 4: Commit** `docs: media folders`. The pull request's "Documentation" names the guide pages of spec §19.
