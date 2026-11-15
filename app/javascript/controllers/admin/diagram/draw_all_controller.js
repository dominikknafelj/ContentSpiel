import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"
import { openFrame } from "diagram/frame"
import { digest } from "diagram/digest"
import { enqueue, currentGeneration } from "saving/queue"
import { headers } from "editing/requests"
import { afterSnapshot } from "diagram/snapshot"

// The Draw diagrams screen's run (`Admin::DiagramDrawingsScreen::ListComponent`,
// draw-diagrams spec §5, the Design System's StudioDrawDiagrams): "Draw all"
// draws every listed diagram in this browser, one after another, and saves
// each drawing as the Diagram card would.
//
// ONE FRAME. At `connect` it builds one renderer frame (`diagram/frame`) in a
// slot of its own at the end of the list (`data-draw-frame`): out of view
// (fixed, far off the left edge, with a real size, since Mermaid measures
// its labels in the frame's layout: `display: none` would measure nothing),
// `aria-hidden`, and the frame itself `tabindex="-1"`. Every row is drawn in
// it, with the colours CS Studio's probe gives (`colourProbe`, the card's
// `--th-diagram-*` read), so the drawing is the card's.
//
// THE RUN. Each row still to draw (every row but those this run or an
// earlier one drew) is marked Waiting; then, in order: the row is marked
// Drawing (`aria-busy`), its source (the text of its `<template>`) is drawn,
// and the answer awaited. An error is "Doesn't draw" with the frame's
// sentence; a drawing is digested (`diagram/digest`) and sent through the
// write queue (`enqueue`) as a PATCH to the row's `data-url` with `locale`,
// `svg`, `from` and the block's base (`base_updated_at`), as multipart
// `FormData`, as the card's autosave sends it (a drawing near its 1 MB
// limit, percent-encoded, could cross Rack's 4 MB limit on an urlencoded
// body, which multipart does not share), the CSRF token and
// the tab header (`editing/requests`' `headers()`), without which the
// server's stale and held checks would not know this tab. The next row is
// drawn only once the save has answered. A save's answer names the block's
// new base, which every row of the same block (its other languages) takes,
// or the next language would be refused as stale by the first.
//
// AN ANSWER is `{ ok: true, published, status, page_id, review_url, base }`
// or `{ ok: false, reason, holder, own_tab }`. A refusal is Skipped (changed
// since the list, held, gone; held by the viewer's own other tab, `own_tab`,
// reads the hold strip's sentence for it, never their own name) or "Doesn't draw" (the drawing too large or refused by
// the sanitizer) with the reason's sentence (`REASONS`); anything else (a
// 403 with no reason, an answer that is not JSON, no answer) is Skipped
// with the generic sentence.
//
// STOP. "Draw all" and "Stop" are one button (`start`, `#toggle`), its label
// and look (`startClass`, `stopClass`) swapped in place so the focus never
// moves. Stop is a flag read between rows: the row in hand finishes while
// the button reads "Stopping…" (disabled, busy), and the rows not reached
// are Skipped as stopped. Leaving the screen ends the run: a Turbo visit
// (`turbo:before-visit`) or a navigation of the frame this screen stands in
// (its `turbo:before-fetch-request`; a prefetch's target is its link, never
// the frame). A save already sent is answered (the visit waits for it,
// `saving/queue`'s drain), and nothing is sent after it, the row in hand's
// drawing included.
//
// WHAT IS SAID. The progress line under the head ("Drawing 2 of 4…" and the
// bar, which is `aria-hidden`) is for the eye; the polite live region
// (`status`) speaks at the start, at each row that doesn't draw or is
// skipped (its text and its reason, as two lines), and at the end (the
// summary), never per drawn row. The rows a Stop skips are said by the
// summary alone. At the end: the summary notice (a clone of
// `summaryNotice`, its parts that are nought left out), the card of the
// pages with a published copy, live or scheduled, that got a drawing
// (`publish`, one clone of `publishRow` per page, its title and path taken
// from the page's group, its status chip a clone of the `publishChip` of the
// save's `status`), the head's count (`count`) of the rows still to draw, in
// its served plural words, hidden when none is left, and "Draw all" back
// while a row is still to draw.
//
// CAN'T DRAW HERE. Without `crypto.subtle` (plain HTTP to another host) no
// frame is built: the `insecure` notice and reason are shown, the reason
// made the button's description, and the button `aria-disabled` (not
// `disabled`), so it keeps the focus and its reason is heard; `#toggle`
// does nothing while it is.
//
// TAKE-BACK. `disconnect` and `turbo:before-cache` end the run (nothing is
// sent after it), remove the frame and its slot, and put back every chip,
// reason, mark, the count, the progress, the live region, the summary, the
// card and the button as the server drew them, so a copy Turbo keeps is the
// server's. At `turbo:before-cache` the screen may be the one still showing
// (a link inside `#content` caches the page it has just drawn), so once the
// copy is made a controller still in the document connects again
// (`diagram/snapshot`): without it, Draw all would find no frame and do
// nothing. A row's base taken from a save stays: it is the block's as
// stored, and a run from a restored copy would otherwise be refused.
const REASONS = {
  stale: { state: "skipped", key: "components.diagram_drawings_screen.row.reasons.changed" },
  changed: { state: "skipped", key: "components.diagram_drawings_screen.row.reasons.changed" },
  gone: { state: "skipped", key: "components.diagram_drawings_screen.row.reasons.gone" },
  denied: { state: "skipped", key: "components.diagram_drawings_screen.row.reasons.gone" },
  held: { state: "skipped", key: "components.diagram_drawings_screen.row.reasons.held" },
  too_large: { state: "failed", key: "components.fields.mermaid_field.too_large" },
  invalid_drawing: { state: "failed", key: "components.diagram_drawings_screen.row.reasons.invalid_drawing" }
}
const GENERIC = { state: "skipped", key: "diagram_drawings.index.failed_generic" }
// A frame that gives no answer for this long leaves its row Skipped, so a
// run never hangs on it.
const DRAW_TIMEOUT = 30000
// A save that never answers holds the queue no longer than this.
const SAVE_TIMEOUT = 30000
const FRAME_SLOT_STYLE = { position: "fixed", left: "-10000px", top: "0", width: "800px", height: "600px", overflow: "hidden", pointerEvents: "none" }

