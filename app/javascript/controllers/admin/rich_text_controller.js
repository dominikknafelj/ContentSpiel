import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import { extensions, safeHref, normalizeHref } from "rich_text/schema"
import { youtubeIdFrom } from "rich_text/youtube"
import { createPopover, createField, createSelect, createButton } from "rich_text/popover"

// The Tiptap rich-text editor in CS Studio (tiptap spec §4.1), on
// `Admin::Columns::RichTextColumnComponent` -- see that component's comment
// for every target and value this reads.
//
// The contract with the rest of CS Studio is the hidden `input` target:
// on every document change this writes `JSON.stringify(editor.getJSON())`
// into it and dispatches a bubbling `input` event, which the enclosing
// form's own `admin--autosave` already listens for -- the editor never
// saves anything itself. The schema (`rich_text/schema.js`) is
// `RichText::Schema`'s, type for type, so whatever lands in that input is
// something `RichText::Document#validate` accepts.
//
// Lifecycle (task 7's ruling): mount in `connect()`, destroy in
// `disconnect()`, and nothing that outlives either. That's what makes the
// editor survive everything that moves or replaces a block card:
// - a Turbo Stream `replace` of the whole card disconnects this element
//   (its editor destroyed) and connects the new one (a fresh editor);
// - a drag reorder *moves* the card, which Stimulus answers with
//   disconnect-then-connect on the same element -- so `connect()` always
//   empties the mount point first, and reads its content from the hidden
//   input (which has every edit so far), never from the page-load HTML;
// - a Turbo cache snapshot captures the rendered ProseMirror DOM; restoring
//   it connects again, and the same "empty the mount point first" rule is
//   what keeps that from becoming a second, dead editor beside the live one.
// Pending fetches (the link search) are aborted on disconnect, and their
// handlers check the editor is still the one they started with.
//
// Images come from the library (media library Task 8): the Image button
// opens the one picker (`admin--media-picker`, `Media::PickerComponent`)
// and the picked asset is inserted as `image{asset_id}` (`#picked`). The
// editor has no upload of its own; the picker's Upload tab covers it.
export default class extends Controller {
  static targets = [ "input", "editor", "message" ]

  static values = {
    linkTargetsUrl: String,
    locale: String,
    assets: Object,
    linkTitles: Object
  }

  static texts = {
    badLink: "Use an http(s), mailto or relative link",
    badYoutube: "That isn't a YouTube URL or video ID",
    invalidContent: "This text contains something the editor can't show, so it's read-only here. Nothing has been changed.",
    searchFailed: "Search failed — check your connection",
    noResults: "No pages or posts match",
    searchHint: "Type to search titles"
  }

  connect() {
    this.aborter = new AbortController()
    this.popover = null
    this.contentInvalid = false
    this.edited = false
    // A view-only editor (access-control design spec §5): the form wraps
    // its fields in a `<fieldset disabled>`, which disables every native
    // control -- the toolbar buttons and the hidden input included -- but
    // not a contenteditable, so the editor itself is mounted read-only to
    // match. Nothing is ever written back, and there's no autosave on the
    // form to send it anyway.
    this.readOnly = this.element.closest("fieldset[disabled]") !== null
    // A popover left behind in a Turbo cache snapshot (the page was cached
    // with one open) is dead DOM -- its listeners belonged to the previous
    // connection. Same "start from a clean slate" rule as the mount point.
    this.element.querySelectorAll(".admin-rich-text-popover").forEach((stale) => stale.remove())
    // Copies, not the value objects themselves: the media picker and the
    // link picker add to these as the editor is used, and writing a
    // Stimulus value back would re-render nothing useful but cost a
    // data-attribute round trip per pick.
    this.assets = { ...this.assetsValue }
    this.linkTitles = { ...this.linkTitlesValue }

    const mount = document.createElement("div")
    this.editorTarget.replaceChildren(mount)

    this.editor = new Editor({
      element: mount,
      content: this.initialContent(),
      extensions: extensions({
        resolveAssetUrl: (id) => this.assets[id]?.url || null,
        resolveLinkTitle: (type, id) => this.linkTitles[`${type}:${id}`] || null,
        onEditImage: (position) => this.openImagePopover(position)
      }),
      injectCSS: false,
      editable: !this.readOnly,
      enableContentCheck: true,
      // The ProseMirror element is the actual text field, so it carries the
      // textbox role and the column's label (the mount's own
      // `aria-labelledby`, rendered by the component).
      editorProps: {
        attributes: {
          class: "admin-rich-text-content min-h-40 px-3 py-2 focus:outline-2 focus:outline-accent",
          role: "textbox",
          "aria-multiline": "true",
          "aria-labelledby": this.editorTarget.dataset.labelledby || ""
        }
      },
      onContentError: () => this.handleInvalidContent(),
      onUpdate: ({ transaction }) => this.documentChanged(transaction),
      onTransaction: () => this.refreshToolbar()
    })

    this.refreshToolbar()
  }

