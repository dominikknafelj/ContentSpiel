import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// AI translation suggestions in the editor (translation helpers spec
// §6.4, design pass round 2 handoff §10). One controller, three places:
//
// - on a field's Translate / Suggest update wrapper (`Admin::
//   TranslationScreen::TranslateButtonComponent`): `#translate` asks for that
//   one field (`data-translate-mode="update"` sends `mode=update`, and the box
//   it gets back also shows the current translation);
// - on the suggestion box under every such field (`admin/shared/
//   _translation_box`): the Use / Discard of a suggestion and the Cancel /
//   Try again of a pending request arrive here, because Stimulus actions only
//   fire inside a controller's element;
// - in the editor header (`TranslateAllComponent`): `#translateEmpty` asks
//   for every field on the screen that has a Translate wrapper and is empty
//   right now, `#cancel` stops that run, `#useAll` presses every Use and
//   `#discardAll` empties every box. The header is in one of three states --
//   idle (the button, with the count of empty fields), running ("Suggesting i
//   of n fields", a bar, Cancel) and ready ("n suggestions ready", Use all,
//   Discard all) -- worked out by `#refresh`, which runs after every run, Use,
//   Discard and Cancel (the `translate:changed` event, below).
//
// Requests are `fetch`es, never form submissions: every one of these
// buttons sits inside (or next to) an autosave `<form>`, and submitting it
// would save the form instead. The answer is a Turbo Stream
// (`Admin::TranslationsController#suggest`) updating each field's box --
// at any status, since a refusal or provider error is a stream too; any
// other answer (a 404 page, a network failure) is shown as a generic error
// in the boxes of the fields that asked.
//
// While a request is out, each field's box holds the pending box (a clone of
// the layout's `<template id="translation-pending-template">`): a spinner, the
// seconds waited and Cancel. At 25 seconds -- the provider's own timeout, which
// the server enforces too -- it turns into "No suggestion after 25 seconds."
// with Try again; an answer that arrives for it after that is ignored unless
// the editor pressed Try again (which starts a fresh request and drops the old
// one). The state a pending box needs lives in a module-level WeakMap, not on a
// controller instance: the box's controller, the wrapper's and the header's
// are three different instances.
//
// Nothing here saves anything either. Use fills the field's input and
// lets that form's own `admin--saving--autosave` save it, as an ordinary edit
// (Review Focus 4): a plain field gets its value set and a bubbling
// `input` event (what typing does -- the autosave queue only sends a form
// whose submitted data changed, so this event is what makes Use save); a
// rich-text body gets a `translate:use` event on its editor's hidden JSON
// input, which bubbles to `admin--rich-text--editor#applySuggestion` -- that editor
// loads the document and writes it back through its own `input` event.
export default class extends Controller {
  static targets = [ "idle", "running", "ready", "status" ]

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
    noAnswer: "No suggestion came back for this field — try again",
    nothingEmpty: "No empty fields to translate",
    label: (count) => `Suggest translations for ${count} empty ${count === 1 ? "field" : "fields"}`,
    progress: (index, total) => `Suggesting ${index} of ${total} ${total === 1 ? "field" : "fields"}`,
    ready: (count) => `${count} ${count === 1 ? "suggestion" : "suggestions"} ready`
  }

  // A request must not outlive the page it was asked on: after a language
  // tab or any Turbo navigation the same input ids exist again, in another
  // language, and a late answer would land under the wrong field. So jobs
  // whose boxes left the page, and this header's run, stop here (and every
  // job at `turbo:before-visit`, below).
  disconnect() {
    this.runController?.abort()
    cancelDetachedJobs()
  }

  // --- Asking ---------------------------------------------------------------

  async translate() {
    // A field of a held or frozen form is nobody's to fill.
    if (!onScreen(this.element)) return
    const field = describe(this.element)
    await this.request([ field ], { url: this.urlValue, locale: this.localeValue })
    await settle()
    announceChange()
  }

  // Every field with a Translate wrapper whose input is empty *now*, one
  // request per record and cap-sized part (`AI::Translate::MAX_FIELDS`/
  // `MAX_CHARACTERS`, rendered as values here), one after another: each
  // has to finish inside the provider's timeout on its own, and a failed
  // part doesn't throw away the others' suggestions. Cancel aborts the run:
  // the in-flight request and the boxes still waiting go, the fields already
  // answered keep their suggestions.
  async translateEmpty() {
    if (this.runController) return

    const fields = emptyFields()
    if (fields.length === 0) {
      this.refresh()
      this.showStatus(this.constructor.texts.nothingEmpty)
      return
    }

    this.showStatus("")
    const parts = split(fields, this.maxFieldsValue, this.maxCharactersValue)
    const run = new AbortController()
    this.runController = run
    let answered = 0
    this.showRunning(0, fields.length)
    try {
      for (const part of parts) {
        if (run.signal.aborted) break
        this.showRunning(answered, fields.length)
        await this.request(part, { url: this.urlValue, locale: this.localeValue, signal: run.signal })
        answered += part.length
      }
      this.setBar(answered / fields.length)
    } finally {
      this.runController = null
    }

    // `Turbo.renderStreamMessage` applies its streams on the next
    // animation frame, not synchronously -- wait for them before looking
    // for Use buttons.
    await settle()
    this.refresh()
  }

  // The header's Cancel: abort the run (see `translateEmpty`).
  cancel() {
    this.runController?.abort()
    this.refresh()
  }

  // One POST for `fields`, which all belong to the same record: the pending
  // boxes go in first, so they exist the instant the button is pressed.
  async request(fields, { url, locale, signal, focus = false }) {
    const job = startJob(fields, { url, locale, signal, focus })
    const [ first ] = fields
    const body = new FormData()
    body.append("record_type", first.recordType)
    body.append("record_id", first.recordId)
    body.append("locale", locale)
    if (first.mode === "update") body.append("mode", "update")
    fields.forEach(({ field, inputId }) => {
      body.append("fields[]", field)
      body.append(`inputs[${field}]`, inputId)
    })

    fields.forEach((field) => setBusy(field.button, true))
    try {
      const response = await fetch(url, {
        method: "POST",
        body,
        credentials: "same-origin",
        signal: job.controller.signal,
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
      const stream = (response.headers.get("Content-Type") || "").includes("text/vnd.turbo-stream.html")
      const text = stream ? await response.text() : null
      // Cancelled, replaced by Try again, or late (past the 25 seconds and
      // not retried): nobody is waiting for this answer any more.
      if (job.over || job.timedOut) return

      if (stream) {
        // Where focus sits now: a pending box that held it (its Cancel button)
        // is about to be replaced, and focus must not fall to the page.
        const focused = fields.filter(({ box }) => box?.contains(document.activeElement))
        Turbo.renderStreamMessage(guardStreams(text, job))
        await settle()
        focused.forEach(({ box }) => box.querySelector("[data-translate-use]")?.focus())
        // A box nothing answered (the stream named no such field) must not
        // wait forever.
        fields.forEach((field) => { if (isPendingOf(field.box, job)) showError(field.box, this.constructor.texts.noAnswer) })
      } else {
        fields.forEach((field) => showError(field.box, this.constructor.texts.failed))
      }
    } catch (error) {
      if (error.name !== "AbortError" && !job.over && !job.timedOut) fields.forEach((field) => showError(field.box, this.constructor.texts.failed))
    } finally {
      fields.forEach((field) => setBusy(field.button, false))
      if (!job.timedOut || job.over) endJob(job)
    }
  }

  // --- Pending boxes ----------------------------------------------------------

  // The pending box's Cancel: this request only -- its whole record's part of
  // a bulk run, since that was one request -- and the run goes on to the next.
  cancelPending(event) {
    const box = event.currentTarget.closest("[data-translation-box]")
    const job = jobOf(box)
    if (!job) return

    cancelJob(job)
    refocus(box)
    announceChange()
  }

  // Try again: a fresh request for the same fields, the old one dropped.
  async retry(event) {
    const job = jobOf(event.currentTarget.closest("[data-translation-box]"))
    if (!job) return

    cancelJob(job)
    // Focus stays in the box: the new pending box takes Try again's place.
    await this.request(job.fields, { url: job.url, locale: job.locale, signal: job.signal, focus: true })
    await settle()
    announceChange()
  }

  // --- Using ----------------------------------------------------------------

  use(event) {
    const button = event.currentTarget
    if (!onScreen(button)) return
    const box = button.closest("[data-translation-box]")
    const input = document.getElementById(button.dataset.translateInputId)
    if (!input) {
      showError(box, this.constructor.texts.gone)
      return
    }
    const hadFocus = box?.contains(document.activeElement)

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
      // The suggestion is an editable textarea (no `name`): what the editor
      // has typed into it now is what gets applied, not what the server sent.
      const text = button.closest("[data-translation-suggestion]")?.querySelector("[data-translate-suggestion-text]")
      if (!text) {
        showError(box, this.constructor.texts.notApplied)
        return
      }
      input.value = text.value
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    box?.replaceChildren()
    // The box (and the button the editor pressed) is gone: focus moves to the
    // field the text went into.
    if (hadFocus) fieldFocusTarget(input)?.focus()
    announceChange()
  }

  // Editing a suggestion is not editing the form: its textarea sits inside
  // the autosave `<form>`, whose `input`/`change`/`focusout` listeners would
  // otherwise save on every keystroke of text that isn't a field's value
  // yet. The box stops them here (`SuggestionComponent` wires this).
  contain(event) {
    event.stopPropagation()
  }

  discard(event) {
    const box = event.currentTarget.closest("[data-translation-box]")
    const hadFocus = box?.contains(document.activeElement)
    box?.replaceChildren()
    if (hadFocus) refocus(box)
    announceChange()
  }

  // Plain fields first, then rich text: every Use is an ordinary edit its
  // form's autosave queues (one save in flight per form, edits coalescing
  // into the next), and the editors' own writes come last.
  useAll() {
    const uses = Array.from(document.querySelectorAll("[data-translate-use]")).filter(onScreen)
    const plain = uses.filter((button) => button.dataset.translateKind !== "rich")
    const rich = uses.filter((button) => button.dataset.translateKind === "rich")
    // One refresh at the end, not one per Use.
    muteChanges = true
    try {
      ;[ ...plain, ...rich ].forEach((button) => button.click())
    } finally {
      muteChanges = false
    }
    this.showStatus("")
    this.refresh()
  }

  // Every suggestion box emptied (a pending box is not a suggestion: Cancel
  // is its way out), nothing saved.
  discardAll() {
    document.querySelectorAll("[data-translation-box]").forEach((box) => {
      if (onScreen(box) && box.querySelector("[data-translation-suggestion]")) box.replaceChildren()
    })
    this.showStatus("")
    this.refresh()
  }

  // --- The header's three states ------------------------------------------------

  // Idle, ready or nothing, from what the page holds *now* (suggestions
  // waiting, else fields still empty). A run in progress owns the header.
  refresh() {
    if (!this.hasIdleTarget || this.runController) return

    const suggestions = Array.from(document.querySelectorAll("[data-translate-use]")).filter(onScreen).length
    if (suggestions > 0) {
      this.show("ready")
      const text = this.constructor.texts.ready(suggestions)
      this.readyTarget.querySelector("[data-translate-ready-text]").textContent = text
      this.showStatus(text)
      return
    }

    this.showStatus("")

    const empty = emptyFields().length
    this.idleTarget.querySelector("[data-translate-label]").textContent = this.constructor.texts.label(empty)
    this.show(empty > 0 ? "idle" : null)
  }

  showRunning(answered, total) {
    this.show("running")
    // Counted per field: the one being waited on (never past the total).
    const text = this.constructor.texts.progress(Math.min(answered + 1, total), total)
    this.runningTarget.querySelector("[data-translate-progress-text]").textContent = text
    // Also in the persistent live region: the running line itself is shown and
    // hidden with the state, and a region that appears is not announced.
    this.showStatus(text)
    this.setBar(answered / total)
  }

  // The bar's width through the CSSOM: the strict CSP refuses a style attribute.
  setBar(fraction) {
    this.runningTarget.querySelector("[data-translate-progress-bar]").style.width = `${Math.round(fraction * 100)}%`
  }

  show(state) {
    this.idleTarget.hidden = state !== "idle"
    this.runningTarget.hidden = state !== "running"
    this.readyTarget.hidden = state !== "ready"
  }

  showStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}

// --- Jobs and pending boxes -------------------------------------------------------

// `box element -> { job, node }`: which request a field's box is waiting on
// and the pending box in it.
const pending = new WeakMap()

// Requests still out (or timed out and waiting for Try again), and the id the
// next one gets.
const liveJobs = new Set()
let jobCounter = 0

// Set while Use all presses its buttons, so the header refreshes once.
let muteChanges = false

// The seconds a request may take before the pending box gives up, as the
// layout's template declares it (`PendingComponent::TIMEOUT_SECONDS`).
function timeoutSeconds(template) {
  return Number(template.content.firstElementChild?.dataset.pendingTimeoutSeconds) || 25
}

// Puts a pending box in every field's box and starts the clock. A job is one
// POST: `fields` (all one record's), where it goes (`url`, `locale`, so a
// Try again from a box's own controller instance knows them) and its abort
// controller, which the run's signal also aborts.
function startJob(fields, { url, locale, signal, focus }) {
  const controller = new AbortController()
  const job = { id: ++jobCounter, fields, url, locale, signal, controller, over: false, timedOut: false, startedAt: Date.now(), timers: [] }
  liveJobs.add(job)
  signal?.addEventListener("abort", () => cancelJob(job), { once: true })

  const template = document.getElementById("translation-pending-template")
  if (template) {
    fields.forEach(({ box }) => {
      if (!box) return
      const node = template.content.firstElementChild.cloneNode(true)
      box.replaceChildren(node)
      pending.set(box, { job, node })
    })
    if (focus) fields[0]?.box?.querySelector("[data-translation-pending] button")?.focus()

    const interval = setInterval(() => {
      const seconds = Math.floor((Date.now() - job.startedAt) / 1000)
      fields.forEach(({ box }) => {
        const node = pending.get(box)?.node
        const elapsed = node?.isConnected ? node.querySelector("[data-pending-elapsed]") : null
        if (elapsed) elapsed.textContent = `${seconds}s`
      })
    }, 1000)
    const timeout = setTimeout(() => {
      job.timedOut = true
      clearInterval(interval)
      fields.forEach(({ box }) => {
        const node = pending.get(box)?.node
        if (!node?.isConnected) return
        node.querySelector("[data-pending-running]").hidden = true
        // Un-hide first, then write: a live region's text is announced only
        // when it changes while the region is rendered.
        node.querySelector("[data-pending-timeout]").hidden = false
        node.querySelector("[data-pending-timeout-message]").textContent = node.dataset.pendingTimeoutText
      })
    }, timeoutSeconds(template) * 1000)
    job.timers.push(() => clearInterval(interval), () => clearTimeout(timeout))
  }
  return job
}

// The clock stopped; the boxes are left to whatever answers (or Cancel).
function endJob(job) {
  job.timers.forEach((stop) => stop())
  job.timers = []
  liveJobs.delete(job)
}

// Stops the request and takes its pending boxes away. A box already holding
// a suggestion (this job answered it before, or another one did) is kept.
function cancelJob(job) {
  job.over = true
  job.controller.abort()
  endJob(job)
  job.fields.forEach(({ box, button }) => {
    // The busy Translate button is usable again at once (and can take focus).
    setBusy(button, false)
    if (isPendingOf(box, job)) box.replaceChildren()
  })
}

// Every job whose boxes are no longer on the page.
function cancelDetachedJobs() {
  liveJobs.forEach((job) => {
    if (job.fields.some(({ box }) => box && !box.isConnected)) cancelJob(job)
  })
}

// A Turbo visit replaces the page: nothing in flight is wanted any more.
document.addEventListener("turbo:before-visit", () => Array.from(liveJobs).forEach(cancelJob))

// The streams of one answer, each tagged with the job that asked, so that
// `turbo:before-stream-render` can refuse one whose box is no longer that
// job's pending box -- cancelled, replaced by Try again or gone with its page
// in the frame between the answer arriving and Turbo applying it.
function guardStreams(text, job) {
  const holder = document.createElement("template")
  holder.innerHTML = text
  holder.content.querySelectorAll("turbo-stream").forEach((stream) => stream.setAttribute("data-translate-job", String(job.id)))
  return holder.innerHTML
}

document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  const id = stream.getAttribute?.("data-translate-job")
  if (!id) return

  const entry = pending.get(document.getElementById(stream.getAttribute("target")))
  if (!entry || String(entry.job.id) !== id || entry.job.over || !entry.node.isConnected) event.preventDefault()
})

