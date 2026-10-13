module BlockTypes
  # Source code with a language, an optional file name and a caption (code
  # block spec §1). The three settings are the same in every language of the
  # site and live in `settings`; the caption is the block's existing
  # translated `caption` column, its only translated field, and optional, so
  # a Code block never makes its page "missing" in a language.
  #
  # Nothing is required: the block picker makes an empty block first, as it
  # does for an image, and the public component draws nothing until there is
  # code. `:code` is the capability the editor's tile asks, never the type's
  # name. The languages, the limit and the colouring are `CodeHighlight`'s.
  module Code
    def self.register
      BlockTypes.register :code do |t|
        t.label "Code"
        t.field :language, :select, options: CodeHighlight::LANGUAGES, blank: "Plain text"
        t.field :filename, :string
        t.field :code, :code, max: CodeHighlight::MAX_CHARACTERS
        t.uses :caption
        t.capability :code
        t.component Blocks::CodeComponent
      end
    end
  end
end
