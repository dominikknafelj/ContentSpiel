module Admin
  module Ui
    # The tabs of a rail, an editor's or the Media screen's (`.admin-rail__tabs`, drawn only where the
    # rail docks): ARIA's tabs pattern on `<button>`s, which are not a
    # `ButtonComponent` variant. Each tab controls its panel
    # (`Admin::Ui::RailPanelComponent`) by id, and only the current one is in
    # the tab order. The server draws `current` once; from then on the current
    # tab is `admin--ui--rail`'s, which re-applies it to a tab or panel that is
    # drawn again, and is never stored beyond the document.
    #
    # A rail of one tab has nothing to choose: it is an `h2` with the tab's
    # label and the tab's id, which the panel's `aria-labelledby` names.
    #
    # `slot_tabs` are the tabs features registered at the rail's panel slot
    # (`Admin::Ui::RailSlotComponent`): they join the tablist after `tabs`, and
    # a rail of one tab of its own becomes a tablist with the first of them.
    #
    # `count` is a figure beside the label (`text-count`), hidden at zero so
    # a redraw of the tab can show it again; nil draws none. It is the tab's
    # bubble (`data-tab-count`, drawn by the stylesheet on the people tint,
    # and on the accent while it carries `data-unread`). `count_data` are
    # the figure's own `data-` attributes, the entry's (`tab_count_data`), so
    # the feature's script can keep the figure current.
    #
    # In the grid (`.admin-rail-grid`) the tabs and the panels stand in the
    # rail's column; the blocks column is the element marked
    # `.admin-rail__main`, and nothing else is placed.
    class RailTabsComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A tablist named Settings of tab buttons, one of them in the tab order, walked with the arrow keys, Home and End; a rail of one tab is a heading instead.",
        motion: :none,
        content_edges: %i[many short],
        widths: :from_container,
        interface: %i[rail_id tabs current slot_tabs],
        limits: [
          "It draws only where the rail docks, and the current tab is the server's only on the first draw.",
          "A current that names no tab is the first tab."
        ],
        states: %i[rest single hover focus],
        script_states: {
          selected: [ "test/system/admin/editor_rail_test.rb", "Page and Section are tabs: arrows move between them, Home and End go to the ends" ]
        },
        keys: %w[label],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/editor_rail_test.rb", "Page and Section are tabs: arrows move between them, Home and End go to the ends" ]
      )

      Tab = Data.define(:key, :label, :count, :count_data) do
        def initialize(key:, label:, count: nil, count_data: nil) = super
      end

      def self.tab_id(rail_id, key) = "#{rail_id}-tab-#{key}"
      def self.panel_id(rail_id, key) = "#{rail_id}-panel-#{key}"

      def initialize(rail_id:, tabs:, current:, slot_tabs: [])
        @rail_id = rail_id
        @tabs = tabs + slot_tabs
        # A `current` that names no tab is the first tab, so one tab is
        # always in the tab order. A slot's tab may be current
        # (`RailSlotComponent#current_key`).
        @current = @tabs.map { |tab| tab.key.to_s }.then { |keys| keys.include?(current.to_s) ? current.to_s : keys.first }
      end

      private

      attr_reader :tabs

      def single? = tabs.one?
      def current?(tab) = tab.key.to_s == @current
      def tab_id(tab) = self.class.tab_id(@rail_id, tab.key)
    end
  end
end
