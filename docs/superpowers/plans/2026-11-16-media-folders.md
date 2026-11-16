# Media Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Library images live in named folders, nested up to four levels, one folder per image; editors create, rename, move and delete folders, move images by drag, menu and selection, upload into the open folder, and the picker browses folders and opens where it last was.

**Architecture:** A `media_folders` table with `parent_id` and a nullable `media_assets.folder_id`; the tree is read whole into `Media::FolderTree` (one query, at most 1,000 rows). Three services write: `Media::SaveFolder`, `Media::DeleteFolder`, `Media::MoveImages`, all behind the tree's table lock. The listing's place is one value, `Media::Place`, beside the unchanged `Media::Search`; counts are one grouped query. Other tabs hear "the library changed" through `Live::Signals` on a `media.upload`-gated stream.

**Tech Stack:** Rails 8.1, Postgres 17, ViewComponent, Stimulus (import maps), Action Cable, Minitest, Cuprite for browser tests.

**Spec:** `docs/superpowers/specs/2026-11-16-media-folders-design.md`, the binding authority; §n below is its. **Design:** Part two waits for the design agent's cards D1 to D14 (spec §17). Where a card and this plan differ on a word, the card wins; on behaviour, the spec does.

## Global Constraints

- Read `CLAUDE.md`; before a test, `docs/reference/writing-tests.md`, and `test/system/README.md` before a browser test. Before each task, the reference files its files name: `media.md`, `trash.md`, `access-control-and-audit.md`, `design-system.md`, `save-rule-and-write-queue.md`, `notes.md` ("Live delivery", for `Live::Signals`), `presence.md` (the list stream), `cs-studio-shell-and-dashboard.md` (if D1 uses the tree column).
- A new worktree runs `bin/rails db:test:prepare` and `bin/rails tailwindcss:build` once, never while tests run. Browser tests run alone, on a quiet machine (`sysctl -n vm.loadavg`).
- Names: model `Media::Folder` (`app/models/media/folder.rb`, `self.table_name = "media_folders"`); `Media::FolderTree`, `Media::Place` (`app/values/media/`); `Media::FolderCounts` (`app/queries/media/`); services `Media::SaveFolder`, `Media::DeleteFolder`, `Media::MoveImages`; `Media::LibrarySignals` (`app/models/media/`); `Media::LibraryChannel` (`app/channels/media/`). No new top-level constant. Never `Admin::Media…` as a module: controllers are `Admin::MediaFoldersController`, `Admin::MediaMovesController`; components `Admin::MediaLibrary::…`.
- Constants, exactly: `Media::Folder::MAX_DEPTH = 4`, `Media::Folder::MAX_FOLDERS = 1000`, `Media::Folder::NAME_LENGTH = 80`, `Media::MoveImages::MAX = 200`, `Media::DeleteFolder::IDS_KEPT = 200`.
- The migration is `db/migrate/20261116130000_create_media_folders.rb`. Every existing image keeps `folder_id` nil.
- The parameter is `folder`: absent or `"all"` is All media, `"none"` is Not in a folder, digits a folder's id. Every Media-screen link keeps it beside `q`, `filter` and `page` (`Admin::MediaController#list_query`).
- Rights: folder writes need `media.manage`; a move needs each image's edit right (`Media::Ownership`), all or nothing; viewing and uploading into a folder need `media.upload`.
- No folder reaches the site: no content version bump, no usage row. Every write on `media_assets` around the callbacks carries `# version: none (a folder is never drawn on the site)`; a move never touches `updated_at`.
- Tree writes take `LOCK TABLE media_folders IN SHARE ROW EXCLUSIVE MODE` first (`# sql:` on its line); a move's or an upload's target folder is read `FOR SHARE`; a delete locks the folder's row `FOR UPDATE` before moving anything.
- Audit actions, exactly: `media_folder.created`, `media_folder.renamed`, `media_folder.moved`, `media_folder.deleted`, `media.moved` (counted). Each joins `Audit::Sentence::ACTIONS` and `Editing::Signals::SILENT`. The audit filter's subject type "Media folder".
- Words are keys: `config/locales/admin/media_library.en.yml` for `Admin::MediaLibrary::*` components; the services' refusal sentences are literals of the services (as `Trash::Restore`'s are) quoted from the spec: "A folder named “%{name}” is already here.", "A folder can't go inside itself.", "That would nest folders more than 4 levels deep.", "That folder is gone.", "%{count} of these images are not yours to move.", "Move at most 200 images at once.", "A site holds at most 1,000 folders.".
- Every write from the browser goes through `app/javascript/saving/queue.js`. No Turbo morphing or page refresh.
- Queries: Active Record, then Arel (`SqlNodes`); the one SQL string is the `LOCK TABLE`.
- Comments state invariants, hazards or reasons, never history or plan steps. No compatibility code.
- `CHANGELOG.md`'s `## Unreleased` gets each task's line in that task; the migration's version under `### Migrations` (`bin/changelog-guard`).
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
5. **The picker's remembered folder deleted meanwhile**, and storage refused: the picker opens on All media with no 404 and forgets it — Task 8, `test "the picker answers All media for a folder that names nothing"`; Task 12, `test "a remembered folder that is gone opens All media and is forgotten"`.

