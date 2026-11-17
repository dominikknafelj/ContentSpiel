// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
//
// The entry point of setup and sign-in (and, through `admin`, of CS Studio):
// Turbo and every controller of the site's own but `PUBLIC_ONLY`. A
// visitor's page does not load it (app/javascript/site.js).
import "@hotwired/turbo-rails"
import { registerControllers, PUBLIC_ONLY } from "controllers"

registerControllers((path) => !path.startsWith("controllers/admin/") && !path.startsWith("controllers/theme/") && !PUBLIC_ONLY.includes(path))
