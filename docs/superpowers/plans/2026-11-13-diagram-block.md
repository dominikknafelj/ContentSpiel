# The Diagram block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Diagram block. An editor types Mermaid and sees it drawn in a sandboxed frame. The cleaned SVG is stored with the block, and a visitor's page shows it inline in the theme's colours, with no script.

**Architecture:**
- `Diagram::Source` holds the line rules and `Diagram::Drawing` is the sanitizer, the only reader of a drawing. Both are plain values in `app/values/diagram/`.
- Two new field types, `:mermaid` and `:diagram_drawing`, carry the values through `translated_settings`. `BlockTypes::Diagram` is generated with `bin/rails generate block_type diagram` and filled in like the Code block.
- Mermaid runs only in `GET <admin>/diagram-renderer`, a frame with an opaque origin. The card's Stimulus controller talks to the frame by `postMessage` and writes the hidden drawing field, so autosave sends the source and the drawing together.

**Tech Stack:** Rails 8.1, ViewComponent, Stimulus with import maps (no npm), Nokogiri, Minitest, Cuprite/Ferrum browser tests, vendored `mermaid@12.2.0` (`dist/mermaid.min.js`, IIFE global `mermaid`).

**Spec:** `docs/superpowers/specs/2026-11-11-diagram-block-design.md`, with `docs/superpowers/specs/2026-11-11-diagram-block-spike.md`. **Design System v213, index `1794424314-9bbe`**: the cards `EditorDiagramBlock`, `EditorDiagramError` and `PublicDiagramBlock`. The controller saves each card's HTML into the SDD workspace and hands its path to Tasks 6, 7, 8 and 9.

## Rulings made while planning (the owner checks these)

- **R1. The pin is `mermaid@12.2.0`, not 11.17.2.**
  - No 11.x release has come since 11.17.2 (2026-08-25). Mermaid publishes no supported-versions policy.
  - A KaTeX advisory (GHSA-238p-pmpm-9mq7) is fixed only from 12.1.0 on.
  - 12.2.0 was published 2026-10-13, so it is more than two weeks old. 12.3.0 (2026-11-03) is not.
  - 12.x lays out flowchart, state, class and ER diagrams with ELK by default. So Task 2 re-measures the spike's findings on 12.2.0 before anything relies on them.
  - **Fallback:** if 12.2.0 draws a `foreignObject` for an allowed type under `htmlLabels: false`, or needs an element or attribute the sanitizer must refuse, Task 2 pins 11.17.2 instead (SHA-256 `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`) and records why in the ledger.
  - *Cost if wrong:* one re-vendor and new fixtures.
- **R2. The spec's "From Markdown content" import has no path in the CMS.**
  - No CMS code turns Markdown into blocks. A fence becomes a rich-text `codeBlock` node (`RichText::Markdown`), and the MCP tools write post bodies only (`app/mcp/mcp/markdown_body.rb`).
  - Diagrams in rich text are a non-goal (spec, "Non-goals"), so no path exists to attach to.
  - The only Markdown-to-blocks path is the guide's loader, `contentspiel-docs/bin/load`, which turns a fence into a Code block. It learns ```` ```mermaid ```` → Diagram block in a docs pull request after this block ships, and the CMS PR says so under "Documentation".
  - This plan builds the file import ("Import file…") only.
  - *Cost if wrong:* a later CMS change, if the owner meant MCP post bodies.
- **R3. A translation's starting source is the Table block's promise, built for a textarea.**
  - On a translation tab with no source of its own, `MermaidField` shows the original's source in the textarea but draws it with **no `name` attribute**, so no save carries it.
  - The script sets `name` at the first `input` event. Only then is the source written, and only then is the drawing field named and written.
  - The Table's own mechanism (`TableControlsComponent.starting_content`) is grid-specific, so it is not reused.
  - *Cost if wrong:* the starting source is never saved, which is the safe direction.
- **R4. "Required where the original has one" becomes a field option, `translation_required: true`.**
  - The only such rule today is the image alt, hard-coded in `Translations::Status#image_missing?`.
  - The new option is a name in `ContentModel::Definition::OPTIONS`. It is refused unless the field is also `translated: true`.
  - `Translations::Status` counts a blank value in a target language as missing when the primary language's value is present.
  - The description declares it.
  - *Cost if wrong:* an option with one user.
