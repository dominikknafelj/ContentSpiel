import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Add/remove/reorder rows in a `groups` field (cs-studio spec §4.3), the
// counterpart to `Admin::Fields::GroupsField`'s markup: `list` wraps the
// rows Sortable can drag, `template` holds one blank row keyed by the
// literal placeholder `__INDEX__` in every input `name` (that component's
// own comment explains why the index can't just be baked in ahead of time),
// and `row` is every actual row, existing or freshly added.
//
// Unlike the page tree's own Sortable controller (tree_controller.js), a
// drop here never round-trips to the server -- a `groups` field's rows are
// just nested form inputs, not their own records, so there's nothing to
// persist until the *page/post* form itself autosaves (Task 4).
// `dispatchInput` is what makes that connection: every
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

    event.target.closest('[data-admin--editor--groups-target="row"]')?.remove()
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
  //
  // `id`/`for` need the same fix (cs-studio Task 7, carried in from Task 2's
  // review): `Admin::Ui::FieldComponent`'s default `dom_id_prefix(form_name)`
  // bakes a row's index into every subfield's own input `id`, `<label
  // for>` and error-slot `id` too -- just without brackets (e.g.
  // "post_fields_speakers_0-name", not "...[0]-name") -- so a stale id left
  // behind after a remove/reorder would silently break the *next* PATCH's
  // Turbo Stream error-slot replace for that row (a `getElementById` that
  // no longer matches). The row's *old* index is read from one of its own
  // `name` attributes (any subfield's -- they all agree) before that
  // attribute gets rewritten below, then every literal `_<oldIndex>-`
  // substring in the row's own `id`/`for` values -- always exactly the
  // fragment `dom_id_prefix` produced for this row's index, immediately
  // before the subfield name's own leading dash -- is swapped for
  // `_<newIndex>-`. Skipped when the index hasn't actually moved, so a
  // remove/reorder that leaves an untouched row alone doesn't churn its ids
  // for no reason.
  renumber() {
    this.rowTargets.forEach((row, newIndex) => {
      const sample = row.querySelector("[name]")
      const match = sample?.getAttribute("name")?.match(/\[(\d+)\]/)
      const oldIndex = match ? match[1] : null

      row.querySelectorAll("[name]").forEach((field) => {
        field.name = field.name.replace(/\[\d+\]/, `[${newIndex}]`)
      })

      if (oldIndex !== null && oldIndex !== String(newIndex)) {
        const oldFragment = `_${oldIndex}-`
        const newFragment = `_${newIndex}-`

        row.querySelectorAll("[id]").forEach((el) => {
          el.id = el.id.replace(oldFragment, newFragment)
        })
        row.querySelectorAll("[for]").forEach((el) => {
          el.setAttribute("for", el.getAttribute("for").replace(oldFragment, newFragment))
        })
      }
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
