module Admin
  module Ui
    # `Admin::Ui::RailPanelComponent`. `rest` is a panel standing in the page,
    # as every panel does below the rail's threshold. `current` and
    # `docked_only` are a whole rail under `admin--ui--rail`, whose grid docks
    # at an editor area of 1200px and more: there the current panel is the
    # one shown, the Page panel in `current` and the docked-only Section panel
    # in `docked_only`. Narrow the preview to see the panels fold back into
    # the page, where the docked-only one is not drawn.
    class RailPanelComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::RailPanelComponent.new(rail_id: "preview-rail", key: "page")) do
          tag.p("The page's settings stand here.", class: "text-sm text-dim")
        end
      end

      def current
        render_with_template
      end

      def docked_only
        render_with_template(template: "admin/ui/rail_panel_component_preview/current", locals: { current: "section" })
      end
    end
  end
end
