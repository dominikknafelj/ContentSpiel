require "application_system_test_case"

class PasswordFieldTest < ApplicationSystemTestCase
  test "the change-password form shows the meter, toggles visibility and blocks a short password" do
    sign_in_via_form users(:one)
    visit admin_account_password_path
    fill_in "New password", with: "short"
    assert_text "Use at least 12 characters."
    assert_selector "[data-password-submit][disabled]"
    fill_in "New password", with: "a much Longer passw0rd"
    assert_text "Strong"
    assert_no_selector "[data-password-submit][disabled]"
    within(find_field("New password").ancestor(".admin-password-field")) { press "Show" }
    assert_equal "text", find_field("New password")[:type]
  end
end
