// The merge of a notes view with the server's fresh markup for it (notes
// spec §6.3). THE RULE: WHAT IS READ IS REPLACED; WHAT IS TYPED IS NEVER
// TOUCHED. This file is the one owner of that rule: every path that draws a
// list or a thread again -- a live refresh after a signal, and the answer to
// one of the tab's own buttons (`controllers/admin/notes/live_controller.js`:
// `fetchPart`, `answered`) -- goes through `mergeList`, `mergeThread` and
// `mergeGone`, and nothing else replaces a part of a view that is on screen.
//
// WHAT COUNTS AS TYPED, and stays the element it is:
// - a composer on screen: the thread's reply part and the list's new-note
//   field, with text, with CHOSEN FILES and no text (a file field's files
//   cannot be put back by a script), or empty;
// - an open edit form, with its typed text and its saved-text baseline (the
//   field's `defaultValue`);
// - an open "Delete this note?" question;
// - an open set of emoji ("Add a reaction"), which is open afterwards too;
// - a file that is playing: a message's files are the very elements that
//   were there (a picture is not fetched again, a GIF goes on playing).
//
// HOW.
// - The list view: everything in `#notes-list` is replaced AROUND a new-note
//   field that is on screen. The field is not moved, not even within the
//   list, so its text, its names, its open picker and the focus stay.
// - The thread view: its `messages` part is replaced -- Back, the heading,
//   Notify, Close and Pin are in it (its two rows, which in the drawer stay
//   at the top while the messages under them scroll: the handoff's decision
//   35), and show a state someone else can change. A message with an open
//   edit form or an open "Delete this note?" stays the element it is. The
//   `reply` part is never replaced: only its Resolve / Reopen button and the
//   empty form that button sends are swapped when the thread's state
//   changed, so the button says what it now does. (The one exception is the
//   answer to the reply's own composer, `reply` below: the part is then the
//   answer's.) A message's reaction chips are read, not typed: they are
//   redrawn with their message, and in a message that stays the element it
//   is (a delete question is open) the chips alone are swapped.
//   Whatever had the focus has it afterwards (the same element, or the same
//   control of the new markup), and the scroll position stays -- unless the
//   reader was at the bottom, who stays at the bottom. Messages that arrived
//   are set off by a "NEW" divider above the first of them, which stays
//   where it first stood until the thread is left; a reader who is not at
//   the bottom gets "1 new message ↓" above the reply field and nothing
//   moves.
// - A thread that is gone (its GET answers the list, "This note is gone")
//   while its reply field or an edit holds text, or its reply field holds
//   chosen files: the text stays, with "This thread was deleted" above the
//   field, and everything that would send it to a thread that is not there
//   is switched off (`mergeGone`).
//
// THE ORDER INSIDE A MERGE IS LOAD-BEARING: what has the focus and where
// the view is scrolled are noted first, whatever can fail (the translator)
// is asked before the first element is moved, the kept elements are put
// into the answer's copy, the copy takes the old part's place, and only then
// are the focus and the scroll position given back. An element that is
// moved drops the focus, and a part that is replaced starts at its top.
//
// WHAT IT TOUCHES. `view`, the element on screen, and `answer`, the view
// element of the server's markup (parsed, not in the document; it is only
// read and copied from). Outside `view` it reaches for three things, as the
// code it was did: what scrolls the view when the view does not scroll
// itself (`scrollerOf`: the drawer's body or the page, read and set), the
// nearest ancestor that can take the focus when nothing in the view can
// (`give`), and a `scroll` listener on the document for as long as "1 new
// message" stands (`jump`). It opens no connection, fetches nothing, raises
// no toast, navigates no frame and knows no controller: the strings it shows
// come in as `t`, the translator of the server's messages.
const NEAR_BOTTOM = 48
const FOCUSABLE = "a[href], button:not([disabled]), input:not([type=hidden]):not([disabled]), textarea:not([disabled]), select:not([disabled]), summary, [tabindex]"

// The last segment of the address a control's form posts to: "follow", "pin".
const change = (control) => control.closest("form")?.getAttribute("action")?.split("?")[0].split("/").pop()

