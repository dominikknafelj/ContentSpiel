# Notes on content: build handoff

The look of every part of "Notes on content", as designed by Claude Design inside the Content Spiel design system (`Studio Notes.dc.html` in the Claude Design project "Content Spiel design system", accepted by the user on 2026-10-09). This file is that design's written handoff, copied from Claude Design's answer and tidied; nothing in it was invented here.

**How to use it.** Follow it for markup, tokens, sizes and states. Where it and the spec (`2026-10-09-notes-on-content-design.md`) differ on **behaviour**, the spec wins; the known differences are listed under "Where the spec wins" at the end. Reuse an existing admin component wherever one draws the part already (button, menu, dialog, switch, alert, toast, chip, empty state, dashboard card): the sizes below describe the result, they are not a reason to restyle a shared component.

## Conventions

- Classes are the Tailwind names from `content-spiel.tailwind.css`: `bg-surface`, `text-meta`, `border-line`, `rounded-cs` (2px), `shadow-menu`, `font-mono`, `tracking-mono` (0.14em).
- Icons are Lucide at 1.5px stroke in `currentColor`: message-square, message-square-plus, paperclip, smile, at-sign, pin, x, arrow-left, file-text, download, check, play. (Check how CS Studio draws icons today and add these the same way.)
- All colour comes from tokens. No new tokens or colours.
- **Mono label** means: `font-mono` 10px, uppercase, `tracking-mono`, `text-meta`.
- Motion is `ease-cs` at 150–200ms, and none with reduced motion.

## New to the system

- The drawer is the one surface in the page flow that has `shadow-menu`.
- Accent means "unread for you". It covers the filled sidebar badge, the accent pills and dot, the toast's accent dot and the NEW divider.
- Reaction chips use the 999px tag-chip shape.

## The parts

### Drawer shell and header
- Shell: `absolute inset-y-0 right-0 w-[400px] bg-surface border-l border-line shadow-menu flex flex-col`. No scrim; the page isn't locked.
- Header: `px-4 py-3.5 border-b border-line`. "Notes" in 15px/600, followed by "4 OPEN" in 11px mono `text-meta`. Then the "New note" default button (12px/500, `border-line-strong rounded-cs px-2.5 py-[5px]`) and a 28×28 close button with a 16px x icon in `text-dim`; the close button gets `bg-sunken` on hover.
- Behaviour: Esc closes it and focus returns to the Notes button. Focus is not trapped. "New note" opens the thread-view composer for a note on the page or post itself.

### Thread row in the list
- Grid `24px 1fr 8px`, gap 10, `px-4 py-[9px] border-b border-line`, hover `bg-paper`, focus-visible a 2px accent outline. The whole row is one link.
- Lines: name 13px/500 with the time in 11px mono `text-meta`; first line 13px `text-dim`, one line, ellipsis; meta as a mono label at 0.1em ("3 REPLIES · 1 NEW").
- Unread: name 600, first line `text-ink`, and a 7px `bg-accent` dot on the right.
- Pinned rows: a 12px pin icon in `text-meta` instead of the dot, listed under a "PINNED" mono label.

### Group heading
- A mono label, `px-4 pt-4 pb-1.5`. It names the block type and its name, for example "RICH TEXT · INTRO". Inside a section it reads "SECTION TEAM › COLUMN 2 · RICH TEXT". Order follows the page. Notes on the page itself sit under "WHOLE PAGE".
- At the bottom, "▸ Resolved (3)" is 13px `text-dim`, `px-4 py-3.5`, and opens on click.

### Thread view with Back
It replaces the list inside the drawer.
- Row 1: `px-3 py-2.5 border-b border-line`. "← All notes 4" is a ghost button (13px/500, 16px arrow-left icon, hover `bg-sunken`). Next comes "Stop notifying me" or "Notify me" as a 12px `text-dim` underlined link (offset 3px) that toggles at once with no toast. Then close.
- Row 2: `pl-4 pr-3 py-2.5 border-b border-line`. On the left, the group heading as a mono label above "2 messages · started on DE" (13px `text-dim`). On the right, a 28×28 pin button (pressed: `bg-sunken text-ink`) and a Resolve button (12px/500, 12px check icon, `border-line-strong`).
- Pin: only people who can edit the record see it. A resolved thread shows "Reopen" instead of Resolve and has no pin.
- Body and composer: the body scrolls (`flex-1 overflow-auto`). The composer is fixed at the bottom.

