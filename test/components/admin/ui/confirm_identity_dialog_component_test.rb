require "test_helper"

# Confirm it's you in its two shapes: with a passkey, "Use your passkey" is
# the one primary and the password is the secondary way; without one, the
# password's Confirm is. Both carry the error line the script fills and the
# place a refused request's stream connects to.
class Admin::Ui::ConfirmIdentityDialogComponentTest < ViewComponent::TestCase
  URLS = { options_url: "/cs-studio/account/confirmation/options", password_url: "/cs-studio/account/confirmation",
           passkey_url: "/cs-studio/account/confirmation/passkey" }.freeze

  def primaries = page.all("button", visible: :all).select { |button| button[:class].to_s.split.include?("bg-accent") }

  test "with a passkey: the lead, Use your passkey as the one primary, or, the password and Confirm with password beside Cancel" do
    render_inline(Admin::Ui::ConfirmIdentityDialogComponent.new(passkey: true, url_options: {}))

    root = page.find("##{Admin::Ui::ConfirmIdentityDialogComponent::ID}[data-controller='admin--passkeys--confirm']", visible: :all)
    assert_equal URLS[:options_url], root["data-admin--passkeys--confirm-options-url-value"]
    assert_equal URLS[:password_url], root["data-admin--passkeys--confirm-password-url-value"]
    assert_equal URLS[:passkey_url], root["data-admin--passkeys--confirm-passkey-url-value"]

    assert_selector "dialog[data-dialog-width=form_narrow] h2", text: "Confirm it's you", visible: :all
    assert_text "To change how you sign in, confirm with your passkey or your password.", normalize_ws: true
    assert_selector "button[data-admin--passkeys--confirm-target=passkey]", text: "Use your passkey", visible: :all
    assert_selector "span", text: "or", visible: :all
    assert_selector "label", text: "Password", visible: :all
    assert_selector "input[type=password][autocomplete=current-password][name=password]", visible: :all
    assert_selector "footer button", text: "Cancel", visible: :all
    assert_selector "footer button[type=submit]", text: "Confirm with password", visible: :all
    assert_no_selector "button", text: /\AConfirm\z/, visible: :all

    assert_equal [ "Use your passkey" ], primaries.map { |button| button.text(:all).strip }
    assert_selector "[role=alert][data-admin--passkeys--confirm-target=error]", visible: :all
    assert_selector "##{Admin::Ui::ConfirmIdentityDialogComponent::REQUESTS_ID}", visible: :all
  end

  test "without a passkey: the password lead, the field and Confirm as the one primary beside Cancel" do
    render_inline(Admin::Ui::ConfirmIdentityDialogComponent.new(passkey: false))

    assert_text "To change how you sign in, confirm with your password.", normalize_ws: true
    assert_no_text "your passkey or"
    assert_no_selector "button", text: "Use your passkey", visible: :all
    assert_no_selector "span", text: /\Aor\z/, visible: :all
    assert_selector "input[type=password][autocomplete=current-password]", visible: :all
    assert_selector "footer button", text: "Cancel", visible: :all
    assert_equal [ "Confirm" ], primaries.map { |button| button.text(:all).strip }
    assert_no_selector "button", text: "Confirm with password", visible: :all
    assert_selector "[role=alert][data-admin--passkeys--confirm-target=error]", visible: :all
  end

  test "the editing language is kept in the addresses" do
    render_inline(Admin::Ui::ConfirmIdentityDialogComponent.new(passkey: true, url_options: { locale: "de" }))

    root = page.find("##{Admin::Ui::ConfirmIdentityDialogComponent::ID}", visible: :all)
    assert_equal "#{URLS[:password_url]}?locale=de", root["data-admin--passkeys--confirm-password-url-value"]
  end
end
