// Registers Stimulus controllers from the import map.
//
// This file only says how and what: each entry point calls
// `registerControllers` with its own choice. `application` (setup and
// sign-in, and through `admin` CS Studio too) registers the site's own
// controllers -- everything under `controllers/` except CS Studio's
// `controllers/admin/*`, a theme's `controllers/theme/*` and `PUBLIC_ONLY`.
// CS Studio's are registered by the separate `admin` entry point
// (app/javascript/admin.js), which only CS Studio's layout imports, so a
// public page never imports -- or, per config/importmap.rb's
// `preload: "admin"`, even modulepreloads -- an admin controller, the editor,
// or anything they import. A visitor's page loads the `site` entry point
// (app/javascript/site.js) and not `application`: it registers `SITE`, the
// site's own controllers a public page draws, and a theme's. So the sign-in,
// password, invitation and setup controllers are neither imported nor
// preloaded on a public page: config/importmap.rb preloads `SITE` alone for
// `site` (its `site_controllers`, held to this list by
// test/integration/public_javascript_test.rb).
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

// Every controller of the site's own a public page draws, and so all that
// `site` registers of `controllers/` besides a theme's: the light/dark
// switch, the Code block's copy, the Form block's send, and `PUBLIC_ONLY`.
// A controller a public template starts to use joins this list and
// `site_controllers` in config/importmap.rb.
export const SITE = [ "controllers/theme_controller", "controllers/code_copy_controller", "controllers/form_send_controller", ...PUBLIC_ONLY ]
