module Admin
  module EditorScreen
    # "5 blocks" in a section's head (sections spec §4.1), after the words
    # that say its settings (`SectionSettingsWordsComponent`, where the
    # column count is a word of its own).
    #
    # Its own component, with the id on its own element, because it is the
    # one part of the head a block's write changes: an add into a column
    # and a delete out of one answer with this line and nothing else of the
    # card (`Admin::Answers::BlockDrawing#section_count_streams`), so the
    # lanes, the tiles and whichever form is open are left as they stand.
    # The card draws it through the same door, `SectionCardComponent
    # .summary`, so the line a stream brings is the line a page load draws.
    #
    # `count:` is handed in, not read from the section: the card has its
    # blocks from the outline already (no query), and a stream counts them
    # after its write. `section:` names the element (`summary_id`).
    class SectionSummaryComponent < AdminComponent
      def initialize(section:, count:)
        @section = section
        @count = count
      end

      def call
        tag.span(t(".blocks", count: count), id: Admin::EditorScreen::SectionCardComponent.summary_id(section), class: "shrink-0 text-count")
      end

      private

      attr_reader :section, :count
    end
  end
end
