module Admin
  module Columns
    class PlainColumnComponentPreview < ViewComponent::Preview
      def single_line
        render Admin::Columns::PlainColumnComponent.new(name: "caption", value: "A caption")
      end

      def multiline
        render Admin::Columns::PlainColumnComponent.new(name: "meta_description", value: "A page's meta description, a sentence or two.", multiline: true)
      end

      def with_original_and_errors
        render Admin::Columns::PlainColumnComponent.new(name: "caption", value: nil, original: "Bildunterschrift", errors: [ "is too long" ])
      end
    end
  end
end
