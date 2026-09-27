require "test_helper"

class PublicSite::UrlsTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    @urls = PublicSite::Urls.new(host: "https://example.org")
  end

  test "default locale is unprefixed, others carry their code" do
    assert_equal "/about", @urls.path_for(@about, "en")
    assert_equal "/de/about", @urls.path_for(@about, "de")
    assert_equal "/de/", @urls.path_for(@root, "de")
    assert_equal "https://example.org/de/about", @urls.url_for(@about, "de")
  end

  test "preview urls stay under /preview" do
    urls = PublicSite::Urls.new(preview: true)
    assert_equal "/preview/about", urls.path_for(@about, "en")
    assert_equal "/preview/de/about", urls.path_for(@about, "de")
  end

  test "alternates list every enabled language with a path" do
    assert_equal %w[en de es], @urls.alternates(@about).keys
  end

  test "switching the default language flips the prefixes" do
    site_settings(:default).update!(default_locale: "de")
    urls = PublicSite::Urls.new
    assert_equal "/about", urls.path_for(@about, "de")
    assert_equal "/en/about", urls.path_for(@about, "en")
    assert urls.redundant_prefix?("de")
  end

  test "a record without a path has no url" do
    post = Post.create!(content_type: :now_update, title: "Unlisted")
    assert_nil @urls.path_for(post, "en")
  end
end
