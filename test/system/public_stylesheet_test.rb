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

  # Capybara's own waits, which outlast a full load: a script waited on in
  # the page (`await_js`) dies with the page a reload replaces.
  def visit_about
    find("header nav a", text: "About").click
    assert_current_path "/about"
    assert_selector "main h1", text: "About"
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
    assert_current_path "/"
    assert_equal 1, theme_styles
    assert page.evaluate_script(%(getComputedStyle(document.body).fontFamily)).include?("Archivo"), "the drawn-in styles still apply"
  end

  test "a stylesheet changed between two visits is a full load, never a visit that keeps the old styles" do
    visit "/"
    await_js("window.Turbo !== undefined", message: "Turbo is loaded")
    mark_window

    changed = Theme::Stylesheet.new(FakeAsset.new(digest: "dddddddd", content: ".changed-styles{color:red}", compiled_content: ".changed-styles{color:red}"), limit: ThemeCss::INLINE_LIMIT)
    with_singleton_override(Theme::Stylesheet, :current, -> { changed }) do
      find("header nav a", text: "About").click
      # Turbo renders no page whose tracked elements differ: it loads it
      # whole, so the changed style is in the head only after that load.
      assert_selector "head style[data-turbo-track=reload]", text: ".changed-styles", visible: :all
      assert_selector "main h1", text: "About"
      assert_not window_marked?, "the page was reloaded"
      assert_equal [ ".changed-styles{color:red}" ], page.evaluate_script(%([...document.head.querySelectorAll("style[data-turbo-track=reload]")].map((style) => style.textContent)))
    end
  end
end
