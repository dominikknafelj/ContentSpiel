require_relative "../preview_fixtures"

module Blocks
  # `Blocks::NoteComponent`: the type's sample, then each of the four kinds
  # with no title, headed by its word.
  class NoteComponentPreview < ViewComponent::Preview
    def sample
      sample = BlockTypes.fetch(:note).sample
      render component(sample.settings, title: sample.translations.dig("en", :title), body: sample.body)
    end

    BlockTypes::Note::KINDS.each_key do |kind|
      define_method(kind) { render component({ "kind" => kind }, body: "A #{kind} with a [link](https://example.com) and `inline code`.") }
    end

    private

    def component(settings, body:, title: nil)
      page = PreviewFixtures.page(title: "Note preview")
      block = page.content_blocks.new(block_type: :note, position: 0, settings: settings)
      block.assign_settings({ "title" => title }, locale: "en") if title
      block.assign_body(RichText::Document.from_markdown(body).first, locale: "en")
      block.save!

      Blocks::NoteComponent.new(block: block, page: page)
    end
  end
end
