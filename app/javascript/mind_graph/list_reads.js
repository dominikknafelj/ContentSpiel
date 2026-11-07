// The list beside the canvas and its two reads. The list (`node_list.js`)
// shows the four groups of what is drawn, or a read's rows in their place:
// the posts no page lists while "Not listed on any page" is on
// (`data-unlisted-url`), and the posts behind a "+N more" after a press on
// it (`data-listed-url`, the pill's page and target), with "Open in Posts →"
// under them. It is drawn (`draw`) once per load, once per filter change and
// once per answer of one of the reads, never per frame. A row whose post IS
// drawn is the drawn node, with the connections it has on the canvas; one
// that is not is the read's row, "not in view", and a press adds its post
// (`app.js`, `addPost`). Without a graph there is nothing to add to, and
// such a row only says it is not in view (`addable`).
//
// A pill is NOT SELECTED: a press on it opens its rows (design answer F4;
// H1: a pill per target), and so does its ROW in the list, which is the
// keyboard's and a screen reader's way to the same rows (`openMore`).
// Pressed again it reads them again. THE WAY BACK to the groups is on
// screen, "Back to the list" over a pill's rows and beside "Try again" when
// a pill's read failed, and Escape pressed in them (`backToList`). Both are
// pressed IN the list, so the focus goes back to where the rows were asked
// from: the pill's row (the list itself puts it on the first row when the
// pill has gone). Escape on the canvas or a click on empty space, with
// nothing selected, gives the groups back too (`app.js`, `dismiss`, which
// asks `pillShown`). The rows of "Not listed on any page" are not a press's:
// its checkbox lets them go.
//
// A READ is a plain `fetch`, ended with everything else when the screen is
// left (`signal`), and GIVEN UP after `LOAD_TIMEOUT_MS` like the graph's own
// load (a TimeoutError is a failure like any other): without a limit a
// request that stalled would leave the checkbox ticked over the groups for
// good, and nothing would be said. WHILE IT IS OUT the rows' region is busy
// (`list.setBusy`, `aria-busy`): what is in it is about to be replaced. That
// is all the pending state there is; nobody gave words for one. A READ THAT
// FAILS says so in the list with "Try again" (design answer G5), which asks
// for the same read, and, for a pill's, the way back. Its error line stays
// through a toggle of the legend (under a checkbox that is still ticked the
// groups would be a list that is not what the checkbox says), until the
// read is asked again or let go. `again` says the ask came from that
// button: if the read fails once more, the new button takes the focus the
// old one had, and when it brings the rows the list itself puts the focus on
// the first of them (`node_list.js`: the focus was in the rows' region).
//
// The heading's figure is the read's whole `total`, which can be more than
// its rows (the server answers the first `PostGraph::ROW_LIMIT`). Over a
// pill's rows it is what the pill counts NOW ("More from Blog · 4" beside
// "+4 more"), which falls as its posts are added: one figure for "more" on
// the screen. "Open in Posts →" stands under a pill's rows where there are
// any: the server names the address also when it found none.
import { fill } from "mind_graph/card"
import { recordId } from "mind_graph/ids"

// How long a read may go unanswered before it is given up and shown as a
// failure, with Retry. This module owns the figure, and the graph's own load
// (`app.js`) imports it: `app.js` itself cannot be imported without a cycle.
export const LOAD_TIMEOUT_MS = 15_000

