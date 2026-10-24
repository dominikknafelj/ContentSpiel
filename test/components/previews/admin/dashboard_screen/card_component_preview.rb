module Admin
  module DashboardScreen
    # The dashboard's card shell: rows, the "→" link, the in-card empty line
    # and its action.
    class CardComponentPreview < ViewComponent::Preview
      def with_rows
        render Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "preview-drafts", empty: "No drafts.",
          link: [ "#", "All drafts" ]) do |card|
          [ "A half-written idea", "Notes from the road", "(untitled)" ].each { |title| card.with_row { title } }
        end
      end

      def empty_with_action
        render Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "preview-empty-action", empty: "No drafts.") do |card|
          card.with_empty_action { '<a href="#" class="text-ink underline">Start a draft</a>'.html_safe }
        end
      end

      def empty
        render Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "preview-empty", empty: "Nothing scheduled.")
      end
    end
  end
end
