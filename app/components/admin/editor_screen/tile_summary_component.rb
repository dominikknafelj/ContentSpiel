module Admin
  module EditorScreen
    # One line of a block's content on its tile (sections spec §4.2): the
    # start of a text, an image's file name with a small thumbnail, a post
    # list's filter, or the line a type with a `summary` answers itself (the
    # Code block's file name, or its language and first line).
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
    # that matches. A type with neither, no summary and no listing has no
    # line at all; its tile is its label.
    #
    # A type that declares `summary` answers its own line as parts (block
    # types spec, decision 8) and that is drawn first; a type without one
    # keeps the rules above, from the columns it uses.
    #
    # THE LINE IS PARTS (`parts`: text and, where it has a look of its own,
    # a class), because a code block's is two (design answer C7): its
    # language in the tile's own face and its first line of code in the
    # monospace one, and an empty one says "Empty" in `text-meta`. Every
    # other line is one part. The whole line is cut off by the stylesheet
    # (`truncate` on the element around the parts), after the count that
    # every tile's text is cut at (`LENGTH`).
    #
    # THE TILE IS THE ONLY PLACE a closed block has a line of its content. A
    # card of the page's own list that is collapsed
    # (`admin--editor--blocks#toggle`) shows its type's label and nothing
    # else, for every type, so the Code block's line (design answer C7,
    # "tile and collapsed card") is here and not on the card.
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

      # A summary part's kind => the class it is drawn in (nil: plain). The
      # set is closed; a type's summary answers nothing else (block types
      # spec, decision 8; `:hint` is the meta colour the Code block's "Empty"
      # was drawn in before the line moved into the type).
      LOOKS = { text: nil, word: nil, mono: "font-cs-mono", hint: "text-meta" }.freeze

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
        elsif definition.summary then own_summary
        elsif uses?("image") then asset ? asset.file.filename.to_s : t(".no_image")
        elsif uses?("body") then block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(LENGTH).presence || t(".empty_text")
        elsif definition.capability?(:lists_posts) then listing
        end
      end

      # The definitions whose faulty summary has been logged, so a page of
      # twenty such tiles says it once (per registration: a reload makes new
      # definitions, and says it again).
      FAULTY = ObjectSpace::WeakMap.new

      # A type's own line. An OUTSIDE type's summary is a gem's code: one that
      # raises, or answers a part of no known kind, was a 500 on every editor
      # page holding a block of the type, so its tile shows the type's label
      # instead and the log says it once, naming the type and the error's
      # class and never its message, which can quote the block's content. A
      # built-in's is the CMS's own and raises, in the tests first.
      def own_summary
        drawn(definition.summary.call(block, locale: locale))
      rescue StandardError => error
        raise unless definition.owner

        unless FAULTY.key?(definition)
          FAULTY[definition] = true
          said = "[ContentSpiel] the block type #{definition.name}'s summary could not be drawn (#{error.class}); its tiles show the type's label" # i18n-ok: a log line for whoever runs the site, not a word of CS Studio
          Rails.logger.error(said)
        end
        definition.label
      end

      # A type's parts as `[text, class]`, its words looked up under the
      # type's own scope, and parts of one look joined, so the markup is what
      # the tile drew when it wrote the line itself.
      def drawn(parts)
        Array(parts).map do |kind, value, values = {}|
          raise ArgumentError, "#{block.block_type}'s summary answered a part of kind #{kind.inspect}: a part is one of #{LOOKS.keys.join(", ")}" unless LOOKS.key?(kind)

          look = LOOKS.fetch(kind)
          [ %i[word hint].include?(kind) ? word(value, **values) : value.to_s, look ]
        end.slice_when { |a, b| a.last != b.last }.map { |run| [ run.map(&:first).join, run.first.last ] }
      end

      def word(key, **values)
        t("admin.components.editor_screen.tile_summary.types.#{block.block_type.tr("/", ".")}.#{key}", **values)
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
