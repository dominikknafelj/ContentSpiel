import { messages } from "i18n/messages"

// THE OPEN SET: which branches of a page tree a person has opened or folded,
// kept per browser in the cookie `cs_tree_open` and shared by both trees.
// This module is its one writer (`admin_design_rules_test.rb`, "the open set
// has one writer"); the server reads it (`TreeOpenSet`) and draws the folds
// from the first paint, and the scripts only toggle them after.
//
// The format is `TreeOpenSet`'s: page ids joined by `.`, the newest first, a
// bare id opened beyond the default and `-id` folded where the default would
// show it open. Nothing but page ids is ever written, on the tree's
// `data-tree-open-path` (the admin path) only, so a visitor's page is never
// sent it; a tree without that attribute writes nothing.
//
// THE RULE is `TreeOpenSet#open?`: the path to the selected page is open
// (a view state, never stored), else a fold folds, else the root is open,
// else only an open opens. So a toggle is written relative to its node's
// default (`openByDefault`: the root, and an ancestor of the selected page):
// opening drops the id's fold and stores an open only where the default is
// folded; folding is the mirror.
//
// THE TREE'S DOM, which both trees draw and `openPathIn`, `setFolded` and
// `admin--tree--disclosure` read: the tree is the `.admin-tree` element with
// `data-tree-open-path`; a node is `[data-tree-node]`, its row
// `[data-tree-row][data-tree-id]` and its children `[data-tree-children]`; a
// node's parent is the closest `[data-tree-node]` above it; the root carries
// `data-tree-root` and the selected page's ancestors `data-tree-on-path`; the
// element holding `aria-expanded` is the node itself when it is a
// `[role="treeitem"]`, else its row's disclosure button.

const COOKIE = "cs_tree_open"
const LIMIT = 300
const MAX_BYTES = 4096
const YEAR = 31536000
const ENTRY = /^-?[1-9]\d{0,18}$/

// The entries a value holds, the newest first, one per id, junk dropped.
function entriesOf(value) {
  if (!value || value.length > MAX_BYTES) return []

  const seen = new Set()
  return value.split(".").slice(0, LIMIT).filter((entry) => {
    if (!ENTRY.test(entry)) return false
    const id = entry.replace(/^-/, "")
    if (seen.has(id)) return false
    seen.add(id)
    return true
  })
}

function cookieValue() {
  const pair = document.cookie.split("; ").find((each) => each.startsWith(`${COOKIE}=`))
  return pair ? pair.slice(COOKIE.length + 1) : ""
}

function write(tree, entries) {
  const path = tree?.dataset.treeOpenPath
  if (!path) return

  const kept = entries.slice(0, LIMIT)
  while (kept.join(".").length > MAX_BYTES - COOKIE.length - 1) kept.pop()
  const value = kept.join(".")
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  const age = value ? YEAR : 0
  document.cookie = `${COOKIE}=${value}; path=${path}; max-age=${age}; SameSite=Lax${secure}`
}

// `{ opened, folded }`, two Sets of bare page ids (strings), read from `seed`
// (a value in the cookie's format, for the mind graph's list, which does not
// read it yet) when one is given, else from the cookie.
export function readOpenSet(seed = null) {
  const opened = new Set()
  const folded = new Set()
  entriesOf(seed ?? cookieValue()).forEach((entry) => {
    if (entry.startsWith("-")) folded.add(entry.slice(1))
    else opened.add(entry)
  })
  return { opened, folded }
}

// Stores a person's open (`open` true) or fold of page `id`'s branch, read
// against the cookie as it stands now, so a toggle in another tab is kept.
export function setOpen(tree, id, open, { openByDefault = false } = {}) {
  const key = String(id)
  const entries = entriesOf(cookieValue()).filter((entry) => entry.replace(/^-/, "") !== key)
  if (open && !openByDefault) entries.unshift(key)
  if (!open && openByDefault) entries.unshift(`-${key}`)
  write(tree, entries)
}

// Drops the folds of `ids` (the path to a page just opened): a fold of an
// ancestor of the open page holds until the person goes to a page.
export function forgetFolds(tree, ids) {
  const keys = new Set(Array.from(ids, String))
  const entries = entriesOf(cookieValue())
  const kept = entries.filter((entry) => !(entry.startsWith("-") && keys.has(entry.slice(1))))
  if (kept.length !== entries.length) write(tree, kept)
}

// Is the branch of `node` open by the rule, the open set's `{ opened, folded }`
// read against it?
export function openByRule(node, { opened, folded }) {
  const id = idOf(node)
  if (node.hasAttribute("data-tree-on-path")) return true
  if (folded.has(id)) return false
  return node.hasAttribute("data-tree-root") || opened.has(id)
}

// The bare page id of `node`, from its own row.
export function idOf(node) {
  const row = node.matches("[data-tree-row]") ? node : node.querySelector(":scope > [data-tree-row]")
  return row?.dataset.treeId ?? null
}

// The element that says whether `node`'s branch is open.
export function expanderOf(node) {
  if (node.matches('[role="treeitem"]')) return node
  return node.querySelector(":scope > [data-tree-row] > .admin-tree-row__disclosure[aria-expanded]")
}

function childrenOf(node) {
  return node.querySelector(":scope > [data-tree-children]")
}

export function isFolded(node) {
  return node.hasAttribute("data-folded")
}

// Draws `node` folded or open: its `data-folded`, its children's `hidden`,
// and its expander's `aria-expanded` and, on a button, its name in the
// tree's words ("Fold %{title}" / "Unfold %{title}"). Each is written only
// where it differs, so drawing what the server drew changes nothing in the
// page; a row redrawn under its node is drawn again from the node this way.
// True when something changed.
export function setFolded(node, folded) {
  const expander = expanderOf(node)
  const list = childrenOf(node)
  if (!expander || !list) return false

  let changed = false
  const put = (element, name, value) => {
    if (element.getAttribute(name) === value) return
    element.setAttribute(name, value)
    changed = true
  }
  if (isFolded(node) !== folded) { node.toggleAttribute("data-folded", folded); changed = true }
  if (list.hidden !== folded) { list.hidden = folded; changed = true }
  put(expander, "aria-expanded", String(!folded))
  if (expander.matches("button")) {
    const title = node.querySelector(":scope > [data-tree-row]")?.dataset.treeTitle ?? ""
    put(expander, "aria-label", messages(expander).t(folded ? "components.ui.tree_item.unfold" : "components.ui.tree_item.fold", { title }))
  }
  return changed
}

function nodeFor(tree, id) {
  return tree.querySelector(`[data-tree-row][data-tree-id="${CSS.escape(String(id))}"]`)?.closest("[data-tree-node]") ?? null
}

// THE PATH TO THE OPEN PAGE, page `id` (or none): its ancestors are drawn
// open and marked `data-tree-on-path` (the marks of any earlier path are
// taken away), and their folds are forgotten, so the selected row is never
// inside a folded branch. Nothing of the path is stored as an open.
export function openPathIn(tree, id) {
  tree.querySelectorAll("[data-tree-on-path]").forEach((node) => node.removeAttribute("data-tree-on-path"))
  const node = id == null ? null : nodeFor(tree, id)
  if (!node) return

  const ids = []
  for (let above = node.parentElement?.closest("[data-tree-node]"); above && tree.contains(above); above = above.parentElement?.closest("[data-tree-node]")) {
    above.setAttribute("data-tree-on-path", "")
    setFolded(above, false)
    const aboveId = idOf(above)
    if (aboveId) ids.push(aboveId)
  }
  forgetFolds(tree, ids)
}
