module Media
  # Edits a library image's own details (media library design spec §5.1):
  # its `title` (from `attributes`, the only attribute taken -- the file,
  # its metadata and `created_by` never change after upload) and its
  # translated alt/caption defaults, per locale (`translations`, the same
  # shape as `Pages::Save`'s). A placement's own overrides live on the
  # placement (a block's `alt`/`caption`, a rich-text node's attributes)
  # and are saved with it, not here.
  #
  # Needs `media.manage`, or to be the image's uploader (`Media::
  # Ownership`, which also documents what that means for a token).
  # Recorded as `media.updated` (coalescing like every `*.updated`) with
  # the field changes; a save that changed nothing records nothing.
  class Save < ApplicationService
    include Ownership

    TRANSLATED = %i[alt caption].freeze

    def initialize(asset, attributes: {}, translations: {}, actor: Current.actor)
      @asset = asset
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      return denied("media.manage", @asset) unless authorize!("media.manage", @asset) || uploader_may_manage?(@asset)

      saved = Media::Asset.transaction do
        assign
        @asset.save || raise(ActiveRecord::Rollback)

        changes = Audit::Snapshot.field_changes_for(@asset)
        record_event("media.updated", subject: @asset, field_changes: changes) if changes.any?
        true
      end

      return failure(@asset) unless saved

      success(@asset)
    end

    private

    def assign
      @asset.assign_attributes(@attributes.slice(:title))

      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @asset.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
    end
  end
end
