// Makes a form read-only IN PLACE (live-editing spec §4.3): the one form that
// is not rendered read-only by the server is one that holds unsaved text when
// its claim or its save is refused. Its text stays where it was typed, to be
// copied.
//
// THE SAME RULE AS THE SERVER'S, FROM THE SAME LIST. `Admin::EditorScreen::
// HeldFields` rewrites a form someone else holds while it is rendered; this is
// the same rewrite for a form that is already on screen. Its lists are not
// written here: the region renders `HeldFields.rules` into the page
// (`data-admin--editing--hold-rules-value`) and the caller hands them in as
// `rules`, so a type or an action allowed on the server is allowed here the
// day it is added, and the other way round. A text control (`textarea`, an
// `input` of a type in `readonly_types`) is `readOnly`: selectable, full
// contrast. A `hidden` input is left alone, so the form still carries the
// same names and values. Everything else -- a select, a button, a checkbox,
// a file input, an input of a type nobody listed -- is disabled. Every
// `data-action` token whose method is not in `allowed_actions` is removed (a
// token is read like the server reads it: `action_of`), and a disabled
// submit button is put first and the form's own `submit` is refused, so that
// Enter in a field sends nothing (HTML submits a form with one text field and
// no button on Enter).
//
// `lock(element)` is called for each rich-text editor element: the caller
// knows its controller. The form is marked `data-editing-frozen="true"`,
// which the translation controls read (`translate_controller.js`).
const GUARD = '<button type="submit" disabled hidden tabindex="-1" data-held-guard></button>'

// `click:stop->admin--x#go:once@window` is `admin--x#go`: the event with its
// filters and options before the arrow, the action's own options and the
// target after the method (the same steps as `HeldFields.action_of`).
export function actionOf(token) {
  return token.replace(/^[^>]*->/, "").replace(/@\w+$/, "").replace(/(?::!?\w+)+$/, "")
}

export function freeze(form, { lock = () => {}, rules } = {}) {
  if (!form || form.dataset.editingFrozen === "true") return
  const allowed = new Set(rules?.allowed_actions || [])
  const readonly = new Set(rules?.readonly_types || [])
  const hidden = new Set(rules?.hidden_types || [])
  form.dataset.editingFrozen = "true"
  form.querySelectorAll("fieldset").forEach((fieldset) => fieldset.classList.add("admin-held"))

  for (const field of form.querySelectorAll("textarea")) field.readOnly = true
  for (const field of form.querySelectorAll("input")) {
    const type = (field.getAttribute("type") || "text").trim().toLowerCase()
    if (hidden.has(type)) continue
    if (readonly.has(type)) field.readOnly = true
    else field.disabled = true
  }
  for (const field of form.querySelectorAll("select, button")) field.disabled = true

  for (const element of [ form, ...form.querySelectorAll("[data-action]") ]) {
    if (!element.hasAttribute("data-action")) continue
    const kept = element.getAttribute("data-action").split(/\s+/).filter((token) => token && allowed.has(actionOf(token)))
    if (kept.length > 0) element.setAttribute("data-action", kept.join(" "))
    else element.removeAttribute("data-action")
  }

  form.insertAdjacentHTML("afterbegin", GUARD)
  form.addEventListener("submit", (event) => event.preventDefault(), true)
  for (const editor of form.querySelectorAll("[data-controller~='admin--rich-text--editor']")) lock(editor)
}

// What the person typed, as plain text: for "Copy my text". Every text
// control that differs from what it was rendered with gives its value; a
// rich-text field whose document differs (its hidden input, which the editor
// writes on every edit) gives its paragraphs as plain text, a blank line
// between them -- no marks, no link targets, no images. A form in which
// nothing differs (the refusal came before the first character reached a
// field we can tell from the original) gives every text field instead, so
// that "Copy my text" never copies nothing from a form that has text.
const TEXT = "input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]):not([type=button]):not([type=submit]), textarea"

export function textOf(form) {
  const parts = []
  const gather = (changedOnly) => {
    for (const field of form.querySelectorAll(`${TEXT}, [data-controller~='admin--rich-text--editor']`)) {
      const rich = field.matches("[data-controller~='admin--rich-text--editor']")
      if (rich) {
        const input = field.querySelector("input[type=hidden]")
        if (changedOnly && input && input.value === input.defaultValue) continue
        parts.push(paragraphsOf(field.querySelector(".ProseMirror")))
      } else {
        if (changedOnly && field.value === field.defaultValue) continue
        parts.push(field.value)
      }
    }
  }
  gather(true)
  if (parts.every((part) => !part.trim())) { parts.length = 0; gather(false) }
  return parts.map((part) => part.trim()).filter(Boolean).join("\n\n")
}

// A rich-text field's blocks (paragraphs, headings, list items' lists,
// quotes), each as its text, a blank line between them: `innerText` of the
// whole editor would join them with single newlines.
function paragraphsOf(editor) {
  if (!editor) return ""
  const blocks = [ ...editor.children ]
  return blocks.length > 0 ? blocks.map((block) => block.innerText.trim()).filter(Boolean).join("\n\n") : editor.innerText
}
