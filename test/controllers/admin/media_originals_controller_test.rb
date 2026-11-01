require "test_helper"

# "Download original" (image delivery spec, decision 2): a library image's
# original is the editors' alone. Active Storage's blob routes refuse it to
# everyone (they cannot tell an editor from a visitor: their proxy controllers
# take no session), so CS Studio serves it here, behind the library's own gate.
class Admin::MediaOriginalsControllerTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "an editor with media.upload downloads the original as an attachment, private and not stored" do
    asset = create_media_asset
    sign_in_as(users(:one))

    get admin_media_original_path(asset)

    assert_response :ok
    assert_equal file_fixture("tiny.png").binread, response.body
    assert_equal "image/png", response.media_type
    assert_match(/\Aattachment; filename="tiny\.png"/, response.headers["Content-Disposition"])
    cache_control = response.headers["Cache-Control"].to_s.split(/,\s*/)
    assert_includes cache_control, "private"
    assert_includes cache_control, "no-store"
    assert_not_includes cache_control, "public"
  end

  test "without media.upload it is the 403; a trashed or missing id the 404" do
    asset = create_media_asset
    original = file_fixture("tiny.png").binread

    sign_in_as(users(:reader))
    get admin_media_original_path(asset)
    assert_response :forbidden
    assert_not_includes response.body.b, original

    sign_in_as(users(:one))
    get admin_media_original_path(id: Media::Asset.maximum(:id) + 1000)
    assert_response :not_found

    asset.update!(trashed_at: Time.current)
    get admin_media_original_path(asset)
    assert_response :not_found
    assert_not_includes response.body.b, original
  end

  test "signed out it is the sign-in, and nothing of the file" do
    asset = create_media_asset

    get admin_media_original_path(asset)

    assert_response :redirect
    assert_not_includes response.body.b, file_fixture("tiny.png").binread
  end
end
