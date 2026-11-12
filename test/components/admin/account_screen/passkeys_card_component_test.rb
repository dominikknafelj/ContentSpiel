require "test_helper"

# Your account's Passkeys card: a row per passkey with when it was added and
# last used, Rename and Remove…, and the foot that counts them and offers
# "Add a passkey…". A covered person's last passkey keeps its Remove
# disabled, with the reason in the row; after a sign-in with a recovery code
# the card opens on the warn notice.
class Admin::AccountScreen::PasskeysCardComponentTest < ViewComponent::TestCase
  include PasskeyHelper

  WORDS = "admin.components.account_screen.passkeys_card".freeze

  setup do
    travel_to Time.zone.parse("2026-11-11 12:00")
    @user = users(:reader)
  end

  def passkey(name, created_at: 3.days.ago, last_used_at: nil)
    @user.passkeys.create!(name: name, external_id: SecureRandom.base64(16), public_key: "key", created_at: created_at, last_used_at: last_used_at)
  end

  def card(passkeys = @user.passkeys.order(:created_at).to_a, covered: false, recovery_left: nil, addable: true)
    with_request_url("/cs-studio/account") do
      render_inline Admin::AccountScreen::PasskeysCardComponent.new(passkeys: passkeys, covered: covered, recovery_left: recovery_left, addable: addable)
    end
  end

  test "each row says its name, when it was added and last used, with Rename and Remove… named after it" do
    used = passkey("MacBook", created_at: Time.zone.parse("2026-11-01 09:00"), last_used_at: 2.hours.ago)
    unused = passkey("Phone", created_at: Time.zone.parse("2026-11-10 09:00"))

    card

    assert_selector "section#account-passkeys[aria-labelledby=passkeys] h2#passkeys", text: "Passkeys"
    assert_text I18n.t("#{WORDS}.intro")
    assert_selector "#passkey-#{used.id}", text: "MacBook"
    assert_selector "#passkey-#{used.id} [data-passkey-details]", exact_text: "Added 1 Nov 2026 · Last used 2h ago"
    assert_selector "#passkey-#{used.id} [data-passkey-details] time[datetime]"
    assert_selector "#passkey-#{unused.id} [data-passkey-details]", exact_text: "Added 10 Nov 2026 · Never used"

    assert_selector "#passkey-#{used.id} button[aria-label='Rename the passkey MacBook']", text: "Rename"
    assert_selector "#passkey-#{used.id} button[aria-label='Remove the passkey MacBook']:not([disabled])", text: "Remove…"
    assert_selector "dialog#passkey-#{used.id}-rename"
    assert_selector "dialog#passkey-#{used.id}-remove[data-destructive] form[data-confirm-identity] input[name=_method][value=delete]", visible: :all
    assert_no_text I18n.t("#{WORDS}.last_required")
  end

  test "a covered person's last passkey keeps Remove disabled, with the reason in its row" do
    only = passkey("MacBook")

    card(covered: true)

    assert_selector "#passkey-#{only.id} button[aria-label='Remove the passkey MacBook'][disabled]"
    assert_selector "#passkey-#{only.id}", text: I18n.t("#{WORDS}.last_required")
    assert_no_selector "dialog#passkey-#{only.id}-remove"
  end

  test "an uncovered person's last passkey can go, and its dialog says the password is the way in again" do
    only = passkey("MacBook")

    card(covered: false)

    assert_selector "#passkey-#{only.id} button[aria-label='Remove the passkey MacBook']:not([disabled])"
    assert_selector "dialog#passkey-#{only.id}-remove", text: I18n.t("admin.components.account_screen.passkey_dialog.remove_last"), visible: :all
  end

  test "the foot counts the passkeys, one and many, beside Add a passkey…" do
    passkey("MacBook")
    card
    assert_selector "[data-passkeys-foot]", text: "1 passkey"
    assert_selector "[data-passkeys-foot] button", text: "Add a passkey…"

    passkey("Phone")
    card(covered: true)
    assert_selector "[data-passkeys-foot]", text: "2 passkeys"
    assert_no_selector "button[disabled][aria-label^='Remove the passkey']", visible: :all
  end

  test "with no passkeys the card says so and still offers Add" do
    card([])

    assert_no_selector "li[id^='passkey-']"
    assert_selector "[data-passkeys-foot]", text: I18n.t("#{WORDS}.none")
    assert_selector "[data-passkeys-foot] button", text: "Add a passkey…"
    assert_selector "dialog#passkey-add input[name=name][maxlength='#{Passkey::NAME_LIMIT}']", visible: :all
  end

  test "where no passkey can be made (no relying party) Add and its dialog are not drawn, and the passkeys held stay listed" do
    held = passkey("MacBook")

    card(addable: false)

    assert_no_button "Add a passkey…"
    assert_no_selector "dialog#passkey-add", visible: :all
    assert_selector "#passkey-#{held.id}", text: "MacBook"
    assert_selector "#passkey-#{held.id} button[aria-label='Rename the passkey MacBook']"
    assert_selector "[data-passkeys-foot]", text: "1 passkey"
  end

  test "after a sign-in with a recovery code the card opens on the warn notice, by how many are left" do
    passkey("MacBook")

    card(recovery_left: 3)
    assert_selector "[role=alert]", text: I18n.t("admin.accounts.passkeys.used_recovery", count: 3)

    card(recovery_left: 0)
    assert_selector "[role=alert]", text: I18n.t("admin.accounts.passkeys.used_last_recovery")

    card
    assert_no_text "You signed in with"
  end

  test "Add carries the register controller with its two addresses and the confirm outlet" do
    card([])

    controller = page.find("section#account-passkeys")
    assert_equal "admin--passkeys--register", controller["data-controller"]
    assert_equal "/cs-studio/account/passkeys/options", controller["data-admin--passkeys--register-options-url-value"]
    assert_equal "/cs-studio/account/passkeys", controller["data-admin--passkeys--register-create-url-value"]
    assert_equal "#confirm-identity", controller["data-admin--passkeys--register-admin--passkeys--confirm-outlet"]
    messages = JSON.parse(controller["data-messages"])
    assert_equal I18n.t("admin.components.account_screen.passkey_dialog.name_blank"), messages["components.account_screen.passkey_dialog.name_blank"]
  end
end