---

## Part one: before the cards

### Task 1: The table, the model and the tree

**Files:**
- Create: `db/migrate/20261116130000_create_media_folders.rb`; `db/schema.rb` by `bin/rails db:migrate`
- Create: `app/models/media/folder.rb`, `app/values/media/folder_tree.rb`
- Modify: `app/models/media/asset.rb` (`belongs_to :folder, class_name: "Media::Folder", optional: true`)
- Modify: `CHANGELOG.md` (`### Migrations`)
- Test: `test/models/media/folder_test.rb`, `test/values/media/folder_tree_test.rb`, `test/migrations/create_media_folders_test.rb`, `test/fixtures/media/folders.yml` (empty unless a test needs rows: build them in tests)

**Interfaces:**
- Produces: `Media::Folder` (`name`, `parent`, `children`, `created_by`, `has_many :assets, class_name: "Media::Asset", foreign_key: :folder_id`); validations: name present after strip, `<= NAME_LENGTH`, no `\p{Cc}`.
- Produces: `Media::FolderTree.load -> Media::FolderTree`; `#roots -> Array<Node>`; `#children(id) -> Array<Node>`; `#find(id) -> Node | nil`; `#path(id) -> Array<Node>` (top first); `#depth(id) -> Integer` (a top folder is 1); `#height(id) -> Integer` (1 for a leaf); `#descendant_ids(id) -> Array<Integer>`; `#inside?(id, of:) -> Boolean`; `#size -> Integer`; `Node = Data.define(:id, :parent_id, :name)`, `#path_name(id) -> String` (names joined with " / ").

