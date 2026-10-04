require "test_helper"

class Admin::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_admin_password_path
    assert_response :success
  end

  test "create" do
    post admin_password_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to admin_sign_in_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    post admin_password_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to admin_sign_in_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "edit" do
    get admin_edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get admin_edit_password_path("invalid token")
    assert_redirected_to new_admin_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
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
      assert_select "div", /#{text}/
    end
end
