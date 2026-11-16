module Admin
  module Answers
    # A folder deleted: the column's part, the parent (All media for a top
    # folder) as the place to go to, and the toast.
    class FolderDeleted
      include FolderTreePart

      def initialize(view:, url:, column:)
        @url = url
        @column = column
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(parent:)
        place = parent ? Media::Place.new(:folder, parent.id) : Media::Place::ALL
        Answer.new(status: :ok, streams: [
          tree_part_stream(place, go_to: @url.call(place)),
          Admin::ToastStream.for(@turbo_stream, I18n.t("admin.media.answers.folder_deleted"))
        ])
      end
    end
  end
end
