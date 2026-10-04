require "application_system_test_case"

# The New page and New post dialogs hang from a fixed top edge, like the media
# picker's `.admin-media-picker` (round 3, Task 9, ruling R3): they open as a
# shell with a loading line and the form loads into it, so a centred dialog
# changed height -- and moved its own header, with the Create button at the foot
# -- right under the pointer. The form's request is held here until the first
# measurement is taken, so the test sees the dialog both before and after the
# form arrives every time, whatever the timing.
class Admin::DialogsHangSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "the New page dialog's top edge does not move when its form loads" do
    visit admin_pages_path
    await_admin_controllers
    assert_hang("dialog#new-page-dialog", %r{/pages/new}) { click_link "+ New page" }
  end

  test "the New post dialog's top edge does not move when its form loads" do
    visit admin_posts_path
    await_admin_controllers
    assert_hang("dialog#new-post-dialog", %r{/posts/new}) { click_link "+ New post", match: :first }
  end

  private

  def assert_hang(selector, form_path)
    # Held on the frame's own request: Turbo fetches with `fetch`.
    page.execute_script(<<~JS)
      const original = window.fetch
      const path = new RegExp(#{form_path.source.to_json})
      window.__formHeld = new Promise((release) => { window.__releaseForm = release })
      window.fetch = (url, options) => {
        if (!path.test(String(url?.url || url))) return original(url, options)
        return window.__formHeld.then(() => original(url, options))
      }
    JS
    top = -> { page.evaluate_script("document.querySelector('#{selector}').getBoundingClientRect().top") }

    yield
    assert_selector "#{selector}[open]"
    assert_selector "#{selector} [data-admin--new-record-target=loading]", visible: :visible
    before = top.call
    assert_operator before, :>, 0

    page.execute_script("window.__releaseForm()")
    assert_selector "#{selector} form", wait: 10
    assert_in_delta before, top.call, 0.5, "the dialog moved when its form loaded"
    # And it hangs below the top of the window rather than being flush with it.
    assert_in_delta page.evaluate_script("window.innerHeight * 0.075"), before, 1
  end
end