  disconnect() {
    this.aborter?.abort()
    this.closePopover({ refocus: false })
    this.editor?.destroy()
    this.editor = null
    this.editorTarget.replaceChildren()
  }

  // The hidden input's JSON, or nothing for an empty/absent document (an
  // empty `doc` isn't valid ProseMirror content -- a doc needs at least one
  // block -- and would otherwise trip the content check below).
  initialContent() {
    try {
      const document = JSON.parse(this.inputTarget.value || "null")
      return document && Array.isArray(document.content) && document.content.length > 0 ? document : null
    } catch {
      return null
    }
  }

  // A stored document the editor's schema can't represent (a type
  // registered on the server that this editor doesn't know, say): Tiptap
  // would otherwise load it as an *empty* document, and the first keystroke
  // would then save that over the real one. Read-only and never written
  // back instead -- the stored document stays exactly as it is.
  handleInvalidContent() {
    this.contentInvalid = true
    queueMicrotask(() => this.editor?.setEditable(false))
    this.showMessage(this.constructor.texts.invalidContent)
    this.element.querySelectorAll("[data-admin--rich-text-command]").forEach((button) => { button.disabled = true })
  }

  // Until the first real edit, an update whose own (root) transaction
  // didn't change the document is ignored: that's a plugin normalizing the
  // freshly loaded document in an appended transaction -- Tiptap's trailing
  // node adding an empty paragraph after a final embed on first focus, say
  // -- and writing it would make simply clicking into the editor autosave.
  // After the first edit every update is written (the normalization rides
  // along with it, harmlessly).
  documentChanged(transaction) {
    if (!this.edited && !transaction?.docChanged) return

    this.edited = true
    this.writeDocument()
  }

