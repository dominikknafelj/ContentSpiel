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
    #
    # Two opt-in extras (design pass round 2, Task 10):
    #
    # * `counter:` is a soft recommended length (a meta title's 60, a meta
    #   description's 160). The field gets "42 / 60" beneath it
    #   (`admin--char-count`) and, past the limit, "70 / 60 · long" in the
    #   warning colour -- never a validation, the field still saves.
    # * `override:` names what the field overrides ("alt text", "caption"): it
    #   is a per-use override of a Media library text whose own value is the
    #   input's placeholder, and gets the shared help line, **Reset** and
    #   library text (`admin/shared/_override_field`).
    class PlainColumnComponent < Base
      def initialize(name:, value:, original: nil, errors: [], locale: nil, multiline: false, id: nil, html_name: nil,
        translation_state: nil, translation_confirm: nil, translation_record: nil, counter: nil, override: nil, **html)
        super(name: name, value: value, original: original, errors: errors, locale: locale, id: id, html_name: html_name,
          translation_state: translation_state, translation_confirm: translation_confirm, translation_record: translation_record, **html)
        @multiline = multiline
        @counter = counter
        @override = override
      end

      def counter? = counter.present?

      def override? = override.present?

      # "42 / 60", as first painted; `admin--char-count` keeps it current (and
      # adds " · long") from the input's own value.
      def counter_text = "#{value.to_s.each_char.count} / #{counter}#{" · long" if value.to_s.each_char.count > counter}"

      def counter_long? = counter? && value.to_s.each_char.count > counter

      # The input's own attributes: the caller's, plus -- with a counter -- the
      # `admin--char-count` target and the action that recounts on typing.
      def input_html
        return html unless counter?

        data = (html[:data] || {}).merge("admin--char-count-target": "input", action: [ html.dig(:data, :action), "input->admin--char-count#update" ].compact.join(" "))
        html.merge(data: data)
      end

      # What the field overrides' value is when rendered (the partial's `overridden`).
      def overridden? = value.present?

      private

      attr_reader :multiline, :counter, :override
    end
  end
end
