module Admin
  module Columns
    class RichTextColumnComponentPreview < ViewComponent::Preview
      def default
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: "<p>Some rich text.</p>")
      end

      def with_original
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, original: "<p>Etwas reicher Text.</p>")
      end
    end
  end
end
