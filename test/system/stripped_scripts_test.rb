require "application_system_test_case"

# The app's own scripts as production serves them, without their comment
# lines (`ContentSpiel::JsCommentCompiler`, registered by
# config/initializers/assets.rb in production only), run in a browser: a
# public page and CS Studio's editor and Settings load every module with no
# JavaScript error (`JsErrorCollector` fails the test on one) and every
# controller they draw connects. The unit tests hold what the stripper
# removes; this holds that what is left still runs.
#
# The compiler is put on this process's own assembly for the test and taken
# off after it, and Propshaft's cached assets are dropped both times, so the
# server compiles each file again. The browser's cache is emptied both times
# too: the addresses do not change (the test environment's version names no
# stripper), so a file the browser kept from an earlier test would be run in
# place of the stripped one.
class StrippedScriptsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    javascript_compilers << ContentSpiel::JsCommentCompiler
    fresh_assets
  end

  teardown do
    javascript_compilers.delete(ContentSpiel::JsCommentCompiler)
    fresh_assets
  end

  def javascript_compilers = Rails.application.assets.compilers.registrations["text/javascript"]

  def fresh_assets
    Rails.application.assets.load_path.send(:clear_cache)
    page.driver.browser.network.clear(:cache)
  end

  # How many lines of the module the page's import map names start with
  # `//`, as the server sends it now (`no-store`: never the browser's copy).
  def comment_lines_served(name)
    page.evaluate_async_script(<<~JS, name)
      const [name, done] = [arguments[0], arguments[arguments.length - 1]]
      const map = JSON.parse(document.querySelector("script[type=importmap]").textContent)
      fetch(map.imports[name], { cache: "no-store" }).then((response) => response.text())
        .then((text) => done(text.split("\\n").filter((line) => line.trimStart().startsWith("//")).length))
    JS
  end

  # Every controller named on the page that Stimulus registered is connected.
  def assert_every_controller_connected
    missing = page.evaluate_script(<<~JS)
      (() => {
        const app = window.Stimulus
        if (!app) return ["window.Stimulus"]
        const registered = new Set(app.router.modules.map((module) => module.identifier))
        return Array.from(document.querySelectorAll("[data-controller]")).flatMap((element) =>
          element.getAttribute("data-controller").split(" ").filter((name) => name && registered.has(name))
            .filter((name) => !app.getControllerForElementAndIdentifier(element, name)))
      })()
    JS
    assert_empty missing, "these controllers did not connect: #{missing.join(", ")}"
  end

  test "a public page runs the stripped site scripts and its controllers connect" do
    page_record = create_page(title: "Docs")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page_record),
      attributes: { block_type: "code", settings: { "language" => "ruby", "code" => "puts 1" } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page_record)

    visit PublicSite::Urls.new.path_for(page_record, "en")
    await_js("Boolean(window.Stimulus) && Boolean(window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('figure.content-block--code'), 'code-copy'))")

    assert_equal 0, comment_lines_served("site")
    assert_every_controller_connected
  end

  test "CS Studio's editor and Settings run the stripped admin scripts and their controllers connect" do
    sign_in_via_form(users(:one))
    visit_editor(create_page(title: "Docs"))

    assert_equal 0, comment_lines_served("admin")
    assert_equal 0, comment_lines_served("controllers/admin/saving/save_bar_controller")
    assert_every_controller_connected

    visit_screen(admin_settings_path)
    assert_every_controller_connected
  end
end
