import { Controller } from "@hotwired/stimulus"

// The Form block's send in place (`Blocks::FormComponent`, forms plan Task 7;
// design.md 4.2). A controller of the site's own, like `code-copy`: a public
// page loads it, and a theme that replaces the block's template keeps the
// send in place by writing the same markup (the identifier, the `send`
// action on the form, the `summary`, `body`, `button` and `done` targets,
// the optional `status` target, the optional `follow` action on the summary
// and the three values; docs/reference/theming.md, "The Form block").
//
// PROGRESSIVE ENHANCEMENT. The form is whole without this script: a plain
// `<form method="post">` to the form's endpoint (`FormSendsController`),
// marked `data-turbo="false"` so Turbo leaves it to the browser, which then
// lands on the plain page the endpoint draws. With the script, `send` stops
// that and posts the same fields itself with `Accept: application/json`,
// and writes the answer in place:
//   sent                         the body and the summary hidden, the
//                                thank-you shown with the server's words and
//                                focused, the fields emptied (a visitor who
//                                comes back by Back is not offered a second
//                                send of the same answers)
//   invalid                      each message written as TEXT into its
//                                field's error element (which the template
//                                drew, empty and hidden, so a theme decides
//                                where an error stands), the control
//                                `aria-invalid` and described by it, and the
//                                summary filled with the server's line and
//                                one item per answer (a link to its field;
//                                an answer of no field the page knows is the
//                                item's words alone), then focused
//   gone, unavailable,           the server's sentence alone in the summary,
//   rate_limited                 which is no mistake of the visitor's
//                                (`data-notice`), focused
//   no answer at all, or one     the `network` value in the summary
//   that is not JSON of a        (pre-flight R16). The browser is NEVER made
//   known status                 to send the form itself: where the network
//                                failed that send fails too, and the
//                                visitor's answers would be lost on the
//                                browser's error page.
// Every refusal keeps what the visitor typed, and the button is enabled
// again. A press on a summary's link (`click->form-send#follow` on the
// summary, optional) moves the focus to the field it names, where an anchor
// alone only scrolls.
//
// THE WORDS ARE THE SERVER'S: every message comes in the answer, the
// button's word while sending and the network sentence are values, so this
// file holds no English. The `fields` value maps a field's key (what the
// answer names) to the ids of its error element and of what its summary
// link goes to (a radio group's first radio), so the script finds nothing
// by a naming rule of the template's.
//
// WHAT IS TAKEN BACK, AND WHEN (the Code block's incident,
// code_copy_controller.js). Turbo copies a page at `turbo:before-cache`,
// and it does that also for a page that is NOT left: following an anchor of
// the page (a table of contents, a heading's link, which the site's entry
// point gives to the browser instead of a Turbo visit: `site.js`), a typed
// fragment or Back between two anchors is a popstate that caches a
// snapshot and draws nothing. So nothing visible is taken back there: a
// thank-you or errors taken back at that moment would vanish under a
// visitor who never left. Instead
//   - `connect` puts the form back to how the server drew it: a copy Turbo
//     shows again on Back is put into the document, and `connect` runs on
//     it before a frame is drawn, so a copy that holds a thank-you or errors
//     is never shown with them. Every error element emptied and hidden,
//     `aria-invalid` and the error ids taken off the `answers[…]` controls,
//     the summary emptied and hidden, the body shown, the thank-you hidden
//     with its drawn words (kept on it by this script, in
//     `data-form-send-drawn`, before it first writes the server's), the
//     button's word (kept in `data-form-send-word` while sending) and state,
//     and the status line;
//   - `disconnect` takes all of it back too, for a page whose script is
//     taken off and the form left in the document.
// The elements are kept as fields at `connect`: a controller taken off its
// element finds no target any more, and `disconnect` has to reach them.
export default class extends Controller {
  static targets = [ "summary", "body", "button", "status", "done" ]
  static values = { sending: String, network: String, fields: Object }

  connect() {
    this.summary = this.summaryTarget
    this.body = this.bodyTarget
    this.button = this.buttonTarget
    this.status = this.hasStatusTarget ? this.statusTarget : null
    this.done = this.doneTarget
    this.sending = false
    this.restore()
    this.live = true
  }

  disconnect() {
    this.live = false
    this.restore()
  }

  async send(event) {
    event.preventDefault()
    if (this.sending) return

    this.sending = true
    this.clear()
    this.busy(true)
    let answer = null
    try {
      const response = await fetch(this.element.action, {
        method: "POST",
        body: new FormData(this.element),
        headers: { Accept: "application/json" },
        credentials: "omit"
      })
      answer = await this.read(response)
    } catch (error) {
      answer = null
    }
    this.sending = false
    // The page was left, or the script taken off, while the server was
    // asked: there is nothing to write any more.
    if (!this.live) return

    this.busy(false)
    this.answer(answer)
  }

  // A press in the summary: a link's field is focused and brought into view.
  follow(event) {
    const link = event.target.closest("a[href^='#']")
    if (!link) return

    const target = this.byId(link.getAttribute("href").slice(1))
    if (!target) return

    event.preventDefault()
    target.focus()
    target.scrollIntoView({ block: "center" })
  }

