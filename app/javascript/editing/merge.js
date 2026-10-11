// THE MERGE RULE of live editing (live-editing spec §3.2), and nothing else:
//
//   A FORM THAT HOLDS CHANGES NOT YET SAVED IS NEVER REPLACED, AND NEITHER IS
//   ANYTHING ELSE OF ITS UNIT. EVERYTHING ELSE IS REPLACED BY WHAT WAS FETCHED.
//
// A UNIT (`data-editing-unit`) is what is replaced or kept as one: a block's
// card (in the list, as a section's panel, in a translation tab's group), a
// section's own settings form, the page settings panel, a post's form. A
// PART (`data-editing-part`, a section's tile) holds no form and is always
// replaced. "Unsaved" is the caller's question (`unsaved(form)`): the write
// queue's own, asked of the form's autosave controller. This module reads no
// controller, so a test can hand it a plain predicate.
//
// DECIDE BY IDS, SUBJECTS AND STATE, NEVER BY COMPARING HTML. A fetched
// fragment is not byte-equal to what is on screen even when nothing changed
// (every form carries a fresh masked CSRF token), and a mounted editor has
// added its own elements to the one on screen. Nothing here compares markup.
//
// A KEPT UNIT IS THE SAME ELEMENT AFTERWARDS, AND IS NOT MOVED. Moving an
// element takes it out of the document and puts it back: its Stimulus
// controllers disconnect and connect, the rich-text editor is mounted again
// and the caret is gone, under someone who is typing. So the list is not
// replaced and the kept units put back into it; the list is RECONCILED
// AROUND them: what does not stay is removed, what was fetched is inserted
// before, between and after what stays, and an element that is the ancestor
// of a kept unit (a section's card, its body, its panels, its header) stays
// too and is reconciled inside, level by level, matched by id. That is why
// every ancestor of a unit up to the list has an id. The one time a kept
// unit is moved is when two kept units changed places.
//
// A kept unit the answer no longer has (its block was deleted) stays where
// it is, marked `data-editing-gone`; the caller puts the notice on it.
//
// What the person did to the screen and the server knows nothing of is put
// back around a merge (`withState`): which cards are collapsed, which panel
// of a section is open (a section reads that from its panels' `hidden`, so
// the panel's `hidden` is what is restored, and its tile's `aria-expanded`),
// and where the focus is.
//
// This module touches the document only inside the element it is handed. It
// opens no connection, fetches nothing, raises no toast and knows no
// controller. Its tests are `test/system/admin/editing_merge_test.rb`.

const UNIT = "[data-editing-unit]"
const FOCUSABLE = "input:not([type=hidden]), textarea, select, button, [contenteditable=true]"
// Set by a script on an element that stays, and not the server's to take away.
const RUNTIME = [ "inert", "data-picked", "data-notes-active", "data-editing-stays", "data-editing-gone" ]
// How long a focus waits for a field that a controller is still mounting.
const FOCUS_WAIT = 3000

// Whether one of the unit's own forms is unsaved. A section's settings form
// is itself the unit; a card's forms are those not inside a nested unit.
export function holds(unit, unsaved) {
  const forms = unit.matches("form") ? [ unit ] : [ ...unit.querySelectorAll("form") ].filter((form) => form.closest(UNIT) === unit)
  return forms.some((form) => unsaved(form))
}

export function mergeList(list, fresh, { unsaved }) {
  const keep = new Set([ ...list.querySelectorAll(UNIT) ].filter((unit) => unit.id && holds(unit, unsaved)))
  const gone = []
  withState(list, () => reconcile(list, [ ...fresh.children ], keep, gone))
  return { kept: [ ...keep ], gone }
}

export function mergeUnits(root, fresh, { unsaved }) {
  const result = { replaced: [], kept: [], missing: false }
  withState(root, () => {
    for (const twin of [ ...fresh.children ]) {
      const live = twin.id ? document.getElementById(twin.id) : null
      if (!live || !root.contains(live) || live === root || live.matches(UNIT) !== twin.matches(UNIT)) { result.missing = true; continue }
      if (live.matches(UNIT) && holds(live, unsaved)) { result.kept.push(live); continue }
      // A notice the person has not dealt with ("Changed elsewhere", lost
      // work) is theirs to dismiss: a part that shows one is not replaced.
      if (!live.matches(UNIT) && live.querySelector("[role=alert]")) { result.kept.push(live); continue }
      // A unit that is not the one asked about but holds a kept unit inside
      // it would take that unit away: the answer for it is not drawn.
      if (live.querySelector(UNIT) && [ ...live.querySelectorAll(UNIT) ].some((unit) => unit.id && holds(unit, unsaved))) { result.kept.push(live); continue }
      live.replaceWith(twin)
      result.replaced.push(twin)
    }
  })
  return result
}

// Runs `draw` and puts the block the person is in, or else the first one in
// view, back where it was on screen.
export function anchored(root, draw) {
  const inFocus = document.activeElement?.closest?.("[data-block-id], [data-editing-unit]")
  const anchor = (inFocus && root.contains(inFocus) && inFocus) ||
    [ ...root.querySelectorAll("[data-block-id]") ].find((card) => !card.closest("[hidden]") && card.getBoundingClientRect().bottom > 0)
  const top = anchor?.getBoundingClientRect().top
  const result = draw()
  const now = anchor && (anchor.isConnected ? anchor : anchor.id && document.getElementById(anchor.id))
  if (now && top !== undefined && root.contains(now)) {
    const moved = now.getBoundingClientRect().top - top
    if (moved !== 0) scrollerOf(root).scrollTop += moved
  }
  return result
}

