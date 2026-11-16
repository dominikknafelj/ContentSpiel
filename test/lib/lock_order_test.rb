require "test_helper"

# `ContentSpiel::LockOrder` read statement by statement: each test hands
# `heard` a sequence of SQL for a stand-in connection, as `sql.active_record`
# would, and says whether the order is refused. The last class runs the real
# connection under development's query log tags.
class LockOrderTest < ActiveSupport::TestCase
  TAG = "/*application='ContentSpiel'*/".freeze

  PAGE_LOCK = 'SELECT "pages"."id" FROM "pages" WHERE "pages"."id" = $1 LIMIT $2 FOR UPDATE'.freeze
  PAGE_UPDATE = 'UPDATE "pages" SET "updated_at" = $1 WHERE "pages"."id" = $2'.freeze
  HOLD = 'SELECT "site_settings"."updated_at" FROM "site_settings" WHERE "site_settings"."id" = $1 LIMIT $2 FOR SHARE'.freeze
  LOCK = 'SELECT "site_settings".* FROM "site_settings" WHERE "site_settings"."id" = $1 LIMIT $2 FOR UPDATE'.freeze
  SETTINGS_UPDATE = 'UPDATE "site_settings" SET "setup_completed_at" = $1 WHERE "site_settings"."id" = $2'.freeze

  setup { @connection = Object.new }

  def send_all(statements)
    statements.each { |sql| ContentSpiel::LockOrder.heard(connection: @connection, sql: sql, name: "SQL") }
  end

  def hear(*statements) = assert_nothing_raised { send_all(statements) }

  def assert_refused(*statements, says: /after a row it comes before/)
    error = assert_raises(ContentSpiel::LockOrder::Violation) { send_all(statements) }
    assert_match says, error.message
  end

  test "the settings row taken after a page's row, in one transaction, is refused" do
    assert_refused "BEGIN", PAGE_LOCK, HOLD
  end

  test "an UPDATE of the settings row after a page's write is refused too" do
    assert_refused "BEGIN", PAGE_UPDATE, SETTINGS_UPDATE
  end

  test "the settings row first, then the page's row, then the settings row again, is free" do
    hear "BEGIN", HOLD, PAGE_LOCK, PAGE_UPDATE, HOLD, "COMMIT"
    hear "BEGIN", LOCK, PAGE_UPDATE, HOLD, SETTINGS_UPDATE, "COMMIT"
  end

  test "a foreign key's KEY SHARE is not a lock of the page" do
    hear "BEGIN", 'SELECT 1 FROM "pages" WHERE "pages"."id" = $1 FOR KEY SHARE', HOLD, "COMMIT"
  end

  test "a tagged COMMIT ends the transaction: an autocommit settings UPDATE after it is its own" do
    hear "BEGIN #{TAG}", "#{PAGE_LOCK} #{TAG}", "COMMIT #{TAG}", "#{SETTINGS_UPDATE} #{TAG}"
  end

  test "a tagged ROLLBACK ends it too, and a prepended tag hides no BEGIN" do
    hear "BEGIN #{TAG}", "#{PAGE_LOCK} #{TAG}", "ROLLBACK #{TAG}", SETTINGS_UPDATE
    assert_refused "#{TAG} BEGIN", "#{TAG} #{PAGE_LOCK}", "#{TAG} #{HOLD}"
  end

  test "a line comment is no statement, and a -- inside a literal is no comment" do
    hear "BEGIN", PAGE_LOCK, "COMMIT -- the end", SETTINGS_UPDATE
    assert_refused "BEGIN", %(UPDATE "pages" SET "title" = '-- x' WHERE "pages"."id" = 1), HOLD
  end

  test "the other ways a transaction ends are heard" do
    [ "END", "ABORT", "COMMIT WORK", "ROLLBACK TRANSACTION", "COMMIT AND NO CHAIN", "PREPARE TRANSACTION 'x'", "COMMIT;" ].each do |ending|
      hear "BEGIN", PAGE_LOCK, ending, SETTINGS_UPDATE
    end
  end

  test "ROLLBACK AND CHAIN ends the transaction and begins the next, which is followed" do
    hear "BEGIN", PAGE_LOCK, "ROLLBACK AND CHAIN #{TAG}", HOLD, PAGE_LOCK
    assert_refused "COMMIT AND CHAIN", PAGE_LOCK, HOLD
  end

  test "a savepoint rolled back takes its write with it" do
    hear "BEGIN", "SAVEPOINT active_record_1", PAGE_LOCK, "ROLLBACK TO SAVEPOINT active_record_1 #{TAG}", HOLD, "COMMIT"
  end

  test "a savepoint released gives its write to its parent" do
    assert_refused "BEGIN", "SAVEPOINT active_record_1", PAGE_LOCK, "RELEASE SAVEPOINT active_record_1 #{TAG}", HOLD
  end

  test "a savepoint released gives its hold to its parent, and one rolled back takes it" do
    hear "BEGIN", "SAVEPOINT active_record_1", HOLD, "RELEASE SAVEPOINT active_record_1", PAGE_LOCK, "COMMIT"
    assert_refused "BEGIN", "SAVEPOINT active_record_1", HOLD, "ROLLBACK TO SAVEPOINT active_record_1", PAGE_LOCK, HOLD
  end

  test "a savepoint name opened again after a rollback goes on in its parent" do
    hear "BEGIN", HOLD, "SAVEPOINT active_record_1", "ROLLBACK TO SAVEPOINT active_record_1", "SAVEPOINT active_record_1",
         PAGE_LOCK, "RELEASE SAVEPOINT active_record_1", HOLD, "COMMIT"
  end

  test "the settings row held FOR SHARE and then updated is refused: two such transactions deadlock" do
    assert_refused "BEGIN", HOLD, PAGE_UPDATE, SETTINGS_UPDATE, says: /held FOR SHARE and then taken for an update/
    assert_refused "BEGIN", HOLD, LOCK, says: /held FOR SHARE/
    assert_refused "BEGIN", "SAVEPOINT active_record_1", HOLD, "RELEASE SAVEPOINT active_record_1", SETTINGS_UPDATE, says: /held FOR SHARE/
  end

  test "a share rolled back with its savepoint is no upgrade" do
    hear "BEGIN", "SAVEPOINT active_record_1", HOLD, "ROLLBACK TO SAVEPOINT active_record_1", LOCK, PAGE_UPDATE, "COMMIT"
  end

  test "aside follows its block as another transaction's, and gives the outer one back" do
    hear "BEGIN", HOLD, PAGE_LOCK
    ContentSpiel::LockOrder.aside(@connection) { assert_refused "BEGIN", PAGE_LOCK, HOLD }
    hear HOLD, "COMMIT"

    hear "BEGIN", PAGE_LOCK
    ContentSpiel::LockOrder.aside(@connection) { hear "BEGIN", HOLD, "COMMIT" }
    assert_refused HOLD
  end

  test "forget drops the open transaction" do
    hear "BEGIN", PAGE_LOCK
    ContentSpiel::LockOrder.forget(@connection)
    hear HOLD
  end
