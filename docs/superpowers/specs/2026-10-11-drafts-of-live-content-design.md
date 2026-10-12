# Drafts of live content

Design, 2026-10-11. The first part of "Versioning" on the roadmap (pending revisions: drafts of live records), moved to the front by the owner after trying a live page by hand. Built on top of step 3 of collaboration (live editing, PR #66), as its own pull request.

## 1. What it is for

Since CS Studio exists (2026-09-27), autosave writes the one record a page or post has, so on a live page every save is public at once: someone starts a sentence, pauses for a second, and the half-sentence is on the site. The design of that day called it interim and named the remedy: "autosave will write a draft revision, and publishing will apply it." Step 3 made it more visible, because a colleague now watches the half-sentence arrive.

After this, nothing typed into a live page or post reaches the public site by itself. Going public is a deliberate act.

## 2. Decisions

The owner's answers in the brainstorm (2026-10-11):

- **D1. Autosave stays and writes a draft.** Publishing is a separate step: now, or at a time. Not: switching autosave off on live content (the owner weighed it as a fallback: structural actions would still go live at once, work could be lost, and step 3 on a live page would have nothing to ride on).
- **D2. One page or post as a whole,** including its changes in every language. Not per block and not per language.
- **D3. Publishing asks first,** in a dialog with an overview of what will change.
- **D4. Preview shows the draft;** the public site shows what was last published.
- **D5. Rights stay as they are.** Whoever may change a live page may publish its changes; editing live content still needs the right to publish. Separating "prepares" from "approves" comes with release management.
- **D6. The public site reads a published copy** (approach A of three; an overlay beside the live rows, and a hidden duplicate of the rows, were set aside): the rows in the database stay what editors work on; a copy is taken on publish and the public site draws from it.
- **D7. Left out of this version,** and immediate as today: whether the page is published at all, its place in the tree, its slug. The slug field of a live page takes effect on confirmation, not while typing.
- **D8. Its own pull request,** on top of step 3.

A test of the design, not a feature of it: a page's copy must later be able to go live together with other pages' copies as a release (roadmap: "A release is a set of pending revisions") without rework.

## 3. What a person sees

**A page or post that was never published** behaves as today: it is a draft, autosave writes it, Publish makes it live.

**A live or scheduled page or post:**

- The save status reads "SAVED · NOT PUBLISHED" where it read "SAVED TO SITE". The line "This page is live. Changes appear on the site as soon as they're saved." becomes a line saying that changes are published with "Publish changes…".
- When the working version differs from what is published, the header says so beside the Live chip and offers **Publish changes…** and **Discard changes…**. "View on site ↗" opens what the public sees; Preview shows the working version.
- **Publish changes…** opens a dialog with the overview: blocks changed, added, removed and moved, each by its type and summary; the record's own fields that changed; the languages in which anything changed; and, if another tab holds unsaved text for this record, a line saying that only what has been saved is published. The dialog publishes now or at a given time.
- **Discard changes…** asks once and returns the working version to what is published.
- The page tree and the posts list mark a live record with unpublished changes; the dashboard lists them under "Unpublished changes".

**Scheduling.** A record scheduled to go live is treated like a live one from the moment it is scheduled: what was scheduled is what goes live at its time, and later edits are unpublished changes until someone publishes them (which replaces what is scheduled, keeping its time, unless a new time is given).

## 4. The published copy

### 4.1 The table

`published_versions`: `record_type`, `record_id` (a `Page` or a `Post`), `number` (counting per record), `snapshot` (jsonb), `live_at` (when it is or becomes what the public sees), `tag_ids` (integer array; a post's tags as published, for list queries), `created_by_id`, `created_at`. A row is never changed after it is written, with one exception: a row whose `live_at` is still in the future may be replaced by a newer publish.

**The current copy** of a record is the one with the greatest `live_at` not after now. A scheduled change is a copy with a future `live_at`; it becomes current by the clock, at read time, as a scheduled page becomes live today. There is at most one future copy per record.

Every live or scheduled record has a copy. A migration writes the first copy of every such record from its rows as they are, so the public site is unchanged on the day this ships.

### 4.2 What a copy holds

- **A page:** its own content columns (title, subtitle, hero image and its alt text, meta title, meta description, page type) and every block of the page in display order, each with all of its columns (type, place in a section, settings, translated settings, body, caption, alt text, image), in every language.
- **A post:** its content columns (title, excerpt, body, the type's fields) and its tags (ids and names).
- **Not in a copy** (D7): slug, parent and position, `published_at`, the trash state, the content type of a post (which cannot change).

`Publishing::Snapshot` builds a copy from the rows and builds read-only objects back from a copy: a `Page` or `Post` and its `ContentBlock`s, instantiated from the stored attributes, with the page's blocks set as its loaded association, so that the existing components and templates draw them unchanged. Library images are looked up live by id, as today: one that is gone renders nothing.

### 4.3 Publishing and discarding

Two services, both `ApplicationService`s with the service contract:

- **`Publishing::PublishChanges`** (needs the right to publish): writes a new copy from the working rows, or replaces the future one; clears the record's unpublished-changes mark; records `page.changes_published` or `post.changes_published` (with the copy's number and whether it is scheduled); moves the public content version.
- **`Publishing::DiscardChanges`** (needs what editing the live record needs): writes the current copy back over the working rows through `Pages::Save`, `Posts::Save` and the block services, reconciling blocks by id (a block that was deleted comes back as a new block; one that was added is deleted; order and sections are restored); clears the mark; records `page.changes_discarded` or `post.changes_discarded`. It is refused while another tab holds any part of the record (step 3's rule: a write to a held subject from another tab is refused), since it would overwrite their text.

Publishing a draft for the first time, scheduling it, and unpublishing stay the actions they are; the first two also write the record's copy. An unpublished record keeps its old copies and uses none.

### 4.4 Knowing that something changed

`pages` and `posts` gain `unpublished_changes_at`: set when a content column of a live or scheduled record, or one of its blocks, is written; cleared by the two services. It drives the header, the marks and the dashboard list without comparing anything on a page view. It may be set when the net difference is nothing (typed and typed back): the dialog then says there is nothing to publish and clears it.

`Publishing::Changes` compares the working rows with the current copy when the dialog opens, and answers the overview of §3 as data; a component words it.

## 5. The public side

Everything the public site draws of a live record comes from its current copy:

- the page or post itself (`PublicPageRendering`, `pages/show`, the block and post components, the SEO fields);
- **another record's title or excerpt wherever one page shows another:** the menu, the list of subpages, post lists and a post's listing;
- **which posts a list holds:** the post's type and `published_at` as today, and its tags as published (`tag_ids` of its current copy);
- the sitemap's last-modified date (the current copy's `live_at`);
- the cache: the ETag and the rich-text render cache follow the current copy, and the public content version moves when a copy becomes current, not on each autosave of a live record.

What stays on the rows: addresses (`public_paths`: slug, tree and publish state are immediate, D7), the tree itself, whether a record is visible at all (`Resolver.visible?`), and internal links (they read only the target's address and visibility).

**Images in use.** An image used by a record's current or future copy counts as used, so it cannot be deleted from under what is public; `Media::UsageIndex` indexes copies as well as rows.

**Preview** keeps reading the rows.

**A guard** (`test/lib`) fails when a public controller, template, helper or component reads a content column of a `Page`, `Post` or `ContentBlock` otherwise than through the copy, with a list of the public readers as `test/integration/trash_visibility_test.rb` has for the trash; a new public list, search or feed belongs in it.

## 6. CS Studio

The editors, autosave, the write queue, step 3, notes and translations are not changed: they work on the rows. What changes:

- the header (the state, the two actions, the dialog), the save status's wording, the marks in the tree and the posts list, the dashboard list;
- the slug field of a live page (D7): it is not part of the autosaving settings form; it has its own small form with a confirmation, since a new slug changes the page's address at once;
- the rule "editing a live record needs the right to publish" stays (D5), with its reason reworded where it is explained: it is no longer that typing publishes, but that the same person publishes.

The MCP server's `update_post` writes the rows, so a live post it changes has unpublished changes afterwards; the tool gains a `publish_changes` argument (default false) so that a client can still publish in one call. Its read tools keep reading the rows and say whether there are unpublished changes.

## 7. Rules added

- Nothing public reads a content column of a live record's rows; it reads the current copy (the guard of §5).
- A copy is written only by `Publishing::PublishChanges`, the first-publish and schedule paths of the save services, and the migration; a copy that is or was current is never changed.
- A write that changes a live record's content sets `unpublished_changes_at`; one that goes around callbacks says so on its line, as the content-version rule does.
- `Admin::Publishing` is never defined.

## 8. Tests

- For every public reader of §5: change a live record's rows, and the public response is unchanged; publish the changes, and it changes. The same for a scheduled copy before and after its time, with the clock moved, not waited for.
- The guard of §5, shown to fail for a reader that reads a row.
- `Publishing::Snapshot`: a copy and the objects rebuilt from it draw the same HTML as the rows did, for every block type, a section with blocks, every language.
- `Publishing::Changes`: each kind of difference, and none.
- The two services in the service contract; discard restores blocks, order, sections, tags and fields, and is refused under someone else's hold.
- Browser tests with two sessions: typing on a live page while a visitor's view stays put; the overview; publish; discard; a scheduled change; the marks. No wall-clock assertions.
- The tests that pin "an edit of a live record is public at once" are rewritten to the opposite; each is listed in the pull request.

## 9. Not in this version

A history screen and restoring an earlier version (every publish keeps its copy, so the data is there). Releases across several records. Publishing per language. Separating the right to edit from the right to publish. Slug, tree position and publish state as pending changes. Notes of a block that was deleted and then brought back by a discard (they were removed with the block; the delete dialog says so for a live page).

## 10. The look

The dialog, the header's state and the marks are built from CS Studio's existing patterns (its dialogs, the header's chips, the tree's and list's marks); every choice of wording and placement is listed in the pull request for the owner, as nobody designed them.

## As built

Written when the work ended (the sections above are not rewritten). The reference document is `docs/reference/publishing.md`; this section says where the code departed from the design above and why. The plan's "Where the code disagrees with the design" lists nine points; they ended like this.

1. **§5, "what stays on the rows: addresses".** A post's address does follow the copies: `PublicSite::Paths.canonical_pages` reads its candidates through `Publishing::Listing.blocks` and judges a post by its published tags. What the plan left to a sweep became **one entry point**, `PublicSite::Paths.refresh(pages:, posts:, everything:, now:)`, after the first attempt (a window of recent pages, a read back through older copies, eleven places each reconstructing its own before-picture) kept leaving holes. It rests on two recorded facts, `public_paths.listed_on_id` (which page gives a post its address) and `published_versions.settled_at` (a copy's coming into force was acted on), so there is no time window and no sweep of pages: the job calls `refresh` with nothing touched. Three mechanisms keep addresses right: `refresh`, the slug's validation and `Version.repoint_tag!`.
2. **§4.1, "every live or scheduled record has a copy".** Not enforced: a published record with no copy is served from its rows, and a guard holds only that `published_at` is assigned in the two save services. Cost: a record published around the services follows typing until it is published once.
3. **§4.1, a scheduled record's first copy with a future `live_at`.** As planned: it is in force at once and shown when `published_at` passes; only a scheduled CHANGE has a future `live_at`. **Publish now** on a scheduled record changes its time only.
4. **One `snapshot` column.** Three, as planned (`snapshot`, `blocks`, `lists_posts`), and `published_versions` gained `settled_at` and an index on `live_at`.
5. **Tags.** Matched by id (`listed_tag_id` in a list block's copy, `tag_ids` in a post's), as planned, with three departures from the plan. **No tag is ever created**: not by a publish, not by a discard; a copy that recorded no id for a named tag lists nothing until its page is published again. **A tag merge is immediate everywhere**, which changes §7's "a copy that is or was current is never changed": `Version.repoint_tag!` replaces the merged id in copies, because a tag's id is a reference and left alone every list lost its posts and their addresses, and (after a hand test found the merged-away name still printed on the site) it rewrites the id and name a post's copy shows of the tag to the kept tag's, so a merge marks no post and leaves nothing to publish. A rename or delete marks the carrying records (it does not change a copy).
6. **A rebuilt record and a scope.** As planned: the fallback and the images go through `Publishing::Listing` and the block objects. The guard of §5 became two: `test/lib/public_readers_test.rb` (source, its scanned set derived) and `test/integration/public_canary_test.rb` (every content column of every live row overwritten, every public URL requested), the second being the one that holds.
7. **Discard and holds.** As planned: the refusal is `Admin::EditingClaims#refuse_discard_under_hold`, in the controller. Publish changes and Cancel scheduled change are NOT refused by a hold (they write no row an editor holds); Change address is, like Publish.
8. **Starter content.** `StarterContents::EnsureHome` and `StarterContents::Add` end by publishing the changes of the pages they wrote.
9. **The order of the build.** As planned: the plain button of Task 2 was replaced by the dialog in Task 7 and nothing of it is left.

Beyond the nine:

- **§4.3, discard returns to the copy IN FORCE**, not the newest, and withdraws a pending copy with it; a record whose only copy is the pending one has nothing to return to. A third service, **`Publishing::CancelScheduledChange`**, withdraws a scheduled change and leaves the rows as unpublished changes.
- **Rights and refusals.** A publish is refused only for the record's OWN address (`Publishing.keep_address!`); another record that loses its address yields, is logged and reported once, and the publish dialog names it beforehand (`Changes.addresses`), together with every live record the publish would move to another address, old and new (added after a hand test found a moving post unnamed; the old address redirects). This replaced a wider refusal that was the fragile part of every round of the address work.
- **State.** `Publishing::State` names five states and their actions in one place (no stored state, no state-machine gem); the header, the marks, the dashboard and `Publishable#status` ask it.
- **The content version** gained a read-time part (the newest `live_at` in force), so a scheduled change moves the ETag at its instant with no write and no job; a page's 304 reads the copy's id only.
- **Images in use** are rows of role `published` for the current and pending copies while the record is live or scheduled.
- **The header.** Its publishing forms are drawn once and never replaced (a press made while a save is out must not be lost); answers replace only `#publishing-chip`. The dialogs ask what they say by a POST through the write queue each time they open, and the three actions carry the pending copy they were shown and are refused on a mismatch (`Publishing::ShownSchedule`). `ApplicationService::Result` gained a `notice`.
- **`Publishing::Changes`** treats a language holding an empty document as a language with none, and a block that came back under a new id as the block it was, so that a discard can end in "nothing differs".
- **MCP.** `update_post` gained `publish_changes`; `get_post`, `list_posts` and the serializer say `unpublished_changes`. The publication is not atomic with the edit.
- **§6, the slug of a live page** is its own form (Task 8): `PATCH pages/:id/slug` behind a dialog, an instant action refused while another tab holds the settings; a post's slug stays in its autosaving form.
- **§8.** The tests that pinned "an edit of a live record is public at once" were rewritten to the opposite; the pull request lists each.
