module Admin
  module TagsScreen
    # One tag's detail as the Tags list's rail shows it (needs a tag, and a
    # post or two carrying it, in the development database; an unsaved tag
    # with no posts otherwise).
    class DetailComponentPreview < ViewComponent::Preview
      def default
        tag = Tag.joins(:post_tags).first || Tag.new(id: 0, name: "music")
        posts = Post.kept.joins(:post_tags).where(post_tags: { tag_id: tag.id }).order(updated_at: :desc).limit(DetailComponent::DETAIL_POSTS).to_a
        render DetailComponent.new(tag:, posts:, count: posts.size + 4, carriers: posts.size + 5, locale: ::Locales.default)
      end

      # A viewer without `posts.read`: no count, no posts, the dialogs' neutral sentences.
      def without_posts_read
        render DetailComponent.new(tag: Tag.new(id: 0, name: "music"), posts: [], count: nil, carriers: nil, locale: ::Locales.default)
      end
    end
  end
end
