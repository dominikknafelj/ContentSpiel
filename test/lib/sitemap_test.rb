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

    assert_includes paths, "/en/"
    assert_includes paths, "/de/"
    assert_includes paths, "/es/"
    assert_includes paths, "/en/about"
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

    assert_includes paths, "/en/"
    %w[/en/draft /de/draft /es/draft /en/scheduled /de/scheduled /es/scheduled].each do |path|
      assert_not_includes paths, path
    end
  end

  # The site has no unprefixed public URLs: "/" only redirects to the default
  # locale, and sitemap_generator adds it by default unless told not to.
  test "the unprefixed root is not listed" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    assert_not_includes sitemap_paths, "/"
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