### Message
- `px-4 py-3.5 border-t border-line flex flex-col gap-2`.
- Meta line: a 20px avatar (round, 8px mono initials), name 13px/600, time 11px mono `text-meta` (absolute time in a title), then "· edited" in 12px `text-meta` if edited. A ⋯ menu (Edit, Delete) shows on the right for your own messages, and Delete for record editors.
- Avatars: yours is `bg-ink text-paper`. Others are `bg-sunken border-line-strong`.
- Text: 14px/1.55, `text-wrap: pretty`. Mentions are `text-accent` at weight 500, and a mention of you looks the same.
- Language: the "written on" translation chip sits only on the thread's first message, and only when that language differs from the current tab. It is the existing chip: 10px mono, `text-dim border-line-strong rounded-cs px-[5px]`.

### Quote block
- `bg-sunken border border-line rounded-cs px-2.5 py-2`. It holds the mono label "QUOTED" above the passage in 13px/1.5 `text-ink`.
- Shown once, at the top of the thread body, with `p-3.5 px-4` around it. A static copy: nothing is highlighted in the editor and it isn't tracked.

### Attachment row (non-image files)
- Grid `16px 1fr 28px`, gap 10, `border border-line rounded-cs py-1.5 pr-1.5 pl-2.5 text-dim`.
- Contents: a file-text icon; the file name in 13px `text-ink` above "PDF · 1.2 MB" in 10px mono `text-meta`; a 28×28 download button (hover `bg-sunken`).
- Stacked rows have an 8px gap. Up to 5 files per message, 10 MB each.

### Inline image and still GIF tile
- Images and GIFs show at full message width (max 368px in the drawer), keep their own aspect ratio, and get a 1px `border-line`. While loading, the `--cs-ph-a` → `--cs-ph-b` placeholder gradient.
- GIF with reduced motion: the first frame with a centred Play button (`bg-surface border-line-strong rounded-cs`, 12px/500, 12px play icon, `px-2.5 py-[5px]`). It turns into Pause while playing.
- GIF label: "GIF · name" in 10px mono `text-dim`, bottom-left, 6px inset.
- Without reduced motion, GIFs play normally.

### Reaction chip
- `inline-flex h-6 px-[9px] gap-[5px] rounded-full border` (the tag-chip shape). The emoji at 13px and the count in 11px mono.
- Others' reactions: `bg-sunken border-line`, count `text-dim`. Yours: `bg-accent-tint border-accent`, count `text-accent`.
- A click toggles your reaction; hover shows "Dana, Jonas" in a title.
- Add-reaction chip: 30×24, `border-line text-meta`, 12px smile icon, opens the emoji picker.
- Chips wrap with a 6px gap, below the message. Reactions never go to the inbox.

### Composer
- Dock: `px-4 pt-3 pb-4 border-t border-line`. Field: `border border-line-strong rounded-cs`, focus `border-accent`.
- Text area: 14px/1.5, `px-2.5 py-[9px]`, min height 62px, grows to 200px and then scrolls. Placeholder "Reply…" or, for a new note, "Write a note…".
- Toolbar: `border-t border-line px-1.5 py-1 gap-0.5 text-dim`. Three 28×28 icon buttons: paperclip (title "Attach up to 5 files, 10 MB each"), smile, at-sign. Hover `bg-sunken`; active or open `bg-sunken text-ink`.
- Send: "⌘↵" in 10px mono `text-meta`, then the Send primary (12px/500, `bg-accent text-on-accent px-[11px] py-[5px]`, hover `bg-accent-hover`). Send is disabled at 0.5 opacity while the field is empty.
- Attachments: chosen files show as attachment rows above the field, each with a remove ×. A sixth file or a file over 10 MB gets an inline 12px `text-danger-ink` line, not a toast.

