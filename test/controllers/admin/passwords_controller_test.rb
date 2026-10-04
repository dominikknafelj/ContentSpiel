require "test_helper"

class Admin::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_admin_password_path
    assert_response :success
  end

  test "new is the request state: email field, send button, and the no-mail hint" do
    get new_admin_password_path
    assert_select "h1", text: "Reset your password"
    assert_select "label[for=email_address]", text: "Email"
    assert_select "button.bg-accent", text: "Send reset link"
    assert_select "main", text: /No outgoing mail on this site\? Ask an owner to set a new password for you\./
    assert_select "a", text: /Back to sign in/
  end

  test "create" do
    post admin_password_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_admin_password_path(sent: 1)

    follow_redirect!
    assert_notice "If that address belongs to an account"
  end

  test "create for an unknown user redirects but sends no mail" do
    post admin_password_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_admin_password_path(sent: 1)

    follow_redirect!
    assert_notice "If that address belongs to an account"
  end

  test "after a reset request the page says the same thing whether or not the account exists" do
    post admin_password_path, params: { email_address: users(:one).email_address }
    follow_redirect!
    known = css_select("main").text.squish
    post admin_password_path, params: { email_address: "nobody@example.com" }
    follow_redirect!
    assert_equal known, css_select("main").text.squish
    assert_match "If that address belongs to an account, we've sent a link. It expires in 15 minutes.", known
  end

  test "an expired or invalid reset link shows the expired state with a way to ask again" do
    get admin_edit_password_path(token: "not-a-token")
    follow_redirect! if response.redirect?
    assert_select "h1", text: "This link has expired"
    assert_select "main", text: /Reset links work for 15 minutes and only once\./
    assert_select "a", text: "Send a new link"
  end

  test "the reset form uses the password field with the meter" do
    get admin_edit_password_path(token: users(:one).password_reset_token)
    assert_select "[data-controller='password-field'] [data-password-field-target=bar]", count: 4
  end

  test "edit" do
    get admin_edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get admin_edit_password_path("invalid token")
    assert_redirected_to new_admin_password_path(expired: 1)

    follow_redirect!
    assert_notice "This link has expired"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path(@user.password_reset_token), params: { password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      assert_redirected_to admin_sign_in_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path(token), params: { password: "long-enough-pw-1", password_confirmation: "long-enough-pw-2" }
      assert_redirected_to admin_edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Password confirmation doesn't match Password"
  end

  test "update with a blank password says so" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path(token), params: { password: "", password_confirmation: "" }
      assert_redirected_to admin_edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Password can't be blank"
  end

  private
    def assert_notice(text)
      assert_select "main", /#{text}/
    end
end
