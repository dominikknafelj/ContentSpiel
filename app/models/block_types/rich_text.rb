module BlockTypes
  # Free-form rich text (spec §3.1): the only field is `body`, an existing
  # per-locale JSON document column (`HasRichTextBody`) the definition opts
  # into via `uses` rather than declaring a new one -- see the "existing
  # columns stay columns" rule (global constraints).
  module RichText
    def self.register
      BlockTypes.register :rich_text do |t|
        t.label "Rich text"
        t.icon "pilcrow"
        t.uses :body
        t.component Blocks::RichTextComponent
        t.theme_methods :block, :page
        t.sample body: "Sample paragraph with **strong words**.", shows: [ "Sample paragraph with", "<strong>strong words</strong>" ]
      end
    end
  end
end
