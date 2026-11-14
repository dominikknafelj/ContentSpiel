# The Diagram block: spike findings

Date: 2026-11-11. Spec: `2026-11-11-diagram-block-design.md` (§9 and every point it marks unverified).
The spike code is throwaway and is not in the repository. It drove headless Chrome through Ferrum 0.20.1 against a small local server. That server served the frame with the spec's CSP header, and a parent page created the frame with `sandbox="allow-scripts"`.

## Mermaid build

- **Version:** `mermaid@11.17.2`, published 2026-08-25. It is the latest 11.x and is at least two weeks old. It is later than 11.15.0, which carries the CVE-2026-41149 fix.
- **File:** `dist/mermaid.min.js`, a single-file IIFE that sets the global `mermaid`.
- **Size:** 3,572,661 bytes; gzip −6 979,561 bytes, gzip −9 976,021 bytes.
- **SHA-256:** `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`. The jsDelivr and unpkg copies are identical. Licence MIT.
- **Note:** 12.x is the current major (12.0.0 on 2026-09-10, 12.3.0 on 2026-11-03). Before pinning 11.x, the plan should check whether 11.x still gets security fixes.

## Answers

### 1. Opaque-origin frame, loading, postMessage, CSP

**Answer: it works.**
- The frame's origin is `"null"`, and the parent's `frame.contentDocument` is `null`.
- `<script src="/mermaid.min.js">` and `<script src="/frame.js">` load under `script-src 'self'`. In the sandboxed document, `'self'` matched the server's origin.
- The card posts `{id, source}` and gets `{id, svg}` or `{id, error}` back. The parent matches on `event.source === frame.contentWindow` and on the id.
- **Posting rules:**
  - The parent must post to the frame with target origin `'*'`, because an opaque origin can't be named.
  - The frame can post to the parent with `'*'`, or with CS Studio's origin written into the frame's markup.
  - The card should also check `event.origin === "null"`.
- **CSP:** the spec's policy works as written: `sandbox allow-scripts; default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'none'; form-action 'none'`.
  - `'unsafe-inline'` for styles is needed anyway, because the frame paints with its own `<style>`. The spike did not test Mermaid without it.
  - During the construct run, the CSP blocked one inline event-handler execution in the frame: "Executing inline event handler violates … script-src 'self'". The only source with an `on*` handler was the HTML-label case. This is evidence that the frame's CSP is load-bearing.
- **Fonts need CORS:** a font fetched by an opaque-origin document is a CORS request with `Origin: null`.
  - Without `Access-Control-Allow-Origin` on the font file, `FontFace.load()` fails with "blocked by CORS policy".
  - With `Access-Control-Allow-Origin: *`, it loads.
- **Clean-up:** after a strict render, the frame's body held only the drawing and the two scripts. Mermaid removes its temporary nodes.

**Plan:**
- Serve the Archivo `.woff2` files that the frame uses with `Access-Control-Allow-Origin: *`. They are public files.
- Load them in the frame with `FontFace` and `document.fonts.add` before the first render.

### 2. `securityLevel: "sandbox"` vs `"strict"`

**Answer: use `"strict"`.**
- **At top level (no frame):** sandbox mode returns `<iframe src="data:text/html;charset=UTF-8;base64,…" sandbox="allow-top-navigation-by-user-activation allow-popups">`. The SVG can be read out by decoding the base64. It is the same SVG, with its `<title>` and `<desc>`.
- **Where it lays out:** in its own iframe. It appends `<iframe sandbox="">` to the body and lays out in that iframe's `contentDocument.body` (`getDiagramRoot`).
- **Inside our opaque-origin frame:** every type fails with `Cannot read properties of null (reading 'body')`, because the nested iframe's `contentDocument` is null there.

Sandbox mode is unusable in the frame. It also adds nothing that the frame doesn't already give, since its isolation is only display isolation.

### 3. The seven types with `htmlLabels: false`

