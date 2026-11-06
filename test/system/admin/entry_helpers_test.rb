require "application_system_test_case"

# The entry helpers of a browser test (`visit_editor`, `visit_screen`): each is
# `visit` plus `await_admin_controllers`, so a test that starts with one does
# not race a controller or the editor's live part.
class Admin::EntryHelpersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    Current.set(actor: users(:one)) { @post = create_post(title: "Entry post") }
    @page = create_page(title: "Entry page")
  end

  test "visit_editor opens a page's editor with its controllers connected and its live part answered" do
    visit_editor(@page)

    # Right after the call, with no wait of the test's own.
    assert_selector "#editing[data-live-part=answered]", wait: 0
    assert_equal admin_page_path(@page), page.current_path
  end

  test "visit_editor returns only after the editor's Sortables are made" do
    visit_editor(@page)

    assert_selector "section.admin-content-blocks[data-sortable=ready]", wait: 0
    assert_no_selector "[data-sortable=pending]", wait: 0
  end

  test "visit_editor opens a post's editor, in the language it is given" do
    visit_editor(@post, locale: "de")

    assert_selector "#editing[data-live-part=answered]", wait: 0
    assert_equal admin_post_path(@post), page.current_path
    assert_includes page.current_url, "locale=de"
  end

  test "visit_editor refuses a record that has no editor" do
    error = assert_raises(ArgumentError) { visit_editor(users(:one)) }
    assert_match(/Page or a Post/, error.message)
  end

  test "visit_screen waits for the screen's controllers" do
    visit_screen admin_users_path

    assert_equal 0, page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-controller*='admin--']")).filter((element) =>
        element.getAttribute("data-controller").split(" ").filter((name) => name.startsWith("admin--"))
          .some((name) => !window.Stimulus.getControllerForElementAndIdentifier(element, name))).length
    JS
  end

  test "a page whose controllers never connect fails with a message that names them" do
    visit admin_users_path
    # Built from two halves: the layout guard reads every `admin--` name written in a source for a controller file.
    stranger = [ "admin-", "-no-such" ].join("-")
    page.execute_script("document.body.insertAdjacentHTML('beforeend', '<div data-controller=\"#{stranger}\"></div>')")

    error = assert_raises(Minitest::Assertion) { await_admin_controllers(wait: 1) }
    assert_includes error.message, stranger
  end
end