  // Focus moving between the editor, its toolbar and its popovers is still
  // "inside the field": stop that `focusout` here so the form's
  // `focusout->admin--autosave#saveNow` only fires when focus actually
  // leaves this column (the debounced `input` save still runs meanwhile).
  containFocus(event) {
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) event.stopPropagation()
  }

  writeDocument() {
    if (this.contentInvalid || !this.editor) return

    this.inputTarget.value = JSON.stringify(this.editor.getJSON())
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Keeps the editor's selection (and focus) when a toolbar button is
  // pressed with the mouse -- the button would otherwise take focus first,
  // blurring the editor mid-command. The Insert menu's items are buttons
  // inside the toolbar element, so they are covered too.
  keepFocus(event) {
    if (event.target.closest("button")) event.preventDefault()
  }

  // Toolbar commands. `data-action="admin--rich-text#<name>"` on each
  // button (`RichTextColumnComponent::TOOLBAR_GROUPS` and, for the Insert menu's
  // items, `INSERT_MENU`).
  bold() { this.run((chain) => chain.toggleBold()) }
  italic() { this.run((chain) => chain.toggleItalic()) }
  strike() { this.run((chain) => chain.toggleStrike()) }
  code() { this.run((chain) => chain.toggleCode()) }
  heading2() { this.run((chain) => chain.toggleHeading({ level: 2 })) }
  heading3() { this.run((chain) => chain.toggleHeading({ level: 3 })) }
  heading4() { this.run((chain) => chain.toggleHeading({ level: 4 })) }
  bulletList() { this.run((chain) => chain.toggleBulletList()) }
  orderedList() { this.run((chain) => chain.toggleOrderedList()) }
  blockquote() { this.run((chain) => chain.toggleBlockquote()) }
  codeBlock() { this.run((chain) => chain.toggleCodeBlock()) }
  horizontalRule() { this.run((chain) => chain.setHorizontalRule()) }

  // With an image node selected (keyboard users get there with the arrow
  // keys), the Image button edits that image's alt text and caption instead
  // of adding another one. Enter on a selected image does the same
  // (`rich_text/image.js`). Otherwise it opens the media picker, with this
  // button as the opener focus returns to on Cancel/Escape.
  image(event) {
    if (!this.editable()) return
    this.showMessage("")

    const { selection } = this.editor.state
    if (selection.node?.type.name === "image") {
      this.openImagePopover(selection.from)
      return
    }
    this.closePopover({ refocus: false })
    // Focus returns to the opener on Cancel/Escape: the item itself sits in
    // the Insert menu, which has closed by then (hidden, unfocusable), so the
    // menu's own button is the opener there.
    const opener = event.currentTarget.closest("[role=menu]")?.closest("[data-controller~='admin--menu']")?.querySelector("[aria-haspopup=menu]") || event.currentTarget
    window.dispatchEvent(new CustomEvent("media-picker:open", { detail: { opener } }))
  }

  run(build) {
    if (!this.editable()) return
    this.closePopover({ refocus: false })
    build(this.editor.chain().focus()).run()
  }

  editable() {
    return this.editor && !this.contentInvalid && !this.readOnly
  }

  // Active state for every toolbar button whose command is "on" at the
  // current selection: `aria-pressed` on the toggle buttons (bold, a
  // heading level, a list, ...), `data-active` on the ones that open a
  // popover or insert something (link, image, ...), which aren't toggles
  // and so mustn't announce themselves as pressed/unpressed. The product
  // CSS styles both.
  refreshToolbar() {
    if (!this.editor) return

    const active = {
      bold: () => this.editor.isActive("bold"),
      italic: () => this.editor.isActive("italic"),
      strike: () => this.editor.isActive("strike"),
      code: () => this.editor.isActive("code"),
      heading2: () => this.editor.isActive("heading", { level: 2 }),
      heading3: () => this.editor.isActive("heading", { level: 3 }),
      heading4: () => this.editor.isActive("heading", { level: 4 }),
      bulletList: () => this.editor.isActive("bulletList"),
      orderedList: () => this.editor.isActive("orderedList"),
      blockquote: () => this.editor.isActive("blockquote"),
      codeBlock: () => this.editor.isActive("codeBlock"),
      link: () => this.editor.isActive("link"),
      internalLink: () => this.editor.isActive("internalLink"),
      image: () => this.editor.isActive("image"),
      youtube: () => this.editor.isActive("youtube")
    }

    this.element.querySelectorAll("[data-admin--rich-text-command]").forEach((button) => {
      const check = active[button.getAttribute("data-admin--rich-text-command")]
      const on = Boolean(check && check())
      if (button.hasAttribute("aria-pressed")) {
        button.setAttribute("aria-pressed", on ? "true" : "false")
      } else {
        button.toggleAttribute("data-active", on)
      }
    })
  }

  // --- Media picker (media library Task 8) ---------------------------------
  //
  // `media-picker:picked` from the picker, bubbling up from the Image
  // button: inserts `image{asset_id, alt: "", caption: ""}` at the
  // selection the editor still holds from before the picker opened, then
  // opens the image popover so alt text can be written straight away (the
  // picker has already handed focus back by now). The picked `url` is only
  // for showing the image here, and its `alt`/`caption` defaults only for
  // the popover's placeholders -- the node stores the id alone.
  picked(event) {
    const { id, url } = event.detail || {}
    if (!Number.isInteger(id) || !this.editable()) return

    this.showMessage("")
    if (url) this.assets[id] = { url, alt: event.detail.alt || "", caption: event.detail.caption || "" }
    this.editor.chain().focus().insertImage({ asset_id: id }).run()

    const position = this.insertedImagePosition(id)
    if (position !== null) this.openImagePopover(position)
  }

  // --- AI translation (translation helpers spec §6.4) -----------------------
  //
  // `translate:use` from `admin--translate#use`, dispatched on this editor's
  // hidden input: replaces the document with the suggested one and writes
  // it back exactly like an edit (`writeDocument`, whose `input` event the
  // form's autosave saves). `assets`/`linkTitles` are what the suggestion's
  // images and internal links need to show here -- this language's
  // document may not have referenced them yet. Sets `detail.applied` so
  // the caller knows whether it took: a read-only editor (view only, or
  // stored content it can't show) refuses, and so does a document this
  // schema rejects -- leaving the current one untouched.
  applySuggestion(event) {
    const detail = event.detail || {}
    const suggested = detail.document
    if (!this.editable() || !suggested || typeof suggested !== "object") return

    Object.assign(this.assets, detail.assets || {})
    Object.assign(this.linkTitles, detail.linkTitles || {})
    this.closePopover({ refocus: false })
    this.showMessage("")
    // `errorOnInvalidContent` makes an invalid document throw here instead
    // of loading as an empty one.
    try {
      if (!this.editor.commands.setContent(suggested, { emitUpdate: false, errorOnInvalidContent: true })) return
    } catch {
      return
    }
    this.edited = true
    this.writeDocument()
    detail.applied = true
  }

  // The image just inserted -- not simply the first `image` node for this
  // asset in the document, since the same library image may already
  // appear earlier in it. `insertContent` leaves the selection either *on*
  // the new node (a NodeSelection, when it replaced an empty paragraph) or
  // just after it; in the second case it's the last such node starting
  // before the selection.
  insertedImagePosition(assetId) {
    const { selection } = this.editor.state
    if (selection.node?.type.name === "image" && selection.node.attrs.asset_id === assetId) return selection.from

    const { from } = selection
    let found = null
    this.editor.state.doc.descendants((node, position) => {
      if (position < from && node.type.name === "image" && node.attrs.asset_id === assetId) found = position
      return position < from
    })
    return found
  }

  showMessage(text) {
    if (this.hasMessageTarget) this.messageTarget.textContent = text || ""
  }

  // --- Popovers ------------------------------------------------------------

  openPopover(popover) {
    this.closePopover({ refocus: false })
    this.popover = popover
    this.element.querySelector("[role=toolbar]").after(popover.root)
    popover.root.querySelector("input, select, button")?.focus()
  }

  closePopover({ refocus = true } = {}) {
    if (!this.popover) return

    clearTimeout(this.searchTimer)
    this.searchAborter?.abort()
    this.popover.root.remove()
    this.popover = null
    if (refocus) this.editor?.commands.focus()
  }

  // Link (external): http(s), mailto or relative only, checked here before
  // anything is applied (the server validates again on save). With text
  // selected it links that text; inside an existing link, it edits that
  // link; with nothing selected it inserts the URL itself as the link text.
  link() {
    if (!this.editable()) return

    const current = this.editor.isActive("link") ? this.editor.getAttributes("link").href || "" : ""
    const popover = createPopover({ title: "Link", onSubmit: () => apply(), onClose: () => this.closePopover() })
    const url = createField("URL", { value: current, placeholder: "https://…" })
    popover.body.append(url.wrapper)

    const apply = () => {
      const typed = url.input.value.trim()
      const href = normalizeHref(typed)
      if (!safeHref(href)) {
        popover.setError(this.constructor.texts.badLink)
        return
      }

      const { empty } = this.editor.state.selection
      const chain = this.editor.chain().focus()
      if (!empty) {
        chain.unsetMark("internalLink").setLink({ href })
      } else if (this.editor.isActive("link")) {
        chain.extendMarkRange("link").setLink({ href })
      } else {
        // The text is what was typed (`münchen.de`), the href its
        // canonical form (`https://xn--mnchen-3ya.de/`).
        chain.unsetMark("internalLink").insertContent({ type: "text", text: typed, marks: [ { type: "link", attrs: { href } } ] })
      }
      chain.run()
      this.closePopover()
    }

    popover.actions.append(createButton("Apply", apply, { variant: "primary" }))
    if (current) {
      popover.actions.append(createButton("Remove link", () => {
        this.editor.chain().focus().extendMarkRange("link").unsetLink().run()
        this.closePopover()
      }, { variant: "danger" }))
    }
    popover.actions.append(createButton("Cancel", () => this.closePopover()))
    this.openPopover(popover)
  }

  // Internal link: searches `<admin>/link_targets` (pages and posts by
  // title, in this column's own editing locale, optionally one type) and
  // stores `internalLink{type, id}` -- never a URL (see
  // `rich_text/internal_link.js`). Same selection rules as `link()`: with
  // nothing selected the target's title is inserted as the link text.
  internalLink() {
    if (!this.editable()) return

    const popover = createPopover({ title: "Internal link", onSubmit: () => this.search(query, type, results, popover, { now: true }), onClose: () => this.closePopover() })
    const query = createField("Search pages and posts", { placeholder: "Title…" })
    const type = createSelect("Type", [ [ "", "Pages and posts" ], [ "page", "Pages" ], [ "post", "Posts" ] ])
    const results = document.createElement("ul")
    results.className = "flex max-h-60 flex-col gap-1 overflow-y-auto"
    results.setAttribute("aria-label", "Link targets")

    const hint = document.createElement("li")
    hint.className = "text-sm text-meta"
    hint.textContent = this.constructor.texts.searchHint
    results.append(hint)

    query.input.addEventListener("input", () => this.search(query, type, results, popover))
    type.select.addEventListener("change", () => this.search(query, type, results, popover, { now: true }))

    popover.body.append(query.wrapper, type.wrapper, results)
    if (this.editor.isActive("internalLink")) {
      popover.actions.append(createButton("Remove link", () => {
        this.editor.chain().focus().unsetInternalLink().run()
        this.closePopover()
      }, { variant: "danger" }))
    }
    popover.actions.append(createButton("Cancel", () => this.closePopover()))
    this.openPopover(popover)
  }

  search(query, type, results, popover, { now = false } = {}) {
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.fetchTargets(query.input.value, type.select.value, results, popover), now ? 0 : 200)
  }

  async fetchTargets(q, type, results, popover) {
    if (q.trim() === "" && type === "") return

    this.searchAborter?.abort()
    this.searchAborter = new AbortController()
    const url = new URL(this.linkTargetsUrlValue, window.location.origin)
    url.searchParams.set("q", q.trim())
    url.searchParams.set("locale", this.localeValue)
    if (type) url.searchParams.set("type", type)

    let targets
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.searchAborter.signal })
      if (!response.ok) throw new Error(`link_targets answered ${response.status}`)
      targets = await response.json()
    } catch (error) {
      if (error.name !== "AbortError" && this.popover === popover) popover.setError(this.constructor.texts.searchFailed)
      return
    }
    if (this.popover !== popover) return

    popover.setError("")
    // Unchanged results aren't re-rendered: a result button someone is
    // about to click shouldn't be swapped out from under them by an
    // identical answer to a later keystroke's search.
    const key = JSON.stringify(targets)
    if (results.dataset.key === key) return
    results.dataset.key = key

    results.replaceChildren(...(targets.length ? targets.map((target) => this.targetItem(target)) : [ this.emptyItem() ]))
  }

  targetItem(target) {
    const item = document.createElement("li")
    const title = target.title || `(untitled ${target.type} #${target.id})`
    const button = createButton(title, () => this.applyInternalLink(target, title))
    button.classList.add("w-full", "justify-between")
    const kind = document.createElement("span")
    kind.className = "font-cs-mono text-label uppercase tracking-mono text-meta"
    kind.textContent = ` ${target.type}`
    button.append(kind)
    item.append(button)
    return item
  }

  emptyItem() {
    const item = document.createElement("li")
    item.className = "text-sm text-meta"
    item.textContent = this.constructor.texts.noResults
    return item
  }

  applyInternalLink(target, title) {
    const attrs = { type: target.type, id: target.id }
    this.linkTitles[`${target.type}:${target.id}`] = title

    const { empty } = this.editor.state.selection
    if (empty && !this.editor.isActive("internalLink")) {
      this.editor.chain().focus().unsetMark("link").insertContent({ type: "text", text: title, marks: [ { type: "internalLink", attrs } ] }).run()
    } else {
      this.editor.chain().focus().extendMarkRange("internalLink").setInternalLink(attrs).run()
    }
    this.closePopover()
  }

  // Image: the per-use alt text and caption for the `image` node at
  // `position` (just picked, or clicked). Applied on Done -- re-checking the node is still
  // an image there, since the document may have changed meanwhile.
  openImagePopover(position) {
    if (!this.editable()) return

    const node = this.editor.state.doc.nodeAt(position)
    if (!node || node.type.name !== "image") return

    const popover = createPopover({ title: "Image", onSubmit: () => done(), onClose: () => this.closePopover() })
    // Blank fields fall back to the image's own defaults in this language
    // (`#assets`), which is what their placeholders show -- the generic
    // hint only when the image has no default of its own.
    const defaults = this.assets[node.attrs.asset_id] || {}
    const alt = createField("Alt text", { value: node.attrs.alt || "", placeholder: defaults.alt || "Describe the image" })
    const caption = createField("Caption", { value: node.attrs.caption || "", placeholder: defaults.caption || "" })
    popover.body.append(alt.wrapper, caption.wrapper)

    const done = () => {
      const current = this.editor.state.doc.nodeAt(position)
      if (current && current.type.name === "image") {
        this.editor.chain().focus().setNodeSelection(position).updateAttributes("image", { alt: alt.input.value, caption: caption.input.value }).run()
      }
      this.closePopover()
    }

    popover.actions.append(createButton("Done", done, { variant: "primary" }))
    popover.actions.append(createButton("Remove image", () => {
      const current = this.editor.state.doc.nodeAt(position)
      if (current && current.type.name === "image") this.editor.chain().focus().setNodeSelection(position).deleteSelection().run()
      this.closePopover()
    }, { variant: "danger" }))
    popover.actions.append(createButton("Cancel", () => this.closePopover()))
    this.openPopover(popover)
  }

  // YouTube: a URL (any form `youtubeIdFrom` knows) or a bare 11-character
  // id -- the same node the paste rule inserts.
  youtube() {
    if (!this.editable()) return

    const popover = createPopover({ title: "YouTube", onSubmit: () => insert(), onClose: () => this.closePopover() })
    const url = createField("YouTube URL or video ID", { placeholder: "https://www.youtube.com/watch?v=…" })
    popover.body.append(url.wrapper)

    const insert = () => {
      const id = youtubeIdFrom(url.input.value, { allowBareId: true })
      if (!id) {
        popover.setError(this.constructor.texts.badYoutube)
        return
      }
      this.editor.chain().focus().insertYoutube(id).run()
      this.closePopover()
    }

    popover.actions.append(createButton("Insert", insert, { variant: "primary" }))
    popover.actions.append(createButton("Cancel", () => this.closePopover()))
    this.openPopover(popover)
  }
}
