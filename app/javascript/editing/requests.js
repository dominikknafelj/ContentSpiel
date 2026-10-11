import { TAB } from "live/connection"

// The requests of live editing, and the tab's id on every write of an editor.
//
// THE TAB HEADER. The server reads `X-Notes-Tab` (the name it had when only
// notes sent it) into `Current.editing_tab` for every CS Studio request: it
// is the `origin` of a signal, so the tab that saved skips its own echo, and
// it is who holds a reservation. A write sent without it is nobody's: it
// claims nothing and its own tab would fetch what it has just drawn. Turbo's
// requests get it here; the three hand-built ones (`admin--saving--autosave`,
// `admin--editor--blocks`' reorder, `admin--pages--tree`'s move) add it
// themselves from `TAB_HEADER`.
export const TAB_HEADER = "X-Notes-Tab"

document.addEventListener("turbo:before-fetch-request", (event) => {
  const headers = event.detail.fetchOptions?.headers
  if (headers && !headers[TAB_HEADER]) headers[TAB_HEADER] = TAB
})

// A plain GET of one part. Not a Turbo request: the write queue neither
// holds nor counts it, and nobody who listens to Turbo's events hears it.
export async function get(url) {
  try {
    const response = await fetch(url, { headers: { Accept: "text/html", [TAB_HEADER]: TAB }, credentials: "same-origin" })
    if (response.redirected) return { status: 0, fragment: null, text: "" }
    const text = await response.text()
    const fragment = response.status === 200 ? new DOMParser().parseFromString(text, "text/html").body : null
    return { status: response.status, fragment, text }
  } catch {
    return { status: 0, fragment: null, text: "" }
  }
}

export function headers() {
  return { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content, [TAB_HEADER]: TAB, Accept: "text/vnd.turbo-stream.html, application/json" }
}

// A POST of a reservation's write. The CALLER puts it in the write queue.
export async function post(url, params = {}, options = {}) {
  try {
    const response = await fetch(url, { method: "POST", headers: headers(), body: new URLSearchParams(params), credentials: "same-origin", ...options })
    return { status: response.redirected ? 0 : response.status, text: await response.text() }
  } catch {
    return { status: 0, text: "" }
  }
}
