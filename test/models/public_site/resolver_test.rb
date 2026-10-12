require "test_helper"

class PublicSite::ResolverTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @published = PublicSite::Resolver.new(scope: :published)
    @preview = PublicSite::Resolver.new(scope: :preview)
  end

  test "finds a published page" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    result = @published.call(locale: "en", path: "/about")
    assert_equal :found, result.status
    assert_equal about, result.record
  end

  test "a published child of a draft parent is hidden publicly but previewable" do
    draft = Page.create!(parent: @root, title: "Draft", published_at: nil)
    child = Page.create!(parent: draft, title: "Child", published_at: 1.day.ago)

    assert_equal :not_found, @published.call(locale: "en", path: "/draft/child").status
    assert_equal child, @preview.call(locale: "en", path: "/draft/child").record
  end

  test "old paths redirect permanently to the current one" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    Mobility.with_locale(:en) { about.update!(slug: "company") }

    result = @published.call(locale: "en", path: "/about")
    assert_equal [ :redirect, "/company", 301 ], [ result.status, result.location, result.http_status ]
  end

  test "a post under a second listing page redirects to its canonical url" do
    %w[Blog Archive].each do |title|
      Page.create!(parent: @root, title: title, published_at: 1.day.ago)
        .content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    end
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    result = @published.call(locale: "en", path: "/archive/hello")
    assert_equal [ :redirect, "/blog/hello", 301 ], [ result.status, result.location, result.http_status ]
  end

  test "the listing fallback asks the page's copy: a list block that is only in the rows redirects nobody" do
    blog = Page.create!(parent: @root, title: "Blog", published_at: 1.day.ago)
    blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    archive = Page.create!(parent: @root, title: "Archive", published_at: 1.day.ago)
    Publishing::Version.take!(archive)
    archive.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal :not_found, @published.call(locale: "en", path: "/archive/hello").status
    assert_equal :redirect, @preview.call(locale: "en", path: "/archive/hello").status
  end

  test "drafts are not found publicly and their old paths don't reveal new ones" do
    draft = Page.create!(parent: @root, title: "Secret", published_at: nil)
    Mobility.with_locale(:en) { draft.update!(slug: "renamed") }
    assert_equal :not_found, @published.call(locale: "en", path: "/secret").status
  end

  test "unknown paths are not found" do
    assert_equal :not_found, @published.call(locale: "en", path: "/nope").status
  end
end
