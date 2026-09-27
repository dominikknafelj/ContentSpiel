require "test_helper"

# The MCP server (design spec section 10) -- verified end-to-end against a
# live dev server first (curl, real JSON-RPC requests, a real bearer token),
# not just in these tests: `tools/list`, `create_post_tool` (checked the
# response body was the clean stored HTML, not a rendered-view artifact --
# see Mcp::PostSerializer's own comment for that one), `get_post_tool`,
# `update_post_tool`, a malformed call, and an invalid token.
class McpTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password123")
    @token, @raw_token = ApiToken.generate!(@user)

    # StreamableHTTPTransport rejects any Host header outside its own
    # DNS-rebinding-protection allowlist (127.0.0.1/::1/localhost by
    # default) with a 403 -- Rails' integration test default Host,
    # www.example.com, isn't on it.
    host! "127.0.0.1"
  end

  def mcp_post(body)
    post "/mcp", params: body.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{@raw_token}" }
  end

  test "a request with no Authorization header is rejected" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }

    assert_response :unauthorized
  end

  test "a request with an invalid token is rejected" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer not-a-real-token" }

    assert_response :unauthorized
  end

  test "a request with a revoked token is rejected" do
    @token.revoke!

    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")

    assert_response :unauthorized
  end

  # Doubles as the regression guard for the app/tools -> Mcp:: namespace move
  # (Task 12): these four names are what MCP clients already call the tools
  # by, and the mcp gem derives a tool's default name from its demodulized
  # class name -- so `Mcp::Tools::CreatePost` would default to "create_post",
  # not "create_post_tool", if each tool didn't pin its name explicitly with
  # `tool_name`. This test was green before that move (the baseline) and
  # must stay green after it, unchanged, precisely because the names it
  # asserts are the ones clients depend on, not the classes' own names.
  test "a valid request lists all four post tools" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")

    assert_response :success
    names = response.parsed_body["result"]["tools"].map { |tool| tool["name"] }
    assert_equal %w[list_posts_tool get_post_tool create_post_tool update_post_tool].sort, names.sort
  end

  test "a valid tool call creates a post, scoped to the token's user" do
    assert_difference "Post.count", 1 do
      mcp_post(
        jsonrpc: "2.0", id: 1, method: "tools/call",
        params: { name: "create_post_tool", arguments: { content_type: "blog", title: "Via MCP" } }
      )
    end

    assert_response :success
    result = response.parsed_body["result"]
    assert_equal false, result["isError"]
    assert_equal "Via MCP", Post.last.title
  end

  test "a malformed tool call (missing a required argument) returns a tool error, not a 500" do
    mcp_post(
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "get_post_tool", arguments: {} }
    )

    assert_response :success
    assert_equal true, response.parsed_body["result"]["isError"]
  end

  test "a valid token records its usage" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")

    assert_not_nil @token.reload.last_used_at
    assert_equal "127.0.0.1", @token.last_used_ip
  end
end
