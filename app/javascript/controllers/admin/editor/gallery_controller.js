import { Controller } from "@hotwired/stimulus"
import { loadSortable, makeCloneInert } from "editor/drag"
import { messages } from "i18n/messages"

const ROW = '[data-admin--editor--gallery-target="row"]'

// A Gallery block's image rows (`Admin::Fields::MediaTextsField`, spec §10.3,
// StudioGallery D3): adds images from the picker, removes, reorders by drag
// and by the keyboard moves on a row's handle, and fills a caption from the
// library's. The list is the hidden input `list` names (the `:media_list`
// field's, `Admin::Fields::MediaListField`): every change of the list writes
// the ids into it as JSON and dispatches a bubbling `input`, which the card's
// `admin--saving--autosave` sends through the write queue with the texts
// beside it. This controller never sends anything itself, and a reorder is a
// change of a field, not a block move.
//
// THE PICKER (`admin--media--picker`) is opened for several images with
// `media-picker:open` on `window`, `{ opener, multiple: true, max, chosen }`:
// `max` what the gallery still takes, `chosen` every id of the list, a
// missing image's too, so the picker counts the whole list ("Add a folder"
// adds `focus: "places"`). It answers `media-picker:picked` on the opener,
// which bubbles here, with `items` in the order chosen; an image already in
// the list is skipped and none is added past `max`.
//
// THE KEYBOARD MOVES, as the block list's (`editor/keyboard_moves.js`):
// Space or Enter on a handle picks its row up, Up and Down move it, Space
// (or Enter) drops it and Escape, or the focus leaving the handle, puts it
// back. Each step is said in the polite `status`, which only a screen reader
// hears (the lifted row is what a person sees). Only a drop writes the list.
// While a row is picked up or dragged the controller says
// `admin--editor--gallery:moving` (true, then false), and the editor's live
// part draws no list meanwhile (`admin--editing--live`), as for the block
// list: a merge would put the row back under the person's hand. A card that
// is replaced all the same (by an answer, or a merge the hold did not cover)
// disconnects this controller, which puts a picked row back and says the
// move is over.
//
// No list (`list` empty: a translation tab) means nothing to reorder or add:
// only "Use library caption" works there. Held by someone else, `HeldFields`
// takes every action of this controller off the form and disables its
// buttons; the drag starts only from a handle that is not disabled, so a
// form frozen in place (`editing/freeze.js`) cannot be reordered either.
export default class extends Controller {
  static targets = [ "list", "row", "handle", "template", "status", "foot", "empty", "count", "countLine", "add", "addFolder", "limit", "thumbnail" ]
  static values = { list: String, max: Number }

  connect() {
    this.inHand = null
    if (!this.listValue) return

    this.element.dataset.sortable = "pending"
    const token = this.loadToken = {}
    loadSortable().then((Sortable) => {
      // Disconnected (or connected again) before SortableJS arrived: nothing to make.
      if (this.loadToken !== token) return

      this.sortable = Sortable.create(this.listTarget, {
        // A list of its own: a row never leaves the gallery, and no block card enters it.
        group: { name: "gallery", pull: false, put: false },
        draggable: ROW,
        handle: ".admin-gallery-row__handle:not(:disabled)",
        animation: 150,
        ghostClass: "admin-drag-ghost",
        chosenClass: "admin-drag-chosen",
        // The pointer-driven drag the block list uses (`editor/drag.js`): the
        // handle is a button, and the clone that follows the pointer is
        // made inert, since it copies the row's fields and ids.
        forceFallback: true,
        fallbackOnBody: true,
        fallbackClass: "admin-drag-fallback",
        fallbackTolerance: 3,
        onStart: () => {
          this.dragging = true
          this.sayMoving()
          makeCloneInert(Sortable.ghost)
        },
        onEnd: (event) => {
          this.dragging = false
          this.sayMoving()
          if (event.oldIndex !== event.newIndex) this.write()
        }
      })
      this.element.dataset.sortable = "ready"
    })
  }

  disconnect() {
    if (this.inHand) this.cancel(this.inHand, { refocus: false, say: false })
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
    this.loadToken = null
    this.sortable?.destroy()
    this.sortable = null
    this.dragging = false
    this.sayMoving()
    delete this.element.dataset.sortable
  }

