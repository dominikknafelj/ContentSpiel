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
  end

  test "generating an MCP token shows it once, bound to the admin, and never in flash" do
    assert_difference "ApiToken.count", 1 do
      patch setup_step_path("mcp_token")
    end

    assert_response :success
    raw = css_select("#mcp-token").first.text.strip
    assert_equal User.find_by(email_address: "owner@example.com"), ApiToken.authenticate(raw).user
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
end
