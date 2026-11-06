// The SortableJS side of the page editor's drag: one set of options for the
// list and every lane, and the clone that follows the pointer.

// SortableJS is fetched when a controller that drags connects, never with the
// screen: `preload: false` in config/importmap.rb, and no static import
// anywhere (`test/lib/admin_design_rules_test.rb`). Resolves to its default
// export; the module is cached, so a second call costs nothing.
//
// The caller's contract: a controller sets `data-sortable="pending"` on its
// element in `connect` and `"ready"` once its Sortables exist (what
// `await_sortables` in the browser tests waits on), and makes none when its
// element left the document before the import resolved.
//
// `window.contentSpielSortableLoader` is the one test seam: a function
// returning the module's promise, set only by a browser test that must settle
// the import itself.
export function loadSortable() {
  const load = window.contentSpielSortableLoader || (() => import("sortablejs"))
  return load().then((module) => module.default)
}

// `put` is what the container takes from another one (`true` for the list,
// `accepts` for a lane); `onStart` and `onEnd` are the controller's, because
// the drag's state (`dragging`, the snapshot taken at its start) is.
//
// `onEnd` is called once, on the Sortable the drag began in, wherever it
// ended: `event.from` is that container, and the item's parent the one it is
// in now.
export function sortableOptions({ put, onStart, onEnd }) {
  return {
    // One group, so a drag can end in another container than it began in.
    group: { name: "blocks", put },
    draggable: "[data-block-id]",
    // A card's handle and a tile's grip. The grip is a `<span>` for the
    // pointer only (`Admin::EditorScreen::BlockTileComponent`).
    handle: ".admin-block-card__handle, .admin-block-tile__grip",
    animation: 150,
    // The drag look (handoff §9 A9): a dashed placeholder where the card
    // would land, and the lifted card itself with a shadow.
    ghostClass: "admin-drag-ghost",
    chosenClass: "admin-drag-chosen",
    // SortableJS's own pointer-driven drag instead of native HTML5
    // drag-and-drop, for the reason `admin--pages--tree` spells out: the handle
    // is a `<button>`, and Firefox never starts a native drag from one.
    // The fallback drags a clone of the card (`fallbackClass`), appended
    // to `<body>` -- so the list's direct children stay exactly the cards.
    // `fallbackTolerance` keeps a shaky click on the handle from lifting
    // the card.
    forceFallback: true,
    fallbackOnBody: true,
    fallbackClass: "admin-drag-fallback",
    fallbackTolerance: 3,
    onStart,
    onEnd
  }
}

// The dragged clone (`Sortable.ghost`) is a deep copy of a card: its forms'
// autosave and rich-text controllers, its `card` target and every id would
// otherwise exist twice for as long as the drag lasts -- a second Tiptap
// editor booting in the clone, a Turbo Stream finding the copy by id.
// SortableJS fires `onStart` synchronously right after appending the clone,
// before Stimulus's mutation observer has seen it, so stripping the wiring
// there means nothing ever connects: the clone is a picture of the card, no
// more.
export function makeCloneInert(clone) {
  if (!clone) return

  for (const element of [clone, ...clone.querySelectorAll("*")]) {
    for (const { name } of Array.from(element.attributes)) {
      if (name === "id" || name === "data-controller" || name === "data-action" || /^data-.+-target$/.test(name)) {
        element.removeAttribute(name)
      }
    }
  }
}
