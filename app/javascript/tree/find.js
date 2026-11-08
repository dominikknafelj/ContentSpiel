import { isFolded, openByRule, readOpenSet, setFolded } from "tree/open_set"

// A FIND OVER A DRAWN TREE: the rows that match a query, and every ancestor
// of one, stay; every other node is `hidden`; the matched part of a title
// is marked. It reads the tree's DOM (`tree/open_set.js`): a node is
// `[data-tree-node]`, its row `[data-tree-row]` with the whole title in
// `data-tree-title` and, where it has one, its address in `data-tree-path`.
//
// MATCHING is as a person types: case and accents are ignored, in the
// tree's language (`normalise`), and a part of the title anywhere matches.
// A query that starts with "/" matches the address only (`matchesPath`),
// and nothing is marked for it, since the address is not drawn.
//
// A BRANCH HOLDING A MATCH IS SHOWN OPEN while the find is on, drawn as a
// fold is (`setFolded`) and marked `data-filter-open`, and never written to
// the open set: the find's opens are a view of the query, not the person's.
// A branch the person folds again while the find is on stays folded as the
// find runs again (a redrawn row, the next keystroke). `clearFilter` draws
// every branch from the open set again, so the person's folds come back as
// they were.
//
// WHAT A FIND WRITES INTO THE TREE, and `clearFilter` takes back: `hidden`
// on a node (marked `data-filter-hidden`, so a `hidden` it did not write is
// left alone), `data-filter-match` on a matching node, `data-filter-open`,
// and the `<mark>`s, which are built with `textContent` only, so a title
// with markup in it is marked as text. Every `<mark>` in a tree is this
// module's.

const MARKS = /\p{M}/gu

function lower(text, locale) {
  try {
    return text.toLocaleLowerCase(locale || undefined)
  } catch {
    return text.toLowerCase()
  }
}

// One character as a find compares it. Lower-casing can give a combining
// mark back (a dotted capital I), so the marks are dropped after it too.
function fold(char, locale) {
  return lower(char.normalize("NFD").replace(MARKS, ""), locale).normalize("NFD").replace(MARKS, "")
}

// `text` as a find compares it: decomposed (NFD), its combining marks
// dropped, lower-cased in `locale`. Folded a character at a time, so a
// position in the folded text maps back to one in the text (`markIn`).
export function normalise(text, locale) {
  return Array.from(String(text ?? ""), (char) => fold(char, locale)).join("")
}

export function matchesTitle(title, query, locale) {
  const needle = normalise(query, locale)
  return needle.length > 0 && normalise(title, locale).includes(needle)
}

// Only a query that starts with "/" asks for the address.
export function matchesPath(path, query) {
  if (!path || !String(query).startsWith("/")) return false
  return normalise(path).includes(normalise(query))
}

function rowOf(node) {
  return node.querySelector(":scope > [data-tree-row]")
}

function parentOf(node, tree) {
  const above = node.parentElement?.closest("[data-tree-node]")
  return above && tree.contains(above) ? above : null
}

// Wraps the first part of `element`'s text that matches `query` in a
// `<mark>`. A text node is split where the match starts and ends, the
// combining marks after its last character kept inside it.
function markIn(element, query, locale) {
  const needle = normalise(query, locale)
  if (!element || !needle) return

  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT)
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const chars = Array.from(node.data)
    const folds = chars.map((char) => fold(char, locale))
    const starts = []
    const offsets = []
    let folded = ""
    let offset = 0
    chars.forEach((char, index) => {
      starts.push(folded.length)
      offsets.push(offset)
      folded += folds[index]
      offset += char.length
    })
    offsets.push(offset)

    const at = folded.indexOf(needle)
    if (at < 0) continue

    const end = at + needle.length
    // The last character that folds to something and starts at or before
    // the match, and the first after it that starts at or past its end.
    let first = 0
    starts.forEach((start, index) => { if (start <= at && folds[index].length > 0) first = index })
    let last = first
    while (last < chars.length && (starts[last] < end || folds[last].length === 0)) last++

    const match = node.splitText(offsets[first])
    match.splitText(offsets[last] - offsets[first])
    const mark = document.createElement("mark")
    mark.textContent = match.data
    match.replaceWith(mark)
    return
  }
}

function takeBack(tree) {
  tree.querySelectorAll("mark").forEach((mark) => {
    const parent = mark.parentNode
    mark.replaceWith(document.createTextNode(mark.textContent))
    parent?.normalize()
  })
  tree.querySelectorAll("[data-filter-hidden]").forEach((node) => {
    node.hidden = false
    node.removeAttribute("data-filter-hidden")
  })
  tree.querySelectorAll("[data-filter-match]").forEach((node) => node.removeAttribute("data-filter-match"))
}

// Narrows `tree` to the nodes matching `query` and their ancestors (a
// query is never blank here: an empty field clears). `{ count }`: how many
// nodes match.
export function filterTree(tree, query, { locale } = {}) {
  takeBack(tree)
  const byPath = query.startsWith("/")
  const nodes = Array.from(tree.querySelectorAll("[data-tree-node]"))
  const shown = new Set()
  const holders = new Set()
  let count = 0

  nodes.forEach((node) => {
    const row = rowOf(node)
    if (!row) return
    const matched = byPath ? matchesPath(row.dataset.treePath, query) : matchesTitle(row.dataset.treeTitle ?? "", query, locale)
    if (!matched) return

    count++
    node.setAttribute("data-filter-match", "")
    if (!byPath) markIn(row.querySelector(".admin-tree-row__title"), query, locale)
    shown.add(node)
    for (let above = parentOf(node, tree); above; above = parentOf(above, tree)) {
      shown.add(above)
      holders.add(above)
    }
  })

  const set = readOpenSet()
  nodes.forEach((node) => {
    if (!shown.has(node)) {
      node.hidden = true
      node.setAttribute("data-filter-hidden", "")
    }
    if (holders.has(node)) {
      if (!node.hasAttribute("data-filter-open") && isFolded(node)) {
        setFolded(node, false)
        node.setAttribute("data-filter-open", "")
      }
    } else if (node.hasAttribute("data-filter-open")) {
      node.removeAttribute("data-filter-open")
      setFolded(node, !openByRule(node, set))
    }
  })
  return { count }
}

// Takes back everything `filterTree` wrote, and draws every branch as the
// open set and the path to the open page have it (`openByRule`, which
// reads the path from the nodes' `data-tree-on-path`).
export function clearFilter(tree) {
  takeBack(tree)
  const set = readOpenSet()
  tree.querySelectorAll("[data-tree-node]").forEach((node) => {
    node.removeAttribute("data-filter-open")
    setFolded(node, !openByRule(node, set))
  })
}

// The control a find moves the focus to in each matching node, in the
// tree's order, the hidden ones left out.
export function matchFocuses(tree) {
  return Array.from(tree.querySelectorAll("[data-filter-match]")).filter((node) => !node.hidden).map((node) => {
    if (node.matches("[data-tree-focus]")) return node
    return rowOf(node)?.querySelector("[data-tree-focus]") ?? null
  }).filter(Boolean)
}
