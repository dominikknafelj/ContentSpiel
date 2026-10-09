module Admin
  module EditorScreen
    # "This also deletes the 3 blocks in it." in the dialog that confirms
    # "Delete section and its blocks…" (sections spec §4.1: the confirmation
    # names how many blocks go with the section).
    #
    # Its own component, with the id on its own element, for the reason
    # `SectionSummaryComponent` is one: the dialog is rendered with the card,
    # long before it is opened, and an add into a column or a delete out of
    # one changes the number meanwhile. Both answer with this line beside the
    # header's count (`Admin::ContentBlocksController#section_count_streams`),
    # and the card draws it through the same door (`SectionCardComponent
    # .delete_count`), so a dialog never promises to delete a number of
    # blocks the section no longer holds.
    #
    # An empty section has nothing to add to the dialog's own sentence: the
    # element is still there, empty, because it is what the next stream
    # replaces.
    class SectionDeleteCountComponent < AdminComponent
      def initialize(section:, count:)
        @section = section
        @count = count
      end

      def call
        tag.p((t(".blocks", count: count) if count.positive?), id: Admin::EditorScreen::SectionCardComponent.delete_count_id(section))
      end

      private

      attr_reader :section, :count
    end
  end
end
