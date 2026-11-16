module Admin
  module MediaLibrary
    # The confirm before a folder is deleted (the card StudioMediaFolders, D4;
    # PatternDestructiveActions): "Delete “Client A”?", what moves where, each
    # subfolder that will take another name, "This can't be undone.", and the
    # danger button Delete folder. Its words are `Media::DeleteFolder.preview`'s
    # (`preview:`), which the service itself follows: the folder's images and
    # subfolders move one level up, into its parent (`preview.target`), or,
    # for a folder at the top, its subfolders to the top and its images to Not
    # in a folder. A part with nothing to move is left out of the sentence; an
    # empty folder "is empty".
    #
    # It is drawn by the Media screen for the folder shown (`admin/media/index`,
    # for `media.manage`), inside the content frame, so a frame navigation to
    # another place draws it again with that place's words; the place menu's
    # "Delete folder…" opens it. The press goes through the write queue
    # (`admin--media--folder-dialog`), and the dialog closes on the answer:
    # the column's part sends the screen to the parent with the toast "Folder
    # deleted", and a refusal ("That folder is gone.") is an error toast
    # (`Admin::Answers::FolderRefused#toast`).
    #
    # `tree` names the subfolders a rename will touch; `query` is the search
    # the screen shows, which the parent's address keeps.
    class DeleteFolderDialogComponent < AdminComponent
      ID = "media-folder-delete-dialog"
      FORM_ID = "media-folder-delete-form"

      def initialize(folder:, preview:, tree:, query: {})
        @folder = folder
        @preview = preview
        @tree = tree
        @query = query.to_h.symbolize_keys
      end

      private

      attr_reader :folder, :preview, :tree, :query

      def words(key, **options) = t("admin.components.media_library.delete_folder_dialog.#{key}", **options)

      def title = words(:title, name: folder.name)

      # What moves where, in one sentence.
      def body
        images = preview.image_count.positive? ? words(:images, count: preview.image_count) : nil
        folders = preview.folder_count.positive? ? words(:folders, count: preview.folder_count) : nil
        return words(:empty) unless images || folders

        if preview.target
          return words(:into_parent_both, images: images, folders: folders, parent: preview.target.name) if images && folders

          words(:into_parent, things: images || folders, parent: preview.target.name)
        elsif images && folders then words(:to_top_both, images: images, folders: folders)
        elsif folders then words(:to_top_folders, folders: folders)
        else words(:to_top_images, images: images)
        end
      end

      # One sentence per subfolder whose name the parent (or the top) already holds.
      def renames
        preview.renames.filter_map do |id, to|
          from = tree.find(id)&.name
          next unless from

          if preview.target then words(:renamed, from: from, to: to, parent: preview.target.name)
          else words(:renamed_at_top, from: from, to: to)
          end
        end
      end

      def url = helpers.admin_media_folder_path(folder.id, **url_options)

      def search_value(key)
        value = query[key]
        value.is_a?(String) ? value : ""
      end

      def dialog_actions
        "turbo:before-fetch-request->admin--media--folder-dialog#send turbo:submit-end->admin--media--folder-dialog#sent"
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options.slice(:locale) : {}
    end
  end
end
