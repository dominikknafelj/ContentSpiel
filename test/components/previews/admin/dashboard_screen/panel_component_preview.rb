module Admin
  module DashboardScreen
    # The dashboard's panel: one per kind (its head's tint), rows with the
    # "→" link, and the empty line with its action.
    class PanelComponentPreview < ViewComponent::Preview
      def shortcuts_with_rows
        render Admin::DashboardScreen::PanelComponent.new(kind: :shortcuts, title: "Pick up where you left off", line: "Your drafts, the latest first.",
          id: "preview-drafts", empty: "No drafts.", link: [ "#", "All drafts" ]) do |panel|
          [ "A half-written idea", "Notes from the road", "(untitled)" ].each { |title| panel.with_row { title } }
        end
      end

      def action_with_badge
        render Admin::DashboardScreen::PanelComponent.new(kind: :action, title: "Notes for you", line: "Mentions and replies addressed to you.",
          id: "preview-notes", empty: "No notes for you.") do |panel|
          panel.with_badge { '<span class="text-label text-accent">2 new</span>'.html_safe }
          [ "Dana mentioned you", "Sam replied" ].each { |row| panel.with_row { row } }
        end
      end

      def empty_with_action
        render Admin::DashboardScreen::PanelComponent.new(kind: :shortcuts, title: "Pick up where you left off", line: "Your drafts, the latest first.",
          id: "preview-empty-action", empty: "No drafts.") do |panel|
          panel.with_empty_action { '<a href="#" class="text-ink underline">Start a draft</a>'.html_safe }
        end
      end

      def information_empty
        render Admin::DashboardScreen::PanelComponent.new(kind: :information, title: "Publishing on its own",
          line: "Scheduled pages and posts, the soonest first.", id: "preview-empty", empty: "Nothing scheduled.")
      end
    end
  end
end
