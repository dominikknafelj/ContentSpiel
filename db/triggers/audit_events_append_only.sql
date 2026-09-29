-- The audit log is append-only (access-control design spec §4.1), enforced
-- here as well as in `Audit::Event` so a raw SQL statement, a console
-- `update_all`/`delete_all`, or a future model bug can't rewrite history.
--
-- The one permitted UPDATE is coalescing (spec §4.2): an `*.updated` or
-- `access.denied` event is extended in place, which only ever touches
-- `field_changes`, `snapshot` and `last_occurred_at`. Rather than listing
-- the frozen columns (and forgetting one added later), the check compares
-- the whole row as jsonb minus those three -- any other column that differs
-- between OLD and NEW, including one that doesn't exist yet, is refused.
--
-- Idempotent (CREATE OR REPLACE / DROP IF EXISTS) because it is applied
-- both by the migration that created the table and after every schema
-- load (config/initializers/db_triggers.rb) -- `db/schema.rb` can't carry
-- triggers, so a database built from it would otherwise have none.
CREATE OR REPLACE FUNCTION audit_events_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'audit_events is append-only: DELETE is not allowed';
  END IF;

  IF (to_jsonb(OLD) - 'field_changes' - 'snapshot' - 'last_occurred_at')
       IS DISTINCT FROM
     (to_jsonb(NEW) - 'field_changes' - 'snapshot' - 'last_occurred_at') THEN
    RAISE EXCEPTION 'audit_events is append-only: only field_changes, snapshot and last_occurred_at may change';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS audit_events_append_only ON audit_events;

CREATE TRIGGER audit_events_append_only
  BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH ROW EXECUTE FUNCTION audit_events_append_only();