  // Whether a row is in someone's hand (picked up or dragged), said once
  // each time the answer changes.
  sayMoving() {
    const moving = Boolean(this.dragging || this.inHand)
    if (moving === Boolean(this.saidMoving)) return
    this.saidMoving = moving
    this.dispatch("moving", { detail: { moving } })
  }

  // Add images.
  add(event) {
    this.open(event.currentTarget, {})
  }

  // Add a folder: the same picker, its focus on the list of places.
  addFolder(event) {
    this.open(event.currentTarget, { focus: "places" })
  }

  open(opener, more) {
    const left = this.maxValue - this.rowTargets.length
    if (opener.getAttribute("aria-disabled") === "true" || left <= 0) return

    window.dispatchEvent(new CustomEvent("media-picker:open", { detail: { opener, multiple: true, max: left, chosen: this.ids(), ...more } }))
  }

  picked(event) {
    const items = event.detail?.items
    if (!Array.isArray(items) || !this.listValue) return

    const present = new Set(this.ids())
    let added = 0
    for (const item of items) {
      if (this.rowTargets.length >= this.maxValue) break
      if (!Number.isInteger(item?.id) || present.has(item.id)) continue

      this.listTarget.append(this.rowFor(item))
      present.add(item.id)
      added += 1
    }
    if (added > 0) this.write()
  }

  remove(event) {
    const row = event.currentTarget.closest(ROW)
    if (!row) return

    const rows = this.rowTargets
    const index = rows.indexOf(row)
    const next = rows[index + 1] || rows[index - 1]
    if (this.inHand === row) {
      this.inHand = null
      this.sayMoving()
    }
    row.remove()
    this.write()
    // The next row's Remove, else Add images; with neither (the last row
    // gone, no right to add), the Images section itself.
    const focus = next?.querySelector(".admin-gallery-row__remove") || this.addTargets[0] || this.element
    focus.focus()
  }

