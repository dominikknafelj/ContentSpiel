module Admin
  module MindGraphScreen
    # `Admin::MindGraphScreen::LegendComponent`: the toggles a viewer gets, the
    # "Status key…" button, the types present and the fixed keys. (The swatches are
    # canvases `admin--mind-graph--swatches` has the graph's renderer draw.)
    class LegendComponentPreview < ViewComponent::Preview
      def registered_types
        render Admin::MindGraphScreen::LegendComponent.new(content_types: ContentTypes.names, pages: true)
      end

      def one_type_and_a_retired_one
        render Admin::MindGraphScreen::LegendComponent.new(content_types: %w[blog gone/type], pages: true)
      end

      # A viewer who can read no page: no toggle for pages, post types, the
      # tree or lists.
      def without_pages
        render Admin::MindGraphScreen::LegendComponent.new(content_types: ContentTypes.names)
      end

      # A viewer who can read no post: the toggles of pages alone.
      def pages_only
        render Admin::MindGraphScreen::LegendComponent.new(content_types: [], pages: true)
      end
    end
  end
end
