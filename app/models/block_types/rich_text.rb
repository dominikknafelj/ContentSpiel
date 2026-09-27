module BlockTypes
  # Free-form rich text (spec §3.1): the only field is `body`, an existing
  # ActionText column the definition opts into via `uses` rather than
  # declaring a new one -- see the "existing columns stay columns" rule
  # (global constraints).
  module RichText
    def self.register
      BlockTypes.register :rich_text do |t|
        t.label "Rich text"
        t.uses :body
      end
    end
  end
end
