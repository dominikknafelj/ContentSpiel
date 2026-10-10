module Admin
  module EditorScreen
    # `Admin::EditorScreen::RelatedPostsComponent` (design spec §6.1, Task 9): the post
    # editor's related-posts picker with nothing chosen yet, and with forward
    # relations plus a post that relates back to this one (the read-only
    # "Also related from" line).
    class RelatedPostsComponentPreview < ViewComponent::Preview
      def empty
        render Admin::EditorScreen::RelatedPostsComponent.new(post: PreviewFixtures.post(title: "Lonely post"), locale: "en")
      end

      def with_relations
        post = PreviewFixtures.post(title: "Hub post")
        PostRelation.create!(post: post, related_post: PreviewFixtures.post(title: "Related one"))
        PostRelation.create!(post: post, related_post: PreviewFixtures.post(title: "Related two", content_type: "now_update"))
        PostRelation.create!(post: PreviewFixtures.post(title: "Points back"), related_post: post)
        render Admin::EditorScreen::RelatedPostsComponent.new(post: post, locale: "en")
      end

      def with_error
        post = PreviewFixtures.post(title: "Broken relation")
        render Admin::EditorScreen::RelatedPostsComponent.new(post: post, locale: "en", errors: [ "Related post ids include posts that don't exist" ])
      end
    end
  end
end
