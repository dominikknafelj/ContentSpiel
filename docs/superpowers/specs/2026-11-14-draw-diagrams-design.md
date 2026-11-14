# Draw diagrams: a CS Studio task that draws every undrawn Diagram block

Status: approved direction (owner, 2026-11-14: "i follow your rec"). The
screen's look and place are the design agent's (§6); everything else here is
decided.

## 1. Why

A Diagram block's drawing is made only in a browser: CS Studio's card draws
the source in the sandboxed renderer frame and saves `{ svg, from }` beside
it (Diagram block spec, `docs/reference/content-blocks-and-types.md`). A
diagram written any other way has a source and no drawing of it: the guide's
`bin/load`, a script through the save services, an MCP client, a translation
filled in elsewhere. Today each such diagram is drawn by a person opening its
card and changing its source once (a space typed and taken out), then
publishing the page. For a site loaded from files that is one manual step per
diagram, repeated whenever a source changes.

The fix keeps the one rule that holds the feature together, that a drawing is
made by the vendored Mermaid in the frame in a person's browser, and takes
away the manual part: one CS Studio task draws every diagram that needs it,
in the admin's browser, one after another, and saves each drawing the way the
card does.

## 2. Goals, non-goals, anti-goals

Goals
- A list of every Diagram block, per language, whose stored drawing is not of
  its current source: "Not drawn yet" (no drawing) or "Last drawing kept"
  (a drawing of an earlier source). Grouped by page.
- "Draw all": the browser draws each listed diagram in turn and saves it.
  A source that does not draw is reported with the frame's sentence and
  skipped; the run goes on.
- After a run, the live pages it changed are listed, each with "Publish
  changes", which opens the editor's existing Publish changes dialog
  (`?review=publish`). Nothing goes live unasked.
- The count of diagrams to draw is on System status, linking to the list.

Non-goals
- Drawing on the server. No Chrome, no Node, no Mermaid in Ruby.
- Drawing at publish time, or automatically at load.
- Changing the card's own drawing, its states, or the frame's protocol.

Anti-goals (a failure even if it works)
- A second way to publish: the task never writes a published copy.
- A save that bypasses the write queue, the block's base, an edit hold or
  the permissions a card's save meets.
- Opening a card's worth of UI per diagram, or a frame per row.

## 3. What is listed

`Diagrams::ToDraw` (`app/queries/diagrams/to_draw.rb`), a query answering
rows `{ block, page, locale, state, source }`, `state` being `:not_drawn` or
`:kept`:

- Diagram blocks (`block_type` of `BlockTypes::Diagram`) on pages that are
  not in the Trash (trashed pages and their branches hidden, as every list
  does; the query joins `test/integration/trash_visibility_test.rb`).
- Through `AccessControl.scope(:pages, actor)`: a page outside the viewer's
  scope is not listed.
- Per switched-on language, a language counting only when it has a source of
  its OWN (a non-blank stored `source` for that locale). A translation that
  falls back to another language's source is not listed: it has nothing to
  draw until a person makes it its own.
- A row when the language's stored drawing is not `Diagrams::Drawing#current?`
  for that source: `:not_drawn` with no drawing (or an unusable one, as
  `Shown` reads it), `:kept` with a drawing of another source.
- Whether a row can be saved by the viewer is the save's own check
  (`ContentBlocks::OwnerPermissions`: `pages.edit`, and `pages.publish` on a
  published page). The list shows only rows the viewer may save; the count
  on System status is the same query for the same viewer.

Order: the page tree's order (`TreeOrder`), then the block's position, then
the language order of Settings.

## 4. Saving one drawing

`PATCH <admin>/diagram-drawings/:block_id` (`Admin::DiagramDrawingsController#update`),
sent through `app/javascript/saving/queue.js` as every write is, with
`locale`, `svg`, `from` and the block's base (`base_updated_at`).

The action, in order:
1. Finds the block through the scope (404 outside it, as everywhere).
2. Refuses a stale base with the usual 409 (`Admin::StaleForm`): the block
   changed since the list was drawn; the row says so and is skipped.
3. Refuses when someone else holds the block (`Admin::EditingClaims`): the
   row says "Being edited by ‹name›" and is skipped. The task takes no claim
   that outlives its own request: it claims for the save and gives the claim
   back in the same request, so a person opening the card a second later is
   not held off.
4. Refuses when `from` is not the digest of the language's stored source
   (`Diagrams::Drawing.digest`): the source changed in between.
5. Saves through `ContentBlocks::Save` with the language's translations
   `{ settings: { drawing: { svg:, from: } } }`, so the drawing is cleaned by
   `Diagrams::Drawing.clean`, size-checked, permission-checked and audited
   exactly as a card's save is.

It answers JSON (`{ ok: true }` or `{ ok: false, reason: <key> }`), not a
Turbo Stream: the list page draws its own row states. The reasons are keys
the script reads its sentence for from `data-messages`.

## 5. Drawing in the browser

One Stimulus controller, `admin--diagram--draw-all`
(`app/javascript/controllers/admin/diagram/draw_all_controller.js`), on the
list. It opens ONE renderer frame (`diagram/frame`'s `openFrame`), hidden
from view and from the accessibility tree, with the colours CS Studio's probe
gives (the same `--th-diagram-*` read as the card's), and for each row in
order:
- `draw(source, colours)`; waits for the answer.
- An `error` answer: the row shows the frame's sentence, as the card's error
  does, and the run moves on.
- An `svg` answer: `digest(source)` (`diagram/digest`), then the save (§4)
  through the queue; the row shows Drawn, or the refusal's sentence.
- Rows are done one at a time: the next draw is posted after the previous
  save has answered.

"Stop" ends the run after the row in hand. Leaving the page stops it; what
is saved stays saved. `disconnect` and `turbo:before-cache` take back the
frame and every row state the script wrote. The run needs a secure context
(`crypto.subtle`), as the card does: over plain HTTP to another host the
button says it cannot draw here, and nothing is sent.

When the run ends, the live pages that got a drawing are listed with
"Publish changes" (the editor at `?review=publish`), and the rows that were
skipped stay, with their reason, for a person to open (each row links to its
page's editor, at the block).

## 6. For the design agent

The list's place (its own screen under System status, a panel of the
Dashboard's "Waiting for you", or both), its rows, the run's progress, the
states of a row (to draw, drawing, drawn, refused with a reason, skipped),
the end-of-run list of live pages, and System status's row. The rule of one
primary button per area holds: "Draw all" is the primary.

## 7. Permissions, audit, live editing

- Seeing the list: any person with `pages.edit` (the rows narrowed as §3
  says). No new permission.
- Each saved drawing is one `ContentBlocks::Save`, audited as a card's save
  is, by the person who ran the task.
- A drawing saved on a live page is an unpublished change of that page, as
  any save is.
- Presence and live refresh: a person with the page open sees the block
  updated by the live merge, as after any colleague's save.

## 8. The guide

`bin/load`'s closing report ("diagrams to draw in CS Studio") names the new
task instead of telling a person to open each card, and the README's
paragraph on drawing says the same. The editors' Diagram page and the
administrators' System status page gain the task. The guide then gets its
first diagrams (a page's publishing states, the page tree and its
addresses), drawn by this task after the load. That is a docs PR after this
one is released.

## 9. Release

`CHANGELOG.md`, "Added": the task and System status's row. No migration, no
new top-level name (`Diagrams` exists), no removal.
