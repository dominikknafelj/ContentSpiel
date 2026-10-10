# Presence, and the seams notes and presence share

Status: design, 2026-10-10. Step 2 of "Collaboration on content" on the roadmap. It opens, as agreed on 2026-10-09, with the extension seams, extracted only where notes and presence both need them.

## 1. What it is for

An editor who opens a page, a post or a library image should know whether someone else is there, before starting to change it; and should see from the page tree or the posts list where colleagues are working, when it is still possible to choose something else. Today nothing says so, and the second writer finds out from a refused autosave.

It is not a lock and holds nothing for anybody. "Dana is editing this block", shown on the block and able to reserve it, is step 3.

## 2. Decisions

The owner's answers in the brainstorm (2026-10-10):

- **D1. Per record.** Presence is shown for a page, a post and a library image. Per block comes with step 3, together with edit reservations.
- **D2. Where.** In the two editors' headers and the media library's image panel (who is on this record), and as a marker in the page tree and the posts list (someone is here). Not on the dashboard, in the mind graph or in the media grid.
- **D3. Here, then away.** A person is here while their tab is visible and they did something in it within the last 5 minutes; away after that or when the tab is hidden; gone when the tab closes or the connection drops. The lists mark only records where someone is here.
- **D4. Everyone who can open a record sees everyone on it**, read-only viewers included. No invisible mode, no per-person setting. Nobody sees themselves.
- **D5. Storage.** One small table in the main database, unlogged if the schema file keeps that marking and an ordinary table otherwise. (On 2026-10-09 I had said presence should stay out of the main database; looking at the setup changed that: the cable database exists only in production, the cache store is the null store in tests and per process in development, and the write load is one tiny update per open tab every 30 seconds.)
- **D6. Order of work.** The live notes script is split first; then the seams, with notes moved onto each; then presence, as their second user.
- **D7. Seams are extracted only where both features need them.** Three are (§4). What only notes needs stays a direct call.

## 3. Splitting the live notes script

`app/javascript/controllers/admin/notes/live_controller.js` (1,136 lines) does four jobs. It becomes four files, with no change of behaviour: same element ids, same signals, the existing notes system tests unedited.

| File | Job | Used by |
|---|---|---|
| `app/javascript/live/connection.js` | Open, share and close the cable connection; subscribe a part of the page to a channel and hand its signals to a listener; give the tab its id (`X-Notes-Tab` today) | notes, presence |
| `app/javascript/controllers/admin/notes/inbox_controller.js` | The person's side: the sidebar count, the dashboard cards, toasts, bursts | notes |
| `app/javascript/notes/merge.js` | The one rule "what is read is replaced, what is typed is never touched", for a list and for a thread | notes |
| `app/javascript/controllers/admin/notes/live_controller.js` | What is left: a record's signal and the tab's own answers, handed to the merge | notes |

`live/` and `notes/` are new plain-module folders. `notes` has a topic of that name; `live` is shared by two topics and joins `i18n` and `search` as a named exception in `test/lib/source_layout_test.rb`.

The merge gets tests of its own, without a connection: given a thread's markup with an open edit form, a half-typed reply and a delete question, and a fresh answer, what stays and what is replaced.

Done in small moves, the whole notes system suite after each. No presence code exists yet at this point.

## 4. The seams

### 4.1 Screen slots

Today the editor header, the tree's row, the posts list's row and the media panel each hold notes' markup and take notes' data as arguments. Presence needs a place in the same four.

- A slot is a name: `editor.header.status`, `editor.header.actions`, `tree.row.markers`, `posts.row.markers`, `media.panel.sections`.
- `Admin::Slots` (`app/components/admin/slots.rb`, in the components layer, since it holds component classes) keeps, per slot, an ordered list of entries. An entry is a component class and, for a list slot, a loader: a callable taking the records of the page and the viewer and returning whatever the component needs for each, in one or two queries however many rows there are.
- Features register in `config/initializers/admin_slots.rb`, the one file that names them all, in order.
- A core component renders its slot with the record and the viewer (`render_slot("tree.row.markers", page)`); a list component calls the slot's loaders once for all its rows. The four components no longer mention notes.
- A slot with nothing registered draws nothing. Order is the registration order.

