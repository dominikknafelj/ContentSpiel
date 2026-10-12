module Publishing
  # What a list block lists AS PUBLISHED (drafts spec §5). Three things meet:
  # the block (the page's copy: its type and tag filter, the tag by the id the
  # copy recorded), each post's tags (the post's copy: `tag_ids`), and what
  # stays on the rows for every reader: the post's content type, its
  # `published_at`, the trash. Matching is by tag ID, never by name: the two
  # copies are taken at different times, and a tag renamed in between would
  # otherwise empty the list.
  #
  # A post with no current copy is judged by its rows, and a block that is a
  # row (a page with no copy, a draft, the preview) by its filter's name as
  # it is now. A block of a COPY is never asked by name: the copy recorded
  # the tag's id, or that no tag had the name, and then it lists nothing
  # until its page is published again (`ContentBlock#tag_recorded?`).
  class Listing
    class << self
      # The posts a visitor sees in `block`'s list, newest first, each as
      # published. Which posts is decided in the database, limit included:
      # the type's posts live at `now` and not trashed, filtered by tag as
      # follows. A post with a CURRENT copy is judged by the copy's `tag_ids`
      # (`SqlNodes.array_contains`, a subquery over current copies of posts).
      # A live post with NO current copy (written around the services; the
      # public serves it from its rows) is judged by its rows' own tags
      # (`post_tags`), so it is listed exactly when its rows carry the tag.
      # Only the posts that survive the limit are then rebuilt from their
      # copies: a fixed number of statements, rows bounded by the limit.
      def posts(block, limit: nil, now: Time.current)
        settings = block.settings_object
        scope = Post.where(published_at: ..now).kept.where(content_type: ContentTypes.names)
        scope = scope.where(content_type: settings.content_type) if settings.content_type.present?
        if settings.tag.to_s.strip.present?
          tag_id = block.listed_tag_id or return []
          scope = scope.merge(carrying(tag_id, now))
        end
        scope = scope.order(published_at: :desc, id: :desc)
        scope = scope.limit(limit) if limit.present?
        views = Publishing.published_all(scope.to_a, now: now)
        # Only a post served from its rows needs its rows' tags; a rebuilt one
        # has the copy's.
        from_rows = views.reject(&:published_version)
        ActiveRecord::Associations::Preloader.new(records: from_rows, associations: :tags).call if from_rows.any?
        views
      end

      # Whether `block` lists `post`: a post as published, or a row.
      #
      # `tags:` is for a caller that judges many posts against many blocks
      # (`PublicSite::Paths.canonical_pages`): the answer of `filter_tags` for
      # those blocks, so that no row block's tag is looked up once per post.
      # Without it the block answers itself (`ContentBlock#listed_tag_id`).
      def lists?(block, post, tags: nil)
        return false unless block.definition&.capability?(:lists_posts) && post.definition

        settings = block.settings_object
        return false if settings.content_type.present? && settings.content_type != post.content_type
        return true if settings.tag.to_s.strip.blank?

        (tag_id = tags ? tags[block] : block.listed_tag_id) ? tag_ids(post).include?(tag_id) : false
      end

      # `{ block => tag id or nil }` for the blocks among `blocks` that filter
      # by a tag, in ONE statement however many there are: a copy's block
      # answers what the copy recorded, and the names the ROW blocks filter
      # by are looked up together, as they are now. Compared by identity: a
      # block is asked for as the very object that was handed in.
      def filter_tags(blocks)
        filtered = blocks.select { |block| filter_name(block).present? }
        names = filtered.reject(&:tag_recorded?).map { |block| filter_name(block).downcase }.uniq
        # The lowest id of a name, as `ContentBlock#listed_tag_id` picks it.
        by_name = names.empty? ? {} : Tag.named_any(names).order(:id).pluck(:name, :id)
          .each_with_object({}) { |(name, id), found| found[name.downcase] ||= id }
        filtered.each_with_object({}.compare_by_identity) do |block, found|
          found[block] = block.tag_recorded? ? block.listed_tag_id : by_name[filter_name(block).downcase]
        end
      end

      # Every list block of the site AS PUBLISHED, for `PublicSite::Paths`:
      # of a kept page that is published or scheduled and has a copy in force,
      # the list blocks of its current copy; of every other kept page (a
      # draft, whatever copies it kept, and a live page written around the
      # services), its rows'. That is the rule `Publishing.published_all`
      # serves a page by, so an address exists under the page whose public
      # list shows the post. A trashed page has none.
      #
      # Each block's `owner` is the page's ROW: what `canonical_pages` ranks
      # and answers.
      #
      # Four statements whatever the number of pages (the row blocks and their
      # owners, the copies, their pages, and nothing per page), and only the
      # copies that list posts are loaded: the newest copy of each page is
      # chosen among the pages that ever had a copy listing posts, so a site's
      # other copies are neither grouped nor read.
      def blocks(now: Time.current)
        pages = Page.kept
        copying = pages.where.not(published_at: nil).where(id: Version.in_force(now).where(record_type: "Page").select(:record_id))

        rows = ContentBlock.listing.where(owner_type: "Page", owner_id: pages.where.not(id: copying.select(:id)).select(:id)).includes(:owner).to_a
        copies = current_copies_listing(now).where(record_id: copying.select(:id)).to_a
        owners = Page.where(id: copies.map(&:record_id)).index_by(&:id)
        copied = copies.flat_map do |version|
          Snapshot.blocks_from(version, owners.fetch(version.record_id)).select { |block| block.definition&.capability?(:lists_posts) }
        end
        rows + copied
      end

      # A post's tags as the public sees them: its copy's, or its rows' when
      # it was not rebuilt from one.
      def tag_ids(post) = post.published_version ? post.published_version.tag_ids : post.tags.map(&:id)

      private

      def filter_name(block) = block.settings_object.tag.to_s.strip

      # The pages' copies in force that list posts, each page's newest: the
      # grouping is narrowed INSIDE to the pages that ever had such a copy (a
      # page whose newest copy lists nothing is then dropped by the outer
      # condition), so the index serves it.
      def current_copies_listing(now)
        ever = Version.unscoped.where(record_type: "Page", lists_posts: true).select(:record_id)
        newest = Version.unscoped.in_force(now).where(record_type: "Page", record_id: ever).group(:record_id).select(Version.arel_table[:id].maximum)
        Version.unscoped.where(id: newest, lists_posts: true)
      end

      def carrying(tag_id, now)
        # Narrowed to posts INSIDE the grouping, so the index serves it and
        # pages' copies are never grouped.
        newest = Version.unscoped.in_force(now).where(record_type: "Post").group(:record_id).select(Version.arel_table[:id].maximum)
        current = Version.unscoped.where(id: newest)
        copied = current.where(SqlNodes.array_contains(Version.arel_table[:tag_ids], [ tag_id ])).select(:record_id)
        bare = PostTag.where(tag_id: tag_id).where.not(post_id: current.select(:record_id)).select(:post_id)
        Post.where(id: copied).or(Post.where(id: bare))
      end
    end
  end
end
