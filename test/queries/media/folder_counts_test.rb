require "test_helper"

class Media::FolderCountsTest < ActiveSupport::TestCase
  test "counts are direct kept images per folder, outside any folder and in all, in one query" do
    parent = Media::Folder.create!(name: "Parent")
    child = Media::Folder.create!(name: "Child", parent: parent)
    empty = Media::Folder.create!(name: "Empty")
    [ parent, parent, child ].each { |folder| create_media_asset.update_columns(folder_id: folder.id) } # version: none (a test's own rows)
    create_media_asset
    create_media_asset.update_columns(folder_id: parent.id, trashed_at: Time.current) # version: none (a test's own rows)

    counts = nil
    assert_queries_count(1) { counts = Media::FolderCounts.call }

    assert_equal({ all: 4, none: 1, folders: { parent.id => 2, child.id => 1 } }, counts)
    assert_not_includes counts[:folders].keys, empty.id
  end
end
