// The list's last line and the whole site's search, in the tree column.
//
// THE LAST LINE (`lastLine`, the server's `[data-mind-graph-search-site]`,
// whose one button is empty until it shows) follows the find field's TEXT,
// heard as the field's `input` (which `admin--tree--find` also dispatches
// when it empties the field itself): while the field holds text the line
// shows, "Search the whole site for “…”", and when it is empty the line
// goes -- whether or not there is a tree to narrow, so a graph that draws
// nothing, or whose read failed, still offers the whole site. No key of the
// field is heard here: the field's keys are the find's.
//
// Pressing it asks the whole site (`lastLine`'s `data-url`, through
// `search/suggestions.js`, with the field's text at the press: an answer to
// text the field has since changed from is dropped), and the list draws the
// answer in the tree's place (`list.showResults`); while the request is out
// the list is busy. Back and Escape give the tree back with the query kept
// and the focus on the last line, or on the field when it was emptied
// meanwhile. Typing in the field while the results show gives the tree back
// too, so no results stand under other text, and the last line names the
// new text.
//
// `attachSiteSearch(lastLine, { list, text, findField })` answers `stop()`,
// which cancels a search still out, stops listening to the document and
// hides the last line. `findField()` answers the column's find field, looked
// up each time.
import { createSuggestions } from "search/suggestions"

export function attachSiteSearch(lastLine, { list, text, findField }) {
  const button = lastLine.querySelector("button")
  let resultsShown = false
  const fieldQuery = () => findField()?.value.trim() ?? ""

  const hide = () => {
    lastLine.hidden = true
    button.replaceChildren()
  }
  const show = (query) => {
    if (!query) return hide()
    button.textContent = text.t("mind_graph.script.list.search_site", { query })
    lastLine.hidden = false
  }
  const backToList = () => {
    resultsShown = false
    const query = fieldQuery()
    show(query)
    if (query) button.focus()
    else findField()?.focus()
  }
  const showResults = (query, answer) => {
    list.setBusy(false)
    resultsShown = true
    hide()
    list.showResults({ query, ...answer, back: { label: text.t("mind_graph.script.list.back"), onBack: backToList } })
  }
  const search = createSuggestions({
    url: lastLine.dataset.url,
    getQuery: fieldQuery,
    onRows: (query, rows) => showResults(query, { rows }),
    onError: () => showResults(fieldQuery(), { failed: true })
  })
  const press = () => {
    if (!fieldQuery()) return
    list.setBusy(true)
    search.fetchNow()
  }
  // The field's text changed: a search still out is for other text, and
  // results that show give the tree back under the new text.
  const typed = (event) => {
    if (event.target !== findField()) return
    if (search.inFlight) {
      search.cancel()
      list.setBusy(false)
    }
    if (resultsShown) {
      resultsShown = false
      list.closeResults()
    }
    show(fieldQuery())
  }
  button.addEventListener("click", press)
  document.addEventListener("input", typed)
  // A field that already holds text: a navigation of the content frame keeps
  // the column, and the find keeps its query across it (`keep`).
  show(fieldQuery())

  return () => {
    search.cancel()
    button.removeEventListener("click", press)
    document.removeEventListener("input", typed)
    hide()
  }
}
