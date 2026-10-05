module Tags
  # Renames a tag (spec §5.3), closing the foundations follow-up "tag rename
  # doesn't resync": a `post_list` block's `settings.tag` is a plain string,
  # not a reference to this row, so renaming the `Tag` itself touches no
  # `Post`, `PostTag` or `ContentBlock` -- none of which has a callback that
  # would otherwise notice a post's canonical URL just changed underneath it.
  # `PostTag#sync_post_paths` only fires on a join row being added or
  # removed, and nothing here does either.
  class Rename < ApplicationService
    include Tags::Listings

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
        # An open post form resends the tag's *old* name on its next autosave,
        # which `Posts::Save` would create anew and attach, leaving both names
        # on the post. Touching the carrying posts moves their `updated_at`,
        # so that form's save is refused as "Changed elsewhere" instead
        # (`touch_all`: callbacks and validations skipped, only the base moves).
        # Only when the name really changed: a rename to the same name is no
        # change and records no event, so it must not stale those forms.
        touch_carrying_posts(@tag) if @tag.saved_change_to_name?

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
  end
end
