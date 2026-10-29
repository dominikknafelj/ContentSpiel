module Admin
  module EditorScreen
    # What stands around a Table block's grid in its card (table block spec,
    # decisions 4, 5, 7 and 12, and "CS Studio"; Claude Design's B5 and its
    # 2026-10-27 follow-up): the options row ("Header row", "First column as
    # header"), the warning line, then the grid (this component's content,
    # the body's `RichTextColumnComponent` in table mode), the row's and the
    # column's "⋯" menus and "+" that follow the cell under the pointer or
    # the caret, and "Add row" under the grid. `admin--editor--table` does the
    # work, through the grid's own editor (`rich_text/editors`): every change
    # is an editor transaction, written into the body's hidden input and
    # autosaved like typing, so nothing here sends anything itself.
    #
    # ONLY FOR SOMEONE WHO MAY CHANGE THE TABLE NOW. A held card (someone else
    # holds the block) and a reader's card draw the grid alone, read-only
    # (decision 13): the block card does not render this component there, so
    # there is no switch, menu or "+" for `HeldFields` to disable and no
    # action of this controller to allow. A form that turns read-only in place
    # (`editing/freeze`) has its buttons disabled and every action of this
    # controller taken off, as every form's are.
    #
    # The two switches and the warning are drawn from what the grid SHOWS:
    # the stored table, or, for a Table that has none yet, the column's
    # starting content (`starting:`, the column's own `#starting_content`:
    # the starting grid, `TableBody.starting_document`, or on a translation
    # tab the copy of the original's table; shown, not written, until the
    # first change). The script draws them again after every change; the
    # server draws the first, so a card reads right before its script runs.
    #
    # The delete confirmations are `TableDeleteDialogsComponent`, which the
    # card draws OUTSIDE its form (a dialog's `<form method="dialog">` cannot
    # sit inside the block's form); the script finds them by id.
    class TableControlsComponent < AdminComponent
      # The starting grid a table body with no table yet is shown, or nil.
      def self.starting_content(document) = filled?(document) ? nil : TableBody.starting_document

      def self.filled?(document) = Array(document.to_h["content"]).any?

      # The floating controls: hidden until the script places them on the
      # edge of the current row or column, centred on it.
      FLOATING_CLASS = "absolute z-20 -translate-x-1/2 -translate-y-1/2".freeze
      # The "⋯" and the "+": small square buttons on the grid's edge, outlined
      # in the field line as everything pressable is. Their look beyond that is
      # an open design question (ledger ruling 8).
      HANDLE_CLASS = "inline-flex size-6 cursor-pointer items-center justify-center rounded-cs border border-field-line bg-surface text-sm leading-none text-meta hover:border-ink hover:text-ink".freeze
      MENU_ITEM_CLASS = BlockCardComponent::MENU_ITEM_CLASS

      # [key, action] of the row's and the column's menus, in their order.
      ROW_ITEMS = [ %w[insert_above insertRowAbove], %w[insert_below insertRowBelow], %w[move_up moveRowUp], %w[move_down moveRowDown] ].freeze
      COLUMN_ITEMS = [ %w[insert_left insertColumnLeft], %w[insert_right insertColumnRight], %w[move_left moveColumnLeft], %w[move_right moveColumnRight] ].freeze
      ALIGNS = TableBody::ALIGNS

      def initialize(block:, document:, starting: nil)
        @block = block
        @document = document
        @starting = starting
      end

      private

      attr_reader :block

      def shown = @shown ||= TableBody.new(self.class.filled?(@document) ? @document : (@starting || TableBody.starting_document))

      def header_row? = shown.header_row?

      def header_column? = shown.header_column?

      # The warning's sentences, in one alert: columns first, then rows.
      def warning = shown.warnings.map { |kind, count| t(".warning.#{kind}", count: count) }.join(" ")

      def id_prefix = "#{BlockCardComponent.error_prefix(block)}-table"

      def controller_data
        {
          controller: "admin--editor--table",
          action: [
            "admin--rich-text--editor:attached->admin--editor--table#attach",
            "admin--rich-text--editor:detached->admin--editor--table#detach",
            "mouseover->admin--editor--table#hover",
            "mouseenter->admin--editor--table#enter",
            "mouseleave->admin--editor--table#leave",
            "focusin->admin--editor--table#focusIn",
            "focusout->admin--editor--table#focusOut",
            "keydown->admin--editor--table#keydown",
            "resize@window->admin--editor--table#place"
          ].join(" "),
          "admin--editor--table-warn-columns-value": TableBody::WARN_COLUMNS,
          "admin--editor--table-warn-rows-value": TableBody::WARN_ROWS,
          "admin--editor--table-row-dialog-value": TableDeleteDialogsComponent.dialog_id(block, :row),
          "admin--editor--table-column-dialog-value": TableDeleteDialogsComponent.dialog_id(block, :column),
          "admin--editor--table-starting-grid-value": TableBody.starting_document.to_json
        }
      end

      def messages = messages_data("components.editor_screen.table_controls.warning.columns", "components.editor_screen.table_controls.warning.rows")

      def switch(target, checked)
        tag.input type: "checkbox", id: "#{id_prefix}-#{target.to_s.dasherize}", class: "cs-toggle", role: "switch", checked: checked,
          data: { "admin--editor--table-target": target.to_s.camelize(:lower), action: "change->admin--editor--table##{target.to_s.camelize(:lower)}" }
      end

      # A menu item; a delete's words are red, as "Delete block…" in the card's menu.
      def item(label, action, danger: false, **data)
        tag.button label, type: "button", class: [ MENU_ITEM_CLASS, ("text-danger-ink" if danger) ].compact.join(" "), data: { action: "admin--editor--table##{action}", **data }
      end

      def align_item(align)
        tag.button type: "button", class: "group #{MENU_ITEM_CLASS}", "aria-label": t(".column.aligns.#{align}.name"),
          data: { action: "admin--editor--table#align", "admin--editor--table-align-param": align, table_align: align } do
          safe_join([ tag.span("✓", class: "mr-1.5 inline-block w-3 invisible group-aria-checked:visible", "aria-hidden": "true"), t(".column.aligns.#{align}.label") ])
        end
      end

      # A floating "+": placed, and shown, by the script.
      def handle(label, action, target)
        tag.button "+", type: "button", hidden: true, class: "#{FLOATING_CLASS} #{HANDLE_CLASS}", title: label, "aria-label": label,
          data: { action: "admin--editor--table##{action}", "admin--editor--table-target": target }
      end
    end
  end
end
