// `data-notes-live` on <body>: "connected" says that EVERY cable subscription
// of this page has been answered -- the person's is up, and each record's is
// confirmed or was rejected (a record the viewer may not read) -- so a
// signal sent from then on is received; "connecting" says that one is not.
// The system tests wait on it before they cause a signal (`await_notes_live`).
//
// It is in `live/`, beside the connection, because more than one topic says
// its word here: notes' two controllers and presence's part. The attribute
// keeps the name it had when only notes spoke.
//
// Two controllers on <body> hold the subscriptions, and each knows only its
// own: `admin--notes--inbox` the person's ("person"), `admin--notes--live`
// the records' ("records"). Each says here how its own stand, whenever that
// changes; what it said is kept on <body> beside the answer
// (`data-notes-live-person`, `data-notes-live-records`), and the answer is
// all of them together. A part that has said nothing yet -- its controller
// has not connected on this <body> -- counts as not answered: the page is
// never called live on the word of one half.
//
// A THIRD KIND OF PART is an element of the page that holds a subscription
// of its own and is not always there: presence's people in an editor's
// header and in the media panel (`admin--presence--record`). Nobody on
// <body> can speak for it, and a page without one must still be called
// live, so such a part says how it stands ON ITS OWN ELEMENT:
// `data-live-part="waiting"`, which the SERVER renders -- the part is
// unanswered from the moment it is in the document, before its controller
// has connected -- and `"answered"`, which its controller writes once its
// subscription is confirmed or rejected. The answer here is read from the
// document each time: no element, nothing to wait for; one that left the
// page (a panel closed) no longer counts. Its controller calls `settle`
// whenever its word changes, and when it connects and disconnects. What was
// found is kept beside the two halves as `data-notes-live-parts` ("none",
// "waiting" or "answered"), for whoever reads a failed wait.
const PARTS = [ "person", "records" ]

export function report(body, part, answered) {
  body.setAttribute(`data-notes-live-${part}`, answered ? "answered" : "waiting")
  settle(body)
}

// Puts the answer together again, from what the two halves last said and
// from the parts the page holds now.
export function settle(body) {
  const parts = [ ...body.querySelectorAll("[data-live-part]") ]
  const waiting = parts.some((each) => each.getAttribute("data-live-part") !== "answered")
  body.setAttribute("data-notes-live-parts", parts.length === 0 ? "none" : waiting ? "waiting" : "answered")
  const all = PARTS.every((each) => body.getAttribute(`data-notes-live-${each}`) === "answered")
  body.dataset.notesLive = all && !waiting ? "connected" : "connecting"
}
