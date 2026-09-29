# Media library Task 2: an asset gains its own editorial fields --
# `title` (a plain string, shown everywhere an asset is picked or listed,
# never blank: it always has *some* value to display, even before an editor
# has typed one) and `alt`/`caption` (jsonb, same shape as `content_blocks
# .alt`/`.caption` -- config/initializers/mobility.rb's jsonb backend, one
# entry per locale), the asset's own translated defaults that `Media::Asset
# #alt_text`/`#caption_text` fall back to when a placement doesn't override
# either (global constraints §"Images": "the asset's default in the locale,
# then the Mobility fallback").
#
# `title` backfills from each existing asset's own blob filename, minus its
# extension (`ActiveStorage::Filename#base`'s own rule, mirrored here in
# plain SQL since a data migration shouldn't depend on the app's current
# model classes surviving unchanged for as long as this migration stays in
# history -- same reasoning as `RenameMediaAssetType`). An asset with no
# attached blob (shouldn't exist -- `Media::Asset` validates `file` is
# attached -- but nothing stops a future direct SQL insert) simply keeps the
# column's own `""` default; there's no filename to derive one from.
#
# Fix round 1's M4: the `(?<=.)` lookbehind requires a real character
# *before* the dot the rest of the pattern strips -- without it, a dotfile
# name like `.gitignore` (or a bare `.png`) matched the whole `\.[^.]+$`
# pattern against itself and backfilled `title` to `""`, exactly the "no
# title yet" state this migration exists to avoid. `File.extname` (what
# `ActiveStorage::Filename#base` itself calls, `#base`'s own rdoc:
# `Filename.new(".gitignore").base # => ".gitignore"`) has the same rule:
# a leading dot with nothing after it *but* more dots isn't an extension.
# `"archive.tar.gz"` still only loses its last segment (`"archive.tar"`),
# matching `#base` there too -- the lookbehind only rules out matching at
# the very start of the string, it doesn't change *which* dot `$` anchors
# the match to.
class AddLibraryFieldsToMediaAssets < ActiveRecord::Migration[8.1]
  def up
    add_column :media_assets, :title, :string, null: false, default: ""
    add_column :media_assets, :alt, :jsonb, null: false, default: {}
    add_column :media_assets, :caption, :jsonb, null: false, default: {}

    backfill_titles
  end

  def down
    remove_column :media_assets, :caption
    remove_column :media_assets, :alt
    remove_column :media_assets, :title
  end

  private

  # Its own method (not inlined into `up`) so `test/migrations/add_library_
  # fields_to_media_assets_test.rb` can exercise just the backfill -- the
  # `add_column` calls above can't run twice against an already-migrated
  # database, but the regex this depends on (fix round 1's M4) is worth its
  # own regression test independent of the columns already being there.
  def backfill_titles
    execute <<~'SQL'
      UPDATE media_assets
      SET title = regexp_replace(blobs.filename, '(?<=.)\.[^.]+$', '')
      FROM active_storage_attachments attachments
      JOIN active_storage_blobs blobs ON blobs.id = attachments.blob_id
      WHERE attachments.record_type = 'Media::Asset'
        AND attachments.record_id = media_assets.id
        AND attachments.name = 'file'
    SQL
  end
end
