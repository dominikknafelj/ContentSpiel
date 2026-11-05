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

// A LINK TO AN ANCHOR OF THE PAGE IS THE BROWSER'S, NOT A TURBO VISIT. Turbo 8 (turbo-rails 2.0.23) draws such a link
// again from the server: `findLinkFromClickTarget` skips a link whose
// `link.href.startsWith("#")`, which never holds, since `href` is the
// absolute address, and `Navigator#locationWithActionIsSamePage` answers
// `false` whatever the location. So a section's anchor an editor wrote, a
// theme's table of contents or a heading's link fetched the page and put
// every element in it anew, and whatever a script had written there (a
// Form block's thank-you or its errors) was gone under a visitor who never
// left. Here a click Turbo is about to follow is given back to the browser
// when it goes to this very page (the same origin, path and query) with a
// fragment: the browser moves to the fragment, and Turbo sees only the
// popstate it answers with `historyPoppedWithEmptyState` (it replaces the
// history entry and caches a copy, drawing nothing). A theme's own scripts
// keep their page the same way: this is the site's rule, not one block's.
// Another page, or this path with another query, is still a Turbo visit.
//
// On a turbo-rails upgrade re-read those three places in Turbo's source
// (`findLinkFromClickTarget`, `locationWithActionIsSamePage`,
// `historyPoppedWithEmptyState`) and `Session#willFollowLinkToLocation`,
// whose `applicationAllowsFollowingLinkToLocation` is what this
// `turbo:click` cancels; test/system/form_block_test.rb and
// test/system/code_block_test.rb hold the behaviour.
document.addEventListener("turbo:click", (event) => {
  const url = new URL(event.detail.url, window.location.href)
  const here = window.location
  if (url.hash && url.origin === here.origin && url.pathname === here.pathname && url.search === here.search) event.preventDefault()
})
