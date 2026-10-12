module Tags
  # What `Tags::Rename`, `Tags::Destroy` and `Tags::Merge` share: a tag is a
  # plain string in a `post_list` block's `settings` and a join row on each post,
  # so changing one reaches content nothing in the tag row itself points at.
  # These helpers find that content (the listing blocks that filter by a name,
  # the posts that carry a tag) so the three services agree on what "affected"
  # means -- a fourth copy of the case-insensitive match would drift from
  # `BlockTypes::PostList.listed_posts`, which is what the match mirrors.
  module Listings
    private

    # `ContentBlock.listing` (every block with the `lists_posts` capability,
    # not just `post_list` by name -- open-types spec §6) whose own `tag`
    # setting matches one of `names`, case-insensitively (the comparison
    # `BlockTypes::PostList.lists?` and `.listed_posts` make against a tag
    # name, trimmed). A block with no tag filter lists by content type alone
    # and is never matched: it can't be affected by any tag change, and a blank
    # would otherwise "equal" a blank name. Blocks on trashed pages are
    # included on purpose: they come back with the page, so they must already
    # name the right tag then.
    def listing_blocks_naming(*names)
      ContentBlock.listing.select { |block| block_names_tag?(block, names) }
    end

    # The match itself, for one block as loaded -- also asked of a block
    # re-read under a lock (`Tags::Merge#repoint_blocks`), so "names this tag"
    # has one definition whenever it is asked.
    def block_names_tag?(block, names)
      names = Array(names).map { |name| name.to_s.strip.downcase }.reject(&:blank?)
      tag = block.settings_object&.tag.to_s.strip
      tag.present? && names.include?(tag.downcase)
    end

    # WHAT A TAG SERVICE TOUCHED, for `PublicSite::Paths.refresh`: the pages
    # whose list blocks refer to a tag. Only a tag service can know them, so
    # this finder is theirs; which posts follow from those pages is the
    # refresh's to know.
    #
    # A ROW refers to a tag by name (a draft's blocks, and those of a page
    # written around the services): the owners of the row blocks that filter
    # by one of `names`. A published COPY refers to it by the id it
    # recorded, and never by name: the pages one of whose copies recorded one
    # of `ids`. A rename changes no id, so it passes names only.
    def pages_listing(names: [], ids: [])
      rows = listing_blocks_naming(*names).select { |block| block.owner_type == Page.polymorphic_name }.map(&:owner_id)
      (rows + Publishing::Version.listing_tag(ids).pluck(:record_id)).uniq
    end

    # An open post form resends every tag chip on every autosave, so a post
    # that carried `tag` and is being edited right now would put the tag
    # straight back (`Posts::Save#build_tag` creates a name it can't find).
    # Touching the carrying posts -- kept AND trashed, because a trashed post
    # restored later must not resurrect the old name either -- moves their
    # `updated_at`, so that form's next save is refused as "Changed elsewhere"
    # (`refuse_stale_autosave`), the same protection `Posts::Save` gives another
    # editor's tag-only change. `touch_all` skips callbacks and validations on
    # purpose: only the stale-save base moves. Must run before the tag's join
    # rows are removed, which is what it reads.
    def touch_carrying_posts(tag)
      Post.where(id: tag.post_tags.select(:post_id)).touch_all
      # `touch_all` runs no `after_commit` on the posts, and what follows it
      # (a rename, a delete, a merge) changes what they print and which
      # listings show them: the public content version moves, whether or not
      # a carrier is live.
      PublicSite.bump_version!
    end
  end
end
