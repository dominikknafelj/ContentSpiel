module Admin
  module Fields
    # A single-line text input (spec §4.3), for `:string` fields.
    #
    # `placeholder` is what the block card hands over (`BlockCardComponent
    # #placeholder_for`): `text:`, and for a field whose type says
    # `placeholder_from:` the input name of that select (`source:`) and its
    # value-to-label Hash (`labels:`), which `admin--ui--placeholder-from`
    # reads to follow a choice before it is saved. A field with `help:` is
    # described by the line `Admin::Ui::FieldComponent` draws under it.
    class StringField < Base
      def placeholder_text = placeholder&.dig(:text)

      def placeholder_data
        return {} unless placeholder&.dig(:source)

        { controller: "admin--ui--placeholder-from",
          admin__ui__placeholder_from_source_value: placeholder[:source],
          admin__ui__placeholder_from_labels_value: placeholder[:labels].to_json }
      end
    end
  end
end
