require "test_helper"
require Rails.root.join("db/migrate/20261031120000_adopt_existing_image_variants").to_s

# An existing site's images keep the widths their pages already named through
# the deploy: the variants the old preprocessing made (a Symbol `:webp`, no
# quality, no strip) are adopted as each image's first generation, and the
# public route serves them by the address the page held before.
class AdoptExistingImageVariantsMigrationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def adopt = ActiveRecord::Migration.suppress_messages { AdoptExistingImageVariants.new.adopt }
  def forget = ActiveRecord::Migration.suppress_messages { AdoptExistingImageVariants.new.forget }

  def old_transformations(width) = { resize_to_limit: [ width, nil ], format: :webp }

  # A row as the old code left it: a size, no preview, no generation.
  def old_asset(filename, content_type: "image/png")
    asset = create_media_asset(filename: filename, content_type: content_type)
    clear_enqueued_jobs
    asset.update_columns(preview: nil, renditions: {}, renditions_fingerprint: nil) # version: none (a test makes a row from before previews)
    asset
  end

  def old_asset_from(bytes, filename:, content_type:)
    asset = Media::Asset.new
    asset.file.attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
    assert asset.save, asset.errors.full_messages.to_sentence
    clear_enqueued_jobs
    asset.update_columns(preview: nil, renditions: {}, renditions_fingerprint: nil) # version: none (a test makes a row from before previews)
    asset
  end

  # A JPEG wider than the smallest old width, carrying the fixture's camera
  # data (its GPS fields among them): libvips keeps the metadata through the
  # resize and the save.
  def gps_jpeg(width:)
    source = Vips::Image.new_from_file(file_fixture("rotated.jpg").to_s)
    source.resize(width.to_f / source.width).jpegsave_buffer
  end

  # What the old preprocessing made, through the attachment's own variant as
  # its named variants were.
  def preprocess(asset, width) = asset.file.variant(old_transformations(width)).processed

  # The variation key of the address the old page named.
  def old_page_key(asset, width)
    rails_representation_path(asset.file.variant(old_transformations(width)), only_path: true).split("/")[-2]
  end

  def key_of(path) = path.split("/")[-2]

  test "an asset's four processed widths are adopted, and the page names the same addresses as before the migration" do
    asset = old_asset("wide.png")
    AdoptExistingImageVariants::OLD_WIDTHS.each { |width| preprocess(asset, width) }
    before = AdoptExistingImageVariants::OLD_WIDTHS.map { |width| old_page_key(asset, width) }

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      adopt
    end
    asset.reload

    assert_equal [ 480, 960, 1600, 2400 ], asset.generation.widths
    assert_equal "adopted", asset.renditions_fingerprint
    assert_equal "adopted", asset.generation.fingerprint
    assert_equal Media::Generation::ADOPTED, AdoptExistingImageVariants::FINGERPRINT
    assert_equal before, asset.generation.files.map(&:key)
    assert_equal before, asset.srcset.map { |path, _| key_of(path) }
  end

  test "a width preprocessed with a Symbol format is served by the public route once adopted, and the request makes nothing" do
    asset = old_asset("wide.png")
    AdoptExistingImageVariants::OLD_WIDTHS.each { |width| preprocess(asset, width) }
    adopt
    asset.reload

    asset.srcset.each do |path, width|
      file = asset.generation.files.find { |made| made.width == width }
      assert_equal asset.file.blob.variant(file.key).variation.digest, file.digest, "the digest a request finds the record by"

      assert_no_difference -> { ActiveStorage::VariantRecord.count } do
        get path
      end
      assert_response :success, "#{width}px"
    end
  end

  test "a width a request had already made again under its own digest is adopted as it is" do
    asset = old_asset("medium.png")
    preprocess(asset, 480)
    key = asset.file.variant(old_transformations(480)).variation.key
    asset.file.blob.variant(key).processed

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      adopt
    end
    asset.reload

    assert_equal [ 480 ], asset.generation.widths
    get asset.srcset.first.first
    assert_response :success
  end

  test "the widths at or above the original's are not adopted, as the old page did not name them" do
    asset = old_asset("medium.png")
    AdoptExistingImageVariants::OLD_WIDTHS.each { |width| preprocess(asset, width) }

    adopt

    assert_equal [ 480 ], asset.reload.generation.widths
  end

  test "an asset with no processed width is left to the backfill" do
    asset = old_asset("wide.png")

    adopt
    asset.reload

    assert_equal({}, asset.renditions)
    assert_nil asset.renditions_fingerprint
    assert_includes Media::Asset.backfill_due, asset
  end

  test "a GIF and an image narrower than 480px are adopted with nothing" do
    gif = old_asset("small.gif", content_type: "image/gif")
    narrow = old_asset("transparent.png")
    preprocess(gif, 480)
    preprocess(narrow, 480)

    adopt

    [ gif, narrow ].each do |asset|
      assert_equal({}, asset.reload.renditions)
      assert_nil asset.renditions_fingerprint
    end
  end

  test "an image the job has already made keeps its generation" do
    asset = make_renditions!(create_media_asset(filename: "medium.png"))
    made = asset.renditions

    adopt

    assert_equal made, asset.reload.renditions
  end

  # Ruling 11: the default settings' fingerprint only if an old width carries
  # no camera data. It does, so the adopted generation is not counted as made
  # with today's settings, and the next job makes it again.
  test "an old width of a JPEG carrying GPS keeps its camera data, so the adopted generation is not the default settings'" do
    asset = old_asset_from(gps_jpeg(width: 1000), filename: "camera.jpg", content_type: "image/jpeg")
    variant = preprocess(asset, 480)
    fields = variant.image.blob.open { |file| Vips::Image.new_from_file(file.path).get_fields }

    assert_includes fields, "exif-data"
    assert fields.any? { |field| field.start_with?("exif-ifd3-GPS") }, "GPS in the old width"

    adopt

    assert_not asset.reload.made_with?(ImageSettings.current.fingerprint)
    assert_equal "adopted", asset.renditions_fingerprint
  end

  # The owner's rule outranks keeping a previous generation: the public gets
  # only widths without camera data, so an adopted generation is dropped, not
  # kept, once its image is made again, and a cached page that still names it
  # finds nothing (the job's bump has the page drawn again).
  test "an adopted image is made again by the job, and its adopted widths are no previous generation: they answer 404" do
    asset = old_asset("medium.png")
    preprocess(asset, 480)
    adopt
    adopted = asset.reload.generation
    adopted_path = asset.srcset.first.first
    assert_equal Media::Generation::ADOPTED, adopted.fingerprint

    Media::RenditionJob.perform_now(asset)
    asset.reload

    assert asset.made_with?(ImageSettings.current.fingerprint)
    assert_nil asset.generation("previous")
    assert_not_includes asset.served_digests, adopted.files.first.digest
    assert_not ActiveStorage::VariantRecord.exists?(blob_id: asset.file.blob.id, variation_digest: adopted.files.first.digest)
    get adopted_path
    assert_response :not_found
    get asset.srcset.first.first
    assert_response :success
  end

  test "a remake of an adopted image that fails withdraws the adopted widths: the page shows the preview or the box" do
    asset = old_asset("medium.png")
    preprocess(asset, 480)
    adopt
    adopted_path = asset.reload.srcset.first.first

    with_singleton_override(Media::Decoding, :read, ->(*, **) { raise Media::Decoding::Unreadable, "not a png" }) do
      perform_enqueued_jobs { Media::RenditionJob.perform_later(asset) }
    end
    asset.reload

    assert_equal({}, asset.renditions)
    assert_nil asset.renditions_fingerprint
    assert_not_nil asset.renditions_failed_at
    assert_empty asset.srcset
    get adopted_path
    assert_response :not_found
  end

  test "a non-adopted generation is still kept as the previous one when the image is made again" do
    asset = make_renditions!(create_media_asset(filename: "medium.png"), widths: [ 480 ], fingerprint: "other-settings")
    before = asset.generation

    Media::RenditionJob.perform_now(asset)
    asset.reload

    assert_equal before.to_h, asset.generation("previous").to_h
  end

  test "down empties the adopted rows and gives a preprocessed record its old digest back" do
    asset = old_asset("medium.png")
    old_digest = preprocess(asset, 480).variation.digest
    adopt

    forget
    asset.reload

    assert_equal({}, asset.renditions)
    assert_nil asset.renditions_fingerprint
    assert ActiveStorage::VariantRecord.exists?(blob_id: asset.file.blob.id, variation_digest: old_digest)
  end
end
