require "test_helper"

class Media::UploadTest < ActiveSupport::TestCase
  def upload = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")

  test "stores the upload, credits the actor and records media.uploaded" do
    result = as(users(:author)) { Media::Upload.call(file: upload) }

    assert result.ok?, result.errors.inspect
    asset = result.record
    assert asset.persisted?
    assert_equal users(:author), asset.created_by
    event = Audit::Event.find_by!(action: "media.uploaded")
    assert_equal asset, event.subject
    assert_equal "tiny.png", event.metadata["filename"]
  end

  test "needs media.upload" do
    result = nil
    assert_no_difference "Media::Asset.count" do
      result = as(users(:reader)) { Media::Upload.call(file: upload) }
    end

    assert_equal [ "You don't have permission to upload media" ], result.errors
    assert_equal "media.upload", Audit::Event.find_by!(action: "access.denied").metadata["permission"]
  end

  test "a missing file fails without an event" do
    result = as_owner { Media::Upload.call(file: nil) }

    assert_equal [ "file must be attached" ], result.errors
    assert_not Audit::Event.exists?(action: "media.uploaded")
  end

  # The library never silently dedupes an
  # upload -- only the one-off data migration collapses identical files.
  test "uploading the same file twice makes two assets" do
    assert_difference "Media::Asset.count", 2 do
      2.times { assert as(users(:author)) { Media::Upload.call(file: upload) }.ok? }
    end
  end

  test "an upload that cannot be decoded is a failure with the sentence, and no asset or blob row remains attached" do
    broken = Rack::Test::UploadedFile.new(file_fixture("not_an_image.png"), "image/png")
    result = nil
    assert_no_difference [ "Media::Asset.count", "ActiveStorage::Attachment.count" ] do
      result = as(users(:author)) { Media::Upload.call(file: broken) }
    end

    assert_not result.ok?
    assert_includes result.errors, "File can't be read as an image"
    assert_not Audit::Event.exists?(action: "media.uploaded")
  end

  test "an explicit actor is credited, not Current.actor" do
    result = Media::Upload.call(file: upload, actor: users(:author))

    assert result.ok?, result.errors.inspect
    assert_equal users(:author), result.record.created_by
  end

  test "an upload in a folder lands in it and says so in its event" do
    folder = Media::Folder.create!(name: "Client A")
    result = as(users(:author)) { Media::Upload.call(file: upload, folder: folder) }

    assert result.ok?, result.errors.inspect
    assert_equal folder.id, result.record.reload.folder_id
    assert_equal folder.id, Audit::Event.find_by!(action: "media.uploaded").metadata["folder_id"]

    by_id = as(users(:author)) { Media::Upload.call(file: upload, folder: folder.id) }
    assert_equal folder.id, by_id.record.reload.folder_id
  end

  test "an upload with no folder lands in none" do
    result = as(users(:author)) { Media::Upload.call(file: upload) }

    assert_nil result.record.reload.folder_id
    assert_nil Audit::Event.find_by!(action: "media.uploaded").metadata["folder_id"]
  end

  test "an upload into a folder deleted meanwhile is refused and stores nothing" do
    folder = Media::Folder.create!(name: "Gone")
    gone_id = folder.id
    folder.destroy!
    result = nil

    assert_no_difference [ "Media::Asset.count", "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
      result = as(users(:author)) { Media::Upload.call(file: upload, folder: gone_id) }
    end

    assert_not result.ok?
    assert_equal [ "That folder is gone." ], result.errors
    assert_not Audit::Event.exists?(action: "media.uploaded")
  end
end
