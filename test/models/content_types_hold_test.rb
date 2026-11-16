require "test_helper"

# `ContentTypes.hold!` sends its `FOR SHARE` once per transaction: again only
# where the transaction that took it is no longer open (a savepoint rolled
# back, which released the lock in Postgres, or one released, whose parent
# holds the lock already and takes it once more), and never so that Active
# Record "restarts" the holder and drops the lock.
class ContentTypesHoldTest < ActiveSupport::TestCase
  def statements
    heard = []
    listener = ->(*, payload) { heard << payload[:sql] }
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { yield }
    heard
  end

  def holds(sql) = sql.grep(/FROM "site_settings".*FOR SHARE/m).size

  setup { Current.site }

  test "a second hold in the same transaction, or in a savepoint of it, sends nothing" do
    sql = statements do
      Page.transaction(requires_new: true) do
        ContentTypes.hold!
        ContentTypes.hold!
        Page.transaction(requires_new: true) { ContentTypes.hold! }
      end
    end
    assert_equal 1, holds(sql)
  end

  test "a hold in a savepoint rolled back is taken again by its parent" do
    sql = statements do
      Page.transaction(requires_new: true) do
        Page.transaction(requires_new: true) do
          ContentTypes.hold!
          raise ActiveRecord::Rollback
        end
        ContentTypes.hold!
      end
    end
    assert_equal 2, holds(sql)
  end

  test "each transaction takes its own hold, and none is kept outside one" do
    sql = statements do
      2.times { Page.transaction(requires_new: true) { ContentTypes.hold! } }
      ContentTypes.hold!
      ContentTypes.hold!
    end
    assert_equal 4, holds(sql)
  end

  test "a nested transaction rolled back never restarts the holder, which would drop its lock" do
    sql = statements do
      Page.transaction(requires_new: true) do
        ContentTypes.hold!
        Page.transaction(requires_new: true) do
          Page.where(id: 0).pick(:id)
          raise ActiveRecord::Rollback
        end
        ContentTypes.hold!
      end
    end
    assert_equal 1, holds(sql)
    assert sql.any? { |s| s.start_with?("ROLLBACK TO SAVEPOINT active_record_2") }, sql.inspect
    assert sql.none? { |s| s.start_with?("ROLLBACK TO SAVEPOINT active_record_1") }, "the holder's savepoint was rolled back: #{sql.inspect}"
  end

  test "a row written since the request read it is read again" do
    Current.site
    SiteSetting.where(id: Current.site.id).update_all(form_keep_days: 17, updated_at: 1.minute.from_now) # changes: none (a test's own row, rolled back)
    Page.transaction(requires_new: true) { ContentTypes.hold! }
    assert_equal 17, Current.site.form_keep_days
  end
end
