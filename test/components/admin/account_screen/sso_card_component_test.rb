require "test_helper"

# Your account's Sign-in card for a person linked to the provider: who they
# sign in with, and that the rest is the provider's. No form, no control.
class Admin::AccountScreen::SsoCardComponentTest < ViewComponent::TestCase
  WORDS = "admin.components.account_screen.sso_card".freeze

  def card(provider_name:)
    with_request_url("/cs-studio/account") { render_inline Admin::AccountScreen::SsoCardComponent.new(provider_name: provider_name) }
  end

  test "it names the provider in its intro and body, and holds no form or control" do
    card(provider_name: "Okta")

    assert_selector "section#password[aria-labelledby=account-sign-in] h2#account-sign-in", text: "Sign-in"
    assert_text "You sign in with Okta."
    assert_text "Your password, your second factor and signing out of Okta are managed there. Ask an owner if you need to sign in another way."
    assert_no_selector "form, button, input, a"
  end

  test "a provider with no name is the fallback words" do
    card(provider_name: nil)

    assert_text "You sign in with your sign-in provider."
    assert_text I18n.t("#{WORDS}.provider_fallback")
  end
end