### Mention picker
- The existing menu panel: `bg-surface border-line shadow-menu rounded-cs p-1`, 250px wide, opening 6px above the composer.
- Rows: `px-2 py-1.5 gap-2`, a 22px avatar, name 13px, email 11px `text-meta`.
- Keyboard focus and hover are `bg-sunken`; the first row is focused when the picker opens.
- Typing "@" or the at-sign button opens it. ↑↓ and Enter insert the name, Esc closes. It lists only people who can read the record, at most 6 rows.

### "NEW" divider
- `flex gap-2 items-center px-4 pt-2.5`: a 1px `bg-accent` line filling the space, then "NEW" in 10px mono `tracking-mono text-accent`. It goes above the first message that arrived while the thread was open.
- Your draft is never touched.
- If you aren't at the bottom, a "1 new message ↓" button (12px/500, `bg-surface border-line-strong shadow-menu`) sits 12px above the composer and the list doesn't move.
- The divider goes away when you leave the thread.

### Notes header button
- Next to Preview: 13px/500, `bg-surface border-line-strong rounded-cs px-[11px] py-1.5 gap-[7px]`, with a 16px message-square icon.
- No open threads: "Notes" only.
- Open threads: a count in 11px mono `text-dim`.
- Unread for you: the count becomes a filled pill (`bg-accent text-on-accent rounded-full px-1.5`, line-height 16px).
- Drawer open (pressed): `bg-sunken border-ink`, `aria-pressed="true"`.
- Hover `border-ink`; focus-visible a 2px accent outline.

### Block card marker
- It sits right after the block name in the card header, so the drawer can't cover it.
- Open threads: a pill `h-5 px-[7px] gap-1 rounded-full border border-line-strong text-meta`, 12px message-square icon, count in 11px mono.
- Unread for you: `bg-accent-tint text-accent border-accent-tint`.
- Click: opens the drawer at that block's group.
- No notes: nothing at rest. On card hover or `:focus-within`, a 24×24 message-square-plus icon in `text-meta` appears in the same place and opens the composer. "Add note" is also always first in the block's ⋯ menu.
- While a thread is open, its block's card border becomes `border-accent`.

### Section tile marker
- The same pill at `h-[18px] px-1.5`, 10px mono, after the mono "COLUMN 2 · RICH TEXT" label in each column tile. The section's own header has no total.
- The add-note control on hover or focus works the same way at 12px.

### Inbox row ("Notes for you" card)
- The existing dashboard card (`bg-surface border-line`, header `px-4 py-[13px] border-b`, 15px/600 title).
- Header extras: "3 NEW" in 11px mono `text-accent`, and a "Mark all read" 13px link on the right.
- Row: a link, grid `7px 24px 1fr auto`, gap 10, `px-4 py-[11px] border-b border-line`, hover `bg-paper`. Line 1 "Dana Weiss mentioned you" (13px). Line 2 the note's first line in 13px `text-dim` with ellipsis. Line 3 the place, "About › Rich text · Intro", in 12px `text-meta`. Time in 11px mono.
- Unread: a `bg-accent` dot, name 600, line 1 `text-ink`. Read: no dot, name 500, line 1 `text-dim`.
- Unread first, then newest first. Opening a row marks it read and opens the drawer on that thread.
- Footer: "All notes for you →" goes to the same rows as a full page.

### Open threads row
- Same card. The header shows the total in 11px mono `text-meta`. Rows are grid `1fr auto`, `px-4 py-[11px]`, hover `bg-paper`.
- Left: the record title in 14px/500 with ellipsis, above "type · last author · time" in 12px `text-meta`. The type marker is 6px: round in `cat-n` for posts, square in `text-meta` for pages and images.
- Right: the neutral count pill.
- 5 rows, most recent activity first, one row per record.

