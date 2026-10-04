module Admin
  # What both upload endpoints (`Admin::MediaController#create`, the Media
  # screen's drop zone and button; `Admin::MediaAssetsController#create`, the
  # picker's header Upload) answer a finished upload with (round 3, Task 9):
  # enough for the browser to turn the file's progress tile into the real one
  # and fix the segment counts without reloading anything -- a reload would
  # throw away what an editor is typing in the side panel, and the other
  # progress tiles still in flight.
  #
  # - `id`, `title`, `url` as before (the picker's own contract);
  # - `tile`: the finished tile's HTML, drawn by `Admin::MediaLibrary::TileComponent`
  #   itself (a link into the panel on the Media screen, a pick button in the
  #   picker) so the markup has one author; and
  # - `counts`: `Media::Search#counts` for the search the grid was showing
  #   (`q` rides along with the file; it respects the search, never the
  #   segment) -- the same numbers the panel's autosave answer rewrites.
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
        id: asset.id, title: asset.title, url: asset.url,
        tile: view_context.render(tile),
        counts: media_counts
      }
    end

    # The segment counts for the search the grid is showing (they respect the
    # search, never the segment). One place for the upload answer and the panel's
    # autosave answer (`Admin::MediaController#grid_streams`).
    def media_counts
      Media::Search.new(q: params[:q], actor: Current.actor).counts
    end

    def upload_list_query
      params.permit(:q, :filter, :page).to_h.symbolize_keys.select { |_, value| value.is_a?(String) }
    end
  end
end
