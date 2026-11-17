module Admin
  module Fields
    # A Gallery block's images (`:media_list`): a hidden input holding the
    # list as JSON. Nobody types in it; the picker's script writes it and
    # dispatches `input`, so the form's autosave sends the list with the
    # rest. No label of its own, no original beside it (the images are the
    # same in every language) and no room in the card (`hidden?`): the
    # images are drawn by the block's own card. Its error slot stays, for a
    # list over its `max:` (`errors.messages.too_many_images`).
    class MediaListField < Base
      # How many images the list holds, as words; nil for none.
      def self.display(_field, value)
        count = Array(value).size
        count.zero? ? nil : I18n.t("admin.components.fields.media_list.display", count:)
      end

      def self.own_label?(_field) = true

      def self.reference?(_field) = false

      def self.hidden?(_field) = true

      def stored_json = Array(value).presence&.to_json
    end
  end
end
