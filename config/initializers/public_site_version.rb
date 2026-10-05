# A processed image variant moves the public content version (`PublicSite`,
# technical cleanup spec §4.8). `Media::Asset#srcset` lists only the variants
# that have a finished `ActiveStorage::VariantRecord`, so a `TransformJob`
# completing -- well after the upload, with no `Media::Asset` row changing --
# changes the `<img srcset>` a page renders and a cached rich-text body holds.
# Without the bump, a body rendered before its image's variants existed would
# keep serving `src`-only HTML until some unrelated published change.
#
# Every commit of a variant record, a deletion included (a purged blob takes
# its variants with it), and whichever attachment it belongs to: the site
# logo's variants bump too, which costs only cache.
#
# Through the load hook, not a reopened class: `ActiveStorage::VariantRecord`
# is the framework's, autoloaded and reloaded in development, and the hook
# runs each time it loads.
ActiveSupport.on_load(:active_storage_variant_record) do
  after_commit { PublicSite.bump_version! }
end
