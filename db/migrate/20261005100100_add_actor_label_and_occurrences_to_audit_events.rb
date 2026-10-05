# `actor_label`: the acting API token's name, written once when the event is
# recorded (round 3 decision D1), so "via <name>" survives the token row
# being deleted with its group or user. `occurrences`: how many saves a
# coalesced event stands for (D22).
#
# The append-only trigger's list of changeable columns gains `occurrences`,
# so the trigger file is re-applied here (and after every schema load, by
# config/initializers/db_triggers.rb).
class AddActorLabelAndOccurrencesToAuditEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :audit_events, :actor_label, :string
    add_column :audit_events, :occurrences, :integer, null: false, default: 1

    say "re-applying the audit_events_append_only trigger"
    suppress_messages { execute Rails.root.join("db/triggers/audit_events_append_only.sql").read }
  end

  def down
    remove_column :audit_events, :occurrences
    remove_column :audit_events, :actor_label
  end
end
