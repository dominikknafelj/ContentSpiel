class CreatePublicPaths < ActiveRecord::Migration[8.1]
  def change
    create_table :public_paths do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :locale, null: false
      t.string :path, null: false
      t.boolean :current, null: false, default: true
      t.timestamps
    end
    add_index :public_paths, [ :locale, :path ], unique: true
    add_index :public_paths, [ :record_type, :record_id, :locale ], unique: true, where: "current",
      name: "index_public_paths_one_current_per_record_locale"
    add_index :public_paths, [ :record_type, :record_id ]

    remove_index :pages, name: "index_pages_on_cached_path_de"
    remove_index :pages, name: "index_pages_on_cached_path_en"
    remove_index :pages, name: "index_pages_on_cached_path_es"
    remove_index :pages, name: "index_pages_on_parent_id_and_slug_de"
    remove_index :pages, name: "index_pages_on_parent_id_and_slug_en"
    remove_index :pages, name: "index_pages_on_parent_id_and_slug_es"
    remove_column :pages, :cached_paths, :jsonb, default: {}, null: false
  end
end