- **R5. The fixtures are made by a rake task that drives the real frame.**
  - `bin/rails diagram:fixtures` (`lib/tasks/diagram.rake`) runs under `RAILS_ENV=test`.
  - It starts the app with `Capybara::Server` and drives `/<admin>/diagram-renderer` through Ferrum (test group, already used by `bin/screenshots`-style code).
  - It writes the **raw** SVG of each sample source to `test/fixtures/diagrams/<type>.svg`, beside `test/fixtures/diagrams/MERMAID_VERSION` (the version and the vendored file's SHA-256).
  - The sanitizer is tested against raw output. A test fails when `MERMAID_VERSION` disagrees with the vendored file's header.

## Global Constraints

- **Mermaid:**
  - exact version `12.2.0` (R1), the file `vendor/javascript/mermaid.js`;
  - its size and SHA-256 in `vendor/javascript/mermaid.VERSION` (lines `version 12.2.0`, `bytes <n>`, `sha256 <hex>`);
  - `pin "mermaid", preload: false # @12.2.0` in `config/importmap.rb`;
  - never on a public page, never preloaded on a CS Studio screen.
- **Frame CSP, exactly:** `sandbox allow-scripts; default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'none'; form-action 'none'`. The element carries `sandbox="allow-scripts"`, never `allow-same-origin`.
- **Mermaid config in the frame:**
  - `startOnLoad: false`, `securityLevel: "strict"`;
  - `htmlLabels: false` and `flowchart.htmlLabels: false`;
  - `maxTextSize: 10_000`, `theme: "base"`;
  - `fontFamily` and `themeVariables.fontFamily` set to `"Archivo"`;
  - `gantt.useWidth: 720`.
- **Limits:** `Diagram::Source::MAX_CHARACTERS = 10_000`; `Diagram::Drawing::MAX_BYTES = 1_048_576`; `Diagram::Drawing::MAX_ELEMENTS = 5_000`.
- **Types** (`Diagram::Source::TYPES`, first keyword → label): `flowchart`/`graph` "Flowchart", `sequenceDiagram` "Sequence", `classDiagram` "Class", `stateDiagram`/`stateDiagram-v2` "State", `erDiagram` "Entity relationship", `gantt` "Gantt", `pie` "Pie". Mermaid's `diagramType` values: `flowchart-v2`, `sequence`, `classDiagram`, `stateDiagram`, `er`, `gantt`, `pie`.
- **Ids:** stored drawings use `d-<n>`. On a public page they are `diagram-<block id>-<locale>-d-<n>`, and in a tile `diagram-tile-<block id>-<locale>-d-<n>`.
- **Comments state invariants, never history or plan steps.** Two parts doing one job become one component. No compatibility code.
- New admin strings are keys. Public words: none (`words: []`).
- Every write goes through `ContentBlocks::Save` and `app/javascript/saving/queue.js`. Opening a card writes nothing.
- Tests are prefixed `PGGSSENCMODE=disable`. Browser files run one at a time, on a quiet machine (15-minute load under 6, no other `bin/rails test`).
- Commits end with the session's `Co-Authored-By` and `Claude-Session` lines and are committed by explicit path.

## Review Focus

1. **A pasted source with Windows line endings, a BOM or tabs.** The cast normalises them like `:code`. The first-keyword check ignores a leading BOM and blank lines. Pinned in Task 1.
2. **Two Diagram blocks of the same drawing on one page, or a block duplicated.** Their marker ids never collide, so each arrow keeps its own head. Pinned in Task 6.
3. **The editor types fast and draws arrive out of order.** Only the latest `id` is written into the hidden field. A slow draw for an older keystroke never overwrites a newer one. Pinned in Task 7.
4. **A language with a source but a drawing that fails on read** (a tightened sanitizer). The page shows nothing for that language, never the default's drawing beside its own source. The failure is logged once. Pinned in Task 6.
5. **A drawing posted by hand with an entity, a DOCTYPE, `<a href>`, `<use href>`, a `style` holding `url(http…)`, or an `on*` handler.** Each is refused on write (422, nothing audited) and draws nothing on read. Pinned in Tasks 3 and 9.

---

### Task 1: `Diagram::Source`, the line rules

**Files:**
- Create: `app/values/diagram.rb` (the module, one line saying what the namespace holds), `app/values/diagram/source.rb`
- Test: `test/values/diagram/source_test.rb`
- Modify: `CHANGELOG.md` (`## Unreleased` → `### Breaking`: the new top-level name `Diagram`, which refuses a gem's hook owner `diagram` at boot)

**Interfaces:**
- Produces:
  - `Diagram::Source::MAX_CHARACTERS` (10_000).
  - `Diagram::Source::TYPES`, a frozen hash of keyword → label (Global Constraints).
  - `Diagram::Source::MERMAID_TYPES` (the seven `diagramType` strings).
  - `Diagram::Source.type(text) -> String | nil`: the first keyword, or nil.
  - `Diagram::Source.refusals(text) -> Array<Refusal>`, where `Refusal = Data.define(:line, :rule, :word)`. `rule` is one of `:directive :front_matter :colours :links :maths :type :too_long`.
  - `Diagram::Source.first_line(text) -> String | nil`: the first line after the keyword, for the tile.
  - `Diagram::Source.rules_json -> String`: what the frame and the card read, so the rules are written once.

- [ ] **Step 1: Write the failing tests.** Each test name is its assertion:
  - "a source whose first keyword is on the list has no refusal": one per keyword, including `graph TD` and `stateDiagram-v2`.
  - "a first line not on the list is refused as :type, naming the word": `mindmap` → `[Refusal.new(line: 1, rule: :type, word: "mindmap")]`.
  - "a leading BOM and blank lines are skipped before the keyword": `"﻿\n\nflowchart LR"` has no refusal.
  - "%%{ is refused anywhere in a line, in any case": `"flowchart LR\n  A --> B %%{init: {}}%%"` → `:directive` at line 2, and the same for `%%{INIT`.
  - "--- as the first non-blank line is :front_matter".
  - "classDef, class with a style name after :::, :::, cssClass, style and linkStyle are :colours": by a trimmed line's first word; `:::` anywhere.
  - "class Foo in a class diagram is not refused": `"classDiagram\n  class Animal"` has no refusal.
  - "click, link, links, href and call are :links".
  - "$$ anywhere is :maths".
  - "over MAX_CHARACTERS is one :too_long refusal at line 0, and the text is not cut".
  - "rules_json parses to the types, the mermaid types, the limit and each rule's words and markers".
- [ ] **Step 2: Run them.** Run: `PGGSSENCMODE=disable bin/rails test test/values/diagram/source_test.rb`. Expected: FAIL, `uninitialized constant Diagram`.
- [ ] **Step 3: Implement `Diagram::Source`.**
  - A rule is data: a hash of rule → `{ first_words: [...], markers: [...] }`, read by both `refusals` and `rules_json`.
  - Matching is case-sensitive except for `%%{`.
  - Write the CHANGELOG `### Breaking` line.
- [ ] **Step 4: Run.** The tests pass, and so do `PGGSSENCMODE=disable bin/rails test test/lib/admin_namespace_shadow_test.rb` and `bin/rails zeitwerk:check`.
- [ ] **Step 5: Commit** `app/values/diagram.rb app/values/diagram/source.rb test/values/diagram/source_test.rb CHANGELOG.md`.

### Task 2: Vendored Mermaid, the renderer frame and the fixtures

**Files:**
- Create:
  - `vendor/javascript/mermaid.js` and `vendor/javascript/mermaid.VERSION`;
  - `app/controllers/admin/diagram_renderers_controller.rb` and `app/views/admin/diagram_renderers/show.html.erb`;
  - `public/diagram-renderer.js`;
  - `lib/tasks/diagram.rake` and `test/support/diagram_fixtures.rb`;
  - `test/fixtures/diagrams/{flowchart,sequence,class,state,er,gantt,pie}.svg`, `test/fixtures/diagrams/sources.yml` (the seven sample sources) and `test/fixtures/diagrams/MERMAID_VERSION`.
- Modify:
  - `config/routes.rb` (inside the admin scope: `get "diagram-renderer", to: "diagram_renderers#show", as: :diagram_renderer`);
  - `config/importmap.rb`;
  - the font serving for the four `archivo-latin-*.woff2` files (see Step 3).
- Test: `test/controllers/admin/diagram_renderers_controller_test.rb`, `test/lib/diagram_fixtures_test.rb`, `test/system/admin/diagram_renderer_test.rb`

**Interfaces:**
- Consumes: `Diagram::Source.rules_json`.
- Produces:
  - **The frame's protocol.** The parent posts `{ id, source, colours }` with target `'*'`. The frame answers `{ id, svg, bytes, elements }` or `{ id, error: { kind, line, message } }`.
    - `kind` is one of `refused | parse | type | too_large | too_long`.
    - `svg` is the frame's own **cleaned** string (the same drop lists as `Diagram::Drawing`, done with DOM APIs), so `bytes` and `elements` are measured on what the server will store.
  - `admin_diagram_renderer_path`.

- [ ] **Step 1: Vendor.**
  - Download `https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz` and check its integrity against the registry's `sha512-w7nr/SFrLO7BaVTs3dQTvYSV6nYSBj0Yy9DjBhsIJtAcHqRzXSq4Pg32ujHZ/AdWsAMNEvvhbm5dt9E2tOiHzw==`.
  - Copy `package/dist/mermaid.min.js` to `vendor/javascript/mermaid.js` and write `mermaid.VERSION`.
  - Add the pin line beside d3-force's. Run `bin/importmap audit` and `bin/importmap outdated` and record their output in the report.
  - Extract into a new empty folder in the scratchpad, never into the repository.
- [ ] **Step 2: Write the failing controller tests.**
  - "the renderer answers the same document to everyone who may open CS Studio, with the frame's CSP exactly": the header equals the Global Constraints string.
  - "the renderer holds no data: no CSRF meta, no user name, no cookie set".
  - "the renderer is not on a public host when ADMIN_HOST is set": `with_admin_address`, then 404 on the public host.
  - "the renderer's markup carries the rules as JSON and the Mermaid file's asset URL".
  - "an Archivo font file answers Access-Control-Allow-Origin: *".
  - "no public page and no CS Studio screen without a Diagram block references mermaid": the public home and the dashboard bodies.
- [ ] **Step 3: Implement.**
  - `DiagramRenderersController < Admin::BaseController`. It skips what writes into a page (the CSRF meta, the flash) and sets `request.content_security_policy` the way `SessionsController#allow_bot_check_origin` builds one. It sets the `sandbox` directive and renders with `layout: false`.
  - The view loads `asset_path("mermaid.js")`, then `/diagram-renderer.js`, both as classic scripts. An opaque-origin document can't load the app's module scripts without CORS (spec, "My calls" 3).
  - The rules JSON goes in `<script type="application/json" id="diagram-rules">`.
  - **Fonts:**
    - If the four font files are served through Propshaft from `app/assets/fonts/`, add `Access-Control-Allow-Origin: *` for exactly those paths: a small Rack middleware `DiagramFontCors` in `lib/`, required from `config/application.rb` and inserted before Propshaft. Put a comment on why: an opaque-origin `FontFace` fetch is CORS with `Origin: null`.
    - Name in the report what serves them in production (`public/assets` behind Thruster).
  - **The frame script, `public/diagram-renderer.js`:**
    - It loads the four faces with `FontFace` and `document.fonts.add` and awaits them before `mermaid.initialize`.
    - It runs the three checks in the spec's order: length, the rules, then `mermaid.parse` (refuse a non-empty `config` or a `diagramType` off the list).
    - It renders, cleans, measures, and refuses `too_large` over either limit.
    - It shows the drawing in its own body, painted by `diagram.css`'s rules on the `colours` posted in. Until Task 6 the frame reads an empty `<style>`.
    - It accepts a message only from `window.parent`.
- [ ] **Step 4: Write the fixture task.**
  - `bin/rails diagram:fixtures` (R5) reads `sources.yml`, a key per type, each a short source using the type's common parts: a flowchart with a subgraph, dotted and thick edges and a labelled edge; a sequence with a note, a loop and an activation; and so on, each also with an `accDescr`.
  - It drives the frame, takes each raw SVG before cleaning (a `raw` flag in the message, honoured only when `window.__diagramFixtures` is set by the task's own page), and writes the files and `MERMAID_VERSION`.
  - `test/lib/diagram_fixtures_test.rb`: "every allowed type has a fixture", and "MERMAID_VERSION names the vendored file's version and SHA-256".
- [ ] **Step 5: Re-measure on 12.2.0 (R1).** Run the task. Then, for each fixture, record in the report:
  - that it has no `foreignObject`;
  - every element and attribute name it holds;
  - the class tokens it holds, against the spike's table (spike §3).
  - If a `foreignObject` appears, or a name on the spec's refusal list is needed, apply R1's fallback and redo Steps 1 and 5. A **new harmless name** goes in the report as "allowlist addition", for Task 3.
- [ ] **Step 6: Write the browser test** `test/system/admin/diagram_renderer_test.rb`.
  - "the frame's origin is null and its contentDocument is out of reach".
  - "a flowchart posted to the frame comes back as an svg with no foreignObject".
  - "a classDef line is refused before Mermaid sees it": its answer is `kind: refused`, `line: 2`.
  - "a source over the limit is refused as too_long, never drawn".
  - "a %%{init}%% at the end of a line is refused".
  - Drive the frame through a minimal host page served only in the test, `test/support/diagram_host.html`, never a route.
- [ ] **Step 7: Run** the controller and fixture tests, then the browser file once (machine quiet). Everything passes.
- [ ] **Step 8: Commit** by path: the vendored file and VERSION, controller, view, route, importmap, frame script, middleware, rake task, fixtures and tests.

### Task 3: `Diagram::Drawing`, the sanitizer

**Files:**
- Create: `app/values/diagram/drawing.rb`
- Test: `test/values/diagram/drawing_test.rb`

**Interfaces:**
- Consumes: the fixtures of Task 2, and its "allowlist addition" names (each named in the code's list with a one-line comment saying which type writes it).
- Produces:
  - `Diagram::Drawing::MAX_BYTES`, `MAX_ELEMENTS` and `REVISION` (starting at 1).
  - `Diagram::Drawing.clean(svg_string) -> Result`, where `Result = Data.define(:svg, :reason)`: `svg` is the cleaned string with ids `d-<n>`, or nil with `reason` a Symbol (`:not_xml :doctype :entity :processing_instruction :roots :element :attribute :url :value :too_large :too_many_elements`).
  - `Diagram::Drawing.new(value_hash)`, where the value is `{ "svg" => String, "from" => hex }`:
    - `#current?(source) -> Boolean` (SHA-256 hex of the cast source equals `from`);
    - `#markup(prefix:, title:, title_id:) -> ActiveSupport::SafeBuffer | nil`. It writes the root's `role="img"`, `aria-labelledby`, an `aria-describedby` only with a `<desc>`, the `<title>` holding the escaped `title`, `width` and `height` from the `viewBox`, and the ids prefixed. Nil when the drawing fails on read.
    - `#width`, `#height` (Floats from the `viewBox`).
  - `Diagram::Drawing.digest(source) -> String`.

- [ ] **Step 1: Write the failing tests.**
  - "each fixture cleans to an svg with no style, fill, stroke, filter, symbol, style attribute or data-*, and keeps its geometry and classes".
  - "the output is written from the parse tree": an input with an attribute in single quotes and a comment comes out with neither the comment nor the input's bytes.
  - "a refusal for each": a DOCTYPE, `<!ENTITY`, `<?xml-stylesheet?>`, two roots, `<script>`, `<foreignObject>`, `<a href>`, `<image>`, `<use href>`, `<animate>`, `<set>`, `<style>` inside `defs`, an `onload=`, `xml:base`, `marker-end="url(http://x)"`, a value holding `javascript:`, `data:` or `//`. Each answers its own `reason` and `svg` nil.
  - "a class token failing the pattern is dropped and the element kept": `class="task width-27.4375"` → `class="task"`.
  - "over MAX_BYTES after cleaning is :too_large; over MAX_ELEMENTS is :too_many_elements".
  - "ids are renamed d-1, d-2… and every url(#…) and aria reference follows".
  - "markup prefixes the ids, writes role, the title as escaped text and width and height from the viewBox": a title `<b>&` comes out `&lt;b&gt;&amp;`.
  - "markup keeps Mermaid's desc as the description and drops Mermaid's title".
  - "current? is true only for the source the drawing was made from".
  - "only Diagram::Drawing parses SVG": a source test over `app/` and `lib/` finds `Nokogiri::XML` beside `svg` in no other file.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Nokogiri strict: `Nokogiri::XML(svg) { |c| c.strict.nonet.nonoent(false).noent(false) }`, with the DTD and the entity checks done on the parsed document. Then:
  - walk the tree and build a new document element by element;
  - serialise with `to_xml(save_with: NO_DECLARATION | AS_XML)`;
  - add the root's `xmlns`.
  - Put a comment over `REVISION`: "Bump when a list changes: a cached read keeps the rules it was cleaned under."
- [ ] **Step 4: Run.** The tests pass.
- [ ] **Step 5: Commit** `app/values/diagram/drawing.rb test/values/diagram/drawing_test.rb`.

### Task 4: The two field types, the option `translation_required`, and their inputs

**Files:**
- Modify:
  - `app/models/content_model/field_types.rb` (register `:mermaid` and `:diagram_drawing` after `:code`);
  - `app/models/content_model/definition.rb` (`OPTIONS` gains `:translation_required`, refused unless `translated: true`);
  - `app/models/translations/status.rb` (a `translation_required` blank in a target language counts as missing when the primary language's value is present);
  - `config/locales/en.yml` (`errors.messages`: one key per `Diagram::Source` rule, plus `invalid_drawing` "This drawing can't be shown on the site.").
- Create: `app/components/admin/fields/mermaid_field.rb` and `.html.erb`, `app/components/admin/fields/diagram_drawing_field.rb` and `.html.erb`
- Modify: `config/locales/admin/fields.en.yml` (the preview's words, Task 7)
- Test:
  - `test/models/content_model/mermaid_field_test.rb`;
  - `test/models/content_model/diagram_drawing_field_test.rb`;
  - `test/components/admin/fields/mermaid_field_test.rb`;
  - `test/components/admin/fields/diagram_drawing_field_test.rb`;
  - a case each in `test/components/admin/editor_screen/shared_fields_component_test.rb` and `test/components/admin/ui/field_component_test.rb`;
  - `test/models/translations/status_test.rb` (the option).

**Interfaces:**
- Consumes: `Diagram::Source.refusals`, `Diagram::Drawing.clean`.
- Produces:
  - `:mermaid`: cast like `:code`; may be `translated: true`; `translatable: false`; `audit: :digest`; `max:`; `validate` adds one error per refusal, with the line and the rule's sentence.
  - `:diagram_drawing`: cast takes a Hash or a JSON String `{ svg, from }` and runs `Drawing.clean`. A failure is the error `:invalid_drawing` (never a nil). It is `translatable: false` and `audit: :digest`, `own_label?` true, and `display` nil.
  - `MermaidField(..., original:)`:
    - draws the Code field's textarea (the same attributes, CSS-only height, Tab leaves it) and the counter from nine tenths;
    - draws `data-controller="admin--diagram--preview"` on its wrapper, with values `renderer-url`, `rules` (the JSON), `messages`, `drawing-field` (the hidden input's id) and `starting` (true when R3 applies);
    - has the targets `source`, `frame-slot`, `status` (the polite live region) and `counter`;
    - with R3, draws the original's source and no `name`.

- [ ] **Step 1: Write the failing tests.**
  - "mermaid keeps text as typed with \n line endings and outer blank lines dropped".
  - "mermaid refuses each rule with its own sentence, naming the line": `"flowchart LR\n  classDef a fill:red"` → "Line 2: colours come from the site's theme, so classDef isn't used here."
  - "mermaid may be translated and is never offered to the AI".
  - "diagram_drawing cleans on cast and a drawing that fails is :invalid_drawing".
  - "translation_required without translated is refused at registration".
  - "a translation_required field blank in a language is missing only when the primary language has a value".
  - "MermaidField on a translation tab with no source of its own shows the original's source with no name attribute".
  - "MermaidField in a held form is readonly and still carries its controller".
  - "DiagramDrawingField is a hidden input with no label whose value is the stored JSON".
  - "SharedFieldsComponent shows nothing for the drawing on a translation tab".
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** in the files above. Each refusal sentence is a key. Write the six wordings, one per rule, plus the type sentence "`mindmap` diagrams aren't supported yet." with the list. The spec's `classDef` sentence is fixed text.
- [ ] **Step 4: Run** the tests above and `test/lib/field_type_branches_test.rb`, `test/lib/source_layout_test.rb` and `test/lib/admin_i18n_test.rb`. All pass.
- [ ] **Step 5: Commit** by path.

### Task 5: `BlockTypes::Diagram`, generated and declared

**Files:**
- Run: `bin/rails generate block_type diagram`. It writes the definition, the component pair, `diagram.css`, the preview, the two tests and the three marker lines.
- Modify:
  - `app/models/block_types/diagram.rb`;
  - `app/models/content_model/block_type_definition.rb` (`ICONS` gains `diagram`);
  - `app/components/admin/ui/block_icon_component.rb` (its drawing: a flowchart of three boxes and two arrows, in the Lucide line style of its neighbours);
  - `test/models/built_in_types_test.rb`.
- Test: `test/models/block_types/diagram_test.rb`

**Interfaces:**
- Consumes: Tasks 1, 3 and 4.
- Produces the definition:
  ```ruby
  t.label "Diagram"
  t.icon "diagram", family: :code
  t.field :source, :mermaid, translated: true, max: Diagram::Source::MAX_CHARACTERS
  t.field :drawing, :diagram_drawing, translated: true
  t.field :description, :text, translated: true, translation_required: true, label: "Description",
          help: "Describe what the diagram shows, for people who can't see it. The diagram shows on the site only with a description."
  t.uses :caption
  t.component Blocks::DiagramComponent
  t.theme_methods :block, :page, :svg, :description, :caption
  t.stylesheet "diagram.css"
  ```
  plus `tokens`, `summary` and `preview` (Tasks 6 and 8), and the sample:
  - `settings: {}`;
  - `translations` for `en`, `de` and `es`, each with a flowchart `source` (labels in the language), a `drawing`, a `description` and a `caption`;
  - `shows`: the en description and caption.
  - **The sample drawings** live in `db/seeds/diagrams/sample-{en,de,es}.svg`, not `test/`, because the sample is registered in every environment and the showcase seed draws it. `diagram:fixtures` writes them from three sources in `sources.yml`, already cleaned by `Diagram::Drawing.clean`. `BlockTypes::Diagram.sample_drawing(locale)` reads one and answers `{ "svg" => …, "from" => Diagram::Drawing.digest(source) }`.

- [ ] **Step 1: Generate**, then write the failing declaration tests:
  - "diagram is three translated settings and a caption, nothing required, the source never offered to the AI";
  - "its description is translation_required".
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Fill the definition.** Add the icon, and register the type after `Code` in `config/initializers/types.rb` (the generator's line).
- [ ] **Step 4: Run** `test/models/block_types/diagram_test.rb`, `test/models/built_in_types_test.rb`, `test/models/content_model/block_type_definition_test.rb`, `test/components/admin/ui/block_icon_component_test.rb` and `test/lib/generators/block_type_generator_test.rb`. All pass.
- [ ] **Step 5: Commit** by path.

### Task 6: The public component, the stylesheet, the tokens and the contract

**Files:**
- Modify:
  - `app/components/blocks/diagram_component.rb` and `.html.erb`;
  - `app/assets/tailwind/themes/default/diagram.css`;
  - `app/assets/tailwind/themes/default/tokens.css` and `sections.css`;
  - `test/support/contract_ledger.rb`;
  - `docs/reference/theming.md` (the component's row, the token rows, and a section "The Diagram block");
  - `public/diagram-renderer.js` (it reads the same rules: see Step 3).
- Create:
  - `test/fixtures/themes/diagram/components/blocks/diagram_component.html.erb` and its `assets/stylesheets/theme.css`;
  - `with_diagram_theme` beside `with_code_theme`.
- Test:
  - `test/components/blocks/diagram_component_test.rb`;
  - cases in `test/integration/design_tokens_test.rb`, `test/integration/public_blocks_test.rb`, `test/integration/theme_pages_test.rb` and `test/lib/theming_reference_test.rb`.

**Interfaces:**
- Consumes: `Diagram::Drawing#markup`, `#width`.
- Produces:
  - `Blocks::DiagramComponent#svg`: the markup with `prefix: "diagram-#{block.id}-#{locale}"`, `title: description`, or nil.
  - `#description`, `#caption`.
  - `render?` is `svg.present? && description.present?`.
  - **Fallback:** a language with no source uses the default language's source, drawing and that language's description (or the default's). A language with its own source uses only its own drawing.
  - The read is cached in `Rails.cache` under `["diagram", sha256(stored svg), block.id, locale, Diagram::Drawing::REVISION]`.
  - A failure on read logs once per block and reason (`Rails.logger.warn` with the block id and the reason, never the content), using the cache key as the "logged" mark.
  - The tokens: `diagram-ink diagram-fill diagram-line diagram-edge diagram-group diagram-note diagram-accent diagram-series-1 … diagram-series-6` themed, and `diagram-font` fixed. Their defaults are the spec's §4 table.

- [ ] **Step 1: Write the failing tests.**
  - "the figure holds an svg with role img, labelled by the description's title, sized from its viewBox".
  - "nothing is drawn with no drawing, with no description, or with a drawing that fails on read, and the failure is logged once with no content".
  - "a language without its own source shows the default's drawing; one with its own source never shows the default's".
  - "two diagram blocks of the same drawing on one page share no id" (Review Focus 2).
  - "text in the description that looks like markup is text".
  - "the component and its template mark nothing html_safe but Drawing's markup".
  - **Tokens:**
    - "every diagram token is defined in both schemes and re-valued on the strong band";
    - "ink on fill, group and note is 4.5:1; edge and line on every ground are 3:1; ink on each series colour is 4.5:1, in both schemes, on the page, a tinted and a strong band";
    - "diagram.css paints by class, holds no colour literal and scopes text-anchor middle to svg.flowchart".
  - "a theme replaces the Diagram block's template from the reference's section alone".
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Write `diagram.css` from spike §3's class table and the layout list of spec §4: the font sizes, the dash patterns, the pie's `:nth-of-type(6n+k)`, and the gantt's `done/active/crit` 0…3.
  - Add any class Task 2's report found new on 12.2.0.
  - **60%-then-scroll (call 13):**
    - the figure gets `overflow-x: auto`;
    - the component writes `style="--diagram-min-width: <0.6 × width>px"` on the `<figure>` (its own value, computed from the `viewBox`);
    - the svg gets `max-width: 100%; height: auto; min-width: min(var(--diagram-min-width), <natural width>)`.
    - The page never scrolls sideways.
  - **The frame paints with the same rules:** `diagram.css` is plain CSS (no utilities, no `@apply`), so the renderer view inlines the file itself, read once per process from `BlockTypes.fetch(:diagram).stylesheet_path`, inside its `<style>`. There is one source of rules, and a test holds that the frame's style holds the file's text.
  - **The frame's colours:** with the source the card posts CS Studio's values for each `--th-diagram-*` token, read with `getComputedStyle` from a hidden element under `.content-block--diagram` in CS Studio's page. The frame sets them as custom properties on its root.
  - Write the ledger line `"blocks/diagram_component" => %w[block page svg description caption]` and the token rows, then the theming reference section. It says:
    - a replacing stylesheet keeps the layout rules;
    - `--th-diagram-font` sized the boxes;
    - Mermaid's class names follow its upgrades;
    - `svg` is printed as given.
- [ ] **Step 4: Run** the tests above and `test/integration/public_canary_test.rb`, `test/integration/block_samples_test.rb` and `test/values/theme/contract_test.rb`. All pass.
- [ ] **Step 5: Commit** by path.

### Task 7: The card's script, `admin--diagram--preview`

**Files:**
- Create: `app/javascript/controllers/admin/diagram/preview_controller.js`, `app/javascript/diagram/frame.js` (the frame's lifecycle and protocol, a plain module), `app/javascript/diagram/digest.js` (SHA-256 hex by `crypto.subtle`)
- Modify: `config/locales/admin/fields.en.yml`, `app/components/admin/fields/mermaid_field.*`
- Test: `test/system/admin/diagram_block_test.rb`

**Interfaces:**
- Consumes: the protocol of Task 2, `MermaidField`'s values and targets (Task 4).
- Produces the behaviour the browser tests pin:
  - **Connect:** it builds `<iframe sandbox="allow-scripts">` into `frame-slot` and draws the current source. It writes nothing.
  - **Input:** after a debounce of 300 ms it posts `{ id: ++n, source, colours }`. It accepts a message only when `event.source === frame.contentWindow && event.origin === "null"` and `id === n` (Review Focus 3).
  - **When a draw succeeds**, it:
    - computes the digest;
    - writes `JSON.stringify({ svg, from })` into the hidden field as its `value`;
    - dispatches `input` on the hidden field, so the form's autosave carries source and drawing together through `saving/queue.js`.
  - **When a draw fails**, the hidden field is left as it was.
  - **The states** are spec §7's table: empty, drawing ("Drawing…" after 300 ms with no answer), drawn, refused line, parse error (with "The site keeps the last drawing that worked." or "Nothing is drawn yet."), type not supported, too large, too long.
    - `status` is a polite live region, written once per new error text and never per keystroke.
  - **R3:** with `starting` true, the first `input` sets the textarea's `name` (and the hidden field's), then proceeds as above.
  - **Take-back:** `disconnect` and `turbo:before-cache` remove the frame and the listener.
  - **Held form:** no action of this controller is in a held form. It draws at connect from the readonly textarea. The type declares no `read_only_actions`.

- [ ] **Step 1: Write the failing browser tests:**
  - "typing a flowchart draws it in the frame and autosave stores source and drawing together";
  - "the stored drawing survives a reload and opening the card saves nothing";
  - "a parse error keeps the last drawing and says so";
  - "a classDef line is refused with its line's sentence";
  - "a card held by someone else draws and writes nothing";
  - "the translation tab starts from the default's source and stores nothing until the first change";
  - "a draw answered late for an older keystroke is ignored";
  - "the frame is gone after leaving the editor and none is built on a screen with no Diagram block".
  - Use the helpers `visit_editor`, and `test/system/README.md`'s rules.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement**, against the Design System card `EditorDiagramBlock` and `EditorDiagramError` (the paths the controller hands over). Use the preview's words as keys under `admin.components.fields.mermaid_field`, read through `data-messages`.
- [ ] **Step 4: Run** the file once on a quiet machine, plus `test/lib/source_layout_test.rb` and `test/components/admin/editor_screen/held_fields_test.rb`. All pass.
- [ ] **Step 5: Commit** by path.

### Task 8: Importing a file into the source

**Files:**
- Modify: `app/components/admin/fields/mermaid_field.*`, `app/javascript/controllers/admin/diagram/preview_controller.js`, `config/locales/admin/fields.en.yml`
- Test: `test/system/admin/diagram_block_test.rb` (cases), `test/components/admin/fields/mermaid_field_test.rb` (the control's markup)

**Interfaces:**
- Produces:
  - "Import file…": a secondary button and a hidden `<input type="file" accept=".mmd,.md,text/markdown,text/plain">`, the action `admin--diagram--preview#import`.
  - It reads the file in the browser with `File.text()`. Its length is held to `MAX_CHARACTERS`: over it, "This file is longer than a diagram may be." and nothing changes.
  - A `.md` file is read for its first ```` ```mermaid ```` fence (the opening line matches `/^(`{3,}|~{3,})\s*mermaid\b/i`, closed by the same fence). A file with no Mermaid says "This file holds no Mermaid diagram."
  - A non-empty field asks first, with the shared `Admin::Ui::ConfirmDialogComponent` ("Replace the diagram with the file's?"). On replacing, the value is set and `input` is dispatched, so it draws and saves as if typed.
  - The file is never sent or stored. It is absent from a held form (the action is not read-only).

- [ ] **Step 1: Write the failing tests:**
  - "importing a .mmd file fills the source and draws it";
  - "a .md file's first mermaid fence is taken";
  - "a file with no Mermaid says so and changes nothing";
  - "replacing a typed source asks first, and Cancel keeps it";
  - "a held card draws no Import control".
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** against `EditorDiagramBlock`'s import drawing.
- [ ] **Step 4: Run** once on a quiet machine. All pass.
- [ ] **Step 5: Commit** by path.

### Task 9: The tile, translation state and the editor's integration cases

**Files:**
- Modify: `app/models/block_types/diagram.rb` (`summary`, `preview`, and the tile's drawing), `config/locales/admin/editor_screen.en.yml` (`tile_summary.types.diagram`: `empty`, `no_description`, `kept`)
- Test:
  - `test/components/admin/editor_screen/tile_summary_component_test.rb`;
  - `test/integration/admin/content_blocks_test.rb`;
  - `test/services/translation_state_parity_test.rb`;
  - `test/services/ai/translate_test.rb`.

**Interfaces:**
- Produces:
  - `BlockTypes::Diagram.summary(block, locale:)`: `[[:text, label], [:text, " · "], [:mono, first_line]]`, or `[[:hint, :empty]]` with no source. Then `[:hint, :no_description]` and `[:hint, :kept]` (when `Drawing#current?` is false), in the meta colour.
  - `BlockTypes::Diagram.preview(block, locale:)`: `Preview.new(heading: description's opening words, text: the source's first three lines, mono: true)`.
  - **The tile's small drawing (call 14)** is not a summary part, since summary parts are text. It renders through the tile's existing preview slot only if `TileSummaryComponent` already has a place for a picture.
    - If it has none, the plan's ruling is: add one declaration, `t.tile_picture ->(block, locale:) { … }`, answering safe markup or nil. It is read only by `TileSummaryComponent` and documented in "Adding a block type".
    - The diagram answers `Drawing#markup(prefix: "diagram-tile-…", title: description)`, scaled by CSS to the tile's preview height, `aria-hidden="true"` (the tile's text names it).
    - Name the choice in the report.

- [ ] **Step 1: Write the failing tests:**
  - "the tile reads Flowchart · A --> B, Empty with no source, and the two hints";
  - "the tile's picture is the stored drawing with tile ids and no script";
  - **content blocks:**
    - "add a diagram from the picker, save source and drawing, a refused drawing writes and audits nothing (422, its sentence in the field's slot), duplicate, delete, a stale 409, another tab's hold";
    - "a hand-posted drawing with an entity, a DOCTYPE, an a href, a use href, a style url or an onload is refused" (Review Focus 5);
  - **parity:** "a change of the description makes a translation outdated; a change of the source makes it outdated; a re-draw of the same source changes no state; a blank description where the original has one is missing";
  - **AI:** "AI translation sends the description and the caption and never the source".
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the tests above and `test/integration/trash_visibility_test.rb`. All pass.
- [ ] **Step 5: Commit** by path.

### Task 10: The public browser file, the documents and the whole check

**Files:**
- Create: `test/system/diagram_block_test.rb`
- Modify:
  - `docs/reference/content-blocks-and-types.md` (the type in the list at its top, a section "The Diagram block", `translation_required` under "Field types", and `tile_picture` if Task 9 added it);
  - `CLAUDE.md` (the reference index entry for the Diagram block's files; under "Rules a change can break silently": `Drawing::REVISION` and the "no guard" items of spec §3 and §4);
  - `CHANGELOG.md` (`### Added` the block, the field types, the option and the route; `### For a gem or an outside caller` the ledger line and tokens);
  - `docs/roadmap.md` ("Shipped", and the gaps: mindmap/kanban/block-beta, non-Latin scripts #246, AI for labels, the guide loader's fence rule R2);
  - the spec's "As built".
- Test: `test/system/diagram_block_test.rb`

- [ ] **Step 1: Write the browser tests:**
  - "a public page draws the diagram inline with no script and its labels as text";
  - "the drawing re-colours with data-theme dark and on a strong band";
  - "a wide diagram scales to its column, then scrolls in its own box at a phone's width, and the page does not scroll sideways".
- [ ] **Step 2: Run** the file once on a quiet machine. All pass.
- [ ] **Step 3: Write the documents** listed above.
- [ ] **Step 4: The whole check.**
  - `PGGSSENCMODE=disable bin/rails test`, `bin/rubocop`, `bin/brakeman` (any new ignore with its note), `bin/bundler-audit`, `bin/importmap audit`, `bin/rails zeitwerk:check` and `bin/changelog-guard origin/main`.
  - Then, alone: `bin/theme-build-check`.
  - Then every Diagram browser file, one at a time.
  - All pass.
- [ ] **Step 5: Commit** by path.
