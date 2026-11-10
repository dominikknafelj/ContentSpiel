import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// CS Studio's one copy script: the editor header's Copy beside the public
// URL, and every `Admin::Ui::CopyValueComponent` (a system check's command,
// the AI assistant page's token, MCP URL and client configuration).
// `navigator.clipboard` needs no server round trip, so this stays its own
// small controller.
//
// What is copied is `textValue` when set, else `urlValue` (the header's
// `PublicSite::Urls`), else the `source` target's text. A copy box sets
// neither value: its value is the source's text and stands in no attribute,
// so a token shown once is blanked whole when `admin--tokens--reveal` empties
// its `secret` targets at `pagehide`. This never builds text of its own.
//
// Two shapes:
// - the controller sits on the button itself (the header): the button's own
//   label is swapped for a moment;
// - it sits on a copy box with `button`, `status` and `source` targets: the
//   button's label is swapped, the polite `status` line says the result to a
//   screen reader, and where the clipboard API is missing (plain http off
//   localhost) or refuses, the source's text is selected so the reader can
//   press the copy shortcut -- never an exception, never `alert()`.
//
// Its words are `components.ui.copy_value.*`, from the box's `data-messages`
// or, for the header's button, <body>'s.
export default class extends Controller {
  static values = { url: String, text: String }
  static targets = ["button", "status", "source"]

  async copy(event) {
    event?.preventDefault()

    try {
      if (!navigator.clipboard?.writeText) throw new Error("Clipboard API unavailable")
      await navigator.clipboard.writeText(this.textValue || this.urlValue || this.sourceText())
      this.flash(this.word("components.ui.copy_value.copied"))
    } catch (error) {
      if (this.hasSourceTarget) {
        this.select(this.sourceTarget)
        this.flash(this.word("components.ui.copy_value.selected"), this.word("components.ui.copy_value.failed"))
      } else {
        this.flash(this.word("components.ui.copy_value.failed"))
      }
    }
  }

  sourceText() {
    return this.hasSourceTarget ? this.sourceTarget.textContent.trim() : ""
  }

  word(key) {
    return messages(this.element).t(key)
  }

  select(element) {
    const range = document.createRange()
    range.selectNodeContents(element)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }

  // Swaps the button's own label for a moment rather than a separate visible
  // element: there's nothing else on this button worth keeping mid-flash,
  // and it's back before an editor could tab away and lose the original
  // text. `message` is also what the polite status line says, when the box
  // has one; `label` is the shorter visible text when they differ.
  flash(message, label = message) {
    const button = this.hasButtonTarget ? this.buttonTarget : this.element
    const original = button.dataset.originalLabel ?? button.textContent
    button.dataset.originalLabel = original
    button.textContent = label
    if (this.hasStatusTarget) this.statusTarget.textContent = message
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      button.textContent = original
      delete button.dataset.originalLabel
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 1500)
  }

  disconnect() { clearTimeout(this.timer) }
}
