// Registers every Stimulus controller in the import map.
//
// CS Studio's controllers (`controllers/admin/*`, identifiers `admin--*`) are
// *lazy*-loaded: imported only when an element using one appears on the
// page. Everything else is eager-loaded, as before. The public site shares
// this entrypoint, and eager-loading `admin--rich-text` there would pull in
// Tiptap and the whole ProseMirror stack (~40 modules) on every public page
// view for nothing (Task 7 fix round 1). The Tiptap/ProseMirror pins are
// also `preload: false` in config/importmap.rb, so nothing on a public page
// even modulepreloads them.
//
// The eager half is `eagerLoadControllersFrom("controllers", ...)` with
// the admin directory filtered out -- that helper has no exclude option.
// `lazyLoadControllersFrom` resolves `admin--rich-text` to
// `controllers/admin/rich_text_controller` itself; for any identifier that's
// already registered (every eager one) it does nothing, and the eager loop
// checks the same thing, so neither half registers a controller twice.
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"

const LAZY_PREFIX = "controllers/admin/"

const imports = JSON.parse(document.querySelector("script[type=importmap]").text).imports

Object.keys(imports)
  .filter((path) => /^controllers\/.*_controller$/.test(path) && !path.startsWith(LAZY_PREFIX))
  .forEach((path) => {
    const name = path.replace(/^controllers\//, "").replace("_controller", "").replace(/\//g, "--").replace(/_/g, "-")

    import(path)
      .then((module) => {
        if (!application.router.modulesByIdentifier.has(name)) application.register(name, module.default)
      })
      .catch((error) => console.error(`Failed to register controller: ${name} (${path})`, error))
  })

lazyLoadControllersFrom("controllers", application)
