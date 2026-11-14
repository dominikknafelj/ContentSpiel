module Admin
  module Fields
    # A Diagram block's drawing (Diagram block spec §1), for
    # `:diagram_drawing` fields: a hidden input holding the stored
    # `{ "svg", "from" }` as JSON. Nobody types in it. The source's
    # `admin--diagram--preview` writes it when a draw succeeds (the
    # `drawing-field` value of `MermaidField` is its id) and dispatches
    # `input`, so the form's autosave sends source and drawing together. A
    # value the type refuses on read (`ContentModel::FieldTypes::
    # DRAWING_REFUSED`) is drawn as no value, so an autosave sends nothing
    # back that would be refused.
    #
    # On a translation tab whose language has no drawing of its own, the
    # input has no `name`, so no save carries it until the script names it
    # (`MermaidField`'s `drawing-name` value), which it does before it writes
    # a drawing: the same promise as the source's starting text.
    #
    # No label of its own and none drawn for it (`own_label?`), no original
    # beside it (`reference?`), no room in the card (`hidden?`), and nothing
    # to show read-only (`display`): the source's field shows the drawing.
    # Its error slot stays, for a refused save
    # (`errors.messages.invalid_drawing`), and shows when it holds one.
    class DiagramDrawingField < Base
      def self.display(_field, _value) = nil

      def self.own_label?(_field) = true

      def self.reference?(_field) = false

      def self.hidden?(_field) = true

      def stored? = value.is_a?(Hash) && value["svg"].is_a?(String)

      def stored_json = stored? ? value.to_json : nil

      def name_attribute = (stored? || original.blank?) ? input_name : nil
    end
  end
end
