require "application_system_test_case"

# `i18n/messages.js`: the one way a script shows a string (docs/reference/
# i18n.md). Run in the real page, against the `data-messages` the layout
# renders on <body>, so the helper's JSON and the module's reading of it are
# tested together.
class Admin::MessagesTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit admin_root_path
    await_admin_controllers
  end

  # Runs `body` (a JavaScript expression, with `messages` in scope) in the
  # page and answers what it returned, or `{ "error" => message }` for what it
  # threw.
  def in_page(body)
    page.evaluate_async_script(<<~JS, body)
      const [body, done] = [arguments[0], arguments[arguments.length - 1]]
      import("i18n/messages").then(({ messages }) => {
        try { done({ value: Function("messages", `return (${body})`)(messages) }) }
        catch (error) { done({ error: error.message }) }
      })
    JS
  end

  def create_tag_with_post
    Current.set(actor: users(:one)) { create_post(title: "Tagged", tags: [ "gear" ]) }
  end

  # A <p> carrying its own `data-messages`, as a component's root does.
  def add_messages_element(id, json)
    page.execute_script(<<~JS, id, json)
      const element = document.createElement("p")
      element.id = arguments[0]
      element.setAttribute("data-messages", arguments[1])
      element.innerHTML = '<b class="inner"></b>'
      document.body.append(element)
    JS
  end

  test "a string, a plural and an interpolated sentence read as the server wrote them" do
    assert_equal "Save or cancel your changes first.", in_page(%(messages(document.body).t("components.save_bar.blocked")))["value"]
    assert_equal "1 unsaved change", in_page(%(messages(document.body).t("components.save_bar.changes", { count: 1 })))["value"]
    assert_equal "0 unsaved changes", in_page(%(messages(document.body).t("components.save_bar.changes", { count: 0 })))["value"]
    assert_equal "3 unsaved changes", in_page(%(messages(document.body).t("components.save_bar.changes", { count: 3 })))["value"]
    assert_equal "You have 1 unsaved change on this screen.",
      in_page(%(messages(document.body).t("layout.leave_dialog.body_with_count", { count: 1 })))["value"]
  end

  test "an element asks each data-messages ancestor in turn, then the page's" do
    add_messages_element("near", { "@locale" => "en", "hello" => "Hi %{name}" }.to_json)

    assert_equal "Hi <Dom>", in_page(%(messages(document.querySelector("#near .inner")).t("hello", { name: "<Dom>" })))["value"]
    assert_equal "Save or cancel your changes first.",
      in_page(%(messages(document.querySelector("#near .inner")).t("components.save_bar.blocked")))["value"], "a key only <body> has"
  end

  test "nested holders answer nearest first, and an inner one never hides an outer one's other keys" do
    add_messages_element("outer", { "@locale" => "en", "a" => "outer a", "b" => "outer b" }.to_json)
    page.execute_script(<<~JS)
      const inner = document.createElement("div")
      inner.id = "inner-holder"
      inner.setAttribute("data-messages", JSON.stringify({ "@locale": "en", a: "inner a" }))
      inner.innerHTML = "<i class='leaf'></i>"
      document.getElementById("outer").append(inner)
    JS

    assert_equal [ "inner a", "outer b" ], in_page(%([ "a", "b" ].map((key) => messages(document.querySelector("#inner-holder .leaf")).t(key))))["value"]
    assert_equal "Save or cancel your changes first.",
      in_page(%(messages(document.querySelector("#inner-holder .leaf")).t("components.save_bar.blocked")))["value"]
  end

  test "the tag dialogs' root and an autosaving row both get the page's messages as well as their own" do
    create_tag_with_post
    visit admin_tags_path
    await_admin_controllers
    field = "#tag-#{Tag.first.id}-name"

    assert_equal "SAVING…", in_page(%(messages(document.querySelector("#{field}")).t("components.save_status.saving")))["value"]
    assert_equal "1 unsaved change", in_page(%(messages(document.querySelector("#{field}")).t("components.save_bar.changes", { count: 1 })))["value"]
    root = "[data-controller='admin--tag-dialogs']"
    assert_match(/wasn't deleted/, in_page(%(messages(document.querySelector("#{root}")).t("tags.dialogs.delete_failed")))["value"].to_s)
    assert_equal "SAVING…", in_page(%(messages(document.querySelector("#{root}")).t("components.save_status.saving")))["value"], "the root's own data-messages does not hide <body>'s"

    find(field).set("renamed")
    assert_selector "#tag-#{Tag.first.id}-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}/, wait: 8
  end

  test "a missing key, a plural without a count and a placeholder without a value all throw" do
    add_messages_element("strict", { "@locale" => "en", "greeting" => "Hi %{name}", "n" => { "one" => "a", "other" => "b" } }.to_json)

    assert_match(/no message "nope"/, in_page(%(messages(document.body).t("nope")))["error"])
    assert_match(/needs a count/, in_page(%(messages(document.body).t("components.save_bar.changes")))["error"])
    assert_match(/needs %\{name\}/, in_page(%(messages(document.getElementById("strict")).t("greeting")))["error"])
  end

  test "a zero form wins for 0 as in Rails, and a locale tag Intl rejects falls back to other" do
    add_messages_element("zero", { "@locale" => "en", "n" => { "zero" => "none", "one" => "one", "other" => "many" } }.to_json)
    add_messages_element("badlocale", { "@locale" => "not a locale!", "n" => { "one" => "one", "other" => "many" } }.to_json)

    assert_equal [ "none", "one", "many" ], in_page(%([ 0, 1, 2 ].map((count) => messages(document.getElementById("zero")).t("n", { count }))))["value"]
    assert_equal [ "many", "many" ], in_page(%([ 1, 2 ].map((count) => messages(document.getElementById("badlocale")).t("n", { count }))))["value"]
  end

  test "the plural category follows the language the server names" do
    add_messages_element("pl", { "@locale" => "pl", "n" => { "one" => "%{count} plik", "few" => "%{count} pliki",
      "many" => "%{count} plikow", "other" => "%{count} pliku" } }.to_json)

    assert_equal [ "1 plik", "2 pliki", "5 plikow", "1.5 pliku" ],
      in_page(%([ 1, 2, 5, 1.5 ].map((count) => messages(document.getElementById("pl")).t("n", { count }))))["value"]
  end
end
