module Admin
  module Answers
    # A folder write the service refused: the dialog's form (`#media-folder-form`)
    # put back with the sentences under their fields. `errors` maps a field
    # (`name`, `parent_id`, or `base`) to its sentences.
    class FolderRefused
      FORM_ID = "media-folder-form"

      def initialize(view:)
        @view = view
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(errors:, status:, form: FORM_ID)
        lines = errors.flat_map do |field, sentences|
          Array(sentences).map { |sentence| @view.tag.p(sentence, class: "text-sm text-danger", role: "alert", data: { media_folder_error: field }) }
        end
        Answer.new(status: status, streams: [ @turbo_stream.replace(form, @view.tag.div(@view.safe_join(lines), id: form)) ])
      end
    end
  end
end
