# The Diagram block: design

Status: draft for the owner's approval, 2026-11-11.
Base: `main` at 9213771f (release 0.3.0). No issue yet.

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
  - The CS Studio preview renders with Mermaid's `securityLevel: "sandbox"` and a pinned, patched Mermaid version. This answers CVE-2026-41149, DOM injection through `classDef` in state diagrams even under `strict`, and GitLab #332528, where sanitizing depended on `htmlLabels`.
  - The server sanitizes the SVG against a strict allowlist before storing it, and refuses what it can't sanitize. The allowlist means: no script, no `foreignObject` or HTML labels, no event handlers, no external references and no `style` that can load anything.
- **Theme colours:** a block type promises the theme's colours, never Tailwind's palette. Mermaid's output reads the theme's colour tokens, in light and in dark.
- **Accessibility:** a required text description is a field of the block, like an image's alt. The public markup is `role="img"` with an accessible name and the description.
- **Import (owner, 2026-11-11):** a diagram can be brought in two ways, beside typing it:
  - **Upload a file into the block:** an "Import file…" control on the Diagram block's card reads a `.mmd` file, or a `.md` file's first ```mermaid fence, into the source field of the language being edited (replacing what is there, after a confirm when the field isn't empty); it is then drawn and saved as if typed. The file is read in the browser and never stored; its size is held to the source limit; a file with no Mermaid in it says so.
  - **From Markdown content:** wherever CS Studio turns Markdown into blocks (the rich-text Markdown form and its import paths, the MCP tools that write content), a ```mermaid fence becomes a Diagram block (source filled, drawing made at the editor's next open, description empty, so the site shows it only once a description is added) instead of a Code block. The plan names each such path from `docs/reference/rich-text.md` and `app/mcp/`.
  - Not in scope: mermaid.live links and ready-made SVG uploads.
- **After the cards (v211), 2026-11-11:** a large diagram scales down to about 60%, then scrolls sideways in its own figure box (call 13); the tile shows a small preview of the stored drawing (call 14).
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
  - Its `validate` refuses:
    - more than `max:` characters;
    - a first line that is not one of the allowed diagram types (§5);
    - any line that is one of the refused constructs (§5).

    Each refusal is its own sentence.
  - Its input, `Admin::Fields::MermaidField`, is the Code field's textarea (the same attributes, the same CSS-only height, and Tab leaves it). Beside it, it holds the preview frame, the error line and the counter.
- **`:diagram_drawing`**
  - Its cast runs the sanitizer (§3). A value that does not pass is an error, `:invalid_drawing`, never a quiet nil.
  - It refuses more than `Diagram::Drawing::MAX_BYTES`.
  - It is not `translatable` and is audited as `:digest`.
  - Its input is hidden, written by the preview script only. `own_label?` is true and it draws no label.
  - Its `display` on a translation tab is nothing, because the source's field shows the drawing.

### 2. Drawing in CS Studio: the renderer frame

**Mermaid runs in a frame of its own with an opaque origin, not in CS Studio's page.**
- The block card's script, `admin--diagram--preview` (the topic `diagram`: its controllers go in `app/javascript/controllers/admin/diagram/`, its plain modules in `app/javascript/diagram/`), creates the frame when the card connects. A screen with no Diagram block never fetches Mermaid.
- The frame is a CS Studio route, `GET <admin>/diagram-renderer`. It holds no data and is the same document for everyone. It is served with:
  - its own `Content-Security-Policy`: `sandbox allow-scripts`, `default-src 'none'`, `script-src 'self'`, `style-src 'self' 'unsafe-inline'` (Mermaid writes a `<style>`), `font-src 'self'`, `connect-src 'none'`, `form-action 'none'`;
  - the element's own `sandbox="allow-scripts"`.

  It has no `allow-same-origin`, so the frame cannot read CS Studio's cookies, storage or DOM. It can send no request and navigate nothing.
- **The protocol:**
  - The card posts `{ id, source }` to the frame.
  - The frame draws and posts back either `{ id, svg }` or `{ id, error }`.
  - The card accepts only messages whose `event.source` is its own frame, and only the latest `id`.
- **The card never puts the frame's SVG into CS Studio's DOM.** It writes the string into the hidden `drawing` field, as text, and the frame displays the drawing itself. What a viewer sees in CS Studio is therefore inside the sandbox.
- **What the frame draws with:**
  - Mermaid at an exact patched version, at least 11.15.0, the release that fixes CVE-2026-41149 (GHSA-ghcm-xqfw-q4vr). It is vendored like d3-force: the file is in `vendor/javascript`, loaded by its asset URL, with a `pin "mermaid", preload: false` line kept only so that `bin/importmap audit` and `outdated` see the package.
  - `startOnLoad: false`, `htmlLabels: false` (and the flowchart's own), `maxTextSize` equal to the block's limit, and `maxEdges` at Mermaid's default.
  - `theme: "base"` and the default theme's font (§4).
  - `securityLevel: "sandbox"` where the spike (§9) shows it hands back a usable SVG, otherwise `"strict"` (see "My calls").
- **Before Mermaid sees the source,** the frame runs the same line rules as the server (§5): the type list and the refused constructs. A refused source is never parsed, so the `classDef` path of the CVE never reaches Mermaid at all.
- **After Mermaid draws,** the frame strips what the server will strip (§3: Mermaid's `<style>`, `style` attributes and colour attributes) and paints with the same class rules on CS Studio's colours, which the card posts in with the source. Light and dark follow CS Studio's theme. In CS Studio the preview therefore follows the backend's look and has the site's shape (the owner's answer of 2026-10-13: "for the backend it follows the backend").

**Saving.**
- The script draws on `input`, with its own short debounce.
- When a draw succeeds, it writes the hidden `drawing` field: the SVG and the SHA-256 of the source it drew (`crypto.subtle`). It then lets the form's autosave send source and drawing together, through `app/javascript/saving/queue.js` like any field.
- When a draw fails, it leaves the hidden field as it was: the last drawing that worked.
- A save that the source's own keystroke sends first carries the old drawing. The next save carries the new one.
- On `connect` the script draws, but writes nothing. Opening a card never saves, which keeps live editing and the stale check as they are.

**The server checks the digest.** It stores `from` as sent, and `Diagram::Drawing#current?(source)` compares it with the saved source's digest. A drawing whose `from` is not the source's digest is *the last drawing that worked*: the card and the tile say so (§7), and the public page still draws it (§6).

**What the frame and the card take back.**
- At `disconnect`, the card removes the frame and forgets its listener.
- At `turbo:before-cache`, the card removes the frame. A page shown from a copy builds it again at `connect`.
- A live refresh that replaces the card replaces the frame. A form with unsaved text is never replaced (`editing/merge.js`).

**A card held by someone else** draws at `connect` and writes nothing: its textarea is `readonly` (`HeldFields`), and no action of the script stays in a held form. So the type declares no `read_only_actions`.

### 3. The server's sanitizer: `Diagram::Drawing`

`Diagram::Drawing` (`app/values/diagram/drawing.rb`) is **the one file that reads a drawing**. It answers data and markup that it builds itself.

- **How it parses:**
  - Nokogiri's strict XML parser, with `NONET`, no DTD loading and no entity expansion.
  - A document with a DOCTYPE, an entity, a processing instruction or more than one root is refused.
  - **The output is written from the parse tree by `Drawing`, never passed through from the input string.**
- **Allowed elements:**
  - `svg`, `g`, `defs`, `marker`, `clipPath`;
  - `path`, `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`;
  - `text`, `tspan`, `title`, `desc`;
  - `use`, with an `href` / `xlink:href` that is a fragment of an id in the same drawing.

  The spike may add an element Mermaid needs for an allowed type, and that element is named in the plan.
- **Allowed attributes:**
  - geometry: `x y x1 y1 x2 y2 cx cy r rx ry width height d points transform viewBox preserveAspectRatio`;
  - text: `dx dy text-anchor dominant-baseline alignment-baseline font-size font-weight`;
  - markers: `marker-start marker-mid marker-end markerWidth markerHeight markerUnits refX refY orient`, and `clip-path`, each only as `url(#<id in this drawing>)`;
  - `id`;
  - `class`, each class matching `/\A[A-Za-z][\w-]*\z/`;
  - on the root, `aria-roledescription`.
- **Dropped quietly,** because Mermaid always writes them and none of them can be harmless *and* themed:
  - the `<style>` element;
  - every `style` attribute;
  - `fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `opacity`, `color` and `font-family`;
  - `data-*` attributes;
  - Mermaid's own root `aria-*` and `role` (§6 writes them);
  - empty `g` elements.
- **A refusal, which refuses the whole drawing:**
  - any element not on the list, by name: `script`, `foreignObject`, `a`, `image`, `iframe`, `animate`, `set`, `animateTransform` and `animateMotion` (SMIL can set an `href`), `style` inside `defs` included;
  - any attribute not on the list, by name: an `on*` handler, `href` other than a local fragment, and `xml:base`;
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

**Mermaid's own styles never reach a page.** The sanitizer drops them (§3). The block's stylesheet, `app/assets/tailwind/themes/default/diagram.css` (declared with `t.stylesheet "diagram.css"`), paints the drawing by the class names Mermaid writes, scoped under `.content-block--diagram`. It writes plain rules, not utilities, since the classes come from data. It holds no colour of its own.

**Themed tokens** (`t.tokens themed:`), defined in `tokens.css` from the base tokens wherever one is right:

| Token | Paints | Default |
|---|---|---|
| `--th-diagram-ink` | every label | `var(--th-ink)` |
| `--th-diagram-fill` | a node, an entity, a participant, a state | `var(--th-surface)` |
| `--th-diagram-line` | a node's outline | `var(--th-line-strong)` |
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

**What a theme may do,** from the least work to the most, as for the Code block:
1. declare the tokens again;
2. restyle, with rules under `.content-block--diagram`. Mermaid's class names are not on a list, and a theme that styles them follows Mermaid's upgrades;
3. replace `components/blocks/diagram_component.html.erb`.

**The component's line:** `block`, `page`, `svg`, `description`, `caption`.
- `svg` is the cleaned drawing, already html-safe, with its root's `role`, `aria-labelledby`, `<title>` and ids written (§6), or nil.
- A template prints it as given and builds no SVG of its own.

The line goes into the ledger (`test/support/contract_ledger.rb`), the tables of `docs/reference/theming.md` and a fixture theme that replaces the template from that section alone, with the release note.

### 5. Allowed diagram types, refused constructs and limits

**The first list** is `Diagram::Source::TYPES`, by the source's first keyword:
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
- `mindmap`, `kanban` and `block-beta`, which rely on HTML labels (unverified: the spike checks them, and one that passes may join);
- `zenuml`, an outside plugin;
- every other `-beta` type.

**Refused constructs,** by a trimmed line's first word or by a marker anywhere in the line. The frame and `:mermaid`'s `validate` hold the same list, written once in Ruby and handed to the script as data:
- `%%{`, an init directive, which can turn `htmlLabels` back on or set `themeCSS`;
- YAML front matter (`---` on the first line);
- `classDef`, `class … <style name>` in flowcharts and states, `:::`, `cssClass`, `style` and `linkStyle`, the CVE's path and editors' own colours;
- `click`, `link`, `links`, `href` and `call`;
- `$$` maths, which draws as HTML or MathML.

Each refusal names the line and says why, in words (§7).

**This is the editor's rule and the frame's first wall, not the security boundary.** The sanitizer is the boundary. The line rules are coarse on purpose: a `class` line that declares a class in a class diagram is allowed.

**Limits:**
- the source holds at most **10,000 characters** (`Diagram::Source::MAX_CHARACTERS`), refused and never cut, with the Code block's counter from nine tenths;
- a drawing holds at most **300 KB** after cleaning (`Drawing::MAX_BYTES`) and **5,000 elements** (`MAX_ELEMENTS`);
- each language's drawing counts separately, so a block in three languages can hold three drawings in its row, in its published copy and in its audit snapshot. An audit event's changes are digests, by the field types.

### 6. The public page

`Blocks::DiagramComponent` (`include Blocks::Contract`) reads the block it is handed and nothing else: the clock, a query or the request never come into it, so the ETag covers it. `render?` is true only when the visitor's language has a drawing that passes on read **and** a description, each with the site's fallback.

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
- **Mermaid's `accDescr`**, if it survives the frame and the sanitizer, is kept as `<desc>` and becomes the description. Mermaid's `accTitle` is dropped, since the block's description is the name. *Whether either survives sandbox mode is unverified;* the spike says, and without them the markup has no `<desc>`.
- **Size:** the drawing keeps its natural `width` and `height` from the `viewBox`. CSS gives it `max-width: 100%` and `height: auto`, so a wide diagram scales down to its column. With `role="img"` its labels are not read one by one, so the description is the whole text alternative.
- **The one `html_safe`** in the component is `Drawing`'s output. A source test holds that nothing else in the component or its template marks a string safe, and that only `Diagram::Drawing` parses SVG.
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

The error is a polite live region, announced once per new error, never per keystroke.

**A refused save** happens only for a hand-made request, or when the frame and the server disagree. It is the form's ordinary 422: the message goes in the field's slot, nothing is written or audited, and the text stays in the field. The message is either "This drawing can't be shown on the site." or the source's own sentence.

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
  - `CHANGELOG.md`'s `## Unreleased` gets the new block, the ledger lines (a contract change) and, under `### Breaking`, the new top-level name `Diagram`, which refuses a gem owner of that name (`TopLevelNames.owners`).

### 9. The spike, before the plan

The spike is one branch that is never merged. It answers what this spec marks unverified, and its answers go into the plan:

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

1. **The spike** (§9), not merged. Its answers update this spec before the plan.
2. **The Design System cards** above.
3. **One pull request** for the block, following "Adding a block type" step by step:
   - the generator;
   - the two field types;
   - `Diagram::Source` and `Diagram::Drawing` with their tests;
   - the renderer route and frame;
   - the card's script;
   - the component, stylesheet and tokens;
   - the ledger and the theming reference;
   - the fixture theme;
   - the sample (a flowchart with labels in en, de and es, a description and a caption, its drawing a fixture);
   - the browser files: typing draws, autosave stores, reload, a parse error keeps the last drawing, a refused line, a held card, and the translation tab's starting content;
   - `bin/ci`.

## My calls (marked so the owner can check them)

1. **Inline SVG, not `<img>`.**
   - Only inline lets the theme's tokens, the page's light/dark switch (`data-theme`, which an `<img>` cannot see: inside one only the system's `prefers-color-scheme` applies) and a section's band reach a stored drawing.
   - Only inline lets a theme re-colour diagrams already stored, and keeps the labels as text in the page.
   - The price is that the sanitizer is the only wall. Hence it runs on write *and* on read, writes its output from a parse tree, and refuses rather than repairs anything dangerous.
   - `<img>` would isolate completely, but it would freeze each drawing's colours at drawing time, in CS Studio's idea of the theme.
2. **Mermaid runs in a renderer frame of CS Studio's own with an opaque origin,** and `securityLevel: "sandbox"` runs inside it where the spike shows it works, else `"strict"`. This goes beyond the owner's decision. Sandbox mode alone isolates Mermaid's *output*, but Mermaid itself would still run in CS Studio's page, which is where a parser bug lands. The frame isolates all of it. If sandbox mode gives back no usable SVG, strict inside the frame is still stronger than sandbox in the page.
3. **Mermaid is not import-mapped with `preload: "admin"`.** It is a vendored single-file build loaded by the frame by URL, with a `preload: false` pin kept for `bin/importmap audit`, as d3-force is. The reasons:
   - it is several MB, and `preload: "admin"` would fetch it on every CS Studio screen;
   - an opaque-origin frame can't load module scripts from the app without CORS;
   - jspm's split build is the jsx-runtime trouble again.

   It is still never on a public page.
4. **Colours by class at the sanitizer and the stylesheet, not by `themeVariables` or `themeCSS`.** Mermaid's theming needs hex colours and derives others from them, so `var(--th-…)` can't go through it. Dropping Mermaid's styles and painting its classes from tokens is what lets a stored drawing follow the theme. The cost: `diagram.css` must know Mermaid's class names per allowed type, and a Mermaid upgrade that renames them is checked against the fixtures.
5. **Editors' own colours and links are refused** (`classDef`, `style`, `:::`, `click`, …), not dropped quietly. They would do nothing on the site, and `classDef` is the CVE's path.
6. **The first type list** is seven types: flowchart, sequence, class, state, ER, gantt, pie. Every other type is left off until proven to draw without HTML.
7. **The source is translated, per language, optional;** the drawing follows it; the description is translated and required where the original has one. A language starts from the default's source as starting content (the Table block's rule).
8. **AI never translates the source.** Labels inside Mermaid syntax would go out as plain text and might come back broken. "Translate a diagram's labels" is a roadmap row.
9. **A source that doesn't parse keeps the last drawing that worked,** saved with the source. Autosave sends half-typed states all the time, and storing no drawing would empty the site's diagram at every keystroke. The editor and the tile say that the kept drawing is older.
10. **No description, no diagram on the site** (and in the preview): the required description is enforced at drawing, not at save, because the picker makes an empty block and "Require nothing unless the block is useless without it". The card and the tile say why it isn't shown.
11. **A public page shows nothing** for a block with no drawing, no description, or a drawing that fails on read. It never shows an error text or an empty box. A failure on read is logged once.
12. **Limits:** 10,000 characters of source, 300 KB and 5,000 elements of drawing.
13. **The drawing is scaled to its column,** down to about 60% of its drawn size (where labels would fall under 9px); below that it keeps that size and scrolls sideways inside its own figure box. The page never scrolls sideways. *(Owner, 2026-11-11, replacing "never scrolled".)*
14. **The tile shows a small preview:** the stored, cleaned SVG scaled down, with no script, painted by the same tokens, beside the summary line; "No description" and "Last drawing kept" as before. *(Owner, 2026-11-11, replacing "text only".)*
15. **Archivo is the drawing's font,** fixed by a token (`--th-diagram-font`), because the boxes are measured in it.
16. **The new top-level name is `Diagram`** (`Diagram::Source`, `Diagram::Drawing`), named under `### Breaking`.

## Left to the builder

- Whether `source` and `drawing` are two fields (as above) or one value of `{ source, svg, from }`, so long as the translation state reads the source and the description only.
- The exact allowlist entries the spike's fixtures need, each named in the plan.
- The debounce, and how the save after a draw is sent so that source and drawing arrive together.
- The key names, and the wording of each refused construct's sentence.
- The task that regenerates the fixture drawings after a Mermaid upgrade.
- Where the shared line rules are written so the frame reads them (a JSON value in the frame's markup is the obvious one).
