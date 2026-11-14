import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"
import { openFrame } from "diagram/frame"
import { digest } from "diagram/digest"

// A Diagram block's source and its preview (`Admin::Fields::MermaidField`,
// Diagram block spec §2 and §7, the Design System's EditorDiagramBlock and
// EditorDiagramError). It stands on the field's wrapper, so the source, the
// preview and the hidden drawing's id are one controller's wherever the
// preview stands.
//
// DRAWING. At `connect` it builds the sandboxed renderer frame into the
// `frameSlot` (`diagram/frame`), shows in it the drawing the hidden field
// holds (the one the site shows), and draws the source as it is: a source
// that draws replaces it, one that does not leaves it shown as the last
// drawing that worked. At each `input` of the source it draws again after
// DRAW_DEBOUNCE. The frame shows the drawing itself: its SVG never enters
// this page. Every answer says how high the drawing stands, and the frame
// takes that height, between FRAME_MIN and FRAME_MAX; past that it scrolls
// inside itself.
//
// WRITING. Only a draw asked for by a person's change writes. When it
// succeeds, the drawing goes into the hidden drawing input as
// `{ svg, from }` (`from` the digest of the source as the server stores it,
// `diagram/digest`), or as nothing for a blank source, and an `input` from
// that field lets the form's autosave send source and drawing together,
// through the write queue like any field. A draw that fails leaves the field
// as it was: the last drawing that worked, which the site keeps showing. The
// draw at `connect` writes nothing, so opening a card never saves, and a
// form turned read-only in place (`editing/freeze`) is never written.
//
// A TRANSLATION'S STARTING SOURCE (`starting`): the textarea shows the
// original's source with no `name`, so no save carries it. The first `input`
// names it (`sourceName`) and the drawing input (`drawingName`), which is
// named again whenever a drawing is written: the language keeps nothing of
// its own until a person changes it.
//
// A FORM SOMEONE ELSE HOLDS has none of this controller's actions
// (`HeldFields` removes them; the type declares no `read_only_actions`): its
// card draws at `connect` from the readonly textarea and writes nothing.
// That is also why the frame's take-back at `turbo:before-cache` and the
// band's scroll are listeners this controller adds itself, not actions in
// the markup: they must hold in a held form too.
//
// THE STATES (spec §7): empty ("Type a diagram to see it drawn." in the
// frame); drawing (the last picture, with "Drawing…" at the top right after
// BUSY_AFTER with no answer, for the eye only); drawn; and an error, said in
// a clone of the warn notice the server put in `notice`, in `status`, the
// polite live region, which is written only when the error's text is new and
// emptied when a draw works. Beside an error the frame keeps its last picture
// under the badge "Last drawing that worked", or says "Nothing is drawn yet."
// when it has none, and the source's offending line is marked with a band
// (`line`), which the sentence also names in words.
//
// THE DESCRIPTION (`descriptionField`, the input of the field the schema
// names): while it is blank, the neutral note the server drew hidden under
// the preview says the site shows the diagram only once it has one.
//
// TAKE-BACK. `disconnect` and `turbo:before-cache` remove the frame, its
// listener, the timers and everything this script showed, so a copy Turbo
// keeps holds the server's markup as drawn, and a page shown again from it
// builds a frame of its own at `connect`.
const DRAW_DEBOUNCE = 300
const BUSY_AFTER = 300
const FRAME_MIN = 200
const FRAME_MAX = 640
// A sentence's coded word is put in as this mark and then cut out as a
// `<code>`: no locale string holds it.
const CODED = ""
// The line rules whose sentence is the server's, by name.
const REFUSED = [ "colours", "links", "directive", "front_matter", "maths" ]

export default class extends Controller {
  static targets = [ "source", "frameSlot", "status", "colourProbe", "blank", "kept", "busy", "line", "notice", "undescribed" ]

  static values = {
    rendererUrl: String,
    rules: Object,
    drawingField: String,
    drawingName: String,
    sourceName: String,
    starting: Boolean,
    colours: Array,
    descriptionField: String
  }

  connect() {
    this.edited = false
    this.pictured = false
    this.spoken = ""
    this.marked = 0
    this.posted = null
    this.frame = openFrame(this.frameSlotTarget, {
      url: this.rendererUrlValue,
      title: this.text("components.fields.mermaid_field.frame_title"),
      onAnswer: (answer) => this.answered(answer)
    })
    this.takeBack = () => this.close()
    this.follow = () => this.placeLine()
    this.described = () => this.showDescribed()
    document.addEventListener("turbo:before-cache", this.takeBack)
    this.sourceTarget.addEventListener("scroll", this.follow)
    this.description = this.descriptionFieldValue ? document.getElementById(this.descriptionFieldValue) : null
    this.description?.addEventListener("input", this.described)
    this.showDescribed()
    this.showStored()
    this.draw()
  }

