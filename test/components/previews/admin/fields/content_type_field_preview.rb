module Admin
  module Fields
    class ContentTypeFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "kind", type: :content_type, options: {})
        render Admin::Fields::ContentTypeField.new(field: field, form_name: "post[fields]", value: ContentTypes.default.name, locale: "en")
      end
    end
  end
end
