module Tags
  # Renames a tag (spec §5.3), closing the foundations follow-up "tag rename
  # doesn't resync": a `post_list` block's `settings.tag` is a plain string,
  # not a reference to this row, so renaming the `Tag` itself touches no
  # `Post`, `PostTag` or `ContentBlock` -- none of which has a callback that
  # would otherwise notice a post's canonical URL just changed underneath it.
  # `PostTag#sync_post_paths` only fires on a join row being added or
  # removed, and nothing here does either.
  class Rename < ApplicationService
    def initialize(tag, name:, actor: Current.actor)
      @tag = tag
      @name = name.to_s.strip.downcase
      @actor = actor
    end

    # Needs `tags.manage` (access-control design spec §3.1): tags are shared
    # across every post, so there's no per-record scope to check.
    def call
      return denied("tags.manage", @tag) unless authorize!("tags.manage", @tag)

      old_name = @tag.name
      saved = Tag.transaction do
        @tag.name = @name
        @tag.save || raise(ActiveRecord::Rollback)

        changes = Audit::Snapshot.field_changes_for(@tag)
        record_event("tag.renamed", subject: @tag, field_changes: changes) if changes.any?
        true
      end

      return failure(@tag) unless saved

      resync(old_name, @tag.name)
      success(@tag)
    end

    private

    # Every content type a post_list block filtering by the tag's old *or*
    # new name could have handed a post's canonical page to, or taken one
    # away from (mirrors `ContentBlock#sync_listed_post_paths`'s own
    # before-and-after shape, but for the tag rather than the block): the
    # old name, because a post carrying this tag may have just fallen out of
    # a block that still names it; the new name, because the rename may have
    # just walked this tag straight into a block that already filtered by
    # it (two tags effectively merging under one listing). Both directions
    # matter regardless of which one actually changed anything -- cheaper to
    # resync a content type that turns out unaffected than to work out in
    # advance which of the two names a given block's posts actually needed.
    def resync(old_name, new_name)
      affected_content_types(old_name, new_name).each { |content_type| PublicSite::Paths.sync_posts(content_type) }
    end

    # `ContentBlock.listing` (every block with the `lists_posts` capability,
    # not just `post_list` by name -- open-types spec §6), filtered to the
    # ones whose own `tag` setting matches either name, case-insensitively
    # (the same comparison `BlockTypes::PostList.lists?` makes against a
    # post's actual tags). A block with no tag filter at all lists by
    # content type alone and is untouched by any tag rename -- its posts'
    # canonical pages can't have changed, so it's excluded here rather than
    # matched against a blank name that could never legitimately equal
    # either downcased argument.
    #
    # `content_type.presence` folds a blank filter to `nil`, which
    # `PublicSite::Paths.sync_posts` already reads as "every content type"
    # -- the same "or nil when an unfiltered listing is involved" case the
    # brief calls out. `select` + `map`, not `filter_map`: that `nil` is a
    # meaningful result here (sync everything), and `filter_map` would
    # silently drop it as if the block had never matched at all.
    def affected_content_types(old_name, new_name)
      names = [ old_name, new_name ].map { |name| name.to_s.downcase }

      matching = ContentBlock.listing.select do |block|
        tag = block.settings_object&.tag.to_s.strip
        tag.present? && names.include?(tag.downcase)
      end

      matching.map { |block| block.settings_object.content_type.presence }.uniq
    end
  end
end
