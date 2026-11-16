module Admin
  module MediaLibrary
    # The Move to… dialog's list (the card StudioMediaFolders, D7), the answer
    # of `GET /media/move/new` into `MoveDialogComponent`'s frame, and drawn
    # again with a refusal on top when a move it sent was refused.
    #
    # `subject:` is what moves: `{ kind: :images, ids: }` or `{ kind: :folder,
    # folder: }`. `current:` is where it stands now, a `Media::Place` (for a
    # folder, `Media::Place::NONE` is the top of the library), or nil when the
    # images stand in more than one place.
    #
    # Top to bottom: the refusal (a danger notice, which the dialog's script
    # focuses as it appears), the find ("Find a folder", outside the form, so
    # Enter in it sends nothing; it hides the rows whose name does not hold
    # what is typed), and the form: a radiogroup named by the dialog's title,
    # its first row "Not in a folder" (images) or "Top of the library" (a
    # folder), then every folder, a folder before its children, every branch
    # open, stepped 20px a level. The current place is marked "Current" and
    # cannot be chosen. In a folder move the folder and its branch ("this
    # folder") and every place where the folder's deepest folder would stand
    # deeper than `Media::Folder::MAX_DEPTH` ("too deep") cannot be chosen
    # either; the reason stands at the row's end and is the radio's
    # description. The services refuse all of these again: the list only
    # spares a person the press.
    #
    # The form is the write itself: images go by `POST /media/move` (`folder`
    # the place's words), a folder by `PATCH /media_folders/:id`
    # (`media_folder[parent_id]`, empty for the top). It carries the place
    # and the search the screen shows (`place`, `q`, `filter`), which the
    # answer keeps, and `dialog=move`, which asks for a refusal to be drawn
    # here rather than as a toast. A subject folder deleted meanwhile has no
    # list: the notice says so alone.
    class MoveChoicesComponent < AdminComponent
      FORM_ID = "media-move-form"

      NOTICE_ID = "media-move-refusal"

      # The `dialog` parameter's value that answers a refusal with this list.
      DIALOG = "move".freeze

      # The row's start padding by its step (8px, then 20px a level).
      INDENT = %w[ps-2 ps-7 ps-12 ps-17].freeze

      Row = Data.define(:value, :label, :step, :glyph, :current, :reason)

      def initialize(tree:, subject:, current:, refusal: nil, place: nil, query: {}, url_options: {})
        @tree = tree
        @subject = subject
        @current = current
        @refusal = Array(refusal).presence
        @place = place
        @query = query.to_h
        @url_options = url_options
      end

      def folder? = subject.fetch(:kind) == :folder

      def refusal = @refusal&.join(" ")

      # A folder that is gone has no place to move to.
      def list? = !(folder? && tree.find(moved_folder.id).nil?)

      def rows
        first = Row.new(value: folder? ? "" : Media::Place::NONE.to_param, label: words(folder? ? :top : :none), step: 0,
                        glyph: (:folder_none unless folder?), current: current == Media::Place::NONE, reason: nil)
        [ first ] + tree.each_in_order.map do |node, depth|
          Row.new(value: node.id.to_s, label: node.name, step: depth - 1, glyph: :folder,
                  current: current == Media::Place.new(:folder, node.id), reason: reason_for(node, depth))
        end
      end

      def disabled?(row) = row.current || row.reason.present?

      def choice_id(row) = "media-move-choice-#{row.value.presence || 'top'}"

      def reason_id(row) = "#{choice_id(row)}-why"

      def indent(row) = INDENT.fetch(row.step)

      def choice_name = folder? ? "media_folder[parent_id]" : "folder"

      def form_url
        locale = url_options.slice(:locale)
        folder? ? helpers.admin_media_folder_path(moved_folder.id, **locale) : helpers.admin_media_move_path(**locale)
      end

      def form_method = folder? ? :patch : :post

      def asset_ids = folder? ? [] : Array(subject.fetch(:ids)).map(&:to_s)

      def hidden_fields = { place: place.to_s, q: query[:q].to_s, filter: query[:filter].to_s, dialog: DIALOG }

      def words(key) = t("admin.components.media_library.move_dialog.#{key}")

      def title_id = "#{MoveDialogComponent::ID}-title"

      private

      attr_reader :tree, :subject, :current, :place, :query, :url_options

      def moved_folder = subject.fetch(:folder)

      # Why the folder being moved cannot go into `node` at `depth`, or nil.
      def reason_for(node, depth)
        return nil unless folder?
        return :this_folder if tree.inside?(node.id, of: moved_folder.id)

        :too_deep if depth + tree.height(moved_folder.id) > Media::Folder::MAX_DEPTH
      end
    end
  end
end
