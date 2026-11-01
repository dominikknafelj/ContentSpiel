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

  test "a file over the site's largest upload is refused with its size in the sentence" do
    SiteSetting.instance.update!(image_max_upload_mb: 1)
    big = File.binread(file_fixture("tiny.png")) + ("\x00".b * (1.megabyte + 100))
    asset = Media::Asset.new
    asset.file.attach(io: StringIO.new(big), filename: "big.png", content_type: "image/png")

    assert_not asset.valid?
    assert_includes asset.errors[:file], "must be 1 MB or smaller"
  end

  test "a file that cannot be read as an image is refused, and nothing is kept" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("not_an_image.png")), filename: "broken.png", content_type: "image/png")

    assert_no_difference [ "Media::Asset.count", "ActiveStorage::Blob.count" ] do
      assert_not asset.save
    end
    assert_includes asset.errors.full_messages, "File can't be read as an image"
  end

  test "an image over 100 megapixels is refused with its own sentence" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("huge_pixels.png")), filename: "huge.png", content_type: "image/png")

    assert_not asset.valid?
    assert_includes asset.errors[:file], "is too large to process (over 100 megapixels)"
  end

  test "a saved asset has its width, height and preview before the save commits" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("transparent.png")), filename: "t.png", content_type: "image/png")

    asset.save! # no job is performed: the size comes from the validation's decode

    row = Media::Asset.find(asset.id)
    assert_equal [ 30, 20 ], [ row.width, row.height ]
    assert_equal 24, Vips::Image.new_from_buffer(row.preview, "").width
    assert row.has_alpha
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

  test "with no generation srcset is empty and src is the preview, never the original" do
    asset = create_media_asset
    assert asset.preview.present?

    assert_equal [], asset.srcset
    assert asset.src.start_with?("data:image/webp;base64,")
    assert_equal asset.preview, Base64.strict_decode64(asset.src.delete_prefix("data:image/webp;base64,"))
    assert_not_includes asset.src, "/blobs/"
    assert_not_includes asset.thumbnail_url, "/blobs/"
  end

  test "with no generation and no preview src is nil" do
    asset = create_media_asset
    asset.update_columns(preview: nil) # version: none (a test removes the derived preview)

    assert_nil asset.reload.src
    assert_nil asset.display_url(min_width: 480)
    assert_nil asset.thumbnail_url
  end

  test "with a generation srcset lists exactly its widths as proxy representation addresses and src is the middle one" do
    asset = make_renditions!(create_media_asset, widths: [ 480, 960, 1600 ])

    assert_equal [ 480, 960, 1600 ], asset.srcset.map(&:last)
    asset.srcset.each do |url, width|
      key = asset.generation.files.find { |f| f.width == width }.key
      assert url.start_with?("/rails/active_storage/representations/proxy/#{asset.file.blob.signed_id}/#{key}/"), url
      assert_not_includes url, "?"
    end
    assert_equal asset.srcset[1].first, asset.src
    assert asset.made?
    assert asset.made_with?(ImageSettings.current.fingerprint)
    assert_not asset.made_with?("other")

    four = make_renditions!(asset, widths: [ 480, 960, 1600, 2400 ])
    assert_equal four.srcset[1].first, four.src
  end

  test "the srcset of fifty assets loaded with with_file costs no query" do
    created = Array.new(3) { make_renditions!(create_media_asset, widths: [ 480, 960 ]) }
    ids = created.map(&:id) * 1
    assets = Media::Asset.with_file.where(id: ids).to_a * 17

    statements = capture_sql { assets.each(&:srcset) }

    assert_empty statements
  end

  test "display_url takes the smallest width that covers, else the largest, else the preview" do
    asset = make_renditions!(create_media_asset, widths: [ 480, 960, 1600 ])
    by_width = asset.srcset.to_h { |url, width| [ width, url ] }

    assert_equal by_width[480], asset.display_url(min_width: 100)
    assert_equal by_width[960], asset.display_url(min_width: 481)
    assert_equal by_width[1600], asset.display_url(min_width: 5000)
    assert_equal by_width[480], asset.thumbnail_url

    asset.update_columns(renditions: {}) # version: none (a test removes the generation)
    assert asset.reload.display_url(min_width: 480).start_with?("data:image/webp")
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

  # Final fix wave (I1): a translated override (a block's `alt`, a page's
  # `hero_alt`) arrives as its `{locale => value}` hash and is interleaved
  # per locale -- the override in a locale, then the asset in that locale,
  # then the next locale in the fallback chain -- so another locale's
  # override never beats this locale's asset default.
  test "#alt_text interleaves a per-locale override with the asset's defaults along the fallback chain" do
    asset = create_media_asset
    Mobility.with_locale(:de) { asset.update!(alt: "Deutscher Alt-Text") }
    Mobility.with_locale(:en) { asset.update!(alt: "English alt") }

    assert_equal "Deutscher Alt-Text", asset.alt_text(override: { "en" => "Override en" }, locale: "de")
    assert_equal "Override de", asset.alt_text(override: { "en" => "Override en", "de" => "Override de" }, locale: "de")
    assert_equal "Override en", asset.alt_text(override: { "en" => "Override en", "de" => "" }, locale: "es")
    assert_equal "English alt", asset.alt_text(override: {}, locale: "es")
    assert_nil asset.caption_text(override: { "de" => "" }, locale: "de")
    assert_equal "Caption en", asset.caption_text(override: { en: "Caption en" }, locale: "de")
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
end
