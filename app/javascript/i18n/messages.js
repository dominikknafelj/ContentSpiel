// The strings a script shows, as the server wrote them (docs/reference/i18n.md,
// "A string a script shows"). A controller never holds English of its own:
// the element it lives on (or <body>, for what every screen's scripts share)
// carries `data-messages`, the JSON `Admin::MessagesHelper#messages_data`
// made from the locale files, and
//
//   const text = messages(this.element).t("save_bar.changes", { count: 3 })
//
// reads one. The nearest element at or above `element` that carries
// `data-messages` answers; <body> is the last resort.
//
// A value is a string, or an object of plural categories (`one`, `other`,
// and whichever else the language needs: `few`, `many`, ...), chosen by
// `Intl.PluralRules` for the `@locale` the server named -- English is `one`
// for 1 and `other` otherwise, exactly Rails' rule, and a German or Slavic file
// only has to define the categories its language has, with no script change.
// `%{name}` is replaced by `vars.name`; `count` is itself a variable, so
// "%{count} unsaved changes" needs no extra argument.
//
// Loud on purpose. An unknown key, a plural value asked for without a
// `count`, a placeholder with no variable and a value of any other type all
// THROW: a script that showed "undefined" would go unnoticed, and an error is
// what the system tests' `JsErrorCollector` fails on. The caller puts the
// result into the page with `textContent` (or an attribute), never
// `innerHTML`: the text is data, and a variable (a tag's name) is the editor's.
const parsed = new Map()

function read(element) {
  const holder = element.closest?.("[data-messages]") ?? document.body
  const source = holder.getAttribute("data-messages")
  if (source === null) throw new Error("i18n: no data-messages on the element or any ancestor")

  if (!parsed.has(source)) parsed.set(source, JSON.parse(source))
  return parsed.get(source)
}

export function messages(element) {
  const all = read(element)

  return {
    t(key, vars = {}) {
      if (!Object.hasOwn(all, key)) throw new Error(`i18n: no message "${key}"`)

      let value = all[key]
      if (value !== null && typeof value === "object") {
        if (!("count" in vars)) throw new Error(`i18n: "${key}" is a plural and needs a count`)

        const category = new Intl.PluralRules(all["@locale"] || "en").select(Number(vars.count))
        value = value[category] ?? value.other
        if (value === undefined) throw new Error(`i18n: "${key}" has no "${category}" or "other" form`)
      }
      if (typeof value !== "string") throw new Error(`i18n: "${key}" is not a string`)

      return value.replace(/%\{(\w+)\}/g, (_, name) => {
        if (!(name in vars)) throw new Error(`i18n: "${key}" needs %{${name}}`)

        return String(vars[name])
      })
    }
  }
}