export default class extends Controller {
  static targets = [ "start", "insecure", "chip", "summaryNotice", "colourProbe", "publish", "publishList", "publishRow",
    "publishChip", "count", "progress", "status", "summary", "row" ]

  static values = { rendererUrl: String, colours: Array, startClass: String, stopClass: String }

  connect() {
    this.generation = currentGeneration()
    this.run = null
    this.drawn = new Set()
    this.publishedPages = new Map()
    this.servedCount = this.hasCountTarget ? this.countTarget.textContent : null
    this.served = new Map(this.rowTargets.map((row) => [ row, [ ...this.slot(row).childNodes ].map((node) => node.cloneNode(true)) ]))
    this.takeBack = () => {
      this.close()
      afterSnapshot(() => { if (this.element.isConnected && !this.frame) this.connect() })
    }
    this.leaving = (event) => this.leave(event)
    document.addEventListener("turbo:before-cache", this.takeBack)
    document.addEventListener("turbo:before-visit", this.leaving)
    document.addEventListener("turbo:before-fetch-request", this.leaving)
    if (!this.hasStartTarget) return
    if (!window.crypto?.subtle) {
      this.insecureTargets.forEach((element) => { element.hidden = false })
      const reason = this.insecureTargets.find((element) => element.id)
      if (reason) this.startTarget.setAttribute("aria-describedby", reason.id)
      this.startTarget.setAttribute("aria-disabled", "true")
      return
    }
    this.openFrame()
  }

  disconnect() {
    this.close()
  }

