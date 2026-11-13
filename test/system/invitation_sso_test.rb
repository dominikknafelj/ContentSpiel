require "application_system_test_case"

# The invitation page's "Continue with <provider>" as a person meets it: the
# token comes from the link's fragment, the button carries it in a body, the
# browser leaves for the fake provider (`OidcHelper`) and comes back signed
# in to the account the invitation makes.
class InvitationSsoSystemTest < ApplicationSystemTestCase
  EMAIL = "newcomer@example.com".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "an invitation is accepted through the provider" do
    invitation = open_invitation(EMAIL, name: "Newcomer")
    token = invitation.generate_token_for(:accept)

    with_fake_idp(email: EMAIL, name: "Prov Name") do |idp|
      Capybara.reset_session!
      visit "#{admin_invitation_path}##{token}"
      assert_selector "form[data-invitation-token-target=form]:not([hidden])"
      assert_not_includes page.evaluate_script("document.documentElement.outerHTML"), "##{token}"

      press "Continue with Example ID"

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_text "Your account is ready."
      user = User.find_by!(email_address: EMAIL)
      assert invitation.reload.accepted?
      assert user.sso_linked?
      assert_equal [ user.id, "sso" ], Session.sole.values_at(:user_id, :authenticated_with)
      assert idp.requests.any? { |request| request.path == "/idp/authorize" }, "the browser went to the provider"

      # Back through the history (the browser's own cache may restore the
      # page): no token is left in the document.
      page.go_back
      assert_selector "body"
      assert_equal 0, page.evaluate_script("Array.from(document.querySelectorAll('input[name=token]')).filter((field) => field.value).length")
    end
  end

  test "under SSO_REQUIRED the provider's button alone accepts the invitation" do
    invitation = open_invitation(EMAIL)
    token = invitation.generate_token_for(:accept)

    with_fake_idp(email: EMAIL, required: true) do
      Capybara.reset_session!
      visit "#{admin_invitation_path}##{token}"
      assert_no_field "Password"
      press "Continue with Example ID"

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_text "Your account is ready."
      assert invitation.reload.accepted?
    end
  end
end
