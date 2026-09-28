require "test_helper"

# MCP under permissions (access-control design spec §3.3, §3.4): a bearer
# token acts within the intersection of its group and its user's own
# rights. Reads go through `AccessControl.scope` -- a post outside that
# scope is "not found", exactly like a missing id, so its existence isn't
# disclosed (Review Focus 2) -- and writes rely on the services, whose
# refusals come back as tool errors carrying the permission message.
class McpAccessControlTest < ActionDispatch::IntegrationTest
  setup do
    # StreamableHTTPTransport's DNS-rebinding allowlist -- see McpTest.
    host! "127.0.0.1"
  end

  def token_for(user, group)
    _token, raw = ApiToken.generate!(user, group: group)
    raw
  end

  def mcp_post(raw_token, body)
    post "/mcp", params: body.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw_token}" }
    assert_response :success
    response.parsed_body
  end

  def call_tool(raw_token, name, arguments = {})
    mcp_post(raw_token, jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments })["result"]
  end

  def text_of(result) = result["content"].map { |item| item["text"] }.join("\n")

  # --- Read only ---------------------------------------------------------

  test "a Read only token lists only the posts its group and user may read" do
    readable = create_post(title: "Readable blog")
    unreadable = create_post(title: "Hidden resume", content_type: "resume_entry")
    # Read only's grants are unscoped, so narrow what the *user* may read:
    # the token sees the intersection, never more than either side.
    reader_only_blogs = AccessControl::Group.create!(name: "Blog readers")
    reader_only_blogs.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    user = User.create!(email_address: "blog-reader@example.com", password: "password123")
    AccessControl::Membership.create!(user: user, group: reader_only_blogs)
    AccessControl::Membership.create!(user: user, group: access_control_groups(:read_only))
    raw = token_for(user, reader_only_blogs)

    result = call_tool(raw, "list_posts_tool")

    assert_equal false, result["isError"]
    ids = result["structuredContent"].map { |post| post["id"] }
    assert_includes ids, readable.id
    assert_not_includes ids, unreadable.id
    assert_not_includes text_of(result), "Hidden resume"
  end

  test "a Read only token can't create posts: a tool error with the permission message" do
    raw = token_for(users(:reader), access_control_groups(:read_only))

    assert_no_difference "Post.count" do
      result = call_tool(raw, "create_post_tool", content_type: "blog", title: "Nope")

      assert_equal true, result["isError"]
      assert_includes text_of(result), "You don't have permission to create posts"
    end
  end

  test "get_post for a post outside the token's read scope is not found, exactly like a missing id" do
    hidden = create_post(title: "Secret resume", content_type: "resume_entry")
    blog_readers = AccessControl::Group.create!(name: "Blog readers")
    blog_readers.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    raw = token_for(users(:reader), blog_readers)

    out_of_scope = call_tool(raw, "get_post_tool", id: hidden.id)
    missing = call_tool(raw, "get_post_tool", id: Post.maximum(:id).to_i + 1000)

    assert_equal true, out_of_scope["isError"]
    assert_equal "Post not found", text_of(out_of_scope)
    assert_not_includes text_of(out_of_scope), "Secret resume"
    assert_equal text_of(missing), text_of(out_of_scope)
    assert_equal missing.except("content"), out_of_scope.except("content")
  end

  test "update_post for a post outside the token's read scope is not found, and writes nothing" do
    hidden = create_post(title: "Secret resume", content_type: "resume_entry")
    blog_readers = AccessControl::Group.create!(name: "Blog readers")
    blog_readers.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    raw = token_for(users(:reader), blog_readers)

    assert_no_difference "Audit::Event.count" do
      result = call_tool(raw, "update_post_tool", id: hidden.id, title: "Hacked")

      assert_equal true, result["isError"]
      assert_equal "Post not found", text_of(result)
    end
    assert_equal "Secret resume", hidden.reload.title
  end

  # --- Author ------------------------------------------------------------

  test "an Author token creates a blog post, audited as the token on the mcp channel" do
    author = users(:author)
    token, raw = ApiToken.generate!(author, group: access_control_groups(:author))

    result = call_tool(raw, "create_post_tool", content_type: "blog", title: "Mine via MCP")

    assert_equal false, result["isError"], text_of(result)
    created = Post.find(result["structuredContent"]["id"])
    assert_equal author, created.author

    event = Audit::Event.find_by!(action: "post.created", subject: created)
    assert_equal "mcp", event.channel
    assert_equal token, event.actor
    assert_equal author.id, event.user_id
  end

  test "an Author token can't update someone else's post" do
    theirs = create_post(title: "Theirs", published: false)
    theirs.update!(author: users(:two))
    raw = token_for(users(:author), access_control_groups(:author))

    result = call_tool(raw, "update_post_tool", id: theirs.id, title: "Mine now")

    assert_equal true, result["isError"]
    assert_includes text_of(result), "You don't have permission to"
    assert_equal "Theirs", theirs.reload.title
  end

  # --- Instructions ------------------------------------------------------

  test "the initialize response names the token's group, and nothing about other tokens or users" do
    other = User.create!(email_address: "someone-else@example.com", password: "password123")
    ApiToken.generate!(other, group: access_control_groups(:editor))
    raw = token_for(users(:author), access_control_groups(:author))

    body = mcp_post(raw, jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })

    instructions = body["result"]["instructions"]
    assert_includes instructions, "the Author group"
    assert_includes instructions, users(:author).email_address
    assert_not_includes instructions, "someone-else@example.com"
    assert_not_includes instructions, "Editor"
  end

  # --- Known references through Markdown ----------------------------------

  # A token that may edit every post but read only branch A of the page
  # tree. A link it can't read (to branch B) was already in the post's
  # body; `update_post` round-trips the body through Markdown, and that
  # link must survive, exactly as it does in the admin editor -- only a
  # *new* reference has to exist and be readable.
  def setup_branch_editor
    @page_a = create_page(title: "A")
    @page_b = create_page(title: "B")
    @page_c = create_page(title: "C")
    group = access_control_groups(:branch_editors)
    %w[posts.read posts.edit posts.publish].each { |key| group.grants.create!(permission: key, scope: {}) }
    group.grants.create!(permission: "pages.read", scope: { "page_ids" => [ @page_a.id ] })
    token_for(users(:editor_branch), group)
  end

  test "update_post keeps a pre-existing link to a page the token can't read" do
    raw = setup_branch_editor
    post_record = create_post(title: "Linked")
    post_record.update!(body: rich_doc("See [B](cs:page/#{@page_b.id}) and [A](cs:page/#{@page_a.id})."))

    result = call_tool(raw, "update_post_tool", id: post_record.id,
      body: "Now see [B](cs:page/#{@page_b.id}) and [A](cs:page/#{@page_a.id}).")

    assert_equal false, result["isError"], text_of(result)
    assert_equal 1, result["content"].size, "no conversion warnings expected: #{text_of(result)}"
    assert_equal rich_doc("Now see [B](cs:page/#{@page_b.id}) and [A](cs:page/#{@page_a.id})."),
      post_record.reload.body_document(locale: Locales.default).to_h
  end

  test "update_post keeps a pre-existing link to a page deleted since" do
    raw = setup_branch_editor
    doomed = create_page(title: "Doomed")
    post_record = create_post(title: "Linked")
    post_record.update!(body: rich_doc("See [gone](cs:page/#{doomed.id})."))
    doomed.destroy!

    result = call_tool(raw, "update_post_tool", id: post_record.id, body: "Still [gone](cs:page/#{doomed.id}).")

    assert_equal false, result["isError"], text_of(result)
    assert_equal 1, result["content"].size, text_of(result)
    assert_includes post_record.reload.body_document(locale: Locales.default).to_markdown, "cs:page/#{doomed.id}"
  end

  test "update_post keeps a pre-existing image whose media asset was deleted since" do
    raw = setup_branch_editor
    asset = create_media_asset
    post_record = create_post(title: "Pictured")
    post_record.update!(body: rich_doc("Intro\n\n::image{asset=\"#{asset.id}\" alt=\"Tiny\"}"))
    asset.destroy!

    result = call_tool(raw, "update_post_tool", id: post_record.id, body: "New intro\n\n::image{asset=\"#{asset.id}\" alt=\"Tiny\"}")

    assert_equal false, result["isError"], text_of(result)
    assert_equal 1, result["content"].size, text_of(result)
    assert_includes post_record.reload.body_document(locale: Locales.default).to_markdown, "::image{asset=\"#{asset.id}\""
  end

  test "update_post drops a newly added link to an unreadable page with the same warning as a missing one" do
    raw = setup_branch_editor
    post_record = create_post(title: "Linked")
    post_record.update!(body: rich_doc("See [B](cs:page/#{@page_b.id})."))
    missing_id = Page.maximum(:id).to_i + 1000

    result = call_tool(raw, "update_post_tool", id: post_record.id,
      body: "See [B](cs:page/#{@page_b.id}), [C](cs:page/#{@page_c.id}) and [X](cs:page/#{missing_id}).")

    assert_equal false, result["isError"], text_of(result)
    warnings = result["content"].second["text"]
    assert_includes warnings, "dropped an internal link to a missing page (#{@page_c.id})"
    assert_includes warnings, "dropped an internal link to a missing page (#{missing_id})"
    markdown = post_record.reload.body_document(locale: Locales.default).to_markdown
    assert_includes markdown, "cs:page/#{@page_b.id}"
    assert_not_includes markdown, "cs:page/#{@page_c.id}"
  end

  test "a pre-existing link in another locale is not a known reference for this one" do
    raw = setup_branch_editor
    with_locales(%w[en de], default: "en")
    post_record = create_post(title: "Linked")
    post_record.update!(body: rich_doc("See [B](cs:page/#{@page_b.id})."))

    result = call_tool(raw, "update_post_tool", id: post_record.id, locale: "de",
      body: "Siehe [B](cs:page/#{@page_b.id}).")

    assert_includes result["content"].second["text"], "dropped an internal link to a missing page (#{@page_b.id})"
    assert_not_includes post_record.reload.body_document(locale: "de").to_markdown, "cs:page/"
  end
end
