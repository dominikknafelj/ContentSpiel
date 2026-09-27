module Admin
  module Columns
    class SlugColumnComponentPreview < ViewComponent::Preview
      def default
        render Admin::Columns::SlugColumnComponent.new(value: "about-us", base_url: "https://example.com/company")
      end

      def with_errors
        render Admin::Columns::SlugColumnComponent.new(value: "", base_url: "https://example.com", errors: [ "can't be blank" ])
      end
    end
  end
end