export function createListReads({ element, list, state, text, number, signal, destroyed }) {
  // The list's rows while a read's are shown in place of the groups: the
  // read's answer (`heading`, `rows`, `link`) and, for a pill's, the pill
  // (`pill`, its node's id). `asked` counts the reads, so that an answer that
  // comes after a later ask, or after the groups were asked back, is not
  // drawn. `failed` is the read that failed and has not been asked again or
  // let go (`{ pill }`): while it is set the list shows its error line, and
  // nothing draws the groups over it.
  let rowsShown = null
  let failed = null
  let asked = 0

  function draw() {
    if (failed) return
    if (rowsShown) {
      const shown = new Set(state.visibleNodes)
      const drawn = (id) => shown.has(state.indexOf.get(id))
      const pill = rowsShown.pill == null ? null : state.nodes[state.indexOf.get(rowsShown.pill)]
      list.showRows({
        heading: pill ? text.t("mind_graph.script.list.more_heading", { target: pill.of, count: number(pill.count) }) : rowsShown.heading, link: rowsShown.link, inView: drawn, rows: rowsShown.rows.map((row) => (drawn(row.id) ? state.nodes[state.indexOf.get(row.id)] : row)),
        back: rowsShown.pill ? wayBack() : null, addable: Boolean(state.data)
      })
    } else {
      list.render(state.visibleNodes.map((index) => state.nodes[index]))
    }
    list.mark(state.selected >= 0 ? state.nodes[state.selected].id : null)
  }

  // A read that is still out is let go: its answer will not be drawn
  // (`asked`), and the list is no longer waiting for it.
  function letGo() {
    asked += 1
    list.setBusy(false)
  }

  function forget() {
    letGo()
    rowsShown = null
    failed = null
  }

  function showGroups() {
    forget()
    list.setUnlisted(false)
    draw()
  }

  const wayBack = () => ({ label: text.t("mind_graph.script.list.back"), onBack: backToList })
  function backToList() {
    const pill = rowsShown?.pill ?? failed?.pill
    showGroups()
    if (pill) list.row(pill)?.focus()
  }

  async function showRowsFrom(url, { pill = null, again = false } = {}) {
    const mine = (asked += 1)
    list.setBusy(true)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: AbortSignal.any([ signal, AbortSignal.timeout(LOAD_TIMEOUT_MS) ]) })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const answer = await response.json()
      if (destroyed() || mine !== asked) return
      list.setBusy(false)
      failed = null
      // A pill's rows are named by what the pill hangs off and counted by the
      // pill (`draw`), and have a way back; the checkbox's are "Posts", and
      // the checkbox is their way back.
      rowsShown = {
        pill,
        heading: text.t("mind_graph.script.list.posts", { count: number(answer.total) }),
        rows: answer.rows,
        link: pill && answer.posts_url && answer.rows.length > 0 ? { href: answer.posts_url, label: text.t("mind_graph.script.list.open_in_posts") } : null
      }
      draw()
    } catch (error) {
      if (destroyed() || error.name === "AbortError" || mine !== asked) return
      list.setBusy(false)
      rowsShown = null
      failed = { pill }
      list.fail(text.t("mind_graph.script.list.failed"), {
        label: text.t("mind_graph.script.list.try_again"), focus: again, onRetry: () => showRowsFrom(url, { pill, again: true }), back: pill ? wayBack() : null
      })
    }
  }

  function openMore(pill) {
    list.setUnlisted(false)
    showRowsFrom(fill(fill(element.dataset.listedUrl, "__ID__", recordId(pill.page)), "__TARGET__", pill.target), { pill: pill.id })
  }

  return {
    draw, showRowsFrom, openMore, showGroups, backToList, letGo,
    // Every read goes, the checkbox's too, and nothing is drawn: the graph
    // itself is going.
    forget,
    // A SPENT PILL's rows go with it (`graph_data.js`, `spent`).
    dropPillRows(pillId) {
      if (rowsShown?.pill !== pillId) return
      letGo()
      rowsShown = null
    },
    // A pill's rows, or its failed read, were of the graph before a new one
    // and go with it. THE CHECKBOX'S ROWS STAY: "Not listed on any page" is a
    // read of its own, a person may have ticked it while the graph was still
    // on its way, and what they asked for is not taken from them when it
    // arrives (the rows are drawn again with the filter, now as rows that can
    // add their post).
    forgetPillReads() {
      if (rowsShown?.pill || failed?.pill) forget()
    },
    pillShown: () => Boolean(rowsShown?.pill || failed?.pill)
  }
}
