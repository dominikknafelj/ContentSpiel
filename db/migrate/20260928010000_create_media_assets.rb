# `media_assets` (design spec §4.2): one row per uploaded image the Tiptap
# editor's own upload button inserts into a rich-text `image` node
# (`asset_id`, `RichText::BuiltIns`). `content_type`/`byte_size` are the
# *sniffed* values `MediaAsset#validate :image_type_and_size` computed at
# save time (never the client's declared Content-Type/filename -- see that
# model's own comment), cached here so a listing or the editor's own upload
# response never has to re-open the blob just to read them back.
# `width`/`height` come from `file.analyze`'s blob metadata and may be nil
# (an analyzer that couldn't run, or hasn't yet) -- there is no NOT NULL on
# either. `created_by_id` is nullable: a `User` for an ordinary CS Studio
# upload, but nothing requires one (a script, a future non-admin uploader).
#
# No `dependent:` cleanup of unreferenced rows yet (global constraints:
# "no automatic cleanup, interim") -- the media library sub-project closes
# this.
class CreateMediaAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :media_assets do |t|
      t.string :content_type
      t.bigint :byte_size
      t.integer :width
      t.integer :height
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :media_assets, :created_by_id
  end
end
