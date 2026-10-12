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
        scope = Post.published.kept.where(content_type: ContentTypes.names).includes(:tags)
        scope = scope.where(content_type: settings.content_type) if settings.content_type.present?
        if settings.tag.to_s.strip.present?
          tag_id = block.listed_tag_id or return []
          scope = scope.merge(carrying(tag_id, now))
        end
        scope = scope.order(published_at: :desc, id: :desc)
        scope = scope.limit(limit) if limit.present?
        Publishing.published_all(scope.to_a, now: now)
      end

      # Whether `block` lists `post`: a post as published, or a row.
      def lists?(block, post)
        return false unless block.definition&.capability?(:lists_posts) && post.definition

        settings = block.settings_object
        return false if settings.content_type.present? && settings.content_type != post.content_type
        return true if settings.tag.to_s.strip.blank?

        (tag_id = block.listed_tag_id) ? tag_ids(post).include?(tag_id) : false
      end

      # A post's tags as the public sees them: its copy's, or its rows' when
      # it was not rebuilt from one.
      def tag_ids(post) = post.published_version ? post.published_version.tag_ids : post.tags.map(&:id)

      private

      def carrying(tag_id, now)
        current = Version.current(now).where(record_type: "Post")
        copied = current.where(SqlNodes.array_contains(Version.arel_table[:tag_ids], [ tag_id ])).select(:record_id)
        bare = PostTag.where(tag_id: tag_id).where.not(post_id: current.select(:record_id)).select(:post_id)
        Post.where(id: copied).or(Post.where(id: bare))
      end
    end
  end
end
