require "test_helper"

class Media::DecodingTest < ActiveSupport::TestCase
  def read(name, content_type)
    File.open(file_fixture(name), "rb") { |io| Media::Decoding.read(io, content_type: content_type) }
  end

  test "a rotated photo has the size it is shown at" do
    result = read("rotated.jpg", "image/jpeg")

    # Stored 40 x 20 with orientation 6: shown 20 wide and 40 high.
    assert_equal [ 20, 40 ], [ result.width, result.height ]
    assert_operator result.width, :<, result.height
  end

  test "the preview is a WebP 24 pixels wide with no camera data" do
    result = read("rotated.jpg", "image/jpeg")

    image = Vips::Image.new_from_buffer(result.preview, "")
    assert_equal "webpload_buffer", image.get("vips-loader")
    assert_equal 24, image.width
    assert_not_includes image.get_fields, "exif-data"
    assert_not_includes image.get_fields.join, "GPS"
  end

  test "an animated GIF's height is one frame's and its preview its first frame" do
    result = read("animated.gif", "image/gif")

    assert_equal [ 30, 20 ], [ result.width, result.height ]
    preview = Vips::Image.new_from_buffer(result.preview, "")
    assert_equal 24, preview.width
    assert_equal 16, preview.height
  end

  test "a transparent PNG says it has alpha, a JPEG does not" do
    assert read("transparent.png", "image/png").alpha
    assert_not read("rotated.jpg", "image/jpeg").alpha
  end

  test "a file with an image's signature that cannot be decoded is Unreadable" do
    assert_raises(Media::Decoding::Unreadable) { read("not_an_image.png", "image/png") }
  end

  test "a file the content type does not describe is Unreadable" do
    assert_raises(Media::Decoding::Unreadable) { read("tiny.png", "image/jpeg") }
  end

  test "over 100 megapixels is refused before the pixels are read" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Media::Decoding::TooManyPixels) { read("huge_pixels.png", "image/png") }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.0
  end

  # 8 frames of 8000 x 8000: each frame is under the 100 megapixels, the
  # animation is 512 megapixels of work for every width made of it.
  test "an animation over 500 megapixels across its frames is refused from the header, though each frame is under the cap" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Media::Decoding::TooManyFrames) { read("long_animation.gif", "image/gif") }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.0
    assert_equal "8000x8000x8", error.message
  end

  test "frames counts an animation's frames and a still image's one" do
    assert_equal 3, File.open(file_fixture("animated.gif"), "rb") { |io| Media::Decoding.frames(io) }
    assert_equal 1, File.open(file_fixture("wide.png"), "rb") { |io| Media::Decoding.frames(io) }
  end
end