Notes is moved onto the slots in the task that builds them: its header button, its tree and posts pills, its media-panel section become registered components, with the counts they need loaded by their loaders (`Notes::Counts`, as now). `test/lib/notes_boundary_test.rb` is extended: the four components and their templates may not name notes.

**Not slots, because only notes uses them:** the block card's marker and menu item, the section tile, the dashboard's two cards, the sidebar badge, the mind graph's count. They keep their direct code and are listed in the boundary test as known exceptions, each with the trigger that would make it a slot (block-level presence, for the block card).

### 4.2 The live core on the server

- `Live::Signals` (`app/models/live/signals.rb`): the one sender. It sends after the outermost commit, takes a stream and a payload, and refuses a payload that holds anything but a kind, ids, a reason and an origin. `Notes::Signals` keeps its own methods (what to say when a thread changes) and sends through it.
- `Live::RecordChannel` (`app/channels/live/record_channel.rb`): the base of a channel on one record. At subscribe time it finds the record through the read rights of the user as they are now (§4.3) and rejects alike a record that is out of scope, in the trash or not there. `Notes::RecordChannel` and `Presence::Channel` inherit from it and say only which stream they are.
- The guard that nothing but `Notes::Signals` broadcasts (`test/models/notes/signals_test.rb`) becomes: nothing but `Live::Signals` broadcasts, and a new sender of signals has a case in its own test.

### 4.3 The registry of record kinds

Notes holds a fixed list of what a note can be on, the right that lets a person read each and how to find one through the read scope, in three places (`Notes::SUBJECT_TYPES` and its key tables, `Admin::NoteContainer`, `Notes::RecordChannel`). Presence needs the same lookup for pages, posts and images.

- `RecordKinds` (`app/models/record_kinds.rb`): a registry. A kind has a name as it appears in a URL or a subscription (`page`, `post`, `media`), a model, the right that reads it, the right that moderates it, and a finder that takes a user, an id and a channel and answers the record through `AccessControl.scope`, or nil.
- The three built-in kinds are registered where the registry is defined. `ContentBlock` is not a kind of its own: a block is reached through its page, as now.
- Notes reads its kinds from the registry; `Admin::NoteContainer` and the two channels find records through it.
- A fourth kind then needs one registration for the server side. Its own screen still has to place the slots. (This is the answer to "are notes ready for other content types": a new post type, block type or page type needs nothing; a new model needs this registration and its screen.)

### 4.4 Not extracted

- **Deletion hooks.** Presence has nothing to clean up when a record is deleted (its rows expire within a minute), so `Notes::Remove` stays a direct call from `Trash::Purge` and `ContentBlocks::Destroy`. Trigger: edit reservations.
- **A "session ended" event.** A session's end already closes the cable connection, and a closed connection removes the person's presence rows. One user, so it stays `Session`'s own callback.

## 5. Presence

### 5.1 What a person sees

- **Editor header and media panel** (`editor.header.status`, `media.panel.sections`): the others on this record as initials, here before away, each group by name. Away is dimmed. Hover or focus says the name and "here" or "away for 12 minutes". Beyond a few, the rest are "+3", which lists them on hover or focus.
- **Tree row and posts row** (`tree.row.markers`, `posts.row.markers`): a marker when at least one other person is here on that record; its accessible name says who.
- A screen reader finds the people by the group's label and each avatar's own; a change is not announced (presence is background information, not an event).

The look is Claude Design's and is recorded in `2026-10-10-presence-handoff.md`, which is binding for it: 24px initials first in the header's action row, one neutral style, away as an unfilled circle, here before away in order of arrival, three and then "+N"; a 12px user icon as the row marker, with a count from two; 20px avatars at the right of the media panel's file-name row; one circle and "+N" below 1024px and nothing in the notes sheet.

### 5.2 How it works

