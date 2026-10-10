require "test_helper"

class Admin::Ui::ErrorSummaryComponentTest < ViewComponent::TestCase
  test "a danger-tint box that lists each field's errors as links to the field" do
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: { "email_address" => [ "has already been taken" ], "password" => [ "Use at least 12 characters." ] },
      field_ids: { "email_address" => "user_email", "password" => "user_password" }))
    assert_selector ".admin-error-summary[role=alert][tabindex='-1'].bg-danger-tint"
    assert_text "2 things need fixing"
    assert_selector "a[href='#user_email']", text: "Email address has already been taken"
    assert_selector "a[href='#user_password']", text: "Use at least 12 characters."
  end

  test "one error reads in the singular, and no errors render nothing" do
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: { "name" => [ "is too long" ] }))
    assert_text "1 thing needs fixing"
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: {}))
    assert_no_selector ".admin-error-summary"
  end

  test "real User errors: fragments get the field name, whole sentences print as they are" do
    user = User.new(email_address: "", password: "short", password_confirmation: "other")
    user.valid?
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: user.errors))

    assert_text "Email address can't be blank"
    assert_text "Use at least 12 characters."
    assert_no_text "Password Use at least"
    assert_text "Password confirmation doesn't match Password"
  end

  test "the password messages that carry their own prefix are not prefixed twice" do
    user = User.new(email_address: "a@example.com", password: "x" * 80, password_confirmation: "x" * 80)
    user.valid?
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: user.errors))
    assert_text "Password is too long"
    assert_no_text "Password Password"

    blank = User.new(email_address: "a@example.com", password: "")
    blank.valid?
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: blank.errors))
    assert_no_text "Password Password"
  end

  test "base errors and plain strings print as they are, without a link" do
    render_inline(Admin::Ui::ErrorSummaryComponent.new(errors: [ "Current password is incorrect" ]))
    assert_text "Current password is incorrect"
    assert_no_selector "a"
  end
end
