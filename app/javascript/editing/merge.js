// THE MERGE RULE of live editing (live-editing spec §3.2), and nothing else:
//
//   A FORM THAT HOLDS CHANGES NOT YET SAVED IS NEVER REPLACED, AND NEITHER IS
//   ANYTHING ELSE OF ITS UNIT. EVERYTHING ELSE IS REPLACED BY WHAT WAS FETCHED.
//
// A UNIT (`data-editing-unit`) is what is replaced or kept as one: a block's
// card (in the list, as a section's panel, in a translation tab's group), a
// section's own settings form, the page settings panel, a post's form. A
// PART (`data-editing-part`, a section's tile) is not a unit: it is replaced
// like anything that holds no unsaved form, with two exceptions that keep what
// is not the answer's to take away -- a part that shows an alert with
// something in it (a notice nobody has dismissed) and a part that holds a kept
// unit are not replaced (`mergeUnits`). "Unsaved" is the caller's question
// (`unsaved(form)`): the write queue's own, asked of the form's autosave
// controller. This module reads no controller, so a test can hand it a plain
// predicate.
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
// of a kept unit (a section's card, its header, its body, its panels) stays
// too and is reconciled inside, level by level, matched by id. That is why
// every ancestor of a unit up to the list has an id. The one time a kept unit
// is moved is when two kept units changed places, and then it is the one that
// does not hold the focus (a unit taken out of the document drops the focus
// and its editor is built again).
//
// A BLOCK IS ONE SUBJECT AND HAS ONE FORM ON SCREEN AT A TIME. The subject is
// `data-editing-subject` ("block-<id>", on a card, a panel, a tile and a
// section's form; "record" on the page settings and a post's form), not the
// element's id: a tile and a top-level card of one block have the same id, and
// a panel and a card have the same inner ids. Three things can become of a
// kept unit:
//   - the answer has its subject in the same place (same id, a unit, in a
//     container of the same id): it is KEPT, and the answer's copy is dropped;
//   - the answer has its subject somewhere else (another container: a card
//     moved into a section or out of one, a panel moved to another section;
//     a panel moved to another lane of its section is home and simply kept) or in another shape (card <-> tile and panel): it is DISPLACED
//     (`moved`, and also in `kept`). It stays where it is and is not marked
//     gone, and EVERY element of that subject is removed from the answer
//     before drawing, so nothing of the block is drawn in its new place: no
//     second form, no tile that opens nothing, no id twice;
//   - the answer has no element of its subject: the block is gone (`gone`).
//     The unit stays, marked `data-editing-gone="true"` (taken back if the
//     answer has the element again), where it was: after the nearest
//     preceding sibling the answer still has, else first, and gone units keep
//     their order. A hidden panel of a kept unit whose tile is no longer on
//     screen (gone or displaced) is shown (`hidden = false`), or nothing on
//     screen would lead to the form that holds the person's text.
// `moved` is a subset of `kept` and never overlaps `gone`. `mergeUnits` sees
// only one block's answer, which names no container, so it reports a unit as
// moved only when the answer has the block in another SHAPE (card <-> tile and
// panel) and never for a change of container: that is the list fetch's to
// find.
// CONTRACT FOR THE CALLER: a displaced unit is not an error and needs no
// notice. The caller fetches the list again once that unit's form is no
// longer unsaved; the unit is then replaced like any clean one and the block
// takes its place. Until then this tab shows that one block where it was.
//
// What the person did to the screen and the server knows nothing of is put
// back around a merge (`withState`): which cards are collapsed, which panel
// of a section is open (a section reads that from its panels' `hidden`, so
// the panel's `hidden` is what is restored, and its tile's `aria-expanded`),
// and where the focus is. A CLEAN FORM THAT HAS THE FOCUS IS STILL REPLACED
// (a hold by someone else must be able to make it read-only): the focus goes
// back to the same control once it exists (an editor mounts a moment after
// its card arrives, so this waits for it, until the person focuses or
// presses somewhere else), and for an `input` or `textarea` the selection is
// put back too. In a rich-text field the caret and the selection are lost.
//
// `anchored(root, draw)` keeps the block the person is reading where it is on
// screen. It returns at once with what `draw` returned and goes on adjusting
// the scroll position for up to ANCHOR_WAIT (1.5 s), while the cards redrawn
// above it mount their editors and grow. The adjusting ends for good as soon
// as the scroller is anywhere but where it last put it (a key, the wheel, the
// browser following the caret, any script), when the time is up, or when
// `anchored` is called again: one adjusting at a time. It sets the scroll
// position of what scrolls the list, which is outside the list.
// `onlyChanged: true` (a CATCH-UP: first connect, reconnect, a document seen
// again) leaves alone what has not changed: a unit or part on screen that
// holds no unsaved text and carries the same `data-editing-version` as the
// answer's element of its id (same container, for a list) is the same element
// afterwards (if every element above it up to the root has an id) -- its open
// menu stays open, its editor is not mounted again --
// and is reported in `same`, not in `replaced` or `kept`. If the answer puts it
// somewhere else among its siblings it is still moved there. Without the
// option (a fetch a signal caused) everything is replaced as before. The
// version is the server's (`Editing.version`); an element with none is
// always replaced.
//
// Otherwise this module touches the document only inside the element it is
// handed, opens no connection, fetches nothing, raises no toast and knows no
// controller. Its tests are `test/system/admin/editing_merge_test.rb`.

