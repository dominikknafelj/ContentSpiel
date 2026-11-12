require "test_helper"

class SetupRedirectTest < ActionDispatch::IntegrationTest
  test "every page redirects to /cs-studio/setup while setup is required" do
    start_fresh_install

    [ "/", "/about", "/de/about", "/cs-studio", "/cs-studio/posts" ].each do |path|
      get path
      assert_redirected_to "/cs-studio/setup", "expected #{path} to redirect to /cs-studio/setup"
    end
  end

  # Only a page load is sent into the wizard: a GET or HEAD that asks for
  # HTML and is no prefetch. Anything else a browser asks for on its own (an
  # icon, DevTools' file, a prefetch) or a write answers 404, and loads no
  # session: sent into the wizard, it would write the session cookie back as
  # read, over what a parallel request had just kept there.
  test "a write is answered 404, and loads no session" do
    start_fresh_install

    post "/cs-studio/posts"

    assert_response :not_found
    assert_nil response.headers["Set-Cookie"]
  end

  test "an icon, DevTools' file and a prefetch are answered 404 and write no cookie" do
    start_fresh_install
    verify_setup_token
    image = { "Accept" => "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", "Sec-Fetch-Dest" => "image" }

    [ "/favicon.ico", "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png" ].each do |path|
      get path, headers: image
      assert_response :not_found, path
      assert_nil response.headers["Set-Cookie"], "#{path} leaves the session cookie alone"
    end

    get "/.well-known/appspecific/com.chrome.devtools.json", headers: { "Accept" => "*/*", "Sec-Fetch-Dest" => "empty" }
    assert_response :not_found
    assert_nil response.headers["Set-Cookie"]

    [ { "X-Sec-Purpose" => "prefetch" }, { "Sec-Purpose" => "prefetch" } ].each do |purpose|
      get "/cs-studio/posts", headers: { "Accept" => "text/html" }.merge(purpose)
      assert_response :not_found, purpose.keys.first
      assert_nil response.headers["Set-Cookie"]
    end

    head "/about", headers: { "Accept" => "text/html" }
    assert_redirected_to "/cs-studio/setup", "a HEAD for a page is a page load"
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

  test "the wizard itself is not redirected, and the preview is" do
    start_fresh_install

    get "/cs-studio/setup"
    assert_not_equal "/cs-studio/setup", URI.parse(response.location.to_s).path if response.redirect?

    get "/cs-studio/preview", headers: { "Accept" => "text/html" }
    assert_redirected_to "/cs-studio/setup"
  end

  test "nothing is redirected once setup is complete" do
    get admin_sign_in_path
    assert_response :success

    get "/cs-studio"
    assert_not_equal "/cs-studio/setup", URI.parse(response.location.to_s).path
  end
end
