module Admin
  module Shell
    # The one control of the folded column's strip, which unfolds it, in the
    # words of what the column holds ("Show page tree", "Show list":
    # `TreeSubjects`): the mirror of the column head's hide button
    # (`Admin::Ui::TreeHideComponent`). Both are the column's
    # (`aria-controls="tree-column"`) and say whether it is expanded;
    # `admin--shell--tree-width` writes `aria-expanded` on both whenever the
    # fold changes, and moves the focus from the one pressed to the other.
    # What is drawn here is right for the state it is shown in, folded:
    # `aria-expanded="false"`.
    #
    # Rendered by the layout as the FIRST child of `aside#tree-column`,
    # outside what the screen puts in the column, so a Pages move, which
    # replaces the tree's frame, does not replace it. The stylesheet shows it
    # only while `data-tree-folded` is on <html> and the window is 1024px wide
    # or more (`.admin-tree-fold`); below that the column is a drawer and the
    # fold means nothing.
    class TreeFoldComponent < Admin::AdminComponent
      def initialize(subject:)
        TreeSubjects.fetch(subject)
        @subject = subject.to_s
      end

      def call
        render Admin::Ui::ButtonComponent.new(label: t("admin.#{TreeSubjects.key(subject, :show)}"), variant: :tertiary, size: :small, icon: :panel_left_open,
          class: "admin-tree-fold",
          aria: { controls: "tree-column", expanded: "false" },
          data: { "admin--shell--tree-width-target": "unfold", action: "admin--shell--tree-width#unfold" })
      end

      private

      attr_reader :subject
    end
  end
end
