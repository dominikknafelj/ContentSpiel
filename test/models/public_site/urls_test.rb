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

  test "preview urls stay under the admin path's preview" do
    urls = PublicSite::Urls.new(preview: true)
    assert_equal "/cs-studio/preview/about", urls.path_for(@about, "en")
    assert_equal "/cs-studio/preview/de/about", urls.path_for(@about, "de")
  end

  test "alternates list every enabled language with a path" do
    assert_equal %w[en de es], @urls.alternates(@about).keys
  end

  # The head's alternates and the language switcher ask every language of the
  # shown record: one statement for all of them, and none for a record a list
  # has prefetched already (`prefetch` keeps every language it read).
  test "a record's addresses in every language are one statement, and none after a prefetch" do
    assert_equal 1, count_statements { @urls.paths_by_language(@about) }
    assert_equal({ "en" => "/about", "de" => "/de/about", "es" => "/es/about" }, @urls.paths_by_language(@about))
    assert_equal 0, count_statements { @urls.alternates(@about) }

    urls = PublicSite::Urls.new
    assert_equal 1, count_statements { urls.prefetch([ @root, @about ]) }
    assert_equal 0, count_statements { urls.paths_by_language(@root) }
    assert_equal({ "en" => "/", "de" => "/de/", "es" => "/es/" }, urls.paths_by_language(@root))
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
