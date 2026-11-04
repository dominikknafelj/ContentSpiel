# Forms (docs/superpowers/specs/2026-11-03-forms-design.md; plan decisions 1
# and 3): a form is its own trashable record, with no drafts. Its fields are a
# jsonb list saved whole by one explicit Save (`Forms::Save`), each with a key
# that never changes, so there is no row per field. `submit_label` and
# `thank_you` are Mobility's jsonb columns, translated values that fall back
# to the default language and join no translation state. `keep_days` nil
# follows the site's default (`site_settings.form_keep_days`). The trash
# columns are the posts' own.
class CreateForms < ActiveRecord::Migration[8.1]
  def change
    create_table :forms do |t|
      t.string :name, null: false
      t.jsonb :fields, null: false, default: []
      t.jsonb :submit_label, null: false, default: {}
      t.jsonb :thank_you, null: false, default: {}
      t.boolean :keep_submissions, null: false, default: false
      t.integer :keep_days
      t.datetime :trashed_at, index: true
      t.references :trashed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
  end
end
