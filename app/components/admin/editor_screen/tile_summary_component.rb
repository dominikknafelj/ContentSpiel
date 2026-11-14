module Admin
  module EditorScreen
    # What a closed block's tile says of its content (sections spec §4.2):
    # the type's preview, a heading over a few lines of its text, or, for a
    # type with no preview or a blank one, one line: the start of a text,
    # an image's file name with a small thumbnail, or the line a type with a
    # `summary` answers itself (a post list's filter, an empty Code block's
    # "Empty").
    # A block in a section's column is a tile until it is opened, so this
    # is all that says which block it is -- and what marks the ones that
    # need attention, as a card would: an image block without an image (see
    # `#missing_image?`), a type that is no longer registered, a save that
    # was refused as invalid (`invalid:`).
    #
    # THE PREVIEW (`#preview`, a `ContentModel::Preview` the type's
    # `preview` answers) is plain text, cut by the Preview itself: the
    # heading is one line (`truncate`), the text at most three
    # (`line-clamp-3`), in the mono face when it is code (`mono`). Both are
    # ERB-escaped where they are drawn, never `raw`: they are what a person
    # typed. A preview with nothing in it is not drawn, so an empty block
    # keeps its line ("Empty text") and never shows an empty heading.
    #
    # WHAT THE LINE IS comes from the type's definition, never from its name:
    # the columns it uses (`uses_columns`) or its own `summary`, so a type a
    # plugin registers gets a sensible tile without being known here. A type
    # that uses an image AND a body is summarised by its image, the first rule
    # that matches. A type with neither and no summary has no
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
    # A TYPE WITH A PICTURE (`tile_picture`, the Diagram block's drawing)
    # has a layout of its own: the picture small in a 112×72 box, hidden from
    # a screen reader, and beside it the summary line, its hints with it,
    # over the preview's heading as the words that describe the tile. The
    # preview's text is drawn only when there is no picture, which stands
    # for it. The picture is markup the type wrote (built-ins alone declare
    # one: `BlockTypeDefinition#refuse_outside!`), printed as it is handed;
    # an answer that is not an `ActiveSupport::SafeBuffer` raises. The box
    # scales it to fit, its aspect kept (`.admin-block-tile__picture` in
    # `content-spiel.tailwind.css`), and never moves the tile.
    #
    # THE TILE IS THE ONLY PLACE a closed block shows its content. A
    # card of the page's own list that is collapsed
    # (`admin--editor--blocks#toggle`) shows its type's label and nothing
    # else, for every type.
    #
    # It is its own component with its own id because it is the one part of
    # a tile that a save changes: `Admin::Answers::BlockDrawing#tile_summary_stream`
    # replaces it (`dom_id`) with every answer for a block in a section, so
    # the preview follows a save. The tile around it -- the button that
    # holds the focus and `aria-expanded` -- is never re-rendered by a save.
    #
    # `invalid:` is only ever true in such an answer. A block's stored state
    # is always valid, so a tile drawn with the page has nothing to say here.
    class TileSummaryComponent < AdminComponent
      LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH
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

      # One render asks the type for its line, its preview and its picture;
      # a type whose three share a costly read keeps it for this render alone
      # (`ContentModel::TileReads`).
      def render_in(...) = ContentModel::TileReads.during { super }

      # The parts of the summary the tile's face is named and described by
      # (`BlockTileComponent`), in the order the name reads them: the
      # attention mark, the preview's heading (or the one line), then
      # "Needs fixing"; the description is the preview's text. The ids are
      # fixed for the block, because a save replaces this component and never
      # the face that points at them, and a part that is not drawn is an id
      # that names nothing, which a name or a description skips.
      def self.part_ids(block) = %w[attention name status].map { |part| "#{dom_id(block)}-#{part}" }
      def self.text_id(block) = "#{dom_id(block)}-text"

      def attention_id = self.class.part_ids(block)[0]
      def name_id = self.class.part_ids(block)[1]
      def status_id = self.class.part_ids(block)[2]
      def text_id = self.class.text_id(block)

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

      # The type's preview, or nil: for a type with none, one with nothing
      # in it, and an outside type whose `preview` raised or answered
      # something that is not a Preview (see `#own_preview`).
      def preview
        return @preview if defined?(@preview)

        @preview = (own_preview if definition&.preview)
      end

      # The preview's text, in the mono face when it is code: the one mono
      # the tile draws besides a summary's `:mono` part (`MONO_ALLOWED` names
      # this file). `whitespace-pre-wrap` keeps code's lines and indents.
      def preview_text_class
        [ "admin-block-tile__text line-clamp-3 text-sm text-dim", ("font-cs-mono whitespace-pre-wrap" if preview.mono) ].compact.join(" ")
      end

      # Whether the type draws a picture on its tile, and so the picture's
      # layout, whether or not this block has one to draw.
      def pictured? = definition&.tile_picture.present?

      # The type's picture of the block, or nil.
      def picture
        return @picture if defined?(@picture)

        @picture = (own_picture if pictured?)
      end

      # The preview's words in the picture's layout: its heading, and its
      # text only when there is no picture.
      def picture_heading = preview&.heading
      def picture_text = (preview&.text unless picture)

      # "Needs fixing" under a preview: a refused save's word, alone.
      def needs_fixing = t(".needs_fixing")

      # The image drawn small (`Admin::Ui::LibraryImageComponent`: a width, the
      # preview or a box, as the Media grid draws it), for a type that uses one
      # and has it.
      def thumbnail_asset = (asset if uses?("image"))

      private

      attr_reader :block, :locale, :invalid

      def definition = block.definition

      def asset = block.media_asset

      def uses?(column) = definition&.uses_columns&.include?(column) || false

      # The mark is for a block that is nothing without its image. A type with
      # a `summary` of its own has more than an image to say (a Card's image is
      # optional, and a card without one is as finished as any), and says what
      # it lacks on its own line; without this every card with no picture
      # would read as needing attention the day the type began to use one.
      def missing_image? = uses?("image") && asset.nil? && definition.summary.nil?

      def content
        if definition.nil? then t(".unavailable", type: block.block_type)
        elsif definition.summary then own_summary
        elsif uses?("image") then asset ? asset.file.filename.to_s : t(".no_image")
        elsif uses?("body") then block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(LENGTH).presence || t(".empty_text")
        end
      end

      def own_picture
        answer = definition.tile_picture.call(block, locale: locale)
        raise ArgumentError, "#{block.block_type}'s tile_picture answered a #{answer.class}: a picture is an ActiveSupport::SafeBuffer or nil" unless answer.nil? || answer.is_a?(ActiveSupport::SafeBuffer)

        answer.presence
      end

      # The definitions whose faulty summary has been logged, so a page of
      # twenty such tiles says it once (per registration: a reload makes new
      # definitions, and says it again). A faulty preview is kept apart, so a
      # type with both faults says each once.
      FAULTY = ObjectSpace::WeakMap.new
      FAULTY_PREVIEW = ObjectSpace::WeakMap.new

      # A type's own preview. As with `own_summary`, an OUTSIDE type's is a
      # gem's code: one that raises, or answers something that is not a
      # Preview, would be a 500 on every editor page holding a block of the
      # type, so its tile draws the summary line instead, and the log and
      # `Rails.error` hear it once, naming the type and the error's class and
      # never its message in the log line. A built-in's raises.
      def own_preview
        answer = definition.preview.call(block, locale: locale)
        raise ArgumentError, "#{block.block_type}'s preview answered a #{answer.class}: a preview is a ContentModel::Preview or nil" unless answer.nil? || answer.is_a?(ContentModel::Preview)

        answer.presence
      rescue StandardError => error
        raise unless definition.owner

        unless FAULTY_PREVIEW.key?(definition)
          FAULTY_PREVIEW[definition] = true
          said = "[ContentSpiel] the block type #{definition.name}'s preview could not be drawn (#{error.class}); its tiles show the summary line" # i18n-ok: a log line for whoever runs the site, not a word of CS Studio
          Rails.logger.error(said)
          Rails.error.report(error, handled: true, context: { block_type: definition.name })
        end
        nil
      end

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
    end
  end
end
