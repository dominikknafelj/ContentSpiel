import { Controller } from "@hotwired/stimulus"

// The Code block's Copy button (`Blocks::CodeComponent`, code block spec §4).
// A controller of the site's own, like `theme`: a public page loads it, and a
// theme that replaces the block's template keeps the button by writing the
// same markup (the identifier, the `button`, `source` and `status` targets,
// the `copy` action, the two values).
//
// The button is `hidden` in the markup and shown here only where there is a
// clipboard to write to, so nobody sees a button that does nothing: a page
// without JavaScript, or on plain http away from localhost, has the code
// and no button.
//
// WHAT IS COPIED is the `source` target's `textContent`: the `pre`, whose
// text is the code as stored and nothing else. The template writes nothing
// between its tags but each token's text and one line break between lines
// (`test/components/blocks/code_component_test.rb` holds that), and
// `textContent` is the text of the nodes as they are, where `innerText`
// would be what the layout made of them. So: no markup, the indentation,
// tabs and blank lines as typed, and no line break added or lost at the end.
//
// The words are the server's (`copied` and `failed` values), so this file
// holds no English. `restore` is how long the answer stays, in milliseconds.
//
// EVERYTHING THIS WRITES INTO THE PAGE IS TAKEN BACK, at two moments, since
// Turbo shows a copy of a page again on Back and this script would connect
// to a button that says "Copied" and take that for its own word:
//   - `turbo:before-cache`, before Turbo copies the page: the words only.
//     The button stays, because Turbo also copies a page that is NOT left (a
//     link to an anchor of the same page), and a button hidden there would
//     be gone for good.
//   - `disconnect`: the words, and the button hidden as the server drew it.
// The copy is made a task after the first and the page is taken out of the
// document about then, so either can come first; the first alone leaves the
// button shown in the copy, which `connect` decides again anyway.
//
// The button and the status line are kept as fields and not read as targets
// later: a controller taken off its element (the attribute removed) finds no
// target any more, and `disconnect` has to reach both.
export default class extends Controller {
  static targets = [ "button", "source", "status" ]
  static values = { copied: String, failed: String, restore: { type: Number, default: 2000 } }

  connect() {
    this.button = this.buttonTarget
    this.status = this.hasStatusTarget ? this.statusTarget : null
    this.label = this.button.textContent
    this.button.hidden = !navigator.clipboard?.writeText

    this.rest = () => this.reset()
    document.addEventListener("turbo:before-cache", this.rest)
    this.live = true
  }

  disconnect() {
    this.live = false
    document.removeEventListener("turbo:before-cache", this.rest)
    this.reset()
    this.button.hidden = true
  }

  async copy() {
    let answer = this.copiedValue
    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent)
    } catch (error) {
      answer = this.failedValue
    }
    // The page was left, or the script taken off, while the browser was
    // asked: there is nothing to say any more, and no timer to leave behind.
    if (this.live) this.say(answer)
  }

  // The button shows the answer and the status line says it to a screen
  // reader (the button's accessible name stays "Copy code").
  say(answer) {
    clearTimeout(this.timer)
    this.button.textContent = answer
    if (this.status) this.status.textContent = answer
    this.timer = setTimeout(() => this.reset(), this.restoreValue)
  }

  reset() {
    clearTimeout(this.timer)
    this.button.textContent = this.label
    if (this.status) this.status.textContent = ""
  }
}
