import { Controller } from "@hotwired/stimulus"

// A library image field -- a page's hero, an image block's image
// (`Admin::Columns::MediaColumnComponent`, media library Task 8; see that
// component for the markup and the save contract).
//
// Choose/Change opens the one picker (`admin--media-picker`, via
// `media-picker:open` on `window`, with the button as the opener focus
// returns to); the pick arrives as `media-picker:picked` on that button and
// bubbles up to here. Either way -- a pick or Remove -- the hidden input's
// new value goes out with a bubbling `input` event, which the enclosing
// form's `admin--autosave` already listens for: this controller never
// saves anything itself.
export default class extends Controller {
  static targets = [ "input", "thumbnail", "title", "choose", "remove" ]
  static values = { placeholderIds: Object, defaults: Object }

  // The override fields' placeholders follow the image this field was
  // rendered with -- which matters after a refused choice, when the server
  // re-renders this field with the stored image (`Admin::MediaFields`)
  // and the placeholders still show the refused pick's defaults.
  connect() {
    this.setPlaceholders(this.defaultsValue)
  }

  static texts = {
    choose: "Choose image",
    change: "Change image",
    empty: "No image chosen"
  }

  choose(event) {
    window.dispatchEvent(new CustomEvent("media-picker:open", { detail: { opener: event.currentTarget } }))
  }

  picked(event) {
    const { id, url, title, alt, caption } = event.detail || {}
    if (!Number.isInteger(id)) return

    this.write(String(id))
    this.thumbnailTarget.src = url || ""
    this.thumbnailTarget.hidden = !url
    this.titleTarget.textContent = title || ""
    this.setPlaceholders({ alt, caption })
    this.showChosen(true)
  }

  remove() {
    this.write("")
    this.thumbnailTarget.removeAttribute("src")
    this.thumbnailTarget.hidden = true
    this.titleTarget.textContent = this.constructor.texts.empty
    this.setPlaceholders({})
    this.showChosen(false)
    // The Remove button just hid itself; focus goes to Choose rather than
    // being dropped on the page body -- or, for someone who can't choose
    // (no `media.upload`, so no Choose button), to the field itself
    // (`tabindex="-1"` on the component's wrapper).
    if (this.hasChooseTarget) {
      this.chooseTarget.focus()
    } else {
      this.element.focus()
    }
  }

  write(value) {
    this.inputTarget.value = value
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  showChosen(chosen) {
    if (this.hasChooseTarget) this.chooseTarget.textContent = chosen ? this.constructor.texts.change : this.constructor.texts.choose
    this.removeTarget.hidden = !chosen
  }

  // The per-use override fields beside this one (`placeholder_ids:` on the
  // component) show the chosen image's own default -- what a blank override
  // falls back to -- and nothing once the image is removed.
  setPlaceholders(defaults) {
    Object.entries(this.placeholderIdsValue).forEach(([ key, id ]) => {
      const field = document.getElementById(id)
      if (field) field.placeholder = defaults[key] || ""
    })
  }
}
