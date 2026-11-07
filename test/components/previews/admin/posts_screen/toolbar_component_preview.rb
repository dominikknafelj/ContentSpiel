module Admin
  module PostsScreen
    # The posts list's filter form: the bar (search, the All/Live/Drafts/
    # Scheduled control with counts, Clear) and the filter panel (Type, Tag,
    # Translation). The form is drawn `display: contents`, so it is shown
    # inside the list rail's grid, as the posts screen draws it: from 1200px
    # of the preview's width the bar stands in the first column and the
    # panel docks in the rail beside it; below that the panel stands under
    # the bar.
    class ToolbarComponentPreview < ViewComponent::Preview
      COUNTS = { "all" => 128, "live" => 96, "drafts" => 20, "scheduled" => 12 }.freeze

      def default
        render_in_rail Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: COUNTS, content_types: ContentTypes.all, tags: [],
          filters: { q: nil, type: nil, tag: nil, translation: nil })
      end

      def with_filters
        render_in_rail Admin::PostsScreen::ToolbarComponent.new(scope: "drafts", counts: COUNTS, content_types: ContentTypes.all, tags: [ Tag.new(name: "rails") ],
          filters: { q: "launch", type: "blog", tag: "rails", translation: "outdated" })
      end

      private

      def render_in_rail(component)
        render_with_template(template: "admin/posts_screen/toolbar_component_preview/in_rail", locals: { component: component })
      end
    end
  end
end