const UNIT = "[data-editing-unit]"
const PANEL = "[data-admin--editor--section-target~='panel']"
const FOCUSABLE = "input:not([type=hidden]), textarea, select, button, a[href], summary, [tabindex]:not([tabindex='-1']), [contenteditable=true]"
// Set by a script on an element that stays, and not the server's to take away.
const RUNTIME = [ "inert", "data-picked", "data-notes-active", "data-editing-gone" ]
// How long a focus waits for a field that a controller is still mounting.
const FOCUS_WAIT = 3000
// How long the block being read is held in place while the cards above it grow.
const ANCHOR_WAIT = 1500
// The correction loop that is running, if any: one at a time.
let running = null

// Whether one of the unit's own forms is unsaved. A section's settings form
// is itself the unit; a card's forms are those not inside a nested unit.
export function holds(unit, unsaved) {
  const forms = unit.matches("form") ? [ unit ] : [ ...unit.querySelectorAll("form") ].filter((form) => form.closest(UNIT) === unit)
  return forms.some((form) => unsaved(form))
}

export function mergeList(list, fresh, { unsaved, onlyChanged = false, hold = null }) {
  const keep = new Set([ ...list.querySelectorAll(UNIT) ].filter((unit) => holds(unit, unsaved)))
  const moved = displace(list, fresh, keep)
  const same = onlyChanged ? unchanged(list, fresh, keep, { containers: true }) : []
  // Parts the caller holds (`hold`: a tile whose menu or dialog is open) stay
  // as they are, like `same` ones: left in place, never marked gone.
  const held = hold ? [ ...list.querySelectorAll("[data-editing-part]") ].filter((part) => !keep.has(part) && reachable(part, list) && hold(part)) : []
  const gone = []
  // A notice slot that shows an alert (a lost claim, a deleted block) stays
  // as it is, wherever it stands: a section's own slot is outside its unit,
  // and the answer's empty or "held" one must not take away what the person
  // has still to copy or discard.
  const notices = [ ...list.querySelectorAll("[data-editing-strip-slot]") ].filter((slot) => slot.querySelector("[role=alert]:not(:empty)") && reachable(slot, list))
  withState(list, () => {
    reconcile(list, [ ...fresh.children ], keep, new Set(moved), gone, new Set([ ...same, ...held, ...notices ]))
    for (const unit of keep) if (!gone.includes(unit)) unit.removeAttribute("data-editing-gone")
    for (const unit of keep) if (unit.matches(PANEL) && unit.hidden && !tileOf(list, unit)) unit.hidden = false
  })
  return { kept: [ ...keep, ...held ], gone, moved, same }
}

