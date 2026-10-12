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
        if @tag.saved_change_to_name?
          touch_carrying_posts(@tag)
          # The lists that named the old name or name the new one (a name
          # that matched no tag until now) resolve to another tag.
          note_pages_changed(pages_listing(names: [ old_name, @tag.name ]))
        end

        changes = Audit::Snapshot.field_changes_for(@tag)
        record_event("tag.renamed", subject: @tag, field_changes: changes) if changes.any?
        true
      end

      return failure(@tag) unless saved

      # A list block's `tag` setting is a plain string: the ROW blocks that
      # filter by the name the tag left have lost its posts, and the ones
      # that filter by the name it arrived at have gained them (two tags
      # effectively meeting under one list). Their pages are what was
      # touched. A published copy holds the tag's id, which a rename does
      # not change, so no copy's list moves.
      PublicSite::Paths.refresh(pages: pages_listing(names: [ old_name, @tag.name ]))
      success(@tag)
    end
  end
end
