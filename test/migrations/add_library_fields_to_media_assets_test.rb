require "test_helper"
require Rails.root.join("db/migrate/20260929020000_add_library_fields_to_media_assets").to_s

# Media library Task 2's own migration (that migration's own comment, fix
# round 1's M4): `title` backfills from each asset's blob filename, minus
# its extension -- but only a real extension, the same rule `ActiveStorage
# ::Filename#base` itself follows. `title`/`alt`/`caption` already exist on
# the test database (this migration already ran against it, same as
# `test/migrations/rename_media_asset_type_test.rb`'s own setup comment),
# so this exercises `#backfill_titles` directly rather than the full `up`
# (whose `add_column` calls can't run twice) -- the same "run the migration
# directly against hand-built 'before' state" pattern every other test in
# this directory uses, just scoped to the one method with a regex worth its
# own regression test.
class AddLibraryFieldsToMediaAssetsMigrationTest < ActiveSupport::TestCase
  def backfill = AddLibraryFieldsToMediaAssets.new.send(:backfill_titles)

  def attach_with_filename(filename)
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: filename, content_type: "image/png")
    assert asset.save, asset.errors.full_messages.to_sentence
    asset.update_column(:title, "")
    asset
  end

  test "backfill strips a real extension, mirroring ActiveStorage::Filename#base" do
    asset = attach_with_filename("hero-photo.jpg")

    backfill

    assert_equal "hero-photo", asset.reload.title
  end

  test "backfill only strips the last extension of a multi-dot name" do
    asset = attach_with_filename("archive.tar.gz")

    backfill

    assert_equal "archive.tar", asset.reload.title
  end

  # M4: a dotfile-style name has no extension by `File.extname`'s own rule
  # (nothing precedes its one dot) -- `ActiveStorage::Filename.new
  # (".gitignore").base` is `".gitignore"`, unchanged, not `""`. Before the
  # `(?<=.)` lookbehind, the backfill's regex matched the whole name against
  # itself here and left `title` blank -- exactly the "no title yet" state
  # this migration exists to avoid.
  test "backfill leaves a dotfile-style name with no real extension untouched" do
    asset = attach_with_filename(".gitignore")

    backfill

    assert_equal ".gitignore", asset.reload.title
  end

  test "backfill leaves a bare extension-shaped name untouched" do
    asset = attach_with_filename(".png")

    backfill

    assert_equal ".png", asset.reload.title
  end
end
