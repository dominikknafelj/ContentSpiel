module Media
  # What a library image is, read once with libvips at validation: the size it
  # is shown at, a tiny preview, and whether it has transparency. Everything
  # `Media::Asset` stores about the pixels comes from this one decode; nothing
  # reads the file again to learn it.
  #
  # The header is read first and a file over `MAX_PIXELS` is refused before a
  # single pixel is decoded: a few kilobytes of compressed one-colour PNG can
  # describe a canvas that needs gigabytes. An animated image is read as its
  # first frame, so its height is one frame's (not all frames stacked) and its
  # preview is that frame. The preview is made from the oriented image with
  # no metadata (`strip`), so no camera data or location reaches a page.
  #
  # An animation is capped twice: each frame by `MAX_PIXELS`, and the whole
  # animation by `MAX_ANIMATION_PIXELS` (a frame's pixels times its frames),
  # because every width made of it decodes and encodes every frame on the one
  # images thread. A screen recording of 1,800 full-HD frames is under 50 MB
  # and 3.7 gigapixels of work per width.
  module Decoding
    MAX_PIXELS = 100_000_000
    MAX_ANIMATION_PIXELS = 500_000_000
    PREVIEW_WIDTH = 24

    # The libvips loader each allowed type must be read by: a file whose bytes
    # are another format than its sniffed type says is not an image of that type.
    LOADERS = {
      "image/png" => "pngload", "image/jpeg" => "jpegload",
      "image/gif" => "gifload", "image/webp" => "webpload"
    }.freeze

    Result = Data.define(:width, :height, :preview, :alpha)

    class Unreadable < StandardError; end
    class TooManyPixels < StandardError; end
    # A kind of TooManyPixels, so whatever stops the one stops the other.
    class TooManyFrames < TooManyPixels; end

    def self.read(io, content_type:)
      io.rewind if io.respond_to?(:rewind)
      data = io.read.to_s.b
      raise Unreadable, "empty" if data.empty?

      header = Vips::Image.new_from_buffer(data, "", access: :sequential)
      loader = LOADERS[content_type]
      raise Unreadable, "not a #{content_type}" unless loader && header.get("vips-loader").to_s.start_with?(loader)

      # `autorot` on an image whose pixels are not read yet only swaps the
      # sides for an orientation of 5 to 8: the size it is shown at.
      shown = header.autorot
      raise TooManyPixels, "#{shown.width}x#{shown.height}" if shown.width * shown.height > MAX_PIXELS

      pages = pages_of(header)
      raise TooManyFrames, "#{shown.width}x#{shown.height}x#{pages}" if shown.width * shown.height * pages > MAX_ANIMATION_PIXELS

      thumbnail = Vips::Image.thumbnail_buffer(data, PREVIEW_WIDTH, height: 10_000_000)
      Result.new(width: shown.width, height: shown.height, preview: thumbnail.webpsave_buffer(strip: true), alpha: header.has_alpha?)
    rescue Vips::Error => e
      raise Unreadable, e.message.to_s.lines.first.to_s.strip
    ensure
      # The upload reads this io again after the save: leave it at the start.
      io.rewind if io.respond_to?(:rewind)
    end

    # The number of frames, from the header alone: 1 for a still image (and
    # for anything libvips cannot read, which the job's own read then fails).
    def self.frames(io)
      io.rewind if io.respond_to?(:rewind)
      pages_of(Vips::Image.new_from_buffer(io.read.to_s.b, "", access: :sequential))
    rescue Vips::Error
      1
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    def self.pages_of(header)
      header.get_typeof("n-pages").zero? ? 1 : [ header.get("n-pages").to_i, 1 ].max
    end
    private_class_method :pages_of
  end
end
