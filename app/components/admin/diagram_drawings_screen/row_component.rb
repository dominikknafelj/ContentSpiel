module Admin
  module DiagramDrawingsScreen
    # One diagram in one language on the Draw diagrams list (`row:`, a
    # `Diagrams::ToDraw::Row`; the Design System's StudioDrawDiagrams): its
    # state as a chip, the block's description in that language (or, with
    # none, the source's opening line in mono), the language's name (only
    # beside other languages, `language_column:`) and the verb "Open". The
    # source's line is its opening line (`Diagrams::Source.opening_line`:
    # blank lines, a BOM and `%%` comments before the keyword skipped), as a
    # loader or a script may write them.
    #
    # THE ONE LINK. The text is the row's link (`.admin-row-link`, stretched
    # over the row) to the block's tile in its page's editor, in the row's
    # language, named by the text, the language and the state (by id, so the
    # name follows a state the script writes into the chip's slot) and
    # described by the verb, which is drawn for the eye alone.
    #
    # WHAT THE SCRIPT READS. The `<li>` is the run's `row` target with the
    # save's address (`data-url`), the language (`data-locale`) and the base
    # (`data-base`, the block's `updated_at` as the block card's form writes
    # it, `BlockCardComponent#base_updated_at_value`). The source is the text
    # of a `<template>` child, escaped as text, so no attribute and nothing
    # the page could run ever holds it. The script writes a run's state into
    # the chip's slot (`data-part="state"`) from the list's chip templates,
    # and a reason into the line drawn hidden and empty under the text
    # (`data-part="reason"`, dim; `data-tone="danger"` for "Doesn't draw"),
    # and marks the row in hand `aria-busy`, which tints it.
    #
    # The server draws only the query's two states, both warn.
    class RowComponent < Admin::AdminComponent
      CONTROLLER = "admin--diagram--draw-all".freeze

      # The narrow grid (the chip and the verb on the first line, the text
      # under them, the language under that) and, from 640px, the card's
      # four columns, or three on a site with one language.
      ROW_CLASS = "admin-draw-row grid grid-cols-[minmax(0,1fr)_auto] items-start gap-x-3 gap-y-1 border-t border-line px-4 py-2.5 " \
                  "hover:bg-paper aria-busy:bg-accent-tint sm:gap-y-0".freeze
      COLUMNS = { true => "sm:grid-cols-[136px_minmax(0,1fr)_84px_48px]", false => "sm:grid-cols-[136px_minmax(0,1fr)_48px]" }.freeze
      VERB_COLUMN = { true => "sm:col-start-4", false => "sm:col-start-3" }.freeze

      def initialize(row:, language_column:)
        @row = row
        @language_column = language_column
      end

      attr_reader :row

      def language_column? = @language_column

      def block = row.block

      def row_class = "#{ROW_CLASS} #{COLUMNS.fetch(language_column?)}"

      def verb_column = VERB_COLUMN.fetch(language_column?)

      def dom_id = "draw-#{block.id}-#{row.locale}"

      def text_id = "#{dom_id}-text"

      def language_id = "#{dom_id}-language"

      def state_id = "#{dom_id}-state"

      def verb_id = "#{dom_id}-verb"

      def labelled_by = [ text_id, (language_id if language_column?), state_id ].compact.join(" ")

      def description = block.translated_settings.to_h.dig(row.locale, "description").presence

      def text = description || ::Diagrams::Source.opening_line(row.source).to_s

      def text_class = description ? "truncate text-sm font-medium text-ink" : "truncate font-cs-mono text-small text-ink"

      def language_name = ::Locales.name(row.locale)

      def state_chip = Admin::Ui::StateChipComponent.new(tone: :warn, label: t(".states.#{row.state}"))

      # The block's tile in its page's editor, in the row's language.
      def editor_path
        locale = row.locale == ::Locales.default ? nil : row.locale
        helpers.admin_page_path(row.page, locale: locale, anchor: ActionView::RecordIdentifier.dom_id(block))
      end

      def row_data
        { draw_row: "", "#{CONTROLLER}-target": "row", url: helpers.admin_diagram_drawing_path(block), locale: row.locale,
          base: block.updated_at.iso8601(6), block_id: block.id }
      end
    end
  end
end
