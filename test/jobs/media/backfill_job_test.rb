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

  def rendition_jobs_for(asset) = performed_jobs.count { |job| job["job_class"] == "Media::BackfillRenditionJob" && job["arguments"].first["_aj_globalid"] == asset.to_global_id.to_s }

  test "an old row with no preview or size gets both from one job, and a row that cannot be decoded is recorded failed and asked again never" do
    old = old_row
    broken = unreadable(old_row)

    perform_enqueued_jobs(only: Media::BackfillRenditionJob) { Media::BackfillJob.perform_now }
    old.reload
    broken.reload

    assert_equal 1, rendition_jobs_for(old)
    assert_equal [ 800, 600 ], [ old.width, old.height ]
    assert old.preview.present?
    assert old.made_with?(ImageSettings.current.fingerprint)
    assert_not_nil broken.renditions_failed_at
    assert_equal "Media::Decoding::Unreadable", broken.renditions_error

    assert_no_enqueued_jobs(only: Media::BackfillRenditionJob) { Media::BackfillJob.perform_now }
  end

  test "a decoded row and a trashed one are asked nothing, and with nothing missing the job is one query" do
    create_media_asset(filename: "medium.png")
    trashed = old_row
    trashed.update_columns(trashed_at: Time.current) # version: none (a test puts an image in the trash)
    clear_enqueued_jobs

    statements = nil
    assert_no_enqueued_jobs(only: Media::BackfillRenditionJob) do
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

  def queued_ids = enqueued_jobs.select { |job| job["job_class"] == "Media::BackfillRenditionJob" }.map { |job| GlobalID::Locator.locate(job["arguments"].first["_aj_globalid"]).id }

  test "an adopted row is selected though it has a preview and a size, and a made one is not" do
    adopted = make_renditions!(create_media_asset(filename: "medium.png"), widths: [ 480 ], fingerprint: Media::Generation::ADOPTED)
    make_renditions!(create_media_asset(filename: "medium.png"))
    clear_enqueued_jobs
    assert adopted.preview.present? && adopted.width.present?

    Media::BackfillJob.perform_now

    assert_equal [ adopted.id ], queued_ids
  end

  test "a run queues a batch at most, the oldest rows first, so the queue never holds the whole library" do
    rows = Array.new(3) { old_row("tiny.png") }

    Media::BackfillJob.perform_now(limit: 2)

    assert_equal rows.first(2).map(&:id), queued_ids
    assert_operator Media::BackfillJob::BATCH, :>, 0
  end

  # The backfill's job holds one place per image in Solid Queue: a second
  # enqueue of an image whose backfill job is still waiting or running is
  # discarded, so a run every ten minutes queues each image once at a time.
  # Uploads and regenerate queue the plain job, which this limit never drops.
  test "the backfill's job is limited to one per image at a time, discarding the rest, and the plain job is not" do
    asset = old_row
    job = Media::BackfillRenditionJob.new(asset)

    assert_equal 1, Media::BackfillRenditionJob.concurrency_limit
    assert_equal :discard, Media::BackfillRenditionJob.concurrency_on_conflict
    assert_includes job.concurrency_key, asset.id.to_s
    assert_nil Media::RenditionJob.concurrency_key
    assert_equal "images", job.queue_name
  end

  # Solid Queue runs the smaller number first. An upload's and a Regenerate's
  # plain job keep the default (0); the backfill's re-encodes wait behind them
  # so a new upload's widths never queue behind a library of old images.
  test "the backfill's job runs after the plain job in the images queue" do
    plain = Media::RenditionJob.new(old_row)
    backfill = Media::BackfillRenditionJob.new(old_row)

    assert_equal "images", backfill.queue_name
    assert_equal "images", plain.queue_name
    assert_operator backfill.priority, :>, plain.priority.to_i
  end
end
