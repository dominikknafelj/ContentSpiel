require "test_helper"
require "rake"
require Rails.root.join("db/migrate/20260929050000_move_images_into_media_library").to_s

# Media library Task 4's data migration (design spec §3.4, that migration's
# own comment): every legacy `Page#hero_image` / `ContentBlock#image` Active
# Storage attachment becomes a reference to a `Media::Asset` that re-attaches
# the *same* blob. The models no longer declare either attachment, so each
# test builds the "before" state as raw `ActiveStorage::Attachment` rows --
# exactly what an un-migrated database holds -- and runs the migration
# directly, the same pattern every other test in this directory uses.
class MoveImagesIntoMediaLibraryMigrationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { MoveImagesIntoMediaLibrary.new.migrate(direction) }

  def blob_for(fixture, filename:)
    ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture(fixture)), filename: filename, content_type: "image/png")
  end

  def legacy_attach(record, name, blob)
    ActiveStorage::Attachment.create!(record_type: record.class.polymorphic_name, record_id: record.id, name: name, blob: blob)
  end

  def legacy_attachments
    ActiveStorage::Attachment.where(record_type: "Page", name: "hero_image")
      .or(ActiveStorage::Attachment.where(record_type: "ContentBlock", name: "image"))
  end

  setup do
    @first = create_page(title: "First")
    @second = create_page(title: "Second")
    @block = @first.content_blocks.create!(block_type: :image, position: 0)

    # Two pages whose heroes are byte-identical files (two blob rows, one
    # checksum), and one block with a different image.
    @hero_a = blob_for("tiny.png", filename: "hero-photo.png")
    @hero_b = blob_for("tiny.png", filename: "hero-copy.png")
    @block_blob = blob_for("medium.png", filename: "studio.png")
    assert_equal @hero_a.checksum, @hero_b.checksum
    assert_not_equal @hero_a.checksum, @block_blob.checksum

    legacy_attach(@first, "hero_image", @hero_a)
    legacy_attach(@second, "hero_image", @hero_b)
    legacy_attach(@block, "image", @block_blob)
  end

  test "identical files collapse into one asset; a different file gets its own" do
    assert_difference "Media::Asset.count", 2 do
      migrate(:up)
    end

    hero_asset = @first.reload.hero_media_asset
    assert_equal hero_asset, @second.reload.hero_media_asset
    assert_not_equal hero_asset, @block.reload.media_asset
  end

  test "the references are set, the assets reuse the blobs and the titles come from the file names" do
    migrate(:up)

    hero_asset = @first.reload.hero_media_asset
    block_asset = @block.reload.media_asset

    assert_equal @hero_a, hero_asset.file.blob, "the first blob seen for a checksum is the one re-attached"
    assert_equal @block_blob, block_asset.file.blob
    assert_equal "hero-photo", hero_asset.title
    assert_equal "studio", block_asset.title
    assert_equal "image/png", block_asset.content_type
    assert_equal @block_blob.byte_size, block_asset.byte_size
  end

  test "the old attachments are gone and the blobs are kept" do
    migrate(:up)

    assert_empty legacy_attachments
    assert ActiveStorage::Blob.exists?(@hero_a.id)
    assert ActiveStorage::Blob.exists?(@hero_b.id), "a deduped duplicate's blob is left for media:orphans, not purged"
    assert ActiveStorage::Blob.exists?(@block_blob.id)
  end

  test "media_usages is rebuilt for the new references" do
    Media::Usage.delete_all
    migrate(:up)

    hero_asset = @first.reload.hero_media_asset
    expected = [
      [ hero_asset.id, "Page", @first.id, "hero", nil ],
      [ hero_asset.id, "Page", @second.id, "hero", nil ],
      [ @block.reload.media_asset_id, "ContentBlock", @block.id, "block_image", nil ]
    ]
    actual = Media::Usage.where(role: %w[hero block_image]).pluck(:media_asset_id, :owner_type, :owner_id, :role, :locale)
    assert_equal expected.sort_by { |row| [ row[1], row[2] ] }, actual.sort_by { |row| [ row[1], row[2] ] }

    # The same rows `Media::UsageIndex` itself computes from those references.
    Media::UsageIndex.rebuild_all
    assert_equal actual.sort_by { |row| [ row[1], row[2] ] },
      Media::Usage.where(role: %w[hero block_image]).pluck(:media_asset_id, :owner_type, :owner_id, :role, :locale).sort_by { |row| [ row[1], row[2] ] }
  end

  test "an existing library asset with the same checksum is reused rather than duplicated" do
    library = create_media_asset(filename: "medium.png")

    migrate(:up)

    assert_equal library, @block.reload.media_asset
  end

  # An asset made by inserting its attachment row never fires Active
  # Storage's own variant preprocessing, so the migration queues it.
  test "up queues the responsive variants for each asset it creates" do
    assert_enqueued_jobs 2 * Media::Asset::VARIANT_WIDTHS.size, only: ActiveStorage::TransformJob do
      migrate(:up)
    end
  end

  test "blobs without a checksum are never collapsed into one asset" do
    @hero_a.update_column(:checksum, nil)
    @hero_b.update_column(:checksum, nil)

    migrate(:up)

    assert_not_equal @first.reload.hero_media_asset, @second.reload.hero_media_asset
  end

  test "a blob of a type the library refuses is left attached, not migrated" do
    svg = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'/>"), filename: "logo.svg", content_type: "image/svg+xml")
    third = create_page(title: "Third")
    legacy_attach(third, "hero_image", svg)

    migrate(:up)

    assert_nil third.reload.hero_media_asset_id
    assert ActiveStorage::Attachment.exists?(record_type: "Page", record_id: third.id, name: "hero_image", blob_id: svg.id)
  end

  test "down restores the attachments from the references and removes the assets it made" do
    migrate(:up)
    assert_equal 2, Media::Asset.count

    migrate(:down)

    assert_nil @first.reload.hero_media_asset_id
    assert_nil @block.reload.media_asset_id
    assert_equal @hero_a.id, ActiveStorage::Attachment.find_by!(record_type: "Page", record_id: @first.id, name: "hero_image").blob_id
    assert_equal @hero_a.id, ActiveStorage::Attachment.find_by!(record_type: "Page", record_id: @second.id, name: "hero_image").blob_id
    assert_equal @block_blob.id, ActiveStorage::Attachment.find_by!(record_type: "ContentBlock", record_id: @block.id, name: "image").blob_id
    assert_equal 0, Media::Asset.count
    assert_empty Media::Usage.where(role: %w[hero block_image])
  end

  test "down keeps an asset that rich text still embeds" do
    migrate(:up)
    hero_asset = @first.reload.hero_media_asset
    post = create_post(title: "Embeds it")
    post.assign_body(rich_doc(%(::image{asset="#{hero_asset.id}"})), locale: "en")
    post.save!

    migrate(:down)

    assert Media::Asset.exists?(hero_asset.id)
    assert ActiveStorage::Attachment.exists?(record_type: "Page", record_id: @first.id, name: "hero_image", blob_id: @hero_a.id)
  end

  # Fix round 1 (M1): `down` removes only what `up` created (its ledger).
  test "down keeps a pre-existing library asset up deduped onto, and a later upload" do
    library = create_media_asset(filename: "medium.png")
    migrate(:up)
    assert_equal library, @block.reload.media_asset
    hero_asset_id = @first.reload.hero_media_asset_id

    later = create_media_asset(filename: "wide.png")
    third = create_page(title: "Third")
    third.update!(hero_media_asset: later)

    migrate(:down)

    assert Media::Asset.exists?(library.id), "a pre-existing library asset survives a rollback"
    assert Media::Asset.exists?(later.id), "an upload made after the migration survives a rollback"
    assert_not Media::Asset.exists?(hero_asset_id), "the asset up created is removed"
    assert_equal 2, Media::Asset.count
    assert_equal library.file.blob_id,
      ActiveStorage::Attachment.find_by!(record_type: "ContentBlock", record_id: @block.id, name: "image").blob_id
    assert_not ActiveRecord::Base.connection.table_exists?(:media_library_migrated_assets)
  end

  # Fix round 1 (M3).
  test "an attachment whose owner no longer exists gets no asset" do
    gone = create_page(title: "Gone")
    legacy_attach(gone, "hero_image", blob_for("wide.png", filename: "gone.png"))
    Page.where(id: gone.id).delete_all

    assert_difference "Media::Asset.count", 2 do
      migrate(:up)
    end
    assert ActiveStorage::Attachment.exists?(record_type: "Page", record_id: gone.id, name: "hero_image")
  end

  # Fix round 1 (M4): a database error while queueing variants is rescued
  # inside its own savepoint, so the migration's transaction -- and the
  # data it already moved -- stays usable.
  test "a database error while queueing variants doesn't abort the migration" do
    boom = ->(*) { ActiveRecord::Base.connection.execute("SELECT 1/0") }

    with_singleton_override(Media::Asset, :where, boom) { migrate(:up) }

    assert @first.reload.hero_media_asset_id.present?
    assert_empty legacy_attachments
  end

  test "up, down, up round-trips to the same references" do
    migrate(:up)
    migrate(:down)
    migrate(:up)

    assert_equal 2, Media::Asset.count
    assert_equal @hero_a, @first.reload.hero_media_asset.file.blob
    assert_equal @block_blob, @block.reload.media_asset.file.blob
    assert_empty legacy_attachments
  end
