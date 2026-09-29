require "test_helper"

class MediaAssets::CreateTest < ActiveSupport::TestCase
  def upload = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")

  test "stores the upload, credits the actor and records media.uploaded" do
    result = as(users(:author)) { MediaAssets::Create.call(file: upload) }

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
      result = as(users(:reader)) { MediaAssets::Create.call(file: upload) }
    end

    assert_equal [ "You don't have permission to upload media" ], result.errors
    assert_equal "media.upload", Audit::Event.find_by!(action: "access.denied").metadata["permission"]
  end

  test "a missing file fails without an event" do
    result = as_owner { MediaAssets::Create.call(file: nil) }

    assert_equal [ "file must be attached" ], result.errors
    assert_not Audit::Event.exists?(action: "media.uploaded")
  end
end