// Where focus goes when a box is emptied: the field's Translate / Suggest
// update button (the box's id is keyed by the input it fills).
function refocus(box) {
  const inputId = box?.id.replace(/^translation-suggestion-/, "")
  if (!inputId) return

  const wrappers = document.querySelectorAll(`[data-translate-input-id="${CSS.escape(inputId)}"]`)
  for (const wrapper of wrappers) {
    const button = wrapper.querySelector("button")
    if (button && !button.disabled) {
      button.focus()
      return
    }
  }
}

// What takes focus after Use: the input itself, or for a rich-text body (whose
// input is a hidden JSON field) its editable area.
function fieldFocusTarget(input) {
  if (input.type !== "hidden") return input
  return input.closest("[data-controller~='admin--rich-text--editor']")?.querySelector("[contenteditable='true']")
}

function isPendingOf(box, job) {
  const entry = box ? pending.get(box) : null
  return Boolean(entry && entry.job === job && entry.node.isConnected)
}

function jobOf(box) {
  const entry = box ? pending.get(box) : null
  return entry && entry.node.isConnected ? entry.job : null
}

// Something about the suggestions on the page changed: the header
// (`translate:changed@document->admin--translation--translate#refresh`) works out its state.
function announceChange() {
  if (muteChanges) return
  document.dispatchEvent(new CustomEvent("translate:changed"))
}

