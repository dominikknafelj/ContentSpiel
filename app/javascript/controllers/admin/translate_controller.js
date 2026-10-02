import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// AI translation suggestions in the editor (translation helpers spec
// §6.4). One controller, two places:
//
// - on a field's Translate wrapper (`Admin::TranslationScreen::
//   TranslateButtonComponent`, in the original's `data-translate-slot`):
//   `#translate` asks for that one field; the suggestion box it gets back
//   lands inside this element, so its Use/Discard (`#use`, `#discard`)
//   arrive here too;
// - in the editor header (`TranslateAllComponent`): `#translateEmpty`
//   asks for every field on the screen that has a Translate wrapper and is
//   empty right now, and `#useAll` presses every Use.
//
// Requests are `fetch`es, never form submissions: every one of these
// buttons sits inside (or next to) an autosave `<form>`, and submitting it
// would save the form instead. The answer is a Turbo Stream
// (`Admin::TranslationsController#suggest`) updating each field's box --
// at any status, since a refusal or provider error is a stream too; any
// other answer (a 404 page, a network failure) is shown as a generic error
// in the boxes of the fields that asked.
//
// Nothing here saves anything either. Use fills the field's input and
// lets that form's own `admin--autosave` save it, as an ordinary edit
// (Review Focus 4): a plain field gets its value set and a bubbling
// `input` event (what typing does); a rich-text body gets a `translate:use`
// event on its editor's hidden JSON input, which bubbles to
// `admin--rich-text#applySuggestion` -- that editor loads the document and
// writes it back through its own `input` event.
export default class extends Controller {
  static targets = [ "button", "useAll", "status" ]

  static values = {
    url: String,
    locale: String,
    maxFields: Number,
    maxCharacters: Number
  }

  static texts = {
    failed: "Couldn't get a suggestion — reload the page and try again",
    gone: "This field is no longer on the page — reload and try again",
    notApplied: "This text can't be replaced here",
    nothingEmpty: "No empty fields to translate",
    ready: "Suggestions are ready — review them under each field",
    progress: (part, parts) => `Translating part ${part} of ${parts}…`
  }

  // --- Asking ---------------------------------------------------------------

  async translate() {
    await this.request([ describe(this.element) ])
  }

  // Every field with a Translate wrapper whose input is empty *now*, one
  // request per record and cap-sized part (`AI::Translate::MAX_FIELDS`/
  // `MAX_CHARACTERS`, rendered as values here), one after another: each
  // has to finish inside the provider's timeout on its own, and a failed
  // part doesn't throw away the others' suggestions.
  async translateEmpty() {
    const fields = Array.from(document.querySelectorAll("[data-translate-field]")).map(describe).filter(isEmpty)
    this.useAllTarget.hidden = true
    if (fields.length === 0) {
      this.showStatus(this.constructor.texts.nothingEmpty)
      return
    }

    const parts = split(fields, this.maxFieldsValue, this.maxCharactersValue)
    setBusy(this.buttonTarget, true)
    try {
      for (const [ index, part ] of parts.entries()) {
        this.showStatus(this.constructor.texts.progress(index + 1, parts.length))
        await this.request(part)
      }
    } finally {
      setBusy(this.buttonTarget, false)
    }

    // `Turbo.renderStreamMessage` applies its streams on the next
    // animation frame, not synchronously -- wait for them before looking
    // for Use buttons.
    await nextFrame()
    await nextFrame()
    const ready = document.querySelector("[data-translate-use]") !== null
    this.useAllTarget.hidden = !ready
    this.showStatus(ready ? this.constructor.texts.ready : "")
  }

  // One POST for `fields`, which all belong to the same record.
  async request(fields) {
    const [ first ] = fields
    const body = new FormData()
    body.append("record_type", first.recordType)
    body.append("record_id", first.recordId)
    body.append("locale", this.localeValue)
    fields.forEach(({ field, inputId }) => {
      body.append("fields[]", field)
      body.append(`inputs[${field}]`, inputId)
    })

    fields.forEach((field) => setBusy(field.button, true))
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        credentials: "same-origin",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
      if ((response.headers.get("Content-Type") || "").includes("text/vnd.turbo-stream.html")) {
        Turbo.renderStreamMessage(await response.text())
      } else {
        fields.forEach((field) => showError(field.box, this.constructor.texts.failed))
      }
    } catch {
      fields.forEach((field) => showError(field.box, this.constructor.texts.failed))
    } finally {
      fields.forEach((field) => setBusy(field.button, false))
    }
  }

  // --- Using ----------------------------------------------------------------

  use(event) {
    const button = event.currentTarget
    const box = button.closest("[data-translation-box]")
    const input = document.getElementById(button.dataset.translateInputId)
    if (!input) {
      showError(box, this.constructor.texts.gone)
      return
    }

    if (button.dataset.translateKind === "rich") {
      const detail = {
        document: parseJSON(button.dataset.translateDocument),
        assets: parseJSON(button.dataset.translateAssets) || {},
        linkTitles: parseJSON(button.dataset.translateLinkTitles) || {},
        applied: false
      }
      // Dispatched synchronously: the editor sets `applied` when it took
      // the document (not when it's read-only or its stored content is
      // something it can't show).
      input.dispatchEvent(new CustomEvent("translate:use", { bubbles: true, detail }))
      if (!detail.applied) {
        showError(box, this.constructor.texts.notApplied)
        return
      }
    } else {
      input.value = button.dataset.translateText
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    box?.replaceChildren()
  }

  discard(event) {
    event.currentTarget.closest("[data-translation-box]")?.replaceChildren()
  }

  // Plain fields first, then rich text: every Use is an ordinary edit its
  // form's autosave queues (one save in flight per form, edits coalescing
  // into the next), and the editors' own writes come last.
  useAll() {
    const uses = Array.from(document.querySelectorAll("[data-translate-use]"))
    const plain = uses.filter((button) => button.dataset.translateKind !== "rich")
    const rich = uses.filter((button) => button.dataset.translateKind === "rich")
    ;[ ...plain, ...rich ].forEach((button) => button.click())
    this.useAllTarget.hidden = true
    this.showStatus("")
  }

  showStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}

