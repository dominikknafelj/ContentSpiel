import { Controller } from "@hotwired/stimulus"

// A "Copy" button: the record header's next to the public URL (cs-studio
// spec §5.1) and the System status rows' next to a console command.
// `navigator.clipboard` needs no server round trip, so this stays its own
// tiny controller rather than folding into `admin--saving--autosave` (which these
// buttons have nothing to do with) or `admin--tree`.
//
// What is copied is `textValue` when set, else `urlValue` -- both read once
// from a value the server already computed (the header's `PublicSite::Urls`,
// a check's fixed command string); this never builds text of its own.
//
// Two shapes:
// - the controller sits on the button itself (the header): the button's own
//   label is swapped for a moment;
// - it sits on a wrapper with `button`, `status` and `source` targets (a
//   System status row): the button's label is swapped, the polite `status`
//   line announces the result to a screen reader, and where the clipboard
//   API is missing (plain http off localhost) or refuses, the `source`
//   element's text is selected so the reader can press the copy shortcut --
//   never an exception, never `alert()`.
export default class extends Controller {
  static values = { url: String, text: String }
  static targets = ["button", "status", "source"]

  async copy(event) {
    event?.preventDefault()

    try {
      if (!navigator.clipboard?.writeText) throw new Error("Clipboard API unavailable")
      await navigator.clipboard.writeText(this.textValue || this.urlValue)
      this.flash("Copied")
    } catch (error) {
      if (this.hasSourceTarget) {
        this.select(this.sourceTarget)
        this.flash("Couldn't copy automatically — the text is selected, press Ctrl+C (⌘C on a Mac).", "Copy failed")
      } else {
        this.flash("Copy failed")
      }
    }
  }

  select(element) {
    const range = document.createRange()
    range.selectNodeContents(element)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }

  // Swaps the button's own label for a moment rather than a separate visible
  // element -- there's nothing else on this button worth preserving
  // mid-flash, and it's gone before an editor could tab away and lose the
  // original text. `message` is also what the polite status line says, when
  // the row has one; `label` is the shorter visible text when they differ.
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
