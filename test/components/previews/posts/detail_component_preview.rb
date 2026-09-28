require_relative "../preview_fixtures"

module Posts
  # `Posts::DetailComponent` (open-types spec §5), shared by every built-in
  # content type's `detail_component`.
  class DetailComponentPreview < ViewComponent::Preview
    def default
      post = PreviewFixtures.post(title: "Hello, world", excerpt: "The first post on this site.",
        body: PreviewFixtures.rich_doc("This is a sample post body, rendered the same way a permalink would."))
      post.tags << Tag.create!(name: "rails-#{SecureRandom.hex(4)}")

      render Posts::DetailComponent.new(post: post)
    end
  end
end
