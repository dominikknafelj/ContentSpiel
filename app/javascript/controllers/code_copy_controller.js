import { Controller } from "@hotwired/stimulus"

// The Code block's Copy button (`Blocks::CodeComponent`, code block spec §4).
// A controller of the site's own, like `theme`: a public page loads it, and a
// theme that replaces the block's template keeps the button by writing the
// same markup (the identifier, the `button`, `source` and `status` targets,
// the `copy` action, the three values, and the `strip` target on a head that
// holds nothing but the button).
//
// The button is `hidden` in the markup and shown here only where there is a
// clipboard to write to, so nobody sees a button that does nothing: a page
// without JavaScript, or on plain http away from localhost, has the code
// and no button. A head strip with no file name and no language is `hidden`
// in the markup too and is the `strip` target: it is shown and hidden with
// the button, so nobody sees an empty strip either. Whether a strip is this
// script's to show is said by the server (it is a target or it is not),
// never read from the page.
//
// WHAT IS COPIED is the `source` target's `textContent`: the `pre`, whose
// text is the code as stored and nothing else. The template writes nothing
// between its tags but each token's text and one line break between lines
// (`test/components/blocks/code_component_test.rb` holds that), and
// `textContent` is the text of the nodes as they are, where `innerText`
// would be what the layout made of them. So: no markup, the indentation,
// tabs and blank lines as typed, and no line break added or lost at the end.
// It is read BEFORE the clipboard is asked: only the clipboard's refusal is
// "Not copied", and a template without the `source` target is an error in
// the console, for the theme's author, and nothing the visitor is told.
//
// The words are the server's (`label`, `copied` and `failed` values), so
// this file holds no English and the button's word at rest is never read
// back from the page: an answer that lands in a page Turbo is about to copy
// cannot become the word the button returns to, and `connect` writes the
// word again, so a copy that kept "Copied" comes back saying "Copy".
// `restore` is how long the answer stays, in milliseconds; the status line
// is emptied with it, so the next press is announced again.
//
// WHAT IS TAKEN BACK, AND WHEN. Turbo keeps a copy of a page and shows it
// again on Back.
//   - `turbo:before-cache`, a task before Turbo copies the page: the WORDS
//     only (the button's word and the status line).
//   - `disconnect`: the words, and the button and the strip hidden as the
//     server drew them.
// `hidden` is left alone at `turbo:before-cache` on purpose. Turbo also
// copies a page that is NOT left (a link to an anchor in it, Back between
// two anchors): a strip hidden there, even for a moment, moves everything
// below it and can leave the visitor off the anchor they asked for.
//
// WHAT A COPY THEREFORE HOLDS: the server's words, with one exception; the
// button and the strip hidden when the script was disconnected before the
// copy was made, shown when the copy was made of the page as it stood. The
// exception is a page that is NOT left (the anchor cases above), where the
// script stays connected: a clipboard's answer that lands after
// `turbo:before-cache` and before Turbo clones the page is written, as it
// should be for the visitor who is still there, and the copy holds "Copied"
// and the status line. That copy is harmless for the same reason as the
// rest: `connect` writes the word and empties the status line. Either is
// right, because nobody is shown a copy without this script running on it:
// a page restored from a copy, and a copy shown as a preview while the
// fresh page loads, are put into the document, where `connect` runs before
// a frame is drawn and decides both `hidden`s again. So a copy can never
// show a button that does nothing: a browser without a clipboard never
// revealed one, and `connect` would hide it again if it had
// (`test/system/code_block_test.rb`).
//
// The button, the strip and the status line are kept as fields and not read
// as targets later: a controller taken off its element (the attribute
// removed) finds no target any more, and `disconnect` has to reach them.
export default class extends Controller {
  static targets = [ "button", "source", "status", "strip" ]
  static values = { label: String, copied: String, failed: String, restore: { type: Number, default: 2000 } }

  connect() {
    this.button = this.buttonTarget
    this.status = this.hasStatusTarget ? this.statusTarget : null
    this.strip = this.hasStripTarget ? this.stripTarget : null
    // A template that hands no `label`, or an empty one (a theme's mistyped
    // key is "" outside development), keeps the word it wrote on the button:
    // an attribute that is there and empty must not leave a button with no
    // word after the first answer.
    this.word = this.labelValue || this.button.textContent
    this.reset()
    this.show(this.able)

    this.rest = () => this.reset()
    document.addEventListener("turbo:before-cache", this.rest)
    this.live = true
  }

  disconnect() {
    this.live = false
    document.removeEventListener("turbo:before-cache", this.rest)
    this.reset()
    this.show(false)
  }

  async copy() {
    const text = this.sourceTarget.textContent
    let answer = this.copiedValue
    try {
      await navigator.clipboard.writeText(text)
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
    this.button.textContent = this.word
    if (this.status) this.status.textContent = ""
  }

  // The button, and the strip where it is this script's.
  show(shown) {
    this.button.hidden = !shown
    if (this.strip) this.strip.hidden = !shown
  }

  get able() {
    return Boolean(navigator.clipboard?.writeText)
  }
}
