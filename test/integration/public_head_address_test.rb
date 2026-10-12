require "test_helper"
require "sitemap_generator"
require "tmpdir"

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

  # THE HOMEPAGE'S ADDRESS ENDS IN A SLASH, IN EVERY LANGUAGE, pinned here on
  # purpose (Task 3's review, Minor 3). `Urls#path_for` is the language's
  # prefix plus the page's path, and the homepage's path is "/": so "/" in
  # the default language and "/de/" in German, not the "/de" a visitor may
  # type. Both spellings answer with the page (the router drops a trailing
  # slash before it matches), and the canonical link is what says which of
  # the two is the address: the one the hreflang alternates, `og:url` and
  # the sitemap print too.
  test "the homepage's canonical link, og:url and hreflang are its address with the slash, which answers 200 with the same page" do
    with_site_address(SITE) do
      get "/"

      assert_response :success
      assert_equal "#{SITE}/", canonical
      assert_equal canonical, og_url
      assert_equal canonical, alternates["en"]
      assert_equal canonical, alternates["x-default"]
      assert_equal({ "en" => "#{SITE}/", "de" => "#{SITE}/de/", "es" => "#{SITE}/es/", "x-default" => "#{SITE}/" }, alternates)
      body = response.body

      get canonical
      assert_response :success
      assert_equal "#{SITE}/", canonical
      assert_equal body, response.body
    end
  end

  test "the homepage in another language: the three agree on /de/, and that address answers 200 with the same page, as /de does" do
    Mobility.with_locale(:de) { @root.update!(title: "Startseite") }

    with_site_address(SITE) do
      get "/de"

      assert_response :success
      assert_equal "#{SITE}/de/", canonical
      assert_equal canonical, og_url
      assert_equal canonical, alternates["de"]
      assert_equal "#{SITE}/", alternates["x-default"]
      assert_equal "de", css_select("html").sole["lang"]
      body = response.body
      assert_includes body, "Startseite"

      # The canonical address is not a redirect (to "/de", which would name
      # "/de/" as canonical again): it is the page.
      get canonical
      assert_response :success
      assert_equal "#{SITE}/de/", canonical
      assert_equal body, response.body
    end
  end

  # One `Urls` builds both, so they agree by construction; this is the test
  # that says so. The one difference is the sitemap's own: for the default
  # language's homepage sitemap_generator joins "/" onto the host and prints
  # the bare origin as `<loc>`, which is the same address as the canonical
  # link's (an empty path and "/" are one http address). Every alternate in
  # the entry, that page's own included, has the slash.
  test "the sitemap lists the homepage in each language at the address its canonical link names" do
    with_site_address(SITE) do
      entries = sitemap_entries

      { "/" => "en", "/de" => "de", "/es" => "es" }.each do |path, locale|
        get path
        assert_response :success

        entry = entries.find { |candidate| with_root_path(candidate[:loc]) == canonical }
        assert entry, "the sitemap has no entry for #{canonical}: #{entries.pluck(:loc).inspect}"
        assert_equal canonical, entry[:alternates][locale]
        assert_equal alternates.except("x-default"), entry[:alternates]
      end

      assert_equal [ SITE, "#{SITE}/de/", "#{SITE}/es/" ], entries.pluck(:loc).reject { |loc| loc.match?(/about|uber/) }.sort
    end
  end

  # WITH NO ADDRESS CONFIGURED THE HEAD FOLLOWS THE REQUEST'S HOST, so the
  # ETag does too (Task 3's review, Minor 2): a validator obtained under one
  # host must not confirm, under another, a body whose `og:url`, canonical
  # link and hreflang name the first. With an address configured the head is
  # the same under every host, and so is the ETag.
  test "with no address configured an ETag obtained under one Host is not confirmed under another, and is under the same one" do
    with_site_address(nil) do
      get "/about", headers: { "Host" => "one.example" }
      assert_response :success
      assert_equal "http://one.example/about", canonical
      etag = response.headers["ETag"]

      get "/about", headers: { "Host" => "two.example", "If-None-Match" => etag }
      assert_response :success
      assert_equal "http://two.example/about", canonical
      assert_not_equal etag, response.headers["ETag"]

      get "/about", headers: { "Host" => "one.example", "If-None-Match" => etag }
      assert_response :not_modified
    end
  end

  test "with no address configured the scheme and the port are part of it too" do
    with_site_address(nil) do
      get "/about", headers: { "Host" => "one.example" }
      etag = response.headers["ETag"]

      get "/about", headers: { "Host" => "one.example:8080", "If-None-Match" => etag }
      assert_response :success
      get "/about", headers: { "Host" => "one.example", "X-Forwarded-Proto" => "https", "If-None-Match" => etag }
      assert_response :success
    end
  end

  test "with an address configured the ETag is the same under every Host, and a 304 is given under any" do
    with_site_address(SITE) do
      get "/about", headers: { "Host" => "one.example" }
      assert_response :success
      etag = response.headers["ETag"]

      get "/about", headers: { "Host" => "two.example" }
      assert_equal etag, response.headers["ETag"]

      get "/about", headers: { "Host" => "two.example", "If-None-Match" => etag }
      assert_response :not_modified
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

  # What `config/sitemap.rb` prints, generated the way the deploy does it
  # (`test/lib/sitemap_test.rb`): each entry's `<loc>` and its alternates.
  def sitemap_entries
    Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"), public_path: dir, compress: false, verbose: false)

      Nokogiri::XML(File.read(File.join(dir, "sitemap.xml"))).tap(&:remove_namespaces!).css("url").map do |url|
        { loc: url.at_css("loc").text, alternates: url.css("link[rel=alternate]").to_h { |link| [ link["hreflang"], link["href"] ] } }
      end
    end
  end

  # An address with no path at all is the address of "/".
  def with_root_path(address)
    uri = URI.parse(address)
    uri.path = "/" if uri.path.empty?
    uri.to_s
  end
end
