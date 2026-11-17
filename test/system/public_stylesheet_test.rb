require "application_system_test_case"

# A stylesheet drawn into the page (`Theme::Stylesheet`) across Turbo's
# visits: Turbo merges a head's stylesheets by their markup and reloads the
# page when the tracked elements differ (`data-turbo-track="reload"`,
# `app/views/layouts/application.html.erb`). The integration half is
# test/integration/public_stylesheet_test.rb.
class PublicStylesheetTest < ApplicationSystemTestCase
  FakeAsset = Data.define(:digest, :content, :compiled_content)

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    create_page(title: "About")
  end

  def theme_styles = page.evaluate_script(%(document.head.querySelectorAll("style[data-turbo-track=reload]").length))

  # A mark on the window, which a Turbo visit keeps and a full load loses.
  def mark_window = page.execute_script("window.stylesheetTestMark = true")

  def window_marked? = page.evaluate_script("window.stylesheetTestMark === true")

  def visit_about
    find("header nav a", text: "About").click
    await_js(%(location.pathname === "/about" && document.querySelector("main h1")?.textContent.includes("About")), message: "the About page is shown")
  end

  test "a Turbo visit between two public pages keeps exactly one theme style element" do
    visit "/"
    await_js("window.Turbo !== undefined", message: "Turbo is loaded")
    assert_equal 1, theme_styles
    mark_window

    visit_about
    assert window_marked?, "the visit was Turbo's, not a full load"
    assert_equal 1, theme_styles

    page.go_back
    await_js(%(location.pathname === "/"), message: "back on the home page")
    assert_equal 1, theme_styles
    assert page.evaluate_script(%(getComputedStyle(document.body).fontFamily)).include?("Archivo"), "the drawn-in styles still apply"
  end

  test "a stylesheet changed between two visits is a full load, never a visit that keeps the old styles" do
    visit "/"
    await_js("window.Turbo !== undefined", message: "Turbo is loaded")
    mark_window

    changed = Theme::Stylesheet.new(FakeAsset.new(digest: "dddddddd", content: ".changed-styles{color:red}", compiled_content: ".changed-styles{color:red}"), limit: ThemeCss::INLINE_LIMIT)
    with_singleton_override(Theme::Stylesheet, :current, -> { changed }) do
      visit_about
      assert_not window_marked?, "the page was reloaded"
      assert_equal [ ".changed-styles{color:red}" ], page.evaluate_script(%([...document.head.querySelectorAll("style[data-turbo-track=reload]")].map((style) => style.textContent)))
    end
  end
end
