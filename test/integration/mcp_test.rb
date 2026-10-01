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
    # The token acts within the intersection of its group and its user's
    # own rights (access-control design spec §3.3), so the user needs some
    # of their own -- a user in no group can't write anything, token or not.
    AccessControl::Membership.create!(user: @user, group: access_control_groups(:admin))
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
  # (Task 12): the four post-tool names are what MCP clients already call
  # those tools by, and the mcp gem derives a tool's default name from its
  # demodulized class name -- so `Mcp::Tools::CreatePost` would default to
  # "create_post", not "create_post_tool", if each tool didn't pin its name
  # explicitly with `tool_name`. This test was green before that move (the
  # baseline) and must stay green after it, precisely because the names it
  # asserts are the ones clients depend on, not the classes' own names.
  # `list_media_tool`/`get_media_tool` (media library Task 9) joined the
  # same registered set afterwards, pinned the same way.
  test "a valid request lists all six tools" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")

    assert_response :success
    names = response.parsed_body["result"]["tools"].map { |tool| tool["name"] }
    assert_equal %w[list_posts_tool get_post_tool create_post_tool update_post_tool list_media_tool get_media_tool].sort,
      names.sort
  end

  # `create_post_tool`'s `content_type` enum has to be read fresh on every
  # `tools/list`, not frozen the moment the class body ran -- a type
  # registered after boot (a plugin, or this test) must still show up
  # without a server restart. Registering one here and then listing is what
  # actually proves that, rather than just asserting the built-in three.
  test "the create_post_tool content_type enum reflects the registry, including a type registered at runtime" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")
    tool = response.parsed_body["result"]["tools"].find { |t| t["name"] == "create_post_tool" }
    assert_equal %w[blog resume_entry now_update].sort, tool["inputSchema"]["properties"]["content_type"]["enum"].sort

    saved = ContentTypes.all.dup
    begin
      ContentTypes.register("test/type") { |t| t.label "Test type" }

      mcp_post(jsonrpc: "2.0", id: 2, method: "tools/list")
      tool = response.parsed_body["result"]["tools"].find { |t| t["name"] == "create_post_tool" }
      assert_includes tool["inputSchema"]["properties"]["content_type"]["enum"], "test/type"
    ensure
      ContentTypes.reset!
      saved.each { |definition| ContentTypes.registry_put(definition) }
    end
  end

  # Mirrors the create_post_tool test above -- ListPosts overrides its own
  # `input_schema_value` too (see the comment there), so it needs the same
  # end-to-end proof.
  test "the list_posts_tool content_type enum reflects the registry, including a type registered at runtime" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")
    tool = response.parsed_body["result"]["tools"].find { |t| t["name"] == "list_posts_tool" }
    assert_equal %w[blog resume_entry now_update].sort, tool["inputSchema"]["properties"]["content_type"]["enum"].sort

    saved = ContentTypes.all.dup
    begin
      ContentTypes.register("test/type") { |t| t.label "Test type" }

      mcp_post(jsonrpc: "2.0", id: 2, method: "tools/list")
      tool = response.parsed_body["result"]["tools"].find { |t| t["name"] == "list_posts_tool" }
      assert_includes tool["inputSchema"]["properties"]["content_type"]["enum"], "test/type"
    ensure
      ContentTypes.reset!
      saved.each { |definition| ContentTypes.registry_put(definition) }
    end
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
    assert_equal @user, Post.last.author
  end

  test "a malformed tool call (missing a required argument) returns a tool error, not a 500" do
    mcp_post(
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "get_post_tool", arguments: {} }
    )

    assert_response :success
    assert_equal true, response.parsed_body["result"]["isError"]
  end

  # Dashboard spec §5: MCP runs under the site's own time zone too (the
  # same `around_action` `Admin::BaseController` wraps every CS Studio
  # request with), so a published_at this serialises carries the site's
  # UTC offset rather than always reading "Z" regardless of what the site
  # considers "local".
  test "a post's published_at carries the site's time zone offset, not Z" do
    site_settings(:default).update!(time_zone: "Europe/Berlin")
    post_record = create_post(title: "Zoned")

    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "get_post_tool", arguments: { id: post_record.id } })

    result = response.parsed_body["result"]
    data = JSON.parse(result["content"].first["text"])
    assert_match(/\A.*\d\d:\d\d\+(01|02):00\z/, data["published_at"])
  end

  test "a valid token records its usage" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")

    assert_not_nil @token.reload.last_used_at
    assert_equal "127.0.0.1", @token.last_used_ip
  end
end