  openFrame() {
    this.frameSlot = document.createElement("div")
    this.frameSlot.setAttribute("data-draw-frame", "")
    this.frameSlot.setAttribute("aria-hidden", "true")
    Object.assign(this.frameSlot.style, FRAME_SLOT_STYLE)
    this.element.append(this.frameSlot)
    this.frame = openFrame(this.frameSlot, {
      url: this.rendererUrlValue,
      title: this.text("components.fields.mermaid_field.frame_title"),
      onAnswer: (answer) => this.answered(answer)
    })
  }

  toggle() {
    if (!this.frame || this.startTarget.getAttribute("aria-disabled") === "true") return
    if (this.run) this.stop()
    else this.start()
  }

  stop() {
    if (!this.run || this.run.stopping) return
    this.run.stopping = true
    this.showButton("stopping")
  }

  // A visit, or a navigation of the frame this screen stands in, ends the
  // run: a save already sent is answered, and nothing more is sent.
  leave(event) {
    if (!this.run) return
    if (event.type === "turbo:before-fetch-request" && event.target !== this.element.closest("turbo-frame")) return
    this.run.leaving = true
    this.stop()
  }

  // --- The run --------------------------------------------------------------

  async start() {
    const rows = this.rowTargets.filter((row) => !this.drawn.has(row))
    if (rows.length === 0) return
    const run = { stopping: false, leaving: false, counts: { drawn: 0, failed: 0, skipped: 0 } }
    this.run = run
    this.summaryTarget.replaceChildren()
    rows.forEach((row) => this.mark(row, "waiting"))
    this.showButton("stop")
    this.progressTarget.hidden = false
    this.say(this.text("diagram_drawings.index.started", { count: rows.length }))

    for (const [ index, row ] of rows.entries()) {
      if (run.stopping) {
        rows.slice(index).forEach((left) => this.mark(left, "skipped", this.text("components.diagram_drawings_screen.row.reasons.stopped")))
        run.counts.skipped += rows.length - index
        break
      }
      this.showProgress(index, rows.length)
      const outcome = await this.drawRow(row, run)
      if (this.run !== run) return
      run.counts[outcome.state] += 1
      this.mark(row, outcome.state, outcome.reason)
      if (outcome.state === "drawn") this.drawn.add(row)
      else this.sayRow(row, outcome.reason)
    }
    this.finish(run)
  }

  // `{ state, reason }` of one row: drawn, failed or skipped.
  async drawRow(row, run) {
    this.mark(row, "drawing")
    row.setAttribute("aria-busy", "true")
    const source = row.querySelector("template[data-part='source']").content.textContent
    const answer = await this.draw(source)
    if (!answer) return this.outcome(GENERIC)
    if (answer.error) {
      if (answer.error.kind === "too_large") return this.outcome({ state: "failed", key: "components.fields.mermaid_field.too_large" })
      return { state: "failed", reason: this.text("components.diagram_drawings_screen.row.reasons.does_not_draw", { message: answer.error.message }) }
    }
    if (typeof answer.svg !== "string" || answer.svg === "") return this.outcome(GENERIC)
    const from = await digest(source)
    if (this.run !== run || run.leaving) return this.unsent(run)
    const sends = (isCurrent) => this.run === run && !run.leaving && isCurrent()
    const saved = await enqueue((isCurrent) => sends(isCurrent) ? this.save(row, answer.svg, from) : null, { generation: this.generation })
    if (this.run !== run || !saved) return this.unsent(run)
    return this.saved(row, saved)
  }

  // A row whose drawing was not sent: stopped by leaving, or the generic
  // failure. A run that was taken back writes no row, whatever this says.
  unsent(run) {
    if (run.leaving) return { state: "skipped", reason: this.text("components.diagram_drawings_screen.row.reasons.stopped") }
    return this.outcome(GENERIC)
  }

