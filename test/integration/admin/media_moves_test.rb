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
    assert_equal "0 images", count.text.strip
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

  # The Move to… dialog's list (`GET /media/move/new`, D7).

  def choices = Nokogiri::HTML.fragment(response.body)

  def radio(value) = choices.at_css("[role=radiogroup] input[type=radio][value='#{value}']")

  test "the choices for images mark the current place and are behind media.upload" do
    sign_in_as(users(:author))
    first, second = create_media_asset, create_media_asset
    [ first, second ].each { |asset| asset.update_columns(folder_id: @folder.id) } # version: none (a test's own rows)

    get "/cs-studio/media/move/new", params: { asset_ids: [ first.id, second.id ].map(&:to_s), place: @folder.id.to_s, q: "logo" },
      headers: { "Turbo-Frame" => "media-move-choices" }

    assert_response :success
    frame = choices.at_css("turbo-frame#media-move-choices")
    assert frame, "the answer is the dialog's frame"
    assert_nil choices.at_css("html, body"), "with no layout"
    assert radio(@folder.id)["disabled"], "the current place cannot be chosen"
    assert_includes radio(@folder.id).parent.text, "Current"
    assert_nil radio("none")["disabled"]
    assert_equal [ first.id, second.id ].map(&:to_s), choices.css("form input[name='asset_ids[]']").map { |input| input["value"] }
    assert_equal @folder.id.to_s, choices.at_css("form input[name=place]")["value"]
    assert_equal "logo", choices.at_css("form input[name=q]")["value"]

    # Images in two places have no current place.
    second.update_columns(folder_id: nil) # version: none (a test's own rows)
    get "/cs-studio/media/move/new", params: { asset_ids: [ first.id, second.id ].map(&:to_s) }
    assert_empty choices.css("[role=radiogroup] input[disabled]")

    sign_in_as(users(:reader))
    get "/cs-studio/media/move/new", params: { asset_ids: [ first.id.to_s ] }
    assert_response :forbidden
  end

  test "the choices for a folder need media.manage" do
    clients = Media::Folder.create!(name: "Clients")
    @folder.update!(parent: clients)

    sign_in_as(users(:author))
    get "/cs-studio/media/move/new", params: { folder_id: @folder.id.to_s }
    assert_response :forbidden

    sign_in_as(users(:one))
    get "/cs-studio/media/move/new", params: { folder_id: @folder.id.to_s }
    assert_response :success
    assert_equal "/cs-studio/media_folders/#{@folder.id}", choices.at_css("form#media-move-form")["action"]
    assert radio(clients.id)["disabled"], "its parent is where it stands"
    assert radio(@folder.id)["disabled"], "itself"
    assert_nil radio("")["disabled"]

    get "/cs-studio/media/move/new", params: { folder_id: (Media::Folder.maximum(:id) + 1000).to_s }
    assert_response :success
    assert_equal "That folder is gone.", choices.at_css("[role=alert]").text.squish
    assert_nil choices.at_css("[role=radiogroup]")
  end

  test "a move the dialog sent is refused in its list, with the notice on top" do
    sign_in_as(users(:author))
    theirs = create_media_asset
    mine = create_media_asset
    mine.update_columns(created_by_id: users(:author).id) # version: none (a test's own rows)

    send_move([ mine.id, theirs.id ], folder: @folder.id, dialog: "move", place: "all")

    assert_response :forbidden
    assert_equal [ [ "update", "media-move-choices" ] ], targets
    assert_equal "1 of these images is not yours to move. Nothing was moved.", streams.first.at_css("[role=alert]").text.squish
    assert streams.first.at_css("[role=radiogroup]")
    assert_nil mine.reload.folder_id
  end

  test "a folder move from the dialog says where it went, and a refused one is drawn in the dialog" do
    sign_in_as(users(:one))
    events = Media::Folder.create!(name: "Events")
    child = Media::Folder.create!(name: "Inner", parent: @folder)

    patch "/cs-studio/media_folders/#{@folder.id}", params: { media_folder: { parent_id: events.id.to_s }, dialog: "move", place: @folder.id.to_s }, as: :turbo_stream
    assert_response :success
    assert_equal events.id, @folder.reload.parent_id
    assert_equal "Moved “Client A” to “Events”.", toast_text

    patch "/cs-studio/media_folders/#{@folder.id}", params: { media_folder: { parent_id: "" }, dialog: "move" }, as: :turbo_stream
    assert_equal "Moved “Client A” to the top of the library.", toast_text

    patch "/cs-studio/media_folders/#{@folder.id}", params: { media_folder: { parent_id: child.id.to_s }, dialog: "move" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal [ [ "update", "media-move-choices" ] ], targets
    assert_equal "A folder can't go inside itself.", streams.first.at_css("[role=alert]").text.squish
    assert_nil @folder.reload.parent_id

    gone = Media::Folder.maximum(:id) + 1000
    patch "/cs-studio/media_folders/#{gone}", params: { media_folder: { parent_id: "" }, dialog: "move" }, as: :turbo_stream
    assert_response :not_found
    assert_equal "That folder is gone.", streams.first.at_css("[role=alert]").text.squish
  end

  test "a move's answer draws the moved image's Folder fact again" do
    sign_in_as(users(:one))
    asset = create_media_asset

    send_move([ asset.id ], folder: @folder.id)

    fact = streams.find { |stream| stream["target"] == "media-panel-folder-#{asset.id}" }
    assert_equal "replace", fact["action"]
    assert_includes fact.at_css("template").inner_html, "Client A"
  end
end
