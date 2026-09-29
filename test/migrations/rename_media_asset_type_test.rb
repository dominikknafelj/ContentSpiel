require "test_helper"
require Rails.root.join("db/migrate/20260929010000_rename_media_asset_type").to_s

# Media library Task 1's data migration (that migration's own comment): the
# rename from `MediaAsset` to `Media::Asset` is Ruby-only, but
# `active_storage_attachments.record_type` stores the class name literally,
# so every existing attachment row still needs rewriting or `Active
# Storage::Attachment#record` (which constantizes `record_type`) can no
# longer find its way back to the record. The test database's own rows are
# already `"Media::Asset"` (this migration already ran against it, same as
# `test/migrations/drop_action_text_test.rb`'s own setup comment) -- each
# test below sets up the "before" state by hand and runs the migration
# directly, the same pattern `test/migrations/access_control_seed_test.rb`
# uses.
class RenameMediaAssetTypeMigrationTest < ActiveSupport::TestCase
  test "up renames a legacy MediaAsset attachment to Media::Asset, and the record association resolves" do
    asset = create_media_asset
    attachment = asset.file.attachment
    attachment.update_column(:record_type, "MediaAsset")

    ActiveRecord::Migration.suppress_messages { RenameMediaAssetType.new.migrate(:up) }

    assert_equal "Media::Asset", attachment.reload.record_type
    assert_equal asset, attachment.record
  end

  test "up leaves an attachment for an unrelated record type untouched" do
    page = create_page(title: "Untouched by the media asset rename")
    block = page.content_blocks.create!(block_type: "image", position: 0)
    # A legacy block-image attachment row, as it stood before media library
    # Task 4 moved block images into the library (the model no longer
    # declares `has_one_attached :image`).
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    attachment = ActiveStorage::Attachment.create!(record_type: "ContentBlock", record_id: block.id, name: "image", blob: blob)

    ActiveRecord::Migration.suppress_messages { RenameMediaAssetType.new.migrate(:up) }

    assert_equal "ContentBlock", attachment.reload.record_type
  end

  test "down restores the legacy MediaAsset record_type, reversibly" do
    asset = create_media_asset
    attachment = asset.file.attachment

    ActiveRecord::Migration.suppress_messages { RenameMediaAssetType.new.migrate(:down) }
    assert_equal "MediaAsset", attachment.reload.record_type

    ActiveRecord::Migration.suppress_messages { RenameMediaAssetType.new.migrate(:up) }
    assert_equal "Media::Asset", attachment.reload.record_type
  end
end