// The controls of a thread's first rows, each as a name and how to find it
// in markup drawn again. Notify and Pin are a form each; which of the two
// words the form's address ends in changes with the thread.
const CONTROLS = [
  [ "back", (root) => root.querySelector("a[data-note-back]") ],
  [ "close", (root) => root.querySelector("button[data-note-close]") ],
  [ "leave", (root) => root.querySelector("button[data-note-leave]") ],
  [ "notify", (root) => [ ...root.querySelectorAll("[data-note-actions] form button") ].find((button) => [ "follow", "unfollow" ].includes(change(button))) ],
  [ "pin", (root) => [ ...root.querySelectorAll("[data-note-actions] form button") ].find((button) => [ "pin", "unpin" ].includes(change(button))) ],
  [ "state", (root) => root.querySelector("button[data-note-state]") ]
]

const nearBottom = (scroller) => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < NEAR_BOTTOM

// A list's view, merged with the answer: everything in it is replaced
// AROUND a new-note field that is on screen (see the header).
//
// Answers null for an answer that is not a list (nothing was touched), or
// `{ kept }`: the new-note field that stayed where it was, if there is one.
export function mergeList(view, answer) {
  if (answer.dataset.notesView !== "list") return null
  const next = document.importNode(answer, true)
  const field = view.querySelector(":scope > #notes-new")
  const held = hold(view)
  const scroller = scrollerOf(view)
  const top = scroller.scrollTop
  const resolved = view.querySelector("#notes-resolved-section")?.open

  if (field) {
    // Around the field, which stays where it is: what the answer has
    // before the field's place goes before it, the rest after. In an
    // answer without the place (the block the note is on went a moment
    // ago) the counts and the list's sentence go before it.
    const place = next.querySelector(":scope > #notes-new")
    const parts = [ ...next.children ]
    const at = place ? parts.indexOf(place) : parts.findIndex((part) => !part.matches("[hidden], [role='status']"))
    // Not the field's own place, and no second "New note" beside the field.
    const drawn = (part) => part !== place && !part.querySelector("[data-note-new-link]")
    ;[ ...view.children ].forEach((part) => { if (part !== field) part.remove() })
    field.before(...(at < 0 ? parts : parts.slice(0, at)).filter(drawn))
    field.after(...(at < 0 ? [] : parts.slice(at)).filter(drawn))
  } else {
    view.replaceChildren(...next.children)
  }

  const section = view.querySelector("#notes-resolved-section")
  if (resolved && section) section.open = true
  scroller.scrollTop = top
  give(view, held)
  return { kept: field ? [ field ] : [] }
}

