module Admin
  module Ui
    # The primary-language original beside a translated field (handoff §4.1).
    class ReferenceCardComponentPreview < ViewComponent::Preview
      def current
        render Admin::Ui::ReferenceCardComponent.new(field: "title", locale: "de", original: "About us", state: :current)
      end

      CONFIRM = { record_type: "Post", record_id: 1, field: "title", locale: "de" }.freeze

      # A word diff: the stored source text against the original now.
      def outdated
        post = Post.new(
          translation_sources: { "title" => { "de" => { "digest" => "x", "text" => "A spare room", "saved_at" => 3.days.ago.iso8601, "from" => Translations.primary_locale } } },
          translation_original_changed_at: { "title" => 1.day.ago.iso8601 }
        )
        render Admin::Ui::ReferenceCardComponent.new(
          field: "title", locale: "de", original: "A small room", state: :outdated, record: post, confirm: CONFIRM
        )
      end

      # An older translation (a bare digest): the current text and the sentence.
      def outdated_without_source
        post = Post.new(translation_sources: { "title" => { "de" => "abc" } })
        render Admin::Ui::ReferenceCardComponent.new(
          field: "title", locale: "de", original: "A small room", state: :outdated, record: post, confirm: CONFIRM
        )
      end

      # An untracked-before translation: shown as the plain original, a rich one.
      def unknown
        document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello there" } ] } ])
        render Admin::Ui::ReferenceCardComponent.new(field: "body", locale: "de", original: document, kind: :rich, state: :unknown)
      end

      def missing
        render Admin::Ui::ReferenceCardComponent.new(field: "title", locale: "de", original: "About us", state: :missing)
      end
    end
  end
end
