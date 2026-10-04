module Admin
  module EditorScreen
    # The primary-language original beside a translated field (handoff §4.1).
    class ReferenceCardComponentPreview < ViewComponent::Preview
      def current
        render Admin::EditorScreen::ReferenceCardComponent.new(field: "title", locale: "de", original: "About us", state: :current)
      end

      def outdated
        render Admin::EditorScreen::ReferenceCardComponent.new(
          field: "title", locale: "de", original: "About us, revised", state: :outdated,
          confirm: { record_type: "Page", record_id: 1, field: "title", locale: "de" }
        )
      end

      def rich
        document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello there" } ] } ])
        render Admin::EditorScreen::ReferenceCardComponent.new(field: "body", locale: "de", original: document, kind: :rich, state: :unknown)
      end
    end
  end
end
