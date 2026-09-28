// CS Studio's import-map entry point (final fix wave, D; the admin layout
// imports this instead of `application`). Everything the public site loads
// -- Turbo, the site's own controllers -- via `application`, plus CS
// Studio's own controllers (`controllers/admin/*`, identifiers `admin--*`).
// Those, the editor's modules (`rich_text/*`) and Tiptap/ProseMirror are
// `preload: "admin"` in config/importmap.rb: modulepreloaded here, and
// never on a public page, which neither imports nor preloads any of them.
//
// A Turbo visit from an `application` page (signing in) still runs this:
// Turbo appends and executes any `<head>` script the new page has that the
// old one didn't (test/system/admin/entry_point_test.rb).
import "application"
import { registerControllers } from "controllers"

registerControllers((path) => path.startsWith("controllers/admin/"))
