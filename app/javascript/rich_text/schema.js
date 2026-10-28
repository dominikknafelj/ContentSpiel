import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import { OrderedList } from "@tiptap/extension-list"
import { Plugin, PluginKey } from "@tiptap/pm/state"
import { Youtube, YoutubePaste } from "rich_text/youtube"
import { Image } from "rich_text/image"
import { InternalLink } from "rich_text/internal_link"
import { Document } from "@tiptap/extension-document"
import { Paragraph } from "@tiptap/extension-paragraph"
import { Text } from "@tiptap/extension-text"
import { HardBreak } from "@tiptap/extension-hard-break"
import { Bold } from "@tiptap/extension-bold"
import { Italic } from "@tiptap/extension-italic"
import { Code } from "@tiptap/extension-code"
import { UndoRedo } from "@tiptap/extensions"
import { SchemaTable, SchemaTableRow, SchemaTableHeader, SchemaTableCell, TableKeys, TableColumnAlignment } from "rich_text/table"

// The editor's schema, in one place, matched against `RichText::Schema`
// (`app/models/rich_text/built_ins.rb`, the source of truth) type by type
// and attribute by attribute -- task 7's "schema fidelity" ruling: anything
// this editor can produce (typed, from the toolbar, or pasted) must pass
// `RichText::Document#validate`, and anything outside the schema must not
// survive a paste. ProseMirror parses pasted HTML against exactly the node
// and mark types registered here, so keeping this list exact is what does
// the constraining.
//
// Nodes: doc paragraph heading bulletList orderedList listItem blockquote
//        codeBlock horizontalRule hardBreak text youtube image
// Marks: bold italic strike code link internalLink
//
// StarterKit (Tiptap 3) brings more than that, so:
// - `underline` is disabled (spec §10: out of scope; the server has no
//   such mark);
// - its bundled `link` is disabled and `@tiptap/extension-link` added
//   below instead, configured for this schema -- one `link` mark, not two;
// - `orderedList` is replaced: Tiptap 3's carries a `type` attr ("a", "i")
//   the server doesn't have; ours keeps only `start`;
// - `heading` is limited to levels 2-4 (`heading.level in: 2..4`), which
//   also means pasted `<h1>`/`<h5>`/`<h6>` parse as paragraphs;
// - `codeBlock` keeps its one attr, `language` (null/absent = no fence
//   info string, which the server skips as an optional attribute).
// The remaining StarterKit extensions (undo/redo, drop/gap cursors, list
// keymap, trailing node) add behaviour, not schema.

// `RichText::BuiltIns.safe_href?`, client-side, rule for rule (Task 7 fix
// round 1, I1) -- the editor must never accept a link the server then
// refuses, which would 422 the save and every later autosave with it:
// decode HTML character references, drop control characters and
// whitespace (what a browser does before deciding a URL's scheme), then
// read the scheme off the front. None means a relative href (allowed);
// otherwise only http, https and mailto. A scheme allowlist, not a URL
// syntax check -- `https://münchen.de` or a raw `|` in a path is a link
// browsers follow fine.
const SCHEME = /^([a-z][a-z0-9+.-]*):/i
const SAFE_SCHEMES = [ "http", "https", "mailto" ]

export function safeHref(value) {
  if (typeof value !== "string") return false

  const textarea = document.createElement("textarea")
  textarea.innerHTML = value
  // eslint-disable-next-line no-control-regex
  const decoded = textarea.value.replace(/[\u0000-\u001f\u007f-\u009f\s]/g, "")
  if (decoded === "") return false

  const scheme = decoded.match(SCHEME)
  return !scheme || SAFE_SCHEMES.includes(scheme[1].toLowerCase())
}

// The stored form of an *absolute* href: what `new URL` makes of it --
// punycode host, percent-encoded path (`https://münchen.de/über` ->
// `https://xn--mnchen-3ya.de/%C3%BCber`). The server accepts either form;
// canonicalising means one link is always stored one way, however it got
// in (typed in the Link popover, pasted, autolinked). A relative href is
// kept as written (resolving it against CS Studio's own origin would
// store the wrong host), and so is anything `URL` can't parse.
//
// Parsed *without* a base (final fix wave, P10): with CS Studio's origin as
// the base, a same-scheme href missing its slashes (`https:example.com`)
// counts as relative to that base and came out as a path on the studio's
// own host; on its own it parses as `https://example.com/`.
export function canonicalHref(value) {
  const href = (value || "").trim()
  if (!SCHEME.test(href)) return href

  try {
    return new URL(href).href
  } catch {
    return href
  }
}

