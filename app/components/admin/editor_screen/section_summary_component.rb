module Admin
  module EditorScreen
    # "3 columns · 5 blocks" in a section's header (sections spec §4.1), the
    # words that make a collapsed section's one line.
    #
    # Its own component, with the id on its own element, because it is the
    # one part of the header a block's write changes: an add into a column
    # and a delete out of one answer with this line and nothing else of the
    # card (`Admin::ContentBlocksController#section_count_streams`), so the
    # lanes, the tiles and whichever form is open are left as they stand.
    # The card draws it through the same door, `SectionCardComponent
    # .summary`, so the line a stream brings is the line a page load draws.
    #
    # `count:` is handed in, not read from the section: the card has its
    # blocks from the outline already (no query), and a stream counts them
    # after its write.
    class SectionSummaryComponent < AdminComponent
      def initialize(section:, count:)
        @section = section
        @count = count
      end

      def call
        tag.span([ t(".columns", count: section.column_count), t(".blocks", count: count) ].join(" · "),
          id: Admin::EditorScreen::SectionCardComponent.summary_id(section), class: "min-w-0 flex-1 truncate text-sm text-dim")
      end

      private

      attr_reader :section, :count
    end
  end
end
