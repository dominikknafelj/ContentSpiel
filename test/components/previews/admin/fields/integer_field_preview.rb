module Admin
  module Fields
    class IntegerFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "limit", type: :integer, options: { min: 1, max: 10 })
        render Admin::Fields::IntegerField.new(field: field, form_name: "block[settings]", value: 3, locale: "en")
      end
    end
  end
end
