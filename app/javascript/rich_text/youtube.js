import { Extension, Node } from "@tiptap/core"
import { Plugin, PluginKey } from "@tiptap/pm/state"

// The `youtube` node (tiptap spec §3.2/§4.1) -- `RichText::BuiltIns`'
// `youtube{id}`, `id` an 11-character video id (`RichText::YOUTUBE_ID_PATTERN`,
// `/\A[\w-]{11}\z/`). An atom: no editable content of its own, just the id.
//
// In the editor it renders as a labelled block, not a live `<iframe>` --
// CS Studio has no reason to load YouTube's player (and its cookies/CSP
// surface) just to show *which* video is embedded; the public site renders
// the real youtube-nocookie embed (`RichText::YoutubeComponent`).

export const YOUTUBE_ID = /^[\w-]{11}$/

// youtube.com/watch?v=ID (with `v` anywhere in the query), youtu.be/ID and
// youtube.com/embed/ID (plus youtube-nocookie.com/embed/ID, what the public
// site itself renders -- so copying an embed's own URL back in works too),
// with or without a scheme or `www.`/`m.`, and with any trailing query or
// fragment (`&t=42s`, `?si=...`). Captures the 11-character id.
const YOUTUBE_URL = /^(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube(?:-nocookie)?\.com\/(?:watch\?(?:[^#\s]*&)?v=|embed\/)|youtu\.be\/)([\w-]{11})(?:[?&#/][^\s]*)?$/i

// The id in `text` when the whole (trimmed) string is a YouTube URL -- or,
// with `allowBareId`, a bare 11-character id (what the toolbar's own
// "YouTube" popover also accepts). `null` otherwise.
export function youtubeIdFrom(text, { allowBareId = false } = {}) {
  const value = (text || "").trim()
  if (allowBareId && YOUTUBE_ID.test(value)) return value

  const match = value.match(YOUTUBE_URL)
  return match ? match[1] : null
}

export const Youtube = Node.create({
  name: "youtube",
  group: "block",
  atom: true,
  draggable: true,
  selectable: true,

  // Default priority, deliberately: Tiptap orders the schema's node types
  // by priority, and the *first* block type is what ProseMirror fills an
  // empty required block with (the trailing node after an embed, a new
  // document) -- that has to stay `paragraph` (priority 1000), never an
  // empty, id-less youtube. The paste handler below needs to run ahead of
  // `link`'s instead, so it lives in its own extension (`YoutubePaste`).

  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: (element) => {
          const id = element.getAttribute("data-youtube-id")
          return YOUTUBE_ID.test(id || "") ? id : null
        },
        renderHTML: (attributes) => ({ "data-youtube-id": attributes.id })
      }
    }
  },

  // Our own rendering (copy/paste between editors), plus the public site's
  // embed `<iframe>` -- anything else (a foreign `<iframe>`, an id that isn't
  // 11 characters) matches no rule and is dropped by the schema.
  parseHTML() {
    return [
      { tag: "div[data-youtube-id]", getAttrs: (element) => (YOUTUBE_ID.test(element.getAttribute("data-youtube-id") || "") ? null : false) },
      {
        tag: "iframe[src]",
        getAttrs: (element) => {
          const id = youtubeIdFrom(element.getAttribute("src"))
          return id ? { id } : false
        }
      }
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return [ "div", { ...HTMLAttributes, class: "admin-rich-text-embed" }, `YouTube video · ${HTMLAttributes["data-youtube-id"]}` ]
  },

  addCommands() {
    return {
      insertYoutube: (id) => ({ commands }) => (YOUTUBE_ID.test(id || "") ? commands.insertContent({ type: this.name, attrs: { id } }) : false)
    }
  }
})

export const YoutubePaste = Extension.create({
  name: "youtubePaste",

  // Ahead of `link` (priority 1000), whose own paste handling would
  // otherwise get the first look at a pasted YouTube URL.
  priority: 1001,

  // The paste rule (tiptap spec §4.1): a paste whose plain text is exactly
  // one YouTube URL becomes a `youtube` node instead of text. A
  // `handlePaste` prop rather than Tiptap's text-matching `addPasteRules`:
  // those run *after* the URL has already been pasted as text (and after
  // `link`'s own paste rule has already turned it into a link), then
  // rewrite it -- a block node replacing inline text mid-paragraph. Taking
  // the paste over up front, before anything was inserted, is both simpler
  // and exact. A URL inside a longer pasted passage stays text (a link).
  addProseMirrorPlugins() {
    const editor = this.editor

    return [
      new Plugin({
        key: new PluginKey("youtubePaste"),
        props: {
          handlePaste: (view, event) => {
            const id = youtubeIdFrom(event.clipboardData?.getData("text/plain"))
            if (!id) return false

            return editor.commands.insertYoutube(id)
          }
        }
      })
    ]
  }
})
