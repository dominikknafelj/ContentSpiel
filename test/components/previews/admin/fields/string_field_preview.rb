module Admin
  module Fields
    class StringFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "title", type: :string, options: { required: true })
        render Admin::Fields::StringField.new(field: field, form_name: "post[fields]", value: "Hello world", locale: "en")
      end
    end
  end
end
