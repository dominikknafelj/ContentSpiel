module Admin
  module Answers
    # The rail's registered tabs (`editor.rail.tabs`), as streams, for an answer
    # to a save: each tab's contents, its label and its number, are drawn again
    # into the tab by id, so its count follows the change.
    #
    # ONLY THE TABS' CONTENTS ARE SENT. A panel may hold text being typed, and
    # a save's answer must not replace it (`Admin::Slots`, the panel shape).
    # The tab's `<button>` is updated, not replaced: a tab with the keyboard's
    # focus keeps it as the answer lands.
    #
    # A stream's context is smaller than the page's: no `query:` (the request is
    # the autosave's, not the page's) and no `reads:`, so `tab_count` and
    # `tab_label` must be answerable from `record` and `viewer` alone, or the
    # entry draws a figure its own script fills as the number connects. A tab
    # that was not drawn at page load is not added by a stream (replacing a
    # missing id does nothing); it appears at the next page load.
    module RailTabStreams
      def self.for(record, view:, viewer:, rail_id: "editor-grid", **context)
        builder = Answers.stream_builder(view)
        Admin::Ui::RailSlotComponent.new(rail_id:, record:, viewer:, **context).tabs.map do |tab|
          builder.update(Admin::Ui::RailTabsComponent.tab_id(rail_id, tab.key), Admin::Ui::RailTabComponent.new(rail_id:, tab:, contents: true))
        end
      end
    end
  end
end
