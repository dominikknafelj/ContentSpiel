# Live refresh and edit reservations

Design, 2026-10-11. Step 3 of "Collaboration on content" on the roadmap, after notes (step 1) and presence (step 2). The look is `2026-10-11-live-editing-handoff.md`.

**Status: built** (2026-10-11, branch `editing`). Sections 1 to 9 are the design as it was approved and are left as they were written; where the code left them is section 10, "As built", at the end. The code is described in `docs/reference/live-editing.md`.

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

## 10. As built

Where the build left the design above, and why. The body is not rewritten: it is the record of what was approved. `docs/reference/live-editing.md` describes the code as it is, with the test behind each rule.

### The seven points the plan found before building

The plan (`docs/superpowers/plans/2026-10-11-live-editing.md`, "Where the code disagrees with the design") checked the design against the code and built these the proposed way.

1. **§3.3, the forwarding of the page's base.** "Removed, if nothing else reads it": something does. `Pages::Move` saves the page's own columns, so the tree's move of the open page moves `settings_changed_at`. The forwarding went from the block side only (`Admin::ContentBlocksController#page_base_streams`, the autosave script's `pageBaseId`, the header on the block requests); `admin--pages--tree` still sent `X-Page-Base-Updated-At` and `Admin::TreeController#page_base_streams` still answered, comparing `settings_changed_at`. **Superseded by the final review** ("Rulings of the final review" below): a move no longer moves the base, and the tree's forwarding is gone as §3.3 intended.
2. **§3.1, `origin`.** Not `Current.notes_tab`, which only the notes controllers set: with it on a content request, the tab that deleted a block would skip the refresh of its own notes drawer. The same header, `X-Notes-Tab`, is read by `Admin::BaseController` into a new `Current.editing_tab`, which only `Editing` reads.
3. **§5, "the card and the tile stop naming notes".** They stop drawing the marker (it is in the slot), but both still name notes for the "Add note" item of their menus, so they stay named exceptions of `test/lib/notes_boundary_test.rb` with the reason narrowed, and a new test holds that neither draws a marker itself.
4. **§3.2, "one block's card".** A section's card holds the forms of every block in it and cannot be fetched and replaced as one. The block's GET answers 204 for a section and the list is fetched instead, merged unit by unit; a block in a section is fetched as its tile and its panel. The unit of a section is its own settings form, not its card.
5. **§4.3, "fields that are `readonly`".** No field component took a read-only option. The held form's fields are drawn as they are and rewritten once by `Admin::EditorScreen::HeldFields`; the browser's counterpart for the one form that turns read-only in place is `editing/freeze.js`, which reads the same lists from the page. It was built with the read-only rendering (Task 7), not with the claims as the plan's text said.
6. **Handoff 17, the "Copied" toast.** There is none in CS Studio. "Copied" is a polite status text beside the button, gone after 2 seconds (settled as handoff 24).
7. **§4.2 against §7, the release when the page is left.** A page that is unloading cannot wait for a queue. Every claim, release, withdrawal, request and hand-over goes through the queue except at `pagehide`, where the release of what the tab holds, and the withdrawal of a request it made, are each a `fetch` with `keepalive` (not a beacon: it carries the tab header and the CSRF token).

### Rulings made while building

**Live refresh**

- **A catch-up draws only what differs (§3.2).** Every unit and part carries `data-editing-version` (`Editing.version`), and the fetch made when a subscription is confirmed leaves a clean unit of the same version as the element it is. Without it, the first connect replaced every clean card after every page load. Cost: a unit whose look depends on something its version does not cover is missed by a catch-up, never by a signal.
- **One GET at a time (§3.2, "an older answer is never drawn over a newer one").** Counting "newest" per part let an older list answer be drawn over a newer block answer. The live script has one read on its way, and what is asked meanwhile is owed and coalesced. An answer on the wire is drawn unless this tab queued a write meanwhile.
- **Displaced units (§3.2).** A block someone else moved to another container while this tab holds unsaved text in it stays where it is, is not marked gone, and nothing of it is drawn in its new place; the list is fetched again once the form is saved. The design had no word for this; the first build drew two forms of one block.
- **A gone unit keeps its place, a hidden panel that is gone is shown, and the focused unit is never the one moved.** A clean form that has the focus *is* replaced (a hold must be able to make it read-only): the focus and, for an `input` or `textarea`, the selection come back; a rich-text caret is lost.
- **The scroll is corrected for up to 1.5 seconds** (§3.2, handoff 12), while the cards redrawn above mount their editors, and stops the moment anything else scrolls.
- **A unit whose block has a menu or a dialog open is kept** and fetched again when it closes. Not in the design.
- **A drop made while a colleague changed the list is refused** (the existing stale reorder) and the list redrawn: the drop does not win. D4's "the existing refusal covers the rare clash" was taken at its word. Cost: a person's drop snaps back when a colleague changed the list in that second.
- **A rejected subscription fetches the record once**, so that its 404 says the access ended. A read has a timeout and three retries, and the editor's live part says "answered" only once its first read was attempted.
- **A trashed branch signals `gone` on each descendant's stream** (§3.1), since it is one event on its root. **A section's fold is `structure`**, but a later plain save coalesced into that audit row is not. **The channel takes a page or a post only**; a library image is rejected.
- **"Updated by …": the newest change decides.** If it was the viewer's own or made without a user, nobody is named.
- **A block deleted with its section gets notice (c) too.** The plan expected a 404 and no notice; the section's `block.deleted` event lists the blocks it took (`deleted_block_ids`), so the answer is the 410 naming who deleted it.

