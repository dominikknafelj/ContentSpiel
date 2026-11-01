# A processed image variant of a page's own file (the site logo's, say) moves
# the public content version (`PublicSite`, technical cleanup spec 4.8): a
# rendered page bakes in the address of what it shows, and a variant record
# committing (or going, with a purged blob) changes what can be shown.
#
# A variant of a LIBRARY image is the exception: the library's widths bump
# once per image, from `Media::RenditionJob`, when the generation that lists
# them is recorded. A page never lists a width before that, so the variant
# records the job makes one by one change nothing a cached page holds, and a
# bump for each would empty the site's caches four times per upload.
#
# Through the load hook, not a reopened class: `ActiveStorage::VariantRecord`
# is the framework's, autoloaded and reloaded in development, and the hook
# runs each time it loads.
ActiveSupport.on_load(:active_storage_variant_record) do
  after_commit do
    library_file = ActiveStorage::Attachment.exists?(blob_id: blob_id, record_type: "Media::Asset", name: "file")
    PublicSite.bump_version! unless library_file
  end
end
