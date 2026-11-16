module Admin
  module MediaLibrary
    # The Move to… dialog (the card StudioMediaFolders, D7): where images, or
    # one folder, go. Only its SHELL is drawn with the screen: the title, an
    # empty `<turbo-frame id="media-move-choices">` and the footer's Cancel and
    # Move here (primary, disabled until a place is chosen). The list itself
    # (`MoveChoicesComponent`, `GET /media/move/new`) is loaded each time the
    # dialog opens, for the subject of the trigger pressed, from the tree as
    # it then is: a list drawn with the screen would go stale with every
    # folder another tab makes, and what a folder move must refuse depends on
    # the folder.
    #
    # ONE DIALOG FOR EVERY TRIGGER. The Media screen draws it once
    # (`admin/media/index`); the triggers are the panel's Folder fact, the
    # place menu's "Move to…" and the selection's bar. A trigger's `data:` is
    # `.images_trigger` or `.folder_trigger`, the one writer of the params
    # `admin--media--move` reads as the dialog opens: `asset-ids` (the ids,
    # comma-joined), `folder-id` and `title` (the one image's title, or the
    # folder's name), from which it words the title and loads the list.
    #
    # The list's form is sent through the write queue; a refusal draws the
    # list again with the danger notice on top, which takes the focus; a
    # success closes the dialog and the answer's streams move the screen.
    class MoveDialogComponent < AdminComponent
      ID = "media-move-dialog"

      FRAME_ID = "media-move-choices"

      MESSAGES = %w[title.images title.folder].map { |key| "components.media_library.move_dialog.#{key}" }.freeze

      # What opens the dialog for the images `ids`; `title` is the image's
      # title when there is one image (the dialog says "Move “beach.jpg”").
      def self.images_trigger(ids, title: nil)
        { "admin--ui--dialog-id-param": ID, action: "admin--ui--dialog#open",
          "admin--media--move-asset-ids-param": Array(ids).join(","),
          "admin--media--move-title-param": title.to_s }
      end

      # What opens the dialog for the folder `folder` (a `Media::Folder` or a
      # `Media::FolderTree::Node`).
      def self.folder_trigger(folder)
        { "admin--ui--dialog-id-param": ID, action: "admin--ui--dialog#open",
          "admin--media--move-folder-id-param": folder.id.to_s,
          "admin--media--move-title-param": folder.name }
      end

      def initialize(url_options: {})
        @url_options = url_options
      end

      private

      attr_reader :url_options

      def choices_url = helpers.admin_new_media_move_path(**url_options.slice(:locale))

      def dialog_data
        actions = [ "admin--ui--dialog:opening@document->admin--media--move#opening",
                    "input->admin--media--move#find",
                    "change->admin--media--move#choose",
                    "turbo:before-fetch-request->admin--media--move#send",
                    "turbo:submit-end->admin--media--move#sent" ].join(" ")
        { controller: "admin--media--move", action: actions, messages: messages_data(*MESSAGES),
          "admin--media--move-url-value": choices_url }
      end
    end
  end
end
