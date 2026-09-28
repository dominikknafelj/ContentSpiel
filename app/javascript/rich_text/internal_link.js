import { Mark } from "@tiptap/core"

// The `internalLink` mark (tiptap spec §3.2/§4.1) -- `RichText::BuiltIns`'
// `internalLink{type, id}`: `type` "page" or "post", `id` that record's
// Integer id. Stored as the *record*, never a URL: the public renderer
// resolves the current path per locale (`PublicSite::Urls#path_for`), so a
// slug change never breaks the link.
//
// In the editor it renders as an `<a>` with no `href` at all (so clicking
// it never navigates away from the editor, and `link`'s own `a[href]` parse
// rule can't claim it on a copy/paste round trip), titled with the
// target's title via `resolveTitle(type, id)` -- an option the
// `admin--rich-text` controller supplies from what the column rendered
// (`#link_titles_json`) plus whatever the picker added this session. No
// title means the target is gone: rendered as "missing" (spec §7).
//
// `excludes: "link internalLink"` -- a run of text links to one place:
// applying either kind of link replaces the other (the controller unsets
// the other mark explicitly as well, see `admin--rich-text#applyLink`), and
// re-pointing an internal link replaces it. ProseMirror's default (a mark
// excludes only itself) stops applying once `excludes` is given, so
// `internalLink` has to name itself: without it, re-pointing added a
// second `internalLink` mark beside the first, a document the server
// refuses (`RichText::MarkType#excludes`, `RichText::BuiltIns`).

const TYPES = [ "page", "post" ]

function toId(value) {
  const id = Number.parseInt(value, 10)
  return Number.isInteger(id) && id > 0 ? id : null
}

export const InternalLink = Mark.create({
  name: "internalLink",
  inclusive: false,
  excludes: "link internalLink",

  addOptions() {
    return {
      resolveTitle: () => null
    }
  },

  addAttributes() {
    return {
      type: {
        default: null,
        parseHTML: (element) => (TYPES.includes(element.getAttribute("data-type")) ? element.getAttribute("data-type") : null),
        renderHTML: (attributes) => ({ "data-type": attributes.type })
      },
      id: {
        default: null,
        parseHTML: (element) => toId(element.getAttribute("data-id")),
        renderHTML: (attributes) => ({ "data-id": attributes.id })
      }
    }
  },

  parseHTML() {
    return [
      {
        tag: "a[data-internal-link]",
        getAttrs: (element) => (TYPES.includes(element.getAttribute("data-type")) && toId(element.getAttribute("data-id")) ? null : false)
      }
    ]
  },

  renderHTML({ mark, HTMLAttributes }) {
    const { type, id } = mark.attrs
    const title = this.options.resolveTitle(type, id)
    const label = type === "post" ? "Post" : "Page"

    return [
      "a",
      {
        ...HTMLAttributes,
        "data-internal-link": "",
        class: title ? "admin-rich-text-internal-link" : "admin-rich-text-internal-link admin-rich-text-missing",
        title: title ? `${label}: ${title}` : `Missing ${label.toLowerCase()} (#${id})`
      },
      0
    ]
  },

  addCommands() {
    return {
      setInternalLink: (attrs) => ({ chain }) => chain().unsetMark("link", { extendEmptyMarkRange: true }).setMark(this.name, { type: attrs.type, id: attrs.id }).run(),
      unsetInternalLink: () => ({ commands }) => commands.unsetMark(this.name, { extendEmptyMarkRange: true })
    }
  }
})
