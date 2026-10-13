module Admin
  module EditorScreen
    # One line of a block's content on its tile (sections spec §4.2): the
    # start of a text, an image's file name with a small thumbnail, a code
    # block's file name or its language and first line, a post list's filter.
    # A block in a section's column is a tile until it is opened, so this
    # line is all that says which block it is -- and what marks the ones that
    # need attention, as a card would: an image block without an image, a
    # type that is no longer registered, a save that was refused as invalid
    # (`invalid:`).
    #
    # WHAT THE LINE IS comes from the type's definition, never from its name:
    # the columns it uses (`uses_columns`) and its capabilities, so a type a
    # plugin registers gets a sensible tile without being known here. A type
    # that uses an image AND a body is summarised by its image, the first rule
    # that matches. A type with neither, no code and no listing has no line
    # at all; its tile is its label.
    #
    # THE LINE IS PARTS (`parts`: text and, where it has a look of its own,
    # a class), because a code block's is two (design answer C7): its
    # language in the tile's own face and its first line of code in the
    # monospace one, and an empty one says "Empty" in `text-meta`. Every
    # other line is one part. The whole line is cut off by the stylesheet
    # (`truncate` on the element around the parts), after the count that
    # every tile's text is cut at (`LENGTH`).
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
      SEPARATOR = " · ".freeze

      def self.dom_id(block) = "#{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-tile-summary"

      def initialize(block:, locale:, invalid: false)
        @block = block
        @locale = locale
        @invalid = invalid
      end

      def dom_id = self.class.dom_id(block)

      # The line as text, whatever its parts look like.
      def line = parts.map(&:first).join

      # `[text, class or nil]` in reading order; "Needs fixing" is the last.
      def parts
        found = content
        drawn = (found.is_a?(Array) ? found : [ [ found, nil ] ]).reject { |text, _| text.blank? }
        return drawn unless invalid

        drawn + [ [ [ (SEPARATOR if drawn.any?), t(".needs_fixing") ].join, nil ] ]
      end

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
        elsif definition.capability?(:code) then code_line
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

      # What tells one code block from another at a glance (design answer
      # C7): its file name if it has one; otherwise its language as an editor
      # reads it, " · ", and the first line of its code, or that line alone
      # for plain text. The line of code is in the monospace face, without
      # the indentation it starts with. A block with no file name and no
      # code says "Empty", whatever language is chosen for the code to come,
      # and is not marked: an empty block is the state the picker leaves it
      # in.
      def code_line
        settings = block.settings_object(locale: locale)
        name = settings&.filename.presence
        return name if name

        first = settings&.code.to_s.lines.first.to_s.strip.truncate(LENGTH).presence
        return [ [ t(".empty_code"), "text-meta" ] ] unless first

        language = ::CodeHighlight.label(settings&.language)
        [ ([ "#{language}#{SEPARATOR}", nil ] if language), [ first, "font-cs-mono" ] ].compact
      end
    end
  end
end