  // The answer's JSON, or null for one that is not JSON.
  async read(response) {
    if (!(response.headers.get("Content-Type") || "").includes("application/json")) return null
    try {
      return await response.json()
    } catch (error) {
      return null
    }
  }

  answer(answer) {
    switch (answer?.status) {
      case "sent": return this.sent(answer.message)
      case "invalid": return this.invalid(answer)
      case "gone":
      case "unavailable":
      case "rate_limited": return this.notice(answer.message)
      default: return this.notice(this.networkValue)
    }
  }

  sent(message) {
    this.element.reset()
    this.body.hidden = true
    this.summary.hidden = true
    if (!this.done.hasAttribute("data-form-send-drawn")) this.done.setAttribute("data-form-send-drawn", this.done.textContent)
    if (message) this.done.textContent = message
    this.done.hidden = false
    this.done.focus()
  }

  invalid(answer) {
    const list = document.createElement("ul")
    for (const error of answer.errors || []) {
      const ids = this.fieldsValue[error.key]
      const item = document.createElement("li")
      list.append(item)
      // An answer of a field this page does not know (the form changed
      // since the page was drawn): its words, with nothing to link to, so
      // the list says as many as the line counts.
      if (!ids) {
        item.textContent = error.item || error.message
        continue
      }

      const element = this.byId(ids.error)
      if (element) {
        element.textContent = error.message
        element.hidden = false
      }
      for (const control of this.controls(error.key)) this.mark(control, ids.error)

      const link = document.createElement("a")
      link.href = `#${ids.target}`
      link.textContent = error.item || error.message
      item.append(link)
    }
    const line = document.createElement("p")
    line.textContent = answer.summary
    this.summary.replaceChildren(line, list)
    this.summary.removeAttribute("data-notice")
    this.show(this.summary)
  }

  // A sentence that is no field's: the form is gone, cannot take answers,
  // too many sends, or no answer at all.
  notice(message) {
    const line = document.createElement("p")
    line.textContent = message
    this.summary.replaceChildren(line)
    this.summary.setAttribute("data-notice", "")
    this.show(this.summary)
  }

  show(element) {
    element.hidden = false
    element.focus()
  }

  // An element of this form by its id: never another placement's, and found
  // also once the form has been taken out of the document.
  byId(id) {
    return id ? this.element.querySelector(`#${CSS.escape(id)}`) : null
  }

  controls(key) {
    return Array.from(this.element.elements).filter((control) => control.name === `answers[${key}]`)
  }

  answerControls() {
    return Array.from(this.element.elements).filter((control) => control.name?.startsWith("answers["))
  }

  errorIds() {
    return new Set(Object.values(this.fieldsValue).map((ids) => ids.error).filter(Boolean))
  }

  // An invalid control: `aria-invalid`, and its error after whatever it was
  // described by (`clear` takes the error's id off again, and only it).
  mark(control, errorId) {
    const described = (control.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean)
    control.setAttribute("aria-invalid", "true")
    control.setAttribute("aria-describedby", [ ...described.filter((id) => id !== errorId), errorId ].join(" "))
  }

  busy(busy) {
    this.button.disabled = busy
    if (busy) {
      if (!this.button.hasAttribute("data-form-send-word")) this.button.setAttribute("data-form-send-word", this.button.textContent)
      this.button.setAttribute("aria-busy", "true")
      if (this.sendingValue) this.button.textContent = this.sendingValue
    } else {
      this.restoreWord()
    }
    if (this.status) this.status.textContent = busy ? this.sendingValue : ""
  }

  restoreWord() {
    this.button.removeAttribute("aria-busy")
    const word = this.button.getAttribute("data-form-send-word")
    if (word !== null) {
      this.button.textContent = word
      this.button.removeAttribute("data-form-send-word")
    }
  }

  // Every error the form shows, from this script or from a copy of the page
  // it wrote: read from the page, never from what this instance remembers.
  clear() {
    const errors = this.errorIds()
    for (const id of errors) {
      const element = this.byId(id)
      if (element) {
        element.textContent = ""
        element.hidden = true
      }
    }
    for (const control of this.answerControls()) {
      if (control.getAttribute("aria-invalid") === "true") control.removeAttribute("aria-invalid")
      const described = control.getAttribute("aria-describedby")
      if (described === null) continue

      const kept = described.split(/\s+/).filter((id) => id && !errors.has(id))
      kept.length ? control.setAttribute("aria-describedby", kept.join(" ")) : control.removeAttribute("aria-describedby")
    }
    this.summary.replaceChildren()
    this.summary.removeAttribute("data-notice")
    this.summary.hidden = true
  }

  // The form as the server drew it.
  restore() {
    this.clear()
    this.button.disabled = false
    this.restoreWord()
    if (this.status) this.status.textContent = ""
    this.body.hidden = false
    const drawn = this.done.getAttribute("data-form-send-drawn")
    if (drawn !== null) {
      this.done.textContent = drawn
      this.done.removeAttribute("data-form-send-drawn")
    }
    this.done.hidden = true
  }
}
