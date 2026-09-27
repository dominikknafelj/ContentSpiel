module Admin
  # `Admin::TreeComponent` (cs-studio spec §4.2): the homepage, two published
  # top-level pages (one with a draft child of its own), and a scheduled
  # page -- enough to see every status dot, a child count above zero, and
  # the selected node's highlight in one screen.
  class TreeComponentPreview < ViewComponent::Preview
    def default
      root = PreviewFixtures.root_page
      about = PreviewFixtures.page(title: "About")
      about.children.create!(page_type: :standard, title: "Team")
      root.children.create!(page_type: :standard, title: "Contact", published_at: 1.week.from_now)

      render Admin::TreeComponent.new(root: root, selected: about, locale: "en")
    end

    def empty
      render Admin::TreeComponent.new(root: nil, locale: "en")
    end
  end
end
