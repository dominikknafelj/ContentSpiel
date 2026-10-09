# Notes on content

The first of four steps of "Collaboration on content" (roadmap, decided 2026-10-08): (1) notes, with live delivery — this spec; (2) presence; (3) live refresh of blocks changed by someone else, and edit reservations; (4) co-editing of rich text, only if 1–3 prove insufficient. Each step has its own spec, plan and PR. This is the binding spec for one implementation plan.

**Status: design, agreed with the user on 2026-10-09; amended the same day (live delivery, the mention sound, desktop notifications and following a thread moved into this step: D16–D20, §6).** **The visual design is `Studio Notes.dc.html` in the Claude Design project "Content Spiel design system"** (every screen in light and dark, made inside the design system and accepted by the user on 2026-10-09; §4.6 lists what it settles). An earlier rough canvas, "Notes on content", is superseded and is not a reference.

## 1. Purpose

People who work on the same site have nowhere in CS Studio to talk about the content. A question about a paragraph goes into chat or mail, loses its link to the paragraph, and is gone when the next person opens the page. A standing instruction ("ask Dana before changing a price") lives in someone's head.

This sub-project adds **notes**: threads of short messages attached to a page, a post, a block or a library image, shown wherever that record appears.

**Success:**
- An editor can ask a question about a block, address it to a colleague, and that colleague finds it without being told elsewhere.
- A thread can be answered, resolved and reopened; a standing note can be pinned.
- Opening a page shows at a glance that it has open notes and where.
- Nobody sees a note on content they may not see.

- A note addressed to you reaches an open CS Studio tab at once, with a sound for a mention.

**Not in this step:** presence ("Dana is editing this page"). That is step 2.

## 2. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | One kind of note: a thread that can be replied to, resolved, reopened and pinned. | A conversation and a standing annotation differ only in whether they are pinned; two kinds would double every screen. |
| D2 | Mentions (`@name`) address a note to a person; each person has an inbox in CS Studio. No mail. | Mail delivery is not configured (pre-launch list). |
| D3 | Notes follow the content. Whoever may read a record in CS Studio may read its notes, start a thread, reply, react and resolve. You edit and delete your own note. Whoever may edit the record may delete others' notes on it and pin. No new permission. | Nothing to configure; a note outside your scope is "not found" like its record. A separate permission can be added later. |
| D4 | A note is on a record: a page, a post, a block or a library image. A note on rich text may carry the selected passage as a **quote, a copy**: shown with the thread, not highlighted in the editor, not tracked when the text changes. | An anchored highlight must survive every edit, autosave and AI translation; that is the machinery of step 4. |
| D5 | Tags take no notes; a note has exactly one subject. | A note on several records raises "what if you may see only one of them" for every list and count. |
| D6 | In the editors, notes live in a drawer on the right, opened from the header and from a marker on each block. | A note and the thing it is about are visible together; one list per record serves every surface. |
| D7 | Three tables for threads, messages and deliveries (the inbox), plus one for reactions. | State, pin and quote belong to the thread; the inbox must hold a read mark per person; step 2 pushes delivery rows that already exist. |
| D8 | A note's text is plain text with mentions, emoji and auto-linked URLs. Not rich text. | Notes are short; the rich-text editor is heavy and its documents are per language. |
| D9 | A note may carry files: up to 5, each up to 10 MB. An image, including an animated GIF, shows inline; anything else is a download link. Files are stored with the note, not in the media library. | Attachments are working material, not content. |
| D10 | Emoji reactions on a note. | Asked for by the user; an acknowledgement without a reply. |
| D11 | No GIF search service (Giphy). | Optional by the user's own word; an outside service needs a key per install and sends editors' IP addresses to a third party. On the roadmap as "Could", behind a key. |
| D12 | A trashed record keeps its notes, hidden with it, back on restore. A purge deletes them. Deleting a block deletes its notes, after a warning when it has open threads. | Notes share the fate of what they are about. |
| D13 | A resolved thread is kept, listed collapsed under "Resolved", and not counted. | The answer is often worth finding again. |
| D14 | A note's text and file names are never copied into the audit log. | The log is append-only: a deleted note's text would otherwise stay readable forever. |
| D15 | A note's files are served only through a CS Studio action that checks the reader's right to the thread, never by an Active Storage URL. | Active Storage's read URLs are public to anyone who holds one and do not expire (`config/initializers/active_storage_access.rb`); a note's file may be confidential. |
| D16 | Notes are pushed to open CS Studio tabs over Action Cable (Solid Cable, already installed). **A push carries no note text**: it is a signal, and the browser re-fetches the part through the same scoped request it uses on load. | A push can then never show a note to someone who may not read it, whatever changed since they subscribed. No new infrastructure. |
| D17 | People follow threads. Writing in a thread or being mentioned in it follows it; a "Notify me" button follows and unfollows by hand; an explicit unfollow is remembered and only a new mention undoes it. Followers are told of replies, resolves and reopens. | Asked for by the user. It also gives a participant a way out, which a fixed "everyone who wrote" rule does not. |
| D18 | A mention plays a short chime, generated in the browser. Mentions only; one tab plays it. A per-person setting, on by default, switches it off. | Asked for by the user. No audio file to ship or license; a setting per person follows them across devices. |
| D19 | A mention can also raise a desktop notification with the author, the record's title and the note's first line. A per-person setting, **off by default**; turning it on asks the browser for permission. | Asked for by the user. Off by default because it puts note text outside CS Studio (a lock screen), and because a browser only grants the permission on a person's own click. |
| D20 | Turbo's morphing page refresh stays off; only the notes parts are refreshed. | The write queue depends on it (`docs/reference/save-rule-and-write-queue.md`). |

