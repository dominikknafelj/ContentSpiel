# CS Studio design pass — gaps in the design system

Written 2026-10-03, after reading the handoff (`design_handoff_cs_studio/`, design system v0.2, 16 screen mockups) against the current CS Studio code. These are the places where the handoff asks for something in words but the design system and mockups don't show it, or where two parts of the handoff disagree. Each one blocks or slows a specific piece of the build.

Group A needs a drawn pattern. Group B needs a rule. Group C is screens without a mockup. Group D is implementation notes for the designer, not requests.

## A. Patterns the handoff uses but never draws

1. **Modal / dialog.** No mockup contains one. The handoff needs it three times: confirmations (Delete now, Empty trash, Turn off language, Revoke token, Unpublish), the New page / New post modal, and the media picker. Needed: overlay, width(s), header, footer button order, the destructive variant, and how a form sits inside one.
2. **Command palette (⌘K).** The sidebar shows the "Jump to…" trigger only. Needed: the open state, a result row (page, post, setting), the grouping, the empty result and the keyboard-selected row.
3. **Flash and toast messages.** The app has a flash component today ("Saved", "Moved to trash · Undo"). The handoff has no pattern for it. Needed: where it sits, the success, warning and error looks, and the variant with an Undo action.
4. **Validation errors.** One field error is drawn (sign-in email). Needed: the error summary for a form with several errors, and the error look for a select, the chip input, the slug prefix field and the rich-text field.
5. **Loading and busy states.** AI suggestions can take up to 25 seconds, "Test connection" a few seconds, uploads longer. Needed: a busy button, the pending suggestion box, upload progress on a media tile, and the pending state for the bulk "Suggest translations for N empty fields".
6. **Pagination.** Media, Trash, Audit log and Translations page with Previous / Next today, and Posts will need it. No list mockup shows a pager.
7. **Narrow screens.** No mockup has a breakpoint. Needed: what the sidebar and the page-tree column do below desktop width (drawer, collapse, or desktop only), and whether side-by-side translation stacks.
8. **Open states of menus.** Only the editor ⋯ menu is drawn open. Needed: the Posts split-button menu, the "+N ▾" language overflow, the tag chip-input autocomplete list, the members chip multi-select, and the row ⋯ menu on Tags.
9. **Drag states.** Tree rows, blocks and language rows are draggable. Needed: the dragged row, the drop indicator and the handle's hover look.
10. **Password controls.** The handoff asks for a show/hide toggle and a strength meter "as in the setup wizard". The setup wizard has no strength meter in code, and none is drawn.
11. **Empty states.** Drawn for the dashboard cards, tokens and one settings list. Needed for: no posts, no filter results, empty media library, empty trash, "all translated", no audit events in range.

## B. Rules that are missing or contradict each other

12. **Autosave or explicit Save.** Editors autosave ("SAVED 10:42"). Settings gets "one Save per section". Group edit gets a sticky save bar with an unsaved-change count. Tags renames inline. Settings autosaves today. Needed: one rule for which kind of screen autosaves and which has a Save button, and what leaving a screen with unsaved changes looks like.
13. **Content-type colours beyond four.** The tokens give `cat-1…3` to Blog, Now update and Resume entry and `cat-4` to "custom". Content types are an open registry, so a site can have many custom types. Needed: how the fifth and later types get a colour (more tokens, a cycle, or one shared colour).
14. **Translation chip glyphs.** The handoff says outdated is "warn border + ↻" and missing is dashed. It doesn't say whether "done" keeps a ✓ or whether the dash alone must carry "missing" for colour-blind users.
15. **Live with unpublished changes.** The "Unpublished changes" chip and the "Publish changes" button depend on draft revisions, which is undecided (handoff open decision 1). Needed: the editor header for the case we are building first, where edits to a Live item go live at once.
16. **API key chip.** "Key saved · ends in 7Qx2" needs the last four characters. The app never renders any part of the key today. Needed: confirmation that showing the last four is intended, or a chip without them.
17. **Default language.** The Languages mockup has a Default radio per row. Today the default is a select in Settings › Site. Needed: confirmation that it moves, and what the warning says, since changing it marks every translation outdated.
18. **Design system page numbering.** Sections run 01–05, then 07, 08. Section 06 is missing; say whether something was dropped.

## C. Screens the handoff changes without a mockup

Described in one or two lines of prose only:

- Groups list (old 23)
- User edit and User new with group cards (old 21, 22)
- Audit event detail with field diffs (old 29)
- Change password (old 30)
- Password reset request and reset form (same layout as sign-in; not mentioned at all)
- New page and New post as modals (old 06, 11)
- Media picker modal (old 31)
- Mind graph legend and empty state (old 26)
- Setup wizard (not in the 33 screenshots; shares the sign-in layout and form classes, so it changes with them)

## D. Notes for the designer (no request)

- The handoff names ERB partials (`_status_chip.html.erb`). The app builds shared UI as ViewComponents with a Lookbook preview each; we'll build the chips, tabs and controls as components.
- `content-spiel.css` in the handoff sets `color-scheme`, renames the font files and maps `--font-sans` / `--font-mono`. We keep the repo's versions of those and take only the new `--cs-chrome` and `--cs-cat-*` tokens; no existing token value differs.
- The "[es] Welcome…" suggestion in screenshot 10 came from a test-only stub provider, not a production leak. Showing the provider and model name and making the suggestion editable are still wanted.
- Mock languages are EN / DE / SL / FR on the design system page and EN / DE / ES in the screens; the app ships en / de / es.
