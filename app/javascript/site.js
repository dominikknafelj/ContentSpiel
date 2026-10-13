// The public site's entry point (theming spec §4, "Scripts"): `application`
// (Turbo and the site's own controllers) plus the theme's controllers, which
// config/importmap.rb pins under controllers/theme/. Only the public layout
// loads it (layouts/application.html.erb), as only CS Studio's layout loads
// `admin`: a theme's script is never imported on a CS Studio screen, on
// sign-in or in setup, because `controllers/index.js` registers neither
// CS Studio's controllers nor a theme's by itself.
import "application"
import { registerControllers } from "controllers"

registerControllers((path) => path.startsWith("controllers/theme/"))
