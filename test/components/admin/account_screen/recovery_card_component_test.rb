require "test_helper"

# Your account's Recovery codes card: how many of the ten are left and when
# they were made, a warn notice at two or fewer, and Regenerate… behind a
# confirm, or Generate… when the person holds none.
class Admin::AccountScreen::RecoveryCardComponentTest < ViewComponent::TestCase
  WORDS = "admin.components.account_screen.recovery_card".freeze

  setup { travel_to Time.zone.parse("2026-11-11 12:00") }

  def card(unused:, generated_at:)
    with_request_url("/cs-studio/account") do
      render_inline Admin::AccountScreen::RecoveryCardComponent.new(unused: unused, generated_at: generated_at)
    end
  end

  test "with codes it says how many are left and when they were made, and Regenerate… asks first" do
    card(unused: 7, generated_at: Time.zone.parse("2026-11-02 10:00"))

    assert_selector "section#account-recovery[aria-labelledby=recovery-codes] h2#recovery-codes", text: "Recovery codes"
    assert_text I18n.t("#{WORDS}.intro")
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
end
