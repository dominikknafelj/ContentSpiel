require "test_helper"

# How the site's images are served (image delivery spec, decision 2): in
# Active Storage's proxy mode, at addresses that name their bytes for ever, so
# a made width is answered public, for a hundred years and immutable, in one
# request. A library image's ORIGINAL is the editors' alone: no read route of
# Active Storage's serves it, signed in or not (CS Studio's "Download original"
# is `Admin::MediaOriginalsController`). And no request makes a width: a
# library image's width that the job has not made is a 404, never a transform
# on a Puma thread. The logo is no library image: it is a public original, and
# its variants keep Rails' behaviour.
class ImageDeliveryTest < ActionDispatch::IntegrationTest
  FOREVER = "max-age=3155695200".freeze

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "a made width is answered public, for a hundred years, immutable, in one request" do
    asset = make_renditions!(create_media_asset)
    path, = asset.srcset.first

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      get path
    end

    assert_response :ok
    assert_cached_forever response
    assert_equal "image/webp", response.media_type
  end

  test "a library original is refused by every read route, signed out and signed in" do
    blob = create_media_asset.file.blob
    original = file_fixture("tiny.png").binread
    disk_key = ActiveStorage.verifier.generate({ key: blob.key, disposition: "inline", content_type: blob.content_type, service_name: blob.service_name }, purpose: :blob_key)
    paths = [ "/rails/active_storage/blobs/proxy/#{blob.signed_id}/tiny.png", "/rails/active_storage/blobs/redirect/#{blob.signed_id}/tiny.png",
      "/rails/active_storage/blobs/#{blob.signed_id}/tiny.png", "/rails/active_storage/disk/#{disk_key}/tiny.png" ]

    [ nil, users(:one) ].each do |user|
      sign_in_as(user) if user
      paths.each do |path|
        get path
        assert_response :not_found, "#{path} (#{user ? "signed in" : "signed out"})"
        assert_not_cacheable response, path
        assert_not_includes response.body.b, original, path
      end
    end
  end

  test "an unmade width of a library image is a 404 and no variant is made" do
    asset = make_renditions!(create_media_asset)
    settings = ImageSettings.current
    unmade = ActiveStorage::Variation.wrap(Media::Renditions.transformations(width: 2400, format: settings.format, quality: settings.quality, content_type: asset.content_type)).key
    assert_not_includes asset.generation.files.map(&:key), unmade
    signed = asset.file.blob.signed_id

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      %w[proxy redirect].each do |kind|
        get "/rails/active_storage/representations/#{kind}/#{signed}/#{unmade}/tiny.png"
        assert_response :not_found, kind
        assert_not_cacheable response, kind
      end
      get "/rails/active_storage/representations/#{signed}/#{unmade}/tiny.png"
      assert_response :not_found
    end
  end

  test "the logo is served through the proxy with the same headers, and its variants still bump" do
    site = site_settings(:default)
    site.logo.attach(io: File.open(file_fixture("tiny.png")), filename: "logo.png", content_type: "image/png")
    Page.create!(title: "Home", slug: "", published_at: 1.day.ago)

    get "/"
    assert_response :ok
    logo = URI.parse(css_select("header img").first["src"]).path
    assert_match %r{\A/rails/active_storage/blobs/proxy/}, logo

    get logo
    assert_response :ok
    assert_cached_forever response
    assert_equal file_fixture("tiny.png").binread, response.body

    variation = ActiveStorage::Variation.encode(resize_to_limit: [ 10, 10 ])
    version = PublicSite.content_version
    assert_difference -> { ActiveStorage::VariantRecord.count }, 1 do
      get "/rails/active_storage/representations/proxy/#{site.logo.blob.signed_id}/#{variation}/logo.png"
    end
    assert_response :ok
    assert_cached_forever response
    assert_not_equal version, PublicSite.content_version
  end

  private

  def assert_cached_forever(response)
    cache_control = response.headers["Cache-Control"].to_s.split(/,\s*/)
    assert_includes cache_control, "public"
    assert_includes cache_control, "immutable"
    assert_includes cache_control, FOREVER
  end

  def assert_not_cacheable(response, message = nil)
    assert_not_includes response.headers["Cache-Control"].to_s, "public", message
  end
end
