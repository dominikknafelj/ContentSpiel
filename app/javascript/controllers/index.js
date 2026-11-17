// Registers Stimulus controllers from the import map.
//
// On its own (imported by the `application` entry point) this registers the
// site's own controllers -- everything under `controllers/` except CS
// Studio's `controllers/admin/*` and a theme's `controllers/theme/*`. CS
// Studio's are registered by the separate `admin` entry point
// (app/javascript/admin.js, final fix wave D), which only CS Studio's layout
// imports, so a public page never imports -- or, per config/importmap.rb's
// `preload: "admin"`, even modulepreloads -- an admin controller, the editor,
// or anything they import. A theme's are registered by the `site` entry
// point (app/javascript/site.js), which only the public layout imports.
// So are the site's own controllers in `PUBLIC_ONLY`: a visitor's page
// alone runs them, and CS Studio, sign-in and setup never import them
// (they are preloaded with the rest of `controllers/`: importmap gives a
// directory's files one preload).
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

// The site's own controllers that only the `site` entry point registers:
// the Search block's suggestions while typing, which a CS Studio screen
// never draws (its search fields are its own), and the Gallery block's
// carousel, which only a public page draws (CS Studio's preview draws one
// through the public layout, which loads `site`).
export const PUBLIC_ONLY = [ "controllers/search_suggest_controller", "controllers/gallery_carousel_controller" ]

registerControllers((path) => !path.startsWith("controllers/admin/") && !path.startsWith("controllers/theme/") && !PUBLIC_ONLY.includes(path))
