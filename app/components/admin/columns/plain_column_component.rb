module Admin
  module Columns
    # A plain string/text input for a translated jsonb column --
    # `Page#subtitle/meta_title/meta_description`, `Post#excerpt`,
    # `ContentBlock#caption`/`alt` -- as opposed to a rich-text `body` column
    # (`RichTextColumnComponent`) or the schema-declared, `ContentModel`-
    # backed fields `Admin::Ui::FieldComponent` renders. `multiline:` picks a
    # `<textarea>` over a single-line `<input>` for the longer ones (an
    # excerpt, a meta description) without needing a whole separate
    # component per column.
    #
    # Two opt-in extras:
    #
    # * `counter:` is a soft recommended length (a meta title's 60, a meta
    #   description's 160). The field gets "42 / 60" beneath it
    #   (`admin--ui--char-count`) and, past the limit, "70 / 60 · long" in the
    #   warning colour -- never a validation, the field still saves.
    # * `override:` names what the field overrides ("alt text", "caption"): it
    #   is a per-use override of a Media library text whose own value is the
    #   input's placeholder, and gets the shared help line, **Reset** and
    #   library text (`admin/shared/_override_field`).
    #
    # `field_name:` is the wrapper's `data-field-name` when it is not `name`:
    # Settings keeps a title per language in one form (`title.de`), so the
    # save bar marks and names each language's field on its own, while `name`
    # stays the column the translation pieces work on. `field_changed:` is
    # the wrapper's `data-save-bar-changed` the server writes ("saved", after
    # a refused save), nil for none.
    class PlainColumnComponent < Base
      def initialize(name:, value:, original: nil, errors: [], locale: nil, multiline: false, id: nil, html_name: nil,
        translation_state: nil, translation_confirm: nil, translation_record: nil, counter: nil, override: nil, label: nil,
        field_name: nil, field_changed: nil, **html)
        super(name: name, value: value, original: original, errors: errors, locale: locale, id: id, html_name: html_name,
          translation_state: translation_state, translation_confirm: translation_confirm, translation_record: translation_record, **html)
        @multiline = multiline
        @label = label
        @counter = counter
        @override = override
        @field_name = field_name
        @field_changed = field_changed
      end

      # The wrapper's attributes for the save bar (see `field_name:`).
      def field_data = { field_name: @field_name || name, save_bar_changed: @field_changed }.compact

      # The label's text; the field's humanized name unless the caller says
      # otherwise (Settings' "Title · translatable").
      def label_text = (@label || name.to_s.humanize)

      def counter? = counter.present?

      def counter_id = "#{id}-count"

      # The field is described by its counter (read when the field is entered,
      # with the current count) rather than the counter being a live region
      # rewritten on every keystroke; only crossing the limit is announced
      # (`admin--ui--char-count`'s announcement target). The error slot keeps its
      # own id in the same list.
      def invalid_attrs
        ids = [ (counter_id if counter?), (errors_id if errors.any?) ].compact
        attrs = errors.any? ? { aria: { invalid: "true" } } : {}
        attrs[:aria] = (attrs[:aria] || {}).merge(describedby: ids.join(" ")) if ids.any?
        attrs
      end

      def override? = override.present?

      # "42 / 60", as first painted; `admin--ui--char-count` keeps it current (and
      # adds " · long") from the input's own value.
      def counter_text = "#{counter_length} / #{counter}#{" · long" if counter_long?}"

      def counter_long? = counter? && counter_length > counter

      def counter_length = value.to_s.each_char.count

      # The input's own attributes: the caller's, plus -- with a counter -- the
      # `admin--ui--char-count` target and the action that recounts on typing.
      def input_html
        return html unless counter?

        data = (html[:data] || {}).merge("admin--ui--char-count-target": "input", action: [ html.dig(:data, :action), "input->admin--ui--char-count#update" ].compact.join(" "))
        html.merge(data: data)
      end

      # What the field overrides' value is when rendered (the partial's `overridden`).
      def overridden? = value.present?

      private

      attr_reader :multiline, :counter, :override
    end
  end
end
