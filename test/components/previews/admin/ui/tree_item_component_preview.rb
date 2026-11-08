module Admin
  module Ui
    # `Admin::Ui::TreeItemComponent`: one row of each state a static render
    # draws, and a long German title cut to one line. Hover and focus are the
    # browser's. Folding is the tree's script's, so `folded` and `open` are
    # the disclosure as the server draws it.
    class TreeItemComponentPreview < ViewComponent::Preview
      def rest
        row(title: "Writing text")
      end

      def selected
        row(title: "The page tree", selected: true, current: true)
      end

      def folded
        row(title: "Translating", parent: true, folded: true, controls: "preview-children") do |item|
          item.with_trailing { count(3) }
        end
      end

      def open
        row(title: "Start here", parent: true, controls: "preview-children")
      end

      def leaf
        row(title: "Move pages") do |item|
          item.with_add(label: "Add a page under Move pages", href: "#")
        end
      end

      def context_only
        render(Admin::Ui::TreeItemComponent.new(id: "preview-row", title: "Members area", parent: true, controls: "preview-children", context_only: true)) do |item|
          item.with_title { "Members area" }
        end
      end

      def flat
        row(title: "A post among the posts", flat: true)
      end

      def root
        row(title: "Home", parent: true, controls: "preview-children", root: true)
      end

      def long_title
        row(title: "Datenschutzerklärung und Hinweise zur Verarbeitung von Daten")
      end

      private

      def row(title:, current: false, **options, &block)
        render(Admin::Ui::TreeItemComponent.new(id: "preview-row", title: title, **options)) do |item|
          item.with_title { "<a href=\"#\" data-tree-focus#{' aria-current="page"' if current}>#{ERB::Util.html_escape(title)}</a>".html_safe }
          block&.call(item)
        end
      end

      def count(figure)
        "<span class=\"admin-tree-row__count admin-tree-row__reveal\" role=\"img\" aria-label=\"#{figure} subpages\">#{figure}</span>".html_safe
      end
    end
  end
end
