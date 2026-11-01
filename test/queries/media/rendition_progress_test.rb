require "test_helper"

class Media::RenditionProgressTest < ActiveSupport::TestCase
  FINGERPRINT = "current-fingerprint".freeze

  def image(**columns)
    asset = create_media_asset
    asset.update_columns(columns) if columns.any? # version: none (a test sets the recorded generation)
    asset
  end

  test "counts kept images only: made with these settings, failed, and all" do
    Media::Asset.delete_all
    image(renditions_fingerprint: FINGERPRINT)
    image(renditions_fingerprint: FINGERPRINT)
    image(renditions_fingerprint: "older")
    image(renditions_fingerprint: nil)
    image(renditions_fingerprint: "older", renditions_failed_at: Time.current)
    image(renditions_fingerprint: FINGERPRINT, renditions_failed_at: Time.current)
    image(renditions_fingerprint: FINGERPRINT, trashed_at: Time.current)
    image(renditions_fingerprint: nil, trashed_at: Time.current, renditions_failed_at: Time.current)

    counts = Media::RenditionProgress.new(fingerprint: FINGERPRINT, scope: Media::Asset.kept).counts

    # A failed image that is made is made; only a failure of an image not made counts as failed.
    assert_equal({ total: 6, made: 3, failed: 1 }, counts)
  end

  test "it is one statement, however many images there are" do
    3.times { image(renditions_fingerprint: FINGERPRINT) }

    statements = capture_sql { Media::RenditionProgress.new(fingerprint: FINGERPRINT, scope: Media::Asset.kept).counts }

    assert_equal 1, statements.size
  end

  test "it defaults to the current settings and the kept images" do
    Media::Asset.delete_all
    image(renditions_fingerprint: ImageSettings.current.fingerprint)
    image(renditions_fingerprint: ImageSettings.current.fingerprint, trashed_at: Time.current)

    assert_equal({ total: 1, made: 1, failed: 0 }, Media::RenditionProgress.new.counts)
  end
end
