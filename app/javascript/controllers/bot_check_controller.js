import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// Cloudflare Turnstile on the sign-in panel, drawn only when the server asks
// for it (`Admin::SessionsController#new` renders this element only then:
// after repeated failures, and never on a site without both Turnstile
// keys). The widget writes its answer into a hidden `cf-turnstile-response`
// inside the box, which is inside the sign-in form, so the form posts it;
// the server verifies it (`SignIn::BotCheck`). Sign in stays enabled
// whatever the widget says: the server decides.
//
// EXPLICIT RENDERING, because of Turbo. Turnstile's implicit mode draws
// every `.cf-turnstile` once, when its script runs. Turbo keeps the window
// and the script across visits and form answers, and shows a page again
// from its snapshot on Back, so an implicit widget would be drawn on the
// first page only, or (from a snapshot that kept its iframe) twice. So the
// script is loaded once per document with `render=explicit` (a <script>
// added to the head when `window.turnstile` is missing; Turbo's head merge
// keeps scripts), each `connect` draws one widget, and `disconnect` and
// `turbo:before-cache` take it away again: a snapshot never holds a
// widget or its answer, and a page shown from one draws a fresh widget.
// A test defines `window.turnstile` before the element connects, and no
// script is loaded.
//
// THE WIDGET'S OPTIONS. `size` is "flexible" (the box is the panel's
// width, at most 356px) unless the box is narrower than Turnstile's 300px
// minimum, and then "compact"; it is chosen once, when the widget is drawn.
// `theme` is the theme <html data-theme> resolves to, "light" or "dark",
// never Turnstile's "auto", which would follow the system and not the
// person's choice; when the theme switch changes it the widget is drawn
// again in the new one. `language` is the page's `lang`, and `action` is
// the server's (`SignIn::BotCheck::ACTION`), which siteverify must answer
// back.
//
// When the script cannot be loaded (blocked, offline) the hint is replaced
// by the server's sentence (`sessions.new.check_unavailable`, from the
// element's `data-messages`), and the next page tries again. The server's
// hint is put back before Turbo caches the page and on disconnect, so a
// snapshot never says the check failed to load.
//
// The frame is allowed only by the document's policy, which a Turbo fetch
// cannot change: on a site with the keys the sign-in page is always loaded
// whole (`Admin::SessionsController`, "THE POLICY BELONGS TO THE
// DOCUMENT").
const SCRIPT = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
// Turnstile's flexible widget is at least this wide.
const FLEXIBLE_MINIMUM = 300

// The one load of the document's script, shared by every widget drawn in
// it. Forgotten when it fails, so a later page may try again.
let loading = null

function loadTurnstile() {
  if (window.turnstile) return Promise.resolve(window.turnstile)
  if (!loading) {
    loading = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = SCRIPT
      script.async = true
      const failed = () => {
        script.remove()
        loading = null
        reject()
      }
      script.addEventListener("load", () => (window.turnstile ? resolve(window.turnstile) : failed()))
      script.addEventListener("error", failed)
      document.head.append(script)
    })
  }
  return loading
}

export default class extends Controller {
  static targets = ["hint", "widget"]
  static values = { siteKey: String, action: String }

  connect() {
    this.serverHint = this.hintTarget.textContent
    this.removeBeforeCache = () => this.takeBack()
    document.addEventListener("turbo:before-cache", this.removeBeforeCache)
    this.themeObserver = new MutationObserver(() => {
      if (this.widgetId !== undefined && this.theme !== this.drawnTheme) this.redraw()
    })
    this.themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })
    this.draw()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.removeBeforeCache)
    this.themeObserver.disconnect()
    this.takeBack()
  }

  // Everything the script wrote into the page: the widget and the hint.
  takeBack() {
    this.removeWidget()
    this.hintTarget.textContent = this.serverHint
  }

  // A draw whose script arrives after the element left the page draws
  // nothing; one whose element already holds a widget draws no second.
  draw() {
    loadTurnstile().then((turnstile) => {
      if (!this.element.isConnected || this.widgetId !== undefined) return
      this.drawnTheme = this.theme
      this.widgetId = turnstile.render(this.widgetTarget, {
        sitekey: this.siteKeyValue,
        action: this.actionValue,
        theme: this.drawnTheme,
        size: this.widgetTarget.clientWidth < FLEXIBLE_MINIMUM ? "compact" : "flexible",
        language: document.documentElement.lang || "auto",
      })
    }, () => {
      if (this.element.isConnected) this.hintTarget.textContent = messages(this.element).t("sessions.new.check_unavailable")
    })
  }

  redraw() {
    this.removeWidget()
    this.draw()
  }

  removeWidget() {
    if (this.widgetId === undefined) return
    window.turnstile?.remove(this.widgetId)
    this.widgetId = undefined
  }

  get theme() {
    return document.documentElement.dataset.theme === "dark" ? "dark" : "light"
  }
}
