require "test_helper"

class Admin::UsersTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "the list shows every user" do
    get "/cs-studio/users"
    assert_response :success
    assert_select "#" + ActionView::RecordIdentifier.dom_id(users(:one))
    assert_select "#" + ActionView::RecordIdentifier.dom_id(users(:two))
  end

  test "never renders a password digest" do
    get "/cs-studio/users"
    assert_not_includes response.body, users(:one).password_digest
  end

  test "creating a user" do
    assert_difference -> { User.count }, 1 do
      post "/cs-studio/users", params: { user: {
        email_address: "new@example.com", password: "password123", password_confirmation: "password123"
      } }
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    user = User.find_by!(email_address: "new@example.com")
    assert user.authenticate("password123")
  end

  test "creating a user with mismatched confirmation fails" do
    assert_no_difference -> { User.count } do
      post "/cs-studio/users", params: { user: {
        email_address: "new@example.com", password: "password123", password_confirmation: "nope"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "doesn&#39;t match"
  end

  test "creating a user with an email already taken (case-insensitively) fails" do
    assert_no_difference -> { User.count } do
      post "/cs-studio/users", params: { user: {
        email_address: users(:one).email_address.upcase, password: "password123", password_confirmation: "password123"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "has already been taken"
  end

  test "editing a user's email without touching the password" do
    user = users(:two)
    digest_before = user.password_digest

    patch "/cs-studio/users/#{user.id}", params: { user: { email_address: "changed@example.com" } }

    assert_response :redirect
    user.reload
    assert_equal "changed@example.com", user.email_address
    assert_equal digest_before, user.password_digest
  end

  test "changing a user's password" do
    user = users(:two)

    patch "/cs-studio/users/#{user.id}", params: { user: {
      password: "brand-new-password", password_confirmation: "brand-new-password"
    } }

    assert_response :redirect
    assert user.reload.authenticate("brand-new-password")
  end

  test "deleting another user" do
    assert_difference -> { User.count }, -1 do
      delete "/cs-studio/users/#{users(:two).id}"
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "User deleted"
  end

  test "refuses to delete the last owner" do
    assert_no_difference -> { User.count } do
      delete "/cs-studio/users/#{users(:one).id}"
    end

    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "The last owner can&#39;t be deleted"
  end

  test "deleting yourself signs you out" do
    # users(:one) is the sole owner (test/fixtures/users.yml) and can't be
    # deleted at all, last-owner or not -- deletes as :two instead, who
    # isn't an owner, so nothing here is exercising the last-owner guard.
    sign_in_as(users(:two))

    delete "/cs-studio/users/#{users(:two).id}"

    assert_redirected_to admin_sign_in_path
    follow_redirect!
    assert_response :success

    # The session is really gone, not just redirected past -- a request
    # against a signed-in-only page bounces back to sign-in instead of
    # succeeding.
    get "/cs-studio/users"
    assert_redirected_to admin_sign_in_path
  end
end
