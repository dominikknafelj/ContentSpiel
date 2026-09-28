# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# The Tiptap editor's own extensions/schema (tiptap spec §4.1), imported by
# `controllers/admin/rich_text_controller.js` as `rich_text/...`.
pin_all_from "app/javascript/rich_text", under: "rich_text"

pin "sortablejs", preload: false # @1.15.7
pin "d3-force", preload: false # @3.0.0
# Tiptap 3 and its ProseMirror dependencies (tiptap spec §4.1), vendored by
# `bin/importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-link`
# -- no npm, no CDN at runtime. `preload: false` on these (and on sortablejs/
# d3-force), every one of them admin-only: `javascript_importmap_tags` would
# otherwise modulepreload them on every page, public ones included. They're
# imported on demand by the lazily-loaded `controllers/admin/*` (see
# app/javascript/controllers/index.js). Re-add `preload: false` after a
# re-pin -- `bin/importmap pin` writes the line without it.
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
pin "@tiptap/core", to: "@tiptap--core.js", preload: false # @3.31.3
pin "@tiptap/extension-link", to: "@tiptap--extension-link.js", preload: false # @3.31.3
pin "@tiptap/starter-kit", to: "@tiptap--starter-kit.js", preload: false # @3.31.3
pin "@tiptap/core/jsx-runtime", to: "@tiptap--core--jsx-runtime.js", preload: false # @3.31.3
pin "@tiptap/extension-blockquote", to: "@tiptap--extension-blockquote.js", preload: false # @3.31.3
pin "@tiptap/extension-bold", to: "@tiptap--extension-bold.js", preload: false # @3.31.3
pin "@tiptap/extension-code", to: "@tiptap--extension-code.js", preload: false # @3.31.3
pin "@tiptap/extension-code-block", to: "@tiptap--extension-code-block.js", preload: false # @3.31.3
pin "@tiptap/extension-document", to: "@tiptap--extension-document.js", preload: false # @3.31.3
pin "@tiptap/extension-hard-break", to: "@tiptap--extension-hard-break.js", preload: false # @3.31.3
pin "@tiptap/extension-heading", to: "@tiptap--extension-heading.js", preload: false # @3.31.3
pin "@tiptap/extension-horizontal-rule", to: "@tiptap--extension-horizontal-rule.js", preload: false # @3.31.3
pin "@tiptap/extension-italic", to: "@tiptap--extension-italic.js", preload: false # @3.31.3
pin "@tiptap/extension-list", to: "@tiptap--extension-list.js", preload: false # @3.31.3
pin "@tiptap/extension-paragraph", to: "@tiptap--extension-paragraph.js", preload: false # @3.31.3
pin "@tiptap/extension-strike", to: "@tiptap--extension-strike.js", preload: false # @3.31.3
pin "@tiptap/extension-text", to: "@tiptap--extension-text.js", preload: false # @3.31.3
pin "@tiptap/extension-underline", to: "@tiptap--extension-underline.js", preload: false # @3.31.3
pin "@tiptap/extensions", to: "@tiptap--extensions.js", preload: false # @3.31.3
pin "@tiptap/pm/commands", to: "@tiptap--pm--commands.js", preload: false # @3.31.3
pin "@tiptap/pm/dropcursor", to: "@tiptap--pm--dropcursor.js", preload: false # @3.31.3
pin "@tiptap/pm/gapcursor", to: "@tiptap--pm--gapcursor.js", preload: false # @3.31.3
pin "@tiptap/pm/history", to: "@tiptap--pm--history.js", preload: false # @3.31.3
pin "@tiptap/pm/keymap", to: "@tiptap--pm--keymap.js", preload: false # @3.31.3
pin "@tiptap/pm/model", to: "@tiptap--pm--model.js", preload: false # @3.31.3
pin "@tiptap/pm/schema-list", to: "@tiptap--pm--schema-list.js", preload: false # @3.31.3
pin "@tiptap/pm/state", to: "@tiptap--pm--state.js", preload: false # @3.31.3
pin "@tiptap/pm/transform", to: "@tiptap--pm--transform.js", preload: false # @3.31.3
pin "@tiptap/pm/view", to: "@tiptap--pm--view.js", preload: false # @3.31.3
pin "linkifyjs", preload: false # @4.3.3
pin "orderedmap", preload: false # @2.1.1
pin "prosemirror-commands", preload: false # @1.7.2
pin "prosemirror-dropcursor", preload: false # @1.8.4
pin "prosemirror-gapcursor", preload: false # @1.4.1
pin "prosemirror-history", preload: false # @1.5.0
pin "prosemirror-keymap", preload: false # @1.2.3
pin "prosemirror-model", preload: false # @1.25.12
pin "prosemirror-schema-list", preload: false # @1.5.1
pin "prosemirror-state", preload: false # @1.4.4
pin "prosemirror-transform", preload: false # @1.12.1
pin "prosemirror-view", preload: false # @1.42.5
pin "rope-sequence", preload: false # @1.3.4
pin "w3c-keyname", preload: false # @2.2.8
