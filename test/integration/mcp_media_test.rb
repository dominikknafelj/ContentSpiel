require "test_helper"

# `list_media_tool`/`get_media_tool` (media library design spec §5.2/§6,
# Task 9): an MCP client finding an id to reference from a rich-text
# ::image{} directive, and looking up where an image is already used.
# Both tools gate on `media.upload` alone (the same permission that gates
# opening the whole module in CS Studio -- there is no per-asset "read"),
# and `get_media` additionally folds any usage the token can't read
# (`pages.read`/`posts.read`) into a bare count rather than naming it
# ("not found, not forbidden", applied to a usage place instead of the
# asset itself).
class McpMediaTest < ActionDispatch::IntegrationTest
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

  # Mirrors `Media::Upload#analyze_dimensions` (test/models/media/asset_test
  # .rb's own private helper): `file.analyze` needs the blob's real bytes on
  # the storage service, which only exist once this record's save has
  # actually committed -- `create_media_asset` (test/support/content_helper
  # .rb) doesn't run it, since it builds the asset directly rather than
  # through `Media::Upload`.
  def analyze(asset)
    asset.file.analyze
    metadata = asset.file.blob.metadata || {}
    asset.update_columns(width: metadata["width"], height: metadata["height"])
  end

  # --- list_media ----------------------------------------------------------

  test "a token without media.upload gets a permission tool error for both tools" do
    raw = token_for(users(:reader), access_control_groups(:read_only))

    listed = call_tool(raw, "list_media_tool")
    got = call_tool(raw, "get_media_tool", id: 1)

    assert_equal true, listed["isError"]
    assert_includes text_of(listed), "You don't have permission to upload media"
    assert_equal true, got["isError"]
    assert_includes text_of(got), "You don't have permission to upload media"
  end

  test "list_media finds an image by title" do
    raw = token_for(users(:one), access_control_groups(:admin))
    matching = create_media_asset
    matching.update!(title: "Alpine trail")
    other = create_media_asset
    other.update!(title: "Beach sunset")

    result = call_tool(raw, "list_media_tool", query: "alpine")

    assert_equal false, result["isError"], text_of(result)
    ids = result["structuredContent"].map { |item| item["id"] }
    assert_equal [ matching.id ], ids
  end

  test "list_media finds an image by alt text" do
    raw = token_for(users(:one), access_control_groups(:admin))
    matching = create_media_asset
    matching.update!(alt: "A golden retriever puppy")
    other = create_media_asset
    other.update!(alt: "A city skyline at dusk")

    result = call_tool(raw, "list_media_tool", query: "retriever")

    ids = result["structuredContent"].map { |item| item["id"] }
    assert_equal [ matching.id ], ids
  end

  test "list_media unused: true filters to images with no usages" do
    raw = token_for(users(:one), access_control_groups(:admin))
    unused = create_media_asset
    used = create_media_asset
    page = create_page(title: "Has a hero")
    Pages::Save.call(page, attributes: { hero_media_asset_id: used.id })

    result = call_tool(raw, "list_media_tool", unused: true)

    ids = result["structuredContent"].map { |item| item["id"] }
    assert_includes ids, unused.id
    assert_not_includes ids, used.id
  end

  test "each list_media entry has id, title, alt, width, height, usage count and a paste-ready directive" do
    raw = token_for(users(:one), access_control_groups(:admin))
    asset = create_media_asset
    asset.update!(title: "Mountain", alt: "A snowy peak")
    analyze(asset)
    page = create_page(title: "Uses it")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })

    result = call_tool(raw, "list_media_tool", query: "Mountain")

    entry = result["structuredContent"].sole
    assert_equal asset.id, entry["id"]
    assert_equal "Mountain", entry["title"]
    assert_equal "A snowy peak", entry["alt"]
    assert_equal asset.width, entry["width"]
    assert_equal asset.height, entry["height"]
    assert_equal 1, entry["usage_count"]
    assert_equal %(::image{asset="#{asset.id}"}), entry["directive"]
  end

  # --- get_media -------------------------------------------------------------

  # Final fix wave (M5): the caption default is part of what an agent needs
  # to decide whether to override it in a directive.
  test "get_media returns the image's default caption in the requested locale" do
    raw = token_for(users(:one), access_control_groups(:admin))
    asset = create_media_asset
    Mobility.with_locale(:en) { asset.update!(caption: "The studio at dusk") }
    Mobility.with_locale(:de) { asset.update!(caption: "Das Studio am Abend") }

    english = call_tool(raw, "get_media_tool", id: asset.id, locale: "en")
    german = call_tool(raw, "get_media_tool", id: asset.id, locale: "de")

    assert_equal "The studio at dusk", english["structuredContent"]["caption"]
    assert_equal "Das Studio am Abend", german["structuredContent"]["caption"]
  end

  test "get_media reports an unknown id as Image not found" do
    raw = token_for(users(:one), access_control_groups(:admin))

    result = call_tool(raw, "get_media_tool", id: Media::Asset.maximum(:id).to_i + 1000)

    assert_equal true, result["isError"]
    assert_equal "Image not found", text_of(result)
  end

  test "get_media names usages the token can read, and folds the rest into hidden_usages" do
    asset = create_media_asset

    readable_post = create_post(title: "A readable post")
    Posts::Save.call(readable_post, translations: { Locales.default => { body: rich_doc(%(::image{asset="#{asset.id}" alt="x"})) } })

    unreadable_page = create_page(title: "A page this token can't read")
    Pages::Save.call(unreadable_page, attributes: { hero_media_asset_id: asset.id })

    # Reads posts, but not pages at all -- so the page hero usage above
    # must be counted, never named.
    group = AccessControl::Group.create!(name: "Post readers")
    group.grants.create!(permission: "posts.read", scope: {})
    group.grants.create!(permission: "media.upload", scope: {})
    raw = token_for(users(:one), group)

    result = call_tool(raw, "get_media_tool", id: asset.id)

    assert_equal false, result["isError"], text_of(result)
    data = result["structuredContent"]
    assert_equal asset.id, data["id"]
    assert_equal [ { "type" => "post", "id" => readable_post.id, "title" => "A readable post" } ], data["usages"]
    assert_equal 1, data["hidden_usages"]
    assert_equal 2, data["usage_count"]
    assert_not_includes text_of(result), "A page this token can't read"
  end

  test "get_media resolves a content block's image usage to the page it's on" do
    asset = create_media_asset
    page = create_page(title: "Has an image block")
    block = page.content_blocks.new
    ContentBlocks::Save.call(block, attributes: { block_type: "image", media_asset_id: asset.id })

    raw = token_for(users(:one), access_control_groups(:admin))

    result = call_tool(raw, "get_media_tool", id: asset.id)

    data = result["structuredContent"]
    assert_equal [ { "type" => "page", "id" => page.id, "title" => "Has an image block" } ], data["usages"]
    assert_equal 0, data["hidden_usages"]
  end

  test "get_media reports no usages for an unused image" do
    asset = create_media_asset
    raw = token_for(users(:one), access_control_groups(:admin))

    result = call_tool(raw, "get_media_tool", id: asset.id)

    data = result["structuredContent"]
    assert_equal [], data["usages"]
    assert_equal 0, data["hidden_usages"]
    assert_equal 0, data["usage_count"]
  end
end