  // The frame's answer to `source`, or null when none came in time.
  draw(source) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => this.settle(null), DRAW_TIMEOUT)
      this.pending = { resolve, timer }
      this.frame.draw(source, this.colours())
    })
  }

  answered(answer) {
    if (answer.shown) return
    this.settle(answer)
  }

  settle(answer) {
    const pending = this.pending
    if (!pending) return
    this.pending = null
    clearTimeout(pending.timer)
    pending.resolve(answer)
  }

  // The PATCH of one drawing; its parsed answer, or `{}` for one that is not JSON.
  async save(row, svg, from) {
    const body = new FormData()
    Object.entries({ locale: row.dataset.locale, svg, from, base_updated_at: row.dataset.base }).forEach(([ name, value ]) => body.append(name, value))
    try {
      const response = await fetch(row.dataset.url, { method: "PATCH", headers: headers(), body, credentials: "same-origin", signal: AbortSignal.timeout(SAVE_TIMEOUT) })
      if (response.redirected) return {}
      return await response.json()
    } catch {
      return {}
    }
  }

  saved(row, answer) {
    if (answer.ok === true) {
      if (typeof answer.base === "string") {
        this.rowTargets.filter((other) => other.dataset.blockId === row.dataset.blockId).forEach((other) => { other.dataset.base = answer.base })
      }
      if (answer.published === true && typeof answer.review_url === "string") {
        this.publishedPages.set(String(answer.page_id), { url: answer.review_url, status: answer.status, group: row.closest("[data-page-id]") })
      }
      return { state: "drawn" }
    }
    const known = Object.hasOwn(REASONS, answer.reason) ? REASONS[answer.reason] : GENERIC
    if (answer.reason === "held") {
      if (answer.own_tab === true) return { state: "skipped", reason: this.text("components.editor_screen.hold_strip.own_tab") }
      return { state: "skipped", reason: answer.holder ? this.text(known.key, { name: answer.holder }) : this.text("components.editor_screen.hold_strip.refused.unknown") }
    }
    return this.outcome(known)
  }

  outcome({ state, key }) {
    return { state, reason: this.text(key) }
  }

  finish(run) {
    this.run = null
    this.progressTarget.hidden = true
    const summary = this.summaryText(run.counts)
    const notice = this.summaryNoticeTarget.content.firstElementChild.cloneNode(true)
    notice.textContent = summary
    this.summaryTarget.replaceChildren(notice)
    this.say(summary)
    this.showPublish()
    this.showCount()
    this.showButton("start")
    this.startTarget.hidden = this.rowTargets.every((row) => this.drawn.has(row))
  }

  // The rows still to draw: every row this run or an earlier one did not draw.
  showCount() {
    if (!this.hasCountTarget) return
    const left = this.rowTargets.filter((row) => !this.drawn.has(row)).length
    this.countTarget.textContent = left > 0 ? this.text("diagram_drawings.index.count", { count: left }) : ""
    this.countTarget.hidden = left === 0
  }

  // Every run ends at least one row, so at least one part is not nought.
  summaryText(counts) {
    const parts = [ "drawn", "failed", "skipped" ].filter((part) => counts[part] > 0)
      .map((part) => this.text(`diagram_drawings.index.summary.${part}`, { count: counts[part] }))
    return parts.join(this.text("diagram_drawings.index.summary.separator")) + this.text("diagram_drawings.index.summary.end")
  }

  showPublish() {
    if (this.publishedPages.size === 0) return
    const items = [ ...this.publishedPages.values() ].map(({ url, status, group }) => {
      const item = this.publishRowTarget.content.firstElementChild.cloneNode(true)
      item.querySelector("[data-part='title']").textContent = group?.querySelector("[data-part='title']")?.textContent ?? ""
      item.querySelector("[data-part='path']").textContent = group?.querySelector("[data-part='path']")?.textContent ?? ""
      item.querySelector("[data-part='review']").href = url
      const chip = this.publishChipTargets.find((template) => template.dataset.status === status)
      if (chip) item.querySelector("[data-part='status']").replaceChildren(chip.content.firstElementChild.cloneNode(true))
      return item
    })
    this.publishListTarget.replaceChildren(...items)
    this.publishTarget.hidden = false
  }

  // --- What the run writes ----------------------------------------------------

  // A row's state: the chip cloned from its template, the reason under the
  // text (danger for "Doesn't draw"), and the busy mark only while drawing.
  mark(row, state, reason = "") {
    const chip = this.chipTargets.find((template) => template.dataset.state === state)
    this.slot(row).replaceChildren(chip.content.firstElementChild.cloneNode(true))
    if (state !== "drawing") row.removeAttribute("aria-busy")
    const line = this.reasonLine(row)
    line.textContent = reason
    line.hidden = reason === ""
    if (state === "failed") line.dataset.tone = "danger"
    else delete line.dataset.tone
  }

  showButton(look) {
    const button = this.startTarget
    button.textContent = this.text(`diagram_drawings.index.${look === "start" ? "draw_all" : look}`)
    button.className = look === "start" ? this.startClassValue : this.stopClassValue
    button.disabled = look === "stopping"
    if (look === "stopping") button.setAttribute("aria-busy", "true")
    else button.removeAttribute("aria-busy")
  }

  showProgress(done, total) {
    this.progressTarget.querySelector("[data-part='words']").textContent = this.text("diagram_drawings.index.progress", { done: done + 1, total })
    this.progressTarget.querySelector("[data-part='bar']").style.width = `${Math.round((done / total) * 100)}%`
  }

  say(words) {
    this.statusTarget.textContent = words
  }

  // A row that doesn't draw or is skipped, as two lines: its text, its reason.
  sayRow(row, reason) {
    const lines = [ row.querySelector("[data-part='text']").textContent.trim(), reason ].map((words) => {
      const line = document.createElement("p")
      line.textContent = words
      return line
    })
    this.statusTarget.replaceChildren(...lines)
  }

  slot(row) {
    return row.querySelector("[data-part='state']")
  }

  reasonLine(row) {
    return row.querySelector("[data-part='reason']")
  }

  // The `--th-diagram-*` colours CS Studio's stylesheet gives the probe, as
  // the frame takes them; one that reads empty is left to the frame's own.
  colours() {
    const style = getComputedStyle(this.colourProbeTarget)
    return Object.fromEntries(this.coloursValue.map((name) => [ name, style.getPropertyValue(name).trim() ]).filter(([ , value ]) => value))
  }

  // --- Take-back --------------------------------------------------------------

  close() {
    document.removeEventListener("turbo:before-cache", this.takeBack)
    document.removeEventListener("turbo:before-visit", this.leaving)
    document.removeEventListener("turbo:before-fetch-request", this.leaving)
    this.run = null
    this.settle(null)
    this.frame?.close()
    this.frame = null
    this.frameSlot?.remove()
    this.frameSlot = null
    this.drawn?.clear()
    this.publishedPages?.clear()
    if (this.hasCountTarget && this.servedCount !== null) {
      this.countTarget.textContent = this.servedCount
      this.countTarget.hidden = false
    }
    this.served?.forEach((nodes, row) => {
      this.slot(row).replaceChildren(...nodes.map((node) => node.cloneNode(true)))
      row.removeAttribute("aria-busy")
      const line = this.reasonLine(row)
      line.textContent = ""
      line.hidden = true
      delete line.dataset.tone
    })
    this.progressTarget.hidden = true
    this.progressTarget.querySelector("[data-part='words']").textContent = ""
    this.progressTarget.querySelector("[data-part='bar']").removeAttribute("style")
    this.statusTarget.replaceChildren()
    this.summaryTarget.replaceChildren()
    this.publishListTarget.replaceChildren()
    this.publishTarget.hidden = true
    this.insecureTargets.forEach((element) => { element.hidden = true })
    if (this.hasStartTarget) {
      this.showButton("start")
      this.startTarget.hidden = false
      this.startTarget.disabled = false
      this.startTarget.removeAttribute("aria-describedby")
      this.startTarget.removeAttribute("aria-disabled")
    }
  }

  get reader() {
    return messages(this.element)
  }

  text(key, vars = {}) {
    return this.reader.t(key, vars)
  }
}
