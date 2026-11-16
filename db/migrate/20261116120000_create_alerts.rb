# Alerts: one row per error or security finding, written by jobs alone
# (docs/superpowers/specs/2026-11-16-alerting-design.md, section 1).
class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.string :kind, null: false
      t.string :fingerprint, null: false
      t.jsonb :details, null: false, default: {}
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :mailed_at
      t.timestamps
    end

    add_index :alerts, :fingerprint, unique: true
    add_index :alerts, :last_seen_at
  end
end
