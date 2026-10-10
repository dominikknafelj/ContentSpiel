// `data-notes-live` on <body>: "connected" says that EVERY cable subscription
// of this page has been answered -- the person's is up, and each record's is
// confirmed or was rejected (a record the viewer may not read) -- so a
// signal sent from then on is received; "connecting" says that one is not.
// The system tests wait on it before they cause a signal (`await_notes_live`).
//
// Two controllers on <body> hold the subscriptions, and each knows only its
// own: `admin--notes--inbox` the person's ("person"), `admin--notes--live`
// the records' ("records"). Each says here how its own stand, whenever that
// changes; what it said is kept on <body> beside the answer
// (`data-notes-live-person`, `data-notes-live-records`), and the answer is
// all of them together. A part that has said nothing yet -- its controller
// has not connected on this <body> -- counts as not answered: the page is
// never called live on the word of one half.
const PARTS = [ "person", "records" ]

export function report(body, part, answered) {
  body.setAttribute(`data-notes-live-${part}`, answered ? "answered" : "waiting")
  const all = PARTS.every((each) => body.getAttribute(`data-notes-live-${each}`) === "answered")
  body.dataset.notesLive = all ? "connected" : "connecting"
}
