# Search 2 (spec §6.3). `pg_trgm` is a requirement of ContentSpiel's
# (docs/reference/hosting.md, "Database requirements"): where it cannot be
# enabled, or the character type makes it blind to letters outside ASCII,
# the migration stops with `SiteSearch::Postgres::DatabaseRequirementMissing`
# before it writes anything. `search_entries.title` holds `""` for the old
# entries until the build rewrites them; `search_words` starts empty, filled
# by the build. No row is written here.
class SearchTwo < ActiveRecord::Migration[8.1]
  def up
    SiteSearch::Postgres::Requirements.enable!(connection)

    add_column :search_entries, :title, :text, null: false, default: ""
    add_index :search_entries, "to_tsvector('simple'::regconfig, title)", using: :gin, name: "index_search_entries_on_title_words"

    create_table :search_words do |t|
      t.string :locale, null: false
      t.string :word, null: false
    end
    add_index :search_words, [ :locale, :word ], unique: true
    add_index :search_words, :word, using: :gin, opclass: :gin_trgm_ops, name: "index_search_words_on_word_trigrams"
  end

  # The extension stays: other code of a host's may use it.
  def down
    drop_table :search_words
    remove_index :search_entries, name: "index_search_entries_on_title_words"
    remove_column :search_entries, :title
  end
end
