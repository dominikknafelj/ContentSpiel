require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get admin_sign_in_path
    assert_response :success
  end

  test "create with valid credentials" do
    post admin_sign_in_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to admin_root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post admin_sign_in_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to admin_sign_in_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete admin_sign_out_path

    assert_redirected_to admin_sign_in_path
    assert_empty cookies[:session_id]
  end
end
