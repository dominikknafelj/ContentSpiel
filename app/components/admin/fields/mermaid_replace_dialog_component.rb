module Admin
  module Fields
    # "Replace the source?": what Import file… on a Diagram's source asks
    # first when the source isn't empty (EditorDiagramBlock, "Importing"), in
    # the shared confirm dialog, destructive, so Cancel takes the focus: the
    # text it replaces can't be got back. Its id is
    # `MermaidField.replace_dialog_id` of the source's input.
    #
    # Drawn by the block card AFTER its form (`MermaidField.outside_form`),
    # not inside it: the dialog's buttons are a `<form method="dialog">`,
    # which cannot sit inside the block's form (the parser would drop it, and
    # Cancel would submit the block). It replaces nothing itself: the confirm
    # closes the dialog with `MermaidField::REPLACE_VALUE` (`returnValue`),
    # and `admin--diagram--preview`, which opened it by id, filled in the
    # file's name (`data-import-file`) and listens for its `close`, then puts
    # the file's text into the source. Cancel and Escape close it with no
    # value.
    #
    # Its words are the source field's (`admin.components.fields.mermaid_field`),
    # beside the import's own.
    class MermaidReplaceDialogComponent < AdminComponent
      WORDS = "admin.components.fields.mermaid_field".freeze
      # The file's name is put into the sentence as this mark, then cut out
      # as the empty place the script fills: no locale string holds it.
      FILE = "".freeze

      def initialize(input_id:)
        @input_id = input_id
      end

      def call
        render Admin::Ui::ConfirmDialogComponent.new(destructive: true, id: MermaidField.replace_dialog_id(@input_id), title: t("#{WORDS}.replace_title"), body: body) do |dialog|
          dialog.with_confirm_action do
            tag.form(method: "dialog") do
              render Admin::Ui::ButtonComponent.new(label: t("#{WORDS}.replace_confirm"), variant: :danger, type: "submit", value: MermaidField::REPLACE_VALUE)
            end
          end
        end
      end

      private

      def body
        before, after = t("#{WORDS}.replace_body", file: FILE).split(FILE, 2)
        safe_join([ before, tag.span(data: { import_file: true }), after ])
      end
    end
  end
end
