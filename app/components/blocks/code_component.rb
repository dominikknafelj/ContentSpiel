module Blocks
  # Source code, coloured on the server (`BlockTypes::Code`, code block spec
  # §4). Built like `Blocks::ImageComponent`: it reads the block it is handed
  # -- a published view on the site, the rows in a preview -- and nothing
  # else.
  #
  # THE CODE IS TEXT. The template prints each token's text through ERB's
  # own escaping and wraps a coloured one in a span whose class is one of
  # `CodeHighlight::ROLES`. Nothing here, in the template or in
  # `CodeHighlight` marks a string as safe, and the highlighter's own markup
  # output is not used, so the code can add no element, no attribute and no
  # class to the page (`test/components/blocks/code_component_test.rb`).
  # The file name and the caption are escaped text too.
  #
  # The head is always drawn, since it holds the Copy button; the button is
  # `hidden` in the markup and `code-copy` shows it where there is a
  # clipboard, so without JavaScript the code is all there and only the
  # button is missing.
  class CodeComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = code.present?

    private

    attr_reader :block, :page

    # The three settings are untranslated: one value for every language.
    def settings = @settings ||= block.settings_object

    def code = settings&.code

    # The language's tag as stored, or nil. A tag that is no longer on the
    # list has no label and is drawn plain.
    def language = settings&.language

    def language_label = CodeHighlight.label(language)

    def filename = settings&.filename

    # One array per line of [role, text] pairs; the role is nil for plain text.
    def lines = CodeHighlight.lines(code, language, block_id: block.id)

    # The block's one translated field, in the visitor's language with fallback.
    def caption = translated(block, :caption)

    def file_id = "code-#{block.id}-file"

    # One of the block's four public strings, in the visitor's language where
    # `config/locales/public.<locale>.yml` has it, in English otherwise.
    def string(key)
      full = "public.blocks.code.#{key}"
      I18n.t(full, locale: I18n.exists?(full, I18n.locale) ? I18n.locale : :en)
    end
  end
end
