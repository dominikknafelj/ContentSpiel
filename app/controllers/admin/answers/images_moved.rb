module Admin
  module Answers
    # Images moved (`Media::MoveImages`): the tiles that left the place shown
    # go (All media keeps them all), the segment counts and the place heading's
    # count are redrawn, each moved image's Folder fact is drawn again (an
    # open panel on it then names the folder it went to; the stream finds
    # nothing for any other), and the toast says how many went where.
    # `assets` are the images that changed folder; none, and nothing is drawn
    # but the counts.
    class ImagesMoved
      include FolderTreePart

      PLACE_COUNT_ID = "media-place-count"

      def initialize(view:)
        @turbo_stream = Answers.stream_builder(view)
      end

      # `column` draws the Folders column with its counts after the move
      # (`Admin::MediaPlaces#folder_column_for`), and `fact` an image's
      # Folder fact (`Admin::MediaPlaces#folder_fact_for`); a refusal draws
      # neither.
      def answer(assets:, folder:, place:, counts:, column:, fact:)
        @column = column
        streams = []
        streams.concat(assets.map { |asset| @turbo_stream.remove(Admin::MediaLibrary::TileComponent.dom_id(asset)) }) unless place.all?
        streams.concat(assets.map { |asset| @turbo_stream.replace(Admin::MediaLibrary::FolderFactComponent.dom_id(asset), fact.call(asset)) })
        streams.concat(counts.map { |key, count| @turbo_stream.update(Admin::MediaLibrary::ToolbarComponent.count_id(key), count.to_s) })
        streams << @turbo_stream.update(PLACE_COUNT_ID, Admin::MediaLibrary::PlaceHeadingComponent.count_text(counts.fetch(:all)))
        streams << tree_part_stream(place)
        streams << Admin::ToastStream.for(@turbo_stream, toast(assets, folder)) if assets.any?
        Answer.new(streams: streams, status: :ok)
      end

      # A refused move: the sentence as an error toast, nothing else drawn.
      def refused(errors:, status:)
        Answer.new(status: status, streams: [ Admin::ToastStream.for(@turbo_stream, errors.to_sentence, kind: :error) ])
      end

      private

      def toast(assets, folder)
        name = folder ? folder.name : I18n.t("admin.media.answers.no_folder")
        I18n.t("admin.media.answers.moved", count: assets.size, title: assets.first.title, folder: name)
      end
    end
  end
end
