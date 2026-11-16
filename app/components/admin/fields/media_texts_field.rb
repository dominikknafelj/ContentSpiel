module Admin
  module Fields
    # The captions and alt texts of a Gallery block's images
    # (`:media_texts`). It draws nothing but its error slot until the
    # block's card draws the texts beside each image: the card owns them,
    # as it owns the list, so no label and no original stand beside it.
    class MediaTextsField < Base
      def self.display(_field, _value) = nil

      def self.own_label?(_field) = true

      def self.reference?(_field) = false
    end
  end
end
