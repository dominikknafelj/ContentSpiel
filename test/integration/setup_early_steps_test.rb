require "test_helper"

class SetupEarlyStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
  end

  test "the system check lists every check and can be continued" do
    get setup_step_path("system_check")

    assert_response :success
    %w[File\ storage Image\ processing Background\ jobs Outgoing\ mail].each do |label|
      assert_includes response.body, label
    end
    assert_select "a[href=?]", setup_step_path("admin"), text: "Continue"
  end

  test "creating the admin signs them in and moves to site identity" do
    assert_difference "User.count", 1 do
      create_setup_admin
    end

    assert_redirected_to setup_step_path("site")
    assert_equal "owner@example.com", User.last.email_address
    assert User.last.owner?, "the first account is the owner"
  end

  test "a password confirmation mismatch is shown, nothing is created" do
    assert_no_difference "User.count" do
      patch setup_step_path("admin"), params: { user: {
        email_address: "owner@example.com", password: "password12345", password_confirmation: "different"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Password confirmation doesn&#39;t match"
  end

  test "a blank email is rejected" do
    patch setup_step_path("admin"), params: { user: { email_address: " ", password: "password12345", password_confirmation: "password12345" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Email address can&#39;t be blank"
  end

  test "the admin step can't be repeated once an admin exists" do
    create_setup_admin

    get setup_step_path("admin")

    assert_redirected_to setup_step_path("site")
  end
end
