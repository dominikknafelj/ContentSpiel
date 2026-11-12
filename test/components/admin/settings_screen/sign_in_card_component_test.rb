require "test_helper"

class Admin::SettingsScreen::SignInCardComponentTest < ViewComponent::TestCase
  WORDS = "admin.components.settings_screen.sign_in_card".freeze
  RADIO = "input[type=radio][name='site_setting[passkey_policy]']".freeze

  def render_card(stored: nil, policy: nil, uncovered: 0, changed: nil)
    site = SiteSetting.instance
    site.passkey_policy = stored
    render_inline Admin::SettingsScreen::SignInCardComponent.new(site: site, policy: policy || site.effective_passkey_policy, uncovered: uncovered, changed: changed)
  end

  test "the card's heading, intro, the three choices in order with the effective one checked, and the admins' help" do
    render_card(stored: "owners_and_admins")

    assert_selector "section#settings-sign_in-card h2#sign_in", text: "Sign-in"
    assert_text I18n.t("#{WORDS}.intro")
    assert_selector "fieldset legend", text: I18n.t("#{WORDS}.legend")
    assert_equal SiteSetting::PASSKEY_POLICIES, page.all(RADIO, visible: :all).map(&:value)
    assert_equal [ "Nobody", "Owners and admins", "Everyone" ], page.all("fieldset label").map(&:text).map(&:strip)
    assert_selector "#{RADIO}[value=owners_and_admins][checked]", visible: :all
    assert_selector "#{RADIO}[checked]", visible: :all, count: 1
    assert_selector "p", text: I18n.t("#{WORDS}.admins_help")
  end

  test "an unset policy checks the environment's default" do
    render_card(stored: nil)

    assert_selector "#{RADIO}[value=#{SiteSetting.instance.effective_passkey_policy}][checked]", visible: :all
  end

  test "the uncovered people are counted, singular and plural" do
    render_card(stored: "everyone", uncovered: 1)
    assert_selector "[data-passkey-uncovered]", text: I18n.t("#{WORDS}.uncovered", count: 1)

    render_card(stored: "everyone", uncovered: 4)
    assert_selector "[data-passkey-uncovered]", text: I18n.t("#{WORDS}.uncovered", count: 4)
    assert_text "4 people this covers have no passkey yet."
  end

  test "everyone covered says so" do
    render_card(stored: "owners_and_admins", uncovered: 0)

    assert_selector "[data-passkey-uncovered]", text: I18n.t("#{WORDS}.all_covered")
  end

  test "at nobody there is no count line" do
    render_card(stored: "nobody", uncovered: 0)

    assert_no_selector "[data-passkey-uncovered]"
    assert_no_text I18n.t("#{WORDS}.all_covered")
  end

  test "the field is marked when a refused save left it unsaved" do
    render_card(stored: "nobody", policy: "everyone", changed: "saved")

    assert_selector "[data-field-name=passkey_policy][data-save-bar-changed=saved]"
    assert_selector "#{RADIO}[value=everyone][checked]", visible: :all
  end
end
