module Admin
  module Shell
    # The bar CS Studio shows instead of the sidebar under 1280px: ☰ opens the
    # modules drawer, the tree column's button opens the column as a drawer,
    # and ⌘K opens the command palette. CSS (`.admin-top-bar`) hides the whole
    # bar at desktop width; the drawer buttons carry
    # `admin--shell--drawer#toggle` and name their panel by `data-drawer`.
    #
    # `tree:` is what the screen's tree column holds (`TreeSubjects`: the
    # Pages tree, the mind graph's list), or nil on a screen without one,
    # which draws no tree button. The button is in the column's words ("Pages
    # ▾" named "Open page tree", "List ▾" named "Open list") and is drawn
    # under 1024px only, where the column is a drawer too
    # (`.admin-top-bar__tree`); above that the column is in the grid.
    class TopBarComponent < Admin::AdminComponent
      def initialize(tree: nil)
        TreeSubjects.fetch(tree) if tree
        @tree = tree&.to_s
      end

      private

      attr_reader :tree

      def tree_word(word) = t("admin.#{TreeSubjects.key(tree, word)}")

      def drawer_button(label:, controls:, name:, classes: "", &block)
        tag.button(type: "button", aria: { label: label, controls: controls, expanded: "false" },
          data: { action: "admin--shell--drawer#toggle", admin__shell__drawer_name_param: name, admin__shell__drawer_target: "trigger" },
          class: "cursor-pointer rounded-button px-2 py-1 text-ink hover:bg-sunken #{classes}", &block)
      end
    end
  end
end
