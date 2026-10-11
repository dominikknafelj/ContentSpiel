// One screen's writes, one at a time (cs-studio design pass round 2, Task 6
// fix round 1).
//
// WHY. A page editor's forms write one record each, and a few of them share
// state on the page: a hidden `base_updated_at` field per autosave form, which
// a save's answer moves forward. Two requests sent from the same screen at the
// same moment (the page form and every block form debounce on the same tick
// after "Use all"; or a block's answer still in flight on a slow connection
// when the next form sends) would both carry the base the first answer is about
// to replace, and the second would be refused against nothing but its own
// editor. The page settings form's base is its own (`Page#settings_changed_at`)
// and a block write no longer moves it, but the tree's move of the open page
// still does (`X-Page-Base-Updated-At`, below).
//
// WHAT. This queue makes a request be SENT only after the previous one's
// answer has been received AND its base values written into the hidden fields
// (`syncBases`, synchronous -- `Turbo.renderStreamMessage` applies a stream on
// the next frame, too late for a request sent straight after). Each request
// therefore reads the freshest bases at SEND time (inside the task), never at
// queue time. The server's base mechanism is unchanged.
//
// Everything that writes goes through here: every `admin--saving--autosave`
// form (`enqueue`), block reorder (`enqueue`), Turbo's own block form
// submissions -- add, duplicate, delete, the Undo toast (`holdTurboRequest`)
// -- and, from outside the editor's forms, the page tree's move (`enqueue`)
// and its Undo toast (`holdTurboRequest`). Only the tree's move sends
// `X-Page-Base-Updated-At`: moving the page that is open moves its
// `settings_changed_at` like any other save of its own columns
// (`admin--pages--tree`).
//
// THE RULE (fix round 3; final fix wave 1): nothing that REPLACES AN EDITOR
// starts until the queue is empty. Three kinds of thing replace an editor:
// - a Turbo visit (a sidebar link, a locale switch, Reload);
// - the editor header's actions (Publish, Unpublish, Schedule, Move to trash,
//   which redirect), and any other Turbo form submission made while something
//   is outstanding (the Undo toast's button, New page / New post, sign out):
//   see "TURBO FORM SUBMISSIONS" in `frame_hold.js`;
// - a Turbo FRAME navigation inside `#content` (the page tree's links, the
//   header's breadcrumb, its menu's Activity link). Turbo fetches and RENDERS
//   the frame first and only then proposes the promoted visit, so by
//   `turbo:before-visit` the editor's forms are long gone -- their debounce
//   timers cleared, a save's follow-up skipped. This one is held twice: its
//   REQUEST (so the answer is not older than the saves it waited for -- the
//   link may lead back to the same record) and its RENDER (for edits that
//   land while the request is on its way). See "FRAME NAVIGATIONS" in
//   `frame_hold.js`.
// All of them wait on `drained()`: a promise that resolves when no task is
// queued or in flight AND no autosave form has a debounced, queued, in-flight
// or retrying save -- forms are asked to send what they hold (`flush()`) in a
// loop until a pass finds nothing new, bounded by `DRAIN_LIMIT_MS` -- the
// whole wait, including the wait for a request already on the wire (fix round
// 4: a save that never answers no longer holds a visit for its own 30 s
// timeout). It resolves to whether every form ended CLEAN (last answer a
// success, not paused by a 409, not failed).
// So no edit is dropped on the way out: before this, a queued save was either
// cancelled by the visit (lost silently) or sent on a base the action had just
// moved (refused). The header action additionally refuses to run when a form
// ended unclean (`admin--saving--queue-hold`): its redirect would throw away the very
// text a 409 bar promised to keep. A plain visit or frame navigation still
// goes on (the editor chose to leave; do not trap them), after the drain.
//
// THE MODULES. This file is the one specifier everybody imports
// (`saving/queue`: the four controllers that write, and the system tests'
// `assert_writes_settled`); what it exports is unchanged by the split, and
// nothing outside this directory imports the files below.
// - `saving/queue_state.js`: what the others share, and nothing else -- the
//   page generations ("PAGE GENERATIONS", "WHAT A GENERATION IS"), the
//   chain and its counters, the registered forms, the promotion window's
//   record. No imports, no listeners.
// - `saving/queue_core.js`: the queue itself -- `acquire`, `enqueue`,
//   `holdTurboRequest`, `syncBases`, `drained()`, and "THE UNLOAD GUARD".
// - `saving/frame_hold.js`: what waits on `drained()` before it replaces an
//   editor -- a visit, a `#content` frame navigation ("FRAME NAVIGATIONS",
//   with the refetch of a stale answer) and a Turbo form submission ("TURBO
//   FORM SUBMISSIONS").
// - `saving/promotion_hold.js`: "THE PROMOTION HOLD", the navigator-level
//   submissions kept back while a frame navigation is promoted to a visit.
// Every module imports the others by their import-map specifier
// (`saving/...`, never a relative path): the import map gives each ONE URL,
// so each is evaluated once per document and there is one queue.
//
// THE ORDER THE LISTENERS ARE REGISTERED IN. Nine listeners are registered as
// these modules are evaluated, and they are registered in the order the
// single file this used to be had them in:
//   1. `document`  `turbo:before-visit`          frame_hold.js
//   2. `document`  `turbo:before-frame-render`   frame_hold.js
//   3. `window`    `turbo:before-fetch-request`  frame_hold.js
//   4. `document`  `turbo:submit-end`            frame_hold.js
//   5. `window`    `submit`, capturing           promotion_hold.js
//   6. `document`  `turbo:load`                  promotion_hold.js
//   7. `document`  `turbo:fetch-request-error`   promotion_hold.js
//   8. `document`  `turbo:frame-missing`         promotion_hold.js
//   9. `document`  `turbo:before-render`         this file, below
// A module's dependencies are evaluated before it, depth first, in the order
// of its `import`s, each once. So the order above is: `queue_state.js` and
// `queue_core.js` first (neither registers anything), then `frame_hold.js`
// (which imports those two), then `promotion_hold.js` (which imports
// `frame_hold.js`), then this file's own body. It holds whichever module is
// imported first and from wherever, as long as NOTHING IMPORTED BY
// `frame_hold.js` IMPORTS `promotion_hold.js`: that is why the promotion
// window's record and its `onPromotionEnd` are in `queue_state.js`, and why
// `frameFor`, which both need, is `frame_hold.js`'s. The imports below are
// written out in that order all the same, so it can be read here.
//
// What depends on it, and what does not:
// - No two of the nine share a target, an event and a phase, so the order
//   AMONG them decides nothing by itself. The two orderings the holds rely on
//   are made by the TARGET, not by when a listener was added: (5) is a
//   capturing listener on `window`, the first stop of every `submit`, so it
//   runs before Turbo's `FormSubmitObserver` (capturing, on `document`),
//   before `admin--saving--queue-hold` and before every Stimulus action; (3) is on
//   `window`, the last stop of a bubbling event, so it runs after every
//   `turbo:before-fetch-request` listener on an element or on `document`, and
//   finds a request `holdTurboRequest` took already `defaultPrevented`.
// - What the order does decide is where each of the nine stands among OTHER
//   code's listeners for the same event on the same target (Turbo's own on
//   `document`, `admin--saving--save-bar`'s `turbo:before-visit` guard, a
//   controller's `turbo:before-render` or `turbo:load`), and those run in the
//   order they were added. The nine are added in one go -- no other module is
//   evaluated in between -- at the first import of `saving/queue`, as they
//   always were. Keeping their order means that position is the same listener
//   for listener, so nothing has to be argued event by event.
// - (9) is here because it belongs to two modules at once (it retires a body,
//   `queue_state.js`, and drops a visit note, `frame_hold.js`) and comes last.
import { Turbo } from "@hotwired/turbo-rails"
import { retire } from "saving/queue_state"
import "saving/queue_core"
import { expectVisit } from "saving/frame_hold"
import "saving/promotion_hold"

export { currentGeneration, isCurrentGeneration } from "saving/queue_state"
export {
  registerForm, unregisterForm, settled, busy, drained, acquire, enqueue, syncBases, holdTurboRequest
} from "saving/queue_core"

// See "WHAT A GENERATION IS" (`queue_state.js`): the body Turbo is about to
// replace is retired now, a moment before the swap.
document.addEventListener("turbo:before-render", () => {
  if (Turbo.navigator?.currentVisit?.willRender === true) retire(document.body)
  expectVisit("answered", null)
})
