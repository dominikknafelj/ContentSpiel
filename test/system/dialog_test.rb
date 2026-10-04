require "application_system_test_case"

# The one dialog component and controller (`admin--dialog` on <body>): a
# trigger opens a dialog by id, a destructive one starts on Cancel, Esc
# closes without acting, and the confirm button does the write.
class DialogSystemTest < ApplicationSystemTestCase
  test "a destructive confirm opens on Cancel, Escape backs out, confirming deletes" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    tag = Tag.create!(name: "dialog-tag")
    sign_in_via_form(users(:one))

    visit "/cs-studio/tags"
    await_admin_controllers

    within("##{ActionView::RecordIdentifier.dom_id(tag)}") { press "Delete" }
    assert_selector "dialog[open]"
    assert_equal "Cancel", page.evaluate_script("document.activeElement.textContent.trim()")

    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(tag)}"

    within("##{ActionView::RecordIdentifier.dom_id(tag)}") { press "Delete" }
    within("dialog[open]") { press "Delete" }
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(tag)}"
    assert_not Tag.exists?(tag.id)
  end
end
