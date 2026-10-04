require "test_helper"

# The Trash screen's round-3 design (Task 14): counted tabs, who and when,
# the retention tag, the subpage sentence, inline "Restore under", the
# disabled "Delete now…" with its reason and the Empty trash dialog. The
# list itself, restore, purge and visibility stay in `trash_test.rb`.
class Admin::TrashScreenTest < ActionDispatch::IntegrationTest
  setup do
    # Midday (final fix wave): the retention tag counts calendar days, so a
    # run that crossed midnight between this setup and a request read "IN 29
    # DAYS". Without a block, so each test may move on with `travel_to` again.
    @now = Time.current.change(hour: 12)
    travel_to @now
    Current.actor = users(:one)
    @section = create_page(title: "Section")
    @child = create_page(title: "Child", parent: @section)
    @post = create_post(title: "Gone post")
    @asset = create_media_asset
    # One second apart: the clock is stopped, and the list is newest first.
    [ @section, @post, @asset ].each_with_index do |record, index|
      travel_to @now + index.seconds
      Trash::Move.call(record)
    end
    travel_to @now + 3.seconds
    Current.reset
  end

  def tab_texts = css_select("nav[aria-label='Filter by type'] a").map { |a| a.text.squish }

  # ---- tabs ----------------------------------------------------------

  test "the tabs carry the counts the sidebar badge sums" do
    sign_in_as users(:one)
    get admin_trash_path
    assert_equal [ "All 3", "Pages 1", "Posts 1", "Images 1" ], tab_texts

    counts = Admin::TrashController.counts(users(:one))
    assert_equal({ "page" => 1, "post" => 1, "media" => 1 }, counts)
    assert_equal Admin::TrashController.badge_count(users(:one)), counts.values.sum
  end

  test "the counts respect the viewer's rights" do
    mine = create_media_asset
    mine.update!(created_by_id: users(:author).id)
    Current.set(actor: users(:one)) { Trash::Move.call(mine) }
    sign_in_as users(:author)
    get admin_trash_path
    assert_equal [ "All 1", "Pages 0", "Posts 0", "Images 1" ], tab_texts
    assert_equal 1, Admin::TrashController.badge_count(users(:author))
  end

  test "a tab is a link that lists its type, junk means All, and the current tab is marked" do
    sign_in_as users(:one)
    get admin_trash_path(type: "posts")
    assert_select "tbody tr", count: 1
    assert_select "tr", text: /Gone post/
    assert_select "nav[aria-label='Filter by type'] a[aria-current=page]", text: /Posts/

    get admin_trash_path(type: "pages")
    assert_select "tbody tr", count: 1
    assert_select "tr", text: /Section/

    get admin_trash_path(type: "images")
    assert_select "tbody tr", count: 1

    get admin_trash_path(type: "nonsense")
    assert_select "tbody tr", count: 3
    assert_select "nav[aria-label='Filter by type'] a[aria-current=page]", text: /All/
  end

  test "changing tab drops the page number" do
    Current.set(actor: users(:one)) { 51.times { |n| Trash::Move.call(create_post(title: "Extra #{n}")) } }
    sign_in_as users(:one)
    get admin_trash_path(page: 2, type: "posts")
    assert_select "nav[aria-label='Filter by type'] a[href*='type=images']"
    assert_select "nav[aria-label='Filter by type'] a:not([href*='page='])", count: 4
  end

  # Final fix wave (I2): the list, the tabs and the badge are the page roots
  # `Trash.roots` -- and so `Trash::Empty` and the retention job -- work on.
  # A page left with no `trash_root_id` (its root's row deleted around the
  # services; the FK nullifies) is not one of them: it was a row here that
  # Empty trash and the sweep would never take.
  test "a trashed page with no trash root is not a row, a count or part of the badge: the screen lists what Trash.roots holds" do
    @child.reload.update_columns(trash_root_id: nil)
    sign_in_as users(:one)

    get admin_trash_path
    assert_equal [ "All 3", "Pages 1", "Posts 1", "Images 1" ], tab_texts
    assert_select "#trash-page-#{@child.id}", count: 0
    assert_equal Trash.roots[:pages].pluck(:id), Admin::TrashController.roots("page", users(:one)).order(:trashed_at, :id).pluck(:id)
    assert_equal 3, Admin::TrashController.badge_count(users(:one))
  end

  # Final fix wave (m2): the tabs' three counts ARE the sidebar badge's; the
  # Trash page used to run them twice.
  test "the Trash page counts each type once: the badge reuses the tabs' counts" do
    group = access_control_groups(:branch_editors)
    %w[pages.delete posts.delete media.manage].each { |key| AccessControl::Grant.create!(group:, permission: key, scope: {}) }
    sign_in_as users(:editor_branch)
    get admin_trash_path

    counts = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      counts << payload[:sql] if payload[:sql].match?(/\ASELECT COUNT\(\*\) FROM "(pages|posts|media_assets)"/) && payload[:sql].include?("trashed_at")
    end
    ActiveRecord::Base.uncached { get admin_trash_path }
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_equal 3, counts.size, counts.join("\n")
    assert_equal [ "All 3", "Pages 1", "Posts 1", "Images 1" ], tab_texts
    assert_select "nav[aria-label='Modules'] a[href='#{admin_trash_path}']", text: /3/
  end

  test "each tab has its own empty state" do
    Current.set(actor: users(:one)) { Trash::Empty.call }
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "*", text: /The trash is empty/
    get admin_trash_path(type: "pages")
    assert_select "*", text: /No pages in the trash/
    get admin_trash_path(type: "posts")
    assert_select "*", text: /No posts in the trash/
    get admin_trash_path(type: "images")
    assert_select "*", text: /No images in the trash/
  end

  # ---- who and when --------------------------------------------------

  test "who: You, a name, the name recorded in the audit log, or System" do
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-post-#{@post.id}", text: /You · /

    sign_in_as users(:two)
    get admin_trash_path
    assert_select "#trash-post-#{@post.id}", text: /one@example\.com · /
    assert_select "#trash-post-#{@post.id}", text: /You/, count: 0

    # The trasher's FK is gone but the `post.trashed` event still names them.
    @post.update_columns(trashed_by_id: nil)
    get admin_trash_path
    assert_select "#trash-post-#{@post.id}", text: /one@example\.com · /

    # Nobody at all: a system move.
    system_post = Current.set(actor: nil, channel: :system) { create_post(title: "System post").tap { |p| Trash::Move.call(p, actor: nil) } }
    get admin_trash_path
    assert_select "#trash-post-#{system_post.id}", text: /System · /
  end

  test "who: an event whose user has been deleted reads as a deleted user" do
    leaver = User.create!(email_address: "leaver@example.com", password: "a-long-password-1")
    AccessControl::Membership.create!(user: leaver, group: access_control_groups(:admin))
    gone = Current.set(actor: users(:one)) { create_post(title: "Leaver's post") }
    Current.set(actor: leaver) { Trash::Move.call(gone) }
    assert_equal leaver.id, gone.reload.trashed_by_id
    AccessControl::Membership.where(user_id: leaver.id).delete_all
    Session.where(user_id: leaver.id).delete_all
    User.where(id: leaver.id).delete_all # the FK nullifies `trashed_by_id`
    assert_nil gone.reload.trashed_by_id
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-post-#{gone.id}", text: /a deleted user · /
  end

  # Final fix wave (m4). A token's trash sets `trashed_by` to the token's
  # USER, so the row named the user alone -- "via <token>" showed only once
  # that user was gone and the event was read instead.
  test "who: an item an API token trashed names its user and the token, for that user and for anyone else" do
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name: "Deploy bot")
    by_token = Current.set(actor: users(:one)) { create_post(title: "Trashed by a token") }
    Current.set(actor: token, channel: :mcp) { assert Trash::Move.call(by_token).ok? }
    assert_equal users(:two).id, by_token.reload.trashed_by_id

    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-post-#{by_token.id}", text: /two@example\.com via Deploy bot · /
    assert_select "#trash-post-#{@post.id}", text: /You · /
    assert_select "#trash-post-#{@post.id}", text: /via/, count: 0

    sign_in_as users(:two)
    get admin_trash_path
    assert_select "#trash-post-#{by_token.id}", text: /You via Deploy bot · /

    # The token row is deleted: the name written on the event still says
    # which token it was.
    ApiToken.where(id: token.id).delete_all
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-post-#{by_token.id}", text: /two@example\.com via Deploy bot · /
  end

  # Final fix wave (m4): the event that names the trasher must be the event of
  # THIS trashing. An item trashed, restored and then trashed again by a path
  # that records no event of its own (a branch member going with its root)
  # would otherwise show whoever trashed it the first time.
  test "who: an older trashing's event doesn't name who trashed it this time" do
    Current.set(actor: users(:two)) { assert Trash::Restore.call(@post.reload).ok? }
    later = @now + 2.hours
    @post.reload.update_columns(trashed_at: later, trashed_by_id: nil)
    travel_to later + 1.minute

    sign_in_as users(:two)
    get admin_trash_path
    assert_select "#trash-post-#{@post.id}", text: /System · /
    assert_select "#trash-post-#{@post.id}", text: /one@example\.com/, count: 0
  end

  test "the audit events of the listed rows are read in one query, however many rows" do
    sign_in_as users(:one)
    2.times { |n| make_orphan("Orphan #{n}") }
    few = audit_queries { get admin_trash_path }
    8.times { |n| make_orphan("More #{n}") }
    many = audit_queries { get admin_trash_path }
    assert_equal few, many
    assert_operator few, :<=, 2
    assert_select "tbody tr", count: 13
  end

  # ---- retention tag -------------------------------------------------

  test "the retention tag counts calendar days in the site zone and never goes negative" do
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-post-#{@post.id} [data-retention]", text: /IN 30 DAYS/

    travel_to @now + 29.days
    get admin_trash_path
    assert_select "#trash-post-#{@post.id} [data-retention]", text: /IN 1 DAY\b/

    travel_to @now + 30.days
    get admin_trash_path
    assert_select "#trash-post-#{@post.id} [data-retention]", text: /TODAY/

    travel_to @now + 45.days # the sweep hasn't run yet
    get admin_trash_path
    assert_select "#trash-post-#{@post.id} [data-retention]", text: /TODAY/
    assert_select "#trash-post-#{@post.id} [data-retention]", text: /-/, count: 0
  end

  test "the exact date is a tooltip and also text for a screen reader; never danger" do
    sign_in_as users(:one)
    get admin_trash_path
    due = (@post.reload.trashed_at.in_time_zone + 30.days).strftime("%-d %b %Y")
    # "on or after": the sweep runs once a day, so the date is the first day
    # it can go, not a promise that it goes then.
    assert_select "#trash-post-#{@post.id} [data-retention][title='Deleted for good on or after #{due}']"
    assert_select "#trash-post-#{@post.id} [data-retention] .sr-only", text: /#{due}/
    assert_select "#trash-post-#{@post.id} [data-retention][class*=danger]", count: 0
  end

  test "retention 0 reads NEVER" do
    site_settings(:default).update!(trash_retention_days: 0)
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-post-#{@post.id} [data-retention]", text: /NEVER/
    assert_select "p", text: /stay in the trash until someone deletes them for good/
  end

  test "the retention line and its Change link" do
    sign_in_as users(:two)
    get admin_trash_path
    assert_select "p", text: /Items are deleted for good after 30 days\./
    assert_select "p a[href$='#publishing']", text: "Change"

    sign_in_as users(:author)
    get admin_trash_path
    assert_select "p", text: /Items are deleted for good after 30 days\./
    assert_select "a", text: "Change", count: 0
  end

  # ---- subpages ------------------------------------------------------

  test "a page says what comes back with it" do
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-page-#{@section.id}", text: /Includes 1 subpage: Child/
  end

  test "the subpage sentence names up to three pages and folds the rest into a count" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@section.reload)
      create_page(title: "Second", parent: @section)
      create_page(title: "Third", parent: @section)
      create_page(title: "Fourth", parent: @section)
      Trash::Move.call(@section.reload)
    end
    sign_in_as users(:one)
    get admin_trash_path
    row = css_select("#trash-page-#{@section.id}").text.squish
    assert_includes row, "Includes 4 subpages: Child, Second, Third and 1 more"
    assert_no_match(/Fourth/, row)
  end

  # The sentence names only members the viewer may READ. A viewer who may
  # delete a branch may read it too (a read check also accepts the subject's
  # write keys), so with today's permissions every member of a listed branch
  # is named; the filter only matters if reads are ever scoped more narrowly
  # than deletes, which no grant can express yet.
  test "a viewer who may delete only the branch still sees its subpages named" do
    group = access_control_groups(:branch_editors)
    AccessControl::Grant.create!(group:, permission: "pages.delete", scope: { "page_ids" => [ @section.id ] })
    sign_in_as users(:editor_branch)
    get admin_trash_path
    assert_includes css_select("#trash-page-#{@section.id}").text.squish, "Includes 1 subpage: Child"
  end

  # ---- restore under -------------------------------------------------

  test "several rows that need a parent share one load of the kept pages" do
    Current.set(actor: users(:one)) do
      3.times do |n|
        parent = create_page(title: "Holder #{n}")
        inner = create_page(title: "Inner #{n}", parent:)
        Trash::Move.call(inner)
        Trash::Move.call(parent)
      end
    end
    sign_in_as users(:one)
    kept_loads = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, p|
      kept_loads << p[:sql] if p[:sql].match?(/SELECT "pages"\."id", "pages"\."parent_id", "pages"\."title" FROM "pages"/)
    end
    get admin_trash_path
    ActiveSupport::Notifications.unsubscribe(subscriber)
    assert_select "select[name=parent_id]", count: 3
    assert_equal 1, kept_loads.size
    assert_select "form[action$='/restore'] select[name=parent_id] option", text: "Home"
  end

  test "restoring under a parent that is refused shows the message, not a 500" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@section.reload)
      Trash::Move.call(@child.reload)
      Trash::Move.call(@section.reload)
    end
    sign_in_as users(:one)
    post admin_restore_trash_item_path("page", @child), params: { parent_id: @section.id }
    assert_redirected_to admin_trash_path
    follow_redirect!
    assert_select "[role=alert]"
  end

  # A forged `parent_id` that names the page itself or one of its own
  # descendants: the service's refusal, shown as the alert -- never a 500, and
  # never a page restored under itself.
  test "restoring under itself or under its own descendant is refused with the message" do
    sign_in_as users(:one)

    [ @section.id, @child.id ].each do |parent_id|
      post admin_restore_trash_item_path("page", @section), params: { parent_id: }
      assert_redirected_to admin_trash_path
      assert flash[:alert].present?, "parent_id #{parent_id} gave no alert"
      assert @section.reload.trashed?
      assert_equal root_page.id, @section.parent_id
    end

    # One of its descendants that is KEPT again is still its descendant.
    Current.set(actor: users(:one)) { assert Trash::Restore.call(@child.reload, parent: root_page).ok? }
    grandchild = Current.set(actor: users(:one)) { create_page(title: "Kept elsewhere", parent: @child.reload) }
    post admin_restore_trash_item_path("page", @child), params: { parent_id: grandchild.id }
    assert_response :not_found # `@child` is kept now: not in the trash at all
  end

  # ---- delete now ----------------------------------------------------

  # One page using the image twice -- as its hero and in a block -- is one
  # item: the block counts as the page it sits on.
  test "the in-use count collapses a block onto its page: a hero and a block of one page are 1 item" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@asset.reload)
      Trash::Restore.call(@section.reload)
      assert Pages::Save.call(@section.reload, attributes: { hero_media_asset_id: @asset.id }).ok?
      assert ContentBlocks::Save.call(@section.content_blocks.build, attributes: { block_type: "image", media_asset_id: @asset.id }).ok?
      assert_equal 2, Media::Usage.where(media_asset_id: @asset.id).count
      Trash::Move.call(@section.reload)
      Trash::Move.call(@asset.reload)
    end
    sign_in_as users(:one)
    get admin_trash_path

    assert_select "#trash-media-#{@asset.id} p", text: "Still used by 1 item in the trash"
  end

  test "Delete now… is disabled with its reason as visible text" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@asset.reload)
      Trash::Restore.call(@section.reload)
      other = create_page(title: "Other")
      Pages::Save.call(@section.reload, attributes: { hero_media_asset_id: @asset.id })
      Pages::Save.call(other, attributes: { hero_media_asset_id: @asset.id })
      Trash::Move.call(other.reload)
      Trash::Move.call(@section.reload)
      Trash::Move.call(@asset.reload)
    end
    sign_in_as users(:one)
    get admin_trash_path
    row = "#trash-media-#{@asset.id}"
    assert_select "#{row} button[disabled][title='Still used by 2 items in the trash']", text: /Delete now…/
    assert_select "#{row} p", text: "Still used by 2 items in the trash"
    assert_select "#{row} dialog", count: 0
  end

  test "Delete now… opens a dialog that says how many subpages go with it" do
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "#trash-page-#{@section.id} button", text: /Delete now…/
    assert_select "dialog#purge-page-#{@section.id}", text: /1 subpage under it is deleted too/
  end

  # ---- empty trash ---------------------------------------------------

  test "Empty trash… sits in the header with a sentence built from the kinds present" do
    sign_in_as users(:two)
    get admin_trash_path
    assert_select "button", text: /Empty trash…/
    assert_select "dialog#empty-trash-dialog", text: /This deletes 1 page \(with 1 subpage\), 1 post and 1 image for good\. It can't be undone\./
  end

  test "the sentence counts everything Empty will delete, not the viewer's tab counts" do
    group = access_control_groups(:branch_editors)
    AccessControl::Grant.create!(group:, permission: "trash.empty", scope: {})
    sign_in_as users(:editor_branch)
    get admin_trash_path
    assert_equal [ "All 0", "Pages 0", "Posts 0", "Images 0" ], tab_texts
    assert_select "dialog#empty-trash-dialog", text: /1 page \(with 1 subpage\), 1 post and 1 image/
  end

  # Final fix wave (m3): "The trash is empty" beside "Empty trash… deletes 1
  # page" was a contradiction on one screen.
  test "a trash.empty-only viewer's empty list says there is nothing they can restore, not that the trash is empty" do
    group = access_control_groups(:branch_editors)
    AccessControl::Grant.create!(group:, permission: "trash.empty", scope: {})
    sign_in_as users(:editor_branch)

    get admin_trash_path
    assert_select "tbody tr", count: 0
    assert_select "*", text: /Nothing here you can restore\./
    assert_select "*", text: /The trash is empty/, count: 0
    get admin_trash_path(type: "posts")
    assert_select "*", text: /Nothing here you can restore\./
    assert_select "*", text: /No posts in the trash/, count: 0

    # A tab whose kind really is absent keeps its own empty state...
    Current.set(actor: users(:one)) { assert Trash::Purge.call(@post.reload).ok? }
    get admin_trash_path(type: "posts")
    assert_select "*", text: /No posts in the trash/
    # ...and so does the whole screen once the trash is empty.
    Current.set(actor: users(:one)) { Trash::Empty.call }
    get admin_trash_path
    assert_select "*", text: /The trash is empty/
    assert_select "*", text: /Nothing here you can restore/, count: 0
  end

  # The service would let `trash.empty` purge any one item; the screen loads an
  # item only through the viewer's own delete right, so by id it is "not found"
  # for them -- and never restorable, which `trash.empty` doesn't cover at all.
  test "a trash.empty-only viewer can't purge or restore one item by id: not found" do
    group = access_control_groups(:branch_editors)
    AccessControl::Grant.create!(group:, permission: "trash.empty", scope: {})
    sign_in_as users(:editor_branch)

    delete admin_trash_item_path("post", @post)
    assert_response :not_found
    post admin_restore_trash_item_path("post", @post)
    assert_response :not_found
    delete admin_trash_item_path("page", @section)
    assert_response :not_found
    assert @post.reload.trashed?
    assert @section.reload.trashed?
    assert_not Audit::Event.exists?(action: %w[post.purged post.restored page.purged])
  end

  test "only the kinds present are named" do
    Current.set(actor: users(:one)) { Trash::Purge.call(@asset.reload); Trash::Purge.call(@section.reload) }
    sign_in_as users(:two)
    get admin_trash_path
    assert_select "dialog#empty-trash-dialog", text: /This deletes 1 post for good\./
  end

  # ---- after an action -----------------------------------------------

  test "restore, delete and empty come back to the tab they were done from" do
    sign_in_as users(:one)
    post admin_restore_trash_item_path("post", @post), params: { tab: "posts" }
    assert_redirected_to admin_trash_path(type: "posts")

    delete admin_trash_item_path("media", @asset), params: { tab: "images" }
    assert_redirected_to admin_trash_path(type: "images")

    post admin_restore_trash_item_path("page", @section), params: { tab: "junk" }
    assert_redirected_to admin_trash_path
  end

  private

  def audit_queries
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| queries << p[:sql] if p[:sql].match?(/FROM "audit_events"/) }
    yield
    queries.size
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def make_orphan(title)
    Current.set(actor: nil, channel: :system) do
      post = create_post(title:)
      Trash::Move.call(post, actor: nil)
      post
    end
  end
end
