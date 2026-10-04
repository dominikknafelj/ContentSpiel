module Admin
  # `MediaLibrary`, not `Media`: a real `Admin::Media` module would shadow
  # the top-level `Media` module (`app/models/media/*`,
  # `app/services/media/*`) for every *bare* `Media::` reference lexically
  # nested under `module Admin` elsewhere in this app -- Ruby's constant
  # lookup checks a class's own lexical scope, `Admin` included, before it
  # ever falls back to the top level. That trap briefly existed mid-task
  # (see the git history) and broke the hero-image and image-block upload
  # paths (`NameError: uninitialized constant Admin::Media::Upload`)
  # without touching a single line of this module's own code -- named
  # `MediaLibrary` instead, so `Admin.const_defined?(:Media, false)` never
  # becomes true and no other `Admin::*` file ever has to remember to
  # write `::Media::` on its own account. `test/lib/admin_namespace_shadow_
  # test.rb` guards against this regressing, for every domain module.
  module MediaLibrary
    # The Media module's own grid (media library design spec §6, round 3 Task 8):
    # one `TileComponent` per asset, each linking to `/media?selected=ID` (the
    # side panel, `PanelComponent`) with the grid's own state (`link_params`:
    # `q`, `filter`, `page`) kept; `selected_id` is the tile with the ring.
    # Every asset this renders must be
    # loaded through `Media::Asset.with_variants` (`Media::Search`'s default
    # scope has it) -- `#thumbnail_url` reads `#srcset`, which is
    # exactly the N+1 that scope exists to prevent over a whole page of
    # cards.
    #
    # `pick: true` is the same grid inside `Media::PickerComponent`
    # (`Admin::MediaController#index` with `picker=1`, in its own frame): each
    # tile is then a button that selects it for the picker
    # (`TileComponent`'s own comment) instead of a link to the panel -- one
    # grid, one search/pagination endpoint, two ways of acting on a tile.
    # `locale` is the editing language the picked asset's default alt/caption
    # are read in, which the fields the picker fills show as placeholders.
    #
    # The `<ul>` is drawn even when there is nothing to list (the empty state
    # follows it, marked `data-media-empty`): an upload that finishes into an
    # empty library (`media/upload_tiles.js`) has a list to put its tiles in,
    # and takes the empty state away once it has.
    class GridComponent < Admin::AdminComponent
      def initialize(assets:, url_options: {}, pick: false, locale: ::Locales.default, selected_id: nil, link_params: {})
        @assets = assets
        @url_options = url_options
        @pick = pick
        @locale = locale
        @selected_id = selected_id
        @link_params = link_params.to_h.symbolize_keys
      end

      def pick? = @pick

      # A search or a segment is active, so an empty grid means "nothing
      # matches", not "nothing uploaded yet". The segment is judged as
      # `Media::Search` normalises it: a forged value, or `untranslated` on a
      # one-language site, is `all` and filters nothing. (The picker's grid asks
      # the same, from the same params.)
      def filtered?
        query = helpers.params[:q]
        (query.is_a?(String) && query.present?) || ::Media::Search.new(filter: helpers.params[:filter]).filter != "all"
      end

      # The unfiltered grid, staying in picker mode inside the picker's own
      # frame (a link inside a `<turbo-frame>` is scoped to it already), or
      # replacing the `content` frame's history entry on the full page.
      def clear_filters_path = helpers.admin_media_path(**url_options, **(pick? ? { picker: 1 } : {}))

      def clear_filters_data = pick? ? {} : { turbo_frame: "content", turbo_action: "replace" }

      # The thumbnail ruling (design spec §6): `Media::Asset#thumbnail_url`.
      def thumbnail_url(asset) = asset.thumbnail_url

      # The panel's URL for one tile: the grid's own state, the editing
      # language, and the choice.
      def show_path(asset) = helpers.admin_media_path(**link_params, **url_options, selected: asset.id)

      def selected?(asset) = asset.id == selected_id

      # Which of this page's images something uses, in ONE query (a tile's
      # `UNUSED` chip), the way `Media::Asset.unused` asks it: any `media_usages`
      # row at all.
      def used_ids = @used_ids ||= Media::Usage.where(media_asset_id: assets.map(&:id)).distinct.pluck(:media_asset_id).to_set

      def grid_class
        pick? ? "grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6" : "grid grid-cols-[repeat(auto-fill,minmax(10.5rem,1fr))] gap-3"
      end

      private

      attr_reader :assets, :url_options, :locale, :selected_id, :link_params
    end
  end
end