end

# `media:orphans` (design spec §3.4 step 5): blobs no attachment points at --
# a deduped duplicate from the migration above, an ActionText import
# leftover -- listed by default, purged only with CONFIRM=1.
class MediaOrphansTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("media:orphans")
    @task = Rake::Task["media:orphans"]
    @task.reenable
    @orphan = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "leftover.png", content_type: "image/png")
    @kept = create_media_asset
  end

  def run_task(env = {})
    previous = env.keys.to_h { |key| [ key, ENV[key] ] }
    env.each { |key, value| ENV[key] = value }
    output, = capture_io { @task.invoke }
    output
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  test "lists an unattached blob without purging it" do
    output = run_task

    assert_includes output, "leftover.png"
    assert_not_includes output, @kept.file.filename.to_s
    assert ActiveStorage::Blob.exists?(@orphan.id)
  end

  # Fix round 1 (M5): only a purge confirmed by the row being gone counts.
  test "CONFIRM=1 doesn't count a purge that failed" do
    ActiveStorage::Blob.class_eval do
      alias_method :__original_purge, :purge
      define_method(:purge) { raise "storage unavailable" }
    end

    output = run_task("CONFIRM" => "1")

    assert_includes output, "purge failed: RuntimeError: storage unavailable"
    assert_includes output, "purged 0 blob(s), 1 could not be purged"
    assert ActiveStorage::Blob.exists?(@orphan.id)
  ensure
    ActiveStorage::Blob.class_eval do
      alias_method :purge, :__original_purge
      remove_method :__original_purge
    end
  end

  test "CONFIRM=1 purges it and leaves attached blobs alone" do
    output = run_task("CONFIRM" => "1")

    assert_includes output, "purged 1"
    assert_not ActiveStorage::Blob.exists?(@orphan.id)
    assert ActiveStorage::Blob.exists?(@kept.file.blob.id)
  end
end
