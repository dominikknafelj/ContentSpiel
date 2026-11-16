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

  # `folder` is deleted just before this request's service takes the tree's
  # lock, inside its transaction: the controller found the folder, the
  # service finds it gone (a refused save rolls the deletion back with it).
  # (The suite has no minitest/mock: the model's own method is put back.)
  def deleted_meanwhile(folder)
    lock_tree = Media::Folder.method(:lock_tree!)
    Media::Folder.define_singleton_method(:lock_tree!) do
      Media::Asset.where(folder_id: folder.id).update_all(folder_id: nil) # version: none (a test's own rows)
      Media::Folder.where(id: folder.id).delete_all
      lock_tree.call
    end
    yield
  ensure
    Media::Folder.define_singleton_method(:lock_tree!, lock_tree)
  end

  def form_stream = streams.find { |stream| stream["target"] == "media-folder-form" }

  test "a refused name answers 422 with the field's sentence and writes nothing" do
    sign_in_as(users(:one))

    assert_no_difference -> { Media::Folder.count } do
      post "/cs-studio/media_folders", params: { media_folder: { name: "  " } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_equal "replace", form_stream["action"]
    assert_equal "Give the folder a name.", form_stream.at_css("[data-media-folder-error='name']").text
  end

  test "a refused create draws the whole form again: the name as typed, the parent and the search, the sentence under the field" do
    sign_in_as(users(:one))
    clients = Media::Folder.create!(name: "Clients")
    Media::Folder.create!(name: "Press", parent: clients)

    post "/cs-studio/media_folders", params: { media_folder: { name: " press ", parent_id: clients.id.to_s }, place: clients.id.to_s, q: "logo", filter: "unused" }, as: :turbo_stream

    assert_response :unprocessable_entity
    form = form_stream.at_css("template form#media-folder-form")
    assert_equal "/cs-studio/media_folders", form["action"]
    assert_equal "post", form.at_css("input[name=_method]")["value"]
    name = form.at_css("input#media-folder-name")
    assert_equal " press ", name["value"]
    assert_equal "true", name["aria-invalid"]
    assert_equal clients.id.to_s, form.at_css("input[name='media_folder[parent_id]']")["value"]
    assert_equal [ clients.id.to_s, "logo", "unused" ], %w[place q filter].map { |field| form.at_css("input[name=#{field}]")["value"] }
    assert_equal "A folder named “press” is already here.", form.at_css("#media-folder-name-errors [data-media-folder-error='name']").text
    assert_equal "Inside Clients", form.at_css("#media-folder-where").text.squish
  end

  test "a refused rename draws the rename form again and a parent deleted meanwhile is said under the field" do
    sign_in_as(users(:one))
    clients = Media::Folder.create!(name: "Clients")
    client_a = Media::Folder.create!(name: "Client A", parent: clients)

    patch "/cs-studio/media_folders/#{client_a.id}", params: { media_folder: { name: "" }, place: client_a.id.to_s }, as: :turbo_stream

    assert_response :unprocessable_entity
    form = form_stream.at_css("template form#media-folder-form")
    assert_equal "/cs-studio/media_folders/#{client_a.id}", form["action"]
    assert_equal "patch", form.at_css("input[name=_method]")["value"]
    assert form.at_css("input[name='media_folder[parent_id]']")["disabled"], "a rename sends no parent"
    assert_equal "Give the folder a name.", form.at_css("[data-media-folder-error='name']").text
    assert_equal "Client A", client_a.reload.name

    events = Media::Folder.create!(name: "Events")
    deleted_meanwhile(events) do
      post "/cs-studio/media_folders", params: { media_folder: { name: "Trips", parent_id: events.id.to_s } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    form = form_stream.at_css("template form#media-folder-form")
    assert_equal "That folder is gone.", form.at_css("[data-media-folder-error]").text
    assert_equal events.id.to_s, form.at_css("input[name='media_folder[parent_id]']")["value"], "the parent asked for is sent again as it was"
  end

  test "a refused delete answers with an error toast and no form" do
    sign_in_as(users(:one))
    clients = Media::Folder.create!(name: "Clients")

    deleted_meanwhile(clients) do
      delete "/cs-studio/media_folders/#{clients.id}", params: { place: clients.id.to_s }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_nil form_stream
    assert_nil part
    assert_equal "That folder is gone.", toast_text
    assert streams.find { |stream| stream["target"] == "toasts" }.at_css("template [role=alert]"), "an error toast"
  end

  test "a rename of a folder another tab deleted first draws the form again with That folder is gone. under the field" do
    sign_in_as(users(:one))
    folder = Media::Folder.create!(name: "Client A")
    folder.destroy!

    patch "/cs-studio/media_folders/#{folder.id}", params: { media_folder: { name: "Client B" }, place: folder.id.to_s, q: "logo" }, as: :turbo_stream

    assert_response :not_found
    form = form_stream.at_css("template form#media-folder-form")
    assert_equal "/cs-studio/media_folders/#{folder.id}", form["action"]
    assert_equal "patch", form.at_css("input[name=_method]")["value"]
    assert_equal "Client B", form.at_css("input#media-folder-name")["value"]
    assert_equal "That folder is gone.", form.at_css("#media-folder-name-errors [data-media-folder-error]").text
    assert form.at_css("#media-folder-where")["hidden"], "no line says where a folder that is gone stands"
    assert_equal "logo", form.at_css("input[name=q]")["value"]
    assert_equal 0, Media::Folder.count
  end

  test "a delete or a move of a folder another tab deleted first says That folder is gone. in an error toast" do
    sign_in_as(users(:one))
    folder = Media::Folder.create!(name: "Client A")
    folder.destroy!

    delete "/cs-studio/media_folders/#{folder.id}", params: { place: folder.id.to_s }, as: :turbo_stream
    assert_response :not_found
    assert_nil form_stream
    assert_equal "That folder is gone.", toast_text
    assert streams.find { |stream| stream["target"] == "toasts" }.at_css("template [role=alert]"), "an error toast"

    patch "/cs-studio/media_folders/#{folder.id}", params: { media_folder: { parent_id: "" } }, as: :turbo_stream
    assert_response :not_found
    assert_nil form_stream
    assert_equal "That folder is gone.", toast_text
  end

  test "the Media screen draws New folder, the folder dialog and, in a folder, the delete confirm for media.manage only" do
    clients = Media::Folder.create!(name: "Clients")
    client_a = Media::Folder.create!(name: "Client A", parent: clients)
    asset = create_media_asset
    asset.update_columns(folder_id: client_a.id) # version: none (a test's own rows)

    sign_in_as(users(:one))
    get "/cs-studio/media?folder=#{client_a.id}"
    html = Nokogiri::HTML(response.body)
    head_button = html.at_css("#tree-column button[data-admin--ui--dialog-id-param='media-folder-dialog']")
    assert_equal "+ New folder", head_button.text.strip
    assert_equal "", head_button["data-admin--media--folder-dialog-parent-id-param"]
    assert html.at_css("#content dialog#media-folder-dialog form#media-folder-form")
    delete_dialog = html.at_css("#content dialog#media-folder-delete-dialog")
    assert_equal "Delete “Client A”?", delete_dialog.at_css("h2").text
    assert_equal "Its 1 image moves to “Clients”. Nothing else is deleted.", delete_dialog.at_css("[data-media-folder-delete-body]").text
    assert_equal "/cs-studio/media_folders/#{client_a.id}", delete_dialog.at_css("form#media-folder-delete-form")["action"]

    get "/cs-studio/media"
    html = Nokogiri::HTML(response.body)
    assert html.at_css("dialog#media-folder-dialog")
    assert_nil html.at_css("dialog#media-folder-delete-dialog"), "no folder to delete in All media"

    sign_in_as(uploader_without_manage)
    get "/cs-studio/media?folder=#{client_a.id}"
    assert_response :success
    html = Nokogiri::HTML(response.body)
    assert_nil html.at_css("[data-admin--ui--dialog-id-param='media-folder-dialog']")
    assert_nil html.at_css("dialog#media-folder-dialog")
    assert_nil html.at_css("dialog#media-folder-delete-dialog")
    assert_nil html.at_css(".admin-tree-row__add")
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

  # The column's part (`GET /media/folders`), which a tab fetches again when
  # another changed the library (the card's D13).
  def fetched_part = Nokogiri::HTML.fragment(response.body).at_css("##{Admin::MediaLibrary::FolderTreeComponent::PART_ID}")

  test "the column's part is behind media.upload and lists kept counts" do
    folder = Media::Folder.create!(name: "Client A")
    create_media_asset.tap { |asset| asset.update_columns(folder_id: folder.id) } # version: none (a test's own rows)
    create_media_asset.tap { |asset| asset.update_columns(folder_id: folder.id, trashed_at: Time.current) } # version: none (a test's own rows)

    sign_in_as(users(:reader))
    get "/cs-studio/media/folders", params: { folder: folder.id.to_s }
    assert_response :forbidden

    sign_in_as(uploader_without_manage)
    get "/cs-studio/media/folders", params: { folder: folder.id.to_s, q: "x" }
    assert_response :ok
    part = fetched_part
    assert part, "the answer is the column's part"
    assert_equal folder.id.to_s, part["data-media-part-place"]
    assert_equal Media::Place.new(:folder, folder.id).digest(Media::FolderTree.load), part["data-media-place-digest"]
    assert_nil part["data-media-place-gone"]
    assert_equal "1", part.at_css("[data-media-place-count='#{folder.id}']").text.strip
    assert_equal "1", part.at_css("[data-media-place-count='all']").text.strip
    # The rows keep the search, and a viewer without media.manage gets no "+".
    assert_includes part.at_css("#media-place-row-#{folder.id}-link")["href"], "q=x"
    assert_nil part.at_css("[data-admin--media--folder-dialog-parent-id-param]")

    # The picker's places: its own ids, the same marks on its wrapper.
    get "/cs-studio/media/folders", params: { folder: folder.id.to_s, picker: "1" }
    assert_response :ok
    picker = Nokogiri::HTML.fragment(response.body).at_css("#media-picker-places")
    assert picker
    assert_equal part["data-media-place-digest"], picker["data-media-place-digest"]
    assert picker.at_css("#media-picker-folder-tree [data-media-place-count='#{folder.id}']")
  end

  test "the part says when the folder asked for is gone" do
    sign_in_as(users(:one))
    gone = Media::Folder.create!(name: "Gone").tap(&:destroy!).id

    get "/cs-studio/media/folders", params: { folder: gone.to_s }
    assert_response :ok
    part = fetched_part
    assert part.key?("data-media-place-gone")
    assert_equal "all", part["data-media-part-place"]

    get "/cs-studio/media/folders", params: { folder: "none" }
    assert_not fetched_part.key?("data-media-place-gone")
    assert_equal Media::Place::NONE.digest(Media::FolderTree.load), fetched_part["data-media-place-digest"]
  end
end
