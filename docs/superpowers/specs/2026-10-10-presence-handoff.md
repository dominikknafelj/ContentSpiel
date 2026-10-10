# Presence: the look

Claude Design's decisions for presence (project "Content Spiel design system", 2026-10-10), asked in words after the design (`2026-10-10-presence-design.md`) was approved. They are binding for the look; where they and the design differ on a point of look, these win. Tokens and patterns are CS Studio's own.

## People in an editor's header

1. **Initials in circles**, the existing actor avatar at 24px: round, `bg-sunken`, `border border-line-strong`, initials in 9px mono `text-ink`. Each circle has a 2px ring in `--cs-paper` and overlaps the one before it by 6px.
2. **Place:** first in the header's action row: people, a 12px gap, the saved status, Notes, Preview, "⋯" / Publish. (Names do not fit in the row; the people say who else is here, so they come before the status that says what has happened.)
3. **One neutral style for everybody**, no colour per person: the `cat-n` colours mean content types and accent means unread.
4. **Away:** the same circle with no fill (`bg-paper`), `border-line`, initials in `text-meta`. Here keeps the full style. Nobody gets a status dot (a green dot would borrow `ok`, which means Live; lower opacity would drop the initials below contrast). Here to away changes at once, with no fade.
5. **Order:** people who are here before people who are away, each group in order of arrival, earliest first, so nobody reshuffles while you work.
6. **Overflow:** 3 circles, then "+N": a circle of the same size with "+2" in 10px mono `text-dim`, not overlapped. Hover, focus or click on it opens the existing menu panel listing everyone (avatar, name, status line) in the same order; Escape closes it.
7. **Hover and focus text:** the shared tooltip (the one on icon buttons, which shows on keyboard focus; never a `title`). Here: "Dana Weiss · here". Away: "Dana Weiss · away 12 min", and "away over an hour" after 60 minutes. A person with no name is the part of the email address before the at sign, as in notes.
8. **Screen readers:** each avatar's `aria-label` repeats its tooltip text, and the group is labelled "Also open by 3 people" (with its singular). No live-region announcement: presence is background information, not an event.

## The marker in a tree row and a posts row

9. **The marker:** a Lucide `user` icon at 12px in `text-meta`, shown only when someone else is here. Away people do not count. With two or more people here, the count follows in 10px mono with a 4px gap ("👤2").
10. **Tree row:** last, after the translation markers and the notes pill, with a 6px gap, so the existing markers keep their places. It shows in the folded tree (the "Pages ▾" menu) too: it is the same row component.
11. **Posts list:** inside the Title cell, right after the title; no column of its own.
12. **Hover and focus:** the same shared tooltip, listing the names.

## The media library's image panel

13. **Place:** the right end of the panel's file-name row, above the preview. 20px avatars, at most 2 and then "+N".

## Arriving, leaving, small screens

14. **Arriving and leaving:** a 150ms opacity fade with `ease-cs`, none with reduced motion. No sliding: the others snap to their new places. No toast, no sound.
15. **Below 1024px:** the editor header shows 1 circle and "+N". The full-screen notes sheet shows no presence (its header already holds Back and New note).

## Reuse, and three rules

16. **Reuse:** the actor avatar, the paper-ring overlap, the menu panel, the shared tooltip, mono counts, `ease-cs`.
17. **Never show yourself.** One person in several tabs counts once, here if any of their tabs is. Presence locks nothing and warns of nothing on save: conflicts stay with the existing save handling.
