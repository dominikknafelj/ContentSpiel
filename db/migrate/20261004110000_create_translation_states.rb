# One row per (page | post | image | the site settings row, target language):
# where it stands in that language -- `complete`, `missing` or `outdated` --
# and how many fields stand behind it. Derived data, like `public_paths` and
# `media_usages`: the save services keep it current
# (`Translations::StateIndex.refresh`), never written by hand, so the
# translations overview and the lists can `WHERE`/`COUNT` on it instead of
# computing every record's state in Ruby.
#
# No foreign key: `record` is polymorphic, so `Trash::Purge` removes a
# record's rows itself.
#
# `up` fills the table from what exists by calling application code
# (`StateIndex.rebuild_all`). On a database built by `db:schema:load` the
# table starts empty and is filled by saves instead; `bin/rails
# translations:reindex` is the repair tool for that, and for any time the
# table is suspected stale.
class CreateTranslationStates < ActiveRecord::Migration[8.1]
  def up
    create_table :translation_states do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :locale, null: false
      t.string :state, null: false
      t.integer :missing_count, null: false, default: 0
      t.integer :outdated_count, null: false, default: 0
      t.timestamps
    end
    add_index :translation_states, %i[record_type record_id locale], unique: true, name: "index_translation_states_on_record_and_locale"
    add_index :translation_states, %i[locale state]

    Translations::State.reset_column_information
    Translations::StateIndex.rebuild_all
  end

  def down
    drop_table :translation_states
  end
end
