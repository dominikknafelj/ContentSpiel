module Admin
  module Fields
    class TextFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "excerpt", type: :text, options: {})
        render Admin::Fields::TextField.new(field: field, form_name: "post[fields]", value: "A longer block of free text.", locale: "en")
      end
    end
  end
end
