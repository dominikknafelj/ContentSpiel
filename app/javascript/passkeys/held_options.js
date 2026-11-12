// The options a passkey script holds for its next press, kept from lapsing.
//
// The prompt opens only inside the press (`passkeys/ceremony`, "THE PROMPT
// OPENS IN THE PRESS"), so a script fetches its options before the press
// and holds them. The server answers them for five minutes
// (`PasskeyChallenges::LIFETIME`, its check of the challenge's `at`) and
// keeps one challenge per purpose, the latest: options a page held past
// that, or options another tab's later fetch replaced, are refused as a
// wrong passkey. So the set held here is replaced:
//
// - REFRESH_AFTER after it arrived, while the tab is shown (a hidden tab
//   waits, so it never takes the challenge from the tab in use);
// - whenever the tab is shown again, which gives the tab in use the latest
//   challenge;
// - at a press, when the set is older than FRESH_FOR or a fresh one is on
//   its way (`take` answers null, `late` is true, and `takeLate` waits for
//   the fresh set). The prompt then opens after an await, which WebKit may
//   refuse as outside the press; that is a closed prompt, which says
//   nothing, and the next press has the fresh set.
//
// Only while `wanted()` (the caller is waiting for a press: always on a
// page, while its dialog is open in a dialog) is a set fetched or kept;
// otherwise a set due for replacing is dropped. One fetch is in flight at a
// time, and an answer that `drop` or `stop` has passed over is never held.
// The page's clock is `performance.now()`, so a change of the computer's
// clock moves nothing.
export const REFRESH_AFTER = 4 * 60 * 1000
export const FRESH_FOR = 4.5 * 60 * 1000

export class HeldOptions {
  // `load`: an async function answering a fresh set, or null when none
  // could be had.
  constructor(load, { wanted = () => true } = {}) {
    this.load = load
    this.wanted = wanted
    this.options = null
    this.heldAt = 0
    this.timer = null
    this.loading = null
    this.shown = () => {
      if (document.visibilityState === "visible" && this.options) this.due()
    }
  }

  start() {
    document.addEventListener("visibilitychange", this.shown)
  }

  stop() {
    document.removeEventListener("visibilitychange", this.shown)
    this.drop()
  }

  // A fresh set, held and answered; null when none could be had or it was
  // passed over.
  refresh() {
    if (this.loading) return this.loading

    const loading = Promise.resolve()
      .then(() => this.load())
      .catch(() => null)
      .then((options) => {
        if (this.loading !== loading) return null
        this.loading = null
        if (options && this.wanted()) this.hold(options)
        return options && this.wanted() ? options : null
      })
    this.loading = loading
    return loading
  }

  hold(options) {
    this.options = options
    this.heldAt = performance.now()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      if (document.visibilityState === "visible") this.due()
    }, REFRESH_AFTER)
  }

  // The held set, given up, when it is fresh and no fresher one is on its
  // way; otherwise null.
  take() {
    if (!this.options || this.loading || performance.now() - this.heldAt >= FRESH_FOR) return null

    const options = this.options
    this.options = null
    clearTimeout(this.timer)
    return options
  }

  // A set is held but too old to use, or a fresh one is on its way.
  get late() {
    return Boolean(this.loading) || (Boolean(this.options) && performance.now() - this.heldAt >= FRESH_FOR)
  }

  // The fresh set a late press waits for, given up as `take` gives it.
  async takeLate() {
    await (this.loading || this.refresh())
    return this.take()
  }

  // Waits out a fetch in flight, so a caller's own fetch of options is never
  // answered before it and replaced by it on the server.
  async settled() {
    if (this.loading) await this.loading
  }

  drop() {
    this.options = null
    this.loading = null
    clearTimeout(this.timer)
  }

  due() {
    if (this.wanted()) this.refresh()
    else this.drop()
  }
}
