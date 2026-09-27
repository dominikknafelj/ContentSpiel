require_relative "../preview_fixtures"

module Blocks
  # `Blocks::PostListComponent` (open-types spec §5): the registry dispatch
  # to a content type's own `list_component`, an empty listing, and a
  # `limit` trimming it -- the three states `Blocks::PostListComponentTest`
  # exercises directly.
  class PostListComponentPreview < ViewComponent::Preview
    def blog
      page = PreviewFixtures.page(title: "Post list preview (blog)")
      block = PreviewFixtures.post_list_block(page, "content_type" => "blog")
      PreviewFixtures.post(title: "Notes on Hotwire", excerpt: "What stayed simple")
      PreviewFixtures.post(title: "A second post")

      render Blocks::PostListComponent.new(block: block, page: page)
    end

    def empty
      page = PreviewFixtures.page(title: "Post list preview (empty)")
      block = PreviewFixtures.post_list_block(page, "content_type" => "blog", "tag" => "no-such-tag")

      render Blocks::PostListComponent.new(block: block, page: page)
    end

    def limited
      page = PreviewFixtures.page(title: "Post list preview (limited)")
      block = PreviewFixtures.post_list_block(page, "content_type" => "blog", "limit" => 1)
      PreviewFixtures.post(title: "First post")
      PreviewFixtures.post(title: "Second post")
      PreviewFixtures.post(title: "Third post")

      render Blocks::PostListComponent.new(block: block, page: page)
    end
  end
end