**Answer: all seven pass.**
- **No `foreignObject`** in flowchart, sequence, class, state, ER, gantt or pie.
- **`accTitle` and `accDescr`** come out as `<title id="chart-title-…">` and `<desc id="chart-desc-…">` in strict mode, referenced by the root's `aria-labelledby` and `aria-describedby`. They survive the sanitizer's element list.
- **Each type is legible after cleaning and painting** (see 4).
- **`mindmap`, `kanban` and `block-beta`** also draw with no `foreignObject` under `htmlLabels: false`. The spec's reason for leaving them off ("rely on HTML labels") is wrong. They could join later with their own rules.

**What Mermaid 11.17.2 writes that the spec's lists don't foresee:**
- `<filter>`/`<feDropShadow>` and `<linearGradient>`/`<stop>` in every flowchart, class, state and ER diagram (in `defs`, referenced only from the dropped styles);
- `<symbol>` in every sequence diagram (three unused actor icons, 13 KB);
- `font-style="normal"` on every label `tspan`;
- `name=` on sequence lifelines;
- `fill-rule` and `clip-rule` (ER);
- `transform-origin` (gantt);
- `width="100%"` and `style="max-width:…"` on the root;
- class tokens that fail `/\A[A-Za-z][\w-]*\z/`: gantt's `width-27.4375` and sequence's `200` on lifelines.

The spec makes each of these a refusal, which would refuse *every* diagram of five types (see "Changes the spec needs").

**Allowlist: what the seven types and a 60-node flowchart actually use after cleaning**

- **Elements:** `svg g defs marker path rect circle line polygon text tspan title desc`.
  - Never produced, so the spec's list can drop them: `use`, `clipPath`, `ellipse`, `polyline`.
  - With `use` gone, the `href` rule goes too.
- **Attributes** (by name, on any allowed element; observed hosts in brackets):
  - geometry: `x y` (rect text tspan), `x1 y1 x2 y2` (line), `cx cy r` (circle), `rx ry` (rect), `width height` (rect circle), `d` (path), `points` (polygon), `transform` (g path polygon text), `viewBox` (svg marker *and path*);
  - text: `dy` (text tspan), `text-anchor` (g text tspan), `dominant-baseline` (text), `alignment-baseline` (text tspan), `font-size` (g text), `font-weight` (tspan), `font-style` (tspan, new);
  - markers: `marker-start marker-end` (path line), only as `url(#id)`; `markerWidth markerHeight markerUnits refX refY orient` (marker);
  - other: `id`, `class`, and `xmlns` on the root.
- **Values seen:**
  - `orient`: `auto`, `auto-start-reverse`;
  - `markerUnits`: `userSpaceOnUse`;
  - `text-anchor`: `middle`;
  - `dominant-baseline` and `alignment-baseline`: `central`, `middle`;
  - `font-size`: `10`, `11`;
  - `font-weight`: empty or `normal`;
  - `font-style`: `normal`.

  Value lists are cheap to enforce.
