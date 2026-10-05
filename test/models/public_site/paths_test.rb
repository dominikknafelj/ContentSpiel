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

  # An address one record of a sync is leaving is free for another record of
  # the same sync: who holds what is judged on where the rows end up, not on
  # the order the records happen to be taken in.
  test "two posts that trade addresses in one sync both get theirs" do
    blogs = listing(@root, "First", "blog")
    updates = listing(@root, "Second", "now_update")
    post = Post.create!(content_type: :blog, title: "Same", published_at: 1.day.ago)
    update = Post.create!(content_type: :now_update, title: "Same", published_at: 1.day.ago)
    assert_equal [ "/first/same", "/second/same" ], [ current(post), current(update) ]

    # Around the callbacks, so that one sync sees both changes at once.
    blogs.content_blocks.first.update_columns(settings: { "content_type" => "now_update" })
    updates.content_blocks.first.update_columns(settings: { "content_type" => "blog" })
    PublicSite::Paths.sync_posts(nil)

    assert_equal [ "/second/same", "/first/same" ], [ current(post), current(update) ]
    assert_empty PublicPath.redirects.where(locale: "en", path: %w[/first/same /second/same]), "a redirect can't sit on a live address"
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

  # -- trashed records (trash spec §5.2) ---------------------------------------

  test "saving a trashed page removes its paths and redirects, restoring rebuilds them" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)
    Mobility.with_locale(:en) { about.update!(slug: "about-us") }
    assert PublicPath.redirects.exists?(record: about, locale: "en", path: "/about")

    about.update!(trashed_at: Time.current)

    assert_not PublicPath.exists?(record: about), "current rows and redirects alike are gone"
    assert_nil current(team), "a descendant has no parent path to hang off"

    about.update!(trashed_at: nil)

    assert_equal "/about-us", current(about)
    assert_equal "/about-us/team", current(team)
    assert_equal "/about/team", current(team, "de"), "only :en was renamed"
    assert_not PublicPath.redirects.exists?(record: about), "old redirects aren't resurrected"
  end

  test "a trashed page's post listing no longer gives posts their URL" do
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post)

    blog.update!(trashed_at: Time.current)

    assert_nil PublicSite::Paths.canonical_page(post.reload)
    assert_nil current(post)
  end

  test "a trashed listing page's posts move to the next listing, and back on restore" do
    blog = listing(@root, "Blog", "blog")
    listing(@root, "Archive", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    blog.update!(trashed_at: Time.current)
    assert_equal "/archive/hello", current(post)

    blog.update!(trashed_at: nil)
    assert_equal "/blog/hello", current(post)
  end

  test "rebuild! never gives a trashed page or post a URL" do
    listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    page = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    post.update_columns(trashed_at: Time.current)
    page.update_columns(trashed_at: Time.current)

    PublicSite::Paths.rebuild!

    assert_not PublicPath.exists?(record: post)
    assert_not PublicPath.exists?(record: page)
  end

  test "canonical_pages ranks a listing page that has no closure rows like a page with an empty ancestry, never raising" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = create_post(title: "Hello")
    PageHierarchy.where(descendant_id: blog.id).delete_all

    assert_equal blog, PublicSite::Paths.canonical_page(post)
    assert_equal({ post => blog }, PublicSite::Paths.canonical_pages([ post ]))
  end

  test "canonical_pages answers every post at once" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    listed = create_post(title: "Listed")
    other = Post.new(content_type: "now_update")

    assert_equal({ listed => blog, other => nil }, PublicSite::Paths.canonical_pages([ listed, other ]))
  end

  # -- parity with a full rebuild ----------------------------------------------
  #
  # `Page` and `Post` sync their URLs only when one of the values a URL is
  # built from changed (`HasPublicPaths#url_inputs`). The risk of a condition
  # is the input it forgot: the write then leaves `public_paths` saying
  # something the records no longer do, and nothing notices until a visitor
  # gets a 404. So after every write below the live rows must equal what
  # `PublicSite::Paths.rebuild!` -- which derives every URL from scratch and
  # asks no condition -- would write. One step per input and per write path
  # that feeds a URL; a new one belongs in this list.
  #
  # Current rows only: a redirect is history (the address a record used to
  # have), which a rebuild from the records alone cannot know and deletes.
  def live_rows
    PublicPath.current.order(:record_type, :record_id, :locale, :path).pluck(:record_type, :record_id, :locale, :path)
  end

  def assert_parity(step)
    stored = live_rows
    rebuilt = nil
    PublicPath.transaction(requires_new: true) do
      PublicSite::Paths.rebuild!
      rebuilt = live_rows
      raise ActiveRecord::Rollback
    end

    assert_equal rebuilt, stored, "after #{step}: public_paths is not what a full rebuild writes"
    assert_empty PublicPath.current.group(:locale, :path).having("COUNT(*) > 1").count, "after #{step}: two live rows share an address"
    assert_empty PublicPath.current.group(:record_type, :record_id, :locale).having("COUNT(*) > 1").count,
      "after #{step}: a record has two live addresses in one language"
  end

  def ok!(result)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def service_page(title, parent: @root, published: true)
    ok! Pages::Save.call(attributes: { parent: parent, published: published }, translations: { "en" => { title: title } })
  end

  def service_listing(page, **settings)
    ok! ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings.compact })
  end

  def service_post(title, content_type: "blog", tags: [])
    ok! Posts::Save.call(attributes: { content_type: content_type, published: true, tag_names: tags }, translations: { "en" => { title: title } })
  end

  test "every write path leaves public_paths equal to a full rebuild" do
    with_locales(%w[en de es], default: "en")

    as_owner do
      # Fifteen pages besides the homepage, four levels deep.
      about = service_page("About")
      team = service_page("Team", parent: about)
      alice = service_page("Alice", parent: team)
      service_page("Bob", parent: team)
      history = service_page("History", parent: about)
      section = service_page("Section")
      sub = service_page("Sub", parent: section)
      service_page("Leaf", parent: sub)
      service_page("Other leaf", parent: sub)
      writing = service_page("Writing")
      blog = service_page("Blog", parent: writing)
      journal = service_page("Journal")
      archive = service_page("Archive")
      news = service_page("News")
      drafts = service_page("Drafts", published: false)
      assert_parity "building the tree"

      teaser = service_listing(@root)
      service_listing(blog, content_type: "blog")
      service_listing(journal, content_type: "blog")
      archive_block = service_listing(archive, content_type: "blog", tag: "old")
      news_block = service_listing(news, content_type: "now_update")
      service_listing(drafts, content_type: "resume_entry")
      assert_parity "adding listing blocks"

      hello = service_post("Hello")
      second = service_post("Second")
      old = service_post("Old", tags: %w[old])
      update = service_post("Now", content_type: "now_update")
      job = service_post("Job", content_type: "resume_entry")
      assert_equal "/writing/blog/hello", current(hello)
      assert_equal "/archive/old", current(old)
      assert_equal "/news/now", current(update)
      assert_equal "/job", current(job), "the live homepage teaser beats a typed listing on a draft page"
      assert_parity "creating posts"

      # -- a page's own inputs -------------------------------------------------
      ok! Pages::Save.call(about, translations: { "de" => { slug: "ueber-uns" } })
      assert_equal "/ueber-uns/team/alice", current(alice, "de")
      assert_equal "/about/team/alice", current(alice, "en")
      assert PublicPath.redirects.exists?(record: alice, locale: "de", path: "/about/team/alice"), "the old address became a redirect"
      assert_parity "renaming a slug in one language"

      ok! Pages::Save.call(about.reload, translations: { "en" => { title: "About us", subtitle: "Who we are" } })
      about.reload.touch
      assert_parity "a title-only save and a bare touch"

      ok! Pages::Move.call(section.reload, parent: about.reload, position: 0)
      assert_equal "/about/section/sub", current(sub)
      assert_parity "moving a branch under another parent"

      # First under Team, first under History: the parent is all that changes.
      assert_equal 0, alice.reload.position
      ok! Pages::Move.call(alice, parent: history.reload, position: 0)
      assert_equal "/about/history/alice", current(alice)
      assert_parity "moving a page to the same rank under another parent"
      ok! Pages::Move.call(alice.reload, parent: team.reload, position: 0)
      assert_parity "moving it back"

      ok! Pages::Move.call(journal.reload, parent: @root.reload, position: 0)
      assert_equal "/journal/hello", current(hello), "the earlier of two equal listings is canonical"
      assert_parity "reordering siblings"

      ok! Pages::Move.call(journal.reload, parent: @root.reload, position: 99)
      assert_equal "/writing/blog/hello", current(hello)
      assert_parity "reordering siblings back"

      ok! Pages::Save.call(writing.reload, attributes: { published: false })
      assert_equal "/journal/hello", current(hello), "a listing under a draft parent loses to a live one"
      assert_parity "unpublishing a parent"

      ok! Pages::Save.call(writing.reload, attributes: { published: true })
      assert_equal "/writing/blog/hello", current(hello)
      assert_parity "republishing a parent"

      ok! Pages::Save.call(drafts.reload, attributes: { published: true })
      assert_equal "/drafts/job", current(job), "once live, the typed listing is the more specific one"
      assert_parity "publishing a draft listing page"

      # -- trash ---------------------------------------------------------------
      ok! Trash::Move.call(about.reload)
      assert_nil current(alice)
      assert_not PublicPath.exists?(record: alice), "a trashed branch member keeps no redirect either"
      assert_parity "trashing a branch"

      ok! Trash::Restore.call(about.reload)
      assert_equal "/about/team/alice", current(alice)
      assert_parity "restoring a branch"

      ok! Trash::Move.call(writing.reload)
      assert_equal "/journal/hello", current(hello), "a trashed listing page gives its posts to the next one"
      assert_parity "trashing a listing page's parent"

      ok! Trash::Restore.call(writing.reload)
      assert_equal "/writing/blog/hello", current(hello)
      assert_parity "restoring a listing page's parent"

      ok! Trash::Move.call(team.reload)
      ok! Trash::Move.call(about.reload)
      ok! Trash::Restore.call(team.reload, parent: news.reload)
      assert_equal "/news/team/alice", current(alice)
      assert_parity "restoring a page under a new parent"
      ok! Trash::Restore.call(about.reload)
      assert_parity "restoring the rest of the branch"

      ok! Trash::Move.call(hello.reload)
      assert_nil current(hello)
      assert_parity "trashing a post"

      ok! Trash::Restore.call(hello.reload)
      assert_equal "/writing/blog/hello", current(hello)
      assert_parity "restoring a post"

      # -- a post's own inputs -------------------------------------------------
      ok! Posts::Save.call(second.reload, translations: { "es" => { slug: "segundo" } })
      assert_equal "/writing/blog/segundo", current(second, "es")
      assert_parity "renaming a post's slug in one language"

      ok! Posts::Save.call(second.reload, translations: { "en" => { excerpt: "An excerpt" } })
      second.reload.touch
      assert_parity "an excerpt-only post save and a bare touch"

      ok! Posts::Save.call(second.reload, attributes: { tag_names: %w[old] })
      assert_equal "/archive/second", current(second), "a tag-filtered listing is more specific"
      assert_parity "adding a tag that changes a post's listing page"

      ok! Posts::Save.call(second.reload, attributes: { tag_names: [] })
      assert_equal "/writing/blog/second", current(second)
      assert_parity "removing that tag"

      ok! Posts::Save.call(second.reload, attributes: { content_type: "now_update" })
      assert_equal "/news/second", current(second)
      assert_parity "changing a post's content type"

      ok! Posts::Save.call(second.reload, attributes: { published: false })
      assert_parity "unpublishing a post"

      # -- listing blocks ------------------------------------------------------
      ok! ContentBlocks::Save.call(news_block.reload, attributes: { settings: { content_type: "blog" } })
      assert_equal "/second", current(second), "only the homepage teaser lists it"
      assert_parity "changing a listing block's content type"

      ok! ContentBlocks::Save.call(news_block.reload, attributes: { settings: { content_type: "now_update" } })
      assert_parity "changing it back"

      ok! ContentBlocks::Destroy.call(teaser.reload)
      assert_parity "removing a listing block"

      body = ok! ContentBlocks::Save.call(ContentBlock.new(owner: news.reload), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: rich_doc("Text") } })
      ok! ContentBlocks::Save.call(body, translations: { "en" => { body: rich_doc("Changed") } })
      assert_parity "writing a text block"

      # -- tags ----------------------------------------------------------------
      ok! Tags::Rename.call(Tag.find_by!(name: "old"), name: "vintage")
      assert_equal "/writing/blog/old", current(old), "the block still names the old tag, so the post falls out of it"
      assert_parity "renaming a tag"

      ok! ContentBlocks::Save.call(archive_block.reload, attributes: { settings: { content_type: "blog", tag: "vintage" } })
      assert_equal "/archive/old", current(old)
      assert_parity "changing a listing block's tag"

      ok! Posts::Save.call(hello.reload, attributes: { tag_names: %w[classic] })
      ok! Tags::Merge.call(Tag.find_by!(name: "classic"), into: Tag.find_by!(name: "vintage"))
      assert_equal "/archive/hello", current(hello)
      assert_parity "merging a tag into a listed one"

      ok! Tags::Destroy.call(Tag.find_by!(name: "vintage"))
      assert_equal "/writing/blog/hello", current(hello)
      assert_parity "deleting a tag"

      # -- languages -----------------------------------------------------------
      ok! Locales::Disable.call("es")
      assert_parity "turning a language off"

      ok! Locales::Enable.call("es")
      assert_equal "/about", current(about, "es")
      assert_parity "turning a language on"

      ok! Locales::MakeDefault.call("de")
      assert_parity "changing the default language"

      ok! Locales::Configure.call([ { "code" => "es" }, { "code" => "de" }, { "code" => "en", "fallbacks" => [ "de" ] } ])
      assert_parity "reordering languages and changing a fallback"

      # -- for good ------------------------------------------------------------
      ok! Trash::Move.call(blog.reload)
      ok! Trash::Purge.call(blog.reload)
      assert_equal "/journal/hello", current(hello)
      assert_parity "deleting a listing page for good"

      ok! Trash::Move.call(hello.reload)
      ok! Trash::Purge.call(hello.reload)
      assert_parity "deleting a post for good"
    end
  end

  # -- cost ---------------------------------------------------------------------
  #
  # Two sizes rather than a ceiling: a per-page cost hides comfortably under
  # any number generous enough for the small tree.
  def branch_with(descendants)
    top = Page.create!(parent: @root, title: "Branch #{descendants}", published_at: 1.day.ago)
    parent = top
    descendants.times do |index|
      parent = top if (index % 5).zero?
      parent = Page.create!(parent: parent, title: "Page #{descendants} #{index}", published_at: 1.day.ago)
    end
    top
  end

  test "a slug change costs the same number of statements with 20 descendants as with 200" do
    small = branch_with(20)
    large = branch_with(200)

    few = capture_sql { Mobility.with_locale(:en) { small.update!(slug: "small-moved") } }
    many = capture_sql { Mobility.with_locale(:en) { large.update!(slug: "large-moved") } }

    assert_equal few.size, many.size, "the statements grew with the subtree:\n#{many.first(40).map { |sql| sql.first(160) }.join("\n")}"
    deepest = Page.where(parent_id: large.id).order(:id).first.descendants.order(:id).last
    assert_equal "/large-moved", current(large)
    assert current(deepest).start_with?("/large-moved/"), "every descendant moved with it"
    assert_equal 201, PublicPath.redirects.where(locale: "en").where("path LIKE '/branch-200%'").count, "and left a redirect behind"
  end

  test "syncing every post costs the same number of statements for 5 posts as for 50" do
    listing(@root, "Blog", "blog")
    5.times { |index| Post.create!(content_type: :blog, title: "Post #{index}", published_at: 1.day.ago) }
    PublicPath.where(record_type: "Post").delete_all
    few = capture_sql { PublicSite::Paths.sync_posts("blog") }
    45.times { |index| Post.create!(content_type: :blog, title: "More #{index}", published_at: 1.day.ago) }
    PublicPath.where(record_type: "Post").delete_all
    many = capture_sql { PublicSite::Paths.sync_posts("blog") }

    assert_equal 50 * Locales.enabled.size, PublicPath.current.where(record_type: "Post").count
    assert_equal few.size, many.size, "the statements grew with the posts:\n#{many.map { |sql| sql.first(160) }.join("\n")}"
  end
end
