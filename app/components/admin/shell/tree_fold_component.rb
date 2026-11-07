module Admin
  module Shell
    # "Show page tree", the one control of the folded tree's strip: the
    # mirror of the tree head's "Hide page tree"
    # (`Admin::PagesScreen::TreeComponent`). Both are the column's
    # (`aria-controls="tree-column"`) and say whether it is expanded;
    # `admin--shell--tree-width` writes `aria-expanded` on both whenever the
    # fold changes, and moves the focus from the one pressed to the other.
    # What is drawn here is right for the state it is shown in, folded:
    # `aria-expanded="false"`.
    #
    # Rendered by the layout as the FIRST child of `aside#tree-column`,
    # outside the tree's frame, so a move does not replace it. The stylesheet
    # shows it only while `data-tree-folded` is on <html> and the window is
    # 1024px wide or more (`.admin-tree-fold`); below that the tree is a
    # drawer and the fold means nothing.
    class TreeFoldComponent < Admin::AdminComponent
      def call
        render Admin::Ui::ButtonComponent.new(label: t(".show"), variant: :tertiary, size: :small, icon: :panel_left_open,
          class: "admin-tree-fold",
          aria: { controls: "tree-column", expanded: "false" },
          data: { "admin--shell--tree-width-target": "unfold", action: "admin--shell--tree-width#unfold" })
      end
    end
  end
end
