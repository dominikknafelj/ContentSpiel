import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import { extensions, safeHref, normalizeHref } from "rich_text/schema"
import { createPopover, createField, createButton } from "rich_text/popover"
import { createTargetSearch } from "rich_text/target_search"

// The Tiptap rich-text editor in CS Studio (tiptap spec §4.1), on
// `Admin::Columns::RichTextColumnComponent` -- see that component's comment
// for every target and value this reads.
//
// The contract with the rest of CS Studio is the hidden `input` target:
// on every document change this writes `JSON.stringify(editor.getJSON())`
// into it and dispatches a bubbling `input` event, which the enclosing
// form's own `admin--saving--autosave` already listens for -- the editor never
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
// opens the one picker (`admin--media--picker`, `Media::PickerComponent`),
// and the picked asset goes on to the image dialog (alt text and caption),
// whose "Insert image" adds `image{asset_id}` (`#picked`, `#dialogClosed`).
// The editor has no upload of its own; the picker's header Upload covers it.
//
// Dialogs (design pass round 2, Task 13): the image, YouTube and "Page link"
// forms are three shared `<dialog>`s rendered once by the layout
// (`Admin::EditorScreen::RichTextDialogsComponent`, `admin--rich-text--dialog`).
// `openDialog` asks for one on `window`, naming this element as the opener;
// the answer is a `rich-text-dialog:closed` event on this element alone (so
// two editors on a page never cross wires), applied by `#dialogClosed`
// through a Tiptap command -- the one path that writes the hidden input and
// fires the autosave `input` event. The Link stays an anchored popover.
export default class extends Controller {
  static targets = [ "input", "editor", "message" ]

  static values = {
    linkTargetsUrl: String,
    locale: String,
    assets: Object,
    linkTitles: Object,
    readOnly: Boolean
  }

  static texts = {
    badLink: "Use an http(s), mailto or relative link",
    pickOrUrl: "Pick a page, or enter a URL",
    invalidContent: "This text contains something the editor can't show, so it's read-only here. Nothing has been changed."
  }

  connect() {
    this.aborter = new AbortController()
    this.popover = null
    this.dialogContext = null
    this.contentInvalid = false
    this.edited = false
    // A view-only editor (access-control design spec §5): the form wraps
    // its fields in a `<fieldset disabled>`, which disables every native
    // control -- the toolbar buttons and the hidden input included -- but
    // not a contenteditable, so the editor itself is mounted read-only to
    // match. Nothing is ever written back, and there's no autosave on the
    // form to send it anyway. A field someone else holds is read-only
    // without a disabled fieldset (its fields are `readonly`, not
    // disabled): the column says so with `readOnly`.
    this.readOnly = this.readOnlyValue || this.element.closest("fieldset[disabled]") !== null
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
        onEditImage: (position) => this.openImageDialog(position)
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
    // A dialog this editor opened is no use to anyone once it is gone (a
    // Turbo Stream replaced its block card): close it, answer nobody.
    if (this.dialogContext) window.dispatchEvent(new CustomEvent("rich-text-dialog:withdraw", { detail: { opener: this.element } }))
    this.dialogContext = null
    this.editor?.destroy()
    this.editor = null
    this.editorTarget.replaceChildren()
  }

