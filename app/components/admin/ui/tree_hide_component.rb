module Admin
  module Ui
    # The tree column's own "Hide": the button at the end of a column's head
    # that folds the column to its strip (`admin--shell--tree-width#fold`).
    # The strip's one button is its mirror (`Admin::Shell::TreeFoldComponent`),
    # and both are the column's (`aria-controls="tree-column"`): the script
    # writes `aria-expanded` on both whenever the fold changes, and moves the
    # focus from the one pressed to the other. Every screen that fills the
    # column draws this one in its head (the Pages tree, the mind graph's
    # list), so the fold is pressed and named the same way on each.
    #
    # `subject:` is what the column holds (`Admin::Shell::TreeSubjects`), and
    # picks the words: "Hide page tree", "Hide list". It is shown from 1024px
    # only, where the column is a column (`.admin-tree-hide`); below, the
    # column is a drawer and folding it means nothing. Drawn expanded: a
    # folded column shows only its strip, and the script writes
    # `aria-expanded` again as the button connects.
    class TreeHideComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A button named by its words, which the shared tooltip also shows; it says it controls the tree column and whether the column is expanded, and a press moves the focus to the strip's button.",
        motion: :reduced,
        content_edges: %i[short],
        widths: :fixed_width,
        interface: %i[subject],
        limits: [
          "Its words are the column's subject's, under admin.components.shell.tree_subject, so it owns no key of its own.",
          "It is a target and an action of admin--shell--tree-width, which the tree column attaches; drawn anywhere else it does nothing.",
          "It is drawn from 1024px only: in a drawer the fold means nothing."
        ],
        states: %i[rest hover focus],
        script_states: {
          folded: [ "test/system/admin/tree_fold_test.rb", "Hide page tree folds the column to a strip, the editor widens, and Show page tree brings it back at its chosen width" ]
        },
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/tree_fold_test.rb", "Enter on the hide button folds the column and gives the focus to the strip, and Space on the strip unfolds it" ]
      )

      def initialize(subject:)
        Admin::Shell::TreeSubjects.fetch(subject)
        @subject = subject.to_s
      end

      def call
        render Admin::Ui::ButtonComponent.new(label: t("admin.#{Admin::Shell::TreeSubjects.key(subject, :hide)}"), variant: :tertiary, size: :small,
          icon: :panel_left_close, class: "admin-tree-hide",
          aria: { controls: "tree-column", expanded: "true" },
          data: { "admin--shell--tree-width-target": "fold", action: "admin--shell--tree-width#fold" })
      end

      private

      attr_reader :subject
    end
  end
end
