import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import { OrderedList } from "@tiptap/extension-list"
import { Youtube, YoutubePaste } from "rich_text/youtube"
import { Image } from "rich_text/image"
import { InternalLink } from "rich_text/internal_link"

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

// `RichText::BuiltIns.safe_href?`, client-side: decode HTML character
// references and drop control characters *before* deciding what the scheme
// is (the same normalization a browser does), then allow http(s), mailto,
// or no scheme at all (a relative URL). The server re-checks on save
// regardless; this is so the toolbar can refuse with an inline message
// instead of the save failing later, and so a pasted `javascript:` link is
// dropped at parse time rather than kept as a mark the save would reject.
export function safeHref(value) {
  if (typeof value !== "string") return false

  const textarea = document.createElement("textarea")
  textarea.innerHTML = value
  // eslint-disable-next-line no-control-regex
  const decoded = textarea.value.replace(/[\u0000-\u001f\u007f]/g, "").trim()
  if (decoded === "" || /\s/.test(decoded)) return false

  const scheme = decoded.match(/^([a-z][a-z0-9+.-]*):/i)
  return !scheme || [ "http", "https", "mailto" ].includes(scheme[1].toLowerCase())
}

// What the toolbar's Link popover stores for what an editor typed: a bare
// domain ("example.com/docs") gets `https://` rather than being saved as a
// relative path that would resolve against this site; anything else is
// kept as typed (trimmed).
export function normalizeHref(value) {
  const href = (value || "").trim()
  if (/^[\w-]+(\.[\w-]+)+(:\d+)?(\/|\?|#|$)/.test(href) && !/^[a-z][a-z0-9+.-]*:/i.test(href)) return `https://${href}`
  return href
}

// `link{href}` and nothing else -- Tiptap's own also stores target, rel,
// class and title. `rel` is still rendered on the editor's own `<a>` via
// `HTMLAttributes` (rendering only; never part of the document).
const SchemaLink = Link.extend({
  addAttributes() {
    return {
      href: { default: null, parseHTML: (element) => element.getAttribute("href") }
    }
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

// `resolveAssetUrl(assetId)`, `resolveLinkTitle(type, id)` and
// `onEditImage(position)` come from `admin--rich-text` -- see `image.js` /
// `internal_link.js`.
export function extensions({ resolveAssetUrl, resolveLinkTitle, onEditImage }) {
  return [
    StarterKit.configure({
      heading: { levels: [ 2, 3, 4 ] },
      underline: false,
      link: false,
      orderedList: false
    }),
    SchemaOrderedList,
    SchemaLink.configure({
      openOnClick: false,
      autolink: true,
      linkOnPaste: true,
      defaultProtocol: "https",
      HTMLAttributes: { target: null, rel: "noopener noreferrer nofollow", class: null },
      isAllowedUri: (url) => safeHref(url)
    }),
    InternalLink.configure({ resolveTitle: resolveLinkTitle }),
    Youtube,
    YoutubePaste,
    Image.configure({ resolveUrl: resolveAssetUrl, onEdit: onEditImage })
  ]
}
