module Admin
  # `Admin::MenuComponent`: the popover menu, aligned right (default) and left.
  class MenuComponentPreview < ViewComponent::Preview
    def default
      render Admin::MenuComponent.new(label: "More ▾") do |menu|
        menu.with_item { "<a href=\"#\">Rename</a>".html_safe }
        menu.with_divider
        menu.with_item { "<a href=\"#\">Delete…</a>".html_safe }
      end
    end

    def aligned_left
      render Admin::MenuComponent.new(label: "More ▾", align: :left) do |menu|
        menu.with_item { "<a href=\"#\">Rename</a>".html_safe }
        menu.with_divider
        menu.with_item { "<a href=\"#\">Delete…</a>".html_safe }
      end
    end
  end
end
