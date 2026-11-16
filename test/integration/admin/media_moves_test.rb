require "test_helper"

# `Admin::MediaMovesController` (media-folders spec §8): `POST /media/move`.
class Admin::MediaMovesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @folder = Media::Folder.create!(name: "Client A")
  end

  def streams = Nokogiri::HTML.fragment(response.body).css("turbo-stream")

  def targets = streams.map { |stream| [ stream["action"], stream["target"] ] }

  def toast_text = streams.select { |stream| stream["target"] == "toasts" }.map { |stream| stream.text.squish }.join(" ")

  def send_move(ids, folder:, **extra)
    post "/cs-studio/media/move", params: { asset_ids: ids.map(&:to_s), folder: folder.to_s, **extra }, as: :turbo_stream
  end

  test "a move answers the column's counts and removes the moved tiles from the place they left" do
    sign_in_as(users(:one))
    first, second = create_media_asset, create_media_asset

    send_move([ first.id, second.id ], folder: @folder.id, place: "none")

    assert_response :success
    assert_equal [ @folder.id ] * 2, [ first, second ].map { |asset| asset.reload.folder_id }
    assert_includes targets, [ "remove", "media-asset-#{first.id}" ]
    assert_includes targets, [ "remove", "media-asset-#{second.id}" ]
    assert_includes targets, [ "replace", "media-folder-tree-part" ]
    assert_includes targets, [ "update", "media-count-all" ]
    count = streams.find { |stream| stream["target"] == "media-place-count" }
    assert_equal "0", count.text.strip
  end

  test "a move in All media removes no tile" do
    sign_in_as(users(:one))
    asset = create_media_asset

    send_move([ asset.id ], folder: @folder.id)

    assert_response :success
    assert_equal @folder.id, asset.reload.folder_id
    assert_empty streams.select { |stream| stream["action"] == "remove" }
  end

  test "a refused move answers 422 with the sentence and moves nothing" do
    sign_in_as(users(:one))
    asset = create_media_asset

    send_move([ asset.id ], folder: Media::Folder.maximum(:id) + 1000)

    assert_response :unprocessable_entity
    assert_equal "That folder is gone.", toast_text
    assert_nil asset.reload.folder_id

    send_move([ asset.id, asset.id + 1000 ], folder: @folder.id)

    assert_response :unprocessable_entity
    assert_equal "An image you chose is gone. Nothing was moved.", toast_text
    assert_nil asset.reload.folder_id
  end

  test "a move needs media.upload or media.manage before anything is read" do
    sign_in_as(users(:reader))
    asset = create_media_asset

    send_move([ asset.id ], folder: @folder.id)

    assert_response :forbidden
    assert_nil asset.reload.folder_id
  end

  test "a move's toast says how many images went where" do
    sign_in_as(users(:one))
    first, second = create_media_asset, create_media_asset
    first.update!(title: "Beach")

    send_move([ first.id, second.id ], folder: @folder.id)
    assert_equal "Moved 2 images to “Client A”.", toast_text

    send_move([ first.id ], folder: "none")
    assert_equal "Moved “Beach” to “Not in a folder”.", toast_text
  end
end
