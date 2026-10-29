module Admin
  module EditorScreen
    # "Delete this row?" and "Delete this column?": what deleting a row or a
    # column of a Table's grid asks first when it has text in it (Claude
    # Design's B5), in the existing confirm dialog, never `window.confirm`.
    #
    # Drawn by the block card AFTER its form, not inside it: the dialog's
    # buttons are a `<form method="dialog">`, which cannot sit inside the
    # block's form (the parser would drop it, and Cancel would submit the
    # block). They delete nothing themselves: the confirm closes the dialog
    # with the value `delete` (`returnValue`), and `admin--editor--table`,
    # which opened it by id and listens for its `close`, then deletes the row
    # or the column through the grid's editor, so the change is autosaved
    # like any other. Cancel and Escape close it with no value.
    class TableDeleteDialogsComponent < AdminComponent
      KINDS = %i[row column].freeze
      CONFIRM_VALUE = "delete".freeze

      def self.dialog_id(block, kind) = "block-#{block.id}-table-delete-#{kind}"

      def initialize(block:)
        @block = block
      end

      def call
        safe_join(KINDS.map { |kind| dialog(kind) })
      end

      private

      def dialog(kind)
        render Admin::Ui::ConfirmDialogComponent.new(destructive: true, id: self.class.dialog_id(@block, kind), title: t(".#{kind}.title"), body: t(".#{kind}.body")) do |dialog|
          dialog.with_confirm_action do
            tag.form(method: "dialog") do
              render Admin::Ui::ButtonComponent.new(label: t(".#{kind}.confirm"), variant: :danger, type: "submit", value: CONFIRM_VALUE)
            end
          end
        end
      end
    end
  end
end
