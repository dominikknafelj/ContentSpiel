require "test_helper"

class Admin::PublishingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
    sign_in_as users(:one)
  end

  test "publish takes a copy and goes back to the editor saying so" do
    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal 2, Publishing.current(@page).number
    follow_redirect!
    assert_includes response.body, "Changes published"
  end

  test "a post is published the same way and returns to its own editor" do
    record = create_post(title: "Post")
    assert Posts::Save.call(record, translations: { "en" => { title: "Changed" } }).ok? # Task 6: a publish with nothing changed takes no copy

    post admin_publishing_publish_path(kind: "post", id: record.id)

    assert_redirected_to admin_post_path(record)
    assert_equal 2, Publishing.current(record).number
  end

  test "a trashed record and one that never existed are not found, and nothing is published" do
    assert Trash::Move.call(@page).ok?

    post admin_publishing_publish_path(kind: "page", id: @page.id)
    assert_response :not_found
    post admin_publishing_publish_path(kind: "page", id: 0)
    assert_response :not_found
    assert_equal 1, Publishing::Version.of(@page).count
  end

  test "a publish that would put the post itself on an address another record holds goes back to the editor with one sentence that names the post and the address" do
    blog = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    Tag.create!(name: "one")
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "one" } })
    publish_changes(@page)
    create_page(title: "Hello", parent: @page)
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, attributes: { tag_names: %w[one] }).ok?
    copies = Publishing::Version.count

    post admin_publishing_publish_path(kind: "post", id: record.id)

    assert_redirected_to admin_post_path(record)
    assert_equal "The post “Hello” would get the address /one/hello, which is already taken in EN, DE, and ES", flash[:publish_error]
    assert_nil flash[:alert], "the dialog shows it, not a toast"
    assert_equal copies, Publishing::Version.count
    assert_equal "/blog/hello", record.reload.full_path("en")
  end

  test "a page's publish that takes another record's address away is not refused: the page is published and the post has no address" do
    blog = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    Tag.create!(name: "one")
    create_page(title: "Hello", parent: @page)
    record = create_post(title: "Hello", tags: %w[one])
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "one" } })
    copies = Publishing::Version.count

    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_nil flash[:alert]
    assert_equal copies + 1, Publishing::Version.count
    assert_nil record.reload.full_path("en")
  end

  test "a draft goes back to the editor with the reason, and nothing is published" do
    draft = create_page(title: "Draft", published: false)

    post admin_publishing_publish_path(kind: "page", id: draft.id)

    assert_redirected_to admin_page_path(draft)
    assert_equal "There is nothing on the site to change: publish it first", flash[:alert]
    assert_empty Publishing::Version.of(draft)
  end

  test "someone who may read but not publish is refused, and nothing is published" do
    sign_in_as users(:reader)

    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_response :forbidden
    assert_equal 1, Publishing::Version.of(@page).count
  end

  # -- the dialog's overview, the time, discard and cancel (Task 7) ----------------

  test "changes is a POST that answers the overview, for a reader too, and is kept by no cache; a GET is no route" do
    post admin_publishing_changes_path(kind: "page", id: @page.id)

    assert_response :success
    assert_select "[data-publishing-overview] [data-changed-fields]", text: "Title"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/<html/, response.body)

    sign_in_as users(:reader)
    post admin_publishing_changes_path(kind: "page", id: @page.id)
    assert_response :success
    assert_select "[data-publishing-overview]"

    get admin_publishing_changes_path(kind: "page", id: @page.id)
    assert_response :not_found
  end

  test "changes writes nothing: no copy, no address, no event, no mark moved, no content version" do
    before = [ Publishing::Version.count, PublicPath.order(:id).pluck(:id, :path), Audit::Event.count, @page.reload.unpublished_changes_at, PublicSite.content_version ]

    post admin_publishing_changes_path(kind: "page", id: @page.id)

    assert_equal before, [ Publishing::Version.count, PublicPath.order(:id).pluck(:id, :path), Audit::Event.count, @page.reload.unpublished_changes_at, PublicSite.content_version ]
  end

  test "changes names the live post that would lose its address when the page's list block is removed, with a link to its editor, and refuses nothing" do
    blog = create_page(title: "Blog", published: false)
    list = ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    record = create_post(title: "Hello")
    assert_equal "/blog/hello", record.reload.full_path("en")
    assert ContentBlocks::Destroy.call(list).ok?

    post admin_publishing_changes_path(kind: "page", id: blog.id)

    assert_select "[data-publishing-lost-addresses] [data-lost-address]", count: 1
    assert_select "[data-lost-address] a[href='#{admin_post_path(record)}']", text: "Hello"
    assert_select "[data-lost-address]", text: %r{/blog/hello}
    assert_select "[data-change=removed]", count: 1
    assert_equal "/blog/hello", record.reload.full_path("en"), "asking took nothing away"

    post admin_publishing_publish_path(kind: "page", id: blog.id), params: { when: "now" }
    assert_nil flash[:publish_error]
    assert_nil record.reload.full_path("en"), "and the publish is not refused for it"
  end

  test "someone who may not publish is shown the overview without the trial of the addresses" do
    blog = create_page(title: "Blog", published: false)
    list = ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(list).ok?
    sign_in_as users(:reader)

    statements = capture_sql { post admin_publishing_changes_path(kind: "page", id: blog.id) }

    assert_response :success
    assert_select "[data-publishing-lost-addresses]", count: 0
    assert_empty statements.grep(/FOR UPDATE|SAVEPOINT/)
  end

  test "changes says who holds a part of the page in another tab" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    users(:two).update!(name: "Dana Weiss")
    reserve(block, @page, users(:two), "tab-bbbbbbbb")

    post admin_publishing_changes_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_select "[data-publishing-held]", text: "Dana Weiss is editing this page. Only what has been saved is published."
  end

  test "publish at a time schedules, and the same form with 'kept' replaces what is scheduled and keeps its time" do
    at = 2.days.from_now.change(sec: 0)

    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "at", published_at: at.in_time_zone(Current.site.effective_time_zone).strftime("%Y-%m-%dT%H:%M") }

    assert_redirected_to admin_page_path(@page)
    assert_match(/\AChanges scheduled for \d+ \w+ \d{4}, \d\d:\d\d\z/, flash[:notice])
    assert_equal 1, Publishing.current(@page).number
    assert_in_delta at.to_f, Publishing.pending(@page).live_at.to_f, 60

    assert Pages::Save.call(@page, translations: { "en" => { title: "Three" } }).ok?
    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "kept" }
    assert_in_delta at.to_f, Publishing.pending(@page).live_at.to_f, 60
    assert_equal({ "en" => "Three" }, Publishing.pending(@page).snapshot.dig("fields", "title"))
  end

  test "'now' publishes at once what was scheduled for later" do
    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "at", published_at: 2.days.from_now.strftime("%Y-%m-%dT%H:%M") }
    assert Publishing.pending(@page)

    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "now" }

    assert_equal "Changes published", flash[:notice]
    assert_nil Publishing.pending(@page)
    assert_equal({ "en" => "Two" }, Publishing.current(@page).snapshot.dig("fields", "title"))
  end

  test "a time in the past, or none, publishes nothing and says why, for the dialog and not as a toast, with what was chosen" do
    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "at", published_at: "" }

    assert_redirected_to admin_page_path(@page)
    assert_equal 1, Publishing::Version.of(@page).count
    assert_equal "Choose a date and time", flash[:publish_error]
    assert_nil flash[:alert]

    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "at", published_at: "2001-01-01T09:00" }
    assert_equal "Pick a time in the future.", flash[:publish_error]
    assert_equal 1, Publishing::Version.of(@page).count
    assert_equal [ "at", "2001-01-01T09:00" ], flash.to_h.values_at("publish_when", "publish_value")
  end

  test "'kept' with nothing scheduled any more publishes nothing and says so" do
    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "kept" }

    assert_equal "These changes are no longer scheduled. Nothing was published.", flash[:publish_error]
    assert_equal 1, Publishing::Version.of(@page).count
  end

  test "discard writes the copy back and says so" do
    post admin_publishing_discard_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal "One", Mobility.with_locale(:en) { @page.reload.title }
    follow_redirect!
    assert_includes response.body, "Changes discarded"
  end

  test "discard is refused while another tab holds a block of the page or its settings, says who, and writes nothing" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    users(:two).update!(name: "Dana Weiss")
    reserve(block, @page, users(:two), "tab-bbbbbbbb")
    events = Audit::Event.count

    post admin_publishing_discard_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_redirected_to admin_page_path(@page)
    assert_match(/Dana Weiss is editing/, flash[:alert])
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
    assert ContentBlock.exists?(block.id)
    assert_equal events, Audit::Event.count

    Editing::Reservation.delete_all # version: none (a reservation is not content)
    reserve(@page, @page, users(:two), "tab-bbbbbbbb")
    post admin_publishing_discard_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }
    assert_match(/Dana Weiss is editing/, flash[:alert])
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "a post's discard is refused while another tab holds the post" do
    record = create_post(title: "Post")
    assert Posts::Save.call(record, translations: { "en" => { title: "Changed" } }).ok?
    users(:two).update!(name: "Dana Weiss")
    reserve(record, record, users(:two), "tab-bbbbbbbb")

    post admin_publishing_discard_path(kind: "post", id: record.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_redirected_to admin_post_path(record)
    assert_match(/Dana Weiss is editing this post/, flash[:alert])
    assert_equal "Changed", Mobility.with_locale(:en) { record.reload.title }
  end

  test "my own hold in my own tab does not refuse my discard" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    reserve(block, @page, users(:one), "tab-aaaaaaaa")

    post admin_publishing_discard_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_equal "One", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "publish is not refused by a hold: it writes no row an editor holds" do
    reserve(@page, @page, users(:two), "tab-bbbbbbbb")

    post admin_publishing_publish_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_equal 2, Publishing.current(@page).number
  end

  test "with nothing to discard the editor says so, and nothing is written" do
    assert Publishing::DiscardChanges.call(@page.reload).ok?
    events = Audit::Event.count

    post admin_publishing_discard_path(kind: "page", id: @page.id)

    assert_equal "There is nothing to discard", flash[:alert]
    assert_equal events, Audit::Event.count
  end

  test "cancel scheduled change withdraws the pending copy, leaves the rows and says so; a second press says nothing is scheduled" do
    publish_changes(@page, at: 2.days.from_now)

    post admin_publishing_cancel_scheduled_change_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal "Scheduled change cancelled", flash[:notice]
    assert_nil Publishing.pending(@page)
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
    assert @page.unpublished_changes?

    post admin_publishing_cancel_scheduled_change_path(kind: "page", id: @page.id)
    assert_equal "No change is scheduled", flash[:alert]
  end

  test "cancel is not refused by a hold, and someone who may not publish is refused" do
    publish_changes(@page, at: 2.days.from_now)
    sign_in_as users(:reader)
    post admin_publishing_cancel_scheduled_change_path(kind: "page", id: @page.id)
    assert_response :forbidden
    assert Publishing.pending(@page)

    sign_in_as users(:one)
    reserve(@page, @page, users(:two), "tab-bbbbbbbb")
    post admin_publishing_cancel_scheduled_change_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }
    assert_nil Publishing.pending(@page)
  end

  test "someone who may read but not edit is refused the discard, and nothing is written" do
    sign_in_as users(:reader)

    post admin_publishing_discard_path(kind: "page", id: @page.id)

    assert_response :forbidden
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "a trashed record and one that never existed are not found by the overview, the discard or the cancel" do
    assert Trash::Move.call(@page).ok?

    %i[admin_publishing_changes_path admin_publishing_discard_path admin_publishing_cancel_scheduled_change_path].each do |route|
      post public_send(route, kind: "page", id: @page.id)
      assert_response :not_found, route.to_s
      post public_send(route, kind: "page", id: 0)
      assert_response :not_found, route.to_s
    end
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
  end

  # -- the header follows the mark (Task 6) --------------------------------------

  # Only the chip is streamed: the Publish changes form is drawn once and
  # never replaced (it may be the form the write queue holds while this very
  # save is out). The chip carries the mark that shows it.
  def chip_in_stream = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='publishing-chip']")

  def assert_publishing_parts(present:)
    chip = chip_in_stream
    assert chip, "the chip is in the answer:\n#{response.body}"
    assert_equal present, chip.at_css("[data-unpublished-changes]").present?, "the chip"
    assert_equal present, chip.at_css("[data-publish-changes-offered]").present?, "the sign that shows the Publish changes button"
    assert_nil Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='publishing-actions']"), "the form is never replaced"
    assert_no_match(/<form/, chip.to_s)
  end

  test "a live page's settings autosave, its block's autosave and a live post's autosave each answer with the chip, and the sign that shows the Publish changes button" do
    live = create_page(title: "Live")
    publish_changes(live)
    patch "/cs-studio/pages/#{live.id}", params: { page: { title: "Typed" }, base_updated_at: live.reload.settings_changed_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    Publishing.clear_changes(live)
    patch "/cs-studio/pages/#{live.id}/content_blocks/#{block.id}", params: { block: { caption: "Typed" }, base_updated_at: block.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_publishing_parts(present: true)

    record = create_post(title: "Post")
    patch "/cs-studio/posts/#{record.id}", params: { post: { title: "Typed" }, base_updated_at: record.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_publishing_parts(present: true)
  end

  test "adding, deleting, duplicating and moving a block of a live page do too, where the answer is a stream" do
    live = create_page(title: "Blocks")
    first = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    second = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    publish_changes(live)
    base = "/cs-studio/pages/#{live.id}/content_blocks"

    post base, params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_response :created
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    post "#{base}/#{first.id}/duplicate", as: :turbo_stream
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    patch "#{base}/reorder", params: { ids: live.content_blocks.reload.reorder(position: :desc).ids }, as: :turbo_stream
    assert_response :success
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    delete "#{base}/#{second.id}", as: :turbo_stream
    assert_response :success
    assert_publishing_parts(present: true)
  end

  test "a draft's answers carry neither part, and a failed save carries none" do
    draft = create_page(title: "Draft", published: false)
    patch "/cs-studio/pages/#{draft.id}", params: { page: { title: "Typed" } }, as: :turbo_stream
    assert_response :success
    assert_nil chip_in_stream

    post "/cs-studio/pages/#{draft.id}/content_blocks", params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_nil chip_in_stream
  end

  test "a draft's editor draws no publishing parts, a live one draws both, empty until something changes" do
    draft = create_page(title: "Draft", published: false)
    get admin_page_path(draft)
    assert_select "#publishing-chip", count: 0
    assert_select "#publishing-actions", count: 0

    live = create_page(title: "Live")
    get admin_page_path(live)
    assert_select "#publishing-chip", count: 1
    assert_select "#publishing-chip *", count: 0
    assert_select "#publishing-actions form[action$='/publishing/page/#{live.id}/publish']", count: 1, text: /Publish changes/
    assert_select "[data-publish-changes-offered]", count: 0
  end

  test "someone who may edit but not publish gets the chip and no button" do
    live = create_page(title: "Live")
    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?
    group = AccessControl::Group.create!(name: "Editors without publish")
    %w[pages.read pages.edit].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    editor = User.create!(email_address: "no-publish@example.com", password: "password12345")
    AccessControl::Membership.create!(user: editor, group: group)
    sign_in_as editor

    get admin_page_path(live)

    assert_response :success
    assert_select "#publishing-chip [data-unpublished-changes]", count: 1
    assert_select "#publishing-chip [data-publish-changes-offered]", count: 0
    assert_select "#publishing-actions form", count: 0
  end

  test "publishing with nothing changed says so and takes no copy" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "One" } }).ok? # back to what is published: the mark is set, nothing differs
    assert @page.reload.unpublished_changes?
    copies = Publishing::Version.of(@page).count

    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal copies, Publishing::Version.of(@page).count
    follow_redirect!
    assert_includes response.body, "Nothing to publish"
    assert_not_includes response.body, "Changes published"
    assert_select "#publishing-chip *", count: 0
  end
end
