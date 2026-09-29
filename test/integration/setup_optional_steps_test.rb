require "test_helper"

class SetupOptionalStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the MCP token step can be skipped" do
    get setup_step_path("mcp_token")

    assert_response :success
    assert_select "a[href=?]", setup_step_path("starter_content"), text: "Skip"
    assert_match(/Admin group/, response.body)
  end

  test "generating an MCP token shows it once, bound to the admin and the Admin group, and never in flash" do
    assert_difference "ApiToken.count", 1 do
      patch setup_step_path("mcp_token")
    end

    assert_response :success
    raw = css_select("#mcp-token").first.text.strip
    token = ApiToken.authenticate(raw)
    assert_equal User.find_by(email_address: "owner@example.com"), token.user
    assert_equal AccessControl::Seeds::ADMIN_NAME, token.group.name
    assert_empty flash.to_h
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "the starter content step can be skipped" do
    get setup_step_path("starter_content")

    assert_response :success
    assert_select "a[href=?]", setup_step_path("review"), text: "Skip"
  end

  test "adding starter content creates the pages in the default language" do
    SiteSetting.instance.update!(default_locale: "de")

    patch setup_step_path("starter_content")

    assert_redirected_to setup_step_path("review")
    assert StarterContent.added?(locale: "de")
  end

  # Final fix wave (C, P23): the wizard takes the same locked, re-checked
  # path as CS Studio (`StarterContent.add_once!`), and a failure is a form
  # error on the step, never a 500.
  test "adding starter content twice doesn't duplicate anything" do
    patch setup_step_path("starter_content")

    assert_no_difference [ "Page.count", "Post.count" ] do
      patch setup_step_path("starter_content")
    end
    assert_redirected_to setup_step_path("review")
  end

  test "a starter content failure is shown on the step instead of a 500" do
    with_singleton_override(StarterContent, :create_pages_and_posts!, ->(**) { raise StarterContent::Error, "StarterContent: Slug has already been taken" }) do
      patch setup_step_path("starter_content")
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /couldn.t be added/
  end
end
