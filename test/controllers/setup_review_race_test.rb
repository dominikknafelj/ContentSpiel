require "test_helper"

# Two submissions of the setup wizard's last step at once
# (`SetupController#update_review`: the homepage made, then the marker that
# ends setup written, in one transaction), on two connections, on a site with
# no pages. The transaction ends by updating the settings row, so it takes
# the row FOR UPDATE first: had it held the row FOR SHARE (`Pages::Save`'s
# `ContentTypes.hold!`) and then updated it, each submission would hold the
# share the other's update waits for, and Postgres would end one with
# `ActiveRecord::Deadlocked` (`ContentSpiel::LockOrder` refuses that upgrade
# too).
#
# The action itself runs on a bare controller. At its first lock of the
# settings row, the second submission is started on another connection and
# waited for until Postgres says it is blocked on a lock; the first then goes
# on and commits, and the second finds the homepage and the marker there.
#
# Outside the test transaction, like `Locales::EnableRaceTest`: the rows are
# made by the action and removed in `clean`, the marker is put back, and
# `Audit.record` is replaced, since the log is append-only.
class SetupReviewRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @completed_at = SiteSetting.instance.setup_completed_at
    @audit = Audit.method(:record)
    Audit.define_singleton_method(:record) { |*, **| nil }
    clean
    SiteSetting.instance.update_columns(setup_completed_at: nil) # changes: none (a test's own marker, put back in teardown)
  end

  teardown do
    Audit.define_singleton_method(:record, @audit) if @audit
    clean
    SiteSetting.instance.update_columns(setup_completed_at: @completed_at) # changes: none (a test's own marker put back)
    Setup.reset!
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

  # The action, as a request runs it; answers where it redirected, or the
  # error it ended in.
  def review
    Current.reset
    controller = SetupController.new
    controller.set_request!(ActionDispatch::TestRequest.create)
    controller.set_response!(ActionDispatch::TestResponse.new)
    controller.send(:update_review)
    controller.response.location
  rescue => error
    error
  end

  def await_blocked
    sql = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()"
    200.times do
      return if Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(sql).to_i.positive? } }.value

      sleep 0.025 # sleep: polling Postgres for the second submission to be waiting on the first's lock
    end
    flunk "the second submission never blocked behind the first"
  end

  test "two submissions of the last step at once both finish, with one homepage" do
    other = nil
    started = ->(*, payload) do
      next if other || payload[:connection] != ActiveRecord::Base.connection || !payload[:sql].match?(/FROM "site_settings".*\bFOR\b/m)

      other = Thread.new { ActiveRecord::Base.connection_pool.with_connection { review } }
      await_blocked
    end
    mine = ActiveSupport::Notifications.subscribed(started, "sql.active_record") { review }
    assert other, "the action never locked the settings row"
    results = [ mine, other.value ]

    results.each do |result|
      assert_not_kind_of Exception, result, (result.full_message(highlight: false) if result.is_a?(Exception))
      assert_match %r{/cs-studio\z}, result
    end
    assert_equal 1, Page.where(parent_id: nil).count
    assert_not_nil SiteSetting.instance.setup_completed_at
  ensure
    other&.join
  end
end
