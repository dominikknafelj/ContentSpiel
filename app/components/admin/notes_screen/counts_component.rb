module Admin
  module NotesScreen
    # One record's open-note counts as data for `admin--notes--drawer`, which fills
    # the header's button and every marker from it (`Notes::Counts
    # .for_container`). Hidden; it carries numbers and keys, no text. With
    # `id:` it is the page's own copy (`#notes-counts`, a Turbo Stream can
    # replace it); without, the copy every answer of the notes frame brings.
    class CountsComponent < Admin::AdminComponent
      def initialize(counts:, id: nil)
        @counts = counts
        @id = id
      end

      def call = tag.span(id: @id, hidden: true, data: { "admin--notes--drawer-target": "counts", counts: @counts.to_json })
    end
  end
end
