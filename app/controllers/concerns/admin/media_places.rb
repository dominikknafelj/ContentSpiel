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
      query = request.parameters.slice("q", "filter").select { |_, value| value.is_a?(String) }.symbolize_keys
      query[:folder] = place.to_param unless place.all?
      query.merge(admin_url_options.slice(:locale))
    end

    # The place the screen was showing when a write was sent (`place`, the
    # same words as `folder`), All media when it is absent or names no folder
    # (a folder deleted meanwhile).
    def shown_place(tree)
      Media::Place.parse(params[:place], tree: tree) || Media::Place::ALL
    end
  end
end
