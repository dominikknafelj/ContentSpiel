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

13. **Place:** the right end of the panel's file-name row, above the preview. 20px avatars, at most 2 and then "+N". The people stand between the file name and the "×", and the "×" stays rightmost: the file name is `flex-1 min-w-0`, then the people group (`flex-none`, `ml-auto`) 8px after the name, then the "×" 12px after the people. A long file name is cut off with an ellipsis on one line, with the full name in a `title`; the people never give way (the name is shown in full in the fields below, and a presence group that vanished on long names would be unreliable). (Asked while the slots were built, 2026-10-10.)

## Arriving, leaving, small screens

14. **Arriving and leaving:** a 150ms opacity fade with `ease-cs`, none with reduced motion. No sliding: the others snap to their new places. No toast, no sound.
15. **Below 1024px:** the editor header shows 1 circle and "+N". The full-screen notes sheet shows no presence (its header already holds Back and New note).

## Reuse, and three rules

16. **Reuse:** the actor avatar, the paper-ring overlap, the menu panel, the shared tooltip, mono counts, `ease-cs`.
17. **Never show yourself.** One person in several tabs counts once, here if any of their tabs is. Presence locks nothing and warns of nothing on save: conflicts stay with the existing save handling.

## Decisions after the header and the panel were built (2026-10-10)

Where these and the items above differ, these win.

18. **The tooltip** (CS Studio had none; icon buttons use `title`). Keep the new shared tooltip component and give it the inverted toast's look: `bg-ink text-paper`, `rounded-cs`, 12px/1.4 sans, padding 4px × 8px, at most 240px wide, no shadow, no arrow. It stands 6px below its host, centred, unless that would cross an edge of the window: then it lines up with the host's edge that has room (a collision check, not a fixed side). 300ms delay on hover, none on keyboard focus; moving from one host to another while one shows switches at once. Escape dismisses it without moving focus. Existing icon buttons move from `title` to it later, in one sweep, not in this feature.
19. **The "+N" menu's side** is fixed: left-aligned in the header, right-aligned in the media panel.
20. **The "+N" circle** has no fill (`bg-paper`; `bg-surface` in the media panel) and `border-line-strong`, so it does not read as one more person who is here. 4px before it.
21. **The menu's rows:** a 24px avatar, the name in 14px `text-ink`, the status line in 12px `text-meta`, row padding 6px × 8px. Rows are plain text, not focusable. The menu itself takes focus as one list a screen reader can read through; Escape returns focus to what opened it. The list is labelled "Everyone with this open".
22. **"+N" for a screen reader:** "2 more people" / "1 more person".
23. **Keyboard: the whole group is ONE Tab stop**, a button whose label is "Also open by 3 people: Dana Weiss, here; Jonas Lind, away 12 min…", which opens the same list as "+N". Each circle still shows its own tooltip on hover. The focus ring is a 2px accent outline with 2px offset, drawn around the group. (This replaces item 8's `role="group"` with per-avatar labels as the keyboard path; the circles are no longer Tab stops.)
24. **The media panel:** circles are centred on the first line of the file name; their 2px ring is `bg-surface`; two and then "+N" at every width (the panel is a fixed-width column).
25. **No fade out.** Someone leaving just disappears; arriving still fades in (this narrows item 14).
26. **Under one minute away:** "Dana Weiss · away just now"; after that it counts minutes, from "away 1 min".
27. **The posts list's marker** (this settles item 11): on the title's line, right after the title text, 6px after it, INSIDE the link. The title line becomes a flex row: the title with `min-w-0` and an ellipsis, then the marker (`flex-none`), which stays `text-meta` on hover like the rest of the link. The path line is unchanged. For a screen reader the marker's text joins the link's accessible name: "Translating Everything With Mobility, 2 people here". (It belongs to the post and shares its click target, and a long title is cut off before the marker is.)
28. **Opening the list.** Tab only focuses the group's button; Enter, Space or a click opens the list and moves focus into it; Escape returns focus to the group. (This replaces item 6's "focus opens it".) By mouse: a tooltip per circle and a click on the group are enough; hovering "+N" shows the list without moving focus; hovering the group does not open it (it would cover the header). The group has a pointer cursor.
29. **The group button's name** names EVERYONE, each with their status ("Also open by 5 people: Dana Weiss, here; Jonas Lind, away 12 min; …"), not only the circles shown, and without a "2 more people" part. "+N" is a visual summary inside the one control and is `aria-hidden`. (This narrows item 22: "2 more people" is not spoken.)
30. **The tooltip's collision check** is against the nearest box that scrolls or clips it, as well as the window.
31. **The group's focus ring** is `rounded-cs` (2px), not `rounded-full`: the group is a row, and 2px is CS Studio's focus shape everywhere else.