// A thread's view, merged with the answer for the same thread.
//
// `own`: the answer to this tab's own button (`answered`), not a signal's
// fetch -- nothing in it "arrived". `reply`: the reply's composer is what
// was sent, so its part is the answer's. `state`: Resolve or Reopen was
// sent, whose refusal is said in the composer (`takeRefusal`). `held`: what had the focus when
// the button was pressed (`asked`). `t`: the translator of the page's
// messages (`messages(element).t`), for the two things said here: "NEW" and
// "1 new message".
//
// Answers null when nothing was touched (a view without its two parts, or
// one that already says its thread was deleted); `{ gone: true }`, with
// nothing touched either, when the answer is not this thread's view -- the
// thread is no longer there, and the caller goes on to `mergeGone`; or
// `{ gone: false, kept, arrived }`: the messages being worked in, which are
// the elements they were, and how many messages the answer has that the
// view had not.
export function mergeThread(view, answer, { own = false, reply: sentReply = false, state: sentState = false, held: heldBefore = null, t } = {}) {
  const old = view.querySelector(":scope > [data-note-part='messages']")
  const reply = view.querySelector(":scope > [data-note-part='reply']")
  if (!old || !reply) return null
  const busy = working(old)

  if (answer.dataset.notesView !== "thread" || answer.dataset.noteThread !== view.dataset.noteThread) return { gone: true }
  if (view.querySelector("[data-note-gone]")) return null

  const scroller = scrollerOf(view)
  const atBottom = nearBottom(scroller)
  const top = scroller.scrollTop
  // What had the focus at the press -- unless the person has since moved
  // into a field: then that field, which is where their typing goes. (It
  // is noted, not left alone: a message that is kept is moved into the new
  // part, and an element that is moved drops the focus.)
  const held = (!typing(view) && heldBefore) || hold(view)
  const known = new Set([ ...old.querySelectorAll("[data-note-message]") ].map((message) => message.dataset.noteMessage))
  const next = document.importNode(answer.querySelector(":scope > [data-note-part='messages']"), true)
  const find = (id) => [ ...next.querySelectorAll("[data-note-message]") ].find((message) => message.dataset.noteMessage === id)

  // NOTHING BELOW MAY FAIL UNTIL THE COPY HAS TAKEN THE OLD PART'S PLACE: the
  // messages being worked in are moved into the copy next, and a throw
  // between that and the swap would leave them, with their typed text, out
  // of the document for good. So what can fail is done here, with nothing
  // moved yet: the "NEW" divider is built whether or not this merge turns
  // out to need it, since building it asks the translator, which throws for
  // a key it does not have and is not there at all for a caller that forgot
  // it. (After this tab's own press there is no divider, and none is built.)
  const line = own ? null : divider(t)

  const arrived = [ ...next.querySelectorAll("[data-note-message]") ].filter((message) => !known.has(message.dataset.noteMessage))
  // The set of emoji that is open under a message, to be open again.
  // (Not after this tab's own press: an emoji was picked from it.)
  const picking = own ? null : old.querySelector("details[data-reaction-add][open]")?.closest("[data-note-message]")?.dataset.noteMessage
  // The very elements, in the place the answer gives their messages -- shown,
  // should that place now be among the folded ones; one whose message was
  // deleted meanwhile keeps its text at the end.
  busy.forEach((message) => {
    const twin = find(message.dataset.noteMessage)
    // Its reactions are what others did, not what is being typed: the new
    // ones, disabled under an edit form (which is not touched). Not while
    // its own set of emoji is open.
    if (twin && !message.querySelector("details[data-reaction-add][open]")) takeReactions(message, twin, { disabled: Boolean(message.querySelector("form[data-note-composer]")) })
    if (twin) twin.replaceWith(message)
    // At the end of the messages, which is inside what scrolls (decision 35).
    else (next.querySelector(":scope > [data-note-scroll]") || next).append(message)
    message.closest("details")?.setAttribute("open", "")
  })
  // A message's files never change (they are fixed when it is written), so
  // the very elements are kept in the place the answer gives them: a
  // picture is not fetched again for every refresh (its address is never
  // cached, `Admin::NoteFilesController`), and a GIF someone set playing
  // goes on playing. A message being worked in was moved whole, above.
  old.querySelectorAll("[data-note-message]").forEach((message) => {
    if (busy.includes(message)) return
    const kept = message.querySelector(":scope > [data-note-files]")
    const place = kept && find(message.dataset.noteMessage)?.querySelector(":scope > [data-note-files]")
    if (place) place.replaceWith(kept)
  })
  if (old.querySelector("details[data-note-fold]")?.open) next.querySelector("details[data-note-fold]")?.setAttribute("open", "")
  if (picking) find(picking)?.querySelector("details[data-reaction-add]")?.setAttribute("open", "")
  // The divider stays where it first stood while the thread is open.
  const first = old.querySelector("[data-note-new-divider]")?.nextElementSibling?.dataset.noteMessage
  const mark = own ? null : (first && find(first)) || arrived[0]
  if (mark) {
    mark.closest("details")?.setAttribute("open", "")
    mark.before(line)
  }

  // A refused Pin or Notify is cleared by the PERSON'S next action (the
  // handoff's decision 40), not by somebody else's change: a refresh that
  // is not this tab's own answer carries the alert over, as the element it
  // is (its four seconds, when the note is gone, go on counting).
  const refusal = own ? null : old.querySelector(":scope > [data-note-refusal]")
  if (refusal) next.querySelector(":scope > [data-note-rows]")?.after(refusal)

  old.replaceWith(next)
  view.dataset.state = answer.dataset.state
  takeCounts(view, answer)
  settle(reply, answer)
  if (sentState) takeRefusal(reply, answer)
  const nextReply = sentReply && document.importNode(answer.querySelector(":scope > [data-note-part='reply']"), true)
  // The reply was sent from its part -- the field, or the button beside
  // it: the focus goes to the field of the part that takes its place.
  const fromReply = Boolean(nextReply && held?.element && reply.contains(held.element))
  if (nextReply) reply.replaceWith(nextReply)
  if (fromReply) nextReply.querySelector("textarea")?.focus({ preventScroll: true })
  else give(view, held)

  // The reader at the bottom stays there, and so sees what arrived; anyone
  // else stays where they are and is told. Asked for again: the messages'
  // own scroller is part of what was just replaced.
  const now = scrollerOf(view)
  now.scrollTop = atBottom ? now.scrollHeight : top
  const merged = { gone: false, kept: busy, arrived: arrived.length }
  if (nextReply) return merged
  if (atBottom) reply.querySelector(":scope > [data-note-jump]")?.remove()
  else if (arrived.length > 0 && !own) jump(view, reply, arrived.length, t)
  return merged
}

