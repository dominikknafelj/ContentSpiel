// The notice: the lines over the canvas's top-left corner, a polite live
// region. A line is a string or a node (the Retry button); it is always
// written as `textContent`, never as markup.
//
// A LINE THAT SAYS WHAT IT SAID IS LEFT WHERE IT IS (`say`): the region is
// live, and a paragraph that is added is announced, also one that was only
// taken out and put back. So a sentence that did not change when a post was
// added is not touched at all: it is found BY ITS WORDS, not by its place (a
// line before it may have come or gone), it stays in the document, and only
// the lines that are new are inserted around it and the ones no longer said
// removed. The announced summary's line is never kept: every `say` takes it.
//
// THE ANNOUNCED SUMMARY (`announce`) is the canvas's name put into the same
// region, in a line hidden from the eye, beside whatever the notice shows:
// how a toggle of the legend, the view a large site opened in and the whole
// graph after "Show everything" are said to a screen reader. A new one
// takes the place of the last.
export function say(notice, ...lines) {
  const kept = new Map()
  for (const held of notice.children) if (!held.hasAttribute("data-mind-graph-announced") && held.childElementCount === 0 && !kept.has(held.textContent)) kept.set(held.textContent, held)
  const wanted = lines.filter(Boolean).map((line) => {
    if (!(line instanceof Node) && kept.has(line)) {
      const held = kept.get(line)
      kept.delete(line)
      return held
    }
    const paragraph = document.createElement("p")
    paragraph.className = "m-0 w-fit rounded-cs bg-surface px-1"
    if (line instanceof Node) paragraph.append(line)
    else paragraph.textContent = line
    return paragraph
  })
  for (const held of Array.from(notice.children)) if (!wanted.includes(held)) held.remove()
  let next = notice.firstChild
  for (const paragraph of wanted) {
    if (paragraph === next) next = next.nextSibling
    else notice.insertBefore(paragraph, next)
  }
}

export function announce(notice, summary) {
  notice.querySelector("[data-mind-graph-announced]")?.remove()
  const line = document.createElement("p")
  line.className = "sr-only"
  line.dataset.mindGraphAnnounced = ""
  line.textContent = summary
  notice.append(line)
}