// Whether every ancestor of `element` up to `root` has an id: the merge
// reconciles level by level and matches by id, so something is left in place
// only where the levels above it can be matched (a unit's are, by design; a
// part such as a tile may sit under a wrapper with none, and is then replaced).
const reachable = (element, root) => {
  for (let up = element.parentElement; up && up !== root; up = up.parentElement) if (!up.id) return false
  return true
}

// The units and parts on screen, outside `keep`, whose version is that of the
// answer's element of the same id and shape (and container, for a list).
function unchanged(root, fresh, keep, { containers }) {
  const versions = new Map()
  for (const twin of fresh.querySelectorAll("[data-editing-version]")) {
    if (twin.id) versions.set(`${twin.id}|${twin.matches(UNIT)}`, twin)
  }
  return [ ...root.querySelectorAll("[data-editing-version]") ].filter((live) => {
    if (keep.has(live) || !live.id || !reachable(live, root)) return false
    const twin = versions.get(`${live.id}|${live.matches(UNIT)}`)
    return Boolean(twin) && twin.dataset.editingVersion === live.dataset.editingVersion &&
      (!containers || containerKey(twin, fresh) === containerKey(live, root))
  })
}

// `fresh`'s children are the answer for some parts of `root`. A child with
// no element of its id and shape on screen is `missing` (the caller fetches
// the list); so is a part that holds a kept unit, which cannot be replaced
// without taking the unit away and is not (the list merge reconciles around
// it).
export function mergeUnits(root, fresh, { unsaved, onlyChanged = false, hold = null }) {
  const result = { replaced: [], kept: [], missing: false, moved: [], same: [] }
  withState(root, () => {
    const keep = new Set([ ...root.querySelectorAll(UNIT) ].filter((unit) => holds(unit, unsaved)))
    for (const unit of displace(root, fresh, keep, { containers: false })) { result.moved.push(unit); result.kept.push(unit) }
    for (const twin of [ ...fresh.children ]) {
      const live = twin.id ? document.getElementById(twin.id) : null
      if (!live || !root.contains(live) || live === root || live.matches(UNIT) !== twin.matches(UNIT)) { result.missing = true; continue }
      if (keep.has(live)) { result.kept.push(live); continue }
      if (!live.matches(UNIT) && hold?.(live)) { result.kept.push(live); continue }
      if (onlyChanged && live.dataset.editingVersion && live.dataset.editingVersion === twin.dataset.editingVersion) { result.same.push(live); continue }
      // A notice the person has not dealt with ("Changed elsewhere", lost
      // work) is theirs to dismiss: a part that shows one is not replaced.
      if (!live.matches(UNIT) && live.querySelector("[role=alert]:not(:empty)")) { result.kept.push(live); continue }
      if ([ ...keep ].some((unit) => live.contains(unit))) { result.missing = true; continue }
      live.replaceWith(twin)
      result.replaced.push(twin)
    }
  })
  return result
}

