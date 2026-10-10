module Admin
  module EditorScreen
    # One line of a block's content on its tile (sections spec §4.2): the
    # start of a text, an image's file name with a small thumbnail, a post
    # list's filter. A block in a section's column is a tile until it is
    # opened, so this line is all that says which block it is -- and what
    # marks the ones that need attention, as a card would: an image block
    # without an image, a type that is no longer registered, a save that was
    # refused as invalid (`invalid:`).
    #
    # WHAT THE LINE IS comes from the type's definition, never from its name:
    # the columns it uses (`uses_columns`) and its capabilities, so a type a
    # plugin registers gets a sensible tile without being known here. A type
    # that uses an image AND a body is summarised by its image, the first rule
    # that matches. A type with neither and no listing has no line at all;
    # its tile is its label.
    #
    # It is its own component with its own id because it is the one part of
    # a tile that a save changes: `Admin::ContentBlocksController#update`
    # replaces it (`dom_id`) with every answer for a block in a section. The
    # tile around it -- the button that holds the focus and `aria-expanded`
    # -- is never re-rendered by a save.
    #
    # `invalid:` is only ever true in such an answer. A block's stored state
    # is always valid, so a tile drawn with the page has nothing to say here.
    class TileSummaryComponent < AdminComponent
      LENGTH = 80

      def self.dom_id(block) = "#{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-tile-summary"

      def initialize(block:, locale:, invalid: false)
        @block = block
        @locale = locale
        @invalid = invalid
      end

      def dom_id = self.class.dom_id(block)

      def line = [ content, (t(".needs_fixing") if invalid) ].compact_blank.join(" · ")

      def attention? = invalid || definition.nil? || missing_image?

      # The image's thumbnail (`Media::Asset#thumbnail_url`, the rule of the
      # Media grid and the image field), for a type that uses one and has it.
      def thumbnail_url = (asset.thumbnail_url if uses?("image") && asset)

      private

      attr_reader :block, :locale, :invalid

      def definition = block.definition

      def asset = block.media_asset

      def uses?(column) = definition&.uses_columns&.include?(column) || false

      def missing_image? = uses?("image") && asset.nil?

      def content
        if definition.nil? then t(".unavailable", type: block.block_type)
        elsif uses?("image") then asset ? asset.file.filename.to_s : t(".no_image")
        elsif uses?("body") then block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(LENGTH).presence || t(".empty_text")
        elsif definition.capability?(:lists_posts) then listing
        end
      end

      # A listing's filter: the content type it lists (or "All posts"), then
      # its tag. A content type that is no longer registered reads as its
      # stored name, as the block card's own field shows it.
      def listing
        settings = block.settings_object(locale: locale)
        type = settings&.content_type.presence
        tag = settings&.tag.presence

        [ type ? (::ContentTypes.find(type)&.label || type) : t(".any_type"), (t(".tag", name: tag) if tag) ].compact.join(" · ")
      end
    end
  end
end
