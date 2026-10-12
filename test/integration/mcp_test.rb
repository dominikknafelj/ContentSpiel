require "test_helper"

# The MCP server (design spec section 10) -- verified end-to-end against a
# live dev server first (curl, real JSON-RPC requests, a real bearer token),
# not just in these tests: `tools/list`, `create_post_tool` (checked the
# response body was the clean stored HTML, not a rendered-view artifact --
# see Mcp::PostSerializer's own comment for that one), `get_post_tool`,
# `update_post_tool`, a malformed call, and an invalid token.
class McpTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password12345")
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

  # Fix round 1: same fallback as Admin::TimeZoneTest's own "unrecognised
  # stored time zone" test, for MCP -- `use_site_time_zone` wraps this
  # controller's one action too, so a bad stored zone must not 500 the
  # whole endpoint either.
  test "an unrecognised stored time zone still answers MCP, in UTC" do
    site_settings(:default).update_column(:time_zone, "Mars/Olympus")
    post_record = create_post(title: "Still answers")
    post_record.update_columns(published_at: Time.utc(2030, 7, 1, 7, 30))

    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "get_post_tool", arguments: { id: post_record.id } })

    assert_response :success
    result = response.parsed_body["result"]
    assert_equal false, result["isError"]
    data = JSON.parse(result["content"].first["text"])
    assert_equal "2030-07-01T07:30:00Z", data["published_at"]
  end

  test "a valid token records its usage" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")

    assert_not_nil @token.reload.last_used_at
    assert_equal "127.0.0.1", @token.last_used_ip
  end

  # -- drafts of live content (Task 7) -------------------------------------------

  def call_tool(name, **arguments)
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments })
    assert_response :success
    response.parsed_body["result"]
  end

  def tool_data(result) = JSON.parse(result["content"].first["text"])

  def live_post(title = "Live post")
    Current.set(actor: @user) do
      Posts::Save.call(attributes: { content_type: "blog", published: true }, translations: { "en" => { title: title, body: rich_doc("As published") } }).record
    end
  end

  test "update_post on a live post leaves the site as it was and answers unpublished_changes: true" do
    record = live_post

    result = call_tool("update_post_tool", id: record.id, title: "Edited by a token")

    assert_equal false, result["isError"]
    assert_equal true, tool_data(result)["unpublished_changes"]
    assert_equal "Edited by a token", tool_data(result)["title"]
    assert_equal "Live post", Mobility.with_locale(:en) { Publishing.published(record.reload).title }, "the site shows what was published"
    assert_equal 1, Publishing::Version.of(record).count
  end

  test "update_post with publish_changes: true publishes in the same call and answers unpublished_changes: false" do
    record = live_post

    result = call_tool("update_post_tool", id: record.id, title: "Edited and published", publish_changes: true)

    assert_equal false, result["isError"]
    assert_equal false, tool_data(result)["unpublished_changes"]
    assert_equal "Edited and published", Mobility.with_locale(:en) { Publishing.published(record.reload).title }
    assert_equal 2, Publishing.current(record).number
    assert_equal "mcp", Audit::Event.where(action: "post.changes_published", subject: record).sole.channel

    again = call_tool("update_post_tool", id: record.id, title: "Edited and published", publish_changes: true)
    assert_equal false, again["isError"], "a second identical call finds nothing to publish"
    assert_equal 2, Publishing::Version.of(record).count
  end

  test "update_post with publish_changes: true publishes now, also over a change already scheduled for later" do
    record = live_post
    assert Current.set(actor: @user) { Posts::Save.call(record, translations: { "en" => { title: "Scheduled for later" } }).ok? }
    Current.set(actor: @user) { publish_changes(record, at: 3.days.from_now) }
    assert Publishing.pending(record)

    result = call_tool("update_post_tool", id: record.id, title: "Edited and published", publish_changes: true)

    assert_equal false, result["isError"]
    assert_equal false, tool_data(result)["unpublished_changes"]
    assert_nil Publishing.pending(record), "the scheduled change is replaced by this publication"
    assert_equal "Edited and published", Mobility.with_locale(:en) { Publishing.published(record.reload).title }
  end

  test "publish_changes on a draft is ignored: it is published with published: true" do
    record = Current.set(actor: @user) { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "Draft" } }).record }

    result = call_tool("update_post_tool", id: record.id, title: "Still a draft", publish_changes: true)

    assert_equal false, result["isError"]
    assert_equal "draft", tool_data(result)["status"]
    assert_equal false, tool_data(result)["unpublished_changes"]
    assert_empty Publishing::Version.of(record)

    result = call_tool("update_post_tool", id: record.id, published: true)
    assert_equal "live", tool_data(result)["status"]
    assert_equal 1, Publishing::Version.of(record).count
  end

  test "a token that may edit and publish posts needs no further right for publish_changes; one that may not publish is refused the whole call's publication and the edit of a live post as before" do
    record = live_post
    group = AccessControl::Group.create!(name: "Post editors and publishers")
    %w[posts.read posts.edit posts.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    @token, @raw_token = ApiToken.generate!(@user, group: group)

    result = call_tool("update_post_tool", id: record.id, title: "By a narrow token", publish_changes: true)
    assert_equal false, result["isError"]
    assert_equal 2, Publishing.current(record).number

    editors = AccessControl::Group.create!(name: "Post editors")
    %w[posts.read posts.edit].each { |key| AccessControl::Grant.create!(group: editors, permission: key, scope: {}) }
    @token, @raw_token = ApiToken.generate!(@user, group: editors)

    result = call_tool("update_post_tool", id: record.id, title: "Not allowed", publish_changes: true)
    assert_equal true, result["isError"]
    assert_match(/permission to publish posts/i, result["content"].first["text"])
    assert_equal "By a narrow token", Mobility.with_locale(:en) { record.reload.title }, "nothing was saved"
    assert_equal 2, Publishing::Version.of(record).count
  end

  test "when the publication is refused the edit stays saved and the answer says both" do
    record = live_post
    refusal = ->(*, **) { ApplicationService::Result.failure(record, [ "The post “Live post” would get the address /x, which is already taken in EN" ]) }

    result = with_singleton_override(Publishing::PublishChanges, :call, refusal) do
      call_tool("update_post_tool", id: record.id, title: "Saved only", publish_changes: true)
    end

    assert_equal true, result["isError"]
    assert_equal "The post was saved, but its changes were not published: The post “Live post” would get the address /x, which is already taken in EN", result["content"].first["text"]
    assert_equal "Saved only", Mobility.with_locale(:en) { record.reload.title }
    assert record.unpublished_changes?
  end

  test "get_post and list_posts say unpublished_changes" do
    changed = live_post("Changed")
    Current.set(actor: @user) { assert Posts::Save.call(changed, translations: { "en" => { title: "Changed since" } }).ok? }
    clean = live_post("Clean")

    assert_equal true, tool_data(call_tool("get_post_tool", id: changed.id))["unpublished_changes"]
    assert_equal false, tool_data(call_tool("get_post_tool", id: clean.id))["unpublished_changes"]
    assert_equal "Changed since", tool_data(call_tool("get_post_tool", id: changed.id))["title"], "the tools read the working version"

    listed = tool_data(call_tool("list_posts_tool")).index_by { |entry| entry["id"] }
    assert_equal [ true, false ], listed.values_at(changed.id, clean.id).map { |entry| entry["unpublished_changes"] }
  end

  test "the update_post_tool schema offers publish_changes, a boolean, and its description says a live post's edit is not public" do
    mcp_post(jsonrpc: "2.0", id: 1, method: "tools/list")
    tool = response.parsed_body["result"]["tools"].find { |entry| entry["name"] == "update_post_tool" }

    assert_equal "boolean", tool["inputSchema"]["properties"]["publish_changes"]["type"]
    assert_match(/Editing a live or scheduled post does not change the site/, tool["description"])
  end
end