  // The drawing the hidden field holds, shown until a draw replaces it.
  showStored() {
    let stored = null
    try {
      stored = JSON.parse(this.drawingInput.value || "null")
    } catch {
      stored = null
    }
    if (typeof stored?.svg !== "string" || stored.svg === "") return
    this.frame.show(stored.svg, this.colours())
    this.pictured = true
  }

  showDescribed() {
    if (!this.hasUndescribedTarget || !this.description) return
    this.undescribedTarget.hidden = this.description.value.trim() !== ""
  }

  disconnect() {
    this.close()
  }

  // The source changed: a person's edit, so the drawing it leads to is written.
  input() {
    if (!this.edited && this.startingValue) {
      this.sourceTarget.name = this.sourceNameValue
      this.drawingInput.name = this.drawingNameValue
    }
    this.edited = true
    clearTimeout(this.drawTimer)
    this.drawTimer = setTimeout(() => this.draw(), DRAW_DEBOUNCE)
  }

  draw() {
    if (!this.frame) return
    const source = this.sourceTarget.value
    const id = this.frame.draw(source, this.colours())
    this.posted = { id, source, writes: this.edited }
    clearTimeout(this.busyTimer)
    this.busyTimer = setTimeout(() => { this.busyTarget.hidden = false }, BUSY_AFTER)
  }

  async answered(answer) {
    if (Number.isFinite(answer.height)) this.frame.resize(Math.min(FRAME_MAX, Math.max(FRAME_MIN, answer.height)))
    if (answer.shown) return
    clearTimeout(this.busyTimer)
    this.busyTarget.hidden = true
    if (answer.error) {
      this.failed(answer.error)
      return
    }

    this.pictured = answer.svg !== ""
    this.say(null)
    this.mark(0)
    this.keptTarget.hidden = true
    this.showBlank(this.pictured ? null : "empty")

    const { id, source, writes } = this.posted
    if (!writes || this.sourceTarget.readOnly) return
    const value = answer.svg === "" ? "" : JSON.stringify({ svg: answer.svg, from: await digest(source) })
    if (this.frame?.current(id)) this.write(value)
  }

  write(value) {
    const field = this.drawingInput
    field.name = this.drawingNameValue
    if (field.value === value) return
    field.value = value
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }

  failed(error) {
    this.keptTarget.hidden = !this.pictured
    this.showBlank(this.pictured ? null : "nothing_yet")
    this.say(this.notice(error))
    this.mark([ "refused", "parse" ].includes(error.kind) ? error.line : 0)
  }

  // The notice for an error: a clone of the server's, its parts filled and
  // the empty ones taken out.
  notice(error) {
    const box = this.noticeTarget.content.firstElementChild.cloneNode(true)
    const parts = Object.fromEntries([ ...box.querySelectorAll("[data-part]") ].map((part) => [ part.dataset.part, part ]))
    const { lead, sentence, message } = this.words(error)
    if (lead) parts.lead.textContent = lead
    if (sentence) parts.sentence.replaceChildren(...sentence)
    if (message) parts.message.textContent = message
    parts.site.textContent = this.siteSays(error)
    for (const part of Object.values(parts)) {
      if (part.textContent === "") part.remove()
      else part.removeAttribute("data-part")
    }
    return box
  }

  // What the notice says of an error: a sentence of the line rules (the
  // server's own words), or Mermaid's message under the lead.
  words(error) {
    const lead = this.text("components.fields.mermaid_field.error_lead")
    switch (error.kind) {
    case "refused":
      if (error.rule === "type") return { sentence: this.unsupported(error.word) }
      if (error.rule === "no_type") return { sentence: this.sentence("components.fields.mermaid_field.no_type") }
      // A directive Mermaid found that no line names has no line to say:
      // the frame's own message stands for it.
      if (REFUSED.includes(error.rule) && error.line > 0) {
        return { sentence: this.sentence(`components.fields.mermaid_field.refused.${error.rule}`, { line: error.line }, error.word || this.marker(error.rule)) }
      }
      return { lead, message: error.message }
    case "type":
      return { sentence: this.unsupported(error.word) }
    case "too_long":
      return { sentence: [ document.createTextNode(this.text("components.fields.mermaid_field.too_long", { limit: this.number(this.rulesValue.max_characters) })) ] }
    case "too_large":
      return { sentence: [ document.createTextNode(this.text("components.fields.mermaid_field.too_large")) ] }
    default:
      return { lead, message: error.message }
    }
  }