const carries = (element, keep) => keep.has(element) || [ ...keep ].some((unit) => element.contains(unit))

// Makes `container`'s children those of `fresh`, in that order, around what stays.
function reconcile(container, fresh, keep, gone) {
  const wanted = new Set(fresh.map((each) => each.id).filter(Boolean))
  for (const child of [ ...container.children ]) {
    if (!carries(child, keep)) { child.remove(); continue }
    if (wanted.has(child.id)) { child.removeAttribute("data-editing-stays"); continue }
    // It stays although the answer has no such element: its block is gone.
    child.setAttribute("data-editing-stays", "true")
    for (const unit of keep) if ((unit === child || child.contains(unit)) && !gone.includes(unit)) { unit.dataset.editingGone = "true"; gone.push(unit) }
  }
  const keptIds = new Set([ ...keep ].map((unit) => unit.id))
  let after = null
  for (const twin of fresh) {
    const live = twin.id ? [ ...container.children ].find((child) => child.id === twin.id) : null
    // A kept unit that is somewhere else in the document (its block was moved
    // to another container) is still the one on screen: the answer's copy of
    // its id is not drawn a second time.
    if (!live && twin.id && keptIds.has(twin.id)) continue
    if (live && !keep.has(live)) {
      syncAttributes(live, twin)
      reconcile(live, [ ...twin.children ], keep, gone)
    } else if (!live) {
      for (const id of keptIds) for (const copy of twin.querySelectorAll(`[id="${CSS.escape(id)}"]`)) copy.remove()
    }
    const node = live || twin
    let expected = after ? after.nextElementSibling : container.firstElementChild
    while (expected && expected !== node && expected.hasAttribute("data-editing-stays")) expected = expected.nextElementSibling
    if (node !== expected) container.insertBefore(node, expected)
    after = node
  }
}

function syncAttributes(live, twin) {
  for (const { name } of [ ...live.attributes ]) if (!twin.hasAttribute(name) && !RUNTIME.includes(name)) live.removeAttribute(name)
  for (const { name, value } of [ ...twin.attributes ]) if (live.getAttribute(name) !== value) live.setAttribute(name, value)
}

function withState(root, draw) {
  const collapsed = [ ...root.querySelectorAll("[data-block-body].hidden") ].map((body) => body.id).filter(Boolean)
  const open = [ ...root.querySelectorAll("[data-admin--editor--section-target~='panel']:not([hidden])") ].map((panel) => panel.id).filter(Boolean)
  const focus = focusOf(root)

  draw()

  for (const id of collapsed) {
    const body = document.getElementById(id)
    if (!body || !root.contains(body)) continue
    body.classList.add("hidden")
    root.querySelector(`[aria-controls="${CSS.escape(id)}"]`)?.setAttribute("aria-expanded", "false")
  }
  for (const id of open) {
    const panel = document.getElementById(id)
    if (!panel || !root.contains(panel)) continue
    panel.hidden = false
    root.querySelector(`.admin-block-tile__face[aria-controls="${CSS.escape(id)}"]`)?.setAttribute("aria-expanded", "true")
  }
  restoreFocus(root, focus)
}

// Where the focus is, as something that survives its element being replaced:
// the nearest ancestor with an id and the control's place among that
// ancestor's controls.
function focusOf(root) {
  const element = document.activeElement
  if (!element || element === document.body || !root.contains(element)) return null
  const holder = element.id ? element : element.closest("[id]")
  if (!holder) return null
  return { element, id: holder.id, index: element === holder ? -1 : [ ...holder.querySelectorAll(FOCUSABLE) ].indexOf(element), editable: element.isContentEditable }
}

function restoreFocus(root, focus) {
  if (!focus || focus.element.isConnected) return
  const find = () => {
    const holder = document.getElementById(focus.id)
    if (!holder || !root.contains(holder)) return null
    const target = focus.index < 0 ? holder : holder.querySelectorAll(FOCUSABLE)[focus.index]
    return target && target.isContentEditable === focus.editable ? target : null
  }
  const attempt = () => {
    const target = find()
    if (target) target.focus({ preventScroll: true })
    return Boolean(target)
  }
  if (attempt()) return

  // The field is not there yet: a controller mounts it (the rich-text editor
  // does, a moment after its card arrives). Wait for it, until the person
  // goes somewhere else or the wait is over.
  const observer = new MutationObserver(() => {
    const moved = document.activeElement && document.activeElement !== document.body
    if (moved || attempt()) observer.disconnect()
  })
  observer.observe(root, { childList: true, subtree: true })
  setTimeout(() => observer.disconnect(), FOCUS_WAIT)
}

function scrollerOf(element) {
  for (let each = element.parentElement; each; each = each.parentElement) {
    const overflow = getComputedStyle(each).overflowY
    if ((overflow === "auto" || overflow === "scroll") && each.scrollHeight > each.clientHeight) return each
  }
  return document.scrollingElement
}
