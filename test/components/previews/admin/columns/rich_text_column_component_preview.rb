module Admin
  module Columns
    # The Tiptap rich-text column (tiptap spec §4.1). The preview layout
    # loads the import map, so `admin--rich-text` mounts a live editor here
    # (typing works). It isn't inside an autosave form, so nothing is ever
    # saved.
    class RichTextColumnComponentPreview < ViewComponent::Preview
      def default
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: document(<<~MARKDOWN))
          ## A heading

          Some **rich** text with *emphasis*, ~~strike~~, `code` and [a link](https://example.com).

          - one
          - two

          > A quote.

          ::youtube{id="dQw4w9WgXcQ"}
        MARKDOWN
      end

      def empty
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)
      end

      # A translation: the German editor, empty, beside the primary
      # language's document rendered read-only.
      def with_original
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, locale: "de", original: document("Some *rich* text in the primary language."))
      end

      # An `image` node whose `MediaAsset` doesn't exist and an
      # `internalLink` to a missing post -- both render as "missing" (spec §7).
      def with_missing_references
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: {
          "type" => "doc", "content" => [
            { "type" => "image", "attrs" => { "asset_id" => 0, "alt" => "", "caption" => "" } },
            { "type" => "paragraph", "content" => [
              { "type" => "text", "text" => "A link to a deleted post", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "post", "id" => 0 } } ] }
            ] }
          ]
        })
      end

      def with_errors
        render Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, errors: [ "Body (en) youtube.id format is invalid" ])
      end

      private

      def document(markdown) = RichText::Document.from_markdown(markdown).first
    end
  end
end
