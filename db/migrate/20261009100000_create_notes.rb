# Notes on content (notes spec §3.1): a thread on a page, a post, a block or a
# library image, its messages, and one delivery row per person told about a
# message (the inbox). `subject` and `container` are polymorphic, so they have
# no foreign key: `Notes::Remove` deletes a record's threads when the record is
# deleted for good. `container` is the record whose screen lists the thread --
# the page for a block -- so one indexed read serves a page's whole drawer.
# The user references are nullified with the user (a note outlives its author,
# shown as "a deleted user"); a delivery belongs to its reader and goes with
# them, and so does a follow (`note_follows`: `following: false` is an
# explicit unfollow, no row means never involved, decision D17). Reactions get
# their own table in a later migration.
class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :note_threads do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :container_type, null: false
      t.bigint :container_id, null: false
      t.string :state, null: false, default: "open"
      t.datetime :resolved_at
      t.references :resolved_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.boolean :pinned, null: false, default: false
      t.datetime :pinned_at
      t.references :pinned_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :quote
      t.string :origin_view, null: false, default: "editor"
      t.string :origin_locale
      t.references :created_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :last_message_at, null: false
      t.timestamps

      t.index %i[container_type container_id state]
      t.index %i[subject_type subject_id]
      t.check_constraint "state IN ('open', 'resolved')", name: "note_threads_state"
    end

    create_table :note_messages do |t|
      t.references :thread, null: false, foreign_key: { to_table: :note_threads, on_delete: :cascade }
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :body, null: false
      t.bigint :mentioned_user_ids, array: true, null: false, default: []
      t.datetime :edited_at
      t.timestamps
    end

    create_table :note_deliveries do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { to_table: :note_messages, on_delete: :cascade }
      t.references :thread, null: false, foreign_key: { to_table: :note_threads, on_delete: :cascade }
      t.string :reason, null: false
      t.datetime :read_at
      t.timestamps

      t.index %i[user_id message_id], unique: true
      t.index %i[user_id read_at]
    end

    create_table :note_follows do |t|
      t.references :thread, null: false, index: false, foreign_key: { to_table: :note_threads, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :following, null: false, default: true
      t.timestamps

      t.index %i[thread_id user_id], unique: true
    end
  end
end
