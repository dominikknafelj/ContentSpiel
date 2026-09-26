require "test_helper"

class SetupRedirectTest < ActionDispatch::IntegrationTest
  test "every page redirects to /setup while setup is required" do
    start_fresh_install

    [ "/", "/about", "/de/about", "/avo", "/avo/resources/posts" ].each do |path|
      get path
      assert_redirected_to "/setup", "expected #{path} to redirect to /setup"
    end
  end

  test "non-GET requests are redirected too" do
    start_fresh_install

    post "/avo/resources/posts"

    assert_redirected_to "/setup"
  end

  test "sign-in, health check and the MCP endpoint stay reachable" do
    start_fresh_install

    get "/up"
    assert_response :success

    get new_session_path
    assert_response :success

    post "/mcp"
    assert_response :unauthorized
  end

  test "nothing is redirected once setup is complete" do
    get new_session_path
    assert_response :success

    get "/avo"
    assert_not_equal "/setup", URI.parse(response.location.to_s).path
  end
end