- [ ] **Step 1: Write the failing tests.**
  - `create_media_folders_test.rb` (on `test/support/schema_loaded_database.rb`'s pattern): `test "existing images start in no folder and the migration reverses"`.
  - `folder_test.rb`: `test "a name is stripped, required, at most 80 characters and holds no control character"`; `test "two folders of one parent may not share a name in any case, and two at the top neither"` (the index: `assert_raises(ActiveRecord::RecordNotUnique)` on `insert_all`); `test "deleting a folder around the services leaves its images in no folder"` (the FK's nullify).
  - `folder_tree_test.rb`: `test "the tree is one query and sorts names case-insensitively with numbers as numbers"` (`"Event 10"`, `"event 2"`, `"Alpha"` → `Alpha, event 2, Event 10`; `assert_queries_count(1)`); `test "depth, height, path and descendants"` (four levels); `test "inside? is true for a folder under another and for itself"`.
- [ ] **Step 2:** `bin/rails test test/models/media/folder_test.rb test/values/media/folder_tree_test.rb test/migrations/create_media_folders_test.rb` → FAIL (`uninitialized constant Media::Folder`).
- [ ] **Step 3: The migration.** `create_table :media_folders` (`name` string null false, `parent_id` references `media_folders` with a plain FK, `created_by_id` FK to `users` `on_delete: :nullify`, timestamps); `add_index :media_folders, "parent_id, lower((name)::text)", unique: true, nulls_not_distinct: true, name: "index_media_folders_on_parent_and_name"`; `add_reference :media_assets, :folder, foreign_key: { to_table: :media_folders, on_delete: :nullify }, index: true`. `down` reverses both. Run `bin/rails db:migrate`.
- [ ] **Step 4: The model and the tree.** The natural order key: `name.downcase.split(/(\d+)/).map { |part| part.match?(/\A\d+\z/) ? [0, part.to_i] : [1, part] }`.
- [ ] **Step 5: CHANGELOG** `### Migrations`: "`20261116130000_create_media_folders`: the table `media_folders` and `media_assets.folder_id`; every existing image starts in no folder."
- [ ] **Step 6:** Step 2's command → PASS; then `bin/rails test test/models/media/` → PASS.
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
- Produces: `Media::DeleteFolder.call(folder) -> Result`; `Media::DeleteFolder.preview(folder, tree: Media::FolderTree.load) -> Data(image_count:, folder_count:, renames: Hash{id => new_name}, target: Media::Folder | nil)` (the confirm dialog's words, Task 9).

- [ ] **Step 1: Write the failing tests:**
  - `test "its images and subfolders move one level up and the event names what moved"` (`metadata` keys `parent_id`, `moved_image_count`, `moved_image_ids`, `moved_folder_ids`).
  - `test "at the top, its images go to no folder and its subfolders to the top"`.
  - `test "a subfolder whose name the parent holds takes the next free suffix and is recorded renamed"` ("Logos" beside "Logos" and "Logos 2" → "Logos 3").
  - `test "the image ids are kept for 200 or fewer and only counted above"`.
  - `test "a trashed image moves up with the rest and is restored into the parent"` (Review Focus 4: `Trash::Move`, delete, `Trash::Restore`, `folder_id == parent.id`).
  - `test "a delete waits for a move into the folder and moves those images up too"` (Review Focus 1: two connections; the suite's two-connection helper, else a thread with its own `ActiveRecord::Base.connection_pool.with_connection` holding `FOR SHARE` on the folder while the delete runs; assert the moved image ends in the parent).
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
  - `test "an uploader moves their own images, and one image not theirs refuses the whole move"` (the sentence "1 of these images are not yours to move.", nothing written, denial recorded once).
  - `test "more than 200 ids are refused before anything is read"` (`assert_queries_count(0)` after the auth query, or no `media_assets` select).
  - `test "a trashed or missing id is refused as missing and nothing moves"`.
  - `test "a move into a folder deleted first moves nothing and says the folder is gone"` (Review Focus 1).
  - `test "a move touches neither updated_at nor the content version"` (an open panel's base still saves after it: `Media::Save` with the earlier `base_updated_at` succeeds through `Admin::StaleForm`'s check in an integration case in `test/integration/admin/media_test.rb`, `test "a panel's autosave after a move elsewhere is not stale"`).
  - `sentence_test.rb`: `test "media.moved reads moved to a folder or out of every folder, and counted for the dashboard"`.
  - `media_folder_writers_test.rb`: `test "folder_id is written only by the folder services, the upload and the migration"` (grep `app/` and `lib/`, comments stripped as `dependency_direction_test.rb` strips them, for `folder_id:` and `folder:` assignments on `Media::Asset`; allowed: `move_images.rb`, `delete_folder.rb`, `upload.rb`).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement:** the count check; `Media::Asset.kept.where(id:)` (missing → failure); each image's right through `Media::Ownership` (all, then refuse); the target `Media::Folder.lock("FOR SHARE").find_by(id:)`; one `update_all(folder_id:)` with its `# version: none` line; one `record_event("media.moved", subject: asset, field_changes: { "folder_id" => [old, new] }, metadata: { "folder_name" => folder&.name }, coalesce: false)` per image.
- [ ] **Step 4:** run Step 1's files, `test/lib/version_bump_test.rb`, the service contracts → PASS.
- [ ] **Step 5: Commit** `feat: Media::MoveImages, the one writer of an image's folder`.

### Task 5: Places, counts, search and the upload target

**Files:**
- Create: `app/values/media/place.rb`, `app/queries/media/folder_counts.rb`
- Modify: `app/services/media/search.rb` (`place:`), `app/services/media/upload.rb` (`folder:`), `app/controllers/admin/media_controller.rb` (`folder` param: parse, 404 for an unknown one on the screen, All media in the picker; `list_query` keeps `folder`; `create` passes the place's folder), `app/controllers/admin/media_assets_controller.rb` (the picker's place), `app/controllers/concerns/admin/media_upload_responses.rb` (`folder_counts`)
- Test: `test/values/media/place_test.rb`, `test/queries/media/folder_counts_test.rb`, `test/services/media/search_test.rb`, `test/services/media/upload_test.rb`, `test/integration/admin/media_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: Task 1's tree.
- Produces: `Media::Place.parse(raw, tree:) -> Media::Place | nil`; `Media::Place::ALL`, `Media::Place::NONE`; `#folder -> Media::Folder id | nil`; `#to_param -> "all" | "none" | String`; `#narrow(scope) -> ActiveRecord::Relation`.
- Produces: `Media::Search.new(q:, filter:, actor:, place: Media::Place::ALL, scope: …)`; counts and results are the place's.
- Produces: `Media::FolderCounts.call -> { all: Integer, none: Integer, folders: Hash{Integer => Integer} }` (kept images, one grouped query).
- Produces: `Media::Upload.call(file:, folder: nil)`; `media.uploaded` metadata `folder_id`.

- [ ] **Step 1: Write the failing tests:**
  - `place_test.rb`: `test "absent and all are All media, none is Not in a folder, an id of the tree is that folder, anything else is nil"` (`["5"]`, `"5x"`, a missing id).
  - `folder_counts_test.rb`: `test "counts are direct kept images per folder, outside any folder and in all, in one query"`.
  - `search_test.rb`: `test "a search and a segment narrow the place, and the counts are the place's"`.
  - `upload_test.rb`: `test "an upload in a folder lands in it and says so in its event"`; `test "an upload into a folder deleted meanwhile is refused and stores nothing"`.
  - `media_test.rb`: `test "the grid lists a folder's own images and not its subfolders'"`; `test "an unknown folder is the 404 with Back to Media"`; `test "the picker answers All media for a folder that names nothing"` (Review Focus 5); `test "every link of the grid and the panel keeps folder"`; `test "an upload answer carries the folder counts"`; `test "selected without folder opens the panel over All media as before"`.
  - `trash_visibility_test.rb`: `test "a trashed image is in no folder's listing or count, and comes back to its folder"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** the value, the query (`Media::Asset.kept.group(:folder_id).count`, `all` the sum), the search's narrowing (`place.narrow(@scope)` before `matching`), the upload's folder (read `FOR SHARE` in its transaction; gone is "That folder is gone." on `:file`), the controller's parse and `list_query`.
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
- [ ] **Step 4:** run `test/integration/mcp_media_test.rb test/integration/mcp_test.rb test/integration/trash_visibility_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: MCP reads folders`.

### Task 8: The endpoints

**Files:**
- Create: `app/controllers/admin/media_folders_controller.rb` (`create`, `update`, `destroy`), `app/controllers/admin/media_moves_controller.rb` (`create`)
- Modify: `config/routes.rb` (beside `resources :media`: `resources :media_folders, only: %i[create update destroy]`, `post "media/move", to: "media_moves#create", as: :media_move`)
- Test: `test/integration/admin/media_folders_test.rb`, `test/integration/admin/media_moves_test.rb`

**Interfaces:**
- Consumes: Tasks 2 to 5.
- Produces: `POST /<ADMIN_PATH>/media_folders` (`media_folder[name]`, `media_folder[parent_id]`), `PATCH /media_folders/:id` (name or parent), `DELETE /media_folders/:id`, `POST /media/move` (`asset_ids[]`, `folder` as the place parameter: `"none"` or an id). Turbo Stream answers through responders in `app/controllers/admin/answers/` (`Admin::Answers::FolderSaved`, `FolderRefused`, `ImagesMoved`), the refusal's status `Admin::RefusalStatus`, the toast `Admin::ToastStream`; what each stream replaces is Part two's (the tree's part, the counts, the grid's tiles that left the place).

- [ ] **Step 1: Write the failing tests:**
  - `media_folders_test.rb`: `test "each action is a 403 before any folder is looked up for someone without media.manage"` (an id that names nothing and one that exists answer alike); `test "a refused name answers 422 with the field's sentence and writes nothing"`; `test "delete answers with the folder's parent as the place"`.
  - `media_moves_test.rb`: `test "a move answers the counts and removes the moved tiles from the place they left"`; `test "a refused move answers 422 with the sentence and moves nothing"`; `test "a move needs media.upload or media.manage before anything is read"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** the controllers (gates as `Admin::MediaController`'s, every write through its service, each action ending in `answer(...)`), and the responders drawing only.
- [ ] **Step 4:** run Step 1's files and `test/integration/admin/media_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: the folder and move endpoints`.

---

## Part two: after the cards (D1 to D14)

Each task names the cards it waits for. A component's look, words and markup are the card's; the behaviour and the tests below are the spec's. A new shared component (one more than one screen draws) takes the full `Admin::Ui::Contract`; one the Media screen and its picker template alone draw stays in `Admin::MediaLibrary::` (`test/lib/component_screens_test.rb`'s `SCREENS` and `SCREEN_FILES`).

### Task 9: The folder tree on the Media screen (D1, D2, D3, D4, D14)

**Files:**
- Create: `app/components/admin/media_library/folder_tree_component.rb` and template (rows through `Admin::Ui::TreeItemComponent`, the rows "All media" and "Not in a folder", the counts as trailings), `folder_dialog_component.rb` (create and rename), `delete_folder_dialog_component.rb` (words from `Media::DeleteFolder.preview`)
- Create: `app/javascript/controllers/admin/media/folders_controller.js` (fold, create, rename, delete through `saving/queue.js`)
- Modify: `app/views/admin/media/index.html.erb` (the tree where D1 puts it; the view comment on the tree column rewritten), `config/locales/admin/media_library.en.yml`, `app/components/admin/shell/tree_subjects.rb` and `config/locales/admin/shell.en.yml` (only if D1 uses the shell's column: subject `"media_folders"`), `admin/shared/_tree_glyph` (the folder mark, D14), `test/lib/component_screens_test.rb` (`SCREENS`), `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/components/admin/media_library/folder_tree_component_test.rb`, `test/system/admin/media_folders_test.rb`

- [ ] **Step 1: Write the failing tests:** component: `test "the tree draws All media, Not in a folder and every folder in order with its count, the place selected"`; `test "a viewer without media.manage gets no create, rename or delete"`. Browser (`visit_screen`): `test "a folder is created, renamed and deleted from the keyboard, and the grid follows"`; `test "deleting a folder says what moves where before the press"`; `test "the folds survive a navigation of the grid"`.
- [ ] **Step 2:** run → FAIL. **Step 3:** build to the cards. **Step 4:** run with `test/lib/admin_design_rules_test.rb`, `test/lib/source_layout_test.rb`, `test/lib/admin_i18n_test.rb` → PASS. **Step 5: Commit** `feat: the folder tree on the Media screen`.

### Task 10: Moving images and folders (D5, D6, D7, D8, D9)

**Files:**
- Create: `app/components/admin/media_library/move_dialog_component.rb` and template (the tree as a chooser, "Not in a folder", the current place marked, unreachable folders for a folder move), `selection_bar_component.rb`
- Create: `app/javascript/controllers/admin/media/selection_controller.js` (select mode, the selection held across the grid's frame loads), `app/javascript/controllers/admin/media/move_controller.js` (drag of tiles and folder rows, drop targets, the dialog's submit; every send through `saving/queue.js`)
- Modify: `app/components/admin/media_library/tile_component.rb` (the selection mode's tile per D6), `panel_component.rb` and template (the folder line and "Move to…", D9)
- Test: `test/components/admin/media_library/move_dialog_component_test.rb`, `test/system/admin/media_folders_test.rb`

- [ ] **Step 1: Write the failing tests:** component: `test "a folder move greys itself, its subfolders and folders that would nest too deep"`. Browser: `test "a tile dragged onto a folder moves, and the counts and the grid follow"`; `test "three images selected move with the dialog from the keyboard alone"`; `test "the panel's Move to moves the image and keeps the panel open on it"`; `test "dragging a tile shows no upload overlay"`; `test "a refused move keeps every image where it was and says why"`; `test "a coarse pointer gets the menu and no drag"` (Cuprite's touch emulation, as the tree's test does).
- [ ] **Step 2:** run → FAIL. **Step 3:** build. **Step 4:** run with the design rules and `test/system/admin/media_library_test.rb` → PASS. **Step 5: Commit** `feat: moving images and folders by drag, menu and selection`.

### Task 11: The place's heading and search in a folder (D10, D11)

**Files:**
- Modify: `app/components/admin/media_library/toolbar_component.rb` and template (the place's heading or breadcrumb, the empty folder, "Search all media"), `grid_component.rb` / `tile_component.rb` (a tile's folder in All media, if D11 asks)
- Test: `test/components/admin/media_library/toolbar_component_test.rb`, `test/integration/admin/media_test.rb`

- [ ] **Step 1: Write the failing tests:** `test "a folder's heading is its path and its empty state offers an upload"`; `test "a search in a folder offers the same words in All media"` (the link carries `q` and `filter`, no `folder`).
- [ ] **Step 2–5:** FAIL, build, PASS, **Commit** `feat: where you are in the library, and searching beyond the folder`.

### Task 12: The picker's places (D12)

**Files:**
- Modify: `app/views/admin/media/picker.html.erb` (the places), `app/components/admin/ui/media_picker_component.rb` (its contract's limits: "It browses the library's places and opens at the last one shown, per browser."), `app/javascript/controllers/admin/media/picker_controller.js` (the remembered place: `localStorage` key `cs.media.picker.place`, every read and write in `try`/`catch`; the frame's `src` carries `folder`; Upload goes to the place)
- Test: `test/components/admin/ui/media_picker_component_test.rb`, `test/system/admin/media_picker_test.rb`

- [ ] **Step 1: Write the failing tests:** browser: `test "the picker browses into a folder, and opens there the next time"`; `test "a remembered folder that is gone opens All media and is forgotten"` (Review Focus 5); `test "storage that throws opens All media and the picker still works"` (stub `localStorage.getItem` to throw); `test "an upload in the picker lands in the folder shown"`.
- [ ] **Step 2–5:** FAIL, build, PASS (with the hero's, the Image block's and the rich-text editor's picker tests unchanged), **Commit** `feat: the picker browses folders and opens where you were`.

### Task 13: Live updates on the screen and in the picker (D13)

**Files:**
- Create: `app/javascript/controllers/admin/media/live_controller.js` (subscribes through `live/connection`, fetches the tree's part and the counts at most once per 2 s, keeps the folds and the focus, shows D13's notice when the shown place changed)
- Create: `GET /<ADMIN_PATH>/media/folders` (`Admin::MediaFoldersController#index`, the tree's part and the counts for a `folder`, `media.upload`)
- Modify: `app/views/admin/media/index.html.erb`, `picker.html.erb`, `config/routes.rb`
- Test: `test/integration/admin/media_folders_test.rb`, `test/system/admin/media_folders_test.rb`

- [ ] **Step 1: Write the failing tests:** integration: `test "the tree's part is behind media.upload and lists kept counts"`; browser (two sessions): `test "a folder made in one tab appears in the other without a reload"`; `test "images moved out of the shown folder by another tab leave the grid alone and offer to show the changes"`; `test "the acting tab does not fetch its own change again"`.
- [ ] **Step 2–5:** FAIL, build, PASS (with `test/lib/notes_guards_test.rb`), **Commit** `feat: other tabs follow the library's folders`.

### Task 14: The documents

**Files:**
- Modify: `docs/reference/media.md` (a section "Folders": the table, the tree, places, the services and their locks, the stream, MCP; the Describes line; a rule under "Rules a change can break silently" naming `test/lib/media_folder_writers_test.rb` and the version-bump marks), `docs/reference/trash.md` (a trashed image keeps its folder), `docs/reference/access-control-and-audit.md` (the five actions), `CLAUDE.md` (the media index line names the new files; the rules with no guard from spec §16), `docs/roadmap.md` (Shipped; "Folders and tags" leaves tags; per-folder permissions as a row with spec §13's seam), the spec's "As built", `CHANGELOG.md` (Added)
- Test: `test/lib/source_layout_test.rb` (identifiers named in the documents exist), `test/lib/theming_reference_test.rb` untouched

- [ ] **Step 1:** write the sections; **Step 2:** `bin/rails test test/lib/` → PASS; **Step 3:** `bin/ci` → green; **Step 4: Commit** `docs: media folders`. The pull request's "Documentation" names the guide pages of spec §19.