// Runs `draw` and holds the block the person is in, or else the first one in
// view, where it was on screen: now, and again while the redrawn cards above
// it mount their editors (an editor's field is empty until its controller
// connects and then at least a field tall), until the person scrolls or the
// time is up. The anchor is looked up again by id each time, and the next one
// in view stands in for one that was removed.
export function anchored(root, draw) {
  running = null
  const scroller = scrollerOf(root)
  const view = viewOf(scroller)
  const inFocus = document.activeElement?.closest?.("[data-block-id], [data-editing-unit]")
  const visible = [ ...root.querySelectorAll("[data-block-id]") ].filter((card) => {
    const rect = card.getBoundingClientRect()
    return !card.closest("[hidden]") && rect.bottom > view.top && rect.top < view.bottom
  })
  const topped = (card) => card.getBoundingClientRect().top >= view.top - 0.5
  const chosen = [ ...(inFocus && root.contains(inFocus) ? [ inFocus ] : []), ...visible.filter(topped), ...visible.filter((card) => !topped(card)) ].slice(0, 6)
  const anchors = chosen.map((card) => ({ element: card, id: card.id, top: card.getBoundingClientRect().top }))

  const result = draw()
  if (!anchors.length) return result

  const find = () => {
    for (const anchor of anchors) {
      const now = anchor.element.isConnected && root.contains(anchor.element) ? anchor.element : anchor.id && document.getElementById(anchor.id)
      if (now && root.contains(now)) return { now, top: anchor.top }
    }
    return null
  }
  const correct = () => {
    const found = find()
    if (!found) return
    const off = found.now.getBoundingClientRect().top - found.top
    if (Math.abs(off) >= 1) scroller.scrollTop += off
  }
  correct()

  // The loop writes the scroll position only while the scroller is where the
  // loop itself last put it: anything else that moved it (a key, a wheel, the
  // browser following the caret, a script) ends the loop for good. A new call
  // ends the one before it.
  const mine = { ended: false }
  running = mine
  let last = scroller.scrollTop
  const until = performance.now() + ANCHOR_WAIT
  const step = () => {
    if (mine.ended || running !== mine || performance.now() > until || scroller.scrollTop !== last) return
    correct()
    last = scroller.scrollTop
    requestAnimationFrame(step)
  }
  requestAnimationFrame(step)
  return result
}

const carries = (element, keep, extra) => [ keep, extra ].some((set) => set.has(element) || [ ...set ].some((unit) => element.contains(unit)))

const tileOf = (root, panel) => root.querySelector(`[data-editing-part][data-block-id="${panel.dataset.blockId}"]`)

// A parent's id, with the element the merge was handed standing for "the list".
const containerKey = (element, root) => element.parentElement === root ? "" : (element.parentElement?.id || "")

// The kept units whose subject the answer has somewhere other than where the
// unit is (`containers`: a list answer has its containers, so a change of
// container is seen; a one-block answer has none and only the id and the shape
// are compared). Every element of that subject is taken out of the answer, so the
// block is not drawn in its new place while this one has unsaved text.
function displace(root, fresh, keep, { containers = true } = {}) {
  const moved = []
  for (const unit of keep) {
    const subject = unit.dataset.editingSubject
    if (!subject) continue
    const copies = [ ...fresh.querySelectorAll(`[data-editing-subject="${subject}"]`) ]
    if (!copies.length) continue
    const home = copies.some((copy) => copy.id === unit.id && copy.matches(UNIT) && (!containers || containerKey(copy, fresh) === containerKey(unit, root)))
    if (home) continue
    copies.forEach((copy) => copy.remove())
    moved.push(unit)
  }
  return moved
}

