# The page settings form's own autosave base (live-editing spec §3.3). Every
# block write touches its page, so `updated_at` moved under someone who was in
# the settings although nobody else had changed them. Filled from `updated_at`
# so that a form open across the deploy is refused once at most.
class AddSettingsChangedAtToPages < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :settings_changed_at, :datetime
    execute "UPDATE pages SET settings_changed_at = updated_at"
    change_column_null :pages, :settings_changed_at, false
  end

  def down
    remove_column :pages, :settings_changed_at
  end
end