## 3. Data and rules

### 3.1 Storage

Models live under `Notes::` (`app/models/notes/`, entry file `app/models/notes.rb`), services under `Notes::` in `app/services/notes/`. Components are `Admin::NotesScreen::` (never `Admin::Notes`, which `test/lib/admin_namespace_shadow_test.rb` refuses).

**`note_threads`** (`Notes::Thread`)
- `subject_type`, `subject_id`: the record the thread is on. One of `Page`, `Post`, `ContentBlock`, `Media::Asset`. Polymorphic, so no foreign key; §3.5 says who removes the rows.
- `container_type`, `container_id`: the record whose screen lists the thread. For a block it is the block's owner (a page today); for anything else it equals the subject. Written by the service from the subject, never by a caller. One query on `container` reads everything a page's drawer shows.
- `state`: `open` or `resolved`. `resolved_at`, `resolved_by_id`.
- `pinned`: boolean. `pinned_at`, `pinned_by_id`.
- `quote`: text, optional, at most 500 characters.
- `origin_view` (`editor`, `mind_graph`, `media`, `list`) and `origin_locale`: where and in which language tab the thread was started. Context only: shown as "written on …", never used to decide where a thread appears.
- `created_by_id`, timestamps. `last_message_at` for ordering.
- Indexes: `(container_type, container_id, state)`, `(subject_type, subject_id)`.

**`note_messages`** (`Notes::Message`)
- `thread_id` (FK, cascade), `author_id` (FK to users, `on_delete: :nullify`), `body` (text, 1–4,000 characters), `edited_at`, timestamps.
- `mentioned_user_ids`: integer array, derived from the body by the service on every write.
- `has_many_attached :files` (D9).
- The first message of a thread is the note that started it; a thread always has at least one message. Deleting the last message deletes the thread.

**`note_deliveries`** (`Notes::Delivery`): the inbox
- `user_id` (FK, cascade), `message_id` (FK, cascade), `thread_id` (FK, cascade), `reason` (`mention`, `reply`, `resolved`), `read_at`, timestamps.
- Unique on `(user_id, message_id)`. Index `(user_id, read_at)`.

