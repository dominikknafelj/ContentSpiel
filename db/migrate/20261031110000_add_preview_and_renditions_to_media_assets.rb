# What one decode at upload keeps on the row (`preview`, `has_alpha`, beside
# the existing `width` and `height`), and the generation of widths made for
# the image (`renditions` with the fingerprint of the settings that made it,
# or why it failed). All derived: none is audited as a change. `width` and
# `height` stay nullable, for a row whose decode has not happened yet.
class AddPreviewAndRenditionsToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    change_table :media_assets, bulk: true do |t|
      t.binary :preview
      t.boolean :has_alpha, null: false, default: false
      t.jsonb :renditions, null: false, default: {}
      t.string :renditions_fingerprint
      t.datetime :renditions_failed_at
      t.string :renditions_error
      t.index :renditions_fingerprint
    end
  end
end
