import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Add/remove/reorder rows in a `groups` field (cs-studio spec §4.3), the
// counterpart to `Admin::Fields::GroupsField`'s markup: `list` wraps the
// rows Sortable can drag, `template` holds one blank row keyed by the
// literal placeholder `__INDEX__` in every input `name` (that component's
// own comment explains why the index can't just be baked in ahead of time),
// and `row` is every actual row, existing or freshly added.
//
// Unlike the "Pages tree" Avo tool's own Sortable controller
// (pages_tree_controller.js), a drop here never round-trips to the server --
// a `groups` field's rows are just nested form inputs, not their own
// records, so there's nothing to persist until the *page/post* form itself
// autosaves (Task 4). `dispatchInput` is what makes that connection: every
// add/remove/reorder fires a bubbling `input` event, which is exactly what
// that autosave controller already debounces on for a plain keystroke.
export default class extends Controller {
  static targets = ["list", "template", "row"]

  connect() {
    this.sortable = Sortable.create(this.listTarget, {
      // Only the ⠿ handle starts a drag -- the row's own inputs stay
      // normal, focusable form fields.
      handle: ".admin-groups-field__handle",
      animation: 150,
      onEnd: () => this.renumber()
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  // Clones the template, replaces every `__INDEX__` placeholder with the
  // next row's index (`rowTargets.length`, i.e. "append at the end" -- rows
  // are always added last, never inserted mid-list), and appends it to
  // `list`. Stimulus re-scans for targets on access, so the new row's own
  // `row` target (and, on the next `add`, its being counted by
  // `rowTargets.length`) needs no manual registration.
  add(event) {
    event?.preventDefault()

    const index = this.rowTargets.length
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", index)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.dispatchInput()
  }

  remove(event) {
    event.preventDefault()

    event.target.closest('[data-admin--groups-target="row"]')?.remove()
    this.renumber()
  }

  // Rewrites every remaining row's own inputs to its current position in
  // the list -- needed after a remove (the rows after the removed one are
  // now off by one) and after a drag (Sortable only moves DOM nodes; it has
  // no idea their `name` attributes encode a position). Every row shares
  // the same `form_name[field]` prefix (only `GroupField`/`GroupsField`
  // itself varies that), so the first purely-numeric `[N]` segment in a
  // given input's name is always that row's own index -- never the prefix,
  // since neither a block's `settings` nor a post's `fields` form_name ever
  // contains a bare digit segment of its own (spec §4.3: field names are
  // schema-declared identifiers, not numeric).
  renumber() {
    this.rowTargets.forEach((row, index) => {
      row.querySelectorAll("[name]").forEach((field) => {
        field.name = field.name.replace(/\[\d+\]/, `[${index}]`)
      })
    })
    this.dispatchInput()
  }

  // Bubbles past the field's own wrapper to whatever form contains it, the
  // same event a keystroke in any of this row's own inputs already fires
  // natively -- the autosave controller listening on the form can't tell
  // the two apart, by design.
  dispatchInput() {
    this.element.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
