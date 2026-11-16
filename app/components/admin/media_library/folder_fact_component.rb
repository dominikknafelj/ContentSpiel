module Admin
  module MediaLibrary
    # The image panel's Folder fact (the card StudioMediaFolders, D9), the
    # `dd` after Type: the image's folder as its path ("Clients / Client A"),
    # a link to that place, or "Not in a folder"; then, for a viewer who may
    # move the image (`movable:`, the panel's `editable?`, which mirrors
    # `Media::Ownership`), a tertiary small "Move to…" that opens the Move to…
    # dialog for this image. A viewer who may not move it sees the path alone.
    #
    # Its own component because two draw it: the panel, and a move's answer
    # (`Admin::Answers::ImagesMoved`), which replaces it by its id
    # (`.dom_id`, the image's own, so an answer never redraws the fact of a
    # panel that shows another image) with the folder the image went to.
    #
    # The link keeps the grid's search and segment (`query:`, `q` and
    # `filter`), as every link to a place does.
    class FolderFactComponent < AdminComponent
      def self.dom_id(asset) = "media-panel-folder-#{asset.id}"

      def initialize(asset:, tree:, movable:, query: {}, url_options: {})
        @asset = asset
        @tree = tree
        @movable = movable
        @query = query.to_h.symbolize_keys
        @url_options = url_options
      end

      def call
        tag.dd(id: self.class.dom_id(asset), class: "flex min-w-0 flex-wrap items-center justify-end gap-x-2 gap-y-1 text-right text-ink") do
          safe_join([ place_part, (move_button if @movable) ].compact)
        end
      end

      private

      attr_reader :asset, :tree, :query, :url_options

      def folder = asset.folder_id && tree.find(asset.folder_id)

      def place_part
        return tag.span(t("admin.components.media_library.panel.no_folder"), class: "text-meta") unless folder

        link_to(tree.path_name(folder.id), place_href, class: "min-w-0 break-words text-accent hover:underline",
          data: { turbo_frame: "content", turbo_action: "advance" })
      end

      def place_href
        kept = query.slice(:q, :filter).select { |_, value| value.is_a?(String) && value.present? }
        helpers.admin_media_path(**kept, folder: folder.id.to_s, **url_options.slice(:locale))
      end

      def move_button
        tag.button(type: "button", class: "#{Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)} gap-1.5",
                   data: MoveDialogComponent.images_trigger([ asset.id ], title: asset.title)) do
          safe_join([ helpers.render("admin/shared/icon", name: :folder_input, size: "size-4"), t("admin.components.media_library.panel.move") ])
        end
      end
    end
  end
end