// A field's Translate wrapper, as the request needs it.
function describe(element) {
  const { translateRecordType, translateRecordId, translateField, translateInputId, translateKind, translateCharacters } = element.dataset
  return {
    recordType: translateRecordType,
    recordId: translateRecordId,
    field: translateField,
    inputId: translateInputId,
    kind: translateKind,
    characters: Number(translateCharacters) || 0,
    button: element.querySelector("[data-admin--translate-target='button']"),
    box: element.querySelector("[data-translation-box]")
  }
}

// Empty is what the input holds now, not what the page loaded with: a
// plain field with nothing but whitespace, a rich-text body with no text
// and no embed. An input that's gone, or a document that won't parse,
// isn't empty -- never overwrite what can't be read.
function isEmpty({ inputId, kind }) {
  const input = document.getElementById(inputId)
  if (!input) return false
  if (kind !== "rich") return input.value.trim() === ""

  const doc = parseJSON(input.value || "null")
  if (doc === undefined) return false
  const stack = doc ? [ doc ] : []
  while (stack.length > 0) {
    const node = stack.pop()
    if (!node || typeof node !== "object") continue
    if (node.type === "text" && String(node.text || "").trim() !== "") return false
    if ([ "image", "youtube", "horizontalRule" ].includes(node.type)) return false
    if (Array.isArray(node.content)) stack.push(...node.content)
  }
  return true
}

// Requests of one record each, at most `maxFields` fields and (unless a
// single field is bigger on its own -- the server then says so under it)
// `maxCharacters` characters, in screen order.
function split(fields, maxFields, maxCharacters) {
  const byRecord = new Map()
  fields.forEach((field) => {
    const key = `${field.recordType}:${field.recordId}`
    if (!byRecord.has(key)) byRecord.set(key, [])
    byRecord.get(key).push(field)
  })

  const parts = []
  byRecord.forEach((recordFields) => {
    let part = []
    let characters = 0
    recordFields.forEach((field) => {
      if (part.length > 0 && (part.length >= maxFields || characters + field.characters > maxCharacters)) {
        parts.push(part)
        part = []
        characters = 0
      }
      part.push(field)
      characters += field.characters
    })
    if (part.length > 0) parts.push(part)
  })
  return parts
}

function setBusy(button, busy) {
  if (!button) return
  button.disabled = busy
  button.toggleAttribute("aria-busy", busy)
  const spinner = button.querySelector("[data-translate-spinner]")
  if (spinner) spinner.hidden = !busy
}

// The same shape as `SuggestionComponent`'s error variant -- including its
// Dismiss, so a client-side error can be cleared like a server-sent one --
// built from text nodes only. The button is `type="button"`: the box sits
// inside an autosave form, and a default (submit) button would post it.
// Its classes mirror `SuggestionComponent::BUTTON_CLASS` (Tailwind only
// sees class names spelled out in full, here as there).
function showError(box, message) {
  if (!box) return
  const wrapper = document.createElement("div")
  wrapper.className = "mt-2 border-t border-line pt-2 text-sm"
  wrapper.dataset.translationSuggestion = ""
  const text = document.createElement("p")
  text.setAttribute("role", "alert")
  text.className = "text-danger-ink"
  text.textContent = message
  const actions = document.createElement("div")
  actions.className = "mt-2"
  const dismiss = document.createElement("button")
  dismiss.type = "button"
  dismiss.className = "cursor-pointer rounded-cs border border-line-strong bg-surface px-2 py-0.5 text-ink hover:bg-sunken"
  dismiss.dataset.action = "admin--translate#discard"
  dismiss.textContent = "Dismiss"
  actions.append(dismiss)
  wrapper.append(text, actions)
  box.replaceChildren(wrapper)
}

function parseJSON(text) {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

function nextFrame() {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()))
}
