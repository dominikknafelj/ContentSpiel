require "test_helper"

class Publishing::HistoryTest < ActiveSupport::TestCase
  def history(record, **options) = Publishing::History.new(record.reload, **options)

  def publish_again(page, title)
    assert Pages::Save.call(page, attributes: {}, translations: { "en" => { title: title } }).ok?
    Publishing::Version.take!(page.reload, by: users(:one)) # version: none (a test takes a copy)
  end

  test "versions are listed newest first with the copy in force on the site" do
    page = create_page(title: "About")
    publish_again(page, "About us")
    rows = history(page).rows

    assert_equal rows.map(&:number).sort.reverse, rows.map(&:number)
    assert_operator rows.size, :>=, 2
    assert_equal :on_site, rows.first.state
    assert_equal [ :earlier ], rows.drop(1).map(&:state).uniq
    assert_not rows.first.was_scheduled
  end

  test "a pending copy is scheduled" do
    page = create_page(title: "About")
    pending = Publishing::Version.take!(page.reload, live_at: 2.days.from_now) # version: none (a test takes a copy)
    rows = history(page).rows

    assert_equal pending.number, rows.first.number
    assert_equal :scheduled, rows.first.state
    assert rows.first.was_scheduled
    assert_equal :on_site, rows.second.state
  end

  test "a scheduled record's copy in force is scheduled, not on the site" do
    page = create_page(title: "Later")
    page.update_columns(published_at: 2.days.from_now) # version: none (a test schedules a page) # changes: none (a test schedules a page)

    assert_equal [ :scheduled ], history(page).rows.map(&:state).uniq
  end

  test "a first copy with no publisher has none" do
    page = create_page(title: "About")
    Publishing::Version.of(page).update_all(created_by_id: nil) # version: none (a test) # changes: none (a test)

    assert_nil history(page).rows.last.publisher
  end

  test "the list reads no content column" do
    page = create_page(title: "About")
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] if payload[:sql].include?("published_versions") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { history(page).rows }

    assert sql.any?
    sql.each { |statement| assert_no_match(/snapshot|blocks/, statement) }
  end

  test "the working version is the same as the copy in force when nothing differs" do
    page = create_page(title: "About")
    working = history(page).working

    assert_equal Publishing.current(page).number, working.same_as
    assert_equal page.reload.updated_at, working.saved_at

    assert Pages::Save.call(page, attributes: {}, translations: { "en" => { title: "Changed" } }).ok?
    changed = history(page).working
    assert changed.changes
    assert_nil changed.same_as
  end

  test "51 copies make two pages" do
    page = create_page(title: "About")
    50.times { Publishing::Version.take!(page.reload) } # version: none (a test takes copies)
    first = history(page)
    second = history(page, page: 2)

    assert_equal 2, first.pagination.total_pages
    assert_equal 50, first.rows.size
    assert_equal 1, second.rows.size
    assert_equal 1, second.rows.first.number
  end

  test "find reads one whole copy and previous the one before it" do
    page = create_page(title: "About")
    second = publish_again(page, "About us")
    h = history(page)

    assert_equal second.number, h.find(second.number).number
    assert_equal second.number - 1, h.previous(second.number).number
    assert_nil h.previous(1)
    assert_raises(ActiveRecord::RecordNotFound) { h.find(999) }
  end

  test "newest is the copy with the highest number, and numbers are every copy's, newest first" do
    page = create_page(title: "About")
    publish_again(page, "About us")
    third = publish_again(page, "About all of us")
    h = history(page)

    assert_equal third.number, h.newest.number
    assert_equal [ 3, 2, 1 ], h.numbers
    assert_nil history(create_page(title: "Draft", published: false)).newest
  end
end
