module Admin
  module Ui
    # One panel of a rail, an editor's or the Media screen's: its content is rendered here once and
    # never cloned, so a form inside keeps its ids and its wiring at every
    # width. Below the rail's threshold every panel stands in the page in
    # document order, but a `docked_only` one (the Section panel, whose
    # settings stand under their section there); docked, only the current
    # panel (`data-current`, written by `admin--ui--rail` from then on) is
    # shown. Named by its tab (`Admin::Ui::RailTabsComponent`), whose ids
    # both components build the same way.
    class RailPanelComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A tabpanel labelled by its tab, with no focus of its own.",
        motion: :none,
        content_edges: %i[none long],
        widths: :from_container,
        interface: %i[rail_id key current docked_only],
        limits: [
          "Its content is drawn once and never cloned; which panel shows is the rail's script from the first draw on.",
          "A docked_only panel is not shown below the rail's threshold.",
          "It is a target of admin--ui--rail, which the rail attaches, not this panel."
        ],
        states: %i[rest current docked_only],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/keyboard_navigation_test.rb", "a rail's panel takes no focus of its own: Tab from its current tab goes to the first control inside it" ]
      )

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
