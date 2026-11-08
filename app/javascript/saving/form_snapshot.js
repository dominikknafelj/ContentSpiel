// What an explicit-save form would SUBMIT, as keys a change can be counted
// by, and the words a person reads for a changed control. Read by
// `admin--saving--save-bar`, which counts, names and marks what changed.
//
// What the form would SUBMIT, not what its controls look like: a disabled
// control and an unticked checkbox are both simply absent. That matters
// because other controllers inside the form adjust controls on connect --
// `admin--groups--branch-picker` ticks and disables every box under a chosen
// branch -- and on a Turbo frame navigation the save bar connects (and takes
// its baseline) *before* they run. Recording a checkbox's `checked` as such
// made an untouched group form count "1 unsaved change" and ask before
// leaving; a box that is ticked-and-disabled submits exactly what an unticked
// one does, so baseline and later snapshots agree whatever the connect order.
//
// KEYS. One per control, so one changed control is one change:
// - a radio group is one key (its name): flipping a radio is one change,
//   not two;
// - a checkbox is `name=value`, present only while ticked;
// - a tracked hidden input whose name ends in `[]` is `name=value` too,
//   present only while it holds a value: the members of a SET (a chip
//   input's chips, the scope editor's carried types), where order means
//   nothing. Keyed by position, removing the first of ten chips shifted the
//   other nine and read "10 unsaved changes", and removing a chip and adding
//   it back counted as a change. One chip removed is one change; removed and
//   re-added is none. The blank sentinel ahead of the chips (so an emptied
//   list still submits) holds no value and is no member;
// - anything else is its name plus its POSITION among the controls of that
//   name (`name#0`, `name#1`, ...). Rows of a list share one name
//   (`site_setting[languages][][fallback]`, one select per language row);
//   keyed by name alone they collapsed into the last row's value, and an
//   edit to an earlier row was not a change at all. A row added, removed or
//   moved shows up as the positions whose value now differs.
// A hidden input is skipped -- the CSRF token, a `_method`, a checkbox's
// "0" twin are not the editor's doing -- unless it carries
// `data-save-bar-track`: the real control behind a widget (a chip, the
// order of sortable rows), whose script dispatches a bubbling `input` or
// `change` on it when it sets the value.
// A control that goes from disabled to enabled-and-empty counts nothing
// (absent and "" are one value, see `changedKeys`); no screen has one.
//
// `controls` maps every key to the elements behind it -- an unticked box's
// key too, which has no value -- and `byName` every field name to its
// elements, so a changed key can be traced to the field it belongs to even
// when its own control has left the page (a chip removed).

// How many changed fields the bar names before it says how many more.
export const NAMES_SHOWN = 3

export function snapshot(form) {
  const values = {}
  const controls = {}
  const byName = {}
  const positions = {}
  const note = (key, field) => { (controls[key] ??= []).push(field) }
  for (const field of form.elements) {
    if (!field.name || field.disabled || field.type === "submit") continue
    // Nothing to save by itself, and filled in by a password manager on
    // load (the account screen's current password).
    if ("saveBarIgnore" in field.dataset) continue
    if (field.type === "hidden" && !("saveBarTrack" in field.dataset)) continue
    ;(byName[field.name] ??= []).push(field)
    if (field.type === "radio") {
      if (field.checked) values[field.name] = field.value
      else values[field.name] ??= ""
      note(field.name, field)
    } else if (field.type === "checkbox") {
      const key = `${field.name}=${field.value}`
      if (field.checked) values[key] = "on"
      note(key, field)
    } else if (field.type === "hidden" && field.name.endsWith("[]")) {
      const key = `${field.name}=${field.value}`
      if (field.value !== "") values[key] = "on"
      note(key, field)
    } else {
      const position = positions[field.name] ?? 0
      positions[field.name] = position + 1
      const key = `${field.name}#${position}`
      values[key] = field.value
      note(key, field)
    }
  }
  return { values, controls, byName }
}

// The keys whose value differs between two snapshots. An absent key and an
// empty string are the same value: a blank row added to a list (`name#1`
// appears, empty) is nothing the editor changed yet. For a checkbox the
// absent key is "unticked" and any present one "on", so the two still differ.
export function changedKeys(initial, now) {
  const before = initial.values
  const after = now.values
  return Object.keys({ ...before, ...after }).filter((key) => (before[key] ?? "") !== (after[key] ?? ""))
}

// The control on the page behind a changed key: its own, else -- when it has
// gone (a removed chip, a removed row) -- one of the same field name.
export function controlOf(key, initial, now) {
  const connected = (list) => (list ?? []).find((element) => element.isConnected)
  const name = key.replace(/(#\d+|=.*)$/, "")
  return connected(now.controls[key]) || connected(initial.controls[key]) || connected(now.byName[name])
}

const words = (element) => {
  if (!element) return ""
  const copy = element.cloneNode(true)
  copy.querySelectorAll(".sr-only").forEach((hidden) => hidden.remove())
  return copy.textContent.replace(/\s+/g, " ").trim()
}

// What a person calls a control, in this order: the name the page gives it
// (`data-save-bar-name` on the control or on its `[data-field-name]`
// wrapper, for a field whose label is not plain: per language, per row, a
// list); a radio's or a checkbox's legend, since its own label is one
// option's word ("STARTTLS"); its label without screen-reader-only words;
// the legend it stands in; its `aria-label`. "" when it has none of them.
export function nameOf(control) {
  if (!control) return ""
  const given = control.dataset?.saveBarName || control.closest("[data-field-name]")?.dataset.saveBarName
  if (given) return given
  const legend = control.closest("fieldset")?.querySelector(":scope > legend")
  if ((control.type === "radio" || control.type === "checkbox") && words(legend)) return words(legend)
  const label = words(control.labels?.[0])
  if (label) return label
  return words(legend) || control.getAttribute("aria-label")?.trim() || ""
}
