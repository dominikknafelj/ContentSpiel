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

    # The format a source's widths are made in. An animation is WebP whatever
    # the setting: libvips writes an animation's AVIF as a still image
    # collection (brands `mif1 avif miaf`, no `avis` sequence), which a
    # browser shows as its first frame. A still GIF or WebP takes the setting.
    def self.format_for(setting, animated:)
      animated ? "webp" : setting.to_s
    end

    # The transformations Active Storage's variant takes for one width. An
    # animated type loads every frame (`n: -1`), or only the first would be
    # made; a still one has no loader option.
    #
    # The format is a String, and no value here is a Symbol: a width's address
    # carries its variation as a JSON key, which decodes a Symbol as a String,
    # and Active Storage finds the variant record by the digest of what the
    # key DECODES to (a Marshal dump, which tells the two apart). With a
    # Symbol the job's record would be found by no request, and the request
    # would make the width again, inline.
    def self.transformations(width:, format:, quality:, content_type:)
      transformations = { resize_to_limit: [ width, nil ], format: format.to_s, saver: { quality: quality, strip: true } }
      transformations[:loader] = { n: -1 } if ANIMATED_TYPES.include?(content_type)
      transformations
    end
  end
end
