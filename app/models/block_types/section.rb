module BlockTypes
  # A band that arranges other blocks in columns (sections spec §2, §3.1). It
  # holds no content of its own: its three settings say how many columns, and
  # which background and width the band has. The blocks in it are ordinary
  # rows that name it in `content_blocks.section_id`. `:container` is what the
  # rest of the code asks; nothing compares a block's type with "section".
  module Section
    # Layout name => the columns' weights, left to right. Their count is the
    # number of columns; the weights are what the public grid and an image's
    # `sizes` are derived from.
    LAYOUTS = {
      "one" => [ 1 ], "two" => [ 1, 1 ], "three" => [ 1, 1, 1 ], "four" => [ 1, 1, 1, 1 ],
      "one_two" => [ 1, 2 ], "two_one" => [ 2, 1 ]
    }.freeze
    BACKGROUNDS = %w[none tinted strong].freeze
    WIDTHS = %w[content full].freeze

    def self.register
      BlockTypes.register :section do |t|
        t.label "Section"
        t.field :layout, :select, options: LAYOUTS.keys, default: "two", required: true
        t.field :background, :select, options: BACKGROUNDS, default: "none", required: true
        t.field :width, :select, options: WIDTHS, default: "content", required: true
        t.capability :container
        t.columns ->(settings) { weights(settings["layout"]).size }
        t.component Blocks::SectionComponent
        t.theme_methods :block, :page, :columns, :layout, :background, :width
        # No `stylesheet` and no `summary` (block types plan, departure 1):
        # sections.css is the default theme's own file, imported by
        # theme.css before every type's, and a section's tile is its lanes.
        t.sample settings: { "layout" => "two", "background" => "tinted", "width" => "content" }, shows: [ "content-section--tinted" ]
      end
    end

    # An unknown or missing layout reads as the default: a stored value this
    # code no longer knows must not take the page down.
    def self.weights(layout) = LAYOUTS.fetch(layout.to_s, LAYOUTS.fetch("two"))
  end
end
