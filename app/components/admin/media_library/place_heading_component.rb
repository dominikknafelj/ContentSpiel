module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # The Media screen's heading over the grid (the card StudioMediaFolders,
    # D10): in a folder, the breadcrumb ("All media › Clients › Client A", the
    # last the place itself, unlinked); the `h1`, which is the place's name
    # ("Client A", "All media", "Not in a folder", while "Media" stays the
    # page's title and the sidebar's word); its count; and at the right the
    # Upload images button. The breadcrumb is a folder's only: All media and
    # Not in a folder are places of the top.
    #
    # The count's element is `#media-place-count` (`PLACE_COUNT_ID`), whose
    # whole text a move's answer replaces (`Admin::Answers::ImagesMoved`), so
    # both draw it through `.count_text`: the words ("1 image") are decided
    # in one place. It is the count of what the grid lists, the search and the
    # segment included, as the segment counts are.
    #
    # The breadcrumb's links are the places' (`query:` is `{ q:, filter: }`,
    # kept; `page`, `selected` and `select` dropped: what
    # `Admin::MediaPlaces#place_query` builds for the Folders column).
    #
    # Upload images opens the file input of the `admin--media--upload`
    # controller this heading is drawn inside (`admin/media/index`); `upload:
    # false` leaves it out. The folder actions' menu (after the count) and
    # Select (before Upload) stand at the two SLOT comments of the template;
    # `manage:` is whether the viewer holds `media.manage`, which the menu asks.
    class PlaceHeadingComponent < AdminComponent
      COUNT_ID = Admin::Answers::ImagesMoved::PLACE_COUNT_ID

      def self.count_text(count) = I18n.t("admin.components.media_library.place_heading.count", count: count)

      def initialize(place:, tree:, count:, query:, manage:, upload: true)
        @place = place
        @tree = tree
        @count = count
        @query = query
        @manage = manage
        @upload = upload
      end

      def folder? = place.folder.present?

      def upload? = @upload

      def manage? = @manage

      def name
        if place.all? then t("admin.components.media_library.folder_tree.all")
        elsif place.none? then t("admin.components.media_library.folder_tree.none")
        else tree.find(place.folder).name
        end
      end

      def count_text = self.class.count_text(count)

      # The places above the folder, the top first: All media, then each
      # ancestor folder.
      def ancestors
        crumbs = [ [ t("admin.components.media_library.folder_tree.all"), Media::Place::ALL ] ]
        tree.path(place.folder).each_with_object(crumbs) do |node, list|
          list << [ node.name, Media::Place.new(:folder, node.id) ] unless node.id == place.folder
        end
      end

      def place_href(each)
        kept = query.to_h.slice(:q, :filter).select { |_, value| value.is_a?(String) && value.present? }
        kept[:folder] = each.to_param unless each.all?
        helpers.admin_media_path(**kept, **url_options.slice(:locale))
      end

      def link_data = { turbo_frame: "content", turbo_action: "advance" }

      private

      attr_reader :place, :tree, :count, :query

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