**The settings base (§3.3)**

- **For a page, "Changed by …" counts only the page's own events** (`Audit::ChangeSince`): only those move the settings base. Cost: a notice that could have named someone says "Changed elsewhere."
- A tag merge touches a page without changing it, so it no longer makes an open settings form stale.

**Reservations (§4.1, §4.2)**

- **D3, "2 minutes after their last saved change": a hold is renewed while typing.** A person can type for longer than a hold without a pause that saves, so a change claims again when the tab's last claim is older than half a hold. `changed_at` is the last saved change *or claim*.
- **D4, a section's layout is not an instant action.** It is saved by the section's own settings form, an autosave, so it claims the section's block and is refused while another tab holds that form. Moving, adding, duplicating and deleting blocks ignore a hold as designed.
- **Publish, Unpublish, Schedule and "Still correct" are refused while another tab holds the subject** (for a page: its settings), and take no hold. Not in the design: a publish would move the record's `updated_at` under the holder's open form. **Bulk publish skips a held post** and says how many it skipped; a bulk trash is not held back.
- **A claim a request took is given back** when the save is then refused as stale, denied or raises; a 422 keeps it.
- **The rule for who may claim moved to `AccessControl::OwnerRule`**, so the services and `Editing::Rights` ask the same one. Someone with `publish` but not `edit` can make a publish-only save as before, and can neither claim, take over nor hand over.
- **The first requester keeps the request (§4.4).** `request` answers `requested`, `pending` or `none`; a second person asking while a request younger than twice the pass-over time stands is told "pending". Two requesters could otherwise postpone each other. `requested_by_id` alone says whether a request exists.
- **A row exactly `HOLD` old is not live**: the read and the claim share one cutoff.
- **A deleted block's row stays until it expires**; no deletion hook was needed. A person whose right to edit is removed keeps a hold until it lapses or is taken over.

**Taking over (§4.4)**

- **The outcome `pending`**, above, and **`withdraw`**: a request ends with its asker (a visit away, a closed page, the unit going), through a statement and a route of their own, so the holder does not hand the subject to a tab that is gone.
- **§4.2 says no statement takes a row lock; the service does.** `Editing::TakeOver` runs its statements in one short transaction with the subject's reservation row locked first, so that what it audits is the row it changed. It locks no content row.
- **The audit sentence has two verbs.** The event's actor is whoever called the service: "handed over editing" when the holder answered, "took over editing" when the requester passed over. The first build logged a hand-over as the holder having taken over. Both ids are in the metadata, as designed; no name is.
- **§4.4 step 2, "waits until its write queue is drained", became a light, reversible lock.** A person typing without a pause never let the screen-wide drain finish, so they were passed over and their last words frozen although they were answering. The holder's tab now makes that subject's fields read-only at the moment it sends them, waits on those forms alone, and hands over; the lock is taken back if the save fails. After the hand-over the fields stay read-only until the unit is redrawn.
- **A holder passed over while awake with nothing unsaved** reads "Taken over by …" (notice (a)) like one who handed over.
- **A `released` signal while waiting** makes the asker claim at once; **a third person's claim** ends the waiting and asks nobody.

**The slot (§5)**

- No `markers:` argument was threaded through the section, lane and group components. The page's `Editing::Holds` goes through as the slot's context `holds:`. As first built, `Admin::Slots.load` also handed context to a loader that declared that keyword, which it found by reading the loader's parameters, and the avatar had such a loader for a host without holds. **Superseded by the final review** (below): the avatar has no loader and `Admin::Slots.load` is as it was before this work.

### Rulings of the final review

The whole-branch review found no path that loses a person's text; these are the rulings its fix round made.

