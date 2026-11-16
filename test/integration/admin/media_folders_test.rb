require "test_helper"

# `Admin::MediaFoldersController` (media-folders spec §8): the Folders column's
# writes, answered as Turbo Streams.
class Admin::MediaFoldersTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  def streams = Nokogiri::HTML.fragment(response.body).css("turbo-stream")

  def part = streams.find { |stream| stream["target"] == "media-folder-tree-part" }

  def toast_text = streams.select { |stream| stream["target"] == "toasts" }.map { |stream| stream.text.squish }.join(" ")

  def uploader_without_manage
    group = AccessControl::Group.create!(name: "Uploaders")
    AccessControl::Grant.create!(group: group, permission: "media.upload", scope: {})
    user = User.create!(email_address: "media-uploader@example.org", password: "a-long-enough-password")
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  test "each action is a 403 before any folder is looked up for someone without media.manage" do
    folder = Media::Folder.create!(name: "Client A")
    sign_in_as(uploader_without_manage)

    [ folder.id, Media::Folder.maximum(:id) + 1000 ].each do |id|
      patch "/cs-studio/media_folders/#{id}", params: { media_folder: { name: "X" } }, as: :turbo_stream
      assert_response :forbidden
      delete "/cs-studio/media_folders/#{id}", as: :turbo_stream
      assert_response :forbidden
    end
    post "/cs-studio/media_folders", params: { media_folder: { name: "New" } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal [ "Client A" ], Media::Folder.pluck(:name)
  end

  test "a refused name answers 422 with the field's sentence and writes nothing" do
    sign_in_as(users(:one))

    assert_no_difference -> { Media::Folder.count } do
      post "/cs-studio/media_folders", params: { media_folder: { name: "  " } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    form = streams.find { |stream| stream["target"] == "media-folder-form" }
    assert_equal "replace", form["action"]
    assert_equal "Give the folder a name.", form.at_css("[data-media-folder-error='name']").text
  end

  test "a create answers the column's part with the new folder as the place to go to and no toast" do
    sign_in_as(users(:one))
    parent = Media::Folder.create!(name: "Client A")

    post "/cs-studio/media_folders", params: { media_folder: { name: "Trips", parent_id: parent.id.to_s }, q: "sun", place: "none" }, as: :turbo_stream

    assert_response :created
    created = Media::Folder.find_by!(name: "Trips")
    assert_equal parent.id, created.parent_id
    assert_equal "replace", part["action"]
    assert_equal "/cs-studio/media?folder=#{created.id}&q=sun", part.at_css("div#media-folder-tree-part")["data-media-go"]
    assert_equal "", toast_text
  end

  test "delete answers the column's part with the folder's parent as the place and the toast Folder deleted" do
    sign_in_as(users(:one))
    parent = Media::Folder.create!(name: "Client A")
    child = Media::Folder.create!(name: "Trips", parent: parent)

    delete "/cs-studio/media_folders/#{child.id}", params: { place: child.id.to_s }, as: :turbo_stream

    assert_response :success
    assert_nil Media::Folder.find_by(id: child.id)
    assert_equal "/cs-studio/media?folder=#{parent.id}", part.at_css("div")["data-media-go"]
    assert_equal "Folder deleted", toast_text

    delete "/cs-studio/media_folders/#{parent.id}", as: :turbo_stream

    assert_equal "/cs-studio/media", part.at_css("div")["data-media-go"]
  end

  test "a rename answers the column's part and keeps the place" do
    sign_in_as(users(:one))
    folder = Media::Folder.create!(name: "Client A")

    patch "/cs-studio/media_folders/#{folder.id}", params: { media_folder: { name: "Client B" }, place: folder.id.to_s }, as: :turbo_stream

    assert_response :success
    assert_equal "Client B", folder.reload.name
    assert_equal "/cs-studio/media?folder=#{folder.id}", part.at_css("div")["data-media-go"]
    assert_equal "", toast_text
  end

  test "a move of a folder into its own subfolder is refused on the parent" do
    sign_in_as(users(:one))
    outer = Media::Folder.create!(name: "Outer")
    inner = Media::Folder.create!(name: "Inner", parent: outer)

    patch "/cs-studio/media_folders/#{outer.id}", params: { media_folder: { parent_id: inner.id.to_s } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_nil outer.reload.parent_id
    assert_includes response.body, "A folder can&#39;t go inside itself."
  end
end
