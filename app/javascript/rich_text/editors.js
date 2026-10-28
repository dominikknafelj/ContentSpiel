// Which Tiptap editor an `admin--rich-text--editor` element holds, for a
// controller AROUND it that works on the same document: the Table block's
// grid controls (`admin--editor--table`), which insert, move and delete rows
// and columns through the editor's own commands, so every change is an
// editor transaction and is written into the hidden input, and autosaved,
// exactly as typing is.
//
// The scripts' rule for one controller reaching another is an event or a
// small shared module, never an outlet: this is the module, and the editor
// controller also dispatches `admin--rich-text--editor:attached` and
// `:detached` on its element (bubbling), which is how a controller around it
// hears of an editor that came after it (a card moved in the list, or
// replaced by a Turbo Stream, mounts a new editor). A controller that
// connects after the editor asks `editorOf` instead. A WeakMap: an element
// that leaves the document takes its entry with it.
const editors = new WeakMap()

export function attach(element, editor) {
  editors.set(element, editor)
}

export function detach(element) {
  editors.delete(element)
}

export function editorOf(element) {
  return (element && editors.get(element)) || null
}
