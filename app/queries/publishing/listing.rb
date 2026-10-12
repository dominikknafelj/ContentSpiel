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
      # published. A fixed number of statements however many posts: the
      # candidates (with their row tags, for a post that has no copy), their
      # copies in one statement, and nothing per post. Without a tag filter
      # the limit is applied in SQL; with one, the candidates are judged by
      # their published tags first, so the whole type is read once.
      def posts(block, limit: nil, now: Time.current)
        settings = block.settings_object
        scope = Post.published.kept.where(content_type: ContentTypes.names).includes(:tags)
        scope = scope.where(content_type: settings.content_type) if settings.content_type.present?
        scope = scope.order(published_at: :desc, id: :desc)

        if settings.tag.to_s.strip.present?
          tag_id = block.listed_tag_id or return []
          views = Publishing.published_all(scope.to_a, now: now)
          views = views.select { |view| tag_ids(view).include?(tag_id) }
          limit.present? ? views.first(limit) : views
        else
          scope = scope.limit(limit) if limit.present?
          Publishing.published_all(scope.to_a, now: now)
        end
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
    end
  end
end
