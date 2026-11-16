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
    #
    # DRAGGING ONTO THE COLUMN (the card's D5 and D8) is `admin--media--drag`'s,
    # on the Media screen's library, which reaches this tree by its id: an
    # image is dropped on a folder row or Not in a folder, a folder (by its
    # row's gutter handle, drawn for `manage:`) on a folder row or All media.
    # Which row can take a folder is read from the rows'
    # `data-media-folder-*` and the tree's `data-media-drag-max-depth`
    # (`Media::Folder::MAX_DEPTH`), so a refusal is said before anything is
    # sent; the server judges again.
    #
    # `mode: :picker` is the same places in `Admin::Ui::MediaPickerComponent`
    # (the card's D12), drawn by `admin/media/picker` inside the picker's
    # frame and answered again with every navigation of it. Its rows are
    # read-only (no "+", no handle, no drag, whatever `manage:` says) and
    # their links load the picker's frame (`picker=1`, no history entry: the
    # page under the dialog keeps its address). Its folds are a view state:
    # the path to the place is open and every other folder folded, and none
    # is kept (no `data-tree-open-cookie`, so `tree/open_set.js` reads and
    # writes no cookie for it; `open_set:` is not read). Its ids are its own
    # (`media-picker-…`), so it never meets the Media screen's column on a
    # page. Below 640px the same places are a select, "Folder", which
    # `admin--media--picker#place` follows; the picker's view lays the two
    # out (the list beside the grid, the select above the toolbar). The two
    # stand in one wrapper, `#media-picker-places` (`PICKER_PART_ID`, drawn
    # `display: contents`, so the frame's grid still places each), which a
    # tab that heard of a change elsewhere replaces whole.
    #
    # `digest:` is the place's `Media::Place#digest` and `gone:` whether the
    # folder that was asked for is gone (the place is then All media): both
    # are drawn on the part (`data-media-place-digest`,
    # `data-media-place-gone`, with the place as `data-media-part-place`) for
    # `admin--media--live`, which compares the digest with the one the tab
    # holds (the card's D13). A write's answer draws the digest too, so the
    # acting tab holds the digest of what its own answer drew.
    class FolderTreeComponent < AdminComponent
      ID = "media-folder-tree"
      PICKER_ID = "media-picker-folder-tree"
      PART_ID = "media-folder-tree-part"
      PICKER_PART_ID = "media-picker-places"
      MODES = %i[screen picker].freeze

      # The select's indent per level below the first, in no-break spaces: an
      # `<option>` draws no padding and collapses ordinary spaces.
      INDENT = "\u00A0" * 4

      ROW = Admin::Ui::TreeItemComponent::CLASSES

      def initialize(tree:, counts:, place:, query:, open_set:, manage:, mode: :screen, go_to: nil, digest: nil, gone: false)
        raise ArgumentError, "unknown mode #{mode.inspect}: one of #{MODES.join(', ')}" unless MODES.include?(mode)

        @tree = tree
        @counts = counts
        @place = place
        @query = query
        @mode = mode
        @open_set = picker? ? TreeOpenSet::EMPTY : open_set
        @manage = manage && !picker?
        @go_to = go_to
        @digest = digest
        @gone = gone
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

      attr_reader :tree, :counts, :place, :query, :open_set, :manage, :mode, :go_to, :path_ids, :digest, :gone

      # The marks on the part for `admin--media--live` (none without a digest).
      def part_data
        return {} unless digest

        { media_part_place: place.to_param, media_place_digest: digest, media_place_gone: ("" if gone) }.compact
      end

      def picker? = mode == :picker

      def tree_id = picker? ? PICKER_ID : ID

      def row_id(each) = picker? ? "media-picker-place-row-#{each.to_param}" : self.class.row_id(each)

      def tree_data
        words = messages_data("components.ui.tree_item.fold", "components.ui.tree_item.unfold")
        return { controller: "admin--tree--disclosure", tree_locale: tree_locale, messages: words } if picker?

        { controller: "admin--tree--disclosure admin--media--folders",
          tree_open_path: "/#{ContentSpiel::ADMIN_PATH}", tree_open_cookie: TreeOpenSet::MEDIA_COOKIE, tree_locale: tree_locale,
          media_drag_tree: true, media_drag_max_depth: Media::Folder::MAX_DEPTH,
          messages: words,
          "admin--media--folders-selected-class": ROW[:row_selected],
          action: "turbo:frame-load@document->admin--media--folders#follow" }
      end

      def folders? = tree.size.positive?

      def selected?(each) = each == place

      # The address of `each`: the search and the segment kept, the place's
      # own `folder` (nothing for All media) and the language.
      def place_href(each)
        kept = query.to_h.slice(:q, :filter).select { |_, value| value.is_a?(String) && value.present? }
        kept[:folder] = each.to_param unless each.all?
        kept[:picker] = 1 if picker?
        helpers.admin_media_path(**kept, **url_options.slice(:locale))
      end

      # The select's choices below 640px: every place in the list's order,
      # a folder indented by its level, each with the address its row links to.
      def select_options
        places = [ [ t(".all"), Media::Place::ALL ], [ t(".none"), Media::Place::NONE ] ]
        places += folder_options(tree.roots, 1)
        safe_join(places.map { |text, each| tag.option(text, value: each.to_param, selected: selected?(each), data: { href: place_href(each) }) })
      end

      def folder_options(nodes, depth)
        nodes.flat_map do |node|
          [ [ "#{INDENT * (depth - 1)}#{node.name}", Media::Place.new(:folder, node.id) ], *folder_options(tree.children(node.id), depth + 1) ]
        end
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}

      def tree_locale = helpers.respond_to?(:admin_locale) ? helpers.admin_locale : Locales.default

      def link_data = picker? ? { turbo_frame: "media-picker-grid", tree_focus: true, action: "admin--media--picker#placePressed" } : { turbo_frame: "content", turbo_action: "advance", tree_focus: true }

      def row_data(each) = picker? ? { media_place: each.to_param } : { media_place: each.to_param, "admin--media--folders-target": "row" }

      def link(text, each)
        link_to text, place_href(each), id: "#{row_id(each)}-link", data: link_data, aria: (selected?(each) ? { current: "page" } : {})
      end

      # A place's count, shown at rest; nothing at 0. The span is drawn at 0
      # too, empty (the stylesheet draws an empty count, and a trailing
      # holding only one, as nothing), so an upload's answer can write the
      # place's new count into it (`updateCounts`, `media/upload_tiles.js`,
      # by `data-media-place-count`: `all`, `none` or the folder's id).
      def count_part(count, place)
        tag.span((count if count.to_i.positive?), class: ROW[:count], data: { media_place_count: place.to_param })
      end

      def glyph(name) = render("admin/shared/tree_glyph", name: name)

      # A folder's drag handle, in the row's gutter (`admin--media--drag`).
      # A part for the pointer only, as the block tile's grip is: the
      # keyboard's way to move a folder is the place menu's Move to…, so the
      # handle is no Tab stop and says nothing to a screen reader. Drawn
      # only where a pointer is fine and no find narrows the tree (the
      # stylesheet, `.admin-tree[data-media-drag-tree]`).
      def handle = tag.span("⠿", class: ROW[:handle], aria: { hidden: true }, data: { media_drag_handle: true })

      # What `admin--media--drag` judges a folder row by; the picker's rows
      # take no drop.
      def drag_data(node, depth)
        return {} if picker?

        { media_folder_depth: depth, media_folder_height: tree.height(node.id),
          media_folder_parent: node.parent_id.to_s, media_folder_name: node.name.downcase }
      end

      def children_list_id(node) = "#{picker? ? 'media-picker' : 'media'}-folder-children-#{node.id}"

      def folded?(node) = tree.children(node.id).any? && !open_set.open?(node.id, root: false, on_path: path_ids.include?(node.id))

      # One folder's `<li>`, its row and its children's list, drawn again for
      # each child: the nesting is this component's, on the tree's own classes.
      # The list stands under every folder, empty under a leaf.
      def folder_node(node, depth)
        folder_place = Media::Place.new(:folder, node.id)
        children = tree.children(node.id)
        folded = folded?(node)
        item = Admin::Ui::TreeItemComponent.new(
          id: row_id(folder_place), title: node.name, parent: children.any?, folded: folded,
          controls: children_list_id(node), selected: selected?(folder_place), node_id: node.id,
          data: row_data(folder_place).merge(drag_data(node, depth))
        )
        row = render(item) do |row_item|
          # Both marks: the stylesheet shows the open folder on the selected
          # row and the closed one elsewhere, so a selection the script moves
          # swaps them too.
          row_item.with_mark { safe_join([ glyph(:folder), glyph(:folder_open) ]) }
          row_item.with_title { link(node.name, folder_place) }
          count = count_part(counts.fetch(:folders, {})[node.id], folder_place)
          row_item.with_trailing { count }
          if manage && depth < Media::Folder::MAX_DEPTH
            row_item.with_add(label: t("admin.components.media_library.folder_tree.add", name: node.name), data: self.class.add_params(node.id, tree.path_name(node.id)))
          end
          row_item.with_handle { handle } if manage
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
