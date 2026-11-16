require "test_helper"

# The confirm before a folder is deleted (the card StudioMediaFolders, D4):
# what moves where, each subfolder that will take another name, and "This
# can't be undone.", its words `Media::DeleteFolder.preview`'s.
class Admin::MediaLibrary::DeleteFolderDialogComponentTest < ViewComponent::TestCase
  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def images(count, into:)
    count.times { create_media_asset.update_columns(folder_id: into.id) } # version: none (a test's own rows)
  end

  def dialog(folder)
    tree = Media::FolderTree.load
    render_inline Admin::MediaLibrary::DeleteFolderDialogComponent.new(folder: folder, preview: Media::DeleteFolder.preview(folder, tree: tree), tree: tree)
  end

  def body = page.find("[data-media-folder-delete-body]", visible: :all).text

  test "the body says what moves where for a folder with a parent" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    folder("2026", client_a)
    folder("Press", client_a)
    images(2, into: client_a)

    dialog(client_a)

    assert_selector "dialog#media-folder-delete-dialog[data-destructive]", visible: :all
    assert_selector "h2", text: "Delete “Client A”?", visible: :all
    assert_equal "Its 2 images and 2 folders move to “Clients”. Nothing else is deleted.", body
    assert_selector "form#media-folder-delete-form[action='/cs-studio/media_folders/#{client_a.id}'] input[name=_method][value=delete]", visible: :all
    assert_selector "form#media-folder-delete-form[data-controller='admin--media--folder-dialog'] button[type=submit].bg-danger", text: "Delete folder", visible: :all

    # A part with nothing to move is left out; one is said in the singular.
    trips = folder("Trips", clients)
    images(1, into: trips)
    dialog(trips)
    assert_equal "Its 1 image move to “Clients”. Nothing else is deleted.", body
  end

  test "at the top it says the folders go to the top and the images to Not in a folder" do
    clients = folder("Clients")
    folder("Client A", clients)
    folder("Client B", clients)
    images(34, into: clients)

    dialog(clients)
    assert_equal "Its 2 folders move to the top of the library, and its 34 images to Not in a folder. Nothing else is deleted.", body

    events = folder("Events")
    folder("2026", events)
    dialog(events)
    assert_equal "Its 1 folder move to the top of the library. Nothing else is deleted.", body
  end

  test "an empty folder says It is empty." do
    clients = folder("Clients")

    dialog(clients)

    assert_equal "It is empty.", body
  end

  test "each suffixed subfolder has its sentence" do
    clients = folder("Clients")
    folder("Press", clients)
    client_a = folder("Client A", clients)
    folder("Press", client_a)
    folder("Logos", client_a)

    dialog(client_a)

    assert_equal [ "“Press” becomes “Press 2”, because “Clients” already has a folder of that name." ],
                 page.all("[data-media-folder-delete-rename]", visible: :all).map(&:text)

    folder("Press")
    dialog(clients)
    assert_equal [ "“Press” becomes “Press 2”, because the top of the library already has a folder of that name." ],
                 page.all("[data-media-folder-delete-rename]", visible: :all).map(&:text)
  end

  test "it ends This can't be undone." do
    dialog(folder("Clients"))

    assert_equal "This can't be undone.", page.all(".admin-dialog__body p", visible: :all).last.text
    assert_selector ".admin-dialog__body p.text-small.text-dim", text: "This can't be undone.", visible: :all
  end
end
