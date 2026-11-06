module Admin
  module Answers
    # The 409 of a save sent on a base older than the record's
    # (`Admin::AutosaveResponses#refuse_stale_autosave`, which decides it): the
    # status line reads "● CHANGED ELSEWHERE", the header's `#editor-notice`
    # explains it with a Reload (`Admin::EditorScreen::ChangedElsewhereComponent`),
    # and the form's failed-save toast goes, since this answer supersedes it.
    #
    # NO NEW BASE. The form keeps the base it sent, so every later save of it is
    # refused too until Reload: advancing it would turn the next keystroke into
    # the very overwrite just refused.
    class Stale
      def initialize(view:)
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(record:, status_id:, error_prefix:, reload_url:, since:, live:)
        Answer.new(status: :conflict, streams: [
          @turbo_stream.replace(status_id, Admin::Ui::SaveStatusComponent.new(id: status_id, state: :stale, live: live)),
          @turbo_stream.update("editor-notice", Admin::EditorScreen::ChangedElsewhereComponent.new(record: record, reload_url: reload_url, since: since)),
          @turbo_stream.remove("toast-#{error_prefix}")
        ])
      end
    end
  end
end
