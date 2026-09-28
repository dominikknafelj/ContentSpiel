require "test_helper"

# Final fix wave (C, P6): Active Storage's direct-upload endpoints are
# Rails defaults the app never uses -- every upload goes through CS
# Studio's own controllers (`Admin::MediaAssetsController`, the settings
# logo, image blocks). Left open, anyone signed out could create blobs and
# write bytes into storage. `config/initializers/active_storage_access.rb`
# puts both behind the same sign-in as the rest of CS Studio, while the
# read side (blob redirects, disk GETs) stays public: the site's own images
# are served through it.
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
  test "reading a stored file stays public" do
    asset = create_media_asset

    get asset.url
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end
end
