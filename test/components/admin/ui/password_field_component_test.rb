require "test_helper"

class Admin::Ui::PasswordFieldComponentTest < ViewComponent::TestCase
  test "renders a labelled password input with a Show button" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_selector "label[for=password]", text: "New password"
    assert_selector "input#password[type=password][name=password][autocomplete='new-password'][data-password-field-target=input]"
    assert_selector "button[type=button][aria-controls=password]", text: "Show"
    # Its changing text ("Show" / "Hide") is the state; a pressed state on top
    # would read as "Hide, pressed".
    assert_no_selector "button[aria-pressed]"
    assert_no_selector "[data-password-field-target=bar]"
  end

  test "Show/Hide is 12px medium sans in the accent colour, not mono capitals" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_selector "button[data-password-field-target=toggle].text-xs.font-medium.text-accent", text: "Show"
    assert_no_selector "button[data-password-field-target=toggle].font-cs-mono"
    assert_no_selector "button[data-password-field-target=toggle].uppercase"
  end

  test "a label_aside sits on the label row, to the right" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "Password")) do |field|
      field.with_label_aside { "<a href='/x'>Forgot?</a>".html_safe }
    end
    assert_selector ".admin-password-field > div.justify-between label[for=password] + a[href='/x']", text: "Forgot?"
  end

  test "with a meter it renders four bars and a polite hint" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true))
    assert_selector "[data-password-field-target=bar]", count: 4
    assert_selector "[data-password-field-target=hint][aria-live=polite]", text: "Use at least 12 characters."
  end

  test "errors are printed under the field and tied to it" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", errors: [ "Use at least 12 characters." ]))
    assert_selector "input[aria-invalid=true][aria-describedby~='password-errors']"
    assert_selector "#password-errors", text: "Use at least 12 characters."
  end

  test "the root carries the class and controller the form and system tests look for, and no value is rendered" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_selector ".admin-password-field[data-controller=password-field]"
    assert_no_selector "input[value]"
  end
  # The well stands outside `.admin-field` on most screens, so its refused
  # look is the component's own: the root's class sets the danger edge, and
  # each message carries the decorative "!" of the shared error slot.
  test "a refused password draws the danger edge and the error mark" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", errors: [ "Use at least 12 characters." ]))
    assert_selector ".admin-password-field.admin-password-field--invalid input#password[aria-invalid=true]"
    assert_selector ".admin-password-field > #password-errors > p span[aria-hidden=true]", text: "!"
    assert_selector "#password-errors > p", text: "Use at least 12 characters."

    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password"))
    assert_no_selector ".admin-password-field--invalid"
    assert_no_selector "input[aria-invalid]"
    assert_no_selector "#password-errors"

    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-password-field--invalid\s*\{\s*--cs-field-invalid-border:\s*var\(--cs-danger\);\s*\}/, css)
    assert_match(/\.admin-password-field--invalid input\s*\{\s*border-bottom-color:\s*var\(--cs-field-invalid-border\);\s*\}/, css)
  end

  test "Show, Hide, the hint and the meter's words are keys the script reads" do
    render_inline(Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true))
    scope = "admin.components.ui.password_field"
    assert_selector "button[data-password-field-target=toggle]", exact_text: I18n.t("#{scope}.show")
    assert_selector "[data-password-field-target=hint]", exact_text: I18n.t("#{scope}.minimum", count: User::MINIMUM_PASSWORD_LENGTH)

    served = JSON.parse(page.find(".admin-password-field")["data-messages"])
    %w[show hide strength.too_short strength.fair strength.good strength.strong].each do |key|
      assert_equal I18n.t("#{scope}.#{key}"), served["components.ui.password_field.#{key}"], key
    end

    script = Rails.root.join("app/javascript/controllers/password_field_controller.js").read
    assert_includes script, %(import { messages } from "i18n/messages")
    %w[hide show strength.too_short strength.fair strength.good strength.strong].each do |key|
      assert_includes script, %("components.ui.password_field.#{key}"), key
    end
  end
end
