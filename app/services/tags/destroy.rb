module Tags
  # Permanently deletes a tag (spec §5.3's "No trash" interim state, global
  # constraints), the same shape `ContentBlocks::Destroy` and
  # `Trash::Purge` use. Removing the tag's own `post_tags` (`Tag#has_many
  # :post_tags, dependent: :destroy`) already resyncs each of those posts'
  # own canonical page individually, through `PostTag#sync_post_paths`'s
  # `after_commit` -- but a tag-filtered `post_list` block's *other*
  # candidates (a post this listing didn't win before, now free to, or an
  # unfiltered listing elsewhere that should pick the post up) are only
  # correctly re-ranked by re-deriving every post of the affected content
  # type from scratch, the same `PublicSite::Paths.sync_posts` call
  # `Tags::Rename` makes -- so this resyncs explicitly too, rather than
  # leaning on `PostTag`'s callback alone to happen to cover it.
  class Destroy < ApplicationService
    def initialize(tag, actor: Current.actor)
      @tag = tag
      @actor = actor
    end

    # Needs `tags.manage`, like `Tags::Rename`. `tag.deleted` is recorded
    # before the destroy, in its transaction (the snapshot is the tag's last
    # state); the resync runs after it commits, as before.
    def call
      return denied("tags.manage", @tag) unless authorize!("tags.manage", @tag)

      content_types = affected_content_types
      destroyed = Tag.transaction do
        record_event("tag.deleted", subject: @tag)
        @tag.destroy || raise(ActiveRecord::Rollback)
      end
      return failure(@tag) unless destroyed

      content_types.each { |content_type| PublicSite::Paths.sync_posts(content_type) }
      success(@tag)
    end

    private

    # Computed *before* the destroy: once `@tag` (and its `post_tags`) are
    # gone, there is nothing left to look this up from, and a listing
    # block's own `settings.tag` is a plain string unrelated to the tag row
    # being removed, so it isn't touched by the destroy either way.
    def affected_content_types
      name = @tag.name.to_s.downcase

      matching = ContentBlock.listing.select do |block|
        tag = block.settings_object&.tag.to_s.strip
        tag.present? && tag.downcase == name
      end

      matching.map { |block| block.settings_object.content_type.presence }.uniq
    end
  end
end