// Makes `container`'s children those of `fresh`, in that order, around what stays.
// `keep` are the units that hold unsaved text: only those can be gone. `extra`
// are what stays for another reason (same version, held by the caller): a clean
// element is never marked gone, an answer that lacks its level removes it only
// through its ancestors being removed.
function reconcile(container, fresh, keep, moved, gone, extra = new Set()) {
  const wanted = new Set(fresh.map((each) => each.id).filter(Boolean))
  // What stays although the answer has no such element, each with the id of
  // the nearest sibling before it that the answer does have (null: first).
  const stays = []
  let anchor = null
  for (const child of [ ...container.children ]) {
    const survives = Boolean(child.id) && wanted.has(child.id)
    // Gone from the answer, and nothing in it holds unsaved text: removed,
    // although a clean element of `extra` is in it.
    if (!carries(child, keep, extra) || (!survives && !carries(child, keep, new Set()))) {
      child.remove()
      if (survives) anchor = child.id
    } else if (survives) {
      anchor = child.id
    } else {
      stays.push({ element: child, anchor })
      for (const unit of keep) if ((unit === child || child.contains(unit)) && !moved.has(unit) && !gone.includes(unit)) { unit.dataset.editingGone = "true"; gone.push(unit) }
    }
  }

  // The order the container ends in: the stayers that belong first, then each
  // of the answer's elements followed by the stayers that were behind it.
  const order = stays.filter((stay) => stay.anchor === null).map((stay) => stay.element)
  for (const twin of fresh) {
    const live = twin.id ? [ ...container.children ].find((child) => child.id === twin.id) : null
    if (live && !keep.has(live) && !extra.has(live)) {
      syncAttributes(live, twin)
      reconcile(live, [ ...twin.children ], keep, moved, gone, extra)
    }
    order.push(live || twin)
    if (twin.id) for (const stay of stays) if (stay.anchor === twin.id) order.push(stay.element)
  }

  let after = null
  for (const node of order) {
    let expected = after ? after.nextElementSibling : container.firstElementChild
    // Whoever has the focus is not the one taken out of the document: what
    // stands in its way is moved to the end instead (and put in its own place
    // when its turn comes).
    while (node !== expected && expected && node.contains(document.activeElement)) {
      container.appendChild(expected)
      expected = after ? after.nextElementSibling : container.firstElementChild
    }
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
  const open = [ ...root.querySelectorAll(`${PANEL}:not([hidden])`) ].map((panel) => panel.id).filter(Boolean)
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

const signature = (element) => [ element.tagName, element.getAttribute("type"), element.getAttribute("name"), element.getAttribute("aria-label"), element.isContentEditable ].join("|")

// Where the focus is, as something that survives its element being replaced:
// the element's own id, or the nearest ancestor with one and the control's
// place among that ancestor's controls, with what kind of control it is.
function focusOf(root) {
  const element = document.activeElement
  if (!element || element === document.body || !root.contains(element)) return null
  const own = Boolean(element.id)
  const holder = own ? element : element.closest("[id]")
  if (!holder) return null
  const index = own ? -1 : [ ...holder.querySelectorAll(FOCUSABLE) ].indexOf(element)
  if (!own && index < 0) return null
  let selection = null
  try { if (typeof element.selectionStart === "number") selection = [ element.selectionStart, element.selectionEnd ] } catch { selection = null }
  return { element, id: holder.id, own, index, kind: signature(element), selection }
}

function restoreFocus(root, focus) {
  if (!focus || document.activeElement === focus.element) return
  // Something else has it already (the person moved on, or a menu took it).
  if (document.activeElement && document.activeElement !== document.body) return
  const find = () => {
    const holder = document.getElementById(focus.id)
    if (!holder || !root.contains(holder)) return null
    const target = focus.own ? holder : holder.querySelectorAll(FOCUSABLE)[focus.index]
    return target && signature(target) === focus.kind ? target : null
  }
  const attempt = () => {
    const target = find()
    if (!target) return false
    target.focus({ preventScroll: true })
    if (focus.selection && typeof target.setSelectionRange === "function") {
      try { target.setSelectionRange(...focus.selection) } catch { /* a control without a selection */ }
    }
    return true
  }
  if (attempt()) return

  // The field is not there yet: a controller mounts it (the rich-text editor
  // does, a moment after its card arrives). Wait for it, until the person
  // focuses or presses somewhere else, or the wait is over.
  const finish = () => {
    observer.disconnect()
    clearTimeout(timer)
    removeEventListener("pointerdown", finish, true)
    removeEventListener("focusin", finish, true)
  }
  const observer = new MutationObserver(() => { if (attempt()) finish() })
  const timer = setTimeout(finish, FOCUS_WAIT)
  addEventListener("pointerdown", finish, true)
  addEventListener("focusin", finish, true)
  observer.observe(root, { childList: true, subtree: true })
}

function viewOf(scroller) {
  if (scroller === document.scrollingElement) return { top: 0, bottom: innerHeight }
  const rect = scroller.getBoundingClientRect()
  return { top: rect.top, bottom: rect.bottom }
}

function scrollerOf(element) {
  for (let each = element.parentElement; each; each = each.parentElement) {
    const overflow = getComputedStyle(each).overflowY
    if ((overflow === "auto" || overflow === "scroll") && each.scrollHeight > each.clientHeight) return each
  }
  return document.scrollingElement
}
