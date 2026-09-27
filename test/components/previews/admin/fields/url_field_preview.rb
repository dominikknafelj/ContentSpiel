module Admin
  module Fields
    class UrlFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "cite", type: :url, options: {})
        render Admin::Fields::UrlField.new(field: field, form_name: "block[settings]", value: "https://example.com", locale: "en")
      end
    end
  end
end
