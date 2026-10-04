import { Controller } from "@hotwired/stimulus"

// Show/Hide and the four-bar strength meter (design pass spec §4, handoff
// §9 A10). The meter is a guide, not the rule -- the server's 12-character
// minimum (User::MINIMUM_PASSWORD_LENGTH) is the rule -- so the only thing
// it ever blocks is submitting something the server would refuse anyway.
//
// Lives in controllers/ rather than controllers/admin/ because sign-in,
// password reset and setup load only the `application` entry point. The bar
// colour classes are named only here, so application.css has an explicit
// @source for this file.
//
// The sentences under the bars (handoff "Studio Change Password"): each a
// whole line, so the first one is built from the minimum the component hands
// over (`User::MINIMUM_PASSWORD_LENGTH`) rather than a second copy of the
// number. The server's own refusal stays "Use at least 12 characters.".
const LEVELS = [
  { bars: 1, colour: "bg-danger", hint: (minimum) => `Too short. Use ${minimum} or more characters.` },
  { bars: 2, colour: "bg-warn", hint: () => "Fair. A few unrelated words work well." },
  { bars: 3, colour: "bg-ok", hint: () => "Good." },
  { bars: 4, colour: "bg-ok", hint: () => "Strong." },
]
const COLOURS = ["bg-danger", "bg-warn", "bg-ok"]

export default class extends Controller {
  static targets = ["input", "toggle", "bar", "hint"]
  static values = { minimum: { type: Number, default: 12 } }

  // The server renders a neutral rule line ("Use at least 12 characters.");
  // it stays until something is typed, so an empty field isn't scolded.
  connect() {
    if (this.hasHintTarget) this.initialHint = this.hintTarget.textContent
    this.measure()
  }

  // The button's own text says what pressing it does ("Show" / "Hide"), and
  // that text is its whole state. It deliberately carries no `aria-pressed`:
  // a label that changes *and* a pressed state that flips reads as "Hide,
  // pressed" -- two signals that contradict each other.
  toggle() {
    const showing = this.inputTarget.type === "text"
    this.inputTarget.type = showing ? "password" : "text"
    this.toggleTarget.textContent = showing ? "Show" : "Hide"
  }

  measure() {
    if (!this.hasBarTarget) return
    const value = this.inputTarget.value
    const length = Array.from(value).length
    const level = LEVELS[this.level(value, length)]
    this.barTargets.forEach((bar, index) => {
      bar.classList.remove(...COLOURS)
      bar.classList.toggle("bg-line-strong", value === "" || index >= level.bars)
      if (value !== "" && index < level.bars) bar.classList.add(level.colour)
    })
    this.hintTarget.textContent = value === "" && this.initialHint ? this.initialHint : level.hint(this.minimumValue)
    const submit = this.element.closest("form")?.querySelector("[data-password-submit]")
    if (submit) submit.disabled = length < this.minimumValue
  }

  // 0 too short; then one step per extra character class or 16+ length.
  level(value, length) {
    if (length < this.minimumValue) return 0
    const classes = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter((re) => re.test(value)).length
    const score = (classes >= 3 ? 1 : 0) + (length >= 16 ? 1 : 0)
    return 1 + score
  }
}
