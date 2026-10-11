# Live refresh and edit reservations

Design, 2026-10-11. Step 3 of "Collaboration on content" on the roadmap, after notes (step 1) and presence (step 2). The look is `2026-10-11-live-editing-handoff.md`.

## 1. What it is for

Two people can open the same page or post. Today the one who saves second is refused ("Changed by Dana 2 min ago. Your text is still here so you can copy it"), nothing warned them beforehand, and nothing on their screen changes until they reload.

This step stops that from happening in the first place and from hurting when it does: what someone else saves appears in an open editor without a reload, and a block (or a page's settings, or a post) that someone is changing is theirs for the moment, read-only for everyone else, who can take it over.

It is not co-editing: one person types in a block at a time. Co-editing of rich text is step 4, and only if this proves insufficient.

## 2. Decisions

The owner's answers in the brainstorm (2026-10-11):

- **D1. A reservation is soft.** What someone holds is read-only for everyone else, with "Take over". Nobody is locked out by a colleague who went to lunch.
- **D2. It begins with the first change**, not with opening a form. Reading reserves nothing.
- **D3. It ends** when the form is closed, when the person leaves the page, or 2 minutes after their last saved change. If it lapses and someone else changes the block, the first person's open form is refreshed: a lapsed hold means everything they typed was saved.
- **D4. What can be held:** a block (a section's own settings form is its block's), a page's settings form, and a post as a whole. Not a library image. Moving, adding and deleting blocks and changing a section's layout are instant actions: they hold nothing and ignore a hold.
- **D5. A refresh shows itself:** the content changes in place and the card says "Updated by Dana Weiss · just now" for a few seconds.
- **D6. Taking over loses nothing.** The holder's tab is told, sends what is unsaved, and lets go; the block then starts from their latest text. A tab that does not answer within 5 seconds is passed over, and keeps its unsaved text for copying when it wakes.
- **D7. The server decides.** Reservations are rows, and a save from a tab that does not hold the record is refused before anything is written (approach A of three; B, browsers only, and C, inside presence, were set aside).
- **D8. One sub-project, one pull request**, built in this order: live refresh; reservations; take-over; the label and the slot; documents.

## 3. Live refresh

### 3.1 The signal

After a content write commits, `Editing::Signals` sends a signal on the stream of the page or post the write belongs to, through `Live::Signals`: a kind, ids and a reason, never text.

- `{ kind: "content", content_block_id:, reason:, origin: }` for one block; `content_block_id` is nil when the record itself (a page's settings, a post) or the list's structure changed.
- `reason` is one of `saved`, `structure` (a block was added, deleted, moved or duplicated, or a section's layout changed) and `gone` (the record was trashed or deleted).

**The source is the audit log's notification**, which every write already makes after its outermost commit (`Audit.record`, also for an event coalesced into an earlier one). `Editing::Signals` subscribes to it and maps event names to signals, so no content service names this feature and a new write path is covered by the mapping, not by a call someone has to remember. A test fails for a content event name that the mapping does not know. Writes through the MCP server and the console are covered the same way. Where an event does not name the page of its block (to be checked per event when the plan is written), its metadata gains the page's id; that is the only change to a content service.

A signal names a record only on that record's own stream, which is subscribed to through the read scope (`Editing::Channel < Live::RecordChannel`), judged at subscribe time like the other two channels.

### 3.2 The fetch and the merge

The tab that caused a write skips its own signal (`origin`). Every other open editor of that record fetches, with a plain GET through the read scope, the part the signal names **as its viewer may see it now**:

- one block's card (in the placement and language its editor shows);
- the block list, for `structure`;
- the page's settings form, or the post's form.

`app/javascript/editing/merge.js` owns one rule: **a form that holds changes not yet saved is never replaced, and neither is anything else of its card.** Everything else is replaced by what was fetched; a card that stays keeps its open or closed state, and the scroll is adjusted so the block being read or typed in does not move on screen (handoff 12). An older answer is never drawn over a newer one.

- A replaced form carries its new `base_updated_at`, so its next save is not refused as stale.
- A block deleted while its form holds unsaved changes stays, with notice (c) of the handoff.
- A hidden document fetches nothing. When it is seen again, and whenever its subscription is confirmed again, it fetches the list and the record's own form once.
- A 404 on any of these means the record is gone or no longer the viewer's to read: the editor says so and offers the way back, as a refused autosave does.

The fetches are plain GETs: the write queue neither holds nor counts them. Nothing here uses Turbo's page refresh or morphing.

### 3.3 The page settings form's base

Every block write touches its page, and the page settings form's stale check compares against the page's `updated_at`. So today someone in the settings is refused after a colleague saves a block, although nobody else changed the settings. With reservations that would break D1's promise.

`pages` gains `settings_changed_at`, set by the model whenever a column of the page itself changes (a `touch` does not move it), and the settings form's base and stale check use it. The forwarding of the page's base in a block's answer (`X-Page-Base-Updated-At`, `page_base_streams`) then has nothing left to do and is removed, if the plan confirms nothing else reads it.

## 4. Reservations

### 4.1 The table

`edit_reservations`: `subject_type` and `subject_id` (unique together; a `ContentBlock`, `Page` or `Post`), `record_type` and `record_id` (the page or post whose stream it is signalled on), `user_id`, `tab` (the tab's opaque id, as presence has it), `changed_at`, and for a pending take-over `requested_by_id`, `requested_tab`, `requested_at`.

A row is **live** until `changed_at + Editing::HOLD` (2 minutes). An expired row counts as no row. A recurring job deletes expired rows; nothing depends on it, so a deleted block's row needs no hook.

### 4.2 Claiming, renewing, releasing

`Editing::Reservation` holds the statements; each is one atomic statement on the unique index, so two tabs can never both hold a subject, and none takes a row lock or writes a content row. (Like presence's marks they are not `ApplicationService`s and are not audited: they are not content, and they would flood the log.)

- **Claim** (`POST`, sent through the write queue ahead of the first save): inserts the row, or takes an expired one, or renews the tab's own. It answers who holds the subject. It is sent when a clean form gets its first change; the autosave script announces that moment, which today only starts its timer.
- **A save is a claim too.** The three autosave actions (`Admin::PagesController#update`, `ContentBlocksController#update`, `PostsController#update`) claim-or-renew before they call their service, beside the stale check. If another tab holds the subject live, the save is refused with a 409 and notice (b); nothing is written and nothing audited. A request with no tab id (a script, a client without JavaScript) is neither refused nor does it claim.
- **Release** (`POST`, through the queue, so after the form's last save): when a block's form is closed, and with a beacon when the page is left. A hold that is not released expires.

A claim and a release are refused exactly where the save would be (the same 404 outside the read scope and 403 without the right to edit, or to publish for a published record).

Each change of holder sends `{ kind: "holder", content_block_id:, reason: }` on the record's stream, and every other tab fetches that card again: it comes back read-only with the strip, or editable.

The check and the save are not one transaction, like the stale check they stand beside: two saves within one request's length can both pass. The stale check stays underneath.

### 4.3 Read-only is rendered, not switched

A card, a settings form or a post form is rendered for its viewer: held by someone else, it has the strip, fields that are `readonly` (handoff 6; a control HTML cannot make read-only, such as a select or a checkbox, is `disabled` and styled at full contrast), a rich-text field with no toolbar and no caret, and **no autosave controller**, so it registers nothing with the write queue. Becoming editable again is another fetch. The rich-text controller learns a read-only value for this; it decides at connect, as today.

The one form that turns read-only in place is one holding unsaved text when its claim or save is refused (a tie, or a tab that woke after a take-over): its text stays in the fields, the script makes them read-only and pauses its autosave, and notice (b) offers "Copy my text" and "Discard", which fetches the card.

A person's own other tab is someone else: "You're editing this in another tab".

### 4.4 Taking over

1. The requester's tab posts the request. `Editing::TakeOver` (an `ApplicationService`: it asks the right and audits) records `requested_by`, `requested_tab` and `requested_at` on the row and signals `holder` / `requested`. If the hold has expired meanwhile, it simply claims.
2. The holder's tab hears it, waits until its write queue is drained, and posts the hand-over. The row passes to the requester; `holder` / `taken` is signalled; one audit event on the content record names both people (ids in metadata, `snapshot: nil`).
3. The requester's card is fetched again and is editable, from the holder's latest text. The holder's card shows notice (a), then the ordinary strip.
4. If no hand-over has come after `Editing::PASS_OVER` (5 seconds), the requester's tab asks again and the service passes the row over on what was saved, with the same event marked as not answered.

Anyone who may save the subject may take it over, including back.

## 5. What people see

As the handoff has it. In structure:

- **The strip and the notices** are the editors' own (`Admin::EditorScreen::`), rendered by the card, the settings panel and, for a post, the header's notice area.
- **The tile's avatar** stands in a new slot, `editor.block.markers`, hosted by the block card's header and the section tile, with a loader that reads the page's holds once. The notes marker on a block moves onto the same slot, so the card and the tile stop naming notes (the trigger presence's design named). The "Add note" menu item stays a named exception.
- Nothing changes in the page tree, the posts list or the header's people.

## 6. The parts

| Part | Job |
|---|---|
| `Editing` (`app/models/editing.rb`, `editing/`) | The namespace: `HOLD`, `PASS_OVER`, `Reservation`, `Signals` |
| `Editing::TakeOver` (`app/services/editing/`) | The one audited write |
| `Editing::Sweep` (job) | Deletes expired rows |
| `Editing::Channel` | The record's stream, through the read scope |
| `Admin::EditingController` | Claim, release, take over, hand over; the GETs of §3.2 |
| `app/javascript/editing/merge.js` | The merge rule |
| `controllers/admin/editing/live_controller.js` | Listens, fetches, merges, the "Updated" mark |
| `controllers/admin/editing/hold_controller.js` | Claims on the first change, releases, hands over, turns a refused form read-only |

`Admin::Editing` is never defined (it would shadow `Editing`); the guard test covers it the day the directory exists.

## 7. Rules kept

- Every claim, release, hand-over and save goes through `app/javascript/saving/queue.js`.
- An open form holding unsaved changes is never fetched over and never removed; a section's panels stay in the document.
- No Turbo page refresh, no morphing, no broadcast but `Live::Signals`'.
- Signals carry a kind, ids and a reason; every part is fetched through the read scope; outside it is the 404.
- No name, text or title in a signal or in the audit event of a take-over.
- A reservation never writes the record it is on, and moves no base.

## 8. Tests

- `Editing::Reservation`: each statement, expiry at the boundary, and two connections claiming at once (one wins).
- `Editing::Signals`: the mapping from every content event name, and a failure for one it does not know; the payload's shape.
- `Editing::Channel` and the controller: outside the read scope is not found; a claim without the right is refused; a save from a tab that does not hold is refused and writes nothing.
- `Editing::TakeOver` in the service contract tests.
- Browser tests with two sessions, waiting on conditions and never on time: a save appears; an added, moved and deleted block; the "Updated" mark; a hold makes the other's card read-only and a release frees it; expiry; a tie; take-over with unsaved text arriving first; take-over from a tab that does not answer; a delete under unsaved text; a hidden tab catching up; a person's own second tab; the settings form saved while a colleague saves blocks.
- A test that stubs `fetch` takes only its own request.

## 9. Not in this step

Library images in the media panel (they keep "saved, also changed elsewhere"). Reservations for writes through the MCP server: they hold nothing and are not refused by a hold; they appear through live refresh, and one that lands on a block someone is changing makes that person's next save stale, as today. Co-editing. Anything on the dashboard, in the lists or in the mind graph. A rate limit on claims.
