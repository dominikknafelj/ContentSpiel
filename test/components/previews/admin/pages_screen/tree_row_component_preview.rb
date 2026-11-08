module Admin
  module PagesScreen
    # `Admin::PagesScreen::TreeRowComponent`: one page's row of the tree in
    # each state the server draws, alone and outside its `<li>` (so a movable
    # row's handle stands in a gutter that is not drawn). Hover and focus are
    # the browser's.
    class TreeRowComponentPreview < ViewComponent::Preview
      def rest
        row(PreviewFixtures.page(title: "About"))
      end

      def selected
        about = PreviewFixtures.page(title: "About")
        row(about, selected: about, child_count: 2)
      end

      def context_only
        row(PreviewFixtures.page(title: "Members area"), context_only: true, child_count: 1)
      end

      def draft
        row(child(title: "Draft page", published_at: nil))
      end

      def scheduled
        row(child(title: "Coming soon", published_at: 1.week.from_now))
      end

      def changes
        row(child(title: "Live, with changes", published_at: 1.day.ago, unpublished_changes_at: Time.current))
      end

      def markers
        row(PreviewFixtures.page(title: "Translating"), child_count: 3,
          translation_counts: { "de" => { outdated: 2, missing: 1 }, "es" => { outdated: 0, missing: 3 } })
      end

      def long_title
        row(PreviewFixtures.page(title: "Datenschutzerklärung und Hinweise zur Verarbeitung personenbezogener Daten"))
      end

      private

      def child(title:, **attributes)
        PreviewFixtures.root_page.children.create!(title: "#{title} #{SecureRandom.hex(4)}", **attributes)
      end

      def row(page, selected: nil, child_count: 0, translation_counts: {}, context_only: false)
        render Admin::PagesScreen::TreeRowComponent.new(page: page, child_count: child_count, translation_counts: translation_counts,
          loaded: {}, selected: selected, locale: "en", url_options: {}, context_only: context_only)
      end
    end
  end
end
