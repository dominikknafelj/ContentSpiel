module Admin
  module EditorScreen
    # A section's settings said as words in its head (E4 decision 9): "3
    # columns ▾ No background ▾ Content width ▾", then the style's name when
    # the theme offers styles and one other than the default is chosen, and
    # "#about" when an anchor is set. Each word is a button that opens the
    # section's settings (`SectionCardComponent.settings_id`) focused on its
    # own setting (`admin--editor--section#openSettings`, its `field` param).
    #
    # The words say what is STORED, not what the form holds: a save's answer
    # replaces this element by its id
    # (`Admin::Answers::BlockDrawing#section_save_streams`), and the card
    # draws it through the same door, `SectionCardComponent.words`, so the
    # words a stream brings are the words a page load draws. The settings
    # region itself is never replaced: it is a form that may hold text.
    #
    # Every word says the region is closed. A page load draws it closed, and
    # a stream that lands while it is open is set right by
    # `admin--editor--section#wordsTargetConnected`, which reads the region.
    #
    # A viewer who can't edit gets the same buttons: reading a setting changes
    # nothing, and the region shows them the disabled fieldset, as a tile
    # shows them a block's disabled form.
    class SectionSettingsWordsComponent < AdminComponent
      FIELDS = %w[layout background width style anchor].freeze

      def initialize(section:)
        @section = section
      end

      def call
        tag.span(id: Admin::EditorScreen::SectionCardComponent.words_id(section), class: "flex min-w-0 flex-1 flex-wrap items-center gap-1",
          data: { "admin--editor--section-target": "words", action: "focusin->admin--editor--section#wordFocused focusout->admin--editor--section#wordLeft" }) do
          safe_join(words.map { |field, word| button(field, word) })
        end
      end

      # `[setting, word]`, in the order the head says them.
      def words
        [ [ "layout", t(".columns", count: section.column_count) ],
          [ "background", t(".backgrounds.#{known(setting("background"), BlockTypes::Section::BACKGROUNDS)}") ],
          [ "width", t(".widths.#{known(setting("width"), BlockTypes::Section::WIDTHS)}") ],
          ([ "style", style_choice.label_for(I18n.locale) ] if style_choice),
          ([ "anchor", t(".anchor", anchor: setting("anchor")) ] if setting("anchor").present?) ].compact
      end

      private

      attr_reader :section

      def button(field, word)
        tag.button(type: "button", class: "admin-section-word", aria: { controls: Admin::EditorScreen::SectionCardComponent.settings_id(section), expanded: "false", label: t(".label", word: word) },
          data: { action: "admin--editor--section#openSettings", "admin--editor--section-field-param": field }) do
          safe_join([ word, tag.span("▾", aria: { hidden: true }) ], " ")
        end
      end

      # A setting as the type reads it: its schema's default where the
      # section stores none.
      def setting(name) = section.settings_object(locale: ::Locales.default)&.public_send(name).to_s

      # A stored value this code no longer knows reads as the type's first,
      # its default: the public page draws it so.
      def known(value, values) = values.include?(value) ? value : values.first

      # The theme's style the section has, nil for the default (blank) and for
      # a name the theme does not declare, which is drawn as the default.
      def style_choice = @style_choice ||= setting("style").presence && ::Theme.current.choice(:section_styles, setting("style"))
    end
  end
end
