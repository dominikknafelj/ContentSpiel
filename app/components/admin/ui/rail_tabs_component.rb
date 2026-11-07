module Admin
  module Ui
    # The tabs of an editor's rail (`.admin-rail__tabs`, drawn only where the
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
    # `count` is a figure beside the label (`text-count`), hidden at zero so
    # a redraw of the tab can show it again; nil draws none.
    #
    # In the grid (`.admin-rail-grid`) the tabs and the panels stand in the
    # rail's column; the blocks column is the element marked
    # `.admin-rail__main`, and nothing else is placed.
    class RailTabsComponent < AdminComponent
      Tab = Data.define(:key, :label, :count) do
        def initialize(key:, label:, count: nil) = super
      end

      def self.tab_id(rail_id, key) = "#{rail_id}-tab-#{key}"
      def self.panel_id(rail_id, key) = "#{rail_id}-panel-#{key}"

      def initialize(rail_id:, tabs:, current:)
        @rail_id = rail_id
        @tabs = tabs
        # A `current` that names no tab is the first tab, so one tab is
        # always in the tab order.
        @current = tabs.map { |tab| tab.key.to_s }.then { |keys| keys.include?(current.to_s) ? current.to_s : keys.first }
      end

      private

      attr_reader :tabs

      def single? = tabs.one?
      def current?(tab) = tab.key.to_s == @current
      def tab_id(tab) = self.class.tab_id(@rail_id, tab.key)
      def panel_id(tab) = self.class.panel_id(@rail_id, tab.key)

      def tab_data(tab)
        { "admin--ui--rail-target": "tab", key: tab.key, action: "admin--ui--rail#select keydown->admin--ui--rail#key" }
      end
    end
  end
end
