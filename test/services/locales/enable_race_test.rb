require "test_helper"

# Switching a language on (`Locales::Enable`) beside a write to a page, on two
# connections. Enable takes the settings row `FOR UPDATE` and then writes
# every page and post row (their blank slugs in the new language); a page's
# writer reaches the same settings row `FOR SHARE` (`ContentTypes.hold!`) on
# its way to the page's addresses. One order is safe only if the writer takes
# the settings row before its page's: it then waits for Enable, or Enable
# waits for it, and neither ends in `ActiveRecord::Deadlocked`.
#
# The writer is a real service. The moment it first writes or locks the
# page's row, Enable is started on another connection and waited for until
# Postgres says it is blocked on a lock: behind the page row (the writer
# held it before the settings row: a deadlock follows) or behind the settings
# row (the writer held the settings first: Enable waits for its commit).
#
# Outside the test transaction, like `Settings::SwitchRaceTest`: the rows are
# made through the models and removed in `clean`, the languages are put back,
# and `Audit.record` is replaced, since the log is append-only.
class Locales::EnableRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @locales = SiteSetting.instance.locales
    clean
    root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @page = Page.create!(parent: root, title: "Everything", published_at: 1.day.ago)
    @list = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: {})
    @audit = Audit.method(:record)
    Audit.define_singleton_method(:record) { |*, **| nil }
  end

  teardown do
    Audit.define_singleton_method(:record, @audit) if @audit
    clean
    SiteSetting.instance.update_columns(locales: @locales) # changes: none (a test's own languages put back)
    Current.reset
  end

  def clean
    Post.find_each { |post| post.published_versions.delete_all } # version: none (a test's own rows)
    Post.find_each(&:destroy)
    Page.find_each { |page| page.published_versions.delete_all } # version: none (a test's own rows)
    Page.where.not(parent_id: nil).find_each(&:destroy!)
    Page.where(parent_id: nil).find_each(&:destroy!)
    SiteSearch::Word.delete_all
    Current.reset
  end

  # Runs `write` on this connection; at its first statement that writes or
  # locks the page's row, starts `Locales::Enable` on another and waits until
  # it is blocked on a lock. Answers both results, or the deadlock either one
  # ended in.
  def race(&write)
    thread = nil
    started = ->(*, payload) do
      next if thread || payload[:connection] != ActiveRecord::Base.connection || !touches_page?(payload[:sql])

      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Current.reset
          Locales::Enable.call("fr")
        rescue ActiveRecord::Deadlocked => error
          error
        end
      end
      await_blocked
    end
    mine = ActiveSupport::Notifications.subscribed(started, "sql.active_record") do
      Current.reset
      write.call
    rescue ActiveRecord::Deadlocked => error
      error
    end
    assert thread, "the write never wrote or locked the page's row"
    [ mine, thread.value ]
  ensure
    thread&.join
  end

  def touches_page?(sql) = sql.match?(/\AUPDATE "pages"/) || (sql.include?('FROM "pages"') && sql.include?("FOR UPDATE"))

  def await_blocked
    sql = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()"
    200.times do
      return if Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(sql).to_i.positive? } }.value

      sleep 0.025 # sleep: polling Postgres for Enable to be waiting on the write's lock
    end
    flunk "Locales::Enable never blocked behind the write"
  end

  def assert_both_stand(mine, enabled)
    assert_not_kind_of ActiveRecord::Deadlocked, mine, "the page's write ended in a deadlock"
    assert_not_kind_of ActiveRecord::Deadlocked, enabled, "Locales::Enable ended in a deadlock"
    assert mine.ok?, mine.errors.inspect
    assert enabled.ok?, enabled.errors.inspect
    assert_includes SiteSetting.instance.locale_codes, "fr"
  end

  test "a list block's save and a language switched on, at once, both stand" do
    mine, enabled = race { ContentBlocks::Save.call(ContentBlock.find(@list.id), attributes: { settings: { "limit" => 3 } }) }

    assert_both_stand(mine, enabled)
    assert_equal 3, @list.reload.settings["limit"]
  end

  test "a page's new slug and a language switched on, at once, both stand" do
    mine, enabled = race { Pages::Save.call(Page.find(@page.id), translations: { "en" => { slug: "all-of-it" } }) }

    assert_both_stand(mine, enabled)
    assert_equal "all-of-it", @page.reload.slug
    assert PublicPath.current.where(record: @page, locale: "fr").exists?, "the new language gave the page its address"
  end
end
