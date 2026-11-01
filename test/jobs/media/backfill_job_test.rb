require "test_helper"

class Media::BackfillJobTest < ActiveJob::TestCase
  # A row as the code before previews left it.
  def old_row(filename = "medium.png")
    asset = create_media_asset(filename: filename)
    clear_enqueued_jobs
    asset.update_columns(preview: nil, width: nil, height: nil) # version: none (a test makes a row from before previews)
    asset
  end

  # Stored bytes no decoder reads, under a checksum that matches them, so the
  # download succeeds and the decode is what fails.
  def unreadable(asset)
    blob = asset.file.blob
    bytes = "these bytes are no image"
    blob.service.upload(blob.key, StringIO.new(bytes))
    blob.update_columns(checksum: OpenSSL::Digest::MD5.base64digest(bytes), byte_size: bytes.bytesize)
    asset
  end

  def rendition_jobs_for(asset) = performed_jobs.count { |job| job["job_class"] == "Media::RenditionJob" && job["arguments"].first["_aj_globalid"] == asset.to_global_id.to_s }

  test "an old row with no preview or size gets both from one job, and a row that cannot be decoded is recorded failed and asked again never" do
    old = old_row
    broken = unreadable(old_row)

    perform_enqueued_jobs(only: Media::RenditionJob) { Media::BackfillJob.perform_now }
    old.reload
    broken.reload

    assert_equal 1, rendition_jobs_for(old)
    assert_equal [ 800, 600 ], [ old.width, old.height ]
    assert old.preview.present?
    assert old.made_with?(ImageSettings.current.fingerprint)
    assert_not_nil broken.renditions_failed_at
    assert_equal "Media::Decoding::Unreadable", broken.renditions_error

    assert_no_enqueued_jobs(only: Media::RenditionJob) { Media::BackfillJob.perform_now }
  end

  test "a decoded row and a trashed one are asked nothing, and with nothing missing the job is one query" do
    create_media_asset(filename: "medium.png")
    trashed = old_row
    trashed.update_columns(trashed_at: Time.current) # version: none (a test puts an image in the trash)
    clear_enqueued_jobs

    statements = nil
    assert_no_enqueued_jobs(only: Media::RenditionJob) do
      statements = capture_sql { Media::BackfillJob.perform_now }
    end
    assert_equal 1, statements.size, statements.join("\n")
  end

  test "it runs on the images queue, every ten minutes in production and development" do
    assert_equal "images", Media::BackfillJob.new.queue_name
    %w[production development].each do |environment|
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig(environment, "media_backfill")
      assert_equal "Media::BackfillJob", schedule["class"], environment
      assert_equal "images", schedule["queue"], environment
      assert_equal "every 10 minutes", schedule["schedule"], environment
    end
  end
end
