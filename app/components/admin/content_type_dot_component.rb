module Admin
  # A content type's colour mark plus its name (design pass spec §4, handoff
  # §9 B13). Six hues: indexes 1-6 are filled dots, 7-12 the same hues as
  # rings, 13+ cycle again -- and the name always accompanies the mark, so
  # colour is never the only cue. The class names are spelled out in full
  # (not interpolated) so Tailwind's scanner sees them.
  class ContentTypeDotComponent < AdminComponent
    FILLED = %w[bg-cat-1 bg-cat-2 bg-cat-3 bg-cat-4 bg-cat-5 bg-cat-6].freeze
    RINGS = [ "border border-cat-1", "border border-cat-2", "border border-cat-3",
              "border border-cat-4", "border border-cat-5", "border border-cat-6" ].freeze

    def initialize(content_type:)
      @name = content_type.to_s
      @definition = ::ContentTypes.find(@name)
    end

    def call
      content_tag(:span, class: "admin-type-dot inline-flex items-center gap-1.5 text-sm text-dim") do
        safe_join([ content_tag(:span, "", class: "h-[7px] w-[7px] shrink-0 rounded-full #{mark}", aria: { hidden: true }), label ])
      end
    end

    def mark_class(index)
      slot = (index - 1) % 12
      slot < 6 ? FILLED[slot] : RINGS[slot - 6]
    end

    # An unregistered type (a plugin that was removed) has no index: a
    # neutral ring and the raw stored name, never an error. Public, with
    # `label`: a row that draws the mark at its own size beside other words
    # (the dashboard's Open threads) asks for the two and draws them itself.
    def mark = @definition ? mark_class(@definition.colour_index) : "border border-meta"

    def label = @definition ? @definition.label : @name
  end
end
