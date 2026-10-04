import { Controller } from "@hotwired/stimulus"
import { slugify } from "controllers/admin/slug_preview_controller"

// The form of the New page / New post dialogs (`NewPageFormComponent`,
// `NewPostFormComponent`; one instance per form, `kind` says which). It does
// three things:
//
// 1. Presets the form when its dialog is opened. `admin--dialog#open`
//    announces the opening (`admin--dialog:opening`, on `document`) with the
//    trigger that was clicked; the trigger's own attributes carry the preset,
//    `data-new-page-parent-id-param` / `data-new-page-title-param` for a page
//    and `data-new-post-type-param` / `data-new-post-title-param` for a post.
//    A trigger without them gets a clean form (Home, the first type, no title),
//    never the leftovers of the last time the dialog was opened, and any error
//    of a refused submit is cleared with them.
// 2. Keeps the URL line live: the chosen parent's (or the chosen type's
//    listing page's) path plus the slug of the typed title, slugified by the
//    same function as `admin--slug-preview`. A type no page lists says "Not
//    listed on any page yet".
// 3. Guards against a double submit. The Create button sits in the dialog's
//    footer, outside the form, tied to it with `form=`, so it is found by that
//    attribute. A refused create answers with a Turbo Stream that replaces this
//    whole form, so a fresh instance connects: it re-enables the button and
//    puts focus on the error summary, which `autofocus` alone doesn't do for a
//    streamed-in element.
export default class extends Controller {
  static targets = [ "title", "inside", "pageType", "type", "url", "note" ]
  static values = { kind: String }

  connect() {
    this.submitted()
    this.update()
    this.element.querySelector(".admin-error-summary")?.focus()
  }

  opened(event) {
    const { dialog, trigger } = event.detail
    if (!dialog.contains(this.element)) return

    const params = trigger?.dataset || {}
    this.element.querySelector(".admin-error-summary")?.remove()
    this.titleTarget.removeAttribute("aria-invalid")
    if (this.kindValue === "page") this.presetPage(params)
    else this.presetPost(params)
    this.update()
  }

  presetPage(params) {
    this.titleTarget.value = params.newPageTitleParam || ""
    const wanted = params.newPageParentIdParam
    const index = Array.from(this.insideTarget.options).findIndex((option) => option.value === wanted)
    this.insideTarget.selectedIndex = index === -1 ? 0 : index
    this.pageTypeTarget.selectedIndex = 0
  }

  presetPost(params) {
    this.titleTarget.value = params.newPostTitleParam || ""
    const radios = this.typeTargets
    const wanted = radios.find((radio) => radio.value === params.newPostTypeParam) || radios[0]
    if (wanted) wanted.checked = true
  }

  update() {
    const slug = slugify(this.titleTarget.value)
    if (this.kindValue === "page") {
      const option = this.insideTarget.selectedOptions[0]
      this.urlTarget.textContent = `URL: ${option?.dataset.path ?? ""}/${slug}`
      this.noteTarget.textContent = `Created as a draft at the end of ${option?.dataset.title ?? "Home"}. Drag it in the tree to move it.`
    } else {
      const path = this.typeTargets.find((radio) => radio.checked)?.dataset.path
      this.urlTarget.textContent = path === undefined ? "Not listed on any page yet" : `URL: ${path}/${slug}`
    }
  }

  submitting() { this.setBusy(true) }

  submitted() { this.setBusy(false) }

  setBusy(busy) {
    const button = document.querySelector(`button[form="${this.element.id}"]`)
    if (button) button.disabled = busy
  }
}
