module Admin
  module Answers
    # The answer to a save, a delete or a duplicate of a block that no longer
    # exists (an editor's tab still open on a card another tab deleted): 410
    # with a fixed message (spec §5.1's "Interfaces" list) in the page's alert
    # slot, since there is no card left to replace a status line inside of.
    class BlockGone
      include BlockDrawing

      MESSAGE = "This block was deleted"

      def answer = Answer.new(streams: [ picker_error_stream([ MESSAGE ]) ], status: :gone)
    end
  end
end
