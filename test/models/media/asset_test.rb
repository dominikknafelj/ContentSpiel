require "test_helper"

# `Media::Asset` (design spec §4.2): the model backing a rich-text `image`
# node's `asset_id` (`RichText::BuiltIns`) and the Tiptap editor's own
# upload endpoint. The one rule this class enforces -- "image type and size"
# -- is deliberately checked against the attached file's *actual bytes*
# (Marcel-sniffed, ignoring whatever Content-Type/filename the upload
# claimed), never the stored `content_type`/`byte_size` columns a caller
# might set by hand: those columns exist to cache what validation already
# found, not to be trusted as input to it.
class Media::AssetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a png under 10 MB is valid" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    assert asset.valid?
  end

  test "a text file is invalid, even renamed .png with an image/png content type" do
    asset = Media::Asset.new
    asset.file.attach(io: StringIO.new("this is plain text, not an image"), filename: "not-a-real-image.png", content_type: "image/png")

    assert_not asset.valid?
    assert_includes asset.errors[:file].join, "PNG, JPEG, GIF, or WEBP"
  end

  test "a file over 10 MB is invalid" do
    asset = Media::Asset.new
    oversized = "\x00" * (10.megabytes + 1)
    asset.file.attach(io: StringIO.new(oversized), filename: "big.png", content_type: "image/png")

    assert_not asset.valid?
    assert_includes asset.errors[:file].join, "10 MB"
  end

  test "with no file attached at all" do
    asset = Media::Asset.new

    assert_not asset.valid?
  end

  test "saving caches the sniffed content type and byte size onto the record" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert asset.save

    assert_equal "image/png", asset.content_type
    assert_equal File.size(file_fixture("tiny.png")), asset.byte_size
  end

  test "#url is the blob's own path, or nil with no file attached" do
    asset = Media::Asset.new
    assert_nil asset.url

    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    asset.save!

    assert_equal Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true), asset.url
  end

  # Fix round 1's I3: this class only knows how to sniff bytes out of a
  # `Hash`/`UploadedFile`-shaped attachable -- a signed blob id String
  # (Active Storage's own "attach an already-uploaded blob" shape, e.g. a
  # direct upload) resolves to an *already*-persisted, already-uploaded
  # blob it never reads bytes from itself at all (`Media::Asset
  # #with_attachable_io`'s own comment), so this exercises that path
  # end-to-end: attaching by signed id must never raise, whatever the
  # already-uploaded blob's own content actually is.
  test "attaching by signed id gives a validation error for a non-image blob, not a raise" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("plain text"), filename: "notes.txt", content_type: "text/plain")

    asset = Media::Asset.new
    asset.file.attach(blob.signed_id)

    assert_not asset.valid?
    assert_includes asset.errors[:file].join, "PNG, JPEG, GIF, or WEBP"
  end

  # The signed-id path's happy case: an already-uploaded, already-real PNG
  # blob is a perfectly valid attachment -- `with_attachable_io`'s
  # `new_record?` branch reads its real bytes back off the storage service
  # (it's already there), the same as any already-persisted `Media::Asset`.
  test "attaching an already-uploaded PNG blob by signed id is valid" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    asset = Media::Asset.new
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
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "x.html", content_type: "text/html")
    assert asset.save, asset.errors.full_messages.to_sentence

    # From the database (final fix wave, P4): the in-memory blob could hold
    # the forced value without it ever having been written.
    assert_equal "image/png", ActiveStorage::Blob.find(asset.file.blob.id).content_type
  end

  # Final fix wave (C, P5): an already-persisted blob attached by signed id
  # keeps its stored `content_type` -- which is what it's served with -- and
  # this class never rewrites another record's blob. So when that stored
  # type disagrees with the bytes, the attachment is refused rather than
  # served under a type nobody validated.
  test "a persisted blob whose stored content type disagrees with its bytes is refused" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "x.html", content_type: "text/html", identify: false)
    assert_equal "text/html", blob.content_type

    asset = Media::Asset.new
    asset.file.attach(blob.signed_id)

    assert_not asset.valid?
    assert_includes asset.errors[:file], "doesn't match its stored content type"
  end

  # Task 2 (media library sub-project): `title` is the one field a library
  # listing/picker always has *something* to show, so it defaults from the
  # upload's own filename the moment it's blank -- but only then, so an
  # editor's own title (or a deliberate rename) always sticks.
  test "title defaults from the file name, and stays editable" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "hero-photo.jpg", content_type: "image/png")
    asset.save!

    assert_equal "hero-photo", asset.title

    asset.update!(title: "Team offsite")
    assert_equal "Team offsite", asset.reload.title
  end

  test "an explicit blank title on create still defaults from the file name" do
    asset = Media::Asset.new(title: "")
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "picnic.png", content_type: "image/png")
    asset.save!

    assert_equal "picnic", asset.title
  end

  # `#alt_text`'s resolution order (global constraints: "override.presence,
  # then the asset's default in the locale, then the Mobility fallback"),
  # against the default test site (en default, de/en/es enabled, no
  # configured fallbacks -- `Locales.fallback_chain("de")` is `de, en, es`).
  test "#alt_text returns the override, then the asset's own locale, then the fallback chain, then blank" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    Mobility.with_locale(:en) { asset.alt = "English alt" }
    Mobility.with_locale(:de) { asset.alt = "Deutscher Alt-Text" }
    asset.save!

    assert_equal "Override alt", asset.alt_text(override: "Override alt", locale: "de")
    assert_equal "Deutscher Alt-Text", asset.alt_text(override: nil, locale: "de")

    Mobility.with_locale(:de) { asset.update!(alt: "") }
    assert_equal "English alt", asset.alt_text(override: "", locale: "de")

    Mobility.with_locale(:en) { asset.update!(alt: "") }
    assert_equal "", asset.alt_text(override: nil, locale: "de")
  end

  # Same order as `#alt_text`, but nil (not `""`) with nothing set anywhere --
  # an absent caption means "render no <figcaption>", not an empty one.
  test "#caption_text follows the same order as #alt_text, but nil rather than blank" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    asset.save!

    assert_nil asset.caption_text(override: nil, locale: "de")

    Mobility.with_locale(:en) { asset.update!(caption: "English caption") }
    assert_equal "English caption", asset.caption_text(override: nil, locale: "de")

    Mobility.with_locale(:de) { asset.update!(caption: "Deutsche Bildunterschrift") }
    assert_equal "Deutsche Bildunterschrift", asset.caption_text(override: nil, locale: "de")

    assert_equal "Override caption", asset.caption_text(override: "Override caption", locale: "de")
  end

  # `wide.png` (test/fixtures/files) is a real 3000x2000 PNG -- every
  # declared variant width (480/960/1600/2400) is smaller than that, so all
  # four should eventually process and appear in `srcset`.
  test "srcset is empty before the preprocessing jobs run, then lists all four widths once they do" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("wide.png")), filename: "wide.png", content_type: "image/png")
    asset.save!
    analyze(asset)

    assert_equal [], asset.srcset

    perform_enqueued_jobs

    srcset = asset.srcset
    assert_equal [ 480, 960, 1600, 2400 ], srcset.map(&:last)
    srcset.each do |path, _width|
      assert_match %r{\A/rails/active_storage/representations/}, path
    end
  end

  # `medium.png` is a real 800x600 PNG: `resize_to_limit` never upscales, so
  # only the one variant narrower than the original (w480) should ever
  # appear -- w960/w1600/w2400 are all >= the original's own 800px width.
  test "srcset skips variants that would upscale the original" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("medium.png")), filename: "medium.png", content_type: "image/png")
    asset.save!
    analyze(asset)

    perform_enqueued_jobs

    assert_equal [ 480 ], asset.srcset.map(&:last)
  end

  test "a GIF is never variable, and never gets a srcset entry" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("small.gif")), filename: "small.gif", content_type: "image/gif")
    asset.save!
    analyze(asset)

    perform_enqueued_jobs

    assert_not asset.variable_image?
    assert_equal [], asset.srcset
  end

  # Fix round 1's I1: `preprocessed:` used to be a plain `true`, which
  # doesn't condition on content type at all -- `ActiveStorage.variable_
  # content_types` includes `image/gif`, so every GIF upload was enqueuing
  # (and a background worker would then actually run) four resized-still
  # WebP transforms of an image `#srcset`/`#variable_image?` were always
  # going to refuse to ever list. `preprocessed: ->(asset) { asset
  # .variable_image? }` is read from `ActiveStorage::Attachment`'s own
  # `after_create_commit`, strictly after this record's save (including
  # `before_save :cache_metadata_from_file`, which is what makes
  # `#variable_image?`'s `content_type` read meaningful) has committed.
  test "uploading a GIF enqueues no TransformJob, but a PNG enqueues one per variant" do
    assert_enqueued_jobs(4, only: ActiveStorage::TransformJob) do
      png = Media::Asset.new
      png.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
      png.save!
    end

    assert_no_enqueued_jobs(only: ActiveStorage::TransformJob) do
      gif = Media::Asset.new
      gif.file.attach(io: File.open(file_fixture("small.gif")), filename: "small.gif", content_type: "image/gif")
      gif.save!
    end
  end

  # Review Focus 3 (global constraints): a variant job that fails or is slow
  # -- a corrupt image, a `vips` error -- must never take the public page
  # down with it. Stubbing `file.variant` itself to blow up stands in for
  # "processing this variant failed": `#srcset` must still return normally,
  # with the error logged instead of raised, once per variant it skipped.
  test "a variant that fails to process is caught, logged, and srcset still returns without raising" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("wide.png")), filename: "wide.png", content_type: "image/png")
    asset.save!
    analyze(asset)

    logged_messages = []

    with_singleton_override(Rails.logger, :error, ->(message) { logged_messages << message }) do
      with_singleton_override(asset.file, :variant, ->(*) { raise "vips blew up" }) do
        assert_equal [], asset.srcset
      end
    end

    assert_equal 4, logged_messages.size
    assert logged_messages.all? { |message| message.include?("vips blew up") }
  end

  # Fix round 1's I2/I3: `#srcset` reads `file.blob.variant_records` to
  # answer "is this variant processed" (`#processed_variant_digests`'s own
  # comment) instead of the private `Variant#processed?`/`VariantWithRecord
  # #processed?`. Read one asset at a time that's one query per asset (a
  # library listing's own N+1); `Media::Asset.with_variants` exists so a
  # caller doesn't have to pay it -- `#srcset` over every asset in a
  # preloaded batch must cost nothing further at all, not "fewer" queries.
  test "srcset over many assets preloaded via .with_variants issues no further queries" do
    assets = Array.new(20) do |index|
      asset = Media::Asset.new
      asset.file.attach(io: File.open(file_fixture("wide.png")), filename: "wide-#{index}.png", content_type: "image/png")
      asset.save!
      analyze(asset)
      asset
    end
    perform_enqueued_jobs

    loaded = Media::Asset.with_variants.where(id: assets.map(&:id)).to_a

    ActiveRecord::Base.uncached do
      assert_no_queries do
        loaded.each { |asset| assert_equal [ 480, 960, 1600, 2400 ], asset.srcset.map(&:last) }
      end
    end
  end

  # The other half of I2/I3: the processed check itself -- `#processed_
  # variant_digests` -- costs exactly one query total for all four widths,
  # not one per variant (the bug it fixes: plucking every digest for this
  # asset's blob once, up front, rather than asking Active Storage's own
  # `variant_records.find_by` once per width). Warms `file.blob` first,
  # the same as any earlier read in a real request (`#url`, `#src`) would
  # already have done before `#srcset` ever runs, so the one query this
  # asserts is only the digest lookup, not the attachment/blob association
  # loading for the first time -- a cost this fix has no way to remove and
  # isn't what I2/I3 are about.
  test "srcset's processed check costs exactly one query, not one per variant" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("wide.png")), filename: "wide.png", content_type: "image/png")
    asset.save!
    analyze(asset)
    perform_enqueued_jobs

    reloaded = Media::Asset.find(asset.id)
    reloaded.file.blob

    ActiveRecord::Base.uncached do
      assert_queries_count(1) { assert_equal [ 480, 960, 1600, 2400 ], reloaded.srcset.map(&:last) }
    end
  end

  private

  # Mirrors `Media::Upload#analyze_dimensions`: `file.analyze` needs the
  # blob's real bytes on the storage service, which only exist once this
  # record's save has actually committed.
  def analyze(asset)
    asset.file.analyze
    metadata = asset.file.blob.metadata || {}
    asset.update_columns(width: metadata["width"], height: metadata["height"])
  end
end
