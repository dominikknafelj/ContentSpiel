require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  test "signing in with valid credentials redirects to root and grants access" do
    post session_url, params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "signing in with invalid credentials redirects back to the sign-in form" do
    post session_url, params: { email_address: "admin@example.com", password: "wrong" }

    assert_redirected_to new_session_url
  end
end
