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
    # false` leaves it out. Select, before it, enters selection mode: a
    # content-frame link to `select_url` (the place as listed, with
    # `select=1`, which the screen builds), drawn while the place lists an
    # image. In selection mode (`selecting: true`) the right end holds neither:
    # the selection's bar (`SelectionBarComponent`) stands over the grid
    # instead, sticky over what it acts on, which a bar inside this heading
    # could not be (a sticky box sticks only inside its parent).
    #
    # THE FOLDER'S MENU (D10), after the count: in a folder, for `manage:`
    # (the viewer holds `media.manage`), the ⋯ "Folder actions" with "New
    # folder inside…" (levels 1 to 3: a folder at level 4 can hold none),
    # "Rename…", "Move to…", and after a separator "Delete folder…". The
    # first two open the one folder dialog (`FolderDialogComponent`), told by
    # their params what for (`admin--media--folder-dialog`); "Move to…" the
    # Move to… dialog for this folder (`MoveDialogComponent`, the keyboard's
    # and a coarse pointer's way to move a folder); the last the delete
    # confirm the Media screen draws for this folder
    # (`DeleteFolderDialogComponent`).
    class PlaceHeadingComponent < AdminComponent
      COUNT_ID = Admin::Answers::ImagesMoved::PLACE_COUNT_ID

      def self.count_text(count) = I18n.t("admin.components.media_library.place_heading.count", count: count)

      def initialize(place:, tree:, count:, query:, manage:, upload: true, select_url: nil, selecting: false)
        @select_url = select_url
        @selecting = selecting
        @place = place
        @tree = tree
        @count = count
        @query = query
        @manage = manage
        @upload = upload
      end

      def folder? = place.folder.present?

      def upload? = @upload && !selecting?

      def selecting? = @selecting

      def select? = @select_url.present? && !selecting? && count.positive?

      attr_reader :select_url

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

      def menu? = manage? && folder?

      def new_inside? = tree.depth(place.folder) < Media::Folder::MAX_DEPTH

      def new_inside_data = FolderTreeComponent.add_params(place.folder, tree.path_name(place.folder))

      def rename_data
        node = tree.find(place.folder)
        { "admin--ui--dialog-id-param": FolderDialogComponent::ID,
          action: "admin--ui--dialog#open",
          "admin--media--folder-dialog-folder-id-param": node.id.to_s,
          "admin--media--folder-dialog-folder-name-param": node.name,
          "admin--media--folder-dialog-parent-path-param": (node.parent_id ? tree.path_name(node.parent_id) : "") }
      end

      def move_data = MoveDialogComponent.folder_trigger(tree.find(place.folder))

      # The icon (`folder_input`) and the words, on one line.
      def move_label
        tag.span(class: "inline-flex items-center gap-2") do
          safe_join([ helpers.render("admin/shared/icon", name: :folder_input, size: "size-4").strip.html_safe, t(".move") ])
        end
      end

      def delete_data = dialog_trigger(DeleteFolderDialogComponent::ID)

      private

      attr_reader :place, :tree, :count, :query

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
