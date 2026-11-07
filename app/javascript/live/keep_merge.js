// THE MERGE CORE that notes (`notes/merge.js`) and live editing
// (`editing/merge.js`) both draw a fetched answer with. Each of them owns its
// own rule of what must stay ("what is typed is never touched", "a form that
// holds changes not yet saved is never replaced") and says it as a set of
// elements, `kept`; this file owns only the mechanics of drawing an answer
// around them:
//
//   keepMerge(container, fresh, { kept, within, sync, place }) -> { orphans }
//
// `container` is the element on screen; `fresh` an Array of the answer's
// elements for its children, not in the document (they are moved in, never
// copied).
//
// A KEPT ELEMENT IS THE SAME ELEMENT AFTERWARDS, AND IS NOT MOVED. Moving an
// element takes it out of the document and puts it back: its Stimulus
// controllers disconnect and connect, a rich-text editor is mounted again, a
// file field loses its files and the caret is gone, under someone who is
// typing. So the container is not replaced with the kept elements put back
// into it; it is RECONCILED AROUND them: what does not stay is removed, the
// answer's elements are inserted before, between and after what stays, in
// the answer's order. The one time a kept element is moved is when two kept
// elements changed places, and then it is the one that does not hold the
// focus (what stands in the focused one's way is moved instead).
//
// MATCHED BY ID, LEVEL BY LEVEL. For each element of `container`, its TWIN is
// the answer's element of the same id among `fresh` (none without an id):
//   - a kept element with a twin takes the twin's place, and the twin is
//     dropped;
//   - any other element with a twin for which `within(element, twin)` is true
//     (it holds something that stays) stays too: its attributes are brought
//     to the twin's through `sync(live, twin)` (none without `sync`), and its
//     children are reconciled against the twin's by the same rule, one level
//     down. That is why every element between `container` and a kept element
//     needs an id: one without is not matched, and is removed or left as an
//     orphan;
//   - any other element with a twin is replaced by the twin.
// An element without a twin stays when it is kept or `within(element, null)`
// is true, and is then an ORPHAN, returned in `orphans` (at every level) for
// the caller to say what became of it; any other is removed. An orphan stands
// before `place(orphan, fresh)` when `place` is given (at the end when that
// is null), and otherwise after the nearest element before it whose id the
// answer has (first when there is none); orphans keep their order.
//
// It decides by ids and the caller's sets and predicates, never by comparing
// markup: a fetched answer is not byte-equal to what is on screen even when
// nothing changed (a fresh CSRF token, an editor's own elements). It touches
// the document only inside `container`, and knows no feature: its tests are
// the "keepMerge" cases of `test/system/admin/editor_modules_test.rb`, and
// both features' merge tests run through it.

export function keepMerge(container, fresh, { kept, within = () => false, sync = null, place = null }) {
  const orphans = []
  reconcile(container, fresh, { kept, within, sync, place }, orphans)
  return { orphans }
}

function reconcile(container, fresh, options, orphans) {
  const { kept, within, sync, place } = options
  const twins = new Map()
  for (const twin of fresh) if (twin.id && !twins.has(twin.id)) twins.set(twin.id, twin)

  // What stays although the answer has no element of its id, each with the
  // id of the nearest sibling before it that the answer does have (null:
  // none), and the matched elements that stay.
  const stays = []
  const matched = new Map()
  let anchor = null
  for (const child of [ ...container.children ]) {
    const twin = (child.id && twins.get(child.id)) || null
    if (kept.has(child) || within(child, twin)) {
      // Of two elements of one id on screen, the first is the one matched.
      if (twin && !matched.has(child.id)) matched.set(child.id, child)
      else { stays.push({ element: child, anchor }); orphans.push(child) }
    } else {
      child.remove()
    }
    if (twin) anchor = child.id
  }

  // The order the container ends in: the answer's elements, each followed
  // by the orphans that were behind it, with the orphans that had nothing
  // before them first -- or, with `place`, each orphan before its place, and
  // at the end when it has none in the answer.
  const placed = place ? new Map(stays.map(({ element }) => [ element, place(element, fresh) ])) : null
  const order = place ? [] : stays.filter((stay) => stay.anchor === null).map((stay) => stay.element)
  for (const twin of fresh) {
    const live = (twin.id && matched.get(twin.id)) || null
    if (live && !kept.has(live)) {
      sync?.(live, twin)
      reconcile(live, [ ...twin.children ], options, orphans)
    }
    if (place) for (const [ element, at ] of placed) if (at === twin) order.push(element)
    order.push(live || twin)
    if (!place && twin.id) for (const stay of stays) if (stay.anchor === twin.id) order.push(stay.element)
  }
  if (place) for (const [ element, at ] of placed) if (!fresh.includes(at)) order.push(element)

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
