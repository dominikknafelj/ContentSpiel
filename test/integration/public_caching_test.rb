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
  end

  test "unknown paths render the theme 404" do
    get "/nope"
    assert_response :not_found
    assert_select "h1", /not found/i
  end
end