### Sidebar badge (Dashboard)
- Counts unread items for you. The only filled sidebar badge: `bg-accent text-on-accent rounded-full px-1.5`, 10px mono, line-height 16px. Hidden at zero. Other badges (Trash) stay plain mono text.

### Posts-list count cell
- A 56px column. The header shows only a 12px message-square icon in `text-meta` with the title "Open notes". The cell holds the pill without an icon (11px mono, `h-5 px-[7px]`): neutral, or accent when unread for you. Empty at zero.

### Tree row count
- After the translation markers, in the existing tree row, with a 6px gap: the 18px pill with a 12px icon and 10px mono count, neutral or accent. Empty at zero.

### Media tile chip
- On the image, 6px from the top-right corner: `h-5 px-[7px] rounded-full bg-surface border border-line-strong text-ink`, 12px icon, 11px mono count. It needs the surface background to stay readable over photos. Unread for you uses `bg-accent-tint text-accent` and keeps the border.

### Media panel Notes section
- Below the existing fields: a header row `px-4 pt-3 pb-1.5` with the mono label "NOTES · 2 OPEN".
- Rows: the drawer's thread rows, but the first line isn't cut short.
- Composer: a collapsed input below ("Write a note…", 13px `text-meta`, `border-line-strong rounded-cs px-2.5 py-2`). On focus it expands into the full composer in place.
- Zero threads: only the header and the input.

### Mind graph node badge
- On the node's top-left corner, overlapping by 4px: 10px mono, line-height 14px, `px-1 rounded-full bg-surface border border-line-strong text-ink`. Only when the node has open threads. It doesn't scale with zoom and stays at 10px. It sits opposite the pinned dot (top-right), so both can show.

### Node card thread list
- Under the title: the mono label "OPEN NOTES · 2", then rows in grid `20px 1fr 7px`, gap 8, 13px.
- Rows: a 20px avatar, the first line with ellipsis (`text-ink` if unread, else `text-dim`), and the unread dot.
- At most 3 rows, then "+N more" as a 12px link that opens the post's notes.
- Then a "Start a note…" field (13px, `border-line-strong rounded-cs px-[9px] py-[7px]`). It expands to the composer inside the card, and the card grows up to 360px.
- Zero threads: only the field.

### Full-screen sheet below 1024px
- It replaces the drawer and goes under the 48px top bar.
- Header: `px-4 py-3 border-b border-line`. A "← Back to About" default button (13px/500), "Notes" in 15px/600, "4 OPEN" in mono, and "New note" on the right.
- Body: centred, max width 720px. Rows get `py-3`, 14px text, and the first line isn't cut short.
- Back returns to the editor at the same scroll position. Opening a thread works as in the drawer, with the composer fixed to the bottom of the screen. Nothing is designed below 768px.

### Account switches
- A "Notes" section card on the own-account screen: header `px-[18px] py-3.5 border-b` with 16px/600 "Notes" and a 13px `text-dim` description.
- Rows: `px-[18px] py-3.5 border-b border-line`, label 14px, and the existing switch on the right (34×20 `rounded-full`: on `bg-accent`, off `bg-line-strong`, a 16px knob that slides 2px→16px; disabled 0.5 opacity).
- Both switches save with the existing sticky save bar.
- Permission not given yet: the desktop row shows the existing info alert below it (`bg-accent-tint rounded-cs px-3 py-2.5`, 13px), with an "Allow in this browser" default button (12px/500). The button acts at once and opens the browser's permission prompt.
- Allowed: the alert goes away.
- Blocked: the alert reads "Blocked in this browser. Change it in the site settings of your browser." and has no button.

### Toast
- The existing inverted toast, bottom-centre of the content column, with an accent dot (new: accent means "for you"). Text "Dana mentioned you on About", action "Open", close ×, hides after 8s. Sound and desktop notification follow the account switches.

