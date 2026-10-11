// JSON from one of CS Studio's own endpoints, or null: a refusal, a
// redirect to the sign-in page (which answers 200 with a page) and
// anything else that is not JSON are all "nothing to show". The notes' two
// live controllers ask through it (`admin--notes--inbox`: the unread count
// and one delivery; `admin--notes--live`: a record's counts).
export async function json(url) {
  const response = await fetch(url, { headers: { Accept: "application/json" } })
  if (!response.ok || response.redirected || !(response.headers.get("Content-Type") || "").includes("json")) return null
  return response.json()
}
