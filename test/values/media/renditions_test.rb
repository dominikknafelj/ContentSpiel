require "test_helper"

class Media::RenditionsTest < ActiveSupport::TestCase
  CONFIGURED = [ 480, 960, 1600, 2400 ].freeze

  test "an image wider than the largest width gets every width and the largest once" do
    assert_equal [ 480, 960, 1600, 2400 ], Media::Renditions.widths_for(original_width: 2880, configured: CONFIGURED)
  end

  test "an image between widths gets the ones below and its own" do
    assert_equal [ 480, 960, 1000 ], Media::Renditions.widths_for(original_width: 1000, configured: CONFIGURED)
  end

  test "an image narrower than the smallest width gets one width, its own" do
    assert_equal [ 300 ], Media::Renditions.widths_for(original_width: 300, configured: CONFIGURED)
  end

  test "an animated format keeps its frames, a still one has no loader option" do
    still = Media::Renditions.transformations(width: 480, format: "webp", quality: 75, content_type: "image/jpeg")
    assert_equal({ resize_to_limit: [ 480, nil ], format: "webp", saver: { quality: 75, strip: true } }, still)

    %w[image/gif image/webp].each do |type|
      assert_equal({ n: -1 }, Media::Renditions.transformations(width: 480, format: "webp", quality: 75, content_type: type)[:loader])
    end
  end

  # A request finds a width's variant record by the digest of the variation
  # its address DECODES to, and the address's key is JSON: a Symbol value
  # comes back a String. So the transformations hold no Symbol value, or the
  # digest the job recorded is not the one a request asks for, the request
  # finds no record, and Rails would make the width again on a Puma thread.
  test "the digest of a width's transformations is the digest of the variation its key decodes to, still and animated" do
    %w[image/jpeg image/gif].each do |type|
      transformations = Media::Renditions.transformations(width: 480, format: "webp", quality: 75, content_type: type)
      made = ActiveStorage::Variation.wrap(transformations).default_to(format: :png)

      assert_equal made.digest, ActiveStorage::Variation.decode(made.key).digest, type
    end
  end

  test "a generation reads and writes its stored shape, files ascending" do
    hash = { "fingerprint" => "f", "files" => [ { "width" => 960, "key" => "b", "digest" => "d2" }, { "width" => 480, "key" => "a", "digest" => "d1" } ] }
    generation = Media::Generation.from(hash)

    assert_equal [ 480, 960 ], generation.files.map(&:width)
    assert_equal "f", generation.fingerprint
    assert_equal "a", Media::Generation.from(generation.to_h).files.first.key
    assert_nil Media::Generation.from(nil)
    assert_nil Media::Generation.from({})
  end
end
