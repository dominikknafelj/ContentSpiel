require "test_helper"

class SetupRedirectTest < ActionDispatch::IntegrationTest
  test "every page redirects to /setup while setup is required" do
    start_fresh_install

    [ "/", "/about", "/de/about", "/cs-studio", "/cs-studio/posts" ].each do |path|
      get path
      assert_redirected_to "/setup", "expected #{path} to redirect to /setup"
    end
  end

  test "non-GET requests are redirected too" do
    start_fresh_install

    post "/cs-studio/posts"

    assert_redirected_to "/setup"
  end

  test "sign-in, health check and the MCP endpoint stay reachable" do
    start_fresh_install

    get "/up"
    assert_response :success

    get admin_sign_in_path
    assert_response :success

    post "/mcp"
    assert_response :unauthorized
  end

  # A browser asks for /favicon.ico beside a page. Redirected into the
  # wizard, that request loaded the session and wrote its cookie back as it
  # read it, over a passkey challenge a parallel request had just kept, so
  # the passkey step's first Add was refused.
  test "the favicon is not sent into the wizard, and its answer writes no session cookie" do
    start_fresh_install
    verify_setup_token

    get "/favicon.ico"

    assert_response :not_found
    assert_nil response.headers["Set-Cookie"], "the favicon's answer leaves the session cookie alone"
  end

  test "nothing is redirected once setup is complete" do
    get admin_sign_in_path
    assert_response :success

    get "/cs-studio"
    assert_not_equal "/setup", URI.parse(response.location.to_s).path
  end
end
