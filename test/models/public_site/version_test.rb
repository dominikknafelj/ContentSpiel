require "test_helper"
require_relative "../../support/service_calls"
require "rake"

# The public content version (technical cleanup spec §4.8): a stored counter
# that moves when published output can have changed, and only then, plus the
# newest publication time that has passed.
#
# One case per write path, each through its service where it has one, each
# saying whether the counter moved. This is the list `app/models/
# public_site.rb` points at: a new write path that can change a public page
# belongs here with "moves", and one that can't with "stays", so that either
# is a decision somebody made.
#
# The failure that matters is a published change that does NOT move the
# counter: the public then gets the old page, and a 304 for it, until
# something else moves it. A bump too many only costs cache -- which is why
# some cases here pin a bump that changes nothing a visitor sees (a library
# image no page uses, a tag no live post carries).
class PublicSite::VersionTest < ActiveSupport::TestCase
  include ServiceCalls::Builders

  # The homepage, which the helpers create (live) the first time they need a
  # parent: made here so no case counts its creation as its own.
  setup { root_page }

  def counter = PublicSite::Version.current

  def ok(result)
    assert result.ok?, result.errors.to_sentence
    result
  end

  def assert_moves(what = nil)
    before = counter
    yield
    assert_operator counter, :>, before, "#{what || 'this change'} must move the public content version"
  end

  def assert_stays(what = nil)
    before = counter
    yield
    assert_equal before, counter, "#{what || 'this change'} must not move the public content version"
  end

  def block_on(page, **attributes)
    ok(ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes))).record
  end

  def live_and_trashed(record)
    travel(1.second)
    ok(Trash::Move.call(record))
    record.reload
  end

  # --- Drafts: nothing moves ---------------------------------------------------

  test "creating and editing a draft post stays" do
    post = nil
    assert_stays("creating a draft post") { post = create_post(title: "Draft", published: false) }
    assert_stays("a draft post's title") { ok(Posts::Save.call(post, translations: { "en" => { title: "Draft, edited" } })) }
    assert_stays("a draft post's body") { ok(Posts::Save.call(post, translations: { "en" => { body: rich_doc("Text") } })) }
    assert_stays("a draft post's slug") { ok(Posts::Save.call(post, translations: { "en" => { slug: "another-address" } })) }
  end

  test "creating and editing a draft page stays" do
    page = nil
    assert_stays("creating a draft page") { page = create_page(title: "Draft", published: false) }
    assert_stays("a draft page's title") { ok(Pages::Save.call(page, translations: { "en" => { title: "Draft, edited" } })) }
    assert_stays("a draft page's slug") { ok(Pages::Save.call(page, translations: { "en" => { slug: "another-address" } })) }
  end

  test "a draft post that a live listing gives an address still stays" do
    listing = create_page(title: "Blog")
    block_on(listing, block_type: "post_list", settings: { "content_type" => "blog" })

    post = nil
    assert_stays("a draft post getting its address") { post = create_post(title: "Listed draft", published: false) }
    assert PublicPath.current.exists?(record: post), "the draft should have an address for the case to mean anything"
    assert_stays("a draft post's address changing") { ok(Posts::Save.call(post, translations: { "en" => { slug: "moved" } })) }
  end

  test "the blocks of a draft page stay: add, edit, reorder, delete" do
    page = create_page(title: "Draft", published: false)
    first = second = nil

    assert_stays("adding a block to a draft") { first = block_on(page) }
    assert_stays("adding a second block to a draft") { second = block_on(page) }
    assert_stays("editing a draft's block") { ok(ContentBlocks::Save.call(first, translations: { "en" => { body: rich_doc("Edited") } })) }
    assert_stays("reordering a draft's blocks") { ok(ContentBlocks::Reorder.call(page, [ second.id, first.id ])) }
    assert_stays("deleting a draft's block") { ok(ContentBlocks::Destroy.call(second)) }
  end

  test "scheduling a draft, changing the schedule and taking it off stay" do
    post = create_post(title: "Later", published: false)
    page = create_page(title: "Later page", published: false)

    assert_stays("scheduling a draft post") { ok(Posts::Save.call(post, attributes: { published_at: 1.day.from_now })) }
    assert_stays("rescheduling a post") { ok(Posts::Save.call(post, attributes: { published_at: 2.days.from_now })) }
    assert_stays("editing a scheduled post") { ok(Posts::Save.call(post, translations: { "en" => { title: "Later still" } })) }
    assert_stays("unscheduling a post") { ok(Posts::Save.call(post, attributes: { published: false })) }
    assert_stays("scheduling a draft page") { ok(Pages::Save.call(page, attributes: { published_at: 1.day.from_now })) }
  end

  test "a draft's trip to the trash and back stays, and so does its purge" do
    post = create_post(title: "Draft", published: false)
    page = create_page(title: "Draft page", published: false)
    create_page(title: "Draft child", parent: page, published: false)

    assert_stays("trashing a draft post") { ok(Trash::Move.call(post)) }
    assert_stays("restoring a draft post") { ok(Trash::Restore.call(post.reload)) }
    assert_stays("trashing a draft branch") { ok(Trash::Move.call(page)) }
    assert_stays("restoring a draft branch") { ok(Trash::Restore.call(page.reload)) }
    ok(Trash::Move.call(post.reload))
    assert_stays("purging a draft post") { ok(Trash::Purge.call(post.reload)) }
  end

  test "a draft post's tags stay" do
    post = create_post(title: "Draft", published: false, tags: [ "one" ])

    assert_stays("a draft gaining a tag") { ok(Posts::Save.call(post, attributes: { tag_names: %w[one two] })) }
    assert_stays("a draft losing a tag") { ok(Posts::Save.call(post, attributes: { tag_names: %w[two] })) }
  end

  # --- Live pages and posts ----------------------------------------------------

  test "creating and editing a live post moves" do
    post = nil
    assert_moves("creating a live post") { post = create_post(title: "Live") }
    assert_moves("a live post's title") { ok(Posts::Save.call(post, translations: { "en" => { title: "Live, edited" } })) }
    assert_moves("a live post's body") { ok(Posts::Save.call(post, translations: { "en" => { body: rich_doc("Text") } })) }
  end

  test "creating and editing a live page moves" do
    page = nil
    assert_moves("creating a live page") { page = create_page(title: "Live") }
    assert_moves("a live page's title") { ok(Pages::Save.call(page, translations: { "en" => { title: "Live, edited" } })) }
    assert_moves("a live page's slug") { ok(Pages::Save.call(page, translations: { "en" => { slug: "renamed" } })) }
    assert_moves("a live page's hero") { ok(Pages::Save.call(page, attributes: { hero_media_asset_id: create_media_asset.id })) }
  end

  test "publishing and unpublishing move, for a post and for a page" do
    post = create_post(title: "Post", published: false)
    page = create_page(title: "Page", published: false)

    assert_moves("publishing a post") { ok(Posts::Save.call(post, attributes: { published: true })) }
    assert_moves("unpublishing a post") { ok(Posts::Save.call(post, attributes: { published: false })) }
    assert_moves("publishing a page") { ok(Pages::Save.call(page, attributes: { published: true })) }
    assert_moves("unpublishing a page") { ok(Pages::Save.call(page, attributes: { published: false })) }
    assert_moves("publishing with a time in the past") { ok(Posts::Save.call(post, attributes: { published_at: 3.days.ago })) }
  end

  # The "before" side of "live before or after": the save that takes a
  # record off the site leaves it a draft, and must still count.
  test "a save that unpublishes and edits at once moves" do
    post = create_post(title: "Post")

    assert_moves { ok(Posts::Save.call(post, attributes: { published: false }, translations: { "en" => { title: "Withdrawn" } })) }
  end

  test "trashing, restoring and purging a live post each move" do
    post = create_post(title: "Live")

    assert_moves("trashing a live post") { ok(Trash::Move.call(post)) }
    assert_moves("restoring a live post") { ok(Trash::Restore.call(post.reload)) }
    ok(Trash::Move.call(post.reload))
    assert_moves("purging a live post") { ok(Trash::Purge.call(post.reload)) }
  end

  test "trashing, restoring and purging a live page each move" do
    page = create_page(title: "Live")

    assert_moves("trashing a live page") { ok(Trash::Move.call(page)) }
    assert_moves("restoring a live page") { ok(Trash::Restore.call(page.reload)) }
    ok(Trash::Move.call(page.reload))
    assert_moves("purging a live page") { ok(Trash::Purge.call(page.reload)) }
  end

  # The members of a branch are flagged with `update_all`, around their own
  # callbacks, and the root here is a draft whose own save bumps nothing.
  test "a draft branch with a live page inside moves on its way to the trash and back" do
    root = create_page(title: "Draft root", published: false)
    create_page(title: "Live inside", parent: root)

    assert_moves("trashing a branch with a live member") { ok(Trash::Move.call(root)) }
    assert_moves("restoring a branch with a live member") { ok(Trash::Restore.call(root.reload)) }
  end

  test "moving a live page and reordering live siblings move" do
    target = create_page(title: "Target")
    first = create_page(title: "First")
    create_page(title: "Second")

    assert_moves("reordering live siblings") { ok(Pages::Move.call(first, parent: root_page, position: 2)) }
    assert_moves("moving a live page under another") { ok(Pages::Move.call(first, parent: target, position: 0)) }
  end

  # `Page::TreeRanking` (and closure_tree before it) renumber the siblings
  # around their callbacks. Placing a draft changes no live page's place
  # relative to another, so nothing a visitor sees: it stays -- and the live
  # pages' order is asserted, since that is what the claim rests on.
  test "a draft placed among live siblings stays, and leaves their order alone" do
    one = create_page(title: "Live one")
    two = create_page(title: "Live two")
    three = create_page(title: "Live three")
    live_order = -> { Page.kept.published.where(parent_id: root_page.id).order(:position).pluck(:id) }
    draft = nil

    assert_stays("a draft appended after live siblings") { draft = create_page(title: "Draft", published: false) }
    assert_stays("a draft placed ahead of live siblings") { ok(Pages::Move.call(draft, parent: root_page, position: 0)) }
    assert_stays("a draft placed between live siblings") { ok(Pages::Move.call(draft, parent: root_page, position: 2)) }
    assert_equal [ one.id, two.id, three.id ], live_order.call

    ok(Trash::Move.call(draft))
    ok(Pages::Move.call(three, parent: root_page, position: 0))
    assert_stays("a draft restored among live siblings") { ok(Trash::Restore.call(draft.reload)) }
    assert_equal [ three.id, one.id, two.id ], live_order.call
  end

  test "the blocks of a live page move: add, edit, reorder, delete" do
    page = create_page(title: "Live")
    first = second = nil

    assert_moves("adding a block to a live page") { first = block_on(page) }
    assert_moves("adding a second block") { second = block_on(page) }
    assert_moves("editing a live page's block") { ok(ContentBlocks::Save.call(first, translations: { "en" => { body: rich_doc("Edited") } })) }
    assert_moves("reordering a live page's blocks") { ok(ContentBlocks::Reorder.call(page, [ second.id, first.id ])) }
    assert_stays("an order resubmitted unchanged") { ok(ContentBlocks::Reorder.call(page, [ second.id, first.id ])) }
    assert_moves("deleting a live page's block") { ok(ContentBlocks::Destroy.call(second)) }
  end

  # Without the services' owner touch: the block's own `after_commit`.
  test "a block of a live page saved or destroyed without its service moves, a draft's stays" do
    live = block_on(create_page(title: "Live"))
    draft = block_on(create_page(title: "Draft", published: false))

    assert_moves("a live page's block, saved directly") { live.update!(position: 5) }
    assert_stays("a draft's block, saved directly") { draft.update!(position: 5) }
    assert_moves("a live page's block, destroyed directly") { live.destroy! }
    assert_stays("a draft's block, destroyed directly") { draft.destroy! }
  end

  test "a live post's tags move" do
    post = create_post(title: "Live", tags: [ "one" ])

    assert_moves("a live post gaining a tag") { ok(Posts::Save.call(post, attributes: { tag_names: %w[one two] })) }
    assert_moves("a live post losing a tag") { ok(Posts::Save.call(post, attributes: { tag_names: %w[two] })) }
    assert_moves("a tag put on a live post around the service") { post.tags << Tag.create!(name: "three") }
  end

  # --- Addresses ---------------------------------------------------------------

  # A draft listing page that changes its address takes the live posts it
  # lists with it; the page's own save bumps nothing.
  test "a live post whose address changes through a draft page's save moves" do
    listing = create_page(title: "Blog", published: false)
    block_on(listing, block_type: "post_list", settings: { "content_type" => "blog" })
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", post.full_path("en")

    assert_moves { ok(Pages::Save.call(listing, translations: { "en" => { slug: "journal" } })) }
    assert_equal "/journal/hello", post.full_path("en")
  end

  test "a sync that finds nothing to write stays, and a rebuild moves" do
    page = create_page(title: "Live")

    assert_stays("a sync with nothing to change") { PublicSite::Paths.sync_subtree(page) }
    assert_moves("a rebuild") { PublicSite::Paths.rebuild! }
  end

  # --- Library images ----------------------------------------------------------

  test "uploading, editing, trashing and purging a library image each move" do
    asset = nil
    assert_moves("an upload") { asset = ok(Media::Upload.call(file: png_upload)).record }
    assert_moves("an image's alt") { ok(Media::Save.call(asset, translations: { "en" => { alt: "A picture" } })) }
    assert_moves("an image's title") { ok(Media::Save.call(asset, attributes: { title: "Renamed" })) }
    assert_moves("trashing an image") { ok(Trash::Move.call(asset)) }
    assert_moves("restoring an image") { ok(Trash::Restore.call(asset.reload)) }
    ok(Trash::Move.call(asset.reload))
    assert_moves("purging an image") { ok(Trash::Purge.call(asset.reload)) }
  end

  # `Trash::Restore` brings a page's trashed images back with `update_all`,
  # around `Media::Asset`'s own callback; the page here is a draft.
  test "an image restored together with a draft page moves" do
    page, _child, asset = draft_branch_with_image
    ok(Trash::Move.call(page))
    ok(Trash::Move.call(asset.reload))

    assert_moves { ok(Trash::Restore.call(page.reload)) }
    assert_not asset.reload.trashed?
  end

  # The dimensions are written with `update_columns` after the upload has
  # committed (and bumped): a write of its own.
  test "an upload's dimensions, written around the callbacks, move" do
    asset = create_media_asset

    assert_moves { Media::Upload.new(file: png_upload).send(:analyze_dimensions, asset) }
  end

  test "a variant record created or removed moves" do
    asset = create_media_asset
    record = nil

    assert_moves("a processed variant") { record = ActiveStorage::VariantRecord.create!(blob: asset.file.blob, variation_digest: "w480-digest") }
    assert_moves("a variant removed") { record.destroy! }
  end

  # --- Settings and languages --------------------------------------------------

  test "saving the settings moves" do
    assert_moves("the site title") { ok(Settings::Save.call(Current.site, translations: { "en" => { title: "Renamed" } })) }
    assert_moves("the time zone") { ok(Settings::Save.call(Current.site, attributes: { time_zone: "Berlin" })) }
  end

  test "enabling, disabling and changing the default language each move" do
    two_locales
    create_page(title: "Something translated")

    assert_moves("enabling a language") { ok(Locales::Enable.call("es")) }
    assert_moves("making a language the default") { ok(Locales::MakeDefault.call("de")) }
    assert_moves("disabling a language") { ok(Locales::Disable.call("es")) }
    assert_moves("reordering the languages") { ok(Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "en" ] } ])) }
  end

  # --- Tags --------------------------------------------------------------------

  test "renaming, merging and deleting a tag a live post carries each move" do
    tagged_post_with_listing("old")
    create_post(title: "Other", tags: [ "into" ])

    assert_moves("a rename") { ok(Tags::Rename.call(tag_named("old"), name: "new")) }
    assert_moves("a merge") { ok(Tags::Merge.call(tag_named("new"), into: tag_named("into"))) }
    assert_moves("a delete") { ok(Tags::Destroy.call(tag_named("into"))) }
  end

  # --- What no public page shows -----------------------------------------------

  test "groups, users, tokens and sessions stay" do
    group = nil
    assert_stays("a group") { group = ok(Groups::Save.call(AccessControl::Group.new, attributes: { name: "Writers", grants: [ { permission: "posts.read", scope: {} } ], member_ids: [] })).record }
    assert_stays("a group's members") { ok(Groups::Save.call(group, attributes: { name: "Writers", grants: [ { permission: "posts.read", scope: {} } ], member_ids: [ users(:author).id ] })) }
    user = nil
    assert_stays("a new user") { user = ok(Users::Save.call(attributes: { email_address: "new@example.com", password: ServiceCalls::PASSWORD, password_confirmation: ServiceCalls::PASSWORD, group_ids: [ group.id ] })).record }
    assert_stays("a user's name") { ok(Users::Save.call(user, attributes: { name: "Somebody" })) }
    assert_stays("a token") { ok(ApiTokens::Issue.call(users(:one), group: access_control_groups(:admin), name: "Laptop")) }
    assert_stays("a session") { users(:one).sessions.create!(user_agent: "test", ip_address: "127.0.0.1") }
    assert_stays("a user deleted") { ok(Users::Destroy.call(user)) }
    assert_stays("a group deleted") { ok(Groups::Destroy.call(group)) }
  end

  test "an audit event stays" do
    post = create_post(title: "Draft", published: false)

    assert_stays { Audit.record("post.updated", subject: post) }
  end

  test "a translation confirmed stays, on a draft and on a live page alike" do
    two_locales
    draft = create_page(title: "Hello", published: false, translations: { "de" => { title: "Hallo" } })
    live = create_page(title: "World", translations: { "de" => { title: "Welt" } })
    [ draft, live ].each { |page| ok(Pages::Save.call(page, translations: { "en" => { title: "#{page.title} again" } })) }

    assert_stays("a draft's translation confirmed") { ok(Translations::Confirm.call(draft, field: "title", locale: "de")) }
    assert_stays("a live page's translation confirmed") { ok(Translations::Confirm.call(live, field: "title", locale: "de")) }
  end

  test "a refused write and a rolled-back one stay" do
    post = create_post(title: "Live")

    assert_stays("a refused save") do
      assert as(users(:reader)) { Posts::Save.call(post, translations: { "en" => { title: "No" } }) }.denied?
    end
    assert_stays("a rolled-back save") do
      Post.transaction do
        ok(Posts::Save.call(post, translations: { "en" => { title: "Never" } }))
        ok(Tags::Rename.call(Tag.create!(name: "gone"), name: "never"))
        raise ActiveRecord::Rollback
      end
    end
  end

  # --- The version itself ------------------------------------------------------

  test "the version read costs exactly three queries" do
    create_post(title: "Live")
    PublicSite::Version.current # the first read of a model loads its schema

    statements = capture_sql { PublicSite.content_version }

    assert_equal 3, statements.size, statements.join("\n")
    assert_match(/public_site_versions/, statements[0])
    assert_match(/MAX\("pages"."published_at"\)/, statements[1])
    assert_match(/MAX\("posts"."published_at"\)/, statements[2])
  end

  test "the per-request memo is one read, and a bump clears it" do
    first = PublicSite.current_content_version
    assert_empty capture_sql { assert_equal first, PublicSite.current_content_version }

    PublicSite.bump_version!

    assert_not_equal first, PublicSite.current_content_version
  end

  test "a bump inside a transaction waits for the commit" do
    before = counter

    ActiveRecord::Base.transaction(requires_new: true) do
      PublicSite.bump_version!
      assert_equal before, counter, "the counter must not move, or be locked, inside the transaction"
    end

    assert_equal before + 1, counter
  end

  test "a database with no version row reads 0 and the first bump creates the row" do
    PublicSite::Version.delete_all
    assert_equal 0, counter

    PublicSite.bump_version!
    PublicSite.bump_version!

    assert_equal 2, counter
    assert_equal 1, PublicSite::Version.count
  end

  # No write happens when a scheduled record's time comes: the two
  # publication-time lookups are what make the next request see it.
  test "a scheduled post going live by the clock changes the version with no write" do
    create_post(title: "Already live")
    ok(Posts::Save.call(create_post(title: "Later", published: false), attributes: { published_at: 1.hour.from_now }))
    before_version, before_counter = PublicSite.content_version, counter

    travel_to 59.minutes.from_now do
      assert_equal before_version, PublicSite.content_version, "nothing has gone live yet"
    end
    travel_to 61.minutes.from_now do
      assert_not_equal before_version, PublicSite.content_version
      assert_equal before_counter, counter, "no write: the counter itself has not moved"
    end
  end

  test "a scheduled page going live by the clock changes the version with no write" do
    ok(Pages::Save.call(create_page(title: "Later", published: false), attributes: { published_at: 1.hour.from_now }))
    before = PublicSite.content_version

    travel_to(61.minutes.from_now) { assert_not_equal before, PublicSite.content_version }
  end

  # A scheduled record in the trash does not go live, and is not counted.
  test "a trashed scheduled post's time passing changes nothing" do
    post = create_post(title: "Later", published: false)
    ok(Posts::Save.call(post, attributes: { published_at: 1.hour.from_now }))
    ok(Trash::Move.call(post.reload))
    before = PublicSite.content_version

    travel_to(61.minutes.from_now) { assert_equal before, PublicSite.content_version }
  end

  test "the rake task bumps and prints the new counter" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("public_site:bump_version")
    before = counter

    out, = capture_io { Rake::Task["public_site:bump_version"].execute }

    assert_equal before + 1, counter
    assert_includes out, (before + 1).to_s
  end
end

# The increment is `counter = counter + 1` in the database, so two writers
# at once both count. Outside the test transaction, where the two threads
# hold a connection each (inside it they would share one, and the test would
# pass for a read-then-write in Ruby too).
class PublicSite::VersionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { @rows = PublicSite::Version.pluck(:id, :counter) }

  teardown do
    PublicSite::Version.delete_all
    @rows.each { |id, counter| PublicSite::Version.create!(id: id, counter: counter) }
  end

  test "bumps from several threads at once all count" do
    PublicSite.bump_version!
    before = PublicSite::Version.current

    threads = Array.new(4) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { 25.times { PublicSite.bump_version! } }
      end
    end
    threads.each(&:join)

    # Uncached: the test runs inside the executor, whose query cache holds
    # this thread's earlier read and is not cleared by another connection's
    # writes.
    assert_equal before + 100, PublicSite::Version.uncached { PublicSite::Version.current }
  end
end
