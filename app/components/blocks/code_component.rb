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
  # THE HEAD STRIP is drawn only when it has something to show (design
  # answer C1): a file name or a language. With neither the strip is
  # in the markup `hidden`, holding nothing but the Copy button, and it is
  # the script's `strip` target: `code-copy` shows it together with the
  # button where there is a clipboard. So a page without JavaScript, or
  # without a clipboard, shows the code alone and never an empty box, and
  # the server never draws an empty strip that is seen. With a file name or
  # a language the strip is drawn as it is and only the button is `hidden`
  # until the script shows it. THE TEMPLATE says so itself, from `filename`
  # and `language_label`, and makes the file name's id from `block`: that is
  # its layout and no method here, because every method the template calls
  # is one `Theme::Contract` promises a theme's own template
  # (`test/values/theme/contract_test.rb`), and a theme's bar is not this
  # one (docs/reference/theming.md, "The Code block").
  class CodeComponent < ApplicationComponent
    # The block's public strings, the keys of `public.blocks.code`
    # (`config/locales/public.en.yml`): what `string` answers, and nothing
    # else.
    STRINGS = %i[copy copy_code copied failed].freeze

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = code.present?

    # Whether this is the first time the process meets `key`, which is what
    # keeps an unknown key in a theme's template to one log line and not
    # one per visitor.
    UNKNOWN_STRINGS_LOCK = Mutex.new

    def self.first_unknown_string?(key)
      UNKNOWN_STRINGS_LOCK.synchronize { (@unknown_strings ||= Set.new).add?(key).present? }
    end

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
    # Remembered: a template may ask twice (a count, then the lines).
    def lines = @lines ||= CodeHighlight.lines(code, language, block_id: block.id)

    # The block's one translated field, in the visitor's language with fallback.
    def caption = translated(block, :caption)

    # One of the block's four public strings (the button's word is handed to the
    # script as well, as its `label` value, so the script never reads it back from
    # the page), in the visitor's language where
    # `config/locales/public.<locale>.yml` has it, in English otherwise.
    #
    # ONLY THOSE FOUR. A theme's template calls this with a key its author
    # typed, and I18n's answer for a key that does not exist is a sentence
    # ("Translation missing: en.public.blocks.code.copy_all") that would be
    # the button's word on a public page. Where a theme is written
    # (development, test) another key raises and names the four; in
    # production it is no word, and one line in the log per key for the
    # life of the process.
    def string(key)
      return unknown_string(key) unless STRINGS.include?(key.to_s.to_sym)

      PublicStrings.read("public.blocks.code.#{key}")
    end

    def unknown_string(key)
      message = "Blocks::CodeComponent#string has no #{key.to_s.to_sym.inspect}: the Code block's words are #{STRINGS.map(&:inspect).join(", ")}"
      raise ArgumentError, message if Rails.env.local?

      Rails.logger.warn(message) if self.class.first_unknown_string?(key.to_s)
      ""
    end
  end
end
