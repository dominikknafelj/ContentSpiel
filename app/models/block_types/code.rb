module BlockTypes
  # Source code with a language, an optional file name and a caption (code
  # block spec §1). The three settings are the same in every language of the
  # site and live in `settings`; the caption is the block's existing
  # translated `caption` column, its only translated field, and optional, so
  # a Code block never makes its page "missing" in a language.
  #
  # Nothing is required: the block picker makes an empty block first, as it
  # does for an image, and the public component draws nothing until there is
  # code. The languages, the limit and the colouring are `CodeHighlight`'s.
  #
  # Everything else the type brings it declares here (block types spec,
  # decision 1): its line in the theme contract, its seven syntax tokens, its
  # stylesheet, its tile's line, the one action of its editor that survives
  # in a held form and its sample. `:code` is no longer a capability: its one
  # reader was the tile's branch, and the tile asks the type's `summary` now
  # (decision 9).
  module Code
    # The first line of code is cut at the length the tile cuts every line at.
    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH

    def self.register
      BlockTypes.register :code do |t|
        t.label "Code"
        t.icon "code_xml"
        t.field :language, :select, options: CodeHighlight::LANGUAGES, blank: "Plain text"
        t.field :filename, :string, label: "File name"
        t.field :code, :code, max: CodeHighlight::MAX_CHARACTERS
        t.uses :caption
        t.component Blocks::CodeComponent
        # `lines` is one array per line of [role, text] pairs, the role nil or
        # one of the seven a `syn-` token exists for; `string(key)` is one of
        # the copy button's four words (:copy, :copy_code, :copied, :failed) in
        # the visitor's language, and of nothing else. When the bar around the
        # copy button is the script's to show, and the id of the file name's
        # element, are a template's own layout and no method: the default
        # template writes both out from these names. The markup the copy script
        # asks of any template is in docs/reference/theming.md, "The Code block".
        t.theme_methods :block, :page, :lines, :code, :language, :language_label, :filename, :caption, :string
        # One per role of `CodeHighlight::ROLES` and in its order
        # (`test/values/theme/contract_test.rb` holds the two together).
        t.tokens themed: %w[syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed]
        t.stylesheet "code.css"
        t.summary ->(block, locale:) { Code.summary(block, locale: locale) }
        # The counter under the code field reads the field and writes nothing
        # but its own line.
        t.read_only_actions "admin--editor--code-limit#update"
        # The values of the hand-written rows this sample replaced (block
        # types review I2): the scaffold's markup-looking ERB, compared byte
        # for byte and coloured as ERB (`syn-embed`), with its caption in
        # English, and the canary's captions in German and Spanish.
        t.sample settings: { "language" => "erb", "filename" => "show.html.erb", "code" => "<p class=\"a\"><%= 1 %></p>\n<%# note %>" },
                 translations: { "en" => { caption: "A template" }, "de" => { caption: "Code caption de" }, "es" => { caption: "Code caption es" } },
                 shows: [ "show.html.erb", %(<span class="syn-embed">), "A template" ]
      end
    end

    # The tile's line of a closed Code block, as parts (block types spec,
    # decision 8; design answer C7): its file name if it has one; otherwise
    # its language as an editor reads it and the first line of its code,
    # without the indentation it starts with, in the monospace face, or that
    # line alone for plain text. A block with no file name and no code says
    # "Empty" in the meta colour, whatever language is chosen, and is not
    # marked: an empty block is the state the picker leaves it in.
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      name = settings&.filename.presence
      return [ [ :text, name ] ] if name

      first = settings&.code.to_s.lines.first.to_s.strip.truncate(SUMMARY_LENGTH).presence
      return [ [ :hint, :empty ] ] unless first

      language = CodeHighlight.label(settings&.language)
      [ ([ :text, "#{language} · " ] if language), [ :mono, first ] ].compact
    end
  end
end
