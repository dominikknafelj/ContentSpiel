# The Diagram block: design

Status: draft for the owner's approval, 2026-11-11.
Base: `main` at 9213771f (release 0.3.0). No issue yet.
Amended 2026-11-11 with the spike's findings (`2026-11-11-diagram-block-spike.md`, items 1–12 of its "Changes the spec needs") and two owner decisions (the drawing limit, non-Latin scripts). Each change is marked "(spike, 2026-11-11)" or "(owner, 2026-11-11)".
**Design System for the build: v213 (index 1794424314-9bbe)**, with the cards `EditorDiagramBlock`, `EditorDiagramError` and `PublicDiagramBlock`. They already show the owner's later decisions: 60%-then-scroll (call 13), the tile preview (call 14) and the import ("Decided by the owner").

## Why

Editors of documentation-like sites (the guide first) want diagrams: a flow, a sequence of requests, a state machine, a data model. Today the only way is to draw elsewhere and upload a picture. That picture can't be edited in place, isn't translated, doesn't follow the theme's colours or dark mode, and has no text a screen reader can use beyond its alt.

Mermaid is the common text form for such diagrams. Editors already know it from GitHub, GitLab and mermaid.live. A block whose source is Mermaid text gives them an editable, translatable diagram in the theme's own look.

## Goals

1. **An editor types Mermaid and sees it drawn while typing,** beside the field, as on mermaid.live and like the Code block's plain field.
2. **A visitor's page carries no script for it.** The drawing is made in CS Studio, stored with the block and served as static markup. The public cache and ETag work as for any block.
3. **The site's colours, in both schemes and on every band.** A diagram is drawn from the theme's tokens, never from Mermaid's palette or an editor's colours.
4. **Nothing an editor types reaches a visitor except as a cleaned drawing.** The server never trusts the SVG the browser sends.
5. **Every diagram has words for people who can't see it.** Those words are translated like an image's alt.
6. **A diagram can be translated.** Its labels are words, so a language may have its own source and its own drawing.

## Non-goals

- **A drag-and-drop composer.** None fits today: Visimer is React and npm, and maxGraph/draw.io would be a separate "Drawing" block, later, if non-technical editors ask.
- **Diagrams in rich text, or in the guide only.** It is a block like the Code block.
- **Editors' own colours** (`classDef`, `style`, `linkStyle`, `:::`). The theme decides the colours.
- **Links and callbacks in a diagram** (`click`, `link`, `links`, `href`).
- **Drawing on the server.** No headless browser and no Node in the image.
- **AI translation of the source.** See "My calls".
- **Re-drawing every stored diagram after a Mermaid upgrade.** It needs a browser. A diagram is drawn again when it is next edited.

## Anti-goals (a failure even if it technically works)

- Mermaid, or anything from its output, running with CS Studio's origin: its cookies, its CSRF token or its DOM.
- Any script, external load or event handler reaching a public page through a drawing. That includes a drawing posted by hand around the editor, and a row written around the services.
- A public page that shows a broken diagram, Mermaid's error text or an empty box.
- Mermaid modulepreloaded on CS Studio screens that have no Diagram block, or on any public page.
- A block that breaks the existing rules. Those rules include: nothing is required of an empty block; a save is not a publication; a refused save writes and audits nothing; and every write goes through `ContentBlocks::Save` and the write queue.

## Decided by the owner

These are the owner's decisions, in his words and mine:

- **What it is:** a Diagram block in the CMS, not rich text and not the guide only. Editors type Mermaid text in a monospace field and see it drawn live beside it, like mermaid.live and like the Code block's field. There is no composer now.
- **Where it is drawn:** in CS Studio. The drawing is stored and served static. Mermaid loads only in CS Studio, never on public pages. On save, the drawn SVG is stored with the block. The public page serves that SVG with no script, and the public cache and ETag work as for any block.
- **Security:**
  - The CS Studio preview renders with a pinned, patched Mermaid version, in the renderer frame with `securityLevel: "strict"` (spike, 2026-11-11: Mermaid's `"sandbox"` mode throws inside an opaque-origin frame and isolates nothing the frame doesn't; see "My calls" 2). This answers CVE-2026-41149, DOM injection through `classDef` in state diagrams even under `strict`, and GitLab #332528, where sanitizing depended on `htmlLabels`.
  - The server sanitizes the SVG against a strict allowlist before storing it, and refuses what it can't sanitize. The allowlist means: no script, no `foreignObject` or HTML labels, no event handlers, no external references and no `style` that can load anything.
