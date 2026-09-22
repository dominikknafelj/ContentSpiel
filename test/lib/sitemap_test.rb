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

  private

  def sitemap_paths
    sitemap_locs.map { |loc| URI.parse(loc).path }
  end

  # Generates the real config/sitemap.rb into a temp directory instead of
  # public/, uncompressed (the default is gzip) so the XML can be read back,
  # and silently so the test output stays clean.
  def sitemap_locs
    @sitemap_locs ||= Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(
        config_file: Rails.root.join("config/sitemap.rb"),
        public_path: dir,
        compress: false,
        verbose: false
      )

      xml = Nokogiri::XML(File.read(File.join(dir, "sitemap.xml")))
      xml.remove_namespaces!.css("url > loc").map(&:text)
    end
  end
end
