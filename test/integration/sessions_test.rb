require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  # Only the immediate redirect is asserted: `root_url` now redirects onward to
  # the default locale's root page, and whether a page renders there is
  # PagesRoutingTest's subject, not sign-in's.
  test "signing in with valid credentials redirects to root" do
    post session_url, params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to root_url
  end

  test "signing in with invalid credentials redirects back to the sign-in form" do
    post session_url, params: { email_address: "admin@example.com", password: "wrong" }

    assert_redirected_to new_session_url
  end
end
