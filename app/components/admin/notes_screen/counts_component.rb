module Admin
  module NotesScreen
    # One record's open-note counts as data for `admin--notes--drawer`, which fills
    # the header's button and every marker from it (`Notes::Counts
    # .for_container`). Hidden; it carries numbers and keys, no text. With
    # `id:` it is the page's own copy (`#notes-counts`, a Turbo Stream can
    # replace it); without, the copy every answer of the notes frame brings.
    class CountsComponent < Admin::AdminComponent
      # One record's counts for the parts of an editor that draw them: the
      # header's button and the rail's Notes tab, two slot entries of one
      # screen. The editors hand every slot the same `reads:` Hash, so the
      # first of the two to ask reads the counts (two statements,
      # `Notes::Counts.for_container`) and the second finds them there. A
      # host that hands no `reads:` (a save's stream) gets nil: it reads
      # nothing, and the part it draws is filled by `admin--notes--drawer`
      # from the counts the page already holds.
      def self.read(record, viewer:, reads:)
        return nil unless reads

        reads[[ :notes_counts, ::Notes.key(record) ]] ||= ::Notes::Counts.for_container(record, user: ::Notes.user_of(viewer))
      end

      def initialize(counts:, id: nil)
        @counts = counts
        @id = id
      end

      def call = tag.span(id: @id, hidden: true, data: { "admin--notes--drawer-target": "counts", counts: @counts.to_json })
    end
  end
end
