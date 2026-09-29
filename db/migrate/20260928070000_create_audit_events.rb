# The audit log's table (access-control design spec §4.1). No foreign keys
# on actor, user or subject on purpose: an event must outlive the record it
# describes (a deleted post's `post.deleted` event, a deleted user's history)
# -- `subject_label` keeps it readable afterwards.
#
# The append-only trigger is created from db/triggers/audit_events_append_only.sql
# rather than inline, so this migration and the post-schema-load hook
# (config/initializers/db_triggers.rb) share one definition. `db/schema.rb`
# won't show it -- see that initializer for how schema-loaded databases get it.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :audit_events do |t|
      t.string :action, null: false
      t.references :actor, polymorphic: true, index: false
      t.bigint :user_id
      t.string :channel
      t.references :subject, polymorphic: true, index: false
      t.string :subject_label
      t.jsonb :field_changes, default: {}, null: false
      t.jsonb :snapshot
      t.jsonb :metadata, default: {}, null: false
      t.string :request_id
      t.string :ip
      t.datetime :occurred_at, null: false
      t.datetime :last_occurred_at, null: false
    end

    add_index :audit_events, [ :subject_type, :subject_id, :occurred_at ]
    add_index :audit_events, [ :user_id, :occurred_at ]
    add_index :audit_events, [ :action, :occurred_at ]

    say "creating the audit_events_append_only trigger"
    suppress_messages { execute Rails.root.join("db/triggers/audit_events_append_only.sql").read }
  end

  def down
    execute "DROP TRIGGER IF EXISTS audit_events_append_only ON audit_events"
    execute "DROP FUNCTION IF EXISTS audit_events_append_only()"
    drop_table :audit_events
  end
end
