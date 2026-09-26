require "test_helper"

class SetupAccessTest < ActionDispatch::IntegrationTest
  test "/setup is a 404 once setup is complete, even for a signed-in admin" do
    sign_in_as(users(:one))

    get setup_path
    assert_response :not_found

    get setup_step_path("site")
    assert_response :not_found
  end

  test "an unknown step is a 404" do
    start_fresh_install

    get setup_step_path("nope")

    assert_response :not_found
  end

  test "a fresh install starts at the token step" do
    start_fresh_install

    get setup_path

    assert_redirected_to setup_step_path("token")
  end

  test "the token page renders" do
    start_fresh_install

    get setup_step_path("token")

    assert_response :success
    assert_includes response.body, "Setup token"
  end

  test "later steps require the token first" do
    start_fresh_install

    get setup_step_path("admin")

    assert_redirected_to setup_step_path("token")
  end

  test "a wrong token is rejected" do
    start_fresh_install

    patch setup_step_path("token"), params: { token: "wrong" }

    assert_response :unprocessable_entity
    assert_includes response.body, "doesn&#39;t match"
  end

  test "the right token unlocks the next step" do
    start_fresh_install

    verify_setup_token

    assert_redirected_to setup_step_path("system_check")
  end

  test "after the token, steps beyond the admin account stay closed" do
    start_fresh_install
    verify_setup_token

    get setup_step_path("site")

    assert_redirected_to setup_step_path("admin")
  end

  test "repeated wrong tokens lock the form, even for the right token" do
    start_fresh_install

    10.times { patch setup_step_path("token"), params: { token: "wrong" } }
    verify_setup_token

    assert_redirected_to setup_step_path("token")
    assert_equal "Too many attempts. Try again in a few minutes.", flash[:alert]
  end

  test "once an admin exists, the wizard requires signing in" do
    start_fresh_install
    User.create!(email_address: "owner@example.com", password: "password123")

    get setup_step_path("site")

    assert_redirected_to new_session_path
  end

  test "signing in resumes the step that was asked for" do
    start_fresh_install
    User.create!(email_address: "owner@example.com", password: "password123")
    get setup_step_path("site")

    post session_path, params: { email_address: "owner@example.com", password: "password123" }

    assert_redirected_to setup_step_path("site")
  end
end
