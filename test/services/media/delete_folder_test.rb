require "test_helper"

# `Media::DeleteFolder`: a folder's images and subfolders move one level up,
# then the row goes; the confirm dialog's words come from `.preview`.
class Media::DeleteFolderTest < ActiveSupport::TestCase
  def delete(folder) = as_owner { Media::DeleteFolder.call(folder) }

  def folder!(name, parent: nil) = Media::Folder.create!(name: name, parent_id: parent&.id)

  def image_in(folder)
    asset = create_media_asset
    asset.update_column(:folder_id, folder&.id) # version: none (a test's own rows)
    asset
  end

  def event
    Audit::Event.where(action: "media_folder.deleted").order(:id).last
  end

  test "its images and subfolders move one level up and the event names what moved" do
    parent = folder!("Clients")
    doomed = folder!("Old", parent: parent)
    inner = folder!("Italy", parent: doomed)
    asset = image_in(doomed)

    result = delete(doomed)

    assert result.ok?, result.errors.inspect
    assert_not Media::Folder.exists?(doomed.id)
    assert_equal parent.id, asset.reload.folder_id
    assert_equal parent.id, inner.reload.parent_id
    assert_equal "Media::Folder", event.subject_type
    assert_equal "Old", event.subject_label
    assert_equal({ "parent_id" => parent.id, "moved_image_count" => 1, "moved_image_ids" => [ asset.id ], "moved_folder_ids" => [ inner.id ] },
      event.metadata.slice("parent_id", "moved_image_count", "moved_image_ids", "moved_folder_ids"))
  end

  test "at the top, its images go to no folder and its subfolders to the top" do
    doomed = folder!("Old")
    inner = folder!("Italy", parent: doomed)
    asset = image_in(doomed)

    assert delete(doomed).ok?

    assert_nil asset.reload.folder_id
    assert_nil inner.reload.parent_id
    assert_nil event.metadata["parent_id"]
  end

  test "a subfolder whose name the parent holds takes the next free suffix and is recorded renamed" do
    parent = folder!("Clients")
    folder!("Logos", parent: parent)
    folder!("Logos 2", parent: parent)
    doomed = folder!("Old", parent: parent)
    clashing = folder!("logos", parent: doomed)
    fine = folder!("Photos", parent: doomed)

    assert delete(doomed).ok?

    assert_equal "logos 3", clashing.reload.name
    assert_equal parent.id, clashing.parent_id
    assert_equal "Photos", fine.reload.name
    renamed = Audit::Event.where(action: "media_folder.renamed")
    assert_equal 1, renamed.count
    assert_equal({ "name" => [ "logos", "logos 3" ] }, renamed.first.field_changes)
    assert_equal clashing.id, renamed.first.subject_id
  end

  test "a suffix never lands on a subfolder that keeps its name" do
    parent = folder!("Clients")
    folder!("Logos", parent: parent)
    doomed = folder!("Old", parent: parent)
    folder!("Logos", parent: doomed)
    kept = folder!("Logos 2", parent: doomed)

    assert delete(doomed).ok?

    assert_equal "Logos 2", kept.reload.name
    assert_equal [ "Logos", "Logos 2", "Logos 3" ], Media::Folder.where(parent_id: parent.id).pluck(:name).sort
  end

  test "the image ids are kept for 200 or fewer and only counted above" do
    doomed = folder!("Old")
    template = image_in(doomed).attributes.except("id")
    ids = Media::Asset.insert_all!(Array.new(200) { template.dup }, returning: :id).map { |row| row["id"] } # version: none (a test's own rows)
    ids << Media::Asset.where(folder_id: doomed.id).where.not(id: ids).pick(:id)

    assert delete(doomed).ok?
    assert_equal 201, event.metadata["moved_image_count"]
    assert_not event.metadata.key?("moved_image_ids")
    assert_equal 201, Media::Asset.where(id: ids, folder_id: nil).count

    again = folder!("Again")
    kept = Media::Asset.where(id: ids.first(200))
    kept.update_all(folder_id: again.id) # version: none (a test's own rows)
    assert delete(again).ok?
    assert_equal 200, event.metadata["moved_image_count"]
    assert_equal ids.first(200).sort, event.metadata["moved_image_ids"].sort
  end

  test "a trashed image moves up with the rest and is restored into the parent" do
    parent = folder!("Clients")
    doomed = folder!("Old", parent: parent)
    asset = image_in(doomed)
    as_owner { assert Trash::Move.call(asset).ok? }

    assert delete(doomed).ok?
    assert_equal parent.id, asset.reload.folder_id

    as_owner { assert Trash::Restore.call(asset.reload).ok? }
    assert_equal parent.id, asset.reload.folder_id
  end

  test "the writes on media_assets bump no content version and leave updated_at alone" do
    doomed = folder!("Old")
    asset = image_in(doomed)
    asset_stamp = asset.reload.updated_at
    version = PublicSite.content_version
    counter = PublicSite::Version.current

    assert delete(doomed).ok?

    assert_equal asset_stamp, asset.reload.updated_at
    assert_equal version, PublicSite.content_version
    assert_equal counter, PublicSite::Version.current
  end

  test "a folder deleted meanwhile is gone, not an error" do
    doomed = folder!("Old")
    Media::Folder.where(id: doomed.id).delete_all # version: none (a test's own rows)

    result = delete(doomed)

    assert_not result.ok?
    assert_equal [ "That folder is gone." ], result.errors
    assert_nil Audit::Event.where(action: "media_folder.deleted").first
  end

  test "media.upload alone may not delete a folder" do
    doomed = folder!("Old")
    asset = image_in(doomed)
    uploader = users(:author)
    assert AccessControl.allowed?(uploader, "media.upload", nil)
    assert_not AccessControl.allowed?(uploader, "media.manage", nil)

    result = as(uploader) { Media::DeleteFolder.call(doomed) }

    assert result.denied?
    assert Media::Folder.exists?(doomed.id)
    assert_equal doomed.id, asset.reload.folder_id
    assert_nil Audit::Event.where(action: "media_folder.deleted").first
  end

  test "the preview counts what moves, names the renames and the target" do
    parent = folder!("Clients")
    folder!("Logos", parent: parent)
    doomed = folder!("Old", parent: parent)
    clashing = folder!("Logos", parent: doomed)
    folder!("Photos", parent: doomed)
    image_in(doomed)
    image_in(doomed)

    preview = Media::DeleteFolder.preview(doomed)

    assert_equal 2, preview.image_count
    assert_equal 2, preview.folder_count
    assert_equal({ clashing.id => "Logos 2" }, preview.renames)
    assert_equal parent, preview.target
    assert_nil Media::DeleteFolder.preview(parent).target
  end
end
