import { Controller } from "@hotwired/stimulus"
import { youtubeIdFrom } from "rich_text/youtube"
import { createTargetSearch } from "rich_text/target_search"

// The rich-text editor's three shared dialogs -- image (alt text and caption),
// YouTube and "Page link" -- on `Admin::EditorScreen::RichTextDialogsComponent`,
// rendered once by the admin layout. This controller only gathers input; the
// editor (`admin--rich-text`) applies it through a Tiptap command, so the
// document change goes down the one path that writes the hidden input and
// fires the autosave `input` event. Nothing here writes a form field, and
// the dialogs sit outside every autosave form with `name`-less fields.
//
// The wire, in both directions a CustomEvent:
// - the editor dispatches `rich-text-dialog:open` on `window` with
//   `detail: { kind, opener, ...values }` (`opener` is the editor's own
//   element -- the one that opened it);
// - the answer is `rich-text-dialog:closed` dispatched on that `opener`
//   alone, with `detail: { kind, applied, ...result }`, after the dialog has
//   closed (the `close` event, so a native Escape, the header ×, Cancel and
//   a submit all end the same way and the opener always hears about it:
//   it restores focus and the selection). Two editors on a page therefore
//   never cross wires: only the one that asked is told.
// - an editor that goes away while its dialog is open (a Turbo Stream
//   replaced its block card) dispatches `rich-text-dialog:withdraw` on
//   `window`; the dialog closes without answering anyone.
//
// Enter in a field submits the dialog's own form (applying it): the forms are
// siblings of the editor form, never inside it, so nothing else submits.
export default class extends Controller {
  static targets = [
    "imageAlt", "imageCaption", "imagePreview", "imageSubmit", "imageRemove",
    "youtubeInput", "youtubeStatus", "youtubeError",
    "pageInput", "pageList", "pageMessage", "pageRemove"
  ]
  static values = { searchUrl: String }

  static texts = {
    altFallback: "Describe the image",
    notYoutube: "That doesn’t look like a YouTube link.",
    videoId: "Video id: "
  }

  connect() {
    this.session = null
    this.dialogs = {
      image: this.dialog("rich-text-image-dialog"),
      youtube: this.dialog("rich-text-youtube-dialog"),
      page: this.dialog("rich-text-page-dialog")
    }
    this.closeHandler = (event) => this.closed(event.currentTarget)
    Object.values(this.dialogs).forEach((dialog) => dialog.addEventListener("close", this.closeHandler))
  }

  disconnect() {
    Object.values(this.dialogs || {}).forEach((dialog) => dialog.removeEventListener("close", this.closeHandler))
    this.search?.destroy()
  }

  dialog(id) {
    return this.element.querySelector(`#${id}`)
  }

  // --- Opening ---------------------------------------------------------------

  open(event) {
    const detail = event.detail || {}
    const dialog = this.dialogs[detail.kind]
    if (!dialog || !detail.opener || dialog.open) return

    this.session = { kind: detail.kind, opener: detail.opener, result: null }
    this[`prepare${detail.kind[0].toUpperCase()}${detail.kind.slice(1)}`](detail)
    dialog.showModal()
    this.focusFirstField(dialog)
  }

  // An editor went away mid-dialog: close without answering.
  withdraw(event) {
    if (!this.session || event.detail?.opener !== this.session.opener) return

    this.session.opener = null
    this.dialogs[this.session.kind].close()
  }

  focusFirstField(dialog) {
    dialog.querySelector(".admin-dialog__body :is(input:not([type=hidden]), select, textarea)")?.focus()
  }

  prepareImage({ mode, alt = "", caption = "", defaultAlt = "", defaultCaption = "", url = "" }) {
    const editing = mode === "edit"
    this.dialogs.image.querySelector("#rich-text-image-dialog-title").textContent = editing ? "Edit image" : "Insert image"
    this.imageSubmitTarget.textContent = editing ? "Save" : "Insert image"
    this.imageRemoveTarget.hidden = !editing
    // Blank fields fall back to the library's own text in this language,
    // which is what the placeholders show.
    this.imageAltTarget.value = alt
    this.imageAltTarget.placeholder = defaultAlt || this.constructor.texts.altFallback
    this.imageCaptionTarget.value = caption
    this.imageCaptionTarget.placeholder = defaultCaption
    this.imagePreviewTarget.hidden = !url
    if (url) this.imagePreviewTarget.src = url
  }

  prepareYoutube() {
    this.youtubeInputTarget.value = ""
    this.youtubeStatusTarget.textContent = ""
    this.youtubeErrorTarget.textContent = ""
  }

  preparePage({ locale, linked = false }) {
    this.search?.destroy()
    this.pageInputTarget.value = ""
    this.pageRemoveTarget.hidden = !linked
    this.search = createTargetSearch({
      input: this.pageInputTarget,
      listbox: this.pageListTarget,
      message: this.pageMessageTarget,
      url: this.searchUrlValue,
      locale,
      autoSelect: true,
      onPick: (row) => this.finish({ target: { type: row.type, id: row.id, title: row.title || `(untitled ${row.type} #${row.id})` } })
    })
  }

  // --- Answering -------------------------------------------------------------

  // The footer's Cancel buttons: the same as Escape or ×.
  cancel() {
    this.currentDialog()?.close()
  }

  remove() {
    this.finish({ remove: true })
  }

  submit(event) {
    event.preventDefault()
    if (!this.session) return

    if (this.session.kind === "image") {
      this.finish({ alt: this.imageAltTarget.value, caption: this.imageCaptionTarget.value })
    } else if (this.session.kind === "youtube") {
      const id = youtubeIdFrom(this.youtubeInputTarget.value, { allowBareId: true })
      if (id) {
        this.finish({ id })
      } else {
        this.youtubeErrorTarget.textContent = this.constructor.texts.notYoutube
        this.youtubeInputTarget.setAttribute("aria-invalid", "true")
        this.youtubeInputTarget.focus()
      }
    }
    // The page dialog has no typed answer: Enter with a highlighted row is
    // handled by the search itself, and a pick calls `finish` directly.
  }

  // Live "Video id: …" as the field changes; the error line only appears on
  // an attempt to insert, and goes as soon as the text is edited again.
  youtubeTyped() {
    this.youtubeErrorTarget.textContent = ""
    this.youtubeInputTarget.removeAttribute("aria-invalid")
    const id = youtubeIdFrom(this.youtubeInputTarget.value, { allowBareId: true })
    this.youtubeStatusTarget.textContent = id ? `${this.constructor.texts.videoId}${id}` : ""
  }

  finish(result) {
    if (!this.session) return

    this.session.result = result
    this.currentDialog().close()
  }

  currentDialog() {
    return this.session ? this.dialogs[this.session.kind] : null
  }

  // The dialog's own `close` event -- after a submit, Cancel, ×, Escape or a
  // withdrawal. Dispatched from here rather than from `finish` so the native
  // focus restoration has already happened and cannot steal back whatever
  // focus the opener moves next (the same ruling as the media picker's).
  closed(dialog) {
    const session = this.session
    if (!session || this.dialogs[session.kind] !== dialog) return

    this.session = null
    this.search?.destroy()
    this.search = null
    const { opener, kind, result } = session
    if (!opener || !opener.isConnected) return

    opener.dispatchEvent(new CustomEvent("rich-text-dialog:closed", { detail: { kind, applied: result !== null, ...result } }))
  }
}