**`note_reactions`** (`Notes::Reaction`)
- `message_id` (FK, cascade), `user_id` (FK, cascade), `emoji` (string), timestamps. Unique on `(message_id, user_id, emoji)`.

**`note_follows`** (`Notes::Follow`)
- `thread_id` (FK, cascade), `user_id` (FK, cascade), `following` (boolean), timestamps. Unique on `(thread_id, user_id)`.
- A row with `following: false` is an explicit unfollow (D17). No row means "never involved".

**`users`** gains `notes_sound` (boolean, default true) and `notes_desktop` (boolean, default false), saved from the account screen through a service like the name is (D18, D19).

User references follow the existing pattern: an author who is deleted leaves the note, shown as "a deleted user" by `Admin::UserNameComponent`.

### 3.2 Mentions

- In the body a mention is stored as a token, `@[<user id>]`, and rendered as the user's current display name. Renaming a user changes how old mentions read; deleting one renders "a deleted user".
- The composer inserts the token from a picker. The picker lists only **users who may read the subject** (the same check as D3), by `display_name` with the email as a hint. This is a second place CS Studio lists users to someone without `users.manage`; like `Admin::UserSuggestionsController` it is not a directory: it needs two typed characters, returns at most eight rows, and answers only for a subject the asker may read.
- A token naming a user who may not read the subject is refused by the service ("… can't see this page"), so a mention never leaks a title or a quote through the inbox.

### 3.3 Who is told

**Following (D17).** In the transaction of a message, its author and each mentioned user follow the thread: a missing `note_follows` row is created with `following: true`; an author's existing `false` row is left alone (writing again does not undo an explicit unfollow); a mentioned user's `false` row is set back to `true` (a mention is addressed to them). `Notes::Follow` is the button: it sets the actor's own row either way.

**Deliveries.** A delivery row is written, in the transaction of the action, for:
- each mentioned user (`mention`);
- on a reply, each follower (`reply`);
- on a resolve or a reopen, each follower (`resolved`, `reopened`), with the thread's first message as `message_id`.

Never for the author of the action. At most one row per person per message; `mention` wins over `reply`. The `reason` column takes `mention`, `reply`, `resolved`, `reopened`.

