# Where a form's submissions go (plan decision 1): one row per destination of
# a form, in its order. `kind` names a `Forms::DestinationTypes` entry (mail
# built in, a gem's `owner/name`); `settings` are its fields' values;
# `secrets` holds the type's secrets, each sealed on its own with Active
# Record encryption (`Forms::Destination#write_secrets!`), so whether one is
# set is read without decrypting anything, and `secrets_saved_at` is when one
# was last written. The rows go with their form (cascade): a purge deletes
# them with it.
class CreateFormDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :form_destinations do |t|
      t.references :form, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.text :secrets
      t.datetime :secrets_saved_at
      t.timestamps
    end
  end
end
