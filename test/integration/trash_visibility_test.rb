require "test_helper"

# Every narrowing point that must hide trashed pages, posts and images
# (trash spec §5.4). Each test builds one kept and one trashed record and
# fails if the trashed one leaks. A new list, search, picker or public query
# that reads pages, posts or library images belongs here too.
#
# Trashing is done by setting `trashed_at` straight on the record (the trash
# services come later): `update!` still runs the model callbacks, so the
# trashed page and post lose their `public_paths` rows exactly as a real
# move to the trash would make them (trash spec §4.1, `PublicSite::Paths
# #compute_path`).
class TrashVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: @blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    @kept_post = create_post(title: "Kept post")
    @gone_post = create_post(title: "Gone post")
    @kept_page = create_page(title: "Kept page")
    @gone_page = create_page(title: "Gone page")
    @kept_asset = create_media_asset
    @gone_asset = create_media_asset
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: Time.current) }
  end

  # --- AccessControl.scope ----------------------------------------------------

  test "AccessControl.scope hides trashed pages, posts and their blocks" do
    as(users(:one)) do
      assert_includes AccessControl.scope(users(:one), "pages.read", Page.all), @kept_page
      assert_not_includes AccessControl.scope(users(:one), "pages.read", Page.all), @gone_page
      assert_includes AccessControl.scope(users(:one), "posts.read", Post.all), @kept_post
      assert_not_includes AccessControl.scope(users(:one), "posts.read", Post.all), @gone_post
      assert_equal [ @gone_page ], AccessControl.scope(users(:one), "pages.read", Page.all, trashed: true).to_a
      assert_equal [ @gone_post ], AccessControl.scope(users(:one), "posts.read", Post.all, trashed: true).to_a
    end
    gone_block = ContentBlock.create!(owner: @gone_page, block_type: "rich_text", position: 1)
    kept_block = ContentBlock.create!(owner: @kept_page, block_type: "rich_text", position: 1)
    # users(:two) holds grants (the Admin group), users(:one) is an owner:
    # the grant path and the unrestricted path both hide the block.
    [ users(:one), users(:two) ].each do |user|
      blocks = AccessControl.scope(user, "pages.read", ContentBlock.all, channel: :admin)
      assert_includes blocks, kept_block
      assert_not_includes blocks, gone_block
    end
    assert_not_includes AccessControl.tree_visibility(users(:two), channel: :admin)[:readable], @gone_page.id
  end

  # --- Public site ------------------------------------------------------------

  test "the public site 404s a trashed page and post and drops them from listings and navigation" do
    assert_not PublicSite::Resolver.visible?(@gone_page)
    assert_not PublicSite::Resolver.visible?(@gone_post)

    get "/gone-page"
    assert_response :not_found
    get "/blog/gone-post"
    assert_response :not_found
    get "/blog"
    assert_response :ok
    assert_includes response.body, "Kept post"
    assert_includes response.body, "Kept page"
    assert_not_includes response.body, "Gone post"
    assert_not_includes response.body, "Gone page"
  end

  test "a post list block never lists a trashed post, published or not" do
    block = @blog.content_blocks.listing.sole
    assert_includes block.listed_posts, @kept_post
    assert_not_includes block.listed_posts, @gone_post
    assert_not_includes block.listed_posts(include_unpublished: true), @gone_post
  end

  test "the listing-page fallback doesn't redirect to a trashed post" do
    # `/blog/<slug>` for a post whose canonical URL lives elsewhere is
    # resolved by slug straight off `posts` -- not `public_paths` -- so it
    # has to skip a trashed post itself.
    other = create_page(title: "Other")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?

    get "/other/kept-post"
    assert_response :moved_permanently
    get "/other/gone-post"
    assert_response :not_found
  end

  test "preview 404s a trashed page and post" do
    sign_in_as users(:one)
    get "/preview/gone-page"
    assert_response :not_found
    get "/preview/blog/gone-post"
    assert_response :not_found
    get "/preview/kept-page"
    assert_response :ok
  end

  # --- CS Studio --------------------------------------------------------------

  test "CS Studio 404s a trashed page, post and image by id, and autosave can't revive one" do
    sign_in_as users(:one)
    get "/cs-studio/pages/#{@gone_page.id}"
    assert_response :not_found
    get "/cs-studio/posts/#{@gone_post.id}"
    assert_response :not_found
    get "/cs-studio/media/#{@gone_asset.id}"
    assert_response :not_found

    # A tab left open on a page someone else trashed keeps autosaving, in
    # the exact shape the page editor sends (Review Focus 4).
    patch "/cs-studio/pages/#{@gone_page.id}", params: { page: { title: "Revived?" }, base_updated_at: @gone_page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :not_found
    patch "/cs-studio/posts/#{@gone_post.id}", params: { post: { title: "Revived?" }, base_updated_at: @gone_post.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :not_found
    patch "/cs-studio/media/#{@gone_asset.id}", params: { media_asset: { title: "Revived?" } }
    assert_response :not_found

    assert @gone_page.reload.trashed?
    assert_equal "Gone page", @gone_page.title
    assert @gone_post.reload.trashed?
    assert_equal "Gone post", @gone_post.title
    assert @gone_asset.reload.trashed?
  end

  test "the page tree, posts list, link targets and mind graph hide trashed pages and posts" do
    sign_in_as users(:one)

    get "/cs-studio"
    assert_select "turbo-frame#tree li[data-page-id='#{@kept_page.id}']"
    assert_select "turbo-frame#tree li[data-page-id='#{@gone_page.id}']", count: 0

    get "/cs-studio/posts"
    assert_select "tbody tr", /Kept post/
    assert_select "tbody tr", text: /Gone post/, count: 0

    get "/cs-studio/link_targets", params: { q: "gone", locale: "en" }
    assert_empty response.parsed_body
    get "/cs-studio/link_targets", params: { q: "kept", locale: "en" }
    assert_equal [ [ "page", @kept_page.id ], [ "post", @kept_post.id ] ].sort, response.parsed_body.map { |r| [ r["type"], r["id"] ] }.sort

    PostRelation.create!(post: @kept_post, related_post: @gone_post)
    get "/cs-studio/mind_graph"
    nodes = JSON.parse(Nokogiri::HTML::Document.parse(response.body).at_css("script#mind-graph-data[type='application/json']").text)["nodes"]
    assert_includes nodes.map { |n| n["id"] }, @kept_post.id
    assert_not_includes nodes.map { |n| n["id"] }, @gone_post.id
  end

  test "the related-posts editor neither shows a trashed post nor counts it as one you can't open" do
    PostRelation.create!(post: @kept_post, related_post: @gone_post)
    component = Admin::RelatedPostsComponent.new(post: @kept_post, locale: "en")

    as(users(:one)) do
      assert_empty component.related
      assert_equal 0, component.hidden_related_count
    end
  end

  test "adding a trashed post as a related post is refused like an unknown id" do
    as(users(:one)) do
      result = Posts::Save.call(@kept_post, attributes: { related_post_ids: [ @gone_post.id ] })
      assert_not result.ok?
    end
    assert_empty @kept_post.reload.related_posts
  end

  test "the media library, picker and search hide trashed images" do
    sign_in_as users(:one)
    get "/cs-studio/media"
    assert_select "#media-asset-#{@kept_asset.id}"
    assert_select "#media-asset-#{@gone_asset.id}", count: 0

    get "/cs-studio/media", params: { picker: 1 }
    assert_select "#media-picker-asset-#{@kept_asset.id}"
    assert_select "#media-picker-asset-#{@gone_asset.id}", count: 0

    get "/cs-studio/media", params: { q: "tiny" }
    assert_select "#media-asset-#{@kept_asset.id}"
    assert_select "#media-asset-#{@gone_asset.id}", count: 0
  end

  # --- Choosing and embedding images -------------------------------------------

  test "choosing or embedding a trashed image reads as missing" do
    as(users(:one)) do
      result = Pages::Save.call(@kept_page, attributes: { hero_media_asset_id: @gone_asset.id })
      assert_not result.ok?
      assert_equal [ "Hero image doesn't exist" ], result.errors

      block = ContentBlock.new(owner: @kept_page)
      result = ContentBlocks::Save.call(block, attributes: { block_type: "image", media_asset_id: @gone_asset.id })
      assert_not result.ok?
      assert_match(/doesn't exist/, result.errors.to_sentence)

      # Built from the kept image's document: the Markdown importer already
      # drops a directive naming a missing image, so it can't spell this one.
      body = rich_doc("::image{asset=\"#{@kept_asset.id}\"}")
      body["content"].sole["attrs"]["asset_id"] = @gone_asset.id
      result = Posts::Save.call(@kept_post, translations: { "en" => { body: body } })
      assert_not result.ok?
      assert_equal [ "Body (en) image.asset_id is invalid" ], result.errors
      assert_empty Media::Usage.where(owner: @kept_post)

      assert Pages::Save.call(@kept_page, attributes: { hero_media_asset_id: @kept_asset.id }).ok?
    end
    assert_equal @kept_asset.id, @kept_page.reload.hero_media_asset_id
  end

  # --- MCP --------------------------------------------------------------------

  test "MCP media and post tools don't see trashed records" do
    host! "127.0.0.1"
    _token, raw = ApiToken.generate!(users(:one), group: access_control_groups(:admin))

    listed_media = call_tool(raw, "list_media_tool")
    assert_equal false, listed_media["isError"], text_of(listed_media)
    media_ids = listed_media["structuredContent"].map { |item| item["id"] }
    assert_includes media_ids, @kept_asset.id
    assert_not_includes media_ids, @gone_asset.id

    got_media = call_tool(raw, "get_media_tool", id: @gone_asset.id)
    missing_media = call_tool(raw, "get_media_tool", id: Media::Asset.maximum(:id).to_i + 1000)
    assert_equal true, got_media["isError"]
    assert_equal text_of(missing_media), text_of(got_media)

    listed_posts = call_tool(raw, "list_posts_tool")
    post_ids = listed_posts["structuredContent"].map { |item| item["id"] }
    assert_includes post_ids, @kept_post.id
    assert_not_includes post_ids, @gone_post.id

    got_post = call_tool(raw, "get_post_tool", id: @gone_post.id)
    assert_equal true, got_post["isError"]
    assert_equal "Post not found", text_of(got_post)

    updated = call_tool(raw, "update_post_tool", id: @gone_post.id, title: "Revived?")
    assert_equal true, updated["isError"]
    assert_equal "Post not found", text_of(updated)
    assert_equal "Gone post", @gone_post.reload.title
  end

  private

  def call_tool(raw_token, name, arguments = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw_token}" }
    assert_response :success
    response.parsed_body["result"]
  end

  def text_of(result) = result["content"].map { |item| item["text"] }.join("\n")
end
