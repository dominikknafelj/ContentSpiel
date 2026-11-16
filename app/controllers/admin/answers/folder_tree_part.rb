module Admin
  module Answers
    # The Folders column's part (`#media-folder-tree-part`). The column is the
    # shell's tree column, outside `#content`, so an answer to a write drawn in
    # the content frame never redraws it: each folder or move answer replaces
    # the part itself. `go` is the address of the place the screen goes to next
    # (`data-media-go`); nothing for an answer that only redraws counts.
    module FolderTreePart
      TARGET = "media-folder-tree-part"

      private

      def tree_part_stream(go: nil)
        @turbo_stream.replace(TARGET, @view.tag.div(id: TARGET, data: { media_go: go }))
      end
    end
  end
end
