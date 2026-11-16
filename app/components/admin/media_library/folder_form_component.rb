module Admin
  module MediaLibrary
    # The form of the New folder and Rename folder dialog
    # (`Admin::MediaLibrary::FolderDialogComponent`; the card StudioMediaFolders,
    # D2 and D3): the field "Name", the sentences of a refusal under it, and
    # where the folder stands ("At the top of the library", "Inside Clients /
    # Client A") under those.
    #
    # It is its own component because it is drawn twice: inside the dialog,
    # and again WHOLE by a refused create or rename
    # (`Admin::Answers::FolderRefused`, which replaces `#media-folder-form`),
    # with the name as it was typed and every sentence of the refusal under
    # the field, whichever field the service named (`name`, `parent_id` or
    # the base: the dialog has one field to say them under).
    #
    # A create (`folder:` nil) posts to the collection and sends `parent_id`
    # (empty for the top); a rename (`folder:`) patches the folder and sends
    # no parent, so it never moves the folder. `parent_id:` is the parent as
    # it was asked for, which may name a folder deleted since: it is sent
    # again as it was, and with no folder of that id in `tree` the line
    # saying where is left out (the refusal says "That folder is gone.").
    # A rename of a folder already gone is drawn with a folder that holds
    # only its id (never saved): the same address, and no line saying where.
    #
    # `place`, `q` and `filter` are what the screen shows (a write's answer
    # keeps or leaves the place and keeps the search: `Admin::MediaPlaces`);
    # `admin--media--folder-dialog` writes them again, and everything else
    # that depends on what was pressed, at each opening.
    class FolderFormComponent < AdminComponent
      ID = "media-folder-form"
      NAME_ID = "media-folder-name"
      ERRORS_ID = "media-folder-name-errors"
      WHERE_ID = "media-folder-where"

      # `errors` maps a field (`name`, `parent_id`, `base`) to its sentences.
      def initialize(tree:, folder: nil, parent_id: nil, name: nil, errors: {}, place: nil, query: {})
        @tree = tree
        @folder = folder
        @parent_id = parent_id
        @name = name.nil? ? folder&.name : name
        @errors = errors.to_h.flat_map { |field, sentences| Array(sentences).map { |sentence| [ field.to_s, sentence ] } }
        @place = place
        @query = query.to_h.symbolize_keys
      end

      private

      attr_reader :tree, :folder, :parent_id, :name, :errors, :place, :query

      def rename? = folder.present?

      def url
        options = url_options.slice(:locale)
        rename? ? helpers.admin_media_folder_path(folder.id, **options) : helpers.admin_media_folders_path(**options)
      end

      def form_method = rename? ? "patch" : "post"

      # The id of the folder the line under the field names: the renamed
      # folder's parent, or the parent asked for.
      def where_id = rename? ? folder.parent_id : parent_id

      # "At the top of the library", "Inside Clients / Client A", or nil for a
      # parent that is gone.
      def where
        return if rename? && !folder.persisted?
        return t("admin.components.media_library.folder_dialog.top") if where_id.nil?
        return unless tree.find(where_id)

        t("admin.components.media_library.folder_dialog.inside", path: tree.path_name(where_id))
      end

      def described_by = [ (ERRORS_ID if errors.any?), WHERE_ID ].compact.join(" ")

      def search_value(key)
        value = query[key]
        value.is_a?(String) ? value : ""
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
