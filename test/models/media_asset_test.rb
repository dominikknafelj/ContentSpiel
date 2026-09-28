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

  # Fix round 1's I3: this class only knows how to sniff bytes out of a
  # `Hash`/`UploadedFile`-shaped attachable -- a signed blob id String
  # (Active Storage's own "attach an already-uploaded blob" shape, e.g. a
  # direct upload) resolves to an *already*-persisted, already-uploaded
  # blob it never reads bytes from itself at all (`MediaAsset
  # #with_attachable_io`'s own comment), so this exercises that path
  # end-to-end: attaching by signed id must never raise, whatever the
  # already-uploaded blob's own content actually is.
  test "attaching by signed id gives a validation error for a non-image blob, not a raise" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("plain text"), filename: "notes.txt", content_type: "text/plain")

    asset = MediaAsset.new
    asset.file.attach(blob.signed_id)

    assert_not asset.valid?
    assert_includes asset.errors[:file].join, "PNG, JPEG, GIF, or WEBP"
  end

  # The signed-id path's happy case: an already-uploaded, already-real PNG
  # blob is a perfectly valid attachment -- `with_attachable_io`'s
  # `new_record?` branch reads its real bytes back off the storage service
  # (it's already there), the same as any already-persisted `MediaAsset`.
  test "attaching an already-uploaded PNG blob by signed id is valid" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    asset = MediaAsset.new
    asset.file.attach(blob.signed_id)

    assert asset.valid?
  end

  # Fix round 1's I4: the served Content-Type (`file.blob.content_type`) --
  # not just this record's own cached `content_type` column -- must equal
  # the sniffed type, even when the upload's own declared Content-Type and
  # filename both lie about it. A `.png` extension with a `text/html`
  # declared type is Active Storage's own `unfurl`/`identify` trusting the
  # *opposite* of what this test's PNG magic bytes actually are, if this
  # class didn't force the blob's own column back to the sniff.
  test "the blob's own content type is forced to the sniffed type, not the declared one" do
    asset = MediaAsset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "x.html", content_type: "text/html")
    assert asset.save, asset.errors.full_messages.to_sentence

    assert_equal "image/png", asset.file.blob.content_type
  end
end
