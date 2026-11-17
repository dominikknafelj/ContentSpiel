require "test_helper"

# The Passkeys card's Recovery codes section: how many of the ten are left
# and when they were made, a warn notice at two or fewer, and Regenerate…
# behind a confirm, or Generate… when the person holds none.
class Admin::AccountScreen::RecoverySectionComponentTest < ViewComponent::TestCase
  WORDS = "admin.components.account_screen.recovery_section".freeze

  setup { travel_to Time.zone.parse("2026-11-11 12:00") }

  def card(unused:, generated_at:, passkey: true)
    with_request_url("/cs-studio/account") do
      render_inline Admin::AccountScreen::RecoverySectionComponent.new(unused: unused, generated_at: generated_at, passkey: passkey)
    end
  end

  test "with codes it says how many are left and when they were made, and Regenerate… asks first" do
    card(unused: 7, generated_at: Time.zone.parse("2026-11-02 10:00"))

    # A section under a line, its heading the card's meta line, not a card.
    assert_selector "section#account-recovery.border-t.border-line[aria-labelledby=recovery-codes] h3#recovery-codes.text-label.text-meta", text: "Recovery codes"
    assert_no_selector ".admin-settings-card"
    assert_selector "h3 + p.text-small", text: I18n.t("#{WORDS}.intro")
    assert_selector "[data-recovery-status]", exact_text: "7 of 10 codes left · made 2 Nov 2026"
    assert_no_selector "[role=alert]"
    assert_selector "button", text: "Regenerate…"
    assert_no_button "Generate recovery codes…"

    dialog = page.find("dialog#regenerate-recovery-codes", visible: :all)
    assert_nil dialog["data-destructive"], "regenerating is not destructive"
    assert_includes dialog.text(:all), "Your 7 unused codes stop working, and you get ten new ones to save."
    assert_selector "dialog#regenerate-recovery-codes form[action='/cs-studio/account/recovery-codes'][data-confirm-identity]", visible: :all
  end

  test "one or two left is the low notice, by count, and none left is out" do
    card(unused: 1, generated_at: 1.day.ago)
    assert_selector "[role=alert]", text: "1 code left. Regenerate them before you run out."
    assert_includes page.find("dialog#regenerate-recovery-codes", visible: :all).text(:all), "Your 1 unused code stops working"

    card(unused: 2, generated_at: 1.day.ago)
    assert_selector "[role=alert]", text: "2 codes left. Regenerate them before you run out."

    card(unused: 0, generated_at: 1.day.ago)
    assert_selector "[role=alert]", text: I18n.t("#{WORDS}.out")
    assert_selector "button", text: "Regenerate…"

    card(unused: 3, generated_at: 1.day.ago)
    assert_no_selector "[role=alert]"
  end

  test "with none ever made it says so, warns of nothing, and Generate… is a form of its own" do
    card(unused: 0, generated_at: nil)

    assert_selector "[data-recovery-status]", exact_text: I18n.t("#{WORDS}.none")
    assert_no_selector "[role=alert]"
    assert_no_button "Regenerate…"
    assert_selector "form[action='/cs-studio/account/recovery-codes'][data-confirm-identity] button", text: "Generate recovery codes…"
    assert_no_selector "dialog#regenerate-recovery-codes", visible: :all
  end

  # Codes are a backup for passkeys (`SignIn::RecoveryCodes::Generate` refuses
  # without one, and removing the last passkey deletes them), so a person
  # with none is offered no section at all.
  test "without a passkey the section is not drawn" do
    card(unused: 0, generated_at: nil, passkey: false)

    assert_no_selector "#account-recovery", visible: :all
    assert_no_selector "form", visible: :all
  end
end
