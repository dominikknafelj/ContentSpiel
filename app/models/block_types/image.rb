module BlockTypes
  # A single attached image with a caption and alt text (spec §3.1). All
  # three are existing columns (`image` is the Active Storage attachment,
  # `caption`/`alt` are Mobility jsonb attributes) the definition opts into
  # via `uses` rather than declaring a schema field for any of them.
  module Image
    def self.register
      BlockTypes.register :image do |t|
        t.label "Image"
        t.uses :image, :caption, :alt
        t.component Blocks::ImageComponent
      end
    end
  end
end
