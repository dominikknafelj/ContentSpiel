module Admin
  module Answers
    # The rail's registered tabs (`editor.rail.tabs`), as streams, for an answer
    # to a save: each tab is drawn again by id, so its count follows the change.
    #
    # ONLY THE TABS ARE SENT. A panel may hold text being typed, and a save's
    # answer must not replace it (`Admin::Slots`, the panel shape).
    module RailTabStreams
      def self.for(record, view:, viewer:, rail_id: "editor-grid", **context)
        builder = Answers.stream_builder(view)
        Admin::Ui::RailSlotComponent.new(rail_id:, record:, viewer:, **context).tabs.map do |tab|
          builder.replace(Admin::Ui::RailTabsComponent.tab_id(rail_id, tab.key), Admin::Ui::RailTabComponent.new(rail_id:, tab:))
        end
      end
    end
  end
end
