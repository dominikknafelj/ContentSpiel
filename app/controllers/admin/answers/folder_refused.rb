module Admin
  module Answers
    # A folder write the service refused.
    #
    # A create or a rename is the folder dialog's form, which is drawn again
    # WHOLE in place of `#media-folder-form` (`form`, an
    # `Admin::MediaLibrary::FolderFormComponent`): the name as it was typed,
    # every sentence of the refusal under the field, and the same address,
    # method and parent, so the next press sends the same write. The dialog
    # stays open and `admin--media--folder-dialog` puts the focus back in the
    # field.
    #
    # A delete, or a move (which sends no name), has no field to stand under:
    # its sentences are an error toast (`#toast`), and the confirm closes.
    class FolderRefused
      FORM_ID = Admin::MediaLibrary::FolderFormComponent::ID

      def initialize(view:)
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(form:, status:)
        Answer.new(status: status, streams: [ @turbo_stream.replace(FORM_ID, form) ])
      end

      def toast(sentences:, status:)
        Answer.new(status: status, streams: [ Admin::ToastStream.for(@turbo_stream, Array(sentences).join(" "), kind: :error) ])
      end
    end
  end
end
