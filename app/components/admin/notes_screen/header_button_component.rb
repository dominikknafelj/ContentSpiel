module Admin
  module NotesScreen
    # The Notes button of the page and post editors' header (notes spec §4.3),
    # registered at the header's `editor.header.actions` slot
    # (`config/initializers/admin_slots.rb`). A toggle for the drawer
    # `Admin::NotesScreen::DrawerComponent` draws beside the editor. Its
    # number is the server's as the page loads; `admin--notes--drawer` keeps it
    # current from then on, and is what says "unread for you" (`data-unread`
    # on the number) and "the drawer is open" (`aria-pressed`).
    #
    # WHEN IT DRAWS. Before the slot the header drew the button when its
    # caller handed over the open-thread count, which the two editor views did
    # for every record they showed (so: every record the viewer could open,
    # since a record out of their scope is a 404), and which a preview or a
    # test of the header did not. Now the component decides from the record and
    # the viewer: it is a saved record of a kind that takes notes, and the
    # viewer may read its notes (`Notes.readable?`). The same screens, and no
    # button on a record that has no id to count.
    #
    # THE COUNT. The component reads it for its one record
    # (`Notes::Counts.for_container`, as the editor view did for the header).
    # A screen that has already read it for the drawer beside the header hands
    # it in as `counts:` through the slot's context, so the page costs the same
    # statements as before; without it the component asks.
    class HeaderButtonComponent < Admin::AdminComponent
      def initialize(record:, viewer:, data: nil, counts: nil, **)
        @record = record
        @viewer = viewer
        @counts = counts
      end

      def render?
        record.persisted? && !RecordKinds.of(record).nil? && ::Notes.readable?(viewer, record)
      end

      def open_notes = (@counts || ::Notes::Counts.for_container(record, user: viewer)).fetch("total").to_i

      # The shared secondary style of the header (Preview's), as a flex row
      # for the icon, the word and the count: the one class swapped is the
      # display, which two utilities can't both set.
      def notes_button_class = helpers.setup_secondary_link_class.sub("inline-block", "inline-flex")

      private

      attr_reader :record, :viewer
    end
  end
end
