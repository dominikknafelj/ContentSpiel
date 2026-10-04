require "test_helper"

class Admin::PasswordFieldComponentTest < ViewComponent::TestCase
  test "renders a labelled password input with a Show button" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_selector "label[for=password]", text: "New password"
    assert_selector "input#password[type=password][name=password][autocomplete='new-password'][data-password-field-target=input]"
    assert_selector "button[type=button][aria-controls=password]", text: "Show"
    # Its changing text ("Show" / "Hide") is the state; a pressed state on top
    # would read as "Hide, pressed".
    assert_no_selector "button[aria-pressed]"
    assert_no_selector "[data-password-field-target=bar]"
  end

  test "with a meter it renders four bars and a polite hint" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true))
    assert_selector "[data-password-field-target=bar]", count: 4
    assert_selector "[data-password-field-target=hint][aria-live=polite]", text: "Use at least 12 characters."
  end

  test "errors are printed under the field and tied to it" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", errors: [ "Use at least 12 characters." ]))
    assert_selector "input[aria-invalid=true][aria-describedby~='password-errors']"
    assert_selector "#password-errors", text: "Use at least 12 characters."
  end

  test "the root carries the class and controller the form and system tests look for, and no value is rendered" do
    render_inline(Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_selector ".admin-password-field[data-controller=password-field]"
    assert_no_selector "input[value]"
  end
end
