require "test_helper"

class ImageSettingsTest < ActiveSupport::TestCase
  setup { @site = site_settings(:default) }

  test "a site that changed nothing has webp at 75, the four widths and 10 MB" do
    settings = ImageSettings.current(@site)

    assert_equal "webp", settings.format
    assert_equal 75, settings.quality
    assert_equal [ 480, 960, 1600, 2400 ], settings.widths
    assert_equal 10.megabytes, settings.max_bytes
  end

  test "the fingerprint changes with the format, the chosen format's quality and the widths, and with nothing else" do
    base = ImageSettings.current(@site).fingerprint

    assert_match(/\A\h{64}\z/, base)
    @site.image_quality_avif = 20
    @site.image_max_upload_mb = 20
    assert_equal base, ImageSettings.current(@site).fingerprint
    @site.image_quality_webp = 60
    assert_not_equal base, ImageSettings.current(@site).fingerprint
    @site.image_quality_webp = 75
    @site.image_widths = [ 480, 960 ]
    assert_not_equal base, ImageSettings.current(@site).fingerprint
    @site.image_widths = [ 480, 960, 1600, 2400 ]
    @site.image_format = "avif"
    assert_not_equal base, ImageSettings.current(@site).fingerprint
  end

  test "the bounds are refused on the row" do
    {
      image_widths: [ [], [ 160, 200, 300, 400, 500, 600, 700 ], [ 159, 960 ], [ 480, 4001 ], [ 480, 480 ] ],
      image_quality_webp: [ 0, 101 ],
      image_quality_avif: [ 0, 101 ],
      image_max_upload_mb: [ 0, 51 ],
      image_format: [ "gif" ]
    }.each do |column, values|
      values.each do |value|
        site = SiteSetting.find(@site.id)
        site.public_send("#{column}=", value)

        assert_not site.valid?, "#{column} = #{value.inspect} should be refused"
        assert site.errors[column].any?, "#{column} = #{value.inspect} needs an error on the column"
      end
    end
  end

  test "widths are stored sorted" do
    @site.update!(image_widths: [ 960, 480 ])

    assert_equal [ 480, 960 ], @site.reload.image_widths
  end

  test "avif is unavailable when the probe raises" do
    assert_not ImageSettings.avif_available?(probe: -> { raise Vips::Error })
  end
end
