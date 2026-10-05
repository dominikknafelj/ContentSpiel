require "application_system_test_case"

# `press` clicks the way a person does: Cuprite scrolls the element into view
# and refuses (`MouseEventFailed`) when another element would receive the
# click. `press_by_script` is the named exception that calls `element.click()`
# and so reaches a covered button; every use of it says why a native click
# can't serve.
class PressHelperSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_via_form(users(:one))
    visit admin_root_path
    assert_selector "h1", text: "Dashboard"
    page.execute_script(<<~JS)
      const cover = document.createElement("div")
      cover.style.cssText = "position: fixed; inset: 0; z-index: 2147483647"
      document.body.append(cover)
    JS
  end

  test "press refuses a button another element covers" do
    assert_raises(Capybara::Cuprite::MouseEventFailed) { press "Create draft" }
  end

  test "press_by_script clicks a covered button" do
    fill_in "Title", with: "Covered draft", visible: :all
    press_by_script "Create draft"
    assert_text "Draft created"
  end
end