  key(event) {
    const row = event.currentTarget.closest(ROW)
    if (!row) return

    if (event.key === " " || event.key === "Enter") {
      event.preventDefault()
      this.inHand === row ? this.drop(row) : this.pickUp(row)
      return
    }
    if (this.inHand !== row) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel(row)
    } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      this.step(row, event.key === "ArrowUp" ? -1 : 1)
    }
  }

  // Focus leaving the handle puts a picked row back: nothing is written
  // yet. A step blurs the handle too and focuses it again at once, so judge
  // after the current task.
  blur(event) {
    const handle = event.currentTarget
    const row = handle.closest(ROW)
    setTimeout(() => {
      if (this.inHand === row && document.activeElement !== handle) this.cancel(row, { refocus: false })
    }, 0)
  }

  // "Use library caption": the library's caption becomes the gallery's own,
  // which stays editable.
  useLibraryCaption(event) {
    const button = event.currentTarget
    const caption = button.closest(ROW)?.querySelector("textarea")
    if (!caption) return

    caption.value = button.dataset.caption || ""
    caption.focus()
    caption.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // The offer stands while the caption is blank.
  captionTyped(event) {
    const offer = event.currentTarget.closest(ROW)?.querySelector("button[data-caption]")
    if (offer) offer.hidden = !offer.dataset.caption || event.currentTarget.value.trim() !== ""
  }

  pickUp(row) {
    if (this.inHand && this.inHand !== row) this.cancel(this.inHand, { refocus: false })
    this.inHand = row
    this.sayMoving()
    this.originNext = row.nextElementSibling
    this.orderBeforePick = this.ids().join(",")
    row.dataset.picked = "true"
    this.say("components.fields.media_texts.picked_up", { title: row.dataset.title || "", ...this.position(row) })
  }

  step(row, direction) {
    const rows = this.rowTargets
    const neighbour = rows[rows.indexOf(row) + direction]
    if (!neighbour) return

    this.listTarget.insertBefore(row, direction < 0 ? neighbour : neighbour.nextElementSibling)
    // The move blurs the handle; the next key press must still reach it.
    this.focusHandle(row)
    this.say("components.fields.media_texts.moved", this.position(row))
  }

  drop(row) {
    this.clearPicked(row)
    this.say("components.fields.media_texts.dropped", this.position(row))
    if (this.ids().join(",") !== this.orderBeforePick) this.write()
  }

  cancel(row, { refocus = true, say = true } = {}) {
    if (row.isConnected) this.listTarget.insertBefore(row, this.originNext?.parentNode === this.listTarget ? this.originNext : null)
    this.clearPicked(row)
    if (refocus) this.focusHandle(row)
    if (say) this.say("components.fields.media_texts.cancelled", { title: row.dataset.title || "" })
  }

  clearPicked(row) {
    delete row.dataset.picked
    this.inHand = null
    this.sayMoving()
  }

  focusHandle(row) {
    row.querySelector(".admin-gallery-row__handle")?.focus()
  }

  position(row) {
    const rows = this.rowTargets
    return { position: rows.indexOf(row) + 1, count: rows.length }
  }

  say(key, vars) {
    this.statusTarget.textContent = this.t(key, vars)
  }

  // Every key is `components.fields.media_texts.<word>` (`config/locales/admin/fields.en.yml`).
  t(key, vars) {
    return messages(this.element).t(key, vars)
  }

  ids() {
    return this.rowTargets.map((row) => Number(row.dataset.assetId))
  }

  // A row for an image the picker handed over, copied from the template:
  // every `__ID__` in a name or an id is the image's id, and the rest is
  // filled in as properties, never as markup.
  rowFor(item) {
    const holder = document.createElement("template")
    holder.innerHTML = this.templateTarget.innerHTML.replaceAll("__ID__", String(item.id)).trim()
    const row = holder.content.firstElementChild
    const title = String(item.title || "")
    row.dataset.assetId = String(item.id)
    row.dataset.title = title
    row.querySelector(".admin-gallery-row__handle")?.setAttribute("aria-label", this.t("components.fields.media_texts.move", { title }))
    const remove = row.querySelector(".admin-gallery-row__remove")
    const removeLabel = this.t("components.fields.media_texts.remove", { title })
    remove?.setAttribute("aria-label", removeLabel)
    // The shared icon button's tooltip says its name too.
    const tip = remove?.querySelector("[data-tooltip]")
    if (tip) tip.textContent = removeLabel

    const thumbnail = row.querySelector('[data-admin--editor--gallery-target="thumbnail"]')
    if (thumbnail && item.url) thumbnail.src = item.url
    // A preview (`Media::Asset.preview_url?`, a data: address) is drawn blurred.
    if (thumbnail && item.url?.startsWith("data:")) thumbnail.classList.add("blur-sm")

    const alt = row.querySelector(".admin-gallery-row__alt")
    if (alt) {
      alt.placeholder = item.alt || this.t("components.fields.media_texts.no_library_alt")
      alt.classList.toggle("admin-gallery-row__alt--warn", !item.alt)
    }

    const offer = row.querySelector("button[data-caption]")
    if (offer && item.caption) {
      offer.dataset.caption = item.caption
      offer.hidden = false
    } else {
      offer?.remove()
    }
    return row
  }

  // Writes the list into its hidden input and tells the form, then draws
  // what follows from the count: the counts, the empty box and the limit.
  write() {
    const input = document.getElementById(this.listValue)
    if (input) {
      const ids = this.ids()
      input.value = ids.length > 0 ? JSON.stringify(ids) : ""
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    this.refresh()
  }

  refresh() {
    const count = this.rowTargets.length
    const empty = count === 0
    const full = count >= this.maxValue
    const max = this.maxValue

    this.listTarget.hidden = empty
    if (this.hasFootTarget) this.footTarget.toggleAttribute("data-empty", empty)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = !empty
    if (this.hasCountTarget) {
      this.countTarget.hidden = empty
      this.countTarget.textContent = this.t("components.fields.media_texts.count", { count, max })
    }
    if (this.hasCountLineTarget) {
      this.countLineTarget.hidden = empty
      this.countLineTarget.textContent = this.t("components.fields.media_texts.count_line", { count, max })
    }
    if (this.hasLimitTarget) this.limitTarget.hidden = !full
    for (const button of [ ...this.addTargets, ...this.addFolderTargets ]) {
      if (full) {
        button.setAttribute("aria-disabled", "true")
        if (this.hasLimitTarget) button.setAttribute("aria-describedby", this.limitTarget.id)
      } else {
        button.removeAttribute("aria-disabled")
        button.removeAttribute("aria-describedby")
      }
    }
  }
}
