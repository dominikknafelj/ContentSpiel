module Admin
  module Fields
    # Code shown read-only: what `CodeField.display` answers for a value, so
    # that where a field cannot be edited (a translation tab's shared fields,
    # `Admin::EditorScreen::SharedFieldsComponent`) the code is drawn in a
    # `pre` and keeps its frame, not flattened to a line of text.
    CodeDisplay = Data.define(:text)
  end
end
