module Admin
  module Answers
    # The Folders column's part (`#media-folder-tree-part`). The column is the
    # shell's tree column, outside `#content`, so an answer to a write drawn in
    # the content frame never redraws it: each folder or move answer replaces
    # the part itself with the column as it stands after the write
    # (`Admin::MediaLibrary::FolderTreeComponent`). `@column` builds it
    # (`Admin::MediaPlaces#folder_column_for`): the place selected, and `go_to`
    # the address of the place the screen goes to next (`data-media-go`);
    # nothing for an answer that only redraws counts.
    module FolderTreePart
      TARGET = Admin::MediaLibrary::FolderTreeComponent::PART_ID

      private

      def tree_part_stream(place, go_to: nil)
        @turbo_stream.replace(TARGET, @column.call(place, go_to: go_to))
      end
    end
  end
end
