# Database triggers that `db/schema.rb` can't carry (access-control design
# spec §4.1: the audit log's append-only trigger). The Ruby schema format
# only knows tables, indexes and foreign keys, so a database built from it
# -- `db:schema:load`, `db:reset`, `db:prepare` on a fresh database,
# `db:test:prepare`, and each parallel test worker's own copy of the test
# database -- would silently come up without them, and the append-only
# guarantee would quietly hold only on databases that happened to be
# migrated step by step.
#
# Rather than enhancing every one of those rake tasks (and separately
# hooking parallel test workers, which never go through rake at all:
# `ActiveRecord::TestDatabases` calls `DatabaseTasks.reconstruct_from_schema`
# directly), this hooks the one method all of them funnel through,
# `DatabaseTasks.load_schema`, and re-applies every trigger right after the
# schema lands, against the same connection pool the schema was loaded
# into. `load_schema` is `:nodoc:` Rails API; if an upgrade renames it, the
# test in test/models/audit/event_test.rb that looks the trigger up in
# `pg_trigger` fails loudly rather than letting this go quiet.
#
# Trigger SQL files are idempotent (CREATE OR REPLACE / DROP IF EXISTS), so
# applying them again after a migration already did is harmless.
# `bin/rails db:triggers:apply` (lib/tasks/db_triggers.rake) re-applies them
# by hand.
module DbTriggers
  # Table => SQL file under db/triggers/. Keyed by table so a schema that
  # predates the table (an older checkout, a partially migrated database)
  # is skipped instead of failing the whole schema load.
  TRIGGERS = { "audit_events" => "audit_events_append_only.sql" }.freeze

  def self.apply!(connection)
    TRIGGERS.each do |table, file|
      next unless connection.table_exists?(table)

      connection.execute(Rails.root.join("db/triggers", file).read)
    end
  end

  module AfterSchemaLoad
    def load_schema(db_config, *)
      super.tap do
        # Only the primary database has these tables; production's
        # cache/queue databases load their own schemas through here too.
        migration_connection_pool.with_connection { |connection| DbTriggers.apply!(connection) } if db_config.name == "primary"
      end
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(DbTriggers::AfterSchemaLoad)
