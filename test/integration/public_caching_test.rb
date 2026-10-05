require "test_helper"

class PublicCachingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  test "public pages set no cookies and are publicly cacheable" do
    get "/"
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    # `expires_in 0, public: true, must_revalidate: true` plus
    # `stale?(public: true)` together produce this exact directive set --
    # pinned here (rather than a substring match) because "public" alone
    # would also match `no-cache, public`, which is a very different
    # (revalidate-every-time-but-never-store-with-max-age) instruction to a
    # CDN. Rails' own Cache-Control builder (ActionDispatch::Http::Cache)
    # always orders `max-age`, then `public`/`private`, then
    # `must-revalidate`.
    assert_equal "max-age=0, public, must-revalidate", response.headers["Cache-Control"]
    assert response.headers["ETag"].present?
    assert_select "meta[name=csrf-token]", count: 0
  end

  # Final fix wave (Minor 9): the public site runs on its own, untrusted
  # channel -- nil actor on `:public` is denied everything -- rather than
  # the nil channel a console gets.
  test "a public request runs on the untrusted public channel" do
    seen = nil
    original = PublicSite::Resolver.method(:new)
    with_singleton_override(PublicSite::Resolver, :new, ->(**options) { seen = [ Current.channel, Current.actor ]; original.call(**options) }) do
      get "/"
    end

    assert_response :success
    assert_equal [ :public, nil ], seen
    assert_not AccessControl.trusted?(nil, seen.first)
  end

  test "a matching etag gets a 304" do
    get "/"
    get "/", headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
  end

  test "etag changes when a scheduled post goes live" do
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Later", published_at: 1.hour.from_now)
    get "/"
    etag = response.headers["ETag"]

    travel 2.hours do
      get "/", headers: { "If-None-Match" => etag }
      assert_response :success
      assert_includes response.body, "Later"
    end
  end

  test "signed-in visitors get the same anonymous response" do
    sign_in_as(users(:one))
    get "/"
    assert_select "a", text: /Edit this page/, count: 0
    assert_nil response.headers["Set-Cookie"]
  end

  # `maximum(:updated_at)` alone never notices a deletion unless the deleted
  # row happened to be the newest one -- the listing would lose a post while
  # conditional GETs kept answering 304 with the stale page.
  test "etag changes when an older post is deleted" do
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    older = travel_to(2.days.ago) { Post.create!(content_type: :blog, title: "Older", published_at: 2.days.ago) }
    Post.create!(content_type: :blog, title: "Newer", published_at: 1.day.ago)
    get "/"
    etag = response.headers["ETag"]

    older.destroy!

    get "/", headers: { "If-None-Match" => etag }
    assert_response :success
    assert_not_includes response.body, "Older"
  end

  # --- The content version (technical cleanup spec §4.8) -----------------------

  # The point of a version that moves only on published changes: an editor
  # autosaving a draft no longer throws away every visitor's cached page.
  test "a draft's edits leave the etag alone, a live record's change it" do
    live = create_post(title: "Live")
    draft = create_post(title: "Draft", published: false)
    draft_page = create_page(title: "Draft page", published: false)
    get "/"
    etag = response.headers["ETag"]

    assert Posts::Save.call(draft, translations: { "en" => { title: "Draft, edited", body: rich_doc("Text") } }).ok?
    assert Pages::Save.call(draft_page, translations: { "en" => { title: "Draft page, edited" } }).ok?
    assert ContentBlocks::Save.call(ContentBlock.new(owner: draft_page), attributes: { block_type: "rich_text" }).ok?
    get "/", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    assert Posts::Save.call(live, translations: { "en" => { title: "Live, edited" } }).ok?
    get "/", headers: { "If-None-Match" => etag }
    assert_response :success
  end

  test "etag changes when a block of the page is reordered" do
    first = ContentBlocks::Save.call(ContentBlock.new(owner: @root), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("First") } }).record
    second = ContentBlocks::Save.call(ContentBlock.new(owner: @root), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Second") } }).record
    get "/"
    etag = response.headers["ETag"]

    assert ContentBlocks::Reorder.call(@root, [ second.id, first.id ]).ok?

    get "/", headers: { "If-None-Match" => etag }
    assert_response :success
    assert_operator response.body.index("Second"), :<, response.body.index("First")
  end

  # Three queries for the version, once, however many rich-text bodies the
  # page renders (each reads it for its cache key).
  test "a rendered page reads the content version in three queries" do
    3.times do |index|
      assert ContentBlocks::Save.call(ContentBlock.new(owner: @root), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Body #{index}") } }).ok?
    end

    statements = capture_sql { get "/" }

    assert_response :success
    assert_equal 1, statements.grep(/FROM "public_site_versions"/).size, statements.join("\n")
    assert_equal 2, statements.grep(/MAX\("(pages|posts)"."published_at"\)/).size, statements.join("\n")
  end

  # S8: a conditional GET that still matches loads neither the blocks nor
  # their images; only a response that is rendered does.
  test "a 304 loads no blocks, images or variants" do
    asset = create_media_asset
    assert ContentBlocks::Save.call(ContentBlock.new(owner: @root), attributes: { block_type: "image", media_asset_id: asset.id }).ok?
    loads = /FROM "(content_blocks|media_assets|active_storage_\w+)"/

    rendered = capture_sql { get "/" }
    assert_response :success
    assert_not_empty rendered.grep(loads)

    not_modified = capture_sql { get "/", headers: { "If-None-Match" => response.headers["ETag"] } }
    assert_response :not_modified
    assert_empty not_modified.grep(loads), not_modified.join("\n")
  end

  test "unknown paths render the theme 404" do
    get "/nope"
    assert_response :not_found
    assert_select "h1", /not found/i
  end
end
