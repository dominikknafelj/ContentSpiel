# The media library's folders (docs/reference/media.md): a tree of named
# folders an image sits in, or in none. A folder is never drawn on the site,
# so nothing here touches a published copy.
class CreateMediaFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :media_folders do |t|
      t.string :name, null: false
      t.references :parent, foreign_key: { to_table: :media_folders }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    # One name per parent in any case, and at the top too: nulls_not_distinct
    # makes two top folders (parent_id NULL) collide as two siblings would.
    add_index :media_folders, "parent_id, lower((name)::text)",
      unique: true, nulls_not_distinct: true, name: "index_media_folders_on_parent_and_name"

    # Every existing image starts in no folder. The services move images out of
    # a folder before deleting it; the nullify is the net for a delete around them.
    add_reference :media_assets, :folder, foreign_key: { to_table: :media_folders, on_delete: :nullify }, index: true
  end
end
