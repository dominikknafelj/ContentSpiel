module Admin
  module Fields
    class TagFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "topic", type: :tag, options: {})
        render Admin::Fields::TagField.new(field: field, form_name: "post[fields]", value: "conference", locale: "en")
      end
    end
  end
end
