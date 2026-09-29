module Media
  # Deletes a library image (media library design spec §5.1). Cleanup is
  # manual only, and an image in use is never deleted:
  #
  # - Refused while any `media_usages` row names it, with a message saying
  #   where it's used (`#in_use_message`) so the editor can go and swap it
  #   out first.
  # - The index can be behind -- a reference written outside the services,
  #   or a save racing this delete between the check and the `DELETE`
  #   (Review Focus 4). The `on_delete: :restrict` FKs on `pages`/
  #   `content_blocks` still refuse the row, and that
  #   `ActiveRecord::InvalidForeignKey` becomes an ordinary failure here,
  #   never a 500. (A rich-text `image` node has no FK -- a document that
  #   still names a deleted asset renders without it, and `Media::
  #   UsageIndex` skips the dead reference.)
  #
  # Needs `media.manage`, or to be the image's uploader (`Media::
  # Ownership`). `media.deleted` is recorded before the destroy, in its
  # transaction, so the snapshot is the asset's last state and a refused
  # destroy leaves no event.
  #
  # The file itself is purged only after the delete commits: `has_one_
  # attached`'s default `dependent: :purge_later` enqueues the purge from
  # an `after_destroy_commit`, so a rolled-back delete (the FK case above)
  # keeps its file, and storage isn't touched inside the transaction.
  class Destroy < ApplicationService
    include Ownership

    # How many places the refusal names before summing up the rest as
    # "and N more".
    NAMED_PLACES = 3

    def initialize(asset, actor: Current.actor)
      @asset = asset
      @actor = actor
    end

    def call
      return denied("media.manage", @asset) unless authorize!("media.manage", @asset) || uploader_may_manage?(@asset)
      return failure(@asset, [ in_use_message ]) if @asset.used?

      destroyed = Media::Asset.transaction(requires_new: true) do
        record_event("media.deleted", subject: @asset)
        @asset.destroy || raise(ActiveRecord::Rollback)
      end

      # A destroy halted by a callback may add no error of its own (final
      # fix wave, T6b) -- `Result.failure`'s generic fallback would then
      # say "could not be saved", which is the wrong verb here.
      return failure(@asset, @asset.errors.full_messages.presence || [ "This image couldn't be deleted" ]) unless destroyed

      success(@asset)
    rescue ActiveRecord::InvalidForeignKey
      failure(@asset, [ "This image is still in use and can't be deleted" ])
    end

    private

    # "This image is used on the page “About”, the post “Hello” and 2
    # more". A block's usage is named by the page or post it sits on, and
    # a place is named once however many ways it uses the image (a hero
    # and a block on the same page, a body image in two locales). A place
    # the actor can't read isn't disclosed ("not found, not forbidden"):
    # it's "a page you can't open" instead of its title.
    def in_use_message
      usages = @asset.usages.includes(:owner).order(:id).to_a
      # Fix round 1 (review of `0695e7a`): batches the `ContentBlock#owner`
      # second hop for every block-owned row in one shot, one query per
      # owner type (Page, Post) -- see `Media::Asset.preload_usage_places`'s
      # own comment for why this can't just share `#usages_summary`'s own
      # query (this needs the strict `.order(:id)` above, which that method
      # doesn't promise).
      Media::Asset.preload_usage_places(usages.map(&:owner))
      places = usages.map { |usage| place_of(usage.owner) }.compact.uniq
      # Only rows whose owner is already gone (a stale index): still refused.
      return "This image is still in use and can't be deleted" if places.empty?

      named = places.first(NAMED_PLACES).map { |place| describe(place) }
      named << "#{places.size - NAMED_PLACES} more" if places.size > NAMED_PLACES

      "This image is used on #{named.to_sentence(two_words_connector: " and ", last_word_connector: " and ")}"
    end

    def place_of(owner) = owner.is_a?(ContentBlock) ? owner&.owner : owner

    def describe(place)
      kind = place.is_a?(Post) ? "post" : "page"
      return "a #{kind} you can't open" unless AccessControl.allowed?(actor, "#{kind}s.read", place)

      "the #{kind} “#{Audit::Snapshot.label_for(place)}”"
    end
  end
end
