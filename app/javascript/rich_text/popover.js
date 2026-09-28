// Small DOM builders for `admin--rich-text`'s popovers (link, internal link,
// image, YouTube) -- task 7's "no browser dialogs" ruling: no
// `window.prompt`/`confirm`/`alert` anywhere, just a panel under the
// toolbar built from CS Studio's own product token classes. The class
// strings here mirror `SetupHelper#setup_input_class`/`#setup_label_class`
// and `Admin::ButtonComponent`'s variants, so a popover reads like every
// other CS Studio form; `app/assets/tailwind/application.css` `@source`s
// this directory so Tailwind actually generates them.
//
// Every popover lives *inside* the autosave `<form>` (the column is), so
// two things are guarded here once for all of them:
// - Enter in a popover field runs the popover's primary action instead of
//   implicitly submitting that form (a full-page PATCH navigation);
// - `input`/`change` from popover fields stop at the popover. Those fields
//   have no `name` and never reach the server, so letting them bubble would
//   only make `admin--autosave` save an unchanged form on every keystroke.

const INPUT_CLASS = "mt-1 block w-full rounded-cs border border-line-strong bg-surface px-3 py-2 text-ink focus:outline-2 focus:outline-accent"
const LABEL_CLASS = "block font-cs-mono text-label uppercase tracking-mono text-meta"
const BUTTON_CLASS = "inline-flex cursor-pointer items-center justify-center gap-2 rounded-cs px-3 py-1.5 text-sm font-semibold transition-colors"
const BUTTON_VARIANTS = {
  primary: "bg-accent text-on-accent hover:bg-accent-hover",
  secondary: "border border-line-strong bg-surface text-ink hover:bg-sunken",
  danger: "border border-danger bg-danger-tint text-danger-ink hover:bg-danger hover:text-on-accent"
}

let sequence = 0

export function createPopover({ title, onSubmit, onClose }) {
  const root = document.createElement("div")
  root.className = "admin-rich-text-popover absolute left-0 right-0 z-20 mt-1 flex flex-col gap-3 rounded-cs border border-line-strong bg-surface p-3 shadow-menu"
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

export function createSelect(labelText, options) {
  sequence += 1
  const id = `admin-rich-text-field-${sequence}`

  const wrapper = document.createElement("div")
  const label = document.createElement("label")
  label.className = LABEL_CLASS
  label.htmlFor = id
  label.textContent = labelText

  const select = document.createElement("select")
  select.id = id
  select.className = INPUT_CLASS
  options.forEach(([ value, text ]) => {
    const option = document.createElement("option")
    option.value = value
    option.textContent = text
    select.append(option)
  })

  wrapper.append(label, select)
  return { wrapper, select }
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
