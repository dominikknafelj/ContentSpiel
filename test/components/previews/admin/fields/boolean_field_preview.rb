module Admin
  module Fields
    class BooleanFieldPreview < ViewComponent::Preview
      def checked
        field = ContentModel::Definition::Field.new(name: "featured", type: :boolean, options: {})
        render Admin::Fields::BooleanField.new(field: field, form_name: "post[fields]", value: true, locale: "en")
      end

      def unchecked
        field = ContentModel::Definition::Field.new(name: "featured", type: :boolean, options: {})
        render Admin::Fields::BooleanField.new(field: field, form_name: "post[fields]", value: false, locale: "en")
      end
    end
  end
end
