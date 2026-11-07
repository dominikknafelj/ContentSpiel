module Admin
  module Ui
    # One tab of a rail's tablist (`Admin::Ui::RailTabsComponent`): a `<button>`
    # that controls its panel by id. Its own component so that a save's answer
    # can draw one tab's contents again (`Admin::Answers::RailTabStreams`)
    # without its panel, and so that the tablist and the answer draw them the
    # same way.
    # `current` is only the first draw's; `admin--ui--rail` re-applies the
    # current tab to a tab that connects.
    #
    # `contents: true` draws only what is inside the button, its label and its
    # number: what the answer puts into the tab, so the button stays and a tab
    # that has the keyboard's focus keeps it.
    class RailTabComponent < AdminComponent
      def initialize(rail_id:, tab:, current: false, contents: false)
        @rail_id = rail_id
        @tab = tab
        @current = current
        @contents = contents
      end

      def call
        return contents if @contents

        tag.button type: "button", role: "tab", id: RailTabsComponent.tab_id(@rail_id, @tab.key), class: "admin-rail__tab text-sm",
          aria: { selected: @current.to_s, controls: RailTabsComponent.panel_id(@rail_id, @tab.key) }, tabindex: (@current ? 0 : -1),
          data: { "admin--ui--rail-target": "tab", key: @tab.key, action: "admin--ui--rail#select keydown->admin--ui--rail#key" } do
          contents
        end
      end

      private

      def contents
        safe_join([ @tab.label, (tag.span(@tab.count, class: "text-count", hidden: @tab.count.zero?, data: @tab.count_data) unless @tab.count.nil?) ])
      end
    end
  end
end
