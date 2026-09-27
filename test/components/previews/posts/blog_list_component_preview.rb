require_relative "../preview_fixtures"

module Posts
  # `Posts::BlogListComponent` (open-types spec §5), and the empty-list state
  # (no posts match a listing block's criteria).
  class BlogListComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Blog list preview")
      PreviewFixtures.post_list_block(page, "content_type" => "blog")
      post = PreviewFixtures.post(title: "Notes on Hotwire", excerpt: "What stayed simple")
      post.tags << Tag.create!(name: "rails-#{SecureRandom.hex(4)}")

      render Posts::BlogListComponent.new(posts: Post.where(id: post.id), page: page)
    end

    def empty
      page = PreviewFixtures.page(title: "Blog list preview (empty)")

      render Posts::BlogListComponent.new(posts: Post.none, page: page)
    end
  end
end
