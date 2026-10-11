// The one suggestions search shared by the chip input
// (`admin--ui--chip-input`: tags, related posts) and the rich-text editor's link
// search (`rich_text/target_search.js`): debounce, one request at a time, the
// stale-answer guard and the status wording. Each caller keeps what is its
// own -- rendering rows and selecting one -- so a fix here (a late answer, an
// aborted request) reaches both.
//
// What it guarantees:
// - `schedule()` waits `DELAY_MS` after the last call before asking;
// - a new request aborts the previous one, and an answer is delivered only
//   if it is still the newest request AND the field still holds the text it
//   was asked for (`getQuery()` is compared with the query at send time) --
//   a late answer is dropped, never shown under the wrong text;
// - `cancel()` (Escape, an emptied field, a pick) stops a pending timer and
//   a request in flight, and the cancelled request never answers;
// - a failure is reported only for the newest request; an abort is silent.
export const DELAY_MS = 150

// "Draft" / "Scheduled" for a row whose `status` isn't live; live (or none)
// is nothing. Link-target rows carry `status`; tag rows do not.
export function statusLabel(row) {
  return row.status && row.status !== "live" ? row.status[0].toUpperCase() + row.status.slice(1) : null
}

export const TEXTS = {
  searchFailed: "Search failed — check your connection"
}

// `url`        string, or a function returning it
// `params`     optional function returning extra query params (an object)
// `getQuery`   the text currently in the field, trimmed
// `onRows(query, rows)` an answer that is still current
// `onError()`  the newest request failed
export function createSuggestions({ url, params = () => ({}), getQuery, onRows, onError = () => {}, delay = DELAY_MS }) {
  let timer = null
  let aborter = null
  let sequence = 0
  const state = { inFlight: false, pending: false }

  async function fetchNow() {
    clearTimeout(timer)
    state.pending = false
    aborter?.abort()
    aborter = new AbortController()
    const mine = ++sequence
    const query = getQuery()
    state.inFlight = true

    const endpoint = new URL(typeof url === "function" ? url() : url, window.location.origin)
    endpoint.searchParams.set("q", query)
    Object.entries(params()).forEach(([ key, value ]) => endpoint.searchParams.set(key, value))

    let rows
    try {
      const response = await fetch(endpoint, { headers: { Accept: "application/json" }, signal: aborter.signal })
      if (!response.ok) throw new Error(`suggestions answered ${response.status}`)
      rows = await response.json()
    } catch (error) {
      if (error.name === "AbortError") return
      if (mine === sequence) {
        state.inFlight = false
        onError()
      }
      return
    }

    if (mine === sequence) state.inFlight = false
    if (mine !== sequence || query !== getQuery()) return
    onRows(query, rows)
  }

  return {
    get inFlight() { return state.inFlight },
    // The debounce timer is running: a search is scheduled and not yet sent.
    get pending() { return state.pending },
    fetchNow,
    schedule() {
      clearTimeout(timer)
      state.pending = true
      timer = setTimeout(fetchNow, delay)
    },
    // Only the debounce timer: a request already on its way still answers
    // (and is dropped if the text has moved on).
    unschedule() {
      clearTimeout(timer)
      state.pending = false
    },
    // Whatever is pending or in flight is void: it will not answer.
    cancel() {
      clearTimeout(timer)
      state.pending = false
      aborter?.abort()
      sequence += 1
      state.inFlight = false
    },
    destroy() {
      this.cancel()
    }
  }
}
