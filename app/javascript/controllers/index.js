// Registers Stimulus controllers from the import map.
//
// On its own (imported by the `application` entry point) this registers the
// site's own controllers -- everything under `controllers/` except CS
// Studio's `controllers/admin/*`. Those are registered by the separate
// `admin` entry point (app/javascript/admin.js, final fix wave D), which
// only CS Studio's layout imports, so a public page never imports -- or,
// per config/importmap.rb's `preload: "admin"`, even modulepreloads -- an
// admin controller, the editor, or anything they import.
//
// Eager: each controller is imported and registered as soon as the page
// loads (a dynamic `import()` per controller, as stimulus-loading's own
// eager loader does). An identifier is derived the stimulus-loading way:
// `controllers/admin/rich_text/editor_controller` -> `admin--rich-text--editor`.
import { application } from "controllers/application"

const imports = JSON.parse(document.querySelector("script[type=importmap]").text).imports

export function registerControllers(include) {
  Object.keys(imports)
    .filter((path) => /^controllers\/.*_controller$/.test(path) && include(path))
    .forEach((path) => {
      const name = path.replace(/^controllers\//, "").replace("_controller", "").replace(/\//g, "--").replace(/_/g, "-")

      import(path)
        .then((module) => {
          if (!application.router.modulesByIdentifier.has(name)) application.register(name, module.default)
        })
        .catch((error) => console.error(`Failed to register controller: ${name} (${path})`, error))
    })
}

registerControllers((path) => !path.startsWith("controllers/admin/"))
