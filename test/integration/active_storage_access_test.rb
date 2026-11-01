require "test_helper"

# Active Storage's direct-upload endpoints are
# Rails defaults the app never uses -- every upload goes through CS
# Studio's own controllers (`Admin::MediaAssetsController`, the settings
# logo, image blocks). Left open, anyone signed out could create blobs and
# write bytes into storage. `config/initializers/active_storage_access.rb`
# puts both behind the same sign-in as the rest of CS Studio, while the
# read side stays public for what the site shows: a library image's made
# widths and the logo (what it refuses is test/integration/image_delivery_test.rb).
class ActiveStorageAccessTest < ActionDispatch::IntegrationTest
  BLOB_PARAMS = { blob: { filename: "x.png", byte_size: 4, checksum: Digest::MD5.base64digest("abcd"), content_type: "image/png" } }.freeze

  test "signed out, a direct upload creates no blob" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
    end
    assert_response :unauthorized
  end

  test "signed out, a disk upload with a valid token writes nothing" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(**BLOB_PARAMS[:blob])
    path = ActiveStorage::Current.set(url_options: { host: "www.example.com" }) { URI.parse(blob.service_url_for_direct_upload).path }

    put path, params: +"abcd", headers: { "Content-Type" => "image/png" }

    assert_response :unauthorized
    assert_not blob.service.exist?(blob.key)
  end

  test "signed in, a direct upload still works" do
    sign_in_as(users(:one))

    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
    end
    assert_response :success
  end

  # Also the regression test for the catch-all route ordering: Rails draws
  # Active Storage's routes after config/routes.rb, so the public `*path`
  # catch-all used to answer every blob URL with a 404.
  #
  # The width was made by the job before the request: the request serves it
  # and makes nothing (no request makes a variant, image delivery spec).
  test "reading a made width stays public, and the request makes no variant" do
    asset = make_renditions!(create_media_asset)

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      get asset.srcset.first.first
    end
    assert_response :success
    assert_includes response.headers["Cache-Control"].to_s.split(/,\s*/), "public"
  end
end
