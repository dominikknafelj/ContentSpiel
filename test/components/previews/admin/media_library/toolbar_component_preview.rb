module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::ToolbarComponent` (round 3, Task 8): the search and the
    # five segments with their counts, and with a segment chosen and a search set.
    class ToolbarComponentPreview < ViewComponent::Preview
      COUNTS = { all: 48, unused: 12, missing_alt: 7, untranslated: 3, mine: 9 }.freeze

      def default
        render Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: nil)
      end

      def segment_chosen_with_a_search
        render Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "missing_alt", q: "studio")
      end

      # Inside the media picker's own frame (round 3, Task 9): no Untranslated.
      def in_the_picker
        render Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: nil, picker: true)
      end
    end
  end
end
