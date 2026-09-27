module Admin
  module Fields
    class DateFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "starts_on", type: :date, options: {})
        render Admin::Fields::DateField.new(field: field, form_name: "post[fields]", value: Date.current, locale: "en")
      end
    end
  end
end
