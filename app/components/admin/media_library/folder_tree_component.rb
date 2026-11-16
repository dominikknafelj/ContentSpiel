module Admin
  module MediaLibrary
    # The Folders column of the Media screen (media-folders spec, the card's
    # D1): the shell's tree column, subject `media`, which stands outside
    # `#content` and outlives a frame navigation. It is the places of the
    # library as rows of the shared tree (`Admin::Ui::TreeItemComponent`):
    # All media and Not in a folder, each with its count, a rule, then the
    # folders in natural order (`Media::FolderTree`), each with its direct
    # count (`Media::FolderCounts`; nothing at 0).
    #
    # The whole column is one part, `#media-folder-tree-part` (`PART_ID`),
    # which the full answer draws through the view's `content_for :tree` and
    # every folder or move answer replaces (`Admin::Answers::FolderTreePart`).
    # `go_to:` is the address the screen goes to after the write that drew it
    # (`data-media-go`, which `admin--media--folders` follows into the content
    # frame and takes away): a stream cannot navigate.
    #
    # THE SELECTED ROW IS THE PLACE SHOWN. `place:` is drawn selected here, so
    # the first paint is right; after a frame navigation the column is not
    # drawn again, and `admin--media--folders` moves the selection to the place
    # `#content` names, opens the path to it and rewrites every row's link to
    # the search the content shows. A row's link keeps `q` and `filter`
    # (`query:`, `{ q:, filter: }`), drops `page`, `selected` and `select`,
    # and carries the place's `folder` and the language: what
    # `Admin::MediaPlaces#place_query` builds.
    #
    # WHICH BRANCHES ARE OPEN is drawn from the first paint as the Pages tree's
    # are: `open_set:` is `cs_media_open` read against the folders
    # (`TreeOpenSet::MEDIA_COOKIE`), a folder tree has no root (`root: false`),
    # and the path to the place shown is open (`data-tree-on-path`). So by
    # default every folder is folded but those above the place. The folds are
    # written by `tree/open_set.js` alone, into the cookie the tree names
    # (`data-tree-open-cookie`).
    #
    # All media and Not in a folder are rows but not nodes of the tree (no
    # `data-tree-node`): a find over folders neither counts nor hides them.
    #
    # `manage:` is whether the viewer holds `media.manage` (the folder
    # writes): each folder row above the deepest level then carries its "+"
    # ("New folder in %{name}", levels 1 to 3; a folder at level 4 can hold
    # none), a button that opens the folder dialog
    # (`Admin::MediaLibrary::FolderDialogComponent`) to create inside it, with
    # the folder and its path as the trigger's params (`.add_params`). The
    # column head's "+ New folder" (the Media screen's view) is the same
    # trigger for the top. `mode:` is `:screen`, the Media screen's own column.
    class FolderTreeComponent < AdminComponent
      ID = "media-folder-tree"
      PART_ID = "media-folder-tree-part"
      MODES = %i[screen].freeze

      ROW = Admin::Ui::TreeItemComponent::CLASSES

      def initialize(tree:, counts:, place:, query:, open_set:, manage:, mode: :screen, go_to: nil)
        raise ArgumentError, "unknown mode #{mode.inspect}: one of #{MODES.join(', ')}" unless MODES.include?(mode)

        @tree = tree
        @counts = counts
        @place = place
        @query = query
        @open_set = open_set
        @manage = manage
        @mode = mode
        @go_to = go_to
        @path_ids = place.folder ? tree.path(place.folder).map(&:id).excluding(place.folder).to_set : Set.new
      end

      # The id of the row of `place` (a `Media::Place`), which the script
      # scrolls to.
      def self.row_id(place) = "media-place-row-#{place.to_param}"

      # What opens the folder dialog to create inside the folder `id` (nil:
      # at the top), whose path `path` the dialog says ("Inside Clients /
      # Client A"): `admin--media--folder-dialog` reads the two params as it
      # opens.
      def self.add_params(id, path)
        { "admin--ui--dialog-id-param": FolderDialogComponent::ID,
          action: "admin--ui--dialog#open",
          "admin--media--folder-dialog-parent-id-param": id.to_s,
          "admin--media--folder-dialog-parent-path-param": path.to_s }
      end

      private

      attr_reader :tree, :counts, :place, :query, :open_set, :manage, :mode, :go_to, :path_ids

      def folders? = tree.size.positive?

      def selected?(each) = each == place

      # The address of `each`: the search and the segment kept, the place's
      # own `folder` (nothing for All media) and the language.
      def place_href(each)
        kept = query.to_h.slice(:q, :filter).select { |_, value| value.is_a?(String) && value.present? }
        kept[:folder] = each.to_param unless each.all?
        helpers.admin_media_path(**kept, **url_options.slice(:locale))
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}

      def tree_locale = helpers.respond_to?(:admin_locale) ? helpers.admin_locale : Locales.default

      def link_data = { turbo_frame: "content", turbo_action: "advance", tree_focus: true }

      def row_data(each) = { media_place: each.to_param, "admin--media--folders-target": "row" }

      def link(text, each)
        link_to text, place_href(each), id: "#{self.class.row_id(each)}-link", data: link_data, aria: (selected?(each) ? { current: "page" } : {})
      end

      # A count, shown at rest; nothing at 0.
      def count_part(count)
        tag.span(count, class: ROW[:count], data: { media_place_count: true }) if count.to_i.positive?
      end

      def glyph(name) = render("admin/shared/tree_glyph", name: name)

      def children_list_id(node) = "media-folder-children-#{node.id}"

      def folded?(node) = tree.children(node.id).any? && !open_set.open?(node.id, root: false, on_path: path_ids.include?(node.id))

      # One folder's `<li>`, its row and its children's list, drawn again for
      # each child: the nesting is this component's, on the tree's own classes.
      # The list stands under every folder, empty under a leaf.
      def folder_node(node, depth)
        folder_place = Media::Place.new(:folder, node.id)
        children = tree.children(node.id)
        folded = folded?(node)
        item = Admin::Ui::TreeItemComponent.new(
          id: self.class.row_id(folder_place), title: node.name, parent: children.any?, folded: folded,
          controls: children_list_id(node), selected: selected?(folder_place), node_id: node.id,
          data: row_data(folder_place).merge(media_folder_depth: depth, media_folder_height: tree.height(node.id),
                                             media_folder_parent: node.parent_id.to_s, media_folder_name: node.name.downcase)
        )
        row = render(item) do |row_item|
          # Both marks: the stylesheet shows the open folder on the selected
          # row and the closed one elsewhere, so a selection the script moves
          # swaps them too.
          row_item.with_mark { safe_join([ glyph(:folder), glyph(:folder_open) ]) }
          row_item.with_title { link(node.name, folder_place) }
          count = count_part(counts.fetch(:folders, {})[node.id])
          row_item.with_trailing { count } if count
          if manage && depth < Media::Folder::MAX_DEPTH
            row_item.with_add(label: t("admin.components.media_library.folder_tree.add", name: node.name), data: self.class.add_params(node.id, tree.path_name(node.id)))
          end
        end
        list = tag.ul(id: children_list_id(node), class: ROW[:children], hidden: folded, data: { tree_children: true }) do
          safe_join(children.map { |child| folder_node(child, depth + 1) })
        end
        tag.li(safe_join([ row, list ]), class: "admin-tree-node",
               data: { tree_node: true, folded: (true if folded), tree_on_path: (true if path_ids.include?(node.id)) }.compact)
      end
    end
  end
end
