require "test_helper"

# Every absolute address a public page prints in its head -- `og:url`, the
# `hreflang` alternates and the `canonical` link -- is the site's own
# (`PUBLIC_HOST`, read through `PublicSite::Urls.configured_host`), never the
# `Host` a request carried (safe-address spec, "Head tags"). Host
# authorisation is production-only, so in this environment a request under a
# foreign `Host` reaches the app, which is exactly the case these tests need:
# the tags must be right without that filter in front of them.
#
# There are no page fixtures: the pages are made here, as in
# `public_theme_test.rb`.
class PublicHeadAddressTest < ActionDispatch::IntegrationTest
  SITE = "https://docs.example.org".freeze
  FOREIGN = { "Host" => "evil.example", "X-Forwarded-Host" => "evil2.example" }.freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: 1.day.ago)
    @about = Page.create!(parent: @root, page_type: :standard, title_en: "About", title_de: "Über", published_at: 1.day.ago)
  end

  test "under a foreign Host, og:url, every hreflang and the canonical link carry the configured address" do
    with_site_address(SITE) do
      get "/about", headers: FOREIGN

      assert_response :success
      assert_equal "#{SITE}/about", og_url
      assert_equal "#{SITE}/about", canonical
      assert_equal({ "en" => "#{SITE}/about", "de" => "#{SITE}/de/uber", "es" => "#{SITE}/es/about", "x-default" => "#{SITE}/about" }, alternates)
      assert_not_includes response.body, "evil.example"
      assert_not_includes response.body, "evil2.example"
    end
  end

  test "the canonical link is the page's own address in the language shown, without the query" do
    with_site_address(SITE) do
      get "/de/uber"
      assert_equal "#{SITE}/de/uber", canonical
      assert_equal "#{SITE}/de/uber", og_url

      get "/de/uber?utm=1"
      assert_response :success
      assert_equal "#{SITE}/de/uber", canonical
      assert_equal "#{SITE}/de/uber", og_url
      assert_not_includes response.body, "utm"
    end
  end

  test "a post's permalink has a canonical link to itself" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: 1.day.ago)
    blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    with_site_address(SITE) do
      get "/blog/hello", headers: FOREIGN

      assert_response :success
      assert_equal "#{SITE}/blog/hello", canonical
      assert_equal "#{SITE}/blog/hello", og_url
      assert_not_includes response.body, "evil.example"
    end
  end

  test "a page that is not found has no canonical link, and names no foreign host" do
    with_site_address(SITE) do
      get "/nothing-here", headers: FOREIGN

      assert_response :not_found
      assert_select "link[rel=canonical]", count: 0
      assert_not_includes response.body, "evil.example"
      assert_not_includes response.body, "evil2.example"
    end
  end

  test "with no address configured the three follow the request's host" do
    with_site_address(nil) do
      get "/about?utm=1"

      assert_response :success
      assert_equal "http://www.example.com/about", og_url
      assert_equal "http://www.example.com/about", canonical
      assert_equal "http://www.example.com/de/uber", alternates["de"]
    end
  end

  test "a preview keeps the request's origin and its /preview addresses, and has no canonical link" do
    sign_in_as(users(:one))

    with_site_address(SITE) do
      get "/preview/about"

      assert_response :success
      assert_select "link[rel=canonical]", count: 0
      assert_equal "http://www.example.com/preview/about", og_url
      assert_equal "http://www.example.com/preview/de/uber", alternates["de"]
      assert_not_includes response.body, "docs.example.org"
    end
  end

  private

  def og_url = css_select("head meta[property='og:url']").sole["content"]

  def canonical = css_select("head link[rel=canonical]").sole["href"]

  def alternates = css_select("head link[rel=alternate]").to_h { |link| [ link["hreflang"], link["href"] ] }
end
