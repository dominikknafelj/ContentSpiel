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

  # The realistic attack: the 2,400px key a larger image's page publishes,
  # replayed against an image that has not made it, and against the larger
  # image itself while its widths are recorded but not made. The key has the
  # shape of a real address, so a made width with such a key answers 200 (the
  # first half), and the 404s below are the mechanism's, not a key no request
  # carries.
  test "an unmade width of a library image is a 404 and no variant is made; a made one is a 200" do
    small = make_renditions!(create_media_asset)
    made_path, = small.srcset.first
    %w[proxy redirect].each do |kind|
      get made_path.sub("/representations/proxy/", "/representations/#{kind}/")
      follow_redirect! if kind == "redirect"
      assert_response :ok, kind
    end

    large = make_renditions!(create_media_asset, widths: [ 480, 2400 ]) # recorded, not made
    unmade = large.generation.files.last.key
    assert_equal 2400, large.generation.files.last.width

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      [ small, large ].each do |asset|
        signed = asset.file.blob.signed_id
        [ "proxy/#{signed}/#{unmade}", "redirect/#{signed}/#{unmade}", "#{signed}/#{unmade}" ].each do |route|
          get "/rails/active_storage/representations/#{route}/tiny.png"
          assert_response :not_found, route
          assert_not_cacheable response, route
        end
      end
    end
  end

  # A purge deletes the attachment row at once and the blob later, through a
  # job, and the blob's signed id is in every srcset ever published. Until the
  # job runs (or for ever, should it fail) the blob is attached to nothing: the
  # routes serve only what they list, so its original, its made widths and a
  # width not made are all refused, and nothing is made.
  test "an image whose attachment row is gone serves nothing: not the original, not a made width, not an unmade one" do
    asset = make_renditions!(create_media_asset)
    blob = asset.file.blob
    made_key = asset.generation.files.first.key
    unmade = ActiveStorage::Variation.encode(resize_to_limit: [ 2400, nil ], format: "webp")
    made_record = blob.variant_records.find_by!(variation_digest: asset.generation.files.first.digest)
    made_file_key = made_record.image.blob.key
    ActiveStorage::Attachment.where(record: asset, name: "file").delete_all

    assert_refuses_everything(blob, variant_keys: [ made_key, unmade ], extra_disk_keys: [ made_file_key ])
  end

  test "a blob that was never attached to anything is refused by every read route, and nothing is made" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    assert_refuses_everything(blob, variant_keys: [ ActiveStorage::Variation.encode(resize_to_limit: [ 10, 10 ]) ])
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

  def assert_refuses_everything(blob, variant_keys:, extra_disk_keys: [])
    original = blob.download
    disk = ([ blob.key ] + extra_disk_keys).map do |key|
      "/rails/active_storage/disk/#{ActiveStorage.verifier.generate({ key: key, disposition: "inline", content_type: blob.content_type, service_name: blob.service_name }, purpose: :blob_key)}/tiny.png"
    end
    signed = blob.signed_id
    paths = [ "/rails/active_storage/blobs/proxy/#{signed}/tiny.png", "/rails/active_storage/blobs/redirect/#{signed}/tiny.png",
      "/rails/active_storage/blobs/#{signed}/tiny.png", *disk ] +
      variant_keys.flat_map { |key| %w[proxy/ redirect/ ].map { |kind| "/rails/active_storage/representations/#{kind}#{signed}/#{key}/tiny.png" } }

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      paths.each do |path|
        get path
        assert_response :not_found, path
        assert_not_cacheable response, path
        assert_nil response.headers["Location"], path
        assert_not_includes response.body.b, original, path
      end
    end
  end

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
