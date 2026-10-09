# An emoji reaction on a note (notes spec D10, §3.1): one row per person,
# message and emoji. Both keys cascade: a reaction goes with its message and
# with its user.
class CreateNoteReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :note_reactions do |t|
      t.references :message, null: false, index: false, foreign_key: { to_table: :note_messages, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :emoji, null: false
      t.timestamps

      t.index %i[message_id user_id emoji], unique: true
    end
  end
end
