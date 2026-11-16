module Admin
  module MediaLibrary
    # The New folder and Rename folder dialog (the card StudioMediaFolders, D2
    # and D3): a small dialog, never typing in the tree (a row is a link with
    # a disclosure, and a field in it would fight both for the keyboard). Its
    # form is `FolderFormComponent`; under it Cancel and Create folder (or
    # Rename).
    #
    # ONE DIALOG FOR EVERY TRIGGER. The Media screen draws it once
    # (`admin/media/index`, for `media.manage`) and every trigger opens it by
    # its id (`dialog_trigger(ID)`): the Folders column's "+ New folder" (at
    # the top) and a row's "+" (inside that folder), the place menu's "New
    # folder inside…" and "Rename…". `admin--media--folder-dialog` sets it up
    # from the trigger pressed, as it opens: a create from `parent-id` and
    # `parent-path` (empty for the top), a rename from `folder-id`,
    # `folder-name` and `parent-path` (the `admin--media--folder-dialog-*-param`
    # attributes). What it is drawn with (`folder:`, `parent:`) is only its
    # first state; the title and the button are worded again at each opening
    # from the words this element carries (`data-messages`).
    #
    # The form is sent through the write queue; a refusal draws the form
    # again (`Admin::Answers::FolderRefused`) and the focus stays in the
    # field; a success closes the dialog, and the answer's column sends the
    # screen to the place (`admin--media--folders`).
    class FolderDialogComponent < AdminComponent
      ID = "media-folder-dialog"

      MESSAGES = %w[new_title rename_title create rename top inside].map { |key| "components.media_library.folder_dialog.#{key}" }.freeze

      def initialize(tree:, folder: nil, parent: nil, errors: nil, place: nil, query: {})
        @tree = tree
        @folder = folder
        @parent = parent
        @errors = errors
        @place = place
        @query = query
      end

      private

      attr_reader :tree, :folder, :parent, :errors, :place, :query

      def rename? = folder.present?

      def title = t("admin.components.media_library.folder_dialog.#{rename? ? 'rename_title' : 'new_title'}")

      def submit_label = t("admin.components.media_library.folder_dialog.#{rename? ? 'rename' : 'create'}")

      def form = FolderFormComponent.new(tree: tree, folder: folder, parent_id: parent&.id, errors: errors.to_h, place: place, query: query)

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options.slice(:locale) : {}

      # The two addresses the form is pointed at: the collection's for a
      # create, a folder's (its id written for `__ID__`) for a rename.
      def dialog_data
        actions = [ "admin--ui--dialog:opening@document->admin--media--folder-dialog#opening",
                    "turbo:before-fetch-request->admin--media--folder-dialog#send",
                    "turbo:submit-end->admin--media--folder-dialog#sent" ].join(" ")
        { controller: "admin--media--folder-dialog", action: actions, messages: messages_data(*MESSAGES),
          "admin--media--folder-dialog-create-url-value": helpers.admin_media_folders_path(**url_options),
          "admin--media--folder-dialog-update-url-value": helpers.admin_media_folder_path("__ID__", **url_options) }
      end
    end
  end
end
