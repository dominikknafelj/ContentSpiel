import { Controller } from "@hotwired/stimulus"

// The Form block's send in place (`Blocks::FormComponent`, forms plan Task 7;
// design.md 4.2). A controller of the site's own, like `code-copy`: a public
// page loads it, and a theme that replaces the block's template keeps the
// send in place by writing the same markup (the identifier, the `send`
// action on the form, the `summary`, `body`, `button` and `done` targets,
// the optional `status` target and the three values; docs/reference/
// theming.md, "The Form block").
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
//                                one link per answer, then focused
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
// again.
//
// THE WORDS ARE THE SERVER'S: every message comes in the answer, the
// button's word while sending and the network sentence are values, so this
// file holds no English. The `fields` value maps a field's key (what the
// answer names) to the ids of its error element and of what its summary
// link goes to (a radio group's first radio), so the script finds nothing
// by a naming rule of the template's.
//
// WHAT IS TAKEN BACK, AND WHEN. Turbo keeps a copy of a page and shows it
// again on Back. At `turbo:before-cache` and at `disconnect` everything this
// script wrote is taken back, `hidden` included: the errors emptied and
// hidden, the controls' marks as drawn, the summary emptied and hidden, the
// button's word and state, the status line, and the body shown and the
// thank-you hidden again with its drawn words. So a page left and come back
// to shows the form as it was drawn. (The Code block keeps `hidden` alone at
// `turbo:before-cache` because Turbo also copies a page an anchor link does
// not leave; the summary's links go nowhere through Turbo: the form is
// `data-turbo="false"`, which covers the links inside it, and a press on one
// moves the focus here.) The elements are kept as fields at `connect`: a
// controller taken off its element finds no target any more, and
// `disconnect` has to reach them.
export default class extends Controller {
  static targets = [ "summary", "body", "button", "status", "done" ]
  static values = { sending: String, network: String, fields: Object }

  connect() {
    this.summary = this.summaryTarget
    this.body = this.bodyTarget
    this.button = this.buttonTarget
    this.status = this.hasStatusTarget ? this.statusTarget : null
    this.done = this.doneTarget
    this.word = this.button.textContent
    this.thanks = this.done.textContent
    this.marked = []
    this.sending = false

    this.rest = () => this.takeBack()
    this.jump = (event) => this.follow(event)
    document.addEventListener("turbo:before-cache", this.rest)
    this.summary.addEventListener("click", this.jump)
    this.live = true
  }

  disconnect() {
    this.live = false
    document.removeEventListener("turbo:before-cache", this.rest)
    this.summary.removeEventListener("click", this.jump)
    this.takeBack()
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
    this.done.textContent = message || this.thanks
    this.done.hidden = false
    this.done.focus()
  }

  invalid(answer) {
    const list = document.createElement("ul")
    for (const error of answer.errors || []) {
      const ids = this.fieldsValue[error.key]
      if (!ids) continue

      const element = this.byId(ids.error)
      if (element) {
        element.textContent = error.message
        element.hidden = false
      }
      for (const control of this.controls(error.key)) this.mark(control, ids.error)

      const link = document.createElement("a")
      link.href = `#${ids.target}`
      link.textContent = error.item || error.message
      const item = document.createElement("li")
      item.append(link)
      list.append(item)
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

  // A press on one of the summary's links: the control it names is focused
  // (an anchor alone scrolls to it and leaves the focus where it was).
  follow(event) {
    const link = event.target.closest("a[href^='#']")
    if (!link) return

    const target = this.byId(link.getAttribute("href").slice(1))
    if (!target) return

    event.preventDefault()
    target.focus()
    target.scrollIntoView({ block: "center" })
  }

  // An element of this form by its id: never another placement's, and found
  // also once the form has been taken out of the document.
  byId(id) {
    return id ? this.element.querySelector(`#${CSS.escape(id)}`) : null
  }

  controls(key) {
    return Array.from(this.element.elements).filter((control) => control.name === `answers[${key}]`)
  }

  // An invalid control: `aria-invalid`, and its error after whatever it was
  // described by; what it was is remembered, to be given back.
  mark(control, errorId) {
    const described = control.getAttribute("aria-describedby")
    this.marked.push({ control, invalid: control.getAttribute("aria-invalid"), described })
    control.setAttribute("aria-invalid", "true")
    control.setAttribute("aria-describedby", [ described, errorId ].filter(Boolean).join(" "))
  }

  busy(busy) {
    this.button.disabled = busy
    if (busy) {
      this.button.setAttribute("aria-busy", "true")
      this.button.textContent = this.sendingValue || this.word
    } else {
      this.button.removeAttribute("aria-busy")
      this.button.textContent = this.word
    }
    if (this.status) this.status.textContent = busy ? this.sendingValue : ""
  }

  // Everything an earlier answer wrote, taken back before the next one.
  clear() {
    for (const { control, invalid, described } of this.marked.reverse()) {
      invalid === null ? control.removeAttribute("aria-invalid") : control.setAttribute("aria-invalid", invalid)
      described === null ? control.removeAttribute("aria-describedby") : control.setAttribute("aria-describedby", described)
    }
    this.marked = []
    for (const ids of Object.values(this.fieldsValue)) {
      const element = this.byId(ids.error)
      if (element) {
        element.textContent = ""
        element.hidden = true
      }
    }
    this.summary.replaceChildren()
    this.summary.removeAttribute("data-notice")
    this.summary.hidden = true
  }

  // The form as the server drew it.
  takeBack() {
    this.clear()
    this.busy(false)
    this.button.disabled = false
    this.body.hidden = false
    this.done.textContent = this.thanks
    this.done.hidden = true
  }
}
