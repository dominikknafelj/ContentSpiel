require "application_system_test_case"

# Browser-only behaviour of round 3's Task 16: the System status Copy button
# (with and without the Clipboard API) and the preview bar's geometry.
class Admin::SystemStatusAndPreviewSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "Copy writes the command, says Copied, and announces it politely" do
    visit admin_system_status_path
    await_admin_controllers
    page.execute_script("window.__copied = null; Object.defineProperty(navigator, 'clipboard', { value: { writeText: (text) => { window.__copied = text; return Promise.resolve() } }, configurable: true })")

    press "Copy"

    assert_selector "button", text: "Copied"
    assert_selector "[data-admin--ui--clipboard-target=status][aria-live=polite]", text: "Copied", visible: :all
    assert_equal Setup::SystemCheck::MAIL_FALLBACK_COMMAND, page.evaluate_script("window.__copied")
    # The label comes back.
    assert_selector "button", text: "Copy", exact_text: true
  end

  test "without a Clipboard API the command is selected instead and nothing raises" do
    visit admin_system_status_path
    await_admin_controllers
    page.execute_script("Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true })")

    press "Copy"

    assert_selector "[data-admin--ui--clipboard-target=status]", text: "the text is selected", visible: :all
    assert_equal Setup::SystemCheck::MAIL_FALLBACK_COMMAND, page.evaluate_script("window.getSelection().toString()").strip
  end

  test "the preview bar is fixed at the top and the page starts below it" do
    root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    Page.create!(parent: root, title: "Draft", published_at: nil)

    visit "/preview/draft"

    bar = page.evaluate_script("(() => { const r = document.querySelector('[role=region][aria-label=Preview]').getBoundingClientRect(); return [r.top, r.height, r.width, window.innerWidth] })()")
    assert_equal [ 0, 36 ], bar.first(2)
    assert_equal bar[3], bar[2]
    header_top = page.evaluate_script("document.querySelector('body > div header').getBoundingClientRect().top")
    assert_operator header_top, :>=, 36

    # Scrolled, the bar stays put.
    page.execute_script("document.body.style.minHeight = '3000px'; window.scrollTo(0, 400)")
    assert_equal 0, page.evaluate_script("document.querySelector('[role=region][aria-label=Preview]').getBoundingClientRect().top")
    # Its links are the first tab stops.
    assert_equal "Edit", page.evaluate_script("document.querySelector('a, button, input').textContent")
  end

  # A phone: the status and language drop out, the title truncates, and Exit
  # preview stays on screen and clickable.
  test "at 360px wide Exit preview is inside the viewport and clickable, with a long title" do
    root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    Page.create!(parent: root, title: "A very long title for a page that is only a draft and has to be truncated", slug: "long", published_at: nil)
    page.driver.resize(360, 700)

    visit "/preview/long"

    right = page.evaluate_script("Array.from(document.querySelectorAll('[role=region][aria-label=Preview] a')).find((a) => a.textContent === 'Exit preview').getBoundingClientRect().right")
    assert_operator right, :<=, page.evaluate_script("document.documentElement.clientWidth")
    click_link "Exit preview"
    # The pages landing redirects to Home's editor for this viewer.
    assert_current_path %r{\A/cs-studio/pages}
  ensure
    # The window outlives the test: every later test in this worker would
    # otherwise run at phone width.
    page.driver.resize(1400, 1400)
  end
end
