// A post's open notes in the selection card (notes spec §4.4; handoff, "Node
// card thread list"): each thread's first message, who wrote it and how many
// replies it has, a link into the post's editor with the drawer open at that
// thread, and a field to start a note without leaving the graph.
//
// Read as JSON from the notes endpoint scoped to that post (`url`), so what a
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
// Nothing here outlives the card: the section is a child of the card's
// container, which `card.js` empties on `hide()` and the controller's
// `reset()` empties on a page Turbo restored. An answer that arrives after
// that fills a section nobody sees.
//
// `cardNotes(node, { text, url, postUrl, onChange })` answers the section
// (`section[data-mind-graph-card-notes]`); a row is `li[data-note-row]`, with
// `data-unread` and the accent dot while it holds something the viewer has
// not read (spec §4.5: the one meaning accent has in notes), and the link to
// the rest is `a[data-note-more]`.
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

export function cardNotes(node, { text, url, postUrl, onChange }) {
  const section = element("section", "mt-1 flex flex-col gap-2 border-t border-line pt-2")
  section.dataset.mindGraphCardNotes = ""
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
  field.setAttribute("aria-label", text.t("mind_graph.script.card.notes.label"))
  field.placeholder = text.t("mind_graph.script.card.notes.label")
  const submit = element("button", "cursor-pointer rounded-cs border border-line-strong bg-surface px-2.5 py-[5px] text-[12px] font-medium text-ink hover:border-ink disabled:opacity-50", text.t("mind_graph.script.card.notes.add"))
  submit.type = "submit"
  form.append(field, submit)

  // The post's editor with the drawer open, at one thread or at the list.
  // The editor's URL arrives with the node; only the two parameters are
  // written here.
  function notesUrl(thread) {
    const target = new URL(postUrl, window.location.origin)
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
      // rows don't show is behind "+N more", which opens the post's notes.
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
    try {
      const body = new FormData(form)
      body.set("view", "mind_graph")
      const response = await fetch(url, {
        method: "POST", body,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
      })
      const answer = await response.json().catch(() => ({}))
      // Saved is a 201 with the thread's id and nothing else: a request that
      // was redirected to the sign-in page ends as a 200 with a page in it,
      // and must not empty the field.
      if (response.status === 201 && answer.id != null) {
        field.value = ""
        await load()
      } else {
        fail(Array.isArray(answer.errors) && answer.errors.length > 0 ? answer.errors.join(" ") : text.t("mind_graph.script.card.notes.failed"))
      }
    } catch {
      fail(text.t("mind_graph.script.card.notes.failed"))
    } finally {
      submit.disabled = false
    }
  })

  title(node.open_notes ?? 0)
  section.append(heading, list, status, form)
  if ((node.open_notes ?? 0) > 0) load()
  return section
}
