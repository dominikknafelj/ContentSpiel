# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# The Tiptap editor's own extensions/schema (tiptap spec §4.1), imported by
# `controllers/admin/rich_text_controller.js` as `rich_text/...`.
pin_all_from "app/javascript/rich_text", under: "rich_text"

# Avo custom JS entrypoint
pin "avo.custom"
pin "sortablejs" # @1.15.7
pin "d3-force" # @3.0.0
# Tiptap 3 and its ProseMirror dependencies (tiptap spec §4.1), vendored by
# `bin/importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-link`
# -- no npm, no CDN at runtime.
#
# One exception to "exactly what `bin/importmap pin` downloaded":
# `@tiptap/core/jsx-runtime` (imported by extension-bold/-blockquote). jspm's
# build of it is a one-line re-export from a shared chunk (`../_/CUaCpXev.js`)
# that the pin command doesn't download, so the browser would resolve it to
# `/_/CUaCpXev.js` and 404, taking the whole editor's module graph down with
# it. The vendored file is instead the package's own self-contained ESM
# build of the same version (`dist/jsx-runtime/jsx-runtime.js`, downloaded
# from jsDelivr -- see the header comment in the file); same exports, no
# imports. Re-pinning/`bin/importmap pristine` re-downloads the broken jspm
# version, so re-apply this after either.
pin "@tiptap/core", to: "@tiptap--core.js" # @3.31.3
pin "@tiptap/extension-link", to: "@tiptap--extension-link.js" # @3.31.3
pin "@tiptap/starter-kit", to: "@tiptap--starter-kit.js" # @3.31.3
pin "@tiptap/core/jsx-runtime", to: "@tiptap--core--jsx-runtime.js" # @3.31.3
pin "@tiptap/extension-blockquote", to: "@tiptap--extension-blockquote.js" # @3.31.3
pin "@tiptap/extension-bold", to: "@tiptap--extension-bold.js" # @3.31.3
pin "@tiptap/extension-code", to: "@tiptap--extension-code.js" # @3.31.3
pin "@tiptap/extension-code-block", to: "@tiptap--extension-code-block.js" # @3.31.3
pin "@tiptap/extension-document", to: "@tiptap--extension-document.js" # @3.31.3
pin "@tiptap/extension-hard-break", to: "@tiptap--extension-hard-break.js" # @3.31.3
pin "@tiptap/extension-heading", to: "@tiptap--extension-heading.js" # @3.31.3
pin "@tiptap/extension-horizontal-rule", to: "@tiptap--extension-horizontal-rule.js" # @3.31.3
pin "@tiptap/extension-italic", to: "@tiptap--extension-italic.js" # @3.31.3
pin "@tiptap/extension-list", to: "@tiptap--extension-list.js" # @3.31.3
pin "@tiptap/extension-paragraph", to: "@tiptap--extension-paragraph.js" # @3.31.3
pin "@tiptap/extension-strike", to: "@tiptap--extension-strike.js" # @3.31.3
pin "@tiptap/extension-text", to: "@tiptap--extension-text.js" # @3.31.3
pin "@tiptap/extension-underline", to: "@tiptap--extension-underline.js" # @3.31.3
pin "@tiptap/extensions", to: "@tiptap--extensions.js" # @3.31.3
pin "@tiptap/pm/commands", to: "@tiptap--pm--commands.js" # @3.31.3
pin "@tiptap/pm/dropcursor", to: "@tiptap--pm--dropcursor.js" # @3.31.3
pin "@tiptap/pm/gapcursor", to: "@tiptap--pm--gapcursor.js" # @3.31.3
pin "@tiptap/pm/history", to: "@tiptap--pm--history.js" # @3.31.3
pin "@tiptap/pm/keymap", to: "@tiptap--pm--keymap.js" # @3.31.3
pin "@tiptap/pm/model", to: "@tiptap--pm--model.js" # @3.31.3
pin "@tiptap/pm/schema-list", to: "@tiptap--pm--schema-list.js" # @3.31.3
pin "@tiptap/pm/state", to: "@tiptap--pm--state.js" # @3.31.3
pin "@tiptap/pm/transform", to: "@tiptap--pm--transform.js" # @3.31.3
pin "@tiptap/pm/view", to: "@tiptap--pm--view.js" # @3.31.3
pin "linkifyjs" # @4.3.3
pin "orderedmap" # @2.1.1
pin "prosemirror-commands" # @1.7.2
pin "prosemirror-dropcursor" # @1.8.4
pin "prosemirror-gapcursor" # @1.4.1
pin "prosemirror-history" # @1.5.0
pin "prosemirror-keymap" # @1.2.3
pin "prosemirror-model" # @1.25.12
pin "prosemirror-schema-list" # @1.5.1
pin "prosemirror-state" # @1.4.4
pin "prosemirror-transform" # @1.12.1
pin "prosemirror-view" # @1.42.5
pin "rope-sequence" # @1.3.4
pin "w3c-keyname" # @2.2.8
