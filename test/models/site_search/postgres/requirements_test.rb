require "test_helper"
require Rails.root.join("db/migrate/20261115120000_search_two.rb").to_s

# ContentSpiel's database requirements (search 2 spec §3.1, docs/reference/hosting.md,
# "Database requirements"): `pg_trgm` and a UTF-8 character type, held at the
# migration, at a schema load and at a serving boot, all with one message.
# The refusals are stubbed at the connection or the probe: a test database
# that meets the requirements is never broken to see them.
class SiteSearch::Postgres::RequirementsTest < ActiveSupport::TestCase
  include LogCapture

  Requirements = SiteSearch::Postgres::Requirements

  test "db/schema.rb enables pg_trgm and carries the trigram index" do
    schema = Rails.root.join("db/schema.rb").read
    assert_includes schema, %(enable_extension "pg_trgm")
    assert_match(/index_search_words_on_word_trigrams.*gin_trgm_ops/m, schema)
    assert_includes schema, "index_search_entries_on_title_words"
  end

  test "the test database meets the requirements" do
    assert Requirements.installed?(ActiveRecord::Base.connection)
    assert Requirements.probe(ActiveRecord::Base.connection)
    assert_nil Requirements.check!
  end

  test "the migration refused the extension stops with the message naming the requirement and the docs section" do
    error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) do
      with_enable_extension_raising(driver_error(PG::InsufficientPrivilege, "permission denied to create extension")) { run_search_two_up }
    end
    assert_includes error.message, "ContentSpiel requires the Postgres extension pg_trgm and a UTF-8 character type"
    assert_includes error.message, %(docs/reference/hosting.md, "Database requirements")
    assert_includes error.message, "pg_trgm is missing: PG::InsufficientPrivilege."
    assert_includes error.message, "a superuser runs CREATE EXTENSION pg_trgm first"
    refute_includes error.message, "permission denied" # the cause is the driver's class, never the server's text
  end

  test "a server without the contrib package is named by the driver's class" do
    error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) do
      with_enable_extension_raising(driver_error(PG::FeatureNotSupported, %(extension "pg_trgm" is not available))) { run_search_two_up }
    end
    assert_includes error.message, "pg_trgm is missing: PG::FeatureNotSupported."
  end

  test "a cancelled statement or a lock wait at enable_extension is raised as itself" do
    [ ActiveRecord::QueryCanceled, ActiveRecord::LockWaitTimeout ].each do |error_class|
      error = error_class.new("canceling statement due to statement timeout")
      assert_raises(error_class) { with_enable_extension_raising(error) { run_search_two_up } }
    end
  end

  test "a schema load whose enable_extension fails says the same" do
    error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { load_schema_with_extension_error(%(extension "pg_trgm" is not available)) }
    assert_includes error.message, "Database requirements"
    assert_includes error.message, "pg_trgm is missing: PG::FeatureNotSupported."
  end

  test "a schema load error that does not name pg_trgm is raised as it is" do
    error = assert_raises(ActiveRecord::StatementInvalid) { load_schema_with_extension_error(%(relation "pages" already exists)) }
    assert_includes error.message, "pages"
  end

  test "a schema load that names pg_trgm but failed for another reason is raised as it is" do
    assert_raises(ActiveRecord::QueryCanceled) do
      schema_loader { raise ActiveRecord::QueryCanceled, %(canceling statement: CREATE EXTENSION "pg_trgm") }.load_schema(primary)
    end
  end

  test "a schema load on a C character type stops after the load" do
    with_probe_false do
      error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { load_schema_that_succeeds }
      assert_includes error.message, "a UTF-8 character type is missing: pg_trgm cannot read letters outside ASCII"
    end
  end

  test "a schema load that leaves the extension out blames the schema, not the host" do
    without_extension_row do
      error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { load_schema_that_succeeds }
      assert_includes error.message, "pg_trgm is missing: db/schema.rb did not enable it (run bin/rails db:migrate)."
    end
  end

  test "a C character type stops the migration and the boot" do
    with_probe_false do
      assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { run_search_two_up }
      error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { Requirements.check! }
      assert_includes error.message, "pg_trgm cannot read letters outside ASCII in this database's character type"
      error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { boot_check(serving: true) }
      assert_includes error.message, "pg_trgm cannot read letters outside ASCII in this database's character type"
      assert_includes error.message, "create the database with a UTF-8 LC_CTYPE (or an ICU locale) and restore into it"
      refute_includes error.message, "CREATE EXTENSION", "no extension gives a database a character type"
    end
  end

  test "a serving boot without the extension stops with the message, a console and a rake task do not, and a pending migration skips the check" do
    without_extension_row do
      error = assert_raises(SiteSearch::Postgres::DatabaseRequirementMissing) { boot_check(serving: true) }
      assert_includes error.message, "pg_trgm is missing: it is not installed in this database."
      assert_nil boot_check(serving: false)
    end
    with_singleton_override(SiteSearch::Word, :table_exists?, ->(*) { false }) { assert_nil boot_check(serving: true) }
  end

  test "a serving boot whose database does not answer is not stopped by the check, and says so by the error's class" do
    unreachable = ->(*) { raise ActiveRecord::ConnectionNotEstablished, "connection to server at 10.0.0.5 failed" }
    logged = capture_log do
      with_singleton_override(SiteSearch::Word, :table_exists?, unreachable) { assert_nil boot_check(serving: true) }
    end
    assert_includes logged, "ActiveRecord::ConnectionNotEstablished"
    refute_includes logged, "10.0.0.5"
  end

  test "the message names hosting.md's Database requirements" do
    assert_includes Requirements.message_for(missing: "pg_trgm", cause: "X"), "\"#{Requirements::DOCS_HEADING}\""
  end

  private
    def with_enable_extension_raising(error, &block)
      with_singleton_override(ActiveRecord::Base.connection, :enable_extension, ->(*) { raise error }, &block)
    end

    def run_search_two_up
      ActiveRecord::Base.transaction(requires_new: true) do
        SearchTwo.new.exec_migration(ActiveRecord::Base.connection, :up)
        raise ActiveRecord::Rollback
      end
    end

    def load_schema_with_extension_error(message)
      error = driver_error(PG::FeatureNotSupported, message)
      schema_loader { raise error }.load_schema(primary)
    end

    # What Active Record raises for a driver's error: a `StatementInvalid`
    # whose cause is the `PG::` class.
    def driver_error(driver_class, message)
      raise driver_class, message
    rescue driver_class
      begin
        raise ActiveRecord::StatementInvalid, "#{driver_class}: ERROR:  #{message}"
      rescue ActiveRecord::StatementInvalid => error
        error
      end
    end

    def load_schema_that_succeeds
      ActiveRecord::Base.transaction(requires_new: true) do
        schema_loader { nil }.load_schema(primary)
        raise ActiveRecord::Rollback
      end
    end

    # `DbTriggers::AfterSchemaLoad` over a stand-in for `DatabaseTasks`,
    # whose own `load_schema` is the block.
    def schema_loader(&super_body)
      Class.new do
        define_method(:load_schema) { |*| super_body.call }
        define_method(:migration_connection_pool) { ActiveRecord::Base.connection_pool }
        prepend DbTriggers::AfterSchemaLoad
      end.new
    end

    def primary = Struct.new(:name).new("primary")

    def without_extension_row(&block) = with_singleton_override(Requirements, :installed?, ->(*) { false }, &block)

    def with_probe_false(&block) = with_singleton_override(Requirements, :probe, ->(*) { false }, &block)

    def boot_check(serving:) = Requirements.check_at_boot(serving: serving)
end
