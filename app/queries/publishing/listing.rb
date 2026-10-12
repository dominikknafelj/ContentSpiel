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
  # row (a page with no copy, the preview) by its filter's name as it is now.
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
          tag_id = tag_id_of(block) or return []
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
      def lists?(block, post)
        return false unless block.definition&.capability?(:lists_posts) && post.definition

        settings = block.settings_object
        return false if settings.content_type.present? && settings.content_type != post.content_type
        return true if settings.tag.to_s.strip.blank?

        (tag_id = tag_id_of(block)) ? tag_ids(post).include?(tag_id) : false
      end

      # A post's tags as the public sees them: its copy's, or its rows' when
      # it was not rebuilt from one.
      def tag_ids(post) = post.published_version ? post.published_version.tag_ids : post.tags.map(&:id)

      private

      # The tag a list block's filter names, by id. A block rebuilt from a copy
      # answers the id the copy recorded, and that id decides: a tag renamed
      # since changes nothing. A recorded nil means no tag of that name existed
      # when the copy was taken (it cannot be a rename), so the name is looked
      # up as it is now, once per call; a name no tag has lists nothing. A row
      # block already asks by name, and asking again is the same answer.
      def tag_id_of(block)
        block.listed_tag_id || Tag.named(block.settings_object.tag.to_s.strip).order(:id).pick(:id)
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
