module Tags
  # Permanently deletes a tag (spec §5.3's "No trash" interim state, global
  # constraints), the same shape `Pages::Destroy`/`ContentBlocks::Destroy`
  # already use. Removing the tag's own `post_tags` (`Tag#has_many
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

    def call
      authorize!(:destroy, @tag)

      content_types = affected_content_types
      return failure(@tag) unless @tag.destroy

      content_types.each { |content_type| PublicSite::Paths.sync_posts(content_type) }
      record_event(:tag_destroyed, tag: @tag)
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
