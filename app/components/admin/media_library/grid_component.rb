module Admin
  # `MediaLibrary`, not `Media`: a real `Admin::Media` module would shadow
  # the top-level `Media` module (`app/models/media/*`,
  # `app/services/media/*`) for every *bare* `Media::` reference lexically
  # nested under `module Admin` elsewhere in this app -- Ruby's constant
  # lookup checks a class's own lexical scope, `Admin` included, before it
  # ever falls back to the top level, so the hero-image and image-block
  # upload paths would raise `NameError: uninitialized constant
  # Admin::Media::Upload` without a line of this module's own code changed.
  # Named `MediaLibrary`, `Admin.const_defined?(:Media, false)` never becomes
  # true and no other `Admin::*` file has to remember to write `::Media::` on
  # its own account. `test/lib/admin_namespace_shadow_test.rb` guards it, for
  # every domain module.
  module MediaLibrary
    # The Media module's own grid: one `TileComponent` per asset, each
    # linking to `/media?selected=ID` (the side panel, `PanelComponent`) with
    # the grid's own state (`link_params`: `q`, `filter`, `page`) kept;
    # `selected_id` is the tile drawn as chosen (`aria-current`).
    # Every asset this renders must be
    # loaded through `Media::Asset.with_file` (`Media::Search`'s default
    # scope has it) -- `#thumbnail_url` reads `#srcset`, which is
    # exactly the N+1 that scope exists to prevent over a whole page of
    # cards.
    #
    # `pick: true` is the same grid inside `Admin::Ui::MediaPickerComponent`
    # (`Admin::MediaController#index` with `picker=1`, in its own frame): each
    # tile is then a button that selects it for the picker
    # (`TileComponent`'s own comment) instead of a link to the panel -- one
    # grid, one search/pagination endpoint, two ways of acting on a tile.
    # `select: true` is the Media screen's selection mode (`select=1`): each
    # tile a button that `admin--media--selection` ticks (`TileComponent`'s
    # own comment), and no link to the panel, which is closed.
    #
    # `locale` is the editing language the picked asset's default alt/caption
    # are read in, which the fields the picker fills show as placeholders.
    #
    # The `<ul>` is drawn even when there is nothing to list (the empty state
    # follows it, marked `data-media-empty`): an upload that finishes into an
    # empty library (`media/upload_tiles.js`) has a list to put its tiles in,
    # and takes the empty state away once it has. Its words are
    # `admin.components.media_library.grid.empty.*`.
    class GridComponent < Admin::AdminComponent
      def initialize(assets:, url_options: {}, pick: false, locale: ::Locales.default, selected_id: nil, link_params: {},
                     place: ::Media::Place::ALL, tree: nil, subfolders: [], select: false)
        @select = select
        @place = place
        @tree = tree
        @subfolders = subfolders
        @assets = assets
        @url_options = url_options
        @pick = pick
        @locale = locale
        @selected_id = selected_id
        @link_params = link_params.to_h.symbolize_keys
      end

      def pick? = @pick

      def select? = @select

      # A tile's link to its panel; none for a button (the picker's, a selection's).
      def tile_url(asset) = (show_path(asset) unless pick? || select?)

      # An empty place that is no search's empty answer: a folder (it takes
      # the upload into it and names the folders it holds) or Not in a folder.
      # Nothing in the picker, whose places are read-only.
      def empty_folder? = !pick? && !filtered? && place.folder.present? && tree
      def empty_none? = !pick? && !filtered? && place.none?

      def folder_name = tree.find(place.folder).name

      # Its subfolders are links to their places, never tiles.
      def holds_text
        links = subfolders.map { |node| link_to(node.name, helpers.admin_media_path(folder: node.id, **url_options.slice(:locale)), class: "text-accent", data: { turbo_frame: "content", turbo_action: "advance" }) }
        t(".empty_folder.holds_html", count: links.size, links: safe_join(links, t(".empty_folder.separator")))
      end

      # The folder a tile names under a search in All media, its whole path
      # ("Clients / Client A"); nothing without a search, in a folder's own
      # place (it is the folder) or for an image in no folder.
      def folder_path(asset)
        return unless tree && place.all? && searching? && asset.folder_id

        tree.path_name(asset.folder_id).presence
      end

      def searching? = helpers.params[:q].is_a?(String) && helpers.params[:q].present?

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

      # The grid's thumbnail is `Media::Asset#thumbnail_url`.
      def thumbnail_url(asset) = asset.thumbnail_url

      # The panel's URL for one tile: the grid's own state, the editing
      # language, and the choice.
      def show_path(asset) = helpers.admin_media_path(**link_params, **url_options, selected: asset.id)

      def selected?(asset) = asset.id == selected_id

      # Which of this page's images something uses, in ONE query (a tile's
      # `UNUSED` chip), the way `Media::Asset.unused` asks it: any `media_usages`
      # row at all.
      def used_ids = @used_ids ||= Media::Usage.where(media_asset_id: assets.map(&:id)).distinct.pluck(:media_asset_id).to_set

      # Open notes per image on this page of the grid, one grouped query like
      # `used_ids`, and one beside it for the images with something unread
      # for the viewer. Not in the picker: choosing an
      # image is not the place to read about it. Both come from
      # `Admin::NoteCountsHelper#media_note_marks`, which is also where the
      # viewer's right to know is asked; `assets` is a page of
      # `Media::Search#results`, kept images only.
      def note_counts = note_marks.first

      def note_unread = note_marks.last

      def note_marks = @note_marks ||= pick? ? [ {}, Set.new ] : helpers.media_note_marks(assets.map(&:id))

      def grid_class
        pick? ? "grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6" : "grid grid-cols-[repeat(auto-fill,minmax(10.5rem,1fr))] gap-3"
      end

      private

      attr_reader :assets, :url_options, :locale, :selected_id, :link_params, :place, :tree, :subfolders
    end
  end
end
