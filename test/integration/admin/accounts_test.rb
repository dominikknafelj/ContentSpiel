require "test_helper"

# "Change my password" (access-control design spec §3.3 "Any user may change
# their own password", §5 "reachable by every user from the account menu").
class Admin::AccountsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "every signed-in user reaches it from the account menu" do
    sign_in_as(users(:reader))

    get "/cs-studio/api_tokens"
    assert_select "a[href='/cs-studio/account/password']", text: /Change password/

    get "/cs-studio/account/password"
    assert_response :success
    assert_select "input[type=password][name=current_password]"
  end

  test "signed out, it redirects to sign-in" do
    get "/cs-studio/account/password"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "a wrong current password fails and changes nothing" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "wrong", password: "new-password-1", password_confirmation: "new-password-1" }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Current password is incorrect/
    assert users(:reader).reload.authenticate("password")
  end

  test "a mismatched confirmation fails" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "other" }

    assert_response :unprocessable_entity
    assert users(:reader).reload.authenticate("password")
  end

  test "a new password under 12 characters is refused with the rule's own message" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "password", password: "elevenchars", password_confirmation: "elevenchars" }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: "Use at least 12 characters."
    assert users(:reader).reload.authenticate("password")
  end

  test "a success changes the password and signs out other sessions only" do
    user = users(:reader)
    other_session = user.sessions.create!
    sign_in_as(user)
    current_session = Current.session

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "new-password-1" }

    assert_redirected_to "/cs-studio/account/password"
    follow_redirect!
    assert_select "[role=status]", text: /Password changed/
    assert user.reload.authenticate("new-password-1")
    assert_not Session.exists?(other_session.id)
    assert Session.exists?(current_session.id)

    event = Audit::Event.find_by!(action: "user.updated", subject: user)
    assert_not_includes event.attributes.to_json, "new-password-1"
    assert_not_includes event.attributes.to_json, user.password_digest
  end

  test "a user saves their own name" do
    user = users(:reader)
    sign_in_as(user)

    patch "/cs-studio/account/profile", params: { name: "Ada" }

    assert_redirected_to "/cs-studio/account/password"
    assert_equal "Ada", user.reload.name
  end

  test "signed out, saving a name redirects to sign-in" do
    patch "/cs-studio/account/profile", params: { name: "Ada" }
    assert_redirected_to "/cs-studio/sign-in"
  end
end
