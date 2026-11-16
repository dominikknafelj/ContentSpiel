module Admin
  # What the Media screen's three controllers (`MediaController`,
  # `MediaFoldersController`, `MediaMovesController`) share about places.
  module MediaPlaces
    extend ActiveSupport::Concern

    included do
      # The one builder of a link to a place (the Folders column's rows, the
      # breadcrumb, the picker's places, a write's answer): `q` and `filter`
      # kept, `folder` the place's own (nothing for All media), the language,
      # and never `page` (page 3 of one folder is no page of another),
      # `selected` or `select`.
      helper_method :place_query
    end

    private

    # `request.parameters`, not the query string alone: a write's `q` and
    # `filter` ride in its body, and for the listing the two are the same.
    def place_query(place)
      query = shown_query
      query[:folder] = place.to_param unless place.all?
      query.merge(admin_url_options.slice(:locale))
    end

    # The search and the segment the screen shows (`q`, `filter`, Strings
    # only), which every link to a place keeps: the Folders column's `query:`.
    def shown_query
      request.parameters.slice("q", "filter").select { |_, value| value.is_a?(String) }.symbolize_keys
    end

    # The Folders column as it stands after a write, `place` selected and
    # `go_to` the address the screen goes to next (`data-media-go`): the
    # answers' part (`Admin::Answers::FolderTreePart`).
    def folder_column_for(place, go_to: nil)
      tree = Media::FolderTree.load
      Admin::MediaLibrary::FolderTreeComponent.new(
        tree: tree, counts: Media::FolderCounts.call, place: place, query: shown_query,
        open_set: TreeOpenSet.parse(cookies[TreeOpenSet::MEDIA_COOKIE], readable_ids: tree.ids),
        manage: can?("media.manage"), go_to: go_to
      )
    end

    # The place the screen was showing when a write was sent (`place`, the
    # same words as `folder`), All media when it is absent or names no folder
    # (a folder deleted meanwhile).
    def shown_place(tree)
      Media::Place.parse(params[:place], tree: tree) || Media::Place::ALL
    end
  end
end
