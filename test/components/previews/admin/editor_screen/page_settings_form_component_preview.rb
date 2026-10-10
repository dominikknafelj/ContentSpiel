module Admin
  module EditorScreen
    # `Admin::EditorScreen::PageSettingsFormComponent` (cs-studio spec §5.1): a standard
    # page (no hero fields), a landing page (hero image + alt shown), and the
    # homepage itself (no slug field -- it has none of its own).
    class PageSettingsFormComponentPreview < ViewComponent::Preview
      def standard_page
        page = PreviewFixtures.page(title: "Standard page")
        render Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "en")
      end

      def landing_page
        page = PreviewFixtures.root_page.children.create!(page_type: :landing, title: "Landing page #{SecureRandom.hex(4)}", published_at: Time.current)
        render Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "en")
      end

      def homepage
        render Admin::EditorScreen::PageSettingsFormComponent.new(page: PreviewFixtures.root_page, locale: "en")
      end
    end
  end
end
