module Admin
  module Columns
    class PlainColumnComponentPreview < ViewComponent::Preview
      def single_line
        render Admin::Columns::PlainColumnComponent.new(name: "caption", value: "A caption")
      end

      def multiline
        render Admin::Columns::PlainColumnComponent.new(name: "meta_description", value: "A page's meta description, a sentence or two.", multiline: true)
      end

      # A soft counter: past the limit it says "· long" and still saves.
      def with_soft_counter
        render Admin::Columns::PlainColumnComponent.new(name: "meta_title", value: "A meta title that has grown well past what a search result shows of it", counter: 60)
      end

      # A per-use override: Reset and the library text appear once it holds its own text.
      def per_use_override
        render Admin::Columns::PlainColumnComponent.new(name: "hero_alt", id: "preview-hero_alt", value: "My own alt text",
          placeholder: "A dog on a beach", override: "alt text")
      end

      def with_original_and_errors
        render Admin::Columns::PlainColumnComponent.new(name: "caption", value: nil, original: "Bildunterschrift", errors: [ "is too long" ])
      end
    end
  end
end
