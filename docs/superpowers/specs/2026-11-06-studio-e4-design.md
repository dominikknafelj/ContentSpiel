# CS Studio in E4

Decided with the owner, 2026-11-06: CS Studio is redesigned in direction **E4**, "colour by role", from the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). The owner then widened it to the whole of CS Studio: "i mean everything shoudl be adjusted do e4". Where this spec says "builder's call", the owner has not decided it and may overrule it.

Status: Approved, 2026-11-06 ("approved, all recommended"). Nothing is built.

The design's sources, in the artifact: `project/components/StudioCalmEditor/README.md` (the problem, the measurements, options A to E), `StudioCalmColour` and `StudioCalmColourE4E5` (E4's tokens, depth, the icon hue map, the buttons, the measured contrast; the exact values are in their `preview.html`, classes `.p4` and `.dp`), `StudioCalmDashboard` and `StudioCalmEditorE` (the staging and costs), and three pages of E4 applied: `StudioCalmE4More` (the mind graph, the posts list with its New post dialog, tags), `StudioCalmE4Setup` (Settings, the wizard's first step and its Mail step) and `StudioCalmE4Together` (notes in the rail, note markers, the inbox, presence, live editing, and the people hue). Their costs and measured contrast are under their drawings.

## Decided on 2026-11-06

The owner accepted every recommendation of the first draft; each is written into its stage below.

1. "Open threads" and "Unpublished changes" merge into "Waiting for you", with a filter for each and a "Review and publish…" action (stage 4).
2. The rail appears only when it fits. The tree never hides on its own; a button folds it away, which frees room for the rail (stage 3).
3. A tile shows its heading and two or three lines of its text (stage 2).
4. Settings come first in the document at every width (stage 3).
5. Mails take a reduced E4; the violet is the one colour allowed in the mail views, as a named exception (stage 7b).
6. The form-send fallback pages stay neutral, not violet (stage 1).
7. The form builder keeps its tabs, restyled; the media library's detail panel becomes a rail at wide widths only (stage 7a).
8. The language tabs stay at the top of the editor, above everything. The rail has three tabs, Page · Section · Notes; the notes drawer *is* the Notes tab (stage 3).
9. At wide widths a section head's words select the section and open the Section tab; below the threshold they open the settings in place; a block's own form never moves into the rail (stages 2 and 3).
10. The controller, on the builder check: the post editor takes its new layout in stage 3 with the page editor, since both use `EditorScreen::HeaderComponent`.

On approving the spec ("approved, all recommended"):

11. The mind graph's status key moves onto the legend row (stage 5a).
12. The posts list's Type, Tag and Translation filters go in a rail at wide widths (stage 5b).
13. Tags gets a detail rail for the selected tag, with Merge and Delete moved out of the ⋯ menu (stage 5b).
14. Settings gets an "At a glance" rail with the state of languages, AI, mail and images (stage 5c).
15. The wizard gets a progress bar and a welcome line on its first step, with no "time left" (stage 5c).
16. Presence in rows and in the tree is shown as avatars (stage 6).
17. The Notes screen gets a rail for open threads (stage 6).
18. Labels are the normal sans everywhere: small, sentence case, in `cs-meta`; no letterspaced mono capitals. This is the single type voice E4 takes from option C (stage 1).
19. Below the rail's threshold, notes open in a 400px panel that slides in over the canvas at elevation 3, with the same Notes tab content; the full-screen sheet is for phone widths only, below 640px (stage 3b).

## Why

The owner, on today's CS Studio:

- "the cms design is still very tiresome because of contrast issues. Like i feel like the elements are competing with the dead space for focus"
- "also the wide screen generates a lot of dead space"
- "there is content, settings, cta to add more content but it's hard do differencitate what is what"
- "same the dashboard, it's hard to understand what the individual componends too"
- "to be honest both dark and light suffer fom it"

And on the proposals:

- "i feel the colours are sill too plain"
- "D … looks the best but it's still very flat"
- "I think the icons should be more coloured, CTAs are blending into the space instead behin hightlighted"
- "i like e4"
- "also review the mind graph and the tags/blog" and "also the settings and the wizard"

What the artifact measured on main 6e7378b5 explains it. The grounds are equal (light paper against the white cards 1.10:1; dark's three grounds 1.04 to 1.14:1 apart), so lines do all the separating, and the hardest lines are the controls' (`cs-field-line`, 3.89:1 on white) while card edges are soft (1.34:1): a Rich text block is four nested outlines. Page settings, a section's settings, content tiles and the nine add buttons are bordered boxes of one weight. A tile shows only its name. At 1900px, 36% of the editor area is empty (58% at 2560px). Every dashboard card has the same 11px mono heading, so one that asks for action looks like one that informs.

**E4** answers that on D's layout (B's light touch plus a right rail at wide widths): depth from elevation tokens instead of lines; colour by role (settings in a cool rail, structure in a warm frame, content on white, adding in the violet accent); a colour per family of block-type icon; real status colour, always with its word; one solid primary button per area, tinted secondary and text tertiary buttons.

## Goals

- A person tells settings, structure, content and "add" apart by colour and place, at a glance, in both themes.
- Depth separates the planes; lines only group.
- The primary action of each area is the brightest thing in it.
- A wide window uses its width (the rail) instead of showing empty paper.
- Every CS Studio screen and surface follows E4, most of it through the shared components, so a new screen gets E4 by building from them.
- A guard keeps raw palette colours, hand-made buttons and loose icons from creeping back.

## Non-goals

- The public site's theme (`th-*`, `app/assets/tailwind/themes/`, the theme contract) is untouched.
- No behaviour changes beyond layout, except what a stage names (stage 2: one add action, tiles that preview; stage 3: choosing a section, folding the tree, notes as a rail tab; stage 4: the dashboard's merge; stage 6: the inbox's filter, presence as avatars).
- No centred column (C, E). Option C's single type voice is taken: labels in sans (decision 18).
- No navigation rail and no collapsible tree beyond what exists (E's stage 6).

## Anti-goals

- **Calmer must never mean less legible.** Every text pair stays 4.5:1 and every control edge, state mark, icon and focus ring 3:1, in both themes, measured by `test/lib/admin_contrast_test.rb`.
- Nothing breaks the save rule, the write queue, live editing or the leave guard. A form that moves (into the rail) is the same form, still sent through `app/javascript/saving/queue.js`, with its `base_updated_at`, its `data-editing-*` marks and its held state.
- No string becomes a literal. Every new heading, button and tab is a key.
- Colour is never the only cue: every status, role and type keeps its word or name beside it.

## The design, as decided

### Tokens

E4 maps onto today's token names where it can, so that stage 1 recolours every screen at once; new tokens are added for what E4 adds. All live in `app/assets/tailwind/content-spiel.css` (values, both schemes) with their `--color-*` and utility mappings in `content-spiel.tailwind.css`. The artifact's `project/tokens.json` is brought in line from the code after stage 1 ships, by an edit of the Design System (the artifact's own rule: the code is the source); this work does not change the artifact.

Today's names, E4's values (light / dark):

| Token | Light | Dark | Role |
|---|---|---|---|
| `--cs-paper` (= elevation 0) | #f3f4f7 | #14161c | the canvas behind everything |
| `--cs-surface` (= elevation 1) | #ffffff | #1d2029 | a raised card, content tiles |
| `--cs-chrome` | #ffffff | #181a21 | sidebar and tree column |
| `--cs-sunken` | #e7e9ef | #252935 | hover, badges, disabled |
| `--cs-ink` | #17191f | #e3e5ec | text |
| `--cs-dim` | #4a4f5a | #b0b6c4 | secondary text |
| `--cs-meta` | #5a6070 | #9ca2b2 | labels (sans, 12px, sentence case), dates, counts |
| `--cs-field-line` | #808797 | #7a8191 | a control's identifying edge |
| `--cs-line` | rgba(23,25,31,0.10) | rgba(255,255,255,0.08) | grouping only |
| `--cs-line-strong` | rgba(23,25,31,0.22) | rgba(255,255,255,0.16) | grouping only |
| `--cs-accent` | #6236d9 | #b49cff | violet: primary, links, focus, adding, unread |
| `--cs-on-accent` | #ffffff | #140c2e | text on the accent |
| `--cs-accent-tint` | #ece6fd | #2c2350 | secondary button fill, menu's current row |

New tokens (names are the builder's call; the values are decided):

| Token | Light | Dark | Role |
|---|---|---|---|
| field fill | #f1f3f7 | #272b36 | a text field's ground (B: fill plus a bottom edge) |
| elevation 2 (the rail) | #eaf1fb | #1f2a3d | a rail or panel: settings' cool ground |
| elevation 3 | #ffffff | #283244 | popover, menu, a dragged card |
| structure | #c98a4b | #b9824a | a section's 1.5px frame |
| structure tint / ink | #fbeedd / #7a4a12 | #3a2a17 / #f0c48f | a section's head and its words |
| live / on live | #1c7a46 / #ffffff | #5cc48f / #0f1a14 | the solid "● Live" chip |
| scheduled / on scheduled | #e8a93a / #3a2600 | #e3a650 / #2a1c00 | a scheduled date's block |
| head: action | #ece6fd / ink #45249f | #2c2350 / ink #cdbfff | a panel that asks for action |
| head: cool | #e6ecfb / ink #24418f | #22304d / ink #a9c0ff | a panel of shortcuts |
| head: warm | #fbeedd / ink #7a4a12 | #3a2a17 / ink #f0c48f | a panel that informs |
| type chip / ink | #e6ecfb / #2b50c8 | #24304f / #9db4ff | the type chip as drawn |

Shadows, one per elevation step (light; ink-tinted, two layers):

- 1: `0 1px 2px rgba(23,25,31,0.06), 0 4px 12px rgba(23,25,31,0.05)`
- 2: `0 2px 4px rgba(23,25,31,0.07), 0 12px 28px rgba(23,25,31,0.09)`
- 3: `0 3px 8px rgba(23,25,31,0.09), 0 18px 40px rgba(23,25,31,0.12)`
- 4: `0 6px 12px rgba(23,25,31,0.12), 0 28px 56px rgba(23,25,31,0.20)`

Dark lifts by lightness (each step about 1.12, 1.25 and 1.25:1 above the one below) and the shadow adds a 1px top highlight: 1 `inset 0 1px 0 rgba(255,255,255,0.04)`; 2 `inset 0 1px 0 rgba(255,255,255,0.06), 0 8px 24px rgba(0,0,0,0.35)`; 3 `inset 0 1px 0 rgba(255,255,255,0.07), 0 12px 32px rgba(0,0,0,0.45)`; 4 `inset 0 1px 0 rgba(255,255,255,0.08), 0 24px 56px rgba(0,0,0,0.6)`.

Where each level is used: 0 the canvas; 1 a card, a tile, the tree column; 2 the rail, a panel, a tile under the pointer, the primary button; 3 the focused tile (with a 2px accent ring), a menu, the add-block menu, a dialog; 4 a dragged tile, over a dashed drop place.

`--cs-ok`, `--cs-warn` and `--cs-danger` keep their roles (translated, outdated or a save that did not land, destruction and failure). E4 does not restate them; the builder keeps today's values and retunes only a pair that fails on E4's grounds. Danger stays far from the violet in hue and always says its word. `--cs-accent-hover` follows the drawn hover (the fill about 10% darker in light, 10% lighter in dark). The content-type dots (`--cs-cat-1…6`) and the graph tokens are kept and measured on the new grounds.

**Radii.** E4 ends "one 2px radius everywhere": fields 6px (top corners only, since a text field has a bottom edge), buttons 8px (small 7px), icon chips 7px, tiles 12px, cards 14px, a section frame 16px, the rail 18px. Pills stay pills. Each is a token.

**Type: one voice.** Every label (a field's label, a card's or a panel's small heading, a disclosure's summary, a table's column head, the tree's head, the wizard's step list) is Archivo at 12px, weight 500, sentence case, in `cs-meta` (6.3 / 6.4:1 on cards, 5.5 / 5.7:1 on the rail), with no tracking and no capitals. `--cs-t-label` becomes 12px and the `text-label` utility, `cs-label` and `setup_label_class` draw it; `--cs-track-mono` is no longer a label's. Mono stays for code, the Code block's fields, a token's or key's value and the save status line, which is a status, not a label ("SAVED · NOT PUBLISHED", as option C kept it). The addresses (`/de/about`) are sans at 13px. Badges (DEFAULT, OWNER, NO ALT) become sentence-case sans words on their fill.

**Measured** (the artifact, E4, light / dark): ink 17.6 / 12.9:1; meta 6.3 / 6.4:1 on cards and 5.5 / 5.7:1 on the rail; section head text 6.5 / 8.5:1; Live 5.4 / 8.3:1; scheduled 7.0 / 7.8:1; panel heads 6.5 to 8.6:1; accent 6.9 / 7.1:1, white on it 6.9:1; field edge 3.2 / 3.6:1. The section frame is 2.6:1 against the canvas: it groups, it is not a control edge, so it needs no 3:1.

### The icon hue map

Seven families; the accent and a neutral (sunken chip, dim icon) are the eighth and ninth. An icon is 14px on a 24px chip with a 7px radius (22px in a tile's and a section's head).

| Family (block types) | Icon / chip, light | on chip / on white | Icon / chip, dark | on chip / on #1b1c20 |
|---|---|---|---|---|
| Text (rich text, note) | #2a4fc6 / #e7ecfb | 5.9 / 6.9 | #9db4ff / #24304f | 6.5 / 8.4 |
| Media (image, card) | #a14a06 / #fbeedd | 5.3 / 6.0 | #f0b06a / #3a2a17 | 7.3 / 9.0 |
| Code (code, table) | #0b6a73 / #dcf0f1 | 5.4 / 6.3 | #6fd0d6 / #14353a | 7.3 / 9.5 |
| Form (form) | #1b7339 / #e0f2e5 | 5.1 / 5.9 | #7fd39a / #183622 | 7.4 / 9.5 |
| Lists (post list) | #6a35c9 / #efe8fb | 5.9 / 7.1 | #c4a8ff / #30264a | 6.9 / 8.4 |
| Structure (section) | #7a4a12 / #f4e6d4 | 6.1 / 7.5 | #e8b77e / #40301c | 6.9 / 9.3 |
| People (no block type) | #8c1d5c / #fbe6ef | 7.2 / 8.6 | #ffb8d6 / #3d2030 | 9.0 / 10.1 |

**People** mark people and talk: avatars, the read note marker, the Notes nav item, the hold strip and the frame of a held or discussed block. The rose is close in lightness to the accent (1.25:1) and to danger (1.31:1), so it is told apart by shape: people always come as a circle or a speech bubble, never as a button's fill. The accent keeps its one meaning on a marker: an unread note addressed to you is a filled accent bubble with the word "new" (6.9 / 8.2:1); a read note is an outline bubble in the people hue. Avatar initials are 11px or larger (today 9px; 7.2 / 9.0:1), and an away person's ring is a dashed edge at 3:1 or more.

At 3:1 on both a pale chip and white the icons sit in a narrow band of lightness, so hue alone tells them apart: a chip always stands beside its type's name, and the glyphs differ in shape. A family follows its type in the sidebar, a section's head, a block's head and the add-block menu. The page tree lists pages, which have no block type, and carries no chip. A block type declares its family beside its icon (`content_model/block_type_definition.rb`); a type that names none, a gem's included, gets the neutral chip.

### Buttons

- **Primary**: a solid accent fill, text 5.5:1 or better, shadow 2; **one per area**: Publish in the editor's header, "+ New page" in the tree, "+ Add block" at the foot of the blocks, "New post…" on the dashboard, a form's Save in a save bar, a dialog's confirm. Hover: the fill darkens (lightens in dark) and rises to shadow 3; focus: a 2px accent ring 2px out; pressed: sinks 1px, no shadow.
- **Secondary**: a tinted fill (`--cs-accent-tint`, words in the accent), no outline: Copy, Change address…, Reply, Review and publish…, New page….
- **Tertiary**: text in the accent: Preview, View on site.
- `danger` (a dialog's destructive confirm) and `danger_text` keep their meaning. The one disabled look stays (sunken, meta words, no accent, no opacity) and is drawn in the new radii.

The secondary button loses its outline. That is allowed because it is a button by its fill and its words, and its words reach 4.5:1 on the tint; the rule "anything pressable is outlined in `cs-field-line`" becomes "**identified by** a `cs-field-line` edge or by a fill of its own": a text field by its bottom edge, a checkbox, toggle and segmented control by full outlines, a button by its fill.

### The four roles, and status

- **Settings**: grey fields (fill plus bottom edge; the focused one gets a 2px accent outline) in the cool rail at wide widths, on the page below the rail's threshold.
- **Structure**: a section is a 1.5px structure-coloured frame (16px radius) with a structure-tinted head holding its chip, name and its settings as words ("3 columns ▾", "No background ▾"), opened on demand.
- **Content**: white tiles at elevation 1 that show their content: the type chip and name, a heading, two or three lines of text.
- **Adding**: violet. One "+ Add block" (primary) opening the existing menu at elevation 3, with each type's chip; "+ Add" under each column.
- **People**: rose, in circles and bubbles: avatars, note markers, the hold strip, a held block's frame.
- **Status**: real colour with its word. Live is a solid green chip with "● Live" (still no chip in the page tree), a scheduled date a solid amber block, Draft an outlined "○ Draft". Translation states keep their words and glyphs and are never red. Accent on a *marker* still means "unread and addressed to you"; the selected tree row's 3px accent bar is a selection, not a marker, and the design-system reference says so.

## Every screen, and its stage

Stage 1 restyles `app/components/admin/ui/` and the stylesheet once; most screens then need nothing of their own or only small class changes. "Drawn" names the artifact page that draws the screen in E4.

| Screen or surface | Its components and views | Stage | Drawn |
|---|---|---|---|
| Shell: sidebar, top bar, account | `shell/sidebar`, `top_bar`, `account_identity`, `layouts/admin` | 1 | E4E5 |
| ⌘K | `shell/command_palette`, `admin/jump` | 1 (elevation 3) | no |
| System status | `admin/system_status`, `ui/system_check_row`, `ui/insecure_notice` | 7b | no |
| Preview bar | public layout, `th-preview-*` | none (public stylesheet) | no |
| Dashboard | `dashboard_screen/*`, `admin/dashboard`, `admin/note_inbox/_card` | 4 | Dashboard, E4E5 |
| Page tree | `pages_screen/tree`, `tree_node`, `tree_state_mark`, `shell/tree_divider`, `shared/_tree_head` | 2 (markers, selection), 3 (fold) | E4E5 |
| Page editor | `editor_screen/*`, `admin/pages/show` | 2, 3 | E4E5 |
| Post editor | `editor_screen/post_form`, `related_posts`, `admin/posts/show` | 3 | E4E5 (layout) |
| Posts list, New post dialog | `posts_screen/*`, `admin/posts/index`, `editor_screen/new_post_*` | 5b | E4More |
| New page dialog | `editor_screen/new_page_*` | 1 | no |
| Tags | `admin/tags/index`, `admin--tags--dialogs` | 5b | E4More |
| Mind graph | `mind_graph_screen/*`, `admin/mind_graph`, `app/javascript/mind_graph/` | 5a | E4More |
| Settings | `settings_screen/*`, `admin/settings` | 5c | E4Setup |
| Setup wizard | `app/views/setup/`, `layouts/setup`, `setup_helper.rb` | 5c | E4Setup (first step, Mail) |
| Notes drawer → the rail's Notes tab | `notes_screen/drawer`, `list`, `thread`, `composer` | 3b | E4Together |
| Note markers, row pills | `notes_screen/marker`, `row_pill` | 6 | E4Together |
| Notes screen and inbox | `notes_screen/*`, `admin/notes`, `admin/note_inbox` | 6 | E4Together |
| Presence | `presence_screen/*`, `ui/avatar` | 6 | E4Together |
| Live editing | `editor_screen/hold_strip`, `holder_avatar`, `updated_mark`, `held_fields.rb` | 6 | E4Together |
| Media library and picker | `media_library/*`, `admin/media/index`, `picker`, `app/components/media/` | 7a | no |
| Trash | `trash_screen/*` | 7a | no |
| Translations | `translation_screen/*`, `admin/translations` | 7a | no |
| Forms: list, builder, submissions, deliveries | `forms_screen/*`, `admin/forms`, `admin/form_submissions` | 7a | no |
| Audit log | `audit_screen/*`, `admin/audit_events` | 7a | no |
| Form-send pages (visitor's fallback) | `layouts/form_send`, `app/views/form_sends/` | 1 (kept neutral) | no |
| Users, invites | `users_screen/*`, `admin/users` | 7b | no |
| Groups | `groups_screen/*`, `admin/groups` | 7b | no |
| API tokens | `tokens_screen/*`, `admin/api_tokens` | 7b | no |
| Your account | `admin/accounts/edit` | 7b | no |
| Sign-in, password reset, invitation | `admin/sessions`, `admin/passwords`, `app/views/invitations`, `layouts/product`, `shared/_auth_heading` | 7b | no |
| 403, 404 | `admin/errors` | 7b | no |
| Empty, loading and busy states, toasts, dialogs, menus, tooltips | `ui/empty_state`, `ui/toast*`, `ui/dialog`, `ui/menu`, `ui/tooltip`, `admin--ui--busy` | 1 | partly |
| Mails | `layouts/mailer.*`, `app/views/mails/_button`, the four mailers' views | 7b, reduced form | no |

### The rule for a screen the artifact does not draw

A builder decides an undrawn screen's look from E4's principles, without asking:

1. **Roles have their own look.** What a person edits or reads is content (white, elevation 1); what configures it is settings (grey fields; in a rail where it stands beside content); a group of things is structure (a frame or a tinted head, never a box of the same weight as its contents); creating is violet; people are rose circles and bubbles.
2. **One primary button per area** (a header, a panel, a dialog, a save bar). Everything else is secondary or tertiary.
3. **Depth comes from elevation**, never a new border: canvas, card, rail or panel, popover. A table is one card with grouping lines inside it.
4. **Colour carries meaning, always paired with words**: status in its status colour with its word, a type in its chip beside its name, a panel's head tinted by its kind (action, shortcuts, information).
5. **The right rail is used where a screen has settings or a record's details beside content**, only when it fits; below that it folds back into the page. Where notes open beside a record, they open as the rail's Notes tab.
6. List and system screens (Trash, Audit log, Users, Groups, Tokens, System status) get no rail: a page heading, a filter bar, one card holding the table.

## Stages

Each stage is one PR that ships working on its own, keeps the full suite green, and names its guide pages under "Documentation" (the guide is `contentspiel-docs`; screenshots are retaken there before release). A stage split into a, b and c is that many PRs.

### Stage 1: foundations

**What changes.** E4's values under today's token names; the new tokens (field fill, elevations 2 and 3, shadows 1 to 4, radii, structure, live, scheduled, panel heads, type chip, the fourteen icon tokens with people's); B's fields (fill plus bottom edge, accent outline on focus) in `.admin-column`/`.admin-field`, `.cs-select` and the rich-text box (`admin-rich-text.css`); every shared component in `app/components/admin/ui/` restyled once: `ButtonComponent` gains the E4 primary, tinted secondary and text tertiary (`ghost` becomes tertiary or is mapped onto it, builder's call), `StatusChipComponent` the solid Live and outlined Draft, `DialogComponent`, `MenuComponent`, `ToastComponent`, `TooltipComponent` the elevations, `BadgeComponent`, `CheckboxComponent`, `ChipInputComponent`, `FileDropComponent`, `SaveBarComponent`, `EmptyStateComponent`, `PaginationComponent`, `TabLinksComponent`, `LanguageTabsComponent` the radii and grounds. A new `Admin::Ui::IconChipComponent` draws an icon on its family's chip; `EditorScreen::BlockIconComponent` draws through it, and the sidebar's entries use it (Posts lists, Media media, Forms form, Notes people, the rest neutral; the current module on the accent tint). A block type declares its family.

**One type voice.** `--cs-t-label`, `text-label`, `cs-label` and `setup_label_class` become the sans label; the 78 inline uses of the mono label in 64 files are rewritten to it (mechanical, but each read, since some are badges, column heads or summaries), and every label's words are checked for sentence case in their keys (a key that holds capitals is rewritten, not its CSS). Browser tests that read upper-cased words change: Cuprite returns the rendered text, so "PAGE SETTINGS" becomes "Page settings".

**The form-send pages stay neutral.** They share the product stylesheet, so they would turn violet with everything else. `layouts/form_send.html.erb` marks its `<html>` as a plain surface, and `content-spiel.css` re-values the accent family under that mark to today's neutral ink pair (accent and its hover the ink, its tint the sunken ground, the words on it the paper), so a visitor's page carries no CMS colour; no second stylesheet. `admin_contrast_test`'s "a form's plain pages are readable" measures the re-valued pair.

**What a person sees.** Every screen at once: a cooler, slightly tinted canvas, white cards that float, violet links and buttons, coloured icons in the sidebar and editor, fields as grey wells, fewer lines.

**Tests and guards.** `admin_contrast_test` (every pair re-measured; "a line that only groups is stronger than it was" is rewritten, since E4's lines are deliberately fainter and elevation now separates; new pairs: each icon on its chip and on surface at 3:1, panel-head and structure words at 4.5:1, Live and scheduled words, the dark elevation steps), `admin_design_rules_test` (the field rule reworded; the guard below), `design_tokens_test` (product tokens in both themes, none in the theme build), the components' tests and Lookbook previews (`test/components/admin/`, `test/components/previews/admin/`), `admin_i18n_test` (the new shared component listed). Browser tests likely to move: `filter_bar_test` (38px heights, the segment frame), `field_error_border_test`, `form_width_test`, `dialogs_hang_test`, `publish_dialog_steady_test`, any test that finds a button by a class, and every test that reads a label's words in capitals.

**Architecture-review findings.** #127 (advances): the sidebar's modules, which stage 1 gives icon families, become a registry instead of the constant `Admin::BaseController::MODULES`, each entry with its permission, badge and icon family, registered like a slot (notes' and trash's badges first); +1 to 2 days, with a registry test and the sidebar's component test. #133 (advances): intention-named entry helpers (`visit_editor(record)` and the like, which already await the controllers and the live part) and the system-test rules moved from `CLAUDE.md` into `test/system/README.md` with one line and a link left behind, since this stage rewrites many browser tests anyway; +1 to 2 days. #117 (advances): the comment rule (a comment states a current invariant, hazard or reason, never a plan step, review round or what used to be there) is added to `CLAUDE.md` beside the existing convention, and every stage applies it to the comments of the files it changes, within its size.

**Size.** 10 to 15 days. **Guide.** Every page with a CS Studio screenshot; the getting-started tour first.

### Stage 2: the editor's canvas

**What changes.** The four roles in the page editor's blocks: block cards lose border and head rule, at elevation 1, 22px apart, with the type chip in the head; a section is a structure frame with a tinted head whose settings are words ("3 columns ▾", "No background ▾"), each a button that opens the section's settings in place under its head (`SectionCardComponent`, `SectionSummaryComponent`, `SectionLayoutMenuComponent`, `SectionLanesComponent`); content tiles (`BlockTileComponent`) show the chip, the heading and two or three lines of text, with hover, focused and dragging drawn by elevation; one add action: `BlockPickerComponent` becomes "+ Add block" (primary) opening the existing menu at elevation 3, plus "+ Add" under each column; the tree's markers ("○N", "↻N") hidden at rest and shown on hover, focus, the selected row and coarse pointers (kept for screen readers as the child count is), and the selected row's 3px accent bar (`TreeNodeComponent`). A block's own form stays in its panel under the lanes.

**The tile's preview.** `TileSummaryComponent` today reads one line. A block type answers a short preview (a heading and plain text, from what it already stores; rich text through its Markdown form, `docs/reference/rich-text.md`); a type that answers none, a gem's included, keeps today's summary line. The preview is escaped text: the Code block's source still reaches a page only as escaped text. This is a declaration on the block type definition, so `docs/reference/content-blocks-and-types.md`, "Adding a block type", gains a step, and the shared samples (`test/support/block_samples.rb`) a check that the preview shows one of the sample's values. The tile's face, which a save does not re-render, takes its preview from the stream that already replaces its icon (`Admin::ContentBlocksController#block_icon_streams`).

**Live editing.** The hold strip, the holder's avatar on a tile, the notes marker (`editor.block.markers` slot), the "Updated" mark and `fieldset.admin-held` keep their places and ids.

**Tests.** `admin_design_rules_test`; the editor's component tests; `contract_ledger` for the new declaration. Browser: `blocks_test`, `sections_test`, `code_block_test`, `table_block_test`, `note_block_test`, `card_block_test`, `rich_text_test`, `editor_fields_test`, `unsaved_order_test`, `editing_held_test`, `editing_live_test`, `editing_merge_test`, `notes_markers_test`, `tree_test`.

**Architecture-review findings.** #132 (advances): `app/javascript/controllers/admin/editor/blocks_controller.js` (1,180 lines), which the add action, the tiles and the section heads change, is split by concern (moving, adding, the section head, the tile), each a module of the `editor` topic with the controller kept thin; and the content-blocks controller's answers, which now carry the tile's preview beside its icon, become a responder per outcome (saved, refused, stale, held, gone) returning streams, testable without a request; +3 to 4 days, with responder unit tests and the browser tests above. #124 (advances): SortableJS is pinned `preload: false` and imported by the split moving module, as the mind graph imports its own; `test/integration/public_javascript_test.rb` gains a non-editing admin screen that loads no SortableJS; +half a day. #139 (advances): `params[:after_id]` in `Admin::ContentBlocksController` ("No view sends it any more") is deleted with its tests when the add action is rebuilt; +half a day. #133 (advances): `test/system/admin/sections_test.rb` (2,254 lines), rewritten here, is split by behaviour, its files kept in their shard (`system_test_shards_test`); +half a day to 1 day.

**Size.** 9 to 13 days. **Guide.** Editing a page, blocks, sections and columns, the page tree.

### Stage 3: the right rail (two PRs)

**3a, the rail, in the page and post editors, and the tree's fold.**

*Layout.* The editor's header, with the language tabs, stays at the top above everything. Below it, when the rail fits (the editor area at least 1200px, a container query on that area, never a window media query), a 360px rail at elevation 2 stands right of a 900px blocks column. Its tabs are **Page · Section · Notes** in the page editor and **Post · Notes** in the post editor (a post has no sections; its tags, related posts and excerpt are its settings). When the rail does not fit, it folds back into the page: the page's or post's settings above the blocks, sections' settings in place, and Notes the 400px overlay panel of 3b. A translation tab (`--cs-form-max-pair`) folds the rail too.

*Tab order.* Settings come first in the document at every width: header, then the rail, then the blocks. At wide widths a grid places the rail on the right; it is never moved by script, and the focus goes header, settings, blocks.

*The page's settings* (`PageSettingsFormComponent`, the post's settings in `PostFormComponent`) live in the rail's first panel, one form with its ids, `data-editing-*` marks, live region and save-bar wiring, so a save's answer, a refresh (`editing/merge.js`) and a hold reach it. Every write still goes through the queue.

*Choosing a section.* At wide widths, pressing a section head's words ("3 columns ▾") selects the section: its frame takes a 2px accent outline and the rail opens its Section tab with that section's settings. The head's words are the only target that selects. They are buttons (`aria-controls` the Section panel, `aria-expanded`); the frame's ground, a tile, a tile's handle, a lane and "+ Add" do not select: a tile's press keeps opening its block's panel and a drag starts only from a tile's handle, so a drag never selects. With no section chosen the Section tab says "Choose a section" (a key). The section's settings form is one element: at wide widths a selection moves it into the Section panel and a deselection, a fold of the rail or a Turbo snapshot (`turbo:before-cache`) puts it back under its head, never cloned, so its id, held state and save answers stay with it. Below the threshold the words open it in place, as in stage 2. A block's form never moves into the rail.

*The tree's fold.* The rail appears only when it fits; the tree never hides on its own. A button at the tree's head ("Hide page tree", a key) folds the tree to a narrow strip with a button that unfolds it; folding frees its width, and the rail appears if it now fits. The fold is a state of the tree's width, so it has the same two writers as `--admin-tree-width` and `data-tree-fits` today: the layout's head script (which reads the remembered fold before first paint, so nothing jumps) and `admin--shell--tree-width` (which folds, unfolds and remembers the choice where it keeps the width). Folded, the property is the strip's width and `<html>` carries the fold as a data attribute those two write; nothing else writes any of the three, and the rail's container query only reads the area's width. The existing drawer below the shell's breakpoint is unchanged.

*The left alignment rule, changed.* Today every form starts at the content area's left edge, the editor column is `--cs-form-max` (760px), and `admin_design_rules_test` refuses `mx-auto` in the shell and holds the widths to tokens written once. After 3a the blocks column and the rail are **one left-aligned group** (the blocks column at the content's left edge, the rail right beside it, 28px apart); neither is centred, and any empty space falls right of the rail. `mx-auto` stays refused (the 403 and 404 alone). The 900px column and the 360px rail become tokens beside `--cs-form-max`, each written once in `content-spiel.css`, held by the test "the form column's width is a token". `.admin-form-column` stays a class on elements that exist, never a new wrapper around an editor's unit.

*Tests.* `admin_design_rules_test` (the widths, the fold's writers if a static check is cheap); browser, at a wide and a narrow window each: `tree_column_test`, `tree_test`, `form_width_test`, `translation_layout_test`, `editor_header_test`, `sections_test`, `editing_claims_test`, `editing_holds_test`, `autosave_test`, `autosave_unload_test` (the leave guard), and for the post editor `drafts_test`, `chip_input_test`, `new_record_test`, `tokens_related_posts_and_starter_pages_test`.

*Architecture-review findings.* #123 (closes): the page tree, whose rows and fold this stage changes, selects only its columns and filters `where(id: visible_ids)` in SQL with trashed pages excluded, instead of `Page.all.to_a.select`; after a settings save, which now comes from the rail, only the changed row is replaced, and the whole tree only after a move; a statement-count test at two tree sizes, like the posts table's; +2 to 3 days. #139 (advances): the post form's "legacy comma-separated" tag string in `Admin::PostsController` goes when the post editor's settings move into the rail, since the chip input sends an array; +half a day.

*Size.* 11 to 14 days.

**3b, notes as the rail's Notes tab.** The drawer's parts are reused as they are (`ListComponent`, `ThreadComponent`, `ComposerComponent`, the live merge in `notes/merge.js`); the Notes tab hosts the drawer's frame. Opening notes (the header button, a marker) switches the rail to Notes, and nothing else on the page moves. The open state moves from `data-notes-open` on `<html>` to the rail's tab, and the 400px column and its width rules in `content-spiel.tailwind.css` go. Below the threshold, notes open in a 400px panel that slides in from the right over the canvas at elevation 3 (shadow 3), with the same Notes tab content; it is not modal (no scrim, nothing inert, Escape closes it while the focus is inside, as the drawer today) and nothing under it moves. Below 640px, a phone's width, it is the full-screen sheet with a way back. Messages, mentions and Reply in E4 (measured: message text 17.6 / 12.9:1, times 6.3 / 6.4:1, your own mention 5.7 / 6.3:1, Reply 6.9 / 8.2:1, composer edge 3.2 / 3.6:1). Tests: `notes_drawer_test`, `notes_column_test`, `notes_flow_test`, `notes_live_test`, `note_composer_test`, `tree_column_test`, `notes_boundary_test` if the header's wording moves, at a wide, a mid and a phone width. *Architecture-review findings.* #127 (advances): the rail's tabs are a new slot shape, an editor panel (`editor.rail.tabs`, a tab and its panel, re-rendered by id after a save as the block icon is), and notes register the Notes tab through it in `config/initializers/admin_slots.rb`, so the rail does not name notes (`notes_boundary_test` holds it); +1 to 2 days. #132 (advances): moving notes into the rail reuses `notes/merge.js`; its kept-element core and `editing/merge.js`'s become one `live/keep_merge.js` (id-keyed replace around kept elements), each feature keeping its own "what is kept" predicate, and the two `mergeList` exports with two contracts end; +1 to 2 days, with the merge module tests of both. *Size.* 7 to 12 days.

**Guide.** Editing a page and a post (the rail), page settings, sections, notes, the page tree.

### Stage 4: the dashboard

**What changes.** Each panel headed by its job, with one line under it, its head tinted by kind: action ("Waiting for you", "Notes for you"), shortcuts ("Pick up where you left off": your drafts as tiles), information ("Publishing on its own", "Languages behind English", "What changed recently"). Action rows end in a verb. **"Open threads" and "Unpublished changes" merge into "Waiting for you"**, with a filter for each (a segmented control over the panel: Everything, Open threads, Unpublished changes; keys) and "Review and publish…" on an unpublished row. What needs you and your drafts fill the main column; information stands in the rail when it fits, without a card. "New post…" is the screen's one primary, "New page…" secondary beside the heading, replacing the quick-create row (`QuickCreateComponent`). Scheduled dates are amber blocks; status in its colour and word.

**Files.** `app/views/admin/dashboard/show.html.erb`, `Admin::DashboardScreen::*`, `app/views/admin/note_inbox/_card` and `_open_threads`, `app/queries/dashboard/` (one query answers the merged panel's rows from `Dashboard::OpenThreads` and `Dashboard::Feed#unpublished_changes`, each still hiding what the viewer may not read). The rule "the dashboard's grid is one, two or three columns by its container" is rewritten for the main column and rail.

**Tests.** `admin_design_rules_test` (the grid rule), dashboard component and query tests, `admin_i18n_test`; browser: `dashboard_test`, `note_inbox_test`, `unpublished_changes_test`, `drafts_test`, `presence_lists_test`.

**Two shell changes, added by the owner on 2026-11-06.** They ride with this stage because it is the next one built; neither touches the dashboard.

- *The theme switch fades.* Switching between light and dark cross-fades the whole page through the View Transitions API (`document.startViewTransition`), about 250ms, ease-out; the duration and easing are a token written once, in the `::view-transition-old(root)` and `::view-transition-new(root)` rules. It is instant where the API is missing and under `prefers-reduced-motion: reduce`, and the first paint (`shared/_theme_head`) never fades. `aria-checked` and the focus change at once, not after the fade. It covers CS Studio's three-way switch, the public footer's toggle (`theme_controller.js` serves both; if the public build cannot carry the rule without touching the theme contract, the public toggle takes the browser's default cross-fade) and an OS change while the choice is Auto. Tests: a browser test that pressing Dark calls the transition (a spy on `startViewTransition`) and that reduced motion does not; the theme tests never wait on an animation. +half a day.
- *Every sidebar module has a colour family.* No chip in the sidebar is neutral. From the seven families (accent stays reserved for the current module and "unread and addressed to you"): Dashboard, Pages and Mind graph structure; Posts and Tags lists; Media media; Forms form; Translations text; Users and Groups people; Trash, Settings, AI assistant, System status and Audit log code. `StudioModules.register` refuses a module without a family, so a gem's module declares one; the selected row keeps its chip's colour; `admin_contrast_test` measures every family's chip on the sidebar's ground at 3:1 in both themes. +half a day.

**Size.** 4 to 6 days. **Guide.** The dashboard; the sidebar's screenshots.

### Stage 5: the screens drawn on E4More and E4Setup (three PRs)

Each is built as drawn, with the owner's answers to the pages' own questions (decisions 11 to 15).

- **5a, the mind graph.** Mostly tokens: `theme.js` reads `--cs-*`, so the canvas follows; the `LOOKS` table, `LINE_STYLES` and the dim factor change in `marks.js` and `renderer.js`; the legend, the list and `node_list.js` gain icon and status chips; the card's buttons become the shared button; the status key moves from its dialog onto the legend row (the dialog may stay for the long words). Pages stay neutral (the hues mean post types); every status keeps its shape and word; the script holds no colour value. The related lines, which fail today (2.25 / 2.93:1), reach 3.9 / 4.3:1; post hues 5.9–7.1 / 8.1–9.1:1, tags 6.2 / 8.9:1, tree lines 3.8 / 4.5:1, the selection ring 6.9 / 7.1:1. The CSS marks outside the canvas change with `marks.js` (no guard holds them). Tests: `admin_contrast_test` (graph tokens), `mind_graph_guards_test`, `mind_graph_test`, `mind_graph_modules_test` (its 25-drawing test keeps the looks apart). Findings: #132 (advances), `mind_graph/app.js` (1,433 lines), whose legend and list change, is split into state, input and render modules, the guards on `reset()` and the ids unchanged; +2 to 3 days. #133 (advances), `mind_graph_test.rb` (3,900 lines) and `mind_graph_modules_test.rb` (2,739) split by behaviour within their shards; +1 day. *Size* 7 to 10 days.
- **5b, the posts list with its New post dialog, and tags.** Posts: the shared chips already carry most of it; the toolbar follows the field rules; the dialog is a field and a button; at wide widths the Type, Tag and Translation filters stand in a rail beside the list, the same filter form (`admin--ui--auto-submit`), above the list below the threshold. Tags: the row and its autosaving input restyled, a usage bar (structure hue, 6.2 / 8.9:1) from the count already read; Tags has no primary, since tags are made on posts; a detail rail shows the selected tag, its posts (the posts query by tag) and Merge into… and Delete tag… as buttons, out of the ⋯ menu, opening the existing two dialogs. Tests: `posts_list_test`, `filter_bar_test`, `new_record_test`, `tags_test`, plus a keyboard test for each rail. *Size* 6 to 9 days.
- **5c, Settings and the setup wizard.** Settings saves explicitly: its save bar is the one primary area, floating at the foot of the column and naming what changed; a changed field carries a violet edge (6.9 / 7.1:1) from the save bar's existing dirty tracking; cards and nav restyled; an "At a glance" rail shows the state of languages, AI, mail and images from what the cards already compute (`MailSettings`, the AI test result, the images' progress), a component and not a query. The wizard keeps one primary per step (Continue), Back and Skip for now as text buttons, "Optional" in words; the current step violet on its tint, a done step's green check; a progress bar (6.9 / 7.1:1 against its track), static per step, and a welcome line on the first step; no time left. Tests: `settings_test`, `settings_mail_test`, `settings_images_test`, `ai_settings_test`, `languages_test`, the setup tests. *Size* 4 to 7 days.

**Guide.** The mind graph, posts, tags, Settings, first-time setup.

### Stage 6: working together

Drawn on `StudioCalmE4Together`; three parts in one PR, because they share the people hue and the avatar.

- **Note markers and presence** (2 to 4 days): `NotesScreen::MarkerComponent`, `RowPillComponent`, `Admin::Ui::AvatarComponent` and `PresenceScreen::RowMarkerComponent` are the shared parts, so the look reaches every screen at once: unread as the accent bubble with "new", read as the rose outline bubble, initials at 11px. The presence slots (`tree.row.markers`, `posts.row.markers`) draw avatars instead of an icon and a count, from what the loader already returns.
- **The Notes screen and inbox** (2 to 3 days): `InboxRowComponent` and `OpenThreadRowComponent` gain the avatar and the type chip; a mentions filter is a scope on `Dashboard::NotesForYou`'s query (mentions are already a delivery kind); the Notes screen gets a rail of open threads that reuses `Dashboard::OpenThreads`; "● New" 5.7 / 6.3:1.
- **Live editing** (2 to 3 days): `HoldStripComponent` on the people tint (14.8 / 11.5:1), `HolderAvatarComponent`, `UpdatedMarkComponent`, and a held or discussed block in a people frame (a card class, 8.6 / 10.1:1 against the card). The rules the tests hold do not change: read-only at full contrast, no lock, warn for lost text, arrivals fade in and nobody fades out.

Notes never write the record, names are text, links into the notes frame do not prefetch, presence and notes stay in their slots. Tests: `notes_markers_test`, `note_inbox_test`, `messages_test`, `presence_test`, `presence_lists_test`, `editing_held_test`, `editing_take_over_test`, `editing_merge_test`, `changed_elsewhere_test`, `notes_boundary_test`, `held_fields_test`, the slot tests. **Architecture-review findings.** #140 (closes): the avatars and names this stage redraws read one short name: `Notes.name_of`, a pure alias, is inlined to `PersonName.of` at its nine call sites and its `CLAUDE.md` bullet deleted, and `User#display_name` is renamed to say that it returns the whole address when there is no name (builder's call of the name); +half a day, with the name tests. **Size.** 7 to 11 days. **Guide.** Notes, working with others, taking over.

### Stage 7: every remaining screen (two PRs)

By the rule above.

- **7a, content-side:** the media library and picker (the panel, the selected image's form, becomes a rail at elevation 2 at wide widths only, with an Image · Notes pair of tabs; at narrower widths it stays the column it is; the grid's tiles at elevation 1), Trash, Translations (the matrix in one card; states in their words, never red), forms (the builder keeps its tabs, restyled; list, submissions, deliveries), the audit log. Browser: `media_library_test`, `media_picker_test`, `trash_test`, `translations_test`, `translation_status_test`, `form_builder_test`, `audit_log_test`, `note_files_test`. 4 to 6 days.
- **7b, people and system:** users and invites, groups (the permission matrix), API tokens, your account, system status, sign-in, password reset, invitation, the 403 and 404, and the mails. Browser: `users_test`, `groups_test`, `groups_editor_test`, `groups_members_test`, `invites_test`, `password_reset_test`, `account_password_answer_test`, `system_status_and_preview_test`, `view_only_test`. 3 to 5 days.

**Mails, a reduced E4.** Mail clients read no stylesheet, drop custom properties, and many ignore shadows, radii and dark-mode rules. The mail keeps the white card on a light ground, ink text and the site's name as text, and gains one solid violet button (`mails/_button`) with white words (6.9:1) and an 8px radius; no shadow, no chips, no dark scheme. The violet, `#6236d9`, is the one colour literal allowed in the mail views (`layouts/mailer.*`, `app/views/mails/`, the mailers' views), a named exception in `admin_design_rules_test` that admits that value and no other; every other colour there stays named, as today.

**Guide.** Media, trash, translations, forms, the audit log, users and groups, tokens, your account, signing in, the mails.

**Total.** About 14 to 21 weeks in seven stages (twelve PRs), of which about 3 to 4 weeks are the architecture-review findings below.

## Architecture-review findings

The rule (the owner's): when a stage changes the code an open finding covers, that finding, or its part in that code, is done in the stage. Checked against every open issue labelled `architecture-review` on 2026-11-06. None of the parts taken changes what a person sees.

| Issue | Stage | Closes or advances | Why |
|---|---|---|---|
| #123 the page tree reads every page and is redrawn on every settings autosave | 3a | closes | 3a changes the tree (the fold) and moves the settings form whose save redraws it |
| #124 admin scripts on demand, a public import map | 2 | advances: SortableJS on demand; lazy registration, Tiptap and the public map remain | 2 splits the blocks controller that imports SortableJS; no stage changes `controllers/index.js`, Tiptap's pins or the public layout |
| #127 slots fit one shape | 1, 3b | advances: the module entry (1), the editor panel (3b); the list column and save-answer contributions remain | 1 restyles the sidebar's modules; 3b adds the rail's tabs, an editor panel by definition |
| #132 split the largest scripts and controllers, one merge core | 2, 3b, 5a | advances: blocks controller and block answers (2), one merge core (3b), `mind_graph/app.js` (5a); `hold_controller.js`, `table_controller.js`, the rich-text editor controller and the posts and pages controllers remain | each is a file its stage rewrites |
| #133 lower the entry cost of a system test | 1, 2, 5a | advances: entry helpers and the rules' own file (1), `sections_test` (2), the mind graph's two files (5a); shorter names remain | E4 rewrites those tests |
| #117 comments about invariants | every stage | advances: the rule in `CLAUDE.md` (1), and each stage's touched files | a stage that rewrites a file rewrites its comments |
| #139 compatibility code before the first release | 2, 3a | advances: `after_id` (2), the comma tag string (3a); the old reset link, `SITEMAP_HOST` and the ActionText import remain | 2 rebuilds the add action, 3a the post form; 7b restyles the reset views but not the legacy route |
| #140 one name for a person's short name | 6 | closes | 6 redraws every avatar and name |

Open findings that do not match E4: #110 (versioning), #112 (registries emptied before a gem registers), #114 (content types are code-only), #115 (integrator kit), #116 (a library-image field type), #120, #121 and #122 (the public site's caches and reads), #128 (a routes hook), #129 (a plugin's tables), #130 (audit events as an extension point), #131 (conformance checks for gems), #135 (local setup), #136 (client sites' appearance), #138 (environment variables), #141 (MCP tools), #143 (Solid Cable polling): none is in code a stage changes. #119 (the reference docs' structure): E4 rewrites paragraphs of `design-system.md` and `cs-studio-shell-and-dashboard.md`, not their structure. #137 (the dev seed's block types): no stage changes `db/seeds.rb`, though seeding every type would help check stage 2's previews by eye. #142 (a new site's one language): it would change what the wizard and the dashboard show, a decision E4 does not take.

## The guard after E4

`test/lib/admin_design_rules_test.rb` checks today: no hex, `rgb()` or `hsl()` in CS Studio's sources; no `dark:` variant but `dark:scheme-dark`; no danger in translation chips, tabs, tree markers, the matrix and the dashboard's cards; the replaced components gone; no `mx-auto` but the 403 and 404; a pressable element outlined in `border-field-line`, never `border-line-strong` (with an allow-list); no text under 11px, a label `text-label` (today mono capitals); the disclosure's triangle; the form column's widths and the filter bar's height as tokens written once; the dashboard's grid.

After E4 it also holds, each with a test that proves its pattern can fail:

- **No Tailwind palette colour** in CS Studio's sources (`bg-violet-600`, `text-gray-500`, any `-{50…950}` step of a named palette, `white`/`black` utilities): a colour is a token. The mail views' one literal is the named exception above.
- **A shadow is an elevation token** (no `shadow-sm`, `shadow-lg`, arbitrary `shadow-[…]`), and **a radius is a radius token** (no `rounded-md`, `rounded-[…]`, beyond the pill).
- **Buttons only through `Admin::Ui::ButtonComponent`**: outside it, the checkbox, the count pill and the unread bubble, nothing carries an accent fill (`bg-accent`) or the secondary's tint-and-accent pair, with a named allow-list like `STRONG_LINE_ALLOWED`. "One primary per area" cannot be read statically; review holds it.
- **Icons only through the chip**: the `--cs-ic-*` tokens and their utilities appear only in `IconChipComponent` and the stylesheet, and a block type's icon is drawn only through `BlockIconComponent`.
- **People are circles and bubbles**: the people tokens appear only in the avatar, the note marker and row pill, the presence marker, the hold strip, the people frame's class and the icon chip, and never in `ButtonComponent` or on a fill beside a button's classes. Avatar initials join the 11px rule, which today an avatar escapes.
- **Status colours only in the status components**: the live, scheduled, ok, warn and danger fills appear only in the status, translation, unpublished and channel chips, the scheduled date and the alerts, each of whose tests asserts its word.
- **One type voice**: no `uppercase` with a `tracking-*` in CS Studio's sources, no `font-mono` outside an allow-list (code, the Code block's fields, a token's or key's value, the save status line), and every label through `text-label` (sans, 12px, `cs-meta`); the 11px floor stays.
- **The new widths written once** (the 900px column and the 360px rail), and the reworded field rule: identified by a `cs-field-line` edge (a text field's bottom edge, a full outline on a checkbox, toggle or segmented control) or by a fill of its own.

`admin_contrast_test` measures the new pairs (above), the people pairs and the form-send pages' neutral re-values. `docs/reference/design-system.md` is rewritten with each stage, its "Rules a change can break silently" included.

## Constraints

From `CLAUDE.md` and the reference files; each binds this work.

- **Components go in their folders.** A component used by more than one screen (the icon chip, the rail, shared by the editors, the dashboard and the media library) is in `app/components/admin/ui/`; a screen's own stays in the screen's folder; nothing loose in `app/components/admin/` (`source_layout_test`). Never define `Admin::<Domain>`.
- **Admin strings are keys**, in `config/locales/admin/<folder>.en.yml` ("Choose a section", "Hide page tree", the rail's tabs, the dashboard's headings and filters); a script's words from `data-messages`; new components join `admin_i18n_test`'s lists.
- **Stimulus conventions.** The rail's and the section choice's controllers sit under `controllers/admin/<topic>/`, their identifiers following their paths; the fold is a new action of `admin--shell--tree-width`, not a second controller. A rename is searched for in the tests by hand. No inline handlers (`inline_handlers_test`).
- **No Turbo morphing**, no `turbo_refreshes_with`, no `broadcast_refresh` (`notes_guards_test`); the rail is redrawn part by part like everything else.
- **The write queue, the save rule, live editing and the leave guard** as in the anti-goals; content screens autosave, configuration screens save explicitly.
- **Design questions are the owner's.** A look this spec does not settle goes to the Design System artifact, not to the builder alone.
- **WCAG AA in both modes**, measured, not judged.
- **The silent rules of the shell, tree, editor, notes and mind graph:** `--admin-tree-width` and `data-tree-fits` (and now the fold) are written by the layout's head script and `admin--shell--tree-width` alone; whatever a script moves or writes into the page is put back before Turbo's snapshot (the section form in the rail, as the mind graph's `reset()` does for the graph); `PostGraph.node_id`, `mind_graph/ids.js` and the `"tag-"` prefix stay in step; the graph's CSS marks and `marks.js` change together, as do the status key's words and the chip's; whatever can be pressed on the canvas has a row in the list beside it; the publish, discard and cancel dialogs stay outside the part a save's answer replaces; every block move goes through `admin--editor--blocks#move` in the queue; code asks `capability?(:container)`, never `block_type == "section"`; a list or count of notes narrows through `Notes.readable_threads`; a test that asserts a controller's absence by a fragment of its name checks nothing after a rename.

## Left to the builder

Token names for the new values; whether `ghost` is renamed tertiary; how a type declares its preview; the rail's markup and its tabs' controller; the plain-surface mark's name on the form-send layout; the container query's exact form; how `ok`, `warn` and `danger` are retuned if a pair fails; which allow-list entries the new guard needs. Each is written into the plan, and any that changes what a person sees goes to the owner first.