- **Theme colours:** a block type promises the theme's colours, never Tailwind's palette. Mermaid's output reads the theme's colour tokens, in light and in dark.
- **Accessibility:** a required text description is a field of the block, like an image's alt. The public markup is `role="img"` with an accessible name and the description.
- **Import (owner, 2026-11-11):** a diagram can be brought in two ways, beside typing it:
  - **Upload a file into the block:** an "Import file…" control on the Diagram block's card reads a `.mmd` file, or a `.md` file's first ```mermaid fence, into the source field of the language being edited (replacing what is there, after a confirm when the field isn't empty); it is then drawn and saved as if typed. The file is read in the browser and never stored; its size is held to the source limit; a file with no Mermaid in it says so.
  - **From Markdown content:** wherever CS Studio turns Markdown into blocks (the rich-text Markdown form and its import paths, the MCP tools that write content), a ```mermaid fence becomes a Diagram block (source filled, drawing made at the editor's next open, description empty, so the site shows it only once a description is added) instead of a Code block. The plan names each such path from `docs/reference/rich-text.md` and `app/mcp/`.
  - Not in scope: mermaid.live links and ready-made SVG uploads.
- **After the cards (v211), 2026-11-11:** a large diagram scales down to about 60%, then scrolls sideways in its own figure box (call 13); the tile shows a small preview of the stored drawing (call 14).
- **Drawing limit (owner, 2026-11-11):** a drawing may hold about 1 MB after cleaning (`Drawing::MAX_BYTES` = 1_048_576), because a full 10,000-character source can draw 770 KB. The source stays at 10,000 characters and the drawing at 5,000 elements. The frame checks the cleaned size and shows a "too large" state before a save would be refused.
- **Non-Latin scripts (owner, 2026-11-11):** Cyrillic, Greek, Vietnamese, CJK and right-to-left text are a general roadmap item for the whole CMS, issue #246 (https://github.com/dominikknafelj/ContentSpiel/issues/246). In this block they are a named limit (§4): the drawing is measured and painted in fallback fonts and its boxes may fit less snugly. The block ships no other font subsets.
- **Questions left to this spec:**
  - inline SVG or `<img>`;
  - how the theme's colours reach the drawing;
  - translation and AI;
  - what happens on a failure;
  - the limits and the allowed diagram types.

  Each is answered below and marked under "My calls".

## The design

### 1. The block and where its values are stored

`BlockTypes::Diagram` (`app/models/block_types/diagram.rb`) is registered after `Code`, with the icon `diagram` (a new entry of `BlockTypeDefinition::ICONS`) in the `:code` family. It has four values:

| Value | Where | Translated | Type |
|---|---|---|---|
| `source`, the Mermaid text | `translated_settings` | yes, optional per language | a new field type, `:mermaid` |
| `drawing`, the cleaned SVG and the digest of the source it was drawn from | `translated_settings` | yes, follows `source` | a new field type, `:diagram_drawing` |
| `description`, the words for people who can't see it | `translated_settings` | yes | `:text`, `label: "Description"` |
| caption | the existing `caption` column | yes | — |

**No migration, no column and no service.** The published copy already holds `settings`, `translated_settings` and `caption`, and writes go through `ContentBlocks::Save`, `Duplicate`, `Destroy` and `Reorder`, as for the Code block ("Adding a block type", step 0).

**Nothing is required in the schema.** The picker makes an empty block first. The description is required for the diagram to *show* (§6), not for a save.

**The two new field types** ("A new field type": an entry of `ContentModel::FieldTypes` plus an input under `Admin::Fields`):

- **`:mermaid`**
  - It casts like `:code`: kept as typed, with line endings as `\n` and outer blank lines dropped.
  - Unlike `:code`, it may be `translated: true`.
  - It is not `translatable`, so it is never offered to the AI.
  - It is audited as `:digest`.
  - Its `validate` refuses only more than `max:` characters (counted in code points), in every language the object holds. The line rules of §5 are the editor's and the frame's: a source that breaks one is stored as typed, and its drawing stays the last that worked.
  - Its input, `Admin::Fields::MermaidField`, is the Code field's textarea (the same attributes, the same CSS-only height, and Tab leaves it). Beside it, it holds the preview frame, the error line and the counter.
- **`:diagram_drawing`**
  - Its cast runs the sanitizer (§3). A value that does not pass is an error, `:invalid_drawing`, never a quiet nil.
  - It refuses more than `Diagrams::Drawing::MAX_BYTES`.
  - It is not `translatable` and is audited as `:digest`.
  - Its input is hidden, written by the preview script only. `own_label?` is true and it draws no label.
  - Its `display` on a translation tab is nothing, because the source's field shows the drawing.

### 2. Drawing in CS Studio: the renderer frame

**Mermaid runs in a frame of its own with an opaque origin, not in CS Studio's page.**
- The block card's script, `admin--diagram--preview` (the topic `diagram`: its controllers go in `app/javascript/controllers/admin/diagram/`, its plain modules in `app/javascript/diagram/`), creates the frame when the card connects. A screen with no Diagram block never fetches Mermaid.
- The frame is a CS Studio route, `GET <admin>/diagram-renderer`. It holds no data and is the same document for everyone. It is served with:
  - its own `Content-Security-Policy`: `sandbox allow-scripts`, `default-src 'none'`, `script-src 'self'`, `style-src 'self' 'unsafe-inline'` (Mermaid writes a `<style>`), `font-src 'self'`, `connect-src 'none'`, `form-action 'none'` (spike, 2026-11-11: works as written);
  - the element's own `sandbox="allow-scripts"`.
- **The frame's origin is `"null"`** (spike, 2026-11-11). `'self'` in its CSP still matches the server's origin, so its two scripts load. The card posts to the frame with target origin `'*'` (an opaque origin can't be named), accepts a message only when `event.source` is its own frame **and** `event.origin === "null"`, and the frame posts back with `'*'`.
- **The frame's font files are served with `Access-Control-Allow-Origin: *`** (spike, 2026-11-11). A font fetched by an opaque-origin document is a CORS request with `Origin: null`, so `font-src 'self'` alone is not enough: without the header `FontFace.load()` fails. The Archivo `.woff2` files are public. The frame loads them with `FontFace` and `document.fonts.add` and awaits them before `initialize` and the first render.

  It has no `allow-same-origin`, so the frame cannot read CS Studio's cookies, storage or DOM. It can send no request and navigate nothing.
- **The protocol:**
  - The card posts `{ id, source }` to the frame.
  - The frame draws and posts back either `{ id, svg }` or `{ id, error }`.
  - The card accepts only messages whose `event.source` is its own frame, and only the latest `id`.
- **The card never puts the frame's SVG into CS Studio's DOM.** It writes the string into the hidden `drawing` field, as text, and the frame displays the drawing itself. What a viewer sees in CS Studio is therefore inside the sandbox.
- **What the frame draws with:**
  - Mermaid at an exact patched version, at least 11.15.0, the release that fixes CVE-2026-41149 (GHSA-ghcm-xqfw-q4vr). It is vendored like d3-force: the file is in `vendor/javascript`, loaded by its asset URL, with a `pin "mermaid", preload: false` line kept only so that `bin/importmap audit` and `outdated` see the package.
  - `startOnLoad: false`, `htmlLabels: false` (and the flowchart's own), `maxTextSize` at twice the block's limit (20,000: Mermaid counts UTF-16 units, the block code points, so Mermaid's never trips first), and `maxEdges` at Mermaid's default.
  - `theme: "base"`, and `fontFamily` and `themeVariables.fontFamily` set to Archivo (§4).
  - **`securityLevel: "strict"`** (spike, 2026-11-11). Sandbox mode lays out in a nested iframe whose `contentDocument` is null inside an opaque-origin frame, so every type fails there.
  - **`gantt.useWidth` at a fixed figure** near the content column's width (spike, 2026-11-11). Without it a gantt is laid out at the frame's width, so a stored gantt would depend on how wide the editor's frame happened to be.
- **Before Mermaid draws,** the frame makes three checks, in this order (spike, 2026-11-11):
  1. the text's length: over `Diagrams::Source::MAX_CHARACTERS` is refused by the frame itself, because Mermaid does not throw for an over-long text but draws a stand-in diagram ("Maximum text size in diagram exceeded");
  2. the line rules of §5, written once in Ruby and handed to it as data: the type list and the refused constructs, so a refused source never reaches the parser and the `classDef` path of the CVE never reaches Mermaid at all;
  3. `mermaid.parse(text)`, refusing when its `config` is non-empty (every directive and front matter shows there) or its `diagramType` is not on the list.
- **After Mermaid draws,** the frame cleans the SVG as the server will (§3), checks the **cleaned size** and element count against `MAX_BYTES` and `MAX_ELEMENTS`, and shows the "too large" state (§7) instead of handing the drawing back, so that a save is never left to be refused (owner, 2026-11-11). It paints with the same class rules on CS Studio's colours, which the card posts in with the source. Light and dark follow CS Studio's theme. In CS Studio the preview therefore follows the backend's look and has the site's shape (the owner's answer of 2026-10-13: "for the backend it follows the backend").

**Saving.**
- The script draws on `input`, with its own short debounce.
- When a draw succeeds, it writes the hidden `drawing` field: the SVG and the SHA-256 of the source it drew (`crypto.subtle`). It then lets the form's autosave send source and drawing together, through `app/javascript/saving/queue.js` like any field.
- When a draw fails, it leaves the hidden field as it was: the last drawing that worked.
- A save that the source's own keystroke sends first carries the old drawing. The next save carries the new one.
- On `connect` the script draws, but writes nothing. Opening a card never saves, which keeps live editing and the stale check as they are.

**The server checks the digest.** It stores `from` as sent when it is a SHA-256 in hex (anything else refuses the drawing), and `Diagrams::Drawing#current?(source)` compares it with the saved source's digest. A drawing whose `from` is not the source's digest is *the last drawing that worked*: the card and the tile say so (§7), and the public page still draws it (§6).

**What the frame and the card take back.**
- At `disconnect`, the card removes the frame and forgets its listener.
- At `turbo:before-cache`, the card removes the frame. A page shown from a copy builds it again at `connect`.
- A live refresh that replaces the card replaces the frame. A form with unsaved text is never replaced (`editing/merge.js`).

**A card held by someone else** draws at `connect` and writes nothing: its textarea is `readonly` (`HeldFields`), and no action of the script stays in a held form. So the type declares no `read_only_actions`.

### 3. The server's sanitizer: `Diagrams::Drawing`

`Diagrams::Drawing` (`app/values/diagrams/drawing.rb`) is **the one file that reads a drawing**. It answers data and markup that it builds itself.

- **How it parses:**
  - Nokogiri's strict XML parser, with `NONET`, no DTD loading and no entity expansion.
  - A document with a DOCTYPE, an entity, a processing instruction or more than one root is refused.
  - **The output is written from the parse tree by `Drawing`, never passed through from the input string.**
- **Allowed elements** (spike, 2026-11-11: what the seven types and a 60-node flowchart use after cleaning; `2026-11-11-diagram-block-spike.md`, §3):
  - `svg`, `g`, `defs`, `marker`;
  - `path`, `rect`, `circle`, `line`, `polygon`;
  - `text`, `tspan`, `desc` (Mermaid's `title`, its `accTitle`, is dropped: the component writes the one title, the description).

  `use`, `clipPath`, `ellipse` and `polyline` are never produced and are not on the list, and with `use` gone there is **no `href` rule**: every `href` is refused. A type that later needs one adds it with its fixture.
- **Allowed attributes:**
  - geometry: `x y x1 y1 x2 y2 cx cy r rx ry width height d points transform viewBox`, by name on any allowed element (`viewBox` is also written on `marker` and `path`);
  - text: `dy text-anchor dominant-baseline alignment-baseline font-size font-weight font-style` (`font-style` is new, spike, 2026-11-11: Mermaid writes `font-style="normal"` on every label `tspan`);
  - markers: `marker-start marker-end` (on `path` and `line`), only as `url(#<id in this drawing>)`; `markerWidth markerHeight markerUnits refX refY orient` (on `marker`);
  - `id`;
  - `class`, each token matching `/\A[A-Za-z][\w-]*\z/`;
  - `xmlns` on the root, and on the root `aria-roledescription`.

  Values seen, which are cheap to enforce as lists: `orient` `auto` / `auto-start-reverse`; `markerUnits` `userSpaceOnUse`; `text-anchor` `middle`; `dominant-baseline` and `alignment-baseline` `central` / `middle`; `font-size` `10` / `11`; `font-weight` empty or `normal`; `font-style` `normal`.
- **Dropped quietly,** because Mermaid always writes them and none of them can be harmless *and* themed (spike, 2026-11-11: the list is what Mermaid 11.17.2 writes in every drawing of the seven types; a refusal for any of them would refuse every flowchart, class, state, ER, sequence or gantt drawing):
  - elements: `style` (as the root's child only), `title`, `filter`, `feDropShadow`, `linearGradient`, `stop` and `symbol` (the last four are in `defs`, referenced only from the dropped styles, or unused: three actor icons of 13 KB in every sequence diagram), and the empty `g`;
  - every `style` attribute;
  - `fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `opacity`, `color` and `font-family`;
  - `name` (sequence lifelines), `fill-rule` and `clip-rule` (ER), `transform-origin` (gantt) and `data-*`;
  - on the root: `width`, `style`, `role` and `aria-*` (§6 writes them);
  - any single class *token* that fails the class pattern (gantt's `width-27.4375`, sequence's `200` on lifelines): the token goes, the element stays.
- **A refusal, which refuses the whole drawing:**
  - any element not on the list and not dropped quietly, by name: `script`, `foreignObject`, `a`, `image`, `iframe`, `animate`, `set`, `animateTransform` and `animateMotion` (SMIL can set an `href`), `style` inside `defs` included;
  - any attribute not on the list and not dropped quietly, by name: an `on*` handler, any `href` (`<a href>` from `click … href`, `link` and `links` is the seen case) and `xml:base`;
  - a `url(` other than `url(#id)`;
  - a value holding `javascript:`, `data:` or `//`;
  - more than `MAX_BYTES` after cleaning, or more than `MAX_ELEMENTS`.
- **Ids are made the block's own.**
  - On write, every `id` and every reference to one is renamed to a neutral `d-<n>`.
  - On read, the component prefixes them with the block and the language (`diagram-<block id>-<locale>-d-<n>`), so two diagrams on a page, or a duplicated block, never share a marker.
- **It runs on write and on read.**
  - On write, a refusal is a refused save (§7).
  - On read, a drawing that no longer passes (a row written around the services, or a sanitizer tightened since) draws nothing and is logged once per block and reason, never with the content.
  - The read is cached under `[ "diagram", sha256 of the stored drawing, block id, locale, Drawing::REVISION ]`. **Bump `REVISION` when the lists change**, or a cached drawing keeps the old rules: this is a rule in `CLAUDE.md`, with no guard, like `CodeHighlight::REVISION`.

**Why the server cannot check that the drawing matches the source:** it has no Mermaid. A person with the edit right who posts a hand-made drawing gets a cleaned picture of their own choosing, which is no more than an image upload already gives them. The sanitizer is what bounds it, and the tests feed it hand-made drawings, not only Mermaid's.

### 4. Colours, the font and the theme contract

**Mermaid's own styles never reach a page.** The sanitizer drops them (§3). The block's stylesheet, `app/assets/tailwind/themes/default/diagram.css` (declared with `t.stylesheet "diagram.css"`), paints the drawing by the class names Mermaid writes, scoped under `.content-block--diagram`. It writes plain rules, not utilities, since the classes come from data. It holds no colour of its own. The class names it must paint, per type, are in the spike's report, §3 ("Class names `diagram.css` must paint").

**It carries Mermaid's layout, not only colours** (spike, 2026-11-11). The dropped `<style>` held layout that the drawing needs, so `diagram.css` writes it again:
- `text-anchor: middle` for flowchart labels, **scoped to `svg.flowchart`** (class, state and ER labels are start-anchored and break if the rule is global);
- the font sizes by class: the root's 16 px, titles 18 px, pie labels and legend 17 px, pie title 25 px, ER edge labels 14 px, class terminals 11 px, gantt task text 11 px;
- the dash patterns: dotted and dashed edges, `messageLine1`, `loopLine`, `note-edge` and state dividers;
- a pie's slice colours from `.pieCircle:nth-of-type(6n+k)` and its legend from `.legend:nth-of-type(6n+k+1)`, and a gantt's task states from `done`, `active` and `crit` with the section suffix `0…3`.

The frame paints with the same rules. **A theme that replaces the stylesheet must keep these layout rules**, and the theming reference says so.

**Themed tokens** (`t.tokens themed:`), defined in `tokens.css` from the base tokens wherever one is right:

| Token | Paints | Default |
|---|---|---|
| `--th-diagram-ink` | every label | `var(--th-ink)` |
| `--th-diagram-fill` | a node, an entity, a participant, a state | `var(--th-surface)` |
| `--th-diagram-line` | a node's outline | `var(--th-dim)` (spike, 2026-11-11: `--th-line-strong` measures 1.54:1 in light and 1.67:1 in dark on the surface, under the 3:1 below; `--th-dim` measures 6.65:1 and 8.21:1) |
| `--th-diagram-edge` | an edge, an arrow, a lifeline, a marker | `var(--th-dim)` |
| `--th-diagram-group` | a subgraph, a composite state, a sequence box, a gantt section | `var(--th-sunken)` |
| `--th-diagram-note` | a note | `color-mix()` of `--th-accent-tint` and the surface |
| `--th-diagram-accent` | an activation, a gantt's critical task and its "today" line | `var(--th-accent)` |
| `--th-diagram-series-1` … `-6` | a pie's slices, a gantt's task states | literals, as the syntax colours are |

The strong band re-values them in `sections.css` as it does for the Code block. Contrast is computed in `test/integration/design_tokens_test.rb` for every pair, on every ground and in both schemes: ink on fill, group and note at 4.5:1; edge and line on the page at 3:1; ink on each series colour at 4.5:1.

**Inline, so the tokens reach it** (see "My calls" for why not `<img>`). The page's `data-theme` switch and a section's band re-colour a stored drawing at once, and a theme that re-colours its base re-colours every diagram, already stored ones included.

**The font is measured where it is drawn.** Mermaid sizes every box from its labels' width at drawing time. So:
- the frame draws in the default theme's face, Archivo, from the CMS's own files;
- `diagram.css` sets the drawing's text in `--th-diagram-font`, a fixed token whose default names Archivo.

A theme may change it, and then answers for labels that no longer fit their boxes. This is said in the theming reference.

**Non-Latin scripts are a named limit** (owner, 2026-11-11; spike, 2026-11-11). The CMS ships `archivo-latin-*` only. A label in Cyrillic, Greek, Vietnamese, CJK or a right-to-left script is measured in the editor's fallback font and painted in the visitor's, so its box may fit less snugly or not at all. With Archivo loaded the spike measured no overflow and a smallest margin of 6.2 px; without it margins fell to 1.9 px and one label overflowed by 2.8 px. Shipping the other subsets is a general item for the whole CMS, issue #246 (https://github.com/dominikknafelj/ContentSpiel/issues/246), and not part of this block. The guide's editor page names the limit.

**What a theme may do,** from the least work to the most, as for the Code block:
1. declare the tokens again;
2. restyle, with rules under `.content-block--diagram`. Mermaid's class names are not on a list, and a theme that styles them follows Mermaid's upgrades;
3. replace `components/blocks/diagram_component.html.erb`.

**The component's line:** `block`, `page`, `svg`, `description`, `caption`.
- `svg` is the cleaned drawing, already html-safe, with its root's `role`, `aria-labelledby`, `<title>` and ids written (§6), or nil.
- A template prints it as given and builds no SVG of its own.

The line goes into the ledger (`test/support/contract_ledger.rb`), the tables of `docs/reference/theming.md` and a fixture theme that replaces the template from that section alone, with the release note.

### 5. Allowed diagram types, refused constructs and limits

**The first list** is `Diagrams::Source::TYPES`, by the source's first keyword:
- `flowchart` / `graph`;
- `sequenceDiagram`;
- `classDiagram`;
- `stateDiagram` / `stateDiagram-v2`;
- `erDiagram`;
- `gantt`;
- `pie`.

A type stays on the list only if the spike shows that it draws with **no `foreignObject` under `htmlLabels: false`** and that its classes are painted by `diagram.css`. A type that fails comes off before the build.

The list only grows. Each later type is an additive change: its line, its rules, its fixture and its contrast pairs.

**Left off, with the reason:**
- `architecture-beta`, which fetches icon packs;
- `C4`, which is experimental and uses HTML in labels;
- `mindmap`, `kanban` and `block-beta`: they draw with no `foreignObject` under `htmlLabels: false` (spike, 2026-11-11), so they are left off for the extra stylesheet work, each needing its own class rules, fixture and contrast pairs, and may join later;
- `zenuml`, an outside plugin;
- every other `-beta` type.

**Refused constructs,** by a trimmed line's first word or by a marker anywhere in the line. The list is written once in Ruby (`Diagrams::Source::RULES`) and handed to the card's script and the frame as data; the editor says the line's sentence and the frame draws nothing from it, and no save is refused for it:
- `%%{`, an init directive, which can turn `htmlLabels` back on or set `themeCSS`, matched **anywhere in a line, case-insensitively** (spike, 2026-11-11: Mermaid honours a directive at the end of a line);
- YAML front matter (`---` as the first non-blank line), which can set `htmlLabels: true` and draws `foreignObject`;
- `classDef`, `class … <style name>` in flowcharts and states, `:::`, `cssClass`, `style` and `linkStyle`, the CVE's path and editors' own colours;
- `click`, `link`, `links`, `href` and `call`;
- `$$` maths, which draws as HTML or MathML.

Each refusal names the line and says why, in words (§7).

**This is the editor's rule and the frame's first wall, not the security boundary, and never a refused save.** Autosave sends half-typed states all the time, Mermaid never runs on the server, and the sanitizer is the boundary. The line rules are coarse on purpose: a `class` line that declares a class in a class diagram is allowed.

**Limits:**
- the source holds at most **10,000 characters** (`Diagrams::Source::MAX_CHARACTERS`), refused and never cut, with the Code block's counter from nine tenths;
- a drawing holds at most **1 MB** after cleaning (`Drawing::MAX_BYTES` = 1_048_576) and **5,000 elements** (`MAX_ELEMENTS`) (owner, 2026-11-11, replacing 300 KB: the spike measured a full 10,000-character flowchart at 770 KB cleaned, 716 KB with coordinates rounded to 2 places, 4,024 elements, gzip about 130 KB). The frame checks the cleaned size and shows the "too large" state (§7) before a save would be refused;
- each language's drawing counts separately, so a block in three languages can hold three drawings in its row, in its published copy and in its audit snapshot. An audit event's changes are digests, by the field types.

### 6. The public page

`Blocks::DiagramComponent` (`include Blocks::Contract`) reads the block it is handed and nothing else: the clock, a query or the request never come into it, so the ETag covers it. `render?` is true only when the visitor's language has a drawing that passes on read **and** a description. The drawing follows the site's fallback with its source (below); the description is the visitor's language's own, or else that of the language whose drawing is shown, never one from further down the chain.

**Drawing and source fall back together.** A language with no source of its own shows the default language's drawing. It never shows a drawing from one language beside another language's source.

```html
<figure class="content-block content-block--diagram">
  <svg role="img" aria-labelledby="diagram-12-de-title" [aria-describedby="diagram-12-de-desc"] viewBox="…" width="…" height="…">
    <title id="diagram-12-de-title">{description}</title>
    [<desc id="diagram-12-de-desc">{Mermaid's accDescr}</desc>]
    …the cleaned drawing…
  </svg>
  <figcaption>{caption}</figcaption>  <!-- only with a caption -->
</figure>
```

- **The accessible name is the block's description**: in the visitor's language, tracked by translation state and written by the server as escaped text.
- **Mermaid's `accDescr`**, if it survives the frame and the sanitizer, is kept as `<desc>` and becomes the description. Mermaid's `accTitle` is dropped, since the block's description is the name. Both survive in strict mode as `<title id="chart-title-…">` and `<desc id="chart-desc-…">`, referenced by Mermaid's root `aria-labelledby` and `aria-describedby`, and pass the element list (spike, 2026-11-11). Without an `accDescr` the markup has no `<desc>`.
- **Size:** a cleaned root has no `width`, `height` or `style` (§3), and an inline SVG then fills its column, so small diagrams would be blown up several times. The component therefore **must** write `width` and `height` from the `viewBox` (spike, 2026-11-11: required, not cosmetic). The drawing keeps its natural `width` and `height` from the `viewBox`. CSS gives it `max-width: 100%` and `height: auto`, so a wide diagram scales down to its column. With `role="img"` its labels are not read one by one, so the description is the whole text alternative.
- **The one `html_safe`** in the component is `Drawing`'s output. A source test holds that nothing else in the component or its template marks a string safe, and that only `Diagrams::Drawing` parses SVG.
- **No public words:** `words: []`. The component draws nothing rather than say something.

### 7. The editor

**The card** is the generic block card, with no branch for the type. In the type's order it shows:
1. Source: `MermaidField`, the textarea, with the preview beside it on a wide card and under it on a narrow one (the Design System card decides);
2. the hidden drawing;
3. Description: a textarea, with help text "Describe what the diagram shows, for people who can't see it. The diagram shows on the site only with a description.";
4. Caption: a plain translated column, as the Code block's is.

**The preview's states:**

| State | What it shows |
|---|---|
| empty | "Type a diagram to see it drawn." |
| drawing | the last picture, with a quiet "Drawing…" |
| drawn | the picture |
| refused line | "Line 3: colours come from the site's theme, so `classDef` isn't used here." (one sentence per construct, keys) |
| parse error | Mermaid's message, as text, under "This diagram doesn't draw:"; then "The site keeps the last drawing that worked." when there is one, or "Nothing is drawn yet." when there isn't |
| type not on the list | "`mindmap` diagrams aren't supported yet." with the list |
| too large | "This diagram is too large to keep. Shorten it or split it in two." (the cleaned drawing is over `MAX_BYTES` or `MAX_ELEMENTS`; owner, 2026-11-11). The hidden field keeps the last drawing that worked, as for a parse error, and the card says so |

The error is a polite live region, announced once per new error, never per keystroke.

**A refused save** happens only for a hand-made request, or when the frame and the server disagree about a drawing, or for a source over its length. It is the form's ordinary 422: the message goes in the field's slot, nothing is written or audited, and the text stays in the field. The message is "This drawing can't be shown on the site." or the length's sentence; a refused line is the preview's state above, never a refused save.

**The tile.**
- The `summary` is the type's label, " · " and the first line after the keyword, in mono ("Flowchart · A --> B"). It is "Empty" as a `:hint` when there is no source.
- It has two attention hints, in the meta colour and never danger: "No description", and "Last drawing kept" when `Drawing#current?` is false.
- The `preview` is the description's opening words over the source's first three lines, in mono.
- A small preview of the stored drawing, scaled down, no script (see "My calls", 14).

**The translation tab.**
- The source and the description are inputs there.
- A language with no source of its own starts from the default's source **as starting content, not as the stored value**, as the Table block does. The field stays empty until the translator's first real change, and only then is the source written and a drawing made for that language. Until then the state is what the rules below say, and the site shows the default's diagram.
- The description gets the Translate button (it is `:text`). The source does not.

**Translation state** (`Translations::Status`):
- **The description is required where the original has one,** like an image's alt: blank in a target language means *missing*.
- **The source is optional,** like a caption: never missing. It is *outdated* when the original's source changes after the translation was saved, and the reference card's word diff reads the source's lines.
- **The drawing is not tracked on its own.** It follows the source, and a re-draw of the same source changes no state.

`test/services/translation_state_parity_test.rb` gets a case for this.

**AI translation** sends the description, as plain text, and the caption, and never the source (`:mermaid` is not `translatable`).

### 8. Strings and documents

- **CS Studio's words** are keys: the field's in `config/locales/admin/fields.en.yml`, the tile's under `tile_summary.types.diagram`, and the script's from `data-messages`.
- **Mermaid's own parse messages are English** and are shown as Mermaid writes them. This is a limit.
- **The type's label, `label:` and the type names in the list** are literals in the definition, as every type's are.
- **The documents:**
  - a section in `docs/reference/content-blocks-and-types.md` and the type in its list;
  - "The Diagram block" in `docs/reference/theming.md`;
  - the reference index in `CLAUDE.md`;
  - the two `REVISION` rules and the "no guard" items of §3 and §4 under "Rules a change can break silently";
  - `CHANGELOG.md`'s `## Unreleased` gets the new block, the ledger lines (a contract change) and, under `### Breaking`, the new top-level name `Diagrams`, which refuses a gem owner of that name (`TopLevelNames.owners`).

### 9. The spike, before the plan

**Done 2026-11-11** (`2026-11-11-diagram-block-spike.md`); its findings are folded into this spec and marked "(spike, 2026-11-11)". The spike was one branch that was never merged. It answered what this spec marked unverified:

1. Pin Mermaid (at least 11.15.0) and serve the renderer frame with its CSP and sandbox. Then check:
   - Does `securityLevel: "sandbox"` inside the frame give back an SVG that can be read out (Mermaid wraps it in an iframe with a `data:` URL)?
   - Does it lay out inside its own iframe or in the document first?
2. For each type on the first list, under `htmlLabels: false`, check:
   - no `foreignObject`;
   - the elements and attributes the sanitizer needs;
   - the class names `diagram.css` must paint.
3. Check whether `accTitle` and `accDescr` reach the output in sandbox and in strict mode.
4. Time the draw of a 10,000-character flowchart in the frame. Measure the size of its cleaned drawing and the read-side sanitize time, to confirm the limits of §5.
5. Write one fixture drawing per type, made by the pinned Mermaid, under `test/fixtures/diagrams/`. These are the sanitizer's and the samples' input, and are regenerated by a task when Mermaid is upgraded.

## Design System cards, before the build

The design agent draws these first:
- **`EditorDiagramBlock`**, the Diagram block's card: source and preview side by side on a wide card and stacked on a narrow one; the description and caption; every preview state of §7 (empty, drawing, drawn, refused line, parse error with and without a kept drawing, type not supported); the counter near and over the limit; held by someone else (read-only, still drawn); and the translation tab, starting from the default's source.
- **The tile:** the summary line, its preview, and the two hints ("No description", "Last drawing kept").
- **`PublicDiagramBlock`**, a diagram on a public page in the default theme: one of each type on the list, on the page, in a tinted band and in a strong band, light and dark, with and without a caption, at a phone's width.
- **The error state** as its own card, since it is the one an editor meets most: Mermaid's message, the kept drawing, and how the two read together.

## Guide pages (`contentspiel-docs`)

- **Editors:**
  - "The Diagram block": writing Mermaid, the supported types, what isn't used and why (colours, links, directives), the description, errors and the kept drawing, the limits;
  - the translation page: a diagram per language and starting from the original's source;
  - the blocks overview: the new block in the picker.
- **Integrators:**
  - "Theming the Diagram block": the tokens, restyling Mermaid's classes, replacing the template, and the font that sized the boxes;
  - the hosting/security page: why drawings are made in CS Studio and cleaned on the server, and that no script reaches the site.

## How it ships

1. **The spike** (§9), not merged, done; its answers are in this spec.
2. **The Design System cards** above, done: v213 (index 1794424314-9bbe), `EditorDiagramBlock`, `EditorDiagramError`, `PublicDiagramBlock`. The build reads those cards, which already show 60%-then-scroll, the tile preview and the import.
3. **One pull request** for the block, following "Adding a block type" step by step:
   - the generator;
   - the two field types;
   - `Diagrams::Source` and `Diagrams::Drawing` with their tests;
   - the renderer route and frame;
   - the card's script;
   - the component, stylesheet and tokens;
   - the ledger and the theming reference;
   - the fixture theme;
   - the sample (a flowchart with labels in en, de and es, a description and a caption, its drawing a fixture);
   - the browser files: typing draws, autosave stores, reload, a parse error keeps the last drawing, a refused line, a held card, and the translation tab's starting content;
   - `bin/ci`.

**The plan's first step is the Mermaid pin** (spike, 2026-11-11, item 12). The spike measured `mermaid@11.17.2` (published 2026-08-25, `dist/mermaid.min.js`, 3,572,661 bytes, SHA-256 `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`, MIT; the jsDelivr and unpkg copies are identical; it is later than 11.15.0, which carries the CVE-2026-41149 fix). But 12.x is the current major (12.0.0 on 2026-09-10, 12.3.0 on 2026-11-03). Before vendoring, the plan checks whether 11.x still receives security fixes. It then pins the version and records the file's size and SHA-256 next to the vendored file, so a later upgrade can tell what changed.

## As built

Where the build (plan `docs/superpowers/plans/2026-11-13-diagram-block.md`, 2026-11-13 to 2026-11-14) left this spec, each with the reason in one line. The sections above state the design as built; the differences live here.

- **The values are `Diagrams::`, not `Diagram::`.** `BlockTypes::Diagram`, which the generator makes, would shadow a top-level `Diagram` for every bare reference inside `BlockTypes`, so the generator refused the name (precedent: `BlockTypes::Form` beside `Forms::`). The top-level name under `### Breaking` is `Diagrams`.
- **Mermaid is `12.2.0`, not 11.17.2** (plan R1): no 11.x release came after 11.17.2, a KaTeX advisory is fixed only from 12.1.0, and on 12.2.0 the seven types still draw no `foreignObject` under `htmlLabels: false`. A class diagram's dashed edge is `edge-pattern-dashed` there (the spike saw `dashed-line`), and class, state and ER share the flowchart's edge and node classes.
- **`maxTextSize` is 20,000, and a length is counted in code points everywhere** (the source's rule, `:mermaid`'s `max:`, the frame): Mermaid counts UTF-16 units, so at the block's own 10,000 an emoji-heavy source would trip Mermaid's stand-in diagram before the block's rule; at twice the limit it never does.
- **No server refusal of a line** (§1, §5, §7 amended): `:mermaid` validates its length alone. The first build refused a `classDef` line on save, which made every half-typed `classDef` an autosave 422 with "Couldn't save", against §7 ("only for a hand-made request") and My calls 9 (autosave sends half-typed states). The line rules are the editor's and the frame's; a hand-posted source with `classDef` is stored, never run on the server, and refused by the frame before Mermaid sees it, and what reaches a page is a drawing the sanitizer cleaned.
- **The description falls back narrower than "each with the site's fallback"** (§6 amended): a language's description is its own, or else that of the language whose drawing is shown, never one from further down the chain, so a drawing is never named by a third language's words. Cost: a diagram hides where the first wording would have shown it.
- **Leading `%%` comment lines are skipped before the keyword**, as Mermaid skips them; a first word off the list is `:type` (another Mermaid type, "isn't supported yet") or `:no_type` (no Mermaid type), the two sentences of the EditorDiagramError card.
- **The digest is of the cast source**: `from` is the SHA-256 of the source as `:mermaid` stores it (CRLF to LF, outer blank lines dropped), and `app/javascript/diagram/digest.js` ports the cast, or every saved drawing would read "Last drawing kept".
- **The sanitizer refuses more than §3 lists**, by the rule "refuse what can fetch, run or link, drop quietly what only paints": geometry values holding anything but numbers, units and separators (path data, a transform list of SVG's six functions); a duplicate id; a `viewBox` that is not four numbers with a positive size; an input over four times `MAX_BYTES` before it is parsed; an element or attribute in another namespace; a nested `svg`; a `style` anywhere but the root's child; an element inside a `desc` (an HTML integration point: the page would build another tree); a marker reference to an element that is no `marker`. It drops quietly `filter` (the attribute), an empty `class`, and `title`; it allows `markerUnits` and keeps the root's `aria-roledescription`. The value lists are SVG's own keywords per attribute, wider than the values seen (none can fetch or run).
- **The read is cached and the markup's size is on the root**: the component caches the untitled markup or the failure's reason by the stored drawing's digest, the block, the language and `Drawing::REVISION`, and writes the title on every read; `--diagram-min-width` (three fifths of the natural width) is in the root's `style`, written by `Drawing`, since a theme's template is handed no width.
- **The scroll box is always a keyboard stop**, `role="group"` with `aria-label` the description (the design's answer to the build's question): the component cannot know whether the column is narrower than the drawing. A screen reader hears the description twice, once for the group and once for the image, as designed.
- **The strong band's tokens** (the design's answer, PublicDiagramBlock): the labels the band's text, edges the band's dim, the accent the band's; a node, a group and a note the band's text mixed into the band (10%, 8%, 14%) and a node's outline at 55%, all opaque, so an edge label's box and a group under a node hide what is behind them; the six series the dark scheme's six grounds in both schemes, written once as the CMS's own `--th-diagram-dark-1` … `-6` in `tokens.css` (the guards forbid literals in `sections.css`). 96 pairs are measured; the lowest, a node's outline on its fill in a dark strong band, is 3.29:1.
- **CS Studio's diagram colours** (a build ruling, then the EditorDiagramBlock card's answer): `--th-diagram-*` are defined once on `.content-block--diagram` under `html[data-surface="studio"]` in `content-spiel.css`, mapped from CS Studio's tokens (the line `--cs-field-line`, the series `color-mix()` of each `--cs-ic-*` family at 35% over its `-bg`), read by the card from a hidden probe and posted to the frame, and painted on the tile by the same `diagram.css` (imported into CS Studio's stylesheet). The series measure 7.9:1 and 4.7:1 at their floors.
- **The card's layout is intrinsic, with no container** (a build ruling): the post form holds no size container (Chrome drops its fields' layout after an autosave), so the source and the preview stand in a wrapping flex row, side by side from 40rem and stacked below (a guard refuses `auto-fit`, so not the grid the ruling first named).
- **The frame's height follows its drawing**, between 200 and 640px, and a card whose source fails at connect shows the stored drawing under "Last drawing that worked"; the frame shows Mermaid's message, and a blank description draws a neutral note under the preview (`:mermaid`'s `description:` option names the field).
- **The tile's picture is shape only** (the EditorDiagramBlock card, v225): the drawing at 112×72 read as faint dashes with its labels as noise, so the picture draws non-scaling 1px strokes, no text and no markers, every node a solid block of `cs-sunken`, fitted whole with its aspect kept. It is a new declaration, `t.tile_picture`, a built-in's only (the tile prints it unescaped); the tile's line skips `accTitle` and `accDescr` lines, and a third hint, "Not drawn yet", says there is no drawing the site could show.
- **"From Markdown content" is not built** (plan R2): no CMS code turns Markdown into blocks (a fence becomes a rich-text `codeBlock`, and the MCP tools write post bodies), and diagrams in rich text are a non-goal. Import file… is built; the guide's loader learns the mermaid fence in a docs pull request after this ships.
- **`translation_required: true`** is a field option (plan R4), the image alt's rule made declarable, refused without `translated: true`; the description is its one user. The drawing is untracked by a field type's `tracked: false`.
- **Import file… is opt-in** (`importable:`, the block card alone): a caller that cannot draw the "Replace the source?" dialog outside its form would have drawn a button with nothing behind it. A `.md` file's opening fence may stand up to three spaces in, as CommonMark allows.
- **AI never sends a non-translatable type's field**: the bulk count and `AI::Translate` skipped only the source by name in the first build; they now follow the Translate button's rule for every type, so a gem's translated `:url`, `:select` or `:link` field is no longer sent either (CHANGELOG, "For a gem or an outside caller").
- **The audit snapshot keeps the source and the drawing whole per language**, as `:code`'s keeps the code (the version basis); an event's changes are digests. An open question for the owner: drop the derived drawing from snapshots (about 30 KB a language for an ordinary drawing).
- **The preview needs a secure context** (`crypto.subtle`), with no fallback, as passkeys do.
- **A drawing's `from` must be a SHA-256 in hex**, or the drawing is refused as `:invalid_drawing` (§2 says the server stores it as sent): it is only ever compared with a digest, and a hand-posted string of any length would otherwise ride along with every later save and snapshot.
- **`:mermaid` and `:diagram_drawing` are a built-in block type's alone** (`FieldTypes::BLOCK_ONLY`): nothing but the Diagram block's card makes a drawing and nothing but its component prints one, so a post type, a field group or a gem may not declare either until a second user exists.
- **Thruster keeps the fonts' CORS header**: measured on a local production image, the fingerprinted `archivo-latin-400-normal-*.woff2` answered `Access-Control-Allow-Origin: *` with and without `Origin: null`, on Thruster's cache miss and hit and with gzip; a face of another family answered none.

## My calls (marked so the owner can check them)

1. **Inline SVG, not `<img>`.**
   - Only inline lets the theme's tokens, the page's light/dark switch (`data-theme`, which an `<img>` cannot see: inside one only the system's `prefers-color-scheme` applies) and a section's band reach a stored drawing.
   - Only inline lets a theme re-colour diagrams already stored, and keeps the labels as text in the page.
   - The price is that the sanitizer is the only wall. Hence it runs on write *and* on read, writes its output from a parse tree, and refuses rather than repairs anything dangerous.
   - `<img>` would isolate completely, but it would freeze each drawing's colours at drawing time, in CS Studio's idea of the theme.
2. **Mermaid runs in a renderer frame of CS Studio's own with an opaque origin, with `securityLevel: "strict"`** (spike, 2026-11-11, replacing "sandbox where it works"). This goes beyond the owner's decision. Sandbox mode alone isolates Mermaid's *output*, but Mermaid itself would still run in CS Studio's page, which is where a parser bug lands. The frame isolates all of it. The spike showed that sandbox mode throws inside the frame (its nested iframe has a null `contentDocument`) and that its isolation is only display isolation, so strict inside the frame is stronger than sandbox in the page and loses nothing. The frame's CSP blocked an inline event handler in the spike's HTML-label run, which is evidence that it is load-bearing.
3. **Mermaid is not import-mapped with `preload: "admin"`.** It is a vendored single-file build loaded by the frame by URL, with a `preload: false` pin kept for `bin/importmap audit`, as d3-force is. The reasons:
   - it is several MB, and `preload: "admin"` would fetch it on every CS Studio screen;
   - an opaque-origin frame can't load module scripts from the app without CORS;
   - jspm's split build is the jsx-runtime trouble again.

   It is still never on a public page.
4. **Colours by class at the sanitizer and the stylesheet, not by `themeVariables` or `themeCSS`.** Mermaid's theming needs hex colours and derives others from them, so `var(--th-…)` can't go through it. Dropping Mermaid's styles and painting its classes from tokens is what lets a stored drawing follow the theme. The cost: `diagram.css` must know Mermaid's class names per allowed type, and a Mermaid upgrade that renames them is checked against the fixtures.
5. **Editors' own colours and links are refused** (`classDef`, `style`, `:::`, `click`, …), not dropped quietly. They would do nothing on the site, and `classDef` is the CVE's path.
6. **The first type list** is seven types: flowchart, sequence, class, state, ER, gantt, pie. All seven draw with no `foreignObject` under `htmlLabels: false` (spike, 2026-11-11). Every other type is left off for the stylesheet work it needs (§5); `mindmap`, `kanban` and `block-beta` could join later.
7. **The source is translated, per language, optional;** the drawing follows it; the description is translated and required where the original has one. A language starts from the default's source as starting content (the Table block's rule).
8. **AI never translates the source.** Labels inside Mermaid syntax would go out as plain text and might come back broken. "Translate a diagram's labels" is a roadmap row.
9. **A source that doesn't parse keeps the last drawing that worked,** saved with the source. Autosave sends half-typed states all the time, and storing no drawing would empty the site's diagram at every keystroke. The editor and the tile say that the kept drawing is older.
10. **No description, no diagram on the site** (and in the preview): the required description is enforced at drawing, not at save, because the picker makes an empty block and "Require nothing unless the block is useless without it". The card and the tile say why it isn't shown.
11. **A public page shows nothing** for a block with no drawing, no description, or a drawing that fails on read. It never shows an error text or an empty box. A failure on read is logged once.
12. **Limits:** 10,000 characters of source, 1 MB (`MAX_BYTES` 1_048_576) and 5,000 elements of drawing. *(Owner, 2026-11-11, replacing 300 KB, after the spike's measurements.)*
13. **The drawing is scaled to its column,** down to about 60% of its drawn size (where labels would fall under 9px); below that it keeps that size and scrolls sideways inside its own figure box. The page never scrolls sideways. *(Owner, 2026-11-11, replacing "never scrolled".)*
14. **The tile shows a small preview:** the stored, cleaned SVG scaled down, with no script, painted by the same tokens, beside the summary line; "No description" and "Last drawing kept" as before. *(Owner, 2026-11-11, replacing "text only".)*
15. **Archivo is the drawing's font,** fixed by a token (`--th-diagram-font`), because the boxes are measured in it.
16. **The new top-level name is `Diagrams`** (`Diagrams::Source`, `Diagrams::Drawing`), named under `### Breaking`.
17. **Non-Latin scripts are a named limit of this block,** with the general fix on the roadmap as issue #246. *(Owner, 2026-11-11.)*
18. **The frame checks before it draws:** text length, the line rules, then `mermaid.parse`; and after: the cleaned size. It refuses over-long text itself because Mermaid draws a stand-in diagram instead of failing. *(Spike, 2026-11-11.)*

## Left to the builder

- Whether `source` and `drawing` are two fields (as above) or one value of `{ source, svg, from }`, so long as the translation state reads the source and the description only.
- Any allowlist entry beyond the spike's lists (§3) that the real fixtures need, each named in the plan.
- Whether the Mermaid 11.x line is still supported, and the pin (the plan's first step, "How it ships").
- The debounce, and how the save after a draw is sent so that source and drawing arrive together.
- The key names, and the wording of each refused construct's sentence.
- The task that regenerates the fixture drawings after a Mermaid upgrade.
- Where the shared line rules are written so the frame reads them (a JSON value in the frame's markup is the obvious one).
