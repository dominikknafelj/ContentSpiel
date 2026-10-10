module Admin
  module EditorScreen
    # `Admin::EditorScreen::PostFormComponent` (cs-studio spec §5.2): a draft with no
    # canonical page yet (the "Not listed on any page yet" line), a live post
    # of a type with its own typed fields filled in, and a post whose stored
    # content type is no longer registered (spec §8's "unknown stored type
    # never 500s" -- the same case `Admin::EditorScreen::BlockCardComponentPreview`'s own
    # "Unavailable type" example covers for a block).
    class PostFormComponentPreview < ViewComponent::Preview
      def draft_post
        post = PreviewFixtures.post(title: "Draft post", content_type: "blog", published_at: nil)
        render Admin::EditorScreen::PostFormComponent.new(post: post, locale: "en")
      end

      def live_resume_entry
        post = PreviewFixtures.post(title: "Staff engineer", content_type: "resume_entry",
          metadata: { "company" => "Acme", "role_type" => "lead" })
        render Admin::EditorScreen::PostFormComponent.new(post: post, locale: "en")
      end

      def unregistered_content_type
        post = PreviewFixtures.post(title: "Old type", content_type: "blog")
        post.update_column(:content_type, "gone/thing")
        render Admin::EditorScreen::PostFormComponent.new(post: post.reload, locale: "en")
      end
    end
  end
end
