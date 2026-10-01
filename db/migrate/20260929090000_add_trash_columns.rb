# Trash (spec §3.1): soft-delete columns on the three trashable tables plus
# the retention setting. `trash_root_id` marks which page an editor actually
# trashed -- every page that went with it carries the same id, which is what
# `Trash::Restore` brings back together. Both user/page references nullify
# rather than restrict: deleting a user or purging a branch root must never be
# blocked by a trash bookkeeping column.
class AddTrashColumns < ActiveRecord::Migration[8.1]
  def change
    %i[pages posts media_assets].each do |table|
      add_column table, :trashed_at, :datetime
      add_index table, :trashed_at
      add_reference table, :trashed_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
    end
    add_reference :pages, :trash_root, foreign_key: { to_table: :pages, on_delete: :nullify }, index: true
    add_column :site_settings, :trash_retention_days, :integer, null: false, default: 30
  end
end
