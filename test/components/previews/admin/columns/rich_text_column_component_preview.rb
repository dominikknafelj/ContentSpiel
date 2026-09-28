module Admin
  module Columns
    class RichTextColumnComponentPreview < ViewComponent::Preview
      def default
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: document("Some **rich** text."))
      end

      def with_original
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, original: document("Etwas *reicher* Text."))
      end

      private

      def document(markdown) = RichText::Document.from_markdown(markdown).first
    end
  end
end
