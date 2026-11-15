// After Turbo's copy of the page. A controller that takes its frame back at
// `turbo:before-cache` (so the copy Turbo keeps holds the server's markup)
// is not always leaving: a `#content` frame navigation promoted to a visit
// (System status's link to Draw diagrams) caches the page it has just drawn,
// so the take-back lands on the controller that connected a moment before
// and is still showing. `afterSnapshot` runs
// `callback` once the copy is made, for the controller to build its frame
// again if it is still in the document.
//
// The copy is made one event-loop tick after the event: `View#cacheSnapshot`
// (turbo-rails 2.0.23) dispatches `turbo:before-cache`, awaits a
// `setTimeout(0)` and then clones. A timeout set inside the listener is
// queued before Turbo's, so the callback waits a second one, which runs after
// the clone. A Turbo upgrade means re-reading `cacheSnapshot`;
// `test/system/admin/draw_diagrams_test.rb` ("reached by a link", "the frame
// is taken back before cache") and `diagram_block_test.rb` ("the frame is
// gone after leaving the editor…") fail when the order changes.
export function afterSnapshot(callback) {
  setTimeout(() => setTimeout(callback, 0), 0)
}
