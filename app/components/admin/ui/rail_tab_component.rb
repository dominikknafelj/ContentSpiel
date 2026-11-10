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
      include Admin::Ui::Contract

      contract(
        accessibility: "A button with role=tab, aria-selected and aria-controls its panel; only the current tab is in the tab order.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[rail_id tab current contents],
        limits: [
          "Its current is only the first draw's: from then on the rail's script decides it.",
          "With contents it draws only the label and the count, for a stream to put into the tab.",
          "Its press and keys are actions of admin--ui--rail, which the rail attaches, not this tab."
        ],
        states: %i[rest current count hover focus],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/editor_rail_test.rb", "Page and Section are tabs: arrows move between them, Home and End go to the ends" ]
      )

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
        safe_join([ @tab.label, (tag.span(@tab.count, class: "text-count", hidden: @tab.count.zero?, data: { tab_count: "", **@tab.count_data.to_h }) unless @tab.count.nil?) ])
      end
    end
  end
end