end

# The review's reproduction, on the real connection with development's query
# log tags on: a transaction that locks a page's row (none has id 0, so
# nothing is written) commits, and then, outside any transaction, the
# settings row is updated (as `MailSettings.record_success!` sends). The two
# are separate transactions, so no order is broken.
class LockOrderTaggedTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def with_query_log_tags(prepend: false)
    taggings = ActiveRecord::QueryLogs.taggings
    prepended = ActiveRecord::QueryLogs.prepend_comment
    ActiveRecord::QueryLogs.taggings = taggings.merge(application: "ContentSpiel")
    ActiveRecord::QueryLogs.prepend_comment = prepend
    ActiveRecord::QueryLogs.clear_cache
    ActiveRecord.query_transformers << ActiveRecord::QueryLogs
    yield
  ensure
    ActiveRecord.query_transformers.delete(ActiveRecord::QueryLogs)
    ActiveRecord::QueryLogs.taggings = taggings
    ActiveRecord::QueryLogs.prepend_comment = prepended
    ActiveRecord::QueryLogs.clear_cache
  end

  def tagged_statements
    heard = []
    listener = ->(*, payload) { heard << payload[:sql] }
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { yield }
    heard
  end

  [ false, true ].each do |prepend|
    test "a committed transaction's lock is not the next autocommit statement's (tags #{prepend ? "prepended" : "appended"})" do
      with_query_log_tags(prepend: prepend) do
        heard = tagged_statements do
          Page.transaction { Page.where(id: 0).lock.pick(:id) }
          SiteSetting.where(id: 0).update_all(mail_last_sent_at: Time.current) # changes: none (no row has id 0)
        end
        assert heard.any? { |sql| sql.match?(/\bCOMMIT\b/) && sql.include?("/*application") }, "the COMMIT was not tagged: #{heard.inspect}"
      end
    end

    test "a tagged transaction that takes the settings row last is still refused (tags #{prepend ? "prepended" : "appended"})" do
      with_query_log_tags(prepend: prepend) do
        assert_raises(ContentSpiel::LockOrder::Violation) do
          Page.transaction do
            Page.where(id: 0).lock.pick(:id)
            SiteSetting.where(id: 0).lock("FOR SHARE").pick(:id)
          end
        end
      end
    end
  end
end
