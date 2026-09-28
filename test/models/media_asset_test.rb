require "test_helper"

# `MediaAsset` (design spec §4.2): the model backing a rich-text `image`
# node's `asset_id` (`RichText::BuiltIns`) and the Tiptap editor's own
# upload endpoint. The one rule this class enforces -- "image type and size"
# -- is deliberately checked against the attached file's *actual bytes*
# (Marcel-sniffed, ignoring whatever Content-Type/filename the upload
# claimed), never the stored `content_type`/`byte_size` columns a caller
# might set by hand: those columns exist to cache what validation already
# found, not to be trusted as input to it.
class MediaAssetTest < ActiveSupport::TestCase
  test "a png under 10 MB is valid" do
    asset = MediaAsset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    assert asset.valid?
  end

  test "a text file is invalid, even renamed .png with an image/png content type" do
    asset = MediaAsset.new
    asset.file.attach(io: StringIO.new("this is plain text, not an image"), filename: "not-a-real-image.png", content_type: "image/png")

    assert_not asset.valid?
    assert_includes asset.errors[:file].join, "PNG, JPEG, GIF, or WEBP"
  end

  test "a file over 10 MB is invalid" do
    asset = MediaAsset.new
    oversized = "\x00" * (10.megabytes + 1)
    asset.file.attach(io: StringIO.new(oversized), filename: "big.png", content_type: "image/png")

    assert_not asset.valid?
    assert_includes asset.errors[:file].join, "10 MB"
  end

  test "with no file attached at all" do
    asset = MediaAsset.new

    assert_not asset.valid?
  end

  test "saving caches the sniffed content type and byte size onto the record" do
    asset = MediaAsset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert asset.save

    assert_equal "image/png", asset.content_type
    assert_equal File.size(file_fixture("tiny.png")), asset.byte_size
  end

  test "#url is the blob's own path, or nil with no file attached" do
    asset = MediaAsset.new
    assert_nil asset.url

    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    asset.save!

    assert_equal Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true), asset.url
  end
end
