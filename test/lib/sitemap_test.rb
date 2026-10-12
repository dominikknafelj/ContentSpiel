require "test_helper"
require "sitemap_generator"
require "tmpdir"

# config/sitemap.rb is a script, not a class: sitemap_generator evaluates it
# inside a `SitemapGenerator::Interpreter` (gem 7.1.1). So it is tested the way
# the deploy runs it -- `rake sitemap:create` is literally
# `SitemapGenerator::Interpreter.run` (lib/sitemap_generator/tasks.rb) -- with
# only the output redirected, and the generated XML read back.
class SitemapTest < ActiveSupport::TestCase
  test "every published page is listed once per locale, at that locale's path" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root,
      published_at: Time.current)
    Mobility.with_locale(:de) { about.update!(slug: "ueber-uns") }

    paths = sitemap_paths

    # The site's default locale (en) gets no prefix at all -- the root page's
    # own entry comes back as "" rather than "/": sitemap_generator joins an
    # unprefixed "/" straight onto the bare host with no trailing slash, and
    # URI#path on a URL with no path component at all reads back as "".
    assert_includes paths, ""
    assert_includes paths, "/de/"
    assert_includes paths, "/es/"
    assert_includes paths, "/about"
    assert_includes paths, "/de/ueber-uns"
    # Untranslated in Spanish, so its path there falls back to the English
    # slug -- exactly the URL the site serves it at under /es.
    assert_includes paths, "/es/about"
  end

  # A draft has a path the moment it is saved and the public site 404s it, so
  # listing it in the sitemap would be inviting search engines to crawl a URL
  # that does not resolve.
  test "unpublished pages are not listed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "Draft", slug: "draft", parent: root, published_at: nil)
    Page.create!(page_type: :standard, title: "Scheduled", slug: "scheduled", parent: root,
      published_at: 1.day.from_now)

    paths = sitemap_paths

    assert_includes paths, ""
    %w[/draft /de/draft /es/draft /scheduled /de/scheduled /es/scheduled].each do |path|
      assert_not_includes paths, path
    end
  end

  # `include_root: false` stops sitemap_generator adding "/" a second time on
  # top of the root Page's own entry above (which is exactly what "/" means).
  test "the root page's entry is not duplicated by sitemap_generator's own include_root" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    assert_equal 1, sitemap_paths.count("")
  end

  test "every listed URL is absolute" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    assert sitemap_locs.all? { |loc| loc.start_with?("http://", "https://") },
      "expected absolute URLs, got #{sitemap_locs.inspect}"
  end

  # A `Post` has no page-tree node of its own (spec §4) -- its entry is its
  # canonical listing page's path plus its slug, exactly the URL
  # `PagesController#show`'s permalink fallback resolves back to a post.
  test "a published post is listed at its canonical url" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title: "Hello", published_at: Time.current)

    assert_includes sitemap_paths, "/blog/hello"
  end

  # A draft post's `public_paths` row exists the moment it is saved (spec
  # §5.4) -- it is `live?`, not "has a row", that decides whether the
  # sitemap lists it, same as a page.
  test "an unpublished post is not listed even though it has a canonical page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title: "Draft Post")

    assert_not_includes sitemap_paths, "/blog/draft-post"
  end

  # A post's canonical page must itself be published (spec §6.5's "the full
  # ancestor rule arrives in Task 6" note names exactly this as the interim
  # rule) -- otherwise the sitemap would send a crawler to a permalink
  # PagesController 404s, since a draft listing page serves no permalinks.
  test "a published post under an unpublished listing page is not listed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title: "Hello", published_at: Time.current)

    assert_not_includes sitemap_paths, "/blog/hello"
  end

  # `Urls.alternates` is what feeds both this and the layout's own hreflang
  # tags (spec §6.5) -- one XML entry per language, each pointing at every
  # other language's URL for the same page.
  test "a page entry carries an hreflang alternate link for every enabled language" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)

    doc = sitemap_document
    about_url = doc.css("url").find { |url| url.at_css("loc").text.end_with?("/about") }
    alternates = about_url.css("link[rel=alternate]").to_h { |link| [ link["hreflang"], link["href"] ] }

    assert_equal "https://www.example.com/about", alternates["en"]
    assert_equal "https://www.example.com/de/about", alternates["de"]
    assert_equal "https://www.example.com/es/about", alternates["es"]
  end

  # The date of a record with a copy is the copy's, not the row's: an autosave
  # of live content is not a change a crawler can see.
  test "a live page's date is when its copy came into force, or when it went live if that was later, and an autosave does not move it" do
    page = create_page(title: "Dated")
    first = lastmod_of("/dated")

    travel 1.day do
      assert Pages::Save.call(page, translations: { "en" => { title: "Dated, edited" } }).ok?
      @sitemap_document = nil
      assert_equal first, lastmod_of("/dated")

      publish_changes(page)
      @sitemap_document = nil
      assert_operator lastmod_of("/dated"), :>, first
    end
  end

  test "a live page with no copy is dated by its row, as before" do
    page = create_page(title: "Bare")
    follow_rows!
    page.update_columns(updated_at: Time.utc(2026, 1, 2, 3, 4, 5)) # version: none (a test dates a row)

    assert_equal Time.utc(2026, 1, 2, 3, 4, 5), Time.iso8601(lastmod_of("/bare"))
  end

  private

  def lastmod_of(path)
    entry = sitemap_document.css("url").find { |url| URI.parse(url.at_css("loc").text).path == path }
    entry.at_css("lastmod").text
  end

  def sitemap_paths
    sitemap_locs.map { |loc| URI.parse(loc).path }
  end

  def sitemap_locs
    sitemap_document.css("url > loc").map(&:text)
  end

  # Generates the real config/sitemap.rb into a temp directory instead of
  # public/, uncompressed (the default is gzip) so the XML can be read back,
  # and silently so the test output stays clean.
  def sitemap_document
    @sitemap_document ||= Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(
        config_file: Rails.root.join("config/sitemap.rb"),
        public_path: dir,
        compress: false,
        verbose: false
      )

      Nokogiri::XML(File.read(File.join(dir, "sitemap.xml"))).tap(&:remove_namespaces!)
    end
  end
end
