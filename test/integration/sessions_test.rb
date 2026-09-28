require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  # The only reason anyone signs in at all is to reach CS Studio -- the public
  # site needs no authentication of its own, so a "cold" sign-in (one that
  # didn't arrive here via `request_authentication` redirecting from some
  # other protected page, which is the only thing that ever records a
  # return_to_after_authenticating) has nothing more useful to send the
  # visitor back to than the admin itself.
  test "signing in with no page to return to redirects to CS Studio" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to admin_root_path
  end

  # The normal case: signing in *because* a protected page demanded it sends
  # the visitor on to the page they actually asked for, not just the admin
  # root.
  test "signing in after being redirected from a protected page returns there" do
    get "/cs-studio/settings"
    assert_redirected_to "/cs-studio/sign-in"

    post "/cs-studio/sign-in", params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to "/cs-studio/settings"
  end

  test "signing in with invalid credentials redirects back to the sign-in form" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "wrong" }

    assert_redirected_to admin_sign_in_url
  end
end
