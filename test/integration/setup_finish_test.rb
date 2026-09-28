require "test_helper"

class SetupFinishTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the review summarises the choices, with edit links" do
    SiteSetting.instance.update!(title: "Dana's Notes", default_locale: "de")

    get setup_step_path("review")

    assert_response :success
    assert_includes response.body, "Dana&#39;s Notes"
    assert_includes response.body, "Deutsch"
    assert_includes response.body, "Skipped"
    assert_select "a[href=?]", setup_step_path("site")
  end

  test "finishing creates the homepage, ends setup and opens the admin" do
    patch setup_step_path("review")

    assert_redirected_to "/cs-studio"
    assert_not Setup.required?

    get "/"
    assert_response :success
    assert_includes response.body, "Welcome to your new site"

    get setup_path
    assert_response :not_found
  end
end
