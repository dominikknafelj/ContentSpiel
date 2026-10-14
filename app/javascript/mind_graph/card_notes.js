// A post's or a page's open notes in the selection card (notes spec §4.4; handoff, "Node
// card thread list"): each thread's first message, who wrote it and how many
// replies it has, a link into the record's editor with the drawer open at that
// thread, and a field to start a note without leaving the graph.
//
// Read as JSON from the notes endpoint scoped to that record (`url`: a
// post's or a page's, the template the view built for its `type`), so what a
// viewer sees here is what they may read; written with `textContent` and
// `href` only, like the rest of the card -- a note's text and its author's
// name are a person's, whatever they contain. A note is started with a form
// post to the same URL, answered as JSON (201 with the new thread's id; 403
// or 422 with the reasons, which are shown above the field, the text kept).
// Its origin view is `mind_graph`. Listing the notes marks nothing read:
// opening one in the editor does.
//
// `onChange` tells the card that its height changed and that the node's
// count may have: this writes `node.open_notes`, which the canvas draws as
// the node's badge (`renderer.js`), from the endpoint's exact `open`.
//
// LIVE (notes spec §6). The section is a `record` of `admin--notes--live`, the
// controller on <body> that holds the socket: it subscribes to this post's
// signals for as long as the section is in the page and, when a thread of the
// post changed, says so with `admin--notes--live:changed` on the section, which
// reads the list again. The target is written with `setAttribute`: the
// identifier's double dash can't be spelled through `dataset`, whose
// `adminNotesLiveTarget` would be `data-admin-notes-live-target`, a target of
// nothing, where the attribute the controller reads is
// `data-admin--notes--live-target`. A note started here says which tab it came from (`X-Notes-Tab`,
// the id that controller wrote on <body>), so this tab is not told about its
// own note: it has read the list again already.
//
// THE FIELD'S DRAFT. The card is built anew every time a node is selected,
// and Escape in the field, a click on the canvas and another node all close
// it: a half-typed note went with it. So what is typed is kept like a
// composer's (`admin--notes--composer`), per person and per post, under
// `cs-note-draft:<user id>:graph-Post-<id>` (a page's: `graph-Page-<id>`, so
// a page and a post of one database id keep two drafts) in `sessionStorage`;
// put back when that record's card is built again; removed when the note is saved or
// the field emptied, and with every other draft when the person signs out
// (`forgetDrafts`). The person is the one `admin--notes--inbox` was given on
// <body>. While a note is on its way the field is read-only, so nothing is
// typed that the emptied field would throw away. A draft is a convenience:
// storage that is absent or full is the same as having none.
//
// Nothing else here outlives the card: the section is a child of the card's
// container, which `card.js` empties on `hide()` and the controller's
// `reset()` empties on a page Turbo restored. An answer that arrives after
// that fills a section nobody sees.
//
// `cardNotes(node, { text, type, url, recordUrl, onChange })` (`type` is
// "post" or "page", what the notes are on; `recordUrl` the record's editor,
// which arrives with its node) answers the section
// (`section[data-mind-graph-card-notes]`), which the card draws under the
// title and above its actions (`card.js` says how); a row is `li[data-note-row]`, with
// `data-unread` while it holds something the viewer has not read -- ink for
// dim, the accent dot (spec §4.5: the one meaning accent has in notes) and
// the word "new" for a screen reader, so it is never colour alone -- and the
// link to the rest is `a[data-note-more]`.
import { draftKey } from "controllers/admin/notes/composer_controller"
import { recordId } from "mind_graph/ids"

