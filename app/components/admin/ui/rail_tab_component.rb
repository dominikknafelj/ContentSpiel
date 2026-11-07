module Admin
  module Ui
    # One tab of a rail's tablist (`Admin::Ui::RailTabsComponent`): a `<button>`
    # that controls its panel by id. Its own component so that a save's answer
    # can draw one tab again (`Admin::Answers::RailTabStreams`) without its
    # panel, and so that the tablist and the answer draw it the same way.
    # `current` is only the first draw's; `admin--ui--rail` re-applies the
    # current tab to a tab that connects.
    class RailTabComponent < AdminComponent
      def initialize(rail_id:, tab:, current: false)
        @rail_id = rail_id
        @tab = tab
        @current = current
      end

      def call
        tag.button type: "button", role: "tab", id: RailTabsComponent.tab_id(@rail_id, @tab.key), class: "admin-rail__tab text-sm",
          aria: { selected: @current.to_s, controls: RailTabsComponent.panel_id(@rail_id, @tab.key) }, tabindex: (@current ? 0 : -1),
          data: { "admin--ui--rail-target": "tab", key: @tab.key, action: "admin--ui--rail#select keydown->admin--ui--rail#key" } do
          safe_join([ @tab.label, (tag.span(@tab.count, class: "text-count", hidden: @tab.count.zero?) unless @tab.count.nil?) ])
        end
      end
    end
  end
end