### Delete-block dialog
- The existing confirm dialog with the 40% black scrim. When the block has open notes, the existing warn alert sits in the body: "This block has 2 open notes. They will be deleted with it." The action is the danger button "Delete block". Resolved notes are deleted too, without a warning.

## Where the spec wins

- **Media screen.** The handoff offered an "Open in drawer" link in the media panel's Notes section. The spec has no drawer on the Media screen (§4.4): leave the link out; a thread opens in place in the panel.
- **Inline image click.** The handoff says a click opens "the existing media lightbox". CS Studio has no lightbox: a click opens the image in a new tab through the authenticated file action (spec §3.6). No lightbox is built in this step.
- **Mention picker size.** Six rows (this file) replaces the spec's earlier "at most eight".
- **"Unread for you" on counts.** The accent state of a count (header button, block and tile markers, posts list, tree row, media tile, node card rows) means the viewer has an unread delivery on a thread counted there. Each surface reads it in the same grouped query as its count, or one beside it; the query count stays constant.

## Decisions after the build started (Claude Design, 2026-10-09)

Eight questions the build raised, answered by Claude Design in the same project. They replace what this file and the spec said before on the same point. No mock was changed for them except where noted.

1. **Drawer against the header and the content.** From 1024px the drawer is a 400px **column to the right of the content, below the sticky header**: it takes its place in the page flow and pushes the editor; the header spans both and is never covered. While notes are open, the page tree column folds into the existing "Pages ▾" breadcrumb drawer (the 768–1023px pattern), which keeps the content column at about 620px at 1024px and about 770px at 1440px. What follows: translation pairs stack through the existing container query (under 880px), sections keep their lanes, block menus open inside the content column. Because the drawer sits in the flow it has `border-l border-line` and **no shadow**: the shadow exception in "New to the system" goes away. Below 1024px: the full-screen sheet, as before.
2. **Notes button.** It uses the shared header secondary style (16px, `px-4 py-2`), like Preview beside it; its icon is 16px and its count 12px mono. The smaller size given under "Notes header button" was a mistake.
3. **Thread controls.** Row 1: "← All notes", the "Notify me" / "Stop notifying me" link, Close. Row 2: the group heading, with Pin on the right. Bottom of the composer: **Resolve** as a secondary button, 8px left of the Send primary; on a resolved thread it reads **Reopen**. (Resolve ends a conversation, so it sits where you finish writing; Pin and Notify change the thread's settings.)
4. **"New note".** Inside the drawer the list's own "New note" link is hidden and the header button is the one way in. In the media panel and on the stand-alone notes page the list keeps its link.
5. **Links and mentions in a note's text.** Accent stays the system's colour for links and focus; "unread for you" applies to **markers only** (dots, pills, badges, the NEW divider). A link: `text-accent`, underlined with a 3px offset, hover `text-accent-hover` (the existing link style). Another person's mention: `text-ink` at weight 500 on `bg-sunken`, `rounded-cs`, 2px side padding. A mention of the viewer: `bg-accent-tint text-accent`. (The mock still shows mentions in accent; this replaces it, and "Message" above.)
6. **Read-only viewers.** They get the block's "⋯" menu with "Add note" as its only item. The add-note icon is **not** shown at rest for anyone.
7. **Deleting a section.** With its blocks: "This section and its blocks have 3 open notes. They will be deleted too." / "…have 1 open note. It will be deleted too.", counting the notes on the blocks inside. "Remove section, keep blocks" stays instant, with no dialog and no notes sentence (see 10).
8. **Group headings.** The type as the mono label ("RICH TEXT", or "SECTION › COLUMN 2 · RICH TEXT" inside a section), then the block's **first words**: the first 4–6 words of the block's text in the current tab, 12px sans `text-dim`, one line with an ellipsis. An image: its file name. An empty block: "Block 3", its position on the page.

Four follow-ups, the same day:

9. **"Pages ▾" from 1280px.** While notes are open the tree folds at every width from 1024px. From 1280px, where there is no top bar, a "Pages ▾" button stands at the start of the page editor's breadcrumb row while notes are open; it opens the same tree drawer beside the sidebar, and Esc or picking a page closes it. (The editor then has about 592px at 1280px and 752px at 1440px.)
10. **Sections take no notes of their own.** No marker on a section card, no "Add note" in its menu: a section has no content of its own to discuss, its notes belong on the blocks inside. "Remove section, keep blocks" stays instant.
11. **The thread view's header.** While a thread is open the drawer's own header is hidden; row 1 is "← All notes 4", the Notify link and Close. "New note" comes back with the list.
12. **Mind graph card.** The document order follows the screen: title, the open notes, "Start a note…", then Open post, Focus and Pin. The keyboard rule changes with it: Enter on the selected node opens the post.

Six more, after live delivery was built:

13. **Account screen.** Name and the two note switches are **one form with one save footer**; the password keeps its own form and footer. (Name and notifications are preferences that save the same way; a password change is a separate, secure step.)
14. **The permission line** ("Allow in this browser") shows **only while the desktop switch is on**.
15. **Turning the switch on.** The info line is enough: accent-toned, with "Allow in this browser". The warn tone is for the blocked state only ("Blocked in this browser. Change it in the site settings of your browser.").
16. **The "Allow in this browser" button** is the shared small secondary button (14px/600), not the 12px/500 given above.
17. **Small screens.** Over a thread the sheet's header is hidden too, and there is one row: "← All notes 4", the Notify link, and "Back to <title>" as a text button on the right.
18. **Several notes at once.** The first two notes of a burst (within about 10 s) get their own toasts. From the third, they are replaced by one toast, "You have 3 new notes", whose Open goes to the inbox; its count updates as more arrive and its 8 s timer restarts. The sound plays once per burst.

Three more, on the combined account form:

19. **Wording.** The combined form's button reads "Save" and its toast "Settings saved" (the wording the app already uses, with no full stop). The section title is "Your account", with no extra title per card.
20. **Layout.** Two cards, Profile (the name) and Notes, inside one form at one shared width (560px), with the single save footer under both.
21. **"Back to page" in the sheet's thread row** (below 1024px): the words "Back to page", 13px/500 `text-dim`, underlined like the Notify link, with no arrow and no title.

Three more, on reactions:

22. **Where the emoji set opens.** Above the chip by default; flipped below only when there is no room above inside the thread's scroll area (the same rule as the mind graph card's placement). It is clipped to the drawer's body and never lies over row 1.
23. **Chips while a message is being edited.** They stay under the edit form, disabled (0.5 opacity, not clickable), until the edit is saved or cancelled.
24. **The add-reaction chip.** At rest it shows on hover or keyboard focus of the message (`:focus-within`), and always when the message already has reactions; "React" is also always in the message's "⋯" menu, for touch. **A resolved thread** shows its reactions read-only and takes no new ones: it is closed, and whoever wants to add something reopens it.

Three more, the same evening:

25. **The account page.** Its h1 is "Your account" (the extra h2 of item 19 goes: it would repeat the h1). Then the Profile and Notes cards with their one save footer. Below them a third card, "Password", holding its own form with its own "Change password" button and the sentence about sessions directly under the card's title. The sidebar's entry reads "Your account", and the name and avatar block above it links to the same page.
26. **The add-reaction control on a message without reactions** sits in the message's meta line: a 24×24 smile icon in `text-meta`, just left of the "⋯" menu, shown on hover or focus of the message. It costs no row at rest. Once a message has reactions, the add chip stands at the end of its chip row and stays visible.
27. **Switching edits.** One edit form at a time. The text of an edit you leave is kept as a local draft; reopening that message's Edit restores it, and a 12px `text-meta` note "Unsaved edit" stands on the message until the edit is saved or cancelled.

Two confirmations:

28. **The meta-line reaction control** is a 24×24 control holding the 16px smile icon (the composer's toolbar size), as built.
29. **"Unsaved edit"** stands in the message's meta line only. While the edit form is open with the restored text there is no line above the field: that space is for errors.
