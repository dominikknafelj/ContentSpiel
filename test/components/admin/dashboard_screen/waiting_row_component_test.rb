require "test_helper"

# `Admin::DashboardScreen::WaitingRowComponent`: one row of Waiting for you,
# which presses as one (its title link stretched over it) and ends in a verb.
class Admin::DashboardScreen::WaitingRowComponentTest < ViewComponent::TestCase
  setup do
    Current.actor = users(:one)
    users(:two).update!(name: "Dana")
  end
  teardown { Current.reset }

  Row = Dashboard::WaitingForYou::Row
  ThreadRow = Dashboard::OpenThreads::Row

  def editor(record) = Audit::Sentence.route_for(record)

  def thread_of(record, kind:, count: 1, last_author: users(:two), last_author_id: last_author&.id)
    route = editor(record)
    ThreadRow.new(record:, kind:, title: record.title.presence, count:, at: 2.hours.ago, route: route.with(params: route.params.merge(notes: "open")),
      last_author:, last_author_id:)
  end

  def unpublished_row(record, publisher:)
    Row.new(reasons: [ :unpublished ].freeze, at: 1.hour.ago, record:, thread: nil, unpublished_at: 1.hour.ago, route: editor(record),
      review_route: (editor(record).with(params: { review: "publish" }) if publisher))
  end

  def both_row(record, publisher:, count: 2)
    thread = thread_of(record, kind: "page", count:)
    Row.new(reasons: [ :thread, :unpublished ].freeze, at: 1.hour.ago, record:, thread:, unpublished_at: 1.hour.ago, route: thread.route,
      review_route: (editor(record).with(params: { review: "publish" }) if publisher))
  end

  def thread_row(record, kind:, **options)
    thread = thread_of(record, kind:, **options)
    Row.new(reasons: [ :thread ].freeze, at: thread.at, record:, thread:, unpublished_at: nil, route: thread.route, review_route: nil)
  end

  test "a publisher's unpublished row ends in Review and publish…, a second link to the editor with review=publish" do
    page = create_page(title: "Pricing")

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: unpublished_row(page, publisher: true))

    assert_selector "div.admin-waiting-row[data-waiting-row=page]" do
      assert_selector "a.admin-waiting-row__link[href='/cs-studio/pages/#{page.id}'][data-turbo-frame=_top]", text: "Pricing"
      assert_no_selector "a.admin-waiting-row__link[aria-describedby]"
      assert_selector "[data-unpublished-changes]", text: "Unpublished changes"
      assert_selector "a[href='/cs-studio/pages/#{page.id}?review=publish'][data-turbo-frame=_top].relative[class~='z-(--cs-z-raised)']", exact_text: "Review and publish…"
      assert_selector "a", count: 2
      assert_no_selector ".admin-notes-marker"
      assert_no_selector ".admin-row-verb"
    end
    assert_includes self.page.find("a[href*='review=publish']")[:class], Admin::Ui::ButtonComponent.classes(:secondary, size: :small)
  end

  test "a discussed and unpublished row shows the count and the chip, and ends in Review and publish… for a publisher and Open thread for anyone else" do
    page = create_page(title: "Pricing")

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: both_row(page, publisher: true))
    assert_selector ".admin-notes-marker.admin-notes-marker--readonly[role=img][aria-label='2 open notes']", text: "2"
    assert_selector "[data-unpublished-changes]"
    assert_selector "a", exact_text: "Review and publish…"
    assert_no_selector ".admin-row-verb"
    places = [ "admin-notes-marker", "data-unpublished-changes", "review=publish" ].map { |text| rendered_content.index(text) }
    assert_equal places.sort, places, "the pill, then the chip, then the verb"

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: both_row(page, publisher: false))
    verb = "waiting-row-page-#{page.id}-verb"
    assert_selector ".admin-notes-marker", text: "2"
    assert_selector "[data-unpublished-changes]"
    assert_selector "span.admin-row-verb##{verb}", exact_text: "Open thread"
    assert_selector "a.admin-waiting-row__link[href='/cs-studio/pages/#{page.id}?notes=open'][aria-describedby=#{verb}]", text: "Pricing"
    assert_selector "a", count: 1
    assert_no_text "Review and publish…"
  end

  # Each is read once (`OneLink`): the link is named by its title and the
  # reasons and described by the verb, and the marks beside it are hidden.
  test "a row's link is named by its title and its reasons and described by its verb, which are hidden beside it" do
    page = create_page(title: "Pricing")
    link = "waiting-row-page-#{page.id}"

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: both_row(page, publisher: false))
    assert_selector "a##{link}[aria-labelledby='#{link} #{link}-count #{link}-unpublished'][aria-describedby=#{link}-verb]"
    assert_selector "##{link}-count[aria-hidden=true][aria-label='2 open notes']"
    assert_selector "##{link}-unpublished[aria-hidden=true] [data-unpublished-changes]"
    assert_selector "##{link}-verb.admin-row-verb[aria-hidden=true]", exact_text: "Open thread"

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: both_row(page, publisher: true))
    assert_selector "a##{link}[aria-labelledby='#{link} #{link}-count #{link}-unpublished']:not([aria-describedby])"
    assert_no_selector "a[href*='review=publish'][aria-hidden]"
  end

  test "an unpublished row the viewer may not publish ends in Open, describing its title link" do
    post = create_post(title: "Hello")

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: unpublished_row(post, publisher: false))

    verb = "waiting-row-post-#{post.id}-verb"
    assert_selector "span.admin-row-verb##{verb}", exact_text: "Open"
    assert_selector "a.admin-waiting-row__link[href='/cs-studio/posts/#{post.id}'][aria-describedby=#{verb}]", text: "Hello"
    assert_selector "a", count: 1
    assert_selector "[data-unpublished-changes]"
    assert_no_selector ".admin-notes-marker"
    assert_no_text "Review and publish…"
  end

  test "a thread row ends in Open thread and names who wrote last" do
    page = create_page(title: "Pricing")
    post = create_post(title: "Hello")
    asset = create_media_asset

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: thread_row(page, kind: "page"))
    assert_selector "span.admin-row-verb", exact_text: "Open thread"
    assert_selector ".admin-notes-marker[aria-label='1 open note']", text: "1"
    assert_selector "[data-type-marker=square][class~='bg-meta'][class~='size-1.5'][aria-hidden=true]", count: 1
    assert_text(/Page · Dana · /)
    assert_selector "time"
    assert_no_selector "[data-unpublished-changes]"

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: thread_row(post, kind: "post"))
    assert_selector "[data-type-marker=round][class~='rounded-full'][class*='cat-']", count: 1
    assert_text(/#{ContentTypes.find(post.content_type).label} · Dana · /)

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: thread_row(asset, kind: "media", last_author: nil, last_author_id: 999_999))
    assert_selector "[data-type-marker=square]"
    assert_text(/Image · a deleted user · /)
    assert_selector "a.admin-waiting-row__link[href='/cs-studio/media?notes=open&selected=#{asset.id}']"

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: thread_row(page, kind: "page", last_author: nil, last_author_id: nil))
    assert_text(/Page · \d/)
    assert_no_text "System"
    assert_no_text "deleted"
  end

  test "a row with no title reads (untitled)" do
    page = create_page(title: "x")
    page.update_columns(title: {})

    render_inline Admin::DashboardScreen::WaitingRowComponent.new(row: unpublished_row(page.reload, publisher: false))
    assert_selector "a.admin-waiting-row__link", exact_text: "(untitled)"
  end
end
