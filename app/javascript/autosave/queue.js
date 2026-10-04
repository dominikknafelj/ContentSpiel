// One screen's writes, one at a time (cs-studio design pass round 2, Task 6
// fix round 1).
//
// WHY. Every write a page editor sends can move the page's `updated_at`: a
// block save, add, duplicate, delete and reorder all `touch` it. The page
// settings form holds that `updated_at` as its autosave base, and a stale
// base is now REFUSED (409, `Admin::AutosaveResponses#refuse_stale_autosave`).
// To keep the page form's base honest the server moves it forward in a block's
// answer -- but only when the base the request carried
// (`X-Page-Base-Updated-At`) was still current before that write. Two
// requests sent from the same screen at the same moment (the page form and
// every block form debounce on the same tick after "Use all"; or a block's
// answer still in flight on a slow connection when the next form sends) carry
// the same base: the first moves the page, the second's base is then stale, so
// no base is streamed back and its own touch moves the page again -- and the
// page form is left holding a base that nobody else made stale. Its next
// save is a 409 and the form is dead until Reload, losing the typed text.
//
// WHAT. This queue makes a request be SENT only after the previous one's
// answer has been received AND its base values written into the hidden fields
// (`syncBases`, synchronous -- `Turbo.renderStreamMessage` applies a stream on
// the next frame, too late for a request sent straight after). Each request
// therefore reads the freshest bases at SEND time (inside the task), never at
// queue time. The server's base mechanism is unchanged.
//
// Everything that sends `X-Page-Base-Updated-At` goes through here: every
// `admin--autosave` form (`enqueue`), block reorder (`enqueue`), and Turbo's
// own block form submissions -- add, duplicate, delete, the Undo toast
// (`holdTurboRequest`). A task that fails does not block the queue: errors are
// swallowed on the chain (the retry schedule re-enters the queue itself), a
// fetch that never answers is cut by the caller's own timeout, and
// `holdTurboRequest` releases after `HOLD_LIMIT_MS` regardless. The queue is
// per page load: `turbo:before-visit` starts a fresh chain.
const HOLD_LIMIT_MS = 30000

let tail = Promise.resolve()

// Resolves with a `release` function once every earlier holder has released.
// The next holder waits for exactly this one's release.
export function acquire() {
  let release
  const released = new Promise((resolve) => { release = resolve })
  const turn = tail.then(() => release)
  tail = tail.then(() => released)
  return turn
}

// Runs `task` (an async function) alone: returns its result or rethrows its
// error, and either way lets the next one go.
export async function enqueue(task) {
  const release = await acquire()
  try {
    return await task()
  } finally {
    release()
  }
}

// Copies each named base field's fresh value out of a Turbo Stream answer onto
// the live hidden field, synchronously. Matched by id (a block's answer may
// carry both its own base and the page form's).
export function syncBases(streamText, ids) {
  const templates = Array.from(new DOMParser().parseFromString(streamText, "text/html").querySelectorAll("template"))
  for (const id of ids) {
    const field = document.getElementById(id)
    if (!field) continue
    const fresh = templates
      .map((template) => template.content.querySelector(`[name="base_updated_at"][id="${id}"]`))
      .find((candidate) => candidate)?.value
    if (fresh) field.value = fresh
  }
}

// For a Turbo-driven request (`turbo:before-fetch-request`): holds it until
// the queue is free, lets `before` set its headers at send time, then keeps
// the queue's slot until the answer's bases are applied.
export function holdTurboRequest(event, { before, baseIds }) {
  event.preventDefault()
  const target = event.target
  const request = event.detail

  acquire().then((release) => {
    let finished = false
    const finish = () => {
      if (finished) return
      finished = true
      clearTimeout(limit)
      target.removeEventListener("turbo:before-fetch-response", onResponse)
      target.removeEventListener("turbo:fetch-request-error", finish)
      release()
    }
    const onResponse = async (responseEvent) => {
      try {
        syncBases(await responseEvent.detail.fetchResponse.response.clone().text(), baseIds)
      } finally {
        finish()
      }
    }
    const limit = setTimeout(finish, HOLD_LIMIT_MS)

    target.addEventListener("turbo:before-fetch-response", onResponse)
    target.addEventListener("turbo:fetch-request-error", finish)
    before(request)
    request.resume()
  })
}

document.addEventListener("turbo:before-visit", () => { tail = Promise.resolve() })

