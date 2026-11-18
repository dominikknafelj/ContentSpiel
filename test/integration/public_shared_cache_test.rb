require "test_helper"

# PUBLIC_SHARED_CACHE_SECONDS (`PublicSite::SharedCache`): above 0, a
# published public page that is rendered or confirmed with a 304 tells a
# shared cache it may keep it that long, and nothing else the site answers
# does. Unset, the header is what it always was
# (`test/integration/public_caching_test.rb` pins it too).
class PublicSharedCacheTest < ActionDispatch::IntegrationTest
  SHARED = "max-age=0, public, s-maxage=60, stale-while-revalidate=86400".freeze
  PLAIN = "max-age=0, public, must-revalidate".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  def shared(seconds = 60, &block) = PublicSite::SharedCache.with(seconds, &block)

  def assert_not_shared(what)
    assert_no_match(/s-maxage|stale-while-revalidate/, response.headers["Cache-Control"].to_s, what)
  end

  test "unset, or 0, a public page says what it always said" do
    assert_equal 0, PublicSite::SharedCache.seconds, "the test environment sets no shared cache"

    [ -> { get "/" }, -> { shared(0) { get "/" } } ].each do |request|
      request.call

      assert_response :success
      assert_equal PLAIN, response.headers["Cache-Control"]
      assert response.headers["ETag"].present?
    end
  end

  test "set, a page says a shared cache may keep it, keeps its ETag, sets no cookie, and its 304 says the same" do
    shared do
      get "/"
      assert_response :success
      assert_equal SHARED, response.headers["Cache-Control"]
      etag = response.headers["ETag"]
      assert etag.present?
      assert_nil response.headers["Set-Cookie"]

      get "/", headers: { "If-None-Match" => etag }
      assert_response :not_modified
      assert_equal SHARED, response.headers["Cache-Control"]
      assert_equal etag, response.headers["ETag"]
      assert_nil response.headers["Set-Cookie"]
    end

    shared(300) { get "/" }
    assert_equal "max-age=0, public, s-maxage=300, stale-while-revalidate=86400", response.headers["Cache-Control"]
  end

  test "a post's permalink takes it, and a signed-in editor's request sets no cookie either" do
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = create_post(title: "Hello")
    sign_in_as(users(:one))
    get "/cs-studio"
    before = cookies.to_hash

    shared do
      get PublicSite::Urls.new.path_for(post.reload, "en")
      assert_response :success
      assert_includes response.body, "Hello"
      assert_equal SHARED, response.headers["Cache-Control"]
      assert_nil response.headers["Set-Cookie"]
      assert_equal before, cookies.to_hash
    end
  end

  test "a search's answer, a 404 and a redirect never take it" do
    create_page(title: "About")
    shared do
      get "/?q=albatross"
      assert_response :success
      assert_equal "private, no-store", response.headers["Cache-Control"], "a search"

      get "/nowhere"
      assert_response :not_found
      assert_not_shared "a 404"
      assert_not_equal "max-age=0, public, must-revalidate", response.headers["Cache-Control"], "a 404 is not public"

      get "/en/about"
      assert_response :found
      assert_not_shared "the default language's redirect"
    end
  end

  test "an old address's redirect never takes it" do
    page = create_page(title: "About")
    assert Pages::Save.call(page, translations: { "en" => { slug: "about-us" } }).ok?
    publish_changes(page)

    shared { get "/about" }
    assert_response :moved_permanently
    assert_not_shared "the old address's redirect"
  end

  test "an old browser's 406 never takes it" do
    shared { get "/", headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36" } }
    assert_response :not_acceptable
    assert_not_shared "a 406"
  end

  test "an error page never takes it" do
    config = Rails.application.env_config
    before = config["action_dispatch.show_exceptions"]
    config["action_dispatch.show_exceptions"] = :all
    shared do
      with_singleton_override(PublicSite::Resolver, :new, ->(**) { raise "boom" }) { get "/" }
    end
    assert_response :internal_server_error
    assert_not_shared "a 500"
  ensure
    config["action_dispatch.show_exceptions"] = before
  end

  test "a page drawn with a late Code block is kept by no shared cache" do
    shared do
      with_singleton_override(CodeHighlight, :late?, -> { true }) { get "/" }
    end
    assert_response :success
    assert_equal PLAIN, response.headers["Cache-Control"]
  end

  test "the preview, CS Studio, sign-in, setup, the suggestions and a form's send never take it" do
    shared do
      get "/cs-studio/sign-in"
      assert_not_shared "sign-in"

      get "/cs-studio/setup"
      assert_not_shared "setup"

      post "/search/suggestions", params: { suggest: "home", language: "en" }.to_json,
        headers: { "Content-Type" => "application/json", "Sec-Fetch-Site" => "same-origin" }
      assert_equal "private, no-store", response.headers["Cache-Control"], "a suggestion"

      post "/forms/#{forms(:contact).id}", params: { answers: {}, locale: "en" }
      assert_includes response.headers["Cache-Control"], "no-store", "a form's send"
      assert_not_shared "a form's send"

      sign_in_as(users(:one))
      get "/cs-studio/preview"
      assert_response :success
      assert_equal "private, no-store", response.headers["Cache-Control"], "the preview"

      get "/cs-studio"
      assert_response :success
      assert_not_shared "CS Studio"
    end
  end

  test "the site's icons keep their own hour, a shared cache's seconds or not" do
    shared { get "/favicon.ico" }
    assert_response :success
    assert_equal ContentSpiel::PublicFileCache::SHORT, response.headers["Cache-Control"]
  end
end
