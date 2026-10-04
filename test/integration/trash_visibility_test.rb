require "test_helper"
require "sitemap_generator"
require "tmpdir"

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

  # A link to a trashed page or post renders as plain text, like a dead link
  # (trash spec §5.2) -- both on the public site and in preview, where links
  # to drafts otherwise do resolve. The block is written with
  # `update_columns` because a *new* link to a trashed target is refused on
  # save (it's outside every read scope); this is the link that already
  # existed when its target was trashed.
  test "an internal link to a trashed page or post renders as plain text, publicly and in preview" do
    # Spelled with kept targets and repointed afterwards: the Markdown
    # importer itself already drops a link to a trashed target.
    body = rich_doc("See [the kept page](cs:page/#{@kept_page.id}), " \
      "[the gone page](cs:page/#{@kept_page.id}) and [the gone post](cs:post/#{@kept_post.id}).")
    targets = { "the gone page" => @gone_page.id, "the gone post" => @gone_post.id }
    body["content"].sole["content"].each do |node|
      next unless (id = targets[node["text"]])

      node["marks"].find { |mark| mark["type"] == "internalLink" }["attrs"]["id"] = id
    end
    block = @kept_page.content_blocks.create!(block_type: :rich_text, position: 0)
    block.update_columns(body: { "en" => body })

    get "/kept-page"
    assert_response :ok
    assert_select ".content-block--rich-text a[href='/kept-page']", text: "the kept page"
    assert_select ".content-block--rich-text", text: /the gone page/
    assert_select ".content-block--rich-text", text: /the gone post/
    assert_select ".content-block--rich-text a", text: /the gone/, count: 0

    sign_in_as users(:one)
    get "/preview/kept-page"
    assert_response :ok
    assert_select ".content-block--rich-text a[href='/preview/kept-page']", text: "the kept page"
    assert_select ".content-block--rich-text", text: /the gone page/
    assert_select ".content-block--rich-text", text: /the gone post/
    assert_select ".content-block--rich-text a", text: /the gone/, count: 0
  end

  # Generated the way the deploy runs it (see test/lib/sitemap_test.rb).
  test "the sitemap lists neither a trashed page nor a trashed post" do
    paths = Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"), public_path: dir, compress: false, verbose: false)
      Nokogiri::XML(File.read(File.join(dir, "sitemap.xml"))).tap(&:remove_namespaces!).css("url > loc").map { |loc| URI.parse(loc.text).path }
    end

    assert_includes paths, "/kept-page"
    assert_includes paths, "/blog/kept-post"
    assert_empty paths.grep(/gone/)
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

  test "the ⌘K jump palette lists kept pages, posts and images and never trashed ones" do
    # Distinct titles so a match proves which record answered: the setup's
    # kept and trashed records are titled "Kept ..."/"Gone ..." (images
    # after their filename, shared by both).
    @kept_asset.update!(title: "Kept image")
    @gone_asset.update!(title: "Gone image")
    sign_in_as users(:one)

    get "/cs-studio/jump", params: { q: "kept" }
    assert_response :success
    assert_select "a[href=?]", "/cs-studio/pages/#{@kept_page.id}"
    assert_select "a[href=?]", "/cs-studio/posts/#{@kept_post.id}"
    assert_select "a[href=?]", "/cs-studio/media/#{@kept_asset.id}"

    get "/cs-studio/jump", params: { q: "gone" }
    assert_response :success
    assert_select "a[href=?]", "/cs-studio/pages/#{@gone_page.id}", count: 0
    assert_select "a[href=?]", "/cs-studio/posts/#{@gone_post.id}", count: 0
    assert_select "a[href=?]", "/cs-studio/media/#{@gone_asset.id}", count: 0
    assert_select "p", text: /No results for/
  end

  # The tree's own counts (handoff §10 B24/C34): a trashed page is no row, no
  # child count and no translation marker; the starter offer counts kept pages.
  test "the page tree's child count and translation markers ignore a trashed page" do
    sign_in_as users(:one)
    with_locales(%w[en de], default: "en") do
      # Both children are outdated in German (translated, then the original
      # edited), so each carries "↻1" while kept: only the trashed one's must
      # not show. The marker count is 1 with the trash honoured and 2 (and
      # the child count 2) if the index counted a trashed page.
      kept_child, gone_child = [ "Kept child", "Gone child" ].map do |title|
        child = create_page(title: title, parent: @kept_page, translations: { "en" => { title: title }, "de" => { title: "#{title} de" } })
        assert Pages::Save.call(child, translations: { "en" => { title: "#{title}!" } }).ok?
        child
      end
      get "/cs-studio/pages/#{@kept_page.id}"
      assert_select "turbo-frame#tree [data-translation-marker=outdated]", text: "↻1", count: 2
      gone_child.update!(trashed_at: Time.current)

      get "/cs-studio/pages/#{@kept_page.id}"

      assert_select "turbo-frame#tree li[data-page-id='#{@kept_page.id}'] > div [data-child-count]", text: "1"
      assert_select "turbo-frame#tree li[data-page-id='#{gone_child.id}']", count: 0
      assert_select "turbo-frame#tree [data-translation-marker=outdated]", text: "↻1", count: 1
    end
  end

  test "the page tree, posts list, link targets and mind graph hide trashed pages and posts" do
    sign_in_as users(:one)

    get "/cs-studio/pages/#{@kept_page.id}"
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

  test "tag suggestions never count a trashed post, and a tag only trashed posts use still appears with 0" do
    sign_in_as users(:one)
    create_post(title: "Kept tagged", tags: [ "shared-tag" ])
    create_post(title: "Gone tagged", tags: [ "shared-tag", "only-trashed" ]).update_columns(trashed_at: Time.current)

    get "/cs-studio/tags/suggest", params: { q: "shared" }
    assert_equal [ "1 post" ], response.parsed_body.map { |row| row["hint"] }

    get "/cs-studio/tags/suggest", params: { q: "only-" }
    assert_equal [ "0 posts" ], response.parsed_body.map { |row| row["hint"] }
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

  # --- Render cache ------------------------------------------------------------

  # Trash spec §5.3/§9: every move, restore and purge must change
  # `PublicSite.content_version`, or a cached rich-text render could keep
  # linking to (or showing) what just left the site, or keep leaving out
  # what just came back. Called directly, with `Current` reset between
  # steps, since `current_content_version` is memoised per request.
  test "moving, restoring and purging each change the content version" do
    post = create_post(title: "Versioned")
    versions = [ fresh_content_version ]

    travel(1.second) { as_owner { assert Trash::Move.call(post).ok? } }
    versions << fresh_content_version
    travel(2.seconds) { as_owner { assert Trash::Restore.call(post.reload).ok? } }
    versions << fresh_content_version
    travel(3.seconds) { as_owner { assert Trash::Move.call(post.reload).ok? } }
    versions << fresh_content_version
    travel(4.seconds) { as_owner { assert Trash::Purge.call(post.reload).ok? } }
    versions << fresh_content_version

    assert_equal versions.size, versions.uniq.size, "each step should change the version: #{versions.inspect}"
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

  def fresh_content_version
    Current.reset
    PublicSite.content_version
  end

  def text_of(result) = result["content"].map { |item| item["text"] }.join("\n")
end
