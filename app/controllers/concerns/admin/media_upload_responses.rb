module Admin
  # What both upload endpoints (`Admin::MediaController#create`, the Media
  # screen's drop zone and button; `Admin::MediaAssetsController#create`, the
  # picker's header Upload) answer a finished upload with:
  # enough for the browser to turn the file's progress tile into the real one
  # and fix the segment counts without reloading anything -- a reload would
  # throw away what an editor is typing in the side panel, and the other
  # progress tiles still in flight.
  #
  # - `id`, `title`, `url` as before (the picker's own contract);
  # - `tile`: the finished tile's HTML, drawn by `Admin::MediaLibrary::TileComponent`
  #   itself (a link into the panel on the Media screen, a pick button in the
  #   picker) so the markup has one author; and
  # - `folder_counts`: `Media::FolderCounts.call`, the Folders column's numbers
  #   (every folder's direct images, those outside any folder, all); and
  # - `counts`: `Media::Search#counts` for the search the grid was showing
  #   (`q` rides along with the file; it respects the search, never the
  #   segment) -- the same numbers the panel's autosave answer rewrites; and
  # - `place` and `place_digest`: the place the file was sent to and its
  #   `Media::Place#digest` now, which the uploading tab holds from here on
  #   (`admin--media--live`): its grid shows the new tile already, so a
  #   later change elsewhere is not taken for a change of what it shows.
  #
  # The server's verdict is the only one: a refusal is `{ errors: [...] }` at
  # 403/422 and the tile it belongs to keeps that reason with a Dismiss button.
  module MediaUploadResponses
    private

    def upload_json(asset, picker:)
      tile = if picker
        Admin::MediaLibrary::TileComponent.new(asset: asset, unused: !asset.used?, pick: true, locale: admin_locale)
      else
        # The link keeps the grid's state like every other tile's (`GridComponent#show_path`):
        # the browser sends `q`, `filter` and `page` along with the file.
        Admin::MediaLibrary::TileComponent.new(asset: asset, unused: !asset.used?,
          url: admin_media_path(**upload_list_query, **admin_url_options, selected: asset.id))
      end

      {
        id: asset.id, title: asset.title, url: asset.display_url(min_width: 960),
        tile: view_context.render(tile),
        counts: media_counts,
        folder_counts: Media::FolderCounts.call,
        place: requested_place&.to_param,
        place_digest: requested_place&.digest(Media::FolderTree.load)
      }
    end

    # The segment counts for the search and the place the grid is showing (they
    # respect the search, never the segment). One place for the upload answer and
    # the panel's autosave answer (`Admin::MediaController#grid_streams`).
    def media_counts
      Media::Search.new(q: params[:q], place: requested_place || Media::Place::ALL, actor: Current.actor).counts
    end

    # The place `folder` names, nil when it names no folder.
    def requested_place
      return @requested_place if defined?(@requested_place)

      @requested_place = Media::Place.parse(params[:folder], tree: Media::FolderTree.load)
    end

    # The folder an upload lands in: the place's, or none. A `folder` that names
    # no folder is not "no folder": the upload is made to a folder that is gone
    # (id 0 when it is no number at all) and `Media::Upload` refuses it.
    def upload_folder_id
      place = requested_place
      return place.folder if place

      Integer(params[:folder].to_s, 10, exception: false) || 0
    end

    def upload_list_query
      params.permit(:q, :filter, :folder, :page).to_h.symbolize_keys.select { |_, value| value.is_a?(String) }
    end
  end
end