const LABEL = "m-0 font-cs-mono text-label uppercase tracking-mono text-meta"
// Three rows, then "+N more" (handoff, "Node card thread list").
const ROWS = 3
// The person as a round mark with their initials, as the drawer draws one
// (`Admin::NotesScreen::AvatarComponent`, whose classes and rule these are:
// the first letters of the first two words of the name; the viewer's own is
// filled ink, everyone else's sunken with a line). Decoration: the name is
// written beside it.
const AVATAR = "flex size-5 shrink-0 items-center justify-center rounded-full font-cs-mono text-[8px] font-medium uppercase leading-none"
const AVATAR_OWN = "bg-ink text-paper"
const AVATAR_OTHER = "border border-line-strong bg-sunken text-ink"
const initials = (name) => name.split(/\s+/).filter(Boolean).slice(0, 2).map((word) => Array.from(word)[0]).join("")

function element(tag, className, content) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (content != null) node.textContent = content
  return node
}

export function cardNotes(node, { text, type = "post", url, recordUrl, onChange }) {
  const section = element("section", "flex flex-col gap-2")
  section.dataset.mindGraphCardNotes = ""
  section.setAttribute("data-admin--notes--live-target", "record")
  section.dataset.notesType = type
  section.dataset.notesId = recordId(node.id)
  const heading = element("h3", LABEL)
  const list = element("ul", "m-0 flex list-none flex-col gap-2 p-0")
  const status = element("p", "m-0 text-[12px] text-danger-ink")
  status.setAttribute("role", "status")
  status.hidden = true

  const form = element("form", "flex flex-col items-start gap-1.5")
  const field = element("textarea", "block w-full rounded-cs border border-line-strong bg-surface px-[9px] py-[7px] text-[13px] text-ink placeholder:text-meta focus:outline-2 focus:outline-accent")
  field.name = "body"
  field.rows = 2
  field.maxLength = 4000
  field.required = true
  // "Write a note on this post", or "on this page": the field says what the
  // note is on.
  const fieldLabel = type === "page" ? text.t("mind_graph.script.card.notes.label_page") : text.t("mind_graph.script.card.notes.label")
  field.setAttribute("aria-label", fieldLabel)
  field.placeholder = fieldLabel
  const submit = element("button", "cursor-pointer rounded-cs border border-line-strong bg-surface px-2.5 py-[5px] text-[12px] font-medium text-ink hover:border-ink disabled:opacity-50", text.t("mind_graph.script.card.notes.add"))
  submit.type = "submit"
  form.append(field, submit)

  const key = draftKey(document.body.getAttribute("data-admin--notes--inbox-person-value") || "", `graph-${type === "page" ? "Page" : "Post"}-${recordId(node.id)}`)
  const draft = {
    read() {
      try {
        const body = JSON.parse(window.sessionStorage.getItem(key) || "null")?.body
        return typeof body === "string" ? body : ""
      } catch {
        return ""
      }
    },
    write() {
      try {
        if (field.value) window.sessionStorage.setItem(key, JSON.stringify({ body: field.value, names: {}, files: [] }))
        else window.sessionStorage.removeItem(key)
      } catch {
        // The text is still in the field.
      }
    }
  }
  field.value = draft.read()
  field.addEventListener("input", () => draft.write())

  // The record's editor with the drawer open, at one thread or at the list.
  // The editor's URL arrives with the node; only the two parameters are
  // written here.
  function notesUrl(thread) {
    const target = new URL(recordUrl, window.location.origin)
    target.searchParams.set("notes", "open")
    if (thread != null) target.searchParams.set("thread", thread)
    return target.pathname + target.search
  }

  // Zero threads: only the field, no heading (handoff, "Node card thread list").
  function title(count) {
    heading.textContent = text.t("mind_graph.script.card.notes.title", { count })
    heading.hidden = count === 0
    list.hidden = count === 0
  }

  // The handoff's row: the avatar, the first line cut with an ellipsis (ink
  // while unread, else dim) over who wrote it and its replies, and the unread
  // dot. The first line is the link.
  function row(thread) {
    const item = element("li", "grid grid-cols-[20px_1fr_7px] items-start gap-2 text-[13px]")
    item.dataset.noteRow = ""
    const who = thread.author ?? text.t("mind_graph.script.card.notes.deleted_user")
    const avatar = element("span", `${AVATAR} ${thread.mine ? AVATAR_OWN : AVATAR_OTHER}`, initials(who))
    avatar.setAttribute("aria-hidden", "true")

    const lines = element("span", "flex min-w-0 flex-col gap-0.5")
    const link = element("a", `truncate no-underline hover:underline ${thread.unread ? "text-ink" : "text-dim"}`, thread.text)
    link.href = notesUrl(thread.id)
    const facts = thread.replies > 0 ? `${who} · ${text.t("mind_graph.script.card.notes.replies", { count: thread.replies })}` : who
    lines.append(link, element("span", "truncate text-[12px] text-meta", facts))
    item.append(avatar, lines)

    if (thread.unread) {
      item.dataset.unread = ""
      // In words, for whoever does not see the ink and the dot.
      lines.append(element("span", "sr-only", text.t("mind_graph.script.card.notes.unread")))
      const dot = element("span", "mt-1.5 size-[7px] rounded-full bg-accent")
      dot.setAttribute("aria-hidden", "true")
      item.append(dot)
    }
    return item
  }

  function fail(reason) {
    status.textContent = reason
    status.hidden = false
    onChange()
  }

  async function load() {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      list.replaceChildren(...data.threads.slice(0, ROWS).map(row))
      // `open` is exact; `threads` is the listing's first page. What the
      // rows don't show is behind "+N more", which opens the record's notes.
      const rest = data.open - Math.min(ROWS, data.threads.length)
      if (rest > 0) {
        const more = element("li")
        const link = element("a", "text-[12px] text-accent hover:underline", text.t("mind_graph.script.card.notes.more", { count: rest }))
        link.dataset.noteMore = ""
        link.href = notesUrl()
        more.append(link)
        list.append(more)
      }
      node.open_notes = data.open
      title(data.open)
      status.hidden = true
      onChange()
    } catch {
      fail(text.t("mind_graph.script.card.notes.failed"))
    }
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault()
    submit.disabled = true
    field.readOnly = true
    // Said only when the send is still out after 300ms, as in a composer
    // (the notes handoff's decision 41): the text dim, the button
    // "Sending…" and busy. The card's field has no other controls.
    const saying = setTimeout(() => {
      field.classList.replace("text-ink", "text-dim")
      submit.textContent = text.t("mind_graph.script.card.notes.sending")
      submit.setAttribute("aria-busy", "true")
    }, 300)
    try {
      const body = new FormData(form)
      body.set("view", "mind_graph")
      const response = await fetch(url, {
        method: "POST", body,
        headers: {
          Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "",
          ...(document.body.dataset.notesTab ? { "X-Notes-Tab": document.body.dataset.notesTab } : {})
        }
      })
      const answer = await response.json().catch(() => ({}))
      // Saved is a 201 with the thread's id and nothing else: a request that
      // was redirected to the sign-in page ends as a 200 with a page in it,
      // and must not empty the field.
      if (response.status === 201 && answer.id != null) {
        field.value = ""
        draft.write()
        await load()
      } else {
        fail(Array.isArray(answer.errors) && answer.errors.length > 0 ? answer.errors.join(" ") : text.t("mind_graph.script.card.notes.failed"))
      }
    } catch {
      fail(text.t("mind_graph.script.card.notes.failed"))
    } finally {
      clearTimeout(saying)
      field.classList.replace("text-dim", "text-ink")
      submit.textContent = text.t("mind_graph.script.card.notes.add")
      submit.removeAttribute("aria-busy")
      submit.disabled = false
      field.readOnly = false
    }
  })

  section.addEventListener("admin--notes--live:changed", load)
  title(node.open_notes ?? 0)
  section.append(heading, list, status, form)
  if ((node.open_notes ?? 0) > 0) load()
  return section
}
