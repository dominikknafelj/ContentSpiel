# Who is changing a block, a page's settings or a post right now (live-editing
# spec §4.1). One row per subject, by the unique index every claim is made on.
# `record` is the page or post whose stream a change of holder is signalled
# on. No foreign key to the subject or the record: a deleted block's row is
# ignored after `Editing::HOLD` and swept. An ordinary table, as presence's
# is (Rails' schema dumper does not record UNLOGGED).
#
# `requested_by_id` is nullified when the requester is deleted; the request is
# then gone, and `requested_tab`/`requested_at` mean nothing without it: every
# reader asks `requested_by_id` first (`Reservation#requested?`) and every
# writer sets or clears the three together.
class CreateEditReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :edit_reservations do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :tab, null: false
      t.datetime :changed_at, null: false
      t.references :requested_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :requested_tab
      t.datetime :requested_at

      t.index %i[subject_type subject_id], unique: true, name: "index_edit_reservations_on_subject"
      t.index %i[record_type record_id], name: "index_edit_reservations_on_record"
    end
  end
end
