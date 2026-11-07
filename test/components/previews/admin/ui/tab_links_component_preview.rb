module Admin
  module Ui
    # `Admin::Ui::TabLinksComponent`: tabs that are links, at rest with no
    # counts (a form's Form | Submissions) and with counts (the Trash
    # screen's).
    class TabLinksComponentPreview < ViewComponent::Preview
      def with_counts
        render(Admin::Ui::TabLinksComponent.new(label: "Filter by type", tabs: [
          { label: "All", href: "#", current: true, count: 7 }, { label: "Pages", href: "#", current: false, count: 2 }
        ]))
      end

      def rest
        render(Admin::Ui::TabLinksComponent.new(label: "Form screens", tabs: [
          { label: "Form", href: "#", current: false }, { label: "Submissions", href: "#", current: true }
        ]))
      end
    end
  end
end
