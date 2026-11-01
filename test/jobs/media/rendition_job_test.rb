require "test_helper"

class Media::RenditionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @site = SiteSetting.instance
  end

  # A new image setting, as a save would leave the row; the request-scoped
  # copy is dropped as a new request would drop it.
  def change_settings(**columns)
    @site.update_columns(columns) # version: none (a test sets the image settings)
    Current.site = nil
  end

  def vips_of(asset, width)
    file = asset.generation.files.find { |made| made.width == width }
    record = ActiveStorage::VariantRecord.find_by!(blob_id: asset.file.blob.id, variation_digest: file.digest)
    record.image.blob.open { |tempfile| Vips::Image.new_from_buffer(File.binread(tempfile.path), "", n: -1) }
  end

  def upload(filename = "wide.png", content_type: "image/png")
    asset = nil
    perform_enqueued_jobs(only: ActiveStorage::AnalyzeJob) { asset = create_media_asset(filename: filename, content_type: content_type) }
    clear_enqueued_jobs
    asset
  end

  test "an upload enqueues one job on the images queue and no TransformJob" do
    assert_enqueued_jobs 1, only: Media::RenditionJob, queue: "images" do
      create_media_asset(filename: "wide.png")
    end
    assert_no_enqueued_jobs(only: ActiveStorage::TransformJob)
  end

  test "the job makes every width of the image, records one generation under the current fingerprint and the page's srcset names them" do
    asset = upload("wide.png")

    Media::RenditionJob.perform_now(asset)
    asset.reload

    assert_equal [ 480, 960, 1600, 2400 ], asset.generation.widths
    assert_equal ImageSettings.current.fingerprint, asset.renditions_fingerprint
    assert_equal asset.renditions_fingerprint, asset.generation.fingerprint
    assert_equal 4, ActiveStorage::VariantRecord.where(blob_id: asset.file.blob.id).count
    assert_equal asset.generation.widths, asset.srcset.map(&:last)
    assert_nil asset.renditions_failed_at
  end

  test "a width carries no camera data and is turned upright" do
    asset = upload("rotated.jpg", content_type: "image/jpeg")

    Media::RenditionJob.perform_now(asset)
    made = vips_of(asset.reload, asset.generation.widths.first)

    assert_not_includes made.get_fields, "exif-data"
    assert_operator made.height, :>, made.width
  end

  test "an animated GIF's widths are animated WebP" do
    asset = upload("animated.gif", content_type: "image/gif")

    Media::RenditionJob.perform_now(asset)
    made = vips_of(asset.reload, asset.generation.widths.first)

    assert_equal 3, made.get("n-pages")
  end

  def skip_unless_avif
    skip "this libvips cannot write AVIF (ImageSettings.avif_available? is false), so Settings offers no AVIF here" unless ImageSettings.avif_available?
  end

  # libvips writes an animation's AVIF as a still image collection (no
  # `avis` brand), which a browser shows as its first frame: an animated
  # source is made in WebP, at the WebP quality, whatever the format. Its
  # widths need no AVIF encoder, so this runs on any libvips.
  test "under AVIF an animated GIF's widths are animated WebP, under the AVIF fingerprint" do
    change_settings(image_format: "avif", image_quality_webp: 70)
    gif = upload("animated.gif", content_type: "image/gif")

    Media::RenditionJob.perform_now(gif)
    animated = vips_of(gif.reload, gif.generation.widths.first)

    assert_equal 3, animated.get("n-pages")
    assert_equal "webpload_buffer", animated.get("vips-loader")
    assert_equal ImageSettings.current.fingerprint, gif.renditions_fingerprint
  end

  test "under AVIF a still image's widths are AVIF" do
    skip_unless_avif
    change_settings(image_format: "avif")
    png = upload("wide.png")

    Media::RenditionJob.perform_now(png)

    assert_equal "heifload_buffer", vips_of(png.reload, png.generation.widths.first).get("vips-loader")
  end

  test "under AVIF a still GIF is AVIF" do
    skip_unless_avif
    change_settings(image_format: "avif")
    gif = upload("small.gif", content_type: "image/gif")

    Media::RenditionJob.perform_now(gif)

    assert_equal "heifload_buffer", vips_of(gif.reload, gif.generation.widths.first).get("vips-loader")
  end

  test "a second run under the same settings makes nothing" do
    asset = upload("wide.png")
    Media::RenditionJob.perform_now(asset)
    count = ActiveStorage::VariantRecord.count
    before = asset.reload.renditions

    Media::RenditionJob.perform_now(asset)

    assert_equal count, ActiveStorage::VariantRecord.count
    assert_equal before, asset.reload.renditions
  end

  test "a change of settings keeps the previous generation's files and deletes the one before it" do
    asset = upload("wide.png")
    digests = []
    [ [ "webp", 75 ], [ "webp", 60 ], [ "webp", 45 ] ].each do |format, quality|
      change_settings(image_format: format, image_quality_webp: quality)
      Media::RenditionJob.perform_now(asset.reload)
      digests << asset.reload.generation.files.map(&:digest)
    end

    stored = ActiveStorage::VariantRecord.where(blob_id: asset.file.blob.id).pluck(:variation_digest)
    assert_empty stored & digests[0]
    assert_equal (digests[1] + digests[2]).sort, stored.sort
    assert_equal digests[1], asset.generation("previous").files.map(&:digest)
  end

  test "a failure is retried and recorded by its class after the last attempt, and the image keeps its preview" do
    asset = upload("wide.png")
    preview = asset.preview

    attempts = 0
    with_singleton_override(Media::Renditions, :transformations, ->(**) { attempts += 1; raise ArgumentError, "secret detail of /some/path.png" }) do
      perform_enqueued_jobs { Media::RenditionJob.perform_later(asset) }
    end

    asset.reload
    assert_equal 3, attempts
    assert_equal "ArgumentError", asset.renditions_error
    assert_not_nil asset.renditions_failed_at
    assert_equal preview, asset.preview
    assert_not asset.made?
  end

  test "an unreadable old row is recorded at once, not retried" do
    asset = upload("wide.png")
    asset.update_columns(preview: nil, width: nil, height: nil) # version: none (a test makes a row from before previews)
    attempts = 0
    with_singleton_override(Media::Decoding, :read, ->(*, **) { attempts += 1; raise Media::Decoding::Unreadable, "not a png" }) do
      perform_enqueued_jobs { Media::RenditionJob.perform_later(asset) }
    end

    assert_equal 1, attempts
    assert_equal "Media::Decoding::Unreadable", asset.reload.renditions_error
    assert_not_nil asset.renditions_failed_at
  end

  test "a missing preview and size are made by the job" do
    asset = upload("wide.png")
    asset.update_columns(preview: nil, width: nil, height: nil, has_alpha: true) # version: none (a test makes a row from before previews)

    Media::RenditionJob.perform_now(asset)
    asset.reload

    assert_equal [ 3000, 2000 ], [ asset.width, asset.height ]
    assert asset.preview.present?
    assert_not asset.has_alpha
    assert asset.made?
  end

  test "a trashed asset is skipped" do
    asset = upload("wide.png")
    asset.update_columns(trashed_at: Time.current) # version: none (a test trashes the row)

    Media::RenditionJob.perform_now(asset)

    assert_not asset.reload.made?
    assert_equal 0, ActiveStorage::VariantRecord.where(blob_id: asset.file.blob.id).count
  end

  test "regenerate, then a new format saved before the job ran: the image is made once, with the new format" do
    asset = upload("wide.png")
    Media::RenditionJob.perform_now(asset)
    enqueued = Media::RenditionJob.perform_later(asset.reload)
    assert enqueued
    change_settings(image_quality_webp: 40)

    assert_difference -> { ActiveStorage::VariantRecord.where(blob_id: asset.file.blob.id).count }, 4 do
      perform_enqueued_jobs(only: Media::RenditionJob)
    end

    assert_equal ImageSettings.current.fingerprint, asset.reload.renditions_fingerprint
    assert_equal 4, asset.generation.files.size
  end

  test "one bump of the content version per image, at the end of the job" do
    asset = upload("wide.png")
    page = create_page(title: "Shows it")
    page.update!(hero_media_asset: asset)
    Media::UsageIndex.refresh(page)

    bumps = 0
    counter = PublicSite.method(:bump_version!)
    with_singleton_override(PublicSite, :bump_version!, -> { bumps += 1; counter.call }) do
      Media::RenditionJob.perform_now(asset)
    end

    assert_equal 1, bumps
  end

  test "the span carries the queue latency, each width's duration and the bytes, and no file name" do
    asset = upload("wide.png")
    @exporter.reset

    OpenTelemetry.tracer_provider.tracer("test").in_span("job", kind: :consumer) do
      perform_enqueued_jobs(only: Media::RenditionJob) { Media::RenditionJob.perform_later(asset) }
    end
    # Active Job's instrumentation makes the job's own consumer span, which is
    # the current one while `perform` runs.
    spans = @exporter.finished_spans.select { |span| span.attributes.key?("image.bytes_in") }
    assert_equal 1, spans.size
    assert_not_equal "job", spans.first.name, "the attributes belong on the job's own span"
    attributes = spans.first.attributes

    assert attributes["image.queue_latency_ms"]
    asset.reload.generation.widths.each { |width| assert attributes["image.width.#{width}.ms"], "width #{width}" }
    assert_operator attributes["image.bytes_in"], :>, 0
    assert_operator attributes["image.bytes_out"], :>, 0
    assert_empty attributes.values.grep(/wide\.png|\.png/)
  end

  test "restoring an image from the trash enqueues the job unless it is made with the current settings" do
    asset = upload("wide.png")
    Trash::Move.call(asset)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: Media::RenditionJob do
      assert Trash::Restore.call(asset.reload).ok?
    end

    Media::RenditionJob.perform_now(asset.reload)
    Trash::Move.call(asset.reload)
    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: Media::RenditionJob) { assert Trash::Restore.call(asset.reload).ok? }
  end

  test "an image purged before its job ran runs once and is not retried" do
    asset = upload("wide.png")
    job = Media::RenditionJob.perform_later(asset)
    assert job
    Media::Asset.where(id: asset.id).delete_all # version: none (a test removes the row the job names)
    runs = 0
    with_singleton_override(Media::Decoding, :read, ->(*, **) { runs += 1 }) do
      perform_enqueued_jobs(only: Media::RenditionJob)
    end

    assert_equal 0, runs
    assert_no_enqueued_jobs(only: Media::RenditionJob)
  end
end
