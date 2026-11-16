module Admin
  module Answers
    # A folder created, renamed or moved: the column's part, and the place to
    # go to. A create goes to the new folder; a rename or a move keeps the
    # place shown. No toast: the folder appearing in the column is the answer.
    class FolderSaved
      include FolderTreePart

      TREE_TARGET = FolderTreePart::TARGET

      # `url` turns a `Media::Place` into the address the screen goes to
      # (`Admin::MediaPlaces#place_query`), and `column` a place and that
      # address into the column (`Admin::MediaPlaces#folder_column_for`).
      def initialize(view:, url:, column:)
        @url = url
        @column = column
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(folder:, place:, created:)
        go = created ? Media::Place.new(:folder, folder.id) : place
        Answer.new(streams: [ tree_part_stream(go, go_to: @url.call(go)) ], status: created ? :created : :ok)
      end
    end
  end
end
