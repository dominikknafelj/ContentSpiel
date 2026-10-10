// The strings a script shows, as the server wrote them (docs/reference/i18n.md,
// "A string a script shows"). A controller never holds English of its own:
// an element carries `data-messages`, the JSON `Admin::MessagesHelper#
// messages_data` made from the locale files, and
//
//   const text = messages(this.element).t("components.ui.save_bar.changes", { count: 3 })
//
// reads one. EVERY KEY IS RELATIVE TO `admin`: the key above is
// `admin.components.ui.save_bar.changes` in `config/locales/admin/ui.en.yml`,
// and a screen's own are `tags.dialogs.delete_failed`, whatever element carries
// the attribute.
//
// Lookup walks UP. The element itself and each ancestor that carries
// `data-messages` are asked in turn, nearest first, then <body> (which holds the
// shared set, `Admin::MessagesHelper::SCRIPT_MESSAGES`); the first one that has
// the key answers. So a screen or a component may carry a few messages of its
// own around a form whose controller asks for one that lives on <body>, and
// nothing is shadowed. Only when none has it does the lookup throw.
//
// A value is a string, or an object of plural categories (`zero`, `one`, `two`,
// `few`, `many`, `other`), chosen by `Intl.PluralRules` for the `@locale` the
// holder names -- English is `one` for 1 and `other` otherwise, exactly Rails'
// rule -- and a `zero` form, where the file has one, wins for 0 as it does in
// Rails. A language whose file defines `few`/`many` needs no script change. A
// locale tag `Intl` rejects falls back to `other`. (The server's own
// pluralisation is Rails': `one`/`other` only without the `rails-i18n` gem, so
// a `few` form the browser would pick is not one the server can render.)
// `%{name}` is replaced by `vars.name`; `count` is itself a variable.
// `messages(element).locale()` answers the nearest holder's `@locale`.
//
// Loud on purpose. An unknown key, a plural value asked for without a `count`,
// a placeholder with no variable and a value of any other type all THROW: a
// script that showed "undefined" would go unnoticed. (Inside a Stimulus action
// the throw is logged with `console.error`, which the system tests'
// `JsErrorCollector` records.) The caller puts the result into the page with
// `textContent` (or an attribute), never `innerHTML`: the text is data, and a
// variable (a tag's name) is the editor's.
const parsed = new Map()
const rules = new Map()

function payload(holder) {
  const source = holder.getAttribute("data-messages")
  if (!parsed.has(source)) parsed.set(source, JSON.parse(source))
  return parsed.get(source)
}

// The holders to ask, nearest first, <body> last (once).
function holders(element) {
  const found = []
  for (let node = element; node; node = node.parentElement) {
    if (node.hasAttribute?.("data-messages")) found.push(node)
  }
  if (!found.includes(document.body) && document.body.hasAttribute("data-messages")) found.push(document.body)
  return found
}

function category(locale, count) {
  try {
    if (!rules.has(locale)) rules.set(locale, new Intl.PluralRules(locale))
    return rules.get(locale).select(count)
  } catch {
    return "other"
  }
}

export function messages(element) {
  return {
    // The language the nearest holder's texts are in (its `@locale`), for a
    // script that formats a number or a date to go INTO one of them: the
    // figure follows the sentence's language, not the browser's.
    locale() {
      const holder = holders(element)[0]
      return (holder && payload(holder)["@locale"]) || "en"
    },
    t(key, vars = {}) {
      const holder = holders(element).find((candidate) => Object.hasOwn(payload(candidate), key))
      if (!holder) throw new Error(`i18n: no message "${key}"`)

      const all = payload(holder)
      let value = all[key]
      if (value !== null && typeof value === "object") {
        if (!("count" in vars)) throw new Error(`i18n: "${key}" is a plural and needs a count`)

        const count = Number(vars.count)
        const chosen = count === 0 && "zero" in value ? "zero" : category(all["@locale"] || "en", count)
        value = value[chosen] ?? value.other
        if (value === undefined) throw new Error(`i18n: "${key}" has no "${chosen}" or "other" form`)
      }
      if (typeof value !== "string") throw new Error(`i18n: "${key}" is not a string`)

      return value.replace(/%\{(\w+)\}/g, (_, name) => {
        if (!(name in vars)) throw new Error(`i18n: "${key}" needs %{${name}}`)

        return String(vars[name])
      })
    }
  }
}
