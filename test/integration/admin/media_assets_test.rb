require "test_helper"

# `Admin::MediaAssetsController#create` (design spec §4.1/§4.2): the media
# picker's header Upload (media library Task 8) POSTs here directly (no page
# or post owns this upload -- the picker hands the id to whichever field or
# editor opened it once this answers), and gets back `{ id, title, url, tile,
# counts }` (the finished pick tile and the segment counts, round 3 Task 9) or
# `{ errors }`.
class Admin::MediaAssetsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "signed in, a real image upload creates a Media::Asset and returns its id and url" do
    sign_in_as(users(:one))

    assert_difference -> { Media::Asset.count }, 1 do
      post "/cs-studio/media_assets", params: { file: fixture_file_upload("tiny.png", "image/png") }
    end

    assert_response :created
    body = response.parsed_body
    asset = Media::Asset.last
    assert_equal asset.id, body["id"]
    assert_equal asset.url, body["url"]
    assert_equal "tiny", body["title"]
    assert asset.file.attached?
  end

  # Round 3 Task 9: the picker puts the finished tile into its grid, so the
  # answer carries it -- a pick button with the asset's payload -- and counts.
  test "the answer carries the picker's finished tile and the new counts" do
    sign_in_as(users(:one))

    post "/cs-studio/media_assets", params: { file: fixture_file_upload("tiny.png", "image/png") }

    body = response.parsed_body
    asset = Media::Asset.last
    tile = Nokogiri::HTML.fragment(body["tile"])
    assert_equal "media-picker-asset-#{asset.id}", tile.at_css("li")["id"]
    button = tile.at_css("button[data-action*='admin--media--select#select']")
    assert_equal asset.id, JSON.parse(button["data-admin--media--select-asset-param"])["id"]
    assert_equal 1, body["counts"]["all"]
  end

  test "signed out is redirected to sign in, and creates nothing" do
    assert_no_difference -> { Media::Asset.count } do
      post "/cs-studio/media_assets", params: { file: fixture_file_upload("tiny.png", "image/png") }
    end

    assert_response :redirect
    assert_redirected_to admin_sign_in_path
  end

  # The core anti-spoofing rule (design spec §4.2, the plan's own ruling):
  # a client's declared Content-Type and filename are never trusted --
  # only the bytes are. This file is plain text, sent with a `.png` name
  # and an `image/png` Content-Type, and must still be rejected.
  test "a text file renamed .png with an image/png content type is rejected" do
    sign_in_as(users(:one))

    assert_no_difference -> { Media::Asset.count } do
      post "/cs-studio/media_assets", params: { file: fixture_file_upload("fake.png", "image/png") }
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].join, "PNG, JPEG, GIF, or WEBP"
  end

  test "an oversized upload is rejected" do
    sign_in_as(users(:one))

    Tempfile.create([ "big", ".png" ]) do |tempfile|
      tempfile.binmode
      tempfile.write("\x00" * (10.megabytes + 1))
      tempfile.rewind

      assert_no_difference -> { Media::Asset.count } do
        post "/cs-studio/media_assets", params: { file: Rack::Test::UploadedFile.new(tempfile.path, "image/png") }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].join, "10 MB"
  end

  test "no file param at all is rejected, not a server error" do
    sign_in_as(users(:one))

    post "/cs-studio/media_assets", params: {}

    assert_response :unprocessable_entity
  end
end
