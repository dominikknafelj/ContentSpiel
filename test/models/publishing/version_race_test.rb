require "test_helper"

# Two connections at once need rows the other connection can see, so this
# class runs outside the test transaction (in the style of
# `Editing::ReservationRaceTest`). Its rows are made through the model and
# removed through it, and nothing else touches them.
class Publishing::VersionRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    clean
    @page = Page.create!(page_type: :standard, title: "Old", slug: "", published_at: 1.day.ago)
  end

  teardown { clean }

  def clean
    Page.find_each { |page| page.published_versions.delete_all } # version: none (a test's own rows)
    Page.where(parent_id: nil).find_each(&:destroy)
  end

  # The order forced: `first` runs in a transaction that stays open; `second`
  # is started on another connection and waited for until Postgres says it is
  # blocked behind the first; then the first commits and the second goes on.
  def behind(first, second)
    thread = nil
    first_answer = Page.transaction do
      answer = first.call
      thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { second.call } }
      await_blocked
      answer
    end
    [ first_answer, thread.value ]
  ensure
    thread&.join
  end

  BLOCKED = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE 'UPDATE \"pages\"%'".freeze

  def blocked? = Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(BLOCKED).to_i.positive? } }.value

  def await_blocked
    200.times do
      return if blocked?

      sleep 0.025 # sleep: polling Postgres for the second statement to be waiting on the first's lock
    end
    flunk "the second statement never blocked behind the first"
  end

  def title_of(page) = Mobility.with_locale(:en) { page.title }

  test "a colleague's save committed between the publisher's load and the copy is in the copy" do
    loaded = Page.find(@page.id)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection { Mobility.with_locale(:en) { Page.find(@page.id).update!(title: "A colleague's") } } }.join

    version = Page.transaction { Publishing::Version.take!(loaded) }

    assert_equal({ "en" => "A colleague's" }, version.snapshot.dig("fields", "title"))
  end

  test "a colleague's save that arrives while the copy is being taken waits for it, and is not in it" do
    version, = behind(
      -> { Publishing::Version.take!(Page.find(@page.id)) },
      -> { Mobility.with_locale(:en) { Page.find(@page.id).update!(title: "Too late") } }
    )

    assert_equal({ "en" => "Old" }, version.snapshot.dig("fields", "title"))
    assert_equal "Too late", title_of(Page.find(@page.id))
  end

  test "a copy that fails after the pending one was replaced leaves the pending one, also when called outside any transaction" do
    pending = Publishing::Version.take!(@page, live_at: 2.days.from_now)
    assert_not Page.connection.transaction_open?

    with_singleton_override(Publishing::Version, :create!, ->(**) { raise ActiveRecord::StatementInvalid, "the insert failed" }) do
      assert_raises(ActiveRecord::StatementInvalid) { Publishing::Version.take!(@page) }
    end

    assert_equal pending, Publishing.pending(@page)
  end

  test "Snapshot.of reads the rows fresh under the query cache, and issues no FOR UPDATE" do
    ActiveRecord::Base.cache do
      assert_empty ContentBlock.where(owner: @page).to_a # the request's own earlier read, now cached
      Page.find(@page.id) # and the row's
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { ContentBlock.create!(owner: @page, block_type: "rich_text", position: 0) } }.join
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { Mobility.with_locale(:en) { Page.find(@page.id).update!(title: "Later") } } }.join

      data = nil
      statements = capture_sql { data = Publishing::Snapshot.of(@page) }

      assert_equal 1, data["blocks"].size
      assert_equal({ "en" => "Later" }, data.dig("fields", "title"))
      assert_empty statements.grep(/FOR UPDATE/i)
    end
  end
end