// A message someone is working in: an open edit form, an open question.
function working(old) {
  return [ ...old.querySelectorAll("[data-note-message]") ].filter((message) => message.querySelector("form[data-note-composer], [data-note-delete-question]"))
}

// The thread is no longer there: its GET answered the list (`mergeThread`
// said `gone`). With nothing typed, nothing is touched and the answer is
// false: the caller sends the frame where that answer came from (the list,
// which says "This note is gone"). With text in the reply field or in an
// edit, the text stays (spec §6.3): the messages go, Back and Close stay,
// Notify, Pin and every way of sending are taken away -- each would be
// answered with the list, over the text -- and the field says why. The
// answer is then true, as it is for a view that says so already. `t` as in
// `mergeThread`, for "This thread was deleted".
export function mergeGone(view, { t } = {}) {
  const old = view.querySelector(":scope > [data-note-part='messages']")
  const reply = view.querySelector(":scope > [data-note-part='reply']")
  // No thread's view (`mergeThread` answers null for it): nothing to keep.
  if (!old || !reply) return true
  if (view.querySelector("[data-note-gone]")) return true

  const busy = working(old)
  const editing = busy.filter((message) => [ ...message.querySelectorAll("textarea") ].some((field) => field.value !== field.defaultValue))
  // Chosen files are typed work too: a field that holds some is kept, even
  // with no text beside them.
  const files = reply.querySelector("input[type='file']")?.files.length > 0
  if (!reply.querySelector("textarea")?.value && !files && editing.length === 0) return false

  // The line that says why, written before anything is taken away: asking
  // the translator can fail, and a view with its rows' forms and its
  // messages gone but no word about it would be worse than one left alone.
  const line = document.createElement("p")
  line.dataset.noteGone = ""
  line.setAttribute("role", "status")
  line.className = "rounded-cs border border-line bg-sunken px-3 py-2 text-[13px] text-ink"
  line.textContent = t("notes.script.live.gone")

  const held = hold(view)
  const rows = old.querySelector(":scope > [data-note-rows]")
  rows?.querySelectorAll("[data-note-actions] form").forEach((form) => form.remove())
  // What is left under the rows: the edits that hold text, and nothing else.
  old.querySelector(":scope > [data-note-scroll]")?.replaceChildren(...editing)

  ;(reply.querySelector("form[data-note-composer]") || reply.lastElementChild).before(line)
  reply.querySelector(":scope > [data-note-jump]")?.remove()

  view.querySelectorAll("form").forEach((form) => form.addEventListener("submit", (event) => event.preventDefault()))
  view.querySelectorAll("button[type='submit']").forEach((button) => {
    // No longer the composer's to enable when the field has text.
    button.removeAttribute("data-admin--notes--composer-target")
    button.disabled = true
  })
  give(view, held)
  return true
}

// Resolve or Reopen, in the composer's bottom row, and the empty form it
// sends: swapped when the thread's state changed, and only then. Nothing
// else of the reply part is ever replaced.
function settle(reply, answer) {
  const button = reply.querySelector("button[data-note-state]")
  const twin = answer.querySelector("[data-note-part='reply'] button[data-note-state]")
  if (!button || !twin || button.dataset.noteState === twin.dataset.noteState) return

  const form = button.form
  const formTwin = answer.querySelector(`[data-note-part='reply'] form[id="${CSS.escape(twin.getAttribute("form"))}"]`)
  if (form && formTwin) form.replaceWith(document.importNode(formTwin, true))
  button.replaceWith(document.importNode(twin, true))
}

