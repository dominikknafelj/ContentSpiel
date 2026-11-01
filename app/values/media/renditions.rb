# What an image is made in: which widths, and with which transformations.
# The rule for the widths (D3) is one function so the job that makes them and
# every test that expects them agree: every configured width below the
# original's, plus one at the smaller of the original's width and the largest
# configured width. Distinct and ascending.
module Media
  module Renditions
    ANIMATED_TYPES = %w[image/gif image/webp].freeze

    def self.widths_for(original_width:, configured:)
      configured = Array(configured).map(&:to_i).uniq.sort
      return configured.first(1) if original_width.nil?

      (configured.select { |width| width < original_width } + [ [ original_width, configured.max ].min ]).uniq.sort
    end

    # The transformations Active Storage's variant takes for one width. An
    # animated type loads every frame (`n: -1`), or only the first would be
    # made; a still one has no loader option.
    def self.transformations(width:, format:, quality:, content_type:)
      transformations = { resize_to_limit: [ width, nil ], format: format.to_sym, saver: { quality: quality, strip: true } }
      transformations[:loader] = { n: -1 } if ANIMATED_TYPES.include?(content_type)
      transformations
    end
  end
end
