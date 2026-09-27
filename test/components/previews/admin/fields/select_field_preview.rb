module Admin
  module Fields
    class SelectFieldPreview < ViewComponent::Preview
      def from_a_hash
        field = ContentModel::Definition::Field.new(name: "role_type", type: :select, options: { options: { "ic" => "Individual contributor", "lead" => "Lead" } })
        render Admin::Fields::SelectField.new(field: field, form_name: "post[fields]", value: "ic", locale: "en")
      end

      def from_an_array
        field = ContentModel::Definition::Field.new(name: "size", type: :select, options: { options: %w[small medium large] })
        render Admin::Fields::SelectField.new(field: field, form_name: "post[fields]", value: "medium", locale: "en")
      end
    end
  end
end
