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
  # refresh (`PublicSite::Paths.refresh`, its subtree's posts): the listing page that
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
    PublicSite::Paths.refresh(posts: [ post ])
    assert_equal "/blog/team", current(post)
  end

  # A page that yields has no address, so nothing hangs off it: its
  # descendants must not be written under the address it did not get, which
  # is another record's URL space ("no URL yet, never borrow one").
  test "a page that yields inside a subtree sync leaves its descendants without an address there" do
    team = Page.create!(parent: @root, title: "Team", published_at: 1.day.ago)
    alice = Page.create!(parent: team, title: "Alice", published_at: 1.day.ago)
    old = Page.create!(parent: @root, title: "Team old", published_at: 1.day.ago)
    bob = Page.create!(parent: old, title: "Bob", published_at: 1.day.ago)
    Mobility.with_locale(:de) { old.update!(slug: "mannschaft") }
    Mobility.with_locale(:de) { old.update!(slug: "team-alt") }
    assert PublicPath.redirects.exists?(record: old, locale: "de", path: "/mannschaft")

    # Around the callbacks and the validation, as `Locales::Enable` fills slugs.
    old.update_columns(slug: old.read_attribute(:slug).merge("de" => "team"))
    PublicSite::Paths.sync_subtree(@root.reload)

    assert_equal "/team", current(team, "de")
    assert_equal "/team/alice", current(alice, "de"), "the holder's own child keeps its unchanged row: it is not taken for a clash"
    assert_nil current(old, "de"), "the page that didn't ask yields"
    assert_nil current(bob, "de"), "and its child is not put under the other page's address"
    assert_not PublicPath.exists?(locale: "de", path: "/team/bob")
    assert PublicPath.redirects.exists?(record: old, locale: "de", path: "/mannschaft"), "the yielder keeps its redirects"
    assert_equal "/team-old/bob", current(bob, "en"), "other languages are untouched"
  end

  test "turning on a language in which two siblings get the same slug gives the second one's branch no address" do
    site_settings(:default).update!(locales: [ { "code" => "en" } ], default_locale: "en")
    PublicSite::Paths.rebuild!
    first = Page.create!(parent: @root, title: "Team", published_at: 1.day.ago)
    second = Page.create!(parent: @root, title: "Team", slug: "team-old", published_at: 1.day.ago)
    bob = Page.create!(parent: second, title: "Bob", published_at: 1.day.ago)
    assert_equal [ "/team", "/team-old/bob" ], [ current(first), current(bob) ]

    as_owner { assert Locales::Enable.call("de").ok? }

    assert_equal "team", second.reload.slug_de, "both were filled from the same title"
    assert_equal "/team", current(first, "de")
    assert_nil current(second, "de")
    assert_nil current(bob, "de")
    assert_empty PublicPath.where(locale: "de").where("path LIKE '/team/%'")
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
    PublicSite::Paths.refresh(posts: Post.all)

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
    publish_changes(blog)
    post = create_post(title: "Hello")
    PageHierarchy.where(descendant_id: blog.id).delete_all

    assert_equal blog, PublicSite::Paths.canonical_page(post)
    assert_equal({ post => blog }, PublicSite::Paths.canonical_pages([ post ]))
  end

  test "canonical_pages answers every post at once" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    publish_changes(blog)
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
  #
  # `rebuild!` is a partial oracle: it asks no condition, but it works the
  # paths out and inserts the rows with the same code the incremental sync
  # uses, so a mistake in that shared code shows on both sides and cancels
  # out. What anchors the derivation itself are the literal addresses
  # asserted along the way (and the tests above that pin single rules).
  def live_rows
    PublicPath.current.order(:record_type, :record_id, :locale, :path).pluck(:record_type, :record_id, :locale, :path, :listed_on_id)
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
      # The four live pages were published before their list blocks were
      # added, so their copies list nothing yet (the homepage of this file is
      # written around the services and has no copy: its rows are read, as
      # are the draft's).
      [ blog, journal, archive, news ].each { |page| publish_changes(page) }
      assert_parity "publishing the list blocks added to live pages"

      hello = service_post("Hello")
      second = service_post("Second")
      old = service_post("Old", tags: %w[old])
      update = service_post("Now", content_type: "now_update")
      job = service_post("Job", content_type: "resume_entry")
      assert_equal "/writing/blog/hello", current(hello)
      assert_equal "/writing/blog/old", current(old), "Archive's copy was taken when no tag was called old: it recorded none, and lists nothing"
      assert_equal "/news/now", current(update)
      assert_equal "/job", current(job), "the live homepage teaser beats a typed listing on a draft page"
      assert_parity "creating posts"
      publish_changes(archive)
      assert_equal "/archive/old", current(old)
      assert_parity "publishing again a page whose list named a tag nobody had"

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
      moved_from = PublicPath.find_by(locale: "en", path: "/section/sub")
      assert_equal [ false, sub ], [ moved_from&.current, moved_from&.record ], "the address the branch left redirects to where it went"
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

      ok! Pages::Save.call(journal.reload, attributes: { published_at: 1.week.from_now })
      assert_equal "scheduled", journal.reload.status
      assert_parity "scheduling a listing page"
      ok! Pages::Save.call(journal.reload, attributes: { published: true })
      assert_parity "publishing it now"

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

      ok! Trash::Move.call(history.reload)
      service_page("History", parent: about.reload)
      ok! Trash::Restore.call(history.reload)
      assert_equal "/about/history-2", current(history), "its slug was taken in the meantime"
      assert_parity "restoring a page whose slug was taken meanwhile"

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
      assert_equal "/writing/blog/second", current(second), "a live post's tag moves nothing until the post is published"
      assert_parity "adding a tag to a live post's rows"
      publish_changes(second)
      assert_equal "/archive/second", current(second), "a tag-filtered listing is more specific"
      assert_parity "adding a tag that changes a post's listing page"

      ok! Posts::Save.call(second.reload, attributes: { tag_names: [] })
      assert_parity "removing that tag from the rows"
      publish_changes(second)
      assert_equal "/writing/blog/second", current(second)
      assert_parity "removing that tag"

      ok! Posts::Save.call(second.reload, attributes: { content_type: "now_update" })
      assert_equal "/news/second", current(second)
      assert_parity "changing a post's content type"

      ok! Posts::Save.call(second.reload, attributes: { published: false })
      assert_parity "unpublishing a post"

      # -- listing blocks ------------------------------------------------------
      ok! ContentBlocks::Save.call(news_block.reload, attributes: { settings: { content_type: "blog" } })
      assert_equal "/news/second", current(second), "a live page's list block moves nothing until the page is published"
      assert_parity "changing a live page's listing block in its rows"
      publish_changes(news)
      assert_equal "/second", current(second), "only the homepage teaser lists it"
      assert_parity "changing a listing block's content type"

      ok! ContentBlocks::Save.call(news_block.reload, attributes: { settings: { content_type: "now_update" } })
      publish_changes(news)
      assert_equal "/news/second", current(second)
      assert_parity "changing it back"

      # A page unpublished, its list block changed, and published again: its
      # own sync runs before the new copy is taken and reads the older copy,
      # which is in force again from the moment the page has a time, and the
      # copy's own refresh corrects it (`Publishing::Version.take!`).
      ok! Pages::Save.call(archive.reload, attributes: { published: false })
      assert_equal "/writing/blog/old", current(old), "a draft listing loses to a live one"
      assert_parity "unpublishing a page whose copy lists posts"
      ok! ContentBlocks::Save.call(archive_block.reload, attributes: { settings: { content_type: "now_update", tag: "" } })
      assert_parity "changing a draft page's listing block, read from its rows at once"
      ok! Pages::Save.call(archive.reload, attributes: { published: true })
      assert_equal "/archive/now", current(update), "the new copy lists the other type, and Archive comes before News"
      assert_equal "/writing/blog/old", current(old), "and no longer the type the older copy listed"
      assert_parity "publishing again a page whose listing block changed while it was unpublished"
      ok! ContentBlocks::Save.call(archive_block.reload, attributes: { settings: { content_type: "blog", tag: "old" } })
      publish_changes(archive)
      assert_equal [ "/news/now", "/archive/old" ], [ current(update), current(old) ]
      assert_parity "putting that listing block back"

      # A live page whose rows list another type than its copy does. The
      # posts it holds are the copy's while it is live, the rows' while it is
      # a draft and nobody's while it is in the trash, so each of those
      # writes has to look at the posts of the type only the COPY names.
      ok! ContentBlocks::Save.call(news_block.reload, attributes: { settings: { content_type: "resume_entry" } })
      assert_equal "/news/now", current(update)
      assert_parity "changing a live page's listing block to a type its copy does not list"
      ok! Trash::Move.call(news.reload)
      assert_equal "/now", current(update), "only the homepage teaser lists it now"
      assert_parity "trashing a page whose copy lists a type its rows do not"
      ok! Trash::Restore.call(news.reload)
      assert_equal "/news/now", current(update)
      assert_parity "restoring it"
      ok! Pages::Save.call(news.reload, attributes: { published: false })
      assert_equal "/now", current(update), "a draft lists what its rows list"
      assert_parity "unpublishing a page whose copy lists a type its rows do not"
      ok! Pages::Save.call(news.reload, attributes: { published: true })
      assert_equal "/now", current(update), "the copy taken now is the rows"
      assert_parity "publishing it again"
      ok! ContentBlocks::Save.call(news_block.reload, attributes: { settings: { content_type: "now_update" } })
      publish_changes(news)
      assert_equal "/news/now", current(update)
      assert_parity "putting its listing block back"

      ok! ContentBlocks::Destroy.call(teaser.reload)
      assert_parity "removing a listing block"

      body = ok! ContentBlocks::Save.call(ContentBlock.new(owner: news.reload), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: rich_doc("Text") } })
      ok! ContentBlocks::Save.call(body, translations: { "en" => { body: rich_doc("Changed") } })
      assert_parity "writing a text block"

      ok! ContentBlocks::Reorder.call(news.reload, news.content_blocks.pluck(:id).reverse)
      assert_parity "reordering a page's blocks"

      # A copy of a listing block lists the same posts from the same page, in
      # a column as at the top level: no URL moves, and the rows agree.
      copied = ok! ContentBlocks::Duplicate.call(news_block.reload)
      assert_parity "duplicating a listing block"

      band = ok! ContentBlocks::Save.call(ContentBlock.new(owner: news.reload), attributes: { block_type: "section" })
      ok! ContentBlocks::Reorder.call(news.reload, [ copied.id ], section: band.id, column: 1, moved_from: { copied.id => { section_id: nil, column: nil } })
      assert_parity "moving a listing block into a section"

      ok! ContentBlocks::Duplicate.call(band.reload)
      assert_parity "duplicating a section that holds a listing block"

      publish_changes(news)
      assert_parity "publishing a page whose listing blocks were copied and moved into a section"

      # -- tags ----------------------------------------------------------------
      ok! Tags::Rename.call(Tag.find_by!(name: "old"), name: "vintage")
      assert_equal "/archive/old", current(old), "the page's copy and the post's both hold the tag's id: a rename moves nothing"
      assert_parity "renaming a tag both copies hold"
      # Published again, the page's copy names a tag nobody has.
      publish_changes(archive)
      assert_equal "/writing/blog/old", current(old), "the block still names the old tag, so the post falls out of it"
      assert_parity "renaming a tag"

      ok! ContentBlocks::Save.call(archive_block.reload, attributes: { settings: { content_type: "blog", tag: "vintage" } })
      publish_changes(archive)
      assert_equal "/archive/old", current(old)
      assert_parity "changing a listing block's tag"

      ok! Posts::Save.call(hello.reload, attributes: { tag_names: %w[classic] })
      ok! Tags::Merge.call(Tag.find_by!(name: "classic"), into: Tag.find_by!(name: "vintage"))
      assert_equal "/writing/blog/hello", current(hello), "the post's copy carries neither tag yet"
      assert_parity "merging a tag a live post carries in its rows only"
      publish_changes(hello)
      assert_equal "/archive/hello", current(hello)
      assert_parity "merging a tag into a listed one"

      ok! Tags::Destroy.call(Tag.find_by!(name: "vintage"))
      assert_equal "/archive/hello", current(hello), "both copies still hold the deleted tag's id, and the public list still shows the post"
      assert_parity "deleting a tag both copies hold"
      publish_changes(hello)
      assert_equal "/writing/blog/hello", current(hello)
      assert_parity "deleting a tag"

      # A tag only a page's COPY still filters by: the copy recorded the
      # tag's id when it was taken (the tag exists by then, or the copy
      # would list nothing: see Archive at the top), while the page's rows
      # have moved on to another name. A rename away from that name, and one
      # back onto it, change no id and so move nothing.
      Tag.create!(name: "press")
      press = service_page("Press", published: false)
      press_block = service_listing(press, content_type: "blog", tag: "press")
      ok! Pages::Save.call(press, attributes: { published: true })
      wire = service_post("Wire", tags: %w[press])
      assert_equal "/press/wire", current(wire)
      ok! ContentBlocks::Save.call(press_block.reload, attributes: { settings: { content_type: "blog", tag: "other" } })
      assert_parity "pointing a live page's listing block at another tag, in its rows"
      ok! Tags::Rename.call(Tag.find_by!(name: "press"), name: "media")
      assert_equal "/press/wire", current(wire), "the copy holds the tag's id, whatever the tag is called"
      assert_parity "renaming a tag away from a name only a page's copy filters by"
      ok! Tags::Rename.call(Tag.find_by!(name: "media"), name: "press")
      assert_equal "/press/wire", current(wire)
      assert_parity "renaming a tag onto a name only a page's copy filters by"

      # A merge is immediate in the copies too: the id they hold is replaced.
      ok! Tags::Merge.call(Tag.find_by!(name: "press"), into: Tag.create!(name: "newsroom"))
      assert_equal "/press/wire", current(wire), "the list and the address are what they were"
      assert_parity "merging a tag the copies hold"
      publish_changes(wire)
      assert_equal "/press/wire", current(wire)
      assert_parity "publishing a post after a merge"
      publish_changes(press)
      assert_equal "/writing/blog/wire", current(wire), "the page's rows filter by another tag"
      assert_parity "publishing the page whose rows had moved on"

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

      # A scheduled change in force by the clock and not settled (nothing
      # sweeps here), then the next publish of the same page: its refresh
      # settles the due copy first, and the posts the page hosted follow.
      # Last in this test: the clock is moved, and a copy taken under it
      # would be a pending one once it is put back.
      ok! ContentBlocks::Save.call(press_block.reload, attributes: { settings: { content_type: "blog", tag: "newsroom" } })
      publish_changes(press)
      assert_equal "/press/wire", current(wire)
      ok! ContentBlocks::Destroy.call(press_block.reload)
      publish_changes(press, at: 1.hour.from_now)
      # And a post whose scheduled tags will put it on an address a page
      # takes before their time: the sweep cannot refuse, the post yields,
      # and the table is still what a rebuild writes. Set up here and swept
      # below, after the publish above was looked at, because both need the
      # same moved clock and a sweep before that publish would do its work.
      Tag.create!(name: "desk")
      desk = service_page("Desk", published: false)
      service_listing(desk, content_type: "blog", tag: "desk")
      ok! Pages::Save.call(desk, attributes: { published: true })
      late = service_post("Late")
      assert_equal "/journal/late", current(late)
      ok! Posts::Save.call(late.reload, attributes: { tag_names: %w[desk] })
      publish_changes(late, at: 1.hour.from_now)
      service_page("Late", parent: desk)
      assert_parity "a page taking the address a post's scheduled change will want"
      travel_to 2.hours.from_now do
        assert_equal "/press/wire", current(wire), "time passing writes nothing"
        publish_changes(press)
        assert_equal "/journal/wire", current(wire)
        assert_parity "publishing a page whose scheduled change was in force and unswept"

        PublicSite::Paths.refresh
        assert_nil current(late), "it yields to the page that holds /desk/late"
        assert_parity "the sweep of a post's scheduled change onto a taken address"
      end
    end
  end

  # A listing block in a section's column is a listing block of its page
  # (sections spec §7): created into the column, carried along by a fold and
  # removed with its section, it gives and takes a post's address exactly as
  # a top-level one does.
  test "a listing block in a section's column gives a post its URL, through a fold and until the section is deleted" do
    as_owner do
      blog = service_page("Blog")
      section = ok! ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "section", settings: { "layout" => "three" } })
      post = service_post("Hello")
      assert_nil current(post)

      listing = ok! ContentBlocks::Save.call(ContentBlock.new(owner: blog),
        attributes: { block_type: "post_list", settings: { "content_type" => "blog" }, section_id: section.id, section_column: 3 })
      publish_changes(blog)
      assert_equal "/blog/hello", current(post)
      assert_parity "creating a listing block in a column"

      ok! ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one" } })
      assert_equal [ section.id, 1 ], listing.reload.then { |block| [ block.section_id, block.section_column ] }
      publish_changes(blog)
      assert_equal "/blog/hello", current(post)
      assert_parity "folding the section's columns"

      ok! ContentBlocks::Destroy.call(section.reload)
      assert_not ContentBlock.exists?(listing.id)
      publish_changes(blog)
      assert_nil current(post)
      assert_parity "deleting the section with its blocks"
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
    few = capture_sql { PublicSite::Paths.refresh(posts: Post.where(content_type: "blog")) }
    45.times { |index| Post.create!(content_type: :blog, title: "More #{index}", published_at: 1.day.ago) }
    PublicPath.where(record_type: "Post").delete_all
    many = capture_sql { PublicSite::Paths.refresh(posts: Post.where(content_type: "blog")) }

    assert_equal 50 * Locales.enabled.size, PublicPath.current.where(record_type: "Post").count
    assert_equal few.size, many.size, "the statements grew with the posts:\n#{many.map { |sql| sql.first(160) }.join("\n")}"
  end

  # -- going live by the clock -------------------------------------------------
  #
  # A scheduled page becomes live when `published_at` passes, and no row is
  # written at that moment. A page scheduled through the services has a copy,
  # and that copy is DUE from the page's time until some refresh settles it
  # (`Publishing::Version.settle!`): the same event as a copy that comes into
  # force by its own time, with no window to remember.

  # A listing page "Fresh" scheduled an hour from now through the services,
  # ahead of the live "Blog" in the tree, and a post at /blog/hello.
  def scheduled_listing_ahead_of_blog(parent: @root)
    fresh = create_page(title: "Fresh", parent: parent, published: false)
    assert ContentBlocks::Save.call(ContentBlock.new(owner: fresh), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    assert Pages::Save.call(fresh, attributes: { published_at: 1.hour.from_now }).ok?
    listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post), "a scheduled page is not live yet"
    [ fresh, post ]
  end

  def writes_to_public_paths(sql) = sql.grep(/\A\s*(INSERT INTO|UPDATE|DELETE FROM) "public_paths"/i)

  test "posts move to a listing page that went live by the clock when the next refresh settles its copy, once" do
    fresh, post = scheduled_listing_ahead_of_blog
    assert_nil Publishing::Version.of(fresh).sole.settled_at, "a scheduled page's copy is due when the page goes live"
    PublicSite::Paths.refresh
    assert_nil Publishing::Version.of(fresh).sole.settled_at, "and not before"

    travel 2.hours
    assert_equal "/blog/hello", current(post), "time passing writes nothing"

    PublicSite::Paths.refresh

    assert_equal "/fresh/hello", current(post)
    old = PublicPath.find_by(locale: "en", path: "/blog/hello")
    assert_equal [ false, post ], [ old.current, old.record ], "the old address is a redirect"
    assert_parity "a scheduled page going live"

    sql = capture_sql { PublicSite::Paths.refresh }.grep_v(/SAVEPOINT/)
    assert_equal 1, sql.size, "a second run did more than look for due copies:\n#{sql.map { |statement| statement.first(160) }.join("\n")}"
  end

  test "a page that went live long before any refresh is settled all the same" do
    _, post = scheduled_listing_ahead_of_blog

    travel 30.days
    PublicSite::Paths.refresh

    assert_equal "/fresh/hello", current(post)
  end

  test "a scheduled page moved to another time is due at the time it has, and published now it is settled by that save" do
    fresh, post = scheduled_listing_ahead_of_blog
    assert Pages::Save.call(fresh.reload, attributes: { published_at: 3.hours.from_now }).ok?

    travel 2.hours
    PublicSite::Paths.refresh
    assert_equal "/blog/hello", current(post), "its first time has passed, its time has not"

    assert Pages::Save.call(fresh.reload, attributes: { published: true }).ok?
    assert_equal "/fresh/hello", current(post)
    assert Publishing::Version.of(fresh).sole.settled_at
    assert_parity "publishing a scheduled page now"
  end

  test "a trashed page that went live is settled and moves nothing" do
    fresh, post = scheduled_listing_ahead_of_blog
    fresh.update_columns(trashed_at: Time.current)

    travel 2.hours
    PublicSite::Paths.refresh

    assert_equal "/blog/hello", current(post)
    assert_nil current(fresh), "trashed around its callbacks, it loses its own address in the same pass"
    assert Publishing::Version.of(fresh).sole.settled_at
    assert_parity "settling the copy of a trashed page that went live"
  end

  test "a page below one that went live is covered: its listing's posts move too" do
    section = create_page(title: "Section", parent: @root, published: false)
    listing(section, "Fresh", "blog")
    assert Pages::Save.call(section, attributes: { published_at: 1.hour.from_now }).ok?
    listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post), "a listing under a scheduled parent has no live chain"

    travel 2.hours
    PublicSite::Paths.refresh

    assert_equal "/section/fresh/hello", current(post)
  end

  # The limit, on purpose: nothing looks through a window any more. A record
  # that is scheduled around the services has no copy to be due; the
  # application has no such writer (`test/lib/publishing_guards_test.rb`:
  # "published_at is assigned only in the two save services").
  test "a page scheduled around the services has no copy, so its going live is acted on by the next refresh that reaches its posts, not by the clock's" do
    listing(@root, "Fresh", "blog", published_at: 1.hour.from_now)
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    travel 2.hours
    PublicSite::Paths.refresh
    assert_equal "/blog/hello", current(post)

    PublicSite::Paths.refresh(pages: [ blog ])
    assert_equal "/fresh/hello", current(post)
  end

  # -- addresses follow the published copy (drafts spec §5, Task 4) -------------
  #
  # A list block is part of its PAGE's copy and a post's tags of the POST's:
  # for a published or scheduled record that has a copy, an address is derived
  # from the copy, so it moves when the record's changes are published and
  # not when they are typed. The pages and posts here are built through the
  # services, which take the copies; the tests above build theirs around them
  # (`Page.create!`), have no copy, and follow the rows as before.

  test "changing a live page's list block to another type moves no address until the page is published" do
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    address = PublicSite::Paths.current_path(post, "en")
    assert address

    assert ContentBlocks::Save.call(block, attributes: { settings: { "content_type" => "resume_entry" } }).ok?
    assert_equal address, PublicSite::Paths.current_path(post, "en")
    assert ContentBlocks::Destroy.call(block.reload).ok?
    assert_equal address, PublicSite::Paths.current_path(post, "en")

    publish_changes(page)
    assert_nil PublicSite::Paths.current_path(post, "en")
  end

  test "a list block added to a live page gives no post an address until the page is published" do
    page = create_page(title: "Blog")
    post = create_post(title: "Hello")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert_nil PublicSite::Paths.current_path(post, "en")

    publish_changes(page)

    assert PublicSite::Paths.current_path(post, "en")
  end

  test "a tag changed in a live post's rows moves it to another listing only when the post is published" do
    ruby = create_page(title: "Ruby", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: ruby), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "ruby" } })
    rails = create_page(title: "Rails", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: rails), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "rails" } })
    post = create_post(title: "Hello", tags: %w[ruby], published: false)
    Tag.create!(name: "rails")
    [ ruby, rails ].each { |page| assert Pages::Save.call(page, attributes: { published: true }).ok? }
    assert Posts::Save.call(post, attributes: { published: true }).ok?
    assert_equal ruby, PublicSite::Paths.canonical_page(post)

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }).ok?
    assert_equal ruby, PublicSite::Paths.canonical_page(post.reload)

    publish_changes(post)
    assert_equal rails, PublicSite::Paths.canonical_page(post.reload)
    assert_includes PublicSite::Paths.current_path(post, "en"), "rails"
  end

  test "a draft page and a draft post are listed by their rows, as before" do
    page = create_page(title: "Draft listing", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    post = create_post(title: "Draft post", published: false)

    assert_equal page, PublicSite::Paths.canonical_page(post)
  end

  test "canonical_pages answers rows, never a page rebuilt from a copy" do
    page = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")

    answer = PublicSite::Paths.canonical_page(post)

    assert_equal page, answer
    assert_not answer.readonly?
    assert_nil answer.published_version
  end

  test "a scheduled change to a list block moves the addresses when the sweep runs after its time, and not before" do
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(block).ok?
    publish_changes(page, at: 2.days.from_now)

    PublicSite::Paths.refresh
    assert PublicSite::Paths.current_path(post, "en"), "moved before its time"

    travel_to 3.days.from_now do
      PublicSite::Paths.refresh
      assert_nil PublicSite::Paths.current_path(post, "en")
      assert_parity "the sweep of a page's copy that came into force"
    end
  end

  # A live page written around the services has no copy and lists what its
  # rows list. Its first copy, taken with a time, is in force when that time
  # comes, and from then on the rows count for nothing: the posts the rows
  # listed in the meantime are looked at too.
  test "a page with no copy whose scheduled change comes into force takes back the posts of its copy and gives up the ones only its rows listed" do
    page = listing(@root, "Blog", "blog", published_at: 3.days.ago)
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 3.days.ago)
    job = Post.create!(content_type: :resume_entry, title: "Job", published_at: 3.days.ago)
    publish_changes(page, at: 1.hour.from_now)
    page.content_blocks.sole.update!(settings: { "content_type" => "resume_entry" })
    assert_equal [ nil, "/blog/job" ], [ current(post), current(job) ], "until the copy's time the rows decide"

    travel_to 2.hours.from_now do
      PublicSite::Paths.refresh

      assert_equal [ "/blog/hello", nil ], [ current(post), current(job) ]
      assert_parity "the sweep of the first copy of a page that had none"
    end
  end

  test "a scheduled change to a post's tags moves its address when a refresh runs after its time, once, and a copy in force at once is never due" do
    Tag.create!(name: "ruby")
    ruby = create_page(title: "Ruby", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: ruby), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "ruby" } })
    assert Pages::Save.call(ruby, attributes: { published: true }).ok?
    post = create_post(title: "Hello", tags: %w[ruby])
    assert_equal "/ruby/hello", current(post)

    sql = capture_sql { PublicSite::Paths.refresh }
    assert_empty sql.grep(/"posts"|"public_paths"/), "copies in force from the moment they were taken were looked at:\n#{sql.map { |statement| statement.first(160) }.join("\n")}"

    assert Posts::Save.call(post, attributes: { tag_names: [] }).ok?
    publish_changes(post, at: 2.days.from_now)
    assert_equal "/ruby/hello", current(post), "a copy with a time changes nothing yet"

    travel_to 3.days.from_now do
      PublicSite::Paths.refresh
      assert_nil current(post)
      assert_parity "the sweep of a post's copy that came into force"

      sql = capture_sql { PublicSite::Paths.refresh }
      assert_empty writes_to_public_paths(sql), "a second run wrote:\n#{sql.map { |statement| statement.first(160) }.join("\n")}"
      assert_empty sql.grep(/"posts"/), "a second run looked at the post again"
    end
  end

  # The opposite of what the windowed sweep did: a copy's coming into force
  # is marked, not looked for in a window, so it is never too late for it.
  test "a copy that came into force long before any sweep is settled all the same, and one of a trashed page is settled and gives no address" do
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(block).ok?
    publish_changes(page, at: 1.hour.from_now)

    travel_to 30.days.from_now do
      PublicSite::Paths.refresh
      assert_nil current(post), "a month late is not too late"
      assert_parity "settling a copy whose time came a month ago"
    end

    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    publish_changes(page)
    assert_equal "/blog/hello", current(post)
    assert ContentBlocks::Destroy.call(block).ok?
    publish_changes(page, at: 1.hour.from_now)
    assert Trash::Move.call(page.reload).ok?
    assert_nil current(post)

    travel_to 2.hours.from_now do
      sql = capture_sql { PublicSite::Paths.refresh }
      assert_empty writes_to_public_paths(sql)
      assert Publishing::Version.of(page).where(settled_at: nil).none?
      assert_parity "settling the copy of a page in the trash"
    end
  end

  test "syncing every post against tag-filtered listings, rows and copies, costs the same number of statements for 5 posts as for 50" do
    listing(@root, "By rows", "blog", tag: "rows")
    Tag.create!(name: "copy")
    copied = create_page(title: "By copy", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: copied), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "copy" } })
    assert Pages::Save.call(copied, attributes: { published: true }).ok?
    5.times { |index| create_post(title: "Post #{index}", tags: [ index.even? ? "rows" : "copy" ]) }
    PublicPath.where(record_type: "Post").delete_all
    few = capture_sql { PublicSite::Paths.refresh(posts: Post.where(content_type: "blog")) }
    45.times { |index| create_post(title: "More #{index}", tags: [ index.even? ? "rows" : "copy" ]) }
    PublicPath.where(record_type: "Post").delete_all
    many = capture_sql { PublicSite::Paths.refresh(posts: Post.where(content_type: "blog")) }

    assert_equal 50 * Locales.enabled.size, PublicPath.current.where(record_type: "Post").count
    assert_equal few.size, many.size, "the statements grew with the posts:\n#{many.map { |sql| sql.first(160) }.join("\n")}"
  end

  # Where nothing sweeps (development), or between two runs: a scheduled copy
  # is in force by the clock while the addresses still say what the copy
  # before it listed. The next publish must not take it for swept.
  test "a scheduled change that came into force and was never swept is not skipped by the next publish of the page" do
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(block).ok?
    publish_changes(page, at: 1.hour.from_now)

    travel_to 2.hours.from_now do
      assert_equal "/blog/hello", current(post), "time passing writes nothing"

      publish_changes(page)

      assert_nil current(post)
      assert_parity "publishing a page whose scheduled change was in force and unswept"
    end
  end

  test "two scheduled changes in a row, neither settled, on a page that had no copy before them: the next publish gives up what the rows listed" do
    page = listing(@root, "Blog", "blog", published_at: 3.days.ago)
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 3.days.ago)
    job = Post.create!(content_type: :resume_entry, title: "Job", published_at: 3.days.ago)
    publish_changes(page, at: 1.hour.from_now)
    page.content_blocks.sole.update!(settings: { "content_type" => "resume_entry" })
    assert_equal [ nil, "/blog/job" ], [ current(post), current(job) ], "until the first copy's time the rows decide"

    travel_to 2.hours.from_now do
      ContentBlock.where(owner: page).delete_all # version: none (a test removes a block around its sync, so only the copies speak)
      publish_changes(page, at: 1.hour.from_now)
      assert_equal [ nil, "/blog/job" ], [ current(post), current(job) ], "nothing was swept and nothing announced"
    end
    travel_to 4.hours.from_now do
      publish_changes(page)

      assert_equal [ nil, nil ], [ current(post), current(job) ]
      assert_parity "publishing after two unswept scheduled changes"
    end
  end

  # -- the recorded host (Task 4b) ---------------------------------------------
  #
  # A post's current row says which page gives it its address. That is the
  # "before" every caller used to reconstruct for itself.

  test "a post's current row records the page that lists it, in every language, and a page's row records none" do
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    assert_equal [ blog.id ], PublicPath.current.where(record: post).distinct.pluck(:listed_on_id)
    assert_equal Locales.enabled.size, PublicPath.current.where(record: post).count
    assert_equal [ nil ], PublicPath.current.where(record_type: "Page").distinct.pluck(:listed_on_id)

    journal = listing(@root, "Journal", "blog")
    journal.update!(position: 0)
    assert_equal "/journal/hello", current(post)
    assert_equal [ journal.id ], PublicPath.current.where(record: post).distinct.pluck(:listed_on_id), "the host follows the address"
  end

  # -- the settle marker (Task 4b) ----------------------------------------------
  #
  # A copy taken with a time comes into force with no write. `settled_at` says
  # that its coming into force has been acted on, and EVERY refresh settles
  # the copies that are due before it derives anything, so no derivation acts
  # on a picture the clock has made stale.

  # A live page that lists blog posts, with a change scheduled an hour from
  # now that lists resume entries instead; a blog post at its address.
  def page_with_scheduled_change
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", current(post)
    assert ContentBlocks::Save.call(block, attributes: { settings: { "content_type" => "resume_entry" } }).ok?
    publish_changes(page, at: 1.hour.from_now)
    [ page, post ]
  end

  {
    "renamed" => ->(page) { Pages::Save.call(page, translations: { "en" => { slug: "journal" } }) },
    "moved" => ->(page) { Pages::Move.call(page, parent: Pages::Save.call(attributes: { parent: page.parent, published: true }, translations: { "en" => { title: "Shelf" } }).record, position: 0) },
    "unpublished" => ->(page) { Pages::Save.call(page, attributes: { published: false }) },
    "trashed" => ->(page) { Trash::Move.call(page) }
  }.each do |verb, write|
    test "a page whose scheduled change is in force and not settled, then #{verb}: the posts its older copy listed are looked at" do
      page, post = page_with_scheduled_change

      travel_to 2.hours.from_now do
        assert_equal "/blog/hello", current(post), "time passing writes nothing"
        assert write.call(page.reload).ok?

        assert_nil current(post), "the copy in force lists another type"
        assert_parity "a page #{verb} while its scheduled change was in force and not settled"
        # A draft shows no copy: its change stays due until the page is live again.
        assert_equal verb == "unpublished", Publishing::Version.of(page).where(settled_at: nil).any?
      end
    end
  end

  test "a copy in force at once is settled when it is taken, one with a time when its time has come, and a rebuild settles what is in force" do
    page, post = page_with_scheduled_change
    first, scheduled = Publishing::Version.of(page).order(:number).to_a
    assert first.settled_at
    assert_nil scheduled.settled_at

    PublicSite::Paths.refresh
    assert_nil scheduled.reload.settled_at, "its time has not come"
    assert_equal "/blog/hello", current(post)

    travel_to 2.hours.from_now do
      PublicSite::Paths.rebuild!
      assert scheduled.reload.settled_at
      assert_nil current(post)
    end
  end

  test "a refresh of nothing settles what is due, once: a second run reads the due copies and nothing else" do
    _, post = page_with_scheduled_change

    travel_to 30.days.from_now do
      PublicSite::Paths.refresh
      assert_nil current(post)
      assert_parity "settling a copy whose time came a month ago"

      sql = capture_sql { PublicSite::Paths.refresh }.grep_v(/SAVEPOINT/)
      assert_equal 1, sql.size, sql.join("\n")
      assert_match(/"published_versions"/, sql.sole)
    end
  end

  test "a save of an unrelated record settles a due copy of another: the first refresh after its time, whoever causes it" do
    _, post = page_with_scheduled_change
    other = create_post(title: "Other", content_type: "now_update")

    travel_to 2.hours.from_now do
      assert Posts::Save.call(other, translations: { "en" => { slug: "elsewhere" } }).ok?

      assert_nil current(post)
      assert_parity "an unrelated save after a copy's time"
    end
  end

  # -- a yielder gets its address when the holder leaves ------------------------

  test "a post that had to yield is given its address by the refresh in which the page that held it moves away" do
    blog = listing(@root, "Blog", "blog")
    holder = Page.create!(parent: blog, title: "Hello", published_at: 1.day.ago)
    post = Post.new(content_type: :blog, title: "Hello", slug: "hello", published_at: 1.day.ago)
    post.save!(validate: false)
    assert_nil current(post), "it yields to the page at /blog/hello"

    holder.update!(slug: "hello-page")

    assert_equal "/blog/hello", current(post)
    assert_parity "a holder moving away"
  end

  test "a post no list block of the site can list is not read by a page's refresh" do
    listing(@root, "Blog", "blog")
    Post.create!(content_type: :now_update, title: "Unlisted", published_at: 1.day.ago)
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)

    sql = capture_sql { about.update!(slug: "about-us") }

    assert_empty sql.grep(/FROM "post_tags"/), "the unhoused post was loaded:\n#{sql.map { |statement| statement.first(160) }.join("\n")}"
  end

  # -- a standing clash is nobody's change (fix round 1, I2) --------------------
  #
  # A live record without an address is looked at by every page's refresh
  # (the unhoused), wants its address again each time and yields again. That
  # writes no row, so it moves no version and is not logged a second time.

  def logged
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    yield
    log.string
  ensure
    Rails.logger = original
  end

  test "with a live post that stands without an address, renaming an unrelated draft page leaves the content version where it was and logs nothing; a real change bumps as it does without it" do
    blog = listing(@root, "Blog", "blog")
    first = Page.create!(parent: @root, title: "First", published_at: 1.day.ago)
    second = Page.create!(parent: @root, title: "Second", published_at: 1.day.ago)
    draft = Page.create!(parent: @root, title: "Draft")
    without = PublicSite::Version.current
    first.update!(slug: "first-renamed")
    without = PublicSite::Version.current - without
    assert_operator without, :>, 0

    Page.create!(parent: blog, title: "Hello", published_at: 1.day.ago)
    post = Post.new(content_type: :blog, title: "Hello", slug: "hello", published_at: 1.day.ago)
    post.save!(validate: false)
    assert_nil current(post), "it yields to the page at /blog/hello"

    before = PublicSite::Version.current
    lines = logged { draft.update!(slug: "draft-renamed") }
    assert_equal before, PublicSite::Version.current, "a yield that writes no row moved the version"
    assert_no_match(/gets no .* URL/, lines)
    assert_nil current(post)

    second.update!(slug: "second-renamed")
    assert_equal without, PublicSite::Version.current - before, "a live page's rename bumps as often with a standing yielder as without"
  end

  test "destroying a kept page that owns a list block leaves no row of it behind, and its posts go to the next list" do
    blog = listing(@root, "Blog", "blog")
    listing(@root, "Archive", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    assert_equal "/blog/hello", current(post)

    blog.destroy!

    assert_empty PublicPath.where(record_type: "Page", record_id: blog.id)
    assert_equal "/archive/hello", current(post)
    assert_parity "destroying a kept listing page directly"
    assert Page.new(parent: @root, title: "Blog", published_at: 1.day.ago).valid?, "its address is free again"
  end

  test "a redirect carries no host: the row a post leaves behind says nothing of the page it was listed on" do
    blog = listing(@root, "Blog", "blog")
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    blog.update!(slug: "journal")

    assert_equal "/journal/hello", current(post)
    assert_equal [ nil ], PublicPath.redirects.where(record: post).distinct.pluck(:listed_on_id)
  end
end
