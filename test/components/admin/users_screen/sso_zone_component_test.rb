require "test_helper"

class Admin::UsersScreen::SsoZoneComponentTest < ViewComponent::TestCase
  def zone(user, provider_name: "Acme ID")
    with_request_url("/cs-studio/users/#{user.id}/edit") do
      render_inline Admin::UsersScreen::SsoZoneComponent.new(user: user, provider_name: provider_name)
    end
  end

  test "the zone names the person and the provider, and its dialog's words" do
    user = users(:reader)
    zone(user)

    assert_selector "section.admin-action-zone.mt-6[data-zone=sso][aria-labelledby=sso-zone-title][data-controller='admin--saving--pending-lock']"
    assert_selector "h2#sso-zone-title.text-h3", text: "Single sign-on"
    assert_text "reader@example.com signs in with Acme ID and has no password here."
    assert_selector "button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='sso-user-#{user.id}'][data-admin--saving--pending-lock-target=control]:not([disabled])", text: "Unlink…"
    assert_selector "dialog#sso-user-#{user.id}", visible: :all do
      assert_selector "dialog", text: "Unlink reader@example.com from Acme ID?", visible: :all
      assert_selector "dialog", text: "reader@example.com can no longer sign in with Acme ID, and is signed out everywhere. They get a mail to set a password here.", visible: :all
      assert_selector "form[action='/cs-studio/users/#{user.id}/sso_link'] input[name=_method][value=delete]", visible: :all
      assert_selector "button.bg-accent[type=submit]", text: "Unlink", visible: :all
    end
    assert_no_selector "dialog button.bg-danger", visible: :all
  end

  test "a provider name that says nothing falls back to words" do
    zone(users(:reader), provider_name: nil)

    assert_text "reader@example.com signs in with your sign-in provider and has no password here."
  end
end