// Resolve or Reopen was pressed, and the answer says in the composer
// whether it was refused (`ThreadComponent`: the sentence stands where the
// button does). The reply part is not replaced for it -- its field may
// hold text -- so the sentence alone is taken over: the answer's, in the
// place the composer has for one, or none when the press went through.
function takeRefusal(reply, answer) {
  const form = reply.querySelector("form[data-note-composer]")
  const twin = answer.querySelector("[data-note-part='reply'] form[data-note-composer]")
  if (!form || !twin) return

  form.querySelector(":scope > ul[role='alert']")?.remove()
  const said = twin.querySelector(":scope > ul[role='alert']")
  if (said) form.querySelector(":scope > input[name='mention_names']")?.after(document.importNode(said, true))
}

// The "NEW" divider (handoff): an accent line filling the row, then the
// word.
function divider(t) {
  const divider = document.createElement("div")
  divider.dataset.noteNewDivider = ""
  divider.className = "flex items-center gap-2 px-4 pt-2.5"
  const line = document.createElement("span")
  line.className = "h-px flex-1 bg-accent"
  const label = document.createElement("span")
  label.className = "font-cs-mono text-[10px] uppercase tracking-mono text-accent"
  label.textContent = t("notes.script.live.new_divider")
  divider.append(line, label)
  return divider
}

// "1 new message ↓", 12px above the reply field (the dock is positioned, so
// the button stands on it wherever the thread is scrolled to; 13px from the
// dock's padding edge, which is 12px above the line on its top). It counts
// what arrived since the reader was last at the bottom, and goes when they
// are there again -- by pressing it or by scrolling.
//
// What scrolls is asked for each time (`scrollerOf`): the messages' own
// scroller is replaced with every refresh, while this button, in the reply
// part, stays. So the scroll is heard on the document in the capture
// phase, which hears every scroller in it (a scroll does not bubble) and
// the window's too.
function jump(view, reply, count, t) {
  let button = reply.querySelector(":scope > [data-note-jump]")
  const total = count + Number(button?.dataset.count || 0)
  if (!button) {
    button = document.createElement("button")
    button.type = "button"
    button.dataset.noteJump = ""
    button.className = "absolute bottom-full left-1/2 mb-[13px] -translate-x-1/2 cursor-pointer whitespace-nowrap rounded-cs border border-line-strong bg-surface px-2.5 py-[5px] text-[12px] font-medium text-ink shadow-menu focus-visible:outline-2 focus-visible:outline-accent"
    const watch = () => { if (!button.isConnected || !view.isConnected || nearBottom(scrollerOf(view))) dismiss() }
    const dismiss = () => {
      document.removeEventListener("scroll", watch, { capture: true })
      if (button.contains(document.activeElement)) view.focus({ preventScroll: true })
      button.remove()
    }
    document.addEventListener("scroll", watch, { capture: true, passive: true })
    button.addEventListener("click", () => {
      if (button.contains(document.activeElement)) view.focus({ preventScroll: true })
      const scroller = scrollerOf(view)
      scroller.scrollTop = scroller.scrollHeight
      dismiss()
    })
    reply.prepend(button)
  }
  button.dataset.count = String(total)
  button.textContent = t("notes.script.live.new_messages", { count: total })
}

// The answer's own copy of the record's counts, in the place of the one
// the view had: `admin--notes--drawer` reads a counts element as it connects.
export function takeCounts(view, answer) {
  const counts = answer.querySelector(":scope > [data-admin--notes--drawer-target~='counts']")
  const own = view.querySelector(":scope > [data-admin--notes--drawer-target~='counts']")
  if (counts && own) own.replaceWith(document.importNode(counts, true))
}

// What scrolls a view. A thread in the drawer or the sheet: its messages'
// own scroller, between the two rows and the composer (decision 35), which
// is so by the stylesheet and is asked of it. Anything else -- the list, a
// thread in the media panel or on a record's notes page: the drawer's
// body, or the page.
export function scrollerOf(view) {
  const own = view.querySelector(":scope > [data-note-part='messages'] > [data-note-scroll]")
  if (own && /auto|scroll/.test(window.getComputedStyle(own).overflowY)) return own
  return view.closest("[data-notes-scroller]") || document.scrollingElement
}

