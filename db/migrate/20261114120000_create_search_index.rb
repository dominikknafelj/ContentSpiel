# The built-in search backend's index (search spec §6.1, §6.6). `search_entries`
# is derived, like `public_paths`: one row per published copy and language,
# written only by `SiteSearch::Postgres`, its copy's delete taking it along
# (`ON DELETE CASCADE`: nothing ever refuses a copy's delete for its
# entries). `search_index_states` is one row per backend, the background
# build's. Both start empty: the documents are made by application code a
# migration cannot freeze, and the first boot's check builds them.
class CreateSearchIndex < ActiveRecord::Migration[8.1]
  def change
    create_table :search_entries do |t|
      t.references :published_version, null: false, foreign_key: { on_delete: :cascade }
      t.string   :record_type, null: false
      t.bigint   :record_id, null: false
      t.string   :locale, null: false
      t.string   :config, null: false
      t.datetime :live_at, null: false
      t.tsvector :document, null: false
      t.text     :text, null: false
      t.datetime :created_at, null: false
    end
    add_index :search_entries, [ :published_version_id, :locale ], unique: true
    add_index :search_entries, [ :record_type, :record_id, :locale, :live_at ]
    add_index :search_entries, :document, using: :gin

    create_table :search_index_states do |t|
      t.string :backend, null: false, index: { unique: true }
      t.string :fingerprint
      t.string :status, null: false
      t.integer :done, null: false, default: 0
      t.integer :total, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
    end
  end
end
