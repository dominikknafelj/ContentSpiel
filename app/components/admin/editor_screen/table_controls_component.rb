module Admin
  module EditorScreen
    # What stands around a Table block's grid in its card (table block spec,
    # decisions 4, 5, 7 and 12, and "CS Studio"; Claude Design's B5 and its
    # 2026-10-27 follow-up; the grid's strips are the owner's option B of
    # 2026-10-29, "Row and column strips"): the options row ("Header row",
    # "First column as header"), the warning line, then the grid (this
    # component's content, the body's `RichTextColumnComponent` in table
    # mode), a strip of column letters above it and of row numbers to its
    # left, each letter and number the button of that column's or row's menu,
    # a dashed "+" at the end of the letters and under the numbers, and "Add
    # row" under the grid. Nothing is drawn over a cell's text: the strips
    # stand in the grid box's padding (`admin-rich-text.css`).
    # `admin--editor--table` does the work, through the grid's own editor
    # (`rich_text/editors`): every change is an editor transaction, written
    # into the body's hidden input and autosaved like typing, so nothing here
    # sends anything itself.
    #
    # THE STRIPS ARE THE SCRIPT'S. How many letters and numbers there are
    # follows the grid as it is typed, and where each stands follows the
    # cells' own boxes, so the server draws one TEMPLATE of a column's and of
    # a row's entry (`<template>`: a menu with every item, inert until
    # cloned) and the script clones one per column and per row, names it
    # ("Column B actions", "Row 3 actions", from `data-messages`) and places
    # it. Before the script runs there is no strip, and a card reads as a grid.
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

      # A letter or a number of the strips: the menu's button, filling the
      # entry the script sizes to its column or row (`admin-rich-text.css`).
      STRIP_BUTTON_CLASS = "admin-table-strip-button".freeze
      MENU_ITEM_CLASS = BlockCardComponent::MENU_ITEM_CLASS
      # The script's targets for the two strips' templates.
      TEMPLATE_TARGETS = { column: "columnTemplate", row: "rowTemplate" }.freeze

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
            "focusin->admin--editor--table#focusIn",
            "keydown->admin--editor--table#keydown",
            "click->admin--editor--table#settle"
          ].join(" "),
          "admin--editor--table-warn-columns-value": TableBody::WARN_COLUMNS,
          "admin--editor--table-warn-rows-value": TableBody::WARN_ROWS,
          "admin--editor--table-row-dialog-value": TableDeleteDialogsComponent.dialog_id(block, :row),
          "admin--editor--table-column-dialog-value": TableDeleteDialogsComponent.dialog_id(block, :column),
          "admin--editor--table-starting-grid-value": TableBody.starting_document.to_json
        }
      end

      def messages
        messages_data(%w[warning.columns warning.rows row.menu column.menu].map { |key| "components.editor_screen.table_controls.#{key}" })
      end

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

      # One strip's entry, as the script clones it: a positioned box (the
      # script sets its place and size, and `data-table-row` or
      # `data-table-column`) holding the menu, whose button is the letter or
      # the number. Its label and name are the script's too.
      def strip_entry(kind, &block)
        tag.template data: { "admin--editor--table-target": TEMPLATE_TARGETS.fetch(kind) } do
          tag.div class: "admin-table-strip-entry", data: { action: "click->admin--editor--table#choose" } do
            render Admin::Ui::MenuComponent.new(label: "", aria_label: "", align: :left, close_on_select: true, button_class: STRIP_BUTTON_CLASS), &block
          end
        end
      end

      # A dashed "+": placed, and shown, by the script.
      def add_button(label, action, target)
        tag.button "+", type: "button", hidden: true, class: "admin-table-strip-add", title: label, "aria-label": label,
          data: { action: "admin--editor--table##{action}", "admin--editor--table-target": target }
      end
    end
  end
end