// What has the focus inside `root`, to be given back after a redraw
// (`give`): the element itself, which may survive; failing that, what it
// was -- one of a thread's own controls, an element with an id (a row of
// the list), or the nth control of a message.
export function hold(root) {
  const active = document.activeElement
  if (!active || active === document.body || !root.contains(active)) return null

  const message = active.closest("[data-note-message]")
  return {
    element: active,
    control: CONTROLS.find(([ , find ]) => find(root) === active)?.[0],
    id: active.id || null,
    message: message && root.contains(message) ? message.dataset.noteMessage : null,
    index: message ? [ ...message.querySelectorAll(FOCUSABLE) ].indexOf(active) : -1,
    // A reaction's chip, or an emoji of the set: by its emoji, since the
    // chips before it may be others after the redraw.
    reaction: active.closest("[data-note-reactions], [data-reaction-add]") ? active.dataset.reaction || active.value || null : null,
    selection: typeof active.selectionStart === "number" ? [ active.selectionStart, active.selectionEnd, active.selectionDirection ] : null
  }
}

// Never left to fall to <body>: when nothing of the new markup is what had
// the focus, the view takes it (or, for the list, what holds it: the
// drawer).
export function give(root, held) {
  if (!held || document.activeElement === held.element) return

  const message = held.message ? [ ...root.querySelectorAll("[data-note-message]") ].find((each) => each.dataset.noteMessage === held.message) : null
  const target = (held.element.isConnected && held.element)
    || (held.control && CONTROLS.find(([ name ]) => name === held.control)[1](root))
    || (held.id && [ ...root.querySelectorAll("[id]") ].find((each) => each.id === held.id))
    || (message && held.reaction && reaction(message, held.reaction))
    || (message && [ ...message.querySelectorAll(FOCUSABLE) ][held.index])
    || root.closest("[tabindex]")
  if (!target) return

  target.focus({ preventScroll: true })
  if (target === held.element && held.selection) target.setSelectionRange(...held.selection)
}

// Whether the focus is in a field of the view right now.
export function typing(root) {
  const active = document.activeElement
  return Boolean(active?.isConnected && root.contains(active) && active.matches("textarea, input:not([type=hidden]), select"))
}

// The chip of an emoji in a message as it is drawn now; the way to the set
// (the add chip, or the meta line's control once the row is gone) when that
// emoji's last reaction went and its chip with it. Compared as data, never
// built into a selector: the emoji is whatever the button held.
function reaction(message, emoji) {
  return [ ...message.querySelectorAll("[data-note-reactions] button[data-reaction]:not([disabled])") ].find((chip) => chip.dataset.reaction === emoji)
    || message.querySelector("details[data-reaction-add] > summary")
}

// A message that stays the element it is gets the answer's reactions: its
// row of chips, or -- for a message nobody has reacted to -- the control in
// its meta line. Either may have come or gone since, so each is taken out
// and put where the message's own markup has it: the row before whatever
// is asked under the text, the control before the "⋯" menu.
//
// `disabled`: the message is being edited. The answer draws it as it is
// for everyone else, with chips to press; here they are made what
// `ReactionsComponent` draws under an edit form -- its `:disabled` state:
// the row at half opacity taking no pointer, every button `disabled`, the
// add chip a disabled button in place of the <details>, and no control in
// the meta line.
export function takeReactions(message, twin, { disabled = false } = {}) {
  const row = twin.querySelector(":scope > [data-note-reactions]")
  const control = disabled ? null : twin.querySelector(":scope > div > details[data-reaction-add]")
  if (row && disabled) {
    row.dataset.noteReactions = "disabled"
    row.classList.add("pointer-events-none", "opacity-50")
    row.querySelectorAll("details[data-reaction-add]").forEach((add) => {
      const summary = add.querySelector("summary")
      const button = document.createElement("button")
      button.type = "button"
      button.className = summary.className
      button.setAttribute("aria-label", summary.getAttribute("aria-label"))
      button.dataset.reactionAdd = "true"
      button.append(...summary.childNodes)
      add.replaceWith(button)
    })
    row.querySelectorAll("button").forEach((button) => { button.disabled = true })
  }
  message.querySelectorAll(":scope > [data-note-reactions], :scope > div > details[data-reaction-add]").forEach((old) => old.remove())
  if (row) {
    const under = message.querySelector(":scope > [role='alert'], :scope > [data-note-delete-question]")
    if (under) under.before(row)
    else message.append(row)
  }
  if (control) {
    const menu = message.querySelector(":scope > div > [data-controller~='admin--ui--menu']")
    if (menu) menu.before(control)
    else message.firstElementChild?.append(control)
  }
}

