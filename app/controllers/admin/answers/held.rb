module Admin
  module Answers
    # The 409 of a save from a tab that does not hold what it saves
    # (`Admin::EditingClaims#refuse_held`, which decides it): a 409 like a
    # stale save's, so the autosave script pauses the form the same way. The
    # status line names the holder (`:held`), the `lost` notice fills the
    # form's strip slot, with "Copy my text" and "Discard", and the form's
    # failed-save toast goes. No new base: nothing was written.
    class Held
      def initialize(view:)
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(subject:, hold:, viewer:, status_id:, error_prefix:, live:)
        strip = Admin::EditorScreen::HoldStripComponent.new(subject:, hold:, viewer:, kind: :lost)
        Answer.new(status: :conflict, streams: [
          @turbo_stream.replace(status_id, Admin::Ui::SaveStatusComponent.new(id: status_id, state: :held, live: live, holder: hold, viewer: viewer)),
          @turbo_stream.update(Admin::EditorScreen::HoldStripComponent.slot_id(subject), strip),
          @turbo_stream.remove("toast-#{error_prefix}")
        ])
      end
    end
  end
end
