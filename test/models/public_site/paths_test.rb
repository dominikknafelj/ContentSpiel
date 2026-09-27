require "test_helper"

class PublicSite::PathsTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  def current(record, locale = "en") = PublicSite::Paths.current_path(record, locale)

  test "root is / and children nest in every enabled locale" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)

    assert_equal "/", current(@root)
    assert_equal "/about", current(about)
    assert_equal "/about/team", current(team, "de")
  end

  test "renaming keeps the old path as a redirect and cascades to descendants" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)

    Mobility.with_locale(:en) { about.update!(slug: "company") }

    assert_equal "/company/team", current(team)
    old = PublicPath.find_by(locale: "en", path: "/about/team")
    assert_not old.current
    assert_equal team, old.record
  end

  test "a new page reclaims a path that is only a redirect" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    # Every enabled locale, not just :en: `about` was only ever titled in
    # English, so `LocalizedSlug` filled its other locales' slugs from that
    # same English title at creation -- renaming just :en here would leave
    # "about" still `about`'s *current* slug in :de/:es, and `fresh` below
    # would collide there instead of freely reclaiming "/about" in every
    # locale the way this test means to exercise.
    Locales.enabled.each { |locale| Mobility.with_locale(locale) { about.update!(slug: "company") } }

    fresh = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    assert_equal "/about", current(fresh)
    assert_equal 1, PublicPath.where(locale: "en", path: "/about").count
  end

  test "a sibling cannot take a current path" do
    Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    clash = Page.new(parent: @root, title: "Other", slug: "about")
    assert_not clash.valid?
    assert clash.errors[Mobility.normalize_locale_accessor(:slug, :en)].any?
  end

  test "destroying a page removes its rows" do
    page = Page.create!(parent: @root, title: "Gone", published_at: 1.day.ago)
    page.destroy!
    assert_not PublicPath.exists?(record: page)
  end

  test "changes are announced after commit" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    events = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { events << payload }, "public_paths.changed") do
      Mobility.with_locale(:en) { about.update!(slug: "company") }
    end
    assert_includes events, { record: about, locale: "en", from: "/about", to: "/company" }
  end

  test "rebuild! recreates current rows from slugs" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    PublicPath.delete_all
    PublicSite::Paths.rebuild!
    assert_equal "/about", current(about)
  end

  def listing(parent, title, content_type, tag: nil)
    Page.create!(parent: parent, title: title, published_at: 1.day.ago).tap do |page|
      settings = { "content_type" => content_type }
      settings["tag"] = tag if tag
      page.content_blocks.create!(block_type: :post_list, position: 0, settings: settings)
    end
  end

  test "a post lives under the first listing page in tree order" do
    blog = listing(@root, "Blog", "blog")
    listing(@root, "Archive", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal blog, PublicSite::Paths.canonical_page(post)
    assert_equal "/blog/hello", current(post)
  end

  test "a post nothing lists has no URL" do
    post = Post.create!(content_type: :now_update, title: "Now", published_at: 1.day.ago)
    assert_nil current(post)
  end

  test "adding a listing block gives existing posts a URL" do
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    listing(@root, "Blog", "blog")
    assert_equal "/blog/hello", current(post)
  end

  test "renaming a listing page moves its posts and redirects the old post URL" do
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    Mobility.with_locale(:en) { blog.update!(slug: "journal") }

    assert_equal "/journal/hello", current(post)
    assert_equal post, PublicPath.redirects.find_by(locale: "en", path: "/blog/hello").record
  end

  test "a post cannot take a path a child page already holds" do
    blog = listing(@root, "Blog", "blog")
    Page.create!(parent: blog, title: "Team", published_at: 1.day.ago)
    post = Post.new(content_type: :blog, title: "Team")

    assert_not post.valid?
    assert post.errors[Mobility.normalize_locale_accessor(:slug, :en)].any? { |m| m.include?("/blog/team") }
  end

  test "tag-filtered listings only host matching posts" do
    listing(@root, "Rails", "blog", tag: "rails")
    post = Post.create!(content_type: :blog, title: "Other", published_at: 1.day.ago)
    assert_nil current(post)
  end
end
