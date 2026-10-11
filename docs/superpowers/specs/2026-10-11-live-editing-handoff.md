# Live refresh and edit reservations: the look

Claude Design's decisions (project "Content Spiel design system", 2026-10-11), asked in words after the behaviour (`2026-10-11-live-editing-design.md`) was agreed. They are binding for the look; where they and the design differ on a point of look, these win. Tokens and patterns are CS Studio's own.

## A block someone else holds

1. **The strip.** Between the card's header row and its form; the header row is unchanged. `bg-sunken border-b border-line px-3.5 py-2 flex items-center gap-2`: the 24px actor avatar, "Dana Weiss is editing this block" in 13px `text-ink`, and "Take over" at the right.
2. **"Take over"** is the shared small default button (an action that changes state; a link would read as navigation). It is also an item of the card's "⋯" menu, for keyboard and touch.
3. **The card's border** is `border-line-strong` while someone else holds the block.
4. **A tile in a section** shows only a 20px avatar, in the place of the add-note hover slot, before the notes marker. Its tooltip (the shared tooltip) reads "Dana Weiss is editing this block". There is no "Take over" on the tile: clicking the tile opens the block as usual, where the strip shows.

## The read-only form

5. **No lock icon and no tint on the card**: the strip says why.
6. **Fields are `readonly`, not `disabled`**, so the text stays selectable and keeps full contrast (disabled styling drops below 4.5:1). Fill `bg-paper`, border `border-line`, text `text-ink`.
7. **Rich text**: the toolbar is hidden; the editing area has the same `bg-paper` fill and no caret.

## The page settings form and a post

8. **A post** (the whole record is held): the label stands in the editor header's notice area, where "Changed elsewhere" stands today: the avatar, "Dana Weiss is editing this post" and the small "Take over" button. The forms below are read-only as in items 5 to 7.
9. **The page settings panel** shows the same strip as a block, at its top.

## A refresh

10. **The "Updated" mark**: in the card's header, after the summary: "Updated by Dana Weiss · just now" in 12px `text-meta`. It stays 6 seconds, then fades out over 200ms with `ease-cs`; with reduced motion it disappears without a fade.
11. **No highlight on the card.** The changed text simply appears (a flash on every save is noise when several people work).
12. **Added, moved and deleted blocks: no mark and no motion.** An added block appears in place, a moved one snaps to its place, a deleted one goes away. **Exception:** if the change would push the block the person is reading or editing, its position on screen is kept by adjusting the scroll.

## Notices that replace the strip

All three stand in the strip's place with its layout.

13. **(a) Taken over**: neutral, the strip of item 1 reading "Taken over by Jonas Lind · just now". After 6 seconds it becomes the ordinary strip naming Jonas.
14. **(b) A tie was lost, or the tab woke after a take-over**: the shared warn alert in the strip's position (`bg-warn-tint text-warn-ink border border-warn`, 13px): "Jonas Lind is editing this block. Your changes weren't saved." with "Copy my text" (small default button) and "Discard" (small ghost button). The person's text stays in the read-only fields.
15. **(c) Deleted while there was unsaved text**: the same warn alert: "Dana Weiss deleted this block. Your changes weren't saved." with "Copy my text" and "Remove".
16. **Why warn**: (b) and (c) can cost work. Danger stays for actions that destroy something, accent for unread.
17. **The buttons**: "Copy my text" confirms with the existing "Copied" toast. "Discard" and "Remove" act at once, with no confirmation (after copying there is nothing left to lose).

## One's own other tab

18. The layout of item 1 with the person's own avatar (`bg-ink text-paper`): "You're editing this in another tab", with the same "Take over" button.

## Screen readers

19. **A change of holder** is announced politely, in a live region on that card: "Jonas Lind took over this block".
20. **Notices (b) and (c)** have `role="alert"`: they mean lost work.
21. **The "Updated" mark** is not announced, and neither is a block that was added, moved or deleted.

## Not shown

22. No live cursors and no typing indicators (a reservation already means one person types in a block); no "Updated" mark for one's own saves; no count of held blocks in the header; no toast for a take-over, a save or a block change (everything shows on the card); nothing in the page tree or the posts list (presence covers who is on a record).
