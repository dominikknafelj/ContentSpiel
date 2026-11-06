// Small DOM builders for `admin--rich-text--editor`'s Link popover (the image, YouTube
// and page dialogs are server-rendered, `RichTextDialogsComponent`) -- task 7's "no browser dialogs" ruling: no
// `window.prompt`/`confirm`/`alert` anywhere, just a panel under the
// toolbar built from CS Studio's own product token classes. The class
// strings here are `SetupHelper#setup_input_class`/`#setup_label_class`
// and `Admin::Ui::ButtonComponent`'s variants, so a popover reads like every
// other CS Studio form; `app/assets/tailwind/application.css` `@source`s
// this directory so Tailwind actually generates them.
//
// Every popover lives *inside* the autosave `<form>` (the column is), so
// two things are guarded here once for all of them:
// - Enter in a popover field runs the popover's primary action instead of
//   implicitly submitting that form (a full-page PATCH navigation);
// - `input`/`change` from popover fields stop at the popover. Those fields
//   have no `name` and never reach the server, so letting them bubble would
//   only make `admin--saving--autosave` save an unchanged form on every keystroke.

const INPUT_CLASS = "mt-1 block w-full rounded-t-field border-0 border-b border-field-line bg-field-fill px-3 py-2 text-ink focus:outline-2 focus:outline-accent"
const LABEL_CLASS = "block text-label text-meta"
// A script cannot render the component, so its classes are written out here:
// `BUTTON_CLASS` followed by a variant is `Admin::Ui::ButtonComponent.classes(
// variant, size: :small)`, and `INPUT_CLASS` is `SetupHelper#setup_input_class`,
// string for string (`test/lib/admin_design_rules_test.rb` compares them). A
// raised accent primary, a tinted secondary, a tertiary for Cancel, and
// danger_text for "Remove link" (not a confirm).
const BUTTON_CLASS = "inline-flex cursor-pointer items-center justify-center gap-2 rounded-button-sm border border-transparent font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta disabled:not-aria-busy:shadow-none aria-busy:cursor-progress px-2 py-0.5 text-sm"
const BUTTON_VARIANTS = {
  primary: "bg-accent text-on-accent shadow-2 not-disabled:hover:bg-accent-hover not-disabled:hover:shadow-3 not-disabled:active:translate-y-px not-disabled:active:shadow-none",
  secondary: "bg-accent-tint text-accent not-disabled:hover:shadow-1",
  tertiary: "bg-transparent text-accent not-disabled:hover:underline",
  danger_text: "bg-sunken text-danger-ink not-disabled:hover:shadow-1"
}

let sequence = 0

export function createPopover({ title, onSubmit, onClose }) {
  const root = document.createElement("div")
  root.className = "admin-rich-text-popover absolute left-0 right-0 z-20 mt-1 flex flex-col gap-3 rounded-card bg-popover p-3 shadow-3"
  root.setAttribute("role", "dialog")
  root.setAttribute("aria-label", title)

  const heading = document.createElement("p")
  heading.className = LABEL_CLASS
  heading.textContent = title
  root.append(heading)

  const body = document.createElement("div")
  body.className = "flex flex-col gap-3"
  root.append(body)

  const error = document.createElement("p")
  error.className = "text-sm text-danger-ink"
  error.setAttribute("role", "alert")
  root.append(error)

  const actions = document.createElement("div")
  actions.className = "flex flex-wrap gap-2"
  root.append(actions)

  root.addEventListener("input", (event) => event.stopPropagation())
  root.addEventListener("change", (event) => event.stopPropagation())
  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.preventDefault()
      onClose()
    } else if (event.key === "Enter" && event.target.tagName === "INPUT") {
      event.preventDefault()
      onSubmit?.()
    }
  })

  return {
    root,
    body,
    actions,
    setError(message) { error.textContent = message || "" }
  }
}

export function createField(labelText, { value = "", type = "text", placeholder = "" } = {}) {
  sequence += 1
  const id = `admin-rich-text-field-${sequence}`

  const wrapper = document.createElement("div")
  const label = document.createElement("label")
  label.className = LABEL_CLASS
  label.htmlFor = id
  label.textContent = labelText

  const input = document.createElement("input")
  input.id = id
  input.type = type
  input.value = value
  input.placeholder = placeholder
  input.autocomplete = "off"
  input.className = INPUT_CLASS

  wrapper.append(label, input)
  return { wrapper, input }
}

export function createButton(text, onClick, { variant = "secondary" } = {}) {
  const button = document.createElement("button")
  button.type = "button"
  button.className = `${BUTTON_CLASS} ${BUTTON_VARIANTS[variant]}`
  button.textContent = text
  button.addEventListener("click", (event) => {
    event.preventDefault()
    onClick()
  })
  return button
}
