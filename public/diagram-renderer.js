// The Diagram block's renderer frame: the one script, beside Mermaid, that
// runs in `<admin>/diagram-renderer` (`Admin::DiagramRenderersController`).
//
// The frame is sandboxed to an opaque origin, so this is a classic script
// from public/ (no module script of the app's loads there without CORS), and
// everything it knows comes from two JSON values in its document
// (`#diagram-rules`, `Diagram::Source.rules_json`; `#diagram-frame`, the
// drawing's limits and the font files) and from its parent's messages.
//
// THE PROTOCOL. The parent posts `{ id, source, colours }` with target '*'
// (an opaque origin cannot be named). The frame answers its parent, with '*',
// in the order the messages came:
//   - `{ id, svg, bytes, elements }`: the CLEANED drawing, as the server will
//     store it, and its UTF-8 size and element count; a blank source answers
//     `svg: ""` and clears the drawing;
//   - `{ id, error: { kind, line, message, ... } }`, `kind` one of
//     `too_long` (over the source's limit in code points; line 0), `refused` (a line rule of
//     `Diagram::Source`, with its `rule` and `word`; `line` is 1-based, 0 for a
//     directive Mermaid found that no line names), `parse` (Mermaid's own
//     error), `type` (Mermaid read a diagram off the list) and `too_large`
//     (the cleaned drawing over either limit, with its `bytes` and
//     `elements`). On an error the frame keeps showing the last drawing.
// Once its fonts are loaded and Mermaid is set up it posts `{ ready: true }`;
// a message that comes earlier waits for that.
//
// THE ORDER OF THE CHECKS is the spec's: the length first (Mermaid does not
// fail on an over-long text, it draws a stand-in diagram), then the line
// rules, so a refused source never reaches Mermaid's parser (a `classDef` is
// the path of CVE-2026-41149), then `mermaid.parse`, whose `config` shows
// every directive and front matter and whose `diagramType` must be on the
// list. Only then does Mermaid draw.
//
// THE LINE RULES are `Diagram::Source`'s, read from its JSON, and this port
// must decide every source as the Ruby does. Hence Ruby's own notions below
// and not JavaScript's: `strip` and the word split are ASCII whitespace
// (JavaScript's `trim` and `\s` also take a no-break space and the BOM),
// the length counts code points (`String#length`), not UTF-16 units, and a
// type or rule is looked up with `Object.hasOwn` (a first word
// `constructor` is not on the list).
//
// THE CLEANING drops what `Diagram::Drawing` drops quietly, with DOM APIs,
// so the size measured is the size stored. It refuses nothing: the server's
// sanitizer is the boundary, and the line rules keep what it refuses out of
// the drawing.
//
// `raw` in a message hands back Mermaid's drawing before cleaning as well,
// and only when `window.__diagramFixtures` is true in THIS frame: no parent
// can set that (the frame's document is out of its reach), only the fixture
// task's browser, which writes it into the frame's own context.
;(() => {
  "use strict"

  const read = (id) => JSON.parse(document.getElementById(id).textContent)
  const RULES = read("diagram-rules")
  const FRAME = read("diagram-frame")

  const BOM = "﻿"
  const RUBY_SPACE = "\\0\\t\\n\\v\\f\\r "
  const STRIP = new RegExp(`^[${RUBY_SPACE}]+|[${RUBY_SPACE}]+$`, "g")
  const WORDS = /[ \t\r\n\f\v]+/
  const CLASS_TOKEN = /^[A-Za-z][\w-]*$/
  const COLOUR_NAME = /^--th-diagram-[a-z0-9-]+$/

  // ---- The line rules, as `Diagram::Source.refusals` reads them.

  const strip = (text) => text.replace(STRIP, "")
  const firstWord = (line) => {
    const stripped = strip(line)
    return stripped === "" ? null : stripped.split(WORDS)[0]
  }
  const isComment = (stripped) => stripped.startsWith("%%") && !stripped.startsWith("%%{")
  const known = (table, key) => key !== null && Object.hasOwn(table, key)

  // [index, stripped line] of the first line neither blank nor a comment.
  const keywordLine = (lines) => {
    const index = lines.findIndex((line) => {
      const stripped = strip(line)
      return stripped !== "" && !isComment(stripped)
    })
    return index === -1 ? [ null, null ] : [ index, strip(lines[index]) ]
  }

  const lineRefusals = (line, number, type) => {
    const first = firstWord(line)
    const found = []
    for (const [ rule, spec ] of Object.entries(RULES.rules)) {
      const allowedIn = (word) => {
        const types = spec.except_types && Object.hasOwn(spec.except_types, word) ? spec.except_types[word] : []
        return types.includes(type)
      }
      const word = spec.first_words.find((w) => w === first && !allowedIn(w)) ||
        spec.markers.find((m) => spec.ignore_case ? line.toLowerCase().includes(m.toLowerCase()) : line.includes(m))
      if (word !== undefined) found.push({ line: number, rule, word })
    }
    return found
  }

  const refusals = (text) => {
    if (Array.from(text).length > RULES.max_characters) return [ { line: 0, rule: "too_long", word: null } ]

    const body = text.startsWith(BOM) ? text.slice(BOM.length) : text
    const lines = body.split("\n").map((line) => line.endsWith("\r") ? line.slice(0, -1) : line)
    const [ index, first ] = keywordLine(lines)
    if (index === null) return []

    const found = []
    const word = firstWord(first)
    if (first === RULES.front_matter) {
      found.push({ line: index + 1, rule: "front_matter", word: RULES.front_matter })
    } else if (!first.startsWith("%%{") && !known(RULES.types, word)) {
      found.push({ line: index + 1, rule: RULES.other_mermaid_types.includes(word) ? "type" : "no_type", word })
    }

    const type = known(RULES.types, word) ? word : null
    lines.forEach((line, i) => {
      if (i === index && first === RULES.front_matter) return
      found.push(...lineRefusals(line, i + 1, type))
    })
    return found
  }

  // ---- Cleaning, as `Diagram::Drawing` drops quietly.

  const DROPPED_ELEMENTS = new Set([ "style", "filter", "feDropShadow", "linearGradient", "stop", "symbol" ])
  // `filter` is the attribute that points a sequence diagram's boxes at the
  // dropped `<filter>`'s drop shadow.
  const DROPPED_ATTRIBUTES = new Set([
    "style", "fill", "stroke", "stroke-width", "stroke-dasharray", "opacity", "color", "font-family",
    "name", "fill-rule", "clip-rule", "transform-origin", "filter"
  ])
  // The component writes the root's role, name and size itself; Mermaid's
  // `aria-roledescription` (the diagram's kind) is the one aria name kept.
  const DROPPED_ROOT_ATTRIBUTES = new Set([ "width", "style", "role" ])
  const KEPT_ROOT_ARIA = "aria-roledescription"

  const clean = (svg) => {
    const root = new DOMParser().parseFromString(svg, "image/svg+xml").documentElement
    if (root.localName !== "svg") throw new Error("Mermaid's drawing is not an svg")

    for (const element of Array.from(root.getElementsByTagName("*"))) {
      if (DROPPED_ELEMENTS.has(element.localName)) element.remove()
    }
    for (const element of [ root, ...root.getElementsByTagName("*") ]) {
      for (const { name } of Array.from(element.attributes)) {
        const dropped = DROPPED_ATTRIBUTES.has(name) || name.startsWith("data-") ||
          (element === root && (DROPPED_ROOT_ATTRIBUTES.has(name) || (name.startsWith("aria-") && name !== KEPT_ROOT_ARIA)))
        if (dropped) element.removeAttribute(name)
      }
      const classes = element.getAttribute("class")
      if (classes !== null) {
        const kept = classes.split(WORDS).filter((token) => CLASS_TOKEN.test(token))
        kept.length ? element.setAttribute("class", kept.join(" ")) : element.removeAttribute("class")
      }
    }
    dropEmptyGroups(root)

    const cleaned = new XMLSerializer().serializeToString(root)
    return { svg: cleaned, bytes: new TextEncoder().encode(cleaned).length, elements: root.getElementsByTagName("*").length + 1, root }
  }

  // A `g` left with no element in it, innermost first, so a group that held
  // only empty groups goes too.
  const dropEmptyGroups = (element) => {
    for (const child of Array.from(element.children)) dropEmptyGroups(child)
    if (element.localName === "g" && element.children.length === 0 && strip(element.textContent) === "") element.remove()
  }

  // ---- Drawing.

  const shown = document.getElementById("diagram")
  let drawings = 0

  const paint = (colours) => {
    const style = document.documentElement.style
    for (const name of Array.from(style)) if (name.startsWith("--th-diagram-")) style.removeProperty(name)
    if (!colours || typeof colours !== "object") return
    for (const [ name, value ] of Object.entries(colours)) {
      if (COLOUR_NAME.test(name) && typeof value === "string" && value.length <= 200) style.setProperty(name, value)
    }
  }

  const refusal = (found) => ({
    kind: found.rule === "too_long" ? "too_long" : "refused",
    line: found.line,
    rule: found.rule,
    word: found.word,
    message: found.rule === "too_long" ? `longer than ${RULES.max_characters} characters` : `${found.rule}: ${found.word} on line ${found.line}`
  })

  // Mermaid's line, 1-based, where its error says one; 0 where it does not.
  const errorLine = (error) => {
    const hash = error && error.hash
    if (hash && hash.loc && Number.isInteger(hash.loc.first_line)) return hash.loc.first_line
    if (hash && Number.isInteger(hash.line)) return hash.line + 1
    const match = /line (\d+)/i.exec(String(error && error.message))
    return match ? Number(match[1]) : 0
  }

  const parseError = (error) => ({ kind: "parse", line: errorLine(error), message: String((error && error.message) || error) })

  const draw = async ({ id, source, colours, raw }) => {
    paint(colours)
    if (strip(source) === "") {
      shown.replaceChildren()
      return { id, svg: "", bytes: 0, elements: 0 }
    }

    const found = refusals(source)
    if (found.length) return { id, error: refusal(found[0]) }

    let parsed
    try {
      parsed = await mermaid.parse(source)
    } catch (error) {
      return { id, error: parseError(error) }
    }
    if (parsed.config && Object.keys(parsed.config).length) {
      return { id, error: { kind: "refused", line: 0, rule: "directive", word: null, message: "the source sets Mermaid's configuration" } }
    }
    if (!RULES.mermaid_types.includes(parsed.diagramType)) {
      return { id, error: { kind: "type", line: 0, word: parsed.diagramType, message: `${parsed.diagramType} is not on the list` } }
    }

    let drawn
    try {
      drawn = (await mermaid.render(`diagram-${++drawings}`, source)).svg
    } catch (error) {
      return { id, error: parseError(error) }
    }

    const { svg, bytes, elements, root } = clean(drawn)
    if (bytes > FRAME.limits.max_bytes || elements > FRAME.limits.max_elements) {
      return { id, error: { kind: "too_large", line: 0, bytes, elements, message: `${bytes} bytes and ${elements} elements after cleaning` } }
    }

    shown.replaceChildren(document.importNode(root, true))
    const answer = { id, svg, bytes, elements }
    if (raw === true && window.__diagramFixtures === true) answer.raw = drawn
    return answer
  }

  // ---- Start: the fonts first, since Mermaid sizes every box from its
  // labels' width at drawing time, in the face the page will paint.

  const loadFonts = () => Promise.all(FRAME.fonts.map(async ({ weight, url }) => {
    const face = new FontFace("Archivo", `url("${url}") format("woff2")`, { weight, style: "normal" })
    document.fonts.add(await face.load())
  }))

  // A face that does not load is said on the console and the frame draws
  // on: in a fallback face the boxes may fit less snugly, which is better
  // than no drawing at all.
  const ready = loadFonts().catch((error) => console.error("Archivo did not load in the diagram frame:", error)).then(() => {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      // Twice the source's limit: Mermaid counts UTF-16 units and draws a
      // stand-in diagram past it, and a source within the limit in code
      // points (the length is counted in code points everywhere, as
      // `Diagram::Source` counts it) is at most twice that in UTF-16 units.
      maxTextSize: 2 * RULES.max_characters,
      theme: "base",
      fontFamily: "Archivo",
      themeVariables: { fontFamily: "Archivo" },
      gantt: { useWidth: 720 }
    })
    window.parent.postMessage({ ready: true }, "*")
  })

  // One drawing at a time and in the order asked: Mermaid's render is not
  // safe to run twice at once, and the parent keeps only its latest id.
  let queue = ready

  window.addEventListener("message", (event) => {
    if (event.source !== window.parent) return
    const message = event.data
    if (!message || typeof message !== "object" || typeof message.source !== "string") return
    if (typeof message.id !== "string" && typeof message.id !== "number") return

    queue = queue.then(() => draw(message)).then(
      (answer) => window.parent.postMessage(answer, "*"),
      (error) => window.parent.postMessage({ id: message.id, error: parseError(error) }, "*")
    )
  })
})()