  // What the site does meanwhile: the drawing it keeps, when the hidden
  // field holds one. Without one, a draw that does not parse, a source too
  // long to draw, a drawing too large to keep and a type the site can't draw
  // say nothing is drawn yet (as the frame does).
  siteSays(error) {
    if (this.drawingInput.value !== "") return this.text("components.fields.mermaid_field.kept")
    const nothing = [ "parse", "too_large", "too_long", "type" ].includes(error.kind) || (error.kind === "refused" && !REFUSED.includes(error.rule))
    return nothing ? this.text("components.fields.mermaid_field.nothing_yet") : ""
  }

  unsupported(type) {
    return this.sentence("components.fields.mermaid_field.unsupported", { types: this.typeList() }, type)
  }

  // "flowchart, sequenceDiagram, …": the first keyword of each type, in the rules' order.
  typeList() {
    const labels = new Set()
    return Object.entries(this.rulesValue.types).filter(([ , label ]) => !labels.has(label) && labels.add(label)).map(([ keyword ]) => keyword).join(", ")
  }

  // The marker a rule's sentence names when the frame names none (`%%{`).
  marker(rule) {
    return this.rulesValue.rules?.[rule]?.markers?.[0] || ""
  }

  // A sentence as nodes, its `word` or `type` as a `<code>`.
  sentence(key, vars = {}, coded = null) {
    const nodes = []
    this.text(key, { ...vars, word: CODED, type: CODED }).split(CODED).forEach((piece, index) => {
      if (index > 0) {
        const code = document.createElement("code")
        code.textContent = coded ?? ""
        nodes.push(code)
      }
      if (piece) nodes.push(document.createTextNode(piece))
    })
    return nodes
  }

  // The status line, written only when what it says is new.
  say(box) {
    const said = box ? box.textContent : ""
    if (said === this.spoken) return
    this.spoken = said
    if (box) this.statusTarget.replaceChildren(box)
    else this.statusTarget.replaceChildren()
  }

  showBlank(key) {
    this.blankTarget.hidden = key === null
    this.blankTarget.textContent = key === null ? "" : this.text(`components.fields.mermaid_field.${key}`)
  }

  // The band over line `line` (1-based) of the source, or none for 0 or a
  // line past the text's end.
  mark(line) {
    this.marked = line > 0 && line <= this.sourceTarget.value.split("\n").length ? line : 0
    this.placeLine()
  }

  // Where the band stands: on its line as the well scrolls, inside the
  // well's own box, never over its border or past its edge.
  placeLine() {
    const band = this.lineTarget
    if (!this.marked) {
      band.hidden = true
      return
    }
    const field = this.sourceTarget
    const style = getComputedStyle(field)
    const height = parseFloat(style.lineHeight)
    const borderTop = parseFloat(style.borderTopWidth)
    const offset = borderTop + parseFloat(style.paddingTop) + (this.marked - 1) * height - field.scrollTop
    const inside = offset >= borderTop && offset + height <= borderTop + field.clientHeight
    band.hidden = !inside
    if (!inside) return
    band.style.top = `${field.offsetTop + offset}px`
    band.style.left = `${field.offsetLeft + parseFloat(style.borderLeftWidth)}px`
    band.style.width = `${field.clientWidth}px`
    band.style.height = `${height}px`
  }

  // The `--th-diagram-*` colours CS Studio's stylesheet gives the probe, as
  // the frame takes them; one that reads empty is left to the frame's own.
  colours() {
    const style = getComputedStyle(this.colourProbeTarget)
    return Object.fromEntries(this.coloursValue.map((name) => [ name, style.getPropertyValue(name).trim() ]).filter(([ , value ]) => value))
  }

  close() {
    clearTimeout(this.drawTimer)
    clearTimeout(this.busyTimer)
    document.removeEventListener("turbo:before-cache", this.takeBack)
    this.sourceTarget.removeEventListener("scroll", this.follow)
    this.description?.removeEventListener("input", this.described)
    this.description = null
    if (this.hasUndescribedTarget) this.undescribedTarget.hidden = true
    this.frame?.close()
    this.frame = null
    this.spoken = ""
    this.marked = 0
    this.statusTarget.replaceChildren()
    this.showBlank(null)
    this.keptTarget.hidden = true
    this.busyTarget.hidden = true
    this.lineTarget.hidden = true
    this.lineTarget.removeAttribute("style")
  }

  get drawingInput() {
    return document.getElementById(this.drawingFieldValue)
  }

  get reader() {
    return messages(this.element)
  }

  text(key, vars = {}) {
    return this.reader.t(key, vars)
  }

  // Grouped for the reader's language; a locale tag `Intl` rejects gets the bare digits.
  number(value) {
    try {
      return new Intl.NumberFormat(this.reader.locale()).format(value)
    } catch {
      return String(value)
    }
  }
}
