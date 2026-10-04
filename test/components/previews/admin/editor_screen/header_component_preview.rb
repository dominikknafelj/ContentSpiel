module Admin
  module EditorScreen
    # `Admin::EditorScreen::HeaderComponent`: a draft (one primary Publish), a
    # scheduled page (Publish now + Edit schedule), a live one (no primary,
    # the live hint), the homepage (Move to trash disabled with its reason),
    # and a post.
    class HeaderComponentPreview < ViewComponent::Preview
      def draft
        page = PreviewFixtures.root_page.children.create!(page_type: :standard, title: "Draft page #{SecureRandom.hex(4)}")
        render Admin::EditorScreen::HeaderComponent.new(record: page, locale: "en")
      end

      def scheduled
        page = PreviewFixtures.root_page.children.create!(page_type: :standard, title: "Scheduled page #{SecureRandom.hex(4)}", published_at: 1.week.from_now)
        render Admin::EditorScreen::HeaderComponent.new(record: page, locale: "en")
      end

      def live
        render Admin::EditorScreen::HeaderComponent.new(record: PreviewFixtures.page(title: "Live page"), locale: "en")
      end

      def homepage_delete_disabled
        render Admin::EditorScreen::HeaderComponent.new(record: PreviewFixtures.root_page, locale: "en")
      end

      def post
        render Admin::EditorScreen::HeaderComponent.new(record: PreviewFixtures.post(title: "Draft post", content_type: "blog", published_at: nil), locale: "en")
      end
    end
  end
end
