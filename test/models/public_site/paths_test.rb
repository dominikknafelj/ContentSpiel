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

  def listing(parent, title, content_type, tag: nil, published_at: 1.day.ago)
    Page.create!(parent: parent, title: title, published_at: published_at).tap do |page|
      add_listing_block(page, content_type, tag: tag)
    end
  end

  def add_listing_block(page, content_type, tag: nil)
    settings = { "content_type" => content_type }.compact
    settings["tag"] = tag if tag
    page.content_blocks.create!(block_type: :post_list, position: page.content_blocks.count, settings: settings)
  end

  def resolve(path, scope: :published) = PublicSite::Resolver.new(scope: scope).call(locale: "en", path: path)

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

  # -- canonical listing page choice (spec §5.3) ------------------------------

  # The seeded site's shape: the homepage carries an unfiltered "latest posts"
  # teaser, and /blog is the real blog listing. Tree order alone would hand
  # every post to the root (it always comes first) -- specificity is what
  # keeps posts under the section that actually names their type.
  test "a homepage teaser does not take a post's URL from a typed listing" do
    add_listing_block(@root, nil)
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal blog, PublicSite::Paths.canonical_page(post)
    assert_equal "/blog/hello", current(post)
    assert_equal :redirect, resolve("/hello").status
  end

  test "a draft listing earlier in the tree does not take a published listing's posts" do
    listing(@root, "Drafts", "blog", published_at: nil)
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal blog, PublicSite::Paths.canonical_page(post)
    assert_equal "/blog/hello", current(post)
    assert_equal :found, resolve("/blog/hello").status
  end

  test "a listing under a draft section counts as unpublished" do
    section = Page.create!(parent: @root, title: "Section", published_at: nil)
    listing(section, "Inner", "blog")
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal blog, PublicSite::Paths.canonical_page(post)
  end

  test "with only a draft listing, the post lives under it for preview but is not public" do
    drafts = listing(@root, "Drafts", "blog", published_at: nil)
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal drafts, PublicSite::Paths.canonical_page(post)
    assert_equal "/drafts/hello", current(post)
    assert_equal :found, resolve("/drafts/hello", scope: :preview).status
    assert_equal :not_found, resolve("/drafts/hello").status
  end

  test "a content-type listing beats an unfiltered one at equal publication" do
    listing(@root, "Everything", nil)
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal blog, PublicSite::Paths.canonical_page(post)
  end

  test "a tag-matching listing beats one with no tag filter" do
    listing(@root, "Blog", "blog")
    rails = listing(@root, "Rails", "blog", tag: "rails")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    post.tags << Tag.create!(name: "rails")

    assert_equal rails, PublicSite::Paths.canonical_page(post)
    assert_equal "/rails/hello", current(post)
  end

  test "publishing a draft listing that comes first in the tree takes the posts over" do
    drafts = listing(@root, "Drafts", "blog", published_at: nil)
    listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post)

    drafts.update!(published_at: 1.minute.ago)

    assert_equal "/drafts/hello", current(post)
  end

  # Moves and reorders reach the post through the moved page's own
  # subtree-scoped resync (`Page#resync_listed_posts`): the listing page that
  # moved is the only one whose rank relative to the others changed.
  test "moving a listing page ahead of another listing makes it canonical" do
    listing(@root, "Blog", "blog")
    archive = listing(@root, "Archive", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post)

    archive.update!(position: 0)

    assert_equal "/archive/hello", current(post)
  end

  # -- clashes from another record's write (spec §5.4) ------------------------

  # The post's own save reports a clash as a validation error, but a sync
  # triggered by *another* record's write (here: a block destroy moving the
  # post onto a path a page already holds) has nobody to report it to -- it
  # must not raise, and the post goes without a URL in that locale instead.
  test "a sync that would clash with another record leaves the post without a URL" do
    block = add_listing_block(@root, "blog")
    blog = listing(@root, "Blog", "blog")
    team = Page.create!(parent: blog, title: "Team", published_at: 1.day.ago)
    post = Post.create!(content_type: :blog, title: "Team", published_at: 1.day.ago)
    assert_equal "/team", current(post)

    assert_nothing_raised { block.destroy! }

    assert_nil current(post)
    assert_equal team, PublicPath.current.find_by(locale: "en", path: "/blog/team").record

    Locales.enabled.each { |locale| Mobility.with_locale(locale) { team.update!(slug: "crew") } }
    PublicSite::Paths.sync(post)
    assert_equal "/blog/team", current(post)
  end

  test "a clash is logged with the record, locale and path" do
    block = add_listing_block(@root, "blog")
    blog = listing(@root, "Blog", "blog")
    Page.create!(parent: blog, title: "Team", published_at: 1.day.ago)
    post = Post.create!(content_type: :blog, title: "Team", published_at: 1.day.ago)

    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    begin
      block.destroy!
    ensure
      Rails.logger = original
    end

    assert_match(%r{Post##{post.id}.*en.*/blog/team}, log.string)
  end

  test "a tag change that would clash does not raise after commit" do
    listing(@root, "Blog", "blog")
    rails = listing(@root, "Rails", "blog", tag: "rails")
    Page.create!(parent: rails, title: "Team", published_at: 1.day.ago)
    post = Post.create!(content_type: :blog, title: "Team", published_at: 1.day.ago)
    assert_equal "/blog/team", current(post)

    assert_nothing_raised { post.tags << Tag.create!(name: "rails") }

    assert_nil current(post)
  end

  test "editing a listing block's content type in place re-points posts of the old type" do
    block = add_listing_block(@root, "blog")
    listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/hello", current(post)

    block.update!(settings: { "content_type" => "now_update" })

    assert_equal "/blog/hello", current(post)
  end

  test "destroying a listing block takes its posts' URLs away, or moves them" do
    only = listing(@root, "News", "now_update").content_blocks.first
    blog_block = add_listing_block(@root, "blog")
    listing(@root, "Blog", "blog")
    update = Post.create!(content_type: :now_update, title: "Now", published_at: 1.day.ago)
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    only.destroy!
    blog_block.destroy!

    assert_nil current(update)
    assert_equal "/blog/hello", current(post)
  end

  test "moving a listing page into an earlier branch makes it canonical" do
    section = Page.create!(parent: @root, title: "Section", published_at: 1.day.ago)
    listing(@root, "Blog", "blog")
    archive = listing(@root, "Archive", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post)

    archive.update!(parent: section)

    assert_equal "/section/archive/hello", current(post)
  end
end
