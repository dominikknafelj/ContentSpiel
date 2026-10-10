module Admin
  module PagesScreen
    # `Admin::PagesScreen::TreeNodeComponent` (cs-studio spec §4.2): a regular node (with a
    # child of its own, so the child count and the nested list both show) and
    # the root node (no drag handle).
    class TreeNodeComponentPreview < ViewComponent::Preview
      def default
        PreviewFixtures.root_page
        about = PreviewFixtures.page(title: "About")
        about.children.create!(page_type: :standard, title: "Team")
        children_by_parent = Page.all.to_a.group_by(&:parent_id)

        render Admin::PagesScreen::TreeNodeComponent.new(page: about, children_by_parent: children_by_parent, selected: about, locale: "en")
      end

      def root_node
        root = PreviewFixtures.root_page
        children_by_parent = Page.all.to_a.group_by(&:parent_id)

        render Admin::PagesScreen::TreeNodeComponent.new(page: root, children_by_parent: children_by_parent, locale: "en", root: true)
      end
    end
  end
end
