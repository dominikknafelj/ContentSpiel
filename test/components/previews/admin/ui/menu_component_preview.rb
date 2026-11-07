module Admin
  module Ui
    # `Admin::Ui::MenuComponent`: the closed menu at rest, aligned right (the
    # default), and aligned left. Opening it is `admin--ui--menu`'s.
    class MenuComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::MenuComponent.new(label: "More ▾") do |menu|
          menu.with_item { "<a href=\"#\">Rename</a>".html_safe }
          menu.with_item { "<a href=\"#\">Delete…</a>".html_safe }
        end
      end

      def aligned_left
        render Admin::Ui::MenuComponent.new(label: "More ▾", align: :left) do |menu|
          menu.with_item { "<a href=\"#\">Rename</a>".html_safe }
          menu.with_item { "<a href=\"#\">Delete…</a>".html_safe }
        end
      end
    end
  end
end
