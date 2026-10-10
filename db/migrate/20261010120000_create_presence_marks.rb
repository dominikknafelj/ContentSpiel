# Who has a record open, one row per person, record and browser tab (presence
# spec §5.3). A throwaway table: a row lives while its tab keeps it fresh
# (`seen_at`), is ignored by every read after `Presence::STALE_AFTER` and deleted by
# `Presence::Sweep` after 5 minutes. No timestamps: `seen_at` and `arrived_at`
# are its only clocks. `record` is polymorphic with no foreign key (a record
# of any kind), so a trashed or purged record's rows expire by themselves.
class CreatePresenceMarks < ActiveRecord::Migration[8.1]
  def change
    create_table :presence_marks do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :tab, null: false
      # Whose row this is: a fresh random value per SUBSCRIPTION, replaced by
      # a newer subscription of the same tab, so a late `leave` of an older
      # one (a dropped connection noticed after the tab reconnected) finds
      # another token and deletes nothing.
      t.string :token, null: false
      t.string :state, null: false, default: "here"
      t.datetime :seen_at, null: false
      t.datetime :arrived_at, null: false
      # When `state` last changed (and when the row was made): what "away for
      # 12 minutes" is counted from. A keep-alive never moves it.
      t.datetime :state_at, null: false

      t.index %i[user_id record_type record_id tab], unique: true, name: "index_presence_marks_on_user_record_tab"
      t.index %i[record_type record_id seen_at], name: "index_presence_marks_on_record_and_seen_at"
      t.check_constraint "state IN ('here','away')", name: "presence_marks_state_known"
    end
  end
end