// Two animation frames: what Turbo does with a stream message.
async function settle() {
  await nextFrame()
  await nextFrame()
}

// Every field with a Translate wrapper whose input is empty now. A Suggest
// update wrapper is no empty field's: its field already has a translation.
function emptyFields() {
  return Array.from(document.querySelectorAll("[data-translate-field]:not([data-translate-mode='update'])")).filter(onScreen).map(describe).filter(isEmpty)
}

// A screen that holds several languages' fields at once (Settings' Site card)
// hides all but one language's panel (`[data-language-panel][hidden]`). The
// header's bulk run, Use all, Discard all and its counts act on what is on
// screen, i.e. the language being looked at -- never on a language whose panel
// is hidden. The editors have no such panel, so for them everything counts.
//
// Nor on a field someone else holds (live editing): a unit that says
// `data-editing-held`, or a form frozen as `fieldset.admin-held` or
// `data-editing-frozen` (a refused form turned read-only in place), is
// read-only and was never saved from here. Its empty fields are not counted or asked
// for, and a suggestion that reached it is neither counted nor applied by
// Use all nor discarded by Discard all.
function onScreen(element) {
  return !element.closest("[data-language-panel][hidden], [data-editing-held], [data-editing-frozen], fieldset.admin-held")
}

// A field's Translate wrapper, as the request needs it.
function describe(element) {
  const { translateRecordType, translateRecordId, translateField, translateInputId, translateKind, translateCharacters, translateMode } = element.dataset
  return {
    recordType: translateRecordType,
    recordId: translateRecordId,
    field: translateField,
    inputId: translateInputId,
    kind: translateKind,
    mode: translateMode === "update" ? "update" : "translate",
    characters: Number(translateCharacters) || 0,
    button: element.querySelector("[data-admin--translation--translate-target='button']"),
    // The box lives under the field's input, not in this wrapper (which sits
    // in the original's panel): found by the id the server also streams to.
    box: document.getElementById(`translation-suggestion-${translateInputId}`)
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
  dismiss.className = "cursor-pointer rounded-cs border border-field-line bg-surface px-2 py-0.5 text-ink hover:bg-sunken"
  dismiss.dataset.action = "admin--translation--translate#discard"
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