  // A form that turned read-only in place (Task 9's `editing/freeze`; nothing calls this yet): the document
  // stays as typed, for copying, and nothing more is written into it.
  lock() {
    this.readOnly = true
    this.editor?.setEditable(false)
    this.element.querySelector("[role=toolbar]")?.setAttribute("hidden", "")
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
    this.element.querySelectorAll("[data-admin--rich-text--editor-command]").forEach((button) => { button.disabled = true })
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
  // `focusout->admin--saving--autosave#saveNow` only fires when focus actually
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

  // Toolbar commands. `data-action="admin--rich-text--editor#<name>"` on each
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
  // keys), the Image button edits that image's alt text and caption (the image
  // dialog) instead
  // of adding another one. Enter on a selected image does the same
  // (`rich_text/image.js`). Otherwise it opens the media picker, with this
  // button as the opener focus returns to on Cancel/Escape.
  image(event) {
    if (!this.editable()) return
    this.showMessage("")

    const { selection } = this.editor.state
    if (selection.node?.type.name === "image") {
      this.openImageDialog(selection.from)
      return
    }
    this.closePopover({ refocus: false })
    // Focus returns to the opener on Cancel/Escape: the item itself sits in
    // the Insert menu, which has closed by then (hidden, unfocusable), so the
    // menu's own button is the opener there.
    const opener = event.currentTarget.closest("[role=menu]")?.closest("[data-controller~='admin--ui--menu']")?.querySelector("[aria-haspopup=menu]") || event.currentTarget
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

    this.element.querySelectorAll("[data-admin--rich-text--editor-command]").forEach((button) => {
      const check = active[button.getAttribute("data-admin--rich-text--editor-command")]
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
  // button: nothing is inserted yet. The image dialog opens for the picked
  // asset (the picked `url` is only for showing it, and its `alt`/`caption`
  // defaults only for the dialog's placeholders -- the node stores the id
  // alone), and "Insert image" there adds `image{asset_id, alt, caption}` at
  // the selection the editor still holds from before the picker opened.
  // Cancelling inserts nothing.
  picked(event) {
    const { id, url } = event.detail || {}
    if (!Number.isInteger(id) || !this.editable()) return

    this.showMessage("")
    if (url) this.assets[id] = { url, alt: event.detail.alt || "", caption: event.detail.caption || "" }
    this.openDialog("image", { mode: "insert", assetId: id, ...this.imageDefaults(id), alt: "", caption: "" })
  }

  // --- AI translation (translation helpers spec §6.4) -----------------------
  //
  // `translate:use` from `admin--translation--translate#use`, dispatched on this editor's
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

    this.popoverSearch?.destroy()
    this.popoverSearch = null
    this.popover.root.remove()
    this.popover = null
    if (refocus) this.editor?.commands.focus()
  }


  // The Link popover: one input that takes either a URL or a title to search
  // for (`rich_text/target_search.js`, the same rows the related-posts chip
  // input shows). Choosing a row makes an internal link
  // (`internalLink{type, id}` -- never a URL, see `rich_text/internal_link.js`);
  // Enter or Apply on typed text makes an external one: http(s), mailto or
  // relative only, checked here before anything is applied (the server
  // validates again on save). Text that already looks like a URL is not
  // searched. Enter picks a row only once one is highlighted (arrow keys):
  // otherwise the typed text is the link, so "https://example.org" + Enter
  // never links to whichever page happened to match first.
  //
  // With text selected it links that text; inside an existing link, it edits
  // that link; with nothing selected it inserts the URL itself (or the
  // target's title) as the link text. "Remove link" shows whenever the
  // selection is already a link of either kind.
  link() {
    if (!this.editable()) return

    const internal = this.editor.isActive("internalLink")
    const current = this.editor.isActive("link") ? this.editor.getAttributes("link").href || "" : ""
    const popover = createPopover({ title: "Link", onSubmit: () => apply(), onClose: () => this.closePopover() })
    const field = createField("URL or search", { value: current, placeholder: "Paste a URL or search pages and posts" })
    const results = document.createElement("ul")
    results.className = "flex max-h-60 flex-col gap-0.5 overflow-y-auto"
    results.setAttribute("aria-label", "Pages and posts")
    const hint = document.createElement("p")
    hint.className = "text-sm text-meta"
    hint.setAttribute("role", "status")
    hint.setAttribute("aria-live", "polite")
    popover.body.append(field.wrapper, results, hint)

    this.popoverSearch = createTargetSearch({
      input: field.input,
      listbox: results,
      message: hint,
      url: this.linkTargetsUrlValue,
      locale: this.localeValue,
      skip: looksLikeUrl,
      onPick: (row) => this.applyInternalLink({ type: row.type, id: row.id }, row.title || `(untitled ${row.type} #${row.id})`)
    })
    // The search clears its own error; a bad-URL message from a previous
    // Apply goes the moment the text changes.
    field.input.addEventListener("input", () => popover.setError(""))

    const apply = () => {
      const typed = field.input.value.trim()
      // A plain word is not a link target: "abo" would otherwise be stored as
      // the relative link `abo`, which goes nowhere. It is either a title to
      // pick from the list or a URL.
      if (!looksLikeUrl(typed)) {
        popover.setError(this.constructor.texts.pickOrUrl)
        return
      }
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
    if (current || internal) {
      popover.actions.append(createButton("Remove link", () => {
        const chain = this.editor.chain().focus()
        if (internal) chain.unsetInternalLink()
        else chain.extendMarkRange("link").unsetLink()
        chain.run()
        this.closePopover()
      }, { variant: "danger" }))
    }
    popover.actions.append(createButton("Cancel", () => this.closePopover()))
    this.openPopover(popover)
  }

  // Insert > Page link: the "Page link" dialog (search, pick one). Same
  // selection rules as the Link popover: with nothing selected the target's
  // title is inserted as the link text.
  internalLink() {
    if (!this.editable()) return

    this.openDialog("page", { locale: this.localeValue, linked: this.editor.isActive("internalLink") })
  }

  applyInternalLink(target, title) {
    const attrs = { type: target.type, id: target.id }
    this.linkTitles[`${target.type}:${target.id}`] = title

    const { empty } = this.editor.state.selection
    if (empty && this.editor.isActive("link")) {
      // The caret is inside an external link: that link is converted (the
      // whole run re-pointed), never split by new text inserted mid-link.
      this.editor.chain().focus().extendMarkRange("link").setInternalLink(attrs).run()
    } else if (empty && !this.editor.isActive("internalLink")) {
      this.editor.chain().focus().insertContent({ type: "text", text: title, marks: [ { type: "internalLink", attrs } ] }).run()
    } else {
      this.editor.chain().focus().extendMarkRange("internalLink").setInternalLink(attrs).run()
    }
    this.closePopover()
  }

  // YouTube: the dialog takes a URL (any form `youtubeIdFrom` knows) or a
  // bare 11-character id -- the same node the paste rule inserts.
  youtube() {
    if (!this.editable()) return

    this.openDialog("youtube")
  }

  // The image just inserted -- not simply the first `image` node for this
  // asset in the document, since the same library image may already appear
  // earlier in it. `insertContent` leaves the selection either *on* the new
  // node (a NodeSelection, when it replaced an empty paragraph) or just after
  // it; in the second case it's the last such node starting before the
  // selection.
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

  // --- Dialogs ---------------------------------------------------------------

  // The library's own alt/caption for an image, in this editor's language
  // (what blank per-use fields fall back to), and where to show it.
  imageDefaults(assetId) {
    const asset = this.assets[assetId] || {}
    return { defaultAlt: asset.alt || "", defaultCaption: asset.caption || "", url: asset.url || "" }
  }

  // Asks the layout's shared dialog for `kind` to open, naming this element as
  // the one to answer. `context` is what applying the answer needs and the
  // dialog doesn't: it stays here, per editor.
  openDialog(kind, detail = {}) {
    this.closePopover({ refocus: false })
    this.dialogContext = { kind, ...detail }
    window.dispatchEvent(new CustomEvent("rich-text-dialog:open", { detail: { ...detail, kind, opener: this.element } }))
  }

  // Alt text and caption for the `image` node at `position` (clicked, or
  // Enter on a selected image). Re-checks it is still an image there when the
  // answer arrives, since the document may have changed meanwhile.
  openImageDialog(position) {
    if (!this.editable()) return

    const node = this.editor.state.doc.nodeAt(position)
    if (!node || node.type.name !== "image") return

    this.openDialog("image", {
      mode: "edit", position, assetId: node.attrs.asset_id,
      alt: node.attrs.alt || "", caption: node.attrs.caption || "",
      ...this.imageDefaults(node.attrs.asset_id)
    })
  }

  // `rich-text-dialog:closed`, dispatched on this element only by the dialog
  // this editor opened -- after a submit and after Cancel/Escape alike. An
  // answer is applied through the editor (a Tiptap command, so the hidden
  // input and the autosave follow); either way focus returns to the editor,
  // whose selection ProseMirror kept while the dialog was up.
  dialogClosed(event) {
    const context = this.dialogContext
    this.dialogContext = null
    const answer = event.detail || {}

    if (context && context.kind === answer.kind && answer.applied && this.editable()) this.applyDialog(context, answer)
    this.editor?.commands.focus()
  }

  applyDialog(context, answer) {
    if (context.kind === "image") {
      this.applyImage(context, answer)
    } else if (context.kind === "youtube") {
      this.editor.chain().focus().insertYoutube(answer.id).run()
    } else if (context.kind === "page") {
      if (answer.remove) this.editor.chain().focus().unsetInternalLink().run()
      else this.applyInternalLink(answer.target, answer.target.title)
    }
  }

  applyImage(context, answer) {
    if (context.mode === "insert") {
      this.editor.chain().focus().insertImage({ asset_id: context.assetId, alt: answer.alt, caption: answer.caption }).run()
      // Selected, so Enter edits it again (`rich_text/image.js`).
      const position = this.insertedImagePosition(context.assetId)
      if (position !== null) this.editor.chain().focus().setNodeSelection(position).run()
      return
    }

    const current = this.editor.state.doc.nodeAt(context.position)
    if (!current || current.type.name !== "image") return
    // Nothing changed: no transaction, so no autosave and no undo entry.
    if (!answer.remove && (current.attrs.alt || "") === answer.alt && (current.attrs.caption || "") === answer.caption) return

    const chain = this.editor.chain().focus().setNodeSelection(context.position)
    if (answer.remove) chain.deleteSelection()
    else chain.updateAttributes("image", { alt: answer.alt, caption: answer.caption })
    chain.run()
  }
}

// Text that is a URL rather than a title to search for: a scheme (http:,
// mailto:, ...), a leading `/` or `#`, or a host with a letters-only TLD of
// two or more ("example.com/docs", `münchen.de`) -- so "v1.2" is a title.
function looksLikeUrl(text) {
  return /^[a-z][a-z0-9+.-]*:/i.test(text) || /^[/#]/.test(text) || /^[^\s/]+\.\p{L}{2,}(?:[/?#:].*)?$/u.test(text)
}