1. **Arriving.** A page that shows a record's presence subscribes the tab to `Presence::Channel` with the record's kind and id. The channel finds the record (§4.3) and upserts one row: user, record, tab, state `here`, seen now. It signals the record.
2. **Staying.** The tab reports a change of state at once, and a keep-alive every 30 seconds, as channel actions. The row's `seen_at` moves.
3. **Going away.** The tab is `away` when the document is hidden, or after 5 minutes without a key, pointer or scroll event in it; `here` again at the next such event while visible.
4. **Leaving.** Unsubscribing (the tab closes, a Turbo visit leaves the screen, the connection drops) deletes the row and signals the record.
5. **Stale rows.** A row whose `seen_at` is older than 60 seconds is ignored by every read. `Presence::Sweep`, a recurring job, deletes rows older than 5 minutes, and signals nothing: what it deletes nobody could see.
6. **Telling others.** `Live::Signals` sends `{kind: "presence"}` to the record's presence stream and to one site-wide stream for lists, `{kind: "presence", record: [kind, id]}`. A tab showing the record fetches its header's presence again; a tab showing a list fetches the markers again, at most once every 5 seconds. Every fetch goes through the read scope, so the list signal tells nobody anything they could not ask.

A list tab that hears a signal for a record it does not show ignores it.

### 5.3 The pieces

| Piece | Where | Job |
|---|---|---|
| `presence_marks` | table | `user_id`, `record_type`, `record_id`, `tab` (the tab's id, shaped as `Live`'s), `state` (`here`, `away`), `seen_at`; unique on user, record and tab; index on record |
| `Presence::Mark` | `app/models/presence/` | The row |
| `Presence::Roster` | `app/queries/presence/` | Who is on this record (one person once: here if any tab of theirs is, else away, with the latest `seen_at`), without the viewer and without stale rows; and which of these records have someone here |
| `Presence::Channel` | `app/channels/presence/` | Arrive, `report(state)`, `beat`, leave |
| `Presence::Sweep` | `app/jobs/presence/`, `config/recurring.yml` | Deletes old rows |
| `Admin::PresenceController` | `app/controllers/admin/` | The two fetches: a record's people, a list's markers; record found through §4.3 |
| The tab's script | `app/javascript/controllers/admin/presence/` | State, keep-alive, idle timer, re-fetch; on `live/connection.js` |
| Components | `app/components/admin/presence_screen/` | The people of a record; the marker of a row; registered in the slots |
| Strings | `config/locales/admin/presence_screen.en.yml` | |

### 5.4 Deliberate limits

- **No service object and no audit event.** Presence is not content and nobody asks for it by name: a channel writes its own throwaway row. This is an exception to "every write goes through an `ApplicationService`", said in `CLAUDE.md` with its reason, and the table is on the exception list of the service contract test if that test looks at tables.
- **A person in two browsers counts once.**
- **Rights taken away mid-session:** every fetch is scoped, so the person stops seeing others. Their own open subscription is not re-judged, the same gap notes has (roadmap).
- **The presence row of a record that is trashed or purged** expires by itself.

## 6. Testing

- **Script split:** the notes system tests, unedited. The merge module's own tests.
- **Slots:** components render what is registered, in order; a list's loader runs once for any number of rows (statement count pinned); the four components do not name notes (boundary test); notes' screens look as before (existing component and system tests).
- **Live core:** the payload guard; subscribe-time scoping for both channels; nothing else broadcasts.
- **Record kinds:** each built-in kind found through its scope and not outside it; a kind registered in a test is found by notes with no other change.
- **Presence:** the roster's rules (stale ignored, never yourself, two tabs once, here over away); a record outside the read scope cannot be subscribed to and its people cannot be fetched (also in `test/integration/trash_visibility_test.rb`); lists in one query at any length; two people as two Capybara sessions (arrive, away on hidden tab, leave); time by moving the clock (`backdate`), not by waiting.
- **First step of the work:** the sign-in helper of the system tests waits longer for the shell (the roadmap's flake), since two-session tests sign in twice.

By hand, as with notes: Safari, and idle detection on a real second machine.

## 7. Out of scope

Block-level presence; live refresh of blocks; presence on the dashboard, in the mind graph or in the media grid; any per-person setting; the seams of §4.4 and the notes-only places of §4.1; MCP tools (roadmap item 8); the notes gaps already on the roadmap.

## 8. Risks

- The script split touches the file that produced most of notes' defects. It goes first and alone.
- Slots are an interface drawn from two users. They are kept as small as those two need: a name, a component, a loader.
- Idle and hidden-tab detection differ between browsers; the tests run in Chrome.