- **`url(` values:** only `marker-start` and `marker-end` as `url(#…)`.
- **Drop quietly** (the spec's list plus these):
  - elements: `style filter feDropShadow linearGradient stop symbol`;
  - attributes: `name fill-rule clip-rule transform-origin`, every `data-*`, and the root's `width`, `style`, `role` and `aria-*`;
  - any class token that fails the class pattern.
- **Refused as the spec says, and seen:**
  - `<a href="https://…">` from `click … href` (flowchart) and from `link`/`links` (sequence);
  - `foreignObject` from front matter `htmlLabels: true` (3 in one small flowchart).

**Class names `diagram.css` must paint**

| Type | Classes |
|---|---|
| flowchart | `node`, `label-container`, `basic`, `outer-path`, `label`, `cluster`, `clusters`, `cluster-label`, `edgePaths`, `flowchart-link`, `edge-pattern-solid`, `edge-pattern-dotted` (`-dashed`), `edge-thickness-normal`, `edgeLabel`, `edgeLabels`, `background`, `marker`, `arrowMarkerPath`, `cross`, `text-outer-tspan`, `text-inner-tspan`, `row`; root `flowchart` |
| sequence | `actor`, `actor-top`, `actor-bottom`, `actor-box`, `actor-line`, `messageLine0` (solid), `messageLine1` (dotted), `messageText`, `activation0`, `note`, `noteText`, `labelBox`, `labelText`, `loopLine`, `loopText`, `sectionTitle` |
| class | `node`, `label-container`, `divider`, `annotation-group`, `label-group`, `members-group`, `methods-group`, `relation`, `edgeTerminals`, `dashed-line`, markers `aggregation` `composition` `extension` `dependency` `lollipop`; root `classDiagram` |
| state | `statediagram-state`, `statediagram-cluster`, `statediagram-note`, `note-cluster`, `note-edge`, `noteLabel`, `state-start`, `transition`, `cluster-label`, `divider`, `inner`, `outer`; root `statediagram` |
| ER | `relationshipLine`, `row-rect-odd`, `row-rect-even`, `attribute-name`, `attribute-type`, `attribute-keys`, `attribute-comment`, `name`, `divider`, markers `onlyOne` `zeroOrOne` `oneOrMore` `zeroOrMore`; root `erDiagram` |
| gantt | `section section0…3`, `task`, `task0…3`, `done0…3`, `active0…3`, `crit0…3`, `milestone`, `taskText*`, `taskTextOutsideLeft`/`Right`, `sectionTitle*`, `grid`, `tick`, `domain`, `today`, `titleText` |
| pie | `pieCircle` (slices, siblings in order: painted by `:nth-of-type`), `pieOuterCircle`, `slice` (percent text), `legend` (one `g` per slice), `pieTitleText` |

The full per-type lists are in the spike's `analysis.json`.

### 4. Dropping Mermaid's styles and painting by class

**Answer: yes, the drawing stays legible.**
- The spike dropped every `<style>`, `style`, `fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `opacity`, `color` and `font-family`. It then painted with a 90-line stylesheet from the default theme's tokens in light and dark, and all seven types stay legible.
- Screenshots (spike folder, not committed): `out/painted-light.png`, `out/painted-dark.png`, and `out/frame-paint-flowchart.png`, which shows the same painting inside the sandboxed frame under its CSP.

**What the dropped `<style>` held that is layout, not colour:**
- **`text-anchor: middle` for flowchart labels.** Without it, every node label starts at the centre and runs out of its box: 4 of 5 labels overflowed in the first paint. The rule must be scoped to `svg.flowchart`, because class, state and ER labels are start-anchored and broke when the rule was global.
- **Font sizes by class:** the root's 16 px, titles 18 px, pie labels and legend 17 px, pie title 25 px, ER edge labels 14 px, class terminals 11 px, gantt task text 11 px.
- **Dash patterns:** dotted and dashed edges, `messageLine1`, `loopLine`, `note-edge`, and state dividers.

**Pie and gantt:**
- A pie's slice colours can only come from `.pieCircle:nth-of-type(6n+k)`, and its legend from `.legend:nth-of-type(6n+k+1)`.
- Gantt task states come from `done/active/crit` with a section suffix `0…3`.

**The root has no size once cleaned.** It has no width, and an inline SVG then fills its column, so small diagrams are blown up: class and ER were drawn several times larger than the flowchart in the screenshot. The component's `width`/`height` from the `viewBox` (spec §6) is required, not cosmetic.

**Gantt width** comes from the frame's width (`parentElement.offsetWidth`, here 1162 px). Its 11 px text is unreadable when scaled to a column. The frame must set `gantt.useWidth` to a fixed figure near the content column's width, so a stored gantt doesn't depend on how wide the editor's frame was.

### 5. Text measurement and the font

**Answer: yes, with Archivo loaded in the frame the boxes fit.**
- **The check:** for every label in a node, the label's box against its shape's box when painted in Archivo.
  - **Drawn with Archivo:** 0 overflows; the smallest margin was 6.2 px (flowchart), and 12–35 px elsewhere.
  - **Drawn without it** (frame fallback font): margins shrink to 1.9 px, and one state label overflows by 2.8 px.
- **What is needed:**
  - the two Archivo files with CORS (see 1);
  - `themeVariables.fontFamily` and `fontFamily` set to `Archivo`;
  - `await` the font load before `initialize`/`render`.
- **A gap:** the CMS ships `archivo-latin-*` only. A label in Cyrillic, Greek, Vietnamese or CJK (all among the 38 locales) is measured in the editor's system fallback and painted in the visitor's, so its box can be wrong.

### 6. Refused constructs

What each does when Mermaid is given it (all drawn in strict mode, inside the frame):

| Construct | In the output |
|---|---|
| `%%{init: … themeCSS …}%%` | `themeCSS` lands in the `<style>`; `htmlLabels: true` is honoured |
| `%%{…}%%` at the **end of a line** | honoured (`theme: dark`), so the marker must be matched anywhere in a line |
| front matter `---` with `config: htmlLabels: true` | **3 `foreignObject`** in a two-node flowchart |
| `classDef`, `:::`, `style`, `linkStyle`, state `classDef`/`class`, class `cssClass` | colours in the `<style>` and in `style` attributes (all dropped by the sanitizer anyway) |
| `click … href` / `link` / `links` | an `<a href="https://…">` around the node or actor |
| `click … call alert(1)` | nothing in strict (no callback, no `<a>`) |
| `$$x^2$$` | drawn as the literal text `$$x^2$$` (no MathML with `htmlLabels: false`) |
| HTML in a label (`<b>…<img onerror>`) | the tags as literal text; the handler stripped |
| a Markdown string in backticks | `tspan`s with `font-weight="bold"`: harmless, allowed |

**`mermaid.parse(text)`:**
- It returns `{ diagramType, config }`.
- `config` is non-empty for every directive and for front matter, including the mid-line directive. It does not reveal `classDef`, `style`, `click` or `link`, so the line rules stay.
- The `diagramType` values: `flowchart-v2`, `sequence`, `classDiagram`, `stateDiagram`, `er`, `gantt`, `pie`; and `mindmap`, `kanban`, `block`.

**Plan for the frame:**
1. Run the line rules first, so a refused source never reaches the parser.
2. Then `mermaid.parse`, and refuse when `config` is non-empty or `diagramType` is not on the list.
3. Then render.

The server keeps only the line rules (no Mermaid).

**Line rules:**
- Front matter: refuse `---` as the first non-blank line.
- Directives: refuse `%%{` anywhere, case-insensitively.

**Maximum text size:** read in the source, not run. When a source is longer than `maxTextSize`, Mermaid does not throw. It draws a stand-in diagram, "Maximum text size in diagram exceeded", with `style a fill:#faa`. The frame must refuse over-long text itself, before calling Mermaid.

### 7. Sizes

| Diagram | Source | Raw SVG | Cleaned | Cleaned, coordinates rounded to 2 places | Elements | gzip (cleaned) |
|---|---|---|---|---|---|---|
| 60 nodes, 69 edges (10 labelled) | 2,216 ch | 110 KB | 78 KB | 76 KB | 1,123 | n/m |
| 60 nodes, 118 labelled edges, 5 subgraphs | 3,832 ch | 343 KB | 221 KB | 208 KB | 1,621 | 37 KB |
| 150 nodes, 298 edges, 10,000 ch | 9,988 ch | 1,227 KB | 769 KB | 716 KB | 4,024 | 131 KB |
| the seven samples | 0.3–0.6 KB | 5–38 KB | 2–28 KB | 2–18 KB | 32–235 | — |

- Path data is half the bytes, at about 190 bytes per element.
- **The 5,000-element limit holds:** a full 10,000-character source stays under it.
- **The 300 KB limit does not match the 10,000-character limit:** a source the field accepts can draw 770 KB.
- **Read side** (Nokogiri on the 1.2 MB raw drawing): strict parse 3.4 ms, clean 22 ms, parse and walk of the cleaned 770 KB 22 ms. That is cheap, and cached anyway.

### 8. Render time (in the frame, headless Chrome)

- **The seven samples:** 9–45 ms on a first render; a repeat flowchart renders in 11 ms.
- **60-node flowcharts:** 87 ms for the moderate one, 220 ms for the heavy one.
- **10,000 characters:** 890–940 ms.
- The frame's own start (parsing the 3.5 MB script) was not timed.
- A debounce of about 300 ms suits typical diagrams. A large one needs "Drawing…" and a guard that only the latest id is kept, as the spec already says.

## Fixtures

The spike's drawings from the pinned Mermaid are in the spike folder (`out/strict-*.svg`). They are not committed. The plan's build writes the real fixtures under `test/fixtures/diagrams/` with its regeneration task, as §9.5 says.

## Changes the spec needs

1. **§2 and "My calls" 2: the frame uses `securityLevel: "strict"`, not `"sandbox"`.** Sandbox mode throws inside an opaque-origin frame, and it isolates nothing the frame doesn't.
2. **§2: the frame's fonts need CORS.** The Archivo files the frame loads are served with `Access-Control-Allow-Origin: *`, or `FontFace` fails from the opaque origin. `font-src 'self'` alone is not enough.
3. **§3: the sanitizer's lists, as measured:**
   - Add the attribute `font-style`.
   - Drop quietly: the elements `filter`, `feDropShadow`, `linearGradient`, `stop` and `symbol`; the attributes `name`, `fill-rule`, `clip-rule` and `transform-origin`; the root's `width` and `style`; and any class *token* that fails the class pattern.
   - As written, all five of these refuse every flowchart, class, state, ER, sequence or gantt drawing.
   - `use`, `clipPath`, `ellipse` and `polyline` are never produced and can come off the list. The `href` rule goes with `use`.
4. **§4: `diagram.css` carries Mermaid's layout, not only colours:**
   - flowchart `text-anchor: middle`, scoped to `svg.flowchart`;
   - the font sizes per class;
   - the dash patterns.

   The frame paints with the same rules. A theme that replaces the stylesheet must keep them, and the theming reference must say so.
5. **§4: `--th-diagram-line` cannot default to `var(--th-line-strong)`.** It measures 1.54:1 on the surface in light and 1.67:1 in dark, against the spec's own 3:1. `var(--th-dim)` measures 6.65:1 and 8.21:1 on paper, and the spike used it.
6. **§4: Archivo is latin-only in the CMS.** Diagrams in non-Latin languages are measured and painted in fallback fonts. Either ship the other subsets the frame needs, or name this as a limit.
7. **§4 / §2: the gantt's width depends on the frame's width.** The frame sets `gantt.useWidth` to a fixed figure.
8. **§5: the size limits disagree.** A 10,000-character flowchart draws 770 KB cleaned (716 KB rounded) and 4,024 elements. Either:
   - raise `MAX_BYTES` to about 1 MB (gzip about 130 KB), keeping 5,000 elements; or
   - keep 300 KB and lower the source limit to about 4,000 characters.

   Whichever is chosen, the frame checks the cleaned size before writing the field, and shows a "too large" state rather than leaving a save to be refused.
9. **§5: the frame and the line rules:**
   - match `%%{` anywhere in a line (a mid-line directive is honoured);
   - add `mermaid.parse` as the frame's second check (`config` must be empty, `diagramType` on the list);
   - the frame refuses text over the limit itself, because Mermaid draws a stand-in diagram instead of failing.
10. **§5: `mindmap`, `kanban` and `block-beta` don't rely on HTML labels.** Under `htmlLabels: false` they draw with no `foreignObject`. The reason given for leaving them off is wrong; leaving them off the first list can stand on the painting work instead.
11. **§6: `accTitle` and `accDescr` do survive** in strict mode (`<title>`/`<desc>`), so the "unverified" note goes. The root's `width`/`height` from the `viewBox` is required, since a cleaned root has no size.
12. **Version note:** 11.17.2 is the pin that fits the brief, but 12.x is the current major. The plan checks 11.x's support before vendoring.
