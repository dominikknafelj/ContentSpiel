import { Controller } from "@hotwired/stimulus"
import { slugify } from "controllers/admin/slug_preview_controller"

// The New page / New post dialogs (`NewPageDialogComponent`,
// `NewPostDialogComponent`; one instance per dialog, on a wrapper inside its
// body, `kind` says which). The layout renders only the shell -- a loading
// line, an empty <turbo-frame> and a disabled Create button -- and this
// controller fills it:
//
// 1. Loads the form when the dialog opens. `admin--dialog#open` announces the
//    opening (`admin--dialog:opening`, on `document`) with the trigger that was
//    clicked; the trigger's own attributes carry the preset --
//    `data-new-page-parent-id-param` / `data-new-page-title-param`, or
//    `data-new-post-type-param` / `data-new-post-title-param` -- and become query
//    params of the form's URL (`GET /pages/new?parent_id=&title=`), so the
//    SERVER renders the form already preset, from the current tree. Every
//    opening clears the frame and loads afresh: titles and listing paths are
//    never stale, and nothing typed last time is left over.
// 2. Watches the wrapper for a form appearing (the frame finished loading, or
//    a refused create's Turbo Stream replaced the form): it enables Create,
//    refreshes the URL line, and puts focus on the error summary if there is
//    one, else on Title (`autofocus` alone does nothing for a streamed-in or
//    late-loaded element). A MutationObserver rather than `frame-load`, because
//    the stream replacement fires no such event; it reacts only when the form
//    element itself changed, so updating the URL line's text can't loop.
// 3. Keeps the URL line live as Title, Inside or the type change: the chosen
//    parent's (or type's listing page's) path plus the slug of the typed title,
//    slugified by the same function as `admin--slug-preview`. A type no page
//    lists says "Not listed on any page yet".
// 4. Guards the Create button, which sits in the dialog's footer outside the
//    form (tied to it with `form=`, so found by that attribute): disabled
//    while a form is loading and while a submit is in flight, re-enabled only
//    if the submission failed -- on success the redirect is on its way and the
//    button stays disabled until the page is replaced.
// 5. A load that fails (a network error, an error status, or a response with no
//    frame) shows a message with "Try again" instead of an empty dialog.
export default class extends Controller {
  static targets = [ "title", "inside", "pageType", "type", "url", "note", "loading", "failure" ]
  static values = { kind: String, url: String }

  connect() {
    this.currentForm = null
    this.observer = new MutationObserver(() => this.watchForm())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  get frame() { return this.element.querySelector("turbo-frame") }
  get form() { return this.element.querySelector("form") }
  get button() {
    const form = this.form
    return form ? document.querySelector(`button[form="${form.id}"]`) : this.footerButton
  }
  get footerButton() { return this.element.closest("dialog")?.querySelector("footer button[type=submit][form]") }

  opened(event) {
    const { dialog, trigger } = event.detail
    if (!dialog.contains(this.element)) return

    this.params = trigger?.dataset || {}
    this.load()
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin)
    const params = this.params || {}
    const preset = this.kindValue === "page"
      ? { parent_id: params.newPageParentIdParam, title: params.newPageTitleParam }
      : { type: params.newPostTypeParam, title: params.newPostTitleParam }
    Object.entries(preset).forEach(([name, value]) => { if (value) url.searchParams.set(name, value) })

    this.failureTarget.hidden = true
    this.loadingTarget.hidden = false
    if (this.footerButton) this.footerButton.disabled = true
    this.frame.removeAttribute("src")
    this.frame.replaceChildren()
    this.frame.setAttribute("src", url.toString())
  }

  retry() { this.load() }

  // The frame's own load answered with an error status (a 403 or 404 page, a
  // 500): Turbo would render nothing useful from it and, for these statuses,
  // does not report the frame as missing. A form SUBMISSION's refusal (422 with
  // a Turbo Stream) is not this: its event targets the form, not the frame.
  checkResponse(event) {
    if (event.target === this.frame && !event.detail.fetchResponse.succeeded) this.failed(event)
  }

  failed(event) {
    event.preventDefault()
    this.frame.replaceChildren()
    this.loadingTarget.hidden = true
    this.failureTarget.hidden = false
  }

  watchForm() {
    const form = this.form
    if (form === this.currentForm) return
    this.currentForm = form
    if (!form) return

    this.loadingTarget.hidden = true
    this.failureTarget.hidden = true
    if (this.button) this.button.disabled = false
    this.update()
    const summary = form.querySelector(".admin-error-summary")
    ;(summary || (this.hasTitleTarget ? this.titleTarget : null))?.focus()
  }

  update() {
    if (!this.hasTitleTarget || !this.hasUrlTarget) return
    const slug = slugify(this.titleTarget.value)
    if (this.kindValue === "page") {
      const option = this.hasInsideTarget ? this.insideTarget.selectedOptions[0] : null
      this.urlTarget.textContent = `URL: ${option?.dataset.path ?? ""}/${slug}`
      if (this.hasNoteTarget && option) {
        this.noteTarget.textContent = `Created as a draft at the end of ${option.dataset.title}. Drag it in the tree to move it.`
      }
    } else {
      const path = this.typeTargets.find((radio) => radio.checked)?.dataset.path
      this.urlTarget.textContent = path === undefined ? "Not listed on any page yet" : `URL: ${path}/${slug}`
    }
  }

  submitting() { if (this.button) this.button.disabled = true }

  submitted(event) {
    if (!event.detail?.success && this.button) this.button.disabled = false
  }
}
