require "test_helper"

# "Connect an AI assistant" (design spec §6.1): the token list, a one-time
# reveal of a freshly issued token, and revoke. The raw token exists only
# in the `create` response itself -- never in a redirect, the flash, the
# session, the database or the log.
class Admin::ApiTokensTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "the list shows active and revoked tokens with last used and IP" do
    active, = ApiToken.generate!(users(:one))
    active.record_usage!("203.0.113.5")
    revoked, = ApiToken.generate!(users(:two))
    revoked.revoke!

    get "/cs-studio/api_tokens"

    assert_response :success
    assert_select "#" + ActionView::RecordIdentifier.dom_id(active) do
      assert_select "*", text: /203\.0\.113\.5/
      assert_select "*", text: /Active/
      assert_select "button", text: "Revoke"
    end
    assert_select "#" + ActionView::RecordIdentifier.dom_id(revoked) do
      assert_select "*", text: /Revoked/
      assert_select "button", text: "Revoke", count: 0
    end
    assert_not_includes response.body, active.token_digest
  end

  test "the list names the MCP URL and a client config snippet" do
    get "/cs-studio/api_tokens"

    assert_includes response.body, "#{PublicSite::Urls.default_host}/mcp"
    assert_select "pre", text: /mcpServers/
  end

  test "creating a token reveals it once, no-store, in the response itself" do
    assert_difference -> { ApiToken.count }, 1 do
      post "/cs-studio/api_tokens"
    end

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    raw = raw_token_from(response.body)
    token = ApiToken.order(:id).last
    assert_equal users(:one), token.user
    assert token.authenticate_token(raw)
    assert_select "pre", text: /#{raw}/ # the client config snippet carries it
    assert_includes response.body, "#{PublicSite::Urls.default_host}/mcp"

    assert_nil flash[:notice]
    assert_not_includes session.to_hash.to_s, raw
    assert_not_includes flash.to_hash.to_s, raw

    get "/cs-studio/api_tokens"
    assert_not_includes response.body, raw
  end

  test "the raw token never reaches the log" do
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    ActionController::Base.logger = Rails.logger

    post "/cs-studio/api_tokens"
    raw = raw_token_from(response.body)

    assert_not_includes io.string, raw
    assert_includes io.string, "api_tokens" # the logger really was capturing this request
  ensure
    Rails.logger = original
    ActionController::Base.logger = original
  end

  test "revoking a token stops it authenticating MCP requests immediately" do
    token, raw = ApiToken.generate!(users(:one))

    mcp_list(raw)
    assert_response :success

    delete "/cs-studio/api_tokens/#{token.id}"
    assert_redirected_to "/cs-studio/api_tokens"
    assert token.reload.revoked_at.present?

    mcp_list(raw)
    assert_response :unauthorized
  end

  test "the modules column links to the AI assistant module" do
    get "/cs-studio/api_tokens"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/api_tokens']", text: "AI assistant"
  end

  private

  def raw_token_from(body)
    Nokogiri::HTML::Document.parse(body).at_css("#api-token-value").text.strip
  end

  # The MCP transport only accepts a loopback Host (`McpTest`'s own setup
  # explains why), while the admin session cookie belongs to the default
  # test host -- so each MCP call switches host and switches straight back.
  def mcp_list(raw)
    admin_host = host
    host! "127.0.0.1"
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw}" }
  ensure
    host! admin_host
  end
end