A delivery is read when its owner opens the thread (the drawer marks the thread's deliveries read when it shows them), presses "Mark all read", or follows the inbox row.

A person who loses the right to read the subject keeps the delivery row but the inbox never shows it: the inbox query narrows through the read scope (§3.4).

### 3.4 Permissions

The read right of a thread is the read right of its container:

| Subject | Read, start, reply, react, resolve, reopen | Delete others' notes, pin, unpin |
|---|---|---|
| Page, or a block of a page | `pages.read` on the page | `pages.edit` on the page |
| Post | `posts.read` on the post | `posts.edit` on the post |
| Library image | `media.upload` (what opens the library; there is no per-image read right) | `media.manage`, or `media.upload` for the image's uploader (`Media::Ownership`) |

- Moderation needs `edit`, not `edit` plus `publish`: a note changes nothing a visitor sees.
- Editing or deleting your own message: allowed while you may still read the subject. These are self-service services (`SELF_SERVICE` in `test/support/service_calls.rb`): a manager with `edit` may delete the message but never edit its text.
- Lookups go through `AccessControl.scope` on the container (`pages.read`, `posts.read`) or `require_permission("media.upload")`, and a thread on a record outside the scope answers 404, never 403. A thread is never found by its id alone.
- API tokens: notes are a CS Studio feature in this step; no MCP tool. The services take any actor, so a later MCP tool needs no change to them.

### 3.5 Services

Each is an `ApplicationService` with `authorize!(` and `record_event(`, listed in `EXPECTED_SERVICES` with a factory.

| Service | Does |
|---|---|
| `Notes::Start` | Creates a thread with its first message on a subject; optional quote, files, origin. |
| `Notes::Reply` | Adds a message to a thread. Replying to a resolved thread reopens it. |
| `Notes::EditMessage` | Changes the author's own message; sets `edited_at`; recomputes mentions and writes deliveries for newly mentioned people only. |
| `Notes::DeleteMessage` | Deletes a message, its files, reactions and deliveries; deletes the thread when it was the last one. |
| `Notes::Resolve` / `Notes::Reopen` | Changes the state. |
| `Notes::Pin` / `Notes::Unpin` | Changes the pin. A pinned thread is listed first and is always open: resolving a thread unpins it, and a resolved thread can't be pinned. |
| `Notes::React` | Adds or removes the actor's reaction (a toggle). |
| `Notes::MarkRead` | Marks the actor's own deliveries read: one thread's, or all. |
| `Notes::Follow` | Follows or unfollows a thread for the actor (D17). Needs the read right. |
| `Notes::Remove` | Deletes every thread of a subject with its files. Not called by a person: called by `Trash::Purge` (page with its blocks, post, image) and `ContentBlocks::Destroy` (the block and, for a section deleted with its blocks, each of them), inside their transactions. |

Rules:
- **A note never writes the record it is on.** No `touch`, no `updated_at`, no public content version. An autosave base is therefore never moved by a note, and a note is neither held up by nor holds up a stale-save check.
- **Existence under a lock.** `Notes::Start` re-reads its subject inside its transaction: for a block it takes the page's row lock first (the lock order of `ContentBlocks::Structure#lock_owner`) and then looks the block up; for a page, post or image it locks that row. A subject deleted in the meantime is an ordinary failure ("This block was deleted"), so `Notes::Remove` can't miss a thread written beside it.
- **Lifting and folding.** A block that changes container inside its page (into, out of or across a section) keeps its threads: the thread's container is the page. Nothing to update.
- **Duplicate** copies no notes.
- **Audit.** New actions `note.started`, `note.replied`, `note.edited`, `note.deleted`, `note.resolved`, `note.reopened`, `note.pinned`, `note.unpinned`, `notes.removed`. The event's subject is the **content record** (page, post, block, image), so the events appear in that record's Activity and are scoped like it. `snapshot: nil`; metadata holds the thread id and the message id only (D14). `Notes::React`, `Notes::MarkRead` and `Notes::Follow` are not audited (`# audit: none (…)`): a reaction, a read mark and a follow are not changes to content. `Audit::Sentence` gains the wording ("Dana started a note on Pricing"); `Dashboard::Activity::ACTIONS` gains `note.started` and `note.resolved` only, so replies don't flood the feed.
- **"Changed elsewhere" and "Mine".** `Audit::ChangeSince` and `Dashboard::Feed` read a record's newest audit event to say who changed it. Note events are excluded from both (as `access.denied` is from the feed): a note is not a change to the record.

### 3.6 Files

- Validated like library images: the type is sniffed from the bytes (`Marcel`), never taken from the client. Allowed: PNG, JPEG, GIF, WEBP, PDF, plain text, CSV, and the Office and OpenDocument text, sheet and slide formats. SVG and HTML are refused. 10 MB each, 5 per message.
- Uploaded with the message as one multipart form post. No direct upload.
- Served by `Admin::NoteFilesController#show`: looks the thread up through the read scope, then sends the file with `Content-Disposition: attachment` for anything that is not one of the four image types, and `X-Content-Type-Options: nosniff` always. No Active Storage URL for a note's file is ever written into a page (D15). Inline images are shown through the same action, at most 320 px wide, without variants.
- Deleted with the message (`purge_later`).

### 3.7 What does not change

- The content tables, their services' behaviour and their permissions.
- The public site: no note, count or file is reachable from it; nothing bumps the content version.
- The write queue: note forms are ordinary Turbo forms inside the drawer's own frame. They send no `X-Page-Base-Updated-At` and replace no editor form.

## 4. The drawer

### 4.1 The component

`Admin::NotesScreen::DrawerComponent`: an `<aside>` on the right edge of the content area, 400 px wide from 1024 px. It follows the Media panel's pattern (surface background, a 1 px line on its left edge, no scrim, no page lock) and overlays the content with the menu shadow, the one stated exception to "shadows on menus and popovers only"; the editor stays usable beside it. Below 1024 px it is a full-screen sheet with a "Back to <title>" button. Nothing is designed below 768 px. It is rendered once per screen, outside every autosave form, and holds a `<turbo-frame id="notes">` whose `src` is set when it first opens.

A Stimulus controller, `admin--notes`, opens and closes it, remembers "open" per browser in `localStorage` (a convenience only), moves focus into the drawer on open and back to the trigger on close, and closes on Escape when focus is inside. It is a `complementary` landmark labelled "Notes".

### 4.2 Content

The drawer has two views; an opened thread **replaces** the list (the design's layout 1b), on every width.

**The list**, top to bottom:
1. Title "Notes", **New note** (a thread on the record itself: no chooser), Close.
2. **Pinned** threads.
3. **Open** threads, grouped: the record's own first, then one group per block that has threads, in the page's display order (`BlockOutline`). A group's heading names the block the way its card does and, inside a section, its column. A row is the first message's author, time and first lines, the reply count, and "new" in accent when it holds an unread delivery for the viewer.
4. **Resolved** (count), collapsed; loaded when opened.
5. Empty: the shared empty state with "New note".

**The thread**: a Back control to the list, the group heading, the messages, and, fixed at the bottom of the drawer, the composer with Resolve. The list keeps its scroll position for the way back.

A thread shows its quote, its messages (author, time, "edited", "written on German" when the origin language differs from the current tab), files, reactions, a reply field, Resolve, and **Notify me** / **Stop notifying me** (D17). A thread with more than three messages shows the first and the last two with "Show 4 more".

The composer is a textarea with three controls: attach files, emoji, and the mention picker that opens on `@`. Enter adds a line; ⌘/Ctrl+Enter sends.

The emoji control is a small fixed set (about 30 common ones) in a popover; the operating system's own picker works in the field as anywhere. Reactions use the same set.

### 4.3 Openers

- **Header**: `Admin::EditorScreen::HeaderComponent` gains a "Notes" button with the count of open threads, before Preview.
- **Block card and section tile**: a marker in the card's header and on the tile. With open threads it is a pill with the count, pressed to open the drawer at that block's group. Without, nothing is shown at rest (the system's rule: no count when it is zero); an add-note control appears on hover or keyboard focus of the card, and "Add note" is always in the block's ⋯ menu, so neither touch nor a test depends on hover. A section's own header shows no total: only its tiles count, so a thread is never counted twice.
- **Quote**: with text selected in a rich-text field, the block's marker reads "Note on selection"; the selected text, cut to 500 characters, becomes the new thread's quote.
- The translation tabs show the same threads (a thread is on the block, not on a language) with its origin language named.
- A view-only viewer (read without edit) gets the drawer and can write notes: D3.

### 4.4 Other surfaces (board 3)

- **Post editor**: the same header button and drawer; a post has no blocks, so one group.
- **Media library**: the panel beside the grid (`Admin::MediaLibrary::PanelComponent`) gains a "Notes" section with the image's threads, rendered by the same thread components; no drawer on that screen. A tile shows a count chip beside `NO ALT` and `UNUSED`, read by the grid in one query.
- **Posts list**: a "Notes" column with the open count as a link that opens the post with the drawer open (`?notes=open`).
- **Page tree**: a row shows the open count of the page and its blocks together, beside the translation markers, read once for the whole tree.
- **Mind graph**: the node of a post with open threads carries a small mono count badge on its top-left corner (no ring: a ring means selected, a corner dot means pinned); the card built by `mind_graph/card.js` shows the post's open threads (first message, author, reply count) and a field to start one. The graph's JSON gains `open_notes` per node, from one grouped query. Threads in the card are read as JSON from a new endpoint; the card writes them with `textContent` only.
- **Trash**: a trashed record's notes are not shown anywhere and not counted.

### 4.5 Look

- **Counts**: open threads are neutral meta-colour pills like the existing count badges. Accent is used for one meaning only: unread and addressed to the viewer (the dot on an inbox row, "new" on a thread row, the Dashboard badge in the sidebar, which is a filled accent pill and the one filled badge there).
- **People**: the existing actor pattern (round avatar, name).
- **Quote**: a sunken block with a 1 px line on all sides; no coloured left border.
- **"Written on German"**: the existing translation chip, shown only when the origin language differs from the current tab.
- **Emoji**: the emoji control is a Lucide icon, never a glyph. Reaction chips are drawn like tag chips (sunken, line border, the emoji and a mono count), with the accent tint for the viewer's own.
- **Motion**: with reduced motion on, an animated GIF does not play by itself; it is a still tile with a Play control.

### 4.6 Strings

Every string is a key under `config/locales/admin/notes.en.yml`; the new components, controllers and scripts go on `CONVERTED` in `test/lib/admin_i18n_test.rb`. The header and the block card, which gain a button each, are not converted today; their new strings are keys all the same.

## 5. The inbox (board 2)

- **Dashboard card "Notes for you"**: the viewer's deliveries, unread first, then newest; five rows and "All notes for you". A row says who did what ("Dana mentioned you"), the first 140 characters of the message, and where (type, title, block). It links to the record with the drawer open at the thread.
- **"All notes for you"**: a full list at `<admin>/notes`, 50 a page, with "Mark all read".
- **Dashboard card "Open threads"**: records the viewer may read that have open threads, one row per record with its count, most recently active first, five rows.
- **Sidebar**: the Dashboard entry shows the viewer's unread count. `Admin::Shell::SidebarComponent#badge_for`, hard-wired to Trash today, takes a count per entry. One `COUNT` per page load, narrowed by the read scope.

`Dashboard::NotesForYou` and `Dashboard::OpenThreads` (`app/queries/dashboard/`) build on `AccessControl.scope` for pages and posts and on `holds?("media.upload")` for images, as `Dashboard::TranslationNeeds` does, and return rows of data; the components word them. Both are constant in the number of queries and both belong in `test/integration/trash_visibility_test.rb`.

## 6. Live delivery

### 6.1 What is pushed

Two kinds of signal, both sent after the transaction commits, neither with any note text, title or name in it (D16):

| Stream | Who subscribes | Sent when | Payload | The browser then |
|---|---|---|---|---|
| **Person** | Every CS Studio page of a signed-in user, for that user | A delivery row is written for them | `{ kind: "delivery", delivery_id, reason }` | Re-fetches the sidebar badge and, if on the dashboard, the inbox card; fetches that one delivery through the scoped inbox endpoint and shows a toast ("Dana mentioned you", linked); for `mention`, plays the chime (D18) and raises the desktop notification (D19) if the person's settings say so. |
| **Record** | A page that shows a record's notes: an editor, the media panel, the mind graph card | A thread of that container is started, replied to, edited, deleted, resolved, reopened, pinned, reacted to, or removed | `{ kind: "threads", thread_id }` | Re-fetches the drawer's thread list and the count markers. Its own author's tab ignores the signal for the action it just made. |

Lists (posts list, page tree, media grid) are not live: their counts are fresh on load.

### 6.2 Subscribing

- `ApplicationCable::Connection` identifies the user from the CS Studio session, as the controllers do; no session, no connection.
- `Notes::PersonChannel` streams for `current_user` only; it takes no parameter.
- `Notes::RecordChannel` takes the container's type and id, looks it up **through the read scope** (§3.4) and rejects the subscription when it is not found. A signed stream name is not enough on its own: the check runs on the server at subscribe time.
- Rights that change while subscribed need no handling: the signal says nothing, and the re-fetch is scoped.
- The cable script is loaded by CS Studio only, never by a public page (`test/integration/public_javascript_test.rb`).

### 6.3 Refreshing without losing work

- The re-fetch replaces the thread list and the markers. It never replaces a composer: a field with text in it, its attached files and its open mention picker stay as they are. A thread that changed under an open reply field shows the new messages above the field.
- A thread deleted while its reply field holds text keeps the field, with "This thread was deleted" above it.
- Signals that arrive in a burst are coalesced: one re-fetch per 500 ms per part.
- When the socket drops, CS Studio keeps working as without push; on reconnect each subscribed part re-fetches once.
- No page-level refresh, no morphing (D20). A note's signal never touches an editor form or the write queue.

### 6.4 The chime, the toast and the desktop notification

- **Toast**: the existing inverted toast, bottom-centre, with the sentence and the action "Open" (the record with the drawer open at the thread), for 8 seconds like the Undo toast. Not shown when that thread is already open in the same tab; the delivery is then marked read at once.
- **Chime** (D18): two short tones made with the Web Audio API; no file. Only for `mention`. With several tabs open, the tabs agree through a `BroadcastChannel` which one plays (the visible one, else the first to claim it). A browser that has not yet had a click in the tab stays silent; nothing is queued for later.
- **Desktop notification** (D19): only when the tab is hidden or unfocused. Title "Dana mentioned you"; body: the record's title and the first 140 characters of the note, read through the scoped inbox endpoint. Clicking it focuses the tab and opens the thread. One per delivery across tabs, by the same agreement as the chime.
- **Settings**: the account screen gains "Notes" with two switches, "Play a sound when I'm mentioned" (on) and "Show a desktop notification when I'm mentioned" (off). They save with the screen's save bar, as configuration does. "Allow in this browser" beside the second acts at once: it asks the browser for permission in that click and says so if the browser refuses. The setting is per person, the permission per browser: on another browser the account screen shows "Allow in this browser".

### 6.5 Deployment

Solid Cable is configured for production (`config/cable.yml`, the `cable` database) and unused until now. The pre-launch checklist gains: the cable database exists and is migrated; the proxy passes WebSocket upgrades on `/cable`. In development and in tests the async adapter runs in the server's own process.

## 7. Errors and edge cases

- **The subject is deleted while the drawer is open.** A reply fails with "This block was deleted" and the drawer reloads.
- **Two people resolve at once.** The second is a no-op that succeeds; no second event.
- **A message deleted while someone replies.** The reply still lands; the thread reads on without the deleted message.
- **A follower loses access later.** Their follow and delivery rows stay and show nowhere; a `Notes::RecordChannel` subscription made earlier keeps receiving signals that tell them nothing.
- **A mentioned user loses access later.** The delivery stays hidden (§3.3); the mention still renders the name.
- **A user is deleted.** Their deliveries and reactions go (cascade); their messages stay as "a deleted user".
- **A file fails validation.** The message is not saved; the composer keeps its text and names the file and the reason.
- **Very many threads.** The drawer lists 50 open threads and "Show more"; counts are exact.
- **Unsent text.** A draft in a composer is kept per thread in `sessionStorage` and restored when the drawer is reopened. Leaving the screen with unsent note text does not raise the leave guard: the guard is about content.
- **The drawer and the shell's drawers** (sidebar, page tree, below 1280 px and 1024 px): opening one closes the other.
- **⌘K and dialogs** work while the drawer is open; it is not a modal.

## 8. Tests

- Models: validations, the container rule, mention parsing, delivery rules (who is told, never the author, one row per person).
- Services: the contract tests; per service the refusal (a stranger, a reader trying to moderate, another person's message), the audit event with no text in it, and `Notes::Start` against a subject deleted beside it (statement order, `capture_sql`).
- `Notes::Remove` from `Trash::Purge` (page with blocks, post, image) and from `ContentBlocks::Destroy` (block, section with its blocks, section with blocks kept): no thread, delivery, reaction or file is left; and it adds a constant number of statements.
- Access: every drawer, list, count, file and JSON endpoint answers 404 for a record outside the scope; the mention picker lists only readers.
- `test/integration/trash_visibility_test.rb`: the inbox, "Open threads", the counts in the posts list, the tree, the media grid and the graph.
- Files: type sniffing, the size and count limits, an SVG and an HTML file refused, the download headers, no Active Storage URL in any rendered note.
- Constant queries: the page editor with notes, the posts list, the tree, the media grid and the graph each cost the same number of statements at any number of threads.
- Live delivery: both channels reject a stranger and a signed-out connection; a signal's payload holds ids only (asserted on every broadcast); a signal is sent after commit and not on a rolled-back action; following rules (auto-follow, explicit unfollow kept, a mention re-follows).
- System, two sessions: one mentions the other and the other's badge, inbox and toast update without a reload; a reply appears in the other's open drawer while their half-typed reply is kept; the chime and the desktop notification are asserted through a stubbed `AudioContext` and `Notification` (called once across two tabs, not called with the setting off).
- System: start a note on a block, mention someone, sign in as them, find it in the inbox, reply, resolve, reopen, pin; quote a selection; attach an image and a PDF; react; delete a block with open threads (the warning); keyboard only through the drawer; the drawer beside an autosave in progress (a note sent while a save is outstanding neither waits forever nor moves the base).

## 9. Risk

- **Size.** This is the largest sub-project since the editor: five tables, twelve services, two channels, a new drawer, and markers on six surfaces. It ships as one PR all the same (the user's decision, 2026-10-09: the app is not in production). The plan orders the work so that reactions and files (D9, D10, §3.6) come last and nothing before them depends on them; live delivery (§6) comes after the drawer and the inbox work without it.
- **Push is the first use of Action Cable in the app.** The risk is a signal that says too much, or a refresh that eats typed text. D16 and §6.3 are the answers, each with its test.
- **The drawer is a new pattern** beside the shell's left drawers and the media panel. It gets its own component and controller, and the reference doc says when to use which.
- **Counts on every list** are where a slow query hides. Each surface reads its counts in one grouped query, pinned by a test.
- **File serving** is the first authenticated read of an upload in the app. It must not become a general way to read blobs: it takes a message's attachment id, never a blob key.

## 10. Documentation

- New `docs/reference/notes.md`, indexed in `CLAUDE.md`.
- `CLAUDE.md` rules: a note never writes its subject; a note's text never reaches the audit log; a note's file is never linked by an Active Storage URL; whoever deletes a page, post, image or block calls `Notes::Remove`; a pushed signal carries ids only and every part it refreshes is fetched through the read scope; the content models never reference `Notes::` (guarded by a test); `Admin::Notes` is never defined.
- `docs/roadmap.md`: step 1 shipped; GIF search and the items of §11 entered; step 2 of collaboration is presence alone.

## 11. Out of scope

- Presence (step 2).
- Following a whole page or post, so that every new thread on it notifies.
- Notifications when no CS Studio tab is open (a service worker and web push).
- A sound or a desktop notification for anything but a mention.
- Mail.
- An anchored highlight in the text (D4).
- Notes on tags, users or settings; a note on several records (D5).
- GIF search (D11).
- MCP tools for notes.
- Notes on a specific language version of a record.
- Assigning a thread to a person, due dates, and "review requested": these belong to "Publishing workflow" on the roadmap, which builds on this.
