# CS Studio in E4

Decided with the owner, 2026-11-06: CS Studio is redesigned in direction **E4**, "colour by role", from the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT). The owner then widened it to the whole of CS Studio: "i mean everything shoudl be adjusted do e4". Where this spec says "builder's call", the owner has not decided it and may overrule it.

Status: spec. Nothing is built.

The design's sources, in the artifact: `project/components/StudioCalmEditor/README.md` (the problem, the measurements, options A to E), `StudioCalmColour` and `StudioCalmColourE4E5` (E4's tokens, depth, the icon hue map, the buttons, the measured contrast; the exact values are in their `preview.html`, classes `.p4` and `.dp`), `StudioCalmDashboard` and `StudioCalmEditorE` (the staging and costs). A page for the mind graph, posts, tags, Settings and the setup wizard in E4 (`StudioCalmE4More`) was not published when this was written: stage 5 takes its look from that page once it is.

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
- No behaviour changes beyond layout, except what a stage names (stage 2: one add action, tiles that preview; stage 3: choosing a section shows its settings in the rail; stage 4: the dashboard's grouping, and the merge if the owner confirms it).
- No single type voice (option C's sans labels) and no centred column (C, E). Mono labels stay.
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
| `--cs-meta` | #5a6070 | #9ca2b2 | labels, dates, counts |
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

**Measured** (the artifact, E4, light / dark): ink 17.6 / 12.9:1; meta 6.3 / 6.4:1 on cards and 5.5 / 5.7:1 on the rail; section head text 6.5 / 8.5:1; Live 5.4 / 8.3:1; scheduled 7.0 / 7.8:1; panel heads 6.5 to 8.6:1; accent 6.9 / 7.1:1, white on it 6.9:1; field edge 3.2 / 3.6:1. The section frame is 2.6:1 against the canvas: it groups, it is not a control edge, so it needs no 3:1.

### The icon hue map

Six families; the accent and a neutral (sunken chip, dim icon) are the seventh and eighth. An icon is 14px on a 24px chip with a 7px radius (22px in a tile's and a section's head).

| Family (block types) | Icon / chip, light | on chip / on white | Icon / chip, dark | on chip / on #1b1c20 |
|---|---|---|---|---|
| Text (rich text, note) | #2a4fc6 / #e7ecfb | 5.9 / 6.9 | #9db4ff / #24304f | 6.5 / 8.4 |
| Media (image, card) | #a14a06 / #fbeedd | 5.3 / 6.0 | #f0b06a / #3a2a17 | 7.3 / 9.0 |
| Code (code, table) | #0b6a73 / #dcf0f1 | 5.4 / 6.3 | #6fd0d6 / #14353a | 7.3 / 9.5 |
| Form (form) | #1b7339 / #e0f2e5 | 5.1 / 5.9 | #7fd39a / #183622 | 7.4 / 9.5 |
| Lists (post list) | #6a35c9 / #efe8fb | 5.9 / 7.1 | #c4a8ff / #30264a | 6.9 / 8.4 |
| Structure (section) | #7a4a12 / #f4e6d4 | 6.1 / 7.5 | #e8b77e / #40301c | 6.9 / 9.3 |

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
- **Status**: real colour with its word. Live is a solid green chip with "● Live" (still no chip in the page tree), a scheduled date a solid amber block, Draft an outlined "○ Draft". Translation states keep their words and glyphs and are never red. Accent on a *marker* still means "unread and addressed to you"; the selected tree row's 3px accent bar is a selection, not a marker, and the design-system reference says so.

## Every screen, and its stage

Stage 1 restyles `app/components/admin/ui/` and the stylesheet once; most screens then need nothing of their own or only small class changes. "Drawn" is whether the artifact draws the screen in E4.

| Screen or surface | Its components and views | Stage | Drawn |
|---|---|---|---|
| Shell: sidebar, top bar, account | `shell/sidebar`, `top_bar`, `account_identity`, `layouts/admin` | 1 (nav icon chips: 1) | yes |
| ⌘K | `shell/command_palette`, `admin/jump` | 1 (elevation 3) | no |
| System status | `admin/system_status`, `ui/system_check_row`, `ui/insecure_notice` | 6b | no |
| Preview bar | public layout, `th-preview-*` | none (public stylesheet) | no |
| Dashboard | `dashboard_screen/*`, `admin/dashboard`, `admin/note_inbox/_card` | 4 | yes |
| Page tree | `pages_screen/tree`, `tree_node`, `tree_state_mark`, `shell/tree_divider`, `shared/_tree_head` | 2 (markers, selection), 3 (threshold) | yes |
| Page editor | `editor_screen/*`, `admin/pages/show` | 2, 3 | yes |
| Post editor | `editor_screen/post_form`, `related_posts`, `admin/posts/show` | 5 | later page |
| Posts list | `posts_screen/*`, `admin/posts/index` | 5 | later page |
| New page / New post dialogs | `editor_screen/new_*` | 1 | no |
| Tags | `admin/tags/index`, `admin--tags--dialogs` | 5 | later page |
| Mind graph | `mind_graph_screen/*`, `admin/mind_graph`, `app/javascript/mind_graph/` | 5 | later page |
| Media library and picker | `media_library/*`, `admin/media/index`, `picker`, `app/components/media/` | 6a | no |
| Trash | `trash_screen/*` | 6a | no |
| Translations | `translation_screen/*`, `admin/translations` | 6a | no |
| Notes, inbox, drawer | `notes_screen/*`, `admin/notes`, `admin/note_inbox` | 6a (drawer's place: 3) | no |
| Presence | `presence_screen/*` | 1 | no |
| Forms: list, builder, submissions, deliveries | `forms_screen/*`, `admin/forms`, `admin/form_submissions` | 6a | no |
| Form-send pages (visitor's fallback) | `layouts/form_send`, `app/views/form_sends/` | 1 (tokens only) | no |
| Users, invites | `users_screen/*`, `admin/users` | 6b | no |
| Groups | `groups_screen/*`, `admin/groups` | 6b | no |
| API tokens | `tokens_screen/*`, `admin/api_tokens` | 6b | no |
| Audit log | `audit_screen/*`, `admin/audit_events` | 6a | no |
| Settings | `settings_screen/*`, `admin/settings` | 5 | later page |
| Your account | `admin/accounts/edit` | 6b | no |
| Setup wizard | `app/views/setup/`, `layouts/setup`, `setup_helper.rb` | 5 | later page |
| Sign-in, password reset, invitation | `admin/sessions`, `admin/passwords`, `app/views/invitations`, `layouts/product`, `shared/_auth_heading` | 6b | no |
| 403, 404 | `admin/errors` | 6b | no |
| Empty, loading and busy states, toasts, dialogs, menus, tooltips | `ui/empty_state`, `ui/toast*`, `ui/dialog`, `ui/menu`, `ui/tooltip`, `admin--ui--busy` | 1 | partly |
| Mails | `layouts/mailer.*`, `app/views/mails/_button`, the four mailers' views | 6b, reduced form | no |

### The rule for a screen the artifact does not draw

A builder decides an undrawn screen's look from E4's principles, without asking:

1. **Roles have their own look.** What a person edits or reads is content (white, elevation 1); what configures it is settings (grey fields; in a rail where it stands beside content); a group of things is structure (a frame or a tinted head, never a box of the same weight as its contents); creating is violet.
2. **One primary button per area** (a header, a panel, a dialog, a save bar). Everything else is secondary or tertiary.
3. **Depth comes from elevation**, never a new border: canvas, card, rail or panel, popover. A table is one card with grouping lines inside it.
4. **Colour carries meaning, always paired with words**: status in its status colour with its word, a type in its chip beside its name, a panel's head tinted by its kind (action, shortcuts, information).
5. **The right rail is used where a screen has settings beside content**, from the same threshold as the editor; below it the rail folds back into the page.
6. List and system screens (Trash, Audit log, Users, Groups, Tokens, System status) get no rail: a page heading, a filter bar, one card holding the table.

Where applying it is a real design choice, it is under "Open for the owner".

## Stages

Each stage is one PR that ships working on its own, keeps the full suite green, and names its guide pages under "Documentation" (the guide is `contentspiel-docs`; screenshots are retaken there before release).

### Stage 1: foundations

**What changes.** E4's values under today's token names; the new tokens (field fill, elevations 2 and 3, shadows 1 to 4, radii, structure, live, scheduled, panel heads, type chip, the twelve icon tokens); B's fields (fill plus bottom edge, accent outline on focus) in `.admin-column`/`.admin-field`, `.cs-select` and the rich-text box (`admin-rich-text.css`); every shared component in `app/components/admin/ui/` restyled once: `ButtonComponent` gains the E4 primary, tinted secondary and text tertiary (`ghost` becomes tertiary or is mapped onto it, builder's call), `StatusChipComponent` the solid Live and outlined Draft, `DialogComponent`, `MenuComponent`, `ToastComponent`, `TooltipComponent` the elevations, `BadgeComponent`, `CheckboxComponent`, `ChipInputComponent`, `FileDropComponent`, `SaveBarComponent`, `EmptyStateComponent`, `PaginationComponent`, `TabLinksComponent`, `LanguageTabsComponent` the radii and grounds. A new `Admin::Ui::IconChipComponent` draws an icon on its family's chip; `EditorScreen::BlockIconComponent` draws through it, and the sidebar's entries use it (Pages and the tree neutral, Posts lists, Media media, Forms form, the rest neutral; current module on the accent tint). A block type declares its family.

**What a person sees.** Every screen at once: a cooler, slightly tinted canvas, white cards that float, violet links and buttons, coloured icons in the sidebar and editor, fields as grey wells, and fewer lines.

**Tests and guards.** `admin_contrast_test` (every pair re-measured; "a line that only groups is stronger than it was" is rewritten, since E4's lines are deliberately fainter and elevation now separates; new pairs: each icon on its chip and on surface at 3:1, panel-head and structure words at 4.5:1, Live and scheduled words, the dark elevation steps), `admin_design_rules_test` (the field-line rule reworded, the new guard below), `design_tokens_test` (product tokens in both themes, none in the theme build), the components' tests and Lookbook previews (`test/components/admin/`, `test/components/previews/admin/`), `admin_i18n_test` (the new shared component listed). Browser tests likely to move: `filter_bar_test` (38px heights, the segment frame), `field_error_border_test`, `form_width_test`, `dialogs_hang_test`, `publish_dialog_steady_test`, any test that finds a button by a class.

**Size.** 5 to 7 days.

**Guide.** Every page with a CS Studio screenshot; the getting-started tour first.

### Stage 2: the editor

**What changes.** The four roles in the page and post editor: block cards lose border and head rule, at elevation 1, 22px apart, with the type chip in the head; a section is a structure frame with a tinted head whose settings are words opened on demand (`SectionCardComponent`, `SectionSummaryComponent`, `SectionLayoutMenuComponent`, `SectionLanesComponent`); content tiles (`BlockTileComponent`) show the chip, a heading and two or three lines, with hover, focused and dragging drawn by elevation; one add action: `BlockPickerComponent` becomes "+ Add block" (primary) opening the existing menu at elevation 3, plus "+ Add" under each column; the tree's markers ("○N", "↻N") hidden at rest and shown on hover, focus, the selected row and coarse pointers (kept for screen readers as the child count is), and the selected row's 3px accent bar (`TreeNodeComponent`).

**The tile's preview.** `TileSummaryComponent` today reads one line. A block type answers a short preview (a heading and plain text, from what it already stores; rich text through its Markdown form, `docs/reference/rich-text.md`); a type that answers none, a gem's included, keeps today's summary line. The preview is escaped text: the Code block's source still reaches a page only as escaped text. This is a declaration on the block type definition, so `docs/reference/content-blocks-and-types.md`, "Adding a block type", gains a step, and the shared samples (`test/support/block_samples.rb`) the guard that a preview is a sample's value. Whether tiles show text at all is the owner's (below); if not, they show the heading only.

**Live editing.** The hold strip, the holder's avatar on a tile, the notes marker (`editor.block.markers` slot), the "Updated" mark and `fieldset.admin-held` keep their places and ids; the tile's face, which a save does not re-render, takes its preview from the same stream that already replaces its icon (`Admin::ContentBlocksController#block_icon_streams`), or the preview goes stale until a reload (builder's call which, but not silently).

**Tests.** `admin_design_rules_test`; component tests of the editor's cards and tiles; `contract_ledger` if a declaration is added. Browser: `blocks_test`, `sections_test`, `code_block_test`, `table_block_test`, `note_block_test`, `card_block_test`, `rich_text_test`, `editor_fields_test`, `unsaved_order_test`, `editing_held_test`, `editing_live_test`, `editing_merge_test`, `notes_markers_test`, `tree_test`.

**Size.** 5 to 7 days.

**Guide.** Editing a page, blocks, sections and columns, the page tree.

### Stage 3: the right rail

**What changes.** When the editor area is at least 1200px wide, page settings (`PageSettingsFormComponent`) and the language tabs move into a 360px rail at elevation 2 on the right, and the blocks column grows from 760 to 900px; the rail's tabs are Page and Section. Choosing a section outlines it in accent and shows its settings in the Section tab (the one behaviour this stage adds). Below the threshold the rail folds back into the page, as in stage 2. The threshold is a container query on the editor area, never a window media query. While the notes drawer is open it takes the rail's place; a translation tab (`--cs-form-max-pair`, 1144px) folds the rail.

**The threshold.** With the 240px sidebar, the rail needs a window of about 1710px with the default 272px tree, about 1870px with a 430px one; "below about 1400px" cannot hold while sidebar and tree are columns. Whether the tree becomes a drawer at the threshold so that the rail appears in narrower windows is the owner's.

**The left alignment rule, changed.** Today every form starts at the content area's left edge, the editor column is `--cs-form-max` (760px), and `admin_design_rules_test` refuses `mx-auto` in the shell and holds the widths to tokens written once. After stage 3: **the blocks column and the rail are one left-aligned group** (the blocks column at the content's left edge, the rail right beside it, 28px apart); neither is centred, and the empty space, if any, falls right of the rail. `mx-auto` stays refused (the 403 and 404 alone). Two new widths, the 900px blocks column and the 360px rail, become tokens beside `--cs-form-max`, each written once in `content-spiel.css`, and the test "the form column's width is a token" holds all four. `.admin-form-column` stays a class on elements that exist, never a new wrapper around an editor's unit.

**One form, never two.** The rail holds the page's settings form and the chosen section's form themselves, moved, not copied: one element per record with the same ids, `data-editing-*` marks, live region and save-bar wiring, so a save's answer, a live refresh (`editing/merge.js`) and a hold reach it where it is. The publish, discard and cancel dialogs stay outside the part a save's answer replaces. Every write still goes through the queue.

**Tab order.** Page settings come first in the document but stand on the right. Keep the document order (settings, then blocks) and accept that at wide widths the focus goes right before left, or put the blocks first and the rail after them at every width: the owner's (below).

**Tests.** `admin_design_rules_test` (the widths); browser: `tree_column_test`, `form_width_test`, `translation_layout_test`, `notes_drawer_test`, `notes_column_test`, `editor_header_test`, `sections_test`, `editing_claims_test`, `editing_holds_test`, `autosave_test`, `autosave_unload_test` (the leave guard), at a wide and a narrow window each.

**Size.** 1 to 1.5 weeks.

**Guide.** Editing a page (the rail), page settings, sections, languages.

### Stage 4: the dashboard

**What changes.** Each panel headed by its job, with one line under it, and its head tinted by kind: action ("Waiting for you", "Notes for you"), shortcuts ("Pick up where you left off": your drafts as tiles), information ("Publishing on its own", "Languages behind English", "What changed recently"). Action rows end in a verb (Reply, Review and publish…). What needs you and your drafts fill the main column; information stands in the rail at the threshold, without a card. "New post…" is the screen's one primary; "New page…" secondary, beside the heading, replacing the quick-create row's form (`QuickCreateComponent`). Scheduled dates are amber blocks; status in its colour and word.

**The merge (the owner's to confirm).** "Open threads" (not personal, asks for no action, listed on the Notes screen) merges into "Waiting for you" as a filter, or is dropped; "Unpublished changes" merges into "Waiting for you" with "Review and publish…". Until confirmed, the stage keeps both as panels in the new look.

**Files.** `app/views/admin/dashboard/show.html.erb`, `Admin::DashboardScreen::*`, `app/views/admin/note_inbox/_card` and `_open_threads`, `app/queries/dashboard/` only if the merge is confirmed. The rule "the dashboard's grid is one, two or three columns by its container" is rewritten for the main column and rail.

**Tests.** `admin_design_rules_test` (the grid rule), dashboard component tests, `admin_i18n_test`; browser: `dashboard_test`, `note_inbox_test`, `unpublished_changes_test`, `drafts_test`, `presence_lists_test`.

**Size.** 2 to 3 days; 1 to 2 more with the merge.

**Guide.** The dashboard.

### Stage 5: the screens drawn later

The mind graph, the post editor and posts list, tags, Settings and the setup wizard, in the look of `StudioCalmE4More` once it is published; until then this stage waits. What is known: the post editor takes stage 2's and 3's parts (its tags, related posts and excerpt are settings, in the rail); Settings is a configuration screen that saves explicitly through `SaveBarComponent`, its cards on elevation 1 with the nav beside them; the wizard is a whole-screen, centred form and keeps that. The mind graph's colours are read by `app/javascript/mind_graph/theme.js` from tokens, and a post's dot and a tag's square outside the canvas are CSS spans that draw the same marks as `mind_graph/marks.js`: both change together (no guard holds them). The status key's five names stay the chip's words.

**Tests.** `admin_contrast_test` (graph tokens), `mind_graph_guards_test`; browser: `mind_graph_test`, `mind_graph_modules_test`, `posts_list_test`, `tags_test`, `settings_test`, `settings_mail_test`, `settings_images_test`, `ai_settings_test`, `languages_test`, `tokens_related_posts_and_starter_pages_test`, the setup tests.

**Size.** 4 to 6 days, once the page exists.

**Guide.** Posts, tags, the mind graph, Settings, first-time setup.

### Stage 6: every remaining screen

By the rule above; two PRs.

- **6a, content-side:** Media library and picker (the panel, which is the selected image's form, becomes a rail at elevation 2; the grid's tiles at elevation 1), Trash, Translations (matrix in one card; states in their words, never red), notes, inbox and drawer, forms (list, builder, submissions, deliveries), the audit log. Browser: `media_library_test`, `media_picker_test`, `trash_test`, `translations_test`, `translation_status_test`, the `notes_*` and `note_*` tests, `form_builder_test`, `audit_log_test`. 4 to 6 days.
- **6b, people and system:** users and invites, groups (the permission matrix), API tokens, your account, system status, sign-in, password reset, invitation, the 403 and 404, and the mails in their reduced form. Browser: `users_test`, `groups_test`, `groups_editor_test`, `groups_members_test`, `invites_test`, `password_reset_test`, `account_password_answer_test`, `system_status_and_preview_test`, `view_only_test`. 3 to 5 days.

**Mails.** Mail clients read no stylesheet, drop custom properties, and many ignore shadows, radii and dark-mode rules. A reduced E4: the white card on a light ground as today, ink text, the site's name as text, one solid violet button (`mails/_button`) with white words and an 8px radius, no shadow, no chips, no dark scheme. Today the mailer layout names colours instead of hex because `admin_design_rules_test` refuses literals under `app/views/layouts`; the violet needs either an exception for the mail views or a named colour near it. The owner's (below).

**Guide.** Media, trash, translations, notes, forms, the audit log, users and groups, tokens, your account, signing in.

**Total.** About 5 to 7 weeks in six stages (seven PRs).

## The guard after E4

`test/lib/admin_design_rules_test.rb` checks today: no hex, `rgb()` or `hsl()` in CS Studio's sources; no `dark:` variant but `dark:scheme-dark`; no danger in translation chips, tabs, tree markers, the matrix and the dashboard's cards; the replaced components gone; no `mx-auto` but the 403 and 404; a pressable element outlined in `border-field-line`, never `border-line-strong` (with an allow-list); no text under 11px, a mono label `text-label`; the disclosure's triangle; the form column's widths and the filter bar's height as tokens written once; the dashboard's grid.

After E4 it also holds, each with a test that proves its pattern can fail:

- **No Tailwind palette colour** in CS Studio's sources (`bg-violet-600`, `text-gray-500`, `border-amber-400`, any `-{50…950}` step of a named palette, and `white`/`black` utilities): a colour is a token.
- **A shadow is an elevation token** (no `shadow-sm`, `shadow-lg`, arbitrary `shadow-[…]`), and **a radius is a radius token** (no `rounded-md`, `rounded-[…]`, beyond the pill).
- **Buttons only through `Admin::Ui::ButtonComponent`**: no element outside it, the checkbox, the count pill and the unread dot carries an accent fill (`bg-accent`) or the tint-and-accent pair of a secondary, with a named allow-list like `STRONG_LINE_ALLOWED`. "One primary per area" cannot be read statically; review holds it, and a component test of each screen's header may count primaries where it is cheap.
- **Icons only through the chip**: the `--cs-ic-*` tokens and their utilities appear only in `IconChipComponent` and the stylesheet, and a block type's icon is drawn only through `BlockIconComponent` (no `shared/_icon` call with a block type's icon name elsewhere).
- **Status colours only in the status components**: the live, scheduled, ok, warn and danger fills appear only in the status, translation, unpublished and channel chips, the scheduled date and the alerts, each of whose tests asserts its word.
- **The new widths written once** (the 900px column and the 360px rail), and the reworded field rule: identified by a `cs-field-line` edge (a text field's bottom edge, a full outline on a checkbox, toggle or segmented control) or by a fill of its own.

`admin_contrast_test` measures the new pairs (above). `docs/reference/design-system.md` is rewritten with each stage, its "Rules a change can break silently" included.

## Constraints

From `CLAUDE.md` and the reference files; each binds this work.

- **Components go in their folders.** A component used by more than one screen (the icon chip, the rail if the editor and the dashboard share it) is in `app/components/admin/ui/`; a screen's own stays in the screen's folder; nothing loose in `app/components/admin/` (`source_layout_test`). Never define `Admin::<Domain>`.
- **Admin strings are keys**, in `config/locales/admin/<folder>.en.yml`; a script's words from `data-messages`; new components join `admin_i18n_test`'s lists.
- **Stimulus conventions.** A rail or section-choosing controller is `admin--editor--…` in `controllers/admin/editor/`, its identifier following its path; a rename is searched for in the tests by hand. No inline handlers (`inline_handlers_test`).
- **No Turbo morphing**, no `turbo_refreshes_with`, no `broadcast_refresh` (`notes_guards_test`); the rail is redrawn part by part like everything else.
- **The write queue, the save rule, live editing and the leave guard** as in the anti-goals; content screens autosave, configuration screens save explicitly.
- **Design questions are the owner's.** A look this spec does not settle goes to the Design System artifact, not to the builder alone.
- **WCAG AA in both modes**, measured, not judged.
- **The silent rules of the shell, tree, editor and mind graph:** `--admin-tree-width` and `data-tree-fits` are written by the layout's head script and `admin--shell--tree-width` alone (the rail's threshold reads the container, it writes neither); the mind graph's `reset()` takes back whatever its script writes into the page; `PostGraph.node_id`, `mind_graph/ids.js` and the `"tag-"` prefix stay in step; the graph's CSS marks and `marks.js` change together, as do the status key's words and the chip's; whatever can be pressed on the canvas has a row in the list beside it; the publish, discard and cancel dialogs stay outside the part a save's answer replaces; every block move goes through `admin--editor--blocks#move` in the queue; code asks `capability?(:container)`, never `block_type == "section"`; a test that asserts a controller's absence by a fragment of its name checks nothing after a rename.

## Left to the builder

Token names for the new values; whether `ghost` is renamed tertiary; the tile preview's length and how a type declares it; how the rail moves its forms without copying them; the rail's tabs' markup; whether the dashboard's rail and the editor's are one component; the container query's exact form; how `ok`, `warn` and `danger` are retuned if a pair fails; which allow-list entries the new guard needs. Each is written into the plan, and any that changes what a person sees goes to the owner first.

## Open for the owner

1. **The dashboard merge**: Open threads into "Waiting for you" as a filter, or dropped; Unpublished changes into "Waiting for you" with "Review and publish…"?
2. **The rail's threshold**: the rail needs a ~1710px window with the default tree. Does the tree become a drawer at the threshold, so the rail appears in narrower windows?
3. **Tiles that preview their text**: a heading and two or three lines, or the heading only?
4. **Tab order with the rail**: settings first in the document (the focus goes right before left at wide widths) or blocks first at every width (settings below the blocks under the threshold)?
5. **Mails**: the reduced form above, with the violet as an exception to the no-literal rule in the mail views, or a named colour near it?
6. **Visitor-facing CMS pages**: the form-send fallback pages share the product stylesheet and will turn violet with stage 1; the preview bar (`th-preview-*`) does not. Keep both as they fall, or hold the form-send pages to a neutral look?
7. **Where the rule is a real choice**: the form builder (fields as content and the form's settings and destinations in a rail, or its tabs kept as they are), and the media library (its panel as a rail at elevation 2, which makes the image grid narrower at mid widths).
