require_relative "../preview_fixtures"

module Posts
  # `Posts::NowListComponent` (open-types spec §5): the latest update, and
  # the empty state -- the pre-flight ruling's whole-list component still
  # has to handle "there is no latest update yet" itself.
  class NowListComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Now list preview")
      post = PreviewFixtures.post(title: "Now", content_type: "now_update", body_doc: PreviewFixtures.rich_doc("Training for a half marathon."))

      render Posts::NowListComponent.new(posts: Post.where(id: post.id), page: page)
    end

    def empty
      page = PreviewFixtures.page(title: "Now list preview (empty)")

      render Posts::NowListComponent.new(posts: Post.none, page: page)
    end
  end
end
