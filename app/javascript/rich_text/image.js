import { Node } from "@tiptap/core"

// The `image` node (tiptap spec §3.2/§4.1) -- `RichText::BuiltIns`'
// `image{asset_id, alt, caption}`: `asset_id` an existing `Media::Asset`'s id
// (an Integer, required), `alt`/`caption` optional Strings, inserted as
// `""` (spec §4.1). Exactly those three attrs and nothing else -- in
// particular no `src`: the document stores which asset, never where it
// happens to live today.
//
// The editor still has to *show* the picture, so `resolveUrl(assetId)` (an
// option the `admin--rich-text` controller supplies) looks the URL up in
// what the column rendered (`Admin::Columns::RichTextColumnComponent
// #asset_urls_json`) plus whatever this session uploaded. No URL means the
// asset is gone: the node view shows a "missing" placeholder (spec §7) --
// the public renderer draws nothing for it at all.
//
// `onEdit(position)` is the controller's image popover (alt/caption); the
// node view calls it when the image is clicked.

function toAssetId(value) {
  const id = Number.parseInt(value, 10)
  return Number.isInteger(id) && id > 0 ? id : null
}

export const Image = Node.create({
  name: "image",
  group: "block",
  atom: true,
  draggable: true,
  selectable: true,

  addOptions() {
    return {
      resolveUrl: () => null,
      onEdit: () => {}
    }
  },

  addAttributes() {
    return {
      asset_id: {
        default: null,
        parseHTML: (element) => toAssetId(element.getAttribute("data-asset-id")),
        renderHTML: (attributes) => ({ "data-asset-id": attributes.asset_id })
      },
      alt: {
        default: "",
        parseHTML: (element) => element.getAttribute("data-alt") || "",
        renderHTML: (attributes) => ({ "data-alt": attributes.alt })
      },
      caption: {
        default: "",
        parseHTML: (element) => element.getAttribute("data-caption") || "",
        renderHTML: (attributes) => ({ "data-caption": attributes.caption })
      }
    }
  },

  // Only our own serialization (copy/paste between CS Studio editors). A
  // pasted `<img>` from anywhere else has no `Media::Asset` behind it, so it
  // matches nothing and the schema drops it -- uploading is the one way an
  // image gets in.
  parseHTML() {
    return [ { tag: "figure[data-asset-id]", getAttrs: (element) => (toAssetId(element.getAttribute("data-asset-id")) ? null : false) } ]
  },

  renderHTML({ HTMLAttributes }) {
    return [ "figure", HTMLAttributes ]
  },

  addCommands() {
    return {
      insertImage: (attrs) => ({ commands }) => commands.insertContent({ type: this.name, attrs: { asset_id: attrs.asset_id, alt: attrs.alt || "", caption: attrs.caption || "" } })
    }
  },

  // Enter on a selected image opens its alt/caption popover -- the
  // keyboard route to what a click on the image does.
  addKeyboardShortcuts() {
    return {
      Enter: ({ editor }) => {
        const { selection } = editor.state
        if (selection.node?.type.name !== this.name) return false

        this.options.onEdit(selection.from)
        return true
      }
    }
  },

  addNodeView() {
    const { resolveUrl, onEdit } = this.options

    return ({ node, getPos }) => {
      const dom = document.createElement("figure")
      dom.className = "admin-rich-text-image"
      dom.setAttribute("contenteditable", "false")

      const render = (current) => {
        const { asset_id: assetId, alt, caption } = current.attrs
        const url = resolveUrl(assetId)
        dom.replaceChildren()
        dom.dataset.assetId = assetId ?? ""

        if (url) {
          const img = document.createElement("img")
          img.src = url
          img.alt = alt || ""
          dom.append(img)
        } else {
          const missing = document.createElement("div")
          missing.className = "admin-rich-text-embed admin-rich-text-missing"
          missing.textContent = `Missing image (#${assetId ?? "?"})`
          dom.append(missing)
        }

        const meta = document.createElement("figcaption")
        meta.textContent = caption || (alt ? `Alt: ${alt}` : "No alt text — click to add")
        dom.append(meta)
      }

      render(node)
      dom.addEventListener("click", () => {
        const position = typeof getPos === "function" ? getPos() : null
        if (typeof position === "number") onEdit(position)
      })

      return {
        dom,
        update(updated) {
          if (updated.type.name !== "image") return false
          render(updated)
          return true
        },
        selectNode() { dom.classList.add("is-selected") },
        deselectNode() { dom.classList.remove("is-selected") },
        ignoreMutation: () => true
      }
    }
  }
})
