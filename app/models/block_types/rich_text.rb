module BlockTypes
  # Free-form rich text (spec §3.1): the only field is `body`, an existing
  # per-locale JSON document column (`HasRichTextBody`) the definition opts
  # into via `uses` rather than declaring a new one -- see the "existing
  # columns stay columns" rule (global constraints).
  module RichText
    # The tile's preview: the body's first heading and the text after it.
    def self.preview(block, locale:) = block.body_document(locale: locale).preview

    def self.register
      BlockTypes.register :rich_text do |t|
        t.label "Rich text"
        t.icon "pilcrow", family: :text
        t.uses :body
        t.component Blocks::RichTextComponent
        t.preview ->(block, locale:) { RichText.preview(block, locale: locale) }
        t.theme_methods :block, :page
        t.sample body: "Sample paragraph with **strong words**.", shows: [ "Sample paragraph with", "<strong>strong words</strong>" ]
      end
    end
  end
end
