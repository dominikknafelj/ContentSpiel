module Admin
  module Answers
    # A folder created, renamed or moved: the column's part, and the place to
    # go to. A create goes to the new folder; a rename or a move keeps the
    # place shown. No toast for a create or a rename: the folder appearing in
    # the column is the answer. A move says where the folder went ("Moved
    # “Client A” to “Events”.", or to the top of the library), since its row
    # may now stand under a folded branch.
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

      def answer(folder:, place:, created:, moved: false)
        go = created ? Media::Place.new(:folder, folder.id) : place
        streams = [ tree_part_stream(go, go_to: @url.call(go)) ]
        streams << Admin::ToastStream.for(@turbo_stream, moved_toast(folder)) if moved
        Answer.new(streams: streams, status: created ? :created : :ok)
      end

      private

      def moved_toast(folder)
        parent = folder.parent
        return I18n.t("admin.media.answers.folder_moved_to_top", name: folder.name) unless parent

        I18n.t("admin.media.answers.folder_moved", name: folder.name, parent: parent.name)
      end
    end
  end
end
