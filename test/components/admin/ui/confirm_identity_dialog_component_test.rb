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

  test "the script's own sentences for a failure that is not the confirmation's are on the wrapper" do
    render_inline(Admin::Ui::ConfirmIdentityDialogComponent.new(passkey: true))

    held = JSON.parse(page.find("##{Admin::Ui::ConfirmIdentityDialogComponent::ID}", visible: :all)["data-messages"])
    assert_equal "That passkey didn't work. Try again, or use your password.", held["components.ui.confirm_identity_dialog.passkey_failed"]
    assert_equal "Try again in a few minutes.", held["components.ui.confirm_identity_dialog.limited"]
  end

  # The browser test of the re-send is the Account screen's; this holds the
  # rule's three lines: a form is remembered only from the gate's refusal,
  # by its own answer, and a false settle forgets it.
  test "the script sends again only the form the gate refused, and forgets it on a cancel" do
    script = Rails.root.join("app/javascript/controllers/admin/passkeys/confirm_controller.js").read

    assert_includes script, %(const CONFIRM_HEADER = "#{Admin::RecentConfirmation::CONFIRM_HEADER}")
    assert_includes script, %(document.addEventListener("turbo:submit-end", this.remember))
    assert_includes script, "response?.statusCode === 403 && response.header(CONFIRM_HEADER)"
    assert_not_includes script, "turbo:submit-start"
    assert_match(/const form = this\.remembered\n\s+this\.remembered = null/, script)
    assert_includes script, "if (!confirmed) this.remembered = null"
  end
end
