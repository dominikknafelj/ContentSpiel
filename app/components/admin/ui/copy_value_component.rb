module Admin
  module Ui
    # A value a person copies exactly -- a token, an address, a command, a
    # client configuration -- in a sunken box beside a Copy button, on the
    # one copy script, `admin--ui--clipboard`.
    #
    # - THE VALUE IS THE BOX'S TEXT AND NOTHING ELSE. The script copies the
    #   `source` target's text, so the value is written once, ERB-escaped,
    #   and into no attribute: a token shown once must not stand a second
    #   time in a `data-*` value that outlives the blanking of its text (the
    #   reveal's `admin--tokens--reveal` blanks every `secret` target at
    #   `pagehide`; `source_data:` is how a caller makes the box one).
    # - `layout: :inline` is a one-line `code` (an address, a command), and
    #   `:block` a `pre` (a token, a configuration). A value longer than its
    #   box scrolls inside the box, never the page.
    # - The button is named for its value (`copy_label:`, "Copy token"), as
    #   every box on a screen reads "Copy". The result is said politely by an
    #   `sr-only` status and, for a moment, on the button: Copied, or, where
    #   the clipboard is missing or refuses (plain http off localhost), the
    #   value is selected and the status says to press the copy shortcut.
    # - Anything else the caller hands it (`class:`) goes on the box, a class
    #   added to its own.
    class CopyValueComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The value is selectable text; Copy is named for its value, and a polite status says Copied, or that the text was selected when the clipboard refused.",
        motion: :none,
        content_edges: %i[short long],
        widths: :from_container,
        interface: %i[id value copy_label layout source_data],
        limits: [
          "It copies the value's text and writes it into no attribute.",
          "A value too long for its box scrolls inside the box, never the page."
        ],
        states: %i[inline block],
        script_states: {
          copied: [ "test/system/admin/system_status_and_preview_test.rb", "Copy writes the command, says Copied, and announces it politely" ],
          selected: [ "test/system/admin/system_status_and_preview_test.rb", "without a Clipboard API the command is selected instead and nothing raises" ]
        },
        keys: %w[copy copied failed selected],
        slots: [],
        controller: "admin--ui--clipboard",
        keyboard: [ "test/system/admin/system_status_and_preview_test.rb", "Copy writes the command, says Copied, and announces it politely" ]
      )

      CLASS = "flex flex-wrap items-start gap-2".freeze
      LAYOUTS = %i[inline block].freeze
      # What the script says, read from the box's `data-messages` (and on
      # every screen from <body>'s, for the editor header's Copy).
      MESSAGES = %w[components.ui.copy_value.copied components.ui.copy_value.failed components.ui.copy_value.selected].freeze

      def initialize(id:, value:, copy_label:, layout: :inline, source_data: {}, **html)
        raise ArgumentError, "unknown copy box layout #{layout.inspect}" unless LAYOUTS.include?(layout)

        @id = id
        @value = value
        @copy_label = copy_label
        @layout = layout
        @source_data = source_data
        @html = html
      end

      private

      attr_reader :id, :value, :copy_label

      def inline? = @layout == :inline

      def source_attributes = { data: { "admin--ui--clipboard-target": "source" }.merge(@source_data) }

      def root_attributes
        @html.merge(class: [ CLASS, @html[:class] ].compact.join(" "),
          data: @html.fetch(:data, {}).merge(controller: "admin--ui--clipboard", messages: messages_data(*MESSAGES)))
      end
    end
  end
end
