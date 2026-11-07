module Admin
  module Ui
    # A record's state as a list row shows it: its status chip (Live left out,
    # since nearly everything in a list is live) and, when the rows have moved on
    # from what the site shows, the unpublished-changes chip. The words belong to
    # the two chips; this component only decides which of them stand together.
    # WHETHER there are changes is `Publishing::State#changes?` through the
    # record's `unpublished_changes?`, so a draft carrying a stale mark shows
    # Draft alone. Renders nothing for a live record without changes.
    class ListStateComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "No role or name of its own: the chips it draws say their words, and nothing in it takes focus.",
        motion: :none,
        content_edges: %i[none short],
        widths: :fluid,
        interface: %i[record],
        limits: [
          "It decides which chips stand together and owns no words: they are the status chip's and the unpublished chip's.",
          "A live record without unpublished changes renders nothing."
        ],
        states: %i[draft scheduled live live_with_changes scheduled_with_changes],
        keys: [],
        slots: [],
        controller: nil
      )

      def initialize(record:)
        @record = record
      end

      def render? = status_chip? || changes?

      def status_chip? = record.status != "live"

      def changes? = record.unpublished_changes?

      private

      attr_reader :record
    end
  end
end