// What the toolbar's Link popover stores for what an editor typed:
// - a bare email address (`a@b.com`) becomes `mailto:a@b.com`;
// - a bare domain (`example.com/docs`, `münchen.de` -- letters and digits
//   of any script, final fix wave P11) gets `https://`, rather than being
//   saved as a relative path that would resolve against this site;
// - then `canonicalHref` (which punycodes a unicode host).
// The bare-domain check comes first: `example.com:8080/x` also has the
// *shape* of a scheme (`example.com:`), but a dotted name followed by a
// numeric port is a host, not a scheme anyone uses.
const BARE_DOMAIN = /^[\p{L}\p{N}_-]+(\.[\p{L}\p{N}_-]+)+(:\d+)?(\/|\?|#|$)/u

export function normalizeHref(value) {
  const href = (value || "").trim()
  if (BARE_DOMAIN.test(href)) return canonicalHref(`https://${href}`)
  if (SCHEME.test(href)) return canonicalHref(href)
  if (/^[^\s@/:?#]+@[^\s@/:?#]+\.[^\s@/:?#]+$/.test(href)) return canonicalHref(`mailto:${href}`)
  return href
}

// `link{href}` and nothing else -- Tiptap's own also stores target, rel,
// class and title. `rel` is still rendered on the editor's own `<a>` via
// `HTMLAttributes` (rendering only; never part of the document). A pasted
// `<a href>` is parsed with its href canonicalised; one that isn't
// `safeHref` matches nothing (Link's own `parseHTML` checks
// `isAllowedUri`), so only its text survives.
//
// `addProseMirrorPlugins` adds one plugin to Link's own: after any change,
// every `link` mark whose href isn't canonical is re-applied with the
// canonical href. That single rule covers every path a link arrives by --
// autolink as you type, Link's URL paste rule, `setLink` -- without
// patching each of Tiptap's own code paths separately.
const SchemaLink = Link.extend({
  addAttributes() {
    return {
      href: { default: null, parseHTML: (element) => canonicalHref(element.getAttribute("href")) }
    }
  },

  addProseMirrorPlugins() {
    const type = this.type

    return [
      ...(this.parent?.() || []),
      new Plugin({
        key: new PluginKey("canonicalLinkHrefs"),
        appendTransaction: (transactions, oldState, newState) => {
          if (!transactions.some((transaction) => transaction.docChanged)) return null

          const fixes = []
          newState.doc.descendants((node, position) => {
            if (!node.isText) return
            node.marks.forEach((mark) => {
              if (mark.type !== type) return
              const canonical = canonicalHref(mark.attrs.href)
              if (canonical !== mark.attrs.href) fixes.push({ from: position, to: position + node.nodeSize, mark, canonical })
            })
          })
          if (fixes.length === 0) return null

          const transaction = newState.tr
          fixes.forEach(({ from, to, mark, canonical }) => {
            transaction.removeMark(from, to, mark)
            transaction.addMark(from, to, type.create({ href: canonical }))
          })
          return transaction
        }
      })
    ]
  }
})

const SchemaOrderedList = OrderedList.extend({
  addAttributes() {
    return {
      start: {
        default: 1,
        parseHTML: (element) => {
          const start = Number.parseInt(element.getAttribute("start") || "", 10)
          return Number.isInteger(start) ? start : 1
        }
      }
    }
  }
})

// The link mark as every body has it, table cells included.
function schemaLink() {
  return SchemaLink.configure({
    openOnClick: false,
    autolink: true,
    linkOnPaste: true,
    defaultProtocol: "https",
    HTMLAttributes: { target: null, rel: "noopener noreferrer nofollow", class: null },
    isAllowedUri: (url) => safeHref(url)
  })
}

// A Table block's body (table block spec decisions 3 and 11; the body rule
// is `HasRichTextBody#body_kind_errors_for`): one table or nothing (`table?`:
// an editor emptied of its table is an empty document, which the server
// takes as a blank body), cells of one paragraph (`rich_text/table.js`), and
// in a cell the marks `HasRichTextBody::TABLE_CELL_MARKS` allows -- bold,
// italic, code, link and internalLink -- and a hard break. No StarterKit:
// it would bring headings, lists, quotes and the rest, which a paste could
// then put into a cell; undo and redo are its one behaviour this needs.
function tableExtensions({ resolveLinkTitle }) {
  return [
    Document.extend({ content: "table?" }),
    Paragraph,
    Text,
    HardBreak,
    Bold,
    Italic,
    Code,
    UndoRedo,
    schemaLink(),
    InternalLink.configure({ resolveTitle: resolveLinkTitle }),
    SchemaTable,
    SchemaTableRow,
    SchemaTableHeader,
    SchemaTableCell,
    TableKeys,
    TableColumnAlignment
  ]
}

// `resolveAssetUrl(assetId)`, `resolveLinkTitle(type, id)` and
// `onEditImage(position)` come from `admin--rich-text--editor` -- see `image.js` /
// `internal_link.js`. `content` is the body's kind (`ContentBlock#body_content_kind`,
// handed over by the column): `"rich"`, every body's today, or `"table"`, a
// Table block's grid. The ordinary set has no table nodes, so a `<table>`
// pasted into a post's body keeps its text and loses its structure.
export function extensions({ resolveAssetUrl, resolveLinkTitle, onEditImage, content = "rich" }) {
  if (content === "table") return tableExtensions({ resolveLinkTitle })

  return [
    StarterKit.configure({
      heading: { levels: [ 2, 3, 4 ] },
      underline: false,
      link: false,
      orderedList: false
    }),
    SchemaOrderedList,
    schemaLink(),
    InternalLink.configure({ resolveTitle: resolveLinkTitle }),
    Youtube,
    YoutubePaste,
    Image.configure({ resolveUrl: resolveAssetUrl, onEdit: onEditImage })
  ]
}
