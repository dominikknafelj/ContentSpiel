# Pin npm packages by running ./bin/importmap
#
# Two entry points (final fix wave, D): `application` (the public site,
# setup and sign-in -- Turbo plus the site's own controllers) and `admin`
# (CS Studio's layout only -- `application` plus `controllers/admin/*`, see
# app/javascript/admin.js). Layouts pick theirs with
# `javascript_importmap_tags` / `javascript_importmap_tags "admin"`.
#
# `preload: "admin"` modulepreloads a module only on pages whose entry point
# is `admin` (importmap-rails' per-entry-point preloading): CS Studio's own
# controllers, the editor's modules, Tiptap/ProseMirror and SortableJS.
# A public page neither imports nor preloads any of them. They all stay in
# the import map itself (it's one shared lookup table), which is harmless:
# a mapping is only fetched when something imports it.
#
# `pin_all_from` directories override one another in declaration order, so
# the `controllers/admin` line must come after the general `controllers`
# one to give those modules `preload: "admin"` instead of `true`.

pin "application"
pin "admin", preload: "admin"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/controllers/admin", under: "controllers/admin", preload: "admin"
# The Tiptap editor's own extensions/schema (tiptap spec §4.1), imported by
# `controllers/admin/rich_text/editor_controller.js` as `rich_text/...`.
pin_all_from "app/javascript/rich_text", under: "rich_text", preload: "admin"
# The one-at-a-time write queue every autosaving form and block action shares.
pin_all_from "app/javascript/saving", under: "saving", preload: "admin"
# The one suggestions search (debounce, abort, stale answers) the chip input and
# the rich-text link search share.
pin_all_from "app/javascript/search", under: "search", preload: "admin"

# The strings a script shows, read from the server's `data-messages`
# (`Admin::MessagesHelper`; docs/reference/i18n.md). Only CS Studio's
# controllers import it today.
pin_all_from "app/javascript/i18n", under: "i18n", preload: "admin"

# The upload queue the Media screen's drop zone and the media picker share:
# files go up one at a time as progress tiles at the start of a grid.
pin_all_from "app/javascript/media", under: "media", preload: "admin"

# The mind graph's modules: imported only by `controllers/admin/mind_graph/graph_controller.js`
# through a dynamic `import()`, so no other CS Studio screen fetches them --
# `preload: false`. `layout_worker.js` is in this directory too but is never
# imported: it is started as a module Worker from its asset URL.
pin_all_from "app/javascript/mind_graph", under: "mind_graph", preload: false

pin "sortablejs", preload: "admin" # @1.15.7
# Vendored for the mind graph's layout WORKER, which imports the file by its
# asset URL (an import map does not apply inside a worker). Nothing in a page
# imports it, so it is not preloaded; the pin stays so `bin/importmap audit`
# and `outdated` still see the package.
pin "d3-force", preload: false # @3.0.0
# Tiptap 3 and its ProseMirror dependencies (tiptap spec §4.1), vendored by
# `bin/importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-link`
# -- no npm, no CDN at runtime. `preload: "admin"` on every one of them (see
# the top of this file); re-add it after a re-pin -- `bin/importmap pin`
# writes the line without it, which would modulepreload the whole editor
# stack on every public page.
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
pin "@tiptap/core", to: "@tiptap--core.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-link", to: "@tiptap--extension-link.js", preload: "admin" # @3.31.3
pin "@tiptap/starter-kit", to: "@tiptap--starter-kit.js", preload: "admin" # @3.31.3
pin "@tiptap/core/jsx-runtime", to: "@tiptap--core--jsx-runtime.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-blockquote", to: "@tiptap--extension-blockquote.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-bold", to: "@tiptap--extension-bold.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-code", to: "@tiptap--extension-code.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-code-block", to: "@tiptap--extension-code-block.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-document", to: "@tiptap--extension-document.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-hard-break", to: "@tiptap--extension-hard-break.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-heading", to: "@tiptap--extension-heading.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-horizontal-rule", to: "@tiptap--extension-horizontal-rule.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-italic", to: "@tiptap--extension-italic.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-list", to: "@tiptap--extension-list.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-paragraph", to: "@tiptap--extension-paragraph.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-strike", to: "@tiptap--extension-strike.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-text", to: "@tiptap--extension-text.js", preload: "admin" # @3.31.3
pin "@tiptap/extension-underline", to: "@tiptap--extension-underline.js", preload: "admin" # @3.31.3
pin "@tiptap/extensions", to: "@tiptap--extensions.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/commands", to: "@tiptap--pm--commands.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/dropcursor", to: "@tiptap--pm--dropcursor.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/gapcursor", to: "@tiptap--pm--gapcursor.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/history", to: "@tiptap--pm--history.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/keymap", to: "@tiptap--pm--keymap.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/model", to: "@tiptap--pm--model.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/schema-list", to: "@tiptap--pm--schema-list.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/state", to: "@tiptap--pm--state.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/transform", to: "@tiptap--pm--transform.js", preload: "admin" # @3.31.3
pin "@tiptap/pm/view", to: "@tiptap--pm--view.js", preload: "admin" # @3.31.3
pin "linkifyjs", preload: "admin" # @4.3.3
pin "orderedmap", preload: "admin" # @2.1.1
pin "prosemirror-commands", preload: "admin" # @1.7.2
pin "prosemirror-dropcursor", preload: "admin" # @1.8.4
pin "prosemirror-gapcursor", preload: "admin" # @1.4.1
pin "prosemirror-history", preload: "admin" # @1.5.0
pin "prosemirror-keymap", preload: "admin" # @1.2.3
pin "prosemirror-model", preload: "admin" # @1.25.12
pin "prosemirror-schema-list", preload: "admin" # @1.5.1
pin "prosemirror-state", preload: "admin" # @1.4.4
pin "prosemirror-transform", preload: "admin" # @1.12.1
pin "prosemirror-view", preload: "admin" # @1.42.5
pin "rope-sequence", preload: "admin" # @1.3.4
pin "w3c-keyname", preload: "admin" # @2.2.8
