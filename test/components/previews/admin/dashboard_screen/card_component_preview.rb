module Admin
  module DashboardScreen
    # The dashboard's card shell: rows, the "→" link, the hint under a short
    # list, and the in-card empty state.
    class CardComponentPreview < ViewComponent::Preview
      def with_rows
        render Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "preview-drafts", empty: "No drafts — start one above.",
          link: [ "#", "All drafts" ]) do |card|
          [ "A half-written idea", "Notes from the road", "(untitled)" ].each { |title| card.with_row { title } }
        end
      end

      def short_list_with_hint
        render Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "preview-live", empty: "Nothing scheduled on the site.",
          hint: "Schedule a draft to see it here.") do |card|
          card.with_row { "Launch post" }
        end
      end

      def empty
        render Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "preview-empty", empty: "No drafts — start one above.")
      end
    end
  end
end
