module Admin
  module Columns
    # A plain string/text input for a translated jsonb column (spec §4.3) --
    # `Page#subtitle/meta_title/meta_description`, `Post#excerpt`,
    # `ContentBlock#caption`/`alt` -- as opposed to a rich-text `body` column
    # (`RichTextColumnComponent`) or the schema-declared, `ContentModel`-
    # backed fields `Admin::FieldComponent` renders. `multiline:` picks a
    # `<textarea>` over a single-line `<input>` for the longer ones (an
    # excerpt, a meta description) without needing a whole separate
    # component per column.
    class PlainColumnComponent < Base
      def initialize(name:, value:, original: nil, errors: [], locale: nil, multiline: false, id: nil, html_name: nil,
        translation_state: nil, translation_confirm: nil, **html)
        super(name: name, value: value, original: original, errors: errors, locale: locale, id: id, html_name: html_name,
          translation_state: translation_state, translation_confirm: translation_confirm, **html)
        @multiline = multiline
      end

      private

      attr_reader :multiline
    end
  end
end
