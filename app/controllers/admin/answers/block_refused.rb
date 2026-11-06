module Admin
  module Answers
    # The answers to a block write the service refused: the reason in the
    # page's alert slot, and what the screen must be put right in. A denial
    # (`result.denied?`: no permission, a stale tab or a forged request) is a
    # 403 and puts nothing right, since it is no fault of the screen's;
    # anything else is a 422 (`status_for`, `Admin::RefusalStatus`).
    class BlockRefused
      include BlockDrawing

      def status_for(result) = Admin::RefusalStatus.for(result)

      # An add into a section this page does not have (another page's, or one
      # deleted meanwhile): refused before the service is asked, with the words
      # a move into a missing section gets.
      def unknown_section
        Answer.new(streams: [ picker_error_stream([ ContentBlocks::Reorder::NO_COLUMN ]) ], status: :unprocessable_entity)
      end

      # A refused add. Into a column, the section's structure as it is now
      # (spec §6, `section_structure_streams`): the column this tab offered may
      # be gone because another tab gave the section fewer columns, and the
      # save under the page's lock saw the layout that tab committed. What is
      # drawn is read after it: the lanes, and with them what names a column,
      # the headings of the forms under them and the header's count. Never a
      # form: it is the same block's and may hold an edit.
      def created(result, section:)
        streams = [ picker_error_stream(result.errors) ]
        streams.concat(section_structure_streams(section)) if section && !result.denied?
        Answer.new(streams: streams, status: status_for(result))
      end

      # A refused autosave of a card: the shared answer (`autosave`), the image
      # put back (`refused_media`), and for a block in a section its tile's
      # line, marked invalid unless the save was denied.
      def updated(block, result:, autosave:, refused_media: nil)
        streams = [ *autosave ]
        streams << refused_media if refused_media
        streams << tile_summary_stream(block, invalid: !result.denied?) if block.section_id
        Answer.new(streams: streams, status: status_for(result))
      end

      # A refused reorder. The order on screen is the browser's optimistic one,
      # so the status line and the alert say it was not saved, or it would look
      # saved.
      #
      # A refused STRUCTURAL move, not for want of permission, gets the whole
      # list as it is now (`blocks_list_stream`): the screen was behind (the
      # block is not where it was dragged from, the column is gone) and how far
      # behind is not known here, so nothing less than the list puts it right.
      # That replaces every form on the screen, as an Undo's answer does;
      # `admin--editor--blocks#move` has had each send what it held first, and
      # does not draw the list at all while a form holds text that is not saved
      # (`#renderKeepingForms`), which only the browser can know, so the list
      # is sent regardless. The page's own order refused is answered with the
      # reason alone: the browser puts its cards back, and they are still the
      # page's.
      def reordered(result, structural:)
        state = result.denied? ? { state: :forbidden } : { state: :error, count: result.errors.size }
        streams = [ turbo_stream.replace(REORDER_STATUS_ID, Admin::Ui::SaveStatusComponent.new(id: REORDER_STATUS_ID, **state)),
          picker_error_stream(result.errors) ]
        streams << blocks_list_stream if structural && !result.denied?
        Answer.new(streams: streams, status: status_for(result))
      end

      # A refused delete or duplicate: the card stays where it is, and the
      # alert says why.
      def refused(result) = Answer.new(streams: [ picker_error_stream(result.errors) ], status: status_for(result))
    end
  end
end
