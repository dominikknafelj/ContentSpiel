module Admin
  module Shell
    # The bar CS Studio shows instead of the sidebar under 1280px (handoff §9
    # A7): ☰ opens the modules drawer, a "Pages ▾" button (only when the
    # screen has a tree column, and only under 1024px, where the tree is a
    # drawer too) opens the tree, and ⌘K opens the command palette. CSS
    # (`.admin-top-bar`) hides the whole bar at desktop width; the buttons
    # carry `admin--shell--drawer#toggle` and name their panel by `data-drawer`.
    class TopBarComponent < Admin::AdminComponent
      def initialize(tree: false)
        @tree = tree
      end

      private

      attr_reader :tree

      def drawer_button(label:, controls:, name:, classes: "", &block)
        tag.button(type: "button", aria: { label: label, controls: controls, expanded: "false" },
          data: { action: "admin--shell--drawer#toggle", admin__shell__drawer_name_param: name, admin__shell__drawer_target: "trigger" },
          class: "cursor-pointer rounded-cs px-2 py-1 text-ink hover:bg-sunken #{classes}", &block)
      end
    end
  end
end