- **A move in the tree is not a change of the page's settings (§3.3).** `Pages::Move` saves `parent_id` and `position`, which moved `settings_changed_at`: a colleague dragging a page in the tree refused whoever held that page's settings form (a final 409), though nothing in that form had changed. Both columns are in `Page::SETTINGS_BASE_IGNORES` now. With nothing left to move, the tree's forwarding of the page base went too: no `X-Page-Base-Updated-At`, no `Admin::TreeController#page_base_streams`. The header no longer exists anywhere. A real change of the settings by a colleague still refuses.
- **The slot's loader is gone (§5).** Both hosts of `editor.block.markers` hand `holds:` to the slot, so the loader served no host and made the component read `Current` for the viewer's tab. `HolderAvatarComponent` takes `holds:` from its context and nothing else; a host that hands none draws no avatar. `Admin::Slots.load(name, records, viewer:)` takes no context and reads no loader's parameters.
- **Leaving releases what was still waiting to be released (§4.2).** A release waits for its form's last save; a form closed with a save on the wire and then left kept its hold for two minutes, because leaving walked only what the tab still counted as held. Leaving now pays both, each once (`owed()` in the hold script).
- **The claim's order and the held unit's questions each have one place.** `Admin::EditingClaims#claim_before_save` is the claim, the refusal and the stale check with its give-back for the three autosave actions; `Admin::EditorScreen::HeldUnit` is what a reservation does to a card, a section, a tile, the settings form and a post's form.
- **Three rules got a guard, with its limits said:** an id on every ancestor of a unit, every version through `Editing.version`, and who may call a reservation's statements (`docs/reference/live-editing.md` names the tests).

### Wording nobody designed

Settled by analogy with the handoff's sentences while building, and **never asked of Claude Design**. Each is one locale key if it is wrong, with two exceptions that are literals in code like the other sentences of their kind: the two audit verbs (`Audit::Sentence`) and the service's failure sentence (`Editing::TakeOver`). The bulk sentence was a literal too and became a key (`hold_strip.bulk_skipped`, with a plural) in the final review.

- "You're editing this in another tab. Your changes weren't saved." (a tie lost against one's own other tab)
- "You deleted this block in another tab. Your changes weren't saved."
- "Asking to take over…", "Someone else is already taking this over", "Couldn't take over. Try again.", "Someone else is editing this now" (the status beside "Take over")
- "● NOT SAVED · SOMEONE ELSE IS EDITING" (the hold lapsed between the refusal and its answer)
- "Someone else changed this block. Your changes weren't saved.", and the same for "this post" and "the page settings"
- "This block was deleted. Your changes weren't saved." (no event names who deleted it)
- "Dana Weiss is editing this block. Try again when they have finished.", the same for "this post" and "the page settings", "You're editing this in another tab. Do it there, or close that tab first." and "Someone else is editing this. Try again when they have finished." (an instant action refused)
- "1 post being edited by someone was skipped." (bulk publish)
- "Couldn't copy. Select the text and copy it yourself." and "Couldn't load the block. Try again."
- "This page was moved to the trash or deleted, or you can no longer open it." with "Back to pages", and the same for a post
- "Dana Weiss took over this post", "… took over the page settings" and "Taken over by Dana Weiss · just now" for a post and the settings (handoff 13 and 19 word them for a block)
- "Dana Weiss is editing this post. Your changes weren't saved." (`hold_strip.lost.post`) and "Dana Weiss is editing the page settings. Your changes weren't saved." (`hold_strip.lost.settings`): the handoff words the lost notice for a block only
- "You're editing this in another tab" as the tooltip and the screen reader's words of the avatar on a tile (`holder_avatar.own_tab`): the handoff has the sentence for the strip, not for the avatar
- In the audit log: "handed over editing" and "took over editing"
- "Taking over needs a signed-in person and a browser tab." (the service's failure for a request with neither; a person does not see it in the editor)

Also decided without a design item: "Take over" and "Copy my text" are the small *secondary* button (the handoff says "the shared small default button", and the design system's default is secondary), "Discard" and "Remove" the small ghost one; notice (a) keeps its "Take over" button.

### What is left open

On the roadmap, under "Live editing": the gaps with their reasons (a save on the wire at `pagehide`; a holder typing in another block; no notice when every re-read after a hand-over fails; a colleague's publish not refreshing the header; tags; the caret of a clean rich-text field; MCP writes; no rate limit on claims; the tests that could not be written; and what the final review left: the displaced unit shown in its old place without a notice, the short window in which a read caused by a request can replace a lightly locked clean card, and a top-level card that stays expanded being freed only by the lapse).
