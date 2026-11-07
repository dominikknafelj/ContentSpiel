module Admin
  module NotesScreen
    # The Notes button of the page and post editors' header (notes spec §4.3),
    # registered at the header's `editor.header.actions` slot
    # (`config/initializers/admin_slots.rb`). It shows the rail's Notes tab
    # (`Admin::NotesScreen::RailPanelComponent`) and closes it again. Its
    # number is the server's as the page loads; `admin--notes--drawer` keeps it
    # current from then on, and is what says "unread for you" (`data-unread`
    # on the number) and "the notes are shown" (`aria-pressed`).
    #
    # WHEN IT DRAWS: a saved record of a kind that takes notes, whose notes
    # the viewer may read (`Notes.readable?`). No button on a record that has
    # no id to count.
    #
    # THE COUNT is the screen's one read of the record's counts
    # (`CountsComponent.read`), shared through the slot's `reads:` with the
    # rail's Notes tab, so the editor reads them once; a host that hands no
    # `reads:` has the component ask.
    class HeaderButtonComponent < Admin::AdminComponent
      def initialize(record:, viewer:, data: nil, reads: nil, **)
        @record = record
        @viewer = viewer
        @reads = reads
      end

      def render?
        record.persisted? && !RecordKinds.of(record).nil? && ::Notes.readable?(viewer, record)
      end

      def open_notes
        (CountsComponent.read(record, viewer:, reads: @reads) || ::Notes::Counts.for_container(record, user: ::Notes.user_of(viewer))).fetch("total").to_i
      end

      # The shared secondary style of the header (Preview's); its common classes
      # are already `inline-flex`, the row for the icon, the word and the count.
      def notes_button_class = helpers.setup_secondary_link_class

      private

      attr_reader :record, :viewer
    end
  end
end
