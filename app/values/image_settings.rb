require "digest"

# The site's image delivery settings (the five `image_*` columns of
# `SiteSetting`): the format the widths are made in, that format's quality,
# the widths, and the largest upload. A value object over a settings row;
# nothing else reads the columns to make or serve an image.
class ImageSettings
  FORMATS = %w[webp avif].freeze
  DEFAULTS = { format: "webp", quality_webp: 75, quality_avif: 50, widths: [ 480, 960, 1600, 2400 ].freeze, max_upload_mb: 10 }.freeze

  WIDTH_RANGE = 160..4000
  WIDTH_COUNT = 1..6
  QUALITY_RANGE = 1..100
  UPLOAD_MB_RANGE = 1..50

  # A 4x4 AV1 encode: whether this libvips was built with an AV1 encoder.
  AVIF_PROBE = lambda do
    Vips::Image.black(4, 4).heifsave_buffer(compression: :av1)
    true
  end

  # The widths field's text ("480, 960 1600") as the list the column stores.
  # A token that is not a whole number stays a string, so the model refuses the
  # list with its one sentence instead of this guessing what was meant; a
  # width typed twice stays twice, and is refused the same way. Order is the
  # model's to fix (it saves them ascending).
  def self.parse_widths(text)
    text.to_s.split(/[\s,;]+/).reject(&:blank?).map { |token| token.match?(/\A\d{1,9}\z/) ? token.to_i : token }
  end

  def self.current(site = Current.site || SiteSetting.instance)
    new(site)
  end

  # Memoised per process: the libvips build does not change under a running
  # server. Every error is "not available".
  def self.avif_available?(probe: AVIF_PROBE)
    return @avif_available if defined?(@avif_available) && probe.equal?(AVIF_PROBE)

    result = begin
      probe.call ? true : false
    rescue StandardError, LoadError
      false
    end
    @avif_available = result if probe.equal?(AVIF_PROBE)
    result
  end

  def initialize(site)
    @site = site
  end

  def format = @site.image_format

  def quality
    format == "avif" ? @site.image_quality_avif : @site.image_quality_webp
  end

  def widths = Array(@site.image_widths).map(&:to_i).sort

  def max_upload_mb = @site.image_max_upload_mb

  def max_bytes = @site.image_max_upload_mb.megabytes

  # What a generation of widths was made with: the format, its quality and
  # the widths. Not an HMAC: nothing in it is secret.
  def fingerprint
    Digest::SHA256.hexdigest([ format, quality, widths ].to_json)
  end
end
