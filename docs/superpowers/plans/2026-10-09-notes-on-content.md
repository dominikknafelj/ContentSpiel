# Notes on content — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add notes to CS Studio: threads of short plain-text messages on a page, a post, a block or a library image, with mentions, following, a per-person inbox, resolve, reopen and pin, reactions and files, shown in a drawer in the editors, counted wherever the record appears, and delivered to open tabs at once with a chime and an optional desktop notification for a mention.

**Architecture:** Five tables under `Notes::` (`note_threads`, `note_messages`, `note_follows`, `note_deliveries`, `note_reactions`), each thread naming its subject and, separately, the container whose screen lists it, so one query on `container` reads a page's whole drawer. Every write is an `ApplicationService`; a note never writes the record it is on, and its audit events take the content record as their subject with no text in them. The UI is one `<turbo-frame id="notes">` with two views (the list, and one thread that replaces it), served by a scoped controller (`/notes/<page|post|media>/<id>`) and drawn inside a new right-hand drawer in the editors and inline in the media panel; every part has a stable DOM id and its own GET endpoint, and one Stimulus controller on `<body>` (`admin--notes`) opens the drawer and fills the count markers from one small JSON payload. Live delivery is two Action Cable streams (a person's, a record's) whose signals carry ids only: the browser re-fetches the named part through the same scoped GET, replacing what is read and never what is being typed.

**Tech Stack:** Rails 8.1, Postgres 17, Minitest with fixtures and `ContentHelper`, system tests on Capybara + Cuprite, ViewComponent, Hotwire (Turbo frames, Stimulus) through importmap, Action Cable (Solid Cable in production, the consumer bundled in turbo-rails), Web Audio and the Notifications API, Tailwind v4, Active Storage (Disk) for a note's files, Marcel for type sniffing.

**Spec:** `docs/superpowers/specs/2026-10-09-notes-on-content-design.md` (behaviour) and its build handoff `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (the look). Executors read the spec section each task names, the handoff's part for anything they draw, and the reference file `CLAUDE.md`'s index names for the code they touch.

## Global Constraints

- Work only in `/Users/dknafelj/src/ContentSpiel-notes` on branch `notes-on-content`. Never push, merge or skip a hook. One PR for the whole plan (spec §8).
- Prefix every test command with `PGGSSENCMODE=disable`. System tests: `bin/rails tailwindcss:build` first, then `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system ...`. **Never two test runners at once**: another checkout shares the test databases.
- Tests are Minitest with fixtures (`users(:one)` the owner, `users(:two)` Admin group, `users(:reader)` Read only, `users(:author)`) and `ContentHelper` (`create_page`, `create_post`, `create_media_asset`); no factories, no RSpec. TDD order in every task: failing test, run, implement, run, commit.
- System tests: no fixed `sleep` without `# sleep: <reason>`; wait with `assert_eventually`, `await_js`, `assert_writes_settled`, `await_frames`, `click_frame_link`; a click is `press` or a native `.click`; a JavaScript error fails the test; a control shown only by `hover:` is clicked with `visible: :all`; a resized window is put back in `ensure`. `click_frame_link` is for a link into `#content` only: it waits for the `turbo:load` of the visit Turbo promotes that navigation to, and a link inside `turbo-frame#notes` is never promoted, so it is clicked plainly and followed by an `assert_selector`. `press(label)` finds a button by its text, never by an `aria-label`: an icon-only control (a card's "⋯" menu, a chosen file's "×") is `find("button[aria-label='…']").click`.
- **The look is the handoff's.** Every UI task follows `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` for markup, tokens, sizes and states, and reuses an existing admin component wherever one draws the part already; where the handoff and the spec differ on behaviour, the spec wins (the handoff's own last section lists the known cases). The classes in this plan's templates are a working baseline from the existing tokens: the handoff's replace them where it names its own, and every id and `data-` attribute named in an Interfaces block stays. Accent means one thing: unread and addressed to the viewer. An icon the handoff names is drawn from `app/views/admin/shared/_icon.html.erb`: the first task that needs one adds its `when :name` branch there (Task 6 shows how), and a glyph in this plan's templates (`✎`, `←`, `×`) is the baseline's stand-in for it.
- **Names.** Models and services are `Notes::` (`app/models/notes/`, `app/models/notes.rb`, `app/services/notes/`, `app/queries/notes/`); components are `Admin::NotesScreen::`. **`Admin::Notes` and `Admin::Note` are never defined** (`test/lib/admin_namespace_shadow_test.rb`); the controllers are `Admin::NotesController`, `Admin::NoteThreadsController`, `Admin::NoteMessagesController`, `Admin::NoteMentionsController`, `Admin::NoteInboxController`, `Admin::NoteReactionsController`, `Admin::NoteFilesController`; the channels are `Notes::PersonChannel` and `Notes::RecordChannel`. `Notes::Follow` is the RECORD (`note_follows`); the service that follows and unfollows is `Notes::SetFollowing`. Inside `module Notes` Ruby's own thread class is `::Thread`.
- **A note never writes the record it is on**: no `touch`, no `updated_at`, no `PublicSite.bump_version!`, no `X-Page-Base-Updated-At`. Note forms are ordinary Turbo forms inside `<turbo-frame id="notes">`; none is an `admin--autosave` form and none sits inside one.
- **The content side does not know notes.** `Page`, `Post`, `ContentBlock`, `Media::` and their services never reference `Notes::`, except `Trash::Purge` and `ContentBlocks::Destroy`, which call `Notes::Remove` (`test/lib/notes_boundary_test.rb`, Task 1).
- Every write goes through an `ApplicationService` that calls `authorize!(` and `record_event(` (or says `# audit: none (reason)` in its class body); a controller never writes a record. Each new service gets its `EXPECTED_SERVICES` entry and its factory in `test/support/service_calls.rb` **in the task that creates it**.
- **Audit.** A note event's subject is the content record (page, post, block, image), `snapshot: nil`, metadata only `thread_id` and `message_id`. A note's text, quote and file names never reach `Audit.record`, a log line or a flash. Every recorded action is a literal and has its entry in `Audit::Sentence::NOTE_VERBS` in the same commit (`test/models/audit/sentence_test.rb` fails in both directions).
- **Access.** A thread is never found by its id alone: a controller finds the container first (`admin_scope(Page.all)` / `admin_scope(Post.all)`, or `require_permission("media.upload")` and `Media::Asset.kept`), then the thread among that container's. Outside the scope is 404, never 403. `AccessControl.holds?` is for navigation only.
- Trashed pages, posts and images are hidden explicitly, never by a `default_scope`; every new list or count over them gets a kept-versus-trashed test in `test/integration/trash_visibility_test.rb`.
- Queries are Active Record, then Arel through `SqlNodes`, then SQL with `# sql: <reason>`; a fragment is a named scope or a method of the query object that owns it. A write around callbacks (`delete_all`, `update_all`, `insert_all`, `update_columns`) says `# version: none (reason)` on its line (`test/lib/version_bump_test.rb`).
- Models, queries and services name no component, controller or route (`test/lib/dependency_direction_test.rb`): a query returns data and a route *name*; a component words it and resolves it.
- **Strings.** Every string a person reads is a key in `config/locales/admin/notes.en.yml` (under `en.admin`), read with `t(".key")` in a component, `I18n.t("admin.notes.…")` in a service or controller, `messages(element).t(key)` in a script (keys served by a literal `messages_data(...)` call). Counts use `one:`/`other:`. Every new component, view, controller and script joins `CONVERTED` in `test/lib/admin_i18n_test.rb` in the task that creates it. `Admin::EditorScreen::HeaderComponent` and `Admin::BlockCardComponent` are not on that list; their new strings are keys all the same.
- CS Studio sources use tokens: no hex, `rgb()` or `hsl()`, no `dark:` variant but `dark:scheme-dark`, no `mx-auto`, no `danger` in a translation chip, no inline event handler (`data-action` only). Script-built text goes in with `textContent`, never `innerHTML`.
- **Turbo's morphing page refresh stays off**: no `turbo_refreshes_with`, no `broadcast_refresh`, no `<meta name="turbo-refresh-method">`. The write queue (`app/javascript/autosave/queue.js`) assumes it.
- **Parts are re-fetchable.** Every part of the notes UI keeps the stable DOM id named in its task's Interfaces block and can be fetched again on its own through a scoped GET endpoint. Live delivery (Tasks 12–14) tells a tab only *that* something changed: **a pushed signal carries a kind and ids, never text, a title or a name**, and the tab re-fetches. What is typed (a composer with text, its files, its open picker, an open edit form) is never replaced by a refresh.
- A note's file is served only by `Admin::NoteFilesController#show`; no `rails_blob_path`, `url_for(blob)` or `rails_storage_*` URL for a note's file is ever rendered (Task 16).
- Long comments that record why are the norm in this codebase: every new rule in a model, service or script carries one.
- Commits follow this repo's conventional commits (`feat|fix|ref|style|docs|test|chore: lower-case sentence`) and end with exactly these two trailer lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
- **Order.** Tasks 1–11 are the core and work without push; 12–14 are live delivery; 15 (reactions) and 16 (files) come last and nothing before them depends on them; 17 is the documentation and the full verification.

## Review Focus

Conditions the spec implies and no happy path exercises, most likely to bite first. Each has its test in the task named.

1. **A follower who already has a delivery for the thread's first message** (they were mentioned in it, or the thread was resolved before) **when the thread is resolved or reopened.** They must get the new row in their inbox, not a unique-index error and not nothing. Task 1 (`Notes::Deliveries`), Task 3 (`Notes::Resolve`, `Notes::Reopen`).
2. **A mention typed by hand or forged in the request**, naming a user who may not read the record (`@[<id>]`): refused with a sentence, nothing saved, and that user's inbox shows nothing. Task 2.
3. **A block deleted, or a page purged, while its drawer is open in another tab and a reply is sent**: an ordinary answer inside the drawer ("This note is gone…"), never a 500 and never a thread left behind. Tasks 2, 4 and 6.
4. **A note sent while an autosave is on the wire**: it is sent after the save, exactly once, and the block's `updated_at` and the form's `base_updated_at` are what the save made them. Task 17.
5. **A file whose bytes are not what its name says** (an HTML page named `report.pdf`, an SVG named `logo.png`): refused by what the bytes are; and a stored file is never answered inline unless it is one of the four image types. Task 16.

## File structure

New files, and what each is for:

- `db/migrate/20261009100000_create_notes.rb`: `note_threads`, `note_messages`, `note_deliveries`, `note_follows`. `20261009120000_add_notes_settings_to_users.rb` (Task 14). `20261009130000_create_note_reactions.rb` (Task 15).
- `app/models/notes.rb`: the namespace's entry: subject types, permission keys, `container_for`, `key`, `readable?`, `moderator?`, `readable_threads`, the emoji set.
- `app/models/notes/thread.rb`, `message.rb`, `delivery.rb`, `follow.rb`, `reaction.rb`: the records.
- `app/models/notes/mentions.rb`: the `@[id]` token: ids, tokenize, display.
- `app/models/notes/text.rb`: a body as parts (text, mention, link) for a component to render.
- `app/models/notes/deliveries.rb`: who follows a thread, and who is told about a message, a reply, a resolve and a reopen.
- `app/models/notes/signals.rb` (Task 12): what is pushed, after commit, ids only.
- `app/models/notes/files.rb` (Task 16): the allowed types and the sniff.
- `app/services/notes/authorization.rb` and `start.rb`, `reply.rb`, `edit_message.rb`, `delete_message.rb`, `resolve.rb`, `reopen.rb`, `pin.rb`, `unpin.rb`, `set_following.rb`, `mark_read.rb`, `remove.rb`, `react.rb`; `app/services/users/update_notifications.rb`.
- `app/channels/application_cable/channel.rb`, `app/channels/notes/person_channel.rb`, `record_channel.rb`.
- `app/queries/notes/counts.rb`, `listing.rb`; `app/queries/dashboard/notes_for_you.rb`, `open_threads.rb`.
- `app/controllers/concerns/admin/note_container.rb`, `app/helpers/admin/note_paths_helper.rb`, and the seven controllers named above with `app/views/admin/notes/` and `app/views/admin/note_inbox/`.
- `app/components/admin/notes_screen/`: `drawer`, `list`, `thread_row`, `thread`, `message`, `body`, `composer`, `counts`, `marker`, `inbox_row`, `open_thread_row`, `reactions`, `files` components.
- `app/javascript/controllers/admin/notes_controller.js` (the drawer, the markers, the counts), `note_composer_controller.js` (drafts, send key, mention picker, emoji, chosen files), `notes_live_controller.js` (the cable, the refreshes, the toast), `notes_alert_controller.js` (the chime, the desktop notification), `notes_permission_controller.js`, `note_gif_controller.js`; `app/javascript/mind_graph/card_notes.js`.
- `config/locales/admin/notes.en.yml`.
- `test/lib/notes_boundary_test.rb`.
- `docs/reference/notes.md`.

Changed files that carry most of the work: `config/routes.rb`, `app/models/audit/sentence.rb`, `app/queries/dashboard/feed.rb`, `app/queries/dashboard/activity.rb`, `app/services/trash/purge.rb`, `app/services/content_blocks/destroy.rb`, `app/components/admin/editor_screen/header_component.*`, `app/components/admin/block_card_component.html.erb`, `app/components/admin/editor_screen/block_tile_component.html.erb`, `app/components/admin/media_library/{panel,tile,grid}_component.*`, `app/components/admin/posts_screen/table_component.*`, `app/components/admin/tree_component.rb`, `app/components/admin/tree_node_component.*`, `app/components/admin/shell/sidebar_component.*`, `app/views/admin/dashboard/show.html.erb`, `app/queries/post_graph/builder.rb`, `app/javascript/mind_graph/{card,renderer,app}.js`, `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`.

## Stable ids and their endpoints (the whole plan uses these)

| Part | DOM id | Fetched again by |
|---|---|---|
| The notes frame | `turbo-frame#notes` | `GET admin_record_notes_path(type, id)` |
| The list view | `#notes-list[data-notes-view=list]` | the same |
| One group of threads | `#notes-group-<key>` | the same |
| One thread's row in the list | `a#note-row-<thread id>` | the list |
| The thread view (replaces the list in `turbo-frame#notes`) | `#note-thread-<thread id>[data-notes-view=thread]`, its parts `#note-thread-<id>-messages` and `#note-thread-<id>-reply` | `GET admin_record_note_thread_path(type, id, thread)` |
| One message | `#note-message-<message id>` | its thread |
| The resolved threads | `turbo-frame#notes-resolved` | `GET admin_resolved_record_notes_path(type, id)` |
| The counts of one record | `#notes-counts` | `GET admin_record_note_counts_path(type, id)` (JSON) |
| A count marker | `#notes-marker-<key>` | filled from the counts |
| The header's button and its count | `#notes-open`, `#notes-open-count` | filled from the counts |
| The drawer | `aside#notes-drawer` | not fetched: it holds the frame |
| The sidebar's badges | `#sidebar-badge-dashboard`, `#sidebar-badge-trash` | `GET admin_unread_notes_path` (JSON) |
| "Notes for you" | `turbo-frame#notes-for-you` | `GET admin_notes_card_path` |
| One delivery, as data | (the toast) | `GET admin_note_delivery_path(id)` (JSON) |
| "Open threads" | `turbo-frame#notes-open-threads` | `GET admin_open_note_threads_path` |

`type` is `page`, `post` or `media`; `<key>` is `Notes.key(record)`: the class name without colons, a dash, the id (`Page-3`, `ContentBlock-12`, `MediaAsset-5`).

---
### Task 1: The data layer — threads, messages, follows, deliveries, mentions, and the boundary guard

**Spec:** §3.1, §3.2 (the token), §3.3 (following and deliveries, D17), §3.4 (the keys). **Read first:** `docs/reference/access-control-and-audit.md` ("The decision point"), `app/models/media/asset.rb` lines 1–60 (how a namespaced model names its table), `test/lib/dependency_direction_test.rb`.

After this task the four tables and their models exist and the rules that need no actor are pinned: the container rule, mention parsing, who follows a thread and who is told. Nothing writes a note yet.

**Files:**
- Create: `db/migrate/20261009100000_create_notes.rb`, `app/models/notes.rb`, `app/models/notes/thread.rb`, `app/models/notes/message.rb`, `app/models/notes/delivery.rb`, `app/models/notes/follow.rb`, `app/models/notes/mentions.rb`, `app/models/notes/text.rb`, `app/models/notes/deliveries.rb`, `test/lib/notes_boundary_test.rb`
- Modify: `db/schema.rb` (by the migration)
- Test: `test/models/notes/thread_test.rb`, `test/models/notes/message_test.rb`, `test/models/notes/mentions_test.rb`, `test/models/notes/text_test.rb`, `test/models/notes/deliveries_test.rb`, `test/models/notes_test.rb` (all new)

**Interfaces:**
- Produces:
  - Tables `note_threads`, `note_messages`, `note_deliveries`, `note_follows` as in Step 3.
  - `Notes::SUBJECT_TYPES`, `Notes::EMOJI` (30 strings), `Notes.container_for(subject) -> Page | Post | Media::Asset`, `Notes.read_key(container) -> String`, `Notes.moderate_key(container) -> String`, `Notes.key(record) -> String` and `Notes.key(type, id) -> String` (`"ContentBlock-12"`, `"MediaAsset-5"`), `Notes.readable?(actor, container, channel: Current.channel) -> Boolean`, `Notes.moderator?(actor, container, channel: Current.channel) -> Boolean`, `Notes.readable_threads(actor, channel: Current.channel) -> ActiveRecord::Relation<Notes::Thread>`.
  - `Notes::Thread` (`subject`, `container`, `created_by`, `resolved_by`, `pinned_by`, `messages` ordered oldest first; scopes `unresolved`, `resolved`, `pinned`, `unpinned`; `#open?`, `#resolved?`, `#first_message`; constants `STATES`, `ORIGIN_VIEWS`, `MAX_QUOTE = 500`).
  - `Notes::Message` (`thread`, `author`, `body`, `mentioned_user_ids` derived before validation, `edited_at`; `MAX_BODY = 4_000`).
  - `Notes::Delivery` (`user`, `message`, `thread`, `reason`, `read_at`; `REASONS = %w[mention reply resolved reopened]`; scope `unread`).
  - `Notes::Follow` (the RECORD: `thread`, `user`, `following`; table `note_follows`). The service that presses the button is `Notes::SetFollowing` (Task 3), because one constant can't be both.
  - `Notes::Mentions::TOKEN`, `.ids(body) -> Array<Integer>`, `.tokenize(text, names) -> String`, `.display(body, users_by_id) -> [String, Hash]`.
  - `Notes::Text.parts(body) -> Array<Notes::Text::Part(kind, value)>`, kinds `:text` (String), `:mention` (Integer user id), `:link` (String URL).
  - `Notes::Deliveries.for_new_message(message, actor_user:)`, `.for_edit(message, newly_mentioned:, actor_user:)`, `.for_state(thread, reason, actor_user:)` (`reason` is `"resolved"` or `"reopened"`), each `-> Array<Notes::Delivery>`; `.followers(thread) -> Array<Integer>`; `.follow(thread, author_id:, mentioned_ids:)`. The first two apply the following rules themselves before they write rows.

- [ ] **Step 1: Write the failing tests.**

`test/models/notes/thread_test.rb`:

```ruby
require "test_helper"

class Notes::ThreadTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
  end

  def thread_on(subject, **attributes)
    Notes::Thread.create!({ subject: subject, created_by: users(:one), last_message_at: Time.current }.merge(attributes))
  end

  test "a thread on a block is listed by the block's page; any other subject is its own container" do
    post = create_post(title: "Hello")
    asset = create_media_asset

    assert_equal @page, thread_on(@block).container
    assert_equal @page, thread_on(@page).container
    assert_equal post, thread_on(post).container
    assert_equal asset, thread_on(asset).container
    assert_equal "Media::Asset", thread_on(asset).container_type
  end

  test "the container is derived, never taken from the caller" do
    other = create_page(title: "Elsewhere")

    assert_equal @page, thread_on(@block, container: other).container
  end

  test "only a page, a post, a block or a library image takes a note" do
    thread = Notes::Thread.new(subject: Tag.create!(name: "news"), last_message_at: Time.current)

    assert_not thread.valid?
    assert_includes thread.errors[:subject_type], "is not included in the list"
  end

  test "state, origin and quote are checked" do
    assert_not Notes::Thread.new(subject: @page, state: "closed", last_message_at: Time.current).valid?
    assert_not Notes::Thread.new(subject: @page, origin_view: "email", last_message_at: Time.current).valid?
    assert_not Notes::Thread.new(subject: @page, quote: "x" * 501, last_message_at: Time.current).valid?
    assert Notes::Thread.new(subject: @page, quote: "x" * 500, origin_view: "mind_graph", last_message_at: Time.current).valid?
  end

  test "scopes split the threads of a container" do
    open = thread_on(@page)
    pinned = thread_on(@block, pinned: true, pinned_at: Time.current)
    done = thread_on(@page, state: "resolved", resolved_at: Time.current)

    assert_equal [ open, pinned ].sort_by(&:id), Notes::Thread.where(container: @page).unresolved.order(:id).to_a
    assert_equal [ done ], Notes::Thread.where(container: @page).resolved.to_a
    assert_equal [ pinned ], Notes::Thread.pinned.to_a
    assert_equal [ open, done ].sort_by(&:id), Notes::Thread.unpinned.order(:id).to_a
  end

  test "deleting a thread's author leaves the thread; deleting the thread takes its messages and deliveries" do
    writer = User.create!(email_address: "writer@example.com", password: "a-long-password-1")
    thread = thread_on(@page, created_by: writer)
    message = thread.messages.create!(author: writer, body: "Hello")
    Notes::Delivery.create!(user: users(:two), message: message, thread: thread, reason: "reply")
    Notes::Follow.create!(user: users(:two), thread: thread, following: true)

    writer.destroy!
    assert_nil thread.reload.created_by_id
    assert_nil message.reload.author_id

    thread.destroy!
    assert_equal 0, Notes::Message.count
    assert_equal 0, Notes::Delivery.count
    assert_equal 0, Notes::Follow.count
  end
end
```

`test/models/notes/message_test.rb`:

```ruby
require "test_helper"

class Notes::MessageTest < ActiveSupport::TestCase
  setup do
    @thread = Notes::Thread.create!(subject: create_page(title: "Pricing"), last_message_at: Time.current)
  end

  test "a body is 1 to 4,000 characters" do
    assert_not @thread.messages.build(body: "  ").valid?
    assert_not @thread.messages.build(body: "x" * 4_001).valid?
    assert @thread.messages.build(body: "x" * 4_000).valid?
  end

  test "the mentioned ids are read from the body on every save" do
    message = @thread.messages.create!(author: users(:one), body: "Ask @[#{users(:two).id}] and @[#{users(:reader).id}], then @[#{users(:two).id}] again")
    assert_equal [ users(:two).id, users(:reader).id ], message.mentioned_user_ids

    message.update!(body: "Nobody now")
    assert_equal [], message.reload.mentioned_user_ids
  end

  test "an emoji and a line break are kept as typed" do
    message = @thread.messages.create!(author: users(:one), body: "Looks good 👍\nShip it")

    assert_equal "Looks good 👍\nShip it", message.reload.body
  end

  test "a delivery is one per person and message, and goes with its user" do
    message = @thread.messages.create!(author: users(:one), body: "Hello")
    reader = User.create!(email_address: "told@example.com", password: "a-long-password-1")
    Notes::Delivery.create!(user: reader, message: message, thread: @thread, reason: "mention")

    assert_raises(ActiveRecord::RecordNotUnique) do
      Notes::Delivery.transaction(requires_new: true) { Notes::Delivery.create!(user: reader, message: message, thread: @thread, reason: "reply") }
    end
    assert_not Notes::Delivery.new(user: reader, message: message, thread: @thread, reason: "poke").valid?

    reader.destroy!
    assert_equal 0, Notes::Delivery.count
  end
end
```

`test/models/notes/mentions_test.rb`:

```ruby
require "test_helper"

class Notes::MentionsTest < ActiveSupport::TestCase
  test "ids are the token's numbers, once each, in order" do
    assert_equal [ 7, 3 ], Notes::Mentions.ids("@[7] and @[3] and @[7]")
    assert_equal [], Notes::Mentions.ids("mail me @home or @[abc] or @ [4]")
    assert_equal [], Notes::Mentions.ids(nil)
  end

  test "tokenize turns the names the picker inserted into tokens, the longest name first" do
    names = { "Dana" => 4, "Dana Smith" => 9 }

    assert_equal "Ask @[9], not @[4].", Notes::Mentions.tokenize("Ask @Dana Smith, not @Dana.", names)
  end

  test "tokenize ignores a name whose id is not a number and a text with no such name" do
    assert_equal "Hi @Dana", Notes::Mentions.tokenize("Hi @Dana", { "Dana" => "4; DROP" })
    assert_equal "Hi there", Notes::Mentions.tokenize("Hi there", { "Dana" => 4 })
    assert_equal "", Notes::Mentions.tokenize(nil, {})
  end

  test "display is the reverse, for the edit form, and leaves a deleted user's token alone" do
    dana = users(:two).tap { |user| user.update!(name: "Dana") }

    text, names = Notes::Mentions.display("Ask @[#{dana.id}] or @[999999]", { dana.id => dana })

    assert_equal "Ask @Dana or @[999999]", text
    assert_equal({ "Dana" => dana.id }, names)
  end
end
```

`test/models/notes/text_test.rb`:

```ruby
require "test_helper"

class Notes::TextTest < ActiveSupport::TestCase
  def parts(body) = Notes::Text.parts(body).map { |part| [ part.kind, part.value ] }

  test "plain text is one part" do
    assert_equal [ [ :text, "Just words <b>not markup</b>" ] ], parts("Just words <b>not markup</b>")
    assert_equal [], parts("")
  end

  test "a mention and a link are parts of their own" do
    assert_equal [ [ :text, "Ask " ], [ :mention, 12 ], [ :text, " about " ], [ :link, "https://example.com/a?b=1" ], [ :text, "." ] ],
      parts("Ask @[12] about https://example.com/a?b=1.")
  end

  test "punctuation after a link stays text, and a link can end the body" do
    assert_equal [ [ :text, "(see " ], [ :link, "http://example.com/x" ], [ :text, ")" ] ], parts("(see http://example.com/x)")
    assert_equal [ [ :link, "https://example.com" ] ], parts("https://example.com")
  end

  test "only http and https become links" do
    assert_equal [ [ :text, "javascript:alert(1) and ftp://x.test" ] ], parts("javascript:alert(1) and ftp://x.test")
  end
end
```

`test/models/notes/deliveries_test.rb`:

```ruby
require "test_helper"

class Notes::DeliveriesTest < ActiveSupport::TestCase
  setup do
    @dana, @eli, @fay = %w[dana eli fay].map { |name| User.create!(email_address: "#{name}@example.com", password: "a-long-password-1") }
    @thread = Notes::Thread.create!(subject: create_page(title: "Pricing"), created_by: @dana, last_message_at: Time.current)
  end

  def message(author, body) = @thread.messages.create!(author: author, body: body)

  # A message as a service would send it: the rows it tells.
  def send_message(author, body) = Notes::Deliveries.for_new_message(message(author, body), actor_user: author)

  def told(rows) = rows.map { |row| [ row.user_id, row.reason ] }.sort

  def following = Notes::Follow.where(thread: @thread, following: true).pluck(:user_id).sort

  test "the first message tells the people it mentions, never its author, and both now follow" do
    rows = send_message(@dana, "Hi @[#{@eli.id}] and me, @[#{@dana.id}]")

    assert_equal [ [ @eli.id, "mention" ] ], told(rows)
    assert_equal [ @thread.id ], rows.map(&:thread_id).uniq
    assert_equal [ @dana.id, @eli.id ].sort, following
  end

  test "a reply tells every follower; a mention wins over a reply" do
    send_message(@dana, "Hi @[#{@eli.id}]")

    assert_equal [ [ @dana.id, "mention" ], [ @eli.id, "reply" ] ].sort, told(send_message(@fay, "Sure, @[#{@dana.id}]"))
    assert_equal [ @dana.id, @eli.id, @fay.id ].sort, following
  end

  test "an explicit unfollow is kept when that person writes again, and undone when they are mentioned" do
    send_message(@dana, "Start")
    send_message(@eli, "Hello")
    Notes::Follow.find_by!(thread: @thread, user: @eli).update!(following: false)

    assert_equal [ [ @dana.id, "reply" ] ], told(send_message(@eli, "Still not following"))
    assert_equal [ @dana.id ], following
    assert_equal [], told(send_message(@dana, "Nobody is told: Eli stopped following"))

    assert_equal [ [ @eli.id, "mention" ] ], told(send_message(@dana, "Back to you, @[#{@eli.id}]"))
    assert_equal [ @dana.id, @eli.id ].sort, following
  end

  test "a mentioned user who no longer exists is skipped and follows nothing" do
    gone = User.create!(email_address: "gone@example.com", password: "a-long-password-1")
    gone_id = gone.id
    gone.destroy!

    assert_equal [], told(send_message(@dana, "Hi @[#{gone_id}]"))
    assert_equal [ @dana.id ], following
  end

  test "an edit tells only the newly mentioned, who now follow, and turns a reply row for that message into a mention" do
    send_message(@dana, "Start")
    reply = message(@eli, "Hello")
    Notes::Deliveries.for_new_message(reply, actor_user: @eli)
    Notes::Delivery.where(user: @dana).update_all(read_at: Time.current) # version: none (a test's own setup)

    rows = Notes::Deliveries.for_edit(reply, newly_mentioned: [ @dana.id, @fay.id ], actor_user: @eli)

    assert_equal [ [ @dana.id, "mention" ], [ @fay.id, "mention" ] ].sort, told(rows)
    assert_equal 1, Notes::Delivery.where(user: @dana, message: reply).count
    assert_nil Notes::Delivery.find_by(user: @dana, message: reply).read_at
    assert_includes following, @fay.id
  end

  # Review Focus 1: the row for this person and the first message exists already.
  test "a resolve and a reopen tell the followers on the first message, reusing the row that is already there" do
    first = message(@dana, "Hi @[#{@eli.id}]")
    Notes::Deliveries.for_new_message(first, actor_user: @dana)
    send_message(@fay, "Done")
    Notes::Delivery.where(user: @eli).update_all(read_at: 1.hour.ago) # version: none (a test's own setup)

    rows = Notes::Deliveries.for_state(@thread, "resolved", actor_user: @fay)

    assert_equal [ [ @dana.id, "resolved" ], [ @eli.id, "resolved" ] ].sort, told(rows)
    assert_equal [ first.id ], rows.map(&:message_id).uniq
    assert_equal 1, Notes::Delivery.where(user: @eli, message: first).count
    assert_nil Notes::Delivery.find_by(user: @eli, message: first).read_at

    again = Notes::Deliveries.for_state(@thread, "reopened", actor_user: @dana)

    assert_equal [ [ @eli.id, "reopened" ], [ @fay.id, "reopened" ] ].sort, told(again)
    assert_equal 1, Notes::Delivery.where(user: @eli, message: first).count
  end

  test "someone who stopped following is not told of a resolve" do
    send_message(@dana, "Start")
    send_message(@eli, "Hello")
    Notes::Follow.find_by!(thread: @thread, user: @dana).update!(following: false)

    assert_equal [], told(Notes::Deliveries.for_state(@thread, "resolved", actor_user: @eli))
  end
end
```

`test/models/notes_test.rb`:

```ruby
require "test_helper"

class NotesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    @nobody = User.create!(email_address: "nobody@example.com", password: "a-long-password-1")
  end

  def thread_on(subject) = Notes::Thread.create!(subject: subject, last_message_at: Time.current)

  test "a key is the class without colons and the id" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_equal "Page-#{@page.id}", Notes.key(@page)
    assert_equal "ContentBlock-#{block.id}", Notes.key(block)
    assert_equal "MediaAsset-#{@asset.id}", Notes.key(@asset)
    assert_equal "MediaAsset-5", Notes.key("Media::Asset", 5)
  end

  test "the keys follow the container" do
    assert_equal %w[pages.read posts.read media.upload], [ @page, @post, @asset ].map { |record| Notes.read_key(record) }
    assert_equal %w[pages.edit posts.edit media.manage], [ @page, @post, @asset ].map { |record| Notes.moderate_key(record) }
  end

  test "a reader reads and does not moderate; an uploader moderates their own image; a stranger does neither" do
    assert Notes.readable?(users(:reader), @page, channel: :admin)
    assert_not Notes.moderator?(users(:reader), @page, channel: :admin)
    assert Notes.moderator?(users(:two), @page, channel: :admin)
    assert_not Notes.readable?(@nobody, @page, channel: :admin)
    assert_not Notes.readable?(@nobody, @asset, channel: :admin)

    @asset.update_columns(created_by_id: users(:author).id)
    AccessControl::Grant.create!(group: access_control_groups(:author), permission: "media.upload", scope: {}) unless AccessControl.holds?(users(:author), "media.upload", channel: :admin)
    assert Notes.moderator?(users(:author), @asset, channel: :admin)
    assert_not Notes.moderator?(users(:author), create_media_asset, channel: :admin)
  end

  test "readable_threads hides what the actor can't read and what is in the trash" do
    kept = [ thread_on(@page), thread_on(@post), thread_on(@asset) ]
    gone_page = create_page(title: "Gone")
    gone = thread_on(gone_page)
    gone_page.update!(trashed_at: Time.current)

    assert_equal kept.map(&:id).sort, Notes.readable_threads(users(:one), channel: :admin).pluck(:id).sort
    assert_not_includes Notes.readable_threads(users(:one), channel: :admin), gone
    assert_empty Notes.readable_threads(@nobody, channel: :admin)
    # Read only reads pages and posts and holds no media right.
    assert_equal kept.first(2).map(&:id).sort, Notes.readable_threads(users(:reader), channel: :admin).pluck(:id).sort
  end
end
```

(If `test/fixtures/access_control/grants.yml` already gives the Author group `media.upload`, the `Grant.create!` line is skipped by its own guard; if `Read only` holds `media.upload` there, change the last assertion's expectation to all three threads and say so in the task report.)

`test/lib/notes_boundary_test.rb`:

```ruby
require "test_helper"

# The content side does not know notes (notes spec §3.7, plan Global
# Constraints). A page, a post, a block and a library image are written and
# read without a thought for the threads on them: no `touch`, no count column,
# no association. Notes point at content, never the other way, so the feature
# can be changed or pushed live without re-reading the content services.
#
# The one exception is removal: what deletes a record for good calls
# `Notes::Remove`, because the reference is polymorphic and no foreign key
# could. Those call sites are listed in ALLOWED with their reason, may name
# nothing of `Notes::` but `Remove`, and an entry that matches nothing fails.
class NotesBoundaryTest < ActiveSupport::TestCase
  CONTENT_SOURCES = %w[
    app/models/page.rb app/models/page/**/*.rb app/models/post.rb app/models/post/**/*.rb app/models/content_block.rb
    app/models/media.rb app/models/media/**/*.rb app/models/concerns/**/*.rb
    app/models/block_types.rb app/models/block_types/**/*.rb app/models/content_types.rb app/models/content_types/**/*.rb
    app/services/pages/**/*.rb app/services/posts/**/*.rb app/services/content_blocks/**/*.rb app/services/media/**/*.rb
    app/services/trash/**/*.rb app/services/tags/**/*.rb app/services/translations/**/*.rb app/services/starter_contents/**/*.rb
  ].freeze

  # path => why it may name `Notes::Remove`.
  ALLOWED = {}.freeze

  REFERENCE = /(?<![A-Za-z0-9_:])(?:::)?Notes::(?<name>[A-Z]\w*)/

  def self.references(source)
    source.lines.each_with_index.flat_map do |line, index|
      next [] if line.lstrip.start_with?("#")

      line.sub(/\s#\s.*\z/, "").to_enum(:scan, REFERENCE).map { [ index + 1, Regexp.last_match[:name] ] }
    end
  end

  def sources = CONTENT_SOURCES.flat_map { |pattern| Dir[Rails.root.join(pattern)] }.uniq.sort

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  test "the guard is looking at the code" do
    assert_operator sources.size, :>, 30
    assert_includes sources.map { |path| relative(path) }, "app/services/trash/purge.rb"
    assert_includes sources.map { |path| relative(path) }, "app/models/content_block.rb"
  end

  test "pages, posts, blocks, images and their services name nothing of Notes" do
    offences = sources.flat_map do |path|
      self.class.references(File.read(path)).filter_map do |line, name|
        next if ALLOWED.key?(relative(path)) && name == "Remove"

        "#{relative(path)}:#{line}: Notes::#{name}"
      end
    end

    assert_empty offences, "Content code must not reach into notes. A note points at content; removal on a permanent delete is " \
                           "the one call the other way, and its call site belongs in ALLOWED with its reason."
  end

  test "every allowance still matches something and says why" do
    ALLOWED.each do |path, reason|
      assert_operator reason.length, :>, 40, "#{path} needs its reason written out"
      names = self.class.references(Rails.root.join(path).read).map(&:last)
      assert_includes names, "Remove", "#{path} no longer calls Notes::Remove: delete its ALLOWED entry"
    end
  end

  test "the pattern finds a reference and nothing that only looks like one" do
    found = self.class.references(<<~RUBY).map(&:last)
      # Notes::InAComment
      Notes::Remove.call(page) # and Notes::AfterCode
      ::Notes::Thread.where(subject: page)
      ReleaseNotes::Entry.new
      footnotes = "Notes: none"
    RUBY

    assert_equal %w[Remove Thread], found
  end
end
```

- [ ] **Step 2: Run them, expect failure** (`NameError: uninitialized constant Notes`; the boundary test alone passes):
`PGGSSENCMODE=disable bin/rails test test/models/notes test/models/notes_test.rb test/lib/notes_boundary_test.rb`

- [ ] **Step 3: The migration.** `db/migrate/20261009100000_create_notes.rb`:

```ruby
# Notes on content (notes spec §3.1): a thread on a page, a post, a block or a
# library image, its messages, and one delivery row per person told about a
# message (the inbox). `subject` and `container` are polymorphic, so they have
# no foreign key: `Notes::Remove` deletes a record's threads when the record is
# deleted for good. `container` is the record whose screen lists the thread --
# the page for a block -- so one indexed read serves a page's whole drawer.
# The user references are nullified with the user (a note outlives its author,
# shown as "a deleted user"); a delivery belongs to its reader and goes with
# them, and so does a follow (`note_follows`: `following: false` is an
# explicit unfollow, no row means never involved, decision D17). Reactions get
# their own table in a later migration.
class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :note_threads do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :container_type, null: false
      t.bigint :container_id, null: false
      t.string :state, null: false, default: "open"
      t.datetime :resolved_at
      t.references :resolved_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.boolean :pinned, null: false, default: false
      t.datetime :pinned_at
      t.references :pinned_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :quote
      t.string :origin_view, null: false, default: "editor"
      t.string :origin_locale
      t.references :created_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :last_message_at, null: false
      t.timestamps

      t.index %i[container_type container_id state]
      t.index %i[subject_type subject_id]
      t.check_constraint "state IN ('open', 'resolved')", name: "note_threads_state"
    end

    create_table :note_messages do |t|
      t.references :thread, null: false, foreign_key: { to_table: :note_threads, on_delete: :cascade }
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :body, null: false
      t.bigint :mentioned_user_ids, array: true, null: false, default: []
      t.datetime :edited_at
      t.timestamps
    end

    create_table :note_deliveries do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { to_table: :note_messages, on_delete: :cascade }
      t.references :thread, null: false, foreign_key: { to_table: :note_threads, on_delete: :cascade }
      t.string :reason, null: false
      t.datetime :read_at
      t.timestamps

      t.index %i[user_id message_id], unique: true
      t.index %i[user_id read_at]
    end

    create_table :note_follows do |t|
      t.references :thread, null: false, index: false, foreign_key: { to_table: :note_threads, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :following, null: false, default: true
      t.timestamps

      t.index %i[thread_id user_id], unique: true
    end
  end
end
```

Run `bin/rails db:migrate` and `PGGSSENCMODE=disable bin/rails db:test:prepare`. `db/schema.rb` must show the four tables, `on_delete: :cascade` on the three thread keys and on the delivery's and the follow's user keys, and `on_delete: :nullify` on the four other user keys.

- [ ] **Step 4: The namespace.** `app/models/notes.rb`:

```ruby
# Notes on content (notes spec): threads of short messages on a page, a post,
# a block or a library image. This file is the namespace's entry: what the
# models, the services, the queries and the components all ask about a note's
# place -- which record lists it, which permission reads and moderates it,
# what it is called in a DOM id.
#
# Notes FOLLOW the content (decision D3): whoever may read a record in CS
# Studio may read and write its notes, and whoever may edit it may moderate
# them. There is no permission of their own, so everything here is asked of
# `AccessControl` with the container's own keys.
#
# Inside this module `Thread` is `Notes::Thread`; Ruby's own is `::Thread`.
module Notes
  SUBJECT_TYPES = %w[Page Post ContentBlock Media::Asset].freeze

  # A library image has no per-image read right: `media.upload` is what opens
  # the library (`Admin::MediaController`).
  READ_KEYS = { "Page" => "pages.read", "Post" => "posts.read", "Media::Asset" => "media.upload" }.freeze
  # `edit`, not `edit` plus `publish`: a note changes nothing a visitor sees.
  MODERATE_KEYS = { "Page" => "pages.edit", "Post" => "posts.edit", "Media::Asset" => "media.manage" }.freeze

  # The composer's emoji popover and the reactions offer the same small set
  # (spec §4.2); the operating system's own picker works in the field as
  # anywhere. `Notes::React` accepts these and nothing else.
  EMOJI = %w[👍 👎 ✅ ❌ ❤️ 🎉 🙏 👀 🤔 😀 😅 😂 😍 😮 😢 😡 🔥 ⭐ 💡 ❓ ❗ ⏳ 🚀 📌 📝 🔗 🖼️ 🐛 💬 👋].freeze

  class << self
    # The record whose screen lists a thread on `subject`: a block's owner (a
    # page today), anything else itself. A block that moves between a
    # section's columns keeps its page, so its threads need no update.
    def container_for(subject) = subject.is_a?(ContentBlock) ? subject.owner : subject

    def read_key(container) = READ_KEYS.fetch(container.class.polymorphic_name)

    def moderate_key(container) = MODERATE_KEYS.fetch(container.class.polymorphic_name)

    # "ContentBlock-12", "MediaAsset-5": a record's name in a DOM id, a
    # `data-` attribute and the counts payload. No colon, so it needs no
    # escaping in a CSS selector.
    def key(record_or_type, id = nil)
      type = id ? record_or_type.to_s : record_or_type.class.polymorphic_name
      "#{type.delete(":")}-#{id || record_or_type.id}"
    end

    def readable?(actor, container, channel: Current.channel)
      AccessControl.allowed?(actor, read_key(container), container, channel:)
    end

    # Delete someone else's note, pin and unpin. An image's uploader stands in
    # for `media.manage` with `media.upload` alone, as for the image itself
    # (`Media::Ownership`, whose rule the services apply through `authorize!`;
    # this is the same rule for a component deciding which buttons to draw).
    def moderator?(actor, container, channel: Current.channel)
      return true if AccessControl.allowed?(actor, moderate_key(container), container, channel:)
      return false unless container.is_a?(Media::Asset)

      user = actor.is_a?(ApiToken) ? actor.user : actor
      user.present? && container.created_by_id == user.id && AccessControl.allowed?(actor, "media.upload", container, channel:)
    end

    # Every thread the actor may read, as one relation: the threads whose
    # container is a readable page or post (`AccessControl.scope`, which also
    # hides the trash) or, for a `media.upload` holder, a kept image. A branch
    # is only added when the actor holds the right at all, like
    # `Dashboard::Activity#readable_subjects`. The inbox, "Open threads" and
    # the sidebar's count all narrow through here, so a person who loses a
    # right stops seeing what was addressed to them without a row changing.
    def readable_threads(actor, channel: Current.channel)
      branches = { "Page" => Page, "Post" => Post }.filter_map do |type, model|
        next unless AccessControl.holds?(actor, READ_KEYS.fetch(type), channel:)

        readable = AccessControl.scope(actor, READ_KEYS.fetch(type), model.all, channel:).unscope(:order).select(:id)
        Thread.where(container_type: type, container_id: readable)
      end
      if AccessControl.holds?(actor, "media.upload", channel:)
        branches << Thread.where(container_type: "Media::Asset", container_id: Media::Asset.kept.select(:id))
      end
      branches.reduce(:or) || Thread.none
    end
  end
end
```

- [ ] **Step 5: The records.** `app/models/notes/thread.rb`:

```ruby
module Notes
  # One conversation on one record (notes spec §3.1, decision D1): it can be
  # replied to, resolved, reopened and pinned. Its first message is the note
  # that started it; a thread with no message does not exist
  # (`Notes::DeleteMessage` deletes the thread with its last one).
  #
  # `subject` is what the thread is about. `container` is the record whose
  # screen lists it and whose permissions it follows -- for a block, the
  # block's page. It is DERIVED here from the subject on every save, never
  # taken from a caller: a thread filed under a page its block does not belong
  # to would be readable by the wrong people.
  #
  # Both references are polymorphic, so there is no foreign key and no
  # `has_many` on the content side (`test/lib/notes_boundary_test.rb`):
  # `Notes::Remove` deletes a record's threads when the record goes for good.
  # A trashed record keeps its threads; every read narrows through the read
  # scope, which hides the trash.
  class Thread < ApplicationRecord
    self.table_name = "note_threads"

    STATES = %w[open resolved].freeze
    # Where the thread was started. Context only ("written on German"), never
    # used to decide where a thread appears.
    ORIGIN_VIEWS = %w[editor mind_graph media list].freeze
    MAX_QUOTE = 500

    belongs_to :subject, polymorphic: true
    belongs_to :container, polymorphic: true
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :resolved_by, class_name: "User", optional: true
    belongs_to :pinned_by, class_name: "User", optional: true
    # Oldest first: the order a thread is read in. `dependent: :destroy` so a
    # message's own callbacks run (its files are purged, Task 16); the
    # deliveries and reactions go by their foreign keys.
    has_many :messages, -> { order(:created_at, :id) }, class_name: "Notes::Message", foreign_key: :thread_id,
      inverse_of: :thread, dependent: :destroy

    before_validation :derive_container

    validates :subject_type, inclusion: { in: SUBJECT_TYPES }
    validates :state, inclusion: { in: STATES }
    validates :origin_view, inclusion: { in: ORIGIN_VIEWS }
    validates :quote, length: { maximum: MAX_QUOTE }
    validates :last_message_at, presence: true

    # Not `open`: `Kernel#open` is a method of every class.
    scope :unresolved, -> { where(state: "open") }
    scope :resolved, -> { where(state: "resolved") }
    scope :pinned, -> { where(pinned: true) }
    scope :unpinned, -> { where(pinned: false) }

    def open? = state == "open"

    def resolved? = state == "resolved"

    def first_message = messages.first

    private

    def derive_container
      self.container = Notes.container_for(subject) if subject
    end
  end
end
```

`app/models/notes/message.rb`:

```ruby
module Notes
  # One message of a thread: plain text with mention tokens, emoji and URLs
  # (decision D8), never rich text. `mentioned_user_ids` is read from the body
  # before every validation, so the column can't say something the text does
  # not. Whether the mentioned people may be mentioned is the services'
  # question (`Notes::Authorization#mention_errors`), not the record's.
  #
  # The author is nullified when the user is deleted; the message stays and
  # reads "a deleted user" (`Admin::UserNameComponent`).
  class Message < ApplicationRecord
    self.table_name = "note_messages"

    MAX_BODY = 4_000

    belongs_to :thread, class_name: "Notes::Thread", inverse_of: :messages
    belongs_to :author, class_name: "User", optional: true

    before_validation { self.mentioned_user_ids = Mentions.ids(body) }

    validates :body, presence: true, length: { maximum: MAX_BODY }
  end
end
```

`app/models/notes/delivery.rb`:

```ruby
module Notes
  # One line of one person's inbox (notes spec §3.3): "this message is for
  # you, because …". At most one per person and message (the unique index).
  # Written by `Notes::Deliveries` inside the transaction of the message;
  # read when its owner opens the record's notes or presses "Mark all read"
  # (`Notes::MarkRead`). A row is kept when its owner loses the right to read
  # the record; the inbox narrows through `Notes.readable_threads` and simply
  # stops showing it.
  class Delivery < ApplicationRecord
    self.table_name = "note_deliveries"

    REASONS = %w[mention reply resolved reopened].freeze

    belongs_to :user
    belongs_to :message, class_name: "Notes::Message"
    belongs_to :thread, class_name: "Notes::Thread"

    validates :reason, inclusion: { in: REASONS }

    scope :unread, -> { where(read_at: nil) }
  end
end
```

`app/models/notes/follow.rb`:

```ruby
module Notes
  # Whether one person follows one thread (decision D17). Followers are told
  # of replies, resolves and reopens. `following: false` is an EXPLICIT
  # unfollow, kept so that writing again in the thread does not undo it; only
  # a new mention does. No row at all means the person was never involved.
  # The rules are `Notes::Deliveries.follow`; the button is the service
  # `Notes::SetFollowing`.
  class Follow < ApplicationRecord
    self.table_name = "note_follows"

    belongs_to :thread, class_name: "Notes::Thread"
    belongs_to :user
  end
end
```

- [ ] **Step 6: Mentions and text.** `app/models/notes/mentions.rb`:

```ruby
module Notes
  # A mention in a stored body is the token `@[<user id>]` (notes spec §3.2):
  # an id, so renaming a user changes how old mentions read and a deleted one
  # reads "a deleted user".
  #
  # A textarea can't show a name for a token, so the composer shows
  # "@Dana Smith" and sends, beside the text, the names its picker inserted
  # and their ids; `tokenize` puts the tokens in before the service sees the
  # body, and `display` is the way back for the edit form. The map comes from
  # the browser and is not trusted for anything but this substitution: who
  # may be mentioned is checked by the service on the ids that result.
  module Mentions
    TOKEN = /@\[(\d+)\]/

    def self.ids(body) = body.to_s.scan(TOKEN).flatten.map(&:to_i).uniq

    # The longest name first: "@Dana Smith" must not be read as "@Dana"
    # followed by " Smith". A block as the replacement, so a `\1` in a name is
    # text.
    def self.tokenize(text, names)
      names.to_h.sort_by { |name, _id| -name.to_s.length }.reduce(text.to_s) do |body, (name, id)|
        next body unless name.to_s.present? && id.to_s.match?(/\A\d+\z/)

        body.gsub("@#{name}") { "@[#{id}]" }
      end
    end

    # `[text, { display name => id }]`. A token whose user is not in
    # `users_by_id` (deleted since) is left as it is, so saving the edit
    # doesn't turn it into loose text.
    def self.display(body, users_by_id)
      names = {}
      text = body.to_s.gsub(TOKEN) do |token|
        user = users_by_id[Regexp.last_match(1).to_i]
        next token unless user

        names[user.display_name] = user.id
        "@#{user.display_name}"
      end
      [ text, names ]
    end
  end
end
```

`app/models/notes/text.rb`:

```ruby
module Notes
  # A message body as parts, for a component to render (data here, markup
  # there: the dependency order). Plain text stays text -- the component
  # escapes it -- a mention token is the user's id, and a bare `http(s)` URL
  # is a link. Nothing else is recognised: no Markdown, no HTML.
  #
  # A link is offered only for what `RichText::BuiltIns.safe_href?` accepts,
  # the one rule for a URL an editor typed; the pattern already admits only
  # http and https. Punctuation that ends a sentence is not part of the URL.
  module Text
    Part = Data.define(:kind, :value)

    URL = %r{https?://[^\s<>"']+}
    PATTERN = Regexp.union(Mentions::TOKEN, URL)
    TRAILING = /[.,;:!?)\]]+\z/

    def self.parts(body)
      text = body.to_s
      parts = []
      position = 0
      text.scan(PATTERN) do
        match = Regexp.last_match
        from = match.begin(0)
        if match[0].start_with?("@[")
          part = Part.new(:mention, match[1].to_i)
          finish = match.end(0)
        else
          url = match[0].sub(TRAILING, "")
          next unless RichText::BuiltIns.safe_href?(url)

          part = Part.new(:link, url)
          finish = from + url.length
        end
        parts << Part.new(:text, text[position...from]) if from > position
        parts << part
        position = finish
      end
      parts << Part.new(:text, text[position..]) if position < text.length
      parts
    end
  end
end
```

- [ ] **Step 7: Who follows and who is told.** `app/models/notes/deliveries.rb`:

```ruby
module Notes
  # Who follows a thread and who is told about what (notes spec §3.3, D17).
  # Called by the services inside the transaction of the action, so a
  # rolled-back note tells nobody.
  #
  # FOLLOWING. A message's author and everyone it mentions follow the thread:
  # a missing row is created; an author's explicit unfollow is left alone
  # (writing again is not asking to be told again); a mentioned person's
  # unfollow is undone (the mention is addressed to them).
  #
  # DELIVERIES.
  # - a new message: everyone it mentions (`mention`), and every follower
  #   (`reply`). A mention wins over a reply. On a thread's first message the
  #   followers are its author and the mentioned, so only mentions are told.
  # - an edit: only the people it newly mentions.
  # - a resolve or a reopen: every follower (`resolved`, `reopened`), on the
  #   thread's FIRST message.
  #
  # Never the person who did it, and at most one row per person and message
  # (the unique index). That rule meets the last bullet: someone mentioned in
  # the first message already has a row for it, and so does every follower
  # after the first resolve. The row is REUSED -- it takes the new reason and
  # is unread again -- because the newest thing to tell that person about
  # that message is what just happened to the thread. The same goes for an
  # edit that mentions someone the message had already told as a reply.
  #
  # A mentioned id whose user is gone follows nothing and is told nothing; a
  # follower who lost the right to read the record still gets the row, which
  # the inbox does not show (`Notes.readable_threads`).
  module Deliveries
    module_function

    def followers(thread) = Follow.where(thread_id: thread.id, following: true).pluck(:user_id)

    def follow(thread, author_id:, mentioned_ids:)
      mentioned = mentioned_ids.empty? ? [] : User.where(id: mentioned_ids).pluck(:id)
      user_ids = ([ author_id ] + mentioned).compact.uniq
      rows = Follow.where(thread_id: thread.id, user_id: user_ids).index_by(&:user_id)
      user_ids.each do |user_id|
        row = rows[user_id]
        if row.nil?
          Follow.create!(thread_id: thread.id, user_id: user_id, following: true)
        elsif !row.following && mentioned.include?(user_id)
          row.update!(following: true)
        end
      end
    end

    def for_new_message(message, actor_user:)
      follow(message.thread, author_id: message.author_id, mentioned_ids: message.mentioned_user_ids)
      reasons = followers(message.thread).index_with { "reply" }.merge(message.mentioned_user_ids.index_with { "mention" })
      write(message, reasons, actor_user)
    end

    def for_edit(message, newly_mentioned:, actor_user:)
      follow(message.thread, author_id: nil, mentioned_ids: newly_mentioned)
      write(message, newly_mentioned.index_with { "mention" }, actor_user)
    end

    def for_state(thread, reason, actor_user:)
      first = thread.first_message or return []
      write(first, followers(thread).index_with { reason }, actor_user)
    end

    def write(message, reasons, actor_user)
      reasons = reasons.except(actor_user&.id)
      return [] if reasons.empty?

      User.where(id: reasons.keys).order(:id).pluck(:id).map do |user_id|
        delivery = Delivery.find_or_initialize_by(user_id: user_id, message_id: message.id)
        delivery.update!(thread_id: message.thread_id, reason: reasons.fetch(user_id), read_at: nil)
        delivery
      end
    end
  end
end
```

- [ ] **Step 8: Run the tests, expect them to pass**, then the guards a new namespace can trip:
`PGGSSENCMODE=disable bin/rails test test/models/notes test/models/notes_test.rb test/lib` and `bin/rails zeitwerk:check`.

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: notes on content — threads, messages, follows and deliveries, mention tokens, who is told" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 2: Services I — start, reply, edit and delete a note, with their audit wording

**Spec:** §3.2, §3.4, §3.5 (Start, Reply, EditMessage, DeleteMessage, the rules, Audit, "Changed elsewhere" and "Mine"), §7 (the subject is deleted; a message deleted while someone replies). **Read first:** `app/services/application_service.rb`, `app/services/content_blocks/destroy.rb` (the lock order), `test/support/service_calls.rb` (its header), `test/models/audit/sentence_test.rb` lines 28–88.

**Files:**
- Create: `app/services/notes/authorization.rb`, `app/services/notes/start.rb`, `app/services/notes/reply.rb`, `app/services/notes/edit_message.rb`, `app/services/notes/delete_message.rb`, `config/locales/admin/notes.en.yml`
- Modify: `app/models/audit/sentence.rb`, `app/queries/dashboard/feed.rb` (`NOT_A_CHANGE`), `app/queries/dashboard/activity.rb` (`ACTIONS`), `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb` (`EXPECTED_SERVICES`), `test/services/service_contract_test.rb` (the floor: `>= 37`)
- Test: `test/services/notes/start_test.rb`, `reply_test.rb`, `edit_message_test.rb`, `delete_message_test.rb` (new), `test/models/audit/sentence_test.rb`, `test/queries/dashboard/feed_test.rb` and `test/queries/audit/change_since_test.rb` (append; if either file lives elsewhere under `test/`, append to the file that tests that class)

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces:
  - `Notes::Start.call(subject, body:, quote: nil, origin_view: "editor", origin_locale: nil, actor: Current.actor) -> Result(record: Notes::Thread | nil)`.
  - `Notes::Reply.call(thread, body:, actor: Current.actor) -> Result(record: Notes::Message | nil)`. Reopens a resolved thread.
  - `Notes::EditMessage.call(message, body:, actor: Current.actor) -> Result(record: Notes::Message)`.
  - `Notes::DeleteMessage.call(message, actor: Current.actor) -> Result(record: Notes::Thread | nil)`: nil when the thread went with its last message.
  - `Notes::Authorization` (private helpers for every notes service): `read_refusal(container) { |key| authorize!(key, container) } -> String | nil`, `moderation_refusal(container) { |key| authorize!(key, container) } -> String | nil` (each yields the key; the service's own class body must hold the `authorize!(` call), `body_errors(body) -> Array<String>`, `mention_errors(user_ids, container) -> Array<String>`, `lock_container(container) -> Integer | nil`, `own?(message) -> Boolean`, `note_metadata(thread, message = nil) -> Hash`, `gone(kind) -> String`, `kind_of(record) -> "page" | "post" | "block" | "image"`.
  - A refusal is `denied(key, container)`: the audit subject of a denial is the **container**.
  - `Audit::Sentence::NOTE_VERBS` (grows in Tasks 3 and 4); `Dashboard::Feed::NOT_A_CHANGE` includes its keys.
  - Locale keys `admin.notes.errors.*` (Step 3).

- [ ] **Step 1: Write the failing tests.**

`test/services/notes/start_test.rb`:

```ruby
require "test_helper"

class Notes::StartTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def start(subject, as_user: users(:reader), **options)
    as(as_user) { Notes::Start.call(subject, **{ body: "Is this price right?" }.merge(options)) }
  end

  test "a reader starts a thread on a block: one thread, one message, filed under the page" do
    result = start(@block, quote: "  €49 a month  ", origin_view: "editor", origin_locale: "en")

    assert result.ok?, result.errors.to_sentence
    thread = result.record
    assert_equal [ @block, @page, "open", "€49 a month", users(:reader) ], [ thread.subject, thread.container, thread.state, thread.quote, thread.created_by ]
    assert_equal [ "Is this price right?" ], thread.messages.map(&:body)
    assert_equal users(:reader), thread.first_message.author
    assert_in_delta thread.first_message.created_at, thread.last_message_at, 1.second
  end

  test "a note writes nothing of the record it is on" do
    before = [ @page.reload.updated_at, @block.reload.updated_at, PublicSite::Version.current ]

    start(@block)

    assert_equal before, [ @page.reload.updated_at, @block.reload.updated_at, PublicSite::Version.current ]
  end

  test "the audit event is on the content record and holds no text" do
    result = start(@block, quote: "a secret quote", body: "a secret body")
    event = Audit::Event.order(:id).last

    assert_equal [ "note.started", "ContentBlock", @block.id, users(:reader).id ], [ event.action, event.subject_type, event.subject_id, event.user_id ]
    assert_equal({ "thread_id" => result.record.id, "message_id" => result.record.first_message.id }, event.metadata)
    assert_nil event.snapshot
    assert_no_match(/secret/, event.attributes.to_json)
  end

  test "a stranger is refused with the read key on the container, and nothing is written" do
    result = start(@block, as_user: @stranger)

    assert_predicate result, :denied?
    assert_equal 0, Notes::Thread.count
    event = Audit::Event.order(:id).last
    assert_equal [ "access.denied", "pages.read", "Page", @page.id ], [ event.action, event.metadata["permission"], event.subject_type, event.subject_id ]
  end

  test "an empty and an over-long body are refused with a sentence" do
    assert_equal [ "Write something first." ], start(@page, body: " \n ").errors
    assert_equal [ "A note can be at most 4,000 characters." ], start(@page, body: "x" * 4_001).errors
    assert_equal 0, Notes::Thread.count
  end

  # Review Focus 2.
  test "a mention of someone who may not read the record is refused, and tells nobody" do
    result = start(@page, body: "Look, @[#{@stranger.id}]")

    assert_equal [ "stranger@example.com can't see this page." ], result.errors
    assert_not_predicate result, :denied?
    assert_equal [ 0, 0 ], [ Notes::Thread.count, Notes::Delivery.count ]
    assert_equal [ "That person no longer exists." ], start(@page, body: "Look, @[999999999]").errors
  end

  test "a mention of a reader is delivered" do
    result = start(@page, as_user: users(:two), body: "Look, @[#{users(:reader).id}]")

    assert result.ok?
    assert_equal [ [ users(:reader).id, "mention", result.record.id ] ], Notes::Delivery.pluck(:user_id, :reason, :thread_id)
  end

  test "an unknown origin view and a language that is not enabled fall back" do
    thread = start(@page, origin_view: "carrier-pigeon", origin_locale: "xx").record

    assert_equal [ "editor", nil ], [ thread.origin_view, thread.origin_locale ]
  end

  test "the page's row is locked before the block is looked up and the thread written" do
    statements = capture_sql { start(@block) }
    lock = statements.index { |sql| sql.include?(%(FROM "pages")) && sql.include?("FOR UPDATE") }
    look = statements.each_index.find { |index| lock && index > lock && statements[index].include?(%(FROM "content_blocks")) }
    write = statements.index { |sql| sql.start_with?(%(INSERT INTO "note_threads")) }

    assert lock && look && write, statements.join("\n")
    assert_operator lock, :<, look
    assert_operator look, :<, write
  end

  test "a block deleted beside the note is an ordinary failure" do
    stale = ContentBlock.find(@block.id)
    @block.destroy!

    result = start(stale)

    assert_equal [ "This block was deleted." ], result.errors
    assert_equal 0, Notes::Thread.count
  end

  test "a page in the trash takes no new note" do
    @page.update!(trashed_at: Time.current)

    assert_equal [ "This page is in the trash or was deleted." ], start(@page, as_user: users(:one)).errors
  end

  test "a library image takes a note from a media.upload holder, and a stranger is refused for that right" do
    asset = create_media_asset

    assert start(asset, as_user: users(:two), origin_view: "media").ok?
    assert_predicate start(asset, as_user: @stranger), :denied?
    event = Audit::Event.order(:id).last
    assert_equal [ "media.upload", "Media::Asset", asset.id ], [ event.metadata["permission"], event.subject_type, event.subject_id ]
  end
end
```

`test/services/notes/reply_test.rb`:

```ruby
require "test_helper"

class Notes::ReplyTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
  end

  def reply(as_user: users(:reader), body: "Yes.") = as(as_user) { Notes::Reply.call(@thread, body: body) }

  test "a reply adds a message, moves last_message_at, tells the followers and is audited without text" do
    result = travel_to(1.minute.from_now) { reply(body: "a secret answer") }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ "Is this right?", "a secret answer" ], @thread.reload.messages.map(&:body)
    assert_equal result.record.created_at.to_i, @thread.last_message_at.to_i
    assert_equal [ [ users(:two).id, "reply" ] ], Notes::Delivery.pluck(:user_id, :reason)
    event = Audit::Event.order(:id).last
    assert_equal [ "note.replied", "Page", @page.id ], [ event.action, event.subject_type, event.subject_id ]
    assert_equal({ "thread_id" => @thread.id, "message_id" => result.record.id }, event.metadata)
    assert_no_match(/secret/, event.attributes.to_json)
  end

  test "a reply to a resolved thread reopens it and says so in the log" do
    @thread.update!(state: "resolved", resolved_at: Time.current, resolved_by: users(:two))

    assert reply.ok?
    assert_equal [ "open", nil, nil ], @thread.reload.then { |thread| [ thread.state, thread.resolved_at, thread.resolved_by_id ] }
    assert_equal %w[note.replied note.reopened], Audit::Event.order(:id).last(2).map(&:action)
  end

  # Spec §7, "A message deleted while someone replies": the reply still lands.
  test "a reply lands in a thread one of whose messages was deleted meanwhile" do
    gone = as(users(:two)) { Notes::Reply.call(@thread, body: "Never mind") }.record
    stale = Notes::Thread.find(@thread.id)
    as(users(:two)) { Notes::DeleteMessage.call(gone) }

    assert as(users(:reader)) { Notes::Reply.call(stale, body: "Still answering") }.ok?
    assert_equal [ "Is this right?", "Still answering" ], @thread.reload.messages.map(&:body)
  end

  # Review Focus 3.
  test "a reply to a thread that was removed meanwhile is an ordinary failure" do
    stale = Notes::Thread.find(@thread.id)
    @thread.destroy!

    result = as(users(:reader)) { Notes::Reply.call(stale, body: "Too late") }

    assert_equal [ "This note is gone: it was deleted, or what it was on was." ], result.errors
    assert_equal 0, Notes::Message.count
  end

  test "a stranger is refused" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_predicate reply(as_user: stranger), :denied?
    assert_equal 1, @thread.messages.count
  end
end
```

`test/services/notes/edit_message_test.rb`:

```ruby
require "test_helper"

class Notes::EditMessageTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:reader)) { Notes::Start.call(@page, body: "Frist draft") }.record
    @message = @thread.first_message
  end

  def edit(body, as_user: users(:reader)) = as(as_user) { Notes::EditMessage.call(@message, body: body) }

  test "the author rewords their note: edited_at is set and the event holds no text" do
    result = edit("First draft, a secret")

    assert result.ok?, result.errors.to_sentence
    assert_equal "First draft, a secret", @message.reload.body
    assert_not_nil @message.edited_at
    event = Audit::Event.order(:id).last
    assert_equal [ "note.edited", { "thread_id" => @thread.id, "message_id" => @message.id } ], [ event.action, event.metadata ]
    assert_no_match(/secret/, event.attributes.to_json)
  end

  test "an unchanged body succeeds, writes nothing and records nothing" do
    assert_no_difference -> { Audit::Event.count } do
      assert edit("Frist draft").ok?
    end
    assert_nil @message.reload.edited_at
  end

  test "only newly mentioned people are told, and only they are checked" do
    lost = User.create!(email_address: "lost@example.com", password: "a-long-password-1")
    @message.update_columns(body: "Ask @[#{lost.id}]", mentioned_user_ids: [ lost.id ])

    result = edit("Ask @[#{lost.id}] and @[#{users(:two).id}]")

    assert result.ok?, result.errors.to_sentence
    assert_equal [ [ users(:two).id, "mention" ] ], Notes::Delivery.pluck(:user_id, :reason)
  end

  test "nobody edits another person's note, not even someone who may edit the page" do
    result = edit("Mine now", as_user: users(:two))

    assert_predicate result, :denied?
    assert_equal [ "Only the person who wrote a note can change it." ], result.errors
    assert_equal "Frist draft", @message.reload.body
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end

  test "an author who can no longer read the page can't edit" do
    AccessControl::Membership.where(user: users(:reader)).destroy_all

    assert_predicate edit("Still here?"), :denied?
  end
end
```

`test/services/notes/delete_message_test.rb`:

```ruby
require "test_helper"

class Notes::DeleteMessageTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:reader)) { Notes::Start.call(@page, body: "First") }.record
    @reply = travel_to(1.minute.from_now) { as(users(:two)) { Notes::Reply.call(@thread, body: "Second, @[#{users(:reader).id}]") } }.record
  end

  def delete(message, as_user:) = as(as_user) { Notes::DeleteMessage.call(message) }

  test "the author deletes their own message; its deliveries go, the thread stays and is dated by what is left" do
    result = delete(@reply, as_user: users(:two))

    assert result.ok?, result.errors.to_sentence
    assert_equal @thread, result.record
    assert_equal [ "First" ], @thread.reload.messages.map(&:body)
    assert_equal @thread.first_message.created_at.to_i, @thread.last_message_at.to_i
    assert_equal 0, Notes::Delivery.where(message_id: @reply.id).count
    event = Audit::Event.order(:id).last
    assert_equal [ "note.deleted", "Page", @page.id, { "thread_id" => @thread.id, "message_id" => @reply.id } ],
      [ event.action, event.subject_type, event.subject_id, event.metadata ]
  end

  test "deleting the last message deletes the thread" do
    delete(@reply, as_user: users(:two))
    result = delete(@thread.first_message, as_user: users(:reader))

    assert result.ok?
    assert_nil result.record
    assert_equal [ 0, 0, 0 ], [ Notes::Thread.count, Notes::Message.count, Notes::Follow.count ]
  end

  test "someone who may edit the page deletes another person's note; a reader may not" do
    assert delete(@thread.first_message, as_user: users(:two)).ok?

    result = delete(@reply, as_user: users(:reader))
    assert_predicate result, :denied?
    assert_equal "pages.edit", Audit::Event.order(:id).last.metadata["permission"]
    assert Notes::Message.exists?(@reply.id)
  end

  test "an image's uploader moderates the notes on it" do
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:author), permission: "media.upload") { |grant| grant.scope = {} }
    asset = create_media_asset
    asset.update_columns(created_by_id: users(:author).id)
    message = as(users(:two)) { Notes::Start.call(asset, body: "Crop it") }.record.first_message

    assert delete(message, as_user: users(:author)).ok?
  end

  test "a message already deleted is a success with nothing recorded" do
    stale = Notes::Message.find(@reply.id)
    @reply.destroy!

    assert_no_difference -> { Audit::Event.count } do
      assert delete(stale, as_user: users(:two)).ok?
    end
  end
end
```

Append to `test/models/audit/sentence_test.rb`:

```ruby
  test "a note's events read as sentences about the record, a block's about its page" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_equal "You started a note on “Pricing”", read(sentence_for(event("note.started", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You replied to a note on “Pricing”", read(sentence_for(event("note.replied", subject_type: "ContentBlock", subject_id: block.id, subject_label: "Rich text block ##{block.id}")))
    assert_equal "You edited a note on “Pricing”", read(sentence_for(event("note.edited", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You deleted a note on “Pricing”", read(sentence_for(event("note.deleted", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
  end
```

Append to the test of `Dashboard::Feed` (find it with `grep -rl "Dashboard::Feed" test`):

```ruby
  test "a note on my draft by someone else does not take it off my drafts, and one by me does not put theirs on mine" do
    mine = as(users(:two)) { create_post(title: "Mine", published: false) }
    theirs = as(users(:one)) { create_post(title: "Theirs", published: false) }
    travel_to(1.minute.from_now) do
      as(users(:one)) { Notes::Start.call(mine, body: "A question") }
      as(users(:two)) { Notes::Start.call(theirs, body: "A question") }
    end

    drafts = Dashboard::Feed.new(actor: users(:two), channel: :admin).drafts

    assert_includes drafts, mine
    assert_not_includes drafts, theirs
  end
```

Append to the test of `Audit::ChangeSince` (`grep -rl "ChangeSince" test`):

```ruby
  test "a note is not a change to the record" do
    page = create_page(title: "Pricing")
    base = page.reload.updated_at
    travel_to(1.minute.from_now) { as(users(:two)) { Notes::Start.call(page, body: "A question") } }

    assert_nil Audit::ChangeSince.for(page, since: base, viewer: users(:one))
  end
```

- [ ] **Step 2: Run them, expect failure** (`uninitialized constant Notes::Start`):
`PGGSSENCMODE=disable bin/rails test test/services/notes test/models/audit/sentence_test.rb`

- [ ] **Step 3: The strings.** Create `config/locales/admin/notes.en.yml`:

```yaml
# Notes on content (docs/reference/i18n.md): everything a person reads about
# notes. `admin.notes.errors` are the sentences the `Notes::` services answer
# with; later tasks add `admin.notes.script` (what the scripts say),
# `admin.notes.index` and `admin.note_inbox` (the views' own lazy-lookup
# scopes) and `admin.components.notes_screen` (the components).
#
# Each shape of a sentence is a whole sentence of its own, one per kind of
# record, never glued from a noun: a translator can reorder it.
en:
  admin:
    notes:
      errors:
        blank: "Write something first."
        too_long: "A note can be at most 4,000 characters."
        mention_unknown: "That person no longer exists."
        mention_cannot_read:
          page: "%{name} can't see this page."
          post: "%{name} can't see this post."
          image: "%{name} can't open the media library."
        gone:
          page: "This page is in the trash or was deleted."
          post: "This post is in the trash or was deleted."
          image: "This image is in the trash or was deleted."
          block: "This block was deleted."
          note: "This note is gone: it was deleted, or what it was on was."
        not_yours: "Only the person who wrote a note can change it."
        delete_others: "Only the person who wrote a note, or someone who can edit what it is on, can delete it."
```

- [ ] **Step 4: What the notes services share.** `app/services/notes/authorization.rb`:

```ruby
module Notes
  # The checks every notes service shares (notes spec §3.4). Notes follow the
  # content: reading, starting, replying, resolving and following need the
  # container's READ right; deleting someone else's note and pinning need its
  # EDIT right (an image: `media.manage`, or its uploader with `media.upload`,
  # `Media::Ownership`). A refusal names the container, the record whose
  # right was missing.
  #
  # `lock_container` is the first statement of every notes transaction: the
  # container's row lock, read through `kept`, so a record trashed or purged
  # meanwhile reads as gone. It is the same first lock every write to a
  # page's blocks takes (`ContentBlocks::Structure#lock_owner`: the page's
  # row, then block rows), so a note and a block's delete run one after the
  # other, never interleaved, and `Notes::Remove` can't miss a thread written
  # beside it.
  module Authorization
    include Media::Ownership

    private

    # Both yield the key to check and answer the refused key, or nil, like
    # `ContentBlocks::OwnerPermissions#owner_refusal`: the service itself
    # writes `authorize!(key, container)` in the block, which is what
    # `test/services/service_contract_test.rb` looks for in its class body.
    def read_refusal(container)
      key = Notes.read_key(container)
      key unless yield(key)
    end

    def moderation_refusal(container)
      key = Notes.moderate_key(container)
      return if yield(key)
      return if container.is_a?(Media::Asset) && uploader_may_manage?(container)

      key
    end

    def own?(message) = actor_user.present? && message.author_id == actor_user.id

    def body_errors(body)
      return [ I18n.t("admin.notes.errors.blank") ] if body.blank?
      return [ I18n.t("admin.notes.errors.too_long") ] if body.length > Message::MAX_BODY

      []
    end

    # A mention is addressed to a person: it must name a user who exists and
    # who may read the record, or the inbox would show them a title and a
    # quote they are not allowed to see. Judged as that user would be judged
    # in CS Studio (`:admin`), whatever channel this call runs on.
    def mention_errors(user_ids, container)
      return [] if user_ids.empty?

      users = User.where(id: user_ids).index_by(&:id)
      user_ids.filter_map do |id|
        user = users[id]
        if user.nil?
          I18n.t("admin.notes.errors.mention_unknown")
        elsif !Notes.readable?(user, container, channel: :admin)
          I18n.t("admin.notes.errors.mention_cannot_read.#{kind_of(container)}", name: user.display_name)
        end
      end.uniq
    end

    def lock_container(container) = container.class.kept.where(id: container.id).lock.pick(:id)

    def kind_of(record)
      { "Page" => "page", "Post" => "post", "ContentBlock" => "block", "Media::Asset" => "image" }.fetch(record.class.polymorphic_name)
    end

    def gone(kind) = I18n.t("admin.notes.errors.gone.#{kind}")

    # Ids only (decision D14): the log is append-only, so a note's text in it
    # would outlive the note.
    def note_metadata(thread, message = nil)
      { "thread_id" => thread.id, "message_id" => message&.id }.compact
    end
  end
end
```

- [ ] **Step 5: `Notes::Start`.** `app/services/notes/start.rb`:

```ruby
module Notes
  # Starts a thread on a page, a post, a block or a library image, with its
  # first message (notes spec §3.5). Needs the container's read right.
  #
  # A NOTE NEVER WRITES THE RECORD IT IS ON: no `touch`, no `updated_at`, no
  # public content version. An autosave base is never moved by a note.
  #
  # EXISTENCE UNDER A LOCK. The subject is re-read inside the transaction,
  # the container's row lock first (`Authorization#lock_container`), then,
  # for a block, the block among that page's. A block deleted or a page
  # purged a moment ago is an ordinary failure, and one deleted a moment
  # later finds this thread in `Notes::Remove`, which runs under the same
  # lock.
  class Start < ApplicationService
    include Authorization

    def initialize(subject, body:, quote: nil, origin_view: "editor", origin_locale: nil, actor: Current.actor)
      @subject = subject
      @body = body.to_s.strip
      @quote = quote.to_s.strip.first(Thread::MAX_QUOTE).presence
      @origin_view = Thread::ORIGIN_VIEWS.include?(origin_view.to_s) ? origin_view.to_s : "editor"
      @origin_locale = Locales.enabled?(origin_locale) ? origin_locale.to_s : nil
      @actor = actor
    end

    def call
      container = Notes.container_for(@subject)
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      errors = body_errors(@body) + mention_errors(Mentions.ids(@body), container)
      return failure(nil, errors) if errors.any?

      thread = Thread.transaction(requires_new: true) do
        next unless subject_still_there?(container)

        created = Thread.create!(subject: @subject, quote: @quote, origin_view: @origin_view, origin_locale: @origin_locale,
          created_by: actor_user, last_message_at: Time.current)
        message = created.messages.create!(author: actor_user, body: @body)
        created.update!(last_message_at: message.created_at)
        Deliveries.for_new_message(message, actor_user: actor_user)
        record_event("note.started", subject: @subject, snapshot: nil, metadata: note_metadata(created, message))
        created
      end

      thread ? success(thread) : failure(nil, [ gone(kind_of(@subject)) ])
    end

    private

    def subject_still_there?(container)
      return false unless lock_container(container)

      !@subject.is_a?(ContentBlock) || ContentBlock.where(id: @subject.id, owner: container).exists?
    end
  end
end
```

- [ ] **Step 6: `Notes::Reply`.** `app/services/notes/reply.rb`:

```ruby
module Notes
  # Adds a message to a thread (notes spec §3.5). Needs the read right.
  # Replying to a resolved thread reopens it: the reply is the news, so the
  # followers get the `reply` row and the log gets both events.
  #
  # The thread is re-read under the container's lock: one removed meanwhile
  # (its block deleted, its page purged, its last message deleted) is an
  # ordinary failure the drawer shows, never an exception.
  class Reply < ApplicationService
    include Authorization

    def initialize(thread, body:, actor: Current.actor)
      @thread = thread
      @body = body.to_s.strip
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      errors = body_errors(@body) + mention_errors(Mentions.ids(@body), container)
      return failure(nil, errors) if errors.any?

      message = Thread.transaction(requires_new: true) do
        thread = lock_container(container) && Thread.where(id: @thread.id).lock.first
        next unless thread

        reopened = thread.resolved?
        created = thread.messages.create!(author: actor_user, body: @body)
        thread.update!(last_message_at: created.created_at, **(reopened ? { state: "open", resolved_at: nil, resolved_by: nil } : {}))
        Deliveries.for_new_message(created, actor_user: actor_user)
        record_event("note.replied", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread, created))
        record_event("note.reopened", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread)) if reopened
        created
      end

      message ? success(message) : failure(nil, [ gone("note") ])
    end
  end
end
```

- [ ] **Step 7: `Notes::EditMessage`.** `app/services/notes/edit_message.rb`:

```ruby
module Notes
  # Changes the text of the actor's OWN message (notes spec §3.5): allowed
  # while they may still read the record, and to nobody else -- someone who
  # may edit the page can delete a note, never put words in its author's
  # mouth. There is no permission that grants it, so the refusal is logged
  # against the read key with its own sentence, as `Users::UpdateProfile`
  # logs its "only yourself" rule against `users.manage`.
  #
  # Only the people the edit NEWLY mentions are checked and told: someone
  # mentioned before who has since lost access stays in the text.
  class EditMessage < ApplicationService
    include Authorization

    def initialize(message, body:, actor: Current.actor)
      @message = message
      @body = body.to_s.strip
      @actor = actor
    end

    def call
      thread = @message.thread
      container = thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused
      return denied(Notes.read_key(container), container, message: I18n.t("admin.notes.errors.not_yours")) unless own?(@message)

      newly_mentioned = Mentions.ids(@body) - @message.mentioned_user_ids
      errors = body_errors(@body) + mention_errors(newly_mentioned, container)
      return failure(@message, errors) if errors.any?

      message = Message.transaction(requires_new: true) do
        current = lock_container(container) && Message.where(id: @message.id).lock.first
        next unless current
        next current if current.body == @body

        current.update!(body: @body, edited_at: Time.current)
        Deliveries.for_edit(current, newly_mentioned: newly_mentioned, actor_user: actor_user)
        record_event("note.edited", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread, current))
        current
      end

      message ? success(message) : failure(@message, [ gone("note") ])
    end
  end
end
```

- [ ] **Step 8: `Notes::DeleteMessage`.** `app/services/notes/delete_message.rb`:

```ruby
module Notes
  # Deletes one message with its deliveries (and, once they exist, its
  # reactions and files); the thread goes with its last message (notes spec
  # §3.5). Your own message needs the read right; someone else's needs the
  # container's edit right (`Authorization#moderation_refusal`).
  #
  # A message someone else deleted a moment ago is a success with nothing
  # recorded: the outcome the caller asked for is already there.
  # `note.deleted` is recorded before the delete, in its transaction.
  class DeleteMessage < ApplicationService
    include Authorization

    def initialize(message, actor: Current.actor)
      @message = message
      @actor = actor
    end

    def call
      container = @message.thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      unless own?(@message)
        refused = moderation_refusal(container) { |key| authorize!(key, container) }
        return denied(refused, container, message: I18n.t("admin.notes.errors.delete_others")) if refused
      end

      thread = Message.transaction(requires_new: true) do
        lock_container(container)
        message = Message.where(id: @message.id).lock.first
        current = Thread.where(id: @message.thread_id).lock.first
        next current unless message && current

        record_event("note.deleted", subject: current.subject, snapshot: nil, metadata: note_metadata(current, message))
        message.destroy!
        newest = current.messages.reload.last
        if newest
          current.update!(last_message_at: newest.created_at)
          current
        else
          current.destroy!
          nil
        end
      end

      success(thread)
    end
  end
end
```

- [ ] **Step 9: The wording.** In `app/models/audit/sentence.rb`, after `OTHER_VERBS`:

```ruby
    # A note's events (notes spec §3.5). Their subject is the CONTENT record
    # the note is on -- a page, a post, an image, or a block, whose sentence
    # names its page (`Targets#owner_target`) -- so they show in that record's
    # Activity and are read-scoped like it. They carry no text, only ids.
    # `Dashboard::Feed::NOT_A_CHANGE` reads these keys: a note is not a change
    # to the record.
    NOTE_VERBS = {
      "note.started" => [ "started a note on ", "" ], "note.replied" => [ "replied to a note on ", "" ],
      "note.edited" => [ "edited a note on ", "" ], "note.deleted" => [ "deleted a note on ", "" ],
      "note.reopened" => [ "reopened a note on ", "" ]
    }.freeze
```

Change `ACTIONS` to `BLOCK_ACTIONS + OTHER_VERBS.keys + NOTE_VERBS.keys + SPECIAL_ACTIONS` and, in `Wording#parts`, add before the `OTHER_VERBS` branch: `elsif NOTE_VERBS.key?(@action) then subject_parts(*NOTE_VERBS[@action])`. (`note.reopened` is here already because `Notes::Reply` records it; `Notes::Reopen` in Task 3 records the same action.)

In `app/queries/dashboard/feed.rb` replace the constant, keeping its comment and adding one sentence to it:

```ruby
    # ... A note's events have the page, post or block as their subject too,
    # and are no change to it either (notes spec §3.5): "Mine" and "Changed
    # by" (`Audit::ChangeSince` reads this list) ignore them.
    NOT_A_CHANGE = (%w[access.denied] + Audit::Sentence::NOTE_VERBS.keys).freeze
```

In `app/queries/dashboard/activity.rb` add to the `ACTIONS` hash, with a comment line above it saying replies are left out so they don't flood the feed: `"note" => %w[started]`.

- [ ] **Step 10: The contract.** In `test/services/service_behaviour_contract_test.rb` add `Notes::DeleteMessage Notes::EditMessage Notes::Reply Notes::Start` to `EXPECTED_SERVICES` (keep the list sorted) and raise the floor in `test/services/service_contract_test.rb` from `33` to `37`. In `test/support/service_calls.rb`, add to `Builders`:

```ruby
    # A thread on `subject` with its first message, written by `by` (a user
    # who may read it): what the notes services act on.
    def note_on(subject, by: users(:one), body: "A question")
      result = as(by) { Notes::Start.call(subject, body: body) }
      assert result.ok?, result.errors.to_sentence
      result.record
    end
```

and to `FACTORIES` (alphabetical place):

```ruby
    # A message someone else wrote: deleting it is moderation, which the
    # trusted actor may; the stranger is refused for the read right first.
    "Notes::DeleteMessage" => lambda {
      page = create_page(title: "Noted", published: false)
      message = note_on(page).first_message
      { call: -> { Notes::DeleteMessage.call(message) }, permission: "pages.read", on: page }
    },

    # Only its author may edit a message, so the control runs as the author.
    "Notes::EditMessage" => lambda {
      page = create_page(title: "Noted", published: false)
      message = note_on(page, by: users(:one)).first_message
      { call: -> { Notes::EditMessage.call(message, body: "Reworded") }, permission: "pages.read", on: page, control_actor: users(:one) }
    },

    "Notes::Reply" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      { call: -> { Notes::Reply.call(thread, body: "An answer") }, permission: "pages.read", on: page }
    },

    "Notes::Start" => lambda {
      page = create_page(title: "Noted", published: false)
      { call: -> { Notes::Start.call(page, body: "A question") }, permission: "pages.read", on: page }
    },
```

- [ ] **Step 11: Run**, expect green:
`PGGSSENCMODE=disable bin/rails test test/services test/models/audit test/models/notes test/queries test/lib`

- [ ] **Step 12: Commit.**

```bash
git add -A
git commit -m "feat: start, reply to, edit and delete a note through services; a note's events name the record and hold no text" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 3: Services II — resolve, reopen, pin, unpin, follow, mark read

**Spec:** §3.3 (the `resolved` and `reopened` rows, the "Notify me" button, when a delivery is read), §3.5, §7 ("Two people resolve at once"). **Read first:** Task 2's `app/services/notes/authorization.rb` and `reply.rb`; `test/services/service_behaviour_contract_test.rb` (`assert_changes_something_when_allowed`).

**Files:**
- Create: `app/services/notes/resolve.rb`, `reopen.rb`, `pin.rb`, `unpin.rb`, `set_following.rb`, `mark_read.rb`
- Modify: `app/services/notes/authorization.rb` (two helpers), `app/models/audit/sentence.rb` (`NOTE_VERBS`), `app/queries/dashboard/activity.rb`, `config/locales/admin/notes.en.yml`, `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/services/service_contract_test.rb` (floor `43`)
- Test: `test/services/notes/thread_state_test.rb`, `test/services/notes/set_following_test.rb`, `test/services/notes/mark_read_test.rb` (new), `test/models/audit/sentence_test.rb`, `test/queries/dashboard/activity_test.rb`

**Interfaces:**
- Consumes: `Notes::Authorization`, `Notes::Deliveries.for_state`, `Notes::Follow`, `Notes::Delivery`.
- Produces:
  - `Notes::Resolve.call(thread, actor: Current.actor)`, `Notes::Reopen.call(thread, actor:)`, `Notes::Pin.call(thread, actor:)`, `Notes::Unpin.call(thread, actor:)`, each `-> Result(record: Notes::Thread)`. A call that finds the thread already in the asked state succeeds and records nothing.
  - `Notes::SetFollowing.call(thread, following:, actor: Current.actor) -> Result(record: Notes::Thread)`. This is the spec's `Notes::Follow` service under another name: `Notes::Follow` is the record.
  - `Notes::MarkRead.call(thread: nil, container: nil, actor: Current.actor) -> Result(record: nil)`: the actor's own unread deliveries on one thread (opening it), on all of a container's threads, or all of them ("Mark all read").
  - `Notes::Authorization#with_locked_thread(thread) { |current| ... }` (answers the block's value, or `:gone`) and `#thread_answer(outcome, thread) -> Result` (`:gone` and a String are failures).
  - In `test/support/service_calls.rb`: the factory option `control_unaudited: "<reason>"` for a service that says `# audit: none`.
  - Rules (spec §3.5): a pinned thread is always open. Resolving a thread unpins it; pinning a resolved thread is refused ("Reopen this note before pinning it.").

- [ ] **Step 1: Write the failing tests.** `test/services/notes/thread_state_test.rb`:

```ruby
require "test_helper"

class Notes::ThreadStateTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right, @[#{users(:reader).id}]?") }.record
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def last_actions(count) = Audit::Event.order(:id).last(count).map(&:action)

  test "a reader resolves: the state, who and when, the followers told, one event" do
    result = as(users(:reader)) { Notes::Resolve.call(@thread) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ "resolved", users(:reader).id ], [ @thread.reload.state, @thread.resolved_by_id ]
    assert_not_nil @thread.resolved_at
    # The reader's own mention row stays as it was; the other follower is told.
    assert_equal [ [ users(:reader).id, "mention" ], [ users(:two).id, "resolved" ] ].sort, Notes::Delivery.pluck(:user_id, :reason).sort
    event = Audit::Event.order(:id).last
    assert_equal [ "note.resolved", "Page", @page.id, { "thread_id" => @thread.id } ], [ event.action, event.subject_type, event.subject_id, event.metadata ]
    assert_nil event.snapshot
  end

  # Review Focus 1, through the service: the mentioned person already has a row on the first message.
  test "a resolve by someone else reuses the mentioned person's row" do
    assert as(users(:two)) { Notes::Resolve.call(@thread) }.ok?

    assert_equal [ [ users(:reader).id, "resolved" ] ], Notes::Delivery.pluck(:user_id, :reason)
  end

  test "resolving twice is one event; the second is a success that changes nothing" do
    as(users(:reader)) { Notes::Resolve.call(@thread) }
    stamp = @thread.reload.resolved_at

    assert_no_difference -> { Audit::Event.count } do
      assert as(users(:two)) { Notes::Resolve.call(Notes::Thread.find(@thread.id)) }.ok?
    end
    assert_equal [ stamp, users(:reader).id ], [ @thread.reload.resolved_at, @thread.resolved_by_id ]
  end

  test "reopen clears the resolve and tells the followers" do
    as(users(:two)) { Notes::Resolve.call(@thread) }

    assert as(users(:two)) { Notes::Reopen.call(@thread) }.ok?
    assert_equal [ "open", nil, nil ], @thread.reload.then { |thread| [ thread.state, thread.resolved_at, thread.resolved_by_id ] }
    assert_equal [ [ users(:reader).id, "reopened" ] ], Notes::Delivery.pluck(:user_id, :reason)
    assert_equal %w[note.resolved note.reopened], last_actions(2)
  end

  test "pin and unpin need the edit right; a reader is refused" do
    refused = as(users(:reader)) { Notes::Pin.call(@thread) }
    assert_predicate refused, :denied?
    assert_equal "pages.edit", Audit::Event.order(:id).last.metadata["permission"]

    assert as(users(:two)) { Notes::Pin.call(@thread) }.ok?
    assert_equal [ true, users(:two).id ], [ @thread.reload.pinned, @thread.pinned_by_id ]
    assert as(users(:two)) { Notes::Unpin.call(@thread) }.ok?
    assert_equal [ false, nil, nil ], @thread.reload.then { |thread| [ thread.pinned, thread.pinned_at, thread.pinned_by_id ] }
    assert_equal %w[note.pinned note.unpinned], last_actions(2)
  end

  test "a pinned thread is always open: resolving it unpins it, and a resolved thread can't be pinned" do
    as(users(:two)) { Notes::Pin.call(@thread) }

    assert as(users(:reader)) { Notes::Resolve.call(@thread) }.ok?
    assert_equal [ "resolved", false, nil, nil ], @thread.reload.then { |thread| [ thread.state, thread.pinned, thread.pinned_at, thread.pinned_by_id ] }
    assert_equal "note.resolved", Audit::Event.order(:id).last.action

    assert_equal [ "Reopen this note before pinning it." ], as(users(:two)) { Notes::Pin.call(@thread) }.errors
    assert_equal [ "resolved", false ], [ @thread.reload.state, @thread.pinned ]
  end

  test "a stranger is refused each of them, and a thread that is gone is a failure" do
    [ Notes::Resolve, Notes::Reopen, Notes::Pin, Notes::Unpin ].each do |service|
      assert_predicate as(@stranger) { service.call(@thread) }, :denied?, service.name
    end
    stale = Notes::Thread.find(@thread.id)
    @thread.destroy!

    assert_equal [ "This note is gone: it was deleted, or what it was on was." ], as(users(:two)) { Notes::Resolve.call(stale) }.errors
  end

  test "none of them writes the page" do
    before = [ @page.reload.updated_at, PublicSite::Version.current ]

    as(users(:two)) { [ Notes::Pin, Notes::Unpin, Notes::Resolve, Notes::Reopen ].each { |service| assert service.call(@thread).ok? } }

    assert_equal before, [ @page.reload.updated_at, PublicSite::Version.current ]
  end
end
```

`test/services/notes/set_following_test.rb`:

```ruby
require "test_helper"

class Notes::SetFollowingTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
  end

  def following?(user) = Notes::Follow.find_by(thread: @thread, user: user)&.following

  test "a reader follows a thread they never wrote in, and is then told of a reply" do
    assert_nil following?(users(:reader))

    assert as(users(:reader)) { Notes::SetFollowing.call(@thread, following: true) }.ok?
    assert following?(users(:reader))

    as(users(:two)) { Notes::Reply.call(@thread, body: "More") }
    assert_equal [ [ users(:reader).id, "reply" ] ], Notes::Delivery.pluck(:user_id, :reason)
  end

  test "an unfollow is remembered, and nothing is audited" do
    assert_no_difference -> { Audit::Event.count } do
      assert as(users(:two)) { Notes::SetFollowing.call(@thread, following: false) }.ok?
    end
    assert_equal false, following?(users(:two))

    as(users(:two)) { Notes::Reply.call(@thread, body: "Writing again") }
    assert_equal false, following?(users(:two))
  end

  test "a stranger can't follow" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_predicate as(stranger) { Notes::SetFollowing.call(@thread, following: true) }, :denied?
    assert_nil following?(stranger)
  end
end
```

`test/services/notes/mark_read_test.rb`:

```ruby
require "test_helper"

class Notes::MarkReadTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    mention = "Look, @[#{users(:reader).id}] and @[#{users(:author).id}]"
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:author), permission: "pages.read") { |grant| grant.scope = {} }
    as(users(:two)) do
      Notes::Start.call(@page, body: mention)
      Notes::Start.call(@post, body: "And here, @[#{users(:reader).id}]")
    end
  end

  def unread(user) = Notes::Delivery.unread.where(user: user).count

  test "one record's deliveries are read, for the actor only" do
    assert_equal [ 2, 1 ], [ unread(users(:reader)), unread(users(:author)) ]

    assert as(users(:reader)) { Notes::MarkRead.call(container: @page) }.ok?

    assert_equal [ 1, 1 ], [ unread(users(:reader)), unread(users(:author)) ]
  end

  test "one thread's deliveries are read, which is what opening it does" do
    thread = Notes::Thread.find_by!(container: @page)
    as(users(:two)) { Notes::Start.call(@page, body: "Another, @[#{users(:reader).id}]") }

    assert as(users(:reader)) { Notes::MarkRead.call(thread: thread) }.ok?

    assert_equal [ 2, 0 ], [ unread(users(:reader)), Notes::Delivery.unread.where(user: users(:reader), thread: thread).count ]
  end

  test "all of the actor's deliveries are read, in one statement, and nothing is audited" do
    statements = nil
    assert_no_difference -> { Audit::Event.count } do
      statements = capture_sql { as(users(:reader)) { Notes::MarkRead.call } }
    end

    assert_equal [ 0, 1 ], [ unread(users(:reader)), unread(users(:author)) ]
    assert_equal 1, statements.count { |sql| sql.start_with?("UPDATE") }
  end

  test "a record the actor can't read is refused" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_predicate as(stranger) { Notes::MarkRead.call(container: @page) }, :denied?
  end
end
```

Append to `test/models/audit/sentence_test.rb`, inside the test Task 2 added, three more lines (same `page`):

```ruby
    assert_equal "You resolved a note on “Pricing”", read(sentence_for(event("note.resolved", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You pinned a note on “Pricing”", read(sentence_for(event("note.pinned", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You unpinned a note on “Pricing”", read(sentence_for(event("note.unpinned", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
```

Append to `test/queries/dashboard/activity_test.rb` (spec §3.5: the feed gains a note started and a note resolved only, so replies don't flood it):

```ruby
  test "the feed lists a note started and a note resolved, on a page and on a block, and never a reply" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) do
      thread = Notes::Start.call(block, body: "A question").record
      Notes::Reply.call(thread, body: "More")
      Notes::Resolve.call(thread)
    end

    rows = Dashboard::Activity.new(actor: users(:one), channel: :admin).rows.select { |row| row.event.action.start_with?("note.") }

    assert_equal %w[note.resolved note.started], rows.map { |row| row.event.action }
    assert_equal [ page, page ], rows.map(&:record) # a block's note is listed under its page
  end
```

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/services/notes test/models/audit/sentence_test.rb test/queries/dashboard/activity_test.rb`

- [ ] **Step 3: Two helpers.** Add to `Notes::Authorization` (private):

```ruby
    # The thread re-read and locked, under its container's lock: the block's
    # value, or `:gone` when the thread, or what it is on, is no longer there.
    def with_locked_thread(thread)
      Thread.transaction(requires_new: true) do
        current = lock_container(thread.container) && Thread.where(id: thread.id).lock.first
        current ? yield(current) : :gone
      end
    end

    # What `with_locked_thread` answered, as a Result: `:gone` and a sentence
    # are failures, anything else is the record of a success.
    def thread_answer(outcome, thread)
      case outcome
      when :gone then failure(thread, [ gone("note") ])
      when String then failure(thread, [ outcome ])
      else success(outcome)
      end
    end
```

Add to `config/locales/admin/notes.en.yml` under `errors`: `pin_resolved: "Reopen this note before pinning it."`

- [ ] **Step 4: The four state services.** `app/services/notes/resolve.rb`:

```ruby
module Notes
  # Resolves a thread (notes spec §3.5): kept, listed under "Resolved", not
  # counted. Needs the read right. Two people resolving at once is one
  # resolve: the second finds it done under the lock and succeeds without an
  # event or a second round of deliveries. A pinned thread is always open, so
  # resolving one unpins it in the same write.
  class Resolve < ApplicationService
    include Authorization

    def initialize(thread, actor: Current.actor)
      @thread = thread
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      outcome = with_locked_thread(@thread) do |thread|
        next thread if thread.resolved?

        thread.update!(state: "resolved", resolved_at: Time.current, resolved_by: actor_user, pinned: false, pinned_at: nil, pinned_by: nil)
        Deliveries.for_state(thread, "resolved", actor_user: actor_user)
        record_event("note.resolved", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
```

`app/services/notes/reopen.rb`:

```ruby
module Notes
  # Reopens a resolved thread (notes spec §3.5). Needs the read right; a
  # thread that is open already is a success with nothing recorded.
  class Reopen < ApplicationService
    include Authorization

    def initialize(thread, actor: Current.actor)
      @thread = thread
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      outcome = with_locked_thread(@thread) do |thread|
        next thread if thread.open?

        thread.update!(state: "open", resolved_at: nil, resolved_by: nil)
        Deliveries.for_state(thread, "reopened", actor_user: actor_user)
        record_event("note.reopened", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
```

`app/services/notes/pin.rb`:

```ruby
module Notes
  # Pins a thread: a standing note, listed first (decision D1). Moderation:
  # the container's edit right. A pinned thread is always open, so a resolved
  # one can't be pinned: it is reopened first, which tells its followers.
  class Pin < ApplicationService
    include Authorization

    def initialize(thread, actor: Current.actor)
      @thread = thread
      @actor = actor
    end

    def call
      container = @thread.container
      refused = moderation_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      outcome = with_locked_thread(@thread) do |thread|
        next thread if thread.pinned?
        next I18n.t("admin.notes.errors.pin_resolved") if thread.resolved?

        thread.update!(pinned: true, pinned_at: Time.current, pinned_by: actor_user)
        record_event("note.pinned", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
```

`app/services/notes/unpin.rb`:

```ruby
module Notes
  # Takes a thread off the pinned list; it stays open. Moderation, like Pin.
  class Unpin < ApplicationService
    include Authorization

    def initialize(thread, actor: Current.actor)
      @thread = thread
      @actor = actor
    end

    def call
      container = @thread.container
      refused = moderation_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      outcome = with_locked_thread(@thread) do |thread|
        next thread unless thread.pinned?

        thread.update!(pinned: false, pinned_at: nil, pinned_by: nil)
        record_event("note.unpinned", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
```

- [ ] **Step 5: Following and reading.** `app/services/notes/set_following.rb`:

```ruby
module Notes
  # "Notify me" / "Stop notifying me" (decision D17): sets the actor's own
  # follow row either way. The spec calls this service `Notes::Follow`; that
  # constant is the record (`note_follows`), so the service has this name.
  # Needs the read right. A `false` row is an explicit unfollow, which
  # `Notes::Deliveries.follow` leaves alone until a new mention.
  class SetFollowing < ApplicationService
    include Authorization

    # audit: none (following a thread changes who is told, not the content or the thread; like a read mark it is the person's own setting)

    def initialize(thread, following:, actor: Current.actor)
      @thread = thread
      @following = following ? true : false
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused
      return success(@thread) unless actor_user

      outcome = with_locked_thread(@thread) do |thread|
        Follow.find_or_initialize_by(thread_id: thread.id, user_id: actor_user.id).update!(following: @following)
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
```

`app/services/notes/mark_read.rb`:

```ruby
module Notes
  # Marks the ACTOR'S OWN deliveries read (notes spec §3.3): those of one
  # thread (opening the thread does this), those on all of one record's
  # threads, or all of them ("Mark all read"). With a thread or a container it
  # needs that container's read right; without either there is nothing to
  # check -- the rows are the actor's own, and reading them tells nobody
  # anything.
  class MarkRead < ApplicationService
    include Authorization

    # audit: none (a read mark is the reader's own bookkeeping, not a change to content or to a note)

    def initialize(thread: nil, container: nil, actor: Current.actor)
      @thread = thread
      @container = thread ? thread.container : container
      @actor = actor
    end

    def call
      if @container
        refused = read_refusal(@container) { |key| authorize!(key, @container) }
        return denied(refused, @container) if refused
      end
      return success(nil) unless actor_user

      rows = Delivery.unread.where(user_id: actor_user.id)
      if @thread
        rows = rows.where(thread_id: @thread.id)
      elsif @container
        rows = rows.where(thread_id: Thread.where(container: @container).select(:id))
      end
      now = Time.current
      rows.update_all(read_at: now, updated_at: now) # version: none (note_deliveries is a person's inbox; no public page reads it)
      success(nil)
    end
  end
end
```

- [ ] **Step 6: Wording.** In `Audit::Sentence::NOTE_VERBS` add `"note.resolved" => [ "resolved a note on ", "" ], "note.pinned" => [ "pinned a note on ", "" ], "note.unpinned" => [ "unpinned a note on ", "" ]`. In `Dashboard::Activity::ACTIONS` make the entry `"note" => %w[started resolved]`.

- [ ] **Step 7: The contract.** In `test/services/service_behaviour_contract_test.rb`: add `Notes::MarkRead Notes::Pin Notes::Reopen Notes::Resolve Notes::SetFollowing Notes::Unpin` to `EXPECTED_SERVICES`, and in `assert_changes_something_when_allowed` replace the audit assertion with

```ruby
      # A service that says `# audit: none` names its reason in the factory
      # too (`control_unaudited:`); every other allowed call must be logged.
      if built[:control_unaudited]
        assert_operator built[:control_unaudited].length, :>, 20, "#{label}: control_unaudited needs its reason"
        assert_equal audit_before, Audit::Event.count, "#{label} says it is not audited but recorded an event"
      else
        assert_operator Audit::Event.count, :>, audit_before, "#{label} is allowed but recorded no audit event"
      end
```

Raise the floor in `service_contract_test.rb` to `43`. In `test/support/service_calls.rb` add a line to the header's "Optional:" paragraph (`control_unaudited:` (a reason, for a service that says `# audit: none`: the control must then record nothing)) and the factories:

```ruby
    # The actor's own inbox rows: the control runs as the person told.
    "Notes::MarkRead" => lambda {
      page = create_page(title: "Noted", published: false)
      note_on(page, by: users(:one), body: "Look, @[#{users(:two).id}]")
      { call: -> { Notes::MarkRead.call(container: page) }, permission: "pages.read", on: page, control_actor: users(:two),
        control_unaudited: "a read mark is the reader's own bookkeeping, not a change to content" }
    },

    "Notes::Pin" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      { call: -> { Notes::Pin.call(thread) }, permission: "pages.edit", on: page }
    },

    "Notes::Reopen" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      assert Notes::Resolve.call(thread).ok?
      { call: -> { Notes::Reopen.call(thread) }, permission: "pages.read", on: page }
    },

    "Notes::Resolve" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      { call: -> { Notes::Resolve.call(thread) }, permission: "pages.read", on: page }
    },

    # A person's own follow row: the control runs as someone who never wrote in the thread.
    "Notes::SetFollowing" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page, by: users(:one))
      { call: -> { Notes::SetFollowing.call(thread, following: true) }, permission: "pages.read", on: page, control_actor: users(:two),
        control_unaudited: "following a thread changes who is told, not the content or the thread" }
    },

    "Notes::Unpin" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      assert Notes::Pin.call(thread).ok?
      { call: -> { Notes::Unpin.call(thread) }, permission: "pages.edit", on: page }
    },
```

- [ ] **Step 8: Run**, expect green: `PGGSSENCMODE=disable bin/rails test test/services test/models/audit test/lib`

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: resolve, reopen, pin and unpin a thread, follow it, and mark the inbox read" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 4: Removal — a purge and a block's delete take the notes with them

**Spec:** D12, §3.5 (`Notes::Remove`, "Existence under a lock", "Lifting and folding", "Duplicate"), §8 (the `Notes::Remove` bullet). **Read first:** `app/services/trash/purge.rb` and `app/services/content_blocks/destroy.rb` in full, `docs/reference/trash.md` ("The services").

A trashed record keeps its threads (nothing here touches `Trash::Move` or `Trash::Restore`); only a permanent delete removes them.

**Files:**
- Create: `app/services/notes/remove.rb`
- Modify: `app/services/trash/purge.rb`, `app/services/content_blocks/destroy.rb`, `app/models/audit/sentence.rb`, `test/lib/notes_boundary_test.rb` (`ALLOWED`), `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/services/service_contract_test.rb` (floor `44`)
- Test: `test/services/notes/remove_test.rb` (new), `test/services/trash/purge_test.rb`, `test/services/content_blocks/destroy_test.rb`, `test/services/content_blocks/duplicate_test.rb`, `test/models/audit/sentence_test.rb`

**Interfaces:**
- Consumes: `Trash::ItemPermissions#item_refusal(record) { |key| ... }`, `Notes::Thread`.
- Produces: `Notes::Remove.call(record, with: [], actor: Current.actor) -> Result(record: record)`. `record` is the page, post, image or block being deleted for good and is what is authorized; `with:` are the records that go with it (a page's blocks, a branch's other pages and their blocks, a section's blocks). Deletes every thread whose **subject** is one of them, in a constant number of statements, and records one `notes.removed` on `record` (metadata `thread_ids`) only when there was something to remove. Called inside the caller's transaction and under its lock: by `Trash::Purge` BEFORE it destroys anything (the purge's own right is checked here again, and a `pages.delete` scoped to a branch is matched against the page's closure rows, which the page's destroy deletes), by `ContentBlocks::Destroy` after the block is destroyed (a block's right is its page's, and the page is still there).

- [ ] **Step 1: Write the failing tests.** `test/services/notes/remove_test.rb`:

```ruby
require "test_helper"

class Notes::RemoveTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @other = create_page(title: "Other")
    as(users(:two)) do
      Notes::Start.call(@page, body: "On the page, @[#{users(:reader).id}]")
      Notes::Start.call(@block, body: "On the block")
      Notes::Start.call(@other, body: "Elsewhere")
    end
  end

  def left = [ Notes::Thread.count, Notes::Message.count, Notes::Delivery.count, Notes::Follow.count ]

  test "it removes the threads of the record and of what goes with it, and nothing else" do
    result = Notes::Remove.call(@page, with: [ @block ])

    assert result.ok?
    assert_equal [ @other ], Notes::Thread.all.map(&:subject)
    assert_equal [ 1, 1, 0, 1 ], left
  end

  test "one event on the record, ids only; none when there was nothing to remove" do
    ids = Notes::Thread.where(container: @page).order(:id).pluck(:id)

    Notes::Remove.call(@page, with: [ @block ])

    event = Audit::Event.order(:id).last
    assert_equal [ "notes.removed", "Page", @page.id, nil ], [ event.action, event.subject_type, event.subject_id, event.snapshot ]
    assert_equal ids, event.metadata["thread_ids"].sort
    assert_no_difference -> { Audit::Event.count } do
      assert Notes::Remove.call(@page, with: [ @block ]).ok?
    end
  end

  test "it costs the same statements for one thread as for many" do
    one = capture_sql { Notes::Remove.call(@other) }.size
    as(users(:two)) { 6.times { |index| Notes::Start.call(@block, body: "Note #{index}") } }
    many = capture_sql { Notes::Remove.call(@page, with: [ @block ]) }.size

    assert_equal one, many
  end

  test "a block's notes go with the right to edit its page; a reader is refused and nothing is removed" do
    refused = as(users(:reader)) { Notes::Remove.call(@block) }

    assert_predicate refused, :denied?
    assert_equal 3, Notes::Thread.count
    assert as(users(:two)) { Notes::Remove.call(@block) }.ok?
    assert_equal 2, Notes::Thread.count
  end
end
```

Append to `test/services/trash/purge_test.rb`:

```ruby
  test "a purged page takes its notes and its blocks' notes; a child's go with the branch" do
    page = create_page(title: "Noted", published: false)
    child = create_page(title: "Child", parent: page, published: false)
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    keep = create_page(title: "Keep")
    as(users(:two)) do
      [ page, child, block, keep ].each { |subject| Notes::Start.call(subject, body: "A note, @[#{users(:reader).id}]") }
    end
    assert Trash::Move.call(page).ok?

    assert Trash::Purge.call(page.reload).ok?

    assert_equal [ keep ], Notes::Thread.all.map(&:subject)
    assert_equal [ 1, 1, 2 ], [ Notes::Message.count, Notes::Delivery.count, Notes::Follow.count ]
    assert_equal 1, Audit::Event.where(action: "notes.removed").count
  end

  test "a purged post and a purged image take their notes" do
    post = create_post(title: "Noted", published: false)
    asset = create_media_asset
    as(users(:two)) { [ post, asset ].each { |subject| Notes::Start.call(subject, body: "A note") } }

    [ post, asset ].each do |record|
      assert Trash::Move.call(record).ok?
      assert Trash::Purge.call(record.reload).ok?
    end

    assert_equal 0, Notes::Thread.count
  end

  # `Notes::Remove` checks the purge's own right again. A `pages.delete`
  # scoped to a branch is matched against the page's closure rows, which the
  # page's destroy deletes: checked after the destroy it would refuse the
  # very person the purge had just allowed, and roll the purge back.
  test "someone whose delete right reaches one branch only purges a page of it, notes and all" do
    page = create_page(title: "Branch", published: false)
    as(users(:two)) { Notes::Start.call(page, body: "A note") }
    assert Trash::Move.call(page).ok?
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.delete", scope: { "page_ids" => [ page.id ] })

    result = as(users(:editor_branch)) { Trash::Purge.call(page.reload) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ 0, 0 ], [ Notes::Thread.count, Page.where(id: page.id).count ]
  end

  test "a purge that is refused keeps the notes" do
    page = create_page(title: "Noted", published: false)
    as(users(:two)) { Notes::Start.call(page, body: "A note") }

    assert_not Trash::Purge.call(page).ok? # not in the trash
    assert_equal 1, Notes::Thread.count
  end

  test "moving to the trash and restoring keep the notes" do
    page = create_page(title: "Noted", published: false)
    as(users(:two)) { Notes::Start.call(page, body: "A note") }

    assert Trash::Move.call(page).ok?
    assert_equal 1, Notes::Thread.count
    assert Trash::Restore.call(page.reload).ok?
    assert_equal 1, Notes::Thread.count
  end

  test "a purge costs the same statements with one note as with many" do
    counts = [ 1, 6 ].map do |notes|
      page = create_page(title: "Noted #{notes}", published: false)
      as(users(:two)) { notes.times { Notes::Start.call(page, body: "A note") } }
      assert Trash::Move.call(page).ok?
      page.reload
      capture_sql { assert Trash::Purge.call(page).ok? }.size
    end

    assert_equal counts.first, counts.last
  end
```

Append to `test/services/content_blocks/destroy_test.rb`:

```ruby
  def noted_section
    page = create_page(title: "Noted", published: false)
    section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    inside = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    as(users(:two)) { [ page, section, inside ].each { |subject| Notes::Start.call(subject, body: "A note") } }
    [ page, section, inside ]
  end

  test "deleting a block deletes its notes and leaves the page's" do
    page = create_page(title: "Noted", published: false)
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { [ page, block ].each { |subject| Notes::Start.call(subject, body: "A note") } }

    assert ContentBlocks::Destroy.call(block).ok?

    assert_equal [ page ], Notes::Thread.all.map(&:subject)
  end

  test "deleting a section with its blocks deletes the notes of each" do
    page, section, = noted_section

    assert ContentBlocks::Destroy.call(section).ok?

    assert_equal [ page ], Notes::Thread.all.map(&:subject)
  end

  test "removing a section and keeping its blocks keeps their notes" do
    page, section, inside = noted_section

    assert ContentBlocks::Destroy.call(section, keep_blocks: true).ok?

    assert_equal [ page, inside ].map(&:id).sort, Notes::Thread.pluck(:subject_id).sort
  end

  test "a block moved into a section keeps its threads under the page" do
    page = create_page(title: "Noted", published: false)
    section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    block = page.content_blocks.create!(block_type: "rich_text", position: 1)
    thread = as(users(:two)) { Notes::Start.call(block, body: "A note") }.record

    assert ContentBlocks::Reorder.call(page, [ block.id ], section: section.id, column: 1, moved_from: { block.id => { section_id: "", column: "" } }).ok?

    assert_equal [ block, page ], [ thread.reload.subject, thread.container ]
    assert_equal section.id, block.reload.section_id
  end
```

(`ContentBlocks::Reorder.new(page, ordered_ids, section: nil, column: nil, moved_from: {}, actor:)` takes the section's id and the column's new order, and `moved_from` keyed by block id with the container the block left, blank for the top level: the call above is `test/services/content_blocks/reorder_test.rb`'s own shape for a move into a column.)

Append to `test/services/content_blocks/duplicate_test.rb`:

```ruby
  test "a duplicate copies no notes" do
    page = create_page(title: "Noted", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    as(users(:two)) { Notes::Start.call(block, body: "A note") }

    assert ContentBlocks::Duplicate.call(block).ok?

    assert_equal [ block.id ], Notes::Thread.pluck(:subject_id)
  end
```

In the sentence test Task 2 added, one more line: `assert_equal "You removed the notes on “Pricing”", read(sentence_for(event("notes.removed", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))`.

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/services/notes/remove_test.rb test/services/trash/purge_test.rb test/services/content_blocks`

- [ ] **Step 3: The service.** `app/services/notes/remove.rb`:

```ruby
module Notes
  # Deletes every thread of a record that is being deleted for good, and of
  # the records that go with it (notes spec §3.5, decision D12). Not called by
  # a person: `Trash::Purge` calls it for a page with its branch and blocks, a
  # post and an image, and `ContentBlocks::Destroy` for a block and the blocks
  # deleted with a section. A thread's subject is polymorphic, so no foreign
  # key could do this -- the same reason `Media::UsageIndex.refresh` is called
  # beside it.
  #
  # It runs INSIDE the caller's transaction and under the lock the caller
  # already holds (the page's row), which is the first lock `Notes::Start`
  # takes: a note being written beside the delete either committed before and
  # is removed here, or waits and finds its subject gone. A post and an image
  # have no such lock and need none: they are purged from the trash, and
  # `Notes::Start` and `Notes::Reply` refuse a container that is not kept.
  #
  # `Trash::Purge` calls it BEFORE it destroys anything: the check below asks
  # the purge's own right again, and a `pages.delete` scoped to a branch is
  # matched against the page's closure rows, which the destroy deletes --
  # asked afterwards it would refuse the person the purge had just allowed.
  # `ContentBlocks::Destroy` calls it after the block is gone: a block's right
  # is its page's, and the page is still there.
  #
  # Constant in statements whatever the number of threads: one read of the
  # thread ids, one audit insert, one DELETE; messages, deliveries, follows
  # and reactions go by their foreign keys. `notes.removed` is recorded on
  # `record` with the ids only, and only when there was something to remove.
  #
  # It authorizes what its callers already did -- the item's delete right or
  # `trash.empty` for a page, post or image, the page's edit right for a
  # block -- so a refusal never happens on those paths; it is here so that
  # nothing else can call this to wipe notes it may not moderate.
  class Remove < ApplicationService
    include Trash::ItemPermissions

    def initialize(record, with: [], actor: Current.actor)
      @record = record
      @with = Array(with)
      @actor = actor
    end

    def call
      refused = refusal
      return denied(refused, @record) if refused

      Thread.transaction(requires_new: true) do
        ids = threads_on([ @record, *@with ]).pluck(:id)
        next if ids.empty?

        record_event("notes.removed", subject: @record, snapshot: nil, metadata: { "thread_ids" => ids })
        Thread.where(id: ids).delete_all # version: none (note tables only; no public page reads a note)
      end
      success(@record)
    end

    private

    def refusal
      if @record.is_a?(ContentBlock)
        key = "#{AccessControl::Checker::BLOCK_OWNER_PREFIX.fetch(@record.owner.class.name)}.edit"
        return (key unless authorize!(key, @record))
      end

      refused = item_refusal(@record) { |key| authorize!(key, @record) }
      refused unless refused.nil? || authorize!("trash.empty", nil)
    end

    # One relation over every record, whatever their classes.
    def threads_on(records)
      records.group_by { |record| record.class.polymorphic_name }
        .map { |type, list| Thread.where(subject_type: type, subject_id: list.map(&:id)) }.reduce(:or)
    end
  end
end
```

- [ ] **Step 4: The callers.** In `app/services/trash/purge.rb`:

`#purge_branch`: after the `Page.where(id: pages.map(&:id)).order(:id).lock.pluck(:id)` line and BEFORE the `pages.each` loop:

```ruby
      # The threads on these pages and their blocks (notes spec D12):
      # polymorphic like the usage rows below, so removed by hand, once for
      # the branch. Before any page is destroyed: `Notes::Remove` asks this
      # purge's own right again, and a `pages.delete` scoped to a branch is
      # matched against the page's closure rows, which its destroy deletes.
      # (`content_blocks.to_a` loads the very objects the loop below reads
      # again and the destroy goes on to destroy.)
      remove_notes(with: (pages - [ @record ]) + pages.flat_map { |page| page.content_blocks.to_a })
```

`#purge_post`: `remove_notes` as the first statement, before `@record.destroy`. `#purge_asset`: `remove_notes` after the `used?` check and before `@record.destroy`. (A refusal further down rolls the removal back with everything else.) And the private method:

```ruby
    def remove_notes(with: [])
      Notes::Remove.call(@record, with: with, actor: actor).ok? || raise(ActiveRecord::Rollback)
    end
```

In `app/services/content_blocks/destroy.rb`, after the `Translations::StateIndex.refresh(@block)` line:

```ruby
        # The block's threads, and those of the blocks deleted with a section
        # (notes spec D12). Lifted blocks keep theirs: their container is the
        # page, which has not changed.
        Notes::Remove.call(@block, with: (@keep_blocks ? [] : inside), actor: actor).ok? || raise(ActiveRecord::Rollback)
```

Add a sentence to each class comment naming the call. In `Audit::Sentence::NOTE_VERBS` add `"notes.removed" => [ "removed the notes on ", "" ]`.

- [ ] **Step 5: The boundary and the contract.** In `test/lib/notes_boundary_test.rb`:

```ruby
  ALLOWED = {
    "app/services/trash/purge.rb" => "a purge deletes a page, a post or an image for good, and their threads have no foreign key to go by",
    "app/services/content_blocks/destroy.rb" => "a block's delete is permanent, and its threads have no foreign key to go by"
  }.freeze
```

`EXPECTED_SERVICES` gains `Notes::Remove`; the floor becomes `44`; the factory:

```ruby
    "Notes::Remove" => lambda {
      page = create_page(title: "Noted", published: false)
      note_on(page)
      trashed(page)
      { call: -> { Notes::Remove.call(page) }, permission: "pages.delete", on: page }
    },
```

- [ ] **Step 6: Run**, expect green: `PGGSSENCMODE=disable bin/rails test test/services test/models/audit test/lib`. No existing purge or destroy test pins a total number of statements (checked: `purge_test.rb` "the branch's pages are locked, in id order, before the first block is deleted" and `destroy_test.rb`'s three `capture_sql` tests assert the ORDER of statements and count only `FROM "pages" … FOR UPDATE` and `UPDATE "content_blocks"`; `content_blocks_test.rb` counts `SELECT "content_blocks".*`), and `Notes::Remove` issues none of those: it takes no lock of its own and reads no block. So none needs a number raised; if one of them fails, `Notes::Remove` is locking or reading what its caller already holds.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: a purge and a block's delete remove the notes on what they delete" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 5: Reading — counts, the listing, the two views of the notes frame and the scoped GET endpoints

**Spec:** §3.3 (a delivery is read when its owner opens the thread), §3.4 (lookups, 404), §4.2 (the two views: the list, and the thread that replaces it), §4.5 (Look), §7 ("Very many threads"), §8 (Access, Constant queries). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (the build handoff: follow it for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins; if the file is not on the branch yet, build from the spec's §4.5 and the existing components and say so in the task report), `docs/reference/design-system.md`, `docs/reference/i18n.md`, `app/components/admin/admin_component.rb`, `app/values/block_outline.rb`, `app/controllers/admin/base_controller.rb`.

After this task `GET /cs-studio/notes/page/<id>` answers the frame every later surface embeds, read-only. The frame has two views under one id, `turbo-frame#notes`: **the list** (rows, grouped) and **one thread**, which replaces the list when a row is followed and has a Back link to it. Nothing can be written yet (Task 6 adds the forms).

**Files:**
- Create: `app/queries/notes/counts.rb`, `app/queries/notes/listing.rb`, `app/helpers/admin/note_paths_helper.rb`, `app/controllers/concerns/admin/note_container.rb`, `app/controllers/admin/notes_controller.rb`, `app/controllers/admin/note_threads_controller.rb`, `app/views/admin/notes/index.html.erb`, `thread.html.erb`, `resolved.html.erb`, `app/components/admin/notes_screen/{counts,body,message,thread,thread_row,list}_component.rb` and their `.html.erb` templates (`counts` is inline)
- Modify: `config/routes.rb`, `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb` (`CONVERTED`)
- Test: `test/queries/notes/counts_test.rb`, `test/queries/notes/listing_test.rb`, `test/integration/admin/notes_test.rb`, `test/components/admin/notes_screen/body_component_test.rb` (new)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `Notes::Counts.for_container(container, user: nil) -> { "total" => Integer, "subjects" => { "<key>" => Integer }, "unread" => ["<key>", ...] }` (open threads, one grouped query; with a user one more, for the keys whose threads hold an unread delivery for them: what turns a count accent, spec §4.5); `Notes::Counts.by_container(type, ids) -> { id => Integer }` (one grouped query; `{}` for no ids); `Notes::Counts.unread_among(type, ids, user) -> Set<Integer>` (the container ids with an open thread holding an unread delivery for the user; one query, none without a user or ids).
  - `Notes::Listing.new(container, limit: 50, viewer: nil)` (`viewer` is the user the counts' `unread` is read for): `#pinned`, `#groups -> [Group(subject, key, threads)]` (the record's own group first, then one per block in `BlockOutline#reading_order`), `#open_count`, `#resolved_count`, `#more?`, `#next_limit`, `#resolved`, `#counts`, `#find(id) -> Notes::Thread | nil`, `#subject_of(thread)`, `#users -> { id => User }`, `#following?(thread, user)`, `#unread?(thread, user)`.
  - Routes (inside the `admin` scope; `type` is `page|post|media`): `admin_record_notes_path(type, id)` → `notes#index` (the list); `admin_record_note_thread_path(type, id, thread)` → `note_threads#show` (one thread, in the same frame; marks the viewer's deliveries of that thread read); `admin_resolved_record_notes_path(type, id)` → `notes#resolved`; `admin_record_note_counts_path(type, id)` → `notes#counts` (JSON).
  - `Admin::NotePathsHelper#note_args(container) -> ["page" | "post" | "media", id]`, `#note_subject_name(record, container, type) -> String`.
  - `Admin::NoteContainer` (controller concern): `@container`, `container_threads`, `note_view`, `note_frame_params(**extra)`, `notes_path(**extra)`, `thread_path(thread, **extra)`, `render_list(status: :ok, failed: nil, notice: nil)`, `render_thread(thread, status: :ok, failed: nil)`.
  - Markup, list view: `turbo-frame#notes` > `div#notes-list[data-notes-view=list][data-notes-container=<key>]` > `section#notes-pinned`, `section#notes-open` > `section#notes-group-<key>[data-notes-group=<key>][tabindex=-1]` > `a#note-row-<id>[data-note-row=<id>]` (`[data-unread]` and a `[data-note-new]` label while it holds an unread delivery for the viewer; `[data-note-replies]`); `details#notes-resolved-section` > `turbo-frame#notes-resolved`; `a[data-note-new-link]` in the empty state.
  - Markup, thread view: `turbo-frame#notes` > `div#note-thread-<id>[data-notes-view=thread][data-note-thread=<id>][data-state][data-notes-container=<key>][tabindex=-1]` > `a[data-note-back]`, `div#note-thread-<id>-messages[data-note-part=messages]` > `div#note-message-<id>`.
  - Both views carry `span[data-admin--notes-target=counts][data-counts=<json>]`.
  - `Admin::NotesScreen::ListComponent.new(listing:, viewer:, locale:, view:, type:, compose: nil, failed: nil, notice: nil)`, `ThreadRowComponent.new(thread:, listing:, viewer:, type:, view:, show_subject: false)`, `ThreadComponent.new(thread:, listing:, viewer:, locale:, view:, type:, failed: nil)`, `MessageComponent.new(message:, thread:, listing:, viewer:, type:, view:, failed: nil)`, `BodyComponent.new(body:, users:)`, `CountsComponent.new(counts:, id: nil)`.

- [ ] **Step 1: Write the failing tests.** `test/queries/notes/counts_test.rb`:

```ruby
require "test_helper"

class Notes::CountsTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) do
      Notes::Start.call(@page, body: "One")
      2.times { Notes::Start.call(@block, body: "Two") }
      Notes::Resolve.call(Notes::Start.call(@block, body: "Done").record)
    end
  end

  test "open threads by subject, with the total, in one query" do
    counts = nil
    statements = capture_sql { counts = Notes::Counts.for_container(@page) }

    assert_equal({ "total" => 3, "subjects" => { "Page-#{@page.id}" => 1, "ContentBlock-#{@block.id}" => 2 }, "unread" => [] }, counts)
    assert_equal 1, statements.size
  end

  test "with a user, the keys whose open threads hold something unread for them, in one more query" do
    as(users(:two)) { Notes::Start.call(@block, body: "For @[#{users(:reader).id}]") }
    counts = nil
    statements = capture_sql { counts = Notes::Counts.for_container(@page, user: users(:reader)) }

    assert_equal [ "ContentBlock-#{@block.id}" ], counts["unread"]
    assert_equal 2, statements.size
    assert_equal [], Notes::Counts.for_container(@page, user: users(:two))["unread"]
    assert_equal Set[@page.id], Notes::Counts.unread_among("Page", [ @page.id, 0 ], users(:reader))
    assert_empty capture_sql { assert_empty Notes::Counts.unread_among("Page", [ @page.id ], nil) }
  end

  test "open threads per container, for a list" do
    other = create_page(title: "Quiet")

    assert_equal({ @page.id => 3 }, Notes::Counts.by_container("Page", [ @page.id, other.id ]))
    assert_empty capture_sql { assert_equal({}, Notes::Counts.by_container("Page", [])) }
  end
end
```

`test/queries/notes/listing_test.rb`:

```ruby
require "test_helper"

class Notes::ListingTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @right = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 2, position: 0)
    @left = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0)
    @last = @page.content_blocks.create!(block_type: "rich_text", position: 1)
  end

  def note(subject, body = "A note") = as(users(:two)) { Notes::Start.call(subject, body: body) }.record

  test "groups: the record first, then the blocks in the page's display order; pinned and resolved apart" do
    on_last, on_right, on_left, on_page = [ @last, @right, @left, @page ].map { |subject| note(subject) }
    pinned = note(@left, "Ask Dana first")
    done = note(@page, "Done")
    as(users(:two)) { Notes::Pin.call(pinned); Notes::Resolve.call(done) }

    listing = Notes::Listing.new(@page.reload)

    assert_equal [ pinned ], listing.pinned
    assert_equal [ @page, @left, @right, @last ], listing.groups.map(&:subject)
    assert_equal [ [ on_page ], [ on_left ], [ on_right ], [ on_last ] ], listing.groups.map(&:threads)
    assert_equal "ContentBlock-#{@left.id}", listing.groups.second.key
    assert_equal [ 5, 1 ], [ listing.open_count, listing.resolved_count ]
    assert_equal [ done ], listing.resolved
    assert_equal @left, listing.subject_of(pinned)
  end

  test "the newest thread of a group comes first" do
    old = note(@page, "Old")
    recent = travel_to(1.minute.from_now) { note(@page, "New") }
    travel_to(2.minutes.from_now) { as(users(:reader)) { Notes::Reply.call(old, body: "Bumped") } }

    assert_equal [ old, recent ], Notes::Listing.new(@page).groups.first.threads
  end

  test "it lists 50 and knows there are more; the counts stay exact" do
    as(users(:two)) { 51.times { |index| Notes::Start.call(@page, body: "Note #{index}") } }
    listing = Notes::Listing.new(@page)

    assert_equal [ 50, 51, true, 100 ], [ listing.groups.sum { |group| group.threads.size }, listing.open_count, listing.more?, listing.next_limit ]
    assert_equal 51, Notes::Listing.new(@page, limit: 100).groups.first.threads.size
    assert_equal 50, Notes::Listing.new(@page, limit: "junk").groups.first.threads.size
  end

  test "it costs the same statements with two threads as with twelve" do
    read = lambda do
      capture_sql do
        listing = Notes::Listing.new(Page.find(@page.id))
        listing.pinned
        listing.groups.each { |group| group.threads.each { |thread| thread.messages.each(&:body) } }
        [ listing.open_count, listing.resolved_count, listing.users, listing.following?(Notes::Thread.first, users(:two)), listing.unread?(Notes::Thread.first, users(:two)) ]
      end.size
    end
    2.times { note(@left) }
    few = read.call
    10.times { |index| as(users(:reader)) { Notes::Reply.call(note([ @page, @right, @last ][index % 3]), body: "Hi @[#{users(:two).id}]") } }

    assert_equal few, read.call
  end

  test "find is among this container's threads only" do
    mine = note(@page)
    elsewhere = note(create_page(title: "Other"))
    listing = Notes::Listing.new(@page)

    assert_equal mine, listing.find(mine.id)
    assert_nil listing.find(elsewhere.id)
  end
end
```

`test/components/admin/notes_screen/body_component_test.rb`:

```ruby
require "test_helper"

class Admin::NotesScreen::BodyComponentTest < ViewComponent::TestCase
  test "text is escaped, a mention reads as the user's name, a link is a link that leaves the tab" do
    dana = users(:two).tap { |user| user.update!(name: "Dana") }

    render_inline(Admin::NotesScreen::BodyComponent.new(body: "Ask @[#{dana.id}] <b>now</b>: https://example.com/a.", users: { dana.id => dana }))

    assert_selector "[data-note-mention]", text: "@Dana"
    assert_no_selector "b"
    assert_text "<b>now</b>"
    assert_selector "a[href='https://example.com/a'][target=_blank][rel='noopener noreferrer']", text: "https://example.com/a"
  end

  test "a mention of a user who is gone reads as a deleted user" do
    render_inline(Admin::NotesScreen::BodyComponent.new(body: "Ask @[424242]", users: {}))

    assert_selector "[data-note-mention]", text: "@a deleted user"
  end
end
```

`test/integration/admin/notes_test.rb`:

```ruby
require "test_helper"

# The notes frame, its two views and its parts (notes spec §4.2, plan "Stable
# ids and their endpoints"): each is a GET scoped to a container the viewer
# may read.
class Admin::NotesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@block, body: "Is €49 right, @[#{users(:reader).id}]? See https://example.com", quote: "€49 a month") }.record
    @stranger = User.create!(email_address: "stranger@example.com", password: "password-password")
    @base = "/cs-studio/notes/page/#{@page.id}"
  end

  def frame = { "Turbo-Frame" => "notes" }

  test "the list: a row per open thread under its block's group, with the author, the first words, and new for the person it is addressed to" do
    as(users(:one)) { Notes::Reply.call(@thread, body: "Yes") }
    sign_in_as(users(:reader))

    get @base, headers: frame

    assert_response :ok
    assert_select "turbo-frame#notes #notes-list[data-notes-view=list][data-notes-container='Page-#{@page.id}']"
    assert_select "section#notes-group-ContentBlock-#{@block.id} a#note-row-#{@thread.id}[data-note-row][data-unread][href='#{@base}/threads/#{@thread.id}']" do
      assert_select "strong", text: "two@example.com"
      assert_select "span", text: /Is €49 right, @reader@example.com\?/
      assert_select "[data-note-replies]", text: "1 reply"
      assert_select "[data-note-new]", text: "new"
    end
    assert_select "span[data-admin--notes-target=counts]" do |nodes|
      assert_equal({ "total" => 1, "subjects" => { "ContentBlock-#{@block.id}" => 1 }, "unread" => [ "ContentBlock-#{@block.id}" ] }, JSON.parse(nodes.first["data-counts"]))
    end
    assert_select "#sidebar", count: 0 # a frame request gets the frame, not the shell
    assert_equal 2, Notes::Delivery.unread.where(user: users(:reader)).count # looking at the list reads nothing
  end

  test "the thread replaces the list in the same frame: Back, what it is on, the quote, the messages with a mention and a link" do
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_response :ok
    assert_select "turbo-frame#notes #notes-list", count: 0
    assert_select "turbo-frame#notes #note-thread-#{@thread.id}[data-notes-view=thread][data-state=open]" do
      assert_select "a[data-note-back][href='#{@base}']"
      assert_select "h3", text: "Rich text"
      assert_select "blockquote", text: "€49 a month"
      assert_select "#note-thread-#{@thread.id}-messages #note-message-#{@thread.first_message.id} [data-note-mention]", text: "@reader@example.com"
      assert_select "a[href='https://example.com']"
    end
    assert_select "span[data-admin--notes-target=counts]"
  end

  test "a long thread folds its middle, and a thread started on another language tab says so" do
    as(users(:two)) { 4.times { |index| Notes::Reply.call(@thread, body: "Reply #{index}") } }
    @thread.update!(origin_locale: "de")
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_select "#note-thread-#{@thread.id}-messages details summary", text: "Show 2 more"
    assert_select "#note-thread-#{@thread.id}-messages details [data-note-message]", count: 2
    assert_select "#note-thread-#{@thread.id}-messages [data-note-message]", count: 5
    assert_select "[data-note-badge=origin]", text: /Written on/

    get "#{@base}/threads/#{@thread.id}", params: { locale: "de" }, headers: frame
    assert_select "[data-note-badge=origin]", count: Locales.enabled?("de") ? 0 : 1
  end

  test "opening a thread marks the viewer's deliveries of that thread read, and no other" do
    other = as(users(:two)) { Notes::Start.call(@page, body: "And this, @[#{users(:reader).id}]") }.record
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_equal [ other.id ], Notes::Delivery.unread.where(user: users(:reader)).pluck(:thread_id)
    get @base, headers: frame
    assert_select "a#note-row-#{@thread.id}[data-unread]", count: 0
    assert_select "a#note-row-#{other.id}[data-unread]"
  end

  test "pinned rows come first and say what they are on; the resolved rows and the counts are fetched on their own" do
    as(users(:two)) do
      Notes::Pin.call(@thread)
      Notes::Resolve.call(Notes::Start.call(@page, body: "Done and dusted").record)
    end
    sign_in_as(users(:reader))

    get @base, headers: frame
    assert_select "section#notes-pinned a#note-row-#{@thread.id}", text: /Rich text/
    assert_select "details#notes-resolved-section turbo-frame#notes-resolved[loading=lazy][src='#{@base}/resolved']"

    get "#{@base}/resolved"
    assert_select "turbo-frame#notes-resolved a[data-note-row][data-turbo-frame=notes]", text: /Done and dusted/

    get "#{@base}/counts"
    assert_equal({ "total" => 1, "subjects" => { "ContentBlock-#{@block.id}" => 1 }, "unread" => [ "ContentBlock-#{@block.id}" ] }, response.parsed_body)
  end

  test "a record without notes shows the empty state with New note" do
    quiet = create_page(title: "Quiet")
    sign_in_as(users(:reader))

    get "/cs-studio/notes/page/#{quiet.id}", headers: frame

    assert_select "#notes-list a[data-note-new-link][href='/cs-studio/notes/page/#{quiet.id}?compose=Page-#{quiet.id}']"
  end

  test "outside the read scope every part is not found, never forbidden" do
    other = create_page(title: "Other")
    elsewhere = as(users(:two)) { Notes::Start.call(other, body: "Elsewhere") }.record
    sign_in_as(@stranger)

    [ "", "/resolved", "/counts", "/threads/#{@thread.id}" ].each do |part|
      get "#{@base}#{part}"
      assert_response :not_found, part
    end

    sign_in_as(users(:reader))
    get "#{@base}/threads/#{elsewhere.id}" # a real thread, of another page
    assert_response :not_found
    get "/cs-studio/notes/page/999999999"
    assert_response :not_found
  end

  test "a trashed page's notes are not found; an image's need the media right" do
    asset = create_media_asset
    as(users(:two)) { Notes::Start.call(asset, body: "Crop it") }
    @page.update!(trashed_at: Time.current)

    sign_in_as(users(:two))
    get @base
    assert_response :not_found
    get "/cs-studio/notes/media/#{asset.id}", headers: frame
    assert_response :ok
    assert_select "a[data-note-row]", count: 1

    sign_in_as(@stranger)
    get "/cs-studio/notes/media/#{asset.id}"
    assert_response :forbidden
  end

  test "the list costs the same statements with one thread as with nine" do
    sign_in_as(users(:two))
    get @base, headers: frame
    one = capture_sql { get @base, headers: frame }.size
    as(users(:reader)) { 8.times { |index| Notes::Reply.call(Notes::Start.call([ @page, @block ][index % 2], body: "Note #{index}").record, body: "And @[#{users(:two).id}]") } }
    get @base, headers: frame

    assert_equal one, capture_sql { get @base, headers: frame }.size
  end
end
```

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/queries/notes test/integration/admin/notes_test.rb test/components/admin/notes_screen`

- [ ] **Step 3: The queries.** `app/queries/notes/counts.rb`:

```ruby
module Notes
  # How many OPEN threads there are, read in one grouped query per surface
  # (notes spec §9, "Counts on every list are where a slow query hides").
  # A pinned thread is open; a resolved one is not counted (decision D13).
  # Callers hand over records they have already narrowed through the read
  # scope: nothing here decides who may see a count.
  class Counts
    # One record's screen: the header's total and each marker's own number.
    # `unread` is the keys whose open threads hold a delivery `user` has not
    # read: what turns that count accent, the one meaning accent has here
    # (spec §4.5). A second query beside the first, and only for a user.
    def self.for_container(container, user: nil)
      open = Thread.unresolved.where(container: container)
      by_subject = open.group(:subject_type, :subject_id).count
      unread = user ? unread_for(open, user).distinct.pluck(:subject_type, :subject_id).map { |type, id| Notes.key(type, id) } : []
      { "total" => by_subject.values.sum, "subjects" => by_subject.to_h { |(type, id), count| [ Notes.key(type, id), count ] }, "unread" => unread }
    end

    # A list's rows: `{ container id => open threads on it and on its blocks }`.
    def self.by_container(type, ids)
      return {} if ids.empty?

      Thread.unresolved.where(container_type: type, container_id: ids).group(:container_id).count
    end

    # The containers among `ids` with an open thread that holds something
    # unread for `user`: the rows whose count is drawn in accent.
    def self.unread_among(type, ids, user)
      return Set.new if user.nil? || ids.empty?

      unread_for(Thread.unresolved.where(container_type: type, container_id: ids), user).distinct.pluck(:container_id).to_set
    end

    def self.unread_for(threads, user) = threads.where(id: Delivery.unread.where(user_id: user.id).select(:thread_id))
    private_class_method :unread_for
  end
end
```

`app/queries/notes/listing.rb`:

```ruby
module Notes
  # Everything one record's notes frame shows (notes spec §4.2), read in a
  # constant number of queries: the open threads with their messages (two),
  # the counts (one grouped, one for the resolved), the people named (one),
  # the viewer's follows (one) and, for a page, its blocks (one, for the
  # order of the groups). The resolved threads are read only when asked for.
  #
  # Open threads are grouped by what they are on: the record itself first,
  # then one group per block, in the order the page shows its blocks
  # (`BlockOutline#reading_order`). Pinned threads are listed apart, first.
  # 50 are listed (`PAGE`), newest activity first, and "Show more" asks for 50
  # more; the counts are exact whatever the limit.
  class Listing
    Group = Data.define(:subject, :key, :threads)

    PAGE = 50
    MAX = 500

    attr_reader :container

    def initialize(container, limit: PAGE, viewer: nil)
      @container = container
      @viewer = viewer
      @limit = limit.to_s.match?(/\A\d+\z/) ? limit.to_i.clamp(PAGE, MAX) : PAGE
    end

    def pinned = open_threads.select(&:pinned)

    def groups
      by_subject = open_threads.reject(&:pinned).group_by { |thread| Notes.key(thread.subject_type, thread.subject_id) }
      subjects.filter_map do |key, subject|
        Group.new(subject: subject, key: key, threads: by_subject[key]) if by_subject.key?(key)
      end
    end

    def counts = @counts ||= Counts.for_container(container, user: @viewer)

    def open_count = counts.fetch("total")

    def resolved_count = @resolved_count ||= scope.resolved.count

    def more? = open_count > open_threads.size

    def next_limit = @limit + PAGE

    def resolved = @resolved ||= load(scope.resolved.order(resolved_at: :desc, id: :desc))

    # One thread of this container, or nil: never a thread by its id alone.
    def find(id) = load(scope.where(id: id)).first

    def subject_of(thread) = subjects[Notes.key(thread.subject_type, thread.subject_id)]

    # Everyone a loaded thread names: authors, the mentioned, who resolved it.
    def users
      @users ||= begin
        ids = loaded.flat_map { |thread| [ thread.resolved_by_id, *thread.messages.flat_map { |message| [ message.author_id, *message.mentioned_user_ids ] } ] }
        User.where(id: ids.compact.uniq).index_by(&:id)
      end
    end

    def following?(thread, user)
      return false unless user

      @following ||= Follow.where(user_id: user.id, following: true, thread_id: scope.select(:id)).pluck(:thread_id).to_set
      @following.include?(thread.id)
    end

    # Does this thread hold a delivery the user has not read? ("new" on its
    # row.) One query for the whole listing.
    def unread?(thread, user)
      return false unless user

      @unread ||= Delivery.unread.where(user_id: user.id, thread_id: scope.select(:id)).distinct.pluck(:thread_id).to_set
      @unread.include?(thread.id)
    end

    private

    def scope = Thread.where(container: container)

    def open_threads = @open_threads ||= load(scope.unresolved.order(pinned: :desc, last_message_at: :desc, id: :desc))

    def load(relation)
      relation.limit(@limit).includes(:messages).to_a.tap { |threads| (@loaded ||= []).concat(threads) }
    end

    def loaded = (@loaded || open_threads)

    # `{ key => record }` in display order: the container, then a page's
    # blocks as the page shows them.
    def subjects
      @subjects ||= begin
        records = [ container ]
        records.concat(BlockOutline.new(container.content_blocks).reading_order) if container.is_a?(Page)
        records.to_h { |record| [ Notes.key(record), record ] }
      end
    end
  end
end
```

- [ ] **Step 4: Routes, helper, concern, controllers.** In `config/routes.rb`, inside the `scope ContentSpiel::ADMIN_PATH, module: :admin, as: :admin` block, before `post "dashboard/draft"`:

```ruby
    # Notes on content (notes spec §3.4, §4). Everything about one record's
    # notes hangs under that record -- `/notes/page/3`, `/notes/post/8`,
    # `/notes/media/5` -- so a controller finds the container through the read
    # scope first and a thread only among that container's: a thread is never
    # found by its id alone. Each part of the notes UI has its own GET here
    # (the list, one thread, the resolved ones, the counts), which is what a
    # live signal asks the browser to fetch again.
    scope "notes/:container_type/:container_id", constraints: { container_type: /page|post|media/, container_id: /\d+/ } do
      get "", to: "notes#index", as: :record_notes
      get "resolved", to: "notes#resolved", as: :resolved_record_notes
      get "counts", to: "notes#counts", as: :record_note_counts, defaults: { format: :json }
      get "threads/:id", to: "note_threads#show", as: :record_note_thread, constraints: { id: /\d+/ }
    end
```

`app/helpers/admin/note_paths_helper.rb`:

```ruby
module Admin
  # The two leading arguments of every `admin_record_note*_path`: which kind
  # of record, and which one. Route segments are a controller's and a
  # component's business, so this lives here and not on `Notes`.
  module NotePathsHelper
    TYPES = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze # i18n-ok: class names keyed to route segments, not copy

    def note_args(container) = [ TYPES.fetch(container.class.polymorphic_name), container.id ]
  end
end
```

`app/helpers/admin/note_paths_helper.rb` also names what a thread is on, for a group's heading, a pinned row and the thread view alike; add to it:

```ruby
    # What a thread is on, as its group's heading says it: the record itself
    # ("This page"), or the block the way its card names it -- with its column
    # inside a section (`Admin::EditorScreen::PanelTitleComponent`'s own key).
    def note_subject_name(record, container, type)
      return t("admin.notes.subject.#{type}") if record.nil? || record == container

      label = record.definition&.label || record.block_type
      record.section_id ? t("admin.components.editor_screen.panel_title.title", type: label, column: record.section_column) : label
    end
```

`app/controllers/concerns/admin/note_container.rb`:

```ruby
module Admin
  # What every notes controller shares: the container, found THROUGH THE READ
  # SCOPE before anything else is looked at (notes spec §3.4). A page or post
  # outside the viewer's scope, a trashed one and an id that names nothing are
  # the same 404; the media library has no per-image right, so its gate is
  # the module's own (`media.upload`, a 403 like `Admin::MediaController`'s).
  # A thread, a message or a file is then looked up among `container_threads`
  # only.
  #
  # The notes frame has two views under one id, `turbo-frame#notes`: the list
  # (`render_list`) and one thread (`render_thread`), which replaces it.
  module NoteContainer
    extend ActiveSupport::Concern

    included do
      before_action :set_container
      # The three notes views ask which surface they are drawn for.
      helper_method :note_view
    end

    private

    def set_container
      @container =
        case params[:container_type]
        when "page" then admin_scope(Page.all).find(params[:container_id])
        when "post" then admin_scope(Post.all).find(params[:container_id])
        else
          return forbidden! unless can?("media.upload")

          Media::Asset.kept.find(params[:container_id])
        end
    end

    def container_threads = Notes::Thread.where(container: @container)

    # Which surface the frame is drawn on; it travels in every notes URL so
    # an answer is drawn for the same surface, and a new thread records it.
    def note_view = Notes::Thread::ORIGIN_VIEWS.include?(params[:view].to_s) ? params[:view].to_s : "editor"

    def note_frame_params(**extra) = { view: (note_view unless note_view == "editor"), **admin_url_options, **extra }.compact

    def notes_path(**extra) = admin_record_notes_path(params[:container_type], @container.id, **note_frame_params(**extra))

    def thread_path(thread, **extra) = admin_record_note_thread_path(params[:container_type], @container.id, thread, **note_frame_params(**extra))

    # The list: what `index` answers, and what a refused or failed new note
    # answers with its own status, the typed text kept (`failed`).
    def render_list(status: :ok, failed: nil, notice: nil)
      @listing = Notes::Listing.new(@container, limit: params[:limit], viewer: Current.user)
      @failed = failed
      @notice = notice
      render "admin/notes/index", status: status, layout: turbo_frame_request? ? false : "admin"
    end

    # One thread, in the list's place: what `show` answers, and what a
    # refused or failed write on that thread answers.
    def render_thread(thread, status: :ok, failed: nil)
      @listing = Notes::Listing.new(@container, viewer: Current.user)
      @thread = @listing.find(thread.id) or raise ActiveRecord::RecordNotFound
      @failed = failed
      render "admin/notes/thread", status: status, layout: turbo_frame_request? ? false : "admin"
    end
  end
end
```

`app/controllers/admin/notes_controller.rb`:

```ruby
module Admin
  # One record's notes (notes spec §4.2): the list view of the frame the
  # drawer and the media panel embed, and its parts. Reading the list marks
  # nothing read: a row says "new" until its thread is opened.
  class NotesController < BaseController
    include NoteContainer

    NOTICES = %w[gone].freeze

    def index
      render_list(notice: (params[:notice] if NOTICES.include?(params[:notice])))
    end

    def resolved
      @listing = Notes::Listing.new(@container, limit: params[:limit], viewer: Current.user)
      render :resolved, layout: false
    end

    def counts
      render json: Notes::Counts.for_container(@container, user: Current.user)
    end
  end
end
```

`app/controllers/admin/note_threads_controller.rb` (Task 6 adds the writes):

```ruby
module Admin
  # One thread of a record's notes, always looked up among the container's
  # threads. `show` is the thread view of the notes frame; opening a thread
  # is what marks the viewer's deliveries of it read (notes spec §3.3) --
  # through the service, as every write is.
  class NoteThreadsController < BaseController
    include NoteContainer

    def show
      thread = container_threads.find(params[:id])
      Notes::MarkRead.call(thread: thread)
      render_thread(thread)
    end
  end
end
```

`app/views/admin/notes/index.html.erb`:

```erb
<%# One record's notes, the list view (notes spec §4.2). The frame is what the
    editors' drawer and the media panel embed by its `src`; opened on its own
    (no script) it is this same list inside the shell. %>
<% content_for :title, t(".title") %>
<turbo-frame id="notes">
  <%= render Admin::NotesScreen::ListComponent.new(listing: @listing, viewer: Current.user, locale: admin_locale, view: note_view,
        type: params[:container_type], compose: params[:compose], failed: @failed, notice: @notice) %>
</turbo-frame>
```

`app/views/admin/notes/thread.html.erb`:

```erb
<%# One thread, in the list's place (notes spec §4.2): the same frame id, so
    following a row replaces the list and Back replaces the thread. %>
<% content_for :title, t("admin.notes.index.title") %>
<turbo-frame id="notes">
  <%= render Admin::NotesScreen::ThreadComponent.new(thread: @thread, listing: @listing, viewer: Current.user, locale: admin_locale,
        view: note_view, type: params[:container_type], failed: @failed) %>
</turbo-frame>
```

`app/views/admin/notes/resolved.html.erb`:

```erb
<%# The resolved threads' rows, loaded when "Resolved" is opened (notes spec
    §4.2). A row leads to its thread in the notes frame, not in this one. %>
<turbo-frame id="notes-resolved">
  <div class="flex flex-col gap-2 pt-2">
    <% @listing.resolved.each do |thread| %>
      <%= render Admin::NotesScreen::ThreadRowComponent.new(thread: thread, listing: @listing, viewer: Current.user,
            type: params[:container_type], view: note_view, show_subject: true) %>
    <% end %>
  </div>
</turbo-frame>
```

- [ ] **Step 5: The components.** All under `app/components/admin/notes_screen/`. The classes below are a working baseline built from the existing tokens; **where the handoff names a class, a size or a state for a part, use the handoff's**, and keep every id and `data-` attribute named under Interfaces.

`counts_component.rb`:

```ruby
module Admin
  module NotesScreen
    # One record's open-note counts as data for `admin--notes`, which fills
    # the header's button and every marker from it (`Notes::Counts
    # .for_container`). Hidden; it carries numbers and keys, no text. With
    # `id:` it is the page's own copy (`#notes-counts`, a Turbo Stream can
    # replace it); without, the copy every answer of the notes frame brings.
    class CountsComponent < Admin::AdminComponent
      def initialize(counts:, id: nil)
        @counts = counts
        @id = id
      end

      def call = tag.span(id: @id, hidden: true, data: { "admin--notes-target": "counts", counts: @counts.to_json })
    end
  end
end
```

`body_component.rb`:

```ruby
module Admin
  module NotesScreen
    # A message's text (decision D8): plain text as typed, line breaks kept,
    # a mention as the user's CURRENT name and a bare URL as a link that
    # opens in another tab. `Notes::Text` splits it; everything here is
    # escaped by ERB, so a note can hold "<b>" and show "<b>".
    class BodyComponent < Admin::AdminComponent
      def initialize(body:, users:)
        @body = body
        @users = users
      end

      private

      attr_reader :users

      def parts = ::Notes::Text.parts(@body)
    end
  end
end
```

`body_component.html.erb` (one line, so `whitespace-pre-wrap` shows no template indentation):

```erb
<p class="whitespace-pre-wrap break-words text-sm text-ink"><% parts.each do |part| %><% if part.kind == :mention %><span data-note-mention class="rounded-cs bg-accent-tint px-1 font-medium">@<%= render Admin::UserNameComponent.new(user: users[part.value], user_id: part.value) %></span><% elsif part.kind == :link %><%= link_to part.value, part.value, target: "_blank", rel: "noopener noreferrer", class: "text-accent underline hover:text-accent-hover" %><% else %><%= part.value %><% end %><% end %></p>
```

`message_component.rb`:

```ruby
module Admin
  module NotesScreen
    # One message: who, when, "edited", the text. (Task 6 adds Edit and
    # Delete; Tasks 15 and 16 the reactions and the files.)
    class MessageComponent < Admin::AdminComponent
      def initialize(message:, thread:, listing:, viewer:, type:, view:, failed: nil)
        @message = message
        @thread = thread
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
        @failed = failed
      end

      def dom_id = "note-message-#{message.id}"

      private

      attr_reader :message, :thread, :listing, :viewer, :type, :view, :failed

      def author = listing.users[message.author_id]

      def own? = viewer.present? && message.author_id == viewer.id
    end
  end
end
```

`message_component.html.erb`:

```erb
<div id="<%= dom_id %>" class="flex flex-col gap-1" data-note-message="<%= message.id %>">
  <p class="flex flex-wrap items-baseline gap-x-2 text-[12px] text-meta">
    <strong class="font-semibold text-ink"><%= render Admin::UserNameComponent.new(user: author, user_id: message.author_id) %></strong>
    <%= render Admin::TimeAgoComponent.new(time: message.created_at) %>
    <% if message.edited_at %><span><%= t(".edited") %></span><% end %>
  </p>
  <%= render Admin::NotesScreen::BodyComponent.new(body: message.body, users: listing.users) %>
</div>
```

`thread_row_component.rb`:

```ruby
module Admin
  module NotesScreen
    # One thread as a row of the list (notes spec §4.2): the first message's
    # author, time and first lines, the reply count, and "new" in accent while
    # it holds a delivery the viewer has not read -- the one meaning accent
    # has here (§4.5). A link into the notes frame: following it replaces the
    # list with the thread.
    class ThreadRowComponent < Admin::AdminComponent
      EXCERPT = 200

      def initialize(thread:, listing:, viewer:, type:, view:, show_subject: false)
        @thread = thread
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
        @show_subject = show_subject
      end

      private

      attr_reader :thread, :listing, :viewer, :type, :view

      def first = thread.messages.first

      def author = listing.users[first.author_id]

      def excerpt = ::Notes::Mentions.display(first.body, listing.users).first.truncate(EXCERPT)

      def replies = thread.messages.size - 1

      def unread? = listing.unread?(thread, viewer)

      def show_subject? = @show_subject

      def subject_name = helpers.note_subject_name(listing.subject_of(thread), listing.container, type)

      def path
        helpers.admin_record_note_thread_path(*helpers.note_args(listing.container), thread,
          **{ view: (view unless view == "editor"), **helpers.admin_url_options }.compact)
      end
    end
  end
end
```

`thread_row_component.html.erb`:

```erb
<%= link_to path, id: "note-row-#{thread.id}",
      class: "flex flex-col gap-0.5 rounded-cs border border-line bg-surface px-3 py-2 text-left no-underline hover:bg-sunken focus-visible:outline-2 focus-visible:outline-accent",
      data: { note_row: thread.id, unread: (true if unread?), turbo_frame: "notes" } do %>
  <span class="flex flex-wrap items-baseline gap-x-2 text-[12px] text-meta">
    <strong class="font-semibold text-ink"><%= render Admin::UserNameComponent.new(user: author, user_id: first.author_id) %></strong>
    <%= render Admin::TimeAgoComponent.new(time: first.created_at) %>
    <% if unread? %><span data-note-new class="font-semibold text-accent"><%= t(".new") %></span><% end %>
  </span>
  <% if show_subject? %>
    <span class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= subject_name %></span>
  <% end %>
  <span class="line-clamp-2 break-words text-sm text-ink"><%= excerpt %></span>
  <% if replies.positive? %>
    <span data-note-replies class="text-[12px] text-meta"><%= t(".replies", count: replies) %></span>
  <% end %>
<% end %>
```

`thread_component.rb`:

```ruby
module Admin
  module NotesScreen
    # The thread view of the notes frame (notes spec §4.2): a Back link to the
    # list, what the thread is on, its messages and -- from Task 6 -- the
    # composer with Resolve, fixed at the bottom. It REPLACES the list in
    # `turbo-frame#notes`, on every width.
    #
    # Two parts with ids of their own: `messages` (everything that is READ:
    # state, quote, messages, and from Task 6 the thread's buttons) and
    # `reply` (the field that is TYPED in). A live refresh replaces the first
    # and never the second.
    #
    # A thread with more than three messages shows the first and the last two
    # and folds the rest into "Show N more" (a `<details>`, no script).
    class ThreadComponent < Admin::AdminComponent
      FOLD_ABOVE = 3

      def initialize(thread:, listing:, viewer:, locale:, view:, type:, failed: nil)
        @thread = thread
        @listing = listing
        @viewer = viewer
        @locale = locale.to_s
        @view = view
        @type = type
        @failed = failed
      end

      def dom_id = "note-thread-#{thread.id}"

      private

      attr_reader :thread, :listing, :viewer, :locale, :view, :type, :failed

      def messages = thread.messages.to_a

      def folded = messages.size > FOLD_ABOVE ? messages[1...-2] : []

      def leading = messages.size > FOLD_ABOVE ? messages.first(1) : messages

      def trailing = messages.size > FOLD_ABOVE ? messages.last(2) : []

      def message(record)
        Admin::NotesScreen::MessageComponent.new(message: record, thread: thread, listing: listing, viewer: viewer, type: type, view: view, failed: failed)
      end

      def args = helpers.note_args(listing.container)

      def frame_params = { view: (view unless view == "editor"), **helpers.admin_url_options }.compact

      def back_path = helpers.admin_record_notes_path(*args, **frame_params)

      def subject_name = helpers.note_subject_name(listing.subject_of(thread), listing.container, type)

      # "Written on German": only when the thread was started on another
      # language tab than the one being read (notes spec §4.2, §4.5).
      def written_on
        origin = thread.origin_locale
        t(".written_on", language: ::Locales.name(origin)) if origin.present? && origin != locale
      end

      def resolver = listing.users[thread.resolved_by_id]
    end
  end
end
```

`thread_component.html.erb`:

```erb
<%= tag.div id: dom_id, tabindex: -1, class: "flex min-h-full flex-col gap-3 focus:outline-none",
      data: { notes_view: "thread", note_thread: thread.id, state: thread.state, notes_container: ::Notes.key(listing.container) } do %>
  <%= render Admin::NotesScreen::CountsComponent.new(counts: listing.counts) %>
  <div class="flex flex-col gap-1">
    <%= link_to t(".back"), back_path, class: "self-start text-sm text-accent hover:underline", data: { note_back: true, turbo_frame: "notes" } %>
    <h3 class="text-sm font-semibold text-ink"><%= subject_name %></h3>
  </div>

  <div id="<%= dom_id %>-messages" data-note-part="messages" class="flex flex-1 flex-col gap-3">
    <% if thread.pinned || thread.resolved? || written_on %>
      <p class="flex flex-wrap items-center gap-x-2 gap-y-1 font-cs-mono text-label uppercase tracking-mono text-meta">
        <% if thread.pinned %><span data-note-badge="pinned"><%= t(".pinned") %></span><% end %>
        <% if thread.resolved? %>
          <span data-note-badge="resolved"><%= t(".resolved_by") %> <%= render Admin::UserNameComponent.new(user: resolver, user_id: thread.resolved_by_id) %></span>
        <% end %>
        <% if written_on %><span data-note-badge="origin"><%= written_on %></span><% end %>
      </p>
    <% end %>
    <% if thread.quote.present? %>
      <blockquote class="rounded-cs border border-line bg-sunken px-2 py-1 text-sm text-dim"><%= thread.quote %></blockquote>
    <% end %>
    <% leading.each do |record| %><%= render message(record) %><% end %>
    <% if folded.any? %>
      <details class="flex flex-col gap-3">
        <summary class="cursor-pointer text-sm text-accent hover:underline"><%= t(".show_more", count: folded.size) %></summary>
        <div class="mt-3 flex flex-col gap-3">
          <% folded.each do |record| %><%= render message(record) %><% end %>
        </div>
      </details>
    <% end %>
    <% trailing.each do |record| %><%= render message(record) %><% end %>
  </div>
<% end %>
```

`list_component.rb`:

```ruby
module Admin
  module NotesScreen
    # The list view of the notes frame (notes spec §4.2), top to bottom:
    # Pinned, Open by group, Resolved (collapsed, loaded when opened), or the
    # shared empty state with "New note". The same list in the editors' drawer
    # and in the media panel. It carries the record's counts for
    # `admin--notes`, so every answer of the frame also corrects the header's
    # number and the markers.
    class ListComponent < Admin::AdminComponent
      def initialize(listing:, viewer:, locale:, view:, type:, compose: nil, failed: nil, notice: nil)
        @listing = listing
        @viewer = viewer
        @locale = locale
        @view = view
        @type = type
        @compose = compose.to_s.presence
        @failed = failed
        @notice = notice
      end

      private

      attr_reader :listing, :viewer, :locale, :view, :type, :compose, :failed, :notice

      def container = listing.container

      def key = ::Notes.key(container)

      def row(record, show_subject: false)
        Admin::NotesScreen::ThreadRowComponent.new(thread: record, listing: listing, viewer: viewer, type: type, view: view, show_subject: show_subject)
      end

      def group_title(group) = helpers.note_subject_name(group.subject, container, type)

      def empty? = listing.open_count.zero? && listing.resolved_count.zero?

      def frame_params(**extra) = { view: (view unless view == "editor"), **helpers.admin_url_options, **extra }.compact

      def more_path = helpers.admin_record_notes_path(*helpers.note_args(container), **frame_params(limit: listing.next_limit))

      def resolved_path = helpers.admin_resolved_record_notes_path(*helpers.note_args(container), **frame_params)

      # "New note": the list again, with the field for a note on the record
      # itself (Task 6 draws the field).
      def new_note_path = helpers.admin_record_notes_path(*helpers.note_args(container), **frame_params(compose: key))
    end
  end
end
```

`list_component.html.erb`:

```erb
<div id="notes-list" class="flex flex-col gap-5" data-notes-view="list" data-notes-container="<%= key %>">
  <%= render Admin::NotesScreen::CountsComponent.new(counts: listing.counts) %>

  <% if notice %>
    <p role="status" class="rounded-cs border border-line bg-sunken px-3 py-2 text-sm text-ink"><%= t(".notices.#{notice}") %></p>
  <% end %>

  <% if empty? && compose.nil? && failed.nil? %>
    <%= render Admin::EmptyStateComponent.new(title: t(".empty_title"), description: t(".empty.#{type}")) do |empty_state| %>
      <% empty_state.with_action do %>
        <%= link_to t(".new"), new_note_path, class: setup_secondary_link_class, data: { note_new_link: true, turbo_frame: "notes" } %>
      <% end %>
    <% end %>
  <% end %>

  <% if listing.pinned.any? %>
    <section id="notes-pinned" aria-labelledby="notes-pinned-title" class="flex flex-col gap-2">
      <h3 id="notes-pinned-title" class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= t(".pinned") %></h3>
      <% listing.pinned.each do |record| %><%= render row(record, show_subject: true) %><% end %>
    </section>
  <% end %>

  <% unless empty? %>
    <section id="notes-open" aria-labelledby="notes-open-title" class="flex flex-col gap-3">
      <h3 id="notes-open-title" class="font-cs-mono text-label uppercase tracking-mono text-meta"><%= t(".open", count: listing.open_count) %></h3>
      <% if listing.open_count.zero? %>
        <p class="text-sm text-meta"><%= t(".none_open") %></p>
      <% end %>
      <% listing.groups.each do |group| %>
        <section id="notes-group-<%= group.key %>" data-notes-group="<%= group.key %>" tabindex="-1" class="flex flex-col gap-2 focus:outline-none">
          <h4 class="text-sm font-semibold text-ink"><%= group_title(group) %></h4>
          <% group.threads.each do |record| %><%= render row(record) %><% end %>
        </section>
      <% end %>
      <% if listing.more? %>
        <%= link_to t(".more"), more_path, class: setup_secondary_link_class, data: { turbo_frame: "notes" } %>
      <% end %>
    </section>
  <% end %>

  <% if listing.resolved_count.positive? %>
    <details id="notes-resolved-section">
      <summary class="cursor-pointer font-cs-mono text-label uppercase tracking-mono text-meta"><%= t(".resolved", count: listing.resolved_count) %></summary>
      <%= tag.turbo_frame id: "notes-resolved", src: resolved_path, loading: "lazy" %>
    </details>
  <% end %>
</div>
```

(`Admin::EmptyStateComponent`'s `action` slot is the one the media grid's "Clear filters" uses.)

- [ ] **Step 6: The strings.** Add to `config/locales/admin/notes.en.yml`, under `en.admin`:

```yaml
    notes:
      index:
        title: "Notes · CS Studio"
      subject:
        page: "This page"
        post: "This post"
        media: "This image"
    components:
      notes_screen:
        list:
          pinned: "Pinned"
          open:
            one: "Open · %{count}"
            other: "Open · %{count}"
          none_open: "No open notes."
          more: "Show more"
          resolved:
            one: "Resolved · %{count}"
            other: "Resolved · %{count}"
          new: "New note"
          empty_title: "No notes yet"
          empty:
            page: "Ask a question about this page or one of its blocks."
            post: "Ask a question about this post."
            media: "Ask a question about this image."
          notices:
            gone: "This note is gone: it was deleted, or what it was on was."
        thread_row:
          new: "new"
          replies:
            one: "%{count} reply"
            other: "%{count} replies"
        thread:
          back: "← All notes"
          pinned: "Pinned"
          resolved_by: "Resolved by"
          written_on: "Written on %{language}"
          show_more:
            one: "Show %{count} more"
            other: "Show %{count} more"
        message:
          edited: "edited"
```

(`notes:` already exists in the file: merge `index` and `subject` into it.) Add to `CONVERTED` in `test/lib/admin_i18n_test.rb` every file this step and Step 4 created under `app/components/admin/notes_screen/`, `app/views/admin/notes/`, and `app/controllers/admin/notes_controller.rb`, `app/controllers/admin/note_threads_controller.rb`, `app/controllers/concerns/admin/note_container.rb`, `app/helpers/admin/note_paths_helper.rb`.

- [ ] **Step 7: Run**, expect green: `PGGSSENCMODE=disable bin/rails test test/queries/notes test/integration/admin/notes_test.rb test/components/admin/notes_screen test/lib`, and `bin/rails routes -g record_note` shows the four routes.

- [ ] **Step 8: Commit.**

```bash
git add -A
git commit -m "feat: one record's notes as a frame — the list and the thread that replaces it, the counts, each part with its own scoped GET" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 6: Writing — the composer, the mention picker and the write endpoints

**Spec:** §3.2 (the picker: six rows), §3.7 (ordinary Turbo forms in the frame), §4.2 (the composer, the thread's buttons, "Notify me"), §7 ("The subject is deleted while the drawer is open", "Unsent text"). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/save-rule-and-write-queue.md` ("The write queue": a frame-level form is never held by the promotion hold, and waits only while a save is outstanding), `app/javascript/i18n/messages.js`, `app/controllers/admin/user_suggestions_controller.rb`.

Every note form sits inside `turbo-frame#notes` and says `data-turbo-frame="notes"`: a success is a 303 to the view the person should now see (the thread after a write on it or a new note, the list after a thread's last message was deleted), a refusal or failure re-renders the same view with its status (403 or 422) and the typed text kept. No form here is an autosave form.

**Files:**
- Create: `app/controllers/admin/note_messages_controller.rb`, `app/controllers/admin/note_mentions_controller.rb`, `app/components/admin/notes_screen/composer_component.{rb,html.erb}`, `app/javascript/controllers/admin/note_composer_controller.js`
- Modify: `config/routes.rb`, `app/controllers/admin/note_threads_controller.rb`, `app/controllers/concerns/admin/note_container.rb`, `app/queries/notes/listing.rb`, `app/components/admin/notes_screen/{thread,message,list}_component.{rb,html.erb}`, `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/integration/admin/note_writes_test.rb`, `test/integration/admin/note_mentions_test.rb`, `test/system/admin/note_composer_test.rb` (new)

**Interfaces:**
- Consumes: Tasks 2, 3, 5.
- Produces:
  - Routes: `admin_record_note_threads_path(type, id)` POST → `note_threads#create` (params `body`, `mention_names` (JSON object name → id), `subject` (a key, blank for the record itself), `quote`); `admin_change_record_note_thread_path(type, id, thread, change)` POST with `change` in `resolve|reopen|pin|unpin|follow|unfollow` → `note_threads#change`; `admin_record_note_messages_path(type, id, thread)` POST → `note_messages#create`; `admin_record_note_message_path(type, id, thread, message)` PATCH/DELETE → `note_messages#update` / `#destroy`; `admin_record_note_mentions_path(type, id, q:)` GET JSON → `[{ id, label, hint? }]`.
  - `Admin::NoteContainer#note_body` (the body with the picker's names turned into tokens), `#failure_status(result)`, `#gone!` (303 to the frame with `notice=gone`).
  - `Notes::Listing#moderator?(actor)`, `#subject_by_key(key)`.
  - `Admin::NotesScreen::ComposerComponent.new(url:, key:, label:, submit:, mentions_url:, method: :post, body: "", names: {}, errors: [], hidden: {}, rows: 2)`; form markup `form[data-controller="admin--note-composer"][data-note-composer=<key>]` with `textarea[name=body]`, `input[type=hidden][name=mention_names]`.
  - `failed` (handed to the list by `render_list`): `{ key:, body:, names:, errors:, subject:, quote: }`, `key` being `"new"`, `"thread-<id>"` or `"message-<id>"`.
  - DOM: in the list view, `#notes-new` (the new-note composer, drawn only for `?compose=<key>`: on the record, or on the block the key names, with `?quote=`; and for a failed new note) and `a[data-note-new-link]` ("New note"); in the thread view, `[data-note-actions]` inside the messages part (Pin, Notify me) and `#note-thread-<id>-reply[data-note-part=reply]`, fixed at the bottom, holding the reply composer and Resolve / Reopen.
  - `admin--note-composer`: ⌘/Ctrl+Enter sends; a draft per `key` in `sessionStorage` under `cs-note-draft:<key>`, restored on connect and dropped when the form's submit succeeds; `@` opens the picker (six rows at most).

- [ ] **Step 1: Write the failing tests.** `test/integration/admin/note_writes_test.rb`:

```ruby
require "test_helper"

class Admin::NoteWritesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
    @base = "/cs-studio/notes/page/#{@page.id}"
    users(:two).update!(name: "Dana")
  end

  test "a note on a block is started from the form, with the picker's name turned into a token" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Ask @Dana about this", mention_names: { "Dana" => users(:two).id }.to_json,
      subject: "ContentBlock-#{@block.id}", quote: "€49", locale: "en" }

    thread = Notes::Thread.order(:id).last
    assert_redirected_to "#{@base}/threads/#{thread.id}"
    assert_response :see_other
    assert_equal [ @block, "€49", "editor", "Ask @[#{users(:two).id}] about this" ], [ thread.subject, thread.quote, thread.origin_view, thread.first_message.body ]
    assert_equal [ [ users(:two).id, "mention" ] ], Notes::Delivery.where(thread: thread).pluck(:user_id, :reason)
  end

  test "a failed note re-renders the frame at 422 with the text, the names and the reason kept" do
    stranger = User.create!(email_address: "stranger@example.com", password: "password-password", name: "Sam")
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Ask @Sam", mention_names: { "Sam" => stranger.id }.to_json }, headers: { "Turbo-Frame" => "notes" }

    assert_response :unprocessable_entity
    assert_select "#notes-new [role=alert]", text: /Sam can't see this page/
    assert_select "#notes-new textarea[name=body]", text: "Ask @Sam"
    assert_select "#notes-new input[name=mention_names]" do |inputs|
      assert_equal({ "Sam" => stranger.id }, JSON.parse(inputs.first["value"]))
    end
    assert_equal 1, Notes::Thread.count
  end

  test "reply, edit and delete" do
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "Yes" }
    assert_redirected_to "#{@base}/threads/#{@thread.id}"
    reply = @thread.messages.last

    patch "#{@base}/threads/#{@thread.id}/messages/#{reply.id}", params: { body: "Yes, it is" }
    assert_redirected_to "#{@base}/threads/#{@thread.id}"
    assert_equal "Yes, it is", reply.reload.body

    delete "#{@base}/threads/#{@thread.id}/messages/#{reply.id}"
    assert_redirected_to "#{@base}/threads/#{@thread.id}"
    assert_not Notes::Message.exists?(reply.id)
  end

  test "editing someone else's note is a 403 in the frame, with the reason in that message's form" do
    sign_in_as(users(:reader))

    patch "#{@base}/threads/#{@thread.id}/messages/#{@thread.first_message.id}", params: { body: "Mine" }, headers: { "Turbo-Frame" => "notes" }

    assert_response :forbidden
    assert_select "turbo-frame#notes #note-thread-#{@thread.id} #note-message-#{@thread.first_message.id} [role=alert]", text: /Only the person who wrote a note/
    assert_equal "Is this right?", @thread.first_message.reload.body
  end

  test "deleting the last message answers the frame without the thread" do
    sign_in_as(users(:two))

    delete "#{@base}/threads/#{@thread.id}/messages/#{@thread.first_message.id}"

    assert_redirected_to @base
    assert_equal 0, Notes::Thread.count
  end

  test "resolve, reopen, pin, unpin, follow and unfollow" do
    sign_in_as(users(:two))

    { "resolve" => -> { @thread.reload.resolved? }, "reopen" => -> { @thread.reload.open? }, "pin" => -> { @thread.reload.pinned },
      "unpin" => -> { !@thread.reload.pinned }, "unfollow" => -> { !Notes::Follow.find_by(thread: @thread, user: users(:two)).following },
      "follow" => -> { Notes::Follow.find_by(thread: @thread, user: users(:two)).following } }.each do |change, done|
      post "#{@base}/threads/#{@thread.id}/#{change}"
      assert_redirected_to "#{@base}/threads/#{@thread.id}"
      assert done.call, change
    end
  end

  test "a reader's pin is refused in the frame, and the thread's buttons follow the viewer's rights" do
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{@thread.id}/pin", headers: { "Turbo-Frame" => "notes" }
    assert_response :forbidden
    assert_select "#note-thread-#{@thread.id} [role=alert]"

    get "#{@base}/threads/#{@thread.id}", headers: { "Turbo-Frame" => "notes" }
    assert_select "#note-thread-#{@thread.id} [data-note-actions]" do
      assert_select "form[action$='/follow']"
      assert_select "form[action$='/pin']", count: 0
    end
    assert_select "#note-thread-#{@thread.id}-reply form[action$='/resolve']"
    assert_select "#note-message-#{@thread.first_message.id} form", count: 0 # someone else's note: nothing to edit or delete
    assert_select "#note-thread-#{@thread.id}-reply form[data-controller='admin--note-composer'][data-turbo-frame=notes] textarea[name=body]"
  end

  # Review Focus 3.
  test "a reply to a thread whose block was deleted meanwhile comes back to the frame saying so" do
    on_block = as(users(:two)) { Notes::Start.call(@block, body: "About this block") }.record
    assert ContentBlocks::Destroy.call(@block).ok?
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{on_block.id}/messages", params: { body: "Too late" }

    assert_redirected_to "#{@base}?notice=gone"
    follow_redirect!
    assert_select "[role=status]", text: /This note is gone/
  end

  test "every write is not found outside the read scope, and a thread of another record is gone, not written" do
    other = create_page(title: "Other")
    elsewhere = as(users(:two)) { Notes::Start.call(other, body: "Elsewhere") }.record
    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))

    post "#{@base}/threads", params: { body: "Hi" }
    assert_response :not_found
    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "Hi" }
    assert_response :not_found
    post "#{@base}/threads/#{@thread.id}/resolve"
    assert_response :not_found

    sign_in_as(users(:reader))
    post "#{@base}/threads/#{elsewhere.id}/messages", params: { body: "Hi" }
    assert_redirected_to "#{@base}?notice=gone"
    assert_equal 1, elsewhere.messages.count
  end

  test "the new-note form is on the record, or on the block the URL names, with the quote" do
    sign_in_as(users(:reader))

    get @base, params: { compose: "ContentBlock-#{@block.id}", quote: "€49 a month" }, headers: { "Turbo-Frame" => "notes" }

    assert_select "#notes-new input[type=hidden][name=subject][value='ContentBlock-#{@block.id}']"
    assert_select "#notes-new input[type=hidden][name=quote][value='€49 a month']"
    assert_select "#notes-new blockquote", text: "€49 a month"

    get @base, params: { compose: "ContentBlock-999999" }, headers: { "Turbo-Frame" => "notes" }
    assert_select "#notes-new input[name=subject][value='']"

    get @base, headers: { "Turbo-Frame" => "notes" }
    assert_select "#notes-new", count: 0
    assert_select "a[data-note-new-link][href='#{@base}?compose=Page-#{@page.id}']"
  end
end
```

`test/integration/admin/note_mentions_test.rb`:

```ruby
require "test_helper"

# The composer's mention picker (notes spec §3.2): not a directory.
class Admin::NoteMentionsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @stranger = User.create!(email_address: "stranger@example.com", password: "password-password")
    sign_in_as(users(:reader))
  end

  def suggest(q) = get("/cs-studio/notes/page/#{@page.id}/mentions", params: { q: q }) && response.parsed_body

  test "it lists users who may read the record, by name with the email as a hint, owners included" do
    users(:two).update!(name: "Dana Example")

    assert_equal [ { "id" => users(:two).id, "label" => "Dana Example", "hint" => "two@example.com" } ], suggest("dana")
    assert_equal [ { "id" => users(:one).id, "label" => "one@example.com" } ], suggest("one@")
  end

  test "someone who may not read the record is never offered" do
    assert_equal [], suggest("stranger")
    assert_not_includes suggest("example.com").map { |row| row["id"] }, @stranger.id
  end

  test "six rows at most, from the first character on, and for a bare @ the first six readers" do
    10.times do |index|
      user = User.create!(email_address: "member#{index}@example.org", password: "password-password")
      AccessControl::Membership.create!(group: access_control_groups(:read_only), user: user)
    end

    assert_equal 6, suggest("member").size
    assert_equal 6, suggest("m").size
    assert_equal 6, suggest("").size
    assert(suggest("").none? { |row| row["id"] == @stranger.id })
  end

  test "it answers only for a record the asker may read" do
    sign_in_as(@stranger)

    get "/cs-studio/notes/page/#{@page.id}/mentions", params: { q: "two" }

    assert_response :not_found
  end
end
```

`test/system/admin/note_composer_test.rb`:

```ruby
require "application_system_test_case"

# The composer on its own (notes spec §4.2), on the notes page of a record --
# the same frame the drawer shows.
class Admin::NoteComposerSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana Example")
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing")
  end

  # The list with the field for a new note on the page: what "New note" opens.
  def open_notes
    visit "/cs-studio/notes/page/#{@page.id}?compose=Page-#{@page.id}"
    await_admin_controllers
  end

  def field = find("#notes-new textarea[name=body]")

  test "the picker opens on @, the keyboard picks a person, and Ctrl+Enter sends the note with a mention" do
    open_notes
    field.send_keys("Ask @dan")

    assert_selector "#notes-new [role=listbox] [role=option]", text: "Dana Example"
    field.send_keys(:down, :enter)
    assert_equal "Ask @Dana Example ", field.value

    field.send_keys("first", [ :control, :enter ])

    assert_selector "[data-note-thread] [data-note-mention]", text: "@Dana Example"
    assert_equal [ users(:two).id ], Notes::Message.last.mentioned_user_ids
    open_notes
    assert_equal "", field.value
  end

  test "Enter adds a line and sends nothing; Escape closes the picker and keeps the text" do
    open_notes
    field.send_keys("One", :enter, "Two @da")
    assert_selector "#notes-new [role=listbox] [role=option]"

    field.send_keys(:escape)

    assert_no_selector "#notes-new [role=listbox] [role=option]"
    assert_equal "One\nTwo @da", field.value
    assert_equal 0, Notes::Thread.count
  end

  test "unsent text comes back after leaving the screen, and is gone once sent" do
    open_notes
    field.send_keys("Half a thought")
    visit "/cs-studio"
    open_notes

    assert_equal "Half a thought", field.value

    within("#notes-new") { press "Add note" }
    assert_selector "[data-note-thread]", text: "Half a thought"
    open_notes
    assert_equal "", field.value
  end

  test "an emoji from the popover goes in at the caret" do
    open_notes
    field.send_keys("Good")
    find("#notes-new [data-admin--note-composer-target=emoji] summary").click
    find("#notes-new button[data-emoji='👍']").click

    assert_equal "Good👍", field.value
  end

  test "the at-sign button opens the picker like a typed @, on its first row" do
    open_notes
    field.send_keys("Ask")
    find("#notes-new [data-note-toolbar] button[data-action='admin--note-composer#mention']").click

    assert_equal "Ask @", field.value
    assert_selector "#notes-new [role=listbox] [role=option]", maximum: 6
    assert_selector "#notes-new [role=listbox] [role=option][aria-selected=true]", count: 1
  end
end
```

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/integration/admin/note_writes_test.rb test/integration/admin/note_mentions_test.rb`

- [ ] **Step 3: Routes.** Inside the `notes/:container_type/:container_id` scope, add:

```ruby
      get "mentions", to: "note_mentions#index", as: :record_note_mentions, defaults: { format: :json }
      post "threads", to: "note_threads#create", as: :record_note_threads
      post "threads/:id/:change", to: "note_threads#change", as: :change_record_note_thread,
        constraints: { id: /\d+/, change: /resolve|reopen|pin|unpin|follow|unfollow/ }
      post "threads/:thread_id/messages", to: "note_messages#create", as: :record_note_messages, constraints: { thread_id: /\d+/ }
      patch "threads/:thread_id/messages/:id", to: "note_messages#update", as: :record_note_message, constraints: { thread_id: /\d+/, id: /\d+/ }
      delete "threads/:thread_id/messages/:id", to: "note_messages#destroy", constraints: { thread_id: /\d+/, id: /\d+/ }
```

- [ ] **Step 4: The concern and the listing.** Add to `Admin::NoteContainer` (private):

```ruby
    # The typed body with the names the picker inserted turned into tokens
    # (`Notes::Mentions.tokenize`). `mention_names` comes from the browser and
    # is used for nothing else: whom a note may mention is the service's check
    # on the ids that result.
    def note_body = Notes::Mentions.tokenize(params[:body], mention_names)

    def mention_names
      names = JSON.parse(params[:mention_names].to_s)
      names.is_a?(Hash) ? names.first(50).to_h : {}
    rescue JSON::ParserError
      {}
    end

    def failure_status(result) = result.denied? ? :forbidden : :unprocessable_entity

    # What a failed form gets back: its own key, what was typed, and why.
    def failed_form(key, result, **extra)
      { key: key, body: params[:body].to_s, names: mention_names, errors: result.errors, **extra }
    end

    # The thread (or what it was on) is no longer there: back to the list,
    # which says so. Never a 404 inside the drawer.
    def gone! = redirect_to(notes_path(notice: "gone"), status: :see_other)
```

Add to `Notes::Listing` (public):

```ruby
    # May `actor` moderate this record's notes? Asked once per listing, not
    # once per thread drawn.
    def moderator?(actor, channel: Current.channel)
      @moderator = Notes.moderator?(actor, container, channel: channel) unless defined?(@moderator)
      @moderator
    end

    # The record a key names, among this container's own (itself and, for a
    # page, its blocks); nil for anything else.
    def subject_by_key(key) = subjects[key.to_s]
```

- [ ] **Step 5: The controllers.** Replace `app/controllers/admin/note_threads_controller.rb`'s body below `show` with:

```ruby
    CHANGES = {
      "resolve" => ->(thread) { Notes::Resolve.call(thread) },
      "reopen" => ->(thread) { Notes::Reopen.call(thread) },
      "pin" => ->(thread) { Notes::Pin.call(thread) },
      "unpin" => ->(thread) { Notes::Unpin.call(thread) },
      "follow" => ->(thread) { Notes::SetFollowing.call(thread, following: true) },
      "unfollow" => ->(thread) { Notes::SetFollowing.call(thread, following: false) }
    }.freeze

    # A new thread on the record, or on one of its blocks (`subject`, a key).
    # A key that names nothing of this record means the record itself: the
    # form only ever sends keys the frame drew.
    def create
      subject = Notes::Listing.new(@container, viewer: Current.user).subject_by_key(params[:subject]) || @container
      result = Notes::Start.call(subject, body: note_body, quote: params[:quote], origin_view: note_view, origin_locale: admin_locale)

      if result.ok?
        redirect_to thread_path(result.record), status: :see_other
      else
        render_list(status: failure_status(result), failed: failed_form("new", result, subject: params[:subject].to_s, quote: params[:quote].to_s))
      end
    end

    def change
      thread = container_threads.find_by(id: params[:id]) or return gone!
      result = CHANGES.fetch(params[:change]).call(thread)

      if result.ok?
        redirect_to thread_path(thread), status: :see_other
      else
        render_thread(thread, status: failure_status(result), failed: failed_form("thread-#{thread.id}", result, body: ""))
      end
    end
```

`app/controllers/admin/note_messages_controller.rb`:

```ruby
module Admin
  # The messages of one thread: a reply, an edit of one's own, a delete. The
  # thread is one of the container's; a thread that is gone (its block
  # deleted, its last message deleted in another tab) answers the frame with
  # a sentence, never a 404 inside the drawer.
  class NoteMessagesController < BaseController
    include NoteContainer

    before_action :set_thread

    def create
      result = Notes::Reply.call(@thread, body: note_body)

      if result.ok?
        redirect_to thread_path(@thread), status: :see_other
      elsif result.record.nil? && !result.denied? && Notes::Thread.where(id: @thread.id).none?
        gone!
      else
        render_thread(@thread, status: failure_status(result), failed: failed_form("thread-#{@thread.id}", result))
      end
    end

    def update
      message = @thread.messages.find_by(id: params[:id]) or return gone!
      result = Notes::EditMessage.call(message, body: note_body)

      if result.ok?
        redirect_to thread_path(@thread), status: :see_other
      else
        render_thread(@thread, status: failure_status(result), failed: failed_form("message-#{message.id}", result))
      end
    end

    def destroy
      message = @thread.messages.find_by(id: params[:id]) or return gone!
      result = Notes::DeleteMessage.call(message)

      if result.ok?
        # The thread, or the list when the thread went with its last message.
        redirect_to (result.record ? thread_path(result.record) : notes_path), status: :see_other
      else
        render_thread(@thread, status: failure_status(result), failed: failed_form("message-#{message.id}", result, body: ""))
      end
    end

    private

    def set_thread
      @thread = container_threads.find_by(id: params[:thread_id]) or gone!
    end
  end
end
```

`app/controllers/admin/note_mentions_controller.rb`:

```ruby
module Admin
  # Whom a note on this record can mention (notes spec §3.2): the users who
  # may READ it, by name with the email as a hint. The second place CS Studio
  # lists users to someone without `users.manage`, and like
  # `Admin::UserSuggestionsController` deliberately not a directory: six rows
  # at most, and only for a record the asker may read (`NoteContainer`) --
  # whoever may read a page may learn who else can, six names at a time. The
  # picker opens on "@" alone, so an empty query answers the first six.
  # Owners are offered: an owner reads everything.
  #
  # The read right has no SQL form across users, so the best `CANDIDATES`
  # matches are judged one by one; a site where more than that many people
  # match and few of them may read the record shows fewer than six, and one
  # more letter finds the rest.
  class NoteMentionsController < BaseController
    include NoteContainer

    LIMIT = 6
    CANDIDATES = 40
    MAX_QUERY_LENGTH = 100

    def index
      query = params[:q].to_s.strip.first(MAX_QUERY_LENGTH)
      matching = query.empty? ? User.all : User.name_or_email_containing(query).name_or_email_starting_first(query)
      users = matching.by_email.limit(CANDIDATES).select { |user| Notes.readable?(user, @container, channel: :admin) }.first(LIMIT)
      render json: users.map { |user| { id: user.id, label: user.display_name, hint: (user.email_address if user.name.present?) }.compact }
    end
  end
end
```

- [ ] **Step 6: The composer.** `app/components/admin/notes_screen/composer_component.rb`:

```ruby
module Admin
  module NotesScreen
    # The field a note is typed in (notes spec §4.2): a textarea with an emoji
    # popover and the mention picker that opens on "@". Enter adds a line;
    # Ctrl/⌘+Enter sends (`admin--note-composer`). An ordinary Turbo form
    # inside the notes frame: it sends no base and is no autosave form.
    #
    # The textarea shows a mention as "@Dana Smith"; `mention_names` carries
    # the names the picker inserted with their ids, and the controller turns
    # them into tokens (`Notes::Mentions`). `key` names the form for its draft
    # in `sessionStorage` and for the answer of a failed submit.
    class ComposerComponent < Admin::AdminComponent
      def initialize(url:, key:, label:, submit:, mentions_url:, method: :post, body: "", names: {}, errors: [], hidden: {}, rows: 2)
        @url = url
        @key = key
        @label = label
        @submit = submit
        @mentions_url = mentions_url
        @method = method
        @body = body
        @names = names
        @errors = Array(errors)
        @hidden = hidden
        @rows = rows
      end

      private

      attr_reader :url, :key, :label, :submit, :mentions_url, :method, :body, :names, :errors, :hidden, :rows

      def field_id = "note-field-#{key}"

      def form_data
        { controller: "admin--note-composer", turbo_frame: "notes", note_composer: key,
          "admin--note-composer-key-value": key, "admin--note-composer-mentions-url-value": mentions_url,
          action: "turbo:submit-end->admin--note-composer#sent", messages: script_messages }
      end

      # On a line of its own, ending the line: `test/lib/script_messages_test.rb`
      # reads the literal keys of a `messages_data(...)` call only when the
      # closing bracket is followed by a line end, a comma or another bracket.
      def script_messages = messages_data("notes.script.mentions.none", "notes.script.mentions.count")
    end
  end
end
```

`composer_component.html.erb`:

```erb
<%= form_with url: url, method: method, class: "flex flex-col gap-2", data: form_data do %>
  <% hidden.each do |name, value| %><%= hidden_field_tag name, value, id: nil %><% end %>
  <%= hidden_field_tag "mention_names", names.to_json, id: nil, data: { "admin--note-composer-target": "names" } %>
  <% if errors.any? %>
    <ul role="alert" class="flex flex-col gap-0.5 text-sm text-danger-ink">
      <% errors.each do |error| %><li><%= error %></li><% end %>
    </ul>
  <% end %>
  <div class="relative">
    <%= label_tag field_id, label, class: "sr-only" %>
    <%= text_area_tag "body", body, id: field_id, rows: rows, maxlength: ::Notes::Message::MAX_BODY, required: true, placeholder: label,
          autocomplete: "off", aria: { autocomplete: "list", controls: "#{field_id}-people" },
          class: "block w-full rounded-cs border border-line-strong bg-surface px-3 py-2 text-sm text-ink focus:outline-2 focus:outline-accent",
          data: { "admin--note-composer-target": "field", action: "input->admin--note-composer#typed keydown->admin--note-composer#key blur->admin--note-composer#left" } %>
    <ul id="<%= field_id %>-people" role="listbox" hidden aria-label="<%= t(".people") %>" data-admin--note-composer-target="suggestions"
        class="absolute left-0 top-full z-20 mt-1 w-full max-w-xs rounded-cs border border-line-strong bg-surface py-1 shadow-menu"></ul>
    <p class="sr-only" role="status" aria-live="polite" data-admin--note-composer-target="status"></p>
  </div>
  <div class="flex items-center justify-between gap-2">
    <%# The toolbar's controls, on the left (handoff "Composer"): emoji and the at-sign; Task 16 puts the paperclip before them, inside this group. %>
    <div class="flex items-center gap-0.5" data-note-toolbar>
    <details class="relative" data-admin--note-composer-target="emoji">
      <summary class="flex cursor-pointer list-none items-center rounded-cs px-2 py-1 text-dim hover:bg-sunken hover:text-ink" aria-label="<%= t(".emoji") %>" title="<%= t(".emoji") %>"><%= helpers.render "admin/shared/icon", name: :smile %></summary>
      <div class="absolute bottom-full left-0 z-20 mb-1 grid w-56 grid-cols-6 gap-0.5 rounded-cs border border-line-strong bg-surface p-1 shadow-menu">
        <% ::Notes::EMOJI.each do |emoji| %>
          <button type="button" class="cursor-pointer rounded-cs px-1 py-0.5 text-base hover:bg-sunken" data-emoji="<%= emoji %>" data-action="admin--note-composer#emoji"><%= emoji %></button>
        <% end %>
      </div>
    </details>
    <button type="button" class="flex cursor-pointer items-center rounded-cs px-2 py-1 text-dim hover:bg-sunken hover:text-ink" aria-label="<%= t(".mention") %>" title="<%= t(".mention") %>"
            data-action="admin--note-composer#mention"><%= helpers.render "admin/shared/icon", name: :at_sign %></button>
    </div>
    <div class="flex items-center gap-2">
      <span class="text-[11px] text-meta" aria-hidden="true"><%= t(".send_hint") %></span>
      <%= render Admin::ButtonComponent.new(label: submit, variant: :primary, size: :small, type: "submit") %>
    </div>
  </div>
<% end %>
```

`app/javascript/controllers/admin/note_composer_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// A note's field (notes spec §4.2, §7 "Unsent text"), on the form
// `Admin::NotesScreen::ComposerComponent` draws.
//
// - Enter adds a line; Ctrl/⌘+Enter sends the form.
// - What is typed is kept per form (`key`) in `sessionStorage` and put back
//   when the form is drawn again: the drawer is closed and reopened, the frame
//   is fetched again, the screen is left and come back to. It is dropped when
//   the form's own submit succeeds. Unsent note text never raises the leave
//   guard, which is about content.
// - "@" opens the mention picker (six rows at most): the people who may read
//   this record, from the server (`mentionsUrl`). The field shows "@Dana
//   Smith"; the hidden `mention_names` field carries name -> id for the server
//   to turn into tokens. A name the picker did not insert is just text.
// - An emoji button puts its character in at the caret.
//
// Text goes into the page with `textContent` only: a name is a person's.
const QUERY = /(?:^|\s)@([^\s@]{0,40})$/
const PREFIX = "cs-note-draft:"

export default class extends Controller {
  static targets = [ "field", "names", "suggestions", "status", "emoji" ]
  static values = { key: String, mentionsUrl: String }

  connect() {
    this.names = this.parse(this.namesTarget.value)
    const draft = this.stored()
    if (draft && !this.fieldTarget.value) {
      this.fieldTarget.value = draft.body
      this.names = { ...draft.names, ...this.names }
      this.namesTarget.value = JSON.stringify(this.names)
    }
  }

  disconnect() {
    this.aborter?.abort()
  }

  typed() {
    this.store()
    this.lookUp()
  }

  key(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      this.closeSuggestions()
      this.element.requestSubmit()
      return
    }
    if (this.suggestionsTarget.hidden) return

    if (event.key === "Escape") {
      // The picker's Escape, not the drawer's.
      event.preventDefault()
      event.stopPropagation()
      this.closeSuggestions()
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.move(event.key === "ArrowDown" ? 1 : -1)
    } else if (event.key === "Enter" || event.key === "Tab") {
      const option = this.options[this.index]
      if (!option) return
      event.preventDefault()
      this.pick(option)
    }
  }

  // The list goes when the field loses the focus -- unless the focus went
  // into the list (a pointer press on a row).
  left(event) {
    if (!this.suggestionsTarget.contains(event.relatedTarget)) this.closeSuggestions()
  }

  choose(event) {
    this.pick(event.currentTarget)
  }

  emoji(event) {
    this.insert(event.currentTarget.dataset.emoji, this.fieldTarget.selectionStart, this.fieldTarget.selectionEnd)
    this.emojiTarget.open = false
    this.store()
  }

  // The toolbar's at-sign button (handoff "Mention picker"): the same as
  // typing "@" at the caret, with a space before it when a word ends there.
  mention() {
    const field = this.fieldTarget
    const at = /(?:^|\s)$/.test(field.value.slice(0, field.selectionStart)) ? "@" : " @"
    this.insert(at, field.selectionStart, field.selectionEnd)
    this.typed()
  }

  // `turbo:submit-end` on the form: a note that went through leaves no draft.
  sent(event) {
    if (event.detail.success) this.forget()
  }

  // --- the mention picker -----------------------------------------------------

  async lookUp() {
    const before = this.fieldTarget.value.slice(0, this.fieldTarget.selectionStart)
    const query = before.match(QUERY)?.[1]
    this.aborter?.abort()
    if (query == null || !this.mentionsUrlValue) return this.closeSuggestions()

    this.aborter = new AbortController()
    try {
      const url = new URL(this.mentionsUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.aborter.signal })
      if (!response.ok) return this.closeSuggestions()
      this.show(await response.json(), query)
    } catch (error) {
      if (error.name !== "AbortError") this.closeSuggestions()
    }
  }

  show(people, query) {
    const text = messages(this.element)
    this.query = query
    this.suggestionsTarget.replaceChildren(...people.map((person, index) => {
      const option = document.createElement("li")
      option.setAttribute("role", "option")
      option.id = `${this.fieldTarget.id}-person-${index}`
      option.dataset.id = person.id
      option.dataset.label = person.label
      option.dataset.action = "mousedown->admin--note-composer#choose"
      option.className = "flex cursor-pointer items-baseline gap-2 px-3 py-1 text-sm text-ink aria-selected:bg-sunken"
      const name = document.createElement("span")
      name.textContent = person.label
      option.append(name)
      if (person.hint) {
        const hint = document.createElement("span")
        hint.className = "truncate text-[12px] text-meta"
        hint.textContent = person.hint
        option.append(hint)
      }
      return option
    }))
    this.suggestionsTarget.hidden = people.length === 0
    this.statusTarget.textContent = people.length === 0 ? text.t("notes.script.mentions.none") : text.t("notes.script.mentions.count", { count: people.length })
    this.index = -1
    if (people.length > 0) this.move(1)
  }

  get options() {
    return [ ...this.suggestionsTarget.children ]
  }

  move(step) {
    const options = this.options
    if (options.length === 0) return
    this.index = (this.index + step + options.length) % options.length
    options.forEach((option, index) => option.setAttribute("aria-selected", index === this.index ? "true" : "false"))
    this.fieldTarget.setAttribute("aria-activedescendant", options[this.index].id)
  }

  // "@que" before the caret becomes "@Label ", and the name is remembered.
  pick(option) {
    const caret = this.fieldTarget.selectionStart
    const start = caret - this.query.length - 1
    this.names[option.dataset.label] = Number(option.dataset.id)
    this.namesTarget.value = JSON.stringify(this.names)
    this.insert(`@${option.dataset.label} `, start, caret)
    this.closeSuggestions()
    this.store()
  }

  closeSuggestions() {
    this.suggestionsTarget.hidden = true
    this.suggestionsTarget.replaceChildren()
    this.fieldTarget.removeAttribute("aria-activedescendant")
    this.statusTarget.textContent = ""
    this.index = -1
  }

  insert(text, from, to) {
    const field = this.fieldTarget
    field.value = field.value.slice(0, from) + text + field.value.slice(to)
    const caret = from + text.length
    field.focus()
    field.setSelectionRange(caret, caret)
  }

  // --- the draft --------------------------------------------------------------
  // `sessionStorage` can be absent or full (private windows): a draft is a
  // convenience, so every failure is the same as having none.

  get storageKey() {
    return PREFIX + this.keyValue
  }

  stored() {
    try {
      const draft = this.parse(window.sessionStorage.getItem(this.storageKey))
      return typeof draft.body === "string" && draft.body ? { body: draft.body, names: draft.names || {} } : null
    } catch {
      return null
    }
  }

  store() {
    try {
      if (this.fieldTarget.value) window.sessionStorage.setItem(this.storageKey, JSON.stringify({ body: this.fieldTarget.value, names: this.names }))
      else window.sessionStorage.removeItem(this.storageKey)
    } catch {
      // Nothing to do: the text is still in the field.
    }
  }

  forget() {
    try {
      window.sessionStorage.removeItem(this.storageKey)
    } catch {
      // As above.
    }
  }

  parse(source) {
    try {
      const value = JSON.parse(source || "{}")
      return value && typeof value === "object" && !Array.isArray(value) ? value : {}
    } catch {
      return {}
    }
  }
}
```

- [ ] **Step 7: The thread's buttons, the reply, the message's own actions, the new note.**

In `thread_component.rb` add (private; `args` and `frame_params` are already there from Task 5):

```ruby
      def change_path(change) = helpers.admin_change_record_note_thread_path(*args, thread, change, **frame_params)

      def reply_path = helpers.admin_record_note_messages_path(*args, thread, **frame_params)

      def mentions_path = helpers.admin_record_note_mentions_path(*args)

      def moderator? = listing.moderator?(Current.actor)

      def following? = listing.following?(thread, viewer)

      def action_class(variant = :ghost) = "#{Admin::ButtonComponent::SMALL_CLASS} #{Admin::ButtonComponent::VARIANT_CLASSES.fetch(variant)}"

      def key = "thread-#{thread.id}"

      def own_failure = (failed if failed && failed[:key] == key)
```

In `thread_component.html.erb`, inside the messages part after the `trailing` loop:

```erb
    <% if own_failure && own_failure[:body].blank? %>
      <ul role="alert" class="text-sm text-danger-ink"><% own_failure[:errors].each do |error| %><li><%= error %></li><% end %></ul>
    <% end %>
    <div class="flex flex-wrap items-center gap-1" data-note-actions>
      <% if moderator? && !thread.resolved? %>
        <%= button_to t(thread.pinned ? ".unpin" : ".pin"), change_path(thread.pinned ? "unpin" : "pin"), class: action_class, form: { data: { turbo_frame: "notes" } } %>
      <% end %>
      <%= button_to t(following? ? ".unfollow" : ".follow"), change_path(following? ? "unfollow" : "follow"), class: action_class,
            aria: { pressed: following? }, form: { data: { turbo_frame: "notes" } } %>
    </div>
```

and after the messages part, as the last child of the view's root (the composer with Resolve, fixed at the bottom of the drawer: spec §4.2):

```erb
  <div id="<%= dom_id %>-reply" data-note-part="reply" class="sticky bottom-0 -mx-4 -mb-4 flex flex-col gap-2 border-t border-line bg-surface px-4 py-3">
    <%= render Admin::NotesScreen::ComposerComponent.new(url: reply_path, key: key, label: t(".reply"), submit: t(".send_reply"), mentions_url: mentions_path,
          body: own_failure&.dig(:body).to_s, names: own_failure&.dig(:names) || {}, errors: (own_failure[:errors] if own_failure && own_failure[:body].present?)) %>
    <%# Resolve is a form of its own beside the reply's, never inside it (forms can't nest). %>
    <% if thread.resolved? %>
      <%= button_to t(".reopen"), change_path("reopen"), class: action_class(:secondary), form: { class: "self-start", data: { turbo_frame: "notes" } } %>
    <% else %>
      <%= button_to t(".resolve"), change_path("resolve"), class: action_class(:secondary), form: { class: "self-start", data: { turbo_frame: "notes" } } %>
    <% end %>
  </div>
```

In `message_component.rb` add (private):

```ruby
      def args = helpers.note_args(listing.container)

      def frame_params = { view: (view unless view == "editor"), **helpers.admin_url_options }.compact

      def message_path = helpers.admin_record_note_message_path(*args, thread, message, **frame_params)

      def mentions_path = helpers.admin_record_note_mentions_path(*args)

      def deletable? = own? || listing.moderator?(Current.actor)

      def key = "message-#{message.id}"

      def own_failure = (failed if failed && failed[:key] == key)

      # The stored body as the field shows it: names for tokens, and the map
      # that turns them back.
      def editable_text = ::Notes::Mentions.display(message.body, listing.users)

      def link_class = "cursor-pointer text-[12px] text-meta hover:text-ink hover:underline"
```

In `message_component.html.erb`, after the body:

```erb
  <%# A refusal with no form to show it in: a delete, or an edit of someone else's note. %>
  <% if own_failure && (own_failure[:body].blank? || !own?) %>
    <ul role="alert" class="text-sm text-danger-ink"><% own_failure[:errors].each do |error| %><li><%= error %></li><% end %></ul>
  <% end %>
  <% if own? || deletable? %>
    <div class="flex flex-wrap items-start gap-3">
      <% if own? %>
        <%# Open again when its own save was refused, so the typed text is in view. %>
        <%= tag.details class: "min-w-0 flex-1", open: (own_failure && own_failure[:body].present?) do %>
          <summary class="<%= link_class %>"><%= t(".edit") %></summary>
          <% text, names = editable_text %>
          <div class="mt-2">
            <%= render Admin::NotesScreen::ComposerComponent.new(url: message_path, method: :patch, key: key, label: t(".edit_label"), submit: t(".save"),
                  mentions_url: mentions_path, body: own_failure&.dig(:body).presence || text, names: own_failure&.dig(:names).presence || names,
                  errors: (own_failure[:errors] if own_failure && own_failure[:body].present?)) %>
          </div>
        <% end %>
      <% end %>
      <% if deletable? %>
        <details>
          <summary class="<%= link_class %>"><%= t(".delete") %></summary>
          <div class="mt-1 flex items-center gap-2 text-sm text-ink">
            <span><%= t(".delete_question") %></span>
            <%= button_to t(".delete_confirm"), message_path, method: :delete,
                  class: "#{Admin::ButtonComponent::SMALL_CLASS} #{Admin::ButtonComponent::VARIANT_CLASSES.fetch(:danger_text)}", form: { data: { turbo_frame: "notes" } } %>
          </div>
        </details>
      <% end %>
    </div>
  <% end %>
```

In `list_component.rb` add (private; the constructor does not change):

```ruby
      # The passage the new note quotes (decision D4): from the failed form, or
      # from the URL the opener built. A copy, cut to the column's length.
      def quote = (failed_new&.dig(:quote) || helpers.params[:quote]).to_s.strip.first(::Notes::Thread::MAX_QUOTE).presence

      def failed_new = (failed if failed && failed[:key] == "new")

      # What the new note is on: the block the URL (or the failed form) names,
      # when it is one of this record's; otherwise the record itself.
      def compose_subject = listing.subject_by_key(failed_new&.dig(:subject) || compose) || container

      def compose_key = compose_subject == container ? "" : ::Notes.key(compose_subject)

      def compose_title
        return t(".new_on.#{type}") if compose_subject == container

        # The block as its group's heading names it (Task 5's helper), column
        # included: plain text, escaped once by the template. (A rendered
        # `PanelTitleComponent` is escaped markup already, and would be
        # escaped a second time inside this sentence.)
        t(".new_on_block", block: helpers.note_subject_name(compose_subject, container, type))
      end

      def threads_path = helpers.admin_record_note_threads_path(*helpers.note_args(container), **frame_params)

      def mentions_path = helpers.admin_record_note_mentions_path(*helpers.note_args(container))
```

and in `list_component.html.erb`, after the notice, the field for a new note -- drawn when the list was asked for one (`?compose=`, what "New note" and a block's "Add note" open) or when a new note just failed:

```erb
  <% if compose || failed_new %>
  <section id="notes-new" aria-labelledby="notes-new-title" class="flex flex-col gap-2 rounded-cs border border-line bg-surface p-3">
    <h3 id="notes-new-title" class="text-sm font-semibold text-ink"><%= compose_title %></h3>
    <% if quote %><blockquote class="rounded-cs border border-line bg-sunken px-2 py-1 text-sm text-dim"><%= quote %></blockquote><% end %>
    <%= render Admin::NotesScreen::ComposerComponent.new(url: threads_path, key: "new-#{key}-#{compose_key}", label: t(".new_label"), submit: t(".add"),
          mentions_url: mentions_path, rows: 3, hidden: { subject: compose_key, quote: quote.to_s },
          body: failed_new&.dig(:body).to_s, names: failed_new&.dig(:names) || {}, errors: failed_new&.dig(:errors)) %>
  </section>
  <% elsif !empty? %>
    <%= link_to t(".new"), new_note_path, class: "#{setup_secondary_link_class} self-start", data: { note_new_link: true, turbo_frame: "notes" } %>
  <% end %>
```

Its quote is drawn as §4.5 says (a sunken block with a line on all sides): `class="rounded-cs border border-line bg-sunken px-2 py-1 text-sm text-dim"` on the `<blockquote>` above.

- [ ] **Step 8: The strings.** Add under `en.admin.notes`:

```yaml
      script:
        mentions:
          none: "Nobody by that name can see this."
          count:
            one: "%{count} person. Use the arrow keys and Enter."
            other: "%{count} people. Use the arrow keys and Enter."
```

and under `en.admin.components.notes_screen`: `composer: { people: "People you can mention", emoji: "Emoji", mention: "Mention someone", send_hint: "Ctrl+Enter to send" }`; in `thread`: `resolve: "Resolve"`, `reopen: "Reopen"`, `pin: "Pin"`, `unpin: "Unpin"`, `follow: "Notify me"`, `unfollow: "Stop notifying me"`, `reply: "Reply"`, `send_reply: "Reply"`; in `message`: `edit: "Edit"`, `edit_label: "Edit your note"`, `save: "Save"`, `delete: "Delete"`, `delete_question: "Delete this note?"`, `delete_confirm: "Delete"`; in `list`: `new_label: "Write a note"`, `add: "Add note"`, `new_on: { page: "New note on this page", post: "New note on this post", media: "New note on this image" }`, `new_on_block: "New note on %{block}"`. Add the composer's two files, the script and the two new controllers to `CONVERTED`. The emoji control is a Lucide icon, never a glyph (spec §4.5). CS Studio draws every icon from one partial, `app/views/admin/shared/_icon.html.erb`: a `case name` with one inline `<svg>` per `when` (`viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="size-5 shrink-0" aria-hidden="true" focusable="false"`), rendered with `helpers.render "admin/shared/icon", name: :x`, and it raises on a name it does not know. None of the handoff's Lucide names is in it today (it holds the sidebar's own: `dashboard`, `pages`, `posts`, `tags`, `settings`, `users`, `assistant`, `groups`, `graph`, `status`, `audit`, `media`, `trash`, `menu`, `search`, `translations`). So add two branches before the `else`, `when :smile` and `when :at_sign`, each with the same `<svg>` attributes as its neighbours and Lucide's paths for `smile` and `at-sign` (round caps and joins, as the existing paths say them). The names are symbols with underscores; later tasks add their own branches the same way (`paperclip` in Task 16). The partial draws at `size-5`; where the handoff asks for a 16px or 12px icon, size the wrapper (`[&>svg]:size-4`), never a second copy of the path.

- [ ] **Step 9: Run** the integration tests, then the system test:

```bash
PGGSSENCMODE=disable bin/rails test test/integration/admin test/components/admin/notes_screen test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/note_composer_test.rb
```

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat: write notes from the frame — the composer with mentions, emoji and drafts, and every thread action" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 7: The drawer — in the page editor and the post editor, opened from the header

**Spec:** D6, §4.1, §4.3 (Header; a view-only viewer), §4.4 (Post editor), §7 ("The drawer and the shell's drawers", "⌘K and dialogs"). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/design-system.md` (the controllers on `<body>`), `app/javascript/controllers/admin/drawer_controller.js`, `app/views/layouts/admin.html.erb`, `app/components/admin/editor_screen/header_component.{rb,html.erb}`, `docs/reference/save-rule-and-write-queue.md` ("The write queue").

The drawer follows the Media panel's pattern (surface background, a 1px line on its left edge, no scrim, no page lock) but lies OVER the content with the menu shadow -- the one stated exception to "shadows on menus and popovers only" (spec §4.1). From 1024px it is 400px wide on the right edge; below, a full-screen sheet with a "Back to <title>" button; nothing is designed below 768px. It is rendered once per editor screen, inside `#content` (so a frame navigation to another page replaces it) and outside every form. One controller on `<body>`, `admin--notes`, serves it wherever it is drawn, as `admin--dialog` serves every dialog.

**Files:**
- Create: `app/components/admin/notes_screen/drawer_component.{rb,html.erb}`, `app/javascript/controllers/admin/notes_controller.js`
- Modify: `app/views/layouts/admin.html.erb` (`<body>`), `app/helpers/admin/messages_helper.rb` (`SCRIPT_MESSAGES`), `app/javascript/controllers/admin/drawer_controller.js`, `app/components/admin/editor_screen/header_component.{rb,html.erb}`, `app/components/admin/post_form_component.{rb,html.erb}`, `app/views/admin/pages/show.html.erb`, `app/views/admin/posts/show.html.erb`, `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/integration/admin/notes_drawer_test.rb`, `test/system/admin/notes_drawer_test.rb` (new)

**Interfaces:**
- Consumes: `turbo-frame#notes` and its parts (Tasks 5, 6), `Notes::Counts.for_container`, `Admin::NotesScreen::CountsComponent`.
- Produces:
  - `Admin::NotesScreen::DrawerComponent.new(container:, counts:, title:, view: "editor", open: false, thread: nil, url_options: {})` (`title` is the record's title, for the sheet's "Back to <title>"): `aside#notes-drawer[data-admin--notes-target=drawer][data-src][data-key][hidden]` holding `turbo-frame#notes[data-admin--notes-target=frame]` and `span#notes-counts`.
  - `Admin::EditorScreen::HeaderComponent.new(record:, locale:, url_options: {}, open_notes: nil)`: with a number, the button `button#notes-open[data-admin--notes-target=opener]` with `span#notes-open-count[data-admin--notes-target=total]`, before Preview. `Admin::PostFormComponent.new(post:, locale:, url_options: {}, open_notes: nil)` passes it on.
  - `admin--notes` on `<body>`. Actions: `toggle`, `open` (a marker: `data-notes-key`, used in Task 8), `hold`, `compose`, `close`, `loaded`, `leaving` (both on the notes frame), `selected`, `shellOpened`. Targets: `drawer`, `frame`, `opener`, `total`, `marker`, `counts`, `warning`. It dispatches `admin--notes:opened`. Public methods a later task calls: `refreshCounts(counts)`, `get isOpen`, `get containerKey`.
  - `admin--drawer#standAside` and the event `admin--drawer:opened`.
  - URL parameters on an editor: `?notes=open` opens the drawer on load, `&thread=<id>` shows that thread.
  - Body-level messages: `notes.script.marker.add`, `notes.script.marker.open`, `notes.script.marker.selection`, `notes.script.total`, `notes.script.delete_warning`.

- [ ] **Step 1: Write the failing tests.** `test/integration/admin/notes_drawer_test.rb`:

```ruby
require "test_helper"

class Admin::NotesDrawerTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    as(users(:two)) { [ @page, @block, @post ].each { |subject| Notes::Start.call(subject, body: "A note") } }
  end

  test "the page editor has the Notes button with the open count before Preview, and the drawer outside every form" do
    sign_in_as(users(:two))

    get "/cs-studio/pages/#{@page.id}"

    assert_select "header.admin-editor-header button#notes-open[aria-controls=notes-drawer] #notes-open-count", text: "2"
    assert_operator response.body.index('id="notes-open"'), :<, response.body.index(">Preview<")
    assert_select "aside#notes-drawer[hidden][data-admin--notes-target=drawer][data-key='Page-#{@page.id}'][data-src='/cs-studio/notes/page/#{@page.id}']" do
      assert_select "turbo-frame#notes[data-admin--notes-target=frame]"
      assert_select "button", text: "Back to Pricing"
      assert_select "form", count: 0
    end
    assert_select "form aside#notes-drawer", count: 0
    assert_select "span#notes-counts[data-counts]"
    assert_select "body[data-controller~='admin--notes']"
  end

  test "the post editor has the same button and drawer; ?notes=open and a thread travel to the drawer" do
    thread = Notes::Thread.find_by!(subject: @post)
    sign_in_as(users(:two))

    get "/cs-studio/posts/#{@post.id}", params: { notes: "open", thread: thread.id }

    assert_select "button#notes-open #notes-open-count", text: "1"
    assert_select "aside#notes-drawer[data-open-on-load=true][data-thread='#{thread.id}'][data-src='/cs-studio/notes/post/#{@post.id}']"
  end

  test "a view-only reader gets the button and the drawer" do
    sign_in_as(users(:reader))

    get "/cs-studio/pages/#{@page.id}"

    assert_select "button#notes-open"
    assert_select "aside#notes-drawer"
  end

  test "the editor costs the same statements whatever the number of threads" do
    sign_in_as(users(:two))
    get "/cs-studio/pages/#{@page.id}"
    few = capture_sql { get "/cs-studio/pages/#{@page.id}" }.size
    as(users(:reader)) { 9.times { Notes::Start.call(@block, body: "More") } }
    get "/cs-studio/pages/#{@page.id}"

    assert_equal few, capture_sql { get "/cs-studio/pages/#{@page.id}" }.size
  end
end
```

`test/system/admin/notes_drawer_test.rb`:

```ruby
require "application_system_test_case"

class Admin::NotesDrawerSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_editor(query = "")
    visit "/cs-studio/pages/#{@page.id}#{query}"
    await_admin_controllers
  end

  test "the header button opens the drawer with the focus in it, a note is written, the count follows, Escape closes and gives the focus back" do
    open_editor
    assert_no_selector "#notes-drawer"

    find("#notes-open").click

    assert_selector "#notes-drawer[aria-label='Notes'] #notes-list"
    assert_selector "#notes-open[aria-expanded=true][aria-pressed=true]"
    assert_eventually(message: "the focus never moved into the drawer") { page.evaluate_script("document.activeElement.closest('#notes-drawer') !== null") }

    within("#notes-drawer") { press "New note" }
    find("#notes-new textarea[name=body]").send_keys("Is this page ready?")
    within("#notes-new") { press "Add note" }

    # The new thread replaces the list; Back returns to it.
    assert_selector "#notes-drawer [data-notes-view=thread]", text: "Is this page ready?"
    assert_no_selector "#notes-list"
    assert_selector "#notes-open-count", text: "1"
    assert_equal @page, Notes::Thread.last.subject
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list a[data-note-row]", text: "Is this page ready?"

    find("#notes-list a[data-note-row]").send_keys(:escape)

    assert_no_selector "#notes-drawer"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
  end

  test "the editor stays usable beside the open drawer: it is not modal and has no scrim" do
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list"

    assert_no_selector ".admin-shell__scrim", visible: true
    assert_equal false, page.evaluate_script("document.querySelector('.admin-content-blocks').inert")
    find("body").send_keys([ :control, "k" ])
    assert_selector "dialog[open]"
  end

  test "open is remembered for the next editor in this browser, and Close forgets it" do
    other = create_page(title: "Other")
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list"

    visit "/cs-studio/pages/#{other.id}"
    await_admin_controllers
    assert_selector "#notes-drawer #notes-list[data-notes-container='Page-#{other.id}']"

    within("#notes-drawer") { press "Close" }
    assert_no_selector "#notes-drawer"
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_no_selector "#notes-drawer"
  end

  test "the list is where it was left when a thread is closed again" do
    as(users(:two)) { 30.times { |index| Notes::Start.call(@page, body: "Note #{index}") } }
    open_editor
    find("#notes-open").click
    assert_selector "#notes-list a[data-note-row]", count: 30
    # To the END of the list, so the last row is in view: a native click on a
    # row out of view would scroll to it first, and "where it was left" would
    # no longer be the number read here.
    page.execute_script("const scroller = document.querySelector('#notes-drawer [data-notes-scroller]'); scroller.scrollTop = scroller.scrollHeight")
    at = page.evaluate_script("document.querySelector('#notes-drawer [data-notes-scroller]').scrollTop")
    assert_operator at, :>, 0

    all("#notes-list a[data-note-row]").last.click
    assert_selector "#notes-drawer [data-notes-view=thread]"
    find("#notes-drawer a[data-note-back]").click

    assert_selector "#notes-list"
    assert_eventually(message: "the list did not come back to where it was") { page.evaluate_script("document.querySelector('#notes-drawer [data-notes-scroller]').scrollTop") == at }
  end

  test "?notes=open with a thread opens the drawer at that thread" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "Look here") }.record

    open_editor("?notes=open&thread=#{thread.id}")

    assert_selector "#notes-drawer #note-thread-#{thread.id}", text: "Look here"
    assert_eventually(message: "the thread never took the focus") { page.evaluate_script("document.activeElement.id") == "note-thread-#{thread.id}" }
  end

  test "below 1280px, opening the sidebar drawer closes the notes drawer, and the other way round" do
    original = page.current_window.size
    page.current_window.resize_to(1100, 800)
    open_editor
    find("#notes-open").click
    assert_selector "#notes-drawer"

    find("button[aria-controls=sidebar]").click
    assert_no_selector "#notes-drawer"
    assert_selector "#sidebar[data-open]", visible: :all

    find("#notes-open", visible: :all).execute_script("this.click()") # press_by_script: the shell's scrim covers the header while the sidebar drawer is open
    assert_selector "#notes-drawer"
    assert_no_selector "#sidebar[data-open]", visible: :all
  ensure
    page.current_window.resize_to(*original)
  end

  test "the post editor's drawer takes a note on the post" do
    post = create_post(title: "Hello")
    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers

    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    find("#notes-new textarea[name=body]").send_keys("Check the intro")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-note-thread]", text: "Check the intro"
    assert_equal post, Notes::Thread.last.subject
  end
end
```

(Checked against the code. A row and Back navigate `turbo-frame#notes`, which Turbo never promotes to a visit, and `click_frame_link` waits for the `turbo:load` of a promoted one (`test/application_system_test_case.rb`): so these are plain `.click`s followed by an `assert_selector`, never `click_frame_link`. The top bar's sidebar button is `button[aria-controls=sidebar]` (`Admin::Shell::TopBarComponent#drawer_button`), and the open panel is `#sidebar[data-open]`. `admin--command-palette` opens on `metaKey || ctrlKey` with "k", so Ctrl+K is right in the test browser.)

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/integration/admin/notes_drawer_test.rb`

- [ ] **Step 3: The drawer component.** `drawer_component.rb`:

```ruby
module Admin
  module NotesScreen
    # The notes drawer of an editor (notes spec §4.1): an `<aside>` on the
    # right edge of the content area, 400px wide from 1024px. It follows the
    # Media panel's pattern -- surface background, a 1px line on its left
    # edge, no scrim, no page lock -- and lies OVER the content with the menu
    # shadow, the one stated exception to "shadows on menus and popovers
    # only". Below 1024px it is a full-screen sheet with "Back to <title>".
    # The editor beside it stays usable. Rendered once per screen, outside
    # every form, `hidden` until `admin--notes` opens it.
    #
    # It holds the notes frame empty: the controller sets the frame's `src`
    # (`data-src`, plus the thread or the block to start on) when the drawer
    # first opens, so an editor that never opens its notes never fetches them.
    # `#notes-counts` is the record's counts as the page loaded them; every
    # answer of the frame brings a newer copy.
    #
    # WHEN TO USE WHICH: the shell's left drawers (`admin--drawer`) are the
    # navigation at narrow widths, with a scrim; the media panel is a column
    # of its screen, in the flow; this is a companion to an editor that must
    # not take the editor away.
    class DrawerComponent < Admin::AdminComponent
      def initialize(container:, counts:, title:, view: "editor", open: false, thread: nil, url_options: {})
        @container = container
        @title = title
        @counts = counts
        @view = view
        @open = open
        @thread = thread.to_s[/\A\d+\z/]
        @url_options = url_options
      end

      private

      attr_reader :container, :counts, :thread, :title

      def src = helpers.admin_record_notes_path(*helpers.note_args(container), **{ view: (@view unless @view == "editor"), **@url_options }.compact)

      def key = ::Notes.key(container)

      def open? = @open ? true : false
    end
  end
end
```

`drawer_component.html.erb`:

```erb
<%= tag.aside id: "notes-drawer", hidden: true, tabindex: -1, aria: { label: t(".title") },
      class: "admin-notes-drawer fixed inset-0 z-20 flex flex-col bg-surface focus:outline-none lg:left-auto lg:top-(--admin-top-offset) lg:w-[400px] lg:border-l lg:border-line lg:shadow-menu",
      data: { "admin--notes-target": "drawer", src: src, key: key, open_on_load: open?, thread: thread, action: "keydown.esc->admin--notes#close" } do %>
  <%# The sheet's way back, below 1024px only. %>
  <div class="border-b border-line px-4 py-2 lg:hidden">
    <%= render Admin::ButtonComponent.new(label: t(".back", title: title), variant: :ghost, size: :small, type: "button", data: { action: "admin--notes#close" }) %>
  </div>
  <header class="flex items-center justify-between gap-2 border-b border-line px-4 py-3">
    <h2 class="text-h2 text-ink"><%= t(".title") %></h2>
    <div class="flex items-center gap-1">
      <%= render Admin::ButtonComponent.new(label: t(".new"), variant: :secondary, size: :small, type: "button", data: { action: "admin--notes#compose" }) %>
      <%= render Admin::ButtonComponent.new(label: t(".close"), variant: :ghost, size: :small, type: "button", data: { action: "admin--notes#close" }) %>
    </div>
  </header>
  <div class="min-h-0 flex-1 overflow-y-auto p-4" data-notes-scroller>
    <%= tag.turbo_frame id: "notes", class: "block min-h-full",
          data: { "admin--notes-target": "frame", action: "turbo:frame-load->admin--notes#loaded turbo:before-fetch-request->admin--notes#leaving" } do %>
      <p class="text-sm text-meta"><%= t(".loading") %></p>
    <% end %>
  </div>
  <%= render Admin::NotesScreen::CountsComponent.new(counts: counts, id: "notes-counts") %>
<% end %>
```

- [ ] **Step 4: The controller.** `app/javascript/controllers/admin/notes_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// Notes on an editor screen (notes spec §4.1, §4.3). Lives on <body>, like
// `admin--dialog`: the header's button, the markers on the block cards and
// the drawer are far apart in the document, and cards come and go by Turbo
// Stream without the screen being drawn again.
//
// THE DRAWER (`drawer` target, `Admin::NotesScreen::DrawerComponent`). Opening
// sets the notes frame's `src` -- the record's list of notes, the list at a
// block's group, the list with a new note ready to type, or one thread, which
// is the frame's other view -- shows the drawer and moves the focus into it
// once the frame has loaded; closing gives the focus back to what opened it.
// A thread replaces the list and Back replaces the thread; the list's scroll
// position is kept for the way back. It is NOT a modal: nothing is made inert,
// there is no scrim, and Escape closes it only while the focus is inside (the
// `keydown.esc` action sits on the drawer itself). "Open" is remembered per
// browser in `localStorage`, a convenience: the next editor opens with its
// notes showing. A shell drawer opening closes this one, and this one opening
// tells the shell's to stand aside (`admin--notes:opened`).
//
// THE COUNTS (`counts` target). One record's open-thread counts,
// `{ total, subjects: { "<key>": n } }`, written by the server into the page
// and into every answer of the notes frame; whichever copy arrived last is
// the truth. From it this fills the header's number (`total`), every marker
// (`marker`: a count pill; without notes nothing at rest, and the same control
// as "add a note" on hover or focus of its card) and the warning in
// a block's delete dialog (`warning`). A card drawn again by a stream
// connects its marker and is filled like the rest, which is why the server
// never renders a count into a card.
//
// A SELECTION. With text selected in a rich-text field, that block's marker
// reads "Note on selection" and a press starts a note quoting the text (cut
// to 500 characters; a copy, decision D4). The selection is noted at
// `mousedown` on the marker, because the press itself may move it.
//
// Nothing here writes a record or touches an editor form; note forms are
// ordinary Turbo forms inside the frame.
const REMEMBER = "cs-notes-open"
const MAX_QUOTE = 500

export default class extends Controller {
  static targets = [ "drawer", "frame", "opener", "total", "marker", "counts", "warning" ]

  initialize() {
    this.counts = { total: 0, subjects: {}, unread: [] }
    this.pending = null
    this.selection = null
    this.held = null
  }

  // --- targets coming and going ----------------------------------------------

  drawerTargetConnected(drawer) {
    if (drawer.dataset.openOnLoad === "true") this.show({ thread: drawer.dataset.thread || null })
    else if (this.remembered) this.show({ focus: false })
  }

  drawerTargetDisconnected() {
    this.pending = null
    this.returnTo = null
  }

  countsTargetConnected(element) {
    this.refreshCounts(JSON.parse(element.dataset.counts))
  }

  markerTargetConnected() { this.schedulePaint() }
  markerTargetDisconnected() { this.schedulePaint() }
  warningTargetConnected() { this.schedulePaint() }
  totalTargetConnected() { this.schedulePaint() }

  // --- actions ----------------------------------------------------------------

  toggle(event) {
    if (this.isOpen) this.close()
    else this.show({ trigger: event.currentTarget })
  }

  // `mousedown` on a marker: what is selected NOW, before the press moves it.
  hold() {
    this.held = this.selection
  }

  // A marker, or "Add note" in a block's menu (`data-notes-compose`). With a
  // selection in that block: a new note quoting it. A marker with open
  // threads: the drawer at that block's group. Otherwise: a new note on the
  // block, ready to type.
  open(event) {
    const marker = event.currentTarget
    const key = marker.dataset.notesKey
    const quote = this.held?.key === key ? this.held.text : null
    this.held = null
    if (quote) this.show({ compose: key, quote, trigger: marker })
    else if (!marker.hasAttribute("data-notes-compose") && (this.counts.subjects[key] || 0) > 0) this.show({ group: key, trigger: marker })
    else this.show({ compose: key, trigger: marker })
  }

  // "New note" in the drawer's header: a note on the record itself.
  compose() {
    this.show({ compose: this.containerKey })
  }

  close(event) {
    if (!this.hasDrawerTarget || !this.isOpen) return
    // An Escape something inside already used (the mention picker's).
    if (event?.type === "keydown" && event.defaultPrevented) return

    this.drawerTarget.hidden = true
    this.syncOpeners()
    this.forget()
    if (this.returnTo?.isConnected) this.returnTo.focus()
    this.returnTo = null
  }

  // A shell drawer opened (`admin--drawer:opened`): this one makes room, and
  // the focus is the shell drawer's. Not a "Close": the choice stays
  // remembered.
  shellOpened() {
    if (!this.hasDrawerTarget || !this.isOpen) return
    this.drawerTarget.hidden = true
    this.syncOpeners()
  }

  // `turbo:before-fetch-request` on the notes frame: the list is about to be
  // replaced (a row was followed, a form was sent). Where it stood is kept
  // for the way back.
  leaving() {
    if (this.frameTarget.querySelector("[data-notes-view='list']")) this.listScroll = this.scroller?.scrollTop ?? null
  }

  // `turbo:frame-load` on the notes frame: put the focus where the opener
  // asked; in a thread, on the thread; and bring the list back to where it
  // was left.
  loaded() {
    const pending = this.pending
    this.pending = null
    const view = this.frameTarget.querySelector("[data-notes-view]")
    if (!view || !this.isOpen) return

    if (view.dataset.notesView === "thread") {
      // A thread just opened, or just redrawn after a note was sent from it
      // (the form that had the focus is gone).
      if (pending?.thread || pending?.focus || !this.drawerTarget.contains(document.activeElement)) this.focus(view)
      return
    }

    if (pending?.compose) this.focus(view.querySelector("#notes-new textarea"))
    else if (pending?.group) this.focus(view.querySelector(`[data-notes-group="${CSS.escape(pending.group)}"]`))
    else if (this.listScroll != null && this.scroller) this.scroller.scrollTop = this.listScroll
    else if (pending?.focus) this.focus(this.drawerTarget)
    this.listScroll = null
  }

  get scroller() {
    return this.hasDrawerTarget ? this.drawerTarget.querySelector("[data-notes-scroller]") : null
  }

  // `selectionchange` on the document.
  selected() {
    const selection = document.getSelection()
    const text = selection && !selection.isCollapsed ? selection.toString().trim() : ""
    const editor = text ? this.elementOf(selection.anchorNode)?.closest("[contenteditable='true']") : null
    const key = editor ? this.blockKey(editor) : null
    const next = key ? { key, text: text.slice(0, MAX_QUOTE) } : null
    if (next?.key === this.selection?.key && next?.text === this.selection?.text) return
    this.selection = next
    this.schedulePaint()
  }

  // --- the drawer ---------------------------------------------------------------

  get isOpen() {
    return this.hasDrawerTarget && !this.drawerTarget.hidden
  }

  get containerKey() {
    return this.hasDrawerTarget ? this.drawerTarget.dataset.key : null
  }

  show({ thread = null, group = null, compose = null, quote = null, trigger = null, focus = true } = {}) {
    if (!this.hasDrawerTarget) return

    if (trigger) this.returnTo = trigger
    // The list, or -- its other view -- one thread: `<src>/threads/<id>`.
    const url = new URL(this.drawerTarget.dataset.src, window.location.origin)
    if (thread) url.pathname = `${url.pathname}/threads/${encodeURIComponent(thread)}`
    if (compose) url.searchParams.set("compose", compose)
    if (quote) url.searchParams.set("quote", quote)
    this.listScroll = null
    this.pending = { thread, group, compose, focus }

    const wasOpen = this.isOpen
    this.drawerTarget.hidden = false
    this.syncOpeners()
    this.remember()
    if (!wasOpen) this.dispatch("opened")

    const frame = this.frameTarget
    const next = url.pathname + url.search
    if (frame.getAttribute("src") === next && frame.querySelector("[data-notes-view]")) this.loaded()
    else frame.src = next
  }

  focus(element) {
    if (!element) return
    if (!element.matches("a, button, input, textarea, select, [tabindex]")) element.setAttribute("tabindex", "-1")
    element.focus({ preventScroll: false })
    element.scrollIntoView({ block: "nearest" })
  }

  syncOpeners() {
    // The header's button is a toggle: pressed while the drawer is open.
    this.openerTargets.forEach((opener) => {
      opener.setAttribute("aria-expanded", this.isOpen ? "true" : "false")
      opener.setAttribute("aria-pressed", this.isOpen ? "true" : "false")
    })
  }

  // --- the counts -----------------------------------------------------------------

  refreshCounts(counts) {
    this.counts = { total: counts?.total || 0, subjects: counts?.subjects || {}, unread: counts?.unread || [] }
    this.schedulePaint()
  }

  // Several targets connect in one render: paint once, after them.
  schedulePaint() {
    if (this.painting) return
    this.painting = true
    queueMicrotask(() => {
      this.painting = false
      this.paint()
    })
  }

  paint() {
    const text = messages(this.element)
    const { total, subjects } = this.counts
    // "Unread for you" turns a count accent (spec §4.5): the keys whose open
    // threads hold a delivery the viewer has not read.
    const unread = new Set(this.counts.unread)

    this.totalTargets.forEach((element) => {
      element.textContent = String(total)
      element.hidden = total === 0
      element.toggleAttribute("data-unread", unread.size > 0)
      element.closest("[data-admin--notes-target~='opener']")?.setAttribute("aria-label", text.t("notes.script.total", { count: total }))
    })

    this.markerTargets.forEach((marker) => {
      const key = marker.dataset.notesKey
      const count = subjects[key] || 0
      const selecting = this.selection?.key === key
      const name = marker.dataset.notesName
      const number = marker.querySelector("[data-notes-count]")
      const quoting = marker.querySelector("[data-notes-selection]")
      number.textContent = count > 0 ? String(count) : ""
      number.hidden = count === 0 || selecting
      quoting.hidden = !selecting
      marker.toggleAttribute("data-has-notes", count > 0 || selecting)
      marker.toggleAttribute("data-unread", unread.has(key))
      marker.setAttribute("aria-label", selecting ? text.t("notes.script.marker.selection", { name })
        : count > 0 ? text.t("notes.script.marker.open", { count, name }) : text.t("notes.script.marker.add", { name }))
    })

    // A delete dialog's warning: the open notes on everything inside the card
    // or tile it names (a section's own and its blocks').
    this.warningTargets.forEach((warning) => {
      const within = document.getElementById(warning.dataset.notesWithin)
      const keys = new Set([ ...(within?.querySelectorAll("[data-admin--notes-target~='marker']") || []) ].map((marker) => marker.dataset.notesKey))
      const count = [ ...keys ].reduce((sum, key) => sum + (subjects[key] || 0), 0)
      warning.hidden = count === 0
      warning.textContent = count === 0 ? "" : text.t("notes.script.delete_warning", { count })
    })
  }

  // --- small things ---------------------------------------------------------------

  elementOf(node) {
    return node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement
  }

  // The block an element belongs to, as a notes key: a card or tile is
  // `#content_block_<id>`, an open form in a section `#block-<id>-panel`.
  blockKey(element) {
    const holder = element.closest("[id^='content_block_'], [id^='block-'][id$='-panel']")
    const id = holder?.id.match(/\d+/)?.[0]
    return id ? `ContentBlock-${id}` : null
  }

  get remembered() {
    try {
      return window.localStorage.getItem(REMEMBER) === "1"
    } catch {
      return false
    }
  }

  remember() {
    try {
      window.localStorage.setItem(REMEMBER, "1")
    } catch {
      // A convenience only.
    }
  }

  forget() {
    try {
      window.localStorage.removeItem(REMEMBER)
    } catch {
      // As above.
    }
  }
}
```

- [ ] **Step 5: `<body>` and the shell's drawers.** In `app/views/layouts/admin.html.erb`, on `<body>`: add `admin--notes` to `data-controller`, and to `data-action` add `selectionchange@document->admin--notes#selected admin--notes:opened->admin--drawer#standAside admin--drawer:opened->admin--notes#shellOpened`. Extend the comment above it with two sentences: `admin--notes` is the fourth controller on `<body>`, for the same reason as `admin--dialog`; the two drawer controllers tell each other when one opens.

In `app/javascript/controllers/admin/drawer_controller.js`: at the end of `open(panel, trigger)` add `this.dispatch("opened")`, and add the method

```js
  // The notes drawer opened (`admin--notes:opened`): a shell drawer makes
  // room. The focus is the notes drawer's, so it is not handed back here.
  standAside() { this.closeAll({ refocus: false }) }
```

In `Admin::MessagesHelper::SCRIPT_MESSAGES` add `notes.script.marker.add notes.script.marker.open notes.script.marker.selection notes.script.total notes.script.delete_warning` (the controller is on `<body>`, so its messages are `<body>`'s), with a line in the comment saying so.

- [ ] **Step 6: The header's button.** In `header_component.rb`: `def initialize(record:, locale:, url_options: {}, open_notes: nil)`, store `@open_notes = open_notes`, and add

```ruby
      # The Notes button (notes spec §4.3) is drawn for a screen that also
      # draws the drawer and hands over the record's open-thread count. Its
      # number is the server's as the page loads; `admin--notes` keeps it
      # current from then on.
      def notes? = !@open_notes.nil?

      def open_notes = @open_notes.to_i
```

In `header_component.html.erb`, after the `SaveStatusComponent` line and before the Preview link:

```erb
      <% if notes? %>
        <%= tag.button type: "button", id: "notes-open", class: "#{setup_secondary_link_class} inline-flex items-center gap-1.5",
              aria: { controls: "notes-drawer", expanded: "false", pressed: "false", label: t(".notes_label", count: open_notes) },
              data: { "admin--notes-target": "opener", action: "admin--notes#toggle" } do %>
          <span><%= t(".notes") %></span>
          <%= tag.span open_notes, id: "notes-open-count", hidden: open_notes.zero?, class: "font-cs-mono text-label text-meta", data: { "admin--notes-target": "total" } %>
        <% end %>
      <% end %>
```

The button's four states are the handoff's ("Notes header button"): no open threads (the word alone), open threads (the count in mono), unread for you (`data-unread` on the count, set by the script: a filled accent pill) and pressed while the drawer is open (`aria-pressed="true"`). Style the last two from those attributes (`data-[unread]:…`, `aria-pressed:…`), with the handoff's classes.

`Admin::PostFormComponent`: `def initialize(post:, locale:, url_options: {}, open_notes: nil)`, keep it in `@open_notes`, and pass `open_notes: @open_notes` to the `HeaderComponent.new` in its template.

- [ ] **Step 7: The two editors.** In `app/views/admin/pages/show.html.erb`: above the header, `<% note_counts = Notes::Counts.for_container(@page, user: Current.user) %>` with a comment (two queries for the header's number, every marker and which of them hold something unread for the viewer; in the view because every way this screen is rendered needs it); pass `open_notes: note_counts.fetch("total")` to `HeaderComponent.new`; and as the last line of the file:

```erb
<%# The notes drawer (notes spec §4.1): once per screen, after everything
    else and outside every form. `?notes=open` (a link from the inbox, the
    posts list) opens it on load, at `?thread=` when there is one. %>
<%= render Admin::NotesScreen::DrawerComponent.new(container: @page, counts: note_counts, title: Locales.read(@page, :title, locale: admin_locale).presence || t("admin.components.notes_screen.drawer.untitled"),
      open: params[:notes] == "open", thread: params[:thread], url_options: admin_url_options) %>
```

In `app/views/admin/posts/show.html.erb` the same three things for `@post` (`open_notes:` goes to `PostFormComponent.new`; the drawer's `title:` is the post's, read the same way).

- [ ] **Step 8: The strings.** Under `en.admin.components`: `editor_screen: { header: { notes: "Notes", notes_label: { one: "Notes, %{count} open", other: "Notes, %{count} open" } } }` (merge into the tree; `components.en.yml` holds the header's other keys and is not edited) and `notes_screen: { drawer: { title: "Notes", new: "New note", close: "Close", loading: "Loading notes…", back: "Back to %{title}", untitled: "(untitled)" } }`. Under `en.admin.notes.script`:

```yaml
        total:
          one: "Notes, %{count} open"
          other: "Notes, %{count} open"
        marker:
          add: "Add a note on %{name}"
          open:
            one: "%{count} open note on %{name}"
            other: "%{count} open notes on %{name}"
          selection: "Add a note on the selected text in %{name}"
        delete_warning:
          one: "It has %{count} open note, which is deleted with it."
          other: "It has %{count} open notes, which are deleted with it."
```

Add the drawer's two files and `notes_controller.js` to `CONVERTED`.

- [ ] **Step 9: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/integration/admin test/components test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/notes_drawer_test.rb test/system/admin/editor_header_test.rb test/system/admin/autosave_test.rb
```

The two existing system files are run because the header gained a control and `<body>` a controller; they must pass with no edited assertion.

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat: the notes drawer in the page and post editors, opened from the header with the open count" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 8: Count markers and "Add note" on block cards and section tiles, a note on a selection, the delete warning

**Spec:** §4.3 (Block card and section tile, Quote, the translation tabs), D4, D12 ("after a warning when it has open threads"). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/content-blocks-and-types.md` ("Sections": cards, tiles, panels, and why a form is never removed), `app/components/admin/block_card_component.html.erb`, `app/components/admin/editor_screen/block_tile_component.html.erb`, `app/components/admin/editor_screen/section_card_component.html.erb`.

A card is drawn in many places (the page, and every Turbo Stream that adds, moves or redraws a block), so the server draws the same marker everywhere, with no number in it; `admin--notes` (Task 7) fills each from the record's counts as it connects. Nothing in this task adds a query.

The look (spec §4.3, §4.5): with open threads the marker is a neutral count pill, pressed to open the drawer at that block's group. Without, **nothing is shown at rest** (no count when it is zero): the same control appears as "add a note" on hover or keyboard focus of the card, and **"Add note" is always in the block's ⋯ menu**, so neither touch nor a test depends on hover. A section's own header carries no marker and no total: only its tiles count, so a thread is never counted twice.

**Files:**
- Create: `app/components/admin/notes_screen/marker_component.{rb,html.erb}`
- Modify: `app/components/admin/block_card_component.{rb,html.erb}`, `app/components/admin/editor_screen/block_tile_component.{rb,html.erb}`, `app/components/admin/editor_screen/section_card_component.{rb,html.erb}`, `app/components/admin/editor_screen/delete_block_dialog_component.{rb,html.erb}`, `app/controllers/admin/content_blocks_controller.rb` (`destroy`), `app/components/admin/notes_screen/thread_component.html.erb` (one `data-` attribute, Step 7), `app/javascript/controllers/admin/notes_controller.js` (`markActive`, Step 7), `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/components/admin/notes_screen/marker_component_test.rb`, `test/system/admin/notes_markers_test.rb` (new), `test/components/admin/block_card_component_test.rb`, `test/integration/admin/content_blocks_test.rb`

**Interfaces:**
- Consumes: `admin--notes` (`marker`, `warning` targets; `hold`, `open` actions), `Notes.key`, `Admin::NotesScreen::CountsComponent`, `Notes::Counts.for_container`.
- Produces:
  - `Admin::NotesScreen::MarkerComponent.new(subject:, name:)`: `button#notes-marker-<key>[data-admin--notes-target=marker][data-notes-key=<key>][data-notes-name]` holding `[data-notes-count]` and `[data-notes-selection]`; `data-has-notes` is set by the script.
  - A marker on: a top-level block card and a translation tab's group card (not on a section's open panel, whose tile carries it) and every section tile. None on a section card's header.
  - "Add note" in the ⋯ menu of a block card and of a tile: `button[data-notes-key=<key>][data-notes-compose]` with `data-action="admin--notes#open"`.
  - `p[data-admin--notes-target=warning][data-notes-within=<dom id>]` in the delete dialog of a block and of a section.
  - After a block's delete, the answer carries `turbo_stream.replace("notes-counts", …)` with the page's fresh counts.
  - The thread view's root gains `data-notes-subject=<key of what the thread is on>`; while that thread is open in the drawer, the card or tile of its block carries `data-notes-active` (set and taken back by `admin--notes#markActive`).

- [ ] **Step 1: Write the failing tests.** `test/components/admin/notes_screen/marker_component_test.rb`:

```ruby
require "test_helper"

class Admin::NotesScreen::MarkerComponentTest < ViewComponent::TestCase
  test "a marker names its block, carries its key and holds no number" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline(Admin::NotesScreen::MarkerComponent.new(subject: block, name: "Rich text"))

    assert_selector "button#notes-marker-ContentBlock-#{block.id}[type=button][data-admin--notes-target=marker][data-notes-key='ContentBlock-#{block.id}'][aria-label='Add a note on Rich text']"
    assert_selector "button [data-notes-count]", visible: :all, text: ""
    assert_selector "button [data-notes-selection]", visible: :all, text: "Note on selection"
  end
end
```

Append to `test/components/admin/block_card_component_test.rb` (use the file's own way of building a card):

```ruby
  test "a card in the list carries a notes marker, for a viewer who can't edit too; an open panel carries none" do
    page = create_page(title: "Noted")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline(Admin::BlockCardComponent.new(page: page, block: block, locale: "en", editable: false))
    assert_selector "#notes-marker-ContentBlock-#{block.id}"

    render_inline(Admin::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true, placement: :panel))
    assert_no_selector "[data-admin--notes-target=marker]"
  end
```

Append to `test/integration/admin/content_blocks_test.rb` (with the file's own sign-in and Turbo Stream headers):

```ruby
  test "deleting a block answers with the page's fresh note counts" do
    page = create_page(title: "Noted", published: false)
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { [ page, block ].each { |subject| Notes::Start.call(subject, body: "A note") } }

    delete "/cs-studio/pages/#{page.id}/content_blocks/#{block.id}", headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_select "turbo-stream[action=replace][target=notes-counts] template span#notes-counts" do |nodes|
      assert_equal [ 1, { "Page-#{page.id}" => 1 } ], JSON.parse(nodes.first["data-counts"]).values_at("total", "subjects")
    end
  end
```

`test/system/admin/notes_markers_test.rb`:

```ruby
require "application_system_test_case"

class Admin::NotesMarkersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Pricing")
    @text = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @inside = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
  end

  def marker(block) = "#notes-marker-ContentBlock-#{block.id}"

  test "a block without notes shows no marker at rest; Add note in its menu starts one, and then the marker is a pill with the count" do
    open_editor
    assert_selector "#{marker(@text)}:not([data-has-notes])", visible: :all
    assert_equal "0", find(marker(@text), visible: :all).evaluate_script("getComputedStyle(this).opacity")

    within("##{ActionView::RecordIdentifier.dom_id(@text)}") do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end

    assert_selector "#notes-drawer #notes-new h3", text: "New note on Rich text"
    assert_eventually(message: "the new note's field never took the focus") { page.evaluate_script("document.activeElement.name") == "body" }
    find("#notes-new textarea[name=body]").send_keys("Shorter, please")
    within("#notes-new") { press "Add note" }

    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"
    assert_selector "#notes-open-count", text: "1"
    assert_selector "#notes-drawer [data-note-thread]", text: "Shorter, please"
    assert_selector "#notes-drawer [data-note-thread] h3", text: "Rich text"
    assert_equal "1", find(marker(@text)).evaluate_script("getComputedStyle(this).opacity")
    assert_equal @text, Notes::Thread.last.subject
  end

  test "the marker of a block without notes appears when the keyboard reaches it, and starts a note" do
    open_editor
    page.execute_script("document.querySelector(arguments[0]).focus()", marker(@text))

    assert_eventually(message: "the focused marker stayed invisible") { find(marker(@text), visible: :all).evaluate_script("getComputedStyle(this).opacity") == "1" }
    find(marker(@text), visible: :all).send_keys(:enter)

    assert_selector "#notes-drawer #notes-new h3", text: "New note on Rich text"
  end

  test "a marker with notes opens the drawer at that block's group; a tile in a section has its own" do
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor

    assert_selector "#{marker(@inside)}[data-has-notes][aria-label='1 open note on Image']"
    find(marker(@inside)).click

    assert_selector "#notes-group-ContentBlock-#{@inside.id} h4", text: "Image · column 1"
    assert_eventually(message: "the group never took the focus") { page.evaluate_script("document.activeElement.id") == "notes-group-ContentBlock-#{@inside.id}" }
  end

  test "with text selected in a block's rich text, its marker starts a note that quotes it" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@text)} [contenteditable=true]").send_keys("The plan costs 49 euros a month.")
    assert_writes_settled
    page.execute_script(<<~JS, ActionView::RecordIdentifier.dom_id(@text))
      const paragraph = document.querySelector(`#${arguments[0]} [contenteditable=true] p`)
      const range = document.createRange()
      range.selectNodeContents(paragraph)
      const selection = document.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    JS

    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-selection]", text: "Note on selection"
    find(marker(@text)).click

    assert_selector "#notes-new blockquote", text: "The plan costs 49 euros a month."
    find("#notes-new textarea[name=body]").send_keys("Is that still the price?")
    within("#notes-new") { press "Add note" }

    assert_selector "[data-note-thread] blockquote", text: "The plan costs 49 euros a month."
    assert_equal "The plan costs 49 euros a month.", Notes::Thread.last.quote
    assert_writes_settled
    assert_equal 0, Audit::Event.where(action: "access.denied").count
  end

  test "deleting a block with open notes warns first, and the count goes with the block" do
    as(users(:two)) { 2.times { Notes::Start.call(@text, body: "A note") } }
    open_editor
    assert_selector "#notes-open-count", text: "2"

    within("##{ActionView::RecordIdentifier.dom_id(@text)}") do
      find("button[aria-label='Block actions']").click
      press "Delete block…"
    end

    assert_selector "dialog[open] [data-admin--notes-target=warning]", text: "It has 2 open notes, which are deleted with it."
    within("dialog[open]") { press "Delete block" }

    assert_no_selector marker(@text)
    assert_no_selector "#notes-open-count"
    assert_equal 0, Notes::Thread.count
  end

  test "a section's delete warning counts the notes on its blocks, and a block without notes is deleted without one" do
    as(users(:two)) { Notes::Start.call(@inside, body: "Wrong picture") }
    open_editor

    assert_selector "#delete-section-#{@section.id} [data-admin--notes-target=warning]", visible: :all, text: "It has 1 open note, which is deleted with it."
    assert_selector "#delete-block-#{@text.id} [data-admin--notes-target=warning]", visible: :all, text: ""
  end

  test "a card drawn again by a stream gets its count back" do
    as(users(:two)) { Notes::Start.call(@text, body: "A note") }
    open_editor
    assert_selector "#{marker(@text)} [data-notes-count]", text: "1"

    within("##{ActionView::RecordIdentifier.dom_id(@text)}") do
      find("button[aria-label='Block actions']").click
      press "Duplicate"
    end

    assert_selector ".admin-block-card [data-admin--notes-target=marker]:not([data-has-notes])", visible: :all, minimum: 1 # the copy: no notes
    assert_selector "#{marker(@text)}[data-has-notes] [data-notes-count]", text: "1"
  end
end
```

(Checked against the code: the card's menu is `Admin::MenuComponent.new(label: "⋯", aria_label: "Block actions")`, a button whose text is "⋯", which is why it is found by its `aria-label` and not with `press`; its items read "Duplicate" and "Delete block…", and the dialog's confirm is `admin.components.editor_screen.delete_block_dialog.confirm`, "Delete block". A card and a tile are both `#content_block_<id>` (`dom_id`), and the dialogs are `#delete-block-<id>` and `#delete-section-<id>`.)

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/components/admin/notes_screen test/components/admin/block_card_component_test.rb test/integration/admin/content_blocks_test.rb`

- [ ] **Step 3: The marker.** `marker_component.rb`:

```ruby
module Admin
  module NotesScreen
    # The notes marker of one block (notes spec §4.3), on its card or tile.
    # With open threads: a neutral pill with their number (§4.5: accent is
    # for "unread and addressed to you" only). Without: nothing at rest --
    # the system shows no count at zero -- and the same control as "add a
    # note" while the pointer is over the card or the keyboard's focus is in
    # it. "Add note" in the block's ⋯ menu is the path that depends on
    # neither.
    # The server draws it WITHOUT a number: a card is drawn by the page and by
    # every stream that adds, moves or redraws a block, and none of them
    # should cost a query for a count. `admin--notes` fills it from the
    # record's counts when it connects (`data-has-notes`, the number, the
    # label), and turns it into "Note on selection" while text is selected in
    # that block's rich text.
    #
    # In the document for everyone who can read the page, whether or not they
    # can edit it (decision D3); a test presses the menu item or focuses the
    # marker, never waits for a hover.
    class MarkerComponent < Admin::AdminComponent
      CLASSES = "admin-notes-marker inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-full border border-transparent px-1.5 py-0.5 " \
                "font-cs-mono text-label leading-none text-meta opacity-0 hover:bg-sunken hover:text-ink " \
                "focus-visible:opacity-100 focus-visible:outline-2 focus-visible:outline-accent " \
                "[.admin-block-card:hover_&]:opacity-100 [.admin-block-card:focus-within_&]:opacity-100 " \
                "[.admin-block-tile:hover_&]:opacity-100 [.admin-block-tile:focus-within_&]:opacity-100 " \
                "data-[has-notes]:border-line-strong data-[has-notes]:opacity-100 " \
                "data-[unread]:border-accent-tint data-[unread]:bg-accent-tint data-[unread]:text-accent".freeze

      def initialize(subject:, name:)
        @subject = subject
        @name = name
      end

      private

      attr_reader :name

      def key = ::Notes.key(@subject)
    end
  end
end
```

`marker_component.html.erb`:

```erb
<%= tag.button type: "button", id: "notes-marker-#{key}", class: CLASSES, aria: { label: t(".add", name: name), controls: "notes-drawer" },
      data: { "admin--notes-target": "marker", notes_key: key, notes_name: name, action: "mousedown->admin--notes#hold admin--notes#open" } do %>
  <span aria-hidden="true">✎</span><span data-notes-count hidden></span><span data-notes-selection hidden><%= t(".selection") %></span>
<% end %>
```

- [ ] **Step 4: Where it goes.**

`block_card_component.rb`: add `def note_marker = Admin::NotesScreen::MarkerComponent.new(subject: block, name: label)` beside `delete_dialog`. `block_card_component.html.erb`: in the `elsif !list?` branch, after the `<span …><%= label %></span>`, and in the `else` branch, directly after the label `<button>…</button>` (before the `Move up / Move down` comment), add `<%= render note_marker %>`. Not in the `unavailable?` and `panel?` branches: an unavailable card has only Delete, and a panel's tile carries the marker.

`block_tile_component.rb`: `def note_marker = Admin::NotesScreen::MarkerComponent.new(subject: block, name: label)`. `block_tile_component.html.erb`: between the face `</button>` and `<% if editable? %>`:

```erb
  <%# The notes marker (notes spec §4.3): outside the `editable?` block below, because a
      viewer who can only read the page writes notes too. %>
  <div class="flex shrink-0 items-center"><%= render note_marker %></div>
```

The section card's header gets no marker (spec §4.3).

**"Add note" in the menus.** `block_card_component.html.erb`, as the FIRST item of the ⋯ menu (handoff, "Block card marker"):

```erb
          <% menu.with_item do %>
            <%= tag.button t(".add_note"), type: "button", class: menu_item_class,
                  data: { action: "admin--notes#open", notes_key: ::Notes.key(block), notes_compose: true } %>
          <% end %>
```

and the same item first in `block_tile_component.html.erb`'s menu (`class: menu_item_class`). The menus exist only for a viewer who can edit; a view-only viewer reaches the marker by hover or by the keyboard.

- [ ] **Step 5: The warning.** `delete_block_dialog_component.rb`: add `def within_id = ActionView::RecordIdentifier.dom_id(block)`. Its template becomes:

```erb
<%= render Admin::ConfirmDialogComponent.new(destructive: true, id: dialog_id, title: t(".title"), body: t(".body")) do |dialog| %>
  <%# Filled by `admin--notes` while the block has open notes (notes spec D12): its
      threads are deleted with it. Empty and hidden otherwise. %>
  <% dialog.with_details do %>
    <%= tag.p hidden: true, class: "text-sm text-warn-ink", data: { "admin--notes-target": "warning", notes_within: within_id } %>
  <% end %>
  <% dialog.with_confirm_action do %>
    <%= form_with url: destroy_path, method: :delete do %>
      <%= render Admin::ButtonComponent.new(label: t(".confirm"), variant: :danger, type: "submit") %>
    <% end %>
  <% end %>
<% end %>
```

In `section_card_component.html.erb`, inside the delete dialog's existing `dialog.with_details` block, after the `delete_count` render: `<%= tag.p hidden: true, class: "mt-1 text-sm text-warn-ink", data: { "admin--notes-target": "warning", notes_within: dom_id } %>` (the section card's own id: the sum then covers every tile's marker).

- [ ] **Step 6: Fresh counts after a delete.** In `Admin::ContentBlocksController#destroy`, the success answer becomes

```ruby
      # The notes on what was deleted are gone with it (`Notes::Remove`): the
      # header's number and the markers are told with the same answer.
      render turbo_stream: [ *removal_streams(block, kept_ids, section), *page_base_streams,
        turbo_stream.replace("notes-counts", Admin::NotesScreen::CountsComponent.new(counts: Notes::Counts.for_container(@page, user: Current.user), id: "notes-counts")) ]
```

- [ ] **Step 7: The active block.** While a thread is open in the drawer, its block's card (or tile) has an accent border (handoff, "Block card marker"). The thread view names its subject: in `thread_component.html.erb` add `notes_subject: ::Notes.key(thread.subject_type, thread.subject_id)` to the root's `data:`. In `notes_controller.js`, at the end of both branches of `loaded()` and in `close()` and `shellOpened()`, call `this.markActive()`:

```js
  // The block whose thread is showing (handoff: its card's border is accent
  // while the thread is open). One at a time; none in the list view or with
  // the drawer closed. An attribute, taken back here: nothing a redrawn
  // card could keep by mistake.
  markActive() {
    const view = this.isOpen ? this.frameTarget.querySelector("[data-notes-view='thread']") : null
    const key = view?.dataset.notesSubject
    this.markerTargets.forEach((marker) => {
      const holder = marker.closest(".admin-block-tile, .admin-block-card")
      holder?.toggleAttribute("data-notes-active", Boolean(key) && marker.dataset.notesKey === key)
    })
  }
```

(`loaded()` returns early from its thread branch: call `markActive()` before that `return`.) Call it from `markerTargetConnected` too, for a card redrawn by a stream while its thread is open. The border: add `data-[notes-active]:border-accent` to the class list of the block card's wrapper in `block_card_component.html.erb` and of the tile's root in `block_tile_component.html.erb`. Add to `notes_markers_test.rb`:

```ruby
  test "the block whose thread is open is marked, and unmarked when the drawer shows the list again" do
    thread = as(users(:two)) { Notes::Start.call(@text, body: "About this block") }.record
    open_editor
    find(marker(@text)).click
    find("#note-row-#{thread.id}").click

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@text)}[data-notes-active]"
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-list"
    assert_no_selector "[data-notes-active]"
  end
```

- [ ] **Step 8: The strings.** Under `en.admin.components.notes_screen`: `marker: { add: "Add a note on %{name}", selection: "Note on selection" }`; under `en.admin.components`: `block_card: { add_note: "Add note" }` and `editor_screen: { block_tile: { add_note: "Add note" } }`. Add the marker's two files to `CONVERTED`.

- [ ] **Step 9: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/components test/integration/admin test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/notes_markers_test.rb test/system/admin/sections_test.rb test/system/admin/blocks_test.rb
```

`sections_test.rb` and `blocks_test.rb` are run because every card and tile gained a control; they must pass with no edited assertion (a test that counts the buttons of a card is the one place an edit with a stated reason is expected).

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat: a count marker and Add note on every block card and section tile, a note on a selection, a warning before a block with notes is deleted" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 9: The media panel, and the open count in the posts list, the page tree and the media grid

**Spec:** §4.4 (Media library, Posts list, Page tree, Trash), §8 (trash visibility, Constant queries), §9 ("Counts on every list"). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/media.md` ("CS Studio's Media module"), `docs/reference/editors-and-translation-pair.md` ("The posts list"), `app/components/admin/tree_component.rb`.

Each surface reads its counts in **one** grouped query over the rows it is about to draw (`Notes::Counts.by_container`), with one more beside it for "unread for you" (`Notes::Counts.unread_among`, decision P27), after those rows were narrowed by the read scope, so a count never exists for a record the viewer may not read or that is in the trash. These lists are not live (spec §6.1): their counts are fresh on load.

**Files:**
- Modify: `app/components/admin/media_library/panel_component.{rb,html.erb}`, `tile_component.{rb,html.erb}`, `grid_component.{rb,html.erb}`, `app/controllers/admin/media_controller.rb` (`grid_streams`), `app/components/admin/posts_screen/table_component.{rb,html.erb}`, `app/controllers/admin/posts_controller.rb` (`index`), `app/views/admin/posts/index.html.erb`, `app/components/admin/tree_component.{rb,html.erb}`, `app/components/admin/tree_node_component.{rb,html.erb}`, `config/locales/admin/notes.en.yml`
- Test: `test/integration/admin/note_counts_test.rb` (new), `test/integration/trash_visibility_test.rb`, `test/system/admin/media_library_test.rb`

**Interfaces:**
- Consumes: `Notes::Counts.by_container(type, ids) -> { id => Integer }`, `Notes::Counts.unread_among(type, ids, user) -> Set<id>` (Task 5), `turbo-frame#notes` (`GET admin_record_notes_path("media", id, view: "media")`), `?notes=open` on an editor (Task 7).
- Produces:
  - Media panel: `div#media-notes` holding `turbo-frame#notes[src][loading=lazy]`, after "Used on", outside the panel's autosave form. `?thread=<id>` on `/media?selected=<id>` makes the frame's `src` that thread's view.
  - `Admin::MediaLibrary::TileComponent.new(..., open_notes: 0, notes_unread: false)`: the chip `span[data-notes-chip]` (`[data-unread]` when the viewer has something unread there) beside `NO ALT` and `UNUSED`. `GridComponent` reads the counts itself (not in the picker).
  - `Admin::PostsScreen::TableComponent.new(..., note_counts: {}, note_unread: Set.new)`: a "Notes" column; a row with open threads links `a[data-notes-count]` (`[data-unread]`) to `admin_post_path(post, notes: "open")`.
  - `Admin::TreeNodeComponent.new(..., note_counts: {}, note_unread: Set.new)`: `span[data-notes-marker]` (`[data-unread]`) beside the translation markers; `TreeComponent` reads the counts for the readable pages.

- [ ] **Step 1: Write the failing tests.** `test/integration/admin/note_counts_test.rb`:

```ruby
require "test_helper"

# The open-note count wherever a record is listed (notes spec §4.4): one
# grouped query per surface, whatever the number of threads.
class Admin::NoteCountsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @quiet = create_post(title: "Quiet")
    @asset = create_media_asset
    as(users(:two)) do
      [ @page, @block, @post, @asset ].each { |subject| Notes::Start.call(subject, body: "A note") }
      Notes::Resolve.call(Notes::Start.call(@post, body: "Done").record)
    end
    sign_in_as(users(:two))
  end

  def more_notes = as(users(:reader)) { 6.times { [ @block, @post ].each { |subject| Notes::Start.call(subject, body: "More") } } }

  def more_image_notes = as(users(:two)) { 6.times { Notes::Start.call(@asset, body: "More") } }

  test "the posts list has a Notes column: the open count as a link that opens the post with its drawer, nothing for a post without" do
    get "/cs-studio/posts"

    assert_select "table.admin-posts-table th", text: "Notes"
    assert_select "tr#post_#{@post.id} a[data-notes-count][href='/cs-studio/posts/#{@post.id}?notes=open'][aria-label='1 open note']", text: "1"
    assert_select "tr#post_#{@quiet.id} [data-notes-count]", count: 0
  end

  test "the page tree shows a page's open notes and its blocks' together" do
    get "/cs-studio/pages/#{@page.id}"

    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div [data-notes-marker][aria-label='2 open notes']", text: "✎2"
    assert_select "#tree-column li[data-page-id='#{root_page.id}'] > div [data-notes-marker]", count: 0
  end

  test "a media tile has a count chip, the picker's tile has none, and the panel embeds the image's notes" do
    get "/cs-studio/media", params: { selected: @asset.id, thread: 7 }

    assert_select "#media-asset-#{@asset.id} [data-notes-chip]", text: "1 NOTE"
    assert_select "#media-panel #media-notes turbo-frame#notes[loading=lazy][src='/cs-studio/notes/media/#{@asset.id}/threads/7?view=media']"
    get "/cs-studio/media", params: { selected: @asset.id }
    assert_select "#media-notes turbo-frame#notes[src='/cs-studio/notes/media/#{@asset.id}?view=media']"
    assert_select "#media-panel form #media-notes", count: 0

    get "/cs-studio/media", params: { picker: 1 }
    assert_select "[data-notes-chip]", count: 0
  end

  test "a note started in the media panel records where it was written" do
    post "/cs-studio/notes/media/#{@asset.id}/threads", params: { body: "Crop tighter", view: "media" }

    assert_redirected_to %r{/cs-studio/notes/media/#{@asset.id}/threads/\d+\?view=media\z}
    assert_equal "media", Notes::Thread.order(:id).last.origin_view
  end

  test "each list costs the same statements whatever the number of threads" do
    paths = [ "/cs-studio/posts", "/cs-studio/pages/#{@page.id}", "/cs-studio/media" ]
    paths.each { |path| get path }
    few = paths.map { |path| capture_sql { get path }.size }
    more_notes
    more_image_notes
    paths.each { |path| get path }

    assert_equal few, paths.map { |path| capture_sql { get path }.size }
  end
end
```

Add to `test/integration/trash_visibility_test.rb`, above the file's `private` line (a test written under it would not be run):

```ruby
  # Notes follow their record into the trash (notes spec D12, §4.4): hidden
  # with it, counted nowhere. The records are trashed AFTER their notes were
  # written, as in life: `Notes::Start` refuses a record that is already in
  # the trash (decision P6), so a note "on" the setup's trashed records would
  # never exist and this test would pass with nothing hidden.
  test "note counts in the posts list, the page tree and the media grid are for kept records only" do
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: nil) }
    as(users(:one)) do
      [ @kept_post, @gone_post, @kept_page, @gone_page, @kept_asset, @gone_asset ].each { |subject| assert Notes::Start.call(subject, body: "A note").ok? }
    end
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: Time.current) }
    assert_equal 6, Notes::Thread.count # the trashed records keep their threads
    sign_in_as users(:one)

    get admin_posts_path
    assert_select "tr#post_#{@kept_post.id} [data-notes-count]", text: "1"
    assert_select "[data-notes-count]", count: 1

    get admin_page_path(@kept_page)
    assert_select "#tree-column li[data-page-id='#{@kept_page.id}'] [data-notes-marker]", text: "✎1"
    assert_select "#tree-column [data-notes-marker]", count: 1

    get admin_media_path
    assert_select "#media-asset-#{@kept_asset.id} [data-notes-chip]"
    assert_select "[data-notes-chip]", count: 1

    get "/cs-studio/notes/media/#{@gone_asset.id}"
    assert_response :not_found
    get "/cs-studio/notes/post/#{@gone_post.id}"
    assert_response :not_found
  end
```

Append to `test/system/admin/media_library_test.rb` (with the file's own setup and its `click_tile` helper):

```ruby
  test "the panel takes a note on the image while its fields autosave beside it" do
    asset = create_media_asset
    visit "/cs-studio/media"
    await_admin_controllers
    click_tile(asset)

    assert_selector "#media-panel #media-notes #notes-list"
    find("#media-notes a[data-note-new-link]").click
    find("#media-notes #notes-new textarea[name=body]").send_keys("Crop the left edge")
    within("#media-notes #notes-new") { press "Add note" }

    assert_selector "#media-notes [data-note-thread]", text: "Crop the left edge"
    assert_equal [ asset, "media" ], Notes::Thread.last.then { |thread| [ thread.subject, thread.origin_view ] }
    assert_selector "#media-panel #media-title"
    assert_writes_settled
  end
```

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/integration/admin/note_counts_test.rb test/integration/trash_visibility_test.rb`

- [ ] **Step 3: The media panel.** `panel_component.rb`: add

```ruby
      # The image's notes (notes spec §4.4): the same frame the editors'
      # drawer shows, inline here -- this screen has no drawer. `view: "media"`
      # travels with every request of the frame, so a thread started here
      # records where it was written; `thread` (a link from the inbox) starts
      # the frame on that thread's view instead of the list.
      def notes_path
        options = { view: "media", **url_options }
        thread = helpers.params[:thread].to_s[/\A\d+\z/]
        thread ? helpers.admin_record_note_thread_path("media", asset.id, thread, **options) : helpers.admin_record_notes_path("media", asset.id, **options)
      end
```

`panel_component.html.erb`: after the "Used on" `<div>…</div>` and before `<% if can_delete? %>`:

```erb
  <%# Outside the panel's autosave form above: a note is no field of the image. %>
  <div id="media-notes">
    <h3 class="mb-2 font-semibold text-ink"><%= t(".notes") %></h3>
    <%= tag.turbo_frame id: "notes", src: notes_path, loading: "lazy" do %>
      <p class="text-sm text-meta"><%= t(".notes_loading") %></p>
    <% end %>
  </div>
```

- [ ] **Step 4: The media grid.** `tile_component.rb`: `def initialize(asset:, url: nil, unused:, selected: false, pick: false, locale: ::Locales.default, open_notes: 0)`, `@open_notes = open_notes`, `def open_notes = @open_notes.to_i`. `tile_component.html.erb`: after the `UNUSED` chip (a `tag.span`, so Step 7 can add to its `data:`):

```erb
      <% if open_notes.positive? %>
        <%= tag.span t(".notes", count: open_notes), data: { notes_chip: true },
              class: "rounded-cs border border-line-strong px-1 font-cs-mono text-[10px] text-ink" %>
      <% end %>
```

`grid_component.rb`:

```ruby
      # Open notes per image on this page of the grid, one grouped query like
      # `used_ids` (notes spec §4.4). Not in the picker: choosing an image is
      # not the place to read about it.
      def note_counts = @note_counts ||= pick? ? {} : ::Notes::Counts.by_container("Media::Asset", assets.map(&:id))
```

and its template passes `open_notes: note_counts.fetch(asset.id, 0)` to `TileComponent.new`. In `Admin::MediaController#grid_streams`, the tile gets `open_notes: Notes::Counts.by_container("Media::Asset", [ asset.id ]).fetch(asset.id, 0)`.

- [ ] **Step 5: The posts list.** `Admin::PostsController#index`: after `@translation_states = …`, `@note_counts = Notes::Counts.by_container("Post", @posts.map(&:id))` with a comment (one grouped query for the page of rows, which the read scope already narrowed). `app/views/admin/posts/index.html.erb`: pass `note_counts: @note_counts` to `TableComponent.new`. `table_component.rb`: `note_counts: {}` in `initialize`, `@note_counts = note_counts`, `attr_reader :note_counts`, and `def open_notes(post) = note_counts.fetch(post.id, 0)`. `table_component.html.erb`: `min-w-[820px]` becomes `min-w-[880px]`; after the Translations `<th>`: `<th scope="col" class="py-2 pr-4"><%= t(".notes") %></th>`; after the Translations `<td>`:

```erb
          <td class="py-2.5 pr-4">
            <% if open_notes(post).positive? %>
              <%= link_to open_notes(post), editor_path(post, notes: "open"), class: "font-cs-mono text-label text-ink hover:underline",
                    aria: { label: t(".open_notes", count: open_notes(post)) }, data: { notes_count: true } %>
            <% end %>
          </td>
```

- [ ] **Step 6: The page tree.** `tree_component.rb`: add `:note_counts` to the `attr_reader`, `@note_counts = {}` in `initialize` before `@root = …`, and in `load_visible` after the translation counts:

```ruby
      # Open notes per page, its blocks' included (a thread's container is the
      # page), read once for the whole tree and only for the pages the viewer
      # may read -- a context-only ancestor shows none (notes spec §4.4).
      @note_counts = Notes::Counts.by_container("Page", pages.reject { |page| @context_only_ids.include?(page.id) }.map(&:id))
```

Pass `note_counts: note_counts` to `TreeNodeComponent.new` in `tree_component.html.erb` and in the recursive render in `tree_node_component.html.erb`. `tree_node_component.rb`: `note_counts: {}` in `initialize`, stored, in the `attr_reader`, and `def open_notes = note_counts.fetch(page.id, 0)`. `tree_node_component.html.erb`, after the missing-translations marker:

```erb
      <% if open_notes.positive? %>
        <%= tag.span "✎#{open_notes}", data: { notes_marker: true }, role: "img", title: t(".open_notes", count: open_notes),
              aria: { label: t(".open_notes", count: open_notes) }, class: "shrink-0 font-cs-mono text-label text-ink" %>
      <% end %>
```

(`Admin::TreeNodeComponent` is an `Admin::AdminComponent` (checked: `class TreeNodeComponent < AdminComponent`), so `t(".open_notes")` reads `admin.components.tree_node.open_notes`. The "✎" before the number is the tree's own marker style, as "○" is for a missing translation.)

- [ ] **Step 7: "Unread for you" turns a count accent** (spec §4.5, handoff "Where the spec wins"). One query beside each surface's count, `Notes::Counts.unread_among(type, ids, Current.user)`, over the same ids:
  - Posts list: `@note_unread = Notes::Counts.unread_among("Post", @posts.map(&:id), Current.user)` in the controller, `note_unread: @note_unread` to `TableComponent.new` (`note_unread: Set.new` in `initialize`, an `attr_reader`), and `unread: (true if note_unread.include?(post.id))` in the link's `data:`.
  - Page tree: `@note_unread = Notes::Counts.unread_among("Page", <the same ids>, Current.user)` in `TreeComponent#load_visible`, handed down as `note_unread:` exactly like `note_counts:`, and `unread: (true if note_unread.include?(page.id))` in the marker's `data:`.
  - Media grid: `def note_unread = @note_unread ||= pick? ? Set.new : ::Notes::Counts.unread_among("Media::Asset", assets.map(&:id), Current.user)` in `GridComponent`, `notes_unread: note_unread.include?(asset.id)` to `TileComponent.new` (`notes_unread: false` in `initialize`, `@notes_unread = notes_unread`), and `unread: (true if @notes_unread)` in the chip's `data:`. The tile `Admin::MediaController#grid_streams` draws after an autosave gets it too, or the chip would lose its accent on the first keystroke in the panel: `notes_unread: Notes::Counts.unread_among("Media::Asset", [ asset.id ], Current.user).include?(asset.id)`.

  Each count's classes take the handoff's accent state from `data-unread` (`data-[unread]:bg-accent-tint data-[unread]:text-accent`). Add to `note_counts_test.rb`:

```ruby
  test "a count is accent for the person its thread is addressed to, and neutral for everyone else" do
    as(users(:one)) { [ @post, @page, @asset ].each { |subject| Notes::Start.call(subject, body: "For @[#{users(:two).id}]") } }

    get "/cs-studio/posts"
    assert_select "tr#post_#{@post.id} a[data-notes-count][data-unread]"
    get "/cs-studio/pages/#{@page.id}"
    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div [data-notes-marker][data-unread]"
    get "/cs-studio/media"
    assert_select "#media-asset-#{@asset.id} [data-notes-chip][data-unread]"

    sign_in_as(users(:one))
    get "/cs-studio/posts"
    assert_select "[data-notes-count][data-unread]", count: 0
  end
```

- [ ] **Step 8: The strings.** Under `en.admin.components`:

```yaml
      media_library:
        panel:
          notes: "Notes"
          notes_loading: "Loading notes…"
        tile:
          notes:
            one: "%{count} NOTE"
            other: "%{count} NOTES"
      posts_screen:
        table:
          notes: "Notes"
          open_notes:
            one: "%{count} open note"
            other: "%{count} open notes"
      tree_node:
        open_notes:
          one: "%{count} open note"
          other: "%{count} open notes"
```

- [ ] **Step 9: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/integration test/components test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/media_library_test.rb test/system/admin/posts_list_test.rb test/system/admin/tree_test.rb
```

No existing test pins an absolute statement count for these three screens (checked: `posts_list_test.rb` "the list costs the same number of queries for 5 posts as for 40", `media_test.rb`'s three `count_queries` tests, `access_control_test.rb` "rendering the tree as a branch editor costs the same queries however many pages it shows" and `new_record_dialogs_test.rb` each compare two runs of the same request over non-empty lists), so none needs a number raised: each surface costs exactly two statements more on both sides (the count and the unread read beside it). If one of them fails, a count is being read per row; fix the code, not the test.

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat: notes in the media panel, and the open count in the posts list, the page tree and the media grid" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 10: The mind graph — a count badge on a post's node, its threads in the card

**Spec:** §4.4 (Mind graph). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/cs-studio-shell-and-dashboard.md` ("Mind graph": the page is a frame with no data in it, the card is built with `textContent` and `href` only, `reset()` takes back what the script wrote), `app/javascript/mind_graph/card.js`, `renderer.js`, `theme.js`, `app/queries/post_graph/builder.rb`, `test/system/admin/mind_graph_test.rb` (how a test selects a node).

**Files:**
- Create: `app/javascript/mind_graph/card_notes.js`
- Modify: `app/queries/post_graph/builder.rb`, `config/routes.rb`, `app/controllers/admin/note_threads_controller.rb` (`index`, JSON for `create`), `app/javascript/mind_graph/card.js`, `renderer.js`, `theme.js`, `app.js`, `app/views/admin/mind_graph/show.html.erb`, `app/components/admin/mind_graph_legend_component.html.erb`, `app/assets/tailwind/content-spiel.tailwind.css` (the legend's swatch, beside `.mg-key-pin`), `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/queries/post_graph/global_test.rb`, `test/integration/admin/mind_graph_data_test.rb`, `test/integration/admin/note_writes_test.rb`, `test/integration/trash_visibility_test.rb`, `test/system/admin/mind_graph_test.rb`

**Interfaces:**
- Consumes: `Notes::Counts.by_container`, `Notes::Listing`, `Notes::Start` through `note_threads#create`.
- Produces:
  - Every post node of the graph's JSON has `open_notes` (Integer), read by `PostGraph::Builder` in one grouped query.
  - `GET admin_record_note_threads_path(type, id)` (JSON) → `{ "open": Integer, "threads": [ { "id", "text" (the first message, mentions as "@Name", at most 140 characters), "author" (String or null for a deleted user), "replies": Integer, "pinned": Boolean, "unread": Boolean (the viewer has an unread delivery on it) } ] }`.
  - `POST admin_record_note_threads_path(type, id)` with `Accept: application/json` → `201 { "id" }` or `403`/`422 { "errors": [...] }`.
  - `cardNotes(node, { text, url, postUrl, onChange }) -> HTMLElement` (`section[data-mind-graph-card-notes]`, the card's fifth child, before Close; a row is `li[data-note-row]`, `[data-unread]` with an accent dot when unread for the viewer; three rows, then `a[data-note-more]`); `createCard(..., { ..., onChange })`; `urls.postNotes` from `data-post-notes-url`.
  - `theme.line`, `theme.countFont`.

- [ ] **Step 1: Write the failing tests.** Append to `test/queries/post_graph/global_test.rb` (with the file's own `graph` and `relate` helpers):

```ruby
  test "a node carries its post's open notes, and the count costs one statement whatever the number of threads" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    relate(a, b)
    as(users(:two)) do
      2.times { Notes::Start.call(a, body: "A note") }
      Notes::Resolve.call(Notes::Start.call(b, body: "Done").record)
    end

    nodes = graph[:nodes].index_by { |node| node[:id] }
    assert_equal [ 2, 0 ], [ nodes[a.id][:open_notes], nodes[b.id][:open_notes] ]

    few = capture_sql { graph }.size
    as(users(:two)) { 7.times { Notes::Start.call(b, body: "More") } }
    assert_equal few, capture_sql { graph }.size
  end
```

Append to `test/integration/admin/note_writes_test.rb`:

```ruby
  test "a record's open threads as JSON for the mind graph's card: first message, author, replies, no markup" do
    users(:two).update!(name: "Dana")
    post_record = create_post(title: "Hello")
    thread = as(users(:two)) { Notes::Start.call(post_record, body: "Ask @[#{users(:reader).id}] <b>now</b> " + ("x" * 200), origin_view: "mind_graph") }.record
    as(users(:reader)) { Notes::Reply.call(thread, body: "On it") }
    sign_in_as(users(:reader))

    get "/cs-studio/notes/post/#{post_record.id}/threads"

    body = response.parsed_body
    assert_equal 1, body["open"]
    row = body["threads"].first
    assert_equal [ thread.id, "Dana", 1, false ], row.values_at("id", "author", "replies", "pinned")
    assert_equal true, row["unread"] # the first message mentions the reader, and reading a list marks nothing read (P10)
    assert row["text"].start_with?("Ask @reader@example.com <b>now</b> x")
    assert_operator row["text"].length, :<=, 140
  end

  test "a note is started over JSON, and a refusal is JSON too" do
    post_record = create_post(title: "Hello")
    sign_in_as(users(:reader))

    post "/cs-studio/notes/post/#{post_record.id}/threads", params: { body: "From the graph", view: "mind_graph" }, headers: { "Accept" => "application/json" }
    assert_response :created
    assert_equal [ "mind_graph", post_record ], Notes::Thread.find(response.parsed_body["id"]).then { |thread| [ thread.origin_view, thread.subject ] }

    post "/cs-studio/notes/post/#{post_record.id}/threads", params: { body: " " }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal [ "Write something first." ], response.parsed_body["errors"]
  end
```

Append to `test/integration/admin/mind_graph_data_test.rb` an assertion, in the test that reads the nodes of a small graph, that every node has an `open_notes` key and that a post with one open thread reads `1`. In `test/integration/trash_visibility_test.rb`, in "the page tree, posts list, link targets and mind graph hide trashed pages and posts" (the one that asserts the trashed post is no node), give the trashed post a thread before the first request. `Notes::Start` refuses a record that is already in the trash (decision P6), so the thread is written first and the post trashed again after it:

```ruby
    @gone_post.update!(trashed_at: nil)
    as(users(:one)) { assert Notes::Start.call(@gone_post, body: "A note").ok? }
    @gone_post.update!(trashed_at: Time.current)
```

and after `get "/cs-studio/mind_graph/data"`: `assert(response.parsed_body["nodes"].none? { |node| node["id"] == @gone_post.id })`, then `get "/cs-studio/notes/post/#{@gone_post.id}/threads"` with `assert_response :not_found`, and `get "/cs-studio/mind_graph/data", params: { post: @kept_post.id }` already there gains `assert_equal [ 0 ], response.parsed_body["nodes"].map { |node| node["open_notes"] }` (the kept post has no thread; the trashed one's is counted nowhere).

Add to `test/system/admin/mind_graph_test.rb`, above its `private` helpers, with the file's own helpers as they are today (checked: `await_graph`, `click_node(id)`, `screen_position(id)`, `pixel_at(x, y)`, `graph`, the constants `GRAPH`, `CANVAS`, `LIST`; relations are made with `PostRelation.create!`, the screen is opened with `visit admin_mind_graph_path`; the file is signed in as `users(:one)`; there is no `relate`, `open_graph` or `select_in_list`, and `element.mindGraph` answers `screenPosition`, `labelBox` and `draws` only, no node data):

```ruby
  test "a post with open notes shows them in its card, and a note is started from the card" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    as(users(:two)) { Notes::Start.call(a, body: "Check the dates, @[#{users(:one).id}]") }
    visit admin_mind_graph_path
    await_graph
    click_node(a.id)

    assert_selector "[data-mind-graph-card] [data-mind-graph-card-notes] li[data-note-row][data-unread]", text: "Check the dates"
    # The heading is in the small upper-case label style: matched whatever the case, as the card's counts are.
    assert_selector "[data-mind-graph-card-notes] h3", text: /1 open note/i
    within("[data-mind-graph-card-notes]") do
      find("textarea").send_keys("And the prices")
      press "Add note"
    end

    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 2
    assert_selector "[data-mind-graph-card-notes] h3", text: /2 open notes/i
    assert_equal [ "mind_graph", a ], Notes::Thread.order(:id).last.then { |thread| [ thread.origin_view, thread.subject ] }
  end

  test "three notes in the card, then a link to the rest; a post without notes has only the field" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)
    as(users(:two)) { 5.times { |index| Notes::Start.call(a, body: "Note #{index}") } }
    visit admin_mind_graph_path
    await_graph

    click_node(a.id)
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 3
    assert_selector "[data-mind-graph-card-notes] a[data-note-more][href$='/posts/#{a.id}?notes=open']", text: "+2 more"

    escape_on_canvas # the open card may stand over the other node
    click_node(b.id)
    assert_selector "[data-mind-graph-card-notes] textarea"
    assert_no_selector "[data-mind-graph-card-notes] li"
    assert_no_selector "[data-mind-graph-card-notes] h3" # zero threads: only the field (handoff)
  end

  # The badge is canvas pixels: the corner opposite the pin's holds something
  # else once the post has an open note.
  test "a post with an open note carries a badge on its top-left corner" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    bare = notes_badge_pixel(a)

    as(users(:two)) { Notes::Start.call(a, body: "Check the dates") }
    visit admin_mind_graph_path
    await_graph

    assert_not_equal bare, notes_badge_pixel(a), "no notes badge at the node's top-left"
    assert_selector "[data-legend='notes']", text: "Open notes"
  end
```

and beside `pin_pixel`, among the helpers:

```ruby
  # The canvas's colour where a node's notes badge is: up and to the LEFT of
  # the centre of a 7 px dot (the pin's corner is up and to the right).
  def notes_badge_pixel(post)
    point = screen_position(post.id)
    pixel_at(point["x"] - 5.04, point["y"] - 5.04)
  end
```

(Each read asks the node's place afresh, so the two visits need not agree on it; if `notes_badge_pixel` reads the same colour both times because the badge's surface fill equals the canvas's own background at that point, sample one pixel further up and left, on the badge's line, and say so in the task report.)

The card's children are pinned by the existing test "the card reads top to bottom: kind and status, the title, the two counts, then its actions as buttons" (`assert_equal %w[DIV H2 P DIV BUTTON], ...`): a post's card gains the notes section before Close, so that line becomes `%w[DIV H2 P DIV SECTION BUTTON]` and the test's name and comment gain "then its notes". Its `div:nth-child(4)` assertions stay as they are.

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/queries/post_graph test/integration/admin/note_writes_test.rb test/integration/admin/mind_graph_data_test.rb`

- [ ] **Step 3: The node's count.** In `PostGraph::Builder#nodes`, before the `Post.where` line: `notes = Notes::Counts.by_container("Post", post_ids.to_a)` with a comment (the posts' open threads, one grouped query; the ids were narrowed by the read scope by whoever built them, so no count is for a post the viewer can't read), and in the node hash `open_notes: notes.fetch(post.id, 0)`. Update the node shape in the class comment. No test in `test/queries/post_graph/` pins an absolute statement count (checked: `global_test.rb` and `local_test.rb` compare two runs), so none needs a number raised.

- [ ] **Step 4: The JSON.** In `config/routes.rb`, in the notes scope, above the `post "threads"` line: `get "threads", to: "note_threads#index", defaults: { format: :json }` (it shares the path and the helper `admin_record_note_threads_path`). In `Admin::NoteThreadsController`:

```ruby
    EXCERPT = 140

    # The record's open threads as data, for the mind graph's card (notes
    # spec §4.4), which is built in the browser with `textContent` only: text
    # and numbers, no markup. A mention reads as "@Name".
    def index
      listing = Notes::Listing.new(@container, viewer: Current.user)
      threads = listing.pinned + listing.groups.flat_map(&:threads)
      render json: {
        open: listing.open_count,
        threads: threads.map do |thread|
          first = thread.messages.first
          { id: thread.id, text: Notes::Mentions.display(first.body, listing.users).first.truncate(EXCERPT),
            author: listing.users[first.author_id]&.display_name, replies: thread.messages.size - 1, pinned: thread.pinned,
            # What turns the row's dot accent in the card (spec §4.5): one
            # query for the whole listing (`Notes::Listing#unread?`).
            unread: listing.unread?(thread, Current.user) }
        end
      }
    end
```

and in `create`, answer a JSON client in kind: after `result = Notes::Start.call(...)`,

```ruby
      if request.format.json?
        return render(json: { id: result.record.id }, status: :created) if result.ok?

        return render(json: { errors: result.errors }, status: failure_status(result))
      end
```

- [ ] **Step 5: The badge.** No ring: on this canvas a ring means "selected" and a corner dot means "pinned" (spec §4.4). A post with open notes carries a small mono count badge on its top-LEFT corner (the pin is top-right), neutral like every count (§4.5).

`app/javascript/mind_graph/theme.js`: add `line: "--cs-line-strong"` to `TOKENS` and, after `theme.strongFont`, the badge's font, read from the mono token so the canvas and the page agree:

```js
  // The notes count on a node: the small mono label style.
  theme.countFont = `10px ${read("--cs-mono") || style.fontFamily}`
```

(`--cs-mono` is the property `app/assets/tailwind/content-spiel.css` defines for the mono face, and `read` is the function `readTheme` already has; 10px is the handoff's size for this badge, which does not scale with zoom.) `renderer.js`: raise `NODE_MARGIN` to `11` (its comment: a node's rings and its notes badge), add

```js
// A post with open notes (notes spec §4.4): the count in a small badge on the
// mark's top-left corner. Half its height, and how far it reaches sideways
// per character.
const NOTES_BADGE = 7
const NOTES_BADGE_PAD = 3
```

in the node loop, after the `drawPin` line: `if (nodes[index].kind !== "tag" && (nodes[index].open_notes ?? 0) > 0) drawNotes(context, theme, nodes[index], x(index), y(index), radii[index])`, and the function:

```js
// A neutral pill, like the count badges of the lists: surface, a line, ink.
// Never the only cue -- the list and the card say it in words. More than
// ninety-nine reads "99+".
function drawNotes(context, theme, node, x, y, radius) {
  const label = node.open_notes > 99 ? "99+" : String(node.open_notes)
  const offset = radius * 0.72
  const half = Math.max(NOTES_BADGE, NOTES_BADGE_PAD * label.length + 2)
  context.save()
  context.setLineDash([])
  context.beginPath()
  context.roundRect(x - offset - half, y - offset - NOTES_BADGE, half * 2, NOTES_BADGE * 2, NOTES_BADGE)
  context.fillStyle = theme.surface
  context.fill()
  context.strokeStyle = theme.line
  context.lineWidth = 1
  context.stroke()
  context.font = theme.countFont
  context.textAlign = "center"
  context.textBaseline = "middle"
  context.fillStyle = theme.ink
  context.fillText(label, x - offset, y - offset + 0.5)
  context.restore()
}
```

In `mind_graph_legend_component.html.erb`, after the `pinned` item, an item `data-legend="notes"` with an SVG in the same style (the node's circle and a small rounded rectangle `mg-key-notes` on its top-left corner) and `<%= t(".notes") %>`; in `content-spiel.tailwind.css` beside `.mg-key-pin`: `.mg-key-notes { fill: var(--cs-surface); stroke: var(--cs-line-strong); stroke-width: 1; }`.

- [ ] **Step 6: The card.** `app/javascript/mind_graph/card_notes.js`:

```js
// A post's open notes in the selection card (notes spec §4.4): each thread's
// first message, who wrote it and how many replies it has, a link into the
// post's editor with the drawer open at that thread, and a field to start a
// note without leaving the graph.
//
// Read as JSON from the notes endpoint scoped to that post (`url`), so what a
// viewer sees here is what they may read; written with `textContent` and
// `href` only, like the rest of the card -- a note's text is a person's. A
// note is started with a form post to the same URL, answered as JSON.
// `onChange` tells the card its height changed and the node's count moved.
//
// `cardNotes(node, { text, url, postUrl, onChange })` answers the section.
const LABEL = "m-0 font-cs-mono text-label uppercase tracking-mono text-meta"
// Three rows, then "+N more" (handoff, "Node card thread list").
const ROWS = 3

function element(tag, className, content) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (content != null) node.textContent = content
  return node
}

export function cardNotes(node, { text, url, postUrl, onChange }) {
  const section = element("section", "mt-1 flex flex-col gap-1.5 border-t border-line pt-2")
  section.dataset.mindGraphCardNotes = ""
  const heading = element("h3", LABEL)
  const list = element("ul", "m-0 flex list-none flex-col gap-1.5 p-0")
  const status = element("p", "m-0 text-sm text-danger-ink")
  status.setAttribute("role", "status")
  status.hidden = true

  const form = element("form", "flex flex-col items-start gap-1")
  const field = element("textarea", "block w-full rounded-cs border border-line-strong bg-surface px-2 py-1 text-sm text-ink focus:outline-2 focus:outline-accent")
  field.name = "body"
  field.rows = 2
  field.maxLength = 4000
  field.required = true
  field.setAttribute("aria-label", text.t("mind_graph.script.card.notes.label"))
  field.placeholder = text.t("mind_graph.script.card.notes.label")
  const submit = element("button", "cursor-pointer rounded-cs border border-line-strong bg-surface px-2 py-0.5 text-sm text-ink hover:bg-sunken", text.t("mind_graph.script.card.notes.add"))
  submit.type = "submit"
  form.append(field, submit)

  // Zero threads: only the field, no heading (handoff, "Node card thread list").
  const title = (count) => {
    heading.textContent = text.t("mind_graph.script.card.notes.title", { count })
    heading.hidden = count === 0
  }

  function row(thread) {
    const item = element("li", "relative flex flex-col pr-3")
    item.dataset.noteRow = ""
    // Unread for the viewer (spec §4.5): ink instead of dim, and the accent
    // dot, the one meaning accent has in notes.
    if (thread.unread) {
      item.dataset.unread = ""
      const dot = element("span", "absolute right-0 top-1.5 size-[7px] rounded-full bg-accent")
      dot.setAttribute("aria-hidden", "true")
      item.append(dot)
    }
    const link = element("a", `break-words text-sm hover:underline ${thread.unread ? "text-ink" : "text-dim"}`, thread.text)
    const target = new URL(postUrl, window.location.origin)
    target.searchParams.set("notes", "open")
    target.searchParams.set("thread", thread.id)
    link.href = target.pathname + target.search
    const who = thread.author ?? text.t("mind_graph.script.card.notes.deleted_user")
    const facts = thread.replies > 0 ? `${who} · ${text.t("mind_graph.script.card.notes.replies", { count: thread.replies })}` : who
    item.append(link, element("span", "text-[12px] text-meta", facts))
    return item
  }

  function fail(message) {
    status.textContent = message
    status.hidden = false
    onChange()
  }

  async function load() {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      // Three rows, then "+N more", which opens the post's notes (handoff,
      // "Node card thread list").
      list.replaceChildren(...data.threads.slice(0, ROWS).map(row))
      // `open` is exact; `threads` is the listing's first page.
      const rest = data.open - Math.min(ROWS, data.threads.length)
      if (rest > 0) {
        const more = element("li")
        const link = element("a", "text-[12px] text-accent hover:underline", text.t("mind_graph.script.card.notes.more", { count: rest }))
        link.dataset.noteMore = ""
        const target = new URL(postUrl, window.location.origin)
        target.searchParams.set("notes", "open")
        link.href = target.pathname + target.search
        more.append(link)
        list.append(more)
      }
      node.open_notes = data.open
      title(data.open)
      status.hidden = true
      onChange()
    } catch {
      fail(text.t("mind_graph.script.card.notes.failed"))
    }
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault()
    submit.disabled = true
    try {
      const body = new FormData(form)
      body.set("view", "mind_graph")
      const response = await fetch(url, {
        method: "POST", body,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
      })
      const answer = await response.json().catch(() => ({}))
      if (response.ok) {
        field.value = ""
        await load()
      } else {
        fail((answer.errors || [ text.t("mind_graph.script.card.notes.failed") ]).join(" "))
      }
    } catch {
      fail(text.t("mind_graph.script.card.notes.failed"))
    } finally {
      submit.disabled = false
    }
  })

  title(node.open_notes ?? 0)
  section.append(heading, list, status, form)
  if ((node.open_notes ?? 0) > 0) load()
  return section
}
```

In `card.js`: `import { cardNotes } from "mind_graph/card_notes"`; `createCard(container, { text, urls, typeLabels, dotClasses, buttonClasses, onClose, onPin, onChange })`; at the end of the array `post(node)` returns, after `actions(...)`, add `cardNotes(node, { text, url: fill(urls.postNotes, "__ID__", node.id), postUrl: node.url, onChange })`; extend the header comment (the fifth part of a post's card, and that `urls` has a fourth template). In `app.js`: `urls` gains `postNotes: element.dataset.postNotesUrl`, and `createCard` gets `onChange: () => { measureCard(); requestDraw() }` with a comment (the notes arrive after the card was measured, and a note started here changes the node's badge). In `show.html.erb`: `data-post-notes-url="<%= admin_record_note_threads_path("post", 0, **admin_url_options).sub("/0/", "/__ID__/") %>"` (why not `"__ID__"` directly: the paragraph below) and, in the `messages_data(...)` list, the literals `"mind_graph.script.card.notes.title", "mind_graph.script.card.notes.label", "mind_graph.script.card.notes.add", "mind_graph.script.card.notes.replies", "mind_graph.script.card.notes.more", "mind_graph.script.card.notes.deleted_user", "mind_graph.script.card.notes.failed"`; extend the comment above the element by one sentence.

The route constraint `container_id: /\d+/` refuses `__ID__` when the helper builds the template (`ActionController::UrlGenerationError`), which is why the attribute above builds the path for id 0 and swaps the segment; say so in the comment above the element. `fill` (`card.js`) URL-encodes the id it puts in.

- [ ] **Step 7: The strings.** In `config/locales/admin/notes.en.yml` under `en.admin`:

```yaml
    mind_graph:
      script:
        card:
          notes:
            title:
              one: "%{count} open note"
              other: "%{count} open notes"
            label: "Write a note on this post"
            add: "Add note"
            replies:
              one: "%{count} reply"
              other: "%{count} replies"
            more:
              one: "+%{count} more"
              other: "+%{count} more"
            deleted_user: "a deleted user"
            failed: "The notes couldn't be loaded or saved. Try again."
    components:
      mind_graph_legend:
        notes: "Open notes"
```

(The heading is drawn in the small uppercase label style, which is why the system test matches it whatever the case: `/2 open notes/i`.) Add `app/javascript/mind_graph/card_notes.js` to `CONVERTED`.

- [ ] **Step 8: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/queries/post_graph test/integration test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/mind_graph_test.rb test/system/admin/mind_graph_modules_test.rb
```

Then look at the graph in a browser, in both themes, with a post that has one note and one that has a hundred and twenty: the badge is readable on every node size, does not hide the pin's dot, and is not cut off at the canvas's edge. Say in the task report what was looked at.

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: the mind graph badges a post with its open notes and shows and starts them in its card" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 11: The inbox — "Notes for you", "Open threads", the full list and the sidebar's count

**Spec:** §5, §3.3 (when a delivery is read; a person who loses the right), §8 (trash visibility, constant queries). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` (follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/cs-studio-shell-and-dashboard.md` (the dashboard's cards, the sidebar), `app/queries/dashboard/activity.rb` (a query that returns rows of data and a route name), `app/components/admin/dashboard_screen/card_component.{rb,html.erb}`, `app/components/admin/shell/sidebar_component.{rb,html.erb}`.

**Files:**
- Create: `app/queries/dashboard/notes_for_you.rb`, `app/queries/dashboard/open_threads.rb`, `app/controllers/admin/note_inbox_controller.rb`, `app/views/admin/note_inbox/index.html.erb`, `_card.html.erb`, `_open_threads.html.erb`, `app/components/admin/notes_screen/inbox_row_component.{rb,html.erb}`, `open_thread_row_component.{rb,html.erb}`
- Modify: `app/models/notes/delivery.rb` (a scope), `config/routes.rb`, `app/controllers/admin/base_controller.rb` (`notes_badge_count`), `app/components/admin/shell/sidebar_component.{rb,html.erb}`, `app/views/layouts/admin.html.erb`, `app/views/admin/dashboard/show.html.erb`, `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/queries/dashboard/notes_for_you_test.rb`, `test/queries/dashboard/open_threads_test.rb`, `test/integration/admin/note_inbox_test.rb` (new), `test/integration/trash_visibility_test.rb`, `test/components/admin/shell/sidebar_component_test.rb` (or wherever the sidebar is tested: `grep -rl SidebarComponent test`)

**Interfaces:**
- Consumes: `Notes.readable_threads`, `Notes::Delivery`, `Notes::MarkRead`, `Notes::Mentions.display`, `Audit::Sentence.route_for(record) -> Route(name, args, params)`, `?notes=open&thread=` on an editor, `?selected=&thread=` on Media.
- Produces:
  - `Notes::Delivery.inbox_order` (unread first, then newest).
  - `Dashboard::NotesForYou.new(actor:, channel: Current.channel)`: `#rows(limit: 5, offset: 0) -> [Row]`, `#total`, `#unread_count`, `#find(delivery_id) -> Row | nil`. `Row = Data.define(:id, :reason, :by, :by_id, :excerpt, :kind, :title, :block, :route, :unread, :at, :thread_id)`: `by` is the User who did it (nil with `by_id` set for a deleted one, both nil when nobody is named), `kind` is `"page" | "post" | "media"`, `block` the ContentBlock the thread is on or nil, `route` an `Audit::Sentence::Route` to the record with its notes open at the thread.
  - `Dashboard::OpenThreads.new(actor:, channel: Current.channel, limit: 5)`: `#rows -> [Row(:record, :kind, :title, :count, :at, :route)]`.
  - Routes: `admin_notes_path` (GET, `?page=`) → `note_inbox#index`; `admin_read_notes_path` (POST) → `note_inbox#read`; `admin_notes_card_path` (GET) → `note_inbox#card`; `admin_open_note_threads_path` (GET) → `note_inbox#open_threads`; `admin_unread_notes_path` (GET, JSON `{ "unread": n }`) → `note_inbox#unread`.
  - DOM: `turbo-frame#notes-for-you` > `section[aria-labelledby=dashboard-notes-for-you]` > rows `[data-delivery=<id>]` (`[data-unread]` while unread); `turbo-frame#notes-open-threads` > `section[aria-labelledby=dashboard-open-threads]`; `#sidebar-badge-dashboard` (always present, `hidden` at zero), `#sidebar-badge-trash` (present only above zero, as today).
  - `Admin::Shell::SidebarComponent.new(modules:, user:, current_path:, url_options:, badges: {})`, `badges` keyed by the entry's `:path`; `Admin::BaseController#notes_badge_count` (helper).

- [ ] **Step 1: Write the failing tests.** `test/queries/dashboard/notes_for_you_test.rb`:

```ruby
require "test_helper"

class Dashboard::NotesForYouTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    users(:two).update!(name: "Dana")
    @me = users(:reader)
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:read_only), permission: "media.upload") { |grant| grant.scope = {} }
  end

  def inbox(user = @me) = Dashboard::NotesForYou.new(actor: user, channel: :admin)

  def mention(subject, body = "Look, @[#{@me.id}]") = as(users(:two)) { Notes::Start.call(subject, body: body) }.record

  test "a row says who did what, the note's first words and where, and leads to the record with its notes open at the thread" do
    thread = mention(@block, "Is @[#{@me.id}] sure about #{"this " * 40}")

    row = inbox.rows.first

    assert_equal [ "mention", users(:two), "page", "Pricing", @block, true, thread.id ], [ row.reason, row.by, row.kind, row.title, row.block, row.unread, row.thread_id ]
    assert row.excerpt.start_with?("Is @reader@example.com sure about this")
    assert_operator row.excerpt.length, :<=, 140
    assert_equal [ :admin_page_path, [ @page.id ], { notes: "open", thread: thread.id } ], [ row.route.name, row.route.args, row.route.params ]
  end

  test "a post and an image lead to their own screens" do
    on_post = mention(@post)
    on_asset = mention(@asset)

    routes = inbox.rows.index_by(&:thread_id).transform_values { |row| [ row.kind, row.route.name, row.route.params ] }

    assert_equal [ "post", :admin_post_path, { notes: "open", thread: on_post.id } ], routes[on_post.id]
    assert_equal [ "media", :admin_media_path, { selected: @asset.id, thread: on_asset.id } ], routes[on_asset.id]
  end

  test "unread first, then newest; the count is the unread ones" do
    old = mention(@page)
    read = travel_to(1.minute.from_now) { mention(@post) }
    newest = travel_to(2.minutes.from_now) { mention(@asset) }
    Notes::Delivery.where(user: @me, thread: read).update_all(read_at: Time.current) # version: none (a test's own setup)

    assert_equal [ newest.id, old.id, read.id ], inbox.rows.map(&:thread_id)
    assert_equal [ 2, 3 ], [ inbox.unread_count, inbox.total ]
    assert_equal [ old.id ], inbox.rows(limit: 1, offset: 1).map(&:thread_id)
  end

  test "a resolve names who resolved, a reply who replied" do
    thread = mention(@page)
    as(users(:one)) { Notes::Reply.call(thread, body: "On it") }
    assert_equal [ "reply", users(:one) ], inbox.rows.first.then { |row| [ row.reason, row.by ] }

    as(users(:two)) { Notes::Resolve.call(thread) }
    assert_equal [ "resolved", users(:two) ], inbox.rows.find { |row| row.reason == "resolved" }.then { |row| [ row.reason, row.by ] }
  end

  test "a delivery on a record I can no longer read, or that is in the trash, is not shown and not counted" do
    mention(@page)
    mention(@post)
    @post.update!(trashed_at: Time.current)
    assert_equal [ [ "page" ], 1 ], [ inbox.rows.map(&:kind), inbox.unread_count ]

    AccessControl::Membership.where(user: @me).destroy_all
    assert_equal [ [], 0, 0 ], [ inbox.rows, inbox.unread_count, inbox.total ]
    assert_equal 2, Notes::Delivery.where(user: @me).count # the rows stay
  end

  test "find answers one of my deliveries and nobody else's" do
    mention(@page)
    mine = Notes::Delivery.find_by!(user: @me)

    assert_equal mine.id, inbox.find(mine.id).id
    assert_nil inbox(users(:author)).find(mine.id)
    assert_nil inbox.find(0)
  end

  test "it costs the same statements for two rows as for five" do
    2.times { mention(@block) }
    few = capture_sql { inbox.rows; inbox.unread_count }.size
    [ @page, @post, @asset ].each { |subject| mention(subject) }

    assert_equal few + 2, capture_sql { inbox.rows; inbox.unread_count }.size # the posts and the images: one read per kind of record on the page
  end
end
```

`test/queries/dashboard/open_threads_test.rb`:

```ruby
require "test_helper"

class Dashboard::OpenThreadsTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @quiet = create_post(title: "Quiet")
  end

  def note(subject) = as(users(:two)) { Notes::Start.call(subject, body: "A note") }.record

  test "records with open threads, the most recently active first, with their counts" do
    note(@page)
    travel_to(1.minute.from_now) { note(@post) }
    travel_to(2.minutes.from_now) { note(@block) }
    as(users(:two)) { Notes::Resolve.call(note(@quiet)) }

    rows = Dashboard::OpenThreads.new(actor: users(:reader), channel: :admin).rows

    assert_equal [ [ @page, "page", "Pricing", 2 ], [ @post, "post", "Hello", 1 ] ], rows.map { |row| [ row.record, row.kind, row.title, row.count ] }
    assert_equal [ :admin_page_path, [ @page.id ], { notes: "open" } ], rows.first.route.then { |route| [ route.name, route.args, route.params ] }
  end

  test "five rows, read-scoped, in a constant number of statements" do
    posts = Array.new(7) { |index| create_post(title: "Post #{index}") }
    posts.first(2).each { |post| note(post) }
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    few = capture_sql { Dashboard::OpenThreads.new(actor: users(:reader), channel: :admin).rows }.size
    posts.each { |post| note(post) }

    assert_equal 5, Dashboard::OpenThreads.new(actor: users(:reader), channel: :admin).rows.size
    assert_equal few, capture_sql { Dashboard::OpenThreads.new(actor: users(:reader), channel: :admin).rows }.size
    assert_empty Dashboard::OpenThreads.new(actor: stranger, channel: :admin).rows
  end
end
```

`test/integration/admin/note_inbox_test.rb`:

```ruby
require "test_helper"

class Admin::NoteInboxTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    users(:two).update!(name: "Dana")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Ready, @[#{users(:reader).id}]?") }.record
    sign_in_as(users(:reader))
  end

  test "the dashboard has Notes for you and Open threads, each in a frame of its own, and the sidebar counts the unread" do
    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you section[aria-labelledby=dashboard-notes-for-you]" do
      assert_select "[data-delivery][data-unread] a[href='/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}'][data-turbo-frame=_top]", text: "Dana mentioned you"
      assert_select "p", text: /Ready, @reader@example.com\?/
      assert_select "p", text: /Page · Pricing/
      assert_select "a[href='/cs-studio/notes'][aria-label='All notes for you']"
    end
    assert_select "turbo-frame#notes-open-threads section[aria-labelledby=dashboard-open-threads] a[href='/cs-studio/pages/#{@page.id}?notes=open']", text: "Pricing"
    assert_select "#sidebar #sidebar-badge-dashboard:not([hidden])", text: "1"
  end

  test "each part is fetched on its own" do
    get "/cs-studio/notes/card"
    assert_select "turbo-frame#notes-for-you [data-delivery]", count: 1
    assert_select "#sidebar", count: 0

    get "/cs-studio/notes/open_threads"
    assert_select "turbo-frame#notes-open-threads a", text: "Pricing"

    get "/cs-studio/notes/unread"
    assert_equal({ "unread" => 1 }, response.parsed_body)
  end

  test "the full list pages by 50 and Mark all read reads everything" do
    as(users(:two)) { 51.times { |index| Notes::Start.call(@page, body: "Note #{index} for @[#{users(:reader).id}]") } }

    get "/cs-studio/notes"
    assert_select "h1", text: "Notes for you"
    assert_select "[data-delivery]", count: 50
    get "/cs-studio/notes", params: { page: 2 }
    assert_select "[data-delivery]", count: 2

    post "/cs-studio/notes/read"
    assert_redirected_to "/cs-studio/notes"
    assert_equal 0, Notes::Delivery.unread.where(user: users(:reader)).count
    follow_redirect!
    assert_select "[data-delivery][data-unread]", count: 0
    assert_select "#sidebar-badge-dashboard[hidden]"
  end

  test "following the row marks it read, because opening the thread does" do
    get "/cs-studio/notes/page/#{@page.id}/threads/#{@thread.id}", headers: { "Turbo-Frame" => "notes" }

    get "/cs-studio/notes/unread"
    assert_equal({ "unread" => 0 }, response.parsed_body)
  end

  test "an empty inbox says so, and someone with no rights sees nothing of anyone's" do
    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))

    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you", text: /No notes for you/
    assert_select "turbo-frame#notes-open-threads", text: /No open threads/
    assert_select "#sidebar-badge-dashboard[hidden]"
    assert_no_match "Pricing", response.body
  end
end
```

Add to `test/integration/trash_visibility_test.rb`, above the file's `private` line like Task 9's test (the helper `create_note_for_reader` goes below that line, with the file's other helpers):

```ruby
  test "the inbox, Open threads and the sidebar's count show notes on kept records and never on trashed ones" do
    kept = [ @kept_page, @kept_post, @kept_asset ].map { |subject| create_note_for_reader(subject) }
    # Trashed after the note was written, as in life.
    gone = [ create_page(title: "Later gone"), create_post(title: "Later gone post"), create_media_asset ].map { |subject| [ subject, create_note_for_reader(subject) ] }
    gone.each { |subject, _thread| subject.update!(trashed_at: Time.current) }
    sign_in_as users(:two)

    get admin_root_path
    assert_select "turbo-frame#notes-for-you [data-delivery]", count: 3
    assert_select "#sidebar-badge-dashboard", text: "3"
    assert_no_match "Later gone", response.body
    get admin_notes_path
    assert_select "[data-delivery]", count: 3

    rows = Dashboard::OpenThreads.new(actor: users(:two), channel: :admin).rows
    assert_equal kept.map(&:container).map(&:id).sort, rows.map { |row| row.record.id }.sort
    assert_equal kept.map(&:id).sort, Dashboard::NotesForYou.new(actor: users(:two), channel: :admin).rows(limit: 50).map(&:thread_id).sort
  end

  def create_note_for_reader(subject)
    as(users(:one)) { Notes::Start.call(subject, body: "For @[#{users(:two).id}]") }.record
  end
```

In the sidebar's test, add: with `badges: { admin_root_path: 3 }` the Dashboard entry holds `#sidebar-badge-dashboard` reading 3; with `badges: {}` it holds the same element `hidden` and empty; and the Trash entry has `#sidebar-badge-trash[data-badge]` only above zero. Change that file's existing `trash_count: n` arguments to `badges: { admin_trash_path: n }`.

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/queries/dashboard test/integration/admin/note_inbox_test.rb`

- [ ] **Step 3: The queries.** In `app/models/notes/delivery.rb`:

```ruby
    # The inbox's order: unread first, then the newest news first. A reused
    # row (`Notes::Deliveries`) is dated by `updated_at`, when it last had
    # something new to say.
    scope :inbox_order, -> { order(arel_table[:read_at].eq(nil).desc, updated_at: :desc, id: :desc) }
```

`app/queries/dashboard/notes_for_you.rb`:

```ruby
module Dashboard
  # One person's inbox (notes spec §5): the deliveries written for them, on
  # threads they may read NOW. The read scope is in the query
  # (`Notes.readable_threads`, which also hides the trash), so a delivery on a
  # record the person has lost the right to is neither listed nor counted,
  # while its row stays (§3.3).
  #
  # Data only, no markup and no component: who did it (as a user, or the id
  # of one who is gone), the first words of the message with mentions as
  # names, what the thread is on, and where it opens as a ROUTE NAME with its
  # arguments -- the record's editor with its notes open at the thread
  # (`Admin::NotesScreen::InboxRowComponent` words and resolves it).
  #
  # Constant in queries whatever the number of rows: the page of deliveries
  # with their messages and threads (three), the people named (one), and one
  # read per kind of record the page's rows are on (pages, posts, images,
  # blocks).
  class NotesForYou
    EXCERPT = 140
    KINDS = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze

    Row = Data.define(:id, :reason, :by, :by_id, :excerpt, :kind, :title, :block, :route, :unread, :at, :thread_id)

    def initialize(actor:, channel: Current.channel)
      @actor = actor
      @channel = channel
      @user = actor.is_a?(ApiToken) ? actor.user : actor
    end

    def rows(limit: 5, offset: 0) = build(mine.inbox_order.limit(limit).offset(offset).includes(:message, :thread).to_a)

    def total = mine.count

    # The sidebar's number: one COUNT, narrowed by the read scope.
    def unread_count = mine.unread.count

    # One delivery of this person's, as a row; nil for anyone else's, for one
    # on a record they can't read, and for an id that names nothing.
    def find(delivery_id) = build(mine.where(id: delivery_id).includes(:message, :thread).to_a).first

    private

    def mine
      return Notes::Delivery.none unless @user

      Notes::Delivery.where(user_id: @user.id, thread_id: Notes.readable_threads(@actor, channel: @channel).select(:id))
    end

    def build(deliveries)
      return [] if deliveries.empty?

      threads = deliveries.map(&:thread)
      users = people(deliveries)
      containers = records(threads.map { |thread| [ thread.container_type, thread.container_id ] })
      blocks = ContentBlock.where(id: threads.select { |thread| thread.subject_type == "ContentBlock" }.map(&:subject_id)).index_by(&:id)
      deliveries.filter_map do |delivery|
        thread = delivery.thread
        container = containers[[ thread.container_type, thread.container_id ]] or next
        by_id = doer_id(delivery)
        Row.new(id: delivery.id, reason: delivery.reason, by: users[by_id], by_id: by_id,
          excerpt: Notes::Mentions.display(delivery.message.body, users).first.truncate(EXCERPT),
          kind: KINDS.fetch(thread.container_type), title: container.title.presence,
          block: (blocks[thread.subject_id] if thread.subject_type == "ContentBlock"),
          route: route(container, thread), unread: delivery.read_at.nil?, at: delivery.updated_at, thread_id: thread.id)
      end
    end

    # Who the row is about: the message's author for a mention or a reply, who
    # resolved it for a resolve. A reopen names nobody: the thread does not
    # record who did it.
    def doer_id(delivery)
      case delivery.reason
      when "resolved" then delivery.thread.resolved_by_id
      when "reopened" then nil
      else delivery.message.author_id
      end
    end

    def people(deliveries)
      ids = deliveries.flat_map { |delivery| [ doer_id(delivery), *delivery.message.mentioned_user_ids ] }.compact.uniq
      User.where(id: ids).index_by(&:id)
    end

    # `{ [type, id] => record }`, one query per kind present. Kept records
    # only: the read scope chose the threads, this is defence in depth for a
    # record trashed between the two reads.
    def records(pairs)
      pairs.uniq.group_by(&:first).flat_map do |type, list|
        type.constantize.kept.where(id: list.map(&:last)).map { |record| [ [ type, record.id ], record ] }
      end.to_h
    end

    def route(container, thread)
      base = Audit::Sentence.route_for(container)
      extra = container.is_a?(Media::Asset) ? { thread: thread.id } : { notes: "open", thread: thread.id }
      base.with(params: base.params.merge(extra))
    end
  end
end
```

`app/queries/dashboard/open_threads.rb`:

```ruby
module Dashboard
  # "Open threads" on the dashboard (notes spec §5): the records the viewer
  # may read that have open threads, the most recently active first. One
  # grouped query over `Notes.readable_threads` (the read scope and the trash
  # are in it), then one read per kind of record among the rows.
  class OpenThreads
    Row = Data.define(:record, :kind, :title, :count, :at, :route)

    def initialize(actor:, channel: Current.channel, limit: 5)
      @actor = actor
      @channel = channel
      @limit = limit
    end

    def rows
      @rows ||= begin
        threads = Notes::Thread.arel_table
        newest = threads[:last_message_at].maximum
        groups = Notes.readable_threads(@actor, channel: @channel).unresolved.group(:container_type, :container_id)
          .order(newest.desc, threads[:container_id].desc).limit(@limit).pluck(:container_type, :container_id, Arel.star.count, newest)
        records = load(groups)
        groups.filter_map do |type, id, count, at|
          record = records[[ type, id ]] or next
          base = Audit::Sentence.route_for(record)
          route = record.is_a?(Media::Asset) ? base : base.with(params: base.params.merge(notes: "open"))
          Row.new(record: record, kind: NotesForYou::KINDS.fetch(type), title: record.title.presence, count: count, at: at, route: route)
        end
      end
    end

    private

    def load(groups)
      groups.group_by(&:first).flat_map do |type, list|
        type.constantize.kept.where(id: list.map { |row| row[1] }).map { |record| [ [ type, record.id ], record ] }
      end.to_h
    end
  end
end
```

- [ ] **Step 4: Routes and the controller.** In `config/routes.rb`, above the `notes/:container_type/:container_id` scope:

```ruby
    # A person's own inbox (notes spec §5): the full list, "Mark all read",
    # and the three parts a page shows of it, each with its own GET.
    get "notes", to: "note_inbox#index", as: :notes
    post "notes/read", to: "note_inbox#read", as: :read_notes
    get "notes/card", to: "note_inbox#card", as: :notes_card
    get "notes/open_threads", to: "note_inbox#open_threads", as: :open_note_threads
    get "notes/unread", to: "note_inbox#unread", as: :unread_notes, defaults: { format: :json }
```

`app/controllers/admin/note_inbox_controller.rb`:

```ruby
module Admin
  # The signed-in person's notes inbox (notes spec §5). Open to every
  # signed-in user, like the dashboard: what it lists is narrowed by the read
  # scope inside the queries, so someone with no rights gets empty lists.
  class NoteInboxController < BaseController
    PER_PAGE = 50

    def index
      @inbox = inbox
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: @inbox.total)
      @rows = @pagination.out_of_range? ? [] : @inbox.rows(limit: PER_PAGE, offset: @pagination.offset)
    end

    def read
      Notes::MarkRead.call
      redirect_to admin_notes_path(**admin_url_options), status: :see_other
    end

    def card
      render partial: "admin/note_inbox/card", locals: { rows: inbox.rows }
    end

    def open_threads
      render partial: "admin/note_inbox/open_threads", locals: { rows: Dashboard::OpenThreads.new(actor: Current.actor).rows }
    end

    def unread
      render json: { unread: inbox.unread_count }
    end

    private

    def inbox = Dashboard::NotesForYou.new(actor: Current.actor)
  end
end
```

- [ ] **Step 5: The rows and the views.** `inbox_row_component.rb`:

```ruby
module Admin
  module NotesScreen
    # One line of the inbox (notes spec §5): who did what, the note's first
    # words, where, and when. `Dashboard::NotesForYou::Row` is data; the
    # sentence, the record's kind and the link are made here, the link from
    # the row's route NAME with this request's URL options.
    class InboxRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.public_send(row.route.name, *row.route.args, **row.route.params, **helpers.admin_url_options)

      # One whole sentence per reason and per kind of actor, never glued.
      def sentence
        return t(".#{row.reason}.nobody") if row.by.nil? && row.by_id.nil?

        t(".#{row.reason}.somebody", name: row.by ? row.by.display_name : Admin::UserNameComponent::DELETED_USER)
      end

      def where
        place = t(".where.#{row.kind}", title: row.title || t(".untitled"))
        return place unless row.block

        t(".where.block", place: place, block: row.block.definition&.label || row.block.block_type)
      end
    end
  end
end
```

`inbox_row_component.html.erb`:

```erb
<%= tag.div class: "flex min-w-0 flex-1 items-start gap-2", data: { delivery: row.id, unread: (true if row.unread) } do %>
  <span class="mt-2 size-1.5 shrink-0 rounded-full <%= row.unread ? "bg-accent" : "bg-transparent" %>" aria-hidden="true"></span>
  <div class="min-w-0 flex-1">
    <%= link_to path, class: "block truncate text-ink hover:underline #{"font-semibold" if row.unread}", data: { turbo_frame: "_top" } do %><%= sentence %><% end %>
    <% if row.unread %><span class="sr-only"><%= t(".unread") %></span><% end %>
    <p class="truncate text-sm text-dim"><%= row.excerpt %></p>
    <p class="flex flex-wrap gap-x-2 text-sm text-meta"><span><%= where %></span><%= render Admin::TimeAgoComponent.new(time: row.at) %></p>
  </div>
<% end %>
```

`open_thread_row_component.rb`:

```ruby
module Admin
  module NotesScreen
    # One record with open threads (notes spec §5, "Open threads").
    class OpenThreadRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.public_send(row.route.name, *row.route.args, **row.route.params, **helpers.admin_url_options)
    end
  end
end
```

`open_thread_row_component.html.erb`:

```erb
<div class="min-w-0 flex-1">
  <%= link_to row.title || t(".untitled"), path, class: "block truncate font-semibold text-ink hover:underline", data: { turbo_frame: "_top" } %>
  <p class="flex flex-wrap gap-x-2 text-sm text-meta">
    <span><%= t(".kind.#{row.kind}") %></span><span><%= t(".open", count: row.count) %></span><%= render Admin::TimeAgoComponent.new(time: row.at) %>
  </p>
</div>
```

`app/views/admin/note_inbox/_card.html.erb`:

```erb
<%# "Notes for you" (notes spec §5): a frame of its own (`display: contents`,
    so the card is still the dashboard grid's item) that `GET notes/card`
    answers again on its own. %>
<%= tag.turbo_frame id: "notes-for-you", class: "contents" do %>
  <%= render Admin::DashboardScreen::CardComponent.new(title: t("admin.note_inbox.card.title"), id: "dashboard-notes-for-you",
        empty: t("admin.note_inbox.card.empty"), link: [ admin_notes_path(**admin_url_options), t("admin.note_inbox.card.all") ]) do |card| %>
    <% rows.each do |row| %>
      <% card.with_row { render Admin::NotesScreen::InboxRowComponent.new(row: row) } %>
    <% end %>
  <% end %>
<% end %>
```

`_open_threads.html.erb`: the same shape with `id: "notes-open-threads"`, the card's `id: "dashboard-open-threads"`, the keys `admin.note_inbox.open_threads.title` / `.empty`, no `link:`, and `OpenThreadRowComponent`.

`app/views/admin/note_inbox/index.html.erb`:

```erb
<%# "All notes for you" (notes spec §5): the inbox in full, 50 a page. %>
<% content_for :title, t(".page_title") %>
<div class="mb-4 flex flex-wrap items-center justify-between gap-3">
  <h1 class="text-h1 text-ink"><%= t(".title") %></h1>
  <%= button_to t(".mark_all_read"), admin_read_notes_path(**admin_url_options), class: setup_secondary_link_class, form: { data: { turbo_frame: "_top" } } %>
</div>
<div class="max-w-[880px] rounded-cs border border-line bg-surface">
  <% if @pagination.out_of_range? %>
    <%= render "admin/shared/out_of_range_page", url: admin_notes_path(**admin_url_options) %>
  <% elsif @rows.empty? %>
    <%= render Admin::EmptyStateComponent.new(title: t(".empty")) %>
  <% else %>
    <ul class="px-4">
      <% @rows.each do |row| %>
        <li class="flex items-center gap-3 border-b border-line py-2.5 last:border-b-0"><%= render Admin::NotesScreen::InboxRowComponent.new(row: row) %></li>
      <% end %>
    </ul>
    <% if @pagination.total_pages > 1 %>
      <%= render Admin::PaginationComponent.new(pagination: @pagination, url: ->(page) { admin_notes_path(**admin_url_options, page: page) }) %>
    <% end %>
  <% end %>
</div>
```

In `app/views/admin/dashboard/show.html.erb`, as the first two children of the cards grid:

```erb
  <%# Notes (notes spec §5): what was addressed to the viewer, and where threads are open. %>
  <%= render "admin/note_inbox/card", rows: Dashboard::NotesForYou.new(actor: Current.actor).rows %>
  <%= render "admin/note_inbox/open_threads", rows: Dashboard::OpenThreads.new(actor: Current.actor).rows %>
```

- [ ] **Step 6: The sidebar.** `Admin::BaseController`: add `:notes_badge_count` to `helper_method` and

```ruby
    # The Dashboard entry's count: the viewer's unread notes (notes spec §5).
    # One COUNT per page load, narrowed by the read scope; none for a frame
    # request that renders no layout.
    def notes_badge_count
      @notes_badge_count ||= Current.user ? Dashboard::NotesForYou.new(actor: Current.actor).unread_count : 0
    end
```

`sidebar_component.rb`: `def initialize(modules:, user:, current_path:, url_options:, badges: {})`, `@badges = badges`, replace `trash_count` in the `attr_reader` by `badges`, and replace `badge_for` with

```ruby
      # An entry's count (notes spec §5): Trash's and Dashboard's today,
      # handed in by the layout keyed by the entry's path helper. The
      # Dashboard's element is always in the page, hidden at zero, because a
      # live signal fills it; Trash's is drawn only when there is something
      # to say, as it always was.
      BADGE_IDS = { admin_root_path: "sidebar-badge-dashboard", admin_trash_path: "sidebar-badge-trash" }.freeze
      ALWAYS = %i[admin_root_path].freeze

      def badge_count(entry) = badges[entry[:path]].to_i

      def badge?(entry) = BADGE_IDS.key?(entry[:path]) && (badge_count(entry).positive? || ALWAYS.include?(entry[:path]))

      # The Dashboard's is the one FILLED badge of the sidebar: accent means
      # "unread and addressed to you" and nothing else (notes spec §4.5).
      # Trash's stays the neutral mono number.
      def badge_class(entry)
        return "ml-auto rounded-full bg-accent px-1.5 font-cs-mono text-label text-on-accent" if entry[:path] == :admin_root_path

        "ml-auto font-cs-mono text-label text-meta"
      end
```

`sidebar_component.html.erb`: the badge line becomes

```erb
                <% if badge?(entry) %>
                  <%= tag.span (badge_count(entry) if badge_count(entry).positive?), id: BADGE_IDS.fetch(entry[:path]), hidden: !badge_count(entry).positive?,
                        class: badge_class(entry), data: { badge: (true if badge_count(entry).positive?) } %>
                <% end %>
```

`app/views/layouts/admin.html.erb`: `trash_count: trash_badge_count` becomes `badges: { admin_trash_path: trash_badge_count, admin_root_path: notes_badge_count }`.

- [ ] **Step 7: The strings.** Under `en.admin`:

```yaml
    note_inbox:
      index:
        page_title: "Notes for you · CS Studio"
        title: "Notes for you"
        mark_all_read: "Mark all read"
        empty: "No notes for you."
      card:
        title: "Notes for you"
        empty: "No notes for you."
        all: "All notes for you"
      open_threads:
        title: "Open threads"
        empty: "No open threads."
```

and under `en.admin.components.notes_screen`:

```yaml
        inbox_row:
          unread: "Unread"
          untitled: "(untitled)"
          mention: { somebody: "%{name} mentioned you", nobody: "You were mentioned" }
          reply: { somebody: "%{name} replied", nobody: "Someone replied" }
          resolved: { somebody: "%{name} resolved a note", nobody: "A note was resolved" }
          reopened: { somebody: "%{name} reopened a note", nobody: "A note was reopened" }
          where:
            page: "Page · %{title}"
            post: "Post · %{title}"
            media: "Image · %{title}"
            block: "%{place} · %{block}"
        open_thread_row:
          untitled: "(untitled)"
          kind: { page: "Page", post: "Post", media: "Image" }
          open:
            one: "%{count} open"
            other: "%{count} open"
```

Add the new components, views and controller to `CONVERTED`.

- [ ] **Step 8: Run**, expect green: `PGGSSENCMODE=disable bin/rails test test/queries test/integration test/components test/lib`. No whole-page test pins an absolute statement count (checked: every `capture_sql` and `count_queries` test under `test/integration` compares two runs of the same request, and the two that count particular statements, `trash_screen_test.rb` and `language_settings_test.rb`, match `SELECT COUNT(*) FROM "pages"|"posts"|"media_assets"` and `jsonb_path_exists`, neither of which the sidebar's count is), so none needs a number raised: every CS Studio page costs one statement more, the sidebar's count, and the dashboard its two cards' reads, the same at any number of notes.

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: the notes inbox — Notes for you and Open threads on the dashboard, the full list, the sidebar's unread count" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 12: Live delivery I — the connection, the two channels and the signals

**Spec:** D16, D20, §6.1, §6.2, §6.5, §8 (Live delivery). **Read first:** `app/channels/application_cable/connection.rb`, `config/cable.yml`, `app/controllers/concerns/authentication.rb`, Task 1's `app/models/notes/deliveries.rb`, the services of Tasks 2–4.

This is the app's first use of Action Cable. **A signal carries ids, never content**: no text, title or name. The browser fetches what changed through the scoped GET endpoints of Tasks 5 and 11, so a push can never show a note to someone who may not read it. No browser code in this task.

**Files:**
- Create: `app/channels/application_cable/channel.rb`, `app/channels/notes/person_channel.rb`, `app/channels/notes/record_channel.rb`, `app/models/notes/signals.rb`
- Modify: `app/models/current.rb` (`attribute :notes_tab`), `app/controllers/concerns/admin/note_container.rb`, `app/models/notes/deliveries.rb` (`write`), `app/services/notes/{start,reply,edit_message,delete_message,resolve,reopen,pin,unpin,remove}.rb`
- Test: `test/channels/application_cable/connection_test.rb`, `test/channels/notes/person_channel_test.rb`, `test/channels/notes/record_channel_test.rb`, `test/models/notes/signals_test.rb` (new)

**Interfaces:**
- Consumes: `Notes.key`, `AccessControl.scope`, `AccessControl.holds?`, `Notes::Delivery`.
- Produces:
  - `Notes::Signals.person_stream(user_id) -> "notes:person:<id>"`, `.record_stream(container_type, container_id) -> "notes:record:<key>"`, `.delivery(delivery)`, `.threads(thread)`, `.threads_removed(container_type, container_id, thread_id)`. Each broadcasts after every open transaction has committed, and not at all when one rolls back.
  - Payloads: `{ "kind" => "delivery", "delivery_id" => Integer, "reason" => String }` on a person's stream; `{ "kind" => "threads", "thread_id" => Integer, "origin" => String (optional) }` on a record's stream. `origin` is the opaque id of the browser tab whose request made the change (`Current.notes_tab`, from the header `X-Notes-Tab`, `/\A[a-z0-9-]{8,40}\z/`), so that tab can ignore its own echo.
  - `Notes::PersonChannel` (no parameter; streams for `current_user`), `Notes::RecordChannel` (params `type` in `page|post|media`, `id`; rejected unless the container is found through the read scope).
  - Every service that changes what a record's notes show signals the record; every delivery row written signals its person.

- [ ] **Step 1: Write the failing tests.** `test/channels/application_cable/connection_test.rb`:

```ruby
require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "a CS Studio session connects as its user" do
    session = users(:reader).sessions.create!
    cookies.signed[:session_id] = session.id

    connect

    assert_equal users(:reader), connection.current_user
  end

  test "no session, no connection" do
    assert_reject_connection { connect }

    cookies.signed[:session_id] = 0
    assert_reject_connection { connect }
  end
end
```

`test/channels/notes/person_channel_test.rb`:

```ruby
require "test_helper"

class Notes::PersonChannelTest < ActionCable::Channel::TestCase
  test "it streams for the connected user, whatever parameters are sent" do
    stub_connection current_user: users(:reader)

    subscribe user_id: users(:two).id

    assert subscription.confirmed?
    assert_has_stream "notes:person:#{users(:reader).id}"
    assert_equal 1, subscription.streams.size
  end
end
```

`test/channels/notes/record_channel_test.rb`:

```ruby
require "test_helper"

class Notes::RecordChannelTest < ActionCable::Channel::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  test "a reader subscribes to a record they may read" do
    stub_connection current_user: users(:reader)

    subscribe type: "page", id: @page.id
    assert subscription.confirmed?
    assert_has_stream "notes:record:Page-#{@page.id}"

    subscribe type: "post", id: @post.id.to_s
    assert_has_stream "notes:record:Post-#{@post.id}"
  end

  test "a stranger, a trashed record, an unknown one and a junk type are rejected alike" do
    stub_connection current_user: @stranger
    [ [ "page", @page.id ], [ "post", @post.id ], [ "media", @asset.id ] ].each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, type
    end

    stub_connection current_user: users(:one)
    @page.update!(trashed_at: Time.current)
    [ [ "page", @page.id ], [ "page", 0 ], [ "page", "1 OR 1=1" ], [ "tag", 1 ], [ nil, nil ] ].each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, [ type, id ].inspect
    end
  end

  test "the media library's right opens an image's stream" do
    stub_connection current_user: users(:two)

    subscribe type: "media", id: @asset.id

    assert_has_stream "notes:record:MediaAsset-#{@asset.id}"
  end
end
```

`test/models/notes/signals_test.rb`:

```ruby
require "test_helper"

# What is pushed (notes spec §6.1): after commit, ids only.
class Notes::SignalsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  ALLOWED = { "kind" => String, "delivery_id" => Integer, "reason" => String, "thread_id" => Integer, "origin" => String }.freeze

  setup do
    @page = create_page(title: "A secret title")
    @record = Notes::Signals.record_stream("Page", @page.id)
    @reader = Notes::Signals.person_stream(users(:reader).id)
    @two = Notes::Signals.person_stream(users(:two).id)
  end

  def start = as(users(:two)) { Notes::Start.call(@page, body: "A secret body for @[#{users(:reader).id}]", quote: "a secret quote") }.record

  def sent(stream) = broadcasts(stream).map { |message| ActiveSupport::JSON.decode(message) }

  test "a new note signals its record and the person it mentions" do
    thread = start

    assert_equal [ { "kind" => "threads", "thread_id" => thread.id } ], sent(@record)
    assert_equal [ { "kind" => "delivery", "delivery_id" => Notes::Delivery.find_by!(user: users(:reader)).id, "reason" => "mention" } ], sent(@reader)
    assert_empty sent(@two)
  end

  test "the tab that made the change is named by its opaque id, and a junk id is dropped" do
    Current.set(notes_tab: "tab-12345678") { start }
    assert_equal "tab-12345678", sent(@record).last["origin"]
  end

  # Every broadcast of a whole thread's life, on every stream it touches.
  test "no signal ever holds anything but a kind, ids and a reason" do
    thread = start
    as(users(:reader)) do
      reply = Notes::Reply.call(thread, body: "Another secret").record
      Notes::EditMessage.call(reply, body: "A reworded secret for @[#{users(:one).id}]")
      Notes::Resolve.call(thread)
      Notes::Reopen.call(thread)
      Notes::DeleteMessage.call(reply)
    end
    as(users(:two)) { Notes::Pin.call(thread); Notes::Unpin.call(thread) }
    Notes::Remove.call(@page)

    streams = [ @record, @reader, @two, Notes::Signals.person_stream(users(:one).id) ]
    payloads = streams.flat_map { |stream| sent(stream) }
    assert_operator payloads.size, :>=, 12
    payloads.each do |payload|
      assert_empty payload.keys - ALLOWED.keys, payload.inspect
      payload.each { |key, value| assert_kind_of ALLOWED.fetch(key), value }
      assert_no_match(/secret/i, payload.to_json)
      assert_match(/\A[a-z0-9-]{8,40}\z/, payload["origin"]) if payload.key?("origin")
    end
    assert_equal 9, sent(@record).size # start, reply, edit, resolve, reopen, delete, pin, unpin, remove
  end

  test "nothing is sent for an action that is rolled back" do
    assert_no_broadcasts(@record) do
      assert_no_broadcasts(@reader) do
        ActiveRecord::Base.transaction do
          start
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "a refused or failed action sends nothing" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_no_broadcasts(@record) do
      as(stranger) { Notes::Start.call(@page, body: "Hi") }
      as(users(:two)) { Notes::Start.call(@page, body: " ") }
    end
  end

  test "following and reading signal nobody" do
    thread = start
    before = [ sent(@record).size, sent(@reader).size ]

    as(users(:reader)) { Notes::SetFollowing.call(thread, following: false); Notes::MarkRead.call }

    assert_equal before, [ sent(@record).size, sent(@reader).size ]
  end
end
```

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/channels test/models/notes/signals_test.rb`

- [ ] **Step 3: The signals.** `app/models/notes/signals.rb`:

```ruby
module Notes
  # What is pushed to open CS Studio tabs (notes spec §6.1, decision D16).
  # A SIGNAL CARRIES NO NOTE TEXT, NO TITLE AND NO NAME: a kind and ids. The
  # browser then fetches the part again through the same scoped request it
  # uses on load, so a push can never show a note to someone who may not read
  # it, whatever changed since they subscribed.
  #
  # Two streams. A PERSON's: "a delivery row was written for you" -- the
  # inbox, the sidebar's count, the toast, the chime. A RECORD's: "a thread
  # of this page, post or image changed" -- the list or the thread showing
  # it, and the count markers. `origin` on the second is the opaque id of the
  # browser tab whose request made the change (`Current.notes_tab`), so that
  # tab does not fetch again what its own answer already showed it.
  #
  # Sent after every open transaction has committed, and never for one that
  # rolls back (`ActiveRecord.after_all_transactions_commit`). Called from
  # inside the services' transactions.
  module Signals
    module_function

    def person_stream(user_id) = "notes:person:#{user_id}"

    def record_stream(container_type, container_id) = "notes:record:#{Notes.key(container_type, container_id)}"

    def delivery(delivery)
      payload = { kind: "delivery", delivery_id: delivery.id, reason: delivery.reason }
      later { ActionCable.server.broadcast(person_stream(delivery.user_id), payload) }
    end

    def threads(thread) = threads_removed(thread.container_type, thread.container_id, thread.id)

    def threads_removed(container_type, container_id, thread_id)
      payload = { kind: "threads", thread_id: thread_id, origin: Current.notes_tab }.compact
      later { ActionCable.server.broadcast(record_stream(container_type, container_id), payload) }
    end

    def later(&block) = ActiveRecord.after_all_transactions_commit(&block)
  end
end
```

- [ ] **Step 4: Where they are sent.** In `Notes::Deliveries.write`, after `delivery.update!(...)`: `Signals.delivery(delivery)`. In each of `Start`, `Reply`, `EditMessage`, `Resolve`, `Reopen`, `Pin`, `Unpin`, directly after the `record_event(...)` line(s) inside the transaction: `Signals.threads(<the thread>)` (`created` in `Start`, `thread` elsewhere). In `DeleteMessage`, after `record_event("note.deleted", ...)`: `Signals.threads(current)`. In `Remove`, replace `ids = threads_on(...).pluck(:id)` by a read that also knows the containers, and signal each container once:

```ruby
        rows = threads_on([ @record, *@with ]).pluck(:id, :container_type, :container_id)
        next if rows.empty?

        ids = rows.map(&:first)
        record_event("notes.removed", subject: @record, snapshot: nil, metadata: { "thread_ids" => ids })
        Thread.where(id: ids).delete_all # version: none (note tables only; no public page reads a note)
        rows.uniq { |_id, type, container_id| [ type, container_id ] }.each { |id, type, container_id| Signals.threads_removed(type, container_id, id) }
```

`SetFollowing` and `MarkRead` signal nobody: they change only the actor's own rows. Add a sentence to each service's class comment naming its signal.

- [ ] **Step 5: The tab's id.** `app/models/current.rb`: `attribute :notes_tab` with a comment (the opaque id of the browser tab a notes request came from; `Notes::Signals` puts it in a record's signal). In `Admin::NoteContainer`, add `before_action :note_tab` to the `included do` block Task 5 wrote, after `before_action :set_container` (the block keeps its `helper_method :note_view`), and

```ruby
    # Which tab this is (`X-Notes-Tab`, set by `admin--notes-live` on its
    # notes requests): an id the tab made up, checked for shape and used for
    # nothing but being echoed in the signal.
    def note_tab = Current.notes_tab = request.headers["X-Notes-Tab"].to_s[/\A[a-z0-9-]{8,40}\z/]
```

- [ ] **Step 6: The channels.** `app/channels/application_cable/channel.rb`:

```ruby
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
```

`app/channels/notes/person_channel.rb`:

```ruby
module Notes
  # One person's stream (notes spec §6.2): "something was addressed to you".
  # It takes no parameter: the user is the connection's, identified from the
  # CS Studio session like every controller, so nobody can ask for someone
  # else's.
  class PersonChannel < ApplicationCable::Channel
    def subscribed
      stream_from Signals.person_stream(current_user.id)
    end
  end
end
```

`app/channels/notes/record_channel.rb`:

```ruby
module Notes
  # One record's stream (notes spec §6.2): "a thread of this page, post or
  # image changed". The container is looked up THROUGH THE READ SCOPE at
  # subscribe time, as `Admin::NoteContainer` does for a request, and a
  # record that is out of scope, in the trash or not there is rejected alike.
  # A right that is taken away later needs no handling: the signal says
  # nothing, and the fetch it leads to is scoped.
  class RecordChannel < ApplicationCable::Channel
    def subscribed
      container = find_container
      container ? stream_from(Signals.record_stream(container.class.polymorphic_name, container.id)) : reject
    end

    private

    def find_container
      id = params[:id].to_s[/\A\d+\z/] or return

      case params[:type]
      when "page" then AccessControl.scope(current_user, "pages.read", Page.where(id: id), channel: :admin).first
      when "post" then AccessControl.scope(current_user, "posts.read", Post.where(id: id), channel: :admin).first
      when "media" then (Media::Asset.kept.find_by(id: id) if AccessControl.holds?(current_user, "media.upload", channel: :admin))
      end
    end
  end
end
```

- [ ] **Step 7: Run**, expect green: `PGGSSENCMODE=disable bin/rails test test/channels test/models/notes test/services test/lib` and `bin/rails zeitwerk:check`. The statement-count tests of Tasks 2–5 are unchanged: a signal is no SQL.

- [ ] **Step 8: Commit.**

```bash
git add -A
git commit -m "feat: notes signal open tabs over Action Cable — a person's stream and a record's, ids only, after commit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 13: Live delivery II — the browser re-fetches what a signal names, without losing typed text

**Spec:** §6.1 (what the browser does), §6.3, §6.4 (the toast), §8 (two-session system tests). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` ("NEW" divider, Toast, Thread view; follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/save-rule-and-write-queue.md` ("The write queue": why nothing here may replace an editor form or cause a page refresh), `app/components/admin/toast_component.{rb,html.erb}`, `app/javascript/controllers/admin/toast_controller.js`, Task 7's `notes_controller.js`.

The cable consumer is the one `turbo-rails` already ships inside `turbo.min.js` (`import { cable } from "@hotwired/turbo-rails"`): no new import-map pin. It is only ever asked for by an admin controller, so a public page opens no socket (`test/integration/public_javascript_test.rb` is extended to say so).

**Files:**
- Create: `app/javascript/controllers/admin/notes_live_controller.js`
- Modify: `app/views/layouts/admin.html.erb` (`<body>`, one `<template>`), `app/helpers/admin/messages_helper.rb`, `app/javascript/controllers/admin/notes_controller.js` (two small methods), `app/components/admin/notes_screen/drawer_component.html.erb`, `app/components/admin/media_library/panel_component.html.erb`, `app/javascript/mind_graph/card_notes.js`, `config/routes.rb`, `app/controllers/admin/note_inbox_controller.rb`, `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/integration/admin/note_inbox_test.rb`, `test/integration/public_javascript_test.rb`, `test/system/admin/notes_live_test.rb` (new)

**Interfaces:**
- Consumes: `Notes::PersonChannel`, `Notes::RecordChannel` and their payloads (Task 12); the scoped GETs of Tasks 5 and 11; `admin--notes#refreshCounts`, `#isOpen`; `Dashboard::NotesForYou#find`.
- Produces:
  - `admin--notes-live` on `<body>`. Targets: `record` (an element that shows one record's notes: `data-notes-type`, `data-notes-id`, `data-notes-counts-url`; it holds `turbo-frame#notes` or listens for the event below). Values: `unreadUrl`, `cardUrl`, `openThreadsUrl`, `deliveryUrl` (with `__ID__`).
  - Events on a `record` element: `admin--notes-live:changed` (`detail: { threadId }`), for a part that refreshes itself (the mind graph's card). On `document`: `admin--notes-live:delivery` (`detail: { id, reason, sentence, title, excerpt, url, threadId, shown }`), which Task 14 listens to.
  - `GET admin_note_delivery_path(id)` (JSON) → `{ id, reason, sentence, title, excerpt, url, thread_id }` for one of the viewer's own deliveries on a record they may read; 404 otherwise.
  - In a thread view refreshed by a signal: `div[data-note-new-divider]` above the first message that arrived, and `button[data-note-jump]` ("1 new message ↓") above the composer while the reader is not at the bottom. `p[data-note-gone]` above a reply field whose thread was deleted.
  - `template#toast-note-template` in the layout.

- [ ] **Step 1: Write the failing tests.** Append to `test/integration/admin/note_inbox_test.rb`:

```ruby
  test "one delivery as data, for the toast and the desktop notification: mine only" do
    delivery = Notes::Delivery.find_by!(user: users(:reader))

    get "/cs-studio/notes/deliveries/#{delivery.id}"

    assert_equal({ "id" => delivery.id, "reason" => "mention", "sentence" => "Dana mentioned you", "title" => "Pricing",
      "excerpt" => "Ready, @reader@example.com?", "url" => "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}", "thread_id" => @thread.id }, response.parsed_body)

    sign_in_as(users(:two))
    get "/cs-studio/notes/deliveries/#{delivery.id}"
    assert_response :not_found
  end
```

Append to `test/integration/public_javascript_test.rb`:

```ruby
  test "a public page asks for no cable connection" do
    create_page(title: "About")

    get "/"

    assert_select "meta[name=action-cable-url]", count: 0
    assert_select "[data-controller*='notes-live']", count: 0
    assert_no_match "turbo-cable-stream-source", response.body
    assert modulepreloads.none? { |href| href.include?("notes_live_controller") }
  end
```

`test/system/admin/notes_live_test.rb`:

```ruby
require "application_system_test_case"

# Live delivery (notes spec §6): a signal over the cable, then a scoped fetch.
# These tests run on the in-process `async` adapter (plan decision C5), which
# reaches the browsers because the system-test server runs in this process.
# (The suite's `test` adapter is that same adapter with a record of what it
# sent -- `ActionCable::SubscriptionAdapter::Test < Async` -- so it would
# deliver too; the switch only makes these tests say which adapter they mean.)
class Admin::NotesLiveSystemTest < ApplicationSystemTestCase
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@block, body: "Is this right?") }.record
    sign_in_via_form(users(:one))
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  def await_cable
    await_admin_controllers
    await_js("document.body.dataset.notesLive === 'connected'", wait: 8)
  end

  def open_thread
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_cable
    assert_selector "#notes-drawer [data-notes-view=thread]"
  end

  test "a mention by someone in another session reaches the badge, the inbox and a toast without a reload" do
    visit "/cs-studio"
    await_cable
    assert_no_selector "#sidebar-badge-dashboard"

    using_session(:dana) do
      sign_in_via_form(users(:two))
      visit "/cs-studio/notes/page/#{@page.id}?compose=Page-#{@page.id}"
      await_admin_controllers
      find("#notes-new textarea[name=body]").send_keys("Look at this, @one")
      assert_selector "#notes-new [role=option]", text: "one@example.com"
      find("#notes-new textarea[name=body]").send_keys(:enter, "please")
      within("#notes-new") { press "Add note" }
      assert_selector "[data-note-thread] [data-note-mention]"
    end

    assert_selector "#sidebar-badge-dashboard", text: "1"
    assert_selector "turbo-frame#notes-for-you [data-delivery][data-unread]", text: "Dana mentioned you"
    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing"
    within("#toasts .admin-toast") { press "Open" }
    assert_selector "#notes-drawer [data-notes-view=thread]", text: "Look at this"
  end

  test "a reply arrives in the open thread under a NEW divider while a half-typed reply is kept" do
    open_thread
    reply = find("#note-thread-#{@thread.id}-reply textarea[name=body]")
    reply.send_keys("Half a thou")

    # Addressed to the viewer, so that there IS a delivery the two lines at the
    # end are about: without the mention this person, who never wrote in the
    # thread, would be told nothing and both would pass with nothing tested.
    as(users(:two)) { Notes::Reply.call(@thread, body: "One more thing, @[#{users(:one).id}]") }

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-new-divider] + [data-note-message]", text: "One more thing"
    assert_equal "Half a thou", find("#note-thread-#{@thread.id}-reply textarea[name=body]").value
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector('#note-thread-#{@thread.id}-reply textarea[name=body]')")
    assert_eventually(message: "the delivery was not marked read") { Notes::Delivery.where(user: users(:one)).pluck(:read_at).then { |read| read.any? && read.all? } }
    assert_no_selector "#toasts .admin-toast" # the thread is open in this tab: no toast, and the delivery is read
  end

  test "the list and the count markers follow a note started elsewhere, and a new note's typed text is kept" do
    visit "/cs-studio/pages/#{@page.id}"
    await_cable
    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    find("#notes-new textarea[name=body]").send_keys("Mine, unfinished")

    other = as(users(:two)) { Notes::Start.call(@page, body: "Started elsewhere") }.record

    assert_selector "#notes-list a#note-row-#{other.id}", text: "Started elsewhere"
    assert_selector "#notes-open-count", text: "2"
    assert_equal "Mine, unfinished", find("#notes-new textarea[name=body]").value
  end

  test "a closed drawer still gets its counts; a burst of signals is one fetch" do
    visit "/cs-studio/pages/#{@page.id}"
    await_cable
    assert_selector "#notes-open-count", text: "1"
    page.execute_script("window.__notesFetches = 0; const f = window.fetch; window.fetch = (...a) => { if (String(a[0].url || a[0]).includes('/notes/')) window.__notesFetches += 1; return f(...a) }")

    as(users(:two)) { 5.times { |index| Notes::Start.call(@block, body: "Burst #{index}") } }

    assert_selector "#notes-open-count", text: "6"
    assert_selector "#notes-marker-ContentBlock-#{@block.id} [data-notes-count]", text: "6"
    assert_operator page.evaluate_script("window.__notesFetches"), :<=, 2
  end

  test "a thread deleted under a typed reply keeps the reply and says so" do
    open_thread
    find("#note-thread-#{@thread.id}-reply textarea[name=body]").send_keys("Still typing")

    assert ContentBlocks::Destroy.call(@block).ok?

    assert_selector "[data-note-gone]", text: "This thread was deleted"
    assert_equal "Still typing", find("#note-thread-#{@thread.id}-reply textarea[name=body]").value
  end

  test "the tab that sent a note does not fetch it again, and the page is never refreshed" do
    open_thread
    page.execute_script("window.__stay = true; window.__notesGets = 0; const f = window.fetch; window.fetch = (...a) => { const o = a[1] || {}; if ((o.method || 'GET') === 'GET' && String(a[0].url || a[0]).includes('/notes/')) window.__notesGets += 1; return f(...a) }")
    find("#note-thread-#{@thread.id}-reply textarea[name=body]").send_keys("From this tab")
    within("#note-thread-#{@thread.id}-reply") { press "Reply" }
    assert_selector "[data-note-message]", text: "From this tab"
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "nothing was fetched" means anything

    assert_equal 0, page.evaluate_script("window.__notesGets") # this controller's fetches; Turbo's own go through the `fetch` it kept at load
    assert_equal true, page.evaluate_script("window.__stay") # the document was never replaced
    assert_writes_settled
  end
end
```

(Turbo keeps its own reference to `fetch`, so the two wrappers above see only this controller's requests: that is what they count. If `sign_in_via_form` inside `using_session` needs the sign-in page visited first, follow what the helper does for the default session.)

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/integration/admin/note_inbox_test.rb test/integration/public_javascript_test.rb`

- [ ] **Step 3: One delivery as data.** `config/routes.rb`, beside the inbox routes: `get "notes/deliveries/:id", to: "note_inbox#delivery", as: :note_delivery, constraints: { id: /\d+/ }, defaults: { format: :json }`. In `Admin::NoteInboxController`:

```ruby
    # One of the viewer's own deliveries as data (notes spec §6.1, §6.4): what
    # a tab asks for after a signal named its id, for the toast and the
    # desktop notification. Through `Dashboard::NotesForYou#find`, so it is
    # the viewer's own row on a record they may read, or not found. The
    # sentence is the inbox row's, from the same keys.
    def delivery
      row = inbox.find(params[:id]) or raise ActiveRecord::RecordNotFound
      name = row.by ? row.by.display_name : Admin::UserNameComponent::DELETED_USER
      nobody = row.by.nil? && row.by_id.nil?
      sentence = t("admin.components.notes_screen.inbox_row.#{row.reason}.#{nobody ? "nobody" : "somebody"}", name: name)
      render json: { id: row.id, reason: row.reason, sentence: sentence, title: row.title || t("admin.components.notes_screen.inbox_row.untitled"),
        excerpt: row.excerpt, url: public_send(row.route.name, *row.route.args, **row.route.params, **admin_url_options), thread_id: row.thread_id }
    end
```

- [ ] **Step 4: The layout.** On `<body>`: add `admin--notes-live` to `data-controller`; add the values `data-admin--notes-live-unread-url-value="<%= admin_unread_notes_path %>"`, `-card-url-value="<%= admin_notes_card_path(**admin_url_options) %>"`, `-open-threads-url-value="<%= admin_open_note_threads_path(**admin_url_options) %>"`, `-delivery-url-value="<%= admin_note_delivery_path(0, **admin_url_options).sub("/0", "/__ID__") %>"`; and to `data-action`: `turbo:before-fetch-request@document->admin--notes-live#tag`. Beside `#toast-error-template`:

```erb
    <%# The toast a note addressed to the viewer raises (notes spec §6.4): the
        existing inverted toast with the action "Open", 8 seconds like Undo.
        `admin--notes-live` clones it and writes the sentence, the accent dot
        and where "Open" leads; inert here, like the template above. %>
    <template id="toast-note-template"><%= render Admin::ToastComponent.new(message: t("admin.notes.script.toast.placeholder"), kind: :undo,
          action: { label: t("admin.notes.script.toast.open"), url: admin_notes_path, method: :get }) %></template>
```

`SCRIPT_MESSAGES` gains `notes.script.toast.on notes.script.live.new_messages notes.script.live.new_divider notes.script.live.gone`. Extend `<body>`'s comment: the fifth controller, and that it is the only thing that opens a socket.

- [ ] **Step 5: The record elements.** `drawer_component.html.erb`: add to the `<aside>`'s `data:` `"admin--notes-live-target": "record", notes_type: helpers.note_args(container).first, notes_id: container.id, notes_counts_url: helpers.admin_record_note_counts_path(*helpers.note_args(container))`. `panel_component.html.erb`: the same four on `#media-notes` (`"media"`, `asset.id`). `card_notes.js`: on the section, `section.setAttribute("data-admin--notes-live-target", "record")` (written out: the identifier's double dash can't be spelled through `dataset`, whose `adminNotesLiveTarget` is `data-admin-notes-live-target`, a target of nothing), `section.dataset.notesType = "post"`, `section.dataset.notesId = node.id`, and `section.addEventListener("admin--notes-live:changed", load)`.

In `notes_controller.js` add the getter the live controller asks (it already calls `refreshCounts`):

```js
  // The thread this tab is showing in its open drawer, or null: a delivery
  // for it needs no toast (`admin--notes-live`).
  get shownThread() {
    if (!this.isOpen) return null
    return this.frameTarget.querySelector("[data-notes-view='thread']")?.dataset.noteThread || null
  }
```

- [ ] **Step 6: The controller.** `app/javascript/controllers/admin/notes_live_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { messages } from "i18n/messages"

// Live delivery of notes (notes spec §6). Lives on <body>. A signal over the
// cable says only THAT something changed (`Notes::Signals`: a kind and ids);
// this controller then fetches the part again through the same scoped GET the
// page used on load, so what a tab can show is always what its viewer may
// read. The consumer is the one bundled in turbo-rails; nothing but this file
// asks for it, so a public page opens no socket.
//
// TWO SUBSCRIPTIONS.
// - `Notes::PersonChannel`, once per tab: a delivery was written for the
//   viewer. The sidebar's count and, on the dashboard, the two cards are
//   fetched again; that one delivery is read as data and announced on
//   `document` (`admin--notes-live:delivery`) and, unless its thread is
//   already showing in this tab, raised as a toast.
// - `Notes::RecordChannel`, one per `record` target (an editor's drawer, the
//   media panel's notes, the mind graph's card): a thread of that record
//   changed.
//
// REFRESHING WITHOUT LOSING WORK (§6.3). What is READ is replaced; what is
// TYPED is never touched.
// - the list view: `#notes-list` is replaced, but a new-note field that is
//   on screen stays the very element it was, text, names and focus included;
// - the thread view: only its `messages` part is replaced; the reply field
//   below it is not. Messages that arrived are set off by a NEW divider, and
//   when the reader is not at the bottom nothing moves: a "1 new message ↓"
//   button appears above the field. A message being edited (an open edit
//   form with text) holds the refresh back until the next signal;
// - a thread that is gone while its reply field holds text keeps the field,
//   with "This thread was deleted" above it; with an empty field the list
//   comes back;
// - a drawer that is closed, or a part that draws itself (the graph's card),
//   gets its counts (`admin--notes#refreshCounts`) and an event
//   (`admin--notes-live:changed`).
// Signals in a burst are one fetch per part per 500 ms. The tab whose own
// request made a change is named in the signal (`origin`, the `X-Notes-Tab`
// header `tag` puts on this tab's notes requests) and ignores it. When the
// socket comes back after a drop, every part is fetched once.
//
// NO PAGE REFRESH, NO MORPHING (decision D20): nothing here touches an editor
// form, the write queue or anything outside the notes parts.
const COALESCE_MS = 500
const NEAR_BOTTOM = 48

export default class extends Controller {
  static targets = [ "record" ]
  static values = { unreadUrl: String, cardUrl: String, openThreadsUrl: String, deliveryUrl: String }

  initialize() {
    this.tab = `tab-${crypto.randomUUID()}`.slice(0, 40)
    this.records = new Map()
    this.timers = new Map()
    this.wasConnected = false
  }

  async connect() {
    this.person = await cable.subscribeTo({ channel: "Notes::PersonChannel" }, {
      connected: () => this.online(),
      received: (signal) => { if (signal.kind === "delivery") this.soon("person", () => this.delivered(signal)) }
    })
  }

  disconnect() {
    this.person?.unsubscribe()
    this.records.forEach((subscription) => subscription.unsubscribe())
    this.records.clear()
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers.clear()
  }

  async recordTargetConnected(element) {
    const subscription = await cable.subscribeTo({ channel: "Notes::RecordChannel", type: element.dataset.notesType, id: element.dataset.notesId }, {
      received: (signal) => {
        if (signal.kind !== "threads" || signal.origin === this.tab) return
        this.soon(element, () => this.refresh(element, signal.thread_id))
      }
    })
    if (element.isConnected) this.records.set(element, subscription)
    else subscription.unsubscribe()
  }

  recordTargetDisconnected(element) {
    this.records.get(element)?.unsubscribe()
    this.records.delete(element)
    clearTimeout(this.timers.get(element))
    this.timers.delete(element)
  }

  // `turbo:before-fetch-request` on the document: this tab's notes requests
  // say which tab they are, so the signal they cause can be ignored here.
  tag(event) {
    const url = event.detail.url?.pathname || ""
    if (url.includes("/notes/")) event.detail.fetchOptions.headers["X-Notes-Tab"] = this.tab
  }

  // The socket is up. The first time that is all; after a drop, every part
  // is fetched once -- signals sent meanwhile were never received.
  online() {
    document.body.dataset.notesLive = "connected"
    if (this.wasConnected) {
      this.recordTargets.forEach((element) => this.soon(element, () => this.refresh(element, null)))
      this.soon("person", () => this.refreshInbox())
    }
    this.wasConnected = true
  }

  // One run per key per COALESCE_MS, at the end of the burst's first window.
  soon(key, run) {
    if (this.timers.has(key)) return
    this.timers.set(key, setTimeout(() => {
      this.timers.delete(key)
      run().catch((error) => console.warn("notes: a live refresh failed", error))
    }, COALESCE_MS))
  }

  // --- a record's notes -----------------------------------------------------------

  async refresh(element, threadId) {
    element.dispatchEvent(new CustomEvent("admin--notes-live:changed", { detail: { threadId } }))
    const frame = element.querySelector("turbo-frame#notes")
    const view = frame?.querySelector("[data-notes-view]")
    if (!view || element.hidden) return this.refreshCounts(element)

    const url = frame.getAttribute("src")
    const response = await fetch(url, { headers: { Accept: "text/html", "Turbo-Frame": "notes", "X-Notes-Tab": this.tab } })
    const fresh = response.ok ? new DOMParser().parseFromString(await response.text(), "text/html").querySelector("turbo-frame#notes [data-notes-view]") : null
    const current = frame.querySelector("[data-notes-view]")
    if (!current) return

    if (current.dataset.notesView === "list") this.replaceList(current, fresh)
    else this.replaceThread(frame, current, fresh)
    this.takeCounts(fresh)
  }

  replaceList(current, fresh) {
    if (!fresh || fresh.dataset.notesView !== "list") return
    const next = document.importNode(fresh, true)
    const field = current.querySelector("#notes-new")
    if (field) {
      // The very element, not a copy: its text, its names and the focus stay.
      const slot = next.querySelector("#notes-new")
      if (slot) slot.replaceWith(field)
      else (next.querySelector("[data-admin--notes-target~='counts']") || next.firstElementChild).after(field)
      next.querySelector("[data-note-new-link]")?.remove()
    }
    const resolved = current.querySelector("#notes-resolved-section")?.open
    current.replaceWith(next)
    if (resolved && next.querySelector("#notes-resolved-section")) next.querySelector("#notes-resolved-section").open = true
  }

  replaceThread(frame, current, fresh) {
    const text = messages(this.element)
    const reply = current.querySelector("[data-note-part='reply']")
    const same = fresh?.dataset.notesView === "thread" && fresh.dataset.noteThread === current.dataset.noteThread

    if (!same) {
      const typed = reply?.querySelector("textarea")?.value
      if (!typed) return void (frame.src = frame.getAttribute("src").replace(/\/threads\/\d+/, ""))
      current.querySelector("[data-note-part='messages']")?.remove()
      if (!current.querySelector("[data-note-gone]")) {
        const gone = document.createElement("p")
        gone.dataset.noteGone = ""
        gone.setAttribute("role", "status")
        gone.className = "rounded-cs border border-line bg-sunken px-3 py-2 text-sm text-ink"
        gone.textContent = text.t("notes.script.live.gone")
        reply.before(gone)
      }
      // Its form posts to a thread that is not there: the text stays to be copied.
      reply.querySelectorAll("button[type=submit]").forEach((button) => { button.disabled = true })
      return
    }

    const old = current.querySelector("[data-note-part='messages']")
    // An edit in progress is typed text too: wait for the next signal.
    if ([ ...old.querySelectorAll("details[open] textarea") ].some((field) => field.value !== field.defaultValue)) return

    const scroller = current.closest("[data-notes-scroller]") || document.scrollingElement
    const atBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < NEAR_BOTTOM
    const known = new Set([ ...old.querySelectorAll("[data-note-message]") ].map((message) => message.dataset.noteMessage))
    const next = document.importNode(fresh.querySelector("[data-note-part='messages']"), true)
    const arrived = [ ...next.querySelectorAll("[data-note-message]") ].filter((message) => !known.has(message.dataset.noteMessage))
    // The divider stays where it first stood while the thread is open.
    const firstNew = old.querySelector("[data-note-new-divider]")?.nextElementSibling?.dataset.noteMessage
    const mark = (firstNew && next.querySelector(`[data-note-message="${CSS.escape(firstNew)}"]`)) || arrived[0]
    if (mark) {
      mark.closest("details")?.setAttribute("open", "")
      mark.before(this.divider(text))
    }
    old.replaceWith(next)
    current.dataset.state = fresh.dataset.state

    current.querySelector("[data-note-jump]")?.remove()
    if (arrived.length === 0) return
    if (atBottom) scroller.scrollTop = scroller.scrollHeight
    else reply.before(this.jump(text, arrived.length, scroller))
  }

  divider(text) {
    const divider = document.createElement("div")
    divider.dataset.noteNewDivider = ""
    divider.className = "flex items-center gap-2"
    const line = document.createElement("span")
    line.className = "h-px flex-1 bg-accent"
    const label = document.createElement("span")
    label.className = "font-cs-mono text-label uppercase tracking-mono text-accent"
    label.textContent = text.t("notes.script.live.new_divider")
    divider.append(line, label)
    return divider
  }

  jump(text, count, scroller) {
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.noteJump = ""
    button.className = "sticky bottom-28 z-10 cursor-pointer self-center rounded-cs border border-line-strong bg-surface px-2.5 py-1 text-[12px] font-medium text-ink shadow-menu"
    button.textContent = text.t("notes.script.live.new_messages", { count })
    button.addEventListener("click", () => {
      scroller.scrollTop = scroller.scrollHeight
      button.remove()
    })
    return button
  }

  takeCounts(fresh) {
    const counts = fresh?.querySelector("[data-admin--notes-target~='counts']")?.dataset.counts
    if (counts) this.notes?.refreshCounts(JSON.parse(counts))
  }

  async refreshCounts(element) {
    const url = element.dataset.notesCountsUrl
    if (!url) return
    const response = await fetch(url, { headers: { Accept: "application/json" } })
    if (response.ok) this.notes?.refreshCounts(await response.json())
  }

  // `admin--notes`, on the same element.
  get notes() {
    return this.application.getControllerForElementAndIdentifier(this.element, "admin--notes")
  }

  // --- the person's inbox -----------------------------------------------------------

  async delivered(signal) {
    await this.refreshInbox()
    const response = await fetch(this.deliveryUrlValue.replace("__ID__", encodeURIComponent(signal.delivery_id)), { headers: { Accept: "application/json" } })
    if (!response.ok) return // not readable (any more): nothing to say
    const row = await response.json()
    const shown = this.notes?.shownThread === String(row.thread_id)
    const detail = { id: row.id, reason: row.reason, sentence: row.sentence, title: row.title, excerpt: row.excerpt, url: row.url, threadId: row.thread_id, shown }
    document.dispatchEvent(new CustomEvent("admin--notes-live:delivery", { detail }))
    // Showing already: its own refresh (the record's signal) fetches the
    // thread, which is what marks the delivery read. No toast.
    if (shown) return this.refreshInbox()
    this.toast(row)
  }

  async refreshInbox() {
    const response = await fetch(this.unreadUrlValue, { headers: { Accept: "application/json" } })
    if (response.ok) {
      const { unread } = await response.json()
      const badge = document.getElementById("sidebar-badge-dashboard")
      if (badge) {
        badge.textContent = unread > 0 ? String(unread) : ""
        badge.hidden = unread === 0
        badge.toggleAttribute("data-badge", unread > 0)
      }
    }
    this.reload(document.getElementById("notes-for-you"), this.cardUrlValue)
    this.reload(document.getElementById("notes-open-threads"), this.openThreadsUrlValue)
  }

  // The dashboard's two cards are frames drawn with the page, with no `src`
  // of their own: the first signal gives them one, later ones reload it.
  reload(frame, url) {
    if (!frame) return
    if (frame.getAttribute("src") === url) frame.reload()
    else frame.src = url
  }

  // The layout's `#toast-note-template`, filled: "Dana mentioned you on
  // Pricing" and "Open". The action is a GET form, whose query a browser
  // rebuilds from its fields: the URL's parameters go in as hidden fields.
  toast(row) {
    const template = document.getElementById("toast-note-template")
    const region = document.getElementById("toasts")
    if (!template || !region) return
    const toast = template.content.firstElementChild.cloneNode(true)
    toast.querySelector("span").textContent = messages(this.element).t("notes.script.toast.on", { sentence: row.sentence, title: row.title })
    const dot = document.createElement("span")
    dot.className = "size-1.5 shrink-0 rounded-full bg-accent"
    dot.setAttribute("aria-hidden", "true")
    toast.prepend(dot)
    const form = toast.querySelector("form")
    const target = new URL(row.url, window.location.origin)
    form.action = target.pathname
    target.searchParams.forEach((value, name) => {
      const field = document.createElement("input")
      field.type = "hidden"
      field.name = name
      field.value = value
      form.append(field)
    })
    region.append(toast)
  }
}
```

(Checked against `app/components/admin/toast_component.html.erb`: the toast is `div.admin-toast` holding one `<span>` with the message, then, with `action:`, a `button_to` whose form says `data-turbo-frame="_top"`, then the dismiss button; `:undo` is the 8-second kind, and the region is `#toasts`. So `querySelector("span")`, read before the dot is put in front of it, is the message, and `querySelector("form")` the action.)

- [ ] **Step 7: The strings.** Under `en.admin.notes.script`:

```yaml
        toast:
          placeholder: "A note for you"
          open: "Open"
          on: "%{sentence} on %{title}"
        live:
          new_divider: "New"
          new_messages:
            one: "%{count} new message ↓"
            other: "%{count} new messages ↓"
          gone: "This thread was deleted"
```

Add `notes_live_controller.js` to `CONVERTED`.

- [ ] **Step 8: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/integration test/channels test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/notes_live_test.rb test/system/admin/notes_drawer_test.rb test/system/admin/autosave_test.rb test/system/admin/promotion_hold_test.rb
```

`autosave_test.rb` and `promotion_hold_test.rb` are run because `<body>` gained a controller that listens to `turbo:before-fetch-request`; they must pass with no edited assertion. The cable needs nothing set up for these tests (checked): `config/application.rb` requires `action_cable/engine`, which mounts the server at `/cable` ahead of the app's own catch-all routes (an internal route: `bin/rails routes` does not list it, `Rails.application.routes.routes` does), the path turbo-rails' consumer asks for when the page has no `action-cable-url` meta tag; `ApplicationCable::Connection` already identifies `current_user` from the signed `session_id` cookie; and Action Cable allows an origin equal to the request's own host by default (`allow_same_origin_as_host`), which is what a system test's browser sends. If `document.body.dataset.notesLive` is never set all the same, say in the task report what was needed.

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: a note reaches open tabs at once — the list, an open thread, the counts, the inbox and a toast, with typed text left alone" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 14: Live delivery III — the mention chime, the desktop notification and their two settings

**Spec:** D18, D19, §3.1 (`users.notes_sound`, `users.notes_desktop`), §6.4, §8 (the stubbed `AudioContext` and `Notification`). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` ("Account switches", "Toast"; follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `docs/reference/save-rule-and-write-queue.md` ("The save rule", "How the footer counts": configuration saves explicitly through `Admin::SaveBarComponent`), `app/services/users/update_profile.rb`, `app/controllers/admin/accounts_controller.rb`, `app/views/admin/accounts/edit.html.erb`, `test/support/service_calls.rb` (`SELF_SERVICE`).

**Files:**
- Create: `db/migrate/20261009120000_add_notes_settings_to_users.rb`, `app/services/users/update_notifications.rb`, `app/javascript/controllers/admin/notes_alert_controller.js`, `app/javascript/controllers/admin/notes_permission_controller.js`
- Modify: `db/schema.rb`, `config/routes.rb`, `app/controllers/admin/accounts_controller.rb`, `app/views/admin/accounts/edit.html.erb`, `app/views/layouts/admin.html.erb` (`<body>`), `app/models/audit/snapshot.rb` (the user's two new fields), `config/locales/admin/notes.en.yml`, `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/services/service_contract_test.rb` (floor `45`), `test/lib/admin_i18n_test.rb`
- Test: `test/services/users/update_notifications_test.rb` (new), `test/integration/admin/accounts_test.rb`, `test/system/admin/notes_live_test.rb`

**Interfaces:**
- Consumes: the `document` event `admin--notes-live:delivery` (`detail: { id, reason, sentence, title, excerpt, url, threadId, shown }`, Task 13).
- Produces:
  - `users.notes_sound` (boolean, not null, default true), `users.notes_desktop` (boolean, not null, default false).
  - `Users::UpdateNotifications.call(user, sound:, desktop:, actor: Current.actor) -> Result(record: User)`: the actor's own account only, like `Users::UpdateProfile`; records `user.updated`.
  - `PATCH admin_account_notifications_path` (params `notes_sound`, `notes_desktop`, each `"1"` or `"0"`) → `accounts#update_notifications`.
  - `admin--notes-alert` on `<body>` (values `sound`, `desktop`): for a `mention` delivery, one tab of the browser plays the chime and, when the tab is hidden or unfocused and the browser allows it, raises the desktop notification.
  - `admin--notes-permission` on the desktop row: `[data-state=default|granted|denied|unsupported]`, the action `allow`.

- [ ] **Step 1: Write the failing tests.** `test/services/users/update_notifications_test.rb`:

```ruby
require "test_helper"

class Users::UpdateNotificationsTest < ActiveSupport::TestCase
  test "the defaults: sound on, desktop off" do
    assert_equal [ true, false ], [ users(:reader).notes_sound, users(:reader).notes_desktop ]
  end

  test "a person changes their own two settings, and it is audited as their account" do
    result = as(users(:reader)) { Users::UpdateNotifications.call(users(:reader), sound: false, desktop: true) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ false, true ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
    event = Audit::Event.order(:id).last
    assert_equal [ "user.updated", "User", users(:reader).id ], [ event.action, event.subject_type, event.subject_id ]
  end

  test "nobody changes someone else's, not even a user manager, and a token never does" do
    assert_predicate as(users(:two)) { Users::UpdateNotifications.call(users(:reader), sound: false, desktop: false) }, :denied?
    token, = ApiToken.generate!(users(:reader), group: access_control_groups(:admin))
    assert_predicate as(token, channel: :mcp) { Users::UpdateNotifications.call(users(:reader), sound: false, desktop: false) }, :denied?
    assert users(:reader).reload.notes_sound
  end
end
```

Append to `test/integration/admin/accounts_test.rb` (with the file's own setup and sign-in; `users(:reader)` below is whoever that file signs in):

```ruby
  test "the account screen has the two Notes switches in a form of their own with a save bar, and saving keeps the screen" do
    get "/cs-studio/account/password"

    assert_select "form#notes-form[action='/cs-studio/account/notifications']" do
      assert_select "input[type=checkbox][name=notes_sound][role=switch][checked]"
      assert_select "input[type=checkbox][name=notes_desktop][role=switch]:not([checked])"
      assert_select "[data-controller='admin--notes-permission'] button", text: "Allow in this browser"
    end
    assert_select "body[data-admin--notes-alert-sound-value=true][data-admin--notes-alert-desktop-value=false]"

    patch "/cs-studio/account/notifications", params: { notes_sound: "0", notes_desktop: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :ok
    assert_match "Notification settings saved.", response.body
    signed_in = Session.order(:id).last.user
    assert_equal [ false, true ], [ signed_in.notes_sound, signed_in.notes_desktop ]
  end
```

Append to `test/system/admin/notes_live_test.rb`:

```ruby
  # A fake AudioContext that counts the tones it is asked for, and a fake
  # Notification that counts and records what it is given.
  STUBS = <<~JS.freeze
    window.__tones = 0
    window.__notified = []
    const node = () => ({ connect() {}, start() {}, stop() {}, frequency: { value: 0 }, gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {}, linearRampToValueAtTime() {} } })
    window.AudioContext = class { get currentTime() { return 0 } get destination() { return {} } createGain() { return node() } createOscillator() { window.__tones += 1; return node() } resume() { return Promise.resolve() } }
    window.Notification = class { static permission = "granted"; static requestPermission() { return Promise.resolve("granted") } constructor(title, options) { window.__notified.push({ title, body: options.body }) } }
  JS

  def mention_me = as(users(:two)) { Notes::Start.call(@page, body: "Over to you, @[#{users(:one).id}]") }

  def stubbed_dashboard
    visit "/cs-studio"
    await_cable
    page.execute_script(STUBS)
    find("h1").click # a click in the tab: a browser plays no sound before one
  end

  test "a mention chimes once across two tabs, and notifies on the desktop only when the setting is on and the tab is not in front" do
    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    second = open_new_window
    within_window(second) { stubbed_dashboard }

    mention_me

    tones = -> { [ page.evaluate_script("window.__tones"), within_window(second) { page.evaluate_script("window.__tones") } ] }
    assert_eventually(message: "nobody chimed") { tones.call.sum == 2 } # two tones, one tab
    sleep 0.6 # sleep: a second tab's late claim would arrive within the agreement window (150 ms) and chime again by now
    assert_equal 2, tones.call.sum
    notified = page.evaluate_script("window.__notified") + within_window(second) { page.evaluate_script("window.__notified") }
    assert_operator notified.size, :<=, 1
    notified.each { |notice| assert_equal [ "Dana mentioned you", "Pricing\nOver to you, @one@example.com" ], notice.values_at("title", "body") }
  ensure
    second&.close
  end

  test "with the sound switched off nothing chimes, and a reply never does" do
    users(:one).update!(notes_sound: false)
    stubbed_dashboard

    mention_me
    assert_selector "#toasts .admin-toast", text: "Dana mentioned you"
    assert_equal 0, page.evaluate_script("window.__tones")

    users(:one).update!(notes_sound: true)
    stubbed_dashboard
    as(users(:one)) { Notes::SetFollowing.call(@thread, following: true) }
    as(users(:two)) { Notes::Reply.call(@thread, body: "Just a reply") }
    assert_selector "#toasts .admin-toast", text: "Dana replied"
    assert_equal 0, page.evaluate_script("window.__tones")
  end

  test "Allow in this browser asks at once, and a browser that refuses says so" do
    visit "/cs-studio/account/password"
    await_admin_controllers
    page.execute_script("window.Notification = class { static permission = 'default'; static requestPermission() { Notification.permission = 'denied'; return Promise.resolve('denied') } }")
    page.execute_script("document.querySelector('[data-controller=\"admin--notes-permission\"]').dispatchEvent(new Event('notes-permission:check'))")
    assert_selector "[data-controller='admin--notes-permission'][data-state=default] button", text: "Allow in this browser"

    press "Allow in this browser"

    assert_selector "[data-controller='admin--notes-permission'][data-state=denied]", text: "Blocked in this browser. Change it in the site settings of your browser."
    assert_no_selector "[data-controller='admin--notes-permission'] button"
  end
```

(The one fixed sleep is there because nothing can be waited FOR when the assertion is that nothing more happens: `await_js` returns as soon as its condition holds. It carries its reason on the line, as `test/lib/system_test_sleeps_test.rb` asks.)

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/services/users test/integration/admin/accounts_test.rb`

- [ ] **Step 3: The columns.** `db/migrate/20261009120000_add_notes_settings_to_users.rb`:

```ruby
# Two settings per person for a mention (notes spec D18, D19): the chime, on
# by default; the desktop notification, OFF by default -- it puts a note's
# first line outside CS Studio (a lock screen), and a browser grants the
# permission only on the person's own click. On the user, not in the browser,
# so they follow the person across devices; the permission itself is the
# browser's.
class AddNotesSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notes_sound, :boolean, null: false, default: true
    add_column :users, :notes_desktop, :boolean, null: false, default: false
  end
end
```

Run `bin/rails db:migrate` and `PGGSSENCMODE=disable bin/rails db:test:prepare`.

- [ ] **Step 4: The service.** `app/services/users/update_notifications.rb`:

```ruby
module Users
  # A signed-in user's own notification settings for notes (notes spec D18,
  # D19): the mention chime and the desktop notification. "Your own account",
  # like `Users::UpdateProfile`, and refused for anyone else the same way --
  # nobody decides for another person whether their browser makes a sound.
  #
  # Never an API token: a token acts for its user within its group's grants
  # and has no business with the account itself.
  class UpdateNotifications < ApplicationService
    include OwnerProtection

    # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(user, sound:, desktop:, actor: Current.actor)
      @user = user
      @sound = sound ? true : false
      @desktop = desktop ? true : false
      @actor = actor
    end

    def call
      # Logged against `users.manage`, the permission a person changing
      # someone else's account would need, as `Users::UpdateProfile` does.
      return denied("users.manage", @user) unless actor.is_a?(User) && actor == @user

      @user.assign_attributes(notes_sound: @sound, notes_desktop: @desktop)
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      saved ? success(@user) : failure(@user)
    end
  end
end
```

Contract: add `Users::UpdateNotifications` to `EXPECTED_SERVICES`, the floor to `45`, to `SELF_SERVICE` `"Users::UpdateNotifications" => { manager_may: false, reason: "any signed-in user may change their own notification settings; nobody may change someone else's" }` (and "four" in its comment becomes "five"), and the factory:

```ruby
    "Users::UpdateNotifications" => lambda {
      target = stranger_target
      mine = stranger_target(email: "mine@example.com")
      { call: -> { Users::UpdateNotifications.call(target, sound: false, desktop: true) }, permission: "users.manage", on: target,
        control_actor: target,
        owner: mine, own: -> { Users::UpdateNotifications.call(mine, sound: false, desktop: true) }, own_event: "user.updated" }
    },
```

`Audit::Snapshot`'s `User` serializer lists its fields by name (checked: `id`, `email_address`, `name`, `owner`, `group_ids`), so without a change the event would say nothing of what was switched: add `"notes_sound" => record.notes_sound, "notes_desktop" => record.notes_desktop` to it (neither is a secret), and where an existing test pins a user's whole snapshot hash (`grep -rn '"group_ids" =>' test`), add the two keys there and say so in the task report.

- [ ] **Step 5: The account screen.** Route, beside `account/profile`: `patch "account/notifications", to: "accounts#update_notifications", as: :account_notifications`. `Admin::AccountsController`:

```ruby
    # The two Notes switches (notes spec §6.4): configuration, so an explicit
    # Save that keeps the screen, like the name above it.
    def update_notifications
      result = Users::UpdateNotifications.call(Current.user, sound: params[:notes_sound] == "1", desktop: params[:notes_desktop] == "1")
      if result.ok?
        if request.accepts.any? { |type| type.symbol == :turbo_stream }
          render turbo_stream: toast_stream(t("admin.accounts.notes.saved"))
        else
          redirect_to admin_account_password_path(**admin_url_options), status: :see_other, notice: t("admin.accounts.notes.saved")
        end
      else
        forbidden_or(result) do
          @notes_errors = result.errors
          render :edit, status: :unprocessable_entity
        end
      end
    end
```

In `app/views/admin/accounts/edit.html.erb`, between the name form and the password form (and give the password form's `save_bar_form_data` no new `after:`; the switches are independent of it). The switch is the existing one (the handoff, "Account switches"; checked: `app/components/admin/fields/boolean_field.html.erb` draws it as a checkbox with `class: "cs-toggle", role: "switch"`, styled in `content-spiel.tailwind.css`), used here as it is:

```erb
  <%# Notes (notes spec §6.4): two per-person settings, saved with this form's
      own save bar. The setting is the person's; the permission to notify is
      this browser's, which the row below the second switch shows and asks
      for at once, outside the save. %>
  <%= form_with url: admin_account_notifications_path(**admin_url_options), method: :patch, id: "notes-form",
        class: "mb-8 max-w-[560px] rounded-cs border border-line bg-surface", data: save_bar_form_data(dirty: Array(@notes_errors).any?) do %>
    <div class="border-b border-line px-[18px] py-3.5">
      <h2 class="text-base font-semibold text-ink"><%= t("admin.accounts.notes.title") %></h2>
      <p class="text-[13px] text-dim"><%= t("admin.accounts.notes.description") %></p>
    </div>
    <% { "notes_sound" => Current.user.notes_sound, "notes_desktop" => Current.user.notes_desktop }.each do |name, on| %>
      <div class="border-b border-line px-[18px] py-3.5">
        <label class="flex items-center justify-between gap-4 text-sm text-ink">
          <span><%= t("admin.accounts.notes.#{name}") %></span>
          <%= hidden_field_tag name, "0", id: nil %>
          <%= check_box_tag name, "1", on, role: "switch", class: "cs-toggle" %>
        </label>
        <% if name == "notes_desktop" %>
          <div class="mt-2" data-controller="admin--notes-permission" data-state="unsupported" data-action="notes-permission:check->admin--notes-permission#render">
            <div class="flex items-center justify-between gap-3 rounded-cs bg-accent-tint px-3 py-2.5 text-[13px] text-ink" data-admin--notes-permission-target="ask" hidden>
              <span><%= t("admin.accounts.notes.permission.ask") %></span>
              <%= render Admin::ButtonComponent.new(label: t("admin.accounts.notes.permission.allow"), variant: :secondary, size: :small, type: "button", data: { action: "admin--notes-permission#allow" }) %>
            </div>
            <p class="rounded-cs bg-accent-tint px-3 py-2.5 text-[13px] text-ink" data-admin--notes-permission-target="blocked" hidden><%= t("admin.accounts.notes.permission.blocked") %></p>
          </div>
        <% end %>
      </div>
    <% end %>
    <%= render Admin::SaveBarComponent.new(form_id: "notes-form", cancel_url: admin_root_path(**admin_url_options), save_label: t("admin.accounts.notes.save")) %>
  <% end %>
```

(A hidden `0` ahead of each box makes an unticked switch submit; `admin--save-bar` ignores a hidden input that is not marked `data-save-bar-track`, so the box alone is counted. The "Allow" button is `type="button"` with no `name`: it is not a field of the form and is never locked by it.)

`app/javascript/controllers/admin/notes_permission_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// The desktop-notification row of the account screen (notes spec §6.4,
// handoff "Account switches"). The SETTING is the person's and is saved with
// the form; the PERMISSION is this browser's, and this shows which of three
// states it is in: not asked yet (an info line with "Allow in this browser",
// which asks at once, in the click, as browsers require), allowed (nothing),
// blocked (a line saying where to change it, no button). A browser without
// notifications shows nothing.
export default class extends Controller {
  static targets = [ "ask", "blocked" ]

  connect() {
    this.render()
  }

  async allow() {
    if (!("Notification" in window)) return
    await window.Notification.requestPermission()
    this.render()
  }

  render() {
    const state = "Notification" in window ? window.Notification.permission : "unsupported"
    this.element.dataset.state = state
    this.askTarget.hidden = state !== "default"
    this.blockedTarget.hidden = state !== "denied"
  }
}
```

- [ ] **Step 6: The alert.** On `<body>` in the layout: add `admin--notes-alert` to `data-controller`, `data-admin--notes-alert-sound-value="<%= Current.user&.notes_sound ? true : false %>"`, `data-admin--notes-alert-desktop-value="<%= Current.user&.notes_desktop ? true : false %>"`, and to `data-action`: `admin--notes-live:delivery@document->admin--notes-alert#delivery`.

`app/javascript/controllers/admin/notes_alert_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// A mention's chime and desktop notification (notes spec §6.4, D18, D19).
// `admin--notes-live` announces every delivery it has read as data
// (`admin--notes-live:delivery`); this acts on a `mention` only, and only as
// the person's settings say (`sound`, `desktop`: on the account screen).
//
// ONE TAB. Every open tab of the browser hears the same delivery, so they
// agree over a `BroadcastChannel` which one alerts: each says "I have it"
// with whether it is visible; after a short wait the visible one -- else the
// one whose id sorts first -- alerts and says "done", and a tab that hears
// "done" for a delivery never alerts for it, however late its own copy of
// the signal arrives. Without `BroadcastChannel` each tab decides alone.
//
// THE CHIME: two short tones from the Web Audio API; no file. A browser that
// has not had a click in this tab plays nothing, and nothing is queued for
// later. THE DESKTOP NOTIFICATION: only when the tab is hidden or not
// focused and the browser has granted the permission; its title is the
// inbox's sentence, its body the record's title and the note's first line,
// both read through the scoped inbox endpoint; a click brings the tab forward
// and opens the thread.
const CHANNEL = "cs-notes-alerts"
const AGREE_MS = 150
const TONES = [ [ 880, 0 ], [ 1175, 0.14 ] ]
const TONE_SECONDS = 0.16

export default class extends Controller {
  static values = { sound: Boolean, desktop: Boolean }

  initialize() {
    this.tab = crypto.randomUUID()
    this.claims = new Map()
    this.done = new Set()
    this.heard = this.heard.bind(this)
  }

  connect() {
    this.channel = "BroadcastChannel" in window ? new BroadcastChannel(CHANNEL) : null
    this.channel?.addEventListener("message", this.heard)
  }

  disconnect() {
    this.channel?.removeEventListener("message", this.heard)
    this.channel?.close()
  }

  delivery(event) {
    const delivery = event.detail
    if (delivery.reason !== "mention" || (!this.soundValue && !this.desktopValue) || this.done.has(delivery.id)) return

    const claim = { type: "claim", id: delivery.id, tab: this.tab, visible: document.visibilityState === "visible" }
    this.note(claim)
    this.channel?.postMessage(claim)
    setTimeout(() => {
      const mine = !this.done.has(delivery.id) && this.winner(delivery.id) === this.tab
      this.claims.delete(delivery.id)
      if (!mine) return
      this.done.add(delivery.id)
      this.channel?.postMessage({ type: "done", id: delivery.id })
      this.alert(delivery)
    }, AGREE_MS)
  }

  heard(event) {
    const message = event.data
    if (message?.type === "claim") this.note(message)
    else if (message?.type === "done") this.done.add(message.id)
  }

  note(claim) {
    this.claims.set(claim.id, [ ...(this.claims.get(claim.id) || []), claim ])
  }

  winner(id) {
    const claims = this.claims.get(id) || []
    const visible = claims.filter((claim) => claim.visible)
    return (visible.length > 0 ? visible : claims).map((claim) => claim.tab).sort()[0]
  }

  alert(delivery) {
    if (this.soundValue) this.chime()
    if (this.desktopValue) this.notify(delivery)
  }

  chime() {
    const Context = window.AudioContext || window.webkitAudioContext
    if (!Context) return
    // No click in this tab yet: the browser would refuse or defer the sound.
    if (navigator.userActivation && !navigator.userActivation.hasBeenActive) return

    this.audio ||= new Context()
    this.audio.resume?.()
    const now = this.audio.currentTime
    TONES.forEach(([ frequency, at ]) => {
      const oscillator = this.audio.createOscillator()
      const gain = this.audio.createGain()
      oscillator.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, now + at)
      gain.gain.exponentialRampToValueAtTime(0.12, now + at + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, now + at + TONE_SECONDS)
      oscillator.connect(gain)
      gain.connect(this.audio.destination)
      oscillator.start(now + at)
      oscillator.stop(now + at + TONE_SECONDS)
    })
  }

  notify(delivery) {
    if (!("Notification" in window) || window.Notification.permission !== "granted") return
    if (document.visibilityState === "visible" && document.hasFocus()) return

    const notification = new window.Notification(delivery.sentence, { body: `${delivery.title}\n${delivery.excerpt}`, tag: `cs-note-${delivery.id}` })
    notification.onclick = () => {
      window.focus()
      Turbo.visit(delivery.url)
    }
  }
}
```

(`notification.onclick` is a property of an object the script made, not an inline handler in markup. Checked against `test/lib/inline_handlers_test.rb`: its pattern for scripts is an `on…=` in attribute position, after a tag's name and whitespace, which `notification.onclick =` is not; its own examples let `once = true` and `onStart:` through the same way.)

- [ ] **Step 7: The strings.** Under `en.admin`:

```yaml
    accounts:
      notes:
        title: "Notes"
        description: "What happens in this browser when someone mentions you in a note."
        notes_sound: "Play a sound when I'm mentioned"
        notes_desktop: "Show a desktop notification when I'm mentioned"
        save: "Save"
        saved: "Notification settings saved."
        permission:
          ask: "This browser has not been allowed to show notifications yet."
          allow: "Allow in this browser"
          blocked: "Blocked in this browser. Change it in the site settings of your browser."
```

Add the two controllers to `CONVERTED`. (`accounts/edit.html.erb` is not on that list; its new strings are keys all the same.)

- [ ] **Step 8: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/services test/integration/admin test/lib
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/notes_live_test.rb test/system/admin/pending_lock_test.rb
```

- [ ] **Step 9: Commit.**

```bash
git add -A
git commit -m "feat: a mention chimes in one tab and can raise a desktop notification, each a setting on the account screen" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 15: Reactions

**Spec:** D10, §3.1 (`note_reactions`), §3.5 (`Notes::React`), §4.2 (the same emoji set), §4.5 (reaction chips). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` ("Reaction chip"; follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), Task 3's `set_following.rb` (a service that says `# audit: none`), Task 5's `listing.rb` and `message_component.*`.

Nothing before this task knows reactions exist; this task adds them everywhere they show.

**Files:**
- Create: `db/migrate/20261009130000_create_note_reactions.rb`, `app/models/notes/reaction.rb`, `app/services/notes/react.rb`, `app/controllers/admin/note_reactions_controller.rb`, `app/components/admin/notes_screen/reactions_component.{rb,html.erb}`
- Modify: `db/schema.rb`, `app/models/notes/message.rb`, `app/queries/notes/listing.rb`, `app/components/admin/notes_screen/message_component.html.erb`, `config/routes.rb`, `config/locales/admin/notes.en.yml`, `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/services/service_contract_test.rb` (floor `46`), `test/lib/admin_i18n_test.rb`
- Test: `test/services/notes/react_test.rb`, `test/integration/admin/note_reactions_test.rb` (new), `test/models/notes/signals_test.rb`, `test/services/notes/remove_test.rb`

**Interfaces:**
- Consumes: `Notes::EMOJI`, `Notes::Authorization`, `Notes::Signals.threads`, `Admin::NoteContainer`.
- Produces:
  - `note_reactions(message_id FK cascade, user_id FK cascade, emoji string, timestamps)`, unique on `(message_id, user_id, emoji)`; `Notes::Reaction`; `Notes::Message#reactions`.
  - `Notes::React.call(message, emoji:, actor: Current.actor) -> Result(record: Notes::Message)`: a toggle of the actor's own reaction; needs the read right; an emoji outside `Notes::EMOJI` is a failure; not audited; no delivery; signals the record.
  - `POST admin_record_note_message_reactions_path(type, id, thread, message)` with `emoji` → `note_reactions#create`.
  - `Admin::NotesScreen::ReactionsComponent.new(message:, listing:, viewer:, type:, view:)`: `div[data-note-reactions]` > a `button[data-reaction=<emoji>]` per emoji in use (`[data-mine]` for the viewer's own) and `details[data-reaction-add]` with the set.

- [ ] **Step 1: Write the failing tests.** `test/services/notes/react_test.rb`:

```ruby
require "test_helper"

class Notes::ReactTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Shipped") }.record
    @message = @thread.first_message
  end

  def react(emoji, as_user: users(:reader)) = as(as_user) { Notes::React.call(@message, emoji: emoji) }

  test "a reader reacts, and the same emoji again takes the reaction back" do
    assert react("👍").ok?
    assert_equal [ [ users(:reader).id, "👍" ] ], @message.reactions.pluck(:user_id, :emoji)

    assert react("👍").ok?
    assert_empty @message.reactions.reload
  end

  test "several people and several emoji; a reaction tells nobody and is not audited" do
    assert_no_difference [ -> { Audit::Event.count }, -> { Notes::Delivery.count } ] do
      react("👍")
      react("🎉")
      react("👍", as_user: users(:two))
    end

    assert_equal({ "👍" => 2, "🎉" => 1 }, @message.reactions.group(:emoji).count)
  end

  test "only the offered set is accepted, and a stranger is refused" do
    assert_not react("<script>").ok?
    assert_not react("").ok?
    assert_predicate react("👍", as_user: User.create!(email_address: "stranger@example.com", password: "a-long-password-1")), :denied?
    assert_equal 0, Notes::Reaction.count
  end

  test "a reaction writes neither the thread's date nor the page" do
    before = [ @thread.reload.last_message_at, @thread.updated_at, @page.reload.updated_at ]

    travel_to(1.minute.from_now) { react("👍") }

    assert_equal before, [ @thread.reload.last_message_at, @thread.updated_at, @page.reload.updated_at ]
  end

  test "reactions go with their message, their user and their record" do
    user = User.create!(email_address: "fan@example.com", password: "a-long-password-1")
    AccessControl::Membership.create!(group: access_control_groups(:read_only), user: user)
    react("👍", as_user: user)
    react("👍")

    user.destroy!
    assert_equal 1, Notes::Reaction.count
    Notes::Remove.call(@page)
    assert_equal 0, Notes::Reaction.count
  end
end
```

`test/integration/admin/note_reactions_test.rb`:

```ruby
require "test_helper"

class Admin::NoteReactionsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Shipped") }.record
    @message = @thread.first_message
    @path = "/cs-studio/notes/page/#{@page.id}/threads/#{@thread.id}"
    users(:two).update!(name: "Dana")
    as(users(:two)) { Notes::React.call(@message, emoji: "🎉") }
    sign_in_as(users(:reader))
  end

  test "a chip per emoji with its count and who, the viewer's own marked, and the set to add from" do
    post "#{@path}/messages/#{@message.id}/reactions", params: { emoji: "👍" }
    assert_redirected_to @path

    get @path, headers: { "Turbo-Frame" => "notes" }

    assert_select "#note-message-#{@message.id} [data-note-reactions]" do
      assert_select "button[data-reaction='🎉'][title='Dana']:not([data-mine])", text: /🎉\s*1/
      assert_select "button[data-reaction='👍'][data-mine][aria-pressed=true]", text: /👍\s*1/
      assert_select "details[data-reaction-add] button[name=emoji]", count: Notes::EMOJI.size
      assert_select "form[data-turbo-frame=notes]", minimum: 3
    end
  end

  test "the thread view costs the same statements with one reaction as with many" do
    get @path, headers: { "Turbo-Frame" => "notes" }
    one = capture_sql { get @path, headers: { "Turbo-Frame" => "notes" } }.size
    as(users(:one)) { Notes::EMOJI.first(6).each { |emoji| Notes::React.call(@message, emoji: emoji) } }

    assert_equal one, capture_sql { get @path, headers: { "Turbo-Frame" => "notes" } }.size
  end

  test "a reaction outside the scope is not found; on a message of another thread it is gone" do
    other = as(users(:two)) { Notes::Start.call(@page, body: "Another") }.record
    post "#{@path}/messages/#{other.first_message.id}/reactions", params: { emoji: "👍" }
    assert_redirected_to "/cs-studio/notes/page/#{@page.id}?notice=gone"

    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))
    post "#{@path}/messages/#{@message.id}/reactions", params: { emoji: "👍" }
    assert_response :not_found
  end
end
```

Append to `test/models/notes/signals_test.rb`: a reaction broadcasts `{ "kind" => "threads", "thread_id" => thread.id }` on the record's stream and nothing on any person's.

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/services/notes/react_test.rb test/integration/admin/note_reactions_test.rb`

- [ ] **Step 3: The table and the record.** `db/migrate/20261009130000_create_note_reactions.rb`:

```ruby
# An emoji reaction on a note (notes spec D10, §3.1): one row per person,
# message and emoji. Both keys cascade: a reaction goes with its message and
# with its user.
class CreateNoteReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :note_reactions do |t|
      t.references :message, null: false, index: false, foreign_key: { to_table: :note_messages, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :emoji, null: false
      t.timestamps

      t.index %i[message_id user_id emoji], unique: true
    end
  end
end
```

Migrate and prepare the test database. `app/models/notes/reaction.rb`:

```ruby
module Notes
  # One person's emoji on one message (decision D10): an acknowledgement
  # without a reply. From the fixed set (`Notes::EMOJI`), so nothing a browser
  # sends is ever drawn that the app did not offer.
  class Reaction < ApplicationRecord
    self.table_name = "note_reactions"

    belongs_to :message, class_name: "Notes::Message", inverse_of: :reactions
    belongs_to :user

    validates :emoji, inclusion: { in: Notes::EMOJI }
  end
end
```

In `Notes::Message`: `has_many :reactions, -> { order(:created_at, :id) }, class_name: "Notes::Reaction", foreign_key: :message_id, inverse_of: :message` with a comment (no `dependent:`: the foreign key removes them with the message).

- [ ] **Step 4: The service.** `app/services/notes/react.rb`:

```ruby
module Notes
  # Adds the actor's reaction to a message, or takes it back (a toggle;
  # notes spec §3.5). Needs the read right. It tells nobody (no delivery: a
  # reaction never goes to the inbox), moves no date and is not audited; the
  # record's stream is signalled so open threads show it.
  class React < ApplicationService
    include Authorization

    # audit: none (a reaction is an acknowledgement, not a change to content or to a note's text)

    def initialize(message, emoji:, actor: Current.actor)
      @message = message
      @emoji = emoji.to_s
      @actor = actor
    end

    def call
      thread = @message.thread
      container = thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused
      return failure(@message, [ I18n.t("admin.notes.errors.emoji") ]) unless Notes::EMOJI.include?(@emoji)
      return success(@message) unless actor_user

      outcome = with_locked_thread(thread) do |current|
        next :gone unless Message.where(id: @message.id).exists?

        mine = Reaction.find_by(message_id: @message.id, user_id: actor_user.id, emoji: @emoji)
        mine ? mine.destroy! : Reaction.create!(message_id: @message.id, user_id: actor_user.id, emoji: @emoji)
        Signals.threads(current)
        @message
      end
      thread_answer(outcome, @message)
    end
  end
end
```

`errors.emoji: "That reaction isn't available."` in the locale file. Contract: `Notes::React` in `EXPECTED_SERVICES`, floor `46`, and

```ruby
    "Notes::React" => lambda {
      page = create_page(title: "Noted", published: false)
      message = note_on(page).first_message
      { call: -> { Notes::React.call(message, emoji: "👍") }, permission: "pages.read", on: page, control_actor: users(:two),
        control_unaudited: "a reaction is an acknowledgement, not a change to content or to a note's text" }
    },
```

- [ ] **Step 5: The endpoint and the chips.** Route, in the notes scope: `post "threads/:thread_id/messages/:id/reactions", to: "note_reactions#create", as: :record_note_message_reactions, constraints: { thread_id: /\d+/, id: /\d+/ }`.

`app/controllers/admin/note_reactions_controller.rb`:

```ruby
module Admin
  # A reaction on one message of one of the container's threads: a toggle.
  class NoteReactionsController < BaseController
    include NoteContainer

    def create
      thread = container_threads.find_by(id: params[:thread_id]) or return gone!
      message = thread.messages.find_by(id: params[:id]) or return gone!
      result = Notes::React.call(message, emoji: params[:emoji])

      if result.ok?
        redirect_to thread_path(thread), status: :see_other
      else
        render_thread(thread, status: failure_status(result), failed: failed_form("message-#{message.id}", result, body: ""))
      end
    end
  end
end
```

In `Notes::Listing#load`: `includes(messages: :reactions)`, and in `#users` add each reaction's `user_id` to the ids (the chip's title names who reacted); update the class comment's count of queries by one.

`reactions_component.rb`:

```ruby
module Admin
  module NotesScreen
    # A message's reactions (notes spec §4.5, handoff "Reaction chip"): a chip
    # per emoji in use, drawn like a tag chip -- the emoji and a mono count --
    # with the accent tint for the viewer's own; a press toggles the viewer's.
    # Then the chip that opens the set to add from, the composer's own
    # (`Notes::EMOJI`). Every button is a submit of a small form into the
    # notes frame; no script.
    class ReactionsComponent < Admin::AdminComponent
      CHIP = "inline-flex h-6 cursor-pointer items-center gap-[5px] rounded-full border px-[9px]".freeze

      def initialize(message:, listing:, viewer:, type:, view:)
        @message = message
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
      end

      private

      attr_reader :message, :listing, :viewer

      # `[[emoji, [reaction, ...]], ...]` in the order each emoji first appeared.
      def groups = message.reactions.group_by(&:emoji).to_a

      def mine?(reactions) = viewer.present? && reactions.any? { |reaction| reaction.user_id == viewer.id }

      def names(reactions)
        reactions.map { |reaction| listing.users[reaction.user_id]&.display_name || Admin::UserNameComponent::DELETED_USER }.join(", ")
      end

      def chip_class(mine) = "#{CHIP} #{mine ? "border-accent bg-accent-tint" : "border-line bg-sunken"}"

      def path
        helpers.admin_record_note_message_reactions_path(*helpers.note_args(listing.container), message.thread_id, message,
          **{ view: (@view unless @view == "editor"), **helpers.admin_url_options }.compact)
      end
    end
  end
end
```

`reactions_component.html.erb`:

```erb
<div class="flex flex-wrap items-center gap-1.5" data-note-reactions>
  <% groups.each do |emoji, reactions| %>
    <% mine = mine?(reactions) %>
    <%= button_to path, params: { emoji: emoji }, class: chip_class(mine), title: names(reactions), aria: { pressed: mine, label: t(".chip", emoji: emoji, count: reactions.size) },
          data: { reaction: emoji, mine: (true if mine) }, form: { class: "inline-flex", data: { turbo_frame: "notes" } } do %>
      <span class="text-[13px]" aria-hidden="true"><%= emoji %></span><span class="font-cs-mono text-[11px] <%= mine ? "text-accent" : "text-dim" %>" aria-hidden="true"><%= reactions.size %></span>
    <% end %>
  <% end %>
  <details class="relative" data-reaction-add>
    <summary class="flex h-6 w-[30px] cursor-pointer list-none items-center justify-center rounded-full border border-line text-meta hover:bg-sunken" aria-label="<%= t(".add") %>" title="<%= t(".add") %>"><%= helpers.render "admin/shared/icon", name: :smile %></summary>
    <%= form_with url: path, method: :post, class: "absolute bottom-full left-0 z-20 mb-1 grid w-56 grid-cols-6 gap-0.5 rounded-cs border border-line-strong bg-surface p-1 shadow-menu", data: { turbo_frame: "notes" } do %>
      <% ::Notes::EMOJI.each do |emoji| %>
        <button type="submit" name="emoji" value="<%= emoji %>" class="cursor-pointer rounded-cs px-1 py-0.5 text-base hover:bg-sunken" aria-label="<%= t(".react_with", emoji: emoji) %>"><%= emoji %></button>
      <% end %>
    <% end %>
  </details>
</div>
```

In `message_component.html.erb`, after the body: `<%= render Admin::NotesScreen::ReactionsComponent.new(message: message, listing: listing, viewer: viewer, type: type, view: view) %>`. Strings under `en.admin.components.notes_screen.reactions`: `add: "Add a reaction"`, `react_with: "React with %{emoji}"`, `chip: { one: "%{emoji}, %{count} reaction", other: "%{emoji}, %{count} reactions" }`. Add the new files to `CONVERTED`.

- [ ] **Step 6: Run**, expect green: `PGGSSENCMODE=disable bin/rails test test/services test/integration/admin test/models/notes test/queries/notes test/lib`. The statement-constancy tests of Task 5 (`listing_test.rb`, `notes_test.rb`) keep passing as written; a test that pins an exact count for the thread view gains one.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat: emoji reactions on a note, from the composer's own set" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 16: Files on a note, and the one authenticated way to read them

**Spec:** D9, D15, §3.6, §4.5 (Motion), §7 ("A file fails validation"), §8 (Files), §9 ("File serving"). **Read first:** `docs/superpowers/specs/2026-10-09-notes-on-content-handoff.md` ("Attachment row", "Inline image and still GIF tile", "Composer", and "Where the spec wins": no lightbox; follow the handoff for markup, tokens, sizes and states; where it and the spec differ on behaviour, the spec wins), `config/initializers/active_storage_access.rb` (Active Storage's read URLs are public to whoever holds one), `app/models/media/asset.rb` lines 470–520 (why the type is sniffed with neither a name nor a declared type), `docs/reference/media.md`.

Nothing before this task knows a note can carry a file. This is the first authenticated read of an upload in the app, and it must not become a general way to read blobs: the action takes the id of an attachment of a message of one of the container's threads, never a blob key or a signed id.

**Files:**
- Create: `app/models/notes/files.rb`, `app/controllers/admin/note_files_controller.rb`, `app/components/admin/notes_screen/files_component.{rb,html.erb}`, `app/javascript/controllers/admin/note_gif_controller.js`
- Modify: `app/models/notes/message.rb`, `app/services/notes/{start,reply,remove}.rb`, `app/controllers/admin/note_threads_controller.rb`, `app/controllers/admin/note_messages_controller.rb`, `app/controllers/concerns/admin/note_container.rb`, `app/components/admin/notes_screen/composer_component.{rb,html.erb}`, `app/components/admin/notes_screen/message_component.html.erb`, `app/javascript/controllers/admin/note_composer_controller.js`, `app/queries/notes/listing.rb`, `config/routes.rb`, `config/locales/admin/notes.en.yml`, `test/lib/admin_i18n_test.rb`
- Test: `test/models/notes/files_test.rb`, `test/services/notes/files_test.rb`, `test/integration/admin/note_files_test.rb` (new), `test/services/notes/remove_test.rb`, `test/system/admin/note_composer_test.rb`

**Interfaces:**
- Consumes: Tasks 2, 4–6.
- Produces:
  - `Notes::Files::MAX_COUNT = 5`, `MAX_BYTES = 10.megabytes`, `IMAGE_TYPES`, `ALLOWED` (`{ content type => label }`), `.type_of(upload) -> String | nil` (from the bytes), `.errors_for(uploads) -> Array<String>`, `.attach(message, uploads)`, `.image?(content_type)`.
  - `Notes::Message has_many_attached :files`.
  - `Notes::Start.call(subject, body:, files: [], ...)`, `Notes::Reply.call(thread, body:, files: [], ...)`: `files` are uploaded files (anything with `tempfile` and `original_filename`). A refused file is a failure naming the file and the reason; nothing is saved.
  - `GET admin_record_note_file_path(type, id, attachment)` → `note_files#show`: the bytes, `X-Content-Type-Options: nosniff`, `Content-Disposition: inline` only for the four image types, `attachment` otherwise, `Cache-Control: private, no-store`.
  - `Admin::NotesScreen::FilesComponent.new(message:, listing:, type:)`: `div[data-note-files]` > `a[data-note-image]` (an inline image, opening the same URL in a new tab), `div[data-note-gif]` (a GIF), `a[data-note-file]` (a download row).
  - Composer: `input[type=file][name="files[]"][multiple]`, `ul[data-admin--note-composer-target=chosen]`; the form is multipart. `Admin::NoteContainer#note_files`.
  - No rendered note ever holds `/rails/active_storage`.

- [ ] **Step 1: Write the failing tests.** `test/models/notes/files_test.rb`:

```ruby
require "test_helper"

class Notes::FilesTest < ActiveSupport::TestCase
  def upload(content, name, declared = "application/octet-stream")
    file = Tempfile.new([ "note", File.extname(name) ], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, declared, true, original_filename: name)
  end

  def fixture(name) = upload(file_fixture(name).binread, name)

  PDF = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".b

  test "the type is what the bytes are" do
    assert_equal "image/png", Notes::Files.type_of(fixture("tiny.png"))
    assert_equal "image/gif", Notes::Files.type_of(fixture("small.gif"))
    assert_equal "application/pdf", Notes::Files.type_of(upload(PDF, "report.pdf"))
    assert_equal "text/plain", Notes::Files.type_of(upload("Just some text.\nSecond line.\n", "notes.txt"))
    assert_equal "text/csv", Notes::Files.type_of(upload("a,b\n1,2\n", "table.csv"))
  end

  # Review Focus 5.
  test "a file is refused by what it is, whatever it is called and whatever the browser said" do
    html = "<!DOCTYPE html><html><body><script>alert(1)</script></body></html>"

    assert_equal [ "report.pdf: this type of file can't be attached." ], Notes::Files.errors_for([ upload(html, "report.pdf", "application/pdf") ])
    assert_equal [ "logo.png: this type of file can't be attached." ], Notes::Files.errors_for([ upload(file_fixture("tiny.svg").binread, "logo.png", "image/png") ])
    assert_equal [ "tool.txt: this type of file can't be attached." ], Notes::Files.errors_for([ upload("MZ\x90\x00\x03\x00\x00\x00".b + ("\x00".b * 64), "tool.txt", "text/plain") ])
    assert_empty Notes::Files.errors_for([ upload(PDF, "page.html", "text/html") ]) # a PDF, whatever its name
  end

  test "five files at most, ten megabytes each" do
    six = Array.new(6) { |index| upload("text #{index}", "f#{index}.txt") }
    assert_equal [ "A note can carry at most 5 files." ], Notes::Files.errors_for(six)

    big = upload("a" * (10.megabytes + 1), "big.txt")
    assert_equal [ "big.txt: files can be at most 10 MB." ], Notes::Files.errors_for([ big ])
    assert_empty Notes::Files.errors_for([])
  end
end
```

`test/services/notes/files_test.rb`:

```ruby
require "test_helper"

class Notes::FilesServiceTest < ActiveSupport::TestCase
  setup { @page = create_page(title: "Pricing") }

  def png = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "text/plain", true, original_filename: "shot.png")

  def svg = Rack::Test::UploadedFile.new(file_fixture("tiny.svg"), "image/png", true, original_filename: "logo.png")

  test "a note is started with a file, stored under the type its bytes are, and the log holds no file name" do
    result = as(users(:two)) { Notes::Start.call(@page, body: "See the screenshot", files: [ png ]) }

    assert result.ok?, result.errors.to_sentence
    file = result.record.first_message.files.sole
    assert_equal [ "shot.png", "image/png" ], [ file.filename.to_s, file.content_type ]
    assert_no_match(/shot/, Audit::Event.order(:id).last.attributes.to_json)
  end

  test "a refused file fails the whole note: nothing is saved, nothing is stored, nobody is told" do
    assert_no_difference [ -> { Notes::Thread.count }, -> { ActiveStorage::Blob.count }, -> { Notes::Delivery.count } ] do
      result = as(users(:two)) { Notes::Start.call(@page, body: "For @[#{users(:reader).id}]", files: [ png, svg ]) }
      assert_equal [ "logo.png: this type of file can't be attached." ], result.errors
    end
  end

  test "a reply carries files too, and deleting the message deletes them" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Start") }.record
    reply = as(users(:reader)) { Notes::Reply.call(thread, body: "Here", files: [ png ]) }.record
    assert_equal 1, reply.files.count

    perform_enqueued_jobs { as(users(:reader)) { Notes::DeleteMessage.call(reply) } }

    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Notes::Message").count
    assert_equal 0, ActiveStorage::Blob.count
  end
end
```

(Include `ActiveJob::TestHelper` in that class for `perform_enqueued_jobs`.) Append to `test/services/notes/remove_test.rb`:

```ruby
  test "removing a record's notes removes their files, in the same number of statements for one file as for many" do
    file = -> { Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png", true, original_filename: "shot.png") }
    quiet = create_page(title: "One file", published: false)
    as(users(:two)) do
      Notes::Start.call(quiet, body: "One", files: [ file.call ])
      3.times { Notes::Start.call(@block, body: "Many", files: [ file.call, file.call ]) }
    end

    one = capture_sql { Notes::Remove.call(quiet) }.size
    many = nil
    assert_enqueued_jobs 6, only: ActiveStorage::PurgeJob do
      many = capture_sql { Notes::Remove.call(@page, with: [ @block ]) }.size
    end

    assert_equal one, many
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Notes::Message").count
  end
```

(Include `ActiveJob::TestHelper` in that class. The blobs themselves are purged by the jobs, after the commit.)

`test/integration/admin/note_files_test.rb`:

```ruby
require "test_helper"

class Admin::NoteFilesTest < ActionDispatch::IntegrationTest
  PDF = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".b

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @base = "/cs-studio/notes/page/#{@page.id}"
    pdf = Tempfile.new([ "report", ".pdf" ], binmode: true).tap { |file| file.write(PDF); file.rewind }
    files = [ Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png", true, original_filename: "shot.png"),
      Rack::Test::UploadedFile.new(pdf.path, "application/pdf", true, original_filename: "report.pdf") ]
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Two files", files: files) }.record
    @image, @pdf = @thread.first_message.files.attachments.sort_by { |attachment| attachment.filename.to_s }.reverse
  end

  test "a note is sent with files as one multipart post" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "With a picture", files: [ fixture_file_upload("tiny.png", "image/png") ] }

    assert_response :see_other
    assert_equal 1, Notes::Thread.order(:id).last.first_message.files.count
  end

  test "an image is shown inline through the notes action, a document is a download, and no Active Storage URL is rendered" do
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: { "Turbo-Frame" => "notes" }

    assert_select "[data-note-files] a[data-note-image][target=_blank][href='#{@base}/files/#{@image.id}'] img[src='#{@base}/files/#{@image.id}'][alt='shot.png']"
    assert_select "[data-note-files] a[data-note-file][href='#{@base}/files/#{@pdf.id}']", text: /report\.pdf/
    assert_no_match "/rails/active_storage", response.body
    assert_no_match @image.blob.key, response.body
    assert_no_match @image.blob.signed_id, response.body
  end

  test "the headers: nosniff always, inline for an image only, never cached by a proxy" do
    sign_in_as(users(:reader))

    get "#{@base}/files/#{@image.id}"
    assert_response :ok
    assert_equal [ "image/png", "nosniff" ], [ response.media_type, response.headers["X-Content-Type-Options"] ]
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
    assert_match "no-store", response.headers["Cache-Control"]
    assert_equal file_fixture("tiny.png").binread, response.body

    get "#{@base}/files/#{@pdf.id}"
    assert_match(/\Aattachment; filename="report\.pdf"/, response.headers["Content-Disposition"])
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "a file is found only as an attachment of a note of this record, by someone who may read it" do
    other = create_page(title: "Other")
    asset = create_media_asset
    logo = asset.file.attachment

    sign_in_as(users(:reader))
    get "/cs-studio/notes/page/#{other.id}/files/#{@image.id}" # a real file, of another record's note
    assert_response :not_found
    get "#{@base}/files/#{logo.id}" # a real attachment, but a library image's
    assert_response :not_found
    get "#{@base}/files/#{@image.blob.key}"
    assert_response :not_found

    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))
    get "#{@base}/files/#{@image.id}"
    assert_response :not_found

    @page.update!(trashed_at: Time.current)
    sign_in_as(users(:one))
    get "#{@base}/files/#{@image.id}"
    assert_response :not_found
  end

  test "a refused file re-renders the form with the text kept and the file and the reason named" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Keep this text", files: [ fixture_file_upload("tiny.svg", "image/png") ] }, headers: { "Turbo-Frame" => "notes" }

    assert_response :unprocessable_entity
    assert_select "#notes-new [role=alert]", text: /tiny\.svg: this type of file can't be attached\./
    assert_select "#notes-new textarea[name=body]", text: "Keep this text"
    assert_select "#notes-new [role=alert]", text: /Attach the files again/
  end
end
```

Append to `test/system/admin/note_composer_test.rb`:

```ruby
  test "chosen files are listed above the field with their size, one can be removed, and a sixth is refused in place" do
    open_notes
    # `set` on the field itself: `attach_file` called on an element looks for a file field INSIDE it.
    find("#notes-new input[type=file]", visible: :all).set([ file_fixture("tiny.png").to_s, file_fixture("small.gif").to_s ])

    assert_selector "#notes-new [data-admin--note-composer-target=chosen] li", count: 2
    # The remove button's text is "×"; its name is its `aria-label`, which `press` does not read.
    find("#notes-new [data-admin--note-composer-target=chosen] button[aria-label='Remove small.gif']").click
    assert_selector "#notes-new [data-admin--note-composer-target=chosen] li", count: 1

    field.send_keys("With a file")
    within("#notes-new") { press "Add note" }

    assert_selector "[data-note-thread] [data-note-files] img[alt='tiny.png']"
    assert_equal [ "tiny.png" ], Notes::Message.last.files.map { |file| file.filename.to_s }
  end
```

- [ ] **Step 2: Run, expect failure:** `PGGSSENCMODE=disable bin/rails test test/models/notes/files_test.rb test/services/notes/files_test.rb test/integration/admin/note_files_test.rb`

- [ ] **Step 3: The rules.** `app/models/notes/files.rb`:

```ruby
module Notes
  # A note's files (notes spec D9, §3.6): up to five, ten megabytes each,
  # stored with the message and not in the media library -- working material,
  # not content.
  #
  # THE TYPE IS WHAT THE BYTES ARE. `Marcel::MimeType.for(io)` is asked with
  # neither the file's name nor the type the browser declared: both are the
  # uploader's to choose, and Marcel trusts either the moment the bytes alone
  # don't settle it (`Media::Asset#sniffed_content_type` has the long form of
  # this). An HTML page named `report.pdf` is HTML, an SVG named `logo.png`
  # is SVG, and neither is allowed.
  #
  # Plain text and CSV have no signature: Marcel answers
  # `application/octet-stream` for them, as for anything it can't place. Such
  # a file is taken as text only when its bytes ARE text (valid UTF-8, no NUL
  # or other control character but tab, newline and return); its name then
  # only picks the label, `.csv` or text. Whatever it holds, it is served as
  # `text/plain` or `text/csv` with `nosniff`, as a download.
  #
  # Legacy Office formats (.doc, .xls, .ppt) share one container signature
  # with files that are none of them, so they are left out: the Office and
  # OpenDocument formats of today are allowed.
  module Files
    MAX_COUNT = 5
    MAX_BYTES = 10.megabytes
    IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
    ALLOWED = {
      "image/png" => "PNG", "image/jpeg" => "JPEG", "image/gif" => "GIF", "image/webp" => "WEBP",
      "application/pdf" => "PDF", "text/plain" => "TXT", "text/csv" => "CSV",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "DOCX",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "XLSX",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "PPTX",
      "application/vnd.oasis.opendocument.text" => "ODT",
      "application/vnd.oasis.opendocument.spreadsheet" => "ODS",
      "application/vnd.oasis.opendocument.presentation" => "ODP"
    }.freeze
    TEXT_SAMPLE = 64.kilobytes
    NOT_TEXT = /[\x00-\x08\x0B\x0C\x0E-\x1F]/

    module_function

    def image?(content_type) = IMAGE_TYPES.include?(content_type)

    # The allowed type the upload's bytes are, or nil.
    def type_of(upload)
      io = upload.tempfile
      io.rewind
      sniffed = Marcel::MimeType.for(io)
      io.rewind
      return sniffed if ALLOWED.key?(sniffed)
      return unless sniffed == "application/octet-stream" && text?(io)

      File.extname(upload.original_filename.to_s).casecmp?(".csv") ? "text/csv" : "text/plain"
    ensure
      io&.rewind
    end

    def text?(io)
      sample = io.read(TEXT_SAMPLE).to_s.force_encoding(Encoding::UTF_8)
      sample.present? && sample.scrub("") == sample && !sample.match?(NOT_TEXT)
    end

    # One sentence per refused file, naming it; or the one about the count.
    def errors_for(uploads)
      uploads = Array(uploads)
      return [ I18n.t("admin.notes.errors.files.too_many", count: MAX_COUNT) ] if uploads.size > MAX_COUNT

      uploads.filter_map do |upload|
        name = upload.original_filename.to_s
        if upload.tempfile.size > MAX_BYTES then I18n.t("admin.notes.errors.files.too_big", name: name)
        elsif type_of(upload).nil? then I18n.t("admin.notes.errors.files.type", name: name)
        end
      end
    end

    # Attaches each upload under the type its bytes are, never the declared
    # one. Call inside the message's transaction, after `errors_for` was empty.
    def attach(message, uploads)
      Array(uploads).each do |upload|
        upload.tempfile.rewind
        message.files.attach(io: upload.tempfile, filename: upload.original_filename.to_s, content_type: type_of(upload), identify: false)
      end
    end
  end
end
```

In `Notes::Message`: `has_many_attached :files` with a comment (purged after the message is destroyed, by Active Storage's own `dependent: :purge_later`; read only through `Admin::NoteFilesController`, never by a blob URL).

- [ ] **Step 4: The services.** `Notes::Start` and `Notes::Reply`: add `files: []` to `initialize` (`@files = Array(files)`), add `+ Files.errors_for(@files)` to the `errors` line, and after the message is created inside the transaction `Files.attach(message, @files)` (`created` in `Reply`). In `Notes::Remove`, between `record_event` and the `delete_all`:

```ruby
        purge_files(ids)
```

and

```ruby
    # The files of the messages about to go (notes spec §3.6). The threads are
    # deleted by one DELETE and their messages by the foreign key, so no
    # message is ever `destroy`ed here and Active Storage's own cleanup never
    # runs: the attachment rows are deleted in one statement, and each blob is
    # purged after the commit. Two statements whatever the number of files.
    def purge_files(thread_ids)
      attachments = ActiveStorage::Attachment.where(record_type: "Notes::Message", record_id: Message.where(thread_id: thread_ids).select(:id))
      blobs = ActiveStorage::Blob.where(id: attachments.select(:blob_id)).to_a
      return if blobs.empty?

      attachments.delete_all # version: none (a note's files; no public page reads one)
      ActiveRecord.after_all_transactions_commit { blobs.each(&:purge_later) }
    end
```

- [ ] **Step 5: The form.** `Admin::NoteContainer`: `def note_files = Array(params[:files]).reject(&:blank?)`. `NoteThreadsController#create` passes `files: note_files` to `Notes::Start.call`; `NoteMessagesController#create` to `Notes::Reply.call`. In `failed_form`, add `files_lost: note_files.any?` to the hash. `composer_component.rb`: two new keywords, `files: true` (the edit form passes `files: false`: an edit changes text only) and `files_lost: false`, kept and read through `def files? = @files` and `def files_lost? = @files_lost`; `MessageComponent`'s edit composer passes `files: false`; `ThreadComponent` and `ListComponent` pass `files_lost: own_failure&.dig(:files_lost)` / `failed_new&.dig(:files_lost)`. In `composer_component.html.erb`: `form_with ..., multipart: true`; in the error list, after the errors, `<% if files_lost? %><li><%= t(".attach_again") %></li><% end %>` (a browser never gives a file field its files back); above the field wrapper

```erb
  <% if files? %>
    <ul class="flex flex-col gap-2" data-admin--note-composer-target="chosen" hidden></ul>
    <p class="text-[12px] text-danger-ink" role="alert" data-admin--note-composer-target="fileError" hidden></p>
  <% end %>
```

and in the toolbar, inside `[data-note-toolbar]` and before the emoji control (the place Task 6's comment there keeps for it):

```erb
    <% if files? %>
      <%= file_field_tag "files[]", id: "#{field_id}-files", multiple: true, class: "sr-only", tabindex: -1, aria: { label: t(".attach") },
            data: { "admin--note-composer-target": "files", action: "change->admin--note-composer#filesChosen", max_count: ::Notes::Files::MAX_COUNT, max_bytes: ::Notes::Files::MAX_BYTES } %>
      <button type="button" class="flex cursor-pointer items-center rounded-cs px-2 py-1 text-dim hover:bg-sunken hover:text-ink" aria-label="<%= t(".attach") %>" title="<%= t(".attach_title") %>"
              data-action="admin--note-composer#browse"><%= helpers.render "admin/shared/icon", name: :paperclip %></button>
    <% end %>
```

`script_messages`' `messages_data(...)` (Task 6 gave the call a method and a line of its own, so that `test/lib/script_messages_test.rb` reads its literal keys; `form_data` only names it) gains `"notes.script.files.too_many", "notes.script.files.too_big", "notes.script.files.remove"`, the call still ending its line. In `note_composer_controller.js`: targets gain `"files", "chosen", "fileError"`, and

```js
  // --- files --------------------------------------------------------------------
  // The chosen files are the file input's own (`DataTransfer` rebuilds its
  // list when one is removed); the rows above the field only show them. A
  // sixth file or one over the limit is refused here, in place, before
  // anything is sent -- the server checks the same again, and what a file IS
  // only the server can tell.

  browse() {
    this.filesTarget.click()
  }

  filesChosen() {
    const text = messages(this.element)
    const limit = Number(this.filesTarget.dataset.maxCount)
    const bytes = Number(this.filesTarget.dataset.maxBytes)
    const all = [ ...(this.kept || []), ...this.filesTarget.files ]
    const tooBig = all.find((file) => file.size > bytes)
    const errors = []
    if (tooBig) errors.push(text.t("notes.script.files.too_big", { name: tooBig.name }))
    if (all.length > limit) errors.push(text.t("notes.script.files.too_many", { count: limit }))
    this.setFiles(all.filter((file) => file.size <= bytes).slice(0, limit))
    this.fileErrorTarget.textContent = errors.join(" ")
    this.fileErrorTarget.hidden = errors.length === 0
  }

  removeFile(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.setFiles(this.kept.filter((_file, at) => at !== index))
  }

  setFiles(files) {
    const text = messages(this.element)
    this.kept = files
    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    this.filesTarget.files = transfer.files
    this.chosenTarget.replaceChildren(...files.map((file, index) => {
      const row = document.createElement("li")
      row.className = "flex items-center justify-between gap-2 rounded-cs border border-line px-2.5 py-1.5 text-[13px] text-ink"
      const name = document.createElement("span")
      name.className = "min-w-0 truncate"
      name.textContent = file.name
      const size = document.createElement("span")
      size.className = "shrink-0 font-cs-mono text-[10px] text-meta"
      size.textContent = `${(file.size / 1048576).toFixed(1)} MB` // i18n-ok: a unit symbol, written the same in every language CS Studio has
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "shrink-0 cursor-pointer rounded-cs px-1.5 text-meta hover:bg-sunken hover:text-ink"
      remove.dataset.action = "admin--note-composer#removeFile"
      remove.dataset.index = index
      remove.setAttribute("aria-label", text.t("notes.script.files.remove", { name: file.name }))
      remove.textContent = "×"
      row.append(name, size, remove)
      return row
    }))
    this.chosenTarget.hidden = files.length === 0
  }
```

(The "×" is a character in a label-bearing button, as the toast's dismiss is; if the handoff's `x` icon is in the icon partial by now, the server can render the row's remove button into a `<template>` for the script to clone.)

- [ ] **Step 6: Reading a file.** Route, in the notes scope: `get "files/:id", to: "note_files#show", as: :record_note_file, constraints: { id: /\d+/ }`.

`app/controllers/admin/note_files_controller.rb`:

```ruby
module Admin
  # A note's file (notes spec D15, §3.6): the ONLY way one is read. Active
  # Storage's own read URLs are public to whoever holds one and do not expire
  # (`config/initializers/active_storage_access.rb`); a note's file may be
  # confidential, so no such URL is ever written into a page, and the bytes
  # are sent from here, after the same lookup as every notes request.
  #
  # It takes the id of an ATTACHMENT -- of a message, of a thread, of the
  # container the viewer may read -- never a blob's key or signed id, so it
  # can't be turned into a way to read any other upload: a library image's
  # attachment id, or a file of another record's note, is not found.
  #
  # `nosniff` always. Only the four image types are answered inline (the
  # thread shows them in an `<img>`); anything else is a download, whatever
  # the stored type says. Never cached by anything shared.
  class NoteFilesController < BaseController
    include NoteContainer

    def show
      attachment = ActiveStorage::Attachment.where(record_type: "Notes::Message", name: "files",
        record_id: Notes::Message.where(thread_id: container_threads.select(:id)).select(:id)).find(params[:id])
      blob = attachment.blob
      inline = Notes::Files.image?(blob.content_type)

      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Cache-Control"] = "private, no-store" # i18n-ok: an HTTP header's name and its directives, not copy
      send_data blob.download, filename: blob.filename.to_s, type: (Notes::Files::ALLOWED.key?(blob.content_type) ? blob.content_type : "application/octet-stream"),
        disposition: inline ? "inline" : "attachment"
    end
  end
end
```

- [ ] **Step 7: Showing them.** In `Notes::Listing#load`: `includes(messages: [ :reactions, { files_attachments: :blob } ])` (two more queries, constant). `files_component.rb`:

```ruby
module Admin
  module NotesScreen
    # A message's files (notes spec §3.6, handoff "Attachment row", "Inline
    # image and still GIF tile"). An image is shown inline at the message's
    # width, through the notes file action, and a click opens the same URL in
    # a new tab (there is no lightbox). Anything else is a row with its name,
    # its kind and size, and a download. Every URL here is
    # `admin_record_note_file_path`: never a blob URL (decision D15).
    #
    # A GIF moves, so with reduced motion it does not play by itself: the tile
    # holds no `<img>` until Play is pressed (`admin--note-gif`). Without
    # variants there is no still first frame to show; the tile says what it
    # is instead.
    class FilesComponent < Admin::AdminComponent
      def initialize(message:, listing:, type:)
        @message = message
        @listing = listing
        @type = type
      end

      def render? = attachments.any?

      private

      def attachments = @message.files.attachments

      def path(attachment) = helpers.admin_record_note_file_path(*helpers.note_args(@listing.container), attachment.id)

      def image?(attachment) = ::Notes::Files.image?(attachment.blob.content_type)

      def gif?(attachment) = attachment.blob.content_type == "image/gif"

      def facts(attachment)
        size = helpers.number_to_human_size(attachment.blob.byte_size) # i18n-ok: a byte size ("1.2 MB"), its units from Rails' own locale data
        [ ::Notes::Files::ALLOWED.fetch(attachment.blob.content_type, t(".file")), size ].join(" · ")
      end
    end
  end
end
```

`files_component.html.erb`:

```erb
<div class="flex flex-col gap-2" data-note-files>
  <% attachments.each do |attachment| %>
    <% name = attachment.blob.filename.to_s %>
    <% if gif?(attachment) %>
      <%= tag.div class: "relative overflow-hidden border border-line", data: { note_gif: true, controller: "admin--note-gif", "admin--note-gif-src-value": path(attachment), "admin--note-gif-alt-value": name } do %>
        <%= image_tag path(attachment), alt: name, loading: "lazy", class: "block max-w-full motion-reduce:hidden", data: { "admin--note-gif-target": "moving" } %>
        <div class="hidden min-h-24 flex-col items-center justify-center gap-2 bg-sunken p-3 motion-reduce:flex" data-admin--note-gif-target="still">
          <%= render Admin::ButtonComponent.new(label: t(".play"), variant: :secondary, size: :small, type: "button", data: { action: "admin--note-gif#toggle", "admin--note-gif-target": "button", play: t(".play"), pause: t(".pause") }) %>
        </div>
        <span class="absolute bottom-1.5 left-1.5 font-cs-mono text-[10px] text-dim"><%= t(".gif", name: name) %></span>
      <% end %>
    <% elsif image?(attachment) %>
      <%= link_to path(attachment), target: "_blank", rel: "noopener", class: "block", data: { note_image: true, turbo: false } do %>
        <%= image_tag path(attachment), alt: name, loading: "lazy", class: "block max-w-full border border-line" %>
      <% end %>
    <% else %>
      <%= link_to path(attachment), class: "flex items-center justify-between gap-2.5 rounded-cs border border-line py-1.5 pl-2.5 pr-1.5 no-underline hover:bg-sunken",
            data: { note_file: true, turbo: false }, download: name do %>
        <span class="flex min-w-0 flex-col">
          <span class="truncate text-[13px] text-ink"><%= name %></span>
          <span class="font-cs-mono text-[10px] text-meta"><%= facts(attachment) %></span>
        </span>
        <span class="sr-only"><%= t(".download") %></span>
      <% end %>
    <% end %>
  <% end %>
</div>
```

`app/javascript/controllers/admin/note_gif_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// A GIF in a note with reduced motion on (notes spec §4.5): it does not play
// by itself. The stylesheet hides the moving image and shows the still tile
// (`motion-reduce:`); Play shows the image, Pause hides it again. Without
// reduced motion this does nothing: the image plays, the tile is hidden.
export default class extends Controller {
  static targets = [ "moving", "still", "button" ]

  toggle() {
    const playing = this.movingTarget.classList.toggle("motion-reduce:hidden") === false
    this.buttonTarget.textContent = playing ? this.buttonTarget.dataset.pause : this.buttonTarget.dataset.play
    this.stillTarget.classList.toggle("absolute", playing)
    this.stillTarget.classList.toggle("bottom-1.5", playing)
    this.stillTarget.classList.toggle("right-1.5", playing)
    this.stillTarget.classList.toggle("min-h-24", !playing)
  }
}
```

In `message_component.html.erb`, after the body and before the reactions: `<%= render Admin::NotesScreen::FilesComponent.new(message: message, listing: listing, type: type) %>`.

- [ ] **Step 8: The strings.** Under `en.admin.notes.errors`: `files: { too_many: "A note can carry at most %{count} files.", too_big: "%{name}: files can be at most 10 MB.", type: "%{name}: this type of file can't be attached." }`; under `en.admin.notes.script`: `files: { too_many: "A note can carry at most %{count} files.", too_big: "%{name} is over 10 MB.", remove: "Remove %{name}" }`; under `en.admin.components.notes_screen`: `composer: { attach: "Attach files", attach_title: "Attach up to 5 files, 10 MB each", attach_again: "Attach the files again: a browser does not keep them." }` (merge) and `files: { file: "File", download: "Download", play: "Play", pause: "Pause", gif: "GIF · %{name}" }`. Add `paperclip` to the icon partial as `smile` was. Add the new files to `CONVERTED`.

- [ ] **Step 9: Run.**

```bash
PGGSSENCMODE=disable bin/rails test test/models/notes test/services/notes test/integration/admin test/lib
bin/brakeman
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/note_composer_test.rb test/system/admin/notes_live_test.rb
```

`bin/brakeman` must exit 0 with `config/brakeman.ignore` still empty: `send_data` here sends a blob found through the scope, by an integer id.

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat: files on a note — typed by their bytes, five of ten megabytes, read only through the notes action" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---
### Task 17: The whole flow in a browser, the documentation, and the full verification

**Spec:** §8 (System), §10 (Documentation), §6.5 (Deployment), §11. **Read first:** `CLAUDE.md` (how a rule and a reference entry are worded), `docs/reference/save-rule-and-write-queue.md`, `docs/reference/access-control-and-audit.md` (the density of a reference file), `docs/roadmap.md`.

**Files:**
- Create: `test/system/admin/notes_flow_test.rb`, `docs/reference/notes.md`
- Modify: `CLAUDE.md`, `docs/reference/design-system.md`, `docs/reference/save-rule-and-write-queue.md`, `docs/reference/access-control-and-audit.md`, `docs/reference/trash.md`, `docs/reference/cs-studio-shell-and-dashboard.md`, `docs/reference/media.md` (one paragraph each), `docs/superpowers/specs/2026-10-09-notes-on-content-design.md` (status line), `docs/roadmap.md` (alone, last)

**Interfaces:**
- Consumes: everything above, as built. Where the code differs from this plan, the documentation follows the code.

- [ ] **Step 1: The flow, end to end.** `test/system/admin/notes_flow_test.rb`:

```ruby
require "application_system_test_case"

# Notes from one person to another and back (notes spec §8, System), and the
# two places the feature must not disturb: the keyboard, and the write queue.
class Admin::NotesFlowSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
  end

  test "a question on a block reaches a colleague's inbox, is answered, resolved, reopened and pinned" do
    sign_in_via_form(users(:one))
    editor
    within("##{ActionView::RecordIdentifier.dom_id(@block)}") do
      find("button[aria-label='Block actions']").click
      press "Add note"
    end
    field = find("#notes-new textarea[name=body]")
    field.send_keys("Is this still right, @Dan")
    assert_selector "#notes-new [role=option]", text: "Dana"
    field.send_keys(:enter, "?")
    within("#notes-new") { press "Add note" }
    assert_selector "#notes-drawer [data-note-thread] [data-note-mention]", text: "@Dana"
    thread = Notes::Thread.last

    using_session(:dana) do
      sign_in_via_form(users(:two))
      visit "/cs-studio"
      await_admin_controllers
      assert_selector "#sidebar-badge-dashboard", text: "1"
      find("turbo-frame#notes-for-you [data-delivery] a", text: "one@example.com mentioned you").click

      assert_selector "#notes-drawer #note-thread-#{thread.id}", text: "Is this still right"
      find("#note-thread-#{thread.id}-reply textarea[name=body]").send_keys("Yes, checked today")
      within("#note-thread-#{thread.id}-reply") { press "Reply" }
      assert_selector "#note-thread-#{thread.id}-messages [data-note-message]", count: 2

      within("#note-thread-#{thread.id}-reply") { press "Resolve" }
      assert_selector "#note-thread-#{thread.id}[data-state=resolved] [data-note-badge=resolved]", text: "Resolved by Dana"
      assert_no_selector "#notes-open-count"

      within("#note-thread-#{thread.id}-reply") { press "Reopen" }
      assert_selector "#note-thread-#{thread.id}[data-state=open]"
      within("#note-thread-#{thread.id} [data-note-actions]") { press "Pin" }
      assert_selector "#note-thread-#{thread.id} [data-note-badge=pinned]"
      find("#notes-drawer a[data-note-back]").click
      assert_selector "#notes-pinned a#note-row-#{thread.id}"
    end

    assert_equal [ "open", true, 2 ], thread.reload.then { |record| [ record.state, record.pinned, record.messages.count ] }
    assert_equal %w[note.started note.replied note.resolved note.reopened note.pinned], Audit::Event.where(subject_type: "ContentBlock", subject_id: @block.id).order(:id).pluck(:action)
  end

  test "the drawer by keyboard alone: open, start a note, send it, go back, close" do
    sign_in_via_form(users(:one))
    editor

    find("#notes-open").send_keys(:enter)
    assert_selector "#notes-drawer #notes-list"
    find("#notes-drawer button", text: "New note").send_keys(:enter)
    assert_eventually(message: "the new note's field never took the focus") { page.evaluate_script("document.activeElement.name") == "body" }
    page.driver.browser.keyboard.type("A note without a mouse")
    find("#notes-new textarea[name=body]").send_keys([ :control, :enter ])

    assert_selector "#notes-drawer [data-notes-view=thread]", text: "A note without a mouse"
    assert_eventually(message: "the thread never took the focus") { page.evaluate_script("document.activeElement.closest('#notes-drawer') !== null") }
    find("#notes-drawer a[data-note-back]").send_keys(:enter)
    assert_selector "#notes-list a[data-note-row]"
    find("#notes-list a[data-note-row]").send_keys(:escape)

    assert_no_selector "#notes-drawer"
    assert_equal "notes-open", page.evaluate_script("document.activeElement.id")
  end

  # Review Focus 4.
  test "a note sent while an autosave is on the wire goes after it, once, and moves no base" do
    sign_in_via_form(users(:one))
    editor
    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__held = []
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET" || window.__released) return originalFetch(url, options)
        return new Promise((resolve) => { window.__held.push(() => resolve(originalFetch(url, options))) })
      }
      window.__release = () => { window.__released = true; window.__held.forEach((go) => go()) }
    JS
    find("##{ActionView::RecordIdentifier.dom_id(@block)} [contenteditable=true]").send_keys("An edit on its way")
    await_js("window.__held.length === 1", wait: 8)

    find("#notes-new textarea[name=body]").send_keys("Written while saving")
    within("#notes-new") { press "Add note" }
    await_frames
    assert_equal 0, Notes::Thread.count # held behind the save, not sent beside it

    page.execute_script("window.__release()")

    assert_selector "#notes-drawer [data-notes-view=thread]", text: "Written while saving"
    assert_writes_settled
    assert_equal 1, Notes::Thread.count
    block_base = find("#block-#{@block.id}-base-updated-at", visible: :all).value
    assert_equal @block.reload.updated_at.iso8601(6), block_base
    assert_no_selector "[data-save-state=stale]", visible: :all
    find("##{ActionView::RecordIdentifier.dom_id(@block)} [contenteditable=true]").send_keys(" and one more")
    assert_writes_settled
    assert_equal 0, Audit::Event.where(action: "access.denied").count
  end

  # Spec §8, System: "attach an image and a PDF; react".
  test "a note carries an image and a PDF, and takes a reaction" do
    sign_in_via_form(users(:one))
    editor
    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    pdf = Tempfile.new([ "report", ".pdf" ], binmode: true).tap { |file| file.write("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".b); file.close }
    find("#notes-new input[type=file]", visible: :all).set([ file_fixture("tiny.png").to_s, pdf.path ])
    assert_selector "#notes-new [data-admin--note-composer-target=chosen] li", count: 2
    find("#notes-new textarea[name=body]").send_keys("Two files")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-note-files] a[data-note-image] img[alt='tiny.png']"
    assert_selector "#notes-drawer [data-note-files] a[data-note-file]", text: /report.*\.pdf/
    assert_equal %w[application/pdf image/png], Notes::Message.last.files.map(&:content_type).sort

    find("#notes-drawer details[data-reaction-add] summary").click
    find("#notes-drawer details[data-reaction-add] button[value='👍']").click
    assert_selector "#notes-drawer button[data-reaction='👍'][data-mine]", text: "1"
    assert_equal [ [ users(:one).id, "👍" ] ], Notes::Reaction.pluck(:user_id, :emoji)
  end

  test "a view-only reader writes a note and can change nothing else" do
    sign_in_via_form(users(:reader))
    editor
    assert_selector ".admin-view-only", visible: :all

    find("#notes-open").click
    within("#notes-drawer") { press "New note" }
    find("#notes-new textarea[name=body]").send_keys("From a reader")
    within("#notes-new") { press "Add note" }

    assert_selector "#notes-drawer [data-notes-view=thread]", text: "From a reader"
    assert_no_selector "#notes-drawer [data-note-actions] button", text: "Pin"
  end
end
```

(The block's autosave goes through `window.fetch` as `test/system/admin/sections_test.rb`'s `hold_first_save` relies on; a note's form goes through Turbo, which the write queue holds while a save is outstanding. If the status line marks a refused save differently from `[data-save-state=stale]`, assert that file's own marker for "CHANGED ELSEWHERE" is absent. `page.driver.browser.keyboard.type` is Cuprite's; if the suite types another way into the focused element, use that.)

Run it: `bin/rails tailwindcss:build && PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system test/system/admin/notes_flow_test.rb`. A failure here is a bug in an earlier task: fix it there, with its own `fix:` commit.

- [ ] **Step 2: Commit the flow test.**

```bash
git add test/system/admin/notes_flow_test.rb
git commit -m "test: notes from one person to another and back, by keyboard alone, and beside an autosave" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 3: The reference.** Create `docs/reference/notes.md` in the reference files' own style (a `> Describes:` line, then `##` parts of dense paragraphs that name the classes and record why). Parts, each from the code as built:
  - **What a note is**: the five tables and their keys; subject and container and why the container is derived; what cascades and what is nullified; the token and `Notes::Mentions` (the composer's names map and why it is not trusted); `Notes::Text`.
  - **Who may do what**: notes follow the content (the two key tables of `Notes`), `readable?`, `moderator?`, the uploader rule; lookups through `Admin::NoteContainer` and why a thread is never found by its id; the mention picker and why it is not a directory (six rows, readers only).
  - **The services**: one line each for the twelve; the lock order (`lock_container` first, the same first lock as a page's blocks) and what it guarantees `Notes::Remove`; "a note never writes the record it is on"; following and deliveries (`Notes::Deliveries`: the rules, the reused row and why); the pin rule; `Notes::SetFollowing` and why it is not named `Notes::Follow`; what is audited, with what subject, and that no text or file name is ever in an event; `NOTE_VERBS`, `NOT_A_CHANGE`, the dashboard's two actions; the contract's `control_unaudited`.
  - **Removal**: who calls `Notes::Remove`, with what `with:`, in how many statements, and the boundary test.
  - **The frame**: the stable ids table of this plan, copied; the two views; redirects and failed forms (`failed`); counts and how "unread for you" turns one accent; the listing's query count.
  - **The drawer and the markers**: `admin--notes` on `<body>` and why; when to use which of the shell's drawers, the media panel and this drawer; counts filled by the script and why the server never renders one into a card; a selection's quote; the delete warning; the active block; the composer (drafts, the send key, the picker); the mind graph's badge and card.
  - **The inbox**: the two queries, the route a row carries, the sidebar's badges.
  - **Live delivery**: the two streams, the payloads and the rule "ids only" with its test; the subscribe-time check; `origin` and `X-Notes-Tab`; how each view is refreshed without touching typed text; coalescing; reconnect; the toast; the chime and the one-tab agreement; the desktop notification and the three permission states; that the consumer is turbo-rails' own and only CS Studio asks for it; the system tests' switch to the `async` adapter; **deployment** (spec §6.5: the `cable` database exists and is migrated, the proxy passes WebSocket upgrades on `/cable`), and that Turbo's morphing refresh stays off.
  - **Files**: the allowed types and the sniff, the text rule, why legacy Office formats are out; the limits; the one action that reads a file and what it refuses; headers; that no Active Storage URL of a note's file is ever rendered, with the test; purge on delete and on removal; GIFs and reduced motion.
  - **What is not built**, pointing at the roadmap rows of Step 6.

  One paragraph in each of: `design-system.md` (the notes drawer among the patterns; accent means "unread for you"), `save-rule-and-write-queue.md` (note forms are frame-level Turbo forms in `#notes`: held only while a save is outstanding, they send no base and replace no editor form; the live refresh touches only the notes parts), `access-control-and-audit.md` (the note events and their subject; `Notes::` services in the contract; `control_unaudited`), `trash.md` (a trashed record keeps its notes; a purge calls `Notes::Remove`), `cs-studio-shell-and-dashboard.md` (the two dashboard cards, the sidebar's badges, the mind graph's badge and card), `media.md` (the panel's Notes section, the tile's chip, and that a note's files are not library images).

- [ ] **Step 4: `CLAUDE.md`.** In the reference index: "Before changing notes, their drawer, the inbox, live delivery or a note's files (`app/models/notes/`, `app/services/notes/`, `app/queries/notes/`, `app/channels/notes/`, `app/components/admin/notes_screen/`, `app/javascript/controllers/admin/notes*_controller.js`, `note_*_controller.js`), read `docs/reference/notes.md`." In "Rules a change can break silently", in the list's wording:
  - A note never writes the record it is on: no `touch`, no `updated_at`, no content version; an autosave base is never moved by a note (`test/services/notes/start_test.rb`).
  - A note's text, quote and file names never reach the audit log, a log line or a pushed signal: a note event's subject is the content record, `snapshot: nil`, metadata ids only (`test/services/notes/`, `test/models/notes/signals_test.rb`).
  - A pushed signal carries a kind and ids only, and every part it refreshes is fetched through the read scope; `Notes::RecordChannel` looks its container up through that scope at subscribe time.
  - A note's file is read only through `Admin::NoteFilesController`, by attachment id among the container's threads; no Active Storage URL of one is ever rendered (`test/integration/admin/note_files_test.rb`).
  - Whoever deletes a page, post, image or block for good calls `Notes::Remove` in its transaction; those two call sites are the only references to `Notes::` from the content models and services (`test/lib/notes_boundary_test.rb`).
  - A thread is never found by its id alone: the container first, through `Admin::NoteContainer`, then the thread among that container's.
  - A new list or count of notes narrows through `Notes.readable_threads` or over rows the read scope already narrowed, and belongs in `test/integration/trash_visibility_test.rb`.

  In "Key Conventions", extend the namespace sentence: **`Admin::Notes` and `Admin::Note`** would shadow `Notes::`; the notes components live under `Admin::NotesScreen::`. In "Pitfalls", under "The write queue", add: "Notes are refreshed part by part for the same reason (`docs/reference/notes.md`, "Live delivery"): no `turbo_refreshes_with`, no `broadcast_refresh`." In the system-test paragraph, add that a test of live delivery switches the cable to the `async` adapter and back (`test/system/admin/notes_live_test.rb`) and that a notes system test clears `localStorage["cs-notes-open"]` in its teardown. Set the spec's status line to "**Status: built** (plan `docs/superpowers/plans/2026-10-09-notes-on-content.md`)."

- [ ] **Step 5: Commit the documentation, without the roadmap.**

```bash
git add CLAUDE.md docs/reference docs/superpowers/specs/2026-10-09-notes-on-content-design.md
git commit -m "docs: notes — the reference, the rules a change can break silently" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 6: The roadmap, alone.** Another session may be editing `docs/roadmap.md`: run `git fetch origin main`, re-read the file as it is on disk immediately before editing, change only what is named here, and commit it by itself.
  - "Collaboration on content": step 1, notes with live delivery, is shipped (in the file's own way of marking, with one line saying what it is); step 2 is presence alone; steps 3 and 4 as they were. The "Workspaces" row's note already points at "the comments … of collaboration": make it say notes.
  - "Before the first deploy": the `cable` database exists and is migrated; the proxy passes WebSocket upgrades on `/cable` (spec §6.5).
  - New rows, in "Collaboration" (all Could unless the file's own judgement says otherwise): GIF search behind a key (D11); mail for a mention and per-person mail settings; following a whole page or post; notifications with no tab open (a service worker and web push); a sound or a desktop notification for more than a mention; an anchored highlight in the text (D4, with step 4); notes on tags, users or settings and on several records (D5); MCP tools for notes (the services take any actor); notes on one language version of a record; assigning a thread, due dates and "review requested" (with "Publishing workflow"); a separate permission for notes (D3). And the gaps this plan leaves, each one row: legacy Office files (.doc, .xls, .ppt) are refused; a GIF's still tile has no first frame; a reopen's inbox row names nobody; the media grid's picker shows no note counts; the posts list, the page tree and the media grid are not live; a section block itself has no notes opener; a thread deleted in another tab is announced in an open thread view but an open edit form's text is kept only until the view is left.

```bash
git add docs/roadmap.md
git commit -m "docs: the roadmap — notes with live delivery shipped, presence is step 2, what notes leave open" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 7: The full verification.** No other test runner may be active on this machine. In order, each must exit 0:

```bash
bin/rubocop
bin/brakeman
bin/rails zeitwerk:check
bin/importmap audit
bin/bundler-audit
PGGSSENCMODE=disable bin/rails test
bin/rails tailwindcss:build
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system
```

  `config/brakeman.ignore` stays empty. For a failure or error in the system run: name the test, run it alone several times, say whether it is deterministic and whose it is; never report "a re-run was clean" without the name. Then, in a browser against a development server started from this worktree on a free port (not the server running from the other checkout), signed in as two people in two browser profiles: start a note on a block with a mention and a file; see it arrive in the other profile (badge, toast, chime after a click); answer, resolve, reopen and pin; react; open the page at 900px of width (the sheet) and in the dark theme; turn the desktop notification on and allow it; and say in the report what was seen, compared with the handoff part by part.

- [ ] **Step 8: Commit whatever the verification made you fix**, one `fix:` commit per finding, each with the two trailer lines.

---
## Decisions the plan made

Where the spec and the handoff are silent, with one line of reasoning each.

| # | Decision | Why |
|---|---|---|
| P1 | A refusal (`access.denied`) names the **container**; a note's own events name the content record the thread is on. | The right that was missing is the container's; the record's Activity is where a note's history belongs. |
| P2 | Editing someone else's message is `denied` against the read key with its own sentence, like `Users::UpdateProfile`'s "only yourself" rule. | No permission grants it, but a forged attempt should leave its one `access.denied` and answer 403. |
| P3 | `mentioned_user_ids` is `bigint[]` and is derived by the model before validation. | User ids are bigint; a column the text can't disagree with needs no service to remember it. |
| P4 | The textarea shows `@Dana Smith`; a hidden `mention_names` map (name → id) rides along and the controller turns names into `@[id]` tokens. The map is trusted for nothing else. | A textarea can't show a name for a token; the service still checks every resulting id. |
| P5 | The mention picker judges the 40 best matches one by one and answers six. | The read right has no SQL form across users; 40 bounded checks keep it honest and cheap. |
| P6 | `Notes::Start` refuses a trashed container ("in the trash or was deleted"); every notes transaction takes the container's row lock first, read through `kept`. | One lock, the same first lock as a page's blocks, is what lets `Notes::Remove` never miss a thread. |
| P7 | A reply to a resolved thread records `note.replied` and `note.reopened`; its followers get the `reply` row only. | The log should show the state changed; the inbox should say it once. |
| P8 | `notes.removed` is recorded only when something was removed, with `thread_ids` in its metadata. | Otherwise every block delete would add an event; ids are not text (D14). |
| P9 | `Notes::Remove.call(record, with: [...])` authorizes what its callers did (the delete right or `trash.empty`; a block: the page's edit right) and is called once per purge or delete. | The contract needs a real refusal; one call keeps the statements constant. |
| P10 | `Notes::MarkRead` takes `thread:`, `container:` or neither. Opening a **thread** marks that thread's deliveries; the list marks nothing. | The design's list shows "new" on a row, which reading the list must not clear. |
| P11 | A thread that is gone answers the list with a sentence (`?notice=gone`), never a 404 inside the drawer. | The thread and its subject no longer exist, so the kind of record can't be named. |
| P12 | Counts in block cards and tiles are filled by `admin--notes` from one payload; the server renders counts only where a row is drawn once (header, lists). | A card is drawn by many streams; none of them should cost a count query or go stale. |
| P13 | `admin--notes`, `admin--notes-live` and `admin--notes-alert` live on `<body>`. | Openers, markers, the drawer and the toast region are far apart and come and go by stream, as with `admin--dialog`. |
| P14 | The new-note field is drawn for `?compose=<key>` (what "New note" and a block's "Add note" request), not as a third frame view. | One list view with an optional field keeps a failed submit and a live refresh simple. |
| P15 | A message's Edit and Delete are `<details>` in place (Delete asks "Delete this note?" inline), not a menu plus a dialog. | A dialog per message would sit inside the drawer's frame; the handoff's ⋯ menu can replace the disclosure's look without changing the forms. |
| P16 | The reaction set opens from a `<details>` per message; no script. | The thread view shows one thread, so the markup stays small. |
| P17 | A record's signal carries `origin`, the opaque id a tab sends as `X-Notes-Tab`. | "Its own author's tab ignores the signal" (§6.1) needs the tab named; an id the tab made up is no content. |
| P18 | The cable consumer is the one bundled in turbo-rails (`cable.subscribeTo`); no import-map pin is added. | Nothing new to audit or preload; only an admin controller asks for it. |
| P19 | The toast is `Admin::ToastComponent` (`:undo` kind, 8 s) cloned from a layout `<template>`, its "Open" a GET form filled by the script. | The existing component and timing, as the spec asks, with no new toast variant. |
| P20 | One tab alerts: claims over `BroadcastChannel`, 150 ms, then a "done" every other tab honours. | A late copy of the signal in another tab must not chime twice. |
| P21 | `Users::UpdateNotifications` is a `SELF_SERVICE` like `Users::UpdateProfile` and records `user.updated`. | "Saved from the account screen through a service like the name is" (§3.1). |
| P22 | Legacy Office files (.doc, .xls, .ppt) are refused; text and CSV are accepted by content (valid UTF-8, no control bytes), their name only picking the label. | Marcel has no signature for text and one shared signature for legacy Office; guessing from a name is what the spec forbids. |
| P23 | A GIF's reduced-motion tile shows no first frame. | There are no variants for a note's file (§3.6); the tile names the file and offers Play. |
| P24 | The media picker's tiles show no note counts; a section block itself has no notes opener. | Choosing an image is not reading about it; the spec gives a section header no marker, so notes go on its blocks or the page. |
| P25 | A reopen's inbox row names nobody ("A note was reopened"). | The thread records who resolved it, not who reopened it; a column for that is not in §3.1. |
| P26 | The mind graph card posts with `fetch` and reads JSON from `GET …/threads`; a new note there carries `view=mind_graph`. | The card is built in the browser with `textContent` only. |
| P27 | Note counts for a list are read in two queries per surface (the count, and "unread for you" beside it). | §4.5 allows "the same grouped query or one beside it"; two simple queries are easier to pin than one with a filtered aggregate. |

## Spec conflicts found

Each is resolved by the reading that keeps the spec's intent; the owner can overrule any of them.

| # | The spec says | The conflict | The plan does |
|---|---|---|---|
| C1 | §3.1: `note_follows` is `Notes::Follow`; §3.5: the service `Notes::Follow` follows or unfollows. | One constant can't be a record and a service. | The record is `Notes::Follow`; the service is `Notes::SetFollowing`. |
| C2 | §3.3: a resolve or a reopen tells each follower "with the thread's first message as `message_id`"; and "at most one row per person per message" (the unique index). | A follower mentioned in the first message, or told of an earlier resolve, already has that row. | The row is reused: it takes the new reason and becomes unread again (`Notes::Deliveries.write`). |
| C3 | §3.4: editing and deleting your own message "are self-service services (`SELF_SERVICE`)"; and "the services take any actor, so a later MCP tool needs no change". | `SELF_SERVICE`'s contract includes "a token of the record's own user is refused", and its meaning is "open to any signed-in user", while these need the read right. | `Notes::EditMessage` and `Notes::DeleteMessage` are ordinary contract entries (refused for the read right; the control runs as the author); "only the author edits" and "a moderator may delete, never edit" are pinned in their own tests. |
| C4 | §3.5: `Notes::React`, `Notes::MarkRead` and `Notes::Follow` are not audited. | `service_behaviour_contract_test.rb` requires every allowed call to record an audit event. | A factory option `control_unaudited: "<reason>"`, under which the control must record **nothing** (Task 3). |
| C5 | §6.5: "in development and in tests the async adapter runs in the server's own process." | `config/cable.yml` gives the test environment the `test` adapter, which the channel and broadcast tests need. | `cable.yml` is left alone; the live system tests switch to `async` in their setup and back in their teardown (Task 13). |
| C6 | §8: "every drawer, list, count, file and JSON endpoint answers 404 for a record outside the scope." | §3.4 gates images with `require_permission("media.upload")`, which is the module's 403. | Pages and posts: 404. An image, for someone without the media right: 403, as `Admin::MediaController`; a trashed or missing image: 404. |
| C7 | §7: a reply to a thread whose block was deleted "fails with 'This block was deleted'". | The thread was removed with the block, so nothing says what it was on. | "This note is gone: it was deleted, or what it was on was." `Notes::Start` on a deleted block does say "This block was deleted." |
| C8 | Handoff, "Mention picker": typing "@" opens it; spec §3.2 (before its last change) required two typed characters. | The spec's amended text dropped the two characters and kept "not a directory". | The picker answers an empty query with the first six readers; it stays scoped to a record the asker may read. |
| C9 | Handoff, "Node card thread list" and "Media panel Notes section" describe a collapsed input that expands into the composer. | The spec gives the card "a field to start one" and the panel the frame's own list. | The card has a plain field (no mentions or files); the panel shows the list with "New note", which draws the full composer in place. The handoff's collapsed look can be applied to both without changing behaviour. |

## Self-review (run when the plan was written)

**Spec coverage.** §2 D1–D20: D1, D13 Tasks 1–3, 5; D2 Tasks 1, 11; D3 Tasks 1–3 (keys, moderation), 6 (picker), 17 (view-only); D4 Tasks 2, 8; D5 Task 1 (`SUBJECT_TYPES`); D6 Tasks 7, 8; D7 Tasks 1, 15; D8 Tasks 1, 5; D9, D15 Task 16; D10 Task 15; D11 Task 17 (roadmap); D12 Task 4; D14 Tasks 2–4, 12; D16 Tasks 12, 13; D17 Tasks 1, 3, 6; D18, D19 Task 14; D20 Global Constraints, Task 13. §3.1 Tasks 1, 14, 15. §3.2 Tasks 1, 2, 6. §3.3 Tasks 1, 3, 5 (read on open), 11. §3.4 Tasks 1–3, 5, 6. §3.5 Tasks 2–4, 15 (twelve services: Start, Reply, EditMessage, DeleteMessage, Resolve, Reopen, Pin, Unpin, SetFollowing, MarkRead, Remove, React), audit wording in each, exclusions in Task 2. §3.6 Task 16. §3.7 Tasks 2 (no write of the subject), 6, 17 (the queue). §4.1 Task 7. §4.2 Tasks 5, 6. §4.3 Tasks 7, 8. §4.4 Tasks 7 (post editor), 9, 10. §4.5 Tasks 5–11, 15, 16 through the handoff. §4.6 every task's locale step and `CONVERTED`. §5 Task 11. §6.1–§6.3 Tasks 12, 13; §6.4 Tasks 13, 14; §6.5 Task 17. §7: subject deleted (2, 6, 13), two resolves (3), a message deleted under a reply (2), access lost (1, 11), a user deleted (1, 15), a failed file (16), very many threads (5), unsent text (6), the two kinds of drawer (7), ⌘K (7), a follower who lost access (11, 12). §8: every bullet has a test in the task that owns the code; the two-session tests are Tasks 13, 14 and 17. §9: order (Global Constraints), counts (5, 9, 10, 11), file serving (16), the signal (12). §10 Task 17.

**Review Focus.** 1: Task 1 (`deliveries_test.rb`, the resolve and reopen test) and Task 3 (`thread_state_test.rb`). 2: Task 2 (`start_test.rb`) and Task 6 (`note_writes_test.rb`, the 422). 3: Task 2 (`reply_test.rb`), Task 4, Task 6 (the gone redirect), Task 13 (the deleted thread under a typed reply). 4: Task 17. 5: Task 16 (`files_test.rb`, `note_files_test.rb`).

**Names across tasks.** `Notes.key`, `read_key`, `moderate_key`, `readable?`, `moderator?`, `readable_threads` (Task 1) are used with those names throughout. `read_refusal`/`moderation_refusal` take a block that calls `authorize!` (Task 2) in every later service. `with_locked_thread`/`thread_answer` (Task 3) are used by Tasks 3 and 15. `Notes::Counts.for_container(container, user:)` returns `total`, `subjects`, `unread` (Task 5) and is what `admin--notes#refreshCounts` takes (Task 7) and `admin--notes-live` hands it (Task 13). `Notes::Listing.new(container, limit:, viewer:)` (Task 5) gains `moderator?`/`subject_by_key` (Task 6) and its preloads in Tasks 15 and 16. `render_list`/`render_thread`/`notes_path`/`thread_path`/`gone!`/`failed_form`/`failure_status` (Tasks 5, 6) are used by Tasks 10, 15, 16. The frame's views are `[data-notes-view=list|thread]`; the thread's parts `[data-note-part=messages|reply]` (Task 5) are what Task 13 replaces and keeps. `data-notes-key`, `data-has-notes`, `data-unread`, `data-notes-compose`, `data-notes-active` are set in Tasks 7 and 8 only. Route helpers are those of the "Stable ids" table plus `admin_change_record_note_thread_path`, `admin_record_note_messages_path`, `admin_record_note_message_path`, `admin_record_note_mentions_path`, `admin_record_note_threads_path` (Task 6), `admin_record_note_message_reactions_path` (15), `admin_record_note_file_path` (16), `admin_account_notifications_path` (14).

**Not verified when the plan was written; resolved since by reading the code** (the cross-task check below; each answer is also written where the task uses it):

- *Block-type labels.* "Rich text", "Image", "Post list", "Section" (`app/models/block_types/*.rb`, `t.label`); a block in a section's column is "%{type} · column %{column}" (`admin.components.editor_screen.panel_title.title`). The tests read them as written.
- *Mind graph test helpers.* `test/system/admin/mind_graph_test.rb` has `await_graph`, `click_node(id)`, `escape_on_canvas`, `screen_position(id)`, `pixel_at(x, y)`, `pin_pixel(post)` and `graph`; `test/queries/post_graph/global_test.rb` has `graph` and `relate(a, b)`. Task 10 uses exactly these.
- *The top bar's selector.* `button[aria-controls=sidebar]`, and the open panel is `#sidebar[data-open]` (Task 7).
- *The empty state's action slot.* `Admin::EmptyStateComponent` has `renders_one :action` (`with_action`), as Task 5 uses it.
- *Icons.* One partial, `app/views/admin/shared/_icon.html.erb`, a `case name` of inline SVGs that raises on an unknown name; none of the handoff's Lucide names is in it, so each is added as a `when :name` branch by the task that first draws it (Global Constraints; Task 6 adds `smile` and `at_sign`, Task 16 `paperclip`).
- *`ActiveRecord.after_all_transactions_commit` inside a transactional test.* The test's own transaction is not joinable, so it does not count as open: a block registered inside a service's `transaction(requires_new: true)` runs when that savepoint is released, and is dropped when it, or a joinable transaction around it, rolls back; called with no service transaction open it runs at once. `Audit.record` already relies on this. The broadcast tests of Task 12 therefore need nothing beyond `ActionCable::TestHelper`, and "nothing is sent for an action that is rolled back" is a real test.
- *`/cable` in system tests.* Mounted by `action_cable/engine` as an internal route ahead of the app's catch-alls; the connection identifies the user from the signed session cookie; an origin equal to the request's host is allowed by default. The suite's `test` adapter is `ActionCable::SubscriptionAdapter::Test < Async`: it delivers to in-process subscribers like `async` and also records what was sent. The switch to `async` that decision C5 makes in `notes_live_test.rb` is therefore harmless and not needed (see "Gaps left for the owner").
- *Pinned statement counts.* No existing test pins an absolute number that a step here changes: the tests of the posts list, the tree, the media grid, the graph, the groups and audit screens compare two runs; the purge and destroy tests assert the order of statements and count only page locks and block updates. Tasks 4, 9, 10 and 11 say so where they used to say "raise the number".

## Cross-task interface check

Run after the plan was written, by one reader over all seventeen tasks, with the code of this branch open (commit `5c9aaf38`). For every pair of tasks that share a class, a method, a route helper, a DOM id, a `data-` attribute, a Stimulus name, a locale key or a column: what the producing task says against what the consuming task's code and tests use. Rows that agreed are counted per pair; every row that was changed is written out.

**Agreed as written**

| Producer → consumer | Shared things checked | Agreed |
|---|---|---|
| 1 → 2 | `Notes.container_for`/`read_key`/`moderate_key`/`readable?`, `Mentions.ids`, `Message::MAX_BODY`, `Thread::MAX_QUOTE`/`ORIGIN_VIEWS`, `Deliveries.for_new_message`/`for_edit`, `first_message` | 10 |
| 1 → 3 | `Deliveries.for_state`, `Notes::Follow` (record), `Delivery.unread`, `open?`/`resolved?`/`pinned?` | 6 |
| 2 → 3 | `read_refusal`, `moderation_refusal`, `lock_container`, `gone`, `note_metadata`, `NOTE_VERBS`, `Dashboard::Activity::ACTIONS`' `"note"` entry, `note_on`, `admin.notes.errors.*` | 9 |
| 2, 3 → 4 | `NOTE_VERBS`, `note_on`, `trashed`, the contract floor (37, 43, 44, then 45 and 46 in Tasks 14 and 15), `Notes::Thread` | 5 |
| 1–3 → 5 | `Notes.key`, the thread scopes, `messages` order, `Delivery.unread`, `Notes::Follow`, `MarkRead.call(thread:)`, `Mentions.display`, `Text.parts`, `Notes::Pin`/`Resolve` | 9 |
| 5 → 6 | `note_args`, `note_view`, `note_frame_params`, `notes_path`, `thread_path`, `render_list`, `render_thread`, `container_threads`, `Listing#find`/`users`/`following?`, the `failed` keys, `#notes-new`, `a[data-note-new-link]`, the four route helpers | 14 |
| 5, 6 → 7 | `turbo-frame#notes`, `data-notes-view`, `data-notes-group`, `#notes-new textarea`, `CountsComponent.new(counts:, id:)`, the `counts` target, the counts' three keys, `admin_record_notes_path`, `?compose=`, `<src>/threads/<id>`, `a[data-note-back]` | 11 |
| 7 → 8 | the `marker` and `warning` targets, `hold`, `open`, `data-notes-key`, `data-notes-name`, `data-notes-compose`, `[data-notes-count]`, `[data-notes-selection]`, `#notes-counts`, the ids `blockKey` reads | 9 |
| 5, 7 → 9 | `Counts.by_container`, `Counts.unread_among`, `view=media`, `?notes=open`, `?thread=` | 5 |
| 5, 6 → 10 | `Listing#pinned`/`groups`/`open_count`/`users`/`unread?`, `admin_record_note_threads_path` (GET and POST), `failure_status`, `view=mind_graph`, `?notes=open&thread=` | 8 |
| 1, 3, 5, 7, 9 → 11 | `Notes.readable_threads`, `MarkRead.call`, `Mentions.display`, `Audit::Sentence.route_for`, `?notes=open&thread=`, `?selected=&thread=`, `Notes::Delivery` | 7 |
| 1–4 → 12 | `Deliveries.write`, the `record_event` line of each of the nine services, `Notes::Remove`'s read of the thread ids, `Current`, `Notes.key(type, id)` | 11 |
| 12 → 13 | the two channel names, `type`/`id`, the payload's five keys, `X-Notes-Tab`, `origin` | 8 |
| 5–11 → 13 | `[data-note-part]`, `data-note-message`, `#notes-new`, `[data-note-new-link]`, `#notes-resolved-section`, the `counts` target, `[data-notes-scroller]`, `refreshCounts`, `isOpen`, the frame's `src`, `#sidebar-badge-dashboard`, `#notes-for-you`, `#notes-open-threads`, `NotesForYou#find`, the `inbox_row` keys, the drawer's and `#media-notes`' attributes, `card_notes.js`' `load` | 17 |
| 13 → 14 | `admin--notes-live:delivery` and its eight detail keys, `<body>`, `#toasts`, the toast's sentence | 4 |
| 3, 5, 6, 12 → 15 | `with_locked_thread`, `thread_answer`, `control_unaudited`, `Signals.threads`, `Listing#load`, `Listing#users`, `gone!`, `failed_form`, `render_thread` | 9 |
| 2, 4, 5, 6, 12, 15 → 16 | `Start`'s and `Reply`'s signatures and `errors` line, `Remove`'s `ids`, `Listing#load`, `[data-note-toolbar]`, `failed_form`, the message's body/files/reactions order, `field_id` | 8 |
| all → 17 | `#notes-open`, `[data-note-actions]`, `[data-note-badge]`, `#notes-pinned`, `#note-thread-<id>-reply`, `#block-<id>-base-updated-at`, `[data-reaction]`, `details[data-reaction-add]`, `[data-note-files]`, `[data-delivery]`, `#sidebar-badge-dashboard`, `.admin-view-only` | 12 |

**Changed: a name or a shape that two tasks spelled differently**

| Tasks | The shared thing | The two spellings | What was done |
|---|---|---|---|
| 5, 12 | `Admin::NoteContainer`'s `included` block | Task 5: `included do … before_action :set_container; helper_method :note_view … end`. Task 12: "`included { before_action :set_container; before_action :note_tab }`", which read as a replacement drops `helper_method :note_view`, and the three notes views call `note_view`. | Task 12 Step 5 now adds one line to Task 5's block and says the helper stays. |
| 6, 16 | Where the composer's `messages_data(...)` call lives | Task 6: `ComposerComponent#script_messages`, on a line of its own (so `script_messages_test.rb` reads its keys). Task 16: "`form_data`'s `messages_data(...)` gains …". | Task 16 names `script_messages` and keeps the call ending its line. |
| 13, 10 | The Stimulus target on the mind graph card's section | Task 13's controller: target `record`, attribute `data-admin--notes-live-target`. Task 13's instruction for `card_notes.js`: `section.dataset.adminNotesLiveTarget = "record"`, which writes `data-admin-notes-live-target` (one dash): no target, so the card never subscribed. | `section.setAttribute("data-admin--notes-live-target", "record")`, with the reason beside it. |
| 5, 6 | How a block is named in "New note on …" | Task 5: `note_subject_name(record, container, type)`, plain text. Task 6: a rendered `PanelTitleComponent` (escaped markup) put into `t(".new_on_block", block: …)`, which the template escapes again; and a second copy of the label rule. | Task 6's `compose_title` calls Task 5's helper. Task 8's test ("New note on Rich text") is unchanged. |
| 7 (its own two halves) | The `admin--notes` actions | The drawer's template binds `turbo:before-fetch-request->admin--notes#leaving`; the Interfaces list of actions had no `leaving`. | Added to the list. |
| 8, 5, 7 | Files Task 8 changes | Step 7 edits `thread_component.html.erb` (Task 5's) and `notes_controller.js` (Task 7's) and adds `data-notes-subject` and `data-notes-active`; neither file was in Task 8's Files, neither attribute in its Produces. | Both added. |
| 10 (test and note) | The card heading's text in the system test | The test: `/2 open notes/i`. Step 7's note: "which is why the system test reads "2 OPEN NOTES"". | The note says what the test does. |
| 9, 11 | Where a test goes in `trash_visibility_test.rb` | Task 9: above the file's `private` line. Task 11: "Append", which is below it. | Task 11 says the same as Task 9; its helper goes below the line. |
| 7, 8, 13, 16, 17 against `test/application_system_test_case.rb` | `click_frame_link`, `press` | `click_frame_link` waits for the `turbo:load` of a visit promoted from `#content`; Task 7 used it for links inside `turbo-frame#notes`, which is never promoted (an 8-second failure). `press(label)` is `find(:link_or_button, label)`, by text; Tasks 8 and 17 pressed "Block actions" and Task 16 "Remove small.gif", which are `aria-label`s of buttons whose text is "⋯" and "×". | Plain clicks in Task 7; `find("button[aria-label='…']").click` in Tasks 8, 16 and 17; both rules are in Global Constraints now. |

**Changed: a task against itself or against the code it edits**

| Task | Defect | What was done |
|---|---|---|
| 4 | `Notes::Remove` was called after the pages were destroyed, and asks the purge's own right again. A `pages.delete` scoped to a branch is matched against the page's closure rows, which its destroy deletes: the check refused the person the purge had just allowed and rolled the purge back (closure_tree deletes the hierarchy rows in `before_destroy`, and `AccessControl::Checker.page_branch_ids` reads them). Read from the code, not run: no existing test purges as a branch-scoped user, so nothing would have caught it. | `Trash::Purge` calls it before it destroys anything (`ContentBlocks::Destroy` is unchanged: a block's right is its page's). A test with `users(:editor_branch)` pins it. |
| 4 | `ContentBlocks::Reorder` was called with a section record and `moved_from` keyed by a string with nils. | The call is `reorder_test.rb`'s own shape: the section's id, `moved_from: { id => { section_id: "", column: "" } }`. |
| 7 | "The list is where it was left": the test scrolled to 600, then clicked the LAST row natively, which scrolls it into view, so the position restored was not the one compared. | The list is scrolled to its end first, so the click moves nothing. |
| 13 | "A reply arrives … while a half-typed reply is kept" ended with "no toast, and the delivery is read", for a viewer who had no delivery: both lines passed with nothing tested. | The reply mentions the viewer, and the assertion needs a delivery that exists and is read. |
| 13 | The test's comment said the suite's `test` cable adapter "delivers nothing". It is `Test < Async` and delivers. | The comment says what is true and that the switch is decision C5's. |
| 14 | `await_js("true", wait: 1)` as a wait for "nothing more happens" returns at once. | The plan's own fallback, a `sleep` with its reason on the line. |
| 14 | The switch's class was `admin-switch`, which no stylesheet has. | `cs-toggle`, the class of the existing switch (`fields/boolean_field.html.erb`). |
| 14 | "If the `User` serializer lists its fields by name": it does. | The step says to add the two fields, and `app/models/audit/snapshot.rb` is in the Files. |
| 16 | `find(…).attach_file([ … ])` on the file field looks for a field inside it. | `find(…).set([ … ])`. |
| 16 | Three lines `test/lib/admin_i18n_test.rb` refuses in files that join `CONVERTED`: `number_to_human_size` (an English-making call), the literal "MB" on a `textContent` line, and the header name `"Cache-Control"` (only `Content-Type`, `Turbo-Frame` and `X-…` are known as headers). | Each carries `i18n-ok:` with its reason. |
| 7 | The controller's comment still described "the faint "add a note" mark" of the superseded design. | Reworded: nothing at rest, the control on hover or focus. |

**Added: a spec line that had no test which would fail without it**

| Task | Spec | Test added |
|---|---|---|
| 2 | §7, "A message deleted while someone replies" | `reply_test.rb`: the reply lands in a thread one of whose messages was deleted meanwhile. |
| 3 | §3.5, the feed gains `note.started` and `note.resolved` only | `activity_test.rb`: started and resolved are listed, on a block under its page; a reply is not. |
| 17 | §8, System: "attach an image and a PDF; react" | `notes_flow_test.rb`: one note with both files, then a reaction, in the drawer. |

**The edits inherited from the earlier, interrupted check** (183 lines added, 48 removed, uncommitted, by reviewers of separate task ranges) were each read against the code and against the other tasks. All were correct and are kept: the fold and origin test and `helper_method :note_view` (Task 5); the `i18n-ok` marker on `NotePathsHelper::TYPES`; the at-sign button, `script_messages`, `[data-note-toolbar]`, the icon partial's description and the removal of two duplicated methods (Task 6); the trash test written before the records are trashed, the tile's `tag.span`, `grid_streams`' unread read and the statement-count paragraph (Task 9); the `unread` key, the helpers the mind graph test really has, the three-row card, the badge test, `--cs-mono` and the route template built for id 0 (Task 10). Three of them left another task behind, which the first table above records: Task 12 (the `included` block), Task 16 (`script_messages`) and Task 10's own Step 7 (the heading's case).

## Gaps left for the owner

Not fixed here, because each is a decision or more than a small step.

1. **Decision C5 is not needed.** `ActionCable::SubscriptionAdapter::Test` is a subclass of `Async`: the suite's adapter already delivers to the system-test browsers. Swapping `ActionCable.server.config.cable` and restarting the server in `notes_live_test.rb`'s setup and teardown is harmless but is machinery with no effect, and the sentence Task 17 adds to `CLAUDE.md` about it would describe a rule nobody needs. Dropping the swap also removes the one place a notes test changes process-wide state under parallel workers.
2. **The look is checked by eye only.** The templates are a baseline (a "✎" for the handoff's message-square icon, "This page" where the handoff has "WHOLE PAGE", a text "Notes" column head where it has an icon, the media tile's chip beside the other chips where it has it on the image, the delete warning's wording). The plan tells each task to follow the handoff and Task 17 to compare part by part in a browser; no test pins a class, a size or an icon, and no task but 6 and 16 says which icon branches to add.
3. **The page tree's drawer.** Spec §7 names both shell drawers ("sidebar, page tree"); Task 7 tests the notes drawer against the sidebar only. Same mechanism (`admin--drawer:opened`), no test for the tree below 1024px.
4. **The chime for a thread that is showing.** A mention that arrives for the thread open in this tab raises no toast (§6.4) but still chimes and, with the tab unfocused, still notifies: `admin--notes-alert` does not read the event's `shown`. The spec is silent; say which is meant.
5. **A restored record's inbox rows.** Task 4 tests that threads survive the trash and a restore (D12); no test says that a delivery on a trashed record, hidden from the inbox meanwhile, is listed again after the restore. It follows from `Notes.readable_threads`, and nothing pins it.
6. **A route without a name.** Task 10's `get "threads", to: "note_threads#index"` has no `as:` (it shares `admin_record_note_threads_path` with the POST); Rails may name such a route from its path on its own. Harmless today; give it `as: nil` if a later `threads` route in the admin scope collides.
