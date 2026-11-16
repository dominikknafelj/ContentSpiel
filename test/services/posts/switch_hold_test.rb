require "test_helper"

# Every write that decides from a post type's switch holds the settings row
# `FOR SHARE` (`ContentTypes.hold!`) before the rows the decision writes: the
# post's own row, its addresses (`public_paths`) and its search entries. A
# switch takes the same row `FOR UPDATE` first (`Settings::Save`), so the two
# are ordered and a switch-off never commits beside a publish that still sees
# the type on. The two orders forced on two connections are
# `Settings::SwitchRaceTest`.
class Posts::SwitchHoldTest < ActiveSupport::TestCase
  def list_page
    root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    everything = Page.create!(parent: root, title: "Everything", published_at: 1.day.ago)
    everything.content_blocks.create!(block_type: :post_list, position: 0, settings: {})
  end

  def hold?(sql) = sql.include?('FROM "site_settings"') && sql.include?("FOR SHARE")
  def address_write?(sql) = sql.match?(/\A(INSERT INTO|UPDATE|DELETE FROM) "public_paths"/)
  def entry_write?(sql) = sql.include?('"search_entries"') && sql.start_with?("INSERT")

  # The index of the first statement that `matches`, failing when none does.
  def first(statements, what, &matches)
    statements.index(&matches).tap { |index| assert index, "no statement #{what}:\n#{statements.join("\n")}" }
  end

  test "a new post's publish holds the switches before it writes the post, its address and its entries" do
    list_page
    post = nil

    statements = capture_sql { post = create_post(title: "Lighthouse keeper", content_type: "resume_entry") }

    hold = first(statements, "holds the switches") { hold?(_1) }
    assert_operator hold, :<, first(statements, "writes the post") { _1.start_with?('INSERT INTO "posts"') }
    assert_operator hold, :<, first(statements, "writes an address") { address_write?(_1) }
    assert_operator hold, :<, first(statements, "writes an entry") { entry_write?(_1) }
    assert PublicPath.current.where(record: post).exists?, "the publish gave the post its address"
  end

  test "Publish changes holds the switches before the post's row lock" do
    list_page
    post = create_post(title: "Lighthouse keeper", content_type: "resume_entry")
    assert Posts::Save.call(post.reload, translations: { "en" => { title: "Harbour master" } }).ok?

    statements = capture_sql { assert Publishing::PublishChanges.call(post.reload).ok? }

    hold = first(statements, "holds the switches") { hold?(_1) }
    assert_operator hold, :<, first(statements, "locks the post") { _1.include?('FROM "posts"') && _1.include?("FOR UPDATE") }
    assert_operator hold, :<, first(statements, "writes an entry") { entry_write?(_1) }
  end

  test "a refresh of addresses holds the switches before it writes one" do
    list_page
    post = create_post(title: "Lighthouse keeper", content_type: "resume_entry")
    PublicPath.where(record: post).delete_all

    statements = capture_sql { PublicSite::Paths.refresh(posts: [ post ]) }

    assert_operator first(statements, "holds the switches") { hold?(_1) }, :<, first(statements, "writes an address") { address_write?(_1) }
  end

  # A switch's own refresh marks the due copies too, so a refresh of nothing
  # (the clock's job) holds the switches before it locks one, and only then.
  test "a refresh of nothing holds the switches before it marks a due copy, and not when nothing is due" do
    page = create_page(title: "Later")
    assert Pages::Save.call(page, translations: { "en" => { title: "Later still" } }).ok?
    publish_changes(page, at: 1.hour.from_now)

    travel_to 2.hours.from_now do
      statements = capture_sql { PublicSite::Paths.refresh }
      mark = first(statements, "locks a due copy") { _1.include?('FROM "published_versions"') && _1.include?("FOR UPDATE") }
      assert_operator first(statements, "holds the switches") { hold?(_1) }, :<, mark

      assert_empty capture_sql { PublicSite::Paths.refresh }.select { hold?(_1) }
    end
  end

  # The outcome of the race, on one connection: the request's memo of the
  # settings still says the type is on, while the row says a switch-off has
  # committed. The save asks the refusal again under the hold and stands under
  # the row's switch.
  test "a save whose memo predates a committed switch-off is refused under the hold and writes nothing" do
    list_page
    post = create_post(title: "Lighthouse keeper", content_type: "resume_entry", published: false)
    stale = SiteSetting.find(Current.site.id)
    SiteSetting.where(id: stale.id).update_all(content_types: %w[blog now_update], updated_at: 1.second.from_now)
    Current.site = stale
    assert ContentTypes.switched_on?("resume_entry"), "the premise: the memo still says on"
    addresses = PublicPath.where(record: post).pluck(:id, :path, :current)

    result = Posts::Save.call(post.reload, attributes: { published: true })

    assert_not result.ok?
    assert_equal :switched_off, result.refusal
    assert_nil post.reload.published_at
    assert_equal addresses, PublicPath.where(record: post).pluck(:id, :path, :current)
    assert_not SiteSearch::Entry.where(record_type: "Post", record_id: post.id).exists?
  end

  test "Publish changes whose memo predates a committed switch-off takes no copy" do
    list_page
    post = create_post(title: "Lighthouse keeper", content_type: "resume_entry")
    assert Posts::Save.call(post.reload, translations: { "en" => { title: "Harbour master" } }).ok?
    copies = Publishing::Version.of(post).count
    stale = SiteSetting.find(Current.site.id)
    SiteSetting.where(id: stale.id).update_all(content_types: %w[blog now_update], updated_at: 1.second.from_now)
    Current.site = stale

    result = Publishing::PublishChanges.call(post.reload)

    assert_not result.ok?
    assert_equal :switched_off, result.refusal
    assert_equal copies, Publishing::Version.of(post).count
  end
end
