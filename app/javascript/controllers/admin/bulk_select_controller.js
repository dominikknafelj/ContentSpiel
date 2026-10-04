import { Controller } from "@hotwired/stimulus"

// Row selection on the posts list (design pass round 2, Task 17). The
// controller sits on a wrapper around the table, the bulk bar and the bulk
// forms, and does four things:
//
// 1. Tracks which row checkboxes are ticked and shows the bulk bar (accent
//    tint) with "N selected" only while there are some. The bar itself is
//    toggled `hidden`, which makes a poor live region (a region that appears
//    with its text is often not announced), so the announcement is a separate,
//    always-present `status` target ("2 posts selected" / "Selection cleared"),
//    written on every change after the first.
// 2. Keeps the header checkbox honest: ticked when every row on the page is,
//    `indeterminate` when only some are, so "select all on this page" is
//    also "clear all" and a half-selected page reads as half.
// 3. Writes the selection where it is submitted: each `ids` target (the
//    publish form, the trash confirmation's form) holds one hidden
//    `ids[]` input per ticked row. The checkboxes themselves carry no form
//    and no name worth submitting -- the forms live outside the table (forms
//    can't nest, and the trash confirmation is a dialog), so the selection
//    is copied into them on every change rather than tied with `form=`.
// 4. Puts the count in the trash confirmation ("3 posts"), so the dialog
//    always names how many it is about to move.
//
// Nothing needs clearing on a page change: the next page is a fresh render of
// the frame, which connects a fresh controller. `connect` reads the boxes as
// they are, so a page restored from Turbo's cache with ticked boxes shows a
// matching bar instead of a stale one.
//
// Keyboard: all of it is native checkboxes and buttons (Space ticks, Tab
// moves), nothing here intercepts a key.
export default class extends Controller {
  static targets = [ "row", "all", "bar", "count", "ids", "confirmCount", "status" ]

  // `announced` is set BEFORE the first `sync`, which announces any change
  // from it: a render with ticked boxes (a page restored from Turbo's cache)
  // is not a change the user made, and read "Selection cleared" or "N posts
  // selected" out on every connect.
  connect() {
    this.announced = this.rowTargets.filter((box) => box.checked).length
    this.sync()
  }

  // A row's own "Move to trash": selects just that post (unticking the rest)
  // and lets the same click open the bulk trash confirmation, so a single
  // trash goes through `posts/bulk` -- confirmed, filters and page kept, with
  // the same Undo -- instead of a second path of its own.
  //
  // The row's click replaced the selection the editor had built, so a dialog
  // that is cancelled (Cancel, Escape) puts the previous ticks back; one that
  // is confirmed submits first, and the page it answers with is a fresh render.
  only(event) {
    const id = String(event.params.id)
    const previous = this.rowTargets.filter((box) => box.checked).map((box) => box.value)
    this.rowTargets.forEach((box) => { box.checked = box.value === id })
    this.sync()

    const dialog = document.getElementById(event.params.dialogId)
    if (!dialog) return
    let submitted = false
    // A `method=dialog` form (Cancel) submits too, but only to close.
    const onSubmit = (e) => { if (e.target.method !== "dialog") submitted = true }
    dialog.addEventListener("submit", onSubmit)
    dialog.addEventListener("close", () => {
      dialog.removeEventListener("submit", onSubmit)
      if (submitted) return
      this.rowTargets.forEach((box) => { box.checked = previous.includes(box.value) })
      this.sync()
    }, { once: true })
  }

  toggleAll() {
    this.rowTargets.forEach((box) => { box.checked = this.allTarget.checked })
    this.sync()
  }

  // The bar's Clear: untick everything and hand focus back to the header
  // checkbox, since the button that had it is about to be hidden.
  clear() {
    this.rowTargets.forEach((box) => { box.checked = false })
    this.sync()
    this.allTarget.focus()
  }

  sync() {
    const selected = this.rowTargets.filter((box) => box.checked)
    const total = this.rowTargets.length

    if (this.hasAllTarget) {
      this.allTarget.checked = total > 0 && selected.length === total
      this.allTarget.indeterminate = selected.length > 0 && selected.length < total
    }

    this.rowTargets.forEach((box) => box.closest("tr")?.toggleAttribute("data-selected", box.checked))

    if (this.hasBarTarget) this.barTarget.hidden = selected.length === 0
    if (this.hasCountTarget) this.countTarget.textContent = selected.length
    this.confirmCountTargets.forEach((el) => { el.textContent = `${selected.length} ${selected.length === 1 ? "post" : "posts"}` })

    this.announce(selected.length)

    this.idsTargets.forEach((container) => {
      container.replaceChildren(...selected.map((box) => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "ids[]"
        input.value = box.value
        return input
      }))
    })
  }

  announce(count) {
    if (!this.hasStatusTarget || count === this.announced) return

    this.statusTarget.textContent = count > 0 ? `${count} ${count === 1 ? "post" : "posts"} selected` : "Selection cleared"
    this.announced = count
  }
}
