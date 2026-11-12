require "test_helper"

class BackendRoutesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "Action Mailbox draws no route" do
    specs = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
    assert_empty specs.grep(%r{\A/rails/(action_mailbox|conductor)})
    assert_not defined?(ActionMailbox::Engine)
  end

  test "a CS Studio page names the cable's address for turbo-rails' consumer" do
    sign_in_as(users(:one))
    get "/cs-studio"
    assert_select "meta[name='action-cable-url'][content='/cs-studio/cable']"
  end

  test "Turbo's historical-location routes are not drawn" do
    assert_empty Rails.application.routes.routes.map { |route| route.path.spec.to_s }.grep(/historical_location/)
  end

  test "the preview answers under the admin path, and /preview is a public page path" do
    create_page(title: "Draft", published: false)
    sign_in_as(users(:one))

    get "/cs-studio/preview/draft"
    assert_response :success

    get "/preview/draft"
    assert_response :not_found
    assert_includes response.body, "Page not found"
  end

  test "the wizard is not at /setup, and answers 404 under the admin path once setup is complete" do
    get "/setup"
    assert_response :not_found
    assert_includes response.body, "Page not found"

    get "/cs-studio/setup"
    assert_response :not_found
  end

  test "POST /mcp is no endpoint any more" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer anything" }
    assert_response :not_found
  end

  test "a top-level page slugged preview is served at /preview" do
    create_page(title: "Preview", published: true)
    get "/preview"
    assert_response :success
  end
end
