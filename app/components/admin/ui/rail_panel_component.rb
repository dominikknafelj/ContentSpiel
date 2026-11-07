module Admin
  module Ui
    # One panel of an editor's rail: its content is rendered here once and
    # never cloned, so a form inside keeps its ids and its wiring at every
    # width. Below the rail's threshold every panel stands in the page in
    # document order, but a `docked_only` one (the Section panel, whose
    # settings stand under their section there); docked, only the current
    # panel (`data-current`, written by `admin--ui--rail` from then on) is
    # shown. Named by its tab (`Admin::Ui::RailTabsComponent`), whose ids
    # both components build the same way.
    class RailPanelComponent < AdminComponent
      def initialize(rail_id:, key:, current: false, docked_only: false)
        @rail_id = rail_id
        @key = key
        @current = current
        @docked_only = docked_only
      end

      def call
        tag.div content, id: RailTabsComponent.panel_id(@rail_id, @key), role: "tabpanel",
          class: [ "admin-rail__panel", ("admin-rail__panel--docked-only" if @docked_only) ],
          aria: { labelledby: RailTabsComponent.tab_id(@rail_id, @key) },
          data: { "admin--ui--rail-target": "panel", key: @key, current: ("" if @current) }
      end
    end
  end
end
