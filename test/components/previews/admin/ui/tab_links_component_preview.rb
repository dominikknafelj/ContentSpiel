module Admin
  module Ui
    # `Admin::Ui::TabLinksComponent`: tabs that are links, with counts (the
    # Trash screen's) and without (a form's Form | Submissions).
    class TabLinksComponentPreview < ViewComponent::Preview
      def with_counts
        render(Admin::Ui::TabLinksComponent.new(label: "Filter by type", tabs: [
          { label: "All", href: "#", current: true, count: 7 }, { label: "Pages", href: "#", current: false, count: 2 }
        ]))
      end

      def without_counts
        render(Admin::Ui::TabLinksComponent.new(label: "Form screens", tabs: [
          { label: "Form", href: "#", current: false }, { label: "Submissions", href: "#", current: true }
        ]))
      end
    end
  end
end
