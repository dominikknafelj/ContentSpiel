require "application_system_test_case"

# "Sign in with %{provider}" as a person meets it: the browser leaves for the
# fake provider (`OidcHelper`, on 127.0.0.1 beside the Capybara server),
# which answers its authorization address with a redirect back to the
# callback, as a real provider does once the person has signed in there.
# The redirect URI is the request's origin (`SignIn::Sso.callback_origin`,
# with no site address in tests), so the provider sends the browser back to
# the Capybara server it left, where the state's cookie waits.
class Admin::SsoSignInSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    # The fake provider's identity, `reader@example.com`, is this account's,
    # unlinked: its first sign-in links it.
    @user = users(:reader)
  end

  test "Sign in with the provider signs an invited person in and lands on the dashboard" do
    with_fake_idp do |idp|
      visit admin_sign_in_path
      press "Sign in with Example ID"

      assert_selector "nav[aria-label='Modules']", wait: 15
      session = Session.sole
      assert_equal [ @user.id, "sso" ], [ session.user_id, session.authenticated_with ]
      assert @user.reload.sso_linked?
      assert idp.requests.any? { |request| request.path == "/idp/authorize" }, "the browser went to the provider"
    end
  end

  # `Admin::Ui::WayInButtonComponent`'s keyboard (its contract's
  # `keyboard:`). Tab starts where a person puts it, in the password field
  # by its label, and passes the field's Show and Sign in.
  test "the provider's way in is the Tab stop after Sign in, and Enter there goes to the provider" do
    with_fake_idp do |idp|
      visit admin_sign_in_path
      find("label", text: "Password").click
      page.send_keys(:tab)
      assert_equal "Show", focused_text
      page.send_keys(:tab)
      assert_equal "Sign in", focused_text
      page.send_keys(:tab)
      assert_equal "Sign in with Example ID", focused_text

      page.send_keys(:enter)
      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal "sso", Session.sole.authenticated_with
      assert idp.requests.any? { |request| request.path == "/idp/authorize" }, "the browser went to the provider"
    end
  end

  test "a cancelled sign-in at the provider comes back to the panel with the sentence" do
    with_fake_idp do |idp|
      idp.deny!
      visit admin_sign_in_path
      press "Sign in with Example ID"

      assert_selector "#alert", text: "Signing in with Example ID didn't finish. Try again.", wait: 15
      assert_button "Sign in with Example ID"
      assert_equal 0, Session.count
      assert_not @user.reload.sso_linked?
    end
  end
end
