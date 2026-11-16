module Admin
  module Ui
    # A record's state as a list row shows it: its status chip (Live left out,
    # since nearly everything in a list is live) and, when the rows have moved on
    # from what the site shows, the unpublished-changes chip. The words belong to
    # the two chips; this component only decides which of them stand together.
    # WHETHER there are changes is `Publishing::State#changes?` through the
    # record's `unpublished_changes?`, so a draft carrying a stale mark shows
    # Draft alone. Renders nothing for a live record without changes.
    #
    # A post of a switched-off type (`type_switched_on?`) leads with the type's
    # off chip (`TypeStateComponent`), then its own chips: its status is kept,
    # since it returns when the type is switched on, and a live one reads
    # "Switched off" alone, which is true: it is not on the site.
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
          "A live record without unpublished changes renders nothing.",
          "A post of a switched-off type leads with the type's chip, and its own state follows."
        ],
        states: %i[draft scheduled live live_with_changes scheduled_with_changes switched_off],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: it draws only chips, which are words beside the row's own link."
      )

      def initialize(record:)
        @record = record
      end

      def render? = type_chip? || status_chip? || changes?

      # Only a post has a type that can be switched off.
      def type_chip? = record.respond_to?(:type_switched_on?) && !record.type_switched_on?

      def status_chip? = record.status != "live"

      def changes? = record.unpublished_changes?

      private

      attr_reader :record
    end
  end
end
